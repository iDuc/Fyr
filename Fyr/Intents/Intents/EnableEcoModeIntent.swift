import AppIntents

/// Intent to enable eco/wave mode - no parameters needed
struct EnableEcoModeIntent: AppIntent {

    static var title: LocalizedStringResource = "Enable Eco Mode"

    static var description = IntentDescription("Enables eco mode on the DRU fireplace")

    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Turn eco mode on")
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
            try await service.setEcoMode(enabled: true)
            return .result(dialog: "Eco mode is now on. The flame will vary to save energy.")
        } catch {
            return .result(dialog: "Could not enable eco mode. Please check the connection.")
        }
    }
}
