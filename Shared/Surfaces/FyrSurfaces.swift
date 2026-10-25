import Foundation
import WidgetKit

/// Publishes the fireplace state to everything outside the open app: the
/// app-group snapshot, the Home Screen / Lock Screen / StandBy widgets, the
/// Control Center controls and the Live Activity.
///
/// None of those surfaces talk to the bridge (it accepts one connection);
/// they only show what Fyr last saw or sent.
nonisolated enum FyrSurfaces {

    /// Reload widgets and controls at most this often when nothing visible
    /// changed (the app polls every 15 s while open).
    static let quietRefreshInterval: TimeInterval = 5 * 60

    /// Save `snapshot` and refresh the surfaces that show it.
    static func publish(_ snapshot: FireplaceSnapshot, previous: FireplaceSnapshot? = FireplaceSnapshot.load()) async {
        snapshot.save()
        let defaults = FyrAppGroup.defaults
        let lastPublished = defaults.object(forKey: lastPublishedKey) as? Date
        guard needsRefresh(snapshot, previous: previous, lastPublished: lastPublished) else { return }
        defaults.set(snapshot.timestamp, forKey: lastPublishedKey)
        reloadAll()
        await FireLiveActivity.update(for: snapshot)
    }

    /// When the surfaces were last refreshed (app group).
    static let lastPublishedKey = "surfacesPublishedAt"

    /// Redraw widgets and controls from the saved snapshot.
    static func reloadAll() {
        WidgetCenter.shared.reloadTimelines(ofKind: FyrAppGroup.widgetKind)
        ControlCenter.shared.reloadAllControls()
    }

    /// Whether something the surfaces show changed, or the last refresh is old
    /// enough that the "last updated" time and stale date should move on.
    static func needsRefresh(_ snapshot: FireplaceSnapshot, previous: FireplaceSnapshot?, lastPublished: Date?) -> Bool {
        guard let previous, let lastPublished else { return true }
        if snapshot.isOn != previous.isOn
            || snapshot.ecoModeActive != previous.ecoModeActive
            || snapshot.lastSetFlameHeight != previous.lastSetFlameHeight
            || snapshot.errorCode != previous.errorCode
            || snapshot.burningSince != previous.burningSince {
            return true
        }
        if let new = snapshot.currentTemperature, let old = previous.currentTemperature, abs(new - old) >= 0.5 {
            return true
        }
        // Keep the "last updated" time and the stale date moving while the
        // state stays the same (polls every 15 s would never get here otherwise).
        return snapshot.timestamp.timeIntervalSince(lastPublished) >= quietRefreshInterval
            || !previous.isFresh(at: snapshot.timestamp)
    }

    // MARK: - Service sinks

    /// `DRUFireplaceService` status sink: a status read from the bridge.
    static let statusRead: @Sendable (FireplaceStatus, Int?) async -> Void = { status, lastSetFlameHeight in
        let previous = FireplaceSnapshot.load()
        let snapshot = FireplaceSnapshot.confirmed(
            isOn: status.isOn,
            ecoModeActive: status.ecoModeActive,
            lastSetFlameHeight: lastSetFlameHeight,
            currentTemperature: status.currentTemperature,
            errorCode: status.rawErrorCode == 0 ? nil : status.rawErrorCode,
            previous: previous
        )
        await publish(snapshot, previous: previous)
    }

    /// `DRUFireplaceService` command sink: the bridge accepted a command.
    static let commandAccepted: @Sendable (FireplaceCommand) async -> Void = { command in
        let previous = FireplaceSnapshot.load()
        let snapshot = (previous ?? .unknown()).applying(command)
        await publish(snapshot, previous: previous)
    }
}
