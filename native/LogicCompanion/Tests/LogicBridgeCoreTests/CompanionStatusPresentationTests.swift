import Foundation
import Testing

@testable import LogicBridgeCore

@Test("status presentation makes active automation continuously visible")
func statusPresentationShowsActiveAutomation() {
    let presentation = CompanionStatusPresentation.make(
        connection: .connected,
        logicRunning: true,
        testMode: ExclusiveTestModeSnapshot(
            phase: .active,
            deadline: Date(timeIntervalSince1970: 1_600),
            pauseReason: nil,
            stopReason: nil
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    #expect(presentation.connectionTitle == "Connection: Connected")
    #expect(presentation.logicTitle == "Logic Pro: Running")
    #expect(presentation.testModeTitle == "Test Mode: ACTIVE · 10:00 remaining")
    #expect(presentation.statusItemText == "TEST")
    #expect(presentation.canPause)
    #expect(presentation.canEmergencyStop)
}
