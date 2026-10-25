import Foundation
import os

/// Modbus TCP client for one unit on one bridge.
///
/// - Requests are serialized: one request is in flight at a time, in FIFO order.
/// - Responses are framed properly: exactly 7 MBAP header bytes, then exactly
///   `length - 1` PDU bytes, however TCP splits or coalesces segments.
/// - The transaction id of every response is checked; stale replies are discarded.
/// - Timeouts are real: on timeout the connection is closed, which unblocks the
///   pending receive, and the next request opens a fresh connection (so a late
///   reply can never be mistaken for the answer to a later request).
///
/// Reconnect policy, rate limiting and idle release live in `DRUFireplaceService`.
actor ModbusTCPClient {

    nonisolated struct Configuration: Sendable {
        var connectTimeout: Duration = .seconds(5)
        var requestTimeout: Duration = .seconds(5)
        /// The DRU bridge needs time after the TCP handshake before it answers.
        var postConnectDelay: Duration = .milliseconds(1500)
        /// Stale frames (wrong transaction id) to skip before giving up.
        var maxStaleFrames = 4
    }

    typealias TransportFactory = @Sendable () -> any BridgeTransport

    let unitId: UInt8
    private let configuration: Configuration
    private let makeTransport: TransportFactory
    private let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "ModbusTCP")

    private var transport: (any BridgeTransport)?
    private var transactionId: UInt16 = 0

    // FIFO request gate (actor methods are re-entrant at every `await`).
    private var gateHeld = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    init(unitId: UInt8, configuration: Configuration = .init(), makeTransport: @escaping TransportFactory) {
        self.unitId = unitId
        self.configuration = configuration
        self.makeTransport = makeTransport
    }

    // MARK: - Connection

    var isConnected: Bool {
        transport?.isOpen ?? false
    }

    /// Open the connection if it is not open yet.
    func connect() async throws {
        await enterGate()
        defer { leaveGate() }
        _ = try await openTransportIfNeeded()
    }

    /// Close the connection. Waits for an in-flight request to finish first.
    func disconnect() async {
        await enterGate()
        defer { leaveGate() }
        closeTransport()
    }

    // MARK: - Requests

    /// Read Holding Registers (0x03). `address` is the PDU address.
    func readHoldingRegisters(address: UInt16, count: UInt16) async throws -> [UInt16] {
        precondition(count > 0 && count <= ModbusProtocol.maxReadCount)
        let pdu = try await transact(ModbusProtocol.readHoldingRegistersPDU(address: address, count: count))
        return try ModbusProtocol.parseReadHoldingRegisters(pdu: pdu, expectedCount: Int(count))
    }

    /// Write Single Register (0x06). `address` is the PDU address.
    func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        logger.info("Write \(value) to address \(address)")
        let pdu = try await transact(ModbusProtocol.writeSingleRegisterPDU(address: address, value: value))
        try ModbusProtocol.parseWriteSingleRegister(pdu: pdu, address: address, value: value)
    }

    // MARK: - Private

    private func transact(_ requestPDU: [UInt8]) async throws -> [UInt8] {
        await enterGate()
        defer { leaveGate() }
        try Task.checkCancellation()

        let transport = try await openTransportIfNeeded()
        transactionId &+= 1
        let tid = transactionId
        let unitId = unitId
        let maxStale = configuration.maxStaleFrames
        let request = ModbusProtocol.frame(transactionId: tid, unitId: unitId, pdu: requestPDU)
        let logger = logger

        do {
            let pdu = try await withDeadline(configuration.requestTimeout, onTimeout: { transport.close() }) {
                try await transport.send(request)
                for _ in 0...maxStale {
                    let header = try ModbusProtocol.parseHeader(try await transport.receive(exactly: ModbusProtocol.headerLength))
                    let pdu = try await transport.receive(exactly: header.pduLength)
                    guard header.transactionId == tid else {
                        logger.warning("Discarding stale frame (tid \(header.transactionId), expected \(tid))")
                        continue
                    }
                    if header.unitId != unitId {
                        // Transaction id already pairs request and reply; a different
                        // unit id is unusual but not fatal.
                        logger.warning("Response unit id \(header.unitId), expected \(unitId)")
                    }
                    return pdu
                }
                throw ModbusError.invalidFrame("too many stale frames")
            }
            return pdu
        } catch let error as ModbusError {
            logger.error("Request tid \(tid) failed: \(error.description)")
            closeTransport()
            throw error
        } catch {
            // Cancellation or an unexpected error: the stream state is unknown.
            closeTransport()
            throw error
        }
    }

    private func openTransportIfNeeded() async throws -> any BridgeTransport {
        if let transport {
            if transport.isOpen { return transport }
            logger.info("Connection no longer open, reconnecting")
            closeTransport()
        }

        let newTransport = makeTransport()
        do {
            try await withDeadline(configuration.connectTimeout, onTimeout: { newTransport.close() }) {
                try await newTransport.open()
            }
        } catch ModbusError.timeout {
            newTransport.close()
            throw ModbusError.connectFailed(.timedOut)
        } catch {
            newTransport.close()
            throw error
        }

        do {
            try await Task.sleep(for: configuration.postConnectDelay)
        } catch {
            newTransport.close()
            throw error
        }
        logger.info("Connected")
        transport = newTransport
        return newTransport
    }

    private func closeTransport() {
        guard let transport else { return }
        transport.close()
        self.transport = nil
        logger.info("Disconnected")
    }

    private func enterGate() async {
        if !gateHeld {
            gateHeld = true
            return
        }
        await withCheckedContinuation { gateWaiters.append($0) }
        // Ownership is handed over by `leaveGate`; `gateHeld` stays true.
    }

    private func leaveGate() {
        if gateWaiters.isEmpty {
            gateHeld = false
        } else {
            gateWaiters.removeFirst().resume()
        }
    }
}
