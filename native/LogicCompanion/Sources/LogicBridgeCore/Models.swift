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

public extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
