import Foundation
import Synchronization
@testable import Fyr

/// In-process `BridgeTransport` connected to a `FakeBridge`.
final class FakeTransport: BridgeTransport {

    private struct State {
        var isOpen = false
        var isClosed = false
        var buffer: [UInt8] = []
        var waiter: (count: Int, continuation: CheckedContinuation<[UInt8], Error>)?
    }

    let bridge: FakeBridge
    private let state = Mutex(State())

    init(bridge: FakeBridge) {
        self.bridge = bridge
    }

    var isOpen: Bool { state.withLock { $0.isOpen && !$0.isClosed } }

    func open() async throws {
        guard await bridge.acceptConnection() else {
            state.withLock { $0.isClosed = true }
            throw ModbusError.connectFailed(.refused)
        }
        state.withLock { $0.isOpen = true }
    }

    func send(_ bytes: [UInt8]) async throws {
        guard isOpen else { throw ModbusError.connectionClosed }
        let reply = await bridge.handle(request: bytes)
        Task {
            if reply.delay > .zero { try? await Task.sleep(for: reply.delay) }
            for frame in reply.frames {
                if reply.byteByByte {
                    for byte in frame { self.deliver([byte]) }
                } else {
                    self.deliver(frame)
                }
            }
            if reply.closeConnection { self.close() }
        }
    }

    func receive(exactly count: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<[UInt8], Error>? = state.withLock { state in
                if state.buffer.count >= count {
                    let bytes = Array(state.buffer.prefix(count))
                    state.buffer.removeFirst(count)
                    return .success(bytes)
                }
                if state.isClosed { return .failure(ModbusError.connectionClosed) }
                state.waiter = (count, continuation)
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
    }

    func close() {
        let (waiter, wasOpen) = state.withLock { state -> (CheckedContinuation<[UInt8], Error>?, Bool) in
            let wasOpen = state.isOpen && !state.isClosed
            state.isClosed = true
            defer { state.waiter = nil }
            return (state.waiter?.continuation, wasOpen)
        }
        waiter?.resume(throwing: ModbusError.connectionClosed)
        if wasOpen {
            Task { await bridge.connectionClosed() }
        }
    }

    private func deliver(_ bytes: [UInt8]) {
        let ready: (CheckedContinuation<[UInt8], Error>, [UInt8])? = state.withLock { state in
            guard !state.isClosed else { return nil }
            state.buffer += bytes
            guard let waiter = state.waiter, state.buffer.count >= waiter.count else { return nil }
            let out = Array(state.buffer.prefix(waiter.count))
            state.buffer.removeFirst(waiter.count)
            state.waiter = nil
            return (waiter.continuation, out)
        }
        if let (continuation, out) = ready { continuation.resume(returning: out) }
    }
}

/// Records the transports a client creates, so tests can inspect them.
final class FakeTransportFactory: Sendable {
    let bridge: FakeBridge
    private let created = Mutex<[FakeTransport]>([])

    init(bridge: FakeBridge) {
        self.bridge = bridge
    }

    var transports: [FakeTransport] { created.withLock { $0 } }

    func make() -> FakeTransport {
        let transport = FakeTransport(bridge: bridge)
        created.withLock { $0.append(transport) }
        return transport
    }
}
