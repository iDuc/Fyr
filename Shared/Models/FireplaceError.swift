import Foundation

/// DRU fireplace error codes with user-friendly descriptions
nonisolated enum FireplaceErrorCode: String, CaseIterable, Sendable {
    case none = ""
    case f01 = "F01"    // Pilot flame failure
    case f02 = "F02"    // Main burner failure
    case f03 = "F03"    // Overheat protection
    case f04 = "F04"    // Communication error
    case f08 = "F08"    // General fault
    case unknown = "???"

    /// Create from raw register value
    /// - Parameter rawValue: Error code register value
    /// - Returns: Corresponding error code
    nonisolated static func from(rawValue: UInt16) -> FireplaceErrorCode? {
        guard rawValue != 0 else { return nil }

        switch rawValue {
        case 1: return .f01
        case 2: return .f02
        case 3: return .f03
        case 4: return .f04
        case 8: return .f08
        default: return .unknown
        }
    }

    /// User-friendly error title
    var friendlyTitle: String {
        switch self {
        case .none:
            return ""
        case .f01:
            return "Pilot Flame Issue"
        case .f02:
            return "Burner Issue"
        case .f03:
            return "Overheating Detected"
        case .f04:
            return "Communication Lost"
        case .f08:
            return "System Error"
        case .unknown:
            return "Unknown Error"
        }
    }

    /// User-friendly error description explaining what happened
    var friendlyDescription: String {
        switch self {
        case .none:
            return ""
        case .f01:
            return "The pilot flame could not ignite. Check that the gas supply is connected and try again."
        case .f02:
            return "The main burner failed to start properly. This may require service."
        case .f03:
            return "The fireplace shut down to prevent overheating. Allow it to cool down before restarting."
        case .f04:
            return "Lost connection to the fireplace controller. Check if the fireplace is powered on."
        case .f08:
            return "An unexpected error occurred. The fireplace has shut down for safety."
        case .unknown:
            return "An unrecognized error occurred."
        }
    }

    /// Instructions for how to resolve the error
    var resetInstructions: String {
        "To reset, press the up (∧) and down (∨) buttons on your remote control simultaneously."
    }

    /// System image name for displaying the error
    var systemImage: String {
        switch self {
        case .none:
            return "checkmark.circle"
        case .f01, .f02:
            return "flame.slash"
        case .f03:
            return "thermometer.high"
        case .f04:
            return "wifi.slash"
        case .f08, .unknown:
            return "exclamationmark.triangle"
        }
    }
}

/// Connection-related errors for the app
enum FireplaceConnectionError: Error, LocalizedError {
    case bridgeNotFound
    case connectionTimeout
    case networkUnavailable
    case invalidBridgeAddress
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .bridgeNotFound:
            return "Bridge Not Found"
        case .connectionTimeout:
            return "Connection Timed Out"
        case .networkUnavailable:
            return "Network Unavailable"
        case .invalidBridgeAddress:
            return "Invalid Bridge Address"
        case .authenticationFailed:
            return "Authentication Failed"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .bridgeNotFound:
            return "Make sure your Honeywell bridge is powered on and connected to the same WiFi network."
        case .connectionTimeout:
            return "The bridge is not responding. Check your network connection and try again."
        case .networkUnavailable:
            return "Connect to a WiFi network to control your fireplace."
        case .invalidBridgeAddress:
            return "The IP address format is invalid. Enter a valid IPv4 address (e.g., 192.168.1.100)."
        case .authenticationFailed:
            return "Could not authenticate with the bridge. Try reconnecting."
        }
    }
}
