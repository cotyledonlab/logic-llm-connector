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
