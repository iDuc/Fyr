import AppIntents

/// Intent to set the thermostat temperature
struct SetTemperatureIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Temperature"

    static let description = IntentDescription("Sets the thermostat temperature of the DRU fireplace")

    static let openAppWhenRun: Bool = false

    /// Temperature parameter (15-30°C)
    @Parameter(
        title: "Temperature",
        description: "Target temperature in degrees Celsius (15-30)",
        requestValueDialog: "What temperature would you like?"
    )
    var temperature: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Set temperature to \(\.$temperature) degrees")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Validate temperature
        let clampedTemp = max(15.0, min(30.0, temperature))

        // Format temperature for display
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        let measurement = Measurement(value: clampedTemp, unit: UnitTemperature.celsius)
        let tempString = formatter.string(from: measurement)

        let dialog = await FireplaceIntentSupport.perform(
            success: "Temperature set to \(tempString).",
            failure: String(localized: "Could not set the temperature.")
        ) { try await $0.setThermostatSetpoint(clampedTemp) }
        return .result(dialog: dialog)
    }
}
