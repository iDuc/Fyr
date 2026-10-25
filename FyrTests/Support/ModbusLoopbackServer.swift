import Foundation
import Network
import Synchronization
@testable import Fyr

/// A small Modbus TCP server on 127.0.0.1 that wraps a `FakeBridge`.
///
/// Used by integration tests for the real `NWBridgeTransport`, and meant for UI
/// tests later: start it in the test runner and launch the app with
/// `-FyrBridgeEndpoint 127.0.0.1:<port>` (see `SettingsStore.endpointOverrideArgument`).
final class ModbusLoopbackServer: Sendable {

    let bridge: FakeBridge
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.vanYperen.FyrTests.loopback-server")
    private let connections = Mutex<[NWConnection]>([])

    /// - Parameter port: 0 picks a free port; read `port` after `start()`.
    init(bridge: FakeBridge, port: UInt16 = 0) throws {
        self.bridge = bridge
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    var endpoint: BridgeEndpoint { BridgeEndpoint(host: "127.0.0.1", port: port) }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume() }
                case .failed(let error): once.run { continuation.resume(throwing: error) }
                case .cancelled: once.run { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        for connection in connections.withLock({ $0 }) {
            connection.cancel()
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let bridge = bridge
        Task {
            guard await bridge.acceptConnection() else {
                // The real bridge has one slot; refuse by closing immediately.
                connection.cancel()
                return
            }
            self.connections.withLock { $0.append(connection) }
            let closed = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled:
                    closed.run { Task { await bridge.connectionClosed() } }
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
            await self.serve(connection)
        }
    }

    private func serve(_ connection: NWConnection) async {
        while true {
            guard let header = await receive(connection, count: ModbusProtocol.headerLength),
                  let parsed = try? ModbusProtocol.parseHeader(header),
                  let pdu = await receive(connection, count: parsed.pduLength) else {
                connection.cancel()
                return
            }
            let reply = await bridge.handle(request: header + pdu)
            if reply.delay > .zero { try? await Task.sleep(for: reply.delay) }
            for frame in reply.frames {
                if reply.byteByByte {
                    for byte in frame {
                        await send(connection, [byte])
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                } else {
                    await send(connection, frame)
                }
            }
            if reply.closeConnection {
                connection.cancel()
                return
            }
        }
    }

    private func receive(_ connection: NWConnection, count: Int) async -> [UInt8]? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if error == nil, let data, data.count == count {
                    continuation.resume(returning: [UInt8](data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func send(_ connection: NWConnection, _ bytes: [UInt8]) async {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in continuation.resume() })
        }
    }
}
