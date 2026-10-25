import AppIntents
import SwiftUI

/// Read the fireplace status from the bridge. Returns the fireplace entity,
/// so Shortcuts can use it (e.g. "if the fireplace is on").
struct GetFireplaceStatusIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Fireplace Status"

    static let description = IntentDescription("Reads the current status of the DRU fireplace")

    static let supportedModes: IntentModes = .background

    // Run in the app process, also from widgets and controls: the bridge's
    // single connection must have one owner (`DRUFireplaceService.shared`).
    static let allowedExecutionTargets: ExecutionTargets = .main

    func perform() async throws -> some IntentResult & ReturnsValue<FireplaceEntity> & ProvidesDialog & ShowsSnippetView {
        let service = DRUFireplaceService.shared
        let status: FireplaceStatus
        do {
            try await service.configureFromSettings()
            status = try await service.fetchStatus()
            await service.releaseConnection()
        } catch {
            await service.releaseConnection()
            throw FireplaceIntentError(message: FireplaceIntentSupport.message(
                for: error,
                failure: String(localized: "Could not get the fireplace status.")
            ))
        }

        return .result(
            value: FireplaceEntity(status: status),
            dialog: IntentDialog(stringLiteral: Self.spokenStatus(status)),
            view: StatusSnippetView(status: status)
        )
    }

    /// What Siri says. The flame height is left out: the bridge does not report it.
    static func spokenStatus(_ status: FireplaceStatus) -> String {
        guard status.isOn else {
            return String(localized: "The fireplace is off.")
        }
        let temperature = Measurement(value: status.currentTemperature, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return status.ecoModeActive
            ? String(localized: "The fireplace is on in wave mode. It is \(temperature).")
            : String(localized: "The fireplace is on. It is \(temperature).")
    }
}

/// An intent failure with a message Siri can say.
struct FireplaceIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
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
                            Label(formatTemperature(status.currentTemperature), systemImage: "thermometer.medium")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    if status.ecoModeActive {
                        Label("Wave Mode", systemImage: "leaf")
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
        Measurement(value: temp, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
