import Foundation
import WidgetKit

/// Persistent storage for app settings using UserDefaults
/// Uses App Groups for sharing with widgets
@MainActor
@Observable
final class SettingsStore {

    // MARK: - Singleton

    static let shared = SettingsStore()

    // MARK: - Nonisolated Accessors (for use in App Intents)

    /// Access bridge IP from any context (reads directly from UserDefaults)
    nonisolated static var bridgeIPValue: String? {
        let defaults = UserDefaults(suiteName: "group.com.fyr.app") ?? .standard
        return defaults.string(forKey: "bridgeIP")
    }

    // MARK: - Keys

    private nonisolated enum Keys {
        static let bridgeIP = "bridgeIP"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastKnownStatus = "lastKnownStatus"
        static let targetTemperature = "targetTemperature"
        static let targetFlameHeight = "targetFlameHeight"
        static let modbusSlaveId = "modbusSlaveId"
        static let modbusAddressOffset = "modbusAddressOffset"
    }

    // MARK: - UserDefaults

    private let defaults: UserDefaults

    // MARK: - Properties

    /// Configured bridge IP address
    var bridgeIP: String? {
        didSet {
            defaults.set(bridgeIP, forKey: Keys.bridgeIP)
        }
    }

    /// Whether the user has completed onboarding
    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// Last known target temperature
    var targetTemperature: Double {
        didSet {
            defaults.set(targetTemperature, forKey: Keys.targetTemperature)
        }
    }

    /// Last known target flame height
    var targetFlameHeight: Int {
        didSet {
            defaults.set(targetFlameHeight, forKey: Keys.targetFlameHeight)
        }
    }

    // MARK: - Modbus Configuration

    /// Modbus slave/unit ID for the fireplace (discovered via diagnostics)
    /// Default is 2, but can vary by installation (1, 2, 3, or 207)
    var modbusSlaveId: UInt8 {
        didSet {
            defaults.set(Int(modbusSlaveId), forKey: Keys.modbusSlaveId)
        }
    }

    /// Modbus address offset adjustment
    /// 0 = Standard (40001 = address 0), 1 = Alternative (40000 = address 0)
    var modbusAddressOffset: Int {
        didSet {
            defaults.set(modbusAddressOffset, forKey: Keys.modbusAddressOffset)
        }
    }

    // MARK: - Nonisolated Modbus Accessors (for use in actors)

    /// Access slave ID from any context
    nonisolated static var modbusSlaveIdValue: UInt8 {
        let defaults = UserDefaults(suiteName: "group.com.fyr.app") ?? .standard
        let value = defaults.integer(forKey: Keys.modbusSlaveId)
        return value == 0 ? 2 : UInt8(value)
    }

    /// Access address offset from any context
    nonisolated static var modbusAddressOffsetValue: Int {
        let defaults = UserDefaults(suiteName: "group.com.fyr.app") ?? .standard
        return defaults.integer(forKey: Keys.modbusAddressOffset)
    }

    // MARK: - Initialization

    private init() {
        // Try to use App Group for widget sharing, fall back to standard
        if let groupDefaults = UserDefaults(suiteName: "group.com.fyr.app") {
            defaults = groupDefaults
        } else {
            defaults = .standard
        }

        // Load persisted values
        bridgeIP = defaults.string(forKey: Keys.bridgeIP)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        targetTemperature = defaults.double(forKey: Keys.targetTemperature)
        targetFlameHeight = defaults.integer(forKey: Keys.targetFlameHeight)

        // Load Modbus configuration
        let savedSlaveId = defaults.integer(forKey: Keys.modbusSlaveId)
        modbusSlaveId = savedSlaveId == 0 ? 2 : UInt8(savedSlaveId)
        modbusAddressOffset = defaults.integer(forKey: Keys.modbusAddressOffset)

        // Set defaults for unset values
        if targetTemperature == 0 {
            targetTemperature = 21.0
        }
        if targetFlameHeight == 0 {
            targetFlameHeight = 8
        }
    }

    // MARK: - Status Caching for Widgets

    /// Save the last known status for widget display
    /// - Parameter status: Current fireplace status
    func cacheStatus(_ status: FireplaceStatus) {
        let data: [String: Any] = [
            "isOn": status.isOn,
            "ecoModeActive": status.ecoModeActive,
            "flameHeight": status.flameHeight,
            "currentTemperature": status.currentTemperature,
            "timestamp": Date().timeIntervalSince1970
        ]
        defaults.set(data, forKey: Keys.lastKnownStatus)

        // Trigger widget refresh
        WidgetCenter.shared.reloadTimelines(ofKind: "FyrWidget")
    }

    /// Load cached status for widget display
    /// - Returns: Cached status or nil if not available
    func loadCachedStatus() -> CachedFireplaceStatus? {
        guard let data = defaults.dictionary(forKey: Keys.lastKnownStatus) else {
            return nil
        }

        return CachedFireplaceStatus(
            isOn: data["isOn"] as? Bool ?? false,
            ecoModeActive: data["ecoModeActive"] as? Bool ?? false,
            flameHeight: data["flameHeight"] as? Int ?? 0,
            currentTemperature: data["currentTemperature"] as? Double ?? 0,
            timestamp: Date(timeIntervalSince1970: data["timestamp"] as? TimeInterval ?? 0)
        )
    }

    // MARK: - Reset

    /// Clear all stored settings
    func reset() {
        bridgeIP = nil
        hasCompletedOnboarding = false
        targetTemperature = 21.0
        targetFlameHeight = 8
        modbusSlaveId = 2
        modbusAddressOffset = 0
        defaults.removeObject(forKey: Keys.lastKnownStatus)
    }
}

// MARK: - Cached Status

/// Simplified status structure for widget caching
struct CachedFireplaceStatus {
    let isOn: Bool
    let ecoModeActive: Bool
    let flameHeight: Int
    let currentTemperature: Double
    let timestamp: Date

    /// Whether the cached data is still considered fresh (within 5 minutes)
    var isFresh: Bool {
        Date().timeIntervalSince(timestamp) < 300
    }
}
