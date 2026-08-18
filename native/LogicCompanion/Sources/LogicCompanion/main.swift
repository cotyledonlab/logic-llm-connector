import Darwin
import Foundation
import LogicBridgeCore

let socketPath: String
switch CommandLine.arguments.count {
case 1:
    socketPath = ProcessInfo.processInfo.environment["LOGIC_COMPANION_SOCKET"]
        ?? CompanionSocketPath.default(userID: getuid())
case 3 where CommandLine.arguments[1] == "--socket":
    socketPath = CommandLine.arguments[2]
default:
    FileHandle.standardError.write(
        Data("Usage: logic-companion [--socket <path>]\n".utf8)
    )
    exit(64)
}

let diagnosticsEnabled = ProcessInfo.processInfo.environment["LOGIC_ENABLE_DIAGNOSTICS"] == "1"
let router = BridgeRouter(
    doctor: Doctor(system: MacSystemObserver()),
    diagnosticsEnabled: diagnosticsEnabled
)

do {
    try UnixSocketServer(path: socketPath, router: router).run()
} catch {
    FileHandle.standardError.write(Data("logic-companion: \(error)\n".utf8))
    exit(1)
}
