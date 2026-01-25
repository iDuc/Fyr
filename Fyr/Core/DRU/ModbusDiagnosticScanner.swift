import Foundation
import os

/// Result of a single diagnostic test
struct DiagnosticTestResult: Sendable, Identifiable {
    let id = UUID()
    let slaveId: UInt8
    let addressOffset: Int
    let success: Bool
    let registerValue: UInt16?
    let errorMessage: String?

    var addressModeName: String {
        addressOffset == 0 ? "Standard" : "Alternative"
    }
}

/// Overall result of the diagnostic scan
struct DiagnosticScanResult: Sendable {
    let results: [DiagnosticTestResult]
    let workingConfiguration: (slaveId: UInt8, addressOffset: Int)?
    let errorMessage: String?

    var hasWorkingConfig: Bool {
        workingConfiguration != nil
    }
}

/// Progress update during scanning
struct ScanProgress: Sendable {
    let currentTest: Int
    let totalTests: Int
    let currentSlaveId: UInt8
    let currentAddressOffset: Int
    let statusMessage: String

    var percentage: Double {
        Double(currentTest) / Double(totalTests)
    }
}

/// Actor that scans for the correct Modbus configuration
/// Tests multiple slave IDs and address conventions to find what works
actor ModbusDiagnosticScanner {

    private let logger = Logger(subsystem: "com.fyr.app", category: "DiagnosticScanner")

    /// Slave IDs to test (common values for DRU/Honeywell bridges)
    private let slaveIdsToTest: [UInt8] = [1, 2, 3, 207]

    /// Address offsets to test
    /// 0 = Raw register number (40203 as-is) - WORKING per Homey app
    /// 1 = Standard Modbus conversion (40203 - 40001 = 202)
    private let addressOffsetsToTest: [Int] = [0, 1]

    /// Base address for status register
    /// Using RAW register number (40203) as working implementations do
    private let statusRegisterBase: UInt16 = 40203

    /// Run a comprehensive diagnostic scan
    /// - Parameters:
    ///   - host: Bridge IP address
    ///   - port: Modbus port (default 502)
    ///   - progressHandler: Called with progress updates
    /// - Returns: Scan results including any working configuration found
    func runScan(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (ScanProgress) -> Void
    ) async -> DiagnosticScanResult {
        logger.info("Starting diagnostic scan for \(host):\(port)")

        var results: [DiagnosticTestResult] = []
        var workingConfig: (slaveId: UInt8, addressOffset: Int)?

        let totalTests = slaveIdsToTest.count * addressOffsetsToTest.count
        var currentTest = 0

        for slaveId in slaveIdsToTest {
            for addressOffset in addressOffsetsToTest {
                currentTest += 1

                let progress = ScanProgress(
                    currentTest: currentTest,
                    totalTests: totalTests,
                    currentSlaveId: slaveId,
                    currentAddressOffset: addressOffset,
                    statusMessage: "Testing Slave ID \(slaveId), \(addressOffset == 0 ? "Standard" : "Alternative") addresses"
                )
                progressHandler(progress)

                logger.debug("Testing slave \(slaveId), offset \(addressOffset)")

                let result = await testConfiguration(
                    host: host,
                    port: port,
                    slaveId: slaveId,
                    addressOffset: addressOffset
                )
                results.append(result)

                if result.success && workingConfig == nil {
                    workingConfig = (slaveId, addressOffset)
                    logger.info("Found working configuration: slave \(slaveId), offset \(addressOffset)")
                }

                // Small delay between tests to not overwhelm the bridge
                try? await Task.sleep(for: .milliseconds(300))
            }
        }

        let scanResult = DiagnosticScanResult(
            results: results,
            workingConfiguration: workingConfig,
            errorMessage: workingConfig == nil ? "No working configuration found. Please verify the bridge IP address and network connection." : nil
        )

        logger.info("Scan complete. Working config found: \(workingConfig != nil)")
        return scanResult
    }

    /// Test a specific configuration
    private func testConfiguration(
        host: String,
        port: UInt16,
        slaveId: UInt8,
        addressOffset: Int
    ) async -> DiagnosticTestResult {
        // Create a temporary client for this test
        let client = ModbusTCPClient(
            host: host,
            port: port,
            slaveId: slaveId,
            timeout: 3.0  // Shorter timeout for scanning
        )

        do {
            // Try to connect
            try await client.connect()

            // Calculate the address with offset
            let address = statusRegisterBase + UInt16(addressOffset)

            // Try to read the status register
            let values = try await client.readHoldingRegisters(startAddress: address, quantity: 1)

            // Disconnect
            await client.disconnect()

            if let value = values.first {
                logger.debug("Success: slave \(slaveId), offset \(addressOffset), value \(value)")
                return DiagnosticTestResult(
                    slaveId: slaveId,
                    addressOffset: addressOffset,
                    success: true,
                    registerValue: value,
                    errorMessage: nil
                )
            } else {
                return DiagnosticTestResult(
                    slaveId: slaveId,
                    addressOffset: addressOffset,
                    success: false,
                    registerValue: nil,
                    errorMessage: "No data returned"
                )
            }
        } catch {
            await client.disconnect()

            logger.debug("Failed: slave \(slaveId), offset \(addressOffset), error: \(error.localizedDescription)")
            return DiagnosticTestResult(
                slaveId: slaveId,
                addressOffset: addressOffset,
                success: false,
                registerValue: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Quick test of a specific configuration (for verifying saved settings)
    func quickTest(
        host: String,
        port: UInt16 = 502,
        slaveId: UInt8,
        addressOffset: Int
    ) async -> Bool {
        let result = await testConfiguration(
            host: host,
            port: port,
            slaveId: slaveId,
            addressOffset: addressOffset
        )
        return result.success
    }

    // MARK: - Deep Scan

    /// Result of a deep address scan
    struct DeepScanResult: Sendable {
        let slaveId: UInt8
        let address: UInt16
        let value: UInt16
    }

    /// Run a deep scan that tests many register addresses to find valid ones
    /// This is useful when the standard addresses don't work
    func runDeepScan(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async -> [DeepScanResult] {
        logger.info("Starting deep diagnostic scan for \(host):\(port)")

        var results: [DeepScanResult] = []

        // Slave IDs to test - prioritize common values
        let slaveIds: [UInt8] = [1, 2, 0, 255]

        // Key addresses to test - based on working Homey app implementation
        // The DRU bridge uses RAW register numbers (40200) not protocol addresses (199)
        let keyAddresses: [UInt16] = [
            // RAW register numbers (WORKING per Homey app)
            40200,      // Action register
            40201,      // Flame height
            40203,      // Status
            40204,      // Fault code
            40205,      // RSSI gateway
            40206,      // RSSI fireplace
            40207,      // Temperature
            40250,      // Thermostat setpoint
            // Legacy protocol addresses (in case some devices use standard Modbus)
            199, 200, 202, 203, 204, 205, 206, 249,
            // Simple addresses
            0, 1, 2, 3, 4, 5,
        ]

        // Remove duplicates and sort
        let uniqueAddresses = Array(Set(keyAddresses)).sorted()
        let totalTests = slaveIds.count * uniqueAddresses.count * 2 // *2 for holding + input
        var currentTest = 0

        for slaveId in slaveIds {
            progressHandler("Testing Slave ID \(slaveId)...")

            let client = ModbusTCPClient(
                host: host,
                port: port,
                slaveId: slaveId,
                timeout: 2.0
            )

            do {
                try await client.connect()

                // Test holding registers (function code 0x03)
                for address in uniqueAddresses {
                    currentTest += 1
                    let progress = Int(Double(currentTest) / Double(totalTests) * 100)
                    progressHandler("[\(progress)%] Slave \(slaveId), Holding Reg \(address)")

                    do {
                        let values = try await client.readHoldingRegisters(startAddress: address, quantity: 1)
                        if let value = values.first {
                            logger.info("SUCCESS: Slave \(slaveId), Holding \(address) = \(value) (0x\(String(format: "%04X", value)))")
                            results.append(DeepScanResult(slaveId: slaveId, address: address, value: value))
                            progressHandler("FOUND: Slave \(slaveId), Holding \(address) = \(value)")
                        }
                    } catch {
                        // Expected - most addresses won't work
                    }

                    try? await Task.sleep(for: .milliseconds(30))
                }

                // Test input registers (function code 0x04) - some devices use these for read-only data
                for address in uniqueAddresses {
                    currentTest += 1
                    let progress = Int(Double(currentTest) / Double(totalTests) * 100)
                    progressHandler("[\(progress)%] Slave \(slaveId), Input Reg \(address)")

                    do {
                        let values = try await client.readInputRegisters(startAddress: address, quantity: 1)
                        if let value = values.first {
                            logger.info("SUCCESS: Slave \(slaveId), Input \(address) = \(value) (0x\(String(format: "%04X", value)))")
                            // Mark as input register by adding 10000 to address in results
                            results.append(DeepScanResult(slaveId: slaveId, address: address + 10000, value: value))
                            progressHandler("FOUND: Slave \(slaveId), Input \(address) = \(value)")
                        }
                    } catch {
                        // Expected - most addresses won't work
                    }

                    try? await Task.sleep(for: .milliseconds(30))
                }

                await client.disconnect()
            } catch {
                logger.debug("Failed to connect with slave \(slaveId): \(error.localizedDescription)")
                currentTest += uniqueAddresses.count * 2 // Skip remaining addresses for this slave
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        logger.info("Deep scan complete. Found \(results.count) valid registers")
        return results
    }

    /// Try to initiate binding by writing to register 40101
    /// Some DRU fireplaces require this before Modbus reads work
    func tryInitiateBinding(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        logger.info("Attempting to initiate binding on \(host):\(port)")

        // Try different slave IDs
        let slaveIds: [UInt8] = [1, 2, 207]

        // Register 40101 = address 100 (with 40001=0 convention)
        // or address 101 (with 40000=0 convention)
        let bindingAddresses: [UInt16] = [100, 101]

        // Common binding values to try
        let bindingValues: [UInt16] = [1, 0xFFFF, 0x0001]

        for slaveId in slaveIds {
            for address in bindingAddresses {
                for value in bindingValues {
                    progressHandler("Trying binding: Slave \(slaveId), Addr \(address), Val \(value)")

                    let client = ModbusTCPClient(
                        host: host,
                        port: port,
                        slaveId: slaveId,
                        timeout: 3.0
                    )

                    do {
                        try await client.connect()

                        // Try to write to binding register
                        try await client.writeSingleRegister(address: address, value: value)
                        logger.info("SUCCESS: Wrote \(value) to slave \(slaveId), address \(address)")
                        progressHandler("SUCCESS: Binding write to Slave \(slaveId), Addr \(address)")

                        // Wait a moment for binding to take effect
                        try? await Task.sleep(for: .milliseconds(500))

                        // Try to read status register to see if it works now
                        // Use RAW register number as working implementations do
                        let statusValues = try await client.readHoldingRegisters(startAddress: 40203, quantity: 1)
                        if let status = statusValues.first {
                            logger.info("After binding, status register = \(status)")
                            progressHandler("Status after binding: \(status)")
                            await client.disconnect()
                            return true
                        }

                        await client.disconnect()
                    } catch {
                        logger.debug("Binding attempt failed: \(error.localizedDescription)")
                        await client.disconnect()
                    }

                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }

        logger.info("Binding initiation failed")
        return false
    }

    /// Run a full range scan to find ANY valid registers
    /// This tests a continuous range of addresses to discover the register map
    func runFullRangeScan(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async -> [DeepScanResult] {
        logger.info("Starting full range scan for \(host):\(port)")

        var results: [DeepScanResult] = []

        // Test slave IDs that responded (even with errors) - they're "alive"
        let slaveIds: [UInt8] = [1, 2]

        // Scan a wide range of addresses in blocks
        // Per working Homey app: DRU uses RAW register numbers (40200, not 199)
        let addressRanges: [(start: UInt16, end: UInt16, name: String)] = [
            // RAW register numbers (WORKING per Homey app)
            (40200, 40210, "DRU Status (raw 40200-40210)"),
            (40250, 40260, "DRU Thermostat (raw 40250-40260)"),
            (40100, 40110, "DRU Binding (raw 40100-40110)"),
            (40420, 40430, "DRU EcoWave (raw 40420-40430)"),
            // Legacy protocol addresses (in case standard Modbus)
            (0, 20, "Low range (0-20)"),
            (199, 210, "Legacy status range (199-210)"),
            (249, 260, "Legacy thermostat range (249-260)"),
        ]

        for slaveId in slaveIds {
            progressHandler("Scanning Slave ID \(slaveId)...")

            let client = ModbusTCPClient(
                host: host,
                port: port,
                slaveId: slaveId,
                timeout: 2.0
            )

            do {
                try await client.connect()

                for range in addressRanges {
                    progressHandler("Slave \(slaveId): \(range.name)")

                    for address in range.start...range.end {
                        do {
                            let values = try await client.readHoldingRegisters(startAddress: address, quantity: 1)
                            if let value = values.first {
                                logger.info("FOUND: Slave \(slaveId), Address \(address) = \(value) (0x\(String(format: "%04X", value)))")
                                results.append(DeepScanResult(slaveId: slaveId, address: address, value: value))
                                progressHandler("✓ FOUND: Slave \(slaveId), Addr \(address) = \(value)")
                            }
                        } catch {
                            // Expected - most addresses won't work
                        }

                        // Small delay to not overwhelm the bridge
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                }

                await client.disconnect()
            } catch {
                logger.debug("Failed to connect with slave \(slaveId): \(error.localizedDescription)")
                progressHandler("Connection failed for slave \(slaveId)")
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        logger.info("Full range scan complete. Found \(results.count) valid registers")
        return results
    }

    /// Scan using broadcast/wildcard addressing to find responsive slaves
    /// Some bridges respond differently to unit ID 0 or 255
    func scanForResponsiveSlaves(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async -> [(slaveId: UInt8, responseType: String)] {
        logger.info("Scanning for responsive slaves on \(host):\(port)")

        var responses: [(slaveId: UInt8, responseType: String)] = []

        // Test all possible slave IDs (0-255) with a simple register read
        // Most won't respond, but we want to find ALL that do
        let testAddress: UInt16 = 0  // Simple address that might exist

        // Test in chunks to show progress
        let chunkSize = 16
        for chunkStart in stride(from: 0, to: 256, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, 256)
            progressHandler("Testing slave IDs \(chunkStart)-\(chunkEnd-1)...")

            for slaveIdInt in chunkStart..<chunkEnd {
                let slaveId = UInt8(slaveIdInt)

                let client = ModbusTCPClient(
                    host: host,
                    port: port,
                    slaveId: slaveId,
                    timeout: 1.0  // Short timeout for quick scanning
                )

                do {
                    try await client.connect()

                    do {
                        let values = try await client.readHoldingRegisters(startAddress: testAddress, quantity: 1)
                        if let value = values.first {
                            logger.info("Slave \(slaveId) responded with value: \(value)")
                            responses.append((slaveId, "Success: value=\(value)"))
                            progressHandler("✓ Slave \(slaveId): Success (value=\(value))")
                        }
                    } catch let error as ModbusError {
                        // Any Modbus error means the slave is responsive
                        let errorDesc = error.localizedDescription
                        if errorDesc.contains("Illegal") || errorDesc.contains("Gateway") {
                            logger.info("Slave \(slaveId) responded with error: \(errorDesc)")
                            responses.append((slaveId, errorDesc))
                            progressHandler("⚠ Slave \(slaveId): \(errorDesc)")
                        }
                    }

                    await client.disconnect()
                } catch {
                    // Connection failed - slave not responsive
                    await client.disconnect()
                }

                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        logger.info("Slave scan complete. Found \(responses.count) responsive slaves")
        return responses
    }

    /// Try to discover registered fireplaces by reading gateway registers
    /// The Homey app reads registers 40201-40207 to get bound device unit IDs
    func discoverFireplaces(
        host: String,
        port: UInt16 = 502,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async -> [UInt8] {
        logger.info("Attempting fireplace discovery on \(host):\(port)")

        var discoveredSlaveIds: [UInt8] = []

        // Try different unit IDs for the gateway
        let gatewaySlaveIds: [UInt8] = [0, 1, 255]

        // The Homey app reads 40201-40207 (addresses 200-206) to discover devices
        let discoveryAddress: UInt16 = 200
        let discoveryCount: UInt16 = 7

        for gatewayId in gatewaySlaveIds {
            progressHandler("Trying gateway ID \(gatewayId)...")

            let client = ModbusTCPClient(
                host: host,
                port: port,
                slaveId: gatewayId,
                timeout: 3.0
            )

            do {
                try await client.connect()

                let values = try await client.readHoldingRegisters(
                    startAddress: discoveryAddress,
                    quantity: discoveryCount
                )

                await client.disconnect()

                logger.info("Gateway \(gatewayId) returned \(values.count) values: \(values)")
                progressHandler("Gateway \(gatewayId): \(values)")

                // Each non-zero value is a slave ID of a connected fireplace
                for value in values where value > 0 && value < 256 {
                    let slaveId = UInt8(value)
                    if !discoveredSlaveIds.contains(slaveId) {
                        discoveredSlaveIds.append(slaveId)
                        logger.info("Discovered fireplace at slave ID \(slaveId)")
                    }
                }

                if !discoveredSlaveIds.isEmpty {
                    break // Found devices, no need to try other gateway IDs
                }

            } catch {
                logger.debug("Gateway \(gatewayId) failed: \(error.localizedDescription)")
                await client.disconnect()
            }

            try? await Task.sleep(for: .milliseconds(300))
        }

        logger.info("Discovery complete. Found \(discoveredSlaveIds.count) fireplaces: \(discoveredSlaveIds)")
        return discoveredSlaveIds
    }
}
