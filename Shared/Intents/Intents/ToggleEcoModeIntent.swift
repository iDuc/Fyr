import AppIntents

/// Wave mode state, for the Shortcuts action "Set Wave Mode".
enum EcoModeState: String, AppEnum {
    case on
    case off

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Wave Mode"
    }

    static var caseDisplayRepresentations: [EcoModeState: DisplayRepresentation] {
        [
            .on: DisplayRepresentation(title: "On"),
            .off: DisplayRepresentation(title: "Off")
        ]
    }
}

/// Set wave mode on or off (Shortcuts). Turning it on needs a burning fire.
struct ToggleEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Wave Mode"

    static let description = IntentDescription("Turns wave mode on or off. Turning it on only works while the fireplace is burning.")

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    // Both values are allowed on a locked device: neither can light the fire.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(
        title: "State",
        default: .on,
        requestValueDialog: IntentDialog("Do you want wave mode on or off?")
    )
    var state: EcoModeState

    static var parameterSummary: some ParameterSummary {
        Summary("Set wave mode \(\.$state)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let enable = state == .on
        let dialog = try await FireplaceIntentSupport.perform(
            .setWaveMode(enabled: enable),
            success: enable ? "Wave mode is now on." : "Wave mode is now off.",
            failure: String(localized: "Could not change wave mode.")
        )
        return .result(dialog: dialog)
    }
}
