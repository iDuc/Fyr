import Foundation

/// Modbus TCP framing (MBAP header + PDU).
/// Pure functions on byte arrays, so they are trivially testable with golden bytes.
nonisolated enum ModbusProtocol {

    /// Function codes used by Fyr. Fyr only ever reads holding registers and
    /// writes single registers.
    enum FunctionCode: UInt8, Sendable {
        case readHoldingRegisters = 0x03
        case writeSingleRegister = 0x06
    }

    /// MBAP header length: transaction id (2), protocol id (2), length (2), unit id (1).
    static let headerLength = 7

    /// Largest allowed value of the MBAP length field (unit id + 253-byte PDU).
    static let maxLengthField = 254

    /// Maximum registers in a single Read Holding Registers request.
    static let maxReadCount: UInt16 = 125

    /// Parsed MBAP header.
    struct Header: Equatable, Sendable {
        let transactionId: UInt16
        let protocolId: UInt16
        /// Number of bytes following the length field (unit id + PDU).
        let length: UInt16
        let unitId: UInt8

        /// Number of PDU bytes that follow the header.
        var pduLength: Int { Int(length) - 1 }
    }

    // MARK: - Requests

    /// Build a complete ADU: MBAP header followed by the PDU.
    static func frame(transactionId: UInt16, unitId: UInt8, pdu: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(headerLength + pdu.count)
        bytes += transactionId.bigEndianBytes
        bytes += UInt16(0).bigEndianBytes                  // protocol id: always 0 for Modbus
        bytes += UInt16(pdu.count + 1).bigEndianBytes      // length: unit id + PDU
        bytes.append(unitId)
        bytes += pdu
        return bytes
    }

    static func readHoldingRegistersPDU(address: UInt16, count: UInt16) -> [UInt8] {
        [FunctionCode.readHoldingRegisters.rawValue] + address.bigEndianBytes + count.bigEndianBytes
    }

    static func writeSingleRegisterPDU(address: UInt16, value: UInt16) -> [UInt8] {
        [FunctionCode.writeSingleRegister.rawValue] + address.bigEndianBytes + value.bigEndianBytes
    }

    // MARK: - Responses

    /// Parse and validate the 7-byte MBAP header of a response.
    static func parseHeader(_ bytes: [UInt8]) throws(ModbusError) -> Header {
        guard bytes.count == headerLength else {
            throw .invalidFrame("header is \(bytes.count) bytes, expected \(headerLength)")
        }
        let header = Header(
            transactionId: UInt16(bigEndianBytes: bytes[0], bytes[1]),
            protocolId: UInt16(bigEndianBytes: bytes[2], bytes[3]),
            length: UInt16(bigEndianBytes: bytes[4], bytes[5]),
            unitId: bytes[6]
        )
        guard header.protocolId == 0 else {
            throw .invalidFrame("protocol id \(header.protocolId), expected 0")
        }
        // Smallest valid PDU is an exception response: function code + exception code.
        guard header.length >= 3, header.length <= maxLengthField else {
            throw .invalidFrame("length field \(header.length) out of range")
        }
        return header
    }

    /// Parse a Read Holding Registers response PDU.
    static func parseReadHoldingRegisters(pdu: [UInt8], expectedCount: Int) throws(ModbusError) -> [UInt16] {
        try checkForException(pdu, expected: .readHoldingRegisters)
        guard pdu.count >= 2 else { throw .invalidFrame("read response too short") }
        let byteCount = Int(pdu[1])
        guard byteCount == expectedCount * 2, pdu.count == 2 + byteCount else {
            throw .invalidFrame("read response has \(byteCount) data bytes, expected \(expectedCount * 2)")
        }
        return stride(from: 2, to: 2 + byteCount, by: 2).map { UInt16(bigEndianBytes: pdu[$0], pdu[$0 + 1]) }
    }

    /// Validate a Write Single Register response PDU (the request is echoed back).
    static func parseWriteSingleRegister(pdu: [UInt8], address: UInt16, value: UInt16) throws(ModbusError) {
        try checkForException(pdu, expected: .writeSingleRegister)
        guard pdu == writeSingleRegisterPDU(address: address, value: value) else {
            throw .invalidFrame("write response does not echo the request")
        }
    }

    private static func checkForException(_ pdu: [UInt8], expected: FunctionCode) throws(ModbusError) {
        guard let functionCode = pdu.first else { throw .invalidFrame("empty PDU") }
        if functionCode == expected.rawValue | 0x80 {
            throw .exception(code: pdu.count > 1 ? pdu[1] : 0)
        }
        guard functionCode == expected.rawValue else {
            throw .unexpectedFunctionCode(expected: expected.rawValue, actual: functionCode)
        }
    }
}

// MARK: - UInt16 helpers

nonisolated extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 8), UInt8(self & 0xFF)]
    }

    init(bigEndianBytes high: UInt8, _ low: UInt8) {
        self = UInt16(high) << 8 | UInt16(low)
    }
}
