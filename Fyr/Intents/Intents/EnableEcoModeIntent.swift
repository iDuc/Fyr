import AppIntents

/// Intent to enable eco/wave mode - no parameters needed
struct EnableEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Enable Eco Mode"

    static let description = IntentDescription("Enables eco mode on the DRU fireplace")

    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Turn eco mode on")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await FireplaceIntentSupport.perform(
            success: "Eco mode is now on. The flame will vary to save energy.",
            failure: String(localized: "Could not enable eco mode.")
        ) { try await $0.setWaveMode(enabled: true) }
        return .result(dialog: dialog)
    }
}
