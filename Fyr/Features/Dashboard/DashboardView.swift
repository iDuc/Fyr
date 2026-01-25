import SwiftUI

/// Main dashboard view for controlling the fireplace
/// Features iOS 26 liquid glass design with animated backgrounds
struct DashboardView: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var flameHeight: Double = 8
    @State private var targetTemperature: Double = 21

    /// Polling timer for status updates
    @State private var statusTask: Task<Void, Never>?

    /// Track consecutive failures for exponential backoff
    @State private var consecutiveFailures: Int = 0

    /// Track stable state count for adaptive polling
    @State private var stableStateCount: Int = 0

    /// Last known fireplace on/off state for stability detection
    @State private var lastKnownIsOn: Bool?

    /// Last known flame height for stability detection
    @State private var lastKnownFlameHeight: Int?

    // MARK: - Polling Configuration

    /// Base polling interval when fireplace is ON (seconds)
    private let activePollingInterval: Double = 15.0

    /// Polling interval when fireplace is OFF (seconds)
    private let idlePollingInterval: Double = 60.0

    /// Maximum polling interval when state is stable for a long time (seconds)
    private let maxStablePollingInterval: Double = 120.0

    /// Maximum polling interval during backoff (seconds)
    private let maxPollingInterval: Double = 60.0

    /// Number of stable polls before increasing interval
    private let stableThreshold: Int = 4

    /// Command timeout in seconds
    private let commandTimeout: Double = 30.0

    var body: some View {
        NavigationStack {
            ZStack {
                // Dynamic animated background
                DynamicBackground(isFireplaceOn: fireplace.isOn)

                // Main content
                ScrollView {
                    VStack(spacing: FyrDesign.Spacing.md) {
                        // Error banner if present (only shown when there's an error)
                        if let errorCode = fireplace.errorCode {
                            ErrorBanner(errorCode: errorCode)
                                .padding(.horizontal)
                        }

                        // Hero section with flame indicator
                        heroSection

                        // Controls section (visible when on)
                        if fireplace.isOn {
                            controlsSection
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle(String(localized: "Fyr"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .refreshable {
                await refreshStatus()
            }
            .task {
                await startPolling()
            }
            .onDisappear {
                statusTask?.cancel()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: FyrDesign.Spacing.md) {
            // Large flame indicator with eco mode support (no percentage badge - shown in slider)
            FlameIndicator(
                flameHeight: fireplace.flameHeight,
                isOn: fireplace.isOn,
                ecoModeActive: fireplace.ecoModeActive,
                size: .large,
                showPercentage: false
            )

            // Quick stats row
            quickStatsRow

            // Ignition slider
            IgnitionSlider(
                onIgnite: { await turnOn() },
                onExtinguish: { await turnOff() }
            )
            .padding(.horizontal, FyrDesign.Spacing.xl)
        }
        .padding(.vertical, FyrDesign.Spacing.sm)
    }

    @ViewBuilder
    private var quickStatsRow: some View {
        HStack(spacing: FyrDesign.Spacing.lg) {
            // Current temperature
            HStack(spacing: FyrDesign.Spacing.xs) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(FyrDesign.Colors.textSecondary)

                Text(fireplace.formattedTemperature)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
            }

            // Eco mode badge
            if fireplace.ecoModeActive {
                HStack(spacing: FyrDesign.Spacing.xs) {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                    Text(String(localized: "Eco"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(FyrDesign.Colors.ecoGreen)
                .padding(.horizontal, FyrDesign.Spacing.sm)
                .padding(.vertical, FyrDesign.Spacing.xs)
                .background(FyrDesign.Colors.ecoGreenSubtle)
                .clipShape(Capsule())
            }

            // Connection indicator
            connectionIndicator
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            Text(connectionText)
                .font(.caption)
                .foregroundStyle(FyrDesign.Colors.textTertiary)
        }
    }

    private var connectionColor: Color {
        switch fireplace.connectionState {
        case .connected:
            return FyrDesign.Colors.connected
        case .connecting, .reconnecting:
            return FyrDesign.Colors.warning
        case .disconnected, .failed:
            return FyrDesign.Colors.error
        }
    }

    private var connectionText: String {
        switch fireplace.connectionState {
        case .connected:
            return String(localized: "Connected")
        case .connecting:
            return String(localized: "Connecting...")
        case .reconnecting:
            return String(localized: "Reconnecting...")
        case .disconnected:
            return String(localized: "Disconnected")
        case .failed:
            return String(localized: "Failed")
        }
    }

    // MARK: - Controls Section

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: FyrDesign.Spacing.md) {
            // Flame height slider with glass effect
            FlameHeightSlider(
                value: $flameHeight,
                ecoModeActive: fireplace.ecoModeActive
            ) { newValue in
                Task {
                    await setFlameHeight(newValue)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
            .padding(.horizontal)

            // Temperature control with glass effect
            TemperatureControl(
                targetTemperature: $targetTemperature,
                currentTemperature: fireplace.currentTemperature
            ) { newValue in
                Task {
                    await setTemperature(newValue)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
            .padding(.horizontal)

            // Eco mode toggle with glass effect
            ecoModeToggle
                .padding(FyrDesign.Spacing.md)
                .glassCard()
                .padding(.horizontal)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
            .spring(response: FyrDesign.Animation.springResponse, dampingFraction: FyrDesign.Animation.springDamping),
            value: fireplace.isOn
        )
    }

    @ViewBuilder
    private var ecoModeToggle: some View {
        @Bindable var fp = fireplace

        Toggle(isOn: $fp.targetEcoMode) {
            HStack(spacing: FyrDesign.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(FyrDesign.Colors.ecoGreenSubtle)
                        .frame(width: 36, height: 36)

                    Image(systemName: fp.targetEcoMode ? "leaf.fill" : "leaf")
                        .foregroundStyle(FyrDesign.Colors.ecoGreen)
                        .symbolEffect(.bounce, value: fp.targetEcoMode)
                }

                VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                    Text(String(localized: "Wave Mode"))
                        .font(.headline)
                        .foregroundStyle(FyrDesign.Colors.textPrimary)

                    Text(String(localized: "Varies flame to your set level for efficiency"))
                        .font(.caption)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
            }
        }
        .tint(FyrDesign.Colors.ecoGreen)
        .onChange(of: fp.targetEcoMode) { _, newValue in
            Task {
                await setEcoMode(newValue)
            }
        }
    }

    // MARK: - Actions

    /// Execute a command with timeout protection and automatic status refresh
    private func executeCommand(_ command: @escaping () async throws -> Void) async {
        fireplace.isProcessing = true
        defer { fireplace.isProcessing = false }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await command()
                }
                group.addTask { [commandTimeout] in
                    try await Task.sleep(for: .seconds(commandTimeout))
                    throw DRUServiceError.commandThrottled
                }
                try await group.next()
                group.cancelAll()
            }
            await refreshStatus()
        } catch {
            fireplace.connectionError = error
            if case DRUServiceError.notConnected = error {
                fireplace.connectionState = .reconnecting
            }
        }
    }

    private func turnOn() async {
        await executeCommand { try await DRUFireplaceService.shared.turnOn() }
    }

    private func turnOff() async {
        await executeCommand { try await DRUFireplaceService.shared.turnOff() }
    }

    private func setFlameHeight(_ height: Int) async {
        do {
            try await DRUFireplaceService.shared.setFlameHeight(height)
        } catch {
            fireplace.connectionError = error
        }
    }

    private func setTemperature(_ temp: Double) async {
        do {
            try await DRUFireplaceService.shared.setThermostatSetpoint(temp)
        } catch {
            fireplace.connectionError = error
        }
    }

    private func setEcoMode(_ enabled: Bool) async {
        do {
            try await DRUFireplaceService.shared.setEcoMode(enabled: enabled)
        } catch {
            fireplace.connectionError = error
        }
    }

    // MARK: - Status Polling

    private func startPolling() async {
        print("[Dashboard] startPolling() called")

        // Connect to bridge
        guard let bridgeIP = settings.bridgeIP else {
            print("[Dashboard] No bridge IP configured")
            fireplace.connectionState = .disconnected
            return
        }

        print("[Dashboard] Connecting to \(bridgeIP)...")
        fireplace.connectionState = .connecting

        do {
            try await DRUFireplaceService.shared.connect(to: bridgeIP)
            print("[Dashboard] Connection successful, fetching initial status...")
            fireplace.connectionState = .connected

            // Fetch initial status
            await refreshStatus()

            print("[Dashboard] Initial status fetch complete, starting polling loop")

            // Start polling loop with adaptive intervals
            statusTask = Task {
                while !Task.isCancelled {
                    let finalInterval = calculatePollingInterval()

                    try? await Task.sleep(for: .seconds(finalInterval))

                    // Skip polling if we're in the background
                    guard scenePhase == .active else {
                        print("[Dashboard] Skipping poll - app not active (phase: \(scenePhase))")
                        continue
                    }

                    print("[Dashboard] Polling: refreshing status (interval: \(finalInterval)s, stable: \(stableStateCount), failures: \(consecutiveFailures), isOn: \(fireplace.isOn))...")
                    await refreshStatus()
                }
            }
        } catch {
            print("[Dashboard] Connection failed: \(error.localizedDescription)")
            fireplace.connectionState = .failed(error.localizedDescription)

            // Retry connection after delay
            Task {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    print("[Dashboard] Retrying connection...")
                    await startPolling()
                }
            }
        }
    }

    private func refreshStatus() async {
        print("[Dashboard] refreshStatus() called")
        do {
            let status = try await DRUFireplaceService.shared.fetchStatus()
            print("[Dashboard] Status fetched successfully")

            // Reset failure count on success
            consecutiveFailures = 0

            // Update connection state on success
            if fireplace.connectionState != .connected {
                fireplace.connectionState = .connected
            }

            fireplace.update(from: status)

            // Track stability for adaptive polling
            updateStabilityTracking()

            // Sync UI state with fireplace state if we have a valid flame height
            if status.flameHeight > 0 {
                flameHeight = Double(status.flameHeight)
            }

            // Cache for widget
            settings.cacheStatus(status)
        } catch is CancellationError {
            // Task was cancelled (e.g., navigation away from view)
            // This is expected behavior, don't change connection state
            print("[Dashboard] Status fetch cancelled (navigation)")
        } catch {
            // Increment failure count for exponential backoff
            consecutiveFailures += 1
            // Reset stability tracking on failures
            stableStateCount = 0
            print("[Dashboard] Status fetch failed (consecutive failures: \(consecutiveFailures))")

            // Handle actual connection errors
            switch fireplace.connectionState {
            case .connected:
                fireplace.connectionState = .reconnecting
            case .reconnecting:
                // Already reconnecting, let it retry
                break
            default:
                break
            }

            fireplace.connectionError = error
        }
    }

    // MARK: - Adaptive Polling

    /// Calculate the optimal polling interval based on current state
    private func calculatePollingInterval() -> Double {
        // If we have failures, use exponential backoff
        if consecutiveFailures > 0 {
            let backoffMultiplier = pow(2.0, Double(min(consecutiveFailures, 4)))
            let intervalWithBackoff = min(activePollingInterval * backoffMultiplier, maxPollingInterval)
            return addJitter(to: intervalWithBackoff)
        }

        // Base interval depends on fireplace state
        let baseInterval: Double
        if fireplace.isOn {
            // Fireplace is ON - poll more frequently
            baseInterval = activePollingInterval
        } else {
            // Fireplace is OFF - poll less frequently
            baseInterval = idlePollingInterval
        }

        // If state has been stable, gradually increase interval
        let stabilityMultiplier: Double
        if stableStateCount >= stableThreshold * 2 {
            stabilityMultiplier = 2.0
        } else if stableStateCount >= stableThreshold {
            stabilityMultiplier = 1.5
        } else {
            stabilityMultiplier = 1.0
        }

        let interval = min(baseInterval * stabilityMultiplier, maxStablePollingInterval)
        return addJitter(to: interval)
    }

    /// Add random jitter to prevent synchronized polling
    private func addJitter(to interval: Double, minimum: Double = 5.0) -> Double {
        let jitter = Double.random(in: -2...2)
        return max(minimum, interval + jitter)
    }

    /// Update stability tracking after a status refresh
    private func updateStabilityTracking() {
        let currentIsOn = fireplace.isOn
        let currentFlameHeight = fireplace.flameHeight

        // Check if state has changed
        if lastKnownIsOn != currentIsOn || lastKnownFlameHeight != currentFlameHeight {
            // State changed - reset stability counter
            stableStateCount = 0
            print("[Dashboard] State changed - resetting stability (isOn: \(lastKnownIsOn ?? false) -> \(currentIsOn), flame: \(lastKnownFlameHeight ?? 0) -> \(currentFlameHeight))")
        } else {
            // State is stable - increment counter
            stableStateCount += 1
            print("[Dashboard] State stable for \(stableStateCount) polls")
        }

        // Update last known state
        lastKnownIsOn = currentIsOn
        lastKnownFlameHeight = currentFlameHeight
    }

    /// Handle app moving between foreground and background
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        print("[Dashboard] Scene phase changed: \(oldPhase) -> \(newPhase)")

        switch newPhase {
        case .active:
            // App became active - refresh immediately if we were in background
            if oldPhase == .background {
                print("[Dashboard] Returning from background - refreshing status")
                Task {
                    await refreshStatus()
                }
            }

        case .inactive:
            // App is transitioning (e.g., Control Center opened)
            // Keep polling but it will be skipped due to scenePhase check
            break

        case .background:
            // App went to background - polling will be skipped automatically
            print("[Dashboard] App went to background - polling paused")

        @unknown default:
            break
        }
    }
}

// MARK: - Preview

#Preview("Dashboard - Connected") {
    let fireplace = Fireplace.preview
    let settings = SettingsStore.shared
    settings.bridgeIP = "192.168.1.100"
    settings.hasCompletedOnboarding = true

    return DashboardView()
        .environment(fireplace)
        .environment(settings)
}

#Preview("Dashboard - Eco Mode") {
    let fireplace = Fireplace.preview
    fireplace.ecoModeActive = true
    let settings = SettingsStore.shared
    settings.bridgeIP = "192.168.1.100"

    return DashboardView()
        .environment(fireplace)
        .environment(settings)
}

#Preview("Dashboard - Off") {
    let fireplace = Fireplace.previewDisconnected
    let settings = SettingsStore.shared

    return DashboardView()
        .environment(fireplace)
        .environment(settings)
}
