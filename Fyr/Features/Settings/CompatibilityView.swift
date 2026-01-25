import SwiftUI

/// Detailed compatibility information for DRU fireplaces
struct CompatibilityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedSeries: Set<String> = []

    var body: some View {
        ZStack {
            // Dynamic background - cool gradient
            DynamicBackground(isFireplaceOn: false)

            ScrollView {
                VStack(spacing: FyrDesign.Spacing.lg) {
                    // Requirements section
                    requirementsSection

                    // Compatible models section
                    compatibleModelsSection

                    // Not compatible section
                    notCompatibleSection

                    // Troubleshooting section
                    troubleshootingSection
                }
                .padding(FyrDesign.Spacing.md)
            }
        }
        .navigationTitle(String(localized: "Compatibility"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .searchable(text: $searchText, prompt: String(localized: "Search models"))
    }

    // MARK: - Requirements Section

    @ViewBuilder
    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Requirements"), icon: "checkmark.shield")

            VStack(spacing: FyrDesign.Spacing.xs) {
                requirementRow(
                    icon: "flame.fill",
                    title: String(localized: "DRU Fireplace"),
                    description: String(localized: "Maestro, Metro, or Lugo series with Eco Wave")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                requirementRow(
                    icon: "wifi",
                    title: String(localized: "Honeywell WiFi Bridge"),
                    description: String(localized: "Model BRDG-03EM01 (older RCH control system)")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                requirementRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: String(localized: "Same Network"),
                    description: String(localized: "iPhone and bridge on the same WiFi network")
                )
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    @ViewBuilder
    private func requirementRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: FyrDesign.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(FyrDesign.Colors.ecoGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, FyrDesign.Spacing.xs)
    }

    // MARK: - Compatible Models Section

    @ViewBuilder
    private var compatibleModelsSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Compatible Models"), icon: "checkmark.circle")

            VStack(spacing: FyrDesign.Spacing.sm) {
                seriesCard(
                    series: "Maestro",
                    models: CompatibilityData.maestroModels,
                    color: FyrDesign.Colors.flameOrange
                )

                seriesCard(
                    series: "Metro",
                    models: CompatibilityData.metroModels,
                    color: FyrDesign.Colors.flameYellow
                )

                seriesCard(
                    series: "Lugo",
                    models: CompatibilityData.lugoModels,
                    color: FyrDesign.Colors.ecoGreen
                )
            }
        }
    }

    @ViewBuilder
    private func seriesCard(series: String, models: [String], color: Color) -> some View {
        let filteredModels = searchText.isEmpty
            ? models
            : models.filter { $0.localizedCaseInsensitiveContains(searchText) }

        if !filteredModels.isEmpty || searchText.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.spring(
                        response: FyrDesign.Animation.springResponse,
                        dampingFraction: FyrDesign.Animation.springDamping
                    )) {
                        if expandedSeries.contains(series) {
                            expandedSeries.remove(series)
                        } else {
                            expandedSeries.insert(series)
                        }
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                            .glow(color: color, radius: 4, intensity: 0.5)

                        Text("DRU \(series)")
                            .font(.headline)
                            .foregroundStyle(FyrDesign.Colors.textPrimary)

                        Spacer()

                        Text(String(localized: "\(filteredModels.count) models"))
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textSecondary)

                        Image(systemName: expandedSeries.contains(series) ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textTertiary)
                    }
                    .padding(FyrDesign.Spacing.md)
                }
                .buttonStyle(.plain)

                if expandedSeries.contains(series) {
                    VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                        ForEach(filteredModels, id: \.self) { model in
                            HStack(spacing: FyrDesign.Spacing.sm) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(FyrDesign.Colors.ecoGreen)

                                Text(model)
                                    .font(.subheadline)
                                    .foregroundStyle(FyrDesign.Colors.textSecondary)

                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, FyrDesign.Spacing.md)
                    .padding(.bottom, FyrDesign.Spacing.md)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Not Compatible Section

    @ViewBuilder
    private var notCompatibleSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Not Compatible"), icon: "xmark.circle")

            VStack(spacing: FyrDesign.Spacing.xs) {
                incompatibleRow(
                    title: String(localized: "DRU Global Series"),
                    reason: String(localized: "No RCH control or app support")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                incompatibleRow(
                    title: String(localized: "DRU Diablo Series"),
                    reason: String(localized: "No RCH control or app support")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                incompatibleRow(
                    title: String(localized: "DRU Virtuo Electric"),
                    reason: String(localized: "Uses Bluetooth only, different protocol")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                incompatibleRow(
                    title: String(localized: "Newer Bluetooth-only RCH"),
                    reason: String(localized: "No WiFi bridge support")
                )
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    @ViewBuilder
    private func incompatibleRow(title: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: FyrDesign.Spacing.md) {
            Image(systemName: "xmark")
                .foregroundStyle(FyrDesign.Colors.error)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(reason)
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(.vertical, FyrDesign.Spacing.xs)
    }

    // MARK: - Troubleshooting Section

    @ViewBuilder
    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Is My Fireplace Compatible?"), icon: "questionmark.circle")

            VStack(alignment: .leading, spacing: FyrDesign.Spacing.md) {
                checklistItem(
                    number: 1,
                    question: String(localized: "Is it a DRU Maestro, Metro, or Lugo?"),
                    detail: String(localized: "Check the model name on your fireplace or documentation")
                )

                checklistItem(
                    number: 2,
                    question: String(localized: "Does it have \"Eco Wave\" in the name?"),
                    detail: String(localized: "Models without Eco Wave lack app control features")
                )

                checklistItem(
                    number: 3,
                    question: String(localized: "Do you have the WiFi bridge?"),
                    detail: String(localized: "The Honeywell BRDG-03EM01 is sold separately")
                )

                checklistItem(
                    number: 4,
                    question: String(localized: "Is the bridge connected to your router?"),
                    detail: String(localized: "It needs an Ethernet cable to your router")
                )
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()

            // Tip
            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                HStack(spacing: FyrDesign.Spacing.sm) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(FyrDesign.Colors.flameYellow)
                    Text(String(localized: "Tip"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }

                Text(String(localized: "If the official DRU Fireplace app can control your fireplace, Fyr should work too. Both apps use the same ModbusTCP protocol."))
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard(intensity: .subtle)
        }
    }

    @ViewBuilder
    private func checklistItem(number: Int, question: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: FyrDesign.Spacing.md) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(FyrDesign.Colors.textPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(FyrDesign.Colors.flameOrange)
                )

            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                Text(question)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }

            Spacer()
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: FyrDesign.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(FyrDesign.Colors.flameOrange)
                .font(.subheadline)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
        .textCase(.uppercase)
    }
}

// MARK: - Compatibility Data

enum CompatibilityData {
    static let maestroModels = [
        "Maestro 60 Eco Wave",
        "Maestro 60/2 Eco Wave",
        "Maestro 60/3 Eco Wave",
        "Maestro 75 Eco Wave",
        "Maestro 75 Tall Eco Wave",
        "Maestro 75 Tunnel Eco Wave",
        "Maestro 75 Tunnel Tall Eco Wave",
        "Maestro 75XTU Eco Wave",
        "Maestro 80/2 Eco Wave",
        "Maestro 80/3 Eco Wave",
        "Maestro 100 Eco Wave",
        "Maestro 105/2 Eco Wave",
        "Maestro 105/3 Eco Wave"
    ]

    static let metroModels = [
        "Metro 100XT Eco Wave",
        "Metro 100XT/2 Eco Wave",
        "Metro 100XT/3 Eco Wave",
        "Metro 100XT Tunnel Eco Wave",
        "Metro 130XT Eco Wave",
        "Metro 130XT/2 Eco Wave",
        "Metro 130XT/3 Eco Wave",
        "Metro 130XT Tunnel Eco Wave",
        "Metro 150XT Eco Wave",
        "Metro 150XT Tunnel Eco Wave",
        "Metro 200XT Eco Wave",
        "Metro 200XT Tunnel Eco Wave"
    ]

    static let lugoModels = [
        "Lugo 80/2 Eco Wave",
        "Lugo 80/3 Eco Wave"
    ]
}

// MARK: - Preview

#Preview("Compatibility") {
    NavigationStack {
        CompatibilityView()
    }
}
