import AppIntents

/// Intent to turn on the fireplace
struct TurnOnFireplaceIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn On Fireplace"

    static let description = IntentDescription("Turns on the DRU fireplace")

    /// Run in background without opening the app
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Phase 2 (safety policy) adds `.requiresAuthentication` and a confirmation
        // step, and then passes `.confirmedIntent` instead.
        let dialog = await FireplaceIntentSupport.perform(
            success: "The fireplace is now on.",
            failure: String(localized: "Could not turn on the fireplace.")
        ) { try await $0.turnOn(authorization: .unconfirmedIntent) }
        return .result(dialog: dialog)
    }
}
