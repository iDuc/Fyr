import SwiftUI
import UIKit

/// Settings view for app configuration with liquid glass design
struct SettingsView: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirmation = false
    @State private var bridgeIPInput: String = ""

    var body: some View {
        ZStack {
            // Dynamic background
            DynamicBackground(isFireplaceOn: fireplace.isOn)

            ScrollView {
                VStack(spacing: FyrDesign.Spacing.lg) {
                    // Connection section
                    connectionSection

                    // Device info section
                    if fireplace.connectionState.isConnected {
                        deviceSection
                    }

                    // Siri & Shortcuts section
                    siriSection

                    // About section
                    aboutSection

                    // Debug section
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(FyrDesign.Spacing.md)
            }
        }
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .confirmationDialog(String(localized: "Reset App?"), isPresented: $showResetConfirmation) {
            Button(String(localized: "Reset"), role: .destructive) {
                settings.reset()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "This will clear all settings and require reconfiguration."))
        }
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Connection"), icon: "antenna.radiowaves.left.and.right")

            VStack(spacing: FyrDesign.Spacing.xs) {
                settingsRow(
                    title: String(localized: "Bridge IP"),
                    value: settings.bridgeIP ?? String(localized: "Not configured")
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                HStack {
                    Text(String(localized: "Status"))
                        .foregroundStyle(FyrDesign.Colors.textPrimary)

                    Spacer()

                    connectionStatusBadge
                }
                .padding(.vertical, FyrDesign.Spacing.sm)

                if fireplace.connectionState.isConnected {
                    Divider()
                        .background(FyrDesign.Colors.glassBorderSubtle)

                    HStack {
                        Text(String(localized: "Signal Strength"))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)

                        Spacer()

                        signalStrengthView
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                Button {
                    settings.hasCompletedOnboarding = false
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(FyrDesign.Colors.flameOrange)
                        Text(String(localized: "Reconfigure Bridge"))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textTertiary)
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    // MARK: - Device Section

    @ViewBuilder
    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Device"), icon: "flame.fill")

            VStack(spacing: FyrDesign.Spacing.xs) {
                settingsRow(
                    title: String(localized: "Fireplace"),
                    value: "DRU 100 XT Metro"
                )

                if let lastUpdate = fireplace.lastStatusUpdate {
                    Divider()
                        .background(FyrDesign.Colors.glassBorderSubtle)

                    HStack {
                        Text(String(localized: "Last Updated"))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)
                        Spacer()
                        Text(lastUpdate, style: .relative)
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    // MARK: - Siri Section

    @ViewBuilder
    private var siriSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Siri & Shortcuts"), icon: "mic.fill")

            VStack(spacing: FyrDesign.Spacing.xs) {
                // Pronunciation tip
                VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                    HStack(spacing: FyrDesign.Spacing.sm) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(FyrDesign.Colors.flameOrange)
                        Text(String(localized: "Say \"Fyr\" like \"Fire\""))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)
                    }

                    Text(String(localized: "Siri recognizes \"Fyr\", \"Fire\", \"Feer\", or \"Fear\""))
                        .font(.caption)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
                .padding(.vertical, FyrDesign.Spacing.sm)

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                // Voice commands examples
                VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
                    Text(String(localized: "Voice Commands (English)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FyrDesign.Colors.textTertiary)

                    VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                        siriExampleRow("Turn on Fyr")
                        siriExampleRow("Turn off Fyr")
                        siriExampleRow("Set flame to 50 percent with Fyr")
                        siriExampleRow("Set temperature with Fyr")
                        siriExampleRow("Turn eco mode on with Fyr")
                        siriExampleRow("Status of Fyr")
                    }
                }
                .padding(.vertical, FyrDesign.Spacing.sm)

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                // Dutch voice commands
                VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
                    Text(String(localized: "Spraakopdrachten (Nederlands)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FyrDesign.Colors.textTertiary)

                    VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                        siriExampleRow("Zet Fyr aan")
                        siriExampleRow("Zet Fyr uit")
                        siriExampleRow("Zet vlam op 50 procent met Fyr")
                        siriExampleRow("Zet eco-modus aan met Fyr")
                        siriExampleRow("Status van Fyr")
                    }
                }
                .padding(.vertical, FyrDesign.Spacing.sm)

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                // Open Shortcuts app
                Button {
                    openShortcutsApp()
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(FyrDesign.Colors.flameOrange)
                        Text(String(localized: "Open Shortcuts App"))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textTertiary)
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                // Tip about custom shortcuts
                VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                    HStack(spacing: FyrDesign.Spacing.sm) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(FyrDesign.Colors.flameYellow)
                        Text(String(localized: "Tip"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                    }

                    Text(String(localized: "The Fyr shortcuts appear automatically in Siri. Create custom shortcuts in the Shortcuts app if you want phrases without the app name (e.g., \"Start the fireplace\")."))
                        .font(.caption)
                        .foregroundStyle(FyrDesign.Colors.textTertiary)
                }
                .padding(.vertical, FyrDesign.Spacing.sm)
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    @ViewBuilder
    private func siriExampleRow(_ phrase: String) -> some View {
        Text("\"\(phrase)\"")
            .font(.callout)
            .foregroundStyle(FyrDesign.Colors.textSecondary)
    }

    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "About"), icon: "info.circle")

            VStack(spacing: FyrDesign.Spacing.xs) {
                settingsRow(
                    title: String(localized: "Version"),
                    value: appVersion
                )

                Divider()
                    .background(FyrDesign.Colors.glassBorderSubtle)

                NavigationLink {
                    CompatibilityView()
                } label: {
                    HStack {
                        Text(String(localized: "Compatibility"))
                            .foregroundStyle(FyrDesign.Colors.textPrimary)
                        Spacer()
                        Text(String(localized: "DRU + Honeywell Bridge"))
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textTertiary)
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    // MARK: - Debug Section

    #if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            sectionHeader(String(localized: "Debug"), icon: "ladybug")

            VStack(spacing: FyrDesign.Spacing.xs) {
                Button {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundStyle(FyrDesign.Colors.error)
                        Text(String(localized: "Reset App"))
                            .foregroundStyle(FyrDesign.Colors.error)
                        Spacer()
                    }
                    .padding(.vertical, FyrDesign.Spacing.sm)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }
    #endif

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

    @ViewBuilder
    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(FyrDesign.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
        .padding(.vertical, FyrDesign.Spacing.sm)
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        HStack(spacing: FyrDesign.Spacing.xs) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
                .glow(color: connectionStatusColor, radius: 4, intensity: 0.6)

            Text(fireplace.connectionState.displayName)
                .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var signalStrengthView: some View {
        HStack(spacing: FyrDesign.Spacing.xxs) {
            // Gradient signal bars
            ForEach(0..<4) { bar in
                let isActive = bar < signalBars
                let barColor = signalBarColor(bar: bar, isActive: isActive)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: 5, height: CGFloat(8 + bar * 4))
                    .glow(
                        color: isActive ? barColor : .clear,
                        radius: 3,
                        intensity: isActive ? 0.5 : 0
                    )
            }

            Text("\(fireplace.signalStrength)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(FyrDesign.Colors.textSecondary)
                .padding(.leading, FyrDesign.Spacing.xs)
        }
    }

    // MARK: - Computed Properties

    private var connectionStatusColor: Color {
        switch fireplace.connectionState {
        case .connected: return FyrDesign.Colors.connected
        case .connecting, .reconnecting: return FyrDesign.Colors.warning
        case .disconnected, .failed: return FyrDesign.Colors.error
        }
    }

    private func signalBarColor(bar: Int, isActive: Bool) -> Color {
        guard isActive else {
            return FyrDesign.Colors.glassHighlight
        }

        // Gradient from green (strong) to yellow (weak)
        switch bar {
        case 0: return .green.opacity(0.7)
        case 1: return .green.opacity(0.85)
        case 2: return .green
        case 3: return FyrDesign.Colors.ecoGreen
        default: return .green
        }
    }

    private var signalBars: Int {
        switch fireplace.signalStrength {
        case 75...100: return 4
        case 50..<75: return 3
        case 25..<50: return 2
        default: return 1
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Preview

#Preview("Settings") {
    NavigationStack {
        SettingsView()
            .environment(Fireplace.preview)
            .environment(SettingsStore.shared)
    }
}
