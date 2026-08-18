import AppKit
import Darwin
import Foundation
import LogicBridgeCore

private func resolveSocketPath() -> String {
    switch CommandLine.arguments.count {
    case 1:
        return ProcessInfo.processInfo.environment["LOGIC_COMPANION_SOCKET"]
            ?? CompanionSocketPath.default(userID: getuid())
    case 3 where CommandLine.arguments[1] == "--socket":
        return CommandLine.arguments[2]
    default:
        FileHandle.standardError.write(
            Data("Usage: logic-companion [--socket <path>]\n".utf8)
        )
        exit(64)
    }
}

@MainActor
private final class CompanionApplicationDelegate: NSObject, NSApplicationDelegate {
    private let socketPath: String
    private let router: BridgeRouter
    private let midiOwner: VirtualMIDIEndpointOwner
    private let systemObserver = MacSystemObserver()
    private let testModeController = ExclusiveTestModeController()
    private lazy var safetyMonitor = AutomationSafetyMonitor(
        controller: testModeController,
        observer: MacAutomationSafetyObserver()
    )

    private var connectionStatus = CompanionConnectionStatus.starting
    private var server: UnixSocketServer?
    private var statusItem: NSStatusItem?
    private var connectionItem: NSMenuItem?
    private var logicItem: NSMenuItem?
    private var testModeItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var resumeItem: NSMenuItem?
    private var emergencyStopItem: NSMenuItem?
    private var statusTimer: Timer?
    private var safetyTimer: Timer?

    init(
        socketPath: String,
        router: BridgeRouter,
        midiOwner: VirtualMIDIEndpointOwner
    ) {
        self.socketPath = socketPath
        self.router = router
        self.midiOwner = midiOwner
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusMenu()
        startServer()
        statusTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )
        safetyTimer = Timer.scheduledTimer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(pollSafety),
            userInfo: nil,
            repeats: true
        )
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        safetyTimer?.invalidate()
    }

    private func configureStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "Logic Companion"

        let menu = NSMenu()
        let connectionItem = NSMenuItem(title: "Connection: Starting", action: nil, keyEquivalent: "")
        let logicItem = NSMenuItem(title: "Logic Pro: Checking", action: nil, keyEquivalent: "")
        let testModeItem = NSMenuItem(title: "Test Mode: Inactive", action: nil, keyEquivalent: "")
        [connectionItem, logicItem, testModeItem].forEach { $0.isEnabled = false }

        let unavailableStartItem = NSMenuItem(
            title: "Start Test Mode (Test Project Required)",
            action: nil,
            keyEquivalent: ""
        )
        unavailableStartItem.isEnabled = false

        let pauseItem = NSMenuItem(
            title: "Pause Automation",
            action: #selector(pauseAutomation),
            keyEquivalent: "p"
        )
        pauseItem.target = self
        let resumeItem = NSMenuItem(
            title: "Resume Automation",
            action: #selector(resumeAutomation),
            keyEquivalent: "r"
        )
        resumeItem.target = self
        let emergencyStopItem = NSMenuItem(
            title: "Emergency Stop",
            action: #selector(emergencyStop),
            keyEquivalent: "."
        )
        emergencyStopItem.target = self

        menu.addItem(connectionItem)
        menu.addItem(logicItem)
        menu.addItem(.separator())
        menu.addItem(testModeItem)
        menu.addItem(unavailableStartItem)
        menu.addItem(pauseItem)
        menu.addItem(resumeItem)
        menu.addItem(emergencyStopItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Logic Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
        self.connectionItem = connectionItem
        self.logicItem = logicItem
        self.testModeItem = testModeItem
        self.pauseItem = pauseItem
        self.resumeItem = resumeItem
        self.emergencyStopItem = emergencyStopItem
    }

    private func startServer() {
        let server = UnixSocketServer(
            path: socketPath,
            router: router
        ) { [weak self] status in
            DispatchQueue.main.async {
                self?.connectionStatus = status
                self?.refreshStatus()
            }
        }
        self.server = server
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try server.run()
            } catch {
                FileHandle.standardError.write(Data("logic-companion: \(error)\n".utf8))
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    @objc private func refreshStatus() {
        do {
            try midiOwner.ensureAvailable()
        } catch {
            FileHandle.standardError.write(
                Data("logic-companion: failed to recover virtual MIDI endpoints: \(error)\n".utf8)
            )
        }
        let presentation = CompanionStatusPresentation.make(
            connection: connectionStatus,
            logicRunning: systemObserver.logicApplication.running,
            testMode: testModeController.snapshot,
            now: Date()
        )
        connectionItem?.title = presentation.connectionTitle
        logicItem?.title = presentation.logicTitle
        testModeItem?.title = presentation.testModeTitle
        pauseItem?.isEnabled = presentation.canPause
        resumeItem?.isEnabled = presentation.canResume
        emergencyStopItem?.isEnabled = presentation.canEmergencyStop

        guard let button = statusItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: presentation.statusSymbolName,
            accessibilityDescription: presentation.testModeTitle
        )
        button.title = presentation.statusItemText.isEmpty
            ? ""
            : " \(presentation.statusItemText)"
        button.contentTintColor = switch presentation.statusTone {
        case .neutral: .labelColor
        case .warning: .systemOrange
        case .automationActive: .systemRed
        }
        button.toolTip = presentation.testModeTitle
    }

    @objc private func pollSafety() {
        safetyMonitor.poll()
        refreshStatus()
    }

    @objc private func pauseAutomation() {
        testModeController.pause()
        refreshStatus()
    }

    @objc private func resumeAutomation() {
        try? testModeController.resume()
        refreshStatus()
    }

    @objc private func emergencyStop() {
        testModeController.emergencyStop()
        refreshStatus()
    }
}

private let diagnosticsEnabled = ProcessInfo.processInfo.environment["LOGIC_ENABLE_DIAGNOSTICS"] == "1"
private let midiOwner: VirtualMIDIEndpointOwner = {
    do {
        return try VirtualMIDIEndpointOwner()
    } catch {
        FileHandle.standardError.write(
            Data("logic-companion: failed to create virtual MIDI endpoints: \(error)\n".utf8)
        )
        exit(70)
    }
}()
private let router = BridgeRouter(
    doctor: Doctor(
        system: MacSystemObserver(),
        midiEndpoints: midiOwner
    ),
    diagnosticsEnabled: diagnosticsEnabled
)
private let application = NSApplication.shared
private let delegate = CompanionApplicationDelegate(
    socketPath: resolveSocketPath(),
    router: router,
    midiOwner: midiOwner
)
application.delegate = delegate
application.run()
