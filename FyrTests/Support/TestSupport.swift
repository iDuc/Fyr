import Foundation
import Synchronization
@testable import Fyr

/// Short timings so the fault-injection tests run quickly.
enum TestTiming {
    static let requestTimeout: Duration = .milliseconds(400)

    static let client = ModbusTCPClient.Configuration(
        connectTimeout: .seconds(1),
        requestTimeout: requestTimeout,
        postConnectDelay: .zero,
        maxStaleFrames: 4
    )

    static let fastLimits = RateLimiter.Intervals(
        read: .milliseconds(10),
        write: .milliseconds(10),
        flameHeight: .milliseconds(10)
    )

    static func service(
        rateLimits: RateLimiter.Intervals = fastLimits,
        idleTimeout: Duration = .seconds(60),
        addressing: DRUAddressing = .registerNumber,
        client: ModbusTCPClient.Configuration = TestTiming.client
    ) -> DRUFireplaceService.Configuration {
        DRUFireplaceService.Configuration(
            unitId: 2,
            addressing: addressing,
            client: client,
            rateLimits: rateLimits,
            idleTimeout: idleTimeout,
            registerReadGap: .zero,
            reconnectBackoffBase: .seconds(30),
            reconnectBackoffMax: .seconds(60)
        )
    }
}

final class MemoryFlameHeightStore: FlameHeightStore {
    private let value = Mutex<Int?>(nil)

    func load() -> Int? { value.withLock { $0 } }
    func save(_ height: Int) { value.withLock { $0 = height } }
}

/// Builds a service wired to a fake bridge.
struct ServiceHarness {
    let bridge: FakeBridge
    let factory: FakeTransportFactory
    let service: DRUFireplaceService

    init(
        bridge: FakeBridge = FakeBridge(),
        configuration: DRUFireplaceService.Configuration = TestTiming.service(),
        store: FlameHeightStore = MemoryFlameHeightStore()
    ) async {
        self.bridge = bridge
        let factory = FakeTransportFactory(bridge: bridge)
        self.factory = factory
        service = DRUFireplaceService(
            configuration: configuration,
            flameHeightStore: store,
            statusSink: { _, _ in },
            makeTransport: { _ in factory.make() }
        )
        await service.configure(endpoint: BridgeEndpoint(host: "fake", port: 502), addressing: configuration.addressing)
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Thread-safe mutable box for collecting values from @Sendable closures.
final class LockedBox<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    var value: Value { storage.withLock { $0 } }

    func mutate(_ body: (inout Value) -> Void) {
        storage.withLock { body(&$0) }
    }
}
