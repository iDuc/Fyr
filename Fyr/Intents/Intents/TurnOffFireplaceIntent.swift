import AppIntents

/// Intent to turn off the fireplace
struct TurnOffFireplaceIntent: AppIntent {

    static var title: LocalizedStringResource = "Turn Off Fireplace"

    static var description = IntentDescription("Turns off the DRU fireplace")

    static var openAppWhenRun: Bool = false

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
            try await service.turnOff()
            return .result(dialog: "The fireplace is now off.")
        } catch {
            return .result(dialog: "Could not turn off the fireplace. Please check the connection.")
        }
    }
}
