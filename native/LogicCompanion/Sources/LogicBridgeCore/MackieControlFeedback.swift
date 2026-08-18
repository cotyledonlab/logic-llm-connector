import Foundation

public struct MackieControlFeedbackSnapshot: Sendable, Equatable {
    public let packetCount: Int
    public let midi1ChannelVoicePacketCount: Int
    public let systemExclusivePacketCount: Int
    public let lastReceivedAt: Date?
    public let transportSequence: UInt64
    public let transportState: TransportStateData
    public let positionSequence: UInt64
    public let positionDisplay: String?
    public let positionObservedAt: Date?

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
        ),
        positionSequence: UInt64 = 0,
        positionDisplay: String? = nil,
        positionObservedAt: Date? = nil
    ) {
        self.packetCount = packetCount
        self.midi1ChannelVoicePacketCount = midi1ChannelVoicePacketCount
        self.systemExclusivePacketCount = systemExclusivePacketCount
        self.lastReceivedAt = lastReceivedAt
        self.transportSequence = transportSequence
        self.transportState = transportState
        self.positionSequence = positionSequence
        self.positionDisplay = positionDisplay
        self.positionObservedAt = positionObservedAt
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
    private var positionSequence: UInt64 = 0
    private var positionDigits = [UInt8?](repeating: nil, count: 10)
    private var positionObservedAt: Date?

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
                transportState: transportStateWithoutLocking(),
                positionSequence: positionSequence,
                positionDisplay: positionDisplayWithoutLocking(),
                positionObservedAt: positionObservedAt
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
                        recordPositionDisplay(word)
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

    private func recordPositionDisplay(_ word: UInt32) {
        let status = UInt8((word >> 16) & 0xFF)
        guard status & 0xF0 == 0xB0 else { return }
        let controller = UInt8((word >> 8) & 0x7F)
        guard (0x40...0x49).contains(controller) else { return }
        let value = UInt8(word & 0x7F)
        positionDigits[Int(controller - 0x40)] = Self.positionDigit(for: value)
        positionSequence &+= 1
        positionObservedAt = now()
    }

    private func positionDisplayWithoutLocking() -> String? {
        guard positionDigits.allSatisfy({ $0 != nil }) else { return nil }
        return String(positionDigits.reversed().compactMap { digit in
            digit.map { Character(String($0)) }
        })
    }

    private static func positionDigit(for value: UInt8) -> UInt8? {
        let characterCode = value & 0x3F
        guard (0x30...0x39).contains(characterCode) else { return nil }
        return characterCode - 0x30
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
