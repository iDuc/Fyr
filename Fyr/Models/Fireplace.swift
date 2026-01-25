import Foundation
import Observation

/// Main observable model for the fireplace
/// Uses iOS 17+ Observation framework for reactive UI updates
@Observable
final class Fireplace {

    // MARK: - Connection State

    /// Current connection state
    var connectionState: ConnectionState = .disconnected

    /// Last connection error, if any
    var connectionError: Error?

    /// Configured bridge IP address
    var bridgeIP: String?

    // MARK: - Current Status (from polling)

    /// Whether the fireplace is currently on
    var isOn: Bool = false

    /// Current measured temperature in °C
    var currentTemperature: Double = 0

    /// Current flame height (0-15)
    var flameHeight: Int = 0

    /// Whether eco/wave mode is active
    var ecoModeActive: Bool = false

    /// Whether there's an active error
    var hasError: Bool = false

    /// Current error code, if any
    var errorCode: FireplaceErrorCode?

    /// Signal strength percentage (0-100)
    var signalStrength: Int = 0

    // MARK: - Target Values (user-controlled)

    /// Target thermostat temperature
    var targetTemperature: Double = 21.0

    /// Target flame height
    var targetFlameHeight: Int = 8

    /// Whether eco mode should be enabled
    var targetEcoMode: Bool = false

    // MARK: - UI State

    /// Whether a command is currently being processed
    var isProcessing: Bool = false

    /// Time remaining until flame height can be changed again (seconds)
    var flameHeightCooldown: TimeInterval = 0

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
        ecoModeActive = status.ecoModeActive
        hasError = status.hasError
        errorCode = status.errorCode
        signalStrength = status.signalStrengthPercentage
        lastStatusUpdate = Date()
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
                return "Disconnected"
            case .connecting:
                return "Connecting..."
            case .connected:
                return "Connected"
            case .reconnecting:
                return "Reconnecting..."
            case .failed(let reason):
                return "Failed: \(reason)"
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
        fireplace.flameHeight = 10
        fireplace.targetTemperature = 22.0
        fireplace.targetFlameHeight = 10
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
