import SwiftUI
import AppIntents

/// Main app entry point
@main
struct FyrApp: App {

    /// Main fireplace model shared across the app
    @State private var fireplace: Fireplace
    /// Polls the bridge and sends commands for the dashboard
    @State private var controller: FireplaceController
    /// Settings store for persisted configuration
    @State private var settings = SettingsStore.shared

    init() {
        #if DEBUG
        UITestSupport.prepare()
        #endif
        let fireplace = Fireplace()
        _fireplace = State(initialValue: fireplace)
        _controller = State(initialValue: FireplaceController(fireplace: fireplace))
        FyrShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(fireplace)
                .environment(controller)
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

#if DEBUG
/// Hooks for UI tests and screenshots (DEBUG builds only).
enum UITestSupport {
    /// `-FyrUITestReset YES`: start without a saved status, flame height or
    /// Live Activity, so every test sees the same first screen.
    static let resetArgument = "FyrUITestReset"

    static func prepare() {
        guard UserDefaults.standard.bool(forKey: resetArgument) else { return }
        let defaults = FyrAppGroup.defaults
        for key in [FireplaceSnapshot.storageKey, AppGroupFlameHeightStore.key] {
            defaults.removeObject(forKey: key)
        }
        Task { await FireLiveActivity.endAll() }
    }
}
#endif
