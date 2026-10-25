import SwiftUI
import UIKit
import os

/// Main dashboard view for controlling the fireplace
/// Features iOS 26 liquid glass design with animated backgrounds
struct DashboardView: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var flameHeight = Double(DRUConstants.defaultFlameHeight)
    @State private var targetTemperature: Double = 21

    /// Track consecutive failures for exponential backoff
    @State private var consecutiveFailures: Int = 0

    /// Track stable state count for adaptive polling
    @State private var stableStateCount: Int = 0

    /// Last known fireplace on/off state for stability detection
    @State private var lastKnownIsOn: Bool?

    /// Last known wave mode for stability detection
    @State private var lastKnownWaveMode: Bool?

    private let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "Dashboard")

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
                await refreshStatus(priority: .userInitiated)
            }
            .task(id: scenePhase) {
                await runSession(for: scenePhase)
            }
            .onAppear {
                targetTemperature = settings.targetTemperature
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

            if let error = fireplace.lastError {
                errorMessage(for: error)
            }

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
    private func errorMessage(for error: BridgeError) -> some View {
        VStack(spacing: FyrDesign.Spacing.xxs) {
            Text(error.localizedDescription)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FyrDesign.Colors.textPrimary)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, FyrDesign.Spacing.xl)
        .accessibilityElement(children: .combine)
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
        let isOn = fireplace.displayedWaveMode
        let binding = Binding(
            get: { fireplace.displayedWaveMode },
            set: { newValue in Task { await setWaveMode(newValue) } }
        )

        Toggle(isOn: binding) {
            HStack(spacing: FyrDesign.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(FyrDesign.Colors.ecoGreenSubtle)
                        .frame(width: 36, height: 36)

                    Image(systemName: isOn ? "leaf.fill" : "leaf")
                        .foregroundStyle(FyrDesign.Colors.ecoGreen)
                        .symbolEffect(.bounce, value: isOn)
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
        .disabled(fireplace.pendingWaveMode != nil)
    }

    // MARK: - Actions

    private var service: DRUFireplaceService { .shared }

    /// Run a user command, then refresh the status. Errors are shown in the dashboard.
    private func executeCommand(_ command: @escaping @Sendable () async throws(BridgeError) -> Void) async {
        fireplace.isProcessing = true
        defer { fireplace.isProcessing = false }

        do {
            try await command()
            fireplace.lastError = nil
            await refreshStatus(priority: .userInitiated)
        } catch {
            handle(error)
        }
    }

    private func turnOn() async {
        await executeCommand { [service] () throws(BridgeError) in
            try await service.turnOn(authorization: .appSlider)
        }
    }

    private func turnOff() async {
        await executeCommand { [service] () throws(BridgeError) in
            try await service.turnOff()
        }
    }

    private func setFlameHeight(_ height: Int) async {
        do {
            try await service.setFlameHeight(height)
            fireplace.flameHeight = await service.lastSetFlameHeight ?? height
            fireplace.flameHeightIsKnown = true
        } catch {
            handle(error)
        }
    }

    private func setTemperature(_ temp: Double) async {
        settings.targetTemperature = temp
        do {
            try await service.setThermostatSetpoint(temp)
        } catch {
            handle(error)
        }
    }

    private func setWaveMode(_ enabled: Bool) async {
        fireplace.pendingWaveMode = enabled
        await executeCommand { [service] () throws(BridgeError) in
            try await service.setWaveMode(enabled: enabled)
        }
        if fireplace.lastError != nil {
            fireplace.pendingWaveMode = nil
        }
    }

    private func handle(_ error: BridgeError) {
        guard error != .cancelled else { return }
        logger.error("Bridge error: \(String(describing: error))")
        fireplace.lastError = error
        if error.isConnectionProblem {
            fireplace.connectionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Connection lifecycle

    /// Driven by `.task(id: scenePhase)`: polls while active, and releases the
    /// bridge's single connection in the background so the DRU app can connect.
    private func runSession(for phase: ScenePhase) async {
        switch phase {
        case .active:
            await pollWhileActive()
        case .background:
            // Ask for background time: a suspended app would keep the socket
            // open and block the bridge's only connection slot.
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Release bridge connection")
            logger.info("Background: releasing bridge connection")
            await service.releaseConnection()
            fireplace.connectionState = .disconnected
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        default:
            break
        }
    }

    private func pollWhileActive() async {
        if fireplace.lastStatusUpdate == nil, let snapshot = settings.loadSnapshot() {
            fireplace.restore(from: snapshot)
            flameHeight = Double(fireplace.flameHeight)
        }

        do {
            try await service.configureFromSettings()
        } catch {
            fireplace.connectionState = .disconnected
            fireplace.lastError = error
            return
        }

        fireplace.connectionState = .connecting
        await refreshStatus(priority: .userInitiated)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(calculatePollingInterval()))
            guard !Task.isCancelled else { break }
            await refreshStatus(priority: .automatic)
        }
    }

    private func refreshStatus(priority: DRUFireplaceService.Priority = .userInitiated) async {
        do {
            let status = try await service.fetchStatus(priority: priority)
            consecutiveFailures = 0
            fireplace.connectionState = .connected
            fireplace.update(from: status)
            updateStabilityTracking()
            if status.flameHeightIsKnown {
                flameHeight = Double(status.flameHeight)
            }
        } catch .cancelled {
            // View disappeared or app went to the background.
        } catch {
            consecutiveFailures += 1
            stableStateCount = 0
            handle(error)
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

        // Poll more often while the fire is on
        let baseInterval = fireplace.isOn ? activePollingInterval : idlePollingInterval

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
        let currentWaveMode = fireplace.ecoModeActive

        if lastKnownIsOn != currentIsOn || lastKnownWaveMode != currentWaveMode {
            stableStateCount = 0
        } else {
            stableStateCount += 1
        }

        lastKnownIsOn = currentIsOn
        lastKnownWaveMode = currentWaveMode
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
