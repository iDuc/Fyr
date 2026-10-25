import AppIntents

/// Turn wave (eco) mode off. Always allowed.
struct DisableEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn Off Wave Mode"

    static let description = IntentDescription("Turns off wave mode on the DRU fireplace")

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await FireplaceIntentSupport.perform(
            .setWaveMode(enabled: false),
            success: "Wave mode is now off.",
            failure: String(localized: "Could not turn off wave mode.")
        )
        return .result(dialog: dialog)
    }
}
