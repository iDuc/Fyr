import Foundation

/// User-facing errors from the fireplace service.
nonisolated enum BridgeError: Error, Equatable, Sendable {
    /// No bridge address configured yet.
    case notConfigured
    /// Wi-Fi is off or Local Network access is not allowed for Fyr.
    case networkUnavailable
    /// The bridge cannot be reached (offline, wrong address, other network).
    case unreachable
    /// The bridge refused the connection. It accepts one connection at a time,
    /// so another app (usually the DRU app) is probably connected.
    case bridgeBusy
    /// The bridge is connected but does not answer.
    case noResponse
    /// The connection dropped during a request.
    case connectionLost
    /// The fireplace answered "busy"; try again shortly.
    case deviceBusy
    /// The bridge rejected the request with a Modbus exception.
    case rejected(exceptionCode: UInt8)
    /// The bridge sent something that is not valid Modbus.
    case protocolError(String)
    /// The bridge's rate limit does not allow this yet.
    case rateLimited(retryAfter: Duration)
    /// Lighting the fire from this place is not allowed (see `IgnitionAuthorization`).
    case ignitionNotAuthorized
    /// The request was cancelled (e.g. the app went to the background).
    case cancelled

    init(_ error: ModbusError) {
        switch error {
        case .connectFailed(.refused): self = .bridgeBusy
        case .connectFailed(.networkDown): self = .networkUnavailable
        case .connectFailed(.unreachable), .connectFailed(.timedOut), .connectFailed(.other): self = .unreachable
        case .connectionClosed, .notConnected, .sendFailed, .receiveFailed: self = .connectionLost
        case .timeout: self = .noResponse
        case .exception(let code) where code == 0x05 || code == 0x06: self = .deviceBusy
        case .exception(let code): self = .rejected(exceptionCode: code)
        case .invalidFrame(let reason): self = .protocolError(reason)
        case .unexpectedFunctionCode: self = .protocolError(error.description)
        }
    }

    /// Whether this is about reaching the bridge, as opposed to a rejected command.
    var isConnectionProblem: Bool {
        switch self {
        case .networkUnavailable, .unreachable, .bridgeBusy, .noResponse, .connectionLost:
            true
        default:
            false
        }
    }
}

extension BridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "No fireplace set up")
        case .networkUnavailable:
            String(localized: "No local network")
        case .unreachable:
            String(localized: "Bridge not reachable")
        case .bridgeBusy:
            String(localized: "Bridge in use")
        case .noResponse:
            String(localized: "Bridge not responding")
        case .connectionLost:
            String(localized: "Connection lost")
        case .deviceBusy:
            String(localized: "Fireplace busy")
        case .rejected(let code):
            String(localized: "Command rejected (code \(Int(code)))")
        case .protocolError:
            String(localized: "Unexpected answer from bridge")
        case .rateLimited(let retryAfter):
            String(localized: "Please wait \(Int(retryAfter.components.seconds) + 1) seconds")
        case .ignitionNotAuthorized:
            String(localized: "Lighting the fire is not allowed from here")
        case .cancelled:
            String(localized: "Cancelled")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            String(localized: "Open Fyr and set up your fireplace.")
        case .networkUnavailable:
            String(localized: "Connect to your home Wi-Fi and allow Local Network access for Fyr in Settings.")
        case .unreachable:
            String(localized: "Check that you are on your home Wi-Fi and that the bridge is powered on.")
        case .bridgeBusy:
            String(localized: "The bridge allows one app at a time. Close the DRU app, or wait a minute and try again.")
        case .noResponse, .connectionLost, .deviceBusy, .protocolError:
            String(localized: "Try again in a few seconds.")
        case .rejected:
            String(localized: "Your fireplace may not support this function.")
        case .rateLimited, .cancelled:
            nil
        case .ignitionNotAuthorized:
            String(localized: "Open Fyr to light the fire.")
        }
    }
}
