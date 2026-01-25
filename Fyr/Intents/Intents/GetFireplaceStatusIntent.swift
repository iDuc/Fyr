import AppIntents
import SwiftUI

/// Intent to get the current fireplace status
struct GetFireplaceStatusIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Fireplace Status"

    static var description = IntentDescription("Shows the current status of the DRU fireplace")

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = DRUFireplaceService.shared
        let isConnected = await service.isConnected
        if !isConnected {
            if let ip = SettingsStore.bridgeIPValue {
                try await service.connect(to: ip)
            } else {
                return .result(
                    dialog: "Please configure your fireplace in the Fyr app first.",
                    view: StatusSnippetView(status: nil)
                )
            }
        }

        do {
            let status = try await service.fetchStatus()

            // Build dialog text
            let dialogText: String
            if status.isOn {
                let formatter = MeasurementFormatter()
                formatter.unitOptions = .providedUnit
                formatter.numberFormatter.maximumFractionDigits = 1
                let temp = Measurement(value: status.currentTemperature, unit: UnitTemperature.celsius)
                let tempString = formatter.string(from: temp)

                var text = "The fireplace is on at flame level \(status.flameHeight) with temperature \(tempString)."
                if status.ecoModeActive {
                    text += " Eco mode is active."
                }
                dialogText = text
            } else {
                dialogText = "The fireplace is currently off."
            }

            return .result(
                dialog: IntentDialog(stringLiteral: dialogText),
                view: StatusSnippetView(status: status)
            )
        } catch {
            return .result(
                dialog: "Could not get the fireplace status. Please check the connection.",
                view: StatusSnippetView(status: nil)
            )
        }
    }
}

// MARK: - Status Snippet View

/// Compact view shown in Siri response
struct StatusSnippetView: View {
    let status: FireplaceStatus?

    var body: some View {
        if let status {
            HStack(spacing: 16) {
                // Flame icon
                Image(systemName: status.isOn ? "flame.fill" : "flame")
                    .font(.largeTitle)
                    .foregroundStyle(status.isOn ? .orange : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.isOn ? "Fireplace On" : "Fireplace Off")
                        .font(.headline)

                    if status.isOn {
                        HStack(spacing: 12) {
                            Label("\(status.flameHeight)", systemImage: "flame")
                            Label(formatTemperature(status.currentTemperature), systemImage: "thermometer.medium")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    if status.ecoModeActive {
                        Label("Eco Mode", systemImage: "leaf")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding()
        } else {
            HStack {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text("Not Connected")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func formatTemperature(_ temp: Double) -> String {
        let measurement = Measurement(value: temp, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}
