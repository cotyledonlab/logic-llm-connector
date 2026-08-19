import AppKit
import Foundation

public struct LogicProjectIdentity: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let modified: Bool
    public let observedAt: Date

    public init(name: String, path: String, modified: Bool, observedAt: Date) {
        self.name = name
        self.path = path
        self.modified = modified
        self.observedAt = observedAt
    }
}

public enum ProjectLifecycleAction: String, Codable, Sendable {
    case observe
    case open
    case save
    case close
    case reopen
    case cleanup
}

public enum ProjectLifecycleFailure: String, Codable, Sendable {
    case fixtureNotFound = "fixture_not_found"
    case invalidFixture = "invalid_fixture"
    case userProjectOpen = "user_project_open"
    case noManagedProject = "no_managed_project"
    case projectIdentityChanged = "project_identity_changed"
    case unsavedChanges = "unsaved_changes"
    case dialogPresented = "dialog_presented"
    case automationDenied = "automation_denied"
    case commandFailed = "command_failed"
    case postconditionFailed = "postcondition_failed"
    case cleanupFailed = "cleanup_failed"
}

public struct ProjectLifecycleData: Codable, Sendable, Equatable {
    public let action: ProjectLifecycleAction
    public let commandDispatched: Bool
    public let project: LogicProjectIdentity?
    public let managedProjectPath: String?
    public let policyContext: Bool
    public let cleanupPerformed: Bool
    public let failure: ProjectLifecycleFailure?

    public init(
        action: ProjectLifecycleAction,
        commandDispatched: Bool,
        project: LogicProjectIdentity?,
        managedProjectPath: String?,
        policyContext: Bool,
        cleanupPerformed: Bool,
        failure: ProjectLifecycleFailure?
    ) {
        self.action = action
        self.commandDispatched = commandDispatched
        self.project = project
        self.managedProjectPath = managedProjectPath
        self.policyContext = policyContext
        self.cleanupPerformed = cleanupPerformed
        self.failure = failure
    }
}

public struct ProjectLifecycleResult: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let operationID: String
    public let status: OperationStatus
    public let reliability: Reliability
    public let startedAt: Date
    public let finishedAt: Date
    public let data: ProjectLifecycleData
    public let evidence: [Evidence]

    public init(
        protocolVersion: String,
        operationID: String,
        status: OperationStatus,
        reliability: Reliability,
        startedAt: Date,
        finishedAt: Date,
        data: ProjectLifecycleData,
        evidence: [Evidence]
    ) {
        self.protocolVersion = protocolVersion
        self.operationID = operationID
        self.status = status
        self.reliability = reliability
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.data = data
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case operationID = "operationId"
        case status
        case reliability
        case startedAt
        case finishedAt
        case data
        case evidence
    }
}

public enum LogicProjectScriptingError: Error, Equatable {
    case dialogPresented
    case automationDenied
    case commandFailed
}

public protocol LogicProjectScripting: Sendable {
    func observe() throws -> LogicProjectIdentity?
    func open(projectAt url: URL) throws
    func save(projectAt url: URL) throws
    func closeWithoutSaving(projectAt url: URL) throws
}

public protocol ProjectLifecycleControlling: Sendable {
    var hasVerifiedPolicyContext: Bool { get }
    func observe(operationID: String) -> ProjectLifecycleResult
    func openFixture(at path: String, operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult
    func save(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult
    func close(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult
    func reopen(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult
    func cleanup(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult
}

public final class TestProjectLifecycleController: ProjectLifecycleControlling, @unchecked Sendable {
    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Logic LLM Connector/Test Projects", isDirectory: true)
    }

    private let lock = NSLock()
    private let rootURL: URL
    private let scripting: any LogicProjectScripting
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void
    private let makeID: @Sendable () -> String
    private var managedProjectURL: URL?
    private var pendingOpenURL: URL?

    public init(
        rootURL: URL = TestProjectLifecycleController.defaultRootURL,
        scripting: any LogicProjectScripting = MacLogicProjectScripting(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.scripting = scripting
        self.fileManager = fileManager
        self.now = now
        self.sleep = sleep
        self.makeID = makeID
    }

    public var hasVerifiedPolicyContext: Bool {
        lock.withLock {
            guard let managedProjectURL,
                  let project = try? scripting.observe() else { return false }
            return samePath(project.path, managedProjectURL.path) && contains(managedProjectURL)
        }
    }

    public func observe(operationID: String) -> ProjectLifecycleResult {
        let startedAt = now()
        do {
            let project = try scripting.observe()
            let managed = lock.withLock { managedProjectURL }
            let verified = project.map { identity in
                managed.map { samePath(identity.path, $0.path) && contains($0) } ?? false
            } ?? false
            return result(
                operationID: operationID,
                action: .observe,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                project: project,
                managedURL: managed,
                policyContext: verified
            )
        } catch {
            return failureResult(
                operationID: operationID,
                action: .observe,
                startedAt: startedAt,
                failure: map(error),
                managedURL: lock.withLock { managedProjectURL }
            )
        }
    }

    public func openFixture(
        at path: String,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> ProjectLifecycleResult {
        let startedAt = now()
        let source = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard source.pathExtension.lowercased() == "logicx" else {
            return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: .invalidFixture)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: .fixtureNotFound)
        }
        guard !contains(source) else {
            return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: .invalidFixture)
        }
        do {
            if try scripting.observe() != nil {
                return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: .userProjectOpen)
            }
        } catch {
            return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: map(error))
        }

        let workspace = rootURL.appendingPathComponent(makeID(), isDirectory: true)
        let destination = workspace.appendingPathComponent(source.lastPathComponent, isDirectory: isDirectory.boolValue)
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            try? fileManager.removeItem(at: workspace)
            return failureResult(operationID: operationID, action: .open, startedAt: startedAt, failure: .commandFailed, cleanupPerformed: true)
        }

        lock.withLock {
            managedProjectURL = destination
            pendingOpenURL = destination
        }
        do {
            try scripting.open(projectAt: destination)
            guard let observed = waitForIdentity(destination, timeoutMilliseconds: timeoutMilliseconds) else {
                return failureResult(
                    operationID: operationID,
                    action: .open,
                    startedAt: startedAt,
                    failure: .postconditionFailed,
                    managedURL: destination,
                    commandDispatched: true,
                    cleanupPerformed: false
                )
            }
            lock.withLock { pendingOpenURL = nil }
            return result(
                operationID: operationID,
                action: .open,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                commandDispatched: true,
                project: observed,
                managedURL: destination,
                policyContext: true
            )
        } catch {
            lock.withLock { pendingOpenURL = nil }
            let cleaned = rollback(destination: destination, workspace: workspace, timeoutMilliseconds: timeoutMilliseconds)
            return failureResult(
                operationID: operationID,
                action: .open,
                startedAt: startedAt,
                failure: map(error),
                managedURL: cleaned ? nil : destination,
                commandDispatched: true,
                cleanupPerformed: cleaned
            )
        }
    }

    public func save(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult {
        mutateManagedProject(action: .save, operationID: operationID, timeoutMilliseconds: timeoutMilliseconds) { identity, managed in
            try scripting.save(projectAt: managed)
            return waitFor(timeoutMilliseconds: timeoutMilliseconds) {
                guard let observed = try? scripting.observe() else { return nil }
                return samePath(observed.path, identity.path) && !observed.modified ? observed : nil
            }
        }
    }

    public func close(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult {
        mutateManagedProject(action: .close, operationID: operationID, timeoutMilliseconds: timeoutMilliseconds) { identity, managed in
            guard !identity.modified else { throw ProjectMutationFailure.unsavedChanges }
            try scripting.closeWithoutSaving(projectAt: managed)
            let closed: LogicProjectIdentity? = waitFor(timeoutMilliseconds: timeoutMilliseconds) {
                do {
                    return try scripting.observe() == nil ? identity : nil
                } catch {
                    return nil
                }
            }
            return closed
        }
    }

    public func reopen(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult {
        let startedAt = now()
        guard let managed = lock.withLock({ managedProjectURL }), contains(managed), fileManager.fileExists(atPath: managed.path) else {
            return failureResult(operationID: operationID, action: .reopen, startedAt: startedAt, failure: .noManagedProject)
        }
        do {
            if try scripting.observe() != nil {
                return failureResult(operationID: operationID, action: .reopen, startedAt: startedAt, failure: .userProjectOpen, managedURL: managed)
            }
            lock.withLock { pendingOpenURL = managed }
            try scripting.open(projectAt: managed)
            guard let observed = waitForIdentity(managed, timeoutMilliseconds: timeoutMilliseconds) else {
                return failureResult(operationID: operationID, action: .reopen, startedAt: startedAt, failure: .postconditionFailed, managedURL: managed, commandDispatched: true)
            }
            lock.withLock { pendingOpenURL = nil }
            return result(
                operationID: operationID,
                action: .reopen,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                commandDispatched: true,
                project: observed,
                managedURL: managed,
                policyContext: true
            )
        } catch {
            lock.withLock { pendingOpenURL = nil }
            return failureResult(operationID: operationID, action: .reopen, startedAt: startedAt, failure: map(error), managedURL: managed, commandDispatched: true)
        }
    }

    public func cleanup(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult {
        let startedAt = now()
        guard let managed = lock.withLock({ managedProjectURL }), contains(managed) else {
            return result(
                operationID: operationID,
                action: .cleanup,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                project: try? scripting.observe(),
                managedURL: nil,
                policyContext: false,
                cleanupPerformed: true
            )
        }
        var commandDispatched = false
        do {
            if let observed = try scripting.observe() {
                guard samePath(observed.path, managed.path) else {
                    return failureResult(operationID: operationID, action: .cleanup, startedAt: startedAt, failure: .userProjectOpen, managedURL: managed)
                }
                lock.withLock { pendingOpenURL = nil }
                try scripting.closeWithoutSaving(projectAt: managed)
                commandDispatched = true
                let closed: Bool? = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                    do {
                        return try scripting.observe() == nil ? true : nil
                    } catch {
                        return nil
                    }
                })
                guard closed != nil else {
                    return failureResult(operationID: operationID, action: .cleanup, startedAt: startedAt, failure: .postconditionFailed, managedURL: managed, commandDispatched: true)
                }
            } else if lock.withLock({ pendingOpenURL != nil }) {
                return failureResult(
                    operationID: operationID,
                    action: .cleanup,
                    startedAt: startedAt,
                    failure: .cleanupFailed,
                    managedURL: managed
                )
            }
            try fileManager.removeItem(at: managed.deletingLastPathComponent())
            lock.withLock {
                managedProjectURL = nil
                pendingOpenURL = nil
            }
            return result(
                operationID: operationID,
                action: .cleanup,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                commandDispatched: commandDispatched,
                project: nil,
                managedURL: nil,
                policyContext: false,
                cleanupPerformed: true
            )
        } catch {
            return failureResult(operationID: operationID, action: .cleanup, startedAt: startedAt, failure: .cleanupFailed, managedURL: managed, commandDispatched: commandDispatched)
        }
    }

    private enum ProjectMutationFailure: Error {
        case unsavedChanges
    }

    private func mutateManagedProject(
        action: ProjectLifecycleAction,
        operationID: String,
        timeoutMilliseconds: Int,
        mutation: (LogicProjectIdentity, URL) throws -> LogicProjectIdentity?
    ) -> ProjectLifecycleResult {
        let startedAt = now()
        guard let managed = lock.withLock({ managedProjectURL }), contains(managed) else {
            return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: .noManagedProject)
        }
        do {
            guard let identity = try scripting.observe() else {
                return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: .noManagedProject, managedURL: managed)
            }
            guard samePath(identity.path, managed.path) else {
                return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: .projectIdentityChanged, managedURL: managed)
            }
            guard let observed = try mutation(identity, managed) else {
                return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: .postconditionFailed, managedURL: managed, commandDispatched: true)
            }
            return result(
                operationID: operationID,
                action: action,
                startedAt: startedAt,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                commandDispatched: true,
                project: action == .close ? nil : observed,
                managedURL: managed,
                policyContext: action != .close
            )
        } catch ProjectMutationFailure.unsavedChanges {
            return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: .unsavedChanges, managedURL: managed)
        } catch {
            return failureResult(operationID: operationID, action: action, startedAt: startedAt, failure: map(error), managedURL: managed, commandDispatched: true)
        }
    }

    private func waitForIdentity(_ url: URL, timeoutMilliseconds: Int) -> LogicProjectIdentity? {
        waitFor(timeoutMilliseconds: timeoutMilliseconds) {
            guard let identity = try? scripting.observe() else { return nil }
            return samePath(identity.path, url.path) ? identity : nil
        }
    }

    private func rollback(destination: URL, workspace: URL, timeoutMilliseconds: Int) -> Bool {
        do {
            if let current = try scripting.observe() {
                guard samePath(current.path, destination.path) else { return false }
                try scripting.closeWithoutSaving(projectAt: destination)
                let closed: Bool? = waitFor(timeoutMilliseconds: timeoutMilliseconds) {
                    do {
                        return try scripting.observe() == nil ? true : nil
                    } catch {
                        return nil
                    }
                }
                guard closed == true else { return false }
            }
            try fileManager.removeItem(at: workspace)
            lock.withLock {
                managedProjectURL = nil
                pendingOpenURL = nil
            }
            return true
        } catch {
            return false
        }
    }

    private func waitFor<Value>(timeoutMilliseconds: Int, condition: () -> Value?) -> Value? {
        let deadline = Date().addingTimeInterval(Double(max(0, timeoutMilliseconds)) / 1_000)
        repeat {
            if let value = condition() { return value }
            sleep(0.05)
        } while Date() < deadline
        return condition()
    }

    private func contains(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let root = rootURL.pathComponents
        return candidate.count > root.count && Array(candidate.prefix(root.count)) == root
    }

    private func samePath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.resolvingSymlinksInPath().path
            == URL(fileURLWithPath: rhs).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func map(_ error: Error) -> ProjectLifecycleFailure {
        switch error as? LogicProjectScriptingError {
        case .dialogPresented: .dialogPresented
        case .automationDenied: .automationDenied
        default: .commandFailed
        }
    }

    private func failureResult(
        operationID: String,
        action: ProjectLifecycleAction,
        startedAt: Date,
        failure: ProjectLifecycleFailure,
        managedURL: URL? = nil,
        commandDispatched: Bool = false,
        cleanupPerformed: Bool = false
    ) -> ProjectLifecycleResult {
        result(
            operationID: operationID,
            action: action,
            startedAt: startedAt,
            status: .failed,
            reliability: .verifiedDeterministic,
            commandDispatched: commandDispatched,
            project: try? scripting.observe(),
            managedURL: managedURL,
            policyContext: false,
            cleanupPerformed: cleanupPerformed,
            failure: failure
        )
    }

    private func result(
        operationID: String,
        action: ProjectLifecycleAction,
        startedAt: Date,
        status: OperationStatus,
        reliability: Reliability,
        commandDispatched: Bool = false,
        project: LogicProjectIdentity?,
        managedURL: URL?,
        policyContext: Bool,
        cleanupPerformed: Bool = false,
        failure: ProjectLifecycleFailure? = nil
    ) -> ProjectLifecycleResult {
        let observedAt = project?.observedAt ?? now()
        var evidenceValue: [String: JSONValue] = [
            "policyContext": .bool(policyContext),
            "action": .string(action.rawValue),
        ]
        if let project {
            evidenceValue["path"] = .string(project.path)
            evidenceValue["modified"] = .bool(project.modified)
        }
        return ProjectLifecycleResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: status,
            reliability: reliability,
            startedAt: startedAt,
            finishedAt: now(),
            data: ProjectLifecycleData(
                action: action,
                commandDispatched: commandDispatched,
                project: project,
                managedProjectPath: managedURL?.path,
                policyContext: policyContext,
                cleanupPerformed: cleanupPerformed,
                failure: failure
            ),
            evidence: [Evidence(source: "Logic document identity observation", observedAt: observedAt, value: .object(evidenceValue))]
        )
    }
}

public struct MacLogicProjectScripting: LogicProjectScripting {
    private static let separator = Character(UnicodeScalar(31))
    private enum AccessibilityObservation {
        case unavailable
        case observed(LogicProjectIdentity?)
    }

    public init() {}

    public func observe() throws -> LogicProjectIdentity? {
        switch observeUsingAccessibility() {
        case .observed(let project): return project
        case .unavailable: return try observeUsingAppleEvents()
        }
    }

    private func observeUsingAppleEvents() throws -> LogicProjectIdentity? {
        let output = try execute("""
        with timeout of 5 seconds
        tell application id "com.apple.logic10"
            if (count documents) is 0 then return ""
            set d to front document
            set fieldSeparator to ASCII character 31
            return (name of d as text) & fieldSeparator & (path of d as text) & fieldSeparator & (modified of d as text)
        end tell
        end timeout
        """)
        guard !output.isEmpty else { return nil }
        let fields = output.split(separator: Self.separator, omittingEmptySubsequences: false)
        guard fields.count == 3 else { throw LogicProjectScriptingError.commandFailed }
        return LogicProjectIdentity(
            name: String(fields[0]),
            path: String(fields[1]),
            modified: String(fields[2]).lowercased() == "true",
            observedAt: Date()
        )
    }

    private func observeUsingAccessibility() -> AccessibilityObservation {
        guard AXIsProcessTrusted(),
              let logic = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.logic10"
              }) else { return .unavailable }
        let application = AXUIElementCreateApplication(logic.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
        let windows = windowsValue as? [AXUIElement] else { return .unavailable }

        for window in windows {
            var documentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXDocumentAttribute as CFString,
                &documentValue
            ) == .success,
            let documentValue else { continue }

            let documentURL: URL?
            if let value = documentValue as? URL {
                documentURL = value
            } else if let value = documentValue as? String {
                let parsed = URL(string: value)
                documentURL = parsed?.isFileURL == true ? parsed : URL(fileURLWithPath: value)
            } else {
                documentURL = nil
            }
            guard let documentURL,
                  documentURL.pathExtension.lowercased() == "logicx" else { continue }

            var closeButtonValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXCloseButtonAttribute as CFString,
                &closeButtonValue
            ) == .success,
            let closeButtonValue else { return .unavailable }
            let closeButton = closeButtonValue as! AXUIElement
            var editedValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                closeButton,
                kAXEditedAttribute as CFString,
                &editedValue
            ) == .success,
            let modified = (editedValue as? NSNumber)?.boolValue else { return .unavailable }
            let standardized = documentURL.standardizedFileURL.resolvingSymlinksInPath()
            return .observed(LogicProjectIdentity(
                name: standardized.lastPathComponent,
                path: standardized.path,
                modified: modified,
                observedAt: Date()
            ))
        }
        return .observed(nil)
    }

    public func open(projectAt url: URL) throws {
        _ = try execute("""
        ignoring application responses
            tell application id "com.apple.logic10"
                open (POSIX file "\(escape(url.path))")
            end tell
        end ignoring
        """)
    }

    public func save(projectAt url: URL) throws {
        _ = try execute("ignoring application responses\ntell application id \"com.apple.logic10\" to save (first document whose path is \"\(escape(url.path))\")\nend ignoring")
    }

    public func closeWithoutSaving(projectAt url: URL) throws {
        _ = try execute("ignoring application responses\ntell application id \"com.apple.logic10\" to close (first document whose path is \"\(escape(url.path))\") saving no\nend ignoring")
    }

    private func execute(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw LogicProjectScriptingError.commandFailed
        }
        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details {
            let number = details[NSAppleScript.errorNumber] as? Int
            if number == -1743 { throw LogicProjectScriptingError.automationDenied }
            if logicHasModalWindow() { throw LogicProjectScriptingError.dialogPresented }
            throw LogicProjectScriptingError.commandFailed
        }
        return result.stringValue ?? ""
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func logicHasModalWindow() -> Bool {
        guard AXIsProcessTrusted(),
              let logic = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.logic10"
              }) else { return false }
        let application = AXUIElementCreateApplication(logic.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue else { return false }
        var modalValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowValue as! AXUIElement,
            kAXModalAttribute as CFString,
            &modalValue
        ) == .success else { return false }
        return (modalValue as? NSNumber)?.boolValue == true
    }
}
