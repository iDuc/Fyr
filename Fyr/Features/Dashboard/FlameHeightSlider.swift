import SwiftUI

/// Custom slider for flame height control (0-100%)
/// Features eco mode indicator and quick preset buttons
struct FlameHeightSlider: View {
    @Binding var value: Double
    var ecoModeActive: Bool = false
    let range: ClosedRange<Double> = 0...100
    let step: Double = 5  // Steps of 5% for usability
    let onChangeEnd: (Int) -> Void

    @State private var isDragging = false
    @State private var showTooltip = false

    var body: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            // Header
            header

            // Custom slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    trackBackground

                    // Filled portion
                    trackFill(in: geometry.size.width)

                    // Eco mode max indicator (dashed line showing current max)
                    if ecoModeActive {
                        ecoIndicator(in: geometry.size.width)
                    }

                    // Tick marks (every 10%)
                    tickMarks

                    // Thumb
                    thumb(in: geometry.size.width)
                }
            }
            .frame(height: 32)

            // Bottom row: state label + presets
            bottomRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Flame height slider"))
        .accessibilityValue("\(Int(value)) " + String(localized: "percent") + (ecoModeActive ? ", " + String(localized: "eco mode maximum") : ""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if value < 100 {
                    value += 5
                    onChangeEnd(Int(value))
                }
            case .decrement:
                if value > 0 {
                    value -= 5
                    onChangeEnd(Int(value))
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
                Image(systemName: "flame.fill")
                    .foregroundStyle(FyrDesign.Colors.flameOrange)

                Text(String(localized: "Flame Height"))
                    .font(.headline)
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
            }

            Spacer()

            // Current value with eco indicator
            HStack(spacing: FyrDesign.Spacing.xs) {
                if ecoModeActive {
                    Text(String(localized: "max"))
                        .font(.caption)
                        .foregroundStyle(FyrDesign.Colors.ecoGreen)
                }

                Text("\(Int(value))%")
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Track Components

    @ViewBuilder
    private var trackBackground: some View {
        Capsule()
            .fill(FyrDesign.Colors.glassBackground)
            .overlay(
                Capsule()
                    .stroke(FyrDesign.Colors.glassBorderSubtle, lineWidth: 1)
            )
            .frame(height: FyrDesign.Size.sliderTrackHeight)
    }

    @ViewBuilder
    private func trackFill(in totalWidth: CGFloat) -> some View {
        Capsule()
            .fill(flameGradient)
            .frame(width: fillWidth(in: totalWidth), height: FyrDesign.Size.sliderTrackHeight)
            .glow(color: FyrDesign.Colors.flameOrange, radius: 8, intensity: 0.3)
    }

    @ViewBuilder
    private func ecoIndicator(in totalWidth: CGFloat) -> some View {
        // Dashed line at current value showing eco mode max
        Rectangle()
            .fill(FyrDesign.Colors.ecoGreen)
            .frame(width: 2, height: 20)
            .offset(x: fillWidth(in: totalWidth) - 1)

        // Small leaf icon above
        Image(systemName: "leaf.fill")
            .font(.caption2)
            .foregroundStyle(FyrDesign.Colors.ecoGreen)
            .offset(x: fillWidth(in: totalWidth) - 6, y: -18)
    }

    @ViewBuilder
    private var tickMarks: some View {
        HStack(spacing: 0) {
            ForEach(0...10, id: \.self) { tick in
                if tick > 0 {
                    Spacer()
                }
                Rectangle()
                    .fill(tick * 10 <= Int(value) ? Color.white.opacity(0.5) : FyrDesign.Colors.glassBorderSubtle)
                    .frame(width: 2, height: tick % 5 == 0 ? 12 : 6)
            }
        }
        .frame(height: 12)
    }

    @ViewBuilder
    private func thumb(in totalWidth: CGFloat) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.white, Color.white.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: FyrDesign.Size.sliderThumbSize, height: FyrDesign.Size.sliderThumbSize)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            .overlay {
                Circle()
                    .stroke(
                        isDragging ? FyrDesign.Colors.flameOrange : FyrDesign.Colors.flameOrange.opacity(0.8),
                        lineWidth: isDragging ? 3 : 2
                    )
            }
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .offset(x: thumbOffset(in: totalWidth))
            .gesture(dragGesture(in: totalWidth))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }

    // MARK: - Bottom Row

    @ViewBuilder
    private var bottomRow: some View {
        HStack {
            // State indicator
            Text(intensityLabel)
                .font(.caption)
                .foregroundStyle(FyrDesign.Colors.textTertiary)

            Spacer()

            // Quick presets
            HStack(spacing: FyrDesign.Spacing.xs) {
                ForEach([25.0, 50.0, 75.0], id: \.self) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: Double) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                value = preset
            }
            onChangeEnd(Int(preset))
        } label: {
            Text("\(Int(preset))%")
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    value == preset
                        ? FyrDesign.Colors.textPrimary
                        : FyrDesign.Colors.textTertiary
                )
                .padding(.horizontal, FyrDesign.Spacing.sm)
                .padding(.vertical, FyrDesign.Spacing.xs)
                .background(
                    value == preset
                        ? FyrDesign.Colors.flameOrange.opacity(0.3)
                        : FyrDesign.Colors.glassBackground
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            value == preset
                                ? FyrDesign.Colors.flameOrange.opacity(0.5)
                                : FyrDesign.Colors.glassBorderSubtle,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var intensityLabel: String {
        if value < 33 {
            return String(localized: "Low Heat")
        } else if value < 66 {
            return String(localized: "Medium Heat")
        } else {
            return String(localized: "High Heat")
        }
    }

    // MARK: - Computed Properties

    private var flameGradient: LinearGradient {
        let intensity = value / 100.0
        let colors: [Color]

        if intensity > 0.7 {
            colors = [FyrDesign.Colors.flameOrange.opacity(0.7), FyrDesign.Colors.flameRed]
        } else if intensity > 0.4 {
            colors = [FyrDesign.Colors.flameYellow.opacity(0.7), FyrDesign.Colors.flameOrange]
        } else {
            colors = [FyrDesign.Colors.flameYellow.opacity(0.5), FyrDesign.Colors.flameOrange.opacity(0.8)]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Helpers

    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        let percentage = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return totalWidth * percentage
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        let percentage = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return (totalWidth - FyrDesign.Size.sliderThumbSize) * percentage
    }

    private func dragGesture(in totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                isDragging = true
                let percentage = gesture.location.x / totalWidth
                let rawValue = range.lowerBound + (range.upperBound - range.lowerBound) * percentage
                let steppedValue = (rawValue / step).rounded() * step
                value = min(max(steppedValue, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in
                isDragging = false
                onChangeEnd(Int(value))
            }
    }
}

// MARK: - Preview

#Preview("Flame Height Slider") {
    @Previewable @State var flameHeight: Double = 65

    ZStack {
        DynamicBackground(isFireplaceOn: true)

        FlameHeightSlider(value: $flameHeight) { newValue in
            print("Flame height changed to: \(newValue)")
        }
        .padding()
        .glassCard()
        .padding()
    }
}

#Preview("Flame Height Slider - Eco Mode") {
    @Previewable @State var flameHeight: Double = 50

    ZStack {
        DynamicBackground(isFireplaceOn: true)

        FlameHeightSlider(value: $flameHeight, ecoModeActive: true) { newValue in
            print("Flame height changed to: \(newValue)")
        }
        .padding()
        .glassCard()
        .padding()
    }
}
