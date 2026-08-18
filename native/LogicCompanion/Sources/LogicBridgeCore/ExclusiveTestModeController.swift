import Foundation

public enum ExclusiveTestModePhase: String, Sendable, Equatable {
    case inactive
    case active
    case paused
}

public enum ExclusiveTestModeStopReason: String, Sendable, Equatable {
    case emergencyStop
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
    public let stopReason: ExclusiveTestModeStopReason?
}

public enum ExclusiveTestModeError: Error, Equatable {
    case accessibilityNotReady
    case testProjectPolicyContextMissing
    case notActive
}

public final class ExclusiveTestModeController: @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var currentSnapshot = ExclusiveTestModeSnapshot(
        phase: .inactive,
        deadline: nil,
        stopReason: nil
    )
    private var pendingOperations: [String: () -> Void] = [:]

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
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
        guard readiness.accessibilityReady else {
            throw ExclusiveTestModeError.accessibilityNotReady
        }
        guard readiness.testProjectPolicyContext else {
            throw ExclusiveTestModeError.testProjectPolicyContextMissing
        }
        lock.withLock {
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .active,
                deadline: now().addingTimeInterval(duration),
                stopReason: nil
            )
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
                stopReason: nil
            )
        }
    }

    public func emergencyStop() {
        stop(reason: .emergencyStop)
    }

    private func stop(reason: ExclusiveTestModeStopReason) {
        let cancellations = lock.withLock {
            currentSnapshot = ExclusiveTestModeSnapshot(
                phase: .inactive,
                deadline: nil,
                stopReason: reason
            )
            let callbacks = Array(pendingOperations.values)
            pendingOperations.removeAll()
            return callbacks
        }
        cancellations.forEach { $0() }
    }
}
