import AppIntents

/// Intent to set the flame height
/// Users specify height as a percentage (0-100)
struct SetFlameHeightIntent: AppIntent {

    static var title: LocalizedStringResource = "Set Flame Height"

    static var description = IntentDescription("Sets the flame height of the DRU fireplace")

    static var openAppWhenRun: Bool = false

    /// Flame height as percentage (0-100)
    @Parameter(
        title: "Percentage",
        description: "Flame height as percentage (0-100)",
        default: 50,
        requestValueDialog: IntentDialog("What percentage should the flame be? (0-100)")
    )
    var percentage: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set flame to \(\.$percentage)%")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clampedPercentage = max(0, min(100, percentage))

        let service = DRUFireplaceService.shared
        let isConnected = await service.isConnected
        if !isConnected {
            if let ip = SettingsStore.bridgeIPValue {
                try await service.connect(to: ip)
            } else {
                return .result(dialog: "Please configure your fireplace in the Fyr app first.")
            }
        }

        // Check rate limiting
        let (allowed, timeRemaining) = await service.canChangeFlameHeight()
        if !allowed {
            let seconds = Int(timeRemaining)
            return .result(dialog: "Please wait \(seconds) seconds before changing the flame height again.")
        }

        do {
            try await service.setFlameHeight(clampedPercentage)
            return .result(dialog: "Flame set to \(clampedPercentage) percent.")
        } catch {
            return .result(dialog: "Could not set the flame height. Please check the connection.")
        }
    }
}
