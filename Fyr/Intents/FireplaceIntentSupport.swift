import AppIntents

/// Shared plumbing for the fireplace App Intents: configure the service from
/// the saved settings, run the command, and always release the bridge
/// connection afterwards (the bridge accepts one connection, and the app may
/// be suspended right after the intent finishes).
nonisolated enum FireplaceIntentSupport {

    /// Run `body` against the fireplace service and turn the outcome into a dialog.
    static func perform(
        success: @autoclosure () -> IntentDialog,
        failure: String,
        _ body: (DRUFireplaceService) async throws -> Void
    ) async -> IntentDialog {
        let service = DRUFireplaceService.shared
        do {
            try await service.configureFromSettings()
            try await body(service)
            await service.releaseConnection()
            return success()
        } catch {
            await service.releaseConnection()
            return dialog(for: error, failure: failure)
        }
    }

    /// Dialog for a failed command, with the reason and what to do about it.
    static func dialog(for error: any Error, failure: String) -> IntentDialog {
        guard let bridgeError = error as? BridgeError else {
            return IntentDialog(stringLiteral: failure)
        }
        if bridgeError == .notConfigured {
            return IntentDialog(stringLiteral: String(localized: "Please configure your fireplace in the Fyr app first."))
        }
        let parts = [failure, bridgeError.localizedDescription + ".", bridgeError.recoverySuggestion]
        return IntentDialog(stringLiteral: parts.compactMap { $0 }.joined(separator: " "))
    }
}
