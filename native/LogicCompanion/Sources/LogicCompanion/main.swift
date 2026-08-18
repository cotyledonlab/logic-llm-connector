import Foundation
import LogicBridgeCore

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--socket" else {
    FileHandle.standardError.write(
        Data("Usage: logic-companion --socket <path>\n".utf8)
    )
    exit(64)
}

let socketPath = CommandLine.arguments[2]
let router = BridgeRouter(doctor: Doctor(system: MacSystemObserver()))

do {
    try UnixSocketServer(path: socketPath, router: router).run()
} catch {
    FileHandle.standardError.write(Data("logic-companion: \(error)\n".utf8))
    exit(1)
}
