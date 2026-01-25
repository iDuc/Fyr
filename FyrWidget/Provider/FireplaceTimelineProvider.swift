import WidgetKit

/// Timeline provider for fireplace widget
struct FireplaceTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> FireplaceEntry {
        FireplaceEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FireplaceEntry) -> Void) {
        // Return cached data for quick preview
        if let cached = loadCachedStatus() {
            completion(cached)
        } else {
            completion(FireplaceEntry.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FireplaceEntry>) -> Void) {
        Task {
            let entry = await fetchCurrentStatus()

            // Refresh every 15 minutes (widget budget constraints)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    // MARK: - Private Methods

    private func fetchCurrentStatus() async -> FireplaceEntry {
        // Try to use App Group UserDefaults for cached data
        guard let defaults = UserDefaults(suiteName: "group.com.fyr.app"),
              let data = defaults.dictionary(forKey: "lastKnownStatus") else {
            return FireplaceEntry.disconnected
        }

        return FireplaceEntry(
            date: Date(),
            isOn: data["isOn"] as? Bool ?? false,
            flameHeight: data["flameHeight"] as? Int ?? 0,
            temperature: data["currentTemperature"] as? Double ?? 0,
            ecoModeActive: data["ecoModeActive"] as? Bool ?? false,
            isConnected: true
        )
    }

    private func loadCachedStatus() -> FireplaceEntry? {
        guard let defaults = UserDefaults(suiteName: "group.com.fyr.app"),
              let data = defaults.dictionary(forKey: "lastKnownStatus") else {
            return nil
        }

        return FireplaceEntry(
            date: Date(),
            isOn: data["isOn"] as? Bool ?? false,
            flameHeight: data["flameHeight"] as? Int ?? 0,
            temperature: data["currentTemperature"] as? Double ?? 0,
            ecoModeActive: data["ecoModeActive"] as? Bool ?? false,
            isConnected: true
        )
    }
}
