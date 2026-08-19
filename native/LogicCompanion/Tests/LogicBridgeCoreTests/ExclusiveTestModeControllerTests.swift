import Foundation
import Testing

@testable import LogicBridgeCore

private final class ManualExpirationScheduler: ExclusiveTestModeExpirationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: (@Sendable () -> Void)?

    func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.withLock { scheduled = action }
    }

    func fire() {
        let action = lock.withLock { scheduled }
        action?()
    }
}

@Test("exclusive test mode pauses, resumes, and emergency-stops pending work")
func exclusiveTestModeTransitions() throws {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var cancelledOperationIDs: [String] = []
    let controller = ExclusiveTestModeController(
        now: { startedAt },
        expirationScheduler: ManualExpirationScheduler()
    )

    #expect(controller.snapshot.phase == .inactive)

    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: true
        )
    )
    #expect(controller.snapshot.phase == .active)
    #expect(controller.snapshot.deadline == startedAt.addingTimeInterval(60))
    #expect(controller.canBeginUIOperation)

    controller.registerPendingOperation(id: "operation-1") {
        cancelledOperationIDs.append("operation-1")
    }
    controller.pause()
    #expect(controller.snapshot.phase == .paused)
    #expect(!controller.canBeginUIOperation)

    try controller.resume(readiness: ExclusiveTestModeReadiness(
        accessibilityReady: true,
        testProjectPolicyContext: true
    ))
    #expect(controller.snapshot.phase == .active)
    #expect(controller.canBeginUIOperation)

    controller.emergencyStop()
    #expect(controller.snapshot.phase == .inactive)
    #expect(controller.snapshot.stopReason == .emergencyStop)
    #expect(!controller.canBeginUIOperation)
    #expect(cancelledOperationIDs == ["operation-1"])
}

@Test("exclusive test mode requires readiness and expires automatically")
func exclusiveTestModeReadinessAndExpiration() throws {
    let scheduler = ManualExpirationScheduler()
    let controller = ExclusiveTestModeController(
        now: { Date(timeIntervalSince1970: 2_000) },
        expirationScheduler: scheduler
    )

    #expect(throws: ExclusiveTestModeError.accessibilityNotReady) {
        try controller.activate(
            duration: 60,
            readiness: ExclusiveTestModeReadiness(
                accessibilityReady: false,
                testProjectPolicyContext: true
            )
        )
    }
    #expect(throws: ExclusiveTestModeError.testProjectPolicyContextMissing) {
        try controller.activate(
            duration: 60,
            readiness: ExclusiveTestModeReadiness(
                accessibilityReady: true,
                testProjectPolicyContext: false
            )
        )
    }
    #expect(throws: ExclusiveTestModeError.invalidDuration) {
        try controller.activate(
            duration: ExclusiveTestModeController.maximumDuration + 1,
            readiness: ExclusiveTestModeReadiness(
                accessibilityReady: true,
                testProjectPolicyContext: true
            )
        )
    }

    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: true
        )
    )
    scheduler.fire()

    #expect(controller.snapshot.phase == .inactive)
    #expect(controller.snapshot.stopReason == .timedOut)
    #expect(controller.snapshot.deadline == nil)
}

@Test("focus loss pauses test mode and cancels in-flight UI work")
func exclusiveTestModeObservesFocusLoss() throws {
    let controller = ExclusiveTestModeController()
    var cancelled = false
    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: true
        )
    )
    controller.registerPendingOperation(id: "operation-1") {
        cancelled = true
    }

    controller.observe(.focusLost)

    #expect(controller.snapshot.phase == .paused)
    #expect(controller.snapshot.pauseReason == .focusLost)
    #expect(!controller.canBeginUIOperation)
    #expect(cancelled)

    #expect(throws: ExclusiveTestModeError.testProjectPolicyContextMissing) {
        try controller.resume(readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: false
        ))
    }
    #expect(controller.snapshot.phase == .paused)
}
