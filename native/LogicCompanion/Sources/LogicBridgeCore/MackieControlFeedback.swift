import Foundation

public struct MackieControlFeedbackSnapshot: Sendable, Equatable {
    public let packetCount: Int
    public let midi1ChannelVoicePacketCount: Int
    public let systemExclusivePacketCount: Int
    public let lastReceivedAt: Date?

    public init(
        packetCount: Int,
        midi1ChannelVoicePacketCount: Int,
        systemExclusivePacketCount: Int,
        lastReceivedAt: Date?
    ) {
        self.packetCount = packetCount
        self.midi1ChannelVoicePacketCount = midi1ChannelVoicePacketCount
        self.systemExclusivePacketCount = systemExclusivePacketCount
        self.lastReceivedAt = lastReceivedAt
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

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public var feedbackSnapshot: MackieControlFeedbackSnapshot {
        lock.withLock {
            MackieControlFeedbackSnapshot(
                packetCount: packetCount,
                midi1ChannelVoicePacketCount: midi1ChannelVoicePacketCount,
                systemExclusivePacketCount: systemExclusivePacketCount,
                lastReceivedAt: lastReceivedAt
            )
        }
    }

    public func record(_ messages: [MIDIMessage]) {
        guard !messages.isEmpty else { return }
        lock.withLock {
            packetCount += messages.count
            for message in messages {
                guard let word = message.words.first else { continue }
                switch (word >> 28) & 0xF {
                case 0x2:
                    midi1ChannelVoicePacketCount += 1
                case 0x3:
                    systemExclusivePacketCount += 1
                default:
                    break
                }
            }
            lastReceivedAt = now()
        }
    }
}
