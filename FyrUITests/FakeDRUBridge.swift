import Foundation
import Network
import Synchronization

/// A fake DRU fireplace bridge for UI tests: a Modbus TCP server on
/// 127.0.0.1 inside the test runner. The app is launched with
/// `-FyrBridgeEndpoint 127.0.0.1:<port>` (DEBUG builds only).
///
/// Self-contained (UI tests cannot import the app). It knows what Fyr uses:
/// function 0x03 (read) and 0x06 (write) on unit 2 with register-number
/// addressing, registers 40200-40250, action values 101/3/105/7, write-only
/// flame height 40201, and one connection at a time.
final class FakeDRUBridge: Sendable {

    static let statusOff: UInt16 = 0x3C00
    static let statusOn: UInt16 = 0xB804
    static let waveBit: UInt16 = 0x0200

    struct Write: Equatable, Sendable {
        let register: UInt16
        let value: UInt16
    }

    private struct State {
        var registers: [UInt16: UInt16] = [
            40200: 0, 40203: FakeDRUBridge.statusOff, 40204: 0, 40205: 80, 40206: 90,
            40207: 214, 40220: 5, 40250: 210,
        ]
        var writes: [Write] = []
        var openConnections = 0
    }

    private let state = Mutex(State())
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.vanYperen.FyrUITests.fake-bridge")

    init(burning: Bool = false, wave: Bool = false) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        if burning {
            setStatus(Self.statusOn | (wave ? Self.waveBit : 0))
        }
    }

    // MARK: - Test API

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// Launch argument value for the app.
    var endpoint: String { "127.0.0.1:\(port)" }

    var writes: [Write] { state.withLock { $0.writes } }

    var statusWord: UInt16 { state.withLock { $0.registers[40203] ?? 0 } }

    var isBurning: Bool { statusWord != Self.statusOff && statusWord != 0 }

    var waveMode: Bool { statusWord & Self.waveBit != 0 }

    func setStatus(_ word: UInt16) {
        state.withLock { $0.registers[40203] = word }
    }

    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        let failure = Mutex<NWError?>(nil)
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                ready.signal()
            case .failed(let error):
                failure.withLock { $0 = error }
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        if let error = failure.withLock({ $0 }) { throw error }
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let accepted = state.withLock { state -> Bool in
            // The real bridge has one connection slot.
            guard state.openConnections == 0 else { return false }
            state.openConnections += 1
            return true
        }
        guard accepted else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed, .cancelled:
                self?.state.withLock { $0.openConnections = max(0, $0.openConnections - 1) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 7, maximumLength: 7) { [weak self] header, _, _, error in
            guard let self, error == nil, let header, header.count == 7 else {
                connection.cancel()
                return
            }
            let bytes = [UInt8](header)
            let length = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
            guard length >= 2 else {
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: length - 1, maximumLength: length - 1) { pdu, _, _, error in
                guard error == nil, let pdu, pdu.count == length - 1 else {
                    connection.cancel()
                    return
                }
                let response = self.respond(header: bytes, pdu: [UInt8](pdu))
                connection.send(content: Data(response), completion: .contentProcessed { _ in
                    self.receiveRequest(on: connection)
                })
            }
        }
    }

    // MARK: - Modbus

    private func respond(header: [UInt8], pdu: [UInt8]) -> [UInt8] {
        let unit = header[6]
        let body: [UInt8]
        if unit != 2 || pdu.count != 5 {
            body = [pdu.first.map { $0 | 0x80 } ?? 0x80, 0x0B]
        } else {
            body = process(pdu)
        }
        let length = UInt16(body.count + 1)
        return [header[0], header[1], 0, 0, UInt8(length >> 8), UInt8(length & 0xFF), unit] + body
    }

    private func process(_ pdu: [UInt8]) -> [UInt8] {
        let function = pdu[0]
        let address = UInt16(pdu[1]) << 8 | UInt16(pdu[2])
        let operand = UInt16(pdu[3]) << 8 | UInt16(pdu[4])
        return state.withLock { state -> [UInt8] in
            switch function {
            case 0x03:
                var data: [UInt8] = []
                for register in address..<(address + operand) {
                    guard register != 40201, let value = state.registers[register] else {
                        return [0x83, 0x02]
                    }
                    data += [UInt8(value >> 8), UInt8(value & 0xFF)]
                }
                return [0x03, UInt8(data.count)] + data
            case 0x06:
                guard [40200, 40201, 40220, 40250].contains(address) else { return [0x86, 0x02] }
                if address == 40200 {
                    var status = state.registers[40203] ?? Self.statusOff
                    switch operand {
                    case 101: status = Self.statusOn | (status & Self.waveBit)
                    case 3: status = Self.statusOff
                    case 105: status |= Self.waveBit
                    case 7: status &= ~Self.waveBit
                    default: return [0x86, 0x03]
                    }
                    state.registers[40203] = status
                } else if address != 40201 {
                    state.registers[address] = operand
                }
                state.writes.append(Write(register: address, value: operand))
                return pdu
            default:
                return [function | 0x80, 0x01]
            }
        }
    }
}
