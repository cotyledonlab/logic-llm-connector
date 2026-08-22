import Foundation

public let bridgeProtocolVersion = "1.0.0"

public enum OperationStatus: String, Codable, Sendable {
    case succeeded
    case partial
    case failed
    case cancelled
    case timedOut = "timed_out"
}

public enum Reliability: String, Codable, Sendable {
    case verifiedDeterministic = "verified_deterministic"
    case verifiedUIDriven = "verified_ui_driven"
    case bestEffort = "best_effort"
    case unsupported
}

public enum CheckStatus: String, Codable, Sendable {
    case passed
    case warning
    case failed
    case unknown
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct Evidence: Codable, Sendable, Equatable {
    public let source: String
    public let observedAt: Date
    public let value: JSONValue

    public init(source: String, observedAt: Date, value: JSONValue) {
        self.source = source
        self.observedAt = observedAt
        self.value = value
    }
}

public struct DoctorCheck: Codable, Sendable, Equatable {
    public let id: String
    public let status: CheckStatus
    public let summary: String
    public let remediation: String?
    public let evidence: [Evidence]

    public init(
        id: String,
        status: CheckStatus,
        summary: String,
        remediation: String? = nil,
        evidence: [Evidence]
    ) {
        self.id = id
        self.status = status
        self.summary = summary
        self.remediation = remediation
        self.evidence = evidence
    }
}

public struct DoctorData: Codable, Sendable, Equatable {
    public let checks: [DoctorCheck]
}

public struct DoctorResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: DoctorData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public enum TransportPlayingState: String, Codable, Sendable {
    case playing
    case stopped
    case unknown
}

public enum TransportCycleState: String, Codable, Sendable {
    case enabled
    case disabled
    case unknown
}

public enum TransportRecordReadyState: String, Codable, Sendable {
    case ready
    case notReady = "not_ready"
    case unknown
}

public struct TransportStateData: Codable, Sendable, Equatable {
    public let playing: TransportPlayingState
    public let cycle: TransportCycleState
    public let recordReady: TransportRecordReadyState
    public let observedAt: Date?

    public init(
        playing: TransportPlayingState,
        cycle: TransportCycleState,
        recordReady: TransportRecordReadyState,
        observedAt: Date?
    ) {
        self.playing = playing
        self.cycle = cycle
        self.recordReady = recordReady
        self.observedAt = observedAt
    }
}

public struct TransportStateResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: TransportStateData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public struct TransportOperationData: Codable, Sendable, Equatable {
    public let requestedState: TransportPlayingState
    public let commandDispatched: Bool
    public let state: TransportStateData

    public init(
        requestedState: TransportPlayingState,
        commandDispatched: Bool,
        state: TransportStateData
    ) {
        self.requestedState = requestedState
        self.commandDispatched = commandDispatched
        self.state = state
    }
}

public struct TransportOperationResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: TransportOperationData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public enum TransportMoveDirection: String, Codable, Sendable {
    case backward
    case forward
}

public enum TransportLocateTarget: String, Codable, Sendable {
    case projectStart = "project_start"
}

public struct TransportPositionData: Codable, Sendable, Equatable {
    public let display: String?
    public let observedAt: Date?

    public init(display: String?, observedAt: Date?) {
        self.display = display
        self.observedAt = observedAt
    }

    enum CodingKeys: String, CodingKey {
        case display
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        display = try container.decodeIfPresent(String.self, forKey: .display)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let display {
            try container.encode(display, forKey: .display)
        } else {
            try container.encodeNil(forKey: .display)
        }
        if let observedAt {
            try container.encode(observedAt, forKey: .observedAt)
        } else {
            try container.encodeNil(forKey: .observedAt)
        }
    }
}

public struct TransportLocationOperationData: Codable, Sendable, Equatable {
    public let requestedDirection: TransportMoveDirection
    public let steps: Int
    public let commandDispatched: Bool
    public let initialPosition: TransportPositionData
    public let position: TransportPositionData

    public init(
        requestedDirection: TransportMoveDirection,
        steps: Int,
        commandDispatched: Bool,
        initialPosition: TransportPositionData,
        position: TransportPositionData
    ) {
        self.requestedDirection = requestedDirection
        self.steps = steps
        self.commandDispatched = commandDispatched
        self.initialPosition = initialPosition
        self.position = position
    }
}

public struct TransportLocationOperationResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: TransportLocationOperationData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public struct TransportLocateOperationData: Codable, Sendable, Equatable {
    public let requestedTarget: TransportLocateTarget
    public let commandDispatched: Bool
    public let initialPosition: TransportPositionData
    public let position: TransportPositionData

    public init(
        requestedTarget: TransportLocateTarget,
        commandDispatched: Bool,
        initialPosition: TransportPositionData,
        position: TransportPositionData
    ) {
        self.requestedTarget = requestedTarget
        self.commandDispatched = commandDispatched
        self.initialPosition = initialPosition
        self.position = position
    }
}

public struct TransportLocateOperationResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: TransportLocateOperationData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public enum LogicTrackType: String, Codable, Sendable {
    case softwareInstrument = "software_instrument"
    case audio
    case externalMIDI = "external_midi"
    case unknown
}

public enum TrackOperationAction: String, Codable, Sendable {
    case observe
    case create
    case rename
    case select
    case duplicate
    case reorder
    case delete
}

public enum TrackOperationFailure: String, Codable, Sendable, Error {
    case projectPolicyMissing = "project_policy_missing"
    case testModeInactive = "test_mode_inactive"
    case accessibilityUnavailable = "accessibility_unavailable"
    case logicNotRunning = "logic_not_running"
    case logicNotFocused = "logic_not_focused"
    case trackNotFound = "track_not_found"
    case unsupportedTrackType = "unsupported_track_type"
    case invalidName = "invalid_name"
    case invalidPosition = "invalid_position"
    case confirmationRequired = "confirmation_required"
    case dialogPresented = "dialog_presented"
    case commandFailed = "command_failed"
    case postconditionFailed = "postcondition_failed"
    case undoUnavailable = "undo_unavailable"
}

public struct LogicTrackIdentity: Codable, Sendable, Equatable {
    public let id: String
    public let position: Int
    public let type: LogicTrackType
    public let name: String
    public let selected: Bool
    public let observedAt: Date

    public init(
        id: String,
        position: Int,
        type: LogicTrackType,
        name: String,
        selected: Bool,
        observedAt: Date
    ) {
        self.id = id
        self.position = position
        self.type = type
        self.name = name
        self.selected = selected
        self.observedAt = observedAt
    }
}

public struct TrackOperationData: Codable, Sendable, Equatable {
    public let action: TrackOperationAction
    public let commandDispatched: Bool
    public let policyContext: Bool
    public let targetTrackID: String?
    public let undoAvailable: Bool
    public let tracks: [LogicTrackIdentity]
    public let failure: TrackOperationFailure?

    public init(
        action: TrackOperationAction,
        commandDispatched: Bool,
        policyContext: Bool,
        targetTrackID: String? = nil,
        undoAvailable: Bool = false,
        tracks: [LogicTrackIdentity],
        failure: TrackOperationFailure? = nil
    ) {
        self.action = action
        self.commandDispatched = commandDispatched
        self.policyContext = policyContext
        self.targetTrackID = targetTrackID
        self.undoAvailable = undoAvailable
        self.tracks = tracks
        self.failure = failure
    }

    enum CodingKeys: String, CodingKey {
        case action
        case commandDispatched
        case policyContext
        case targetTrackID = "targetTrackId"
        case undoAvailable
        case tracks
        case failure
    }
}

public struct TrackOperationResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: TrackOperationData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public let logicMusicalTimePPQ = 960

public struct MusicalTime: Codable, Sendable, Equatable, Hashable {
    public let ticks: Int64
    public let ppq: Int

    public init(ticks: Int64, ppq: Int = logicMusicalTimePPQ) {
        self.ticks = ticks
        self.ppq = ppq
    }
}

public struct MIDINoteContent: Codable, Sendable, Equatable {
    public let pitch: Int
    public let onset: MusicalTime
    public let duration: MusicalTime
    public let velocity: Int
    public let channel: Int

    public init(
        pitch: Int,
        onset: MusicalTime,
        duration: MusicalTime,
        velocity: Int,
        channel: Int
    ) {
        self.pitch = pitch
        self.onset = onset
        self.duration = duration
        self.velocity = velocity
        self.channel = channel
    }
}

public struct MIDINoteIdentity: Codable, Sendable, Equatable {
    public let id: String
    public let pitch: Int
    public let onset: MusicalTime
    public let duration: MusicalTime
    public let velocity: Int
    public let channel: Int

    public init(
        id: String,
        pitch: Int,
        onset: MusicalTime,
        duration: MusicalTime,
        velocity: Int,
        channel: Int
    ) {
        self.id = id
        self.pitch = pitch
        self.onset = onset
        self.duration = duration
        self.velocity = velocity
        self.channel = channel
    }

    public init(id: String, content: MIDINoteContent) {
        self.init(
            id: id,
            pitch: content.pitch,
            onset: content.onset,
            duration: content.duration,
            velocity: content.velocity,
            channel: content.channel
        )
    }

    public var content: MIDINoteContent {
        MIDINoteContent(
            pitch: pitch,
            onset: onset,
            duration: duration,
            velocity: velocity,
            channel: channel
        )
    }
}

public struct MIDIRegionIdentity: Codable, Sendable, Equatable {
    public let id: String
    public let trackID: String
    public let name: String
    public let position: MusicalTime
    public let length: MusicalTime
    public let notes: [MIDINoteIdentity]
    public let selected: Bool
    public let active: Bool
    public let observedAt: Date

    public init(
        id: String,
        trackID: String,
        name: String,
        position: MusicalTime,
        length: MusicalTime,
        notes: [MIDINoteIdentity],
        selected: Bool,
        active: Bool,
        observedAt: Date
    ) {
        self.id = id
        self.trackID = trackID
        self.name = name
        self.position = position
        self.length = length
        self.notes = notes
        self.selected = selected
        self.active = active
        self.observedAt = observedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case trackID = "trackId"
        case name
        case position
        case length
        case notes
        case selected
        case active
        case observedAt
    }
}

public struct MIDIFidelityDifference: Codable, Sendable, Equatable {
    public let targetID: String?
    public let field: String
    public let requested: JSONValue
    public let observed: JSONValue
    public let reason: String

    public init(targetID: String? = nil, field: String, requested: JSONValue, observed: JSONValue, reason: String) {
        self.targetID = targetID
        self.field = field
        self.requested = requested
        self.observed = observed
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case targetID = "targetId"
        case field
        case requested
        case observed
        case reason
    }
}

public enum MIDIRegionOperationAction: String, Codable, Sendable {
    case observe
    case create
    case rename
    case move
    case resize
    case duplicate
    case split
    case updateNote = "update_note"
    case replaceNotes = "replace_notes"
    case delete
    case verifyPlayback = "verify_playback"
}

public enum MIDIRegionOperationFailure: String, Codable, Sendable, Error {
    case projectPolicyMissing = "project_policy_missing"
    case testModeInactive = "test_mode_inactive"
    case accessibilityUnavailable = "accessibility_unavailable"
    case logicNotRunning = "logic_not_running"
    case logicNotFocused = "logic_not_focused"
    case trackNotFound = "track_not_found"
    case regionNotFound = "region_not_found"
    case noteNotFound = "note_not_found"
    case invalidMusicalTime = "invalid_musical_time"
    case invalidNote = "invalid_note"
    case invalidName = "invalid_name"
    case invalidSplitPosition = "invalid_split_position"
    case confirmationRequired = "confirmation_required"
    case dialogPresented = "dialog_presented"
    case commandFailed = "command_failed"
    case postconditionFailed = "postcondition_failed"
    case undoUnavailable = "undo_unavailable"
    case playbackNotObserved = "playback_not_observed"
}

public struct MIDIRegionOperationData: Codable, Sendable, Equatable {
    public let action: MIDIRegionOperationAction
    public let commandDispatched: Bool
    public let policyContext: Bool
    public let targetRegionID: String?
    public let createdRegionIDs: [String]
    public let exactFidelity: Bool
    public let fidelityDifferences: [MIDIFidelityDifference]
    public let playbackVerified: Bool
    public let undoAvailable: Bool
    public let regions: [MIDIRegionIdentity]
    public let failure: MIDIRegionOperationFailure?

    public init(
        action: MIDIRegionOperationAction,
        commandDispatched: Bool,
        policyContext: Bool,
        targetRegionID: String? = nil,
        createdRegionIDs: [String] = [],
        fidelityDifferences: [MIDIFidelityDifference] = [],
        playbackVerified: Bool = false,
        undoAvailable: Bool = false,
        regions: [MIDIRegionIdentity],
        failure: MIDIRegionOperationFailure? = nil
    ) {
        self.action = action
        self.commandDispatched = commandDispatched
        self.policyContext = policyContext
        self.targetRegionID = targetRegionID
        self.createdRegionIDs = createdRegionIDs
        self.exactFidelity = fidelityDifferences.isEmpty
        self.fidelityDifferences = fidelityDifferences
        self.playbackVerified = playbackVerified
        self.undoAvailable = undoAvailable
        self.regions = regions
        self.failure = failure
    }

    enum CodingKeys: String, CodingKey {
        case action
        case commandDispatched
        case policyContext
        case targetRegionID = "targetRegionId"
        case createdRegionIDs = "createdRegionIds"
        case exactFidelity
        case fidelityDifferences
        case playbackVerified
        case undoAvailable
        case regions
        case failure
    }
}

public struct MIDIRegionOperationResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: MIDIRegionOperationData
    public let evidence: [Evidence]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
