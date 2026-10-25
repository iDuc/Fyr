import Foundation
import os
import WidgetKit

/// How a request to light the fire was authorized.
///
/// Turning the fire *off* never needs one. Turning it *on* requires a value of
/// this type, so every caller has to state where ignition came from. Phase 2
/// (safety policy): Siri, Control Center and widgets may only create
/// `.confirmedIntent` after the device is unlocked and the user confirmed.
nonisolated enum IgnitionAuthorization: Sendable, Equatable {
    /// The user completed the swipe-to-ignite slider in the app.
    case appSlider
    /// An App Intent that required an unlocked device and asked for confirmation.
    case confirmedIntent
    /// Fyr v1 behaviour: Siri/Shortcuts ignite without confirmation.
    /// Temporary; phase 2 removes this case.
    case unconfirmedIntent
}

/// Stores the last flame height Fyr set. Register 40201 is write-only, so this
/// is the only record of it; it survives app restarts.
nonisolated protocol FlameHeightStore: Sendable {
    func load() -> Int?
    func save(_ height: Int)
}

nonisolated struct AppGroupFlameHeightStore: FlameHeightStore {
    static let key = "lastSetFlameHeight"

    func load() -> Int? {
        FyrAppGroup.defaults.object(forKey: Self.key) as? Int
    }

    func save(_ height: Int) {
        FyrAppGroup.defaults.set(height, forKey: Self.key)
    }
}

/// Controls one DRU fireplace through its Modbus TCP bridge.
///
/// This actor is the only owner of the bridge connection:
/// - every request goes through one FIFO gate (connect, rate limit check and
///   request are one atomic step, so a reconnect can never interleave with a
///   command and rate limits cannot be bypassed by concurrent callers);
/// - failed connects back off exponentially for automatic polling;
/// - the connection is released after `idleTimeout` without requests, and on
///   `releaseConnection()` (app background, end of an App Intent), because the
///   bridge accepts only one connection and the DRU app must be able to connect.
actor DRUFireplaceService {

    static let shared = DRUFireplaceService()

    nonisolated struct Configuration: Sendable {
        var unitId: UInt8 = DRUConstants.fireplaceUnitId
        var addressing: DRUAddressing = .default
        var client = ModbusTCPClient.Configuration()
        var rateLimits: RateLimiter.Intervals = .production
        /// Close the connection after this long without requests.
        var idleTimeout: Duration = .seconds(30)
        /// Pause between the individual register reads of one status fetch.
        var registerReadGap: Duration = .milliseconds(100)
        /// Reconnect backoff for automatic polling: base * 2^(failures-1), capped.
        var reconnectBackoffBase: Duration = .seconds(2)
        var reconnectBackoffMax: Duration = .seconds(60)
    }

    typealias TransportFactory = @Sendable (BridgeEndpoint) -> any BridgeTransport

    /// Whether a request may wait for the reconnect backoff to expire.
    nonisolated enum Priority: Sendable {
        /// Something the user just asked for: always try to connect.
        case userInitiated
        /// Background polling: respect the reconnect backoff.
        case automatic
    }

    // MARK: - State

    private var configuration: Configuration
    private let makeTransport: TransportFactory
    private let flameHeightStore: FlameHeightStore
    private let statusSink: @Sendable (FireplaceStatus, Int?) -> Void
    private let rateLimiter: RateLimiter
    private let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "DRUService")
    private let clock = ContinuousClock()

    private(set) var endpoint: BridgeEndpoint?
    private var client: ModbusTCPClient?

    private var gateHeld = false
    /// FIFO per priority: user commands (e.g. turn off) go before queued polls.
    private var gateWaiters: [GateWaiter] = []

    private struct GateWaiter {
        let priority: Priority
        let continuation: CheckedContinuation<Void, Never>
    }

    private var consecutiveConnectFailures = 0
    private var reconnectNotBefore: ContinuousClock.Instant?
    private var lastConnectError: BridgeError?

    private var idleTask: Task<Void, Never>?
    private var activityGeneration = 0

    /// Incremented by every flame height request; older pending requests yield.
    private var flameHeightGeneration = 0

    /// Last flame height set by Fyr (persisted), nil if never set.
    private(set) var lastSetFlameHeight: Int?

    // MARK: - Init

    init(
        configuration: Configuration = .init(),
        flameHeightStore: FlameHeightStore = AppGroupFlameHeightStore(),
        statusSink: @escaping @Sendable (FireplaceStatus, Int?) -> Void = DRUFireplaceService.saveSnapshot,
        makeTransport: @escaping TransportFactory = { NWBridgeTransport(endpoint: $0) }
    ) {
        self.configuration = configuration
        self.flameHeightStore = flameHeightStore
        self.statusSink = statusSink
        self.makeTransport = makeTransport
        self.rateLimiter = RateLimiter(intervals: configuration.rateLimits)
        self.lastSetFlameHeight = flameHeightStore.load()
    }

    // MARK: - Configuration & connection

    /// Point the service at a bridge. Drops the current connection if the
    /// address or Modbus settings change.
    func configure(endpoint: BridgeEndpoint, unitId: UInt8? = nil, addressing: DRUAddressing? = nil) async {
        let newUnitId = unitId ?? configuration.unitId
        let newAddressing = addressing ?? configuration.addressing
        guard endpoint != self.endpoint || newUnitId != configuration.unitId || newAddressing != configuration.addressing else {
            return
        }
        // Swap under the gate, so no queued request can connect to the old bridge meanwhile.
        await enterGate(priority: .userInitiated)
        defer { leaveGate() }
        guard endpoint != self.endpoint || newUnitId != configuration.unitId || newAddressing != configuration.addressing else {
            return
        }
        await closeClient()
        self.endpoint = endpoint
        configuration.unitId = newUnitId
        configuration.addressing = newAddressing
        client = nil
        consecutiveConnectFailures = 0
        reconnectNotBefore = nil
        logger.info("Configured bridge \(endpoint.description), unit \(newUnitId), addressing \(newAddressing.rawValue)")
    }

    /// Configure from the saved settings (bridge address, unit id, addressing).
    /// Throws `BridgeError.notConfigured` when no bridge has been set up.
    func configureFromSettings() async throws(BridgeError) {
        guard let endpoint = SettingsStore.bridgeEndpointValue else { throw .notConfigured }
        await configure(endpoint: endpoint, unitId: SettingsStore.modbusUnitIdValue, addressing: SettingsStore.addressingValue)
    }

    /// Whether a connection is currently open.
    var isConnected: Bool {
        get async {
            guard let client else { return false }
            return await client.isConnected
        }
    }

    /// Close the bridge connection now so other apps can connect. Waits for an
    /// in-flight request. The next request reconnects automatically.
    func releaseConnection() async {
        idleTask?.cancel()
        idleTask = nil
        await enterGate(priority: .userInitiated)
        defer { leaveGate() }
        await closeClient()
    }

    // MARK: - Commands

    /// Light the fire. Requires an authorization, see `IgnitionAuthorization`.
    func turnOn(authorization: IgnitionAuthorization) async throws(BridgeError) {
        logger.info("Turn on (\(String(describing: authorization)))")
        try await writeAction(.mainBurnerOn)
    }

    /// Turn the fire off. Always allowed.
    func turnOff() async throws(BridgeError) {
        logger.info("Turn off")
        try await writeAction(.fireplaceOff)
    }

    /// Enable or disable wave (eco) mode.
    func setWaveMode(enabled: Bool) async throws(BridgeError) {
        try await writeAction(enabled ? .waveModeOn : .waveModeOff)
    }

    /// Set the flame height (0-100 %). At most one change per 10 s is sent;
    /// while waiting, a newer request replaces an older one ("latest wins").
    /// - Returns: `false` if a newer request superseded this one.
    @discardableResult
    func setFlameHeight(_ height: Int) async throws(BridgeError) -> Bool {
        let clamped = min(DRUConstants.maxFlameHeight, max(DRUConstants.minFlameHeight, height))
        flameHeightGeneration += 1
        let generation = flameHeightGeneration
        let address = configuration.addressing.pduAddress(for: .flameHeightTarget)

        // A retry (after a lost connection) still waits for its own 10 s slot.
        let sent: Void? = try await perform(.flameHeight, priority: .userInitiated, attempts: 2,
                                     shouldProceed: { self.flameHeightGeneration == generation }) { client in
            try await client.writeSingleRegister(address: address, value: UInt16(clamped))
        }
        guard sent != nil else {
            logger.info("Flame height \(clamped) superseded by a newer request")
            return false
        }
        lastSetFlameHeight = clamped
        flameHeightStore.save(clamped)
        return true
    }

    /// Set the thermostat setpoint in °C.
    func setThermostatSetpoint(_ temperature: Double) async throws(BridgeError) {
        let clamped = min(DRUConstants.maxTemperature, max(DRUConstants.minTemperature, temperature))
        let value = UInt16((clamped * DRUConstants.temperatureScaleFactor).rounded())
        try await writeRegister(.thermostatSetpoint, value: value)
    }

    /// Set the wave interval in seconds (1-60).
    func setWaveInterval(_ seconds: Int) async throws(BridgeError) {
        let clamped = min(DRUConstants.maxWaveInterval, max(DRUConstants.minWaveInterval, seconds))
        try await writeRegister(.waveInterval, value: UInt16(clamped))
    }

    /// Time until a flame height change is allowed.
    func flameHeightCooldown() async -> Duration {
        await rateLimiter.remaining(.flameHeight)
    }

    // MARK: - Status

    /// Read the status registers.
    func fetchStatus(priority: Priority = .userInitiated) async throws(BridgeError) -> FireplaceStatus {
        let addressing = configuration.addressing
        let gap = configuration.registerReadGap
        let registers: [DRURegister] = [.status, .errorCode, .rssiGateway, .rssiFireplace, .temperature]

        // The DRU bridge is read one register at a time (as Fyr v1 and Node-RED do).
        // The 3 s read limit applies to the whole status fetch.
        let values = try await perform(.read, priority: priority, attempts: 2) { client in
            var values: [DRURegister: UInt16] = [:]
            for (index, register) in registers.enumerated() {
                if index > 0 { try await Task.sleep(for: gap) }
                let result = try await client.readHoldingRegisters(address: addressing.pduAddress(for: register), count: 1)
                values[register] = result[0]
            }
            return values
        }!

        let status = FireplaceStatus(registers: values, lastSetFlameHeight: lastSetFlameHeight)
        statusSink(status, lastSetFlameHeight)
        return status
    }

    // MARK: - Private: requests

    private func writeAction(_ action: DRUAction) async throws(BridgeError) {
        try await writeRegister(.action, value: action.rawValue)
    }

    private func writeRegister(_ register: DRURegister, value: UInt16) async throws(BridgeError) {
        let address = configuration.addressing.pduAddress(for: register)
        // Commands are idempotent (absolute values), so one retry after a lost
        // connection is safe; it still waits for its own rate-limit slot.
        _ = try await perform(.write, priority: .userInitiated, attempts: 2) { client in
            try await client.writeSingleRegister(address: address, value: value)
        }
    }

    /// Run one bridge request: gate -> connect -> rate-limit slot -> request.
    /// - Parameter shouldProceed: checked before every attempt; returning false
    ///   abandons the request (used to coalesce flame height changes).
    /// - Returns: The result, or nil if `shouldProceed` returned false.
    private func perform<T: Sendable>(
        _ kind: RateLimiter.Kind,
        priority: Priority,
        attempts: Int,
        shouldProceed: () -> Bool = { true },
        _ request: @escaping @Sendable (ModbusTCPClient) async throws -> T
    ) async throws(BridgeError) -> T? {
        defer { scheduleIdleRelease() }
        var attempt = 0

        while true {
            guard shouldProceed() else { return nil }

            await enterGate(priority: priority)
            guard shouldProceed() else { leaveGate(); return nil }

            let client: ModbusTCPClient
            do {
                client = try await connectedClient(priority: priority)
            } catch {
                leaveGate()
                throw error
            }

            // Connecting may have taken a while; a newer flame request may exist now.
            guard shouldProceed() else { leaveGate(); return nil }

            // Check the slot only now, right before sending, while holding the gate.
            if let wait = await rateLimiter.tryAcquire(kind) {
                leaveGate()
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    throw .cancelled
                }
                continue
            }

            attempt += 1
            do {
                let result = try await request(client)
                leaveGate()
                return result
            } catch {
                let modbusError = (error as? ModbusError) ?? .connectionClosed
                if modbusError.invalidatesConnection {
                    await closeClient()
                }
                leaveGate()

                if error is CancellationError || Task.isCancelled {
                    throw .cancelled
                }
                let bridgeError = BridgeError(modbusError)
                let retryable = bridgeError == .connectionLost || bridgeError == .deviceBusy || bridgeError == .noResponse
                guard retryable, attempt < attempts else {
                    logger.error("Request failed: \(modbusError.description)")
                    throw bridgeError
                }
                logger.info("Retrying after \(modbusError.description)")
            }
        }
    }

    /// Returns a connected client. Call while holding the gate.
    private func connectedClient(priority: Priority) async throws(BridgeError) -> ModbusTCPClient {
        guard let endpoint else { throw .notConfigured }
        if let client, await client.isConnected { return client }

        if priority == .automatic, let notBefore = reconnectNotBefore, clock.now < notBefore {
            throw lastConnectError ?? .unreachable
        }

        let client = self.client ?? ModbusTCPClient(
            unitId: configuration.unitId,
            configuration: configuration.client,
            makeTransport: { [makeTransport] in makeTransport(endpoint) }
        )
        self.client = client
        do {
            try await client.connect()
            consecutiveConnectFailures = 0
            reconnectNotBefore = nil
            lastConnectError = nil
            return client
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw .cancelled
            }
            let bridgeError = BridgeError((error as? ModbusError) ?? .connectFailed(.other(error.localizedDescription)))
            consecutiveConnectFailures += 1
            let backoff = min(
                configuration.reconnectBackoffMax,
                configuration.reconnectBackoffBase * (1 << min(consecutiveConnectFailures - 1, 10))
            )
            reconnectNotBefore = clock.now + backoff
            lastConnectError = bridgeError
            logger.error("Connect failed (\(self.consecutiveConnectFailures)x): \(String(describing: bridgeError)); backoff \(backoff)")
            throw bridgeError
        }
    }

    private func closeClient() async {
        guard let client else { return }
        await client.disconnect()
    }

    // MARK: - Private: idle release

    private func scheduleIdleRelease() {
        activityGeneration += 1
        let generation = activityGeneration
        let timeout = configuration.idleTimeout
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.releaseIfIdle(generation: generation)
        }
    }

    private func releaseIfIdle(generation: Int) async {
        guard generation == activityGeneration, !gateHeld else { return }
        logger.info("Idle: releasing bridge connection")
        await enterGate(priority: .automatic)
        defer { leaveGate() }
        if generation == activityGeneration {
            await closeClient()
        }
    }

    // MARK: - Private: gate

    private func enterGate(priority: Priority) async {
        if !gateHeld {
            gateHeld = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enqueueGateWaiter(priority: priority, continuation: continuation)
        }
        // Ownership is handed over by `leaveGate`; `gateHeld` stays true.
    }

    private func enqueueGateWaiter(priority: Priority, continuation: CheckedContinuation<Void, Never>) {
        let waiter = GateWaiter(priority: priority, continuation: continuation)
        if priority == .userInitiated, let firstAutomatic = gateWaiters.firstIndex(where: { $0.priority == .automatic }) {
            gateWaiters.insert(waiter, at: firstAutomatic)
        } else {
            gateWaiters.append(waiter)
        }
    }

    private func leaveGate() {
        if gateWaiters.isEmpty {
            gateHeld = false
        } else {
            gateWaiters.removeFirst().continuation.resume()
        }
    }

    // MARK: - Default status sink

    /// Persist the status for the widget and a relaunched app, then reload widgets.
    static let saveSnapshot: @Sendable (FireplaceStatus, Int?) -> Void = { status, lastSetFlameHeight in
        FireplaceSnapshot(
            isOn: status.isOn,
            ecoModeActive: status.ecoModeActive,
            lastSetFlameHeight: lastSetFlameHeight,
            currentTemperature: status.currentTemperature,
            errorCode: status.rawErrorCode == 0 ? nil : status.rawErrorCode,
            timestamp: .now
        ).save()
        WidgetCenter.shared.reloadTimelines(ofKind: FyrAppGroup.widgetKind)
    }
}
