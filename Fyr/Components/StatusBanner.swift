import SwiftUI

/// Subtle banner showing connection status
/// Always visible to provide connection feedback
struct StatusBanner: View {
    @Environment(Fireplace.self) private var fireplace

    var body: some View {
        Group {
            switch fireplace.connectionState {
            case .connected:
                bannerContent(
                    icon: "wifi",
                    text: String(localized: "Connected"),
                    color: .green,
                    showPulse: false
                )

            case .connecting:
                bannerContent(
                    icon: "wifi",
                    text: String(localized: "Connecting..."),
                    color: .secondary,
                    showPulse: true
                )

            case .reconnecting:
                bannerContent(
                    icon: "wifi",
                    text: String(localized: "Reconnecting..."),
                    color: .orange,
                    showPulse: true
                )

            case .disconnected:
                bannerContent(
                    icon: "wifi.slash",
                    text: String(localized: "Not connected"),
                    color: .secondary,
                    showPulse: false
                )

            case .failed(let reason):
                bannerContent(
                    icon: "wifi.exclamationmark",
                    text: reason,
                    color: .red,
                    showPulse: false
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fireplace.connectionState)
    }

    @ViewBuilder
    private func bannerContent(icon: String, text: String, color: Color, showPulse: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .imageScale(.small)
                .symbolEffect(.pulse, options: .repeating, isActive: showPulse)

            Text(text)
                .font(.caption)

            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Error Banner

/// Banner for displaying fireplace errors
struct ErrorBanner: View {
    let errorCode: FireplaceErrorCode

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: errorCode.systemImage)
                    .foregroundStyle(.red)

                Text(errorCode.friendlyTitle)
                    .font(.headline)

                Spacer()

                Button {
                    showDetails.toggle()
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            // Details (expandable)
            if showDetails {
                Text(errorCode.friendlyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text(errorCode.resetInstructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview("Status Banner - Reconnecting") {
    let fireplace = Fireplace()
    fireplace.connectionState = .reconnecting

    return StatusBanner()
        .environment(fireplace)
}

#Preview("Error Banner") {
    ErrorBanner(errorCode: .f01)
        .padding()
}
