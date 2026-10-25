import Foundation

/// Enforces the DRU bridge's minimum intervals between requests.
///
/// `tryAcquire` checks and records a slot in one synchronous step (no
/// suspension point), so concurrent callers can never both pass. Callers must
/// call it immediately before sending, while holding the bridge request gate.
actor RateLimiter {

    nonisolated enum Kind: Hashable, Sendable {
        /// Status polling.
        case read
        /// General writes: on/off, wave mode, thermostat, wave interval.
        case write
        /// Flame height changes. Also counts as a write.
        case flameHeight
    }

    nonisolated struct Intervals: Sendable, Equatable {
        var read: Duration
        var write: Duration
        var flameHeight: Duration

        /// DRU limits: 3 s between reads, 3 s between writes, 10 s between flame
        /// height changes (regulatory, must not be reduced).
        static let production = Intervals(read: .seconds(3), write: .seconds(3), flameHeight: .seconds(10))
    }

    let intervals: Intervals
    private let clock = ContinuousClock()
    private var lastGrant: [Kind: ContinuousClock.Instant] = [:]

    init(intervals: Intervals = .production) {
        self.intervals = intervals
    }

    /// Record a slot for `kind` if allowed now.
    /// - Returns: `nil` if the slot was granted, otherwise how long to wait.
    func tryAcquire(_ kind: Kind) -> Duration? {
        let now = clock.now
        let wait = remaining(kind, at: now)
        guard wait <= .zero else { return wait }
        for affected in Self.affectedKinds(kind) {
            lastGrant[affected] = now
        }
        return nil
    }

    /// Time until `kind` is allowed, zero if allowed now.
    func remaining(_ kind: Kind) -> Duration {
        max(.zero, remaining(kind, at: clock.now))
    }

    private func remaining(_ kind: Kind, at now: ContinuousClock.Instant) -> Duration {
        Self.affectedKinds(kind)
            .compactMap { affected in lastGrant[affected].map { $0 + interval(affected) - now } }
            .max() ?? .zero
    }

    private func interval(_ kind: Kind) -> Duration {
        switch kind {
        case .read: intervals.read
        case .write: intervals.write
        case .flameHeight: intervals.flameHeight
        }
    }

    /// A flame height change is also a write, so it waits for and stamps both.
    private static func affectedKinds(_ kind: Kind) -> [Kind] {
        kind == .flameHeight ? [.flameHeight, .write] : [kind]
    }
}
