import AppIntents

/// Intent to turn off the fireplace. Always allowed, no confirmation.
struct TurnOffFireplaceIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn Off Fireplace"

    static let description = IntentDescription("Turns off the DRU fireplace")

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await FireplaceIntentSupport.perform(
            success: "The fireplace is now off.",
            failure: String(localized: "Could not turn off the fireplace.")
        ) { try await $0.turnOff() }
        return .result(dialog: dialog)
    }
}
