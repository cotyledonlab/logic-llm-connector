import Foundation
import Testing

@testable import LogicBridgeCore

private func positionSweep(_ display: String) -> [UInt32] {
    display.enumerated().map { index, character in
        0x20B0_0000
            | UInt32(0x49 - index) << 8
            | UInt32(character.asciiValue!)
    }
}

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

@Test("feedback monitor decodes Mackie transport LEDs into observed state")
func feedbackMonitorDecodesTransportLEDs() {
    let observedAt = Date(timeIntervalSince1970: 1_700_000_001)
    let monitor = MackieControlFeedbackMonitor(now: { observedAt })

    monitor.record([MIDIMessage(timestamp: 1, words: [
        0x2090_567F,
        0x2090_5D7F,
        0x2090_5F00,
    ])])

    let snapshot = monitor.feedbackSnapshot
    #expect(snapshot.transportSequence == 3)
    #expect(snapshot.transportState == TransportStateData(
        playing: .stopped,
        cycle: .enabled,
        recordReady: .notReady,
        observedAt: observedAt
    ))
}

@Test("feedback monitor decodes a complete Mackie position display")
func feedbackMonitorDecodesCompletePositionDisplay() {
    let observedAt = Date(timeIntervalSince1970: 1_700_000_002)
    let monitor = MackieControlFeedbackMonitor(now: { observedAt })

    monitor.record([MIDIMessage(timestamp: 1, words: [
        0x20B0_4920,
        0x20B0_4800,
        0x20B0_4737,
        0x20B0_4636,
        0x20B0_4535,
        0x20B0_4474,
        0x20B0_4333,
        0x20B0_4232,
        0x20B0_4131,
        0x20B0_4030,
    ])])

    let snapshot = monitor.feedbackSnapshot
    #expect(snapshot.positionSequence == 1)
    #expect(snapshot.positionDisplay == "0076543210")
    #expect(snapshot.positionObservedAt == observedAt)
}

@Test("feedback monitor commits only complete Mackie position sweeps")
func feedbackMonitorCommitsOnlyCompletePositionSweeps() {
    let monitor = MackieControlFeedbackMonitor()
    monitor.record([MIDIMessage(
        timestamp: 1,
        words: positionSweep("0010101006")
    )])

    monitor.record([MIDIMessage(timestamp: 2, words: [
        0x20B0_4031,
    ])])
    #expect(monitor.feedbackSnapshot.positionSequence == 1)
    #expect(monitor.feedbackSnapshot.positionDisplay == "0010101006")

    monitor.record([MIDIMessage(
        timestamp: 3,
        words: positionSweep("0020101001")
    )])
    #expect(monitor.feedbackSnapshot.positionSequence == 2)
    #expect(monitor.feedbackSnapshot.positionDisplay == "0020101001")
}
