import Testing

@testable import LogicBridgeCore

@Test("setup parser extracts the smallest relevant assignment groups")
func setupParserExtractsRelevantAssignmentGroups() throws {
    let tree = ControlSurfaceUIElement(strings: ["Control Surface Setup"], children: [
        ControlSurfaceUIElement(strings: ["Device", "Mackie Control"], children: [
            ControlSurfaceUIElement(strings: ["Input Port", "Logic LLM Connector Out"]),
            ControlSurfaceUIElement(strings: ["Output Port", "Logic LLM Connector In"]),
        ]),
        ControlSurfaceUIElement(strings: ["Device", "HUI"], children: [
            ControlSurfaceUIElement(strings: ["Input Port", "Other Input"]),
            ControlSurfaceUIElement(strings: ["Output Port", "Other Output"]),
        ]),
    ])

    let assignments = try #require(ControlSurfaceSetupParser.assignments(in: tree))
    #expect(assignments == [
        ControlSurfaceAssignment(
            model: "Mackie Control",
            inputPort: "Logic LLM Connector Out",
            outputPort: "Logic LLM Connector In"
        ),
    ])
}

@Test("setup parser preserves split assignments for conflict classification")
func setupParserPreservesSplitAssignments() throws {
    let tree = ControlSurfaceUIElement(strings: ["Control Surface Setup"], children: [
        ControlSurfaceUIElement(strings: ["Mackie Control", "Logic LLM Connector Out"]),
        ControlSurfaceUIElement(strings: ["Mackie Control", "Logic LLM Connector In"]),
    ])

    let assignments = try #require(ControlSurfaceSetupParser.assignments(in: tree))
    #expect(MackieControlConfigurationClassifier.classify(assignments).state == .conflicting)
}

@Test("empty setup trees are unreadable and unrelated surfaces are missing")
func emptyAndUnrelatedSetupTreesRemainDistinct() throws {
    #expect(ControlSurfaceSetupParser.assignments(
        in: ControlSurfaceUIElement(strings: [])
    ) == nil)
    let unrelated = try #require(ControlSurfaceSetupParser.assignments(
        in: ControlSurfaceUIElement(strings: ["HUI", "Other Input", "Other Output"])
    ))
    #expect(MackieControlConfigurationClassifier.classify(unrelated).state == .missing)
}
