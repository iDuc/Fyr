import AppIntents

/// Intent to set the flame height
/// Users specify height as a percentage (0-100)
struct SetFlameHeightIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Flame Height"

    static let description = IntentDescription("Sets the flame height of the DRU fireplace")

    static let openAppWhenRun: Bool = false

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

        // Flame height changes are limited to one per 10 seconds.
        let cooldown = await DRUFireplaceService.shared.flameHeightCooldown()
        if cooldown > .zero {
            let seconds = Int(cooldown.components.seconds) + 1
            return .result(dialog: "Please wait \(seconds) seconds before changing the flame height again.")
        }

        let dialog = await FireplaceIntentSupport.perform(
            success: "Flame set to \(clampedPercentage) percent.",
            failure: String(localized: "Could not set the flame height.")
        ) { try await $0.setFlameHeight(clampedPercentage) }
        return .result(dialog: dialog)
    }
}
