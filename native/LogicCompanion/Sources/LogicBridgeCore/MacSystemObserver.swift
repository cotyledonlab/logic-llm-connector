import AppKit
import ApplicationServices
import Foundation

public struct MacSystemObserver: SystemObserving {
    public init() {}

    public var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    public var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    public var logicApplication: LogicApplicationObservation {
        let path = "/Applications/Logic Pro.app"
        let bundleIdentifier = "com.apple.logic10"
        let bundle = Bundle(path: path)
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }

        return LogicApplicationObservation(
            installed: bundle != nil,
            running: running,
            version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            bundleIdentifier: bundleIdentifier,
            path: path
        )
    }

    public var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }
}
