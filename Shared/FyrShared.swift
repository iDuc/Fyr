import Foundation

/// Code shared between the app and the widget extension.
/// Compiled into both targets (see the `Shared` synchronized group in the project).
nonisolated enum FyrAppGroup {
    /// App group used to share settings and the last known status with the widget.
    static let identifier = "group.com.vanYperen.Fyr"

    /// Kind of the home screen and Lock Screen widget, used to reload its timelines.
    static let widgetKind = "FyrWidget"

    /// Kinds of the Control Center / Lock Screen controls.
    enum ControlKind {
        static let turnOff = "com.vanYperen.Fyr.control.turnOff"
        static let turnOn = "com.vanYperen.Fyr.control.turnOn"
        static let waveMode = "com.vanYperen.Fyr.control.waveMode"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Last known fireplace state, persisted in the app group so the widgets,
/// controls, Live Activity and a relaunched app can show it together with its age.
nonisolated struct FireplaceSnapshot: Codable, Equatable, Sendable {
    var isOn: Bool
    var ecoModeActive: Bool
    /// Last flame height *set by Fyr* (0-100 %). Register 40201 is write-only,
    /// so this is not a measured value.
    var lastSetFlameHeight: Int?
    var currentTemperature: Double?
    var errorCode: UInt16?
    /// When the bridge last confirmed this state (a status read, or a command
    /// the bridge accepted).
    var timestamp: Date
    /// When Fyr saw the fire go from off to on. Nil when the fire is off, or
    /// when it was already burning the first time Fyr looked.
    var burningSince: Date?

    static let storageKey = "fireplaceSnapshot.v3"

    /// Status older than this is shown as stale instead of live.
    static let freshness: TimeInterval = 15 * 60

    func isFresh(at date: Date = .now) -> Bool {
        date.timeIntervalSince(timestamp) < Self.freshness
    }

    /// When this state stops being trustworthy.
    var staleDate: Date {
        timestamp.addingTimeInterval(Self.freshness)
    }

    static func load(from defaults: UserDefaults = FyrAppGroup.defaults) -> FireplaceSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(FireplaceSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults = FyrAppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// The state after a status read, keeping track of when the fire was lit.
    static func confirmed(
        isOn: Bool,
        ecoModeActive: Bool,
        lastSetFlameHeight: Int?,
        currentTemperature: Double?,
        errorCode: UInt16?,
        previous: FireplaceSnapshot?,
        at date: Date = .now
    ) -> FireplaceSnapshot {
        FireplaceSnapshot(
            isOn: isOn,
            ecoModeActive: isOn && ecoModeActive,
            lastSetFlameHeight: lastSetFlameHeight,
            currentTemperature: currentTemperature,
            errorCode: errorCode,
            timestamp: date,
            burningSince: Self.burningSince(isOn: isOn, previous: previous, at: date)
        )
    }

    /// The state right after the bridge accepted `command`, before the next
    /// status read confirms it. Off is certain; "on" is what was asked for.
    func applying(_ command: FireplaceCommand, at date: Date = .now) -> FireplaceSnapshot {
        var next = self
        switch command {
        case .turnOn:
            next.isOn = true
        case .turnOff:
            next.isOn = false
            next.ecoModeActive = false
        case .setWaveMode(false):
            next.ecoModeActive = false
        case .setWaveMode(true):
            // The service only sends this after reading that the fire burns.
            next.isOn = true
            next.ecoModeActive = true
        case .setFlameHeight(let height):
            next.isOn = true
            next.lastSetFlameHeight = height
        case .setTemperature, .setWaveInterval:
            next.isOn = true
        }
        next.timestamp = date
        next.burningSince = Self.burningSince(isOn: next.isOn, previous: self, at: date)
        return next
    }

    /// A first snapshot for a command when nothing is known yet.
    static func unknown(at date: Date = .now) -> FireplaceSnapshot {
        FireplaceSnapshot(isOn: false, ecoModeActive: false, timestamp: date)
    }

    private static func burningSince(isOn: Bool, previous: FireplaceSnapshot?, at date: Date) -> Date? {
        guard isOn else { return nil }
        // An old snapshot says nothing about when this fire was lit.
        guard let previous, previous.isFresh(at: date) else { return nil }
        return previous.isOn ? previous.burningSince : date
    }
}
