import Foundation

public struct MackieControlFeedbackSnapshot: Sendable, Equatable {
    public let packetCount: Int
    public let midi1ChannelVoicePacketCount: Int
    public let systemExclusivePacketCount: Int
    public let lastReceivedAt: Date?
    public let transportSequence: UInt64
    public let transportState: TransportStateData

    public init(
        packetCount: Int,
        midi1ChannelVoicePacketCount: Int,
        systemExclusivePacketCount: Int,
        lastReceivedAt: Date?,
        transportSequence: UInt64 = 0,
        transportState: TransportStateData = TransportStateData(
            playing: .unknown,
            cycle: .unknown,
            recordReady: .unknown,
            observedAt: nil
        )
    ) {
        self.packetCount = packetCount
        self.midi1ChannelVoicePacketCount = midi1ChannelVoicePacketCount
        self.systemExclusivePacketCount = systemExclusivePacketCount
        self.lastReceivedAt = lastReceivedAt
        self.transportSequence = transportSequence
        self.transportState = transportState
    }

    public var hasControlSurfaceTraffic: Bool {
        midi1ChannelVoicePacketCount > 0 || systemExclusivePacketCount > 0
    }
}

public protocol MackieControlFeedbackObserving: Sendable {
    var feedbackSnapshot: MackieControlFeedbackSnapshot { get }
}

public final class MackieControlFeedbackMonitor: MackieControlFeedbackObserving, @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var packetCount = 0
    private var midi1ChannelVoicePacketCount = 0
    private var systemExclusivePacketCount = 0
    private var lastReceivedAt: Date?
    private var transportSequence: UInt64 = 0
    private var playLED: Bool?
    private var stopLED: Bool?
    private var cycleLED: Bool?
    private var recordLED: Bool?
    private var transportObservedAt: Date?

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public var feedbackSnapshot: MackieControlFeedbackSnapshot {
        lock.withLock {
            MackieControlFeedbackSnapshot(
                packetCount: packetCount,
                midi1ChannelVoicePacketCount: midi1ChannelVoicePacketCount,
                systemExclusivePacketCount: systemExclusivePacketCount,
                lastReceivedAt: lastReceivedAt,
                transportSequence: transportSequence,
                transportState: transportStateWithoutLocking()
            )
        }
    }

    public func record(_ messages: [MIDIMessage]) {
        guard !messages.isEmpty else { return }
        lock.withLock {
            packetCount += messages.count
            for message in messages {
                for word in message.words {
                    switch (word >> 28) & 0xF {
                    case 0x2:
                        midi1ChannelVoicePacketCount += 1
                        recordTransportLED(word)
                    case 0x3:
                        systemExclusivePacketCount += 1
                    default:
                        break
                    }
                }
            }
            lastReceivedAt = now()
        }
    }

    private func recordTransportLED(_ word: UInt32) {
        let status = UInt8((word >> 16) & 0xFF)
        let messageType = status & 0xF0
        guard messageType == 0x80 || messageType == 0x90 else { return }
        let note = UInt8((word >> 8) & 0x7F)
        let velocity = UInt8(word & 0x7F)
        let enabled = messageType == 0x90 && velocity > 0
        switch note {
        case MackieTransportNote.cycle.rawValue: cycleLED = enabled
        case MackieTransportNote.stop.rawValue: stopLED = enabled
        case MackieTransportNote.play.rawValue: playLED = enabled
        case MackieTransportNote.record.rawValue: recordLED = enabled
        default: return
        }
        transportSequence &+= 1
        transportObservedAt = now()
    }

    private func transportStateWithoutLocking() -> TransportStateData {
        let playing: TransportPlayingState = if playLED == true {
            .playing
        } else if stopLED == true || playLED == false {
            .stopped
        } else {
            .unknown
        }
        let cycle: TransportCycleState = switch cycleLED {
        case true: .enabled
        case false: .disabled
        case nil: .unknown
        }
        let recordReady: TransportRecordReadyState = switch recordLED {
        case true: .ready
        case false: .notReady
        case nil: .unknown
        }
        return TransportStateData(
            playing: playing,
            cycle: cycle,
            recordReady: recordReady,
            observedAt: transportObservedAt
        )
    }
}

public enum MackieTransportNote: UInt8, Sendable {
    case cycle = 0x56
    case rewind = 0x5B
    case stop = 0x5D
    case play = 0x5E
    case record = 0x5F
}
