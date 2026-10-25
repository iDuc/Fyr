import AppIntents

/// Light the fireplace from Siri, Shortcuts, widgets or controls.
///
/// Safety policy: the device must be unlocked (`authenticationPolicy`) and the
/// user must confirm this run (`requestConfirmation`) before anything is sent.
struct TurnOnFireplaceIntent: AppIntent {

    static let title: LocalizedStringResource = "Turn On Fireplace"

    static let description = IntentDescription("Lights the DRU fireplace. Asks you to unlock your iPhone and to confirm first.")

    static let supportedModes: IntentModes = .background

    // Must be a literal (App Intents metadata); IntentDeclarationTests checks
    // that it matches FireplaceIntentSupport.authenticationPolicy(for: .turnOn).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await FireplaceIntentSupport.perform(
            .turnOn,
            success: "The fireplace is now on.",
            failure: String(localized: "Could not turn on the fireplace."),
            confirm: {
                try await requestConfirmation(actionName: .turnOn, dialog: "Light the fireplace now?")
            }
        )
        return .result(dialog: dialog)
    }
}
