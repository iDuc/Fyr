import WidgetKit

/// Timeline provider for the fireplace widget.
///
/// The widget never talks to the bridge (it has a single connection slot);
/// it shows the snapshot the app saves in the app group after every status
/// fetch. A snapshot older than `FireplaceSnapshot.freshness` is shown as
/// "not connected" instead of as live state.
struct FireplaceTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> FireplaceEntry {
        FireplaceEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FireplaceEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FireplaceEntry>) -> Void) {
        let now = Date.now
        var entries = [Self.currentEntry(at: now)]

        // Switch to "not connected" once the snapshot goes stale.
        if let snapshot = FireplaceSnapshot.load(), snapshot.isFresh(at: now) {
            let staleDate = snapshot.timestamp.addingTimeInterval(FireplaceSnapshot.freshness)
            entries.append(Self.entry(for: snapshot, at: staleDate))
        }

        // The app reloads the timeline after every status fetch; this is a fallback.
        let nextUpdate = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    // MARK: - Entries

    static func currentEntry(at date: Date) -> FireplaceEntry {
        guard let snapshot = FireplaceSnapshot.load() else { return .disconnected }
        return entry(for: snapshot, at: date)
    }

    static func entry(for snapshot: FireplaceSnapshot, at date: Date) -> FireplaceEntry {
        FireplaceEntry(
            date: date,
            isOn: snapshot.isOn,
            flameHeight: snapshot.lastSetFlameHeight ?? 0,
            temperature: snapshot.currentTemperature ?? 0,
            ecoModeActive: snapshot.ecoModeActive,
            isConnected: snapshot.isFresh(at: date),
            updatedAt: snapshot.timestamp,
            flameHeightIsKnown: snapshot.lastSetFlameHeight != nil
        )
    }
}
