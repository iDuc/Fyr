import SwiftUI

/// On and off, following the safety policy:
/// - Off: one tap, always.
/// - On: only the deliberate swipe-to-ignite gesture (`IgnitionAuthorization.appSlider`).
struct PowerControl: View {
    @Environment(Fireplace.self) private var fireplace

    let onIgnite: () async -> Void
    let onTurnOff: () async -> Void

    var body: some View {
        Group {
            if fireplace.isOn {
                TurnOffButton(action: onTurnOff)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                IgnitionSlider(onIgnite: onIgnite)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(FyrDesign.Animation.spring, value: fireplace.isOn)
    }
}

/// Turns the fire off with one tap.
struct TurnOffButton: View {
    @Environment(Fireplace.self) private var fireplace

    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: FyrDesign.Spacing.sm) {
                if fireplace.isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: "power")
                        .fontWeight(.semibold)
                }
                Text("Turn Off")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: FyrDesign.Size.buttonHeight - 16)
        }
        .buttonStyle(.glass)
        .controlSize(.extraLarge)
        .tint(FyrDesign.Colors.textPrimary)
        .disabled(fireplace.isProcessing)
        .sensoryFeedback(.impact(weight: .medium), trigger: fireplace.isOn) { wasOn, isOn in wasOn && !isOn }
        .accessibilityHint(Text("Turns the fireplace off"))
        .accessibilityIdentifier("dashboard.turnOff")
    }
}

/// Swipe-to-ignite: the only way to light the fire from inside the app.
/// Multi-stage haptics while dragging; VoiceOver users get a named action.
struct IgnitionSlider: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onIgnite: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var hapticStage = 0
    @State private var ignitions = 0
    /// VoiceOver cannot swipe; its "Light the fire" action asks first instead.
    @State private var confirmsAccessibleIgnition = false

    private let thumbSize: CGFloat = 60
    private let inset: CGFloat = 6
    /// Share of the track the thumb must travel.
    private let threshold: CGFloat = 0.82

    private var isEnabled: Bool {
        fireplace.lastStatusUpdate != nil && !fireplace.isProcessing && fireplace.connectionState != .connecting
    }

    var body: some View {
        GeometryReader { proxy in
            let maxOffset = max(1, proxy.size.width - thumbSize - inset * 2)
            let progress = min(1, max(0, dragOffset / maxOffset))

            ZStack(alignment: .leading) {
                // Ember fill that follows the thumb.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [FyrDesign.Colors.flameOrange.opacity(0.15), FyrDesign.Colors.flameOrange.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: dragOffset + thumbSize + inset * 2)
                    .opacity(isDragging ? 1 : 0)

                label
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumbSize)
                    .opacity(1 - progress * 1.4)

                thumb
                    .offset(x: inset + dragOffset)
                    .gesture(dragGesture(maxOffset: maxOffset))
            }
            .frame(height: thumbSize + inset * 2)
            .glassEffect(.regular.interactive(), in: Capsule())
            .clipShape(Capsule())
        }
        .frame(height: thumbSize + inset * 2)
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
        .sensoryFeedback(.success, trigger: ignitions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Slide to ignite"))
        .accessibilityHint(Text("Use the action Light the fire to light the fireplace."))
        .accessibilityAction(named: Text("Light the fire")) {
            guard isEnabled else { return }
            confirmsAccessibleIgnition = true
        }
        .confirmationDialog(Text("Light the fireplace now?"), isPresented: $confirmsAccessibleIgnition, titleVisibility: .visible) {
            Button("Light the Fire") {
                ignitions += 1
                Task { await onIgnite() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("dashboard.ignite")
    }

    @ViewBuilder
    private var label: some View {
        if fireplace.isProcessing {
            ProgressView()
        } else {
            HStack(spacing: FyrDesign.Spacing.xs) {
                Text("Slide to ignite")
                Image(systemName: "chevron.right.2")
                    .font(.footnote.weight(.semibold))
                    .symbolEffect(.wiggle.right, options: .repeat(.periodic(delay: 3)), isActive: !reduceMotion && isEnabled)
            }
            .font(.headline)
            .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
    }

    private var thumb: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [FyrDesign.Colors.flameYellow, FyrDesign.Colors.flameOrange, FyrDesign.Colors.flameRed],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: FyrDesign.Colors.flameOrange.opacity(0.35), radius: isDragging ? 14 : 6, y: 2)
            .scaleEffect(isDragging ? 1.06 : 1)
            .animation(FyrDesign.Animation.spring, value: isDragging)
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                dragOffset = max(0, min(maxOffset, value.translation.width))
                let stage = Int(dragOffset / maxOffset * 4)
                if stage != hapticStage {
                    hapticStage = stage
                    if stage > 0 {
                        UIImpactFeedbackGenerator(style: stage >= 3 ? .heavy : .light).impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                if dragOffset / maxOffset >= threshold {
                    ignitions += 1
                    Task { await onIgnite() }
                }
                withAnimation(FyrDesign.Animation.spring) {
                    dragOffset = 0
                    isDragging = false
                }
                hapticStage = 0
            }
    }
}

#Preview("Power – off") {
    let fireplace = Fireplace.preview
    fireplace.isOn = false
    return PowerControl(onIgnite: {}, onTurnOff: {})
        .padding()
        .background(DynamicBackground(isFireplaceOn: false))
        .environment(fireplace)
}

#Preview("Power – on") {
    PowerControl(onIgnite: {}, onTurnOff: {})
        .padding()
        .background(DynamicBackground(isFireplaceOn: true))
        .environment(Fireplace.preview)
}
