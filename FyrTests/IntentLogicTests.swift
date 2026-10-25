import AppIntents
import Foundation
import Testing
@testable import Fyr

private struct UserDeclined: Error {}

@Suite("Fireplace intents", .serialized)
struct IntentLogicTests {

    private let noConfigure: (DRUFireplaceService) async throws(BridgeError) -> Void = { _ in }

    // MARK: Ignition

    @Test func ignitionWithoutAConfirmationStepIsRefused() async throws {
        let harness = await ServiceHarness()
        let outcome = try await FireplaceIntentSupport.execute(.turnOn, service: harness.service, configure: noConfigure)
        #expect(outcome == .failure(.ignitionNotAuthorized))
        #expect(await harness.bridge.writes.isEmpty)
        #expect(await harness.bridge.connectionAttempts == 0)
    }

    @Test func declinedConfirmationSendsNothing() async {
        let harness = await ServiceHarness()
        await #expect(throws: UserDeclined.self) {
            try await FireplaceIntentSupport.execute(.turnOn, service: harness.service, configure: noConfigure) {
                throw UserDeclined()
            }
        }
        #expect(await harness.bridge.writes.isEmpty)
        #expect(await harness.bridge.connectionAttempts == 0)
    }

    @Test func confirmationComesBeforeAnyBridgeTraffic() async throws {
        let harness = await ServiceHarness()
        let bridge = harness.bridge
        let attemptsWhenAsked = LockedBox<Int?>(nil)
        let outcome = try await FireplaceIntentSupport.execute(.turnOn, service: harness.service, configure: noConfigure) {
            let attempts = await bridge.connectionAttempts
            attemptsWhenAsked.mutate { $0 = attempts }
        }
        #expect(outcome == .success)
        #expect(attemptsWhenAsked.value == 0)
        #expect(await bridge.writes.map(\.value) == [101])
        #expect(await bridge.statusWord == FakeBridge.statusOn)
    }

    @Test func notConfiguredDoesNotAskForConfirmation() async throws {
        let harness = await ServiceHarness()
        let asked = LockedBox(false)
        let outcome = try await FireplaceIntentSupport.execute(
            .turnOn,
            service: harness.service,
            configure: { _ throws(BridgeError) in throw .notConfigured },
            confirm: { asked.mutate { $0 = true } }
        )
        #expect(outcome == .failure(.notConfigured))
        #expect(!asked.value)
    }

    // MARK: Other commands

    @Test func turningOffNeverAsksForConfirmation() async throws {
        let harness = await ServiceHarness(bridge: .burning())
        let asked = LockedBox(false)
        let outcome = try await FireplaceIntentSupport.execute(.turnOff, service: harness.service, configure: noConfigure) {
            asked.mutate { $0 = true }
        }
        #expect(outcome == .success)
        #expect(!asked.value)
        #expect(await harness.bridge.statusWord == FakeBridge.statusOff)
    }

    @Test func waveModeFromSiriDoesNotIgniteAnOffFire() async throws {
        let harness = await ServiceHarness()
        let outcome = try await FireplaceIntentSupport.execute(.setWaveMode(enabled: true), service: harness.service, configure: noConfigure)
        #expect(outcome == .failure(.fireplaceOff))
        #expect(await harness.bridge.writes.isEmpty)
        #expect(await harness.bridge.statusWord == FakeBridge.statusOff)
    }

    @Test func flameHeightFromSiriDoesNotIgniteAnOffFire() async throws {
        let harness = await ServiceHarness()
        let outcome = try await FireplaceIntentSupport.execute(.setFlameHeight(70), service: harness.service, configure: noConfigure)
        #expect(outcome == .failure(.fireplaceOff))
        #expect(await harness.bridge.writes.isEmpty)
    }

    @Test func waveModeWhileBurningWorks() async throws {
        let harness = await ServiceHarness(bridge: .burning())
        #expect(try await FireplaceIntentSupport.execute(.setWaveMode(enabled: true), service: harness.service, configure: noConfigure) == .success)
        #expect(try await FireplaceIntentSupport.execute(.setWaveMode(enabled: false), service: harness.service, configure: noConfigure) == .success)
        #expect(await harness.bridge.writes.map(\.value) == [105, 7])
    }

    @Test(arguments: [
        FireplaceCommand.turnOff,
        .setWaveMode(enabled: true),
        .setFlameHeight(30),
    ])
    func connectionIsReleasedAfterEveryIntent(command: FireplaceCommand) async throws {
        let harness = await ServiceHarness(bridge: .burning())
        _ = try await FireplaceIntentSupport.execute(command, service: harness.service, configure: noConfigure)
        #expect(await harness.service.isConnected == false)
        #expect(await harness.bridge.openConnections == 0)
    }

    @Test func connectionIsReleasedAfterAFailure() async throws {
        let harness = await ServiceHarness()
        _ = try await FireplaceIntentSupport.execute(.setWaveMode(enabled: true), service: harness.service, configure: noConfigure)
        #expect(await harness.bridge.openConnections == 0)
    }

    // MARK: Messages

    @Test func fireplaceOffMessageExplainsWhy() {
        let message = FireplaceIntentSupport.message(for: BridgeError.fireplaceOff, failure: "Could not turn on wave mode.")
        #expect(!message.contains("Could not"))
        #expect(message.contains(BridgeError.fireplaceOff.localizedDescription))
    }

    @Test func connectionProblemsIncludeTheFailureAndAdvice() {
        let message = FireplaceIntentSupport.message(for: BridgeError.bridgeBusy, failure: "Could not turn off the fireplace.")
        #expect(message.hasPrefix("Could not turn off the fireplace."))
        #expect(message.contains(BridgeError.bridgeBusy.recoverySuggestion!))
    }
}

@Suite("Intent declarations")
@MainActor
struct IntentDeclarationTests {

    @Test func declaredPoliciesMatchTheSafetyPolicy() {
        let declared: [(IntentAuthenticationPolicy, FireplaceCommand)] = [
            (TurnOnFireplaceIntent.authenticationPolicy, .turnOn),
            (TurnOffFireplaceIntent.authenticationPolicy, .turnOff),
            (EnableEcoModeIntent.authenticationPolicy, .setWaveMode(enabled: true)),
            (DisableEcoModeIntent.authenticationPolicy, .setWaveMode(enabled: false)),
            (ToggleEcoModeIntent.authenticationPolicy, .setWaveMode(enabled: true)),
            (ToggleEcoModeIntent.authenticationPolicy, .setWaveMode(enabled: false)),
            (SetFlameHeightIntent.authenticationPolicy, .setFlameHeight(50)),
            (SetTemperatureIntent.authenticationPolicy, .setTemperature(21)),
        ]
        for (policy, command) in declared {
            #expect(policy == FireplaceIntentSupport.authenticationPolicy(for: command), "\(command)")
        }
        #expect(TurnOnFireplaceIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(TurnOffFireplaceIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test func policyMappingFollowsTheSafetyPolicy() {
        #expect(FireplaceIntentSupport.authenticationPolicy(for: .turnOn) == .requiresLocalDeviceAuthentication)
        for command in [FireplaceCommand.turnOff, .setWaveMode(enabled: true), .setWaveMode(enabled: false), .setFlameHeight(1), .setTemperature(20)] {
            #expect(FireplaceIntentSupport.authenticationPolicy(for: command) == .alwaysAllowed)
        }
    }

    @Test func intentsRunWithoutOpeningTheApp() {
        #expect(TurnOnFireplaceIntent.supportedModes == .background)
        #expect(TurnOffFireplaceIntent.supportedModes == .background)
        #expect(EnableEcoModeIntent.supportedModes == .background)
        #expect(GetFireplaceStatusIntent.supportedModes == .background)
    }

    @Test func thermostatIsNotPromotedAsAnAppShortcut() {
        let shortcuts = FyrShortcuts.appShortcuts
        #expect(shortcuts.count == 6)
    }

    @Test func entityFromSnapshot() {
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let entity = FireplaceEntity(snapshot: FireplaceSnapshot(
            isOn: true, ecoModeActive: true, lastSetFlameHeight: 70,
            currentTemperature: 21.5, errorCode: nil, timestamp: timestamp
        ))
        #expect(entity.id == FireplaceEntity.defaultID)
        #expect(entity.isOn)
        #expect(entity.waveModeActive)
        #expect(entity.temperature?.value == 21.5)
        #expect(entity.lastSetFlameHeight == 70)
        #expect(entity.lastUpdated == timestamp)
    }

    @Test func entityWithoutSnapshotIsOffAndUndated() {
        let entity = FireplaceEntity(snapshot: nil)
        #expect(!entity.isOn)
        #expect(entity.lastUpdated == nil)
        #expect(entity.temperature == nil)
    }

    @Test func entityFromStatusHidesUnknownFlameHeight() {
        let status = FireplaceStatus(registers: [.status: FakeBridge.statusOn, .temperature: 200], lastSetFlameHeight: nil)
        let entity = FireplaceEntity(status: status)
        #expect(entity.isOn)
        #expect(entity.lastSetFlameHeight == nil)
        #expect(entity.temperature?.value == 20)
    }

    @Test func spokenStatusMentionsWaveMode() {
        let off = FireplaceStatus(registers: [.status: FakeBridge.statusOff], lastSetFlameHeight: nil)
        let on = FireplaceStatus(registers: [.status: FakeBridge.statusOn, .temperature: 215], lastSetFlameHeight: 50)
        let wave = FireplaceStatus(registers: [.status: 0xBA04, .temperature: 215], lastSetFlameHeight: 50)
        let spokenOff = GetFireplaceStatusIntent.spokenStatus(off)
        let spokenOn = GetFireplaceStatusIntent.spokenStatus(on)
        let spokenWave = GetFireplaceStatusIntent.spokenStatus(wave)
        #expect(spokenOff != spokenOn)
        #expect(spokenOn != spokenWave)
        #expect(spokenOn.contains("21.5") || spokenOn.contains("21,5"))
    }
}
