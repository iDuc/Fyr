import AppIntents

/// Intent to disable eco/wave mode - no parameters needed
struct DisableEcoModeIntent: AppIntent {

    static var title: LocalizedStringResource = "Disable Eco Mode"

    static var description = IntentDescription("Disables eco mode on the DRU fireplace")

    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Turn eco mode off")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = DRUFireplaceService.shared
        let isConnected = await service.isConnected
        if !isConnected {
            if let ip = SettingsStore.bridgeIPValue {
                try await service.connect(to: ip)
            } else {
                return .result(dialog: "Please configure your fireplace in the Fyr app first.")
            }
        }

        do {
            try await service.setEcoMode(enabled: false)
            return .result(dialog: "Eco mode is now off.")
        } catch {
            return .result(dialog: "Could not disable eco mode. Please check the connection.")
        }
    }
}
