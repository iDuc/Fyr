import AppIntents
import SwiftUI
import WidgetKit

/// The last known state for the controls. Never connects to the bridge.
struct FireplaceControlValue: ControlValueProvider {
    var previewValue: FireplaceSnapshot {
        FireplaceSnapshot(isOn: true, ecoModeActive: true, timestamp: .now)
    }

    func currentValue() async throws -> FireplaceSnapshot {
        FireplaceSnapshot.load() ?? .unknown()
    }
}

/// Control Center / Lock Screen / Action button: turn the fire off. Always
/// allowed, also on a locked iPhone, no confirmation.
struct FireOffControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FyrAppGroup.ControlKind.turnOff, provider: FireplaceControlValue()) { snapshot in
            ControlWidgetButton(action: TurnOffFireplaceIntent()) {
                Label {
                    Text("Fire Off")
                    Text(snapshot.isOn ? "Burning" : "Off")
                } icon: {
                    Image(systemName: "flame.slash")
                }
            } actionLabel: { isActive in
                if isActive {
                    Label("Turning off…", systemImage: "flame.slash")
                }
            }
        }
        .displayName("Fire Off")
        .description("Turns the fireplace off.")
    }
}

/// Control Center / Lock Screen: wave mode on or off. Turning it on needs a
/// burning fire and never lights it.
struct WaveModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FyrAppGroup.ControlKind.waveMode, provider: FireplaceControlValue()) { snapshot in
            ControlWidgetToggle(isOn: snapshot.isOn && snapshot.ecoModeActive, action: SetWaveModeIntent()) {
                Label("Wave", systemImage: "water.waves")
            } valueLabel: { isOn in
                Text(isOn ? "On" : "Off")
            }
            .tint(FyrDesign.Colors.wave)
        }
        .displayName("Wave")
        .description("Turns wave mode on or off while the fire burns.")
    }
}

/// Control Center / Lock Screen / Action button: light the fire. Runs
/// `TurnOnFireplaceIntent`, so the iPhone must be unlocked and you confirm
/// every time, as the safety policy requires.
struct LightFireControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FyrAppGroup.ControlKind.turnOn, provider: FireplaceControlValue()) { snapshot in
            ControlWidgetButton(action: TurnOnFireplaceIntent()) {
                Label {
                    Text("Light Fire")
                    Text(snapshot.isOn ? "Burning" : "Off")
                } icon: {
                    Image(systemName: "flame")
                }
            } actionLabel: { isActive in
                if isActive {
                    Label("Lighting…", systemImage: "flame.fill")
                }
            }
            .tint(FyrDesign.Colors.flameOrange)
        }
        .displayName("Light Fire")
        .description("Lights the fireplace after you unlock your iPhone and confirm.")
    }
}
