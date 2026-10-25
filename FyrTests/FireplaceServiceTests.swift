import Foundation
import Testing
@testable import Fyr

@Suite("Fireplace service", .serialized)
struct FireplaceServiceTests {

    @Test func commandsWriteDRUActionValues() async throws {
        let harness = await ServiceHarness()
        try await harness.service.turnOn(authorization: .appSlider)
        try await harness.service.setWaveMode(enabled: true)
        #expect(await harness.bridge.statusWord == 0xBA04)
        try await harness.service.setWaveMode(enabled: false)
        try await harness.service.turnOff()

        let writes = await harness.bridge.writes
        #expect(writes.map(\.register) == [40200, 40200, 40200, 40200])
        #expect(writes.map(\.value) == [101, 105, 7, 3])
        #expect(await harness.bridge.statusWord == FakeBridge.statusOff)
    }

    @Test func statusReflectsBridgeState() async throws {
        let harness = await ServiceHarness()
        try await harness.service.turnOn(authorization: .appSlider)
        try await harness.service.setWaveMode(enabled: true)

        let status = try await harness.service.fetchStatus()
        #expect(status.isOn)
        #expect(status.ecoModeActive)
        #expect(status.currentTemperature == 21.5)
        #expect(status.signalStrength == -45)
        #expect(!status.flameHeightIsKnown)
    }

    @Test func addressingConventionIsApplied() async throws {
        let bridge = FakeBridge()
        await bridge.setAddressing(.zeroBasedOffset)
        let harness = await ServiceHarness(bridge: bridge, configuration: TestTiming.service(addressing: .zeroBasedOffset))
        try await harness.service.turnOn(authorization: .appSlider)
        #expect(await bridge.writes.map(\.register) == [40200])
        #expect(try await harness.service.fetchStatus().isOn)
    }

    @Test func wrongAddressingIsRejectedNotMisapplied() async throws {
        let bridge = FakeBridge()
        await bridge.setAddressing(.zeroBasedOffset)
        let harness = await ServiceHarness(bridge: bridge) // service uses register numbers
        await #expect(throws: BridgeError.rejected(exceptionCode: 0x02)) {
            try await harness.service.fetchStatus()
        }
        #expect(await bridge.writes.isEmpty)
    }

    @Test func flameHeightIsPersisted() async throws {
        let store = MemoryFlameHeightStore()
        let first = await ServiceHarness(store: store)
        try await first.service.setFlameHeight(70)
        #expect(await first.bridge.flameHeightTarget == 70)
        #expect(store.load() == 70)

        // A relaunched app (new service) still knows the last set height.
        let second = await ServiceHarness(store: store)
        #expect(await second.service.lastSetFlameHeight == 70)
        let status = try await second.service.fetchStatus()
        #expect(status.flameHeight == 70)
        #expect(status.flameHeightIsKnown)
    }

    @Test func flameHeightIsClamped() async throws {
        let harness = await ServiceHarness()
        try await harness.service.setFlameHeight(150)
        #expect(await harness.bridge.flameHeightTarget == 100)
    }

    @Test func flameHeightLimitHoldsAndLatestValueWins() async throws {
        let interval = Duration.milliseconds(400)
        let harness = await ServiceHarness(configuration: TestTiming.service(
            rateLimits: .init(read: .milliseconds(10), write: .milliseconds(10), flameHeight: interval)
        ))
        let service = harness.service
        #expect(try await service.setFlameHeight(10))

        // Three slider releases while the 10 s (here 400 ms) window is closed.
        let a = Task { try await service.setFlameHeight(20) }
        try await Task.sleep(for: .milliseconds(30))
        let b = Task { try await service.setFlameHeight(30) }
        try await Task.sleep(for: .milliseconds(30))
        let c = Task { try await service.setFlameHeight(40) }

        #expect(try await a.value == false)
        #expect(try await b.value == false)
        #expect(try await c.value == true)

        let writes = await harness.bridge.writes.filter { $0.register == 40201 }
        #expect(writes.map(\.value) == [10, 40])
        #expect(writes[1].at - writes[0].at >= interval)
        #expect(await service.lastSetFlameHeight == 40)
    }

    @Test func concurrentFlameChangesCannotBypassTheLimit() async throws {
        let interval = Duration.milliseconds(300)
        let harness = await ServiceHarness(configuration: TestTiming.service(
            rateLimits: .init(read: .milliseconds(10), write: .milliseconds(10), flameHeight: interval)
        ))
        let service = harness.service
        await withTaskGroup(of: Void.self) { group in
            for height in [15, 25, 35, 45, 55, 65] {
                group.addTask { _ = try? await service.setFlameHeight(height) }
            }
        }
        let writes = await harness.bridge.writes.filter { $0.register == 40201 }
        #expect(!writes.isEmpty)
        for (earlier, later) in zip(writes, writes.dropFirst()) {
            #expect(later.at - earlier.at >= interval)
        }
    }

    @Test func turnOffIsNotHeldUpByFlameCooldown() async throws {
        let harness = await ServiceHarness(configuration: TestTiming.service(
            rateLimits: .init(read: .milliseconds(10), write: .milliseconds(50), flameHeight: .seconds(5))
        ))
        try await harness.service.setFlameHeight(50)
        let elapsed = try await ContinuousClock().measure {
            try await harness.service.turnOff()
        }
        #expect(elapsed < .milliseconds(500))
    }

    @Test func turnOffGoesAheadOfQueuedPolls() async throws {
        let harness = await ServiceHarness()
        let service = harness.service
        // Each status fetch holds the gate for ~5 x 100 ms.
        await harness.bridge.setFault(.lateReply(.milliseconds(100)))
        let polls = (0..<3).map { _ in
            Task { _ = try? await service.fetchStatus(priority: .automatic) }
        }
        try await Task.sleep(for: .milliseconds(50))
        let elapsed = try await ContinuousClock().measure {
            try await service.turnOff()
        }
        // Waits for the running poll only, not for the two queued ones (~1.5 s).
        #expect(elapsed < .milliseconds(900))
        for poll in polls { await poll.value }
    }

    @Test func readsCannotBypassTheRateLimit() async throws {
        let interval = Duration.milliseconds(200)
        let harness = await ServiceHarness(configuration: TestTiming.service(
            rateLimits: .init(read: interval, write: .milliseconds(10), flameHeight: .milliseconds(10))
        ))
        let service = harness.service
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { _ = try await service.fetchStatus() }
            }
            try await group.waitForAll()
        }
        // A status fetch reads 5 registers; the limit applies per fetch.
        let times = await harness.bridge.requestTimes
        #expect(times.count == 20)
        let fetchStarts = stride(from: 0, to: times.count, by: 5).map { times[$0] }
        for (earlier, later) in zip(fetchStarts, fetchStarts.dropFirst()) {
            #expect(later - earlier >= interval - .milliseconds(5))
        }
    }

    @Test func deviceBusyIsRetried() async throws {
        let harness = await ServiceHarness()
        await harness.bridge.setFault(.busy(remaining: 1))
        try await harness.service.turnOff()
        #expect(await harness.bridge.writes.map(\.value) == [3])
    }

    @Test func refusedConnectionIsReportedAsBridgeBusy() async {
        let harness = await ServiceHarness()
        await harness.bridge.setFault(.refuseConnections)
        await #expect(throws: BridgeError.bridgeBusy) {
            try await harness.service.fetchStatus()
        }
    }

    @Test func automaticPollingBacksOffButUserCommandsStillTry() async throws {
        let harness = await ServiceHarness()
        await harness.bridge.setFault(.refuseConnections)

        await #expect(throws: BridgeError.bridgeBusy) { try await harness.service.fetchStatus(priority: .automatic) }
        #expect(await harness.bridge.connectionAttempts == 1)

        // Within the backoff window, polling does not touch the bridge.
        await #expect(throws: BridgeError.bridgeBusy) { try await harness.service.fetchStatus(priority: .automatic) }
        #expect(await harness.bridge.connectionAttempts == 1)

        // A user action always tries.
        await harness.bridge.setFault(.none)
        try await harness.service.turnOff()
        #expect(await harness.bridge.connectionAttempts == 2)
        // After a successful connect, polling works again.
        _ = try await harness.service.fetchStatus(priority: .automatic)
    }

    @Test func silentBridgeFailsWithNoResponse() async {
        let harness = await ServiceHarness()
        await harness.bridge.setFault(.silent)
        let elapsed = await ContinuousClock().measure {
            await #expect(throws: BridgeError.noResponse) { try await harness.service.fetchStatus() }
        }
        // Two attempts at most, each bounded by the request timeout.
        #expect(elapsed < TestTiming.requestTimeout * 2 + .seconds(1))
    }

    @Test func idleConnectionIsReleased() async throws {
        let harness = await ServiceHarness(configuration: TestTiming.service(idleTimeout: .milliseconds(200)))
        _ = try await harness.service.fetchStatus()
        #expect(await harness.bridge.openConnections == 1)
        try await Task.sleep(for: .milliseconds(600))
        #expect(await harness.bridge.openConnections == 0)
        #expect(await harness.service.isConnected == false)

        // The next request reconnects.
        _ = try await harness.service.fetchStatus()
        #expect(await harness.bridge.acceptedConnections == 2)
    }

    @Test func releaseConnectionLetsAnotherAppConnect() async throws {
        let bridge = FakeBridge() // one connection slot, like the real bridge
        let fyr = await ServiceHarness(bridge: bridge)
        let druApp = await ServiceHarness(bridge: bridge)

        _ = try await fyr.service.fetchStatus()
        await #expect(throws: BridgeError.bridgeBusy) { try await druApp.service.fetchStatus() }

        await fyr.service.releaseConnection() // e.g. Fyr went to the background
        try await Task.sleep(for: .milliseconds(20))
        _ = try await druApp.service.fetchStatus()
        #expect(await bridge.maxOpenConnections == 1)
    }

    @Test func unconfiguredServiceReportsNotConfigured() async {
        let service = DRUFireplaceService(
            configuration: TestTiming.service(),
            flameHeightStore: MemoryFlameHeightStore(),
            statusSink: { _, _ in },
            makeTransport: { _ in FakeTransport(bridge: FakeBridge()) }
        )
        await #expect(throws: BridgeError.notConfigured) { try await service.turnOff() }
    }

    @Test func statusIsPublishedToSink() async throws {
        let bridge = FakeBridge()
        let factory = FakeTransportFactory(bridge: bridge)
        let published = LockedBox<[FireplaceStatus]>([])
        let service = DRUFireplaceService(
            configuration: TestTiming.service(),
            flameHeightStore: MemoryFlameHeightStore(),
            statusSink: { status, _ in published.mutate { $0.append(status) } },
            makeTransport: { _ in factory.make() }
        )
        await service.configure(endpoint: BridgeEndpoint(host: "fake"))
        _ = try await service.fetchStatus()
        #expect(published.value.count == 1)
    }
}
