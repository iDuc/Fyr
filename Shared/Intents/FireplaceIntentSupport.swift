import AppIntents

/// Shared plumbing for the fireplace App Intents. Every intent goes through
/// `execute`, which applies `SafetyPolicy` for the `.intent` surface:
/// - configure the service from the saved settings;
/// - ask for confirmation when the command needs it (ignition), *before*
///   anything is sent; without a confirmation step ignition is refused;
/// - run the command (the service refuses changes that need a burning fire);
/// - always release the bridge connection afterwards (the bridge accepts one
///   connection, and the app may be suspended right after the intent).
///
/// The unlocked-device requirement is the intent's `authenticationPolicy`
/// (see `authenticationPolicy(for:)`); the system enforces it before `perform`.
nonisolated enum FireplaceIntentSupport {

    /// Result of a fireplace command run from an intent.
    enum Outcome: Equatable, Sendable {
        case success
        case failure(BridgeError)
    }

    /// The default confirmation step: none. Ignition without a real
    /// confirmation step is refused.
    static func noConfirmation() async throws {
        throw BridgeError.ignitionNotAuthorized
    }

    /// The `authenticationPolicy` an intent for `command` must declare. Intents
    /// have to spell it as a literal; `IntentDeclarationTests` checks they match.
    static func authenticationPolicy(for command: FireplaceCommand) -> IntentAuthenticationPolicy {
        SafetyPolicy.requirements(for: command, from: .intent).contains(.unlockedDevice)
            ? .requiresLocalDeviceAuthentication
            : .alwaysAllowed
    }

    /// Run `command` from an intent.
    /// - Parameter confirm: asks the user to confirm; throws if they decline.
    ///   Only called for commands that need an explicit confirmation.
    /// - Throws: Only what `confirm` throws (other than `BridgeError`), e.g.
    ///   the user cancelling. Bridge problems are returned as `.failure`.
    static func execute(
        _ command: FireplaceCommand,
        service: DRUFireplaceService,
        configure: (DRUFireplaceService) async throws(BridgeError) -> Void,
        confirm: () async throws -> Void = noConfirmation
    ) async throws -> Outcome {
        let requirements = SafetyPolicy.requirements(for: command, from: .intent)
        do {
            try await configure(service)
        } catch {
            return .failure(error)
        }

        var authorization: IgnitionAuthorization?
        if requirements.contains(.explicitConfirmation) {
            // Ask before connecting: the bridge's single connection slot must
            // not be held while the user decides.
            do {
                try await confirm()
            } catch let error as BridgeError {
                return .failure(error)
            }
            authorization = .confirmedIntent
        }

        do throws(BridgeError) {
            switch command {
            case .turnOn:
                guard let authorization else { throw .ignitionNotAuthorized }
                try await service.turnOn(authorization: authorization)
            case .turnOff:
                try await service.turnOff()
            case .setWaveMode(let enabled):
                try await service.setWaveMode(enabled: enabled)
            case .setFlameHeight(let height):
                try await service.setFlameHeight(height)
            case .setTemperature(let temperature):
                try await service.setThermostatSetpoint(temperature)
            case .setWaveInterval(let seconds):
                try await service.setWaveInterval(seconds)
            }
            await service.releaseConnection()
            return .success
        } catch {
            await service.releaseConnection()
            return .failure(error)
        }
    }

    /// Run `command` against the shared service and turn the outcome into a dialog.
    static func perform(
        _ command: FireplaceCommand,
        success: @autoclosure () -> IntentDialog,
        failure: String,
        confirm: () async throws -> Void = noConfirmation
    ) async throws -> IntentDialog {
        let outcome = try await execute(
            command,
            service: .shared,
            configure: { service throws(BridgeError) in try await service.configureFromSettings() },
            confirm: confirm
        )
        return switch outcome {
        case .success:
            success()
        case .failure(let error):
            dialog(for: error, failure: failure)
        }
    }

    /// Run `command` for a control, widget or Live Activity button: no
    /// dialog, but a thrown error the system can show. On failure the
    /// surfaces are refreshed, so a toggle flips back to the known state.
    static func performForControl(_ command: FireplaceCommand, failure: String) async throws {
        let outcome = try await execute(
            command,
            service: .shared,
            configure: { service throws(BridgeError) in try await service.configureFromSettings() }
        )
        if case .failure(let error) = outcome {
            FyrSurfaces.reloadAll()
            throw FireplaceIntentError(message: message(for: error, failure: failure))
        }
    }

    /// Dialog for a failed command, with the reason and what to do about it.
    static func dialog(for error: any Error, failure: String) -> IntentDialog {
        IntentDialog(stringLiteral: message(for: error, failure: failure))
    }

    static func message(for error: any Error, failure: String) -> String {
        guard let bridgeError = error as? BridgeError else {
            return failure
        }
        switch bridgeError {
        case .notConfigured:
            return String(localized: "Please configure your fireplace in the Fyr app first.")
        case .fireplaceOff, .ignitionNotAuthorized:
            // Not a failure of the bridge: say why nothing happened.
            let parts = [bridgeError.localizedDescription + ".", bridgeError.recoverySuggestion]
            return parts.compactMap { $0 }.joined(separator: " ")
        default:
            let parts = [failure, bridgeError.localizedDescription + ".", bridgeError.recoverySuggestion]
            return parts.compactMap { $0 }.joined(separator: " ")
        }
    }
}
