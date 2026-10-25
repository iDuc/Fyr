import SwiftUI

/// The fire, drawn: three layered flame tongues over a glowing bed.
///
/// - Burning: the flame flickers; its height follows the last set flame height.
/// - Wave mode: the flame also rises and falls slowly between low and the set
///   height, as the fireplace does.
/// - Off: only the bed and a faint outline remain.
///
/// Respects Reduce Motion (a still flame), and can be drawn still for widgets.
struct FlameView: View {
    var isOn: Bool
    /// Flame height 0-100 %.
    var flameHeight: Int
    var waveMode: Bool = false
    /// Animate the flicker (off in widgets, where views cannot animate).
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Grows from 0 (off) to 1 (burning) when the fire is lit or put out.
    @State private var ignition: Double = 0

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
                    Canvas { canvas, size in
                        draw(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                // Widgets draw one frame.
                Canvas { canvas, size in
                    draw(in: &canvas, size: size, time: 0)
                }
            }
        }
        .onAppear { ignition = isOn ? 1 : 0 }
        .onChange(of: isOn) { _, on in
            withAnimation(reduceMotion || !animated ? nil : .easeInOut(duration: on ? 1.4 : 0.9)) {
                ignition = on ? 1 : 0
            }
        }
        .accessibilityHidden(true)
    }

    private var isAnimating: Bool {
        animated && !reduceMotion && (isOn || ignition > 0)
    }

    // MARK: - Drawing

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = size.width
        let height = size.height
        let base = height * 0.86
        let centerX = width / 2
        let still = !isAnimating

        // 0.45 ... 1.0 of the available height, from the set flame height.
        let setLevel = 0.45 + 0.55 * Double(max(0, min(100, flameHeight))) / 100
        var level = setLevel
        if waveMode {
            // Wave mode: between low and the set height, one slow cycle.
            let phase = still ? 0.75 : (sin(time * 2 * .pi / FyrDesign.Animation.breathing) + 1) / 2
            level = 0.45 + (setLevel - 0.45) * (0.35 + 0.65 * phase)
        }
        let burn = still ? (isOn ? 1 : 0) : ignition
        let flameHeightPoints = height * 0.78 * level * burn
        let flameWidth = width * 0.26

        drawBed(in: &canvas, centerX: centerX, base: base, width: width, burn: burn)

        if burn < 0.02 {
            drawOutline(in: &canvas, centerX: centerX, base: base, width: flameWidth, height: height * 0.5)
            return
        }

        // Glow behind the flame.
        // Stays inside the canvas, so the glow never shows a square edge.
        let glowRadius = min(max(flameWidth, flameHeightPoints) * 1.1, min(width, height) / 2)
        let glowCenter = CGPoint(x: centerX, y: base - flameHeightPoints * 0.38)
        canvas.drawLayer { layer in
            layer.opacity = (colorScheme == .dark ? 0.55 : 0.4) * burn
            layer.fill(
                Path(ellipseIn: CGRect(x: glowCenter.x - glowRadius, y: glowCenter.y - glowRadius,
                                       width: glowRadius * 2, height: glowRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [FyrDesign.Colors.glow, FyrDesign.Colors.glow.opacity(0)]),
                    center: glowCenter, startRadius: 0, endRadius: glowRadius
                )
            )
        }

        // Three tongues: outer red-orange, middle orange, a bright core.
        let layers: [(scale: Double, widthScale: Double, colors: [Color], seed: Double)] = [
            (1.0, 1.0, [FyrDesign.Colors.flameRed, FyrDesign.Colors.flameOrange], 0),
            (0.78, 0.72, [FyrDesign.Colors.flameOrange, FyrDesign.Colors.flameYellow], 1.7),
            (0.48, 0.42, [FyrDesign.Colors.flameYellow, .white.opacity(0.95)], 3.1),
        ]
        for layer in layers {
            let flicker = still ? 0 : 0.05 * sin(time * 7.1 + layer.seed) + 0.035 * sin(time * 12.7 + layer.seed * 2)
            let sway = still ? 0 : flameWidth * 0.16 * sin(time * 2.3 + layer.seed) + flameWidth * 0.06 * sin(time * 5.9 + layer.seed)
            let h = flameHeightPoints * layer.scale * (1 + flicker)
            let w = flameWidth * layer.widthScale * (1 - flicker * 0.5)
            let path = Self.tongue(centerX: centerX, base: base, width: w, height: h, sway: sway)
            canvas.fill(path, with: .linearGradient(
                Gradient(colors: layer.colors),
                startPoint: CGPoint(x: centerX, y: base),
                endPoint: CGPoint(x: centerX, y: base - h)
            ))
        }
    }

    /// The burner bed: a thin rounded bar that glows while the fire burns.
    private func drawBed(in canvas: inout GraphicsContext, centerX: CGFloat, base: CGFloat, width: CGFloat, burn: Double) {
        let bedWidth = width * 0.62
        let rect = CGRect(x: centerX - bedWidth / 2, y: base + 6, width: bedWidth, height: 5)
        let bed = Path(roundedRect: rect, cornerRadius: 2.5)
        canvas.fill(bed, with: .color(FyrDesign.Colors.textPrimary.opacity(0.14)))
        if burn > 0 {
            canvas.fill(bed, with: .linearGradient(
                Gradient(colors: [.clear, FyrDesign.Colors.flameOrange.opacity(0.9 * burn), .clear]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            ))
        }
    }

    /// The outline of a flame, shown when the fire is off.
    private func drawOutline(in canvas: inout GraphicsContext, centerX: CGFloat, base: CGFloat, width: CGFloat, height: CGFloat) {
        // Two leaning tongues, so it reads as a flame and not as a drop.
        let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        let color = GraphicsContext.Shading.color(FyrDesign.Colors.textPrimary.opacity(0.24))
        canvas.stroke(Self.tongue(centerX: centerX, base: base, width: width, height: height, sway: width * 0.32),
                      with: color, style: style)
        canvas.stroke(Self.tongue(centerX: centerX, base: base, width: width * 0.5, height: height * 0.48, sway: -width * 0.12),
                      with: color, style: style)
    }

    /// One flame tongue: a rounded base that narrows to a tip, leaning by `sway`.
    static func tongue(centerX: CGFloat, base: CGFloat, width: CGFloat, height: CGFloat, sway: CGFloat) -> Path {
        var path = Path()
        let tip = CGPoint(x: centerX + sway, y: base - height)
        path.move(to: CGPoint(x: centerX, y: base))
        path.addCurve(
            to: tip,
            control1: CGPoint(x: centerX + width * 1.05, y: base - height * 0.02),
            control2: CGPoint(x: centerX + width * 0.22 + sway * 0.4, y: base - height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: base),
            control1: CGPoint(x: centerX - width * 0.22 + sway * 0.4, y: base - height * 0.62),
            control2: CGPoint(x: centerX - width * 1.05, y: base - height * 0.02)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Burning") {
    FlameView(isOn: true, flameHeight: 70)
        .frame(width: 260, height: 300)
        .background(DynamicBackground(isFireplaceOn: true))
}

#Preview("Wave") {
    FlameView(isOn: true, flameHeight: 90, waveMode: true)
        .frame(width: 260, height: 300)
        .background(DynamicBackground(isFireplaceOn: true))
}

#Preview("Off") {
    FlameView(isOn: false, flameHeight: 50)
        .frame(width: 260, height: 300)
        .background(DynamicBackground(isFireplaceOn: false))
}
