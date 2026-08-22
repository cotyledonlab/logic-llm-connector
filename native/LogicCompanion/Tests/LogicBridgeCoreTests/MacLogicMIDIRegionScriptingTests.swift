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
