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

    static var title: LocalizedStringResource = "Set Eco Mode"

    static var description = IntentDescription("Enables or disables eco mode on the DRU fireplace")

    static var openAppWhenRun: Bool = false

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
        let service = DRUFireplaceService.shared
        let isConnected = await service.isConnected
        if !isConnected {
            if let ip = SettingsStore.bridgeIPValue {
                try await service.connect(to: ip)
            } else {
                return .result(dialog: "Please configure your fireplace in the Fyr app first.")
            }
        }

        let enable = state == .on

        do {
            try await service.setEcoMode(enabled: enable)

            if enable {
                return .result(dialog: "Eco mode is now on. The flame will vary to save energy.")
            } else {
                return .result(dialog: "Eco mode is now off.")
            }
        } catch {
            return .result(dialog: "Could not change eco mode. Please check the connection.")
        }
    }
}
