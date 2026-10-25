import Foundation

/// Code shared between the app and the widget extension.
/// Compiled into both targets (see the `Shared` synchronized group in the project).
nonisolated enum FyrAppGroup {
    /// App group used to share settings and the last known status with the widget.
    static let identifier = "group.com.vanYperen.Fyr"

    /// Kind of the home screen widget, used to reload its timelines.
    static let widgetKind = "FyrWidget"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Last known fireplace state, persisted in the app group so the widget (and a
/// relaunched app) can show it together with its age.
nonisolated struct FireplaceSnapshot: Codable, Equatable, Sendable {
    var isOn: Bool
    var ecoModeActive: Bool
    /// Last flame height *set by Fyr* (0-100 %). Register 40201 is write-only,
    /// so this is not a measured value.
    var lastSetFlameHeight: Int?
    var currentTemperature: Double?
    var errorCode: UInt16?
    /// When the bridge last confirmed this state.
    var timestamp: Date

    static let storageKey = "fireplaceSnapshot.v2"

    /// Status older than this is shown as stale instead of live.
    static let freshness: TimeInterval = 15 * 60

    func isFresh(at date: Date = .now) -> Bool {
        date.timeIntervalSince(timestamp) < Self.freshness
    }

    static func load(from defaults: UserDefaults = FyrAppGroup.defaults) -> FireplaceSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(FireplaceSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults = FyrAppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
