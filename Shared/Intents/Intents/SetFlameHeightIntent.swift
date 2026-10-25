import AppIntents

/// Set the flame height (0-100 %). Only while the fire burns: never lights the fire.
struct SetFlameHeightIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Flame Height"

    static let description = IntentDescription("Sets the flame height while the DRU fireplace is burning. Does not light the fire.")

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(
        title: "Percentage",
        description: "Flame height as percentage (0-100)",
        default: 50,
        inclusiveRange: (0, 100),
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

        let dialog = try await FireplaceIntentSupport.perform(
            .setFlameHeight(clampedPercentage),
            success: "Flame set to \(clampedPercentage) percent.",
            failure: String(localized: "Could not set the flame height.")
        )
        return .result(dialog: dialog)
    }
}
