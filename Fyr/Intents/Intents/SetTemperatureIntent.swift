import AppIntents

/// Intent to set the thermostat temperature
struct SetTemperatureIntent: AppIntent {

    static var title: LocalizedStringResource = "Set Temperature"

    static var description = IntentDescription("Sets the thermostat temperature of the DRU fireplace")

    static var openAppWhenRun: Bool = false

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

        let service = DRUFireplaceService.shared
        let isConnected = await service.isConnected
        if !isConnected {
            if let ip = SettingsStore.bridgeIPValue {
                try await service.connect(to: ip)
            } else {
                return .result(dialog: "Please configure your fireplace in the Fyr app first.")
            }
        }

        do {
            try await service.setThermostatSetpoint(clampedTemp)

            // Format temperature for display
            let formatter = MeasurementFormatter()
            formatter.unitOptions = .providedUnit
            formatter.numberFormatter.maximumFractionDigits = 1
            let measurement = Measurement(value: clampedTemp, unit: UnitTemperature.celsius)
            let tempString = formatter.string(from: measurement)

            return .result(dialog: "Temperature set to \(tempString).")
        } catch {
            return .result(dialog: "Could not set the temperature. Please check the connection.")
        }
    }
}
