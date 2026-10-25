import AppIntents
import SwiftUI
import WidgetKit

/// The fireplace on the Home Screen, Lock Screen and in StandBy.
///
/// Small and medium are interactive: Turn Off whenever the fire is (or was
/// last seen) burning, and the wave toggle. Lighting the fire is not offered
/// here; tapping the widget opens Fyr, where the swipe-to-ignite slider is.
struct FyrWidget: Widget {
    let kind: String = FyrAppGroup.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireplaceTimelineProvider()) { entry in
            FyrWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    DynamicBackground(isFireplaceOn: entry.isOn && entry.isFresh)
                }
        }
        .configurationDisplayName(Text("Fireplace"))
        .description(Text("Shows whether the fire burns, with an off button and wave mode."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FyrWidgetView: View {
    let entry: FireplaceEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumFireWidget(entry: entry)
        case .accessoryCircular:
            CircularFireWidget(entry: entry)
        case .accessoryRectangular:
            RectangularFireWidget(entry: entry)
        case .accessoryInline:
            InlineFireWidget(entry: entry)
        default:
            SmallFireWidget(entry: entry)
        }
    }
}

// MARK: - Shared pieces

/// "Burning", "Off", or "Set up Fyr", plus whether it is the last known state.
struct FireStateText: View {
    let entry: FireplaceEntry
    var font: Font = .title3

    var body: some View {
        Text(title)
            .font(font.weight(.light))
            .fontWidth(.expanded)
            .foregroundStyle(FyrDesign.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var title: LocalizedStringResource {
        guard entry.isConfigured, entry.snapshot != nil else { return "Set up Fyr" }
        return entry.isOn ? "Burning" : "Off"
    }
}

/// Since when / room temperature, or how old the state is when stale.
struct FireDetailText: View {
    let entry: FireplaceEntry

    var body: some View {
        Group {
            if let updated = entry.updatedAt, !entry.isFresh {
                Text("Last known, \(updated, style: .relative) ago")
            } else if entry.isOn, let since = entry.burningSince {
                Text("Since \(since, style: .time)")
            } else if let temperature = entry.temperature {
                Text(Measurement(value: temperature, unit: UnitTemperature.celsius),
                     format: .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...1))))
            }
        }
        .font(.caption)
        .foregroundStyle(FyrDesign.Colors.textSecondary)
        .lineLimit(2)
    }
}

/// One-tap off, always allowed. Runs `TurnOffFireplaceIntent` in the app.
struct WidgetTurnOffButton: View {
    var compact = false

    var body: some View {
        Button(intent: TurnOffFireplaceIntent()) {
            Label("Turn Off", systemImage: "power")
                .font(.caption.weight(.semibold))
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(FyrDesign.Colors.textPrimary)
        .accessibilityLabel(Text("Turn Off"))
    }
}

/// Wave mode toggle. Needs a burning fire to turn on (the app refuses otherwise).
struct WidgetWaveToggle: View {
    let isOn: Bool

    var body: some View {
        Toggle(isOn: isOn, intent: SetWaveModeIntent(value: !isOn)) {
            Label("Wave", systemImage: "water.waves")
                .font(.caption.weight(.semibold))
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .tint(FyrDesign.Colors.wave)
    }
}

/// Type-erased label style for the compact/regular button.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

// MARK: - Small (also StandBy)

struct SmallFireWidget: View {
    let entry: FireplaceEntry

    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                FlameView(isOn: entry.isOn, flameHeight: entry.flameHeight, waveMode: entry.waveMode, animated: false)
                    .frame(width: 44, height: 52)
                    .widgetAccentable()
                Spacer()
                if entry.isOn && entry.waveMode {
                    Image(systemName: "water.waves")
                        .font(.caption)
                        .foregroundStyle(FyrDesign.Colors.wave)
                        .accessibilityLabel(Text("Wave"))
                }
            }
            Spacer(minLength: 0)
            FireStateText(entry: entry, font: showsBackground ? .title3 : .title2)
            FireDetailText(entry: entry)
            if entry.offersTurnOff {
                WidgetTurnOffButton()
                    .padding(.top, 2)
            }
        }
        .widgetURL(URL(string: "fyr://dashboard"))
    }
}

// MARK: - Medium

struct MediumFireWidget: View {
    let entry: FireplaceEntry

    var body: some View {
        HStack(spacing: 16) {
            FlameView(isOn: entry.isOn, flameHeight: entry.flameHeight, waveMode: entry.waveMode, animated: false)
                .frame(width: 96)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 6) {
                FireStateText(entry: entry, font: .title2)
                FireDetailText(entry: entry)
                if entry.isOn, let height = entry.snapshot?.lastSetFlameHeight {
                    Label {
                        Text(Double(height) / 100, format: .percent)
                    } icon: {
                        Image(systemName: "flame")
                    }
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                if entry.offersTurnOff {
                    HStack(spacing: 8) {
                        WidgetTurnOffButton()
                        if entry.isOn {
                            WidgetWaveToggle(isOn: entry.waveMode)
                        }
                    }
                } else if entry.isConfigured {
                    Text("Open Fyr and slide to ignite")
                        .font(.caption2)
                        .foregroundStyle(FyrDesign.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "fyr://dashboard"))
    }
}

// MARK: - Lock Screen

struct CircularFireWidget: View {
    let entry: FireplaceEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.isOn ? "flame.fill" : "flame")
                    .font(.title3)
                    .widgetAccentable()
                if entry.isOn && entry.waveMode {
                    Image(systemName: "water.waves")
                        .font(.caption2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.isOn ? "Fireplace burning" : "Fireplace off"))
        .widgetURL(URL(string: "fyr://dashboard"))
    }
}

struct RectangularFireWidget: View {
    let entry: FireplaceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(entry.isOn ? "Burning" : "Off")
                    .font(.headline)
            } icon: {
                Image(systemName: entry.isOn ? "flame.fill" : "flame")
            }
            .widgetAccentable()

            if entry.isOn && entry.waveMode {
                Label("Wave", systemImage: "water.waves")
                    .font(.caption)
            }
            if let updated = entry.updatedAt, !entry.isFresh {
                Text("Last known, \(updated, style: .relative) ago")
                    .font(.caption)
            } else if entry.isOn, let since = entry.burningSince {
                Text("Since \(since, style: .time)")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "fyr://dashboard"))
    }
}

struct InlineFireWidget: View {
    let entry: FireplaceEntry

    var body: some View {
        if entry.isOn, let since = entry.burningSince, entry.isFresh {
            Label {
                Text("Burning since \(since, style: .time)")
            } icon: {
                Image(systemName: "flame.fill")
            }
        } else {
            Label {
                Text(entry.isOn ? "Burning" : "Fireplace off")
            } icon: {
                Image(systemName: entry.isOn ? "flame.fill" : "flame")
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    FyrWidget()
} timeline: {
    FireplaceEntry.placeholder
    FireplaceEntry(date: .now, snapshot: FireplaceSnapshot(isOn: false, ecoModeActive: false, currentTemperature: 19.5, timestamp: .now))
}

#Preview("Medium", as: .systemMedium) {
    FyrWidget()
} timeline: {
    FireplaceEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    FyrWidget()
} timeline: {
    FireplaceEntry.placeholder
}
