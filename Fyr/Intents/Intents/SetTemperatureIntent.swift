import AppIntents

/// Set the thermostat setpoint. Kept for Shortcuts, not promoted as an App
/// Shortcut. Only while the fire burns: never lights the fire.
struct SetTemperatureIntent: AppIntent {

    static let title: LocalizedStringResource = "Set Temperature"

    static let description = IntentDescription("Sets the thermostat temperature while the DRU fireplace is burning. Does not light the fire.")

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

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
        let clampedTemp = max(15.0, min(30.0, temperature))
        let tempString = Measurement(value: clampedTemp, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        let dialog = try await FireplaceIntentSupport.perform(
            .setTemperature(clampedTemp),
            success: "Temperature set to \(tempString).",
            failure: String(localized: "Could not set the temperature.")
        )
        return .result(dialog: dialog)
    }
}
