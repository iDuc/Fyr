import SwiftUI

/// Large power button for turning the fireplace on/off
struct PowerButton: View {
    @Environment(Fireplace.self) private var fireplace

    let onTap: () async -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            Task {
                await onTap()
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        fireplace.isOn ? Color.orange : Color.gray.opacity(0.3),
                        lineWidth: 4
                    )
                    .frame(width: 120, height: 120)

                // Fill
                Circle()
                    .fill(fillColor)
                    .frame(width: 110, height: 110)

                // Power icon
                Image(systemName: "power")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(fireplace.isProcessing || !fireplace.connectionState.isConnected)
        .opacity(fireplace.connectionState.isConnected ? 1.0 : 0.5)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: fireplace.isOn)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Computed Properties

    private var fillColor: Color {
        if fireplace.isProcessing {
            return .gray.opacity(0.3)
        }
        return fireplace.isOn ? .orange : .gray.opacity(0.2)
    }

    private var iconColor: Color {
        if fireplace.isProcessing {
            return .gray
        }
        return fireplace.isOn ? .white : .gray
    }

    private var accessibilityLabel: String {
        fireplace.isOn ? "Power button, fireplace is on" : "Power button, fireplace is off"
    }

    private var accessibilityHint: String {
        if fireplace.isProcessing {
            return "Processing command"
        }
        return fireplace.isOn ? "Double tap to turn off" : "Double tap to turn on"
    }
}

// MARK: - Preview

#Preview("Power Button - Off") {
    let fireplace = Fireplace.preview
    fireplace.isOn = false

    return PowerButton { }
        .environment(fireplace)
}

#Preview("Power Button - On") {
    let fireplace = Fireplace.preview

    return PowerButton { }
        .environment(fireplace)
}
