import SwiftUI
import UIKit

/// Fyr's design tokens. Scandinavian and quiet: warm birch and soot neutrals,
/// one ember accent for fire and a fjord blue for wave mode. Every color
/// adapts to light and dark mode. Shared by the app and the widget extension.
nonisolated enum FyrDesign {

    // MARK: - Colors

    enum Colors {
        // Fire palette, used for the flame itself (the same in both modes).
        static let flameYellow = Color(red: 1.0, green: 0.86, blue: 0.42)
        static let flameOrange = Color(red: 0.96, green: 0.47, blue: 0.16)
        static let flameRed = Color(red: 0.84, green: 0.20, blue: 0.10)
        static let ember = Color(red: 0.72, green: 0.27, blue: 0.10)

        /// The accent for "burning": controls, the on state, the ignite slider.
        static let accent = adaptive(light: (0.80, 0.33, 0.10), dark: (0.98, 0.52, 0.22))

        /// Wave mode: fjord blue.
        static let wave = adaptive(light: (0.17, 0.43, 0.55), dark: (0.47, 0.74, 0.86))
        static let waveSubtle = wave.opacity(0.14)

        // Backgrounds: birch (light) and soot (dark); warmer while the fire burns.
        static let coolGradientStart = adaptive(light: (0.955, 0.945, 0.925), dark: (0.075, 0.078, 0.086))
        static let coolGradientEnd = adaptive(light: (0.905, 0.893, 0.870), dark: (0.110, 0.114, 0.125))
        static let warmGradientStart = adaptive(light: (0.975, 0.944, 0.905), dark: (0.090, 0.060, 0.045))
        static let warmGradientEnd = adaptive(light: (0.955, 0.865, 0.770), dark: (0.180, 0.090, 0.045))
        /// The glow behind a burning flame.
        static let glow = adaptive(light: (0.98, 0.62, 0.30), dark: (0.98, 0.45, 0.14))

        // Status
        static let connected = adaptive(light: (0.20, 0.55, 0.33), dark: (0.42, 0.80, 0.55))
        static let warning = adaptive(light: (0.76, 0.48, 0.05), dark: (0.98, 0.72, 0.28))
        static let error = adaptive(light: (0.75, 0.18, 0.15), dark: (1.0, 0.45, 0.40))

        // Text: soot on birch, birch on soot.
        static let textPrimary = adaptive(light: (0.11, 0.10, 0.09), dark: (0.95, 0.93, 0.90))
        static let textSecondary = textPrimary.opacity(0.68)
        static let textTertiary = textPrimary.opacity(0.48)

        // Hairlines and fills on top of glass.
        static let glassHighlight = textPrimary.opacity(0.06)
        static let glassBackground = textPrimary.opacity(0.04)
        static let glassBorder = textPrimary.opacity(0.16)
        static let glassBorderSubtle = textPrimary.opacity(0.09)

        /// A color with a light and a dark variant (sRGB components).
        static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
            Color(uiColor: UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }
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
        static let lg: CGFloat = 22
        static let xl: CGFloat = 30
        static let full: CGFloat = 999
    }

    // MARK: - Animation

    enum Animation {
        /// Quick interactions (button presses, toggles)
        static let quick: Double = 0.15
        /// Standard transitions
        static let standard: Double = 0.25
        /// Smooth state changes
        static let smooth: Double = 0.35
        /// One wave-mode cycle of the flame visual
        static let breathing: Double = 8.0
        /// Background change between on and off
        static let backgroundTransition: Double = 1.2
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.82

        static var spring: SwiftUI.Animation {
            .spring(response: springResponse, dampingFraction: springDamping)
        }
    }

    // MARK: - Shadows

    enum Shadow {
        static let small = (color: Color.black.opacity(0.08), radius: CGFloat(4), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.10), radius: CGFloat(12), y: CGFloat(6))
        static let large = (color: Color.black.opacity(0.14), radius: CGFloat(20), y: CGFloat(10))
    }

    // MARK: - Sizes

    enum Size {
        static let flameIndicatorSmall: CGFloat = 80
        static let flameIndicatorMedium: CGFloat = 120
        static let flameIndicatorLarge: CGFloat = 200

        static let buttonHeight: CGFloat = 56
        static let iconButtonSize: CGFloat = 44

        static let sliderTrackHeight: CGFloat = 8
        static let sliderThumbSize: CGFloat = 28

        /// A single column never grows wider than this (iPad, open iPhone Duo).
        static let readableWidth: CGFloat = 560
    }
}

// MARK: - Glass Card

/// A Liquid Glass card. `intensity` only changes how strongly the glass is
/// tinted; the material itself is the system's.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = FyrDesign.Radius.lg
    var intensity: GlassIntensity = .standard
    var tint: Color?

    enum GlassIntensity {
        case subtle
        case standard
        case strong
    }

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glass: Glass {
        switch intensity {
        case .subtle: .regular.tint(tint?.opacity(0.08))
        case .standard: .regular.tint(tint?.opacity(0.14))
        case .strong: .regular.tint((tint ?? FyrDesign.Colors.textPrimary).opacity(0.18))
        }
    }
}

// MARK: - Glow Effect

/// A soft colored glow behind a view.
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

// MARK: - Background

/// Birch or soot, warming up from below while the fire burns.
struct DynamicBackground: View {
    let isFireplaceOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isFireplaceOn
                    ? [FyrDesign.Colors.warmGradientStart, FyrDesign.Colors.warmGradientEnd]
                    : [FyrDesign.Colors.coolGradientStart, FyrDesign.Colors.coolGradientEnd],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [FyrDesign.Colors.glow.opacity(isFireplaceOn ? 0.28 : 0), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: FyrDesign.Animation.backgroundTransition), value: isFireplaceOn)
    }
}

// MARK: - View Extensions

extension View {
    /// A Liquid Glass card with continuous corners.
    func glassCard(
        cornerRadius: CGFloat = FyrDesign.Radius.lg,
        intensity: GlassCard.GlassIntensity = .standard,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, intensity: intensity, tint: tint))
    }

    func glow(color: Color, radius: CGFloat = 20, intensity: Double = 0.4) -> some View {
        modifier(GlowEffect(color: color, radius: radius, intensity: intensity))
    }
}

// MARK: - Flame Color

extension FyrDesign.Colors {
    /// Flame color for an intensity of 0...1: yellow, orange, then red.
    static func flameColor(intensity: Double) -> Color {
        let value = max(0, min(1, intensity))
        if value < 0.5 {
            return blend(flameYellow, flameOrange, amount: value / 0.5)
        }
        return blend(flameOrange, flameRed, amount: (value - 0.5) / 0.5)
    }

    private static func blend(_ color1: Color, _ color2: Color, amount: Double) -> Color {
        let amount = max(0, min(1, amount))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(color1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(color2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount)
    }
}

// MARK: - Previews

#Preview("Glass Cards") {
    ZStack {
        DynamicBackground(isFireplaceOn: true)
        VStack(spacing: 20) {
            Text("Subtle Glass").padding().glassCard(intensity: .subtle)
            Text("Standard Glass").padding().glassCard(intensity: .standard)
            Text("Strong Glass").padding().glassCard(intensity: .strong)
        }
        .foregroundStyle(FyrDesign.Colors.textPrimary)
    }
}
