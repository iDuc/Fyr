import SwiftUI
import UIKit

/// Guided onboarding flow for first-time setup with liquid glass design
struct OnboardingFlow: View {
    @Environment(SettingsStore.self) private var settings

    @State private var currentStep: OnboardingStep = .welcome
    @State private var discoveredBridges: [DRUDiscovery.DiscoveredBridge] = []
    @State private var selectedBridge: DRUDiscovery.DiscoveredBridge?
    @State private var manualIP: String = ""
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var connectionTestResult: ConnectionTestResult?
    /// Address that answered Modbus but did not pass the DRU check; the user
    /// may still choose to use it (escape hatch if the check is too strict).
    @State private var unverifiedIP: String?
    @State private var scanTask: Task<Void, Never>?

    enum OnboardingStep: CaseIterable {
        case welcome
        case compatibility
        case networkScan
        case manualEntry
        case connectionTest
        case dhcpAdvice
        case complete

        var stepIndex: Int {
            switch self {
            case .welcome: return 0
            case .compatibility: return 1
            case .networkScan, .manualEntry: return 2
            case .connectionTest: return 3
            case .dhcpAdvice: return 4
            case .complete: return 5
            }
        }

        static var totalSteps: Int { 6 }
    }

    enum ConnectionTestResult {
        case success
        case failed(String)
    }

    var body: some View {
        ZStack {
            // Dynamic background - cool gradient for onboarding
            DynamicBackground(isFireplaceOn: false)

            VStack(spacing: 0) {
                // Enhanced progress indicator with step dots
                progressIndicator
                    .padding(.top, FyrDesign.Spacing.lg)
                    .padding(.horizontal, FyrDesign.Spacing.xl)

                Spacer()

                // Content based on current step
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .compatibility:
                        compatibilityStep
                    case .networkScan:
                        networkScanStep
                    case .manualEntry:
                        manualEntryStep
                    case .connectionTest:
                        connectionTestStep
                    case .dhcpAdvice:
                        dhcpAdviceStep
                    case .complete:
                        completeStep
                    }
                }
                .padding(.horizontal, FyrDesign.Spacing.lg)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Navigation buttons
                navigationButtons
                    .padding(FyrDesign.Spacing.lg)
            }
        }
        .animation(.spring(
            response: FyrDesign.Animation.springResponse,
            dampingFraction: FyrDesign.Animation.springDamping
        ), value: currentStep)
    }

    // MARK: - Progress Indicator

    @ViewBuilder
    private var progressIndicator: some View {
        HStack(spacing: FyrDesign.Spacing.sm) {
            ForEach(0..<OnboardingStep.totalSteps, id: \.self) { step in
                let isActive = step <= currentStep.stepIndex
                let isCurrent = step == currentStep.stepIndex

                Circle()
                    .fill(isActive ? FyrDesign.Colors.flameOrange : FyrDesign.Colors.glassHighlight)
                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                    .glow(
                        color: isActive ? FyrDesign.Colors.flameOrange : .clear,
                        radius: isCurrent ? 6 : 0,
                        intensity: 0.5
                    )
                    .animation(.spring(
                        response: FyrDesign.Animation.springResponse,
                        dampingFraction: FyrDesign.Animation.springDamping
                    ), value: currentStep)

                if step < OnboardingStep.totalSteps - 1 {
                    Rectangle()
                        .fill(step < currentStep.stepIndex
                              ? FyrDesign.Colors.flameOrange.opacity(0.5)
                              : FyrDesign.Colors.glassHighlight)
                        .frame(height: 2)
                }
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var welcomeStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon with glow
            glassHeroIcon(systemName: "flame.fill", color: FyrDesign.Colors.flameOrange, size: 80)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "Welcome to Fyr"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(String(localized: "Control your DRU fireplace with your iPhone. Let's connect to your Honeywell bridge."))
                    .font(.body)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var compatibilityStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon
            glassHeroIcon(systemName: "checkmark.shield", color: FyrDesign.Colors.ecoGreen, size: 60)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "Before You Start"))
                    .font(.title.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(String(localized: "Fyr works with DRU gas fireplaces that have the Honeywell WiFi bridge."))
                    .font(.body)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Requirements card
            VStack(alignment: .leading, spacing: FyrDesign.Spacing.md) {
                compatibilityRequirementRow(
                    icon: "flame.fill",
                    title: String(localized: "DRU Maestro, Metro, or Lugo"),
                    subtitle: String(localized: "with Eco Wave feature")
                )

                compatibilityRequirementRow(
                    icon: "wifi",
                    title: String(localized: "Honeywell WiFi Bridge"),
                    subtitle: String(localized: "Model BRDG-03EM01")
                )

                compatibilityRequirementRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: String(localized: "Same WiFi Network"),
                    subtitle: String(localized: "iPhone and bridge connected")
                )
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()

            // Info note
            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                HStack(spacing: FyrDesign.Spacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                        .font(.caption)
                    Text(String(localized: "Not sure if compatible?"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }

                Text(String(localized: "If the official DRU app works with your fireplace, Fyr will too."))
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard(intensity: .subtle)
        }
    }

    @ViewBuilder
    private func compatibilityRequirementRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: FyrDesign.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(FyrDesign.Colors.ecoGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var networkScanStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon
            glassHeroIcon(systemName: "wifi", color: .blue, size: 60)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "Find Your Bridge"))
                    .font(.title.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                if isScanning {
                    scanningContent
                } else if !discoveredBridges.isEmpty {
                    discoveredBridgesContent
                } else {
                    Text(String(localized: "Make sure your bridge is powered on and connected to the same WiFi network."))
                        .font(.body)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                cancelScan()
                currentStep = .manualEntry
            } label: {
                Text(String(localized: "Enter IP Manually"))
                    .font(.subheadline)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var scanningContent: some View {
        VStack(spacing: FyrDesign.Spacing.md) {
            ProgressView(value: scanProgress)
                .tint(FyrDesign.Colors.flameOrange)
                .padding(.horizontal, FyrDesign.Spacing.xl)

            Text(String(localized: "Scanning network..."))
                .font(.subheadline)
                .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
        .padding(FyrDesign.Spacing.md)
        .glassCard(intensity: .subtle)
    }

    @ViewBuilder
    private var discoveredBridgesContent: some View {
        VStack(spacing: FyrDesign.Spacing.md) {
            Text(String(localized: "Found \(discoveredBridges.count) bridge(s)"))
                .font(.subheadline)
                .foregroundStyle(FyrDesign.Colors.textSecondary)

            VStack(spacing: FyrDesign.Spacing.sm) {
                ForEach(discoveredBridges) { bridge in
                    bridgeSelectionRow(bridge)
                }
            }
        }
    }

    @ViewBuilder
    private func bridgeSelectionRow(_ bridge: DRUDiscovery.DiscoveredBridge) -> some View {
        let isSelected = selectedBridge?.id == bridge.id

        Button {
            withAnimation(.spring(
                response: FyrDesign.Animation.springResponse,
                dampingFraction: FyrDesign.Animation.springDamping
            )) {
                selectedBridge = bridge
            }
        } label: {
            HStack(spacing: FyrDesign.Spacing.md) {
                Image(systemName: "network")
                    .foregroundStyle(isSelected ? FyrDesign.Colors.flameOrange : FyrDesign.Colors.textSecondary)

                Text(bridge.ipAddress)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FyrDesign.Colors.ecoGreen)
                        .glow(color: FyrDesign.Colors.ecoGreen, radius: 4, intensity: 0.5)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard(
                cornerRadius: FyrDesign.Radius.md,
                intensity: isSelected ? .standard : .subtle
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var manualEntryStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon
            glassHeroIcon(systemName: "keyboard", color: FyrDesign.Colors.textSecondary, size: 60)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "Enter Bridge IP"))
                    .font(.title.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(String(localized: "Enter the IP address of your Honeywell bridge. You can find this in your router's DHCP client list."))
                    .font(.body)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Glass-styled text field
            TextField("192.168.1.100", text: $manualIP)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(FyrDesign.Colors.textPrimary)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .padding(FyrDesign.Spacing.md)
                .glassCard(cornerRadius: FyrDesign.Radius.md)

            Button {
                currentStep = .networkScan
            } label: {
                Text(String(localized: "Scan Network Instead"))
                    .font(.subheadline)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var connectionTestStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            if connectionTestResult == nil {
                // Testing state
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(FyrDesign.Colors.flameOrange)

                VStack(spacing: FyrDesign.Spacing.sm) {
                    Text(String(localized: "Testing Connection"))
                        .font(.title.bold())
                        .foregroundStyle(FyrDesign.Colors.textPrimary)

                    Text(String(localized: "Connecting to \(bridgeIPToTest)..."))
                        .font(.body)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
            } else if case .success = connectionTestResult {
                // Success state
                glassHeroIcon(systemName: "checkmark.circle.fill", color: FyrDesign.Colors.ecoGreen, size: 60)

                VStack(spacing: FyrDesign.Spacing.sm) {
                    Text(String(localized: "Connected!"))
                        .font(.title.bold())
                        .foregroundStyle(FyrDesign.Colors.textPrimary)

                    Text(String(localized: "Successfully connected to your DRU bridge."))
                        .font(.body)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                }
            } else if case .failed(let reason) = connectionTestResult {
                // Failed state
                glassHeroIcon(systemName: "xmark.circle.fill", color: FyrDesign.Colors.error, size: 60)

                VStack(spacing: FyrDesign.Spacing.sm) {
                    Text(String(localized: "Connection Failed"))
                        .font(.title.bold())
                        .foregroundStyle(FyrDesign.Colors.textPrimary)

                    Text(reason)
                        .font(.body)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let unverifiedIP {
                    VStack(spacing: FyrDesign.Spacing.xs) {
                        Button(String(localized: "Use this address anyway")) {
                            settings.saveBridge(ip: unverifiedIP, addressing: .default)
                            self.unverifiedIP = nil
                            connectionTestResult = .success
                        }
                        .buttonStyle(.bordered)

                        Text(String(localized: "Only if you are sure this is your DRU bridge."))
                            .font(.caption)
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dhcpAdviceStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon
            glassHeroIcon(systemName: "info.circle", color: .blue, size: 60)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "DHCP Reservation"))
                    .font(.title.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(String(localized: "For reliable connections, we recommend setting up a DHCP reservation for your bridge in your router settings."))
                    .font(.body)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Tips card
            VStack(alignment: .leading, spacing: FyrDesign.Spacing.md) {
                tipRow(number: 1, text: String(localized: "Open your router's admin page"))
                tipRow(number: 2, text: String(localized: "Find DHCP reservation settings"))
                tipRow(number: 3, text: String(localized: "Add a reservation for \(bridgeIPToTest)"))
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    @ViewBuilder
    private var completeStep: some View {
        VStack(spacing: FyrDesign.Spacing.lg) {
            // Hero icon with celebratory glow
            glassHeroIcon(systemName: "checkmark.seal.fill", color: FyrDesign.Colors.ecoGreen, size: 80)

            VStack(spacing: FyrDesign.Spacing.sm) {
                Text(String(localized: "All Set!"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Text(String(localized: "Your fireplace is ready to control with the app or Siri voice commands."))
                    .font(.body)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Siri voice commands card
            VStack(alignment: .leading, spacing: FyrDesign.Spacing.md) {
                HStack(spacing: FyrDesign.Spacing.sm) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(FyrDesign.Colors.flameOrange)
                    Text(String(localized: "Voice Commands"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FyrDesign.Colors.textPrimary)
                }

                // Pronunciation tip
                VStack(alignment: .leading, spacing: FyrDesign.Spacing.xs) {
                    HStack(spacing: FyrDesign.Spacing.sm) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                            .font(.caption)
                        Text(String(localized: "Say \"Fyr\" like \"Fire\""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FyrDesign.Colors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
                    siriPhraseRow("Turn on Fyr")
                    siriPhraseRow("Set flame to 50 percent with Fyr")
                    siriPhraseRow("Turn eco mode on with Fyr")
                    siriPhraseRow("Zet Fyr aan")
                }

                // Open Shortcuts button
                Button {
                    openShortcutsApp()
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text(String(localized: "View All in Shortcuts App"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.flameOrange)
                    .padding(.top, FyrDesign.Spacing.xs)
                }
            }
            .padding(FyrDesign.Spacing.md)
            .glassCard()
        }
    }

    @ViewBuilder
    private func siriPhraseRow(_ phrase: String) -> some View {
        Text("\"\(phrase)\"")
            .font(.callout)
            .foregroundStyle(FyrDesign.Colors.textSecondary)
    }

    private func openShortcutsApp() {
        // Open Shortcuts app to the Fyr app shortcuts
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: FyrDesign.Spacing.md) {
            // Back button
            if currentStep != .welcome && currentStep != .complete {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: FyrDesign.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text(String(localized: "Back"))
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .padding(.horizontal, FyrDesign.Spacing.lg)
                    .padding(.vertical, FyrDesign.Spacing.md)
                    .glassCard(cornerRadius: FyrDesign.Radius.md, intensity: .subtle)
                }
            }

            Spacer()

            // Primary action button
            Button {
                goNext()
            } label: {
                HStack(spacing: FyrDesign.Spacing.xs) {
                    Text(nextButtonTitle)

                    if currentStep != .complete && connectionTestResult != nil || currentStep == .welcome || currentStep == .compatibility || (!discoveredBridges.isEmpty && currentStep == .networkScan) {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(canProceed ? FyrDesign.Colors.textPrimary : FyrDesign.Colors.textTertiary)
                .padding(.horizontal, FyrDesign.Spacing.lg)
                .padding(.vertical, FyrDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: FyrDesign.Radius.md)
                        .fill(
                            canProceed
                                ? FyrDesign.Colors.flameOrange
                                : FyrDesign.Colors.glassHighlight
                        )
                )
                .glow(
                    color: canProceed ? FyrDesign.Colors.flameOrange : .clear,
                    radius: 8,
                    intensity: 0.3
                )
            }
            .disabled(!canProceed)
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func glassHeroIcon(systemName: String, color: Color, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(color)
            .glow(color: color, radius: size * 0.25, intensity: 0.4)
    }

    @ViewBuilder
    private func tipRow(number: Int, text: String) -> some View {
        HStack(spacing: FyrDesign.Spacing.md) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(FyrDesign.Colors.textPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(FyrDesign.Colors.flameOrange)
                )

            Text(text)
                .font(.callout)
                .foregroundStyle(FyrDesign.Colors.textPrimary)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return String(localized: "Get Started")
        case .compatibility: return String(localized: "Continue")
        case .networkScan: return isScanning ? String(localized: "Scanning...") : (discoveredBridges.isEmpty ? String(localized: "Scan") : String(localized: "Continue"))
        case .manualEntry: return String(localized: "Test Connection")
        case .connectionTest:
            if connectionTestResult == nil { return String(localized: "Testing...") }
            if case .success = connectionTestResult { return String(localized: "Continue") }
            return String(localized: "Retry")
        case .dhcpAdvice: return String(localized: "Finish Setup")
        case .complete: return String(localized: "Start Using Fyr")
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .welcome, .compatibility: return true
        case .networkScan: return !isScanning && (selectedBridge != nil || !discoveredBridges.isEmpty)
        case .manualEntry: return isValidIP(manualIP)
        case .connectionTest: return connectionTestResult != nil
        case .dhcpAdvice, .complete: return true
        }
    }

    private var bridgeIPToTest: String {
        selectedBridge?.ipAddress ?? manualIP
    }

    private func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }

    // MARK: - Actions

    private func goBack() {
        withAnimation(.spring(
            response: FyrDesign.Animation.springResponse,
            dampingFraction: FyrDesign.Animation.springDamping
        )) {
            switch currentStep {
            case .compatibility:
                currentStep = .welcome
            case .networkScan, .manualEntry:
                currentStep = .compatibility
            case .connectionTest:
                currentStep = selectedBridge != nil ? .networkScan : .manualEntry
            case .dhcpAdvice:
                currentStep = .connectionTest
            default:
                break
            }
        }
    }

    private func goNext() {
        withAnimation(.spring(
            response: FyrDesign.Animation.springResponse,
            dampingFraction: FyrDesign.Animation.springDamping
        )) {
            switch currentStep {
            case .welcome:
                currentStep = .compatibility

            case .compatibility:
                currentStep = .networkScan
                startNetworkScan()

            case .networkScan:
                if discoveredBridges.isEmpty {
                    startNetworkScan()
                } else {
                    currentStep = .connectionTest
                    testConnection()
                }

            case .manualEntry:
                currentStep = .connectionTest
                testConnection()

            case .connectionTest:
                if case .success = connectionTestResult {
                    currentStep = .dhcpAdvice
                } else {
                    connectionTestResult = nil
                    testConnection()
                }

            case .dhcpAdvice:
                currentStep = .complete

            case .complete:
                settings.hasCompletedOnboarding = true
            }
        }
    }

    private func startNetworkScan() {
        // Cancel any existing scan first
        cancelScan()

        isScanning = true
        discoveredBridges = []
        scanProgress = 0

        scanTask = Task {
            let discovery = DRUDiscovery()
            let bridges = await discovery.scanNetwork { progress in
                if case .scanning(let p, _) = progress {
                    Task { @MainActor in
                        scanProgress = p
                    }
                }
            }

            // Check if task was cancelled before updating UI
            guard !Task.isCancelled else { return }

            await MainActor.run {
                discoveredBridges = bridges
                isScanning = false
                if let first = bridges.first {
                    selectedBridge = first
                }
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func testConnection() {
        // Cancel any ongoing scan before testing connection
        // DRU bridge only allows one connection at a time
        cancelScan()

        connectionTestResult = nil
        unverifiedIP = nil

        Task {
            // Add small delay to ensure scan connections are fully closed
            try? await Task.sleep(for: .milliseconds(500))

            let discovery = DRUDiscovery()
            let ip = bridgeIPToTest
            // A bridge found by the scan was verified moments ago; check again
            // anyway, since a manually entered address was not.
            switch await discovery.verifyManualIP(ip) {
            case .bridge(let bridge):
                settings.saveBridge(ip: bridge.ipAddress, addressing: bridge.addressing)
                connectionTestResult = .success
            case .notADRUBridge:
                unverifiedIP = ip
                connectionTestResult = .failed(String(localized: "The device at \(ip) answers, but not like a DRU bridge. Check the address, and make sure the fireplace is powered on."))
            case .unreachable:
                connectionTestResult = .failed(String(localized: "Could not connect to \(ip). Check that the bridge is powered on and connected to the same network."))
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding - Welcome") {
    OnboardingFlow()
        .environment(SettingsStore.shared)
}

#Preview("Onboarding - Network Scan") {
    OnboardingFlow()
        .environment(SettingsStore.shared)
}
