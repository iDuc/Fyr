import Foundation
import Network
import os

/// Thread-safe ModbusTCP client using Network.framework
/// Uses actor isolation for safe concurrent access
actor ModbusTCPClient {

    // MARK: - Types

    /// Thread-safe flag for connection state tracking
    private final class ConnectionFlag: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: false)

        func setTrueIfFalse() -> Bool {
            lock.withLock { current in
                if !current {
                    current = true
                    return true
                }
                return false
            }
        }
    }

    // MARK: - Properties

    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private let slaveId: UInt8
    private var transactionId: UInt16 = 0
    private let timeout: TimeInterval
    private let logger = Logger(subsystem: "com.fyr.app", category: "ModbusTCP")

    /// Serial queue for NWConnection - CRITICAL: must be serial, not concurrent
    private let networkQueue = DispatchQueue(label: "com.fyr.modbus.network", qos: .userInitiated)

    /// Connection state for external observation
    private(set) var isConnected: Bool = false

    /// Last successful communication timestamp
    private(set) var lastCommunication: Date?

    /// Delay after connection before sending first command (ms)
    /// DRU bridge needs time to be ready after TCP handshake
    /// Increased to 1500ms for better reliability with DRU bridge
    private let postConnectionDelay: UInt64 = 1500

    /// Keepalive interval - if no communication for this long, connection may be stale
    private let keepaliveInterval: TimeInterval = 30.0

    // MARK: - Initialization

    /// Initialize ModbusTCP client
    /// - Parameters:
    ///   - host: Bridge IP address
    ///   - port: Modbus TCP port (default: 502)
    ///   - slaveId: Slave/unit ID (default: 2 for DRU fireplace)
    ///   - timeout: Request timeout in seconds (default: 5)
    init(host: String, port: UInt16 = 502, slaveId: UInt8 = 2, timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.slaveId = slaveId
        self.timeout = timeout
        logger.info("ModbusTCPClient initialized for \(host):\(port)")
    }

    // MARK: - Connection Management

    /// Connect to the Modbus TCP server
    func connect() async throws {
        // If already connected, verify the connection is still valid
        if isConnected, let conn = connection {
            if conn.state == .ready {
                logger.debug("Already connected to \(self.host)")
                return
            } else {
                logger.warning("Connection state is \(String(describing: conn.state)), reconnecting...")
                await disconnect()
            }
        }

        logger.info("Connecting to \(self.host):\(self.port)...")

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.tcp
        parameters.serviceClass = .responsiveData

        let newConnection = NWConnection(to: endpoint, using: parameters)
        connection = newConnection

        let flag = ConnectionFlag()
        let connectionTimeout = timeout

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Set up viability handler to detect network path changes
            newConnection.viabilityUpdateHandler = { [weak self, logger] isViable in
                logger.debug("Connection viability changed: \(isViable)")
                if !isViable {
                    Task { await self?.handleViabilityLost() }
                }
            }

            newConnection.stateUpdateHandler = { [weak self, logger] (state: NWConnection.State) in
                logger.debug("Connection state: \(String(describing: state))")

                switch state {
                case .ready:
                    if flag.setTrueIfFalse() {
                        logger.info("Connected to \(self?.host ?? "unknown")")
                        // Set isConnected SYNCHRONOUSLY before resuming continuation
                        // This is safe because we're in the state handler callback
                        Task {
                            await self?.setConnected(true)
                            continuation.resume()
                        }
                    }

                case .failed(let error):
                    if flag.setTrueIfFalse() {
                        logger.error("Connection failed: \(error.localizedDescription)")
                        Task { await self?.setConnected(false) }
                        continuation.resume(throwing: ModbusError.connectionFailed(error.localizedDescription))
                    }

                case .cancelled:
                    if flag.setTrueIfFalse() {
                        logger.info("Connection cancelled")
                        Task { await self?.setConnected(false) }
                        continuation.resume(throwing: ModbusError.connectionFailed("Connection cancelled"))
                    }

                case .waiting(let error):
                    // Network path is not available, likely WiFi issue
                    logger.warning("Connection waiting: \(error.localizedDescription)")
                    // Treat waiting state as a failure for connection purposes
                    if flag.setTrueIfFalse() {
                        Task { await self?.setConnected(false) }
                        continuation.resume(throwing: ModbusError.connectionFailed("Network not available: \(error.localizedDescription)"))
                    }

                case .preparing:
                    logger.debug("Connection preparing...")

                case .setup:
                    break

                @unknown default:
                    break
                }
            }

            // CRITICAL: Use serial queue, not global concurrent queue
            newConnection.start(queue: networkQueue)

            // Add connection timeout
            Task {
                try? await Task.sleep(for: .seconds(connectionTimeout))
                if flag.setTrueIfFalse() {
                    logger.error("Connection timeout after \(connectionTimeout)s")
                    newConnection.cancel()
                    continuation.resume(throwing: ModbusError.connectionFailed("Connection timeout"))
                }
            }
        }

        // Add post-connection delay for Modbus device readiness
        // Many embedded devices need time after TCP handshake before accepting Modbus requests
        logger.debug("Waiting \(self.postConnectionDelay)ms for device readiness...")
        try await Task.sleep(for: .milliseconds(postConnectionDelay))

        // Flush any stale data from the buffer
        // This prevents transaction ID mismatches from leftover responses
        await flushReceiveBuffer()

        logger.debug("Post-connection delay complete, ready for commands")
    }

    /// Flush any pending data from the receive buffer
    /// This prevents stale responses from previous sessions from causing issues
    /// Note: This is a simple implementation that just waits a short time
    /// rather than trying to actively drain the buffer (which can block)
    private func flushReceiveBuffer() async {
        logger.debug("Buffer flush - waiting for any stale data to clear...")
        // Simple approach: just wait a moment for any in-flight data
        // The NWConnection receive() call can block indefinitely if there's no data,
        // so we avoid actively trying to drain it
        try? await Task.sleep(for: .milliseconds(100))
        logger.debug("Buffer flush complete")
    }

    /// Handle loss of network viability
    /// Note: This is called from within the actor, so state updates are safe
    private func handleViabilityLost() {
        logger.warning("Network viability lost, marking as disconnected")
        isConnected = false
        // Cancel the connection to trigger reconnection logic
        connection?.cancel()
    }

    /// Check if connection appears healthy based on last communication time
    /// - Returns: True if last communication was within keepalive interval
    func isConnectionHealthy() -> Bool {
        guard isConnected, let lastComm = lastCommunication else {
            return false
        }
        return Date().timeIntervalSince(lastComm) < keepaliveInterval
    }

    /// Get time since last successful communication
    /// - Returns: Time interval since last communication, or nil if never communicated
    func timeSinceLastCommunication() -> TimeInterval? {
        guard let lastComm = lastCommunication else { return nil }
        return Date().timeIntervalSince(lastComm)
    }

    /// Disconnect from the Modbus TCP server
    func disconnect() async {
        logger.info("Disconnecting from \(self.host)")

        guard let conn = connection else {
            isConnected = false
            return
        }

        // Clear handlers before cancelling
        conn.viabilityUpdateHandler = nil
        conn.stateUpdateHandler = nil
        conn.cancel()

        connection = nil
        isConnected = false
    }

    private func setConnected(_ value: Bool) {
        isConnected = value
        if value {
            lastCommunication = Date()
        }
    }

    // MARK: - Read Operations

    /// Read Holding Registers (Function Code 0x03)
    /// - Parameters:
    ///   - startAddress: Starting register address (offset, not full 40xxx)
    ///   - quantity: Number of registers to read
    /// - Returns: Array of register values
    func readHoldingRegisters(startAddress: UInt16, quantity: UInt16) async throws -> [UInt16] {
        guard let connection else {
            logger.error("Read failed: no connection object")
            throw ModbusError.notConnected
        }

        guard isConnected else {
            logger.error("Read failed: isConnected is false")
            throw ModbusError.notConnected
        }

        // Verify connection is still ready
        guard connection.state == .ready else {
            logger.error("Read failed: connection not ready (state: \(String(describing: connection.state)))")
            isConnected = false
            throw ModbusError.notConnected
        }

        transactionId &+= 1
        let currentTxn = transactionId

        logger.debug("Reading \(quantity) registers from address \(startAddress) [txn:\(currentTxn)]")

        let pdu = ModbusProtocol.buildReadRequest(startAddress: startAddress, quantity: quantity)
        let header = ModbusProtocol.buildMBAPHeader(transactionId: currentTxn, pduLength: pdu.count, unitId: slaveId)
        let request = header + pdu

        logger.debug("Sending request: \(request.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let response = try await sendAndReceive(connection: connection, data: request)

        logger.debug("Received response (\(response.count) bytes): \(response.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let values = try ModbusProtocol.parseReadResponse(response, expectedRegisters: Int(quantity))

        lastCommunication = Date()
        logger.debug("Read successful: \(values)")

        return values
    }

    // MARK: - Write Operations

    /// Write Single Register (Function Code 0x06)
    /// - Parameters:
    ///   - address: Register address (offset, not full 40xxx)
    ///   - value: Value to write
    func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        guard let connection else {
            logger.error("Write failed: no connection object")
            throw ModbusError.notConnected
        }

        guard isConnected else {
            logger.error("Write failed: isConnected is false")
            throw ModbusError.notConnected
        }

        // Verify connection is still ready
        guard connection.state == .ready else {
            logger.error("Write failed: connection not ready (state: \(String(describing: connection.state)))")
            isConnected = false
            throw ModbusError.notConnected
        }

        transactionId &+= 1
        let currentTxn = transactionId

        logger.info("Writing value \(value) to register \(address) [txn:\(currentTxn)]")

        let pdu = ModbusProtocol.buildWriteSingleRequest(address: address, value: value)
        let header = ModbusProtocol.buildMBAPHeader(transactionId: currentTxn, pduLength: pdu.count, unitId: slaveId)
        let request = header + pdu

        logger.debug("Sending write request: \(request.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let response = try await sendAndReceive(connection: connection, data: request)

        logger.debug("Received write response (\(response.count) bytes): \(response.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Validate the write response
        try ModbusProtocol.parseWriteSingleResponse(response, expectedAddress: address, expectedValue: value)

        lastCommunication = Date()
        logger.info("Write verified successful to register \(address)")
    }

    /// Read Input Registers (Function Code 0x04)
    /// - Parameters:
    ///   - startAddress: Starting register address (offset, not full 30xxx)
    ///   - quantity: Number of registers to read
    /// - Returns: Array of register values
    func readInputRegisters(startAddress: UInt16, quantity: UInt16) async throws -> [UInt16] {
        guard let connection else {
            logger.error("Read input registers failed: no connection object")
            throw ModbusError.notConnected
        }

        guard isConnected else {
            logger.error("Read input registers failed: isConnected is false")
            throw ModbusError.notConnected
        }

        guard connection.state == .ready else {
            logger.error("Read input registers failed: connection not ready (state: \(String(describing: connection.state)))")
            isConnected = false
            throw ModbusError.notConnected
        }

        transactionId &+= 1
        let currentTxn = transactionId

        logger.debug("Reading \(quantity) input registers from address \(startAddress) [txn:\(currentTxn)]")

        let pdu = ModbusProtocol.buildReadInputRegistersRequest(startAddress: startAddress, quantity: quantity)
        let header = ModbusProtocol.buildMBAPHeader(transactionId: currentTxn, pduLength: pdu.count, unitId: slaveId)
        let request = header + pdu

        logger.debug("Sending request: \(request.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let response = try await sendAndReceive(connection: connection, data: request)

        logger.debug("Received response (\(response.count) bytes): \(response.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let values = try ModbusProtocol.parseInputRegisterResponse(response, expectedRegisters: Int(quantity))

        lastCommunication = Date()
        logger.debug("Read input registers successful: \(values)")

        return values
    }

    /// Write Multiple Registers (Function Code 0x10)
    /// - Parameters:
    ///   - startAddress: Starting register address (offset, not full 40xxx)
    ///   - values: Values to write
    func writeMultipleRegisters(startAddress: UInt16, values: [UInt16]) async throws {
        guard let connection else {
            logger.error("Write multiple failed: no connection object")
            throw ModbusError.notConnected
        }

        guard isConnected else {
            logger.error("Write multiple failed: isConnected is false")
            throw ModbusError.notConnected
        }

        // Verify connection is still ready
        guard connection.state == .ready else {
            logger.error("Write multiple failed: connection not ready (state: \(String(describing: connection.state)))")
            isConnected = false
            throw ModbusError.notConnected
        }

        transactionId &+= 1
        let currentTxn = transactionId

        logger.info("Writing \(values.count) registers starting at \(startAddress) [txn:\(currentTxn)]")

        let pdu = ModbusProtocol.buildWriteMultipleRequest(startAddress: startAddress, values: values)
        let header = ModbusProtocol.buildMBAPHeader(transactionId: currentTxn, pduLength: pdu.count, unitId: slaveId)
        let request = header + pdu

        _ = try await sendAndReceive(connection: connection, data: request)

        lastCommunication = Date()
        logger.info("Write multiple successful")
    }

    // MARK: - Private Helpers

    private func sendAndReceive(connection: NWConnection, data: Data) async throws -> Data {
        // Send request
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { [logger] error in
                if let error {
                    logger.error("Send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: ModbusError.sendFailed(error))
                } else {
                    logger.debug("Send completed successfully")
                    continuation.resume()
                }
            })
        }

        // Receive response with timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.receiveResponse(connection: connection)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(self.timeout))
                throw ModbusError.timeout
            }

            guard let result = try await group.next() else {
                throw ModbusError.invalidResponse
            }
            group.cancelAll()
            return result
        }
    }

    private func receiveResponse(connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { [logger] continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { content, _, isComplete, error in
                if let error {
                    logger.error("Receive failed: \(error.localizedDescription)")
                    continuation.resume(throwing: ModbusError.receiveFailed(error))
                } else if isComplete && content == nil {
                    // EOF - connection closed by remote
                    logger.warning("Connection closed by remote (EOF)")
                    continuation.resume(throwing: ModbusError.connectionClosed)
                } else if let data = content {
                    logger.debug("Received \(data.count) bytes")
                    continuation.resume(returning: data)
                } else {
                    logger.warning("Receive returned nil content without error")
                    continuation.resume(throwing: ModbusError.invalidResponse)
                }
            }
        }
    }
}
