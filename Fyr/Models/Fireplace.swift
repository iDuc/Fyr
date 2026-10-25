import Foundation
import Observation

/// Main observable model for the fireplace
/// Uses iOS 17+ Observation framework for reactive UI updates
@Observable
final class Fireplace {

    // MARK: - Connection State

    /// Current connection state
    var connectionState: ConnectionState = .disconnected

    /// Last error from the bridge, shown to the user until the next success
    var lastError: BridgeError?

    /// Configured bridge IP address
    var bridgeIP: String?

    // MARK: - Current Status (from polling)

    /// Whether the fireplace is currently on
    var isOn: Bool = false

    /// Current measured temperature in °C
    var currentTemperature: Double = 0

    /// Last flame height set by Fyr (0-100 %); the bridge cannot report it
    var flameHeight: Int = DRUConstants.defaultFlameHeight

    /// Whether `flameHeight` was actually set by Fyr (otherwise it is a default)
    var flameHeightIsKnown: Bool = false

    /// Whether eco/wave mode is active
    var ecoModeActive: Bool = false

    /// When Fyr saw the fire being lit (nil if unknown or off)
    var burningSince: Date?

    /// Whether there's an active error
    var hasError: Bool = false

    /// Current error code, if any
    var errorCode: FireplaceErrorCode?

    /// Signal strength percentage (0-100)
    var signalStrength: Int = 0

    // MARK: - Target Values (user-controlled)

    /// Target thermostat temperature
    var targetTemperature: Double = 21.0

    /// Wave mode state the user just asked for, shown until the bridge
    /// confirms it (or the request fails). Nil when nothing is pending.
    var pendingWaveMode: Bool?

    // MARK: - UI State

    /// Whether a command is currently being processed
    var isProcessing: Bool = false

    /// Flame height the user just asked for, until the bridge accepted it
    var pendingFlameHeight: Int?

    /// When the next flame height change can be sent (10 s rule)
    var flameHeightReadyAt: Date?

    /// Whether a status has been read from the bridge in this session
    var hasLiveStatus: Bool = false

    /// Last status update timestamp
    var lastStatusUpdate: Date?

    // MARK: - Computed Properties

    /// Shared temperature formatter to avoid repeated allocations
    private static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    /// Whether the fireplace is connected and controllable
    var isControllable: Bool {
        connectionState == .connected && !hasError
    }

    /// Wave mode as shown in the UI: the pending request, else the bridge state
    var displayedWaveMode: Bool {
        pendingWaveMode ?? ecoModeActive
    }

    /// Formatted current temperature string
    var formattedTemperature: String {
        let measurement = Measurement(value: currentTemperature, unit: UnitTemperature.celsius)
        return Self.temperatureFormatter.string(from: measurement)
    }

    /// Formatted target temperature string
    var formattedTargetTemperature: String {
        let measurement = Measurement(value: targetTemperature, unit: UnitTemperature.celsius)
        return Self.temperatureFormatter.string(from: measurement)
    }

    // MARK: - Status Update

    /// Update from a fetched status
    /// - Parameter status: Status from the fireplace service
    func update(from status: FireplaceStatus) {
        isOn = status.isOn
        currentTemperature = status.currentTemperature
        flameHeight = status.flameHeight
        flameHeightIsKnown = status.flameHeightIsKnown
        ecoModeActive = status.ecoModeActive
        if pendingWaveMode == status.ecoModeActive {
            pendingWaveMode = nil
        }
        hasError = status.hasError
        errorCode = status.errorCode
        signalStrength = status.signalStrengthPercentage
        lastStatusUpdate = Date()
        hasLiveStatus = true
        lastError = nil
    }

    /// Show the last known state from the app group until the first live status
    func restore(from snapshot: FireplaceSnapshot) {
        isOn = snapshot.isOn
        ecoModeActive = snapshot.ecoModeActive
        if let height = snapshot.lastSetFlameHeight {
            flameHeight = height
            flameHeightIsKnown = true
        }
        if let temperature = snapshot.currentTemperature {
            currentTemperature = temperature
        }
        burningSince = snapshot.burningSince
        lastStatusUpdate = snapshot.timestamp
    }

    /// Clear error state
    func clearError() {
        hasError = false
        errorCode = nil
    }
}

// MARK: - Connection State

extension Fireplace {
    /// Connection state enumeration
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)

        var isConnected: Bool {
            self == .connected
        }

        var displayName: String {
            switch self {
            case .disconnected:
                return String(localized: "Disconnected")
            case .connecting:
                return String(localized: "Connecting…")
            case .connected:
                return String(localized: "Connected")
            case .reconnecting:
                return String(localized: "Reconnecting…")
            case .failed(let reason):
                return String(localized: "Failed: \(reason)")
            }
        }

        var systemImage: String {
            switch self {
            case .disconnected:
                return "wifi.slash"
            case .connecting, .reconnecting:
                return "wifi"
            case .connected:
                return "wifi"
            case .failed:
                return "wifi.exclamationmark"
            }
        }
    }
}

// MARK: - Preview Support

extension Fireplace {
    /// Create a preview instance with mock data
    static var preview: Fireplace {
        let fireplace = Fireplace()
        fireplace.connectionState = .connected
        fireplace.bridgeIP = "192.168.1.100"
        fireplace.isOn = true
        fireplace.currentTemperature = 21.5
        fireplace.flameHeight = 60
        fireplace.flameHeightIsKnown = true
        fireplace.targetTemperature = 22.0
        fireplace.signalStrength = 75
        return fireplace
    }

    /// Create a preview instance in error state
    static var previewError: Fireplace {
        let fireplace = Fireplace()
        fireplace.connectionState = .connected
        fireplace.hasError = true
        fireplace.errorCode = .f01
        return fireplace
    }

    /// Create a preview instance in disconnected state
    static var previewDisconnected: Fireplace {
        let fireplace = Fireplace()
        fireplace.connectionState = .disconnected
        return fireplace
    }
}
