import ActivityKit
import Foundation
import os

/// The Live Activity shown on the Lock Screen and in the Dynamic Island while
/// the fire burns.
nonisolated struct FireActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable, Sendable {
        var isOn: Bool
        var waveMode: Bool
        var burningSince: Date?
        var temperature: Double?
        var lastSetFlameHeight: Int?
        /// When the bridge last confirmed this state.
        var updatedAt: Date
    }
}

/// Starts, updates and ends the Live Activity.
///
/// Fyr is 100 % local: there is no server, so no push updates. The activity
/// changes only when Fyr itself talks to the bridge: while the app is open
/// (polling), and when a Siri, Shortcuts, widget or control command runs. If
/// the fire is turned off with the remote or the DRU app while Fyr is closed,
/// the activity does not know. It therefore carries a stale date
/// (`FireplaceSnapshot.freshness`) after which it says the state is
/// unconfirmed, and iOS ends it after at most 8 hours.
nonisolated enum FireLiveActivity {

    /// User setting in the app group (default on).
    static let enabledKey = "liveActivityEnabled"

    /// How long the final "off" state stays visible after the fire goes out.
    static let dismissDelay: TimeInterval = 60

    private static let logger = Logger(subsystem: "com.vanYperen.Fyr", category: "LiveActivity")

    static var isEnabled: Bool {
        get { FyrAppGroup.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { FyrAppGroup.defaults.set(newValue, forKey: enabledKey) }
    }

    static func state(for snapshot: FireplaceSnapshot) -> FireActivityAttributes.ContentState {
        FireActivityAttributes.ContentState(
            isOn: snapshot.isOn,
            waveMode: snapshot.ecoModeActive,
            burningSince: snapshot.burningSince,
            temperature: snapshot.currentTemperature,
            lastSetFlameHeight: snapshot.lastSetFlameHeight,
            updatedAt: snapshot.timestamp
        )
    }

    static func content(for snapshot: FireplaceSnapshot) -> ActivityContent<FireActivityAttributes.ContentState> {
        ActivityContent(state: state(for: snapshot), staleDate: snapshot.staleDate, relevanceScore: snapshot.isOn ? 1 : 0)
    }

    /// Bring the activity in line with `snapshot`: start it when the fire
    /// burns (only possible while the app is in the foreground), update it,
    /// or end it when the fire is off.
    static func update(for snapshot: FireplaceSnapshot) async {
        // An activity that was ended stays listed until it is dismissed.
        let activities = Activity<FireActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
        let content = content(for: snapshot)

        guard snapshot.isOn, isEnabled else {
            for activity in activities {
                await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(dismissDelay)))
            }
            return
        }

        if activities.isEmpty {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                _ = try Activity.request(attributes: FireActivityAttributes(), content: content, pushType: nil)
                logger.info("Live Activity started")
            } catch {
                // Expected when the fire is lit from Siri or a control while
                // Fyr is in the background: activities start in the foreground.
                logger.info("Live Activity not started: \(error.localizedDescription)")
            }
        } else {
            for activity in activities {
                await activity.update(content)
            }
        }
    }

    /// End every activity right away (setting switched off, bridge reset).
    static func endAll() async {
        for activity in Activity<FireActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
