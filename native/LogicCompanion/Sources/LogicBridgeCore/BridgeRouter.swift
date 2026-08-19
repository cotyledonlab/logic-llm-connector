import Foundation

public enum BridgeRouterError: Error, Equatable {
    case invalidJSONRPCVersion(String)
    case unsupportedProtocolVersion(String)
    case unsupportedMethod(String)
    case diagnosticsDisabled
    case transportUnavailable
    case projectLifecycleUnavailable
    case trackOperationsUnavailable
}

public enum JSONRPCID: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .integer(try container.decode(Int.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        }
    }
}

private struct DoctorParameters: Codable {
    let protocolVersion: String
    let operationID: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
    }
}

private struct RequestEnvelope: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
}

private struct DoctorRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: DoctorParameters
}

private struct InspectUIParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let maxDepth: Int
    let maxNodes: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case maxDepth
        case maxNodes
    }
}

private struct InspectUIRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: InspectUIParameters
}

private struct TransportStateRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: DoctorParameters
}

private struct TransportSetPlayingParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let playing: Bool
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case playing
        case timeoutMs
    }
}

private struct TransportSetPlayingRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: TransportSetPlayingParameters
}

private struct TransportMovePlayheadParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let direction: TransportMoveDirection
    let steps: Int
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case direction
        case steps
        case timeoutMs
    }
}

private struct TransportMovePlayheadRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: TransportMovePlayheadParameters
}

private struct TransportLocateParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let target: TransportLocateTarget
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case target
        case timeoutMs
    }
}

private struct TransportLocateRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: TransportLocateParameters
}

private struct ProjectOpenParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let fixturePath: String
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case fixturePath
        case timeoutMs
    }
}

private struct ProjectOpenRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: ProjectOpenParameters
}

private struct ProjectMutationParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case timeoutMs
    }
}

private struct ProjectMutationRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: ProjectMutationParameters
}

private struct TrackMutationParameters: Codable {
    let protocolVersion: String
    let operationID: String
    let trackID: String?
    let type: LogicTrackType?
    let name: String?
    let position: Int?
    let confirm: Bool?
    let timeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case trackID = "trackId"
        case type
        case name
        case position
        case confirm
        case timeoutMs
    }
}

private struct TrackMutationRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: TrackMutationParameters
}

private struct JSONRPCResponse<Result: Codable>: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let result: Result
}

public struct BridgeRouter: Sendable {
    private let doctor: Doctor
    private let axSnapshotter: any LogicAXSnapshotting
    private let diagnosticsEnabled: Bool
    private let transport: (any TransportControlling)?
    private let projectLifecycle: (any ProjectLifecycleControlling)?
    private let trackOperations: (any TrackOperationsControlling)?
    private let now: @Sendable () -> Date

    public init(
        doctor: Doctor,
        axSnapshotter: any LogicAXSnapshotting = MacLogicAXSnapshotter(),
        diagnosticsEnabled: Bool = false,
        transport: (any TransportControlling)? = nil,
        projectLifecycle: (any ProjectLifecycleControlling)? = nil,
        trackOperations: (any TrackOperationsControlling)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.doctor = doctor
        self.axSnapshotter = axSnapshotter
        self.diagnosticsEnabled = diagnosticsEnabled
        self.transport = transport
        self.projectLifecycle = projectLifecycle
        self.trackOperations = trackOperations
        self.now = now
    }

    public func handle(_ data: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        guard envelope.jsonrpc == "2.0" else {
            throw BridgeRouterError.invalidJSONRPCVersion(envelope.jsonrpc)
        }

        switch envelope.method {
        case "logic.doctor":
            return try routeDoctor(data)
        case "logic.inspectUI":
            return try routeInspectUI(data)
        case "logic.transport.state":
            return try routeTransportState(data)
        case "logic.transport.setPlaying":
            return try routeTransportSetPlaying(data)
        case "logic.transport.movePlayhead":
            return try routeTransportMovePlayhead(data)
        case "logic.transport.locate":
            return try routeTransportLocate(data)
        case "logic.project.state":
            return try routeProjectState(data)
        case "logic.project.openFixture":
            return try routeProjectOpen(data)
        case "logic.project.save", "logic.project.close", "logic.project.reopen", "logic.project.cleanup":
            return try routeProjectMutation(data, method: envelope.method)
        case "logic.tracks.state":
            return try routeTrackState(data)
        case "logic.tracks.create", "logic.tracks.rename", "logic.tracks.select", "logic.tracks.duplicate", "logic.tracks.reorder", "logic.tracks.delete":
            return try routeTrackMutation(data, method: envelope.method)
        default:
            throw BridgeRouterError.unsupportedMethod(envelope.method)
        }
    }

    private func routeTrackState(_ data: Data) throws -> Data {
        guard let trackOperations else { throw BridgeRouterError.trackOperationsUnavailable }
        let request = try JSONDecoder().decode(TransportStateRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: trackOperations.observe(operationID: request.params.operationID)
        ))
    }

    private func routeTrackMutation(_ data: Data, method: String) throws -> Data {
        guard let trackOperations else { throw BridgeRouterError.trackOperationsUnavailable }
        let request = try JSONDecoder().decode(TrackMutationRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        let params = request.params
        let result: TrackOperationResult
        switch method {
        case "logic.tracks.create":
            result = trackOperations.create(
                type: try required(params.type),
                name: params.name,
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        case "logic.tracks.rename":
            result = trackOperations.rename(
                trackID: try required(params.trackID),
                name: try required(params.name),
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        case "logic.tracks.select":
            result = trackOperations.select(
                trackID: try required(params.trackID),
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        case "logic.tracks.duplicate":
            result = trackOperations.duplicate(
                trackID: try required(params.trackID),
                name: params.name,
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        case "logic.tracks.reorder":
            result = trackOperations.reorder(
                trackID: try required(params.trackID),
                position: try required(params.position),
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        default:
            result = trackOperations.delete(
                trackID: try required(params.trackID),
                confirmed: params.confirm == true,
                operationID: params.operationID,
                timeoutMilliseconds: params.timeoutMs
            )
        }
        return try JSONEncoder.bridge.encode(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: result))
    }

    private func required<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw DecodingError.valueNotFound(Value.self, .init(codingPath: [], debugDescription: "Missing required track parameter")) }
        return value
    }

    private func routeProjectState(_ data: Data) throws -> Data {
        guard let projectLifecycle else { throw BridgeRouterError.projectLifecycleUnavailable }
        let request = try JSONDecoder().decode(TransportStateRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: projectLifecycle.observe(operationID: request.params.operationID)
        ))
    }

    private func routeProjectOpen(_ data: Data) throws -> Data {
        guard let projectLifecycle else { throw BridgeRouterError.projectLifecycleUnavailable }
        let request = try JSONDecoder().decode(ProjectOpenRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: projectLifecycle.openFixture(
                at: request.params.fixturePath,
                operationID: request.params.operationID,
                timeoutMilliseconds: request.params.timeoutMs
            )
        ))
    }

    private func routeProjectMutation(_ data: Data, method: String) throws -> Data {
        guard let projectLifecycle else { throw BridgeRouterError.projectLifecycleUnavailable }
        let request = try JSONDecoder().decode(ProjectMutationRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        let result = switch method {
        case "logic.project.save": projectLifecycle.save(
            operationID: request.params.operationID,
            timeoutMilliseconds: request.params.timeoutMs
        )
        case "logic.project.close": projectLifecycle.close(
            operationID: request.params.operationID,
            timeoutMilliseconds: request.params.timeoutMs
        )
        case "logic.project.reopen": projectLifecycle.reopen(
            operationID: request.params.operationID,
            timeoutMilliseconds: request.params.timeoutMs
        )
        default: projectLifecycle.cleanup(
            operationID: request.params.operationID,
            timeoutMilliseconds: request.params.timeoutMs
        )
        }
        return try JSONEncoder.bridge.encode(JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: result
        ))
    }

    private func routeTransportState(_ data: Data) throws -> Data {
        guard let transport else { throw BridgeRouterError.transportUnavailable }
        let request = try JSONDecoder().decode(TransportStateRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: transport.observe(operationID: request.params.operationID)
            )
        )
    }

    private func routeTransportSetPlaying(_ data: Data) throws -> Data {
        guard let transport else { throw BridgeRouterError.transportUnavailable }
        let request = try JSONDecoder().decode(TransportSetPlayingRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: transport.setPlaying(
                    request.params.playing,
                    operationID: request.params.operationID,
                    timeoutMilliseconds: request.params.timeoutMs
                )
            )
        )
    }

    private func routeTransportMovePlayhead(_ data: Data) throws -> Data {
        guard let transport else { throw BridgeRouterError.transportUnavailable }
        let request = try JSONDecoder().decode(TransportMovePlayheadRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: transport.movePlayhead(
                    request.params.direction,
                    steps: request.params.steps,
                    operationID: request.params.operationID,
                    timeoutMilliseconds: request.params.timeoutMs
                )
            )
        )
    }

    private func routeTransportLocate(_ data: Data) throws -> Data {
        guard let transport else { throw BridgeRouterError.transportUnavailable }
        let request = try JSONDecoder().decode(TransportLocateRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: transport.locate(
                    request.params.target,
                    operationID: request.params.operationID,
                    timeoutMilliseconds: request.params.timeoutMs
                )
            )
        )
    }

    private func routeDoctor(_ data: Data) throws -> Data {
        let request = try JSONDecoder().decode(DoctorRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: doctor.run(operationID: request.params.operationID)
            )
        )
    }

    private func routeInspectUI(_ data: Data) throws -> Data {
        guard diagnosticsEnabled else { throw BridgeRouterError.diagnosticsDisabled }
        let request = try JSONDecoder().decode(InspectUIRequest.self, from: data)
        try validateProtocolVersion(request.params.protocolVersion)
        let startedAt = now()
        let snapshot = try axSnapshotter.capture(
            limits: AXSnapshotLimits(
                maxDepth: request.params.maxDepth,
                maxNodes: request.params.maxNodes
            )
        )
        let evidence = Evidence(
            source: "AXUIElement",
            observedAt: snapshot.capturedAt,
            value: .object([
                "nodeCount": .number(Double(snapshot.nodes.count)),
                "truncated": .bool(snapshot.truncated),
            ])
        )

        return try JSONEncoder.bridge.encode(
            JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: AXInspectionResult(
                    protocolVersion: bridgeProtocolVersion,
                    operationID: request.params.operationID,
                    status: .succeeded,
                    reliability: .verifiedDeterministic,
                    startedAt: startedAt,
                    finishedAt: now(),
                    data: snapshot,
                    evidence: [evidence]
                )
            )
        )
    }

    private func validateProtocolVersion(_ version: String) throws {
        guard version == bridgeProtocolVersion else {
            throw BridgeRouterError.unsupportedProtocolVersion(version)
        }
    }
}
