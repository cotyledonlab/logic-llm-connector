import Foundation
import Testing

@testable import LogicBridgeCore

@Test(
    "real Logic installation is observable",
    .enabled(if: ProcessInfo.processInfo.environment["LOGIC_INTEGRATION_TEST"] == "1")
)
func realLogicInstallationIsObservable() {
    let system = MacSystemObserver()
    let logic = system.logicApplication

    #expect(system.architecture == "arm64")
    #expect(logic.installed)
    #expect(logic.running)
    #expect(logic.version == "12.3")
    #expect(logic.bundleIdentifier == "com.apple.logic10")
    #expect(logic.path == "/Applications/Logic Pro.app")
}
