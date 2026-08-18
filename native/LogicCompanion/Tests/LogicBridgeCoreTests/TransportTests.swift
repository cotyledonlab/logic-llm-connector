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
