import AppIntents

/// Turn off the fireplace. Always allowed, also on a locked device, no confirmation.
struct TurnOffFireplaceIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn Off Fireplace"

    static let description = IntentDescription("Turns off the DRU fireplace")

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await FireplaceIntentSupport.perform(
            .turnOff,
            success: "The fireplace is now off.",
            failure: String(localized: "Could not turn off the fireplace.")
        )
        return .result(dialog: dialog)
    }
}
