import SwiftUI
import UIKit
import os

/// Runs the dashboard: polls the bridge while the app is active, sends the
/// user's commands, and keeps `Fireplace` up to date. Releases the bridge's
/// single connection in the background so the DRU app can connect.
@MainActor
@Observable
final class FireplaceController {

    let fireplace: Fireplace

    @ObservationIgnored private let service: DRUFireplaceService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "Dashboard")

    // MARK: - Polling

    /// Polling while the fire burns (seconds).
    static let activePollingInterval: Double = 15
    /// Polling while the fire is off.
    static let idlePollingInterval: Double = 60
    /// Upper bound once the state has been stable for a while.
    static let maxStablePollingInterval: Double = 120
    /// Upper bound during failure backoff.
    static let maxBackoffInterval: Double = 60
    /// Stable polls before the interval grows.
    static let stableThreshold = 4
    /// Flame height changes: at most one per 10 s (enforced by the service).
    static let flameHeightInterval: TimeInterval = 10

    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var stableStateCount = 0
    @ObservationIgnored private var lastKnownState: (isOn: Bool, wave: Bool)?

    init(fireplace: Fireplace, settings: SettingsStore = .shared, service: DRUFireplaceService = .shared) {
        self.fireplace = fireplace
        self.settings = settings
        self.service = service
    }

    // MARK: - Session

    /// Driven by `.task(id: scenePhase)`: polls while active, and releases the
    /// bridge's single connection in the background.
    func runSession(for phase: ScenePhase) async {
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
        if !fireplace.hasLiveStatus, let snapshot = settings.loadSnapshot() {
            fireplace.restore(from: snapshot)
        }

        do {
            try await service.configureFromSettings()
        } catch {
            fireplace.connectionState = .disconnected
            fireplace.lastError = error
            return
        }

        fireplace.connectionState = fireplace.hasLiveStatus ? .reconnecting : .connecting
        await refresh(priority: .userInitiated)
        if let snapshot = settings.loadSnapshot() {
            // The surfaces only refresh on changes; make sure a fire that was
            // already burning gets its Live Activity when the app opens.
            await FireLiveActivity.update(for: snapshot)
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pollingInterval()))
            guard !Task.isCancelled else { break }
            await refresh(priority: .automatic)
        }
    }

    /// Read the status now.
    func refresh(priority: DRUFireplaceService.Priority = .userInitiated) async {
        do {
            let status = try await service.fetchStatus(priority: priority)
            consecutiveFailures = 0
            fireplace.connectionState = .connected
            fireplace.update(from: status)
            fireplace.burningSince = settings.loadSnapshot()?.burningSince
            updateStability()
        } catch .cancelled {
            // The view went away or the app went to the background.
        } catch {
            consecutiveFailures += 1
            stableStateCount = 0
            handle(error)
        }
    }

    // MARK: - Commands

    /// Light the fire. Only called by the swipe-to-ignite slider.
    func turnOn() async {
        await run { [service] () throws(BridgeError) in
            try await service.turnOn(authorization: .appSlider)
        }
    }

    /// Turn the fire off. Always allowed, one tap.
    func turnOff() async {
        await run { [service] () throws(BridgeError) in
            try await service.turnOff()
        }
    }

    func setWaveMode(_ enabled: Bool) async {
        fireplace.pendingWaveMode = enabled
        await run { [service] () throws(BridgeError) in
            try await service.setWaveMode(enabled: enabled)
        }
        // After the read-back (or a failure) the toggle shows the bridge again.
        fireplace.pendingWaveMode = nil
    }

    /// Set the flame height. The service sends at most one change per 10 s;
    /// a newer value replaces one that is still waiting.
    func setFlameHeight(_ height: Int) async {
        fireplace.pendingFlameHeight = height
        do {
            let sent = try await service.setFlameHeight(height)
            guard sent else { return }
            fireplace.flameHeight = await service.lastSetFlameHeight ?? height
            fireplace.flameHeightIsKnown = true
            fireplace.flameHeightReadyAt = .now.addingTimeInterval(Self.flameHeightInterval)
            fireplace.lastError = nil
            if fireplace.pendingFlameHeight == height {
                fireplace.pendingFlameHeight = nil
            }
        } catch {
            if fireplace.pendingFlameHeight == height {
                fireplace.pendingFlameHeight = nil
            }
            handle(error)
        }
    }

    func setThermostat(_ temperature: Double) async {
        settings.targetTemperature = temperature
        do {
            try await service.setThermostatSetpoint(temperature)
            fireplace.lastError = nil
        } catch {
            handle(error)
        }
    }

    /// Run a command, then read the status back.
    private func run(_ command: @escaping @Sendable () async throws(BridgeError) -> Void) async {
        fireplace.isProcessing = true
        defer { fireplace.isProcessing = false }
        do {
            try await command()
            fireplace.lastError = nil
            await refresh(priority: .userInitiated)
        } catch {
            handle(error)
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

    // MARK: - Adaptive polling

    private func pollingInterval() -> Double {
        if consecutiveFailures > 0 {
            let backoff = Self.activePollingInterval * pow(2, Double(min(consecutiveFailures, 4)))
            return Self.jitter(min(backoff, Self.maxBackoffInterval))
        }
        let base = fireplace.isOn ? Self.activePollingInterval : Self.idlePollingInterval
        let multiplier: Double = if stableStateCount >= Self.stableThreshold * 2 {
            2
        } else if stableStateCount >= Self.stableThreshold {
            1.5
        } else {
            1
        }
        return Self.jitter(min(base * multiplier, Self.maxStablePollingInterval))
    }

    /// ±2 s, so several devices do not poll in step.
    static func jitter(_ interval: Double, minimum: Double = 5) -> Double {
        max(minimum, interval + Double.random(in: -2...2))
    }

    private func updateStability() {
        let state = (isOn: fireplace.isOn, wave: fireplace.ecoModeActive)
        if let last = lastKnownState, last == state {
            stableStateCount += 1
        } else {
            stableStateCount = 0
        }
        lastKnownState = state
    }
}
