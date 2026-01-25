import Foundation

/// Modbus TCP protocol utilities
/// All methods are pure functions operating on value types, making this inherently thread-safe
enum ModbusProtocol: Sendable {
    /// Modbus function codes
    enum FunctionCode: UInt8 {
        case readHoldingRegisters = 0x03
        case readInputRegisters = 0x04
        case writeSingleRegister = 0x06
        case writeMultipleRegisters = 0x10
    }

    /// Build MBAP (Modbus Application Protocol) header
    /// - Parameters:
    ///   - transactionId: Unique transaction identifier
    ///   - pduLength: Length of the PDU (Protocol Data Unit)
    ///   - unitId: Slave/unit identifier
    /// - Returns: MBAP header as Data
    nonisolated static func buildMBAPHeader(transactionId: UInt16, pduLength: Int, unitId: UInt8) -> Data {
        var header = Data()
        header.append(contentsOf: transactionId.bigEndianBytes)     // Transaction ID (2 bytes)
        header.append(contentsOf: UInt16(0).bigEndianBytes)         // Protocol ID (2 bytes) - always 0 for Modbus
        header.append(contentsOf: UInt16(pduLength + 1).bigEndianBytes) // Length (2 bytes) - PDU + Unit ID
        header.append(unitId)                                        // Unit ID (1 byte)
        return header
    }

    /// Build Read Holding Registers request PDU
    /// - Parameters:
    ///   - startAddress: Starting register address
    ///   - quantity: Number of registers to read
    /// - Returns: PDU as Data
    nonisolated static func buildReadRequest(startAddress: UInt16, quantity: UInt16) -> Data {
        var pdu = Data()
        pdu.append(FunctionCode.readHoldingRegisters.rawValue)
        pdu.append(contentsOf: startAddress.bigEndianBytes)
        pdu.append(contentsOf: quantity.bigEndianBytes)
        return pdu
    }

    /// Build Write Single Register request PDU
    /// - Parameters:
    ///   - address: Register address
    ///   - value: Value to write
    /// - Returns: PDU as Data
    nonisolated static func buildWriteSingleRequest(address: UInt16, value: UInt16) -> Data {
        var pdu = Data()
        pdu.append(FunctionCode.writeSingleRegister.rawValue)
        pdu.append(contentsOf: address.bigEndianBytes)
        pdu.append(contentsOf: value.bigEndianBytes)
        return pdu
    }

    /// Build Write Multiple Registers request PDU
    /// - Parameters:
    ///   - startAddress: Starting register address
    ///   - values: Values to write
    /// - Returns: PDU as Data
    nonisolated static func buildWriteMultipleRequest(startAddress: UInt16, values: [UInt16]) -> Data {
        var pdu = Data()
        pdu.append(FunctionCode.writeMultipleRegisters.rawValue)
        pdu.append(contentsOf: startAddress.bigEndianBytes)
        pdu.append(contentsOf: UInt16(values.count).bigEndianBytes)
        pdu.append(UInt8(values.count * 2))  // Byte count

        for value in values {
            pdu.append(contentsOf: value.bigEndianBytes)
        }
        return pdu
    }

    /// Build Read Input Registers request PDU (Function Code 0x04)
    /// - Parameters:
    ///   - startAddress: Starting register address
    ///   - quantity: Number of registers to read
    /// - Returns: PDU as Data
    nonisolated static func buildReadInputRegistersRequest(startAddress: UInt16, quantity: UInt16) -> Data {
        var pdu = Data()
        pdu.append(FunctionCode.readInputRegisters.rawValue)
        pdu.append(contentsOf: startAddress.bigEndianBytes)
        pdu.append(contentsOf: quantity.bigEndianBytes)
        return pdu
    }

    /// Parse read response to extract register values
    /// - Parameters:
    ///   - data: Response data
    ///   - expectedRegisters: Expected number of registers
    /// - Returns: Array of register values
    /// - Throws: ModbusError if response is invalid
    nonisolated static func parseReadResponse(_ data: Data, expectedRegisters: Int) throws -> [UInt16] {
        // Minimum response size for error detection: MBAP header (7) + function code (1)
        guard data.count >= 8 else {
            throw ModbusError.invalidResponseSize(expected: 8, actual: data.count)
        }

        // Check for exception response FIRST (function code with high bit set)
        // Exception responses are only 9 bytes: MBAP header (7) + function code (1) + exception code (1)
        let functionCode = data[7]
        if functionCode & 0x80 != 0 {
            let exceptionCode = data.count > 8 ? data[8] : 0
            throw ModbusError.modbusException(code: exceptionCode)
        }

        // Now check full response size for success response
        let expectedSize = 9 + (expectedRegisters * 2)
        guard data.count >= expectedSize else {
            throw ModbusError.invalidResponseSize(expected: expectedSize, actual: data.count)
        }

        // Verify function code is correct
        guard functionCode == FunctionCode.readHoldingRegisters.rawValue else {
            throw ModbusError.unexpectedFunctionCode(expected: FunctionCode.readHoldingRegisters.rawValue, actual: functionCode)
        }

        // Verify byte count matches expected
        let byteCount = Int(data[8])
        let expectedByteCount = expectedRegisters * 2
        guard byteCount == expectedByteCount else {
            throw ModbusError.invalidByteCount(expected: expectedByteCount, actual: byteCount)
        }

        // Skip MBAP header (7 bytes) + function code (1 byte) + byte count (1 byte)
        let dataStart = 9
        var registers: [UInt16] = []

        for i in 0..<expectedRegisters {
            let offset = dataStart + (i * 2)
            let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            registers.append(value)
        }

        return registers
    }

    /// Parse write single register response to validate success
    /// - Parameters:
    ///   - data: Response data
    ///   - expectedAddress: Expected register address
    ///   - expectedValue: Expected value that was written
    /// - Throws: ModbusError if response is invalid or indicates failure
    nonisolated static func parseWriteSingleResponse(_ data: Data, expectedAddress: UInt16, expectedValue: UInt16) throws {
        // Minimum response size for error detection: MBAP header (7) + function code (1)
        guard data.count >= 8 else {
            throw ModbusError.invalidResponseSize(expected: 8, actual: data.count)
        }

        // Check for exception response FIRST (function code with high bit set)
        // Exception responses are only 9 bytes: MBAP header (7) + function code (1) + exception code (1)
        let functionCode = data[7]
        if functionCode & 0x80 != 0 {
            let exceptionCode = data.count > 8 ? data[8] : 0
            throw ModbusError.modbusException(code: exceptionCode)
        }

        // Write single register success response is 12 bytes:
        // MBAP header (7) + function code (1) + address (2) + value (2)
        let expectedSize = 12
        guard data.count >= expectedSize else {
            throw ModbusError.invalidResponseSize(expected: expectedSize, actual: data.count)
        }

        // Verify function code is correct
        guard functionCode == FunctionCode.writeSingleRegister.rawValue else {
            throw ModbusError.unexpectedFunctionCode(expected: FunctionCode.writeSingleRegister.rawValue, actual: functionCode)
        }

        // Verify echoed address matches
        let echoedAddress = UInt16(data[8]) << 8 | UInt16(data[9])
        guard echoedAddress == expectedAddress else {
            throw ModbusError.invalidResponse
        }

        // Verify echoed value matches
        let echoedValue = UInt16(data[10]) << 8 | UInt16(data[11])
        guard echoedValue == expectedValue else {
            throw ModbusError.invalidResponse
        }
    }

    /// Parse read response for input registers (FC 0x04)
    /// Uses same format as holding registers
    nonisolated static func parseInputRegisterResponse(_ data: Data, expectedRegisters: Int) throws -> [UInt16] {
        // Same parsing as holding registers, just different expected function code
        guard data.count >= 8 else {
            throw ModbusError.invalidResponseSize(expected: 8, actual: data.count)
        }

        // Check for exception response
        let functionCode = data[7]
        if functionCode & 0x80 != 0 {
            let exceptionCode = data.count > 8 ? data[8] : 0
            throw ModbusError.modbusException(code: exceptionCode)
        }

        let expectedSize = 9 + (expectedRegisters * 2)
        guard data.count >= expectedSize else {
            throw ModbusError.invalidResponseSize(expected: expectedSize, actual: data.count)
        }

        guard functionCode == FunctionCode.readInputRegisters.rawValue else {
            throw ModbusError.unexpectedFunctionCode(expected: FunctionCode.readInputRegisters.rawValue, actual: functionCode)
        }

        let byteCount = Int(data[8])
        let expectedByteCount = expectedRegisters * 2
        guard byteCount == expectedByteCount else {
            throw ModbusError.invalidByteCount(expected: expectedByteCount, actual: byteCount)
        }

        let dataStart = 9
        var registers: [UInt16] = []

        for i in 0..<expectedRegisters {
            let offset = dataStart + (i * 2)
            let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            registers.append(value)
        }

        return registers
    }
}

// MARK: - UInt16 Extension

extension UInt16 {
    /// Convert to big-endian byte array
    nonisolated var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}
