import Foundation
import Testing

@testable import LogicBridgeCore

private struct FixedSafetyObserver: AutomationSafetyObserving {
    let interruption: AutomationSafetyInterruption?

    func currentInterruption() -> AutomationSafetyInterruption? {
        interruption
    }
}

@Test("safety monitor forwards environmental interruptions to test mode")
func safetyMonitorForwardsInterruption() throws {
    let controller = ExclusiveTestModeController()
    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: true
        )
    )
    let monitor = AutomationSafetyMonitor(
        controller: controller,
        observer: FixedSafetyObserver(interruption: .unexpectedModal)
    )

    monitor.poll()

    #expect(controller.snapshot.phase == .paused)
    #expect(controller.snapshot.pauseReason == .unexpectedModal)
}

@Test("safety monitor pauses when Test Project identity is no longer verified")
func safetyMonitorRejectsProjectIdentityChange() throws {
    let controller = ExclusiveTestModeController()
    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: true,
            testProjectPolicyContext: true
        )
    )
    var cancelled = false
    controller.registerPendingOperation(id: "operation-1") { cancelled = true }
    let monitor = AutomationSafetyMonitor(
        controller: controller,
        observer: FixedSafetyObserver(interruption: nil),
        policyContextReady: { false }
    )

    monitor.poll()

    #expect(controller.snapshot.phase == .paused)
    #expect(controller.snapshot.pauseReason == .projectIdentityChanged)
    #expect(cancelled)
}
