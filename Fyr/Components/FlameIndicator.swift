import SwiftUI

/// Visual flame indicator showing current flame height with animated effects
/// Features eco mode breathing animation and dynamic color gradients
struct FlameIndicator: View {
    let flameHeight: Int
    let maxHeight: Int = 100
    let isOn: Bool
    var ecoModeActive: Bool = false
    var size: FlameSize = .large
    var showPercentage: Bool = true

    enum FlameSize {
        case small   // 80pt - for widgets
        case medium  // 120pt - for compact views
        case large   // 200pt - hero display

        var dimension: CGFloat {
            switch self {
            case .small: return 80
            case .medium: return 120
            case .large: return 200
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 40
            case .medium: return 64
            case .large: return 100
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .small: return 30
            case .medium: return 60
            case .large: return 100
            }
        }
    }

    /// Animation phase for floating effect
    @State private var floatPhase: Double = 0

    /// Breathing scale for eco mode animation
    @State private var breathingScale: Double = 1.0

    /// Timer for eco mode breathing animation
    @State private var breathingTimer: Timer?

    var body: some View {
        ZStack {
            // Multi-layer glow when on
            if isOn {
                glowLayers
            }

            // Main flame content
            flameContent

            // Percentage badge when on (optional)
            if isOn && showPercentage {
                percentageBadge
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .scaleEffect(ecoModeActive ? breathingScale : 1.0)
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            stopAnimations()
        }
        .onChange(of: ecoModeActive) { _, newValue in
            if newValue {
                startBreathingAnimation()
            } else {
                stopBreathingAnimation()
                breathingScale = 1.0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var glowLayers: some View {
        let intensity = Double(flameHeight) / Double(maxHeight)
        let flameColor = FyrDesign.Colors.flameColor(intensity: intensity)

        // Outer glow - soft ambient
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        flameColor.opacity(0.2 * intensity),
                        flameColor.opacity(0.1 * intensity),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.glowRadius * 1.2
                )
            )
            .frame(width: size.dimension * 1.4, height: size.dimension * 1.4)
            .blur(radius: 20)

        // Inner glow - more intense
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        flameColor.opacity(0.4 * intensity),
                        flameColor.opacity(0.2 * intensity),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.glowRadius * 0.8
                )
            )
            .frame(width: size.dimension, height: size.dimension)
            .blur(radius: 10)
    }

    @ViewBuilder
    private var flameContent: some View {
        ZStack {
            // Flame icon with dynamic gradient
            Image(systemName: isOn ? "flame.fill" : "flame")
                .font(.system(size: size.iconSize, weight: .medium))
                .foregroundStyle(flameGradient)
                .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: isOn && !ecoModeActive)
                .offset(y: isOn ? sin(floatPhase) * 2 : 0) // Subtle floating motion
        }
    }

    @ViewBuilder
    private var percentageBadge: some View {
        VStack {
            Spacer()

            Text("\(flameHeight)%")
                .font(.system(size: badgeFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, size == .large ? 12 : 8)
                .padding(.vertical, size == .large ? 6 : 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .offset(y: size == .large ? 10 : 5)
        }
    }

    private var badgeFontSize: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 14
        case .large: return 18
        }
    }

    // MARK: - Computed Properties

    private var flameGradient: LinearGradient {
        if isOn {
            let intensity = Double(flameHeight) / Double(maxHeight)
            return LinearGradient(
                colors: flameColors(for: intensity),
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                colors: [.gray.opacity(0.5), .gray.opacity(0.3)],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }

    private func flameColors(for intensity: Double) -> [Color] {
        // Dynamic color based on intensity
        if intensity > 0.7 {
            return [
                FyrDesign.Colors.flameRed,
                FyrDesign.Colors.flameOrange,
                FyrDesign.Colors.flameYellow
            ]
        } else if intensity > 0.4 {
            return [
                FyrDesign.Colors.flameOrange,
                FyrDesign.Colors.flameOrange.opacity(0.9),
                FyrDesign.Colors.flameYellow
            ]
        } else {
            return [
                FyrDesign.Colors.flameOrange.opacity(0.8),
                FyrDesign.Colors.flameYellow.opacity(0.9),
                FyrDesign.Colors.flameYellow.opacity(0.7)
            ]
        }
    }

    private var accessibilityLabel: String {
        if ecoModeActive {
            return "Fireplace in eco mode"
        }
        return isOn ? "Fireplace flame" : "Fireplace off"
    }

    private var accessibilityValue: String {
        if !isOn {
            return "Not burning"
        }
        var value = "Flame height \(flameHeight) percent"
        if ecoModeActive {
            value += ", eco mode active"
        }
        return value
    }

    // MARK: - Animations

    private func startAnimations() {
        // Start floating animation
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            floatPhase = .pi * 2
        }

        // Start breathing if eco mode is active
        if ecoModeActive {
            startBreathingAnimation()
        }
    }

    private func stopAnimations() {
        stopBreathingAnimation()
    }

    private func startBreathingAnimation() {
        // Eco mode breathing: scale 0.95-1.0 over 2-second cycle
        breathingTimer?.invalidate()
        breathingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated {
                let time = Date().timeIntervalSince1970
                let phase = time.truncatingRemainder(dividingBy: FyrDesign.Animation.breathing)
                let normalizedPhase = phase / FyrDesign.Animation.breathing

                // Smooth sine wave: oscillates between 0.95 and 1.0
                withAnimation(.linear(duration: 0.05)) {
                    breathingScale = 0.97 + 0.03 * sin(normalizedPhase * .pi * 2)
                }
            }
        }
    }

    private func stopBreathingAnimation() {
        breathingTimer?.invalidate()
        breathingTimer = nil
    }
}

// MARK: - Compact Flame Indicator

/// Smaller flame indicator for widgets and compact views
struct CompactFlameIndicator: View {
    let flameHeight: Int
    let isOn: Bool
    var ecoModeActive: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOn ? "flame.fill" : "flame")
                .foregroundStyle(isOn ? FyrDesign.Colors.flameOrange : .secondary)
                .symbolEffect(.pulse, options: .repeating.speed(0.3), isActive: ecoModeActive)

            if isOn {
                Text("\(flameHeight)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if ecoModeActive {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(FyrDesign.Colors.ecoGreen)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flame height")
        .accessibilityValue(isOn ? "\(flameHeight) percent\(ecoModeActive ? ", eco mode" : "")" : "Off")
    }
}

// MARK: - Preview

#Preview("Flame Indicator - High") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        FlameIndicator(flameHeight: 85, isOn: true, size: .large)
    }
}

#Preview("Flame Indicator - Medium") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        FlameIndicator(flameHeight: 50, isOn: true, size: .large)
    }
}

#Preview("Flame Indicator - Low") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        FlameIndicator(flameHeight: 20, isOn: true, size: .large)
    }
}

#Preview("Flame Indicator - Eco Mode") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        FlameIndicator(flameHeight: 65, isOn: true, ecoModeActive: true, size: .large)
    }
}

#Preview("Flame Indicator - Off") {
    ZStack {
        DynamicBackground(isFireplaceOn: false)
        FlameIndicator(flameHeight: 0, isOn: false, size: .large)
    }
}

#Preview("Flame Indicator Sizes") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        VStack(spacing: 40) {
            FlameIndicator(flameHeight: 70, isOn: true, size: .small)
            FlameIndicator(flameHeight: 70, isOn: true, size: .medium)
            FlameIndicator(flameHeight: 70, isOn: true, size: .large)
        }
    }
}

#Preview("Compact Flame Indicator") {
    VStack(spacing: 20) {
        CompactFlameIndicator(flameHeight: 65, isOn: true, ecoModeActive: false)
        CompactFlameIndicator(flameHeight: 45, isOn: true, ecoModeActive: true)
        CompactFlameIndicator(flameHeight: 0, isOn: false)
    }
    .padding()
    .background(Color.black)
}
