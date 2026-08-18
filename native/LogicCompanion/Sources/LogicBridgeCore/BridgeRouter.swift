import Foundation

public enum BridgeRouterError: Error, Equatable {
    case invalidJSONRPCVersion(String)
    case unsupportedProtocolVersion(String)
    case unsupportedMethod(String)
    case diagnosticsDisabled
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

private struct JSONRPCResponse<Result: Codable>: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let result: Result
}

public struct BridgeRouter: Sendable {
    private let doctor: Doctor
    private let axSnapshotter: any LogicAXSnapshotting
    private let diagnosticsEnabled: Bool
    private let now: @Sendable () -> Date

    public init(
        doctor: Doctor,
        axSnapshotter: any LogicAXSnapshotting = MacLogicAXSnapshotter(),
        diagnosticsEnabled: Bool = false,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.doctor = doctor
        self.axSnapshotter = axSnapshotter
        self.diagnosticsEnabled = diagnosticsEnabled
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
        default:
            throw BridgeRouterError.unsupportedMethod(envelope.method)
        }
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
