import Foundation

/// Current status snapshot from the fireplace
struct FireplaceStatus: Sendable, Equatable {
    /// Whether the fireplace is currently on
    let isOn: Bool

    /// Whether eco/wave mode is active
    let ecoModeActive: Bool

    /// Whether temperature control is active
    let temperatureControlActive: Bool

    /// Current error code, if any
    let errorCode: FireplaceErrorCode?

    /// Current flame height (0-15)
    let flameHeight: Int

    /// DFGT signal strength (RSSI)
    let signalStrength: Int

    /// Current measured temperature in °C
    let currentTemperature: Double

    /// Whether the fireplace has an active error
    var hasError: Bool {
        errorCode != nil
    }

    /// Signal strength as a percentage (0-100)
    var signalStrengthPercentage: Int {
        // RSSI typically ranges from -100 (weak) to 0 (strong)
        // Convert to percentage
        min(100, max(0, signalStrength + 100))
    }

    /// Flame height as a percentage (0-100)
    var flameHeightPercentage: Double {
        Double(flameHeight) / Double(DRUConstants.maxFlameHeight) * 100
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
            flameHeight: 10,
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
            flameHeight: 8,
            signalStrength: -50,
            currentTemperature: 22.0
        )
    }
}
