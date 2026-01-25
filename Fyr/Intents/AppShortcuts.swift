import AppIntents

/// App Shortcuts provider for Siri integration
/// Includes both English and Dutch (Nederlands) phrases
/// Note: "Fyr" pronunciation - can be said as "Fire", "Feer", or "Fear"
struct FyrShortcuts: AppShortcutsProvider {

    /// Alternative app names for Siri pronunciation
    /// Helps Siri recognize "Fyr" pronounced different ways
    static var shortcutTileColor: ShortcutTileColor { .orange }

    /// All available app shortcuts
    static var appShortcuts: [AppShortcut] {
        // MARK: - Turn On Fireplace
        AppShortcut(
            intent: TurnOnFireplaceIntent(),
            phrases: [
                // Primary phrase with app name (required)
                "Turn on \(.applicationName)",
                "Start \(.applicationName)",
                // Natural English phrases
                "Turn on the fireplace with \(.applicationName)",
                "Start the fireplace with \(.applicationName)",
                "Light the fire with \(.applicationName)",
                // Dutch phrases - "openhaard" = fireplace
                "Zet \(.applicationName) aan",
                "Start \(.applicationName)",
                "Doe de openhaard aan met \(.applicationName)",
                "Zet de openhaard aan met \(.applicationName)",
                "Start de openhaard met \(.applicationName)"
            ],
            shortTitle: "Turn On",
            systemImageName: "flame"
        )

        // MARK: - Turn Off Fireplace
        AppShortcut(
            intent: TurnOffFireplaceIntent(),
            phrases: [
                // Primary phrase with app name
                "Turn off \(.applicationName)",
                "Stop \(.applicationName)",
                // Natural English phrases
                "Turn off the fireplace with \(.applicationName)",
                "Stop the fireplace with \(.applicationName)",
                // Dutch phrases
                "Zet \(.applicationName) uit",
                "Stop \(.applicationName)",
                "Doe de openhaard uit met \(.applicationName)",
                "Zet de openhaard uit met \(.applicationName)",
                "Stop de openhaard met \(.applicationName)"
            ],
            shortTitle: "Turn Off",
            systemImageName: "flame.slash"
        )

        // MARK: - Set Flame Height
        AppShortcut(
            intent: SetFlameHeightIntent(),
            phrases: [
                // Primary phrases - Siri will prompt for percentage (0-100)
                "Set flame with \(.applicationName)",
                "Set flame height with \(.applicationName)",
                "Adjust flame with \(.applicationName)",
                "Change flame level with \(.applicationName)",
                // Alternative phrasings
                "Set \(.applicationName) flame",
                "Adjust \(.applicationName) flame",
                // Dutch phrases - "vlammen" = flames, "vlamhoogte" = flame height
                "Stel vlamhoogte in met \(.applicationName)",
                "Zet de vlammen in met \(.applicationName)",
                "Pas de vlammen aan met \(.applicationName)",
                "Stel vlam in met \(.applicationName)"
            ],
            shortTitle: "Set Flame",
            systemImageName: "flame"
        )

        // MARK: - Set Temperature
        AppShortcut(
            intent: SetTemperatureIntent(),
            phrases: [
                // Primary phrases
                "Set temperature with \(.applicationName)",
                "Change temperature with \(.applicationName)",
                // Natural English phrases
                "Set fireplace temperature with \(.applicationName)",
                "Adjust fireplace temperature with \(.applicationName)",
                // Dutch phrases
                "Stel temperatuur in met \(.applicationName)",
                "Zet de temperatuur op met \(.applicationName)",
                "Pas de temperatuur aan met \(.applicationName)"
            ],
            shortTitle: "Set Temperature",
            systemImageName: "thermometer.medium"
        )

        // MARK: - Enable Eco/Wave Mode
        AppShortcut(
            intent: EnableEcoModeIntent(),
            phrases: [
                // English phrases - ON
                "Turn on eco mode with \(.applicationName)",
                "Enable eco mode with \(.applicationName)",
                "Turn eco mode on with \(.applicationName)",
                "Start eco mode with \(.applicationName)",
                // Wave mode (DRU terminology)
                "Turn on wave mode with \(.applicationName)",
                "Enable wave mode with \(.applicationName)",
                // Dutch phrases - eco-modus AAN (on)
                "Zet eco-modus aan met \(.applicationName)",
                "Schakel eco-modus in met \(.applicationName)",
                "Zet de eco-modus aan met \(.applicationName)",
                "Zet wave-modus aan met \(.applicationName)",
                "Schakel wave-modus in met \(.applicationName)"
            ],
            shortTitle: "Eco On",
            systemImageName: "leaf.fill"
        )

        // MARK: - Disable Eco/Wave Mode
        AppShortcut(
            intent: DisableEcoModeIntent(),
            phrases: [
                // English phrases - OFF
                "Turn off eco mode with \(.applicationName)",
                "Disable eco mode with \(.applicationName)",
                "Turn eco mode off with \(.applicationName)",
                "Stop eco mode with \(.applicationName)",
                // Wave mode (DRU terminology)
                "Turn off wave mode with \(.applicationName)",
                "Disable wave mode with \(.applicationName)",
                // Dutch phrases - eco-modus UIT (off)
                "Zet eco-modus uit met \(.applicationName)",
                "Schakel eco-modus uit met \(.applicationName)",
                "Zet de eco-modus uit met \(.applicationName)",
                "Zet wave-modus uit met \(.applicationName)",
                "Schakel wave-modus uit met \(.applicationName)"
            ],
            shortTitle: "Eco Off",
            systemImageName: "leaf"
        )

        // MARK: - Get Fireplace Status
        AppShortcut(
            intent: GetFireplaceStatusIntent(),
            phrases: [
                // Primary phrases
                "Status of \(.applicationName)",
                "Check \(.applicationName)",
                // Natural English phrases
                "What's the fireplace status with \(.applicationName)",
                "Is the fireplace on with \(.applicationName)",
                "Fireplace status with \(.applicationName)",
                // Dutch phrases
                "Status van \(.applicationName)",
                "Controleer \(.applicationName)",
                "Wat is de status met \(.applicationName)",
                "Staat de openhaard aan met \(.applicationName)"
            ],
            shortTitle: "Status",
            systemImageName: "info.circle"
        )
    }
}
