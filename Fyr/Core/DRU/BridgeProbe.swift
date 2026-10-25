import Foundation
import os

/// Checks whether a host is really a DRU bridge, with one harmless read.
///
/// An open TCP port 502 only means "some Modbus device" (solar inverters,
/// heat pumps and energy meters use it too). The probe connects, reads the
/// status register 40203 from the fireplace unit with function 0x03 (Read
/// Holding Registers) and accepts the host only if the value looks like a DRU
/// status word. It never writes. If the bridge rejects the address
/// (exception 0x02), the other addressing conventions are tried, also
/// read-only and with the bridge's 3 s pause between reads.
nonisolated struct BridgeProbe: Sendable {

    nonisolated enum Result: Sendable, Equatable {
        /// A DRU bridge: the status register answered with a plausible value.
        case bridge(addressing: DRUAddressing, status: UInt16)
        /// Answers Modbus, but not like a DRU bridge.
        case notADRUBridge
        /// No usable Modbus answer (no connection, silence, refused).
        case noAnswer(BridgeError)
    }

    typealias TransportFactory = @Sendable (BridgeEndpoint) -> any BridgeTransport

    var unitId: UInt8 = DRUConstants.fireplaceUnitId
    var client = ModbusTCPClient.Configuration()
    /// Pause between two reads on the same bridge (DRU limit: 3 s).
    var readInterval: Duration = .seconds(3)
    var makeTransport: TransportFactory = { NWBridgeTransport(endpoint: $0) }

    private static let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "BridgeProbe")

    /// Whether a status register value looks like a DRU bridge.
    ///
    /// Every status word seen on a real fireplace (`0x3C00` off, `0xB804` on,
    /// `0xBA04` on + wave) has bits 11-13 (`0x3800`) set; 0 and 0xFFFF (typical
    /// "nothing here" values) do not match, and neither do most values of an
    /// unrelated device. Revisit with the register dump.
    static func isPlausibleStatus(_ value: UInt16) -> Bool {
        value != 0xFFFF && value & plausibleStatusMask == plausibleStatusMask
    }

    static let plausibleStatusMask: UInt16 = 0x3800

    /// Probe one host. Opens one connection and closes it before returning.
    func probe(_ endpoint: BridgeEndpoint, preferred: DRUAddressing = .default) async -> Result {
        let client = ModbusTCPClient(unitId: unitId, configuration: self.client, makeTransport: { [makeTransport] in
            makeTransport(endpoint)
        })
        let result = await read(with: client, from: endpoint, preferred: preferred)
        await client.disconnect()
        return result
    }

    private func read(with client: ModbusTCPClient, from endpoint: BridgeEndpoint, preferred: DRUAddressing) async -> Result {
        let order = [preferred] + DRUAddressing.allCases.filter { $0 != preferred }
        for (index, addressing) in order.enumerated() {
            if index > 0 {
                do {
                    try await Task.sleep(for: readInterval)
                } catch {
                    return .noAnswer(.cancelled)
                }
            }
            do {
                let value = try await client.readHoldingRegisters(address: addressing.pduAddress(for: .status), count: 1)[0]
                guard Self.isPlausibleStatus(value) else {
                    Self.logger.info("\(endpoint.description): status 0x\(String(value, radix: 16)) is not a DRU status word")
                    return .notADRUBridge
                }
                return .bridge(addressing: addressing, status: value)
            } catch ModbusError.exception(code: 0x02) {
                // Illegal data address: try the next addressing convention.
                continue
            } catch let error as ModbusError {
                switch error {
                case .exception, .invalidFrame, .unexpectedFunctionCode:
                    // It speaks Modbus, but not like the fireplace unit of a DRU bridge.
                    return .notADRUBridge
                default:
                    return .noAnswer(BridgeError(error))
                }
            } catch {
                return .noAnswer(.cancelled)
            }
        }
        return .notADRUBridge
    }
}
