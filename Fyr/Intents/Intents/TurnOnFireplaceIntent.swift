import AppIntents

/// Intent to turn on the fireplace
struct TurnOnFireplaceIntent: AppIntent {

    static var title: LocalizedStringResource = "Turn On Fireplace"

    static var description = IntentDescription("Turns on the DRU fireplace")

    /// Run in background without opening the app
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Ensure we're connected
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
            try await service.turnOn()
            return .result(dialog: "The fireplace is now on.")
        } catch {
            return .result(dialog: "Could not turn on the fireplace. Please check the connection.")
        }
    }
}
