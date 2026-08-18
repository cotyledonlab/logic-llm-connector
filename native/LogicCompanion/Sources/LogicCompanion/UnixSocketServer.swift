import Darwin
import Foundation
import LogicBridgeCore

enum UnixSocketServerError: Error {
    case pathTooLong(String)
    case systemCall(String, Int32)
    case requestTooLarge
}

final class UnixSocketServer: @unchecked Sendable {
    private let path: String
    private let router: BridgeRouter
    private let onConnectionStatus: @Sendable (CompanionConnectionStatus) -> Void
    private var descriptor: Int32 = -1

    init(
        path: String,
        router: BridgeRouter,
        onConnectionStatus: @escaping @Sendable (CompanionConnectionStatus) -> Void = { _ in }
    ) {
        self.path = path
        self.router = router
        self.onConnectionStatus = onConnectionStatus
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        try? FileManager.default.removeItem(atPath: path)
    }

    func run() throws -> Never {
        signal(SIGPIPE, SIG_IGN)
        try? FileManager.default.removeItem(atPath: path)

        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw systemError("socket") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw UnixSocketServerError.pathTooLong(path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw systemError("bind") }
        guard Darwin.chmod(path, S_IRUSR | S_IWUSR) == 0 else {
            throw systemError("chmod")
        }
        guard Darwin.listen(descriptor, 8) == 0 else { throw systemError("listen") }
        onConnectionStatus(.listening)

        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                throw systemError("accept")
            }
            onConnectionStatus(.connected)
            do {
                try handle(client)
            } catch {
                let message = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Native bridge request failed\"}}\n"
                try? writeAll(Data(message.utf8), to: client)
            }
            Darwin.close(client)
            onConnectionStatus(.listening)
        }
    }

    private func handle(_ client: Int32) throws {
        var request = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while request.count <= 1_048_576 {
            let count = Darwin.read(client, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw systemError("read")
            }
            if count == 0 { break }
            request.append(contentsOf: chunk.prefix(Int(count)))
            if let newline = request.firstIndex(of: 0x0A) {
                request = request[..<newline]
                let response = try router.handle(request)
                try writeAll(response + Data([0x0A]), to: client)
                return
            }
        }
        throw UnixSocketServerError.requestTooLarge
    }

    private func writeAll(_ data: Data, to client: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    client,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw systemError("write")
                }
                written += count
            }
        }
    }

    private func systemError(_ call: String) -> UnixSocketServerError {
        .systemCall(call, errno)
    }
}
