// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LogicBridgeCore", targets: ["LogicBridgeCore"]),
        .executable(name: "logic-companion", targets: ["LogicCompanion"]),
    ],
    targets: [
        .target(name: "LogicBridgeCore"),
        .executableTarget(
            name: "LogicCompanion",
            dependencies: ["LogicBridgeCore"]
        ),
        .testTarget(
            name: "LogicBridgeCoreTests",
            dependencies: ["LogicBridgeCore"]
        ),
    ]
)
