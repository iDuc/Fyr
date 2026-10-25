import Foundation

/// DRU / Honeywell BRDG-03EM01 holding registers, by register number.
/// Based on the Homey app (amstelzone/com.amstelzone.dru) and Fyr v1.
nonisolated enum DRURegister: UInt16, CaseIterable, Sendable {
    /// Action register (write-only command): see `DRUAction`.
    case action = 40200
    /// Requested flame height, 0-100 % (write-only: the bridge does not report it).
    case flameHeightTarget = 40201
    /// Status bit field, see `DRUStatusWord`.
    case status = 40203
    /// Fault code (0 = no fault).
    case errorCode = 40204
    /// Gateway RSSI (multiply by -0.5 for dBm).
    case rssiGateway = 40205
    /// Fireplace receiver RSSI (multiply by -0.5 for dBm).
    case rssiFireplace = 40206
    /// Room temperature in 0.1 °C.
    case temperature = 40207
    /// Wave interval in seconds (1-60).
    case waveInterval = 40220
    /// Thermostat setpoint in 0.1 °C (may not exist on all models).
    case thermostatSetpoint = 40250
}

/// How register numbers map to Modbus PDU addresses.
///
/// Fyr v1 and the Homey app send the register number itself (40203 -> 40203).
/// Standard Modbus tools use 0-based offsets from 40001 (40203 -> 202); modpoll's
/// `-r` flag is 1-based (40203 -> 203). Which one the bridge accepts is confirmed
/// by a read-only register dump, never by writing.
nonisolated enum DRUAddressing: String, CaseIterable, Sendable {
    /// PDU address = register number (40203 -> 40203). Default, as in Fyr v1.
    case registerNumber
    /// PDU address = register - 40001 (40203 -> 202). Standard Modbus.
    case zeroBasedOffset
    /// PDU address = register - 40000 (40203 -> 203).
    case oneBasedOffset

    static let `default` = DRUAddressing.registerNumber

    func pduAddress(for register: DRURegister) -> UInt16 {
        pduAddress(forRegisterNumber: register.rawValue)
    }

    func pduAddress(forRegisterNumber number: UInt16) -> UInt16 {
        switch self {
        case .registerNumber: number
        case .zeroBasedOffset: number - 40001
        case .oneBasedOffset: number - 40000
        }
    }
}

/// Values written to the action register 40200.
nonisolated enum DRUAction: UInt16, Sendable {
    /// Ignite / main burner on.
    case mainBurnerOn = 101
    /// Fireplace off.
    case fireplaceOff = 3
    /// Wave (eco) mode on.
    case waveModeOn = 105
    /// Wave (eco) mode off.
    case waveModeOff = 7
}

/// Decoded status register 40203.
///
/// Values observed on a real fireplace with Fyr v1:
/// - `0x3C00` (15360): off
/// - `0xB804` (47108): on
/// - `0xBA04` (47620): on, wave mode (bit 9, `0x0200`)
///
/// The other bits are not documented. Until a register dump in every state
/// confirms them, "on" keeps v1's rule (anything except 0 and 0x3C00).
nonisolated struct DRUStatusWord: Equatable, Sendable {
    let rawValue: UInt16

    static let offValue: UInt16 = 0x3C00
    static let waveModeBit: UInt16 = 0x0200

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    var isOn: Bool {
        rawValue != 0 && rawValue != Self.offValue
    }

    var waveModeActive: Bool {
        rawValue & Self.waveModeBit != 0
    }
}

/// Constants for DRU fireplace control.
nonisolated enum DRUConstants {
    static let minFlameHeight = 0
    static let maxFlameHeight = 100
    /// Shown when Fyr has never set a flame height.
    static let defaultFlameHeight = 50

    static let minTemperature = 5.0
    static let maxTemperature = 35.0
    /// Register value / factor = °C.
    static let temperatureScaleFactor = 10.0

    static let minWaveInterval = 1
    static let maxWaveInterval = 60

    /// Unit id of the fireplace behind the bridge.
    static let fireplaceUnitId: UInt8 = 2
    static let modbusPort: UInt16 = 502
}
