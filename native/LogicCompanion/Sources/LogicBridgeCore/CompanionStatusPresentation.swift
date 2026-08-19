import Foundation

public enum CompanionConnectionStatus: Sendable, Equatable {
    case starting
    case listening
    case connected
}

public enum CompanionStatusTone: Sendable, Equatable {
    case neutral
    case warning
    case automationActive
}

public struct CompanionStatusPresentation: Sendable, Equatable {
    public let connectionTitle: String
    public let logicTitle: String
    public let testModeTitle: String
    public let statusItemText: String
    public let statusSymbolName: String
    public let statusTone: CompanionStatusTone
    public let canPause: Bool
    public let canResume: Bool
    public let canEmergencyStop: Bool

    public static func make(
        connection: CompanionConnectionStatus,
        logicRunning: Bool,
        testMode: ExclusiveTestModeSnapshot,
        now: Date
    ) -> CompanionStatusPresentation {
        let connectionTitle = switch connection {
        case .starting: "Connection: Starting"
        case .listening: "Connection: Listening"
        case .connected: "Connection: Connected"
        }
        let logicTitle = "Logic Pro: \(logicRunning ? "Running" : "Not Running")"

        switch testMode.phase {
        case .inactive:
            return CompanionStatusPresentation(
                connectionTitle: connectionTitle,
                logicTitle: logicTitle,
                testModeTitle: inactiveTitle(stopReason: testMode.stopReason),
                statusItemText: "",
                statusSymbolName: "waveform.circle",
                statusTone: .neutral,
                canPause: false,
                canResume: false,
                canEmergencyStop: false
            )
        case .active:
            return CompanionStatusPresentation(
                connectionTitle: connectionTitle,
                logicTitle: logicTitle,
                testModeTitle: "Test Mode: ACTIVE · \(remaining(deadline: testMode.deadline, now: now)) remaining",
                statusItemText: "TEST",
                statusSymbolName: "bolt.circle.fill",
                statusTone: .automationActive,
                canPause: true,
                canResume: false,
                canEmergencyStop: true
            )
        case .paused:
            return CompanionStatusPresentation(
                connectionTitle: connectionTitle,
                logicTitle: logicTitle,
                testModeTitle: "Test Mode: Paused · \(pauseLabel(testMode.pauseReason))",
                statusItemText: "PAUSED",
                statusSymbolName: "pause.circle.fill",
                statusTone: .warning,
                canPause: false,
                canResume: true,
                canEmergencyStop: true
            )
        }
    }

    private static func remaining(deadline: Date?, now: Date) -> String {
        let seconds = max(0, Int((deadline ?? now).timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func pauseLabel(_ reason: ExclusiveTestModePauseReason?) -> String {
        switch reason {
        case .user: "Paused by user"
        case .focusLost: "Logic focus lost"
        case .unexpectedModal: "Unexpected modal"
        case .humanInput: "Human input observed"
        case .projectIdentityChanged: "Test Project changed"
        case nil: "Safety pause"
        }
    }

    private static func inactiveTitle(stopReason: ExclusiveTestModeStopReason?) -> String {
        switch stopReason {
        case .emergencyStop: "Test Mode: Inactive · Emergency stopped"
        case .timedOut: "Test Mode: Inactive · Timed out"
        case nil: "Test Mode: Inactive"
        }
    }
}
