import AppIntents

/// Turn wave (eco) mode on. Only while the fire burns: never lights the fire.
struct EnableEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn On Wave Mode"

    static let description = IntentDescription("Turns on wave mode while the DRU fireplace is burning. Does not light the fire.")

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await FireplaceIntentSupport.perform(
            .setWaveMode(enabled: true),
            success: "Wave mode is now on.",
            failure: String(localized: "Could not turn on wave mode.")
        )
        return .result(dialog: dialog)
    }
}
