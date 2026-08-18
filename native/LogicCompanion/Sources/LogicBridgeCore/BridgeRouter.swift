import Foundation

public enum BridgeRouterError: Error, Equatable {
    case invalidJSONRPCVersion(String)
    case unsupportedProtocolVersion(String)
    case unsupportedMethod(String)
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

private struct DoctorRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let method: String
    let params: DoctorParameters
}

private struct DoctorResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCID
    let result: DoctorResult
}

public struct BridgeRouter: Sendable {
    private let doctor: Doctor

    public init(doctor: Doctor) {
        self.doctor = doctor
    }

    public func handle(_ data: Data) throws -> Data {
        let request = try JSONDecoder().decode(DoctorRequest.self, from: data)
        guard request.jsonrpc == "2.0" else {
            throw BridgeRouterError.invalidJSONRPCVersion(request.jsonrpc)
        }
        guard request.params.protocolVersion == bridgeProtocolVersion else {
            throw BridgeRouterError.unsupportedProtocolVersion(request.params.protocolVersion)
        }
        guard request.method == "logic.doctor" else {
            throw BridgeRouterError.unsupportedMethod(request.method)
        }

        return try JSONEncoder.bridge.encode(
            DoctorResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: doctor.run(operationID: request.params.operationID)
            )
        )
    }
}
