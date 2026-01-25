import SwiftUI
import UIKit

/// Design system tokens and components for Fyr iOS 26 liquid glass design
enum FyrDesign {

    // MARK: - Colors

    enum Colors {
        // Fire palette - warm tones for flame visualization
        static let flameYellow = Color(red: 1.0, green: 0.95, blue: 0.3)
        static let flameOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
        static let flameRed = Color(red: 1.0, green: 0.2, blue: 0.0)
        static let ember = Color(red: 0.8, green: 0.3, blue: 0.1)

        // Background gradients
        static let warmGradientStart = Color(red: 0.15, green: 0.08, blue: 0.05)
        static let warmGradientEnd = Color(red: 0.25, green: 0.12, blue: 0.05)
        static let coolGradientStart = Color(red: 0.05, green: 0.08, blue: 0.15)
        static let coolGradientEnd = Color(red: 0.08, green: 0.1, blue: 0.18)

        // Status colors
        static let ecoGreen = Color(red: 0.0, green: 0.85, blue: 0.5)
        static let ecoGreenSubtle = Color(red: 0.0, green: 0.85, blue: 0.5).opacity(0.15)
        static let connected = Color.green
        static let warning = Color.orange
        static let error = Color.red

        // Glass effect colors
        static let glassHighlight = Color.white.opacity(0.08)
        static let glassHighlightStrong = Color.white.opacity(0.15)
        static let glassBorder = Color.white.opacity(0.2)
        static let glassBorderSubtle = Color.white.opacity(0.1)
        static let glassBackground = Color.white.opacity(0.05)

        // Text colors
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.5)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let full: CGFloat = 999
    }

    // MARK: - Animation Durations

    enum Animation {
        /// Quick interactions (button presses, toggles)
        static let quick: Double = 0.15
        /// Standard transitions
        static let standard: Double = 0.25
        /// Smooth state changes
        static let smooth: Double = 0.35
        /// Breathing animation cycle (eco mode)
        static let breathing: Double = 2.0
        /// Background gradient transition
        static let backgroundTransition: Double = 2.0
        /// Spring response for bouncy animations
        static let springResponse: Double = 0.35
        /// Spring damping for bouncy animations
        static let springDamping: Double = 0.75
    }

    // MARK: - Shadows

    enum Shadow {
        static let small = (color: Color.black.opacity(0.1), radius: CGFloat(4), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.15), radius: CGFloat(12), y: CGFloat(6))
        static let large = (color: Color.black.opacity(0.2), radius: CGFloat(20), y: CGFloat(10))
        static let glow = (color: Colors.flameOrange.opacity(0.4), radius: CGFloat(20), y: CGFloat(0))
    }

    // MARK: - Sizes

    enum Size {
        /// Flame indicator sizes
        static let flameIndicatorSmall: CGFloat = 80
        static let flameIndicatorMedium: CGFloat = 120
        static let flameIndicatorLarge: CGFloat = 200

        /// Button sizes
        static let buttonHeight: CGFloat = 50
        static let iconButtonSize: CGFloat = 44

        /// Slider dimensions
        static let sliderTrackHeight: CGFloat = 8
        static let sliderThumbSize: CGFloat = 28
    }
}

// MARK: - Glass Card Modifier

/// Applies liquid glass morphism effect to a view
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = FyrDesign.Radius.lg
    var intensity: GlassIntensity = .standard

    enum GlassIntensity {
        case subtle
        case standard
        case strong

        var backgroundOpacity: (start: Double, end: Double) {
            switch self {
            case .subtle: return (0.04, 0.01)
            case .standard: return (0.08, 0.02)
            case .strong: return (0.12, 0.04)
            }
        }

        var borderOpacity: Double {
            switch self {
            case .subtle: return 0.1
            case .standard: return 0.2
            case .strong: return 0.3
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(intensity.backgroundOpacity.start),
                                Color.white.opacity(intensity.backgroundOpacity.end)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(intensity.borderOpacity),
                                        Color.white.opacity(intensity.borderOpacity * 0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(
                color: FyrDesign.Shadow.medium.color,
                radius: FyrDesign.Shadow.medium.radius,
                y: FyrDesign.Shadow.medium.y
            )
    }
}

// MARK: - Glow Effect Modifier

/// Applies a colored glow effect behind a view
struct GlowEffect: ViewModifier {
    var color: Color
    var radius: CGFloat = 20
    var intensity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(intensity), radius: radius)
            .shadow(color: color.opacity(intensity * 0.5), radius: radius * 0.5)
    }
}

// MARK: - Dynamic Background

/// Animated gradient background that transitions between warm (on) and cool (off) states
struct DynamicBackground: View {
    let isFireplaceOn: Bool

    var body: some View {
        LinearGradient(
            colors: isFireplaceOn
                ? [FyrDesign.Colors.warmGradientStart, FyrDesign.Colors.warmGradientEnd]
                : [FyrDesign.Colors.coolGradientStart, FyrDesign.Colors.coolGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: FyrDesign.Animation.backgroundTransition), value: isFireplaceOn)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply glass card effect with customizable corner radius and intensity
    func glassCard(
        cornerRadius: CGFloat = FyrDesign.Radius.lg,
        intensity: GlassCard.GlassIntensity = .standard
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, intensity: intensity))
    }

    /// Apply glow effect
    func glow(color: Color, radius: CGFloat = 20, intensity: Double = 0.4) -> some View {
        modifier(GlowEffect(color: color, radius: radius, intensity: intensity))
    }
}

// MARK: - Flame Color Gradient

extension FyrDesign.Colors {
    /// Returns a gradient color based on flame intensity (0-1)
    static func flameColor(intensity: Double) -> Color {
        let clampedIntensity = max(0, min(1, intensity))

        if clampedIntensity < 0.33 {
            // Yellow to orange transition
            let localIntensity = clampedIntensity / 0.33
            return blend(flameYellow, flameOrange, amount: localIntensity)
        } else if clampedIntensity < 0.66 {
            // Orange to red transition
            let localIntensity = (clampedIntensity - 0.33) / 0.33
            return blend(flameOrange, flameRed, amount: localIntensity)
        } else {
            // Red stays red at high intensity
            return flameRed
        }
    }

    /// Blend two colors together
    private static func blend(_ color1: Color, _ color2: Color, amount: Double) -> Color {
        // SwiftUI Color blending
        let clampedAmount = max(0, min(1, amount))

        // Use UIColor for proper blending
        let uiColor1 = UIColor(color1)
        let uiColor2 = UIColor(color2)

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let r = r1 + (r2 - r1) * clampedAmount
        let g = g1 + (g2 - g1) * clampedAmount
        let b = b1 + (b2 - b1) * clampedAmount

        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Previews

#Preview("Glass Cards") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)

        VStack(spacing: 20) {
            Text("Subtle Glass")
                .padding()
                .glassCard(intensity: .subtle)

            Text("Standard Glass")
                .padding()
                .glassCard(intensity: .standard)

            Text("Strong Glass")
                .padding()
                .glassCard(intensity: .strong)
        }
        .foregroundStyle(.white)
    }
}

#Preview("Flame Colors") {
    ZStack {
        Color.black.ignoresSafeArea()

        HStack(spacing: 20) {
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                Circle()
                    .fill(FyrDesign.Colors.flameColor(intensity: intensity))
                    .frame(width: 50, height: 50)
                    .glow(color: FyrDesign.Colors.flameColor(intensity: intensity))
            }
        }
    }
}
