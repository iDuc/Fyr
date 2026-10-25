import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity while the fire burns: Lock Screen banner and Dynamic
/// Island, with one-tap off and the wave toggle.
///
/// Fyr has no server, so this only changes when Fyr itself talks to the
/// fireplace. After `FireplaceSnapshot.freshness` without news iOS marks the
/// content stale and it says so, instead of pretending to know.
struct FireLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FireActivityAttributes.self) { context in
            FireLiveActivityView(state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(FyrDesign.Colors.flameOrange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FlameView(isOn: context.state.isOn, flameHeight: context.state.lastSetFlameHeight ?? 60,
                              waveMode: context.state.waveMode, animated: false)
                        .frame(width: 44, height: 52)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isOn ? "Burning" : "Off")
                            .font(.headline)
                        LiveActivityDetail(state: context.state, isStale: context.isStale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isOn {
                        LiveActivityButtons(waveMode: context.state.waveMode)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isOn ? "flame.fill" : "flame")
                    .foregroundStyle(FyrDesign.Colors.flameOrange)
            } compactTrailing: {
                if context.state.isOn, context.state.waveMode {
                    Image(systemName: "water.waves")
                        .foregroundStyle(FyrDesign.Colors.wave)
                } else if context.state.isOn, let since = context.state.burningSince {
                    Text(since, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text(context.state.isOn ? "On" : "Off")
                }
            } minimal: {
                Image(systemName: context.state.isOn ? "flame.fill" : "flame")
                    .foregroundStyle(FyrDesign.Colors.flameOrange)
            }
            .keylineTint(FyrDesign.Colors.flameOrange)
        }
    }
}

struct FireLiveActivityView: View {
    let state: FireActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FlameView(isOn: state.isOn, flameHeight: state.lastSetFlameHeight ?? 60, waveMode: state.waveMode, animated: false)
                .frame(width: 46, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.isOn ? "Burning" : "Off")
                        .font(.headline)
                    if state.isOn && state.waveMode {
                        Label("Wave", systemImage: "water.waves")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FyrDesign.Colors.wave)
                    }
                }
                LiveActivityDetail(state: state, isStale: isStale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.isOn {
                Button(intent: TurnOffFireplaceIntent()) {
                    Label("Turn Off", systemImage: "power")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
            }
        }
    }
}

/// Since when, the room temperature, and when it was last confirmed.
struct LiveActivityDetail: View {
    let state: FireActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("Not confirmed since \(state.updatedAt, style: .time). Open Fyr to check.")
        } else if state.isOn, let since = state.burningSince {
            if let temperature = state.temperature {
                Text("Since \(since, style: .time) · \(Measurement(value: temperature, unit: UnitTemperature.celsius), format: .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...1))))")
            } else {
                Text("Since \(since, style: .time)")
            }
        } else {
            Text("Updated \(state.updatedAt, style: .time)")
        }
    }
}

struct LiveActivityButtons: View {
    let waveMode: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: TurnOffFireplaceIntent()) {
                Label("Turn Off", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .tint(.primary)

            Button(intent: SetWaveModeIntent(value: !waveMode)) {
                Label(waveMode ? "Wave Off" : "Wave On", systemImage: "water.waves")
                    .frame(maxWidth: .infinity)
            }
            .tint(FyrDesign.Colors.wave)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.semibold))
    }
}

#Preview("Lock Screen", as: .content, using: FireActivityAttributes()) {
    FireLiveActivityWidget()
} contentStates: {
    FireActivityAttributes.ContentState(isOn: true, waveMode: true, burningSince: .now.addingTimeInterval(-2400),
                                        temperature: 21.4, lastSetFlameHeight: 70, updatedAt: .now)
}
