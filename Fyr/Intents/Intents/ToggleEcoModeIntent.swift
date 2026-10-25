import AppIntents

/// Eco mode state for better Siri understanding
enum EcoModeState: String, AppEnum {
    case on
    case off

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Eco Mode State"
    }

    static var caseDisplayRepresentations: [EcoModeState: DisplayRepresentation] {
        [
            .on: DisplayRepresentation(title: "On", subtitle: "Enable eco mode"),
            .off: DisplayRepresentation(title: "Off", subtitle: "Disable eco mode")
        ]
    }
}

/// Intent to toggle eco/wave mode
struct ToggleEcoModeIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Eco Mode"

    static let description = IntentDescription("Enables or disables eco mode on the DRU fireplace")

    static let openAppWhenRun: Bool = false

    /// Eco mode state - on or off
    @Parameter(
        title: "State",
        description: "Turn eco mode on or off",
        default: .on,
        requestValueDialog: IntentDialog("Do you want eco mode on or off?")
    )
    var state: EcoModeState

    static var parameterSummary: some ParameterSummary {
        Switch(\.$state) {
            Case(.on) {
                Summary("Turn eco mode on")
            }
            Case(.off) {
                Summary("Turn eco mode off")
            }
            DefaultCase {
                Summary("Set eco mode to \(\.$state)")
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let enable = state == .on
        let dialog = await FireplaceIntentSupport.perform(
            success: enable
                ? "Eco mode is now on. The flame will vary to save energy."
                : "Eco mode is now off.",
            failure: String(localized: "Could not change eco mode.")
        ) { try await $0.setWaveMode(enabled: enable) }
        return .result(dialog: dialog)
    }
}
