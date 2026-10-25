import Foundation
import Network
import Synchronization

/// Host and port of the Modbus TCP bridge.
nonisolated struct BridgeEndpoint: Hashable, Sendable, CustomStringConvertible {
    var host: String
    var port: UInt16 = 502

    /// Parse "host" or "host:port" (IPv4 or host name).
    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard let hostPart = parts.first, !hostPart.isEmpty, parts.count <= 2 else { return nil }
        host = String(hostPart)
        if parts.count == 2 {
            guard let port = UInt16(parts[1]), port > 0 else { return nil }
            self.port = port
        }
    }

    init(host: String, port: UInt16 = 502) {
        self.host = host
        self.port = port
    }

    var description: String { "\(host):\(port)" }
}

/// A byte-stream connection to the bridge. One instance is one TCP connection;
/// after `close()` a new instance must be created.
///
/// `receive(exactly:)` must be completed (with an error) by `close()`, so that
/// a timeout can always unblock a pending read.
nonisolated protocol BridgeTransport: AnyObject, Sendable {
    /// Open the connection. Throws `ModbusError.connectFailed`.
    func open() async throws
    /// Whether the connection is (still) open and usable.
    var isOpen: Bool { get }
    func send(_ bytes: [UInt8]) async throws
    /// Read exactly `count` bytes, however the bridge's TCP segments are split.
    func receive(exactly count: Int) async throws -> [UInt8]
    /// Close the connection. Idempotent; fails any pending `open`/`receive`.
    func close()
}

// MARK: - Deadline

/// Run `operation`, and if it has not finished after `timeout` call `onTimeout`
/// and throw `ModbusError.timeout`.
///
/// Network.framework callbacks ignore Swift task cancellation, so a plain
/// "race against Task.sleep" would still wait for the stuck receive. `onTimeout`
/// (and task cancellation) therefore closes the transport, which makes the
/// pending operation fail promptly.
nonisolated func withDeadline<T: Sendable>(
    _ timeout: Duration,
    onTimeout: @escaping @Sendable () -> Void,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ModbusError.timeout }
            if let value = first { return value }
            onTimeout()
            throw ModbusError.timeout
        }
    } onCancel: {
        onTimeout()
    }
}

// MARK: - Network.framework transport

/// `BridgeTransport` backed by an `NWConnection`.
nonisolated final class NWBridgeTransport: BridgeTransport {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.vanYperen.Fyr.bridge-transport")
    private let closed = Mutex(false)

    init(endpoint: BridgeEndpoint) {
        let parameters = NWParameters.tcp
        parameters.serviceClass = .responsiveData
        // Fail fast instead of waiting for a better path: the bridge is on the local network.
        parameters.prohibitedInterfaceTypes = [.cellular]
        connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port) ?? 502,
            using: parameters
        )
    }

    var isOpen: Bool {
        connection.state == .ready
    }

    func open() async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .waiting(let error), .failed(let error):
                    // `.waiting` is how NWConnection reports "connection refused"
                    // and "no route": treat it as a failure instead of waiting.
                    once.run { continuation.resume(throwing: ModbusError.connectFailed(Self.classify(error))) }
                    connection.cancel()
                case .cancelled:
                    once.run { continuation.resume(throwing: ModbusError.connectionClosed) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // `close()` may have run before `start()`, when `cancel()` has no
            // effect; cancel again now that the connection has started.
            if closed.withLock({ $0 }) {
                connection.cancel()
            }
        }
    }

    func send(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: ModbusError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive(exactly count: Int) async throws -> [UInt8] {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(count)
        while buffer.count < count {
            let remaining = count - buffer.count
            let chunk: [UInt8] = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
                    if let error {
                        if case .posix(.ECANCELED) = error {
                            continuation.resume(throwing: ModbusError.connectionClosed)
                        } else {
                            continuation.resume(throwing: ModbusError.receiveFailed(error.localizedDescription))
                        }
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: [UInt8](data))
                    } else {
                        // No data and no error: EOF, the bridge closed the connection.
                        continuation.resume(throwing: ModbusError.connectionClosed)
                    }
                }
            }
            buffer += chunk
        }
        return buffer
    }

    func close() {
        closed.withLock { $0 = true }
        connection.cancel()
    }

    static func classify(_ error: NWError) -> ModbusError.ConnectFailure {
        switch error {
        case .posix(.ECONNREFUSED):
            return .refused
        case .posix(.EHOSTUNREACH), .posix(.EHOSTDOWN), .posix(.ENETUNREACH):
            return .unreachable
        case .posix(.ENETDOWN):
            return .networkDown
        case .posix(.ETIMEDOUT):
            return .timedOut
        default:
            return .other(error.localizedDescription)
        }
    }
}

/// Runs a closure at most once, from any thread.
nonisolated final class Once: Sendable {
    private let done = Mutex(false)

    func run(_ body: () -> Void) {
        let first = done.withLock { done in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
