import CoreMIDI
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
