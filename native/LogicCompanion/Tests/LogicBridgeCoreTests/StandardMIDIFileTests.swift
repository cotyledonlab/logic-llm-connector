import Foundation
import Testing

@testable import LogicBridgeCore

private func note(
    _ id: String,
    pitch: Int,
    onset: Int64,
    duration: Int64,
    velocity: Int,
    channel: Int
) -> MIDINoteIdentity {
    MIDINoteIdentity(
        id: id,
        pitch: pitch,
        onset: MusicalTime(ticks: onset),
        duration: MusicalTime(ticks: duration),
        velocity: velocity,
        channel: channel
    )
}

@Test("four-bar MIDI fixture round-trips pitch, onset, duration, velocity, and channel")
func standardMIDIFourBarRoundTrip() throws {
    let requested = [
        note("kick", pitch: 36, onset: 0, duration: 240, velocity: 127, channel: 10),
        note("chord-c", pitch: 60, onset: 960, duration: 1_920, velocity: 96, channel: 1),
        note("chord-e", pitch: 64, onset: 960, duration: 1_920, velocity: 80, channel: 1),
        note("last", pitch: 72, onset: 14_400, duration: 960, velocity: 48, channel: 2),
    ]
    let data = try StandardMIDIFile.encode(
        name: "Four Bars",
        lengthTicks: 15_360,
        notes: requested
    )
    let decoded = try StandardMIDIFile.decode(data)

    #expect(decoded.name == "Four Bars")
    #expect(decoded.ppq == 960)
    #expect(decoded.lengthTicks == 15_360)
    #expect(decoded.notes.count == requested.count)
    for (actual, expected) in zip(decoded.notes, requested) {
        #expect(actual.pitch == expected.pitch)
        #expect(actual.onset == expected.onset)
        #expect(actual.duration == expected.duration)
        #expect(actual.velocity == expected.velocity)
        #expect(actual.channel == expected.channel)
    }
}

@Test("MIDI import scales exact source divisions to the public 960 PPQ timebase")
func standardMIDIScalesExactPPQ() throws {
    let source = [MIDINoteIdentity(
        id: "source",
        pitch: 60,
        onset: MusicalTime(ticks: 240, ppq: 480),
        duration: MusicalTime(ticks: 480, ppq: 480),
        velocity: 100,
        channel: 16
    )]
    let data = try StandardMIDIFile.encode(name: nil, ppq: 480, lengthTicks: 960, notes: source)
    let decoded = try StandardMIDIFile.decode(data)

    #expect(decoded.lengthTicks == 1_920)
    #expect(decoded.notes.first?.onset == MusicalTime(ticks: 480))
    #expect(decoded.notes.first?.duration == MusicalTime(ticks: 960))
    #expect(decoded.notes.first?.channel == 16)
}

@Test("MIDI codec rejects invalid notes and inexact time scaling")
func standardMIDIRejectsLossyValues() throws {
    let invalid = note("bad", pitch: 128, onset: 0, duration: 1, velocity: 1, channel: 1)
    #expect(throws: StandardMIDIFileError.invalidNote) {
        try StandardMIDIFile.encode(name: nil, lengthTicks: 960, notes: [invalid])
    }

    let oddDivision = try StandardMIDIFile.encode(
        name: nil,
        ppq: 7,
        lengthTicks: 7,
        notes: [MIDINoteIdentity(
            id: "odd",
            pitch: 60,
            onset: MusicalTime(ticks: 1, ppq: 7),
            duration: MusicalTime(ticks: 1, ppq: 7),
            velocity: 64,
            channel: 1
        )]
    )
    #expect(throws: StandardMIDIFileError.inexactTimeScaling) {
        try StandardMIDIFile.decode(oddDivision)
    }
}
