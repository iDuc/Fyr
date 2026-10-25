import Foundation

/// Low-level errors from the Modbus TCP client. The service layer maps these to
/// user-facing `BridgeError`s.
nonisolated enum ModbusError: Error, Equatable, Sendable {
    /// Why opening the TCP connection failed.
    enum ConnectFailure: Equatable, Sendable {
        /// The bridge actively refused: its single connection slot is probably taken.
        case refused
        /// No route to the bridge (wrong IP, bridge offline, other network).
        case unreachable
        /// Wi-Fi is off or Local Network access is not allowed.
        case networkDown
        /// No answer to the TCP handshake within the connect timeout.
        case timedOut
        case other(String)
    }

    case connectFailed(ConnectFailure)
    /// The bridge closed the connection, or it was closed locally.
    case connectionClosed
    case notConnected
    /// The bridge accepted the request but did not answer in time.
    case timeout
    /// The response was not a well-formed Modbus TCP frame.
    case invalidFrame(String)
    case unexpectedFunctionCode(expected: UInt8, actual: UInt8)
    /// The bridge answered with a Modbus exception response.
    case exception(code: UInt8)
    case sendFailed(String)
    case receiveFailed(String)

    /// Exception codes that mean "try again shortly" (Acknowledge, Server Device Busy).
    var isDeviceBusy: Bool {
        if case .exception(let code) = self { return code == 0x05 || code == 0x06 }
        return false
    }

    /// Whether the connection must be considered unusable after this error.
    /// Exceptions and function-code mismatches arrive in a complete, well-framed
    /// response, so the stream is still in sync.
    var invalidatesConnection: Bool {
        switch self {
        case .exception, .unexpectedFunctionCode:
            return false
        default:
            return true
        }
    }
}

extension ModbusError: CustomStringConvertible {
    var description: String {
        switch self {
        case .connectFailed(let failure): "connect failed: \(failure)"
        case .connectionClosed: "connection closed"
        case .notConnected: "not connected"
        case .timeout: "request timed out"
        case .invalidFrame(let reason): "invalid frame: \(reason)"
        case .unexpectedFunctionCode(let expected, let actual):
            "unexpected function code 0x\(String(actual, radix: 16)) (expected 0x\(String(expected, radix: 16)))"
        case .exception(let code): "Modbus exception 0x\(String(code, radix: 16))"
        case .sendFailed(let reason): "send failed: \(reason)"
        case .receiveFailed(let reason): "receive failed: \(reason)"
        }
    }
}
