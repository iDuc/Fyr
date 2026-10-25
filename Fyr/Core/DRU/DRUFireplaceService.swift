import Foundation
import os

/// High-level service for controlling DRU fireplaces
/// Handles rate limiting and translates high-level commands to Modbus operations
actor DRUFireplaceService {

    // MARK: - Singleton

    static let shared = DRUFireplaceService()

    // MARK: - Properties

    private var modbusClient: ModbusTCPClient?
    private let rateLimiter = RateLimiter()
    private let logger = Logger(subsystem: "com.fyr.app", category: "DRUService")

    private(set) var isConnected: Bool = false
    private(set) var bridgeIP: String?

    /// Current Modbus slave ID (loaded from settings)
    private var currentSlaveId: UInt8 = 2

    /// Current address offset (loaded from settings)
    private var currentAddressOffset: Int = 0

    /// Number of retry attempts for commands
    private let maxRetries = 3

    /// Flag to prevent concurrent reconnection attempts
    private var isReconnecting: Bool = false

    /// Flag to prevent concurrent status fetches
    private var isFetchingStatus: Bool = false

    /// Timestamp when isFetchingStatus was set to true (for timeout protection)
    private var fetchStatusStartTime: Date?

    /// Maximum time before isFetchingStatus auto-resets (prevents hung state)
    private let fetchStatusTimeout: TimeInterval = 15.0

    /// Delay between reconnection attempts to avoid overwhelming the bridge
    private let reconnectionDelay: TimeInterval = 2.0

    /// Command serialization - only one command can execute at a time
    /// DRU bridge cannot handle concurrent Modbus operations
    private var isExecutingCommand: Bool = false

    /// Queue of pending operations waiting for command slot
    private var pendingCommandContinuations: [CheckedContinuation<Void, Never>] = []

    /// Delay after receiving Modbus Acknowledge (0x05) error before retry
    private let acknowledgeRetryDelay: TimeInterval = 1.0

    /// Flag to pause all operations during diagnostic scanning
    /// When true, fetchStatus and reconnect will immediately return/throw
    private(set) var scanningInProgress: Bool = false

    /// Last set flame height (register 40201 is write-only, so we track locally)
    private(set) var lastSetFlameHeight: Int = 0

    // MARK: - Initialization

    private init() {
        logger.info("DRUFireplaceService initialized")
    }

    // MARK: - Connection Management

    /// Configure and connect to the bridge
    /// - Parameter ip: Bridge IP address
    func connect(to ip: String) async throws {
        // Load Modbus configuration from settings
        currentSlaveId = SettingsStore.modbusSlaveIdValue
        currentAddressOffset = SettingsStore.modbusAddressOffsetValue

        logger.info("Using Modbus config: slaveId=\(self.currentSlaveId), addressOffset=\(self.currentAddressOffset)")

        // Check if we're already connected to the same IP with same config
        if let existingIP = bridgeIP, existingIP == ip, isConnected, let client = modbusClient {
            let clientConnected = await client.isConnected
            if clientConnected {
                logger.debug("Already connected to \(ip), reusing existing connection")
                return
            }
        }

        logger.info("Connecting to bridge at \(ip)")
        bridgeIP = ip

        // Disconnect existing client if any
        if modbusClient != nil {
            await disconnect()
        }

        let client = ModbusTCPClient(
            host: ip,
            port: DRUConstants.modbusPort,
            slaveId: currentSlaveId,
            timeout: 5.0
        )

        try await client.connect()
        modbusClient = client
        isConnected = true
        logger.info("Successfully connected to bridge")
    }

    /// Update Modbus configuration and reconnect if needed
    /// Called after diagnostic scan finds a working configuration
    func updateConfiguration(slaveId: UInt8, addressOffset: Int) async throws {
        logger.info("Updating Modbus config: slaveId=\(slaveId), addressOffset=\(addressOffset)")

        currentSlaveId = slaveId
        currentAddressOffset = addressOffset

        // Force reconnect with new configuration
        if let ip = bridgeIP {
            await disconnect()
            try await Task.sleep(for: .milliseconds(500))

            let client = ModbusTCPClient(
                host: ip,
                port: DRUConstants.modbusPort,
                slaveId: currentSlaveId,
                timeout: 5.0
            )

            try await client.connect()
            modbusClient = client
            isConnected = true
            logger.info("Reconnected with new configuration")
        }
    }

    /// Disconnect from the bridge
    func disconnect() async {
        logger.info("Disconnecting from bridge")
        if let client = modbusClient {
            await client.disconnect()
        }
        modbusClient = nil
        isConnected = false
    }

    /// Start scanning mode - pauses all normal operations
    /// Call this before running diagnostic scans
    func startScanning() async {
        logger.info("Starting scanning mode - pausing normal operations")
        scanningInProgress = true
        await disconnect()
    }

    /// Stop scanning mode - resumes normal operations
    /// Call this after diagnostic scans complete
    func stopScanning() {
        logger.info("Stopping scanning mode - resuming normal operations")
        scanningInProgress = false
    }

    // MARK: - Command Serialization

    /// Acquire exclusive command slot - blocks until available
    /// DRU bridge can only handle one Modbus operation at a time
    private func acquireCommandSlot() async {
        if !isExecutingCommand {
            isExecutingCommand = true
            logger.debug("Command slot acquired immediately")
            return
        }

        // Wait for current command to complete
        logger.debug("Command slot busy, waiting in queue...")
        await withCheckedContinuation { continuation in
            pendingCommandContinuations.append(continuation)
        }
        isExecutingCommand = true
        logger.debug("Command slot acquired from queue")
    }

    /// Release command slot and wake next waiting command
    private func releaseCommandSlot() {
        isExecutingCommand = false

        if let next = pendingCommandContinuations.first {
            pendingCommandContinuations.removeFirst()
            logger.debug("Releasing command slot, waking next in queue (\(self.pendingCommandContinuations.count) remaining)")
            next.resume()
        } else {
            logger.debug("Command slot released, queue empty")
        }
    }

    /// Reconnect to the last known bridge
    /// Thread-safe: prevents concurrent reconnection attempts
    func reconnect() async throws {
        // Don't reconnect during scanning
        guard !scanningInProgress else {
            logger.debug("Reconnect skipped: scanning in progress")
            throw DRUServiceError.commandThrottled
        }

        guard let ip = bridgeIP else {
            logger.error("Cannot reconnect: no bridge configured")
            throw DRUServiceError.noBridgeConfigured
        }

        // Prevent concurrent reconnection attempts
        guard !isReconnecting else {
            logger.debug("Reconnection already in progress, waiting...")
            // Wait for the ongoing reconnection to complete
            try await Task.sleep(for: .seconds(reconnectionDelay))
            // Check if we're now connected
            if isConnected {
                return
            }
            throw DRUServiceError.notConnected
        }

        isReconnecting = true
        defer { isReconnecting = false }

        logger.info("Reconnecting to \(ip)")

        // Disconnect first and wait for cleanup
        await disconnect()
        try await Task.sleep(for: .milliseconds(500))

        try await connect(to: ip)
    }

    /// Ensure we have an active connection, reconnecting if necessary
    private func ensureConnected() async throws {
        guard let client = modbusClient else {
            if bridgeIP != nil {
                try await reconnect()
                return
            }
            throw DRUServiceError.notConnected
        }

        // Check if connection is still valid
        let clientConnected = await client.isConnected
        if !clientConnected {
            logger.warning("Connection lost, attempting reconnect...")
            try await reconnect()
        }
    }

    // MARK: - Commands

    /// Turn on the fireplace
    func turnOn() async throws {
        logger.info("Turning fireplace ON")
        try await executeCommandWithRetry(.generalWrite) {
            try await self.writeActionRegister(.mainBurner)
        }
        logger.info("Fireplace ON command sent successfully")
    }

    /// Turn off the fireplace
    func turnOff() async throws {
        logger.info("Turning fireplace OFF")
        try await executeCommandWithRetry(.generalWrite) {
            try await self.writeActionRegister(.fireplaceOff)
        }
        logger.info("Fireplace OFF command sent successfully")
    }

    /// Set flame height
    /// - Parameter height: Flame height percentage (0-100)
    func setFlameHeight(_ height: Int) async throws {
        let clampedHeight = max(DRUConstants.minFlameHeight, min(DRUConstants.maxFlameHeight, height))
        logger.info("Setting flame height to \(clampedHeight)")

        try await executeCommandWithRetry(.flameHeight) {
            try await self.writeRegister(.flameHeightTarget, value: UInt16(clampedHeight))
        }

        // Track locally since register 40201 is write-only
        lastSetFlameHeight = clampedHeight
    }

    /// Set thermostat setpoint
    /// - Parameter temperature: Target temperature in °C (5-35)
    func setThermostatSetpoint(_ temperature: Double) async throws {
        let clampedTemp = max(DRUConstants.minTemperature, min(DRUConstants.maxTemperature, temperature))
        let scaledValue = UInt16(clampedTemp * DRUConstants.temperatureScaleFactor)
        logger.info("Setting thermostat to \(clampedTemp)°C")

        try await executeCommandWithRetry(.generalWrite) {
            try await self.writeRegister(.thermostatSetpoint, value: scaledValue)
        }
    }

    /// Enable or disable eco/wave mode
    /// - Parameter enabled: Whether eco mode should be enabled
    func setEcoMode(enabled: Bool) async throws {
        logger.info("Setting eco mode to \(enabled)")
        try await executeCommandWithRetry(.generalWrite) {
            // Use waveModeOn (105) to enable, waveModeOff (7) to disable
            let action: DRUAction = enabled ? .waveModeOn : .waveModeOff
            try await self.writeActionRegister(action)
        }
    }

    /// Set wave interval for eco mode
    /// - Parameter seconds: Interval in seconds (1-60)
    func setWaveInterval(_ seconds: Int) async throws {
        let clampedInterval = max(DRUConstants.minWaveInterval, min(DRUConstants.maxWaveInterval, seconds))
        logger.info("Setting wave interval to \(clampedInterval)s")

        try await executeCommandWithRetry(.generalWrite) {
            try await self.writeRegister(.waveInterval, value: UInt16(clampedInterval))
        }
    }

    // MARK: - Status

    /// Fetch current fireplace status
    /// - Returns: Current status
    /// Note: DRU bridge has limited Modbus implementation - must read registers individually
    func fetchStatus() async throws -> FireplaceStatus {
        logger.info("fetchStatus() called")

        // Don't fetch during scanning
        guard !scanningInProgress else {
            logger.debug("Status fetch skipped: scanning in progress")
            throw DRUServiceError.commandThrottled
        }

        // Prevent concurrent status fetches - DRU bridge only handles one request at a time
        // Include timeout protection to prevent hung state
        if isFetchingStatus {
            // Check if the fetch has been running too long (timeout protection)
            if let startTime = fetchStatusStartTime,
               Date().timeIntervalSince(startTime) > fetchStatusTimeout {
                logger.warning("isFetchingStatus timeout detected, resetting flag")
                isFetchingStatus = false
                fetchStatusStartTime = nil
            } else {
                logger.debug("Status fetch already in progress, skipping")
                throw DRUServiceError.commandThrottled
            }
        }

        isFetchingStatus = true
        fetchStatusStartTime = Date()
        defer {
            isFetchingStatus = false
            fetchStatusStartTime = nil
        }

        logger.debug("Ensuring connection before status fetch...")
        try await ensureConnected()
        logger.debug("Connection verified, proceeding with status fetch")

        await rateLimiter.waitIfNeeded(for: .read)

        // Serialize with other commands - DRU bridge can only handle one operation at a time
        await acquireCommandSlot()
        defer { releaseCommandSlot() }

        logger.debug("Rate limiter cleared, starting register reads...")

        // Read status registers individually (DRU bridge doesn't support batch reads)
        var lastError: Error?
        for attempt in 1...maxRetries {
            // Get fresh client reference on each attempt (may change after reconnect)
            guard let client = modbusClient else {
                throw DRUServiceError.notConnected
            }

            do {
                // Read each register individually with small delays
                // This matches the Node-RED implementation which reads one register at a time
                let statusReg = try await readSingleRegister(client: client, register: .status)
                try await Task.sleep(for: .milliseconds(100))

                let errorReg = try await readSingleRegister(client: client, register: .errorCode)
                try await Task.sleep(for: .milliseconds(100))

                _ = try await readSingleRegister(client: client, register: .rssiGateway)
                try await Task.sleep(for: .milliseconds(100))

                let rssiFireplaceReg = try await readSingleRegister(client: client, register: .rssiFireplace)
                try await Task.sleep(for: .milliseconds(100))

                let temperatureReg = try await readSingleRegister(client: client, register: .temperature)

                await rateLimiter.recordExecution(of: .read)

                // Status register 40203 contains bitfield status:
                // - 15360 (0x3C00) = OFF
                // - 47108 (0xB804) = ON, normal mode
                // - 47620 (0xBA04) = ON, eco-wave mode (bit 9 set = 0x0200)
                // Non-zero and not 15360 means ON
                let statusCode = statusReg
                let isOn = statusCode != 15360 && statusCode != 0

                // Eco mode is indicated by bit 9 (0x0200) being set
                let ecoModeActive = (statusCode & 0x0200) != 0

                // RSSI values: multiply by -0.5 to get dBm
                let rssiFireplace = Double(rssiFireplaceReg) * -0.5

                let status = FireplaceStatus(
                    isOn: isOn,
                    ecoModeActive: ecoModeActive,
                    temperatureControlActive: false, // Not available in basic status
                    errorCode: FireplaceErrorCode.from(rawValue: errorReg),
                    flameHeight: self.lastSetFlameHeight, // Flame height is write-only, track locally
                    signalStrength: Int(rssiFireplace),
                    currentTemperature: Double(temperatureReg) / DRUConstants.temperatureScaleFactor
                )

                logger.debug("Status fetched: isOn=\(status.isOn), statusCode=\(statusCode), temp=\(status.currentTemperature), rssi=\(rssiFireplace)dBm")
                return status

            } catch is CancellationError {
                // Task was cancelled - propagate immediately without retry
                logger.debug("Status fetch cancelled")
                throw CancellationError()
            } catch {
                lastError = error
                logger.warning("Status fetch attempt \(attempt) failed: \(error.localizedDescription)")

                // Check if this is a Modbus Acknowledge (device busy) error
                if isAcknowledgeError(error) && attempt < maxRetries {
                    logger.info("Device busy (Acknowledge), waiting \(self.acknowledgeRetryDelay)s before retry...")
                    try? await Task.sleep(for: .seconds(acknowledgeRetryDelay))
                    continue
                }

                // Only retry with reconnection if error indicates connection problem
                if attempt < maxRetries && errorRequiresReconnection(error) {
                    logger.info("Connection error detected, attempting reconnect before retry...")
                    do {
                        try await reconnect()
                    } catch {
                        logger.error("Reconnection failed during status fetch: \(error.localizedDescription)")
                    }
                } else if attempt < maxRetries {
                    // Protocol error - retry without reconnection, just a small delay
                    logger.debug("Protocol error, retrying without reconnection...")
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }

        logger.error("Status fetch failed after \(self.maxRetries) attempts")
        throw lastError ?? DRUServiceError.notConnected
    }

    /// Read a single register from the Modbus client
    /// Applies the configured address offset automatically
    private func readSingleRegister(client: ModbusTCPClient, register: DRURegister) async throws -> UInt16 {
        let address = register.rawValue + UInt16(currentAddressOffset)
        let values = try await client.readHoldingRegisters(
            startAddress: address,
            quantity: 1
        )
        guard let value = values.first else {
            throw ModbusError.invalidResponse
        }
        return value
    }

    /// Check if a flame height change is currently allowed
    /// - Returns: True if allowed, with time remaining if not
    func canChangeFlameHeight() async -> (allowed: Bool, timeRemaining: TimeInterval) {
        let canExecute = await rateLimiter.canExecute(.flameHeight)
        let remaining = await rateLimiter.timeRemaining(for: .flameHeight)
        return (canExecute, remaining)
    }

    // MARK: - Private Helpers

    private func executeCommandWithRetry(_ type: RateLimiter.CommandType, _ command: @Sendable @escaping () async throws -> Void) async throws {
        try await ensureConnected()

        await rateLimiter.waitIfNeeded(for: type)

        // Serialize commands - DRU bridge can only handle one at a time
        await acquireCommandSlot()
        defer { releaseCommandSlot() }

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                try await command()
                await rateLimiter.recordExecution(of: type)
                return
            } catch {
                lastError = error
                logger.warning("Command attempt \(attempt) failed: \(error.localizedDescription)")

                // Check if this is a Modbus Acknowledge (device busy) error
                if isAcknowledgeError(error) && attempt < maxRetries {
                    logger.info("Device busy (Acknowledge), waiting \(self.acknowledgeRetryDelay)s before retry...")
                    try? await Task.sleep(for: .seconds(acknowledgeRetryDelay))
                    continue
                }

                // Only retry with reconnection if error indicates connection problem
                if attempt < maxRetries && errorRequiresReconnection(error) {
                    logger.info("Connection error detected, attempting reconnect before retry...")
                    do {
                        try await reconnect()
                    } catch {
                        logger.error("Reconnection failed during command retry: \(error.localizedDescription)")
                    }
                } else if attempt < maxRetries {
                    // Protocol error - retry without reconnection, just a small delay
                    logger.debug("Protocol error, retrying without reconnection...")
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }

        logger.error("Command failed after \(self.maxRetries) attempts")
        throw lastError ?? DRUServiceError.notConnected
    }

    /// Check if error is a Modbus Acknowledge (0x05) - device busy
    private nonisolated func isAcknowledgeError(_ error: Error) -> Bool {
        if let modbusError = error as? ModbusError {
            if case .modbusException(code: let code) = modbusError {
                return code == 0x05  // Acknowledge - device busy
            }
        }
        return false
    }

    private func writeActionRegister(_ action: DRUAction) async throws {
        guard let client = modbusClient else {
            throw DRUServiceError.notConnected
        }

        let address = DRURegister.action.rawValue + UInt16(currentAddressOffset)
        try await client.writeSingleRegister(
            address: address,
            value: action.rawValue
        )
    }

    private func writeRegister(_ register: DRURegister, value: UInt16) async throws {
        guard let client = modbusClient else {
            throw DRUServiceError.notConnected
        }

        let address = register.rawValue + UInt16(currentAddressOffset)
        try await client.writeSingleRegister(address: address, value: value)
    }

    // MARK: - Diagnostics

    /// Diagnostic result for register scanning
    struct DiagnosticResult: Sendable {
        let address: UInt16
        let functionCode: UInt8
        let success: Bool
        let value: UInt16?
        let errorMessage: String?
    }

    /// Run diagnostics to find valid register addresses
    /// This helps debug "Illegal Data Address" errors by scanning multiple addresses
    func runDiagnostics() async -> [DiagnosticResult] {
        logger.info("Starting Modbus diagnostics...")

        try? await ensureConnected()

        guard let client = modbusClient else {
            logger.error("Diagnostics failed: not connected")
            return []
        }

        var results: [DiagnosticResult] = []

        // Test addresses to try:
        // IMPORTANT: DRU bridge expects RAW Modbus register numbers, NOT protocol addresses!
        // Working implementations (Homey app) pass 40200 directly, NOT 199 (40200 - 40001).
        // See: https://github.com/amstelzone/com.amstelzone.dru
        let testAddresses: [UInt16] = [
            // RAW register addresses (what DRU bridge actually expects)
            40200,  // Action register (raw) - confirmed working in Homey app
            40201,  // Flame height target (raw)
            40203,  // Status register (raw) - confirmed working in Homey app
            40204,  // Error code (raw)
            40205,  // Gateway RSSI (raw)
            40206,  // Fireplace RSSI (raw)
            40207,  // Temperature (raw)
            // Legacy addresses (for fallback testing with standard Modbus)
            202,    // Legacy: 40203 - 40001
            199,    // Legacy: 40200 - 40001
        ]

        // Try both holding registers (FC 0x03) and input registers (FC 0x04)
        for address in testAddresses {
            // Add delay between tests to not overwhelm the bridge
            try? await Task.sleep(for: .milliseconds(200))

            // Test with holding registers (FC 0x03)
            logger.debug("Testing holding register at address \(address)")
            do {
                let values = try await client.readHoldingRegisters(startAddress: address, quantity: 1)
                if let value = values.first {
                    logger.info("SUCCESS: Holding register \(address) = \(value) (0x\(String(format: "%04X", value)))")
                    results.append(DiagnosticResult(
                        address: address,
                        functionCode: 0x03,
                        success: true,
                        value: value,
                        errorMessage: nil
                    ))
                }
            } catch {
                logger.debug("Holding register \(address) failed: \(error.localizedDescription)")
                results.append(DiagnosticResult(
                    address: address,
                    functionCode: 0x03,
                    success: false,
                    value: nil,
                    errorMessage: error.localizedDescription
                ))
            }

            // Add delay before trying input registers
            try? await Task.sleep(for: .milliseconds(200))

            // Test with input registers (FC 0x04)
            logger.debug("Testing input register at address \(address)")
            do {
                let values = try await client.readInputRegisters(startAddress: address, quantity: 1)
                if let value = values.first {
                    logger.info("SUCCESS: Input register \(address) = \(value) (0x\(String(format: "%04X", value)))")
                    results.append(DiagnosticResult(
                        address: address,
                        functionCode: 0x04,
                        success: true,
                        value: value,
                        errorMessage: nil
                    ))
                }
            } catch {
                logger.debug("Input register \(address) failed: \(error.localizedDescription)")
                results.append(DiagnosticResult(
                    address: address,
                    functionCode: 0x04,
                    success: false,
                    value: nil,
                    errorMessage: error.localizedDescription
                ))
            }
        }

        let successCount = results.filter { $0.success }.count
        logger.info("Diagnostics complete: \(successCount)/\(results.count) successful")

        return results
    }
}

// MARK: - Service Errors

enum DRUServiceError: Error, LocalizedError {
    case notConnected
    case noBridgeConfigured
    case commandThrottled
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to fireplace"
        case .noBridgeConfigured:
            return "No bridge IP configured"
        case .commandThrottled:
            return "Command rate limited, please wait"
        case .protocolError(let message):
            return "Communication error: \(message)"
        }
    }

    /// Returns true if this error indicates the connection is broken and needs reconnection
    var requiresReconnection: Bool {
        switch self {
        case .notConnected:
            return true
        case .noBridgeConfigured, .commandThrottled, .protocolError:
            return false
        }
    }
}

// MARK: - Error Classification

/// Determines if an error requires reconnection or is just a protocol-level issue
nonisolated func errorRequiresReconnection(_ error: Error) -> Bool {
    // DRUServiceError has its own classification
    if let serviceError = error as? DRUServiceError {
        return serviceError.requiresReconnection
    }

    // ModbusError classification
    if let modbusError = error as? ModbusError {
        switch modbusError {
        case .connectionFailed, .connectionClosed, .notConnected, .timeout:
            // Connection is broken - reconnection needed
            return true
        case .sendFailed, .receiveFailed:
            // IO errors often indicate connection issues
            return true
        case .modbusException, .invalidResponse, .invalidResponseSize,
             .unexpectedFunctionCode, .invalidByteCount:
            // Protocol errors - connection is fine, data is wrong
            // Reconnecting won't help
            return false
        }
    }

    // CancellationError doesn't require reconnection
    if error is CancellationError {
        return false
    }

    // Unknown errors - default to requiring reconnection
    return true
}
