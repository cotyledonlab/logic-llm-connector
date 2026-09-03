import AppKit
import Foundation
import Testing

@testable import LogicBridgeCore

@Test("Logic 4/4 BBT positions preserve the public 960 PPQ timebase")
func logicBBTPositionConversion() {
    let cases: [(Int64, LogicBBTValue)] = [
        (0, .init(bars: 1, beats: 1, divisions: 1, ticks: 1)),
        (239, .init(bars: 1, beats: 1, divisions: 1, ticks: 240)),
        (240, .init(bars: 1, beats: 1, divisions: 2, ticks: 1)),
        (960, .init(bars: 1, beats: 2, divisions: 1, ticks: 1)),
        (3_840, .init(bars: 2, beats: 1, divisions: 1, ticks: 1)),
        (15_359, .init(bars: 4, beats: 4, divisions: 4, ticks: 240)),
    ]
    for (ticks, expected) in cases {
        let actual = LogicBBTValue.position(from: ticks)
        #expect(actual == expected)
        #expect(actual.positionTicks == ticks)
    }
}

@Test("Logic 4/4 BBT lengths use zero-based duration components")
func logicBBTDurationConversion() {
    #expect(LogicBBTValue.duration(from: 1) == .init(bars: 0, beats: 0, divisions: 0, ticks: 1))
    #expect(LogicBBTValue.duration(from: 960) == .init(bars: 0, beats: 1, divisions: 0, ticks: 0))
    #expect(LogicBBTValue.duration(from: 3_840) == .init(bars: 1, beats: 0, divisions: 0, ticks: 0))
    #expect(LogicBBTValue.duration(from: 15_360) == .init(bars: 4, beats: 0, divisions: 0, ticks: 0))
}

private func activateLogicForMIDIAcceptance(_ logic: NSRunningApplication) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "tell application id \"com.apple.logic10\" to activate"]
    try process.run()
    let processDeadline = Date().addingTimeInterval(5)
    while process.isRunning, Date() < processDeadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning { process.terminate() }

    if NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier {
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-a", "Logic Pro"]
        try launcher.run()
        let launcherDeadline = Date().addingTimeInterval(5)
        while launcher.isRunning, Date() < launcherDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if launcher.isRunning { launcher.terminate() }
    }

    let focusDeadline = Date().addingTimeInterval(5)
    while NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier,
          Date() < focusDeadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

private func reportMIDIAcceptanceStage(_ stage: String, startedAt: Date) {
    let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
    FileHandle.standardError.write(
        Data("MIDI_ACCEPTANCE_STAGE \(stage) elapsed-ms=\(elapsedMilliseconds)\n".utf8)
    )
}

@Test(
    "real Logic MIDI adapter exports exact region note content",
    .enabled(if: ProcessInfo.processInfo.environment["LOGIC_MIDI_ADAPTER_DISCOVERY"] == "1")
)
func realLogicMIDIAdapterExportsNotes() throws {
    let tracks = MacLogicTrackScripting()
    let adapter = MacLogicMIDIRegionScripting(trackScripting: tracks)
    let regions = try adapter.observeRegions()
    #expect(!regions.isEmpty)
    #expect(regions.allSatisfy { !$0.notes.isEmpty })
    for region in regions {
        print("MIDI_ADAPTER region=\(region.name) position=\(region.position.ticks) length=\(region.length.ticks) notes=\(region.notes.map { [String($0.pitch), String($0.onset.ticks), String($0.duration.ticks), String($0.velocity), String($0.channel)].joined(separator: ":") })")
    }
}

@Test(
    "real Logic resolves and confirms a staged MIDI file in the Import panel",
    .enabled(if:
        ProcessInfo.processInfo.environment["LOGIC_MIDI_IMPORT_PANEL_TEST"] == "1" &&
        ProcessInfo.processInfo.environment["LOGIC_MANAGED_TEST_PROJECT_PATH"] != nil
    )
)
func realLogicMIDIImportPanelRoundTrip() throws {
    let managedPath = try #require(ProcessInfo.processInfo.environment["LOGIC_MANAGED_TEST_PROJECT_PATH"])
    let projectScripting = MacLogicProjectScripting()
    let observedProject = try #require(try projectScripting.observe())
    try #require(URL(fileURLWithPath: observedProject.path).standardizedFileURL.path ==
        URL(fileURLWithPath: managedPath).standardizedFileURL.path)

    let logic = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first)
    try activateLogicForMIDIAcceptance(logic)
    try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier == logic.processIdentifier)

    let trackScripting = MacLogicTrackScripting()
    let trackID = try #require(try trackScripting.observeTracks().sorted(by: { $0.position < $1.position }).first?.id)
    let scripting = MacLogicMIDIRegionScripting(trackScripting: trackScripting)
    try scripting.exerciseImportPanelForAcceptance(
        trackID: trackID,
        position: MusicalTime(ticks: 19_200),
        length: MusicalTime(ticks: 3_840),
        notes: [
            MIDINoteContent(
                pitch: 60, onset: MusicalTime(ticks: 0),
                duration: MusicalTime(ticks: 960), velocity: 96, channel: 1
            ),
        ]
    )
}

@Test(
    "real Logic MIDI operations round-trip a deterministic four-bar region",
    .enabled(if:
        ProcessInfo.processInfo.environment["LOGIC_MIDI_INTEGRATION_TEST"] == "1" &&
        ProcessInfo.processInfo.environment["LOGIC_MANAGED_TEST_PROJECT_PATH"] != nil
    )
)
func realLogicMIDIOperationsRoundTripFourBars() throws {
    let acceptanceStartedAt = Date()
    reportMIDIAcceptanceStage("test-started", startedAt: acceptanceStartedAt)
    let managedPath = try #require(ProcessInfo.processInfo.environment["LOGIC_MANAGED_TEST_PROJECT_PATH"])
    let projectScripting = MacLogicProjectScripting()
    let observedProject = try #require(try projectScripting.observe())
    try #require(URL(fileURLWithPath: observedProject.path).standardizedFileURL.path ==
        URL(fileURLWithPath: managedPath).standardizedFileURL.path)
    reportMIDIAcceptanceStage("project-verified", startedAt: acceptanceStartedAt)

    let logic = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first)
    try activateLogicForMIDIAcceptance(logic)
    try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier == logic.processIdentifier)
    reportMIDIAcceptanceStage("logic-focused", startedAt: acceptanceStartedAt)

    let trackScripting = MacLogicTrackScripting()
    let scripting = MacLogicMIDIRegionScripting(trackScripting: trackScripting)
    let controller = MIDIRegionOperationsController(
        scripting: scripting,
        policyContextReady: {
            guard let project = try? projectScripting.observe() else { return false }
            return URL(fileURLWithPath: project.path).standardizedFileURL.path ==
                URL(fileURLWithPath: managedPath).standardizedFileURL.path
        },
        testModeReady: { true }
    )

    reportMIDIAcceptanceStage("initial-observe-began", startedAt: acceptanceStartedAt)
    let initial = controller.observe(operationID: "midi-real-initial")
    reportMIDIAcceptanceStage("initial-observe-returned-\(initial.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(initial.status == .succeeded, Comment(rawValue: String(describing: initial)))
    #expect(initial.data.regions.count == 4)
    #expect(initial.data.regions.map(\.position.ticks) == [0, 3_840, 7_680, 11_520])
    #expect(initial.data.regions.allSatisfy { $0.length.ticks == 3_840 && !$0.notes.isEmpty })
    let trackID = try #require(initial.data.regions.first?.trackID)

    let fixtureNotes = [
        MIDINoteContent(pitch: 36, onset: MusicalTime(ticks: 0), duration: MusicalTime(ticks: 240), velocity: 127, channel: 10),
        MIDINoteContent(pitch: 60, onset: MusicalTime(ticks: 960), duration: MusicalTime(ticks: 1_920), velocity: 96, channel: 1),
        MIDINoteContent(pitch: 64, onset: MusicalTime(ticks: 960), duration: MusicalTime(ticks: 1_920), velocity: 80, channel: 1),
        MIDINoteContent(pitch: 72, onset: MusicalTime(ticks: 14_400), duration: MusicalTime(ticks: 960), velocity: 48, channel: 2),
    ]
    reportMIDIAcceptanceStage("create-began", startedAt: acceptanceStartedAt)
    let created = controller.create(
        trackID: trackID,
        name: "LLM Four Bars",
        position: MusicalTime(ticks: 19_200),
        length: MusicalTime(ticks: 15_360),
        notes: fixtureNotes,
        operationID: "midi-real-create",
        timeoutMilliseconds: 45_000
    )
    reportMIDIAcceptanceStage("create-returned-\(created.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(created.status == .succeeded, Comment(rawValue: String(describing: created)))
    #expect(created.data.fidelityDifferences.isEmpty)
    let regionID = try #require(created.data.targetRegionID)
    let createdRegion = try #require(created.data.regions.first(where: { $0.id == regionID }))
    #expect(createdRegion.notes.map(\.content) == fixtureNotes)

    reportMIDIAcceptanceStage("rename-began", startedAt: acceptanceStartedAt)
    let renamed = controller.rename(
        regionID: regionID, name: "LLM Four Bars Edited",
        operationID: "midi-real-rename", timeoutMilliseconds: 30_000
    )
    reportMIDIAcceptanceStage("rename-returned-\(renamed.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(renamed.status == .succeeded, Comment(rawValue: String(describing: renamed)))

    reportMIDIAcceptanceStage("move-began", startedAt: acceptanceStartedAt)
    let moved = controller.move(
        regionID: regionID, position: MusicalTime(ticks: 23_040),
        operationID: "midi-real-move", timeoutMilliseconds: 30_000
    )
    reportMIDIAcceptanceStage("move-returned-\(moved.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(moved.status == .succeeded, Comment(rawValue: String(describing: moved)))

    reportMIDIAcceptanceStage("resize-began", startedAt: acceptanceStartedAt)
    let resized = controller.resize(
        regionID: regionID, length: MusicalTime(ticks: 16_320),
        operationID: "midi-real-resize", timeoutMilliseconds: 30_000
    )
    reportMIDIAcceptanceStage("resize-returned-\(resized.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(resized.status == .succeeded, Comment(rawValue: String(describing: resized)))

    let firstNote = try #require(resized.data.regions.first(where: { $0.id == regionID })?.notes.first)
    let changedNote = MIDINoteContent(
        pitch: 37, onset: firstNote.onset, duration: firstNote.duration,
        velocity: 111, channel: firstNote.channel
    )
    reportMIDIAcceptanceStage("update-note-began", startedAt: acceptanceStartedAt)
    let updated = controller.updateNote(
        regionID: regionID, noteID: firstNote.id, note: changedNote,
        operationID: "midi-real-update-note", timeoutMilliseconds: 45_000
    )
    reportMIDIAcceptanceStage("update-note-returned-\(updated.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(updated.status == .succeeded, Comment(rawValue: String(describing: updated)))
    #expect(updated.data.regions.first(where: { $0.id == regionID })?.notes.contains(where: { $0.content == changedNote }) == true)

    reportMIDIAcceptanceStage("duplicate-began", startedAt: acceptanceStartedAt)
    let duplicated = controller.duplicate(
        regionID: regionID, position: MusicalTime(ticks: 42_240),
        operationID: "midi-real-duplicate", timeoutMilliseconds: 45_000
    )
    reportMIDIAcceptanceStage("duplicate-returned-\(duplicated.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(duplicated.status == .succeeded, Comment(rawValue: String(describing: duplicated)))
    #expect(duplicated.data.fidelityDifferences.isEmpty)
    let duplicateID = try #require(duplicated.data.targetRegionID)

    reportMIDIAcceptanceStage("split-began", startedAt: acceptanceStartedAt)
    let split = controller.split(
        regionID: duplicateID, position: MusicalTime(ticks: 49_920),
        operationID: "midi-real-split", timeoutMilliseconds: 45_000
    )
    reportMIDIAcceptanceStage("split-returned-\(split.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(split.status == .succeeded, Comment(rawValue: String(describing: split)))
    #expect(!split.data.createdRegionIDs.isEmpty)

    reportMIDIAcceptanceStage("playback-began", startedAt: acceptanceStartedAt)
    let playback = controller.verifyPlayback(
        regionID: regionID, operationID: "midi-real-playback", timeoutMilliseconds: 5_000
    )
    reportMIDIAcceptanceStage("playback-returned-\(playback.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(playback.status == .succeeded, Comment(rawValue: String(describing: playback)))
    #expect(playback.data.playbackVerified)

    reportMIDIAcceptanceStage("delete-began", startedAt: acceptanceStartedAt)
    let deleted = controller.delete(
        regionID: regionID, confirmed: true,
        operationID: "midi-real-delete", timeoutMilliseconds: 30_000
    )
    reportMIDIAcceptanceStage("delete-returned-\(deleted.status.rawValue)", startedAt: acceptanceStartedAt)
    try #require(deleted.status == .succeeded, Comment(rawValue: String(describing: deleted)))
    #expect(deleted.data.undoAvailable)
    #expect(!deleted.data.regions.contains(where: { $0.id == regionID }))
    #expect(!logic.isTerminated)
    reportMIDIAcceptanceStage("test-passed", startedAt: acceptanceStartedAt)
}
