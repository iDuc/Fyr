import Foundation
@testable import Fyr

/// In-memory model of a Honeywell BRDG-03EM01 bridge with a DRU fireplace.
///
/// Behaves like the real bridge as far as Fyr knows it: one connection slot,
/// registers 40200-40250, action values 101/3/105/7, write-only flame height
/// (40201), and Modbus exceptions for unknown addresses. Faults can be injected
/// to test timeouts, late and stale replies, refusals and busy responses.
/// Used by `FakeTransport` (in-process) and `ModbusLoopbackServer` (real TCP).
actor FakeBridge {

    enum Fault: Sendable, Equatable {
        case none
        /// Accept requests but never answer.
        case silent
        /// Answer after a delay.
        case lateReply(Duration)
        /// Refuse all new connections (as when the DRU app holds the slot).
        case refuseConnections
        /// Answer every request with exception 0x02 (Illegal Data Address).
        case illegalAddress
        /// Answer the next `remaining` requests with exception 0x06 (Server Device Busy).
        case busy(remaining: Int)
        /// Send a frame with a wrong transaction id before the real answer.
        case staleReplyFirst
        /// Close the connection when a request arrives, without answering.
        case dropOnRequest
        /// Deliver the answer one byte at a time.
        case splitReplies
    }

    /// What to send back for one request.
    struct Reply: Sendable {
        var frames: [[UInt8]] = []
        var delay: Duration = .zero
        var closeConnection = false
        var byteByByte = false
    }

    struct Write: Sendable, Equatable {
        let register: UInt16
        let value: UInt16
        let at: ContinuousClock.Instant
    }

    static let statusOff: UInt16 = 0x3C00
    static let statusOn: UInt16 = 0xB804

    // MARK: - Configuration

    var fault: Fault = .none
    var unitId: UInt8 = 2
    var addressing: DRUAddressing = .registerNumber
    /// The real bridge accepts one TCP connection at a time.
    var singleConnectionSlot = true

    // MARK: - State

    private(set) var registers: [UInt16: UInt16] = [
        40200: 0,
        40202: 0,
        40203: FakeBridge.statusOff,
        40204: 0,
        40205: 80,   // -40 dBm
        40206: 90,   // -45 dBm
        40207: 215,  // 21.5 °C
        40220: 5,
        40250: 210,
    ]
    private(set) var flameHeightTarget: UInt16?
    private(set) var writes: [Write] = []
    private(set) var requestTimes: [ContinuousClock.Instant] = []
    private(set) var connectionAttempts = 0
    private(set) var acceptedConnections = 0
    private(set) var openConnections = 0
    private(set) var maxOpenConnections = 0

    private let writable: Set<UInt16> = [40200, 40201, 40220, 40250]
    private let clock = ContinuousClock()

    init() {}

    // MARK: - Test helpers

    func setFault(_ fault: Fault) { self.fault = fault }
    func setAddressing(_ addressing: DRUAddressing) { self.addressing = addressing }
    func setRegister(_ register: UInt16, _ value: UInt16) { registers[register] = value }
    func register(_ register: UInt16) -> UInt16? { registers[register] }
    var statusWord: UInt16 { registers[40203] ?? 0 }

    // MARK: - Connections

    /// Returns false if the connection is refused.
    func acceptConnection() -> Bool {
        connectionAttempts += 1
        if fault == .refuseConnections { return false }
        if singleConnectionSlot && openConnections >= 1 { return false }
        acceptedConnections += 1
        openConnections += 1
        maxOpenConnections = max(maxOpenConnections, openConnections)
        return true
    }

    func connectionClosed() {
        openConnections = max(0, openConnections - 1)
    }

    // MARK: - Requests

    /// Handle one complete request ADU.
    func handle(request: [UInt8]) -> Reply {
        requestTimes.append(clock.now)
        guard request.count >= 8 else { return Reply(closeConnection: true) }
        let tid = UInt16(bigEndianBytes: request[0], request[1])
        let unit = request[6]
        let pdu = Array(request[7...])

        switch fault {
        case .silent:
            return Reply()
        case .dropOnRequest:
            return Reply(closeConnection: true)
        case .illegalAddress:
            return Reply(frames: [frame(tid, unit, exception(pdu[0], 0x02))])
        case .busy(let remaining) where remaining > 0:
            fault = remaining > 1 ? .busy(remaining: remaining - 1) : .none
            return Reply(frames: [frame(tid, unit, exception(pdu[0], 0x06))])
        default:
            break
        }

        let responsePDU: [UInt8] = unit == unitId
            ? process(pdu)
            : exception(pdu[0], 0x0B) // gateway: target device failed to respond
        var reply = Reply(frames: [frame(tid, unit, responsePDU)])

        switch fault {
        case .lateReply(let delay):
            reply.delay = delay
        case .staleReplyFirst:
            reply.frames.insert(frame(tid &- 1, unit, responsePDU), at: 0)
        case .splitReplies:
            reply.byteByByte = true
        default:
            break
        }
        return reply
    }

    private func process(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count == 5 else { return exception(pdu.first ?? 0, 0x03) }
        let function = pdu[0]
        let address = UInt16(bigEndianBytes: pdu[1], pdu[2])
        let operand = UInt16(bigEndianBytes: pdu[3], pdu[4])

        switch function {
        case 0x03:
            let count = operand
            guard (1...125).contains(count), let first = registerNumber(for: address) else {
                return exception(function, 0x02)
            }
            var data: [UInt8] = []
            for register in first..<(first + count) {
                // 40201 is write-only on the real bridge.
                guard register != 40201, let value = registers[register] else { return exception(function, 0x02) }
                data += value.bigEndianBytes
            }
            return [function, UInt8(data.count)] + data

        case 0x06:
            guard let register = registerNumber(for: address), writable.contains(register) else {
                return exception(function, 0x02)
            }
            guard apply(register: register, value: operand) else { return exception(function, 0x03) }
            writes.append(Write(register: register, value: operand, at: clock.now))
            return pdu // echo

        default:
            return exception(function, 0x01)
        }
    }

    private func apply(register: UInt16, value: UInt16) -> Bool {
        switch register {
        case 40200:
            var status = statusWord
            switch value {
            case 101: status = Self.statusOn | (status & DRUStatusWord.waveModeBit)
            case 3: status = Self.statusOff
            case 105: status |= DRUStatusWord.waveModeBit
            case 7: status &= ~DRUStatusWord.waveModeBit
            default: return false
            }
            registers[40203] = status
            return true
        case 40201:
            guard value <= 100 else { return false }
            flameHeightTarget = value
            return true
        case 40220:
            guard (1...60).contains(value) else { return false }
            registers[40220] = value
            return true
        default:
            registers[register] = value
            return true
        }
    }

    private func registerNumber(for pduAddress: UInt16) -> UInt16? {
        let number: Int = switch addressing {
        case .registerNumber: Int(pduAddress)
        case .zeroBasedOffset: Int(pduAddress) + 40001
        case .oneBasedOffset: Int(pduAddress) + 40000
        }
        return (40000...40300).contains(number) ? UInt16(number) : nil
    }

    private func exception(_ function: UInt8, _ code: UInt8) -> [UInt8] {
        [function | 0x80, code]
    }

    private func frame(_ tid: UInt16, _ unit: UInt8, _ pdu: [UInt8]) -> [UInt8] {
        ModbusProtocol.frame(transactionId: tid, unitId: unit, pdu: pdu)
    }
}
