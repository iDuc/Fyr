import AppIntents

/// Wave mode on/off for the Control Center toggle, the interactive widget and
/// the Live Activity. Not shown in Shortcuts (that is "Set Wave Mode",
/// `ToggleEcoModeIntent`).
///
/// Turning wave mode on needs a burning fire and never lights it; turning it
/// off is always allowed. Both may run on a locked device.
struct SetWaveModeIntent: SetValueIntent {

    static let title: LocalizedStringResource = "Wave Mode"

    static let description = IntentDescription("Turns wave mode on or off. Turning it on only works while the fireplace is burning.")

    static let isDiscoverable = false

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    // Neither value can light the fire.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Wave Mode")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        try await FireplaceIntentSupport.performForControl(
            .setWaveMode(enabled: value),
            failure: String(localized: "Could not change wave mode.")
        )
        return .result()
    }
}
