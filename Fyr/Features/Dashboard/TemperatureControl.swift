import SwiftUI

/// Temperature control for thermostat setpoint
/// Features current vs target display and quick presets
struct TemperatureControl: View {
    @Binding var targetTemperature: Double
    let currentTemperature: Double
    let range: ClosedRange<Double> = 15...30
    let step: Double = 0.5
    let onChangeEnd: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            // Header with temperature comparison
            header

            // Custom temperature slider
            temperatureSlider

            // Quick presets
            presetButtons
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Temperature control"))
        .accessibilityValue(String(localized: "Current %@, target %@", defaultValue: "Current \(formatTemperature(currentTemperature)), target \(formatTemperature(targetTemperature))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if targetTemperature < range.upperBound {
                    targetTemperature += step
                    onChangeEnd(targetTemperature)
                }
            case .decrement:
                if targetTemperature > range.lowerBound {
                    targetTemperature -= step
                    onChangeEnd(targetTemperature)
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            HStack(spacing: FyrDesign.Spacing.xs) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(temperatureColor)

                Text(String(localized: "Temperature"))
                    .font(.headline)
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
            }

            Spacer()

            // Current vs Target display
            HStack(spacing: FyrDesign.Spacing.xs) {
                // Current temperature
                Text(formatTemperature(currentTemperature))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(FyrDesign.Colors.textSecondary)

                // Delta indicator
                temperatureDelta

                // Target temperature
                Text(formatTemperature(targetTemperature))
                    .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder
    private var temperatureDelta: some View {
        let delta = targetTemperature - currentTemperature

        if abs(delta) > 0.5 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                Text(String(format: "%.1f°", abs(delta)))
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(delta > 0 ? FyrDesign.Colors.flameOrange : .cyan)
            .padding(.horizontal, FyrDesign.Spacing.xs)
            .padding(.vertical, 2)
            .background(
                (delta > 0 ? FyrDesign.Colors.flameOrange : Color.cyan)
                    .opacity(0.15)
            )
            .clipShape(Capsule())
        } else {
            Image(systemName: "equal")
                .font(.caption)
                .foregroundStyle(FyrDesign.Colors.textTertiary)
        }
    }

    // MARK: - Slider

    @ViewBuilder
    private var temperatureSlider: some View {
        Slider(
            value: $targetTemperature,
            in: range,
            step: step
        ) {
            Text(String(localized: "Target temperature"))
        } minimumValueLabel: {
            Text("\(Int(range.lowerBound))°")
                .font(.caption)
                .foregroundStyle(FyrDesign.Colors.textTertiary)
        } maximumValueLabel: {
            Text("\(Int(range.upperBound))°")
                .font(.caption)
                .foregroundStyle(FyrDesign.Colors.textTertiary)
        }
        .tint(temperatureColor)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isDragging = true }
                .onEnded { _ in
                    isDragging = false
                    onChangeEnd(targetTemperature)
                }
        )
    }

    // MARK: - Preset Buttons

    @ViewBuilder
    private var presetButtons: some View {
        HStack(spacing: FyrDesign.Spacing.sm) {
            ForEach([18.0, 20.0, 22.0, 24.0], id: \.self) { preset in
                presetButton(preset)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: Double) -> some View {
        let isSelected = abs(targetTemperature - preset) < 0.1

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                targetTemperature = preset
            }
            onChangeEnd(preset)
        } label: {
            Text("\(Int(preset))°")
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    isSelected
                        ? FyrDesign.Colors.textPrimary
                        : FyrDesign.Colors.textTertiary
                )
                .padding(.horizontal, FyrDesign.Spacing.sm)
                .padding(.vertical, FyrDesign.Spacing.xs)
                .background(
                    isSelected
                        ? temperatureColor.opacity(0.3)
                        : FyrDesign.Colors.glassBackground
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected
                                ? temperatureColor.opacity(0.5)
                                : FyrDesign.Colors.glassBorderSubtle,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var temperatureColor: Color {
        // Color based on target temperature
        if targetTemperature >= 24 {
            return FyrDesign.Colors.flameOrange
        } else if targetTemperature >= 20 {
            return FyrDesign.Colors.flameYellow
        } else {
            return .cyan
        }
    }

    // MARK: - Helpers

    private func formatTemperature(_ temp: Double) -> String {
        let measurement = Measurement(value: temp, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}

// MARK: - Preview

#Preview("Temperature Control") {
    @Previewable @State var targetTemp: Double = 21.0

    ZStack {
        DynamicBackground(isFireplaceOn: true)

        TemperatureControl(
            targetTemperature: $targetTemp,
            currentTemperature: 19.5
        ) { newValue in
            print("Temperature changed to: \(newValue)")
        }
        .padding()
        .glassCard()
        .padding()
    }
}

#Preview("Temperature Control - Heating") {
    @Previewable @State var targetTemp: Double = 24.0

    ZStack {
        DynamicBackground(isFireplaceOn: true)

        TemperatureControl(
            targetTemperature: $targetTemp,
            currentTemperature: 18.5
        ) { newValue in
            print("Temperature changed to: \(newValue)")
        }
        .padding()
        .glassCard()
        .padding()
    }
}
