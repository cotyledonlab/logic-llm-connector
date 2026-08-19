import CoreMIDI
import Foundation
import Testing

@testable import LogicBridgeCore

private final class FakeTransportMIDI: TransportMIDISending, @unchecked Sendable {
    private let lock = NSLock()
    private let onSend: @Sendable (MIDIMessage) -> Void
    let snapshot: VirtualMIDIEndpointSnapshot
    private var sentStorage: [MIDIMessage] = []

    init(
        sourceAvailable: Bool = true,
        onSend: @escaping @Sendable (MIDIMessage) -> Void = { _ in }
    ) {
        snapshot = VirtualMIDIEndpointSnapshot(
            sourceAvailable: sourceAvailable,
            destinationAvailable: true,
            protocolID: ._1_0
        )
        self.onSend = onSend
    }

    var sent: [MIDIMessage] { lock.withLock { sentStorage } }

    func send(_ message: MIDIMessage) throws {
        lock.withLock { sentStorage.append(message) }
        onSend(message)
    }
}

private final class FakeTransportClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) {
        lock.withLock { value.addTimeInterval(interval) }
    }
}

private final class ScriptedTransportFeedback: MackieControlFeedbackObserving, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshots: [MackieControlFeedbackSnapshot]
    private var index = 0

    init(_ snapshots: [MackieControlFeedbackSnapshot]) {
        self.snapshots = snapshots
    }

    var feedbackSnapshot: MackieControlFeedbackSnapshot {
        lock.withLock {
            let snapshot = snapshots[min(index, snapshots.count - 1)]
            index += 1
            return snapshot
        }
    }
}

private func positionSnapshot(
    _ display: String,
    sequence: UInt64
) -> MackieControlFeedbackSnapshot {
    MackieControlFeedbackSnapshot(
        packetCount: Int(sequence),
        midi1ChannelVoicePacketCount: Int(sequence),
        systemExclusivePacketCount: 0,
        lastReceivedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
        positionSequence: sequence,
        positionDisplay: display,
        positionObservedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
    )
}

private func recordPosition(_ display: String, in monitor: MackieControlFeedbackMonitor) {
    let words = display.enumerated().map { index, character in
        0x20B0_0000
            | UInt32(0x49 - index) << 8
            | UInt32(character.asciiValue!)
    }
    monitor.record([MIDIMessage(timestamp: 1, words: words)])
}

@Test("play dispatch is verified only after matching Mackie feedback")
func playDispatchIsVerifiedByFeedback() {
    let monitor = MackieControlFeedbackMonitor()
    let midi = FakeTransportMIDI { message in
        guard message.words.first == 0x2090_5E7F else { return }
        monitor.record([MIDIMessage(timestamp: 1, words: [
            0x2090_5D00,
            0x2090_5E7F,
        ])])
    }
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.setPlaying(
        true,
        operationID: "play-1",
        timeoutMilliseconds: 500
    )

    #expect(midi.sent.map(\.words) == [[0x2090_5E7F], [0x2090_5E00]])
    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.commandDispatched)
    #expect(result.data.state.playing == .playing)
    #expect(result.evidence.first?.source == "Mackie Control feedback")
}

@Test("stop is idempotent when stopped feedback is already observed")
func stopIsIdempotentFromObservedFeedback() {
    let monitor = MackieControlFeedbackMonitor()
    monitor.record([MIDIMessage(timestamp: 1, words: [0x2090_5D7F])])
    let midi = FakeTransportMIDI()
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.setPlaying(
        false,
        operationID: "stop-1",
        timeoutMilliseconds: 500
    )

    #expect(midi.sent.isEmpty)
    #expect(result.status == .succeeded)
    #expect(!result.data.commandDispatched)
    #expect(result.data.state.playing == .stopped)
}

@Test("missing feedback produces an explicit timed-out partial effect")
func missingFeedbackTimesOut() {
    let monitor = MackieControlFeedbackMonitor()
    let midi = FakeTransportMIDI()
    let clock = FakeTransportClock()
    let controller = MackieTransportController(
        midi: midi,
        feedback: monitor,
        now: { clock.now },
        wait: { clock.advance($0) }
    )

    let result = controller.setPlaying(
        true,
        operationID: "play-timeout",
        timeoutMilliseconds: 100
    )

    #expect(result.status == .timedOut)
    #expect(result.reliability == .bestEffort)
    #expect(result.data.commandDispatched)
    #expect(result.data.state.playing == .unknown)
    #expect(result.evidence.last?.source == "Mackie Control feedback deadline")
}

@Test("missing MIDI source fails without dispatch")
func missingMIDISourceFailsWithoutDispatch() {
    let monitor = MackieControlFeedbackMonitor()
    let midi = FakeTransportMIDI(sourceAvailable: false)
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.setPlaying(
        true,
        operationID: "play-no-source",
        timeoutMilliseconds: 100
    )

    #expect(result.status == .failed)
    #expect(result.reliability == .unsupported)
    #expect(!result.data.commandDispatched)
    #expect(midi.sent.isEmpty)
}

@Test("forward jog is verified after a reversible display refresh")
func forwardJogIsVerifiedAfterDisplayRefresh() {
    let monitor = MackieControlFeedbackMonitor()
    recordPosition("0000000100", in: monitor)
    let midi = FakeTransportMIDI { message in
        switch message.words.first {
        case 0x20B0_3C01:
            monitor.record([MIDIMessage(timestamp: 1, words: [0x20B0_4031])])
        case 0x2090_357F:
            recordPosition("0000000101", in: monitor)
        default:
            break
        }
    }
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.movePlayhead(
        .forward,
        steps: 1,
        operationID: "jog-1",
        timeoutMilliseconds: 500
    )

    #expect(midi.sent.map(\.words) == [
        [0x20B0_3C01],
        [0x2090_357F], [0x2090_3500],
        [0x2090_357F], [0x2090_3500],
    ])
    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.requestedDirection == .forward)
    #expect(result.data.steps == 1)
    #expect(result.data.initialPosition.display == "0000000100")
    #expect(result.data.position.display == "0000000101")
}

@Test("sparse position updates cannot verify a relative jog")
func sparsePositionUpdatesDoNotVerifyRelativeJog() {
    let feedback = ScriptedTransportFeedback([
        positionSnapshot("0010101006", sequence: 10),
        positionSnapshot("0010101006", sequence: 10),
        positionSnapshot("0010101001", sequence: 11),
        positionSnapshot("0020101001", sequence: 12),
    ])
    let midi = FakeTransportMIDI()
    let clock = FakeTransportClock()
    let controller = MackieTransportController(
        midi: midi,
        feedback: feedback,
        now: { clock.now },
        wait: { clock.advance($0) }
    )

    let result = controller.movePlayhead(
        .backward,
        steps: 1,
        operationID: "jog-sparse-display",
        timeoutMilliseconds: 100
    )

    #expect(result.status != .succeeded)
    #expect(result.reliability != .verifiedDeterministic)
}

@Test("project-start locate uses double STOP and fresh position feedback")
func projectStartLocateUsesDoubleStopAndFreshPositionFeedback() {
    let monitor = MackieControlFeedbackMonitor()
    monitor.record([MIDIMessage(timestamp: 1, words: [0x2090_5600, 0x2090_5D7F])])
    let midi = FakeTransportMIDI { message in
        if message.words.first == 0x2090_357F {
            recordPosition("0010101001", in: monitor)
        }
    }
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.locate(
        .projectStart,
        operationID: "locate-start",
        timeoutMilliseconds: 500
    )

    #expect(midi.sent.map(\.words) == [
        [0x2090_5D7F], [0x2090_5D00],
        [0x2090_5D7F], [0x2090_5D00],
        [0x2090_357F], [0x2090_3500],
        [0x2090_357F], [0x2090_3500],
    ])
    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.requestedTarget == .projectStart)
    #expect(result.data.initialPosition.display == nil)
    #expect(result.data.position.display == "0010101001")
}

@Test("project-start locate restores an enabled cycle")
func projectStartLocateRestoresEnabledCycle() {
    let monitor = MackieControlFeedbackMonitor()
    monitor.record([MIDIMessage(timestamp: 1, words: [0x2090_567F, 0x2090_5D7F])])
    recordPosition("0010103009", in: monitor)
    let midi = FakeTransportMIDI { message in
        switch message.words.first {
        case 0x2090_567F:
            let cycleWord: UInt32 = monitor.feedbackSnapshot.transportState.cycle == .enabled
                ? 0x2090_5600
                : 0x2090_567F
            monitor.record([MIDIMessage(timestamp: 1, words: [cycleWord])])
        case 0x2090_357F:
            recordPosition("0010101001", in: monitor)
        default:
            break
        }
    }
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.locate(
        .projectStart,
        operationID: "locate-cycle-restore",
        timeoutMilliseconds: 500
    )

    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.position.display == "0010101001")
    #expect(monitor.feedbackSnapshot.transportState.cycle == .enabled)
    #expect(midi.sent.map(\.words).filter { $0 == [0x2090_567F] }.count == 2)
}

@Test("project-start locate rejects unknown cycle state without dispatch")
func projectStartLocateRejectsUnknownCycle() {
    let monitor = MackieControlFeedbackMonitor()
    recordPosition("0010103009", in: monitor)
    let midi = FakeTransportMIDI()
    let controller = MackieTransportController(midi: midi, feedback: monitor)

    let result = controller.locate(
        .projectStart,
        operationID: "locate-cycle-unknown",
        timeoutMilliseconds: 500
    )

    #expect(result.status == .failed)
    #expect(result.reliability == .unsupported)
    #expect(!result.data.commandDispatched)
    #expect(midi.sent.isEmpty)
    #expect(result.evidence.last?.source == "Mackie Control locate precondition")
}
