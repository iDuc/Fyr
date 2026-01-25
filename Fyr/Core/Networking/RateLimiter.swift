import Foundation

/// Rate limiter for DRU fireplace commands
/// Enforces timing constraints required by the device
actor RateLimiter {

    /// Command types with different rate limits
    enum CommandType {
        case read           // Status polling
        case flameHeight    // Regulatory: max 1 change per 10 seconds
        case generalWrite   // General commands
        case wavePattern    // Wave pattern storage (max 1x per day to EEPROM)

        /// Minimum interval between commands of this type (in seconds)
        var minimumInterval: TimeInterval {
            switch self {
            case .read:
                return 3.0   // Reduced from 10s - reads are less impactful
            case .flameHeight:
                return 10.0  // Regulatory requirement - cannot be reduced
            case .generalWrite:
                return 3.0   // Reduced from 10s for better responsiveness
            case .wavePattern:
                return 86400.0  // 24 hours (1 day)
            }
        }
    }

    // MARK: - Properties

    private var lastCommandTimes: [CommandType: Date] = [:]
    private var wavePatternWriteCount: Int = 0
    private var wavePatternWriteDate: Date?

    // MARK: - Public Methods

    /// Wait if needed before executing a command
    /// - Parameter command: The type of command to execute
    func waitIfNeeded(for command: CommandType) async {
        let now = Date()
        let waitTime = timeUntilAllowed(for: command, at: now)

        if waitTime > 0 {
            try? await Task.sleep(for: .seconds(waitTime))
        }

        lastCommandTimes[command] = Date()
    }

    /// Check if a command can be executed immediately
    /// - Parameter command: The type of command
    /// - Returns: True if the command can be executed now
    func canExecute(_ command: CommandType) -> Bool {
        timeUntilAllowed(for: command, at: Date()) <= 0
    }

    /// Get time remaining until command is allowed
    /// - Parameter command: The type of command
    /// - Returns: Seconds remaining, or 0 if allowed now
    func timeRemaining(for command: CommandType) -> TimeInterval {
        max(0, timeUntilAllowed(for: command, at: Date()))
    }

    /// Record that a command was executed (call after successful execution)
    /// - Parameter command: The type of command that was executed
    func recordExecution(of command: CommandType) {
        lastCommandTimes[command] = Date()

        if command == .wavePattern {
            let today = Calendar.current.startOfDay(for: Date())
            if wavePatternWriteDate != today {
                wavePatternWriteDate = today
                wavePatternWriteCount = 1
            } else {
                wavePatternWriteCount += 1
            }
        }
    }

    /// Check if wave pattern can be written today
    /// - Returns: True if wave pattern write is allowed
    func canWriteWavePattern() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        if wavePatternWriteDate != today {
            return true
        }
        return wavePatternWriteCount < 1
    }

    // MARK: - Private Methods

    private func timeUntilAllowed(for command: CommandType, at date: Date) -> TimeInterval {
        guard let lastTime = lastCommandTimes[command] else {
            return 0
        }

        let timeSinceLastCommand = date.timeIntervalSince(lastTime)
        return command.minimumInterval - timeSinceLastCommand
    }
}
