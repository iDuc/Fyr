import SwiftUI
import WidgetKit

/// Main widget entry view with glass-style design matching the app
struct FyrWidgetEntryView: View {
    var entry: FireplaceEntry

    // Widget-specific design colors (matching app's FyrDesign)
    private let flameOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    private let flameYellow = Color(red: 1.0, green: 0.95, blue: 0.3)
    private let ecoGreen = Color(red: 0.0, green: 0.85, blue: 0.5)
    private let warmBackground = Color(red: 0.15, green: 0.08, blue: 0.05)
    private let coolBackground = Color(red: 0.05, green: 0.08, blue: 0.15)

    var body: some View {
        if entry.isConnected {
            connectedView
        } else {
            disconnectedView
        }
    }

    // MARK: - Connected View

    @ViewBuilder
    private var connectedView: some View {
        HStack(spacing: 16) {
            // Left: Flame indicator with glow
            flameIndicator

            // Vertical divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)

            // Right: Stats
            statsColumn

            Spacer()
        }
        .padding()
        // Background is now handled by containerBackground in FyrWidget.swift
    }

    @ViewBuilder
    private var flameIndicator: some View {
        VStack(spacing: 8) {
            ZStack {
                // Glow effect when on
                if entry.isOn {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [flameOrange.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                        .frame(width: 80, height: 80)
                        .blur(radius: 10)
                }

                // Flame icon
                Image(systemName: entry.isOn ? "flame.fill" : "flame")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        entry.isOn
                            ? LinearGradient(colors: [flameYellow, flameOrange], startPoint: .bottom, endPoint: .top)
                            : LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.3)], startPoint: .bottom, endPoint: .top)
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: entry.isOn && !entry.ecoModeActive)
            }

            // Status text
            Text(entry.isOn ? "On" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isOn ? .white : .white.opacity(0.5))
        }
        .frame(width: 80)
    }

    @ViewBuilder
    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Temperature
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(.white.opacity(0.6))

                Text(formatTemperature(entry.temperature))
                    .font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }

            // Flame height (when on)
            if entry.isOn {
                HStack(spacing: 6) {
                    Image(systemName: "flame")
                        .foregroundStyle(flameOrange)

                    Text("\(entry.flameHeight)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))

                    // Eco mode badge
                    if entry.ecoModeActive {
                        HStack(spacing: 4) {
                            Image(systemName: "leaf.fill")
                                .font(.caption2)
                            Text("Eco")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(ecoGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(ecoGreen.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // Last updated
            Text("Updated \(entry.date, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Disconnected View

    @ViewBuilder
    private var disconnectedView: some View {
        VStack(spacing: 12) {
            ZStack {
                // Subtle glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.gray.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("Not Connected")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            Text("Open Fyr to reconnect")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Background is now handled by containerBackground in FyrWidget.swift
    }

    // MARK: - Helpers

    private func formatTemperature(_ temp: Double) -> String {
        guard temp > 0 else { return "--°" }

        let measurement = Measurement(value: temp, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    FyrWidget()
} timeline: {
    FireplaceEntry.placeholder
    FireplaceEntry(
        date: Date(),
        isOn: true,
        flameHeight: 65,
        temperature: 22.5,
        ecoModeActive: true,
        isConnected: true
    )
    FireplaceEntry(
        date: Date(),
        isOn: true,
        flameHeight: 45,
        temperature: 20.0,
        ecoModeActive: false,
        isConnected: true
    )
    FireplaceEntry.disconnected
}
