import Foundation
import Testing

@testable import LogicBridgeCore

@Test("exclusive test mode pauses, resumes, and emergency-stops pending work")
func exclusiveTestModeTransitions() throws {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var cancelledOperationIDs: [String] = []
    let controller = ExclusiveTestModeController(now: { startedAt })

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

    try controller.resume()
    #expect(controller.snapshot.phase == .active)
    #expect(controller.canBeginUIOperation)

    controller.emergencyStop()
    #expect(controller.snapshot.phase == .inactive)
    #expect(controller.snapshot.stopReason == .emergencyStop)
    #expect(!controller.canBeginUIOperation)
    #expect(cancelledOperationIDs == ["operation-1"])
}
