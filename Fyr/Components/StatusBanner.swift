import SwiftUI

/// A fault reported by the fireplace (register 40204), with what it means and
/// how to reset it.
struct ErrorBanner: View {
    let errorCode: FireplaceErrorCode

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            Button {
                withAnimation(FyrDesign.Animation.spring) { showDetails.toggle() }
            } label: {
                HStack {
                    Label(errorCode.friendlyTitle, systemImage: errorCode.systemImage)
                        .font(.headline)
                        .foregroundStyle(FyrDesign.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                        .foregroundStyle(FyrDesign.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(showDetails ? "Hides the details" : "Shows what to do"))

            if showDetails {
                Text(errorCode.friendlyDescription)
                    .font(.subheadline)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                Divider()
                Text(errorCode.resetInstructions)
                    .font(.footnote)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
            }
        }
        .padding(FyrDesign.Spacing.md)
        .glassCard(cornerRadius: FyrDesign.Radius.md, tint: FyrDesign.Colors.error)
        .accessibilityIdentifier("dashboard.fault")
    }
}

#Preview("Error Banner") {
    ErrorBanner(errorCode: .f01)
        .padding()
}
