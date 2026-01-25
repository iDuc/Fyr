import SwiftUI
import AppIntents

/// Main app entry point
@main
struct FyrApp: App {

    // MARK: - State

    /// Main fireplace model shared across the app
    @State private var fireplace = Fireplace()

    /// Settings store for persisted configuration
    @State private var settings = SettingsStore.shared

    // MARK: - Initialization

    init() {
        // Register App Shortcuts with the system
        FyrShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(fireplace)
                .environment(settings)
        }
    }
}

/// Root content view that handles navigation based on onboarding state
struct ContentView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.hasCompletedOnboarding {
            DashboardView()
        } else {
            OnboardingFlow()
        }
    }
}
