import CoreMIDI
import Darwin
import Foundation
import Testing

@testable import LogicBridgeCore

@Test("virtual MIDI endpoint identity remains stable")
func virtualMIDIEndpointIdentityRemainsStable() {
    #expect(VirtualMIDIEndpointIdentity.clientName == "Logic LLM Connector")
    #expect(VirtualMIDIEndpointIdentity.manufacturer == "Cotyledon Lab")
    #expect(VirtualMIDIEndpointIdentity.model == "Logic LLM Connector Control")
    #expect(VirtualMIDIEndpointIdentity.protocolID == ._1_0)
    #expect(VirtualMIDIEndpointIdentity.source.name == "Logic LLM Connector Out")
    #expect(VirtualMIDIEndpointIdentity.source.uniqueID == 0x4C4C_4D01)
    #expect(VirtualMIDIEndpointIdentity.destination.name == "Logic LLM Connector In")
    #expect(VirtualMIDIEndpointIdentity.destination.uniqueID == 0x4C4C_4D02)
}

@Suite("Virtual MIDI endpoint owner", .serialized)
struct VirtualMIDIEndpointOwnerTests {
    @Test("virtual MIDI endpoints are discoverable with stable metadata")
    func endpointsAreDiscoverableWithStableMetadata() throws {
        let owner = try VirtualMIDIEndpointOwner()

        let snapshot = owner.snapshot
        #expect(snapshot.sourceAvailable)
        #expect(snapshot.destinationAvailable)
        #expect(snapshot.protocolID == ._1_0)

        let source = try #require(findMIDIObject(uniqueID: VirtualMIDIEndpointIdentity.source.uniqueID))
        #expect(source.type == .source)
        #expect(try midiStringProperty(source.reference, kMIDIPropertyName) == "Logic LLM Connector Out")
        #expect(try midiStringProperty(source.reference, kMIDIPropertyManufacturer) == "Cotyledon Lab")
        #expect(try midiStringProperty(source.reference, kMIDIPropertyModel) == "Logic LLM Connector Control")

        let destination = try #require(findMIDIObject(uniqueID: VirtualMIDIEndpointIdentity.destination.uniqueID))
        #expect(destination.type == .destination)
        #expect(try midiStringProperty(destination.reference, kMIDIPropertyName) == "Logic LLM Connector In")
        #expect(try midiStringProperty(destination.reference, kMIDIPropertyManufacturer) == "Cotyledon Lab")
        #expect(try midiStringProperty(destination.reference, kMIDIPropertyModel) == "Logic LLM Connector Control")
    }

    @Test("timestamped MIDI messages loop through both endpoints without callback work")
    func timestampedMessagesLoopThroughBothEndpoints() throws {
        let destinationMessages = LockedMessages()
        let destinationReceived = DispatchSemaphore(value: 0)
        let callbackQueue = DispatchQueue(label: "dev.cotyledonlab.logic-midi-test-receive")
        let queueMarker = QueueMarker()
        callbackQueue.setSpecific(key: queueMarker.key, value: true)
        let owner = try VirtualMIDIEndpointOwner(receiveQueue: callbackQueue) { messages in
            queueMarker.wasObserved.set(DispatchQueue.getSpecific(key: queueMarker.key) == true)
            destinationMessages.append(contentsOf: messages)
            destinationReceived.signal()
        }

        var client = MIDIClientRef()
        #expect(MIDIClientCreateWithBlock("Logic MIDI Loopback Test" as CFString, &client, { _ in }) == noErr)
        defer { MIDIClientDispose(client) }

        let sourceMessages = LockedMessages()
        let sourceReceived = DispatchSemaphore(value: 0)
        var input = MIDIPortRef()
        #expect(MIDIInputPortCreateWithProtocol(
            client,
            "Loopback Input" as CFString,
            ._1_0,
            &input
        ) { eventList, _ in
            sourceMessages.append(contentsOf: copyMessages(from: eventList))
            sourceReceived.signal()
        } == noErr)

        var output = MIDIPortRef()
        #expect(MIDIOutputPortCreate(client, "Loopback Output" as CFString, &output) == noErr)

        let source = try #require(findMIDIObject(uniqueID: VirtualMIDIEndpointIdentity.source.uniqueID))
        let destination = try #require(findMIDIObject(uniqueID: VirtualMIDIEndpointIdentity.destination.uniqueID))
        #expect(MIDIPortConnectSource(input, MIDIEndpointRef(source.reference), nil) == noErr)

        let outgoing = MIDIMessage(timestamp: mach_absolute_time(), words: [0x2090_3C64])
        try owner.send(outgoing)
        #expect(sourceReceived.wait(timeout: .now() + 2) == .success)
        #expect(sourceMessages.values == [outgoing])

        let incoming = MIDIMessage(timestamp: mach_absolute_time(), words: [0x2080_3C00])
        let sendStatus = withEventList(incoming) { eventList in
            MIDISendEventList(output, MIDIEndpointRef(destination.reference), eventList)
        }
        #expect(sendStatus == noErr)
        #expect(destinationReceived.wait(timeout: .now() + 2) == .success)
        #expect(destinationMessages.values == [incoming])
        #expect(queueMarker.wasObserved.value)
    }
}

private func findMIDIObject(uniqueID: MIDIUniqueID) -> (reference: MIDIObjectRef, type: MIDIObjectType)? {
    var reference = MIDIObjectRef()
    var type = MIDIObjectType.other
    guard MIDIObjectFindByUniqueID(uniqueID, &reference, &type) == noErr else { return nil }
    return (reference, type)
}

private func midiStringProperty(_ object: MIDIObjectRef, _ property: CFString) throws -> String {
    var value: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(object, property, &value)
    guard status == noErr, let value else { throw MIDIEndpointTestError.property(status) }
    return value.takeRetainedValue() as String
}

private enum MIDIEndpointTestError: Error {
    case property(OSStatus)
}

private final class LockedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MIDIMessage] = []

    var values: [MIDIMessage] {
        lock.withLock { storage }
    }

    func append(contentsOf messages: [MIDIMessage]) {
        lock.withLock { storage.append(contentsOf: messages) }
    }
}

private final class QueueMarker: @unchecked Sendable {
    let key = DispatchSpecificKey<Bool>()
    let wasObserved = LockedValue(false)
}

private final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }
}

private func withEventList<Result>(
    _ message: MIDIMessage,
    body: (UnsafePointer<MIDIEventList>) -> Result
) -> Result {
    var eventList = MIDIEventList()
    return withUnsafeMutablePointer(to: &eventList) { eventListPointer in
        let packet = MIDIEventListInit(eventListPointer, ._1_0)
        message.words.withUnsafeBufferPointer { words in
            _ = MIDIEventListAdd(
                eventListPointer,
                MemoryLayout<MIDIEventList>.size,
                packet,
                message.timestamp,
                words.count,
                words.baseAddress!
            )
        }
        return body(UnsafePointer(eventListPointer))
    }
}

private func copyMessages(from eventList: UnsafePointer<MIDIEventList>) -> [MIDIMessage] {
    var messages: [MIDIMessage] = []
    var packet = withUnsafePointer(to: eventList.pointee.packet) {
        UnsafeRawPointer($0).assumingMemoryBound(to: MIDIEventPacket.self)
    }
    for _ in 0..<eventList.pointee.numPackets {
        let words = withUnsafePointer(to: packet.pointee.words) {
            Array(UnsafeBufferPointer(
                start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt32.self),
                count: Int(packet.pointee.wordCount)
            ))
        }
        messages.append(MIDIMessage(timestamp: packet.pointee.timeStamp, words: words))
        packet = UnsafePointer(MIDIEventPacketNext(packet))
    }
    return messages
}
