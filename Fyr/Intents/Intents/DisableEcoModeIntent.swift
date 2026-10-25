import AppIntents

/// Intent to disable eco/wave mode - no parameters needed
struct DisableEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Disable Eco Mode"

    static let description = IntentDescription("Disables eco mode on the DRU fireplace")

    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Turn eco mode off")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await FireplaceIntentSupport.perform(
            success: "Eco mode is now off.",
            failure: String(localized: "Could not disable eco mode.")
        ) { try await $0.setWaveMode(enabled: false) }
        return .result(dialog: dialog)
    }
}
