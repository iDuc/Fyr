import ActivityKit
import AppIntents
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Fyr

/// The state shown outside the app (widgets, controls, Live Activity) and the
/// declarations that keep the safety policy on those surfaces.
@Suite("Surfaces")
struct SurfacesTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(isOn: Bool, wave: Bool = false, at date: Date? = nil, since: Date? = nil) -> FireplaceSnapshot {
        FireplaceSnapshot(isOn: isOn, ecoModeActive: wave, lastSetFlameHeight: 60, currentTemperature: 21,
                          timestamp: date ?? t0, burningSince: since)
    }

    // MARK: - Snapshot transitions

    @Test func lightingTheFireRecordsWhenItStarted() {
        let lit = snapshot(isOn: false).applying(.turnOn, at: t0 + 60)
        #expect(lit.isOn)
        #expect(lit.burningSince == t0 + 60)
        #expect(lit.timestamp == t0 + 60)
    }

    @Test func turningOffClearsWaveAndSince() {
        let off = snapshot(isOn: true, wave: true, since: t0).applying(.turnOff, at: t0 + 600)
        #expect(!off.isOn)
        #expect(!off.ecoModeActive)
        #expect(off.burningSince == nil)
    }

    @Test func waveOffKeepsTheFireState() {
        let state = snapshot(isOn: false).applying(.setWaveMode(enabled: false))
        #expect(!state.isOn)
        #expect(!state.ecoModeActive)
    }

    @Test func burningSinceSurvivesStatusReads() {
        let previous = snapshot(isOn: true, since: t0)
        let next = FireplaceSnapshot.confirmed(isOn: true, ecoModeActive: true, lastSetFlameHeight: 60,
                                               currentTemperature: 21.5, errorCode: nil, previous: previous, at: t0 + 600)
        #expect(next.burningSince == t0)
        #expect(next.ecoModeActive)
    }

    @Test func aFireAlreadyBurningAtFirstSightHasNoSince() {
        let first = FireplaceSnapshot.confirmed(isOn: true, ecoModeActive: false, lastSetFlameHeight: nil,
                                                currentTemperature: 20, errorCode: nil, previous: nil, at: t0)
        #expect(first.isOn)
        #expect(first.burningSince == nil)
    }

    @Test func snapshotGoesStaleAfterFifteenMinutes() {
        let state = snapshot(isOn: true)
        #expect(state.isFresh(at: t0 + 14 * 60))
        #expect(!state.isFresh(at: t0 + 15 * 60))
        #expect(state.staleDate == t0 + 15 * 60)
    }

    // MARK: - Refresh rule

    @Test func surfacesRefreshOnVisibleChangesOnly() {
        let previous = snapshot(isOn: true, at: t0)
        var same = previous
        same.timestamp = t0 + 15
        #expect(!FyrSurfaces.needsRefresh(same, previous: previous, lastPublished: t0))

        #expect(FyrSurfaces.needsRefresh(previous.applying(.turnOff, at: t0 + 15), previous: previous, lastPublished: t0))
        #expect(FyrSurfaces.needsRefresh(previous.applying(.setWaveMode(enabled: true), at: t0 + 15), previous: previous, lastPublished: t0))

        var warmer = same
        warmer.currentTemperature = 21.6
        #expect(FyrSurfaces.needsRefresh(warmer, previous: previous, lastPublished: t0))

        #expect(FyrSurfaces.needsRefresh(previous, previous: nil, lastPublished: t0))
        #expect(FyrSurfaces.needsRefresh(previous, previous: previous, lastPublished: nil))
    }

    /// Polls every 15 s: the previous snapshot is always recent, but the
    /// surfaces still refresh every 5 minutes so their stale date moves on.
    @Test func steadyPollingStillRefreshesEveryFiveMinutes() {
        var last = snapshot(isOn: true, at: t0)
        var refreshes: [Date] = []
        var published = t0
        for step in 1...40 {
            var next = last
            next.timestamp = t0 + Double(step * 15)
            if FyrSurfaces.needsRefresh(next, previous: last, lastPublished: published) {
                refreshes.append(next.timestamp)
                published = next.timestamp
            }
            last = next
        }
        #expect(refreshes == [t0 + 300, t0 + 600])
    }

    @Test func verifiedBurningCommandsMeanTheFireIsOn() {
        let unknown = FireplaceSnapshot.unknown(at: t0)
        #expect(unknown.applying(.setWaveMode(enabled: true), at: t0 + 1).isOn)
        #expect(unknown.applying(.setFlameHeight(40), at: t0 + 1).isOn)
        #expect(!unknown.applying(.setWaveMode(enabled: false), at: t0 + 1).isOn)
    }

    @Test func anOldSnapshotDoesNotDateANewFire() {
        let old = snapshot(isOn: true, since: t0)
        let later = FireplaceSnapshot.confirmed(isOn: true, ecoModeActive: false, lastSetFlameHeight: nil,
                                                currentTemperature: 20, errorCode: nil, previous: old, at: t0 + 3 * 3600)
        #expect(later.burningSince == nil)
    }

    // MARK: - Live Activity content

    @Test func liveActivityIsStaleWhenTheSnapshotIs() {
        let state = snapshot(isOn: true, wave: true, since: t0 - 600)
        let content = FireLiveActivity.content(for: state)
        #expect(content.staleDate == state.staleDate)
        #expect(content.state.isOn)
        #expect(content.state.waveMode)
        #expect(content.state.burningSince == t0 - 600)
        #expect(content.state.updatedAt == t0)
    }

    // MARK: - Intent declarations for widgets and controls

    @Test func widgetAndControlIntentsFollowTheSafetyPolicy() {
        // Wave on/off may run on a locked device; neither can light the fire.
        #expect(SetWaveModeIntent.authenticationPolicy == .alwaysAllowed)
        #expect(SetWaveModeIntent.authenticationPolicy == FireplaceIntentSupport.authenticationPolicy(for: .setWaveMode(enabled: true)))
        // The Light Fire control runs TurnOnFireplaceIntent: unlocked device + confirmation.
        #expect(TurnOnFireplaceIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(!SetWaveModeIntent.isDiscoverable)
    }

    @Test func commandIntentsRunInTheAppProcess() {
        let targets: [IntentExecutionTargets] = [
            TurnOnFireplaceIntent.allowedExecutionTargets,
            TurnOffFireplaceIntent.allowedExecutionTargets,
            EnableEcoModeIntent.allowedExecutionTargets,
            DisableEcoModeIntent.allowedExecutionTargets,
            ToggleEcoModeIntent.allowedExecutionTargets,
            SetWaveModeIntent.allowedExecutionTargets,
            SetFlameHeightIntent.allowedExecutionTargets,
            SetTemperatureIntent.allowedExecutionTargets,
            GetFireplaceStatusIntent.allowedExecutionTargets,
        ]
        for target in targets {
            #expect(target == .main)
        }
    }

    @Test func waveIntentWithoutBurningFireSendsNothing() async throws {
        let harness = await ServiceHarness()
        let outcome = try await FireplaceIntentSupport.execute(
            .setWaveMode(enabled: true),
            service: harness.service,
            configure: { _ throws(BridgeError) in }
        )
        #expect(outcome == .failure(.fireplaceOff))
        #expect(await harness.bridge.writes.isEmpty)
    }
}

/// Where the dashboard puts its two panes on an iPhone Duo.
@Suite("Duo layout")
@MainActor
struct DuoLayoutTests {
    typealias Arrangement = DashboardLayout<EmptyView, EmptyView>.Arrangement

    @Test func bookFoldSplitsWhenBothHalvesFit() {
        // Open Duo held upright: the fold runs top to bottom in the middle.
        let fold = CGRect(x: 340, y: 0, width: 20, height: 900)
        #expect(Arrangement.fits(fold, in: CGSize(width: 700, height: 900)))
    }

    @Test func laptopFoldSplitsTopAndBottom() {
        let fold = CGRect(x: 0, y: 330, width: 900, height: 20)
        #expect(Arrangement.fits(fold, in: CGSize(width: 900, height: 680)))
    }

    @Test func tooNarrowHalvesStayOneColumn() {
        let fold = CGRect(x: 200, y: 0, width: 20, height: 800)
        #expect(!Arrangement.fits(fold, in: CGSize(width: 420, height: 800)))
    }
}
