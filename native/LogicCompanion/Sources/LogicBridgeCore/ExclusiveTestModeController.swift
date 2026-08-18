import Foundation

public enum ExclusiveTestModePhase: String, Sendable, Equatable {
    case inactive
    case active
    case paused
}

public enum ExclusiveTestModeStopReason: String, Sendable, Equatable {
    case emergencyStop
    case timedOut
}

public enum ExclusiveTestModePauseReason: String, Sendable, Equatable {
    case user
    case focusLost
    case unexpectedModal
    case humanInput
}

public enum AutomationSafetyInterruption: Sendable, Equatable {
    case focusLost
    case unexpectedModal
    case humanInput
}

public struct ExclusiveTestModeReadiness: Sendable, Equatable {
    public let accessibilityReady: Bool
    public let testProjectPolicyContext: Bool

    public init(accessibilityReady: Bool, testProjectPolicyContext: Bool) {
        self.accessibilityReady = accessibilityReady
        self.testProjectPolicyContext = testProjectPolicyContext
    }
}

public struct ExclusiveTestModeSnapshot: Sendable, Equatable {
    public let phase: ExclusiveTestModePhase
    public let deadline: Date?
    public let pauseReason: ExclusiveTestModePauseReason?
    public let stopReason: ExclusiveTestModeStopReason?
}

public enum ExclusiveTestModeError: Error, Equatable {
    case accessibilityNotReady
    case testProjectPolicyContextMissing
    case invalidDuration
    case notActive
}

public protocol ExclusiveTestModeExpirationScheduling: Sendable {
    func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void)
}

public struct DispatchExpirationScheduler: ExclusiveTestModeExpirationScheduling {
    public init() {}

    public func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + duration,
            execute: action
        )
    }
}

public final class ExclusiveTestModeController: @unchecked Sendable {
    public static let maximumDuration: TimeInterval = 60 * 60

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let expirationScheduler: any ExclusiveTestModeExpirationScheduling
    private var currentSnapshot = ExclusiveTestModeSnapshot(
        phase: .inactive,
        deadline: nil,
        pauseReason: nil,
        stopReason: nil
    )
    private var pendingOperations: [String: () -> Void] = [:]
    private var generation = 0

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        expirationScheduler: any ExclusiveTestModeExpirationScheduling = DispatchExpirationScheduler()
    ) {
        self.now = now
        self.expirationScheduler = expirationScheduler
    }

    public var snapshot: ExclusiveTestModeSnapshot {
        lock.withLock { currentSnapshot }
    }

    public var canBeginUIOperation: Bool {
        lock.withLock { currentSnapshot.phase == .active }
    }

    public func activate(
        duration: TimeInterval,
        readiness: ExclusiveTestModeReadiness
    ) throws {
        guard duration > 0, duration <= Self.maximumDuration else {
            throw ExclusiveTestModeError.invalidDuration
        }
        guard readiness.accessibilityReady else {
            throw ExclusiveTestModeError.accessibilityNotReady
        }
        guard readiness.testProjectPolicyContext else {
            throw ExclusiveTestModeError.testProjectPolicyContextMissing
        }
        let deadline = now().addingTimeInterval(duration)
        let activationGeneration = lock.withLock {
            generation += 1
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .active,
                deadline: deadline,
                pauseReason: nil,
                stopReason: nil
            )
            return generation
        }
        expirationScheduler.schedule(after: duration) { [weak self] in
            self?.expire(generation: activationGeneration)
        }
    }

    public func registerPendingOperation(id: String, cancel: @escaping () -> Void) {
        lock.withLock {
            pendingOperations[id] = cancel
        }
    }

    public func pause() {
        lock.withLock {
            guard currentSnapshot.phase == .active else { return }
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .paused,
                deadline: currentSnapshot.deadline,
                pauseReason: .user,
                stopReason: nil
            )
        }
    }

    public func resume() throws {
        try lock.withLock {
            guard currentSnapshot.phase == .paused else {
                throw ExclusiveTestModeError.notActive
            }
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .active,
                deadline: currentSnapshot.deadline,
                pauseReason: nil,
                stopReason: nil
            )
        }
    }

    public func emergencyStop() {
        stop(reason: .emergencyStop)
    }

    public func observe(_ interruption: AutomationSafetyInterruption) {
        let pauseReason: ExclusiveTestModePauseReason = switch interruption {
        case .focusLost: .focusLost
        case .unexpectedModal: .unexpectedModal
        case .humanInput: .humanInput
        }
        let cancellations = lock.withLock {
            guard currentSnapshot.phase == .active else { return [() -> Void]() }
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .paused,
                deadline: currentSnapshot.deadline,
                pauseReason: pauseReason,
                stopReason: nil
            )
            let callbacks = Array(pendingOperations.values)
            pendingOperations.removeAll()
            return callbacks
        }
        cancellations.forEach { $0() }
    }

    private func stop(reason: ExclusiveTestModeStopReason) {
        let cancellations = lock.withLock {
            generation += 1
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .inactive,
                deadline: nil,
                pauseReason: nil,
                stopReason: reason
            )
            let callbacks = Array(pendingOperations.values)
            pendingOperations.removeAll()
            return callbacks
        }
        cancellations.forEach { $0() }
    }

    private func expire(generation expectedGeneration: Int) {
        let cancellations = lock.withLock {
            guard generation == expectedGeneration,
                  currentSnapshot.phase != .inactive else { return [() -> Void]() }
            generation += 1
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .inactive,
                deadline: nil,
                pauseReason: nil,
                stopReason: .timedOut
            )
            let callbacks = Array(pendingOperations.values)
            pendingOperations.removeAll()
            return callbacks
        }
        cancellations.forEach { $0() }
    }
}
