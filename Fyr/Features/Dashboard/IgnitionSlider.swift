import SwiftUI

/// Swipe-to-ignite slider for turning the fireplace on/off
/// Features glass morphism design and multi-stage haptic feedback
struct IgnitionSlider: View {
    @Environment(Fireplace.self) private var fireplace

    let onIgnite: () async -> Void
    let onExtinguish: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var hapticStage: Int = 0

    private let trackWidth: CGFloat = 280
    private let thumbSize: CGFloat = 64
    private let threshold: CGFloat = 0.7

    private var maxOffset: CGFloat {
        trackWidth - thumbSize - 16
    }

    private var progress: CGFloat {
        min(1, max(0, dragOffset / maxOffset))
    }

    private var isEnabled: Bool {
        fireplace.connectionState.isConnected && !fireplace.isProcessing
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Track background with glass effect
            trackBackground

            // Progress fill
            progressFill

            // Label
            sliderLabel

            // Draggable thumb
            thumb
        }
        .frame(width: trackWidth, height: thumbSize + 16)
        .clipShape(Capsule())
        .opacity(isEnabled ? 1.0 : 0.5)
        .allowsHitTesting(isEnabled)
        .sensoryFeedback(.impact(weight: .medium), trigger: fireplace.isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Track Background

    @ViewBuilder
    private var trackBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        FyrDesign.Colors.glassHighlight,
                        FyrDesign.Colors.glassBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Capsule()
                    .stroke(
                        fireplace.isOn
                            ? FyrDesign.Colors.flameOrange.opacity(0.4)
                            : FyrDesign.Colors.glassBorder,
                        lineWidth: 1.5
                    )
            }
    }

    // MARK: - Progress Fill

    @ViewBuilder
    private var progressFill: some View {
        if isDragging {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: fireplace.isOn
                            ? [Color.gray.opacity(0.2), Color.gray.opacity(0.4)]
                            : [FyrDesign.Colors.flameOrange.opacity(0.2), FyrDesign.Colors.flameOrange.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: dragOffset + thumbSize + 8)
                .animation(.easeOut(duration: 0.1), value: dragOffset)
        }
    }

    // MARK: - Label

    @ViewBuilder
    private var sliderLabel: some View {
        HStack {
            Spacer()

            if fireplace.isProcessing {
                ProgressView()
                    .tint(FyrDesign.Colors.textSecondary)
            } else {
                Text(labelText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
            }

            Spacer()
        }
        .opacity(isDragging ? 0.3 : 1.0)
    }

    private var labelText: String {
        if fireplace.isOn {
            return String(localized: "Slide to turn off")
        } else {
            return String(localized: "Slide to ignite")
        }
    }

    // MARK: - Thumb

    @ViewBuilder
    private var thumb: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: thumbGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                // Icon
                Image(systemName: thumbIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(thumbIconColor)
            }
            .overlay {
                // Border glow when dragging
                Circle()
                    .stroke(
                        isDragging
                            ? (fireplace.isOn ? Color.gray : FyrDesign.Colors.flameOrange)
                            : Color.clear,
                        lineWidth: 2
                    )
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .offset(x: 8 + dragOffset)
            .gesture(dragGesture)
            .animation(
                .spring(response: FyrDesign.Animation.springResponse, dampingFraction: FyrDesign.Animation.springDamping),
                value: dragOffset
            )
            .animation(
                .spring(response: FyrDesign.Animation.springResponse, dampingFraction: FyrDesign.Animation.springDamping),
                value: isDragging
            )
    }

    private var thumbGradientColors: [Color] {
        if fireplace.isProcessing {
            return [Color.gray.opacity(0.8), Color.gray.opacity(0.6)]
        }
        if isDragging {
            return fireplace.isOn
                ? [Color.gray.opacity(0.8), Color.gray.opacity(0.6)]
                : [FyrDesign.Colors.flameOrange, FyrDesign.Colors.flameRed.opacity(0.8)]
        }
        return fireplace.isOn
            ? [FyrDesign.Colors.flameOrange, FyrDesign.Colors.flameRed.opacity(0.8)]
            : [Color.gray.opacity(0.7), Color.gray.opacity(0.5)]
    }

    private var thumbIcon: String {
        if fireplace.isProcessing {
            return "ellipsis"
        }
        return fireplace.isOn ? "flame.fill" : "flame"
    }

    private var thumbIconColor: Color {
        if fireplace.isProcessing {
            return FyrDesign.Colors.textSecondary
        }
        return .white
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                let newOffset = max(0, min(maxOffset, value.translation.width))
                dragOffset = newOffset

                // Multi-stage haptic feedback
                let newStage = Int(progress * 4) // 0, 1, 2, 3 stages
                if newStage != hapticStage {
                    hapticStage = newStage
                    if newStage > 0 {
                        let generator = UIImpactFeedbackGenerator(style: newStage >= 3 ? .heavy : .light)
                        generator.impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                if progress >= threshold {
                    // Action completed - heavy haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    Task {
                        if fireplace.isOn {
                            await onExtinguish()
                        } else {
                            await onIgnite()
                        }
                    }
                }

                // Reset position
                withAnimation(
                    .spring(response: FyrDesign.Animation.springResponse, dampingFraction: FyrDesign.Animation.springDamping)
                ) {
                    dragOffset = 0
                    isDragging = false
                }
                hapticStage = 0
            }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        fireplace.isOn ? String(localized: "Fireplace is on") : String(localized: "Fireplace is off")
    }

    private var accessibilityHint: String {
        if fireplace.isProcessing {
            return String(localized: "Processing command")
        }
        return fireplace.isOn ? String(localized: "Slide to turn off") : String(localized: "Slide to ignite")
    }
}

// MARK: - Preview

#Preview("Ignition Slider - Off") {
    let fireplace = Fireplace.preview
    fireplace.isOn = false
    fireplace.connectionState = .connected

    return ZStack {
        DynamicBackground(isFireplaceOn: false)

        IgnitionSlider(
            onIgnite: { },
            onExtinguish: { }
        )
        .environment(fireplace)
    }
}

#Preview("Ignition Slider - On") {
    let fireplace = Fireplace.preview
    fireplace.connectionState = .connected

    return ZStack {
        DynamicBackground(isFireplaceOn: true)

        IgnitionSlider(
            onIgnite: { },
            onExtinguish: { }
        )
        .environment(fireplace)
    }
}

#Preview("Ignition Slider - Processing") {
    let fireplace = Fireplace.preview
    fireplace.isProcessing = true
    fireplace.connectionState = .connected

    return ZStack {
        DynamicBackground(isFireplaceOn: true)

        IgnitionSlider(
            onIgnite: { },
            onExtinguish: { }
        )
        .environment(fireplace)
    }
}
