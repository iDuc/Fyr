import SwiftUI

/// The big state: "Burning" or "Off", with since when, wave mode and the room
/// temperature underneath. Shows when the state is only the last known one.
struct FireStatusHeader: View {
    @Environment(Fireplace.self) private var fireplace

    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: FyrDesign.Spacing.xs) {
            Text(stateTitle)
                .font(.system(.largeTitle, design: .default, weight: .light))
                .fontWidth(.expanded)
                .foregroundStyle(FyrDesign.Colors.textPrimary)
                .contentTransition(.opacity)
                .accessibilityIdentifier("dashboard.state")

            details
                .font(.subheadline)
                .foregroundStyle(FyrDesign.Colors.textSecondary)

            if let note = freshnessNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .combine)
        .animation(FyrDesign.Animation.spring, value: fireplace.isOn)
    }

    private var stateTitle: String {
        if fireplace.lastStatusUpdate == nil {
            return fireplace.connectionState == .connecting
                ? String(localized: "Connecting…")
                : String(localized: "Not connected")
        }
        return fireplace.isOn ? String(localized: "Burning") : String(localized: "Off")
    }

    @ViewBuilder
    private var details: some View {
        let temperature = fireplace.lastStatusUpdate != nil && fireplace.currentTemperature > 0
            ? fireplace.formattedTemperature
            : nil
        if fireplace.isOn {
            HStack(spacing: FyrDesign.Spacing.sm) {
                if let since = fireplace.burningSince {
                    Text("Since \(since, style: .time)")
                }
                if fireplace.ecoModeActive {
                    Label(String(localized: "Wave"), systemImage: "water.waves")
                        .foregroundStyle(FyrDesign.Colors.wave)
                }
                if let temperature {
                    Text(temperature)
                        .monospacedDigit()
                }
            }
            .labelStyle(.titleAndIcon)
        } else if let temperature {
            Text("\(temperature) in the room")
                .monospacedDigit()
        }
    }

    /// "Last known, 12 min ago" until the first live status of this session.
    private var freshnessNote: String? {
        guard !fireplace.hasLiveStatus, let updated = fireplace.lastStatusUpdate else { return nil }
        let age = updated.formatted(.relative(presentation: .named))
        return String(localized: "Last known state, \(age)")
    }
}

/// A short line about the connection, only when something is not right.
struct ConnectionNote: View {
    @Environment(Fireplace.self) private var fireplace

    var body: some View {
        if let error = fireplace.lastError {
            VStack(spacing: FyrDesign.Spacing.xxs) {
                Label(error.localizedDescription, systemImage: icon(for: error))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, FyrDesign.Spacing.md)
            .padding(.vertical, FyrDesign.Spacing.sm + FyrDesign.Spacing.xs)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: FyrDesign.Radius.md, intensity: .subtle, tint: color(for: error))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard.error")
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if let errorCode = fireplace.errorCode {
            ErrorBanner(errorCode: errorCode)
        }
    }

    private func icon(for error: BridgeError) -> String {
        switch error {
        case .fireplaceOff: "flame"
        case .bridgeBusy: "person.2.fill"
        case .networkUnavailable: "wifi.slash"
        default: error.isConnectionProblem ? "antenna.radiowaves.left.and.right.slash" : "exclamationmark.circle"
        }
    }

    private func color(for error: BridgeError) -> Color {
        error.isConnectionProblem ? FyrDesign.Colors.warning : FyrDesign.Colors.textPrimary
    }
}
