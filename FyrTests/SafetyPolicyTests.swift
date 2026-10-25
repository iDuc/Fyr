import Foundation
import Testing
@testable import Fyr

@Suite("Safety policy")
struct SafetyPolicyTests {

    @Test(arguments: ControlSurface.allCases)
    func turningOffIsAlwaysAllowedWithoutFriction(surface: ControlSurface) {
        #expect(SafetyPolicy.requirements(for: .turnOff, from: surface).isEmpty)
        #expect(SafetyPolicy.requirements(for: .setWaveMode(enabled: false), from: surface).isEmpty)
    }

    @Test func ignitionInTheAppNeedsTheSwipeGesture() {
        #expect(SafetyPolicy.requirements(for: .turnOn, from: .app) == .appGesture)
    }

    @Test func ignitionOutsideTheAppNeedsUnlockAndConfirmation() {
        let requirements = SafetyPolicy.requirements(for: .turnOn, from: .intent)
        #expect(requirements.contains(.unlockedDevice))
        #expect(requirements.contains(.explicitConfirmation))
    }

    @Test(arguments: [
        FireplaceCommand.setWaveMode(enabled: true),
        .setFlameHeight(40),
        .setTemperature(21),
        .setWaveInterval(10),
    ])
    func changesWhileBurningMustNotIgnite(command: FireplaceCommand) {
        for surface in ControlSurface.allCases {
            let requirements = SafetyPolicy.requirements(for: command, from: surface)
            #expect(requirements == .fireMustBeBurning)
        }
        #expect(SafetyPolicy.requiresBurningFire(command))
    }

    @Test func onlyIgnitionNeedsAnAuthorization() {
        #expect(!SafetyPolicy.requiresBurningFire(.turnOn))
        #expect(!SafetyPolicy.requiresBurningFire(.turnOff))
        #expect(IgnitionAuthorization.appSlider.surface == .app)
        #expect(IgnitionAuthorization.confirmedIntent.surface == .intent)
    }
}

@Suite("Service enforces the burning-fire rule", .serialized)
struct BurningFireGuardTests {

    @Test func waveModeOnIsRefusedWhileOff() async {
        let harness = await ServiceHarness()
        await #expect(throws: BridgeError.fireplaceOff) {
            try await harness.service.setWaveMode(enabled: true)
        }
        #expect(await harness.bridge.writes.isEmpty)
        #expect(await harness.bridge.statusWord == FakeBridge.statusOff)
    }

    @Test func flameHeightIsRefusedWhileOff() async {
        let harness = await ServiceHarness()
        await #expect(throws: BridgeError.fireplaceOff) {
            try await harness.service.setFlameHeight(80)
        }
        #expect(await harness.bridge.writes.isEmpty)
        #expect(await harness.bridge.flameHeightTarget == nil)
        #expect(await harness.service.lastSetFlameHeight == nil)
    }

    @Test func thermostatAndWaveIntervalAreRefusedWhileOff() async {
        let harness = await ServiceHarness()
        await #expect(throws: BridgeError.fireplaceOff) {
            try await harness.service.setThermostatSetpoint(22)
        }
        await #expect(throws: BridgeError.fireplaceOff) {
            try await harness.service.setWaveInterval(10)
        }
        #expect(await harness.bridge.writes.isEmpty)
    }

    @Test func changesWhileBurningAreSent() async throws {
        let harness = await ServiceHarness(bridge: .burning())
        try await harness.service.setWaveMode(enabled: true)
        try await harness.service.setFlameHeight(60)
        try await harness.service.setThermostatSetpoint(22)
        let writes = await harness.bridge.writes
        #expect(writes.map(\.register) == [40200, 40201, 40250])
        #expect(writes.map(\.value) == [105, 60, 220])
        // Each change first read the status (0x03), then wrote (0x06).
        #expect(await harness.bridge.functionCodes == [0x03, 0x06, 0x03, 0x06, 0x03, 0x06])
    }

    @Test func turningOffAndWaveOffNeedNoStatusRead() async throws {
        let harness = await ServiceHarness()
        try await harness.service.setWaveMode(enabled: false)
        try await harness.service.turnOff()
        #expect(await harness.bridge.writes.map(\.value) == [7, 3])
        #expect(await harness.bridge.functionCodes == [0x06, 0x06])
    }

    @Test func turnOffQueuedAheadOfWaveModeWins() async throws {
        let harness = await ServiceHarness(bridge: .burning())
        let service = harness.service
        // Hold the gate briefly so both commands queue up behind it.
        await harness.bridge.setFault(.lateReply(.milliseconds(100)))
        let poll = Task { _ = try? await service.fetchStatus() }
        try await Task.sleep(for: .milliseconds(30))
        let off = Task { try await service.turnOff() }
        try await Task.sleep(for: .milliseconds(30))
        let wave = Task { try await service.setWaveMode(enabled: true) }

        try await off.value
        await #expect(throws: BridgeError.fireplaceOff) { try await wave.value }
        await poll.value
        #expect(await harness.bridge.writes.map(\.value) == [3])
        #expect(await harness.bridge.statusWord == FakeBridge.statusOff)
    }

    @Test func statusCheckFailureSendsNothing() async {
        let harness = await ServiceHarness(bridge: .burning())
        await harness.bridge.setFault(.illegalAddress)
        await #expect(throws: BridgeError.rejected(exceptionCode: 0x02)) {
            try await harness.service.setWaveMode(enabled: true)
        }
        #expect(await harness.bridge.writes.isEmpty)
    }

    @Test func statusCheckIsRepeatedOnRetry() async throws {
        let harness = await ServiceHarness(bridge: .burning())
        // The first attempt's status read is answered "busy", the retry reads again.
        await harness.bridge.setFault(.busy(remaining: 1))
        try await harness.service.setWaveMode(enabled: true)
        #expect(await harness.bridge.functionCodes == [0x03, 0x03, 0x06])
        #expect(await harness.bridge.writes.map(\.value) == [105])
    }
}
