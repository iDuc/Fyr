import Foundation

/// Persistent app settings in the shared app group (readable by the widget).
@MainActor
@Observable
final class SettingsStore {

    // MARK: - Singleton

    static let shared = SettingsStore()

    // MARK: - Keys

    nonisolated enum Keys {
        static let bridgeIP = "bridgeIP"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let targetTemperature = "targetTemperature"
        static let modbusUnitId = "modbusUnitId"
        static let modbusAddressing = "modbusAddressing"
    }

    /// Launch argument that points the app at another bridge, e.g. the local
    /// test server in UI tests: `-FyrBridgeEndpoint 127.0.0.1:15020`.
    nonisolated static let endpointOverrideArgument = "FyrBridgeEndpoint"

    // MARK: - Nonisolated accessors (for actors and App Intents)

    nonisolated private static var defaults: UserDefaults { FyrAppGroup.defaults }

    /// Saved bridge IP address (without port).
    nonisolated static var bridgeIPValue: String? {
        defaults.string(forKey: Keys.bridgeIP)
    }

    /// Bridge endpoint: the launch argument override, else the saved IP on port 502.
    nonisolated static var bridgeEndpointValue: BridgeEndpoint? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: endpointOverrideArgument),
           let endpoint = BridgeEndpoint(override) {
            return endpoint
        }
        #endif
        return bridgeIPValue.flatMap { BridgeEndpoint(host: $0, port: DRUConstants.modbusPort) }
    }

    /// Modbus unit id of the fireplace (default 2).
    nonisolated static var modbusUnitIdValue: UInt8 {
        let value = defaults.integer(forKey: Keys.modbusUnitId)
        return (1...247).contains(value) ? UInt8(value) : DRUConstants.fireplaceUnitId
    }

    /// Register addressing convention (default: register numbers, as in Fyr v1).
    nonisolated static var addressingValue: DRUAddressing {
        defaults.string(forKey: Keys.modbusAddressing).flatMap(DRUAddressing.init(rawValue:)) ?? .default
    }

    // MARK: - Properties

    private let store: UserDefaults

    /// Configured bridge IP address
    var bridgeIP: String? {
        didSet { store.set(bridgeIP, forKey: Keys.bridgeIP) }
    }

    /// Whether the user has completed onboarding
    var hasCompletedOnboarding: Bool {
        didSet { store.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Last target thermostat temperature
    var targetTemperature: Double {
        didSet { store.set(targetTemperature, forKey: Keys.targetTemperature) }
    }

    // MARK: - Initialization

    private init() {
        store = FyrAppGroup.defaults
        bridgeIP = store.string(forKey: Keys.bridgeIP)
        hasCompletedOnboarding = store.bool(forKey: Keys.hasCompletedOnboarding)
        let savedTemperature = store.double(forKey: Keys.targetTemperature)
        targetTemperature = savedTemperature == 0 ? 21.0 : savedTemperature

        #if DEBUG
        // UI tests against the local test server skip onboarding.
        if UserDefaults.standard.string(forKey: Self.endpointOverrideArgument) != nil {
            hasCompletedOnboarding = true
        }
        #endif
    }

    /// Save a bridge verified by `DRUDiscovery`, with the addressing convention
    /// it answered to.
    func saveBridge(ip: String, addressing: DRUAddressing) {
        bridgeIP = ip
        store.set(addressing.rawValue, forKey: Keys.modbusAddressing)
    }

    /// Last known status, persisted by `DRUFireplaceService` after every fetch.
    func loadSnapshot() -> FireplaceSnapshot? {
        FireplaceSnapshot.load(from: store)
    }

    // MARK: - Reset

    /// Clear all stored settings
    func reset() {
        bridgeIP = nil
        hasCompletedOnboarding = false
        targetTemperature = 21.0
        for key in [Keys.modbusUnitId, Keys.modbusAddressing, FireplaceSnapshot.storageKey, AppGroupFlameHeightStore.key] {
            store.removeObject(forKey: key)
        }
    }
}
