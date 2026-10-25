import WidgetKit

/// One moment of the fireplace widget: the last known state and how old it is.
struct FireplaceEntry: TimelineEntry {
    let date: Date
    /// Nil before Fyr has ever read the fireplace.
    let snapshot: FireplaceSnapshot?
    /// Whether a bridge has been set up in the app.
    var isConfigured = true

    var isOn: Bool { snapshot?.isOn ?? false }
    var waveMode: Bool { snapshot?.ecoModeActive ?? false }
    var flameHeight: Int { snapshot?.lastSetFlameHeight ?? DRUConstants.defaultFlameHeight }
    var temperature: Double? { snapshot?.currentTemperature }
    var burningSince: Date? { snapshot?.burningSince }
    var updatedAt: Date? { snapshot?.timestamp }

    /// Whether the state is recent enough to show as current.
    var isFresh: Bool { snapshot?.isFresh(at: date) ?? false }

    /// Turning off is always safe, so offer it unless Fyr knows for sure the
    /// fire is off (it may have been lit with the remote meanwhile).
    var offersTurnOff: Bool { isConfigured && snapshot != nil && (isOn || !isFresh) }

    static let placeholder = FireplaceEntry(
        date: .now,
        snapshot: FireplaceSnapshot(
            isOn: true, ecoModeActive: true, lastSetFlameHeight: 70, currentTemperature: 21.5,
            timestamp: .now, burningSince: .now.addingTimeInterval(-3600)
        )
    )

    static func current(at date: Date = .now) -> FireplaceEntry {
        FireplaceEntry(date: date, snapshot: FireplaceSnapshot.load(), isConfigured: SettingsStore.bridgeIPValue != nil)
    }
}

/// Timeline provider for the fireplace widgets.
///
/// The widgets never talk to the bridge (it has a single connection slot).
/// They show the snapshot Fyr saves after every status read and every command
/// (`FyrSurfaces`), which also reloads them. A snapshot older than
/// `FireplaceSnapshot.freshness` is shown as "last known" instead of as live.
struct FireplaceTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> FireplaceEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FireplaceEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FireplaceEntry>) -> Void) {
        let now = Date.now
        let entry = FireplaceEntry.current(at: now)
        var entries = [entry]

        // Switch to "last known" once the snapshot goes stale.
        if let snapshot = entry.snapshot, snapshot.isFresh(at: now) {
            entries.append(FireplaceEntry(date: snapshot.staleDate, snapshot: snapshot, isConfigured: entry.isConfigured))
        }

        // Fyr reloads the timeline whenever it learns something; this is a fallback.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }
}
