import Foundation

/// Errors that can occur during Modbus communication
enum ModbusError: Error, LocalizedError {
    case connectionFailed(String)
    case connectionClosed
    case timeout
    case invalidResponse
    case invalidResponseSize(expected: Int, actual: Int)
    case unexpectedFunctionCode(expected: UInt8, actual: UInt8)
    case invalidByteCount(expected: Int, actual: Int)
    case modbusException(code: UInt8)
    case notConnected
    case sendFailed(Error)
    case receiveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionClosed:
            return "Connection closed by remote"
        case .timeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response received"
        case .invalidResponseSize(let expected, let actual):
            return "Invalid response size: expected \(expected) bytes, got \(actual)"
        case .unexpectedFunctionCode(let expected, let actual):
            return "Unexpected function code: expected 0x\(String(format: "%02X", expected)), got 0x\(String(format: "%02X", actual))"
        case .invalidByteCount(let expected, let actual):
            return "Invalid byte count: expected \(expected), got \(actual)"
        case .modbusException(let code):
            let description = switch code {
            case 0x01: "Illegal Function"
            case 0x02: "Illegal Data Address"
            case 0x03: "Illegal Data Value"
            case 0x04: "Server Device Failure"
            case 0x05: "Acknowledge"
            case 0x06: "Server Device Busy"
            default: "Unknown"
            }
            return "Modbus exception: \(description) (0x\(String(format: "%02X", code)))"
        case .notConnected:
            return "Not connected to bridge"
        case .sendFailed(let error):
            return "Send failed: \(error.localizedDescription)"
        case .receiveFailed(let error):
            return "Receive failed: \(error.localizedDescription)"
        }
    }
}
