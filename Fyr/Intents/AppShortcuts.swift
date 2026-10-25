import AppIntents

/// App Shortcuts for Siri, Spotlight and the Shortcuts app.
///
/// Phrases are written in English here; the Dutch phrases are their
/// translations in `AppShortcuts.xcstrings` (one English phrase can have
/// several Dutch variants). Order matters: the first shortcuts are shown most
/// prominently, so on/off and wave mode come first. The thermostat intent
/// stays available in Shortcuts but is not promoted here.
struct FyrShortcuts: AppShortcutsProvider {

    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        // Asks to unlock and to confirm before lighting the fire.
        AppShortcut(
            intent: TurnOnFireplaceIntent(),
            phrases: [
                "Turn on \(.applicationName)",
                "Turn on the fireplace with \(.applicationName)",
                "Light the fire with \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Fire On",
            systemImageName: "flame.fill"
        )

        AppShortcut(
            intent: TurnOffFireplaceIntent(),
            phrases: [
                "Turn off \(.applicationName)",
                "Turn off the fireplace with \(.applicationName)",
                "Put out the fire with \(.applicationName)",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Fire Off",
            systemImageName: "flame.slash"
        )

        AppShortcut(
            intent: EnableEcoModeIntent(),
            phrases: [
                "Turn on wave mode with \(.applicationName)",
                "Start wave mode with \(.applicationName)",
                "Turn on eco mode with \(.applicationName)"
            ],
            shortTitle: "Wave On",
            systemImageName: "water.waves"
        )

        AppShortcut(
            intent: DisableEcoModeIntent(),
            phrases: [
                "Turn off wave mode with \(.applicationName)",
                "Stop wave mode with \(.applicationName)",
                "Turn off eco mode with \(.applicationName)"
            ],
            shortTitle: "Wave Off",
            systemImageName: "water.waves.slash"
        )

        AppShortcut(
            intent: GetFireplaceStatusIntent(),
            phrases: [
                "Is \(.applicationName) on",
                "Status of \(.applicationName)",
                "Is the fireplace on with \(.applicationName)"
            ],
            shortTitle: "Status",
            systemImageName: "info.circle"
        )

        // Siri asks for the percentage. Only works while the fire burns.
        AppShortcut(
            intent: SetFlameHeightIntent(),
            phrases: [
                "Set the flame with \(.applicationName)",
                "Change the flame height with \(.applicationName)"
            ],
            shortTitle: "Flame Height",
            systemImageName: "slider.horizontal.3"
        )
    }
}
