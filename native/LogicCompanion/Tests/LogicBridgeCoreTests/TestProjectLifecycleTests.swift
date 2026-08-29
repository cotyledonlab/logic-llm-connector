import Foundation
import Testing

@testable import LogicBridgeCore

private final class FakeProjectScripting: LogicProjectScripting, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LogicProjectIdentity?
    var openError: LogicProjectScriptingError?
    var publishOpenIdentity = true
    var ignoredCloseAttempts = 0
    var openedPaths: [String] = []
    var closeCount = 0

    init(current: LogicProjectIdentity? = nil) {
        self.current = current
    }

    func observe() throws -> LogicProjectIdentity? {
        lock.withLock { current }
    }

    func open(projectAt url: URL) throws {
        if let openError { throw openError }
        lock.withLock {
            openedPaths.append(url.path)
            if publishOpenIdentity {
                current = LogicProjectIdentity(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url.path,
                    modified: false,
                    observedAt: Date(timeIntervalSince1970: 10)
                )
            }
        }
    }

    func save(projectAt _: URL) throws {
        lock.withLock {
            guard let current else { return }
            self.current = LogicProjectIdentity(
                name: current.name,
                path: current.path,
                modified: false,
                observedAt: Date(timeIntervalSince1970: 20)
            )
        }
    }

    func closeWithoutSaving(projectAt _: URL) throws {
        lock.withLock {
            closeCount += 1
            if closeCount > ignoredCloseAttempts { current = nil }
        }
    }

    func markModified() {
        lock.withLock {
            guard let current else { return }
            self.current = LogicProjectIdentity(
                name: current.name,
                path: current.path,
                modified: true,
                observedAt: Date(timeIntervalSince1970: 30)
            )
        }
    }

    func replaceCurrent(with identity: LogicProjectIdentity?) {
        lock.withLock { current = identity }
    }
}

private struct LifecycleFixture {
    let temporaryRoot: URL
    let testRoot: URL
    let source: URL
    let scripting: FakeProjectScripting
    let controller: TestProjectLifecycleController

    init(scripting: FakeProjectScripting = FakeProjectScripting()) throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("logic-lifecycle-tests-\(UUID().uuidString)", isDirectory: true)
        testRoot = temporaryRoot.appendingPathComponent("managed", isDirectory: true)
        source = temporaryRoot.appendingPathComponent("Fixture.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: source.appendingPathComponent("marker.txt"))
        self.scripting = scripting
        controller = TestProjectLifecycleController(
            rootURL: testRoot,
            scripting: scripting,
            sleep: { _ in },
            makeID: { "copy-1" }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}

@Test("test project lifecycle copies before open and verifies open save close reopen cleanup")
func testProjectLifecycleHappyPath() throws {
    let fixture = try LifecycleFixture()
    defer { fixture.remove() }

    let opened = fixture.controller.openFixture(
        at: fixture.source.path,
        operationID: "open-1",
        timeoutMilliseconds: 10
    )
    #expect(opened.status == .succeeded)
    #expect(opened.data.policyContext)
    #expect(opened.data.project?.path != fixture.source.path)
    #expect(fixture.controller.hasVerifiedPolicyContext)
    let managedPath = try #require(opened.data.managedProjectPath)
    #expect(FileManager.default.fileExists(atPath: managedPath + "/marker.txt"))
    #expect(fixture.scripting.openedPaths == [managedPath])

    fixture.scripting.markModified()
    let saved = fixture.controller.save(operationID: "save-1", timeoutMilliseconds: 10)
    #expect(saved.status == .succeeded)
    #expect(saved.data.project?.modified == false)

    let closed = fixture.controller.close(operationID: "close-1", timeoutMilliseconds: 10)
    #expect(closed.status == .succeeded)
    #expect(closed.data.project == nil)
    #expect(!fixture.controller.hasVerifiedPolicyContext)

    let reopened = fixture.controller.reopen(operationID: "reopen-1", timeoutMilliseconds: 10)
    #expect(reopened.status == .succeeded)
    #expect(reopened.data.project?.path == managedPath)

    fixture.scripting.markModified()
    let cleaned = fixture.controller.cleanup(operationID: "cleanup-1", timeoutMilliseconds: 10)
    #expect(cleaned.status == .succeeded)
    #expect(cleaned.data.cleanupPerformed)
    #expect(!FileManager.default.fileExists(atPath: managedPath))
}

@Test("cleanup retries one ignored close command for the exact managed project")
func testProjectCleanupRetriesIgnoredClose() throws {
    let scripting = FakeProjectScripting()
    scripting.ignoredCloseAttempts = 1
    let fixture = try LifecycleFixture(scripting: scripting)
    defer { fixture.remove() }
    let opened = fixture.controller.openFixture(
        at: fixture.source.path,
        operationID: "open-retry",
        timeoutMilliseconds: 10
    )
    let managedPath = try #require(opened.data.managedProjectPath)

    let cleaned = fixture.controller.cleanup(operationID: "cleanup-retry", timeoutMilliseconds: 10)

    #expect(cleaned.status == .succeeded)
    #expect(cleaned.data.cleanupPerformed)
    #expect(scripting.closeCount == 2)
    #expect(!FileManager.default.fileExists(atPath: managedPath))
}

@Test("close fails explicitly when the managed project has unsaved changes")
func testProjectCloseRejectsUnsavedChanges() throws {
    let fixture = try LifecycleFixture()
    defer { fixture.remove() }
    _ = fixture.controller.openFixture(at: fixture.source.path, operationID: "open-1", timeoutMilliseconds: 10)
    fixture.scripting.markModified()

    let result = fixture.controller.close(operationID: "close-1", timeoutMilliseconds: 10)

    #expect(result.status == .failed)
    #expect(result.data.failure == .unsavedChanges)
    #expect(fixture.scripting.closeCount == 0)
    #expect(fixture.controller.hasVerifiedPolicyContext)
}

@Test("open rejects an existing user project without dispatch or copy")
func testProjectOpenRejectsUserProject() throws {
    let userProject = LogicProjectIdentity(
        name: "User Project",
        path: "/Users/example/Music/User.logicx",
        modified: true,
        observedAt: Date(timeIntervalSince1970: 1)
    )
    let fixture = try LifecycleFixture(scripting: FakeProjectScripting(current: userProject))
    defer { fixture.remove() }

    let result = fixture.controller.openFixture(at: fixture.source.path, operationID: "open-1", timeoutMilliseconds: 10)

    #expect(result.status == .failed)
    #expect(result.data.failure == .userProjectOpen)
    #expect(!result.data.commandDispatched)
    #expect(!FileManager.default.fileExists(atPath: fixture.testRoot.path))
}

@Test("failed open removes its copied fixture")
func testProjectFailedOpenCleansCopy() throws {
    let scripting = FakeProjectScripting()
    scripting.openError = .dialogPresented
    let fixture = try LifecycleFixture(scripting: scripting)
    defer { fixture.remove() }

    let result = fixture.controller.openFixture(at: fixture.source.path, operationID: "open-1", timeoutMilliseconds: 10)

    #expect(result.status == .failed)
    #expect(result.data.failure == .dialogPresented)
    #expect(result.data.cleanupPerformed)
    #expect(!FileManager.default.fileExists(atPath: fixture.testRoot.appendingPathComponent("copy-1").path))
}

@Test("cleanup clears stale ownership after an already-closed workspace is absent")
func testProjectCleanupReconcilesAbsentWorkspace() throws {
    let scripting = FakeProjectScripting()
    let fixture = try LifecycleFixture(scripting: scripting)
    defer { fixture.remove() }
    let opened = fixture.controller.openFixture(
        at: fixture.source.path,
        operationID: "open-1",
        timeoutMilliseconds: 10
    )
    let managedPath = try #require(opened.data.managedProjectPath)
    let closed = fixture.controller.close(operationID: "close-1", timeoutMilliseconds: 10)
    #expect(closed.status == .succeeded)
    try FileManager.default.removeItem(at: URL(fileURLWithPath: managedPath).deletingLastPathComponent())

    let cleaned = fixture.controller.cleanup(operationID: "cleanup-1", timeoutMilliseconds: 10)

    #expect(cleaned.status == .succeeded)
    #expect(cleaned.data.cleanupPerformed)
    #expect(cleaned.data.managedProjectPath == nil)
    #expect(fixture.controller.observe(operationID: "state-1").data.managedProjectPath == nil)
}

@Test("timed-out open retains its workspace until the delayed document can be closed")
func testTimedOutOpenRetainsWorkspaceUntilReconciled() throws {
    let scripting = FakeProjectScripting()
    scripting.publishOpenIdentity = false
    let fixture = try LifecycleFixture(scripting: scripting)
    defer { fixture.remove() }

    let opened = fixture.controller.openFixture(
        at: fixture.source.path,
        operationID: "open-1",
        timeoutMilliseconds: 0
    )
    let managedPath = try #require(opened.data.managedProjectPath)

    #expect(opened.status == .failed)
    #expect(opened.data.failure == .postconditionFailed)
    #expect(!opened.data.cleanupPerformed)
    #expect(FileManager.default.fileExists(atPath: managedPath))

    let pendingCleanup = fixture.controller.cleanup(
        operationID: "cleanup-pending",
        timeoutMilliseconds: 0
    )
    #expect(pendingCleanup.status == .failed)
    #expect(pendingCleanup.data.failure == .cleanupFailed)
    #expect(FileManager.default.fileExists(atPath: managedPath))

    scripting.replaceCurrent(with: LogicProjectIdentity(
        name: "Fixture.logicx",
        path: managedPath,
        modified: false,
        observedAt: Date(timeIntervalSince1970: 40)
    ))
    let reconciled = fixture.controller.cleanup(
        operationID: "cleanup-reconciled",
        timeoutMilliseconds: 10
    )
    #expect(reconciled.status == .succeeded)
    #expect(reconciled.data.cleanupPerformed)
    #expect(!FileManager.default.fileExists(atPath: managedPath))
}

@Test("managed operations reject an observed project identity change")
func testProjectMutationRejectsIdentityChange() throws {
    let fixture = try LifecycleFixture()
    defer { fixture.remove() }
    _ = fixture.controller.openFixture(at: fixture.source.path, operationID: "open-1", timeoutMilliseconds: 10)
    fixture.scripting.replaceCurrent(with: LogicProjectIdentity(
        name: "User",
        path: "/Users/example/User.logicx",
        modified: false,
        observedAt: Date(timeIntervalSince1970: 1)
    ))

    let save = fixture.controller.save(operationID: "save-1", timeoutMilliseconds: 10)
    let cleanup = fixture.controller.cleanup(operationID: "cleanup-1", timeoutMilliseconds: 10)

    #expect(save.data.failure == .projectIdentityChanged)
    #expect(cleanup.data.failure == .userProjectOpen)
    #expect(fixture.scripting.closeCount == 0)
}
