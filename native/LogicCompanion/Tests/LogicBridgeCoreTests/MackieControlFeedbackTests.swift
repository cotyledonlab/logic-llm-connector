import Foundation
import Testing

@testable import LogicBridgeCore

@Test("feedback monitor distinguishes Mackie-compatible UMP traffic")
func feedbackMonitorDistinguishesMackieCompatibleUMPTraffic() {
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let monitor = MackieControlFeedbackMonitor(now: { observedAt })

    monitor.record([
        MIDIMessage(timestamp: 1, words: [0x2090_3C64]),
        MIDIMessage(timestamp: 2, words: [0x3016_0000, 0x0066_1400]),
        MIDIMessage(timestamp: 3, words: [0x1000_0000]),
    ])

    #expect(monitor.feedbackSnapshot == MackieControlFeedbackSnapshot(
        packetCount: 3,
        midi1ChannelVoicePacketCount: 1,
        systemExclusivePacketCount: 1,
        lastReceivedAt: observedAt
    ))
    #expect(monitor.feedbackSnapshot.hasControlSurfaceTraffic)
}

@Test("empty feedback monitor does not claim traffic")
func emptyFeedbackMonitorDoesNotClaimTraffic() {
    let monitor = MackieControlFeedbackMonitor()

    #expect(monitor.feedbackSnapshot.packetCount == 0)
    #expect(!monitor.feedbackSnapshot.hasControlSurfaceTraffic)
    #expect(monitor.feedbackSnapshot.lastReceivedAt == nil)
}
