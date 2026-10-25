import SwiftUI

/// The fireplace at a glance: the fire and its state first, then on/off,
/// wave mode and flame height. The thermostat is tucked away at the bottom.
struct DashboardView: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(FireplaceController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase

    /// The iPhone Duo's hinge, if there is one (nil on other devices).
    @State private var hingeStatus: DeviceHinge.Status?

    var body: some View {
        NavigationStack {
            DashboardLayout { isWide in
                hero(isWide: isWide)
            } controls: {
                controls
            }
            .background { DynamicBackground(isFireplaceOn: fireplace.isOn) }
            .navigationTitle(Text("Fyr"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("dashboard.settings")
                }
            }
            .refreshable {
                await controller.refresh(priority: .userInitiated)
            }
            .task(id: scenePhase) {
                await controller.runSession(for: scenePhase)
            }
            .onHingeChange { _, context in
                hingeStatus = context.hinge?.status
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hingeStatus)
        }
    }

    // MARK: - Hero

    private func hero(isWide: Bool) -> some View {
        VStack(spacing: isWide ? FyrDesign.Spacing.lg : FyrDesign.Spacing.md) {
            FlameView(
                isOn: fireplace.isOn,
                flameHeight: fireplace.pendingFlameHeight ?? fireplace.flameHeight,
                waveMode: fireplace.ecoModeActive
            )
            .frame(maxWidth: isWide ? 340 : 260)
            .frame(height: flameHeight(isWide: isWide))
            .padding(.top, isWide ? 0 : FyrDesign.Spacing.sm)

            FireStatusHeader()
        }
        .accessibilityElement(children: .contain)
    }

    private func flameHeight(isWide: Bool) -> CGFloat {
        if isWide {
            return hingeStatus == .partiallyOpen ? 220 : 300
        }
        return 240
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: FyrDesign.Spacing.md) {
            ConnectionNote()

            PowerControl(
                onIgnite: { await controller.turnOn() },
                onTurnOff: { await controller.turnOff() }
            )

            if fireplace.isOn {
                WaveModeCard { await controller.setWaveMode($0) }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                FlameHeightCard { await controller.setFlameHeight($0) }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                ThermostatRow { await controller.setThermostat($0) }
                    .glassCard(cornerRadius: FyrDesign.Radius.md, intensity: .subtle)
                    .transition(.opacity)
            } else if fireplace.lastStatusUpdate != nil {
                Text("Wave mode and flame height are available while the fire burns.")
                    .font(.footnote)
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FyrDesign.Spacing.lg)
                    .transition(.opacity)
            }
        }
        .animation(FyrDesign.Animation.spring, value: fireplace.isOn)
        .animation(FyrDesign.Animation.spring, value: fireplace.lastError)
    }
}

// MARK: - Previews

#Preview("Burning, wave") {
    let fireplace = Fireplace.preview
    fireplace.ecoModeActive = true
    fireplace.burningSince = .now.addingTimeInterval(-3600)
    fireplace.hasLiveStatus = true
    return DashboardView()
        .environment(fireplace)
        .environment(FireplaceController(fireplace: fireplace))
        .environment(SettingsStore.shared)
}

#Preview("Off") {
    let fireplace = Fireplace.preview
    fireplace.isOn = false
    fireplace.hasLiveStatus = true
    return DashboardView()
        .environment(fireplace)
        .environment(FireplaceController(fireplace: fireplace))
        .environment(SettingsStore.shared)
}
