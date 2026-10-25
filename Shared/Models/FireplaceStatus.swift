import Foundation

/// Current status snapshot from the fireplace
nonisolated struct FireplaceStatus: Sendable, Equatable {
    /// Whether the fireplace is currently on
    let isOn: Bool

    /// Whether eco/wave mode is active
    let ecoModeActive: Bool

    /// Whether temperature control is active (not reported by the bridge)
    let temperatureControlActive: Bool

    /// Current error code, if any
    let errorCode: FireplaceErrorCode?

    /// Last flame height set by Fyr (0-100 %). Register 40201 is write-only, so
    /// this is not measured; see `flameHeightIsKnown`.
    let flameHeight: Int

    /// Whether Fyr has ever set a flame height (otherwise `flameHeight` is a default).
    let flameHeightIsKnown: Bool

    /// DFGT signal strength (RSSI, dBm)
    let signalStrength: Int

    /// Current measured temperature in °C
    let currentTemperature: Double

    /// Raw status register 40203, for diagnostics.
    let rawStatus: UInt16

    /// Raw error code register 40204.
    let rawErrorCode: UInt16

    init(
        isOn: Bool,
        ecoModeActive: Bool,
        temperatureControlActive: Bool,
        errorCode: FireplaceErrorCode?,
        flameHeight: Int,
        flameHeightIsKnown: Bool = true,
        signalStrength: Int,
        currentTemperature: Double,
        rawStatus: UInt16 = 0,
        rawErrorCode: UInt16 = 0
    ) {
        self.isOn = isOn
        self.ecoModeActive = ecoModeActive
        self.temperatureControlActive = temperatureControlActive
        self.errorCode = errorCode
        self.flameHeight = flameHeight
        self.flameHeightIsKnown = flameHeightIsKnown
        self.signalStrength = signalStrength
        self.currentTemperature = currentTemperature
        self.rawStatus = rawStatus
        self.rawErrorCode = rawErrorCode
    }

    /// Decode the status registers 40203-40207.
    init(registers: [DRURegister: UInt16], lastSetFlameHeight: Int?) {
        let statusWord = DRUStatusWord(rawValue: registers[.status] ?? 0)
        let rawError = registers[.errorCode] ?? 0
        self.init(
            isOn: statusWord.isOn,
            ecoModeActive: statusWord.waveModeActive,
            temperatureControlActive: false,
            errorCode: FireplaceErrorCode.from(rawValue: rawError),
            flameHeight: lastSetFlameHeight ?? DRUConstants.defaultFlameHeight,
            flameHeightIsKnown: lastSetFlameHeight != nil,
            // RSSI register: multiply by -0.5 for dBm
            signalStrength: Int(Double(registers[.rssiFireplace] ?? 0) * -0.5),
            currentTemperature: Double(registers[.temperature] ?? 0) / DRUConstants.temperatureScaleFactor,
            rawStatus: statusWord.rawValue,
            rawErrorCode: rawError
        )
    }

    /// Whether the fireplace has an active error
    var hasError: Bool {
        errorCode != nil
    }

    /// Signal strength as a percentage (0-100)
    var signalStrengthPercentage: Int {
        // RSSI typically ranges from -100 (weak) to 0 (strong)
        min(100, max(0, signalStrength + 100))
    }
}

// MARK: - Mock Data for Previews

extension FireplaceStatus {
    /// Mock status for SwiftUI previews - fireplace on
    static var previewOn: FireplaceStatus {
        FireplaceStatus(
            isOn: true,
            ecoModeActive: false,
            temperatureControlActive: true,
            errorCode: nil,
            flameHeight: 60,
            signalStrength: -45,
            currentTemperature: 21.5
        )
    }

    /// Mock status for SwiftUI previews - fireplace off
    static var previewOff: FireplaceStatus {
        FireplaceStatus(
            isOn: false,
            ecoModeActive: false,
            temperatureControlActive: false,
            errorCode: nil,
            flameHeight: 0,
            signalStrength: -45,
            currentTemperature: 18.0
        )
    }

    /// Mock status for SwiftUI previews - with error
    static var previewError: FireplaceStatus {
        FireplaceStatus(
            isOn: false,
            ecoModeActive: false,
            temperatureControlActive: false,
            errorCode: .f01,
            flameHeight: 0,
            signalStrength: -45,
            currentTemperature: 19.0
        )
    }

    /// Mock status for SwiftUI previews - eco mode active
    static var previewEcoMode: FireplaceStatus {
        FireplaceStatus(
            isOn: true,
            ecoModeActive: true,
            temperatureControlActive: true,
            errorCode: nil,
            flameHeight: 50,
            signalStrength: -50,
            currentTemperature: 22.0
        )
    }
}
