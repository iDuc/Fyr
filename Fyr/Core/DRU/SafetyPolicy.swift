import Foundation

/// Where a fireplace command comes from.
nonisolated enum ControlSurface: Sendable, CaseIterable {
    /// The open Fyr app (dashboard).
    case app
    /// Anything outside the open app: Siri, Shortcuts, interactive widgets,
    /// Control Center / Lock Screen controls, the Action button. All of these
    /// run App Intents.
    case intent
}

/// A command the user can give the fireplace.
nonisolated enum FireplaceCommand: Sendable, Equatable {
    case turnOn
    case turnOff
    case setWaveMode(enabled: Bool)
    case setFlameHeight(Int)
    case setTemperature(Double)
    case setWaveInterval(Int)
}

/// What has to be true before a command may be sent.
nonisolated struct SafetyRequirements: OptionSet, Sendable {
    let rawValue: Int

    /// The device running the command must be unlocked (App Intent
    /// `authenticationPolicy`).
    static let unlockedDevice = SafetyRequirements(rawValue: 1 << 0)
    /// The user must explicitly confirm this run (App Intent `requestConfirmation`).
    static let explicitConfirmation = SafetyRequirements(rawValue: 1 << 1)
    /// The user must complete the swipe-to-ignite gesture in the app.
    static let appGesture = SafetyRequirements(rawValue: 1 << 2)
    /// The fire must already be burning, checked against the bridge right
    /// before the write (the command must never light a fire that is off).
    static let fireMustBeBurning = SafetyRequirements(rawValue: 1 << 3)
}

/// Fyr's safety policy for a gas fireplace (Richard's decision, Oct 2026):
///
/// - Turning **off** is always allowed, from everywhere, without friction.
/// - Turning **on** from the app needs the deliberate swipe-to-ignite gesture.
///   From any surface outside the open app it needs an unlocked device *and*
///   an explicit confirmation.
/// - Flame height, wave mode, thermostat and wave interval changes are allowed
///   while the fire burns, but must never light a fire that is off. Switching
///   wave mode *off* is a reduction and is always allowed.
///
/// `DRUFireplaceService` enforces `fireMustBeBurning` and requires an
/// `IgnitionAuthorization` for ignition; the App Intents enforce the
/// unlocked-device and confirmation requirements.
nonisolated enum SafetyPolicy {

    static func requirements(for command: FireplaceCommand, from surface: ControlSurface) -> SafetyRequirements {
        switch command {
        case .turnOff, .setWaveMode(enabled: false):
            []
        case .turnOn:
            surface == .app ? .appGesture : [.unlockedDevice, .explicitConfirmation]
        case .setWaveMode(enabled: true), .setFlameHeight, .setTemperature, .setWaveInterval:
            .fireMustBeBurning
        }
    }

    /// Whether the command may only be sent while the fire burns. The same on
    /// every surface, so the service can enforce it without knowing the caller.
    static func requiresBurningFire(_ command: FireplaceCommand) -> Bool {
        ControlSurface.allCases.contains { requirements(for: command, from: $0).contains(.fireMustBeBurning) }
    }
}

/// Proof that ignition was authorized according to `SafetyPolicy`.
///
/// Turning the fire *off* never needs one. `DRUFireplaceService.turnOn`
/// requires a value of this type, so every caller has to state where ignition
/// came from.
nonisolated enum IgnitionAuthorization: Sendable, Equatable {
    /// The user completed the swipe-to-ignite slider in the app.
    case appSlider
    /// An App Intent that ran on an unlocked device (`authenticationPolicy`)
    /// and whose run the user explicitly confirmed (`requestConfirmation`).
    /// Only `FireplaceIntentSupport.turnOn` creates this.
    case confirmedIntent

    /// The surface this authorization belongs to.
    var surface: ControlSurface {
        switch self {
        case .appSlider: .app
        case .confirmedIntent: .intent
        }
    }
}
