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

public extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
