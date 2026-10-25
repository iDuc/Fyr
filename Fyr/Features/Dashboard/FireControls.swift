import SwiftUI

/// Wave mode as a first-class control: the flames rise and fall between low
/// and the set flame height. Shows the bridge's state, with a pending state
/// while a change is on its way. Turning it on needs a burning fire.
struct WaveModeCard: View {
    @Environment(Fireplace.self) private var fireplace

    let onChange: (Bool) async -> Void

    var body: some View {
        let isOn = fireplace.displayedWaveMode
        let isPending = fireplace.pendingWaveMode != nil

        Toggle(isOn: Binding(
            get: { fireplace.displayedWaveMode },
            set: { newValue in Task { await onChange(newValue) } }
        )) {
            HStack(spacing: FyrDesign.Spacing.md) {
                Image(systemName: "water.waves")
                    .font(.title2)
                    .foregroundStyle(isOn ? FyrDesign.Colors.wave : FyrDesign.Colors.textTertiary)
                    .symbolEffect(.variableColor.iterative, options: .repeating.speed(0.4), isActive: isOn && !isPending)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: FyrDesign.Spacing.xxs) {
                    Text("Wave")
                        .font(.headline)
                        .foregroundStyle(FyrDesign.Colors.textPrimary)
                    Text(subtitle(isOn: isOn, isPending: isPending))
                        .font(.subheadline)
                        .foregroundStyle(FyrDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(FyrDesign.Colors.wave)
        .disabled(isPending || !fireplace.isOn || fireplace.lastStatusUpdate == nil)
        .padding(FyrDesign.Spacing.md)
        .glassCard(tint: isOn ? FyrDesign.Colors.wave : nil)
        .sensoryFeedback(.selection, trigger: fireplace.ecoModeActive)
        .accessibilityIdentifier("dashboard.wave")
    }

    private func subtitle(isOn: Bool, isPending: Bool) -> String {
        if isPending {
            return isOn ? String(localized: "Starting wave…") : String(localized: "Stopping wave…")
        }
        if !fireplace.isOn {
            return String(localized: "Available while the fire burns")
        }
        return isOn
            ? String(localized: "Flames rise and fall up to the set height")
            : String(localized: "Steady flame")
    }
}

/// Flame height 0-100 % in steps of 5. In wave mode this is the highest the
/// flames go. The bridge accepts one change per 10 seconds; a newer value
/// replaces one that is still waiting.
struct FlameHeightCard: View {
    @Environment(Fireplace.self) private var fireplace

    let onCommit: (Int) async -> Void

    @State private var value: Double = Double(DRUConstants.defaultFlameHeight)
    @State private var isEditing = false
    /// Changes that do not come from dragging (VoiceOver, keyboard) are
    /// committed shortly after the last step, so one adjustment sends one value.
    @State private var pendingCommit: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: FyrDesign.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(fireplace.ecoModeActive ? "Highest flame" : "Flame height")
                } icon: {
                    Image(systemName: "flame")
                        .foregroundStyle(FyrDesign.Colors.accent)
                }
                .font(.headline)
                .foregroundStyle(FyrDesign.Colors.textPrimary)

                Spacer()

                Text(Double(Int(value)) / 100, format: .percent)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)
                    .animation(.snappy, value: Int(value))
            }

            Slider(value: $value, in: 0...100, step: 5) {
                Text("Flame height")
            } minimumValueLabel: {
                Image(systemName: "flame").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "flame.fill").imageScale(.medium)
            } onEditingChanged: { editing in
                isEditing = editing
                pendingCommit?.cancel()
                if !editing {
                    commit()
                }
            }
            .tint(FyrDesign.Colors.accent)
            .foregroundStyle(FyrDesign.Colors.textTertiary)
            .sensoryFeedback(.selection, trigger: Int(value))
            .accessibilityValue(Text(Double(Int(value)) / 100, format: .percent))
            .accessibilityIdentifier("dashboard.flameHeight")

            status
                .font(.footnote)
                .foregroundStyle(FyrDesign.Colors.textSecondary)
        }
        .padding(FyrDesign.Spacing.md)
        .glassCard()
        .onAppear { value = Double(fireplace.flameHeight) }
        .onChange(of: value) { _, newValue in
            // Dragging commits when the finger lifts; other changes (VoiceOver,
            // keyboard) after a short pause. A drag that never reports its end
            // still commits once the value has rested for a while.
            guard Int(newValue) != committedHeight else { return }
            pendingCommit?.cancel()
            let pause: Duration = isEditing ? .milliseconds(1500) : .milliseconds(700)
            pendingCommit = Task {
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled else { return }
                isEditing = false
                commit()
            }
        }
        .onChange(of: fireplace.flameHeight) { _, height in
            if !isEditing && fireplace.pendingFlameHeight == nil {
                value = Double(height)
            }
        }
        .onChange(of: fireplace.pendingFlameHeight) { _, pending in
            // A change that was not sent (fire off, no connection) snaps back.
            if pending == nil && !isEditing {
                value = Double(fireplace.flameHeight)
            }
        }
    }

    /// The value Fyr last sent or is sending.
    private var committedHeight: Int {
        fireplace.pendingFlameHeight ?? fireplace.flameHeight
    }

    private func commit() {
        let height = Int(value)
        guard height != committedHeight || !fireplace.flameHeightIsKnown else { return }
        Task { await onCommit(height) }
    }

    @ViewBuilder
    private var status: some View {
        if let pending = fireplace.pendingFlameHeight {
            Label {
                Text("Setting \(Double(pending) / 100, format: .percent)…")
            } icon: {
                ProgressView().controlSize(.mini)
            }
        } else if let readyAt = fireplace.flameHeightReadyAt, readyAt > .now {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(readyAt.timeIntervalSince(context.date).rounded(.up)))
                if seconds > 0 {
                    Text("Next change in \(seconds) s")
                } else {
                    Text(lastSetText)
                }
            }
        } else {
            Text(lastSetText)
        }
    }

    private var lastSetText: String {
        fireplace.flameHeightIsKnown
            ? String(localized: "The fireplace does not report its flame height; this is the last value Fyr set.")
            : String(localized: "Not set from Fyr yet.")
    }
}

/// The thermostat, tucked away: a quiet row that opens a sheet.
struct ThermostatRow: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(SettingsStore.self) private var settings

    let onSet: (Double) async -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Label("Thermostat", systemImage: "thermometer.medium")
                Spacer()
                Text(Measurement(value: settings.targetTemperature, unit: UnitTemperature.celsius),
                     format: .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...1))))
                    .monospacedDigit()
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FyrDesign.Colors.textTertiary)
            }
            .font(.subheadline)
            .foregroundStyle(FyrDesign.Colors.textSecondary)
            .padding(.horizontal, FyrDesign.Spacing.md)
            .padding(.vertical, FyrDesign.Spacing.sm + FyrDesign.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.thermostat")
        .sheet(isPresented: $isPresented) {
            ThermostatSheet(initial: settings.targetTemperature, onSet: onSet)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Set the fireplace's thermostat. Only while the fire burns.
struct ThermostatSheet: View {
    @Environment(Fireplace.self) private var fireplace
    @Environment(\.dismiss) private var dismiss

    let initial: Double
    let onSet: (Double) async -> Void

    @State private var target: Double = 21

    var body: some View {
        NavigationStack {
            VStack(spacing: FyrDesign.Spacing.lg) {
                Text(Measurement(value: target, unit: UnitTemperature.celsius),
                     format: .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: target))
                    .foregroundStyle(FyrDesign.Colors.textPrimary)

                Stepper(value: $target, in: DRUConstants.minTemperature...DRUConstants.maxTemperature, step: 0.5) {
                    Text("Target temperature")
                }
                .sensoryFeedback(.selection, trigger: target)

                Text("The fireplace adjusts its flame to reach this room temperature. Most people never need this.")
                    .font(.footnote)
                    .foregroundStyle(FyrDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                if !fireplace.isOn {
                    Label("Available while the fire burns", systemImage: "flame")
                        .font(.footnote)
                        .foregroundStyle(FyrDesign.Colors.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(FyrDesign.Spacing.lg)
            .navigationTitle(Text("Thermostat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        let value = target
                        dismiss()
                        Task { await onSet(value) }
                    }
                    .disabled(!fireplace.isOn)
                }
            }
        }
        .onAppear { target = initial }
    }
}
