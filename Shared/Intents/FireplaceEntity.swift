import AppIntents
import Foundation

/// The fireplace as an App Intents entity, for Siri, Shortcuts and Spotlight.
///
/// Fyr controls one fireplace, so there is one entity. Its values come from
/// the last status the bridge reported (the app-group snapshot): building an
/// entity never connects to the bridge. `GetFireplaceStatusIntent` reads the
/// bridge first and returns a fresh entity.
struct FireplaceEntity: AppEntity {

    static let defaultID = "fireplace"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fireplace"

    static let defaultQuery = FireplaceEntityQuery()

    let id: String

    @Property(title: "On")
    var isOn: Bool

    @Property(title: "Wave Mode")
    var waveModeActive: Bool

    @Property(title: "Room Temperature")
    var temperature: Measurement<UnitTemperature>?

    /// Last flame height set by Fyr; the bridge does not report the real one.
    @Property(title: "Last Set Flame Height")
    var lastSetFlameHeight: Int?

    @Property(title: "Last Updated")
    var lastUpdated: Date?

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = if !isOn {
            "Off"
        } else if waveModeActive {
            "On, wave mode"
        } else {
            "On"
        }
        return DisplayRepresentation(
            title: "Fireplace",
            subtitle: subtitle,
            image: .init(systemName: isOn ? "flame.fill" : "flame")
        )
    }

    init(isOn: Bool, waveModeActive: Bool, temperature: Double?, lastSetFlameHeight: Int?, lastUpdated: Date?) {
        id = Self.defaultID
        self.isOn = isOn
        self.waveModeActive = waveModeActive
        self.temperature = temperature.map { Measurement(value: $0, unit: .celsius) }
        self.lastSetFlameHeight = lastSetFlameHeight
        self.lastUpdated = lastUpdated
    }

    /// From the last known status. Without one, the fireplace shows as off.
    init(snapshot: FireplaceSnapshot?) {
        self.init(
            isOn: snapshot?.isOn ?? false,
            waveModeActive: snapshot?.ecoModeActive ?? false,
            temperature: snapshot?.currentTemperature,
            lastSetFlameHeight: snapshot?.lastSetFlameHeight,
            lastUpdated: snapshot?.timestamp
        )
    }

    /// From a status just read from the bridge.
    init(status: FireplaceStatus, at date: Date = .now) {
        self.init(
            isOn: status.isOn,
            waveModeActive: status.ecoModeActive,
            temperature: status.currentTemperature,
            lastSetFlameHeight: status.flameHeightIsKnown ? status.flameHeight : nil,
            lastUpdated: date
        )
    }
}

/// Finds the fireplace. Only offers it once a bridge has been set up.
struct FireplaceEntityQuery: EntityQuery {

    func entities(for identifiers: [FireplaceEntity.ID]) async throws -> [FireplaceEntity] {
        guard identifiers.contains(FireplaceEntity.defaultID), let entity = Self.current() else { return [] }
        return [entity]
    }

    func suggestedEntities() async throws -> [FireplaceEntity] {
        Self.current().map { [$0] } ?? []
    }

    func defaultResult() async -> FireplaceEntity? {
        Self.current()
    }

    /// The configured fireplace with its last known status, nil before setup.
    static func current() -> FireplaceEntity? {
        guard SettingsStore.bridgeIPValue != nil else { return nil }
        return FireplaceEntity(snapshot: FireplaceSnapshot.load())
    }
}
