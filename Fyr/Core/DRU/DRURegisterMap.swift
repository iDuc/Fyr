import Foundation

/// DRU Modbus register addresses
/// Based on working Homey app implementation (amstelzone/com.amstelzone.dru)
///
/// IMPORTANT: The DRU bridge expects RAW Modbus register numbers, NOT protocol addresses!
/// Working implementations pass 40200 directly, NOT 199 (40200 - 40001).
/// This is non-standard but confirmed working.
enum DRURegister: UInt16 {
    // Action Register (Write) - values: 101=main on, 3=main off, 102=second on, 4=second off
    case action = 40200             // Fireplace action control

    // Flame Height Control (Write) - 0-100 percentage
    case flameHeightTarget = 40201  // Requested flame height

    // Status Registers (Read)
    case status = 40203             // Fireplace status (bitfield)
    case errorCode = 40204          // Fault detail code
    case rssiGateway = 40205        // Gateway RSSI (multiply by -0.5 for dBm)
    case rssiFireplace = 40206      // Device RSSI (multiply by -0.5 for dBm)
    case temperature = 40207        // Room temperature (divide by 10 for °C)

    // Eco-Wave Settings
    case waveInterval = 40220       // Wave interval in seconds
    case wavePatternStart = 40421   // Wave pattern (10 registers)

    // Thermostat setpoint (may not exist on all models)
    case thermostatSetpoint = 40250
}

/// DRU Action register command values
/// Based on working Homey app (amstelzone/com.amstelzone.dru) and Node-RED implementation
/// Write these to register 40200 to control the fireplace
enum DRUActionCommand: UInt16, Sendable {
    /// Turn main burner on (ignite)
    case mainBurnerOn = 101

    /// Turn main burner off
    case mainBurnerOff = 3

    /// Turn secondary burner on
    case secondBurnerOn = 102

    /// Turn secondary burner off
    case secondBurnerOff = 4

    /// Activate eco-wave mode
    case waveModeOn = 105

    /// Deactivate eco-wave mode
    case waveModeOff = 7

    /// Pilot flame control (legacy)
    case pilotFlame = 100
}

/// Legacy DRUAction for backwards compatibility
/// Deprecated: Use DRUActionCommand instead
struct DRUAction: OptionSet, Sendable {
    let rawValue: UInt16

    /// Main burner on - maps to DRUActionCommand.mainBurnerOn
    nonisolated static let mainBurner = DRUAction(rawValue: 101)

    /// Fireplace off - maps to DRUActionCommand.mainBurnerOff
    nonisolated static let fireplaceOff = DRUAction(rawValue: 3)

    /// Wave mode ON - maps to DRUActionCommand.waveModeOn
    nonisolated static let waveModeOn = DRUAction(rawValue: 105)

    /// Wave mode OFF - maps to DRUActionCommand.waveModeOff
    nonisolated static let waveModeOff = DRUAction(rawValue: 7)
}

/// DRU Status register bit definitions
struct DRUStatus: OptionSet, Sendable {
    let rawValue: UInt16

    /// Fireplace is currently on
    static let isOn = DRUStatus(rawValue: 1 << 0)

    /// Main burner is active
    static let mainBurnerActive = DRUStatus(rawValue: 1 << 1)

    /// Second burner is active
    static let secondBurnerActive = DRUStatus(rawValue: 1 << 2)

    /// Wave mode is active
    static let waveModeActive = DRUStatus(rawValue: 1 << 3)

    /// Temperature control is active
    static let temperatureControlActive = DRUStatus(rawValue: 1 << 4)
}

/// Constants for DRU fireplace control
/// All properties are immutable constants, making this inherently thread-safe
/// Marked nonisolated for safe access from any actor context
enum DRUConstants: Sendable {
    /// Minimum flame height (percentage)
    nonisolated static let minFlameHeight: Int = 0

    /// Maximum flame height (percentage)
    /// Note: This is a percentage 0-100, NOT discrete levels
    nonisolated static let maxFlameHeight: Int = 100

    /// Minimum thermostat setpoint (°C)
    nonisolated static let minTemperature: Double = 5.0

    /// Maximum thermostat setpoint (°C)
    nonisolated static let maxTemperature: Double = 35.0

    /// Minimum wave interval (seconds)
    nonisolated static let minWaveInterval: Int = 1

    /// Maximum wave interval (seconds)
    nonisolated static let maxWaveInterval: Int = 60

    /// Temperature scale factor (register value / factor = °C)
    nonisolated static let temperatureScaleFactor: Double = 10.0

    /// Gateway slave ID (Honeywell BRDG-03EM01)
    nonisolated static let gatewaySlaveId: UInt8 = 207

    /// Fireplace slave ID
    nonisolated static let fireplaceSlaveId: UInt8 = 2

    /// Modbus TCP port
    nonisolated static let modbusPort: UInt16 = 502
}
