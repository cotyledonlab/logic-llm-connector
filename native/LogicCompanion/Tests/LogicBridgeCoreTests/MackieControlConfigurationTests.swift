import Testing

@testable import LogicBridgeCore

@Test("no connector endpoint assignment is missing")
func noConnectorEndpointAssignmentIsMissing() {
    let configuration = MackieControlConfigurationClassifier.classify([
        ControlSurfaceAssignment(
            model: "HUI",
            inputPort: "Other Input",
            outputPort: "Other Output"
        ),
    ])

    #expect(configuration.state == .missing)
    #expect(configuration.assignments.isEmpty)
}

@Test("one Mackie Control owning both connector ports is configured")
func oneMackieControlOwningBothConnectorPortsIsConfigured() {
    let expected = ControlSurfaceAssignment(
        model: "Mackie Control",
        inputPort: "Logic LLM Connector Out",
        outputPort: "Logic LLM Connector In"
    )
    let configuration = MackieControlConfigurationClassifier.classify([
        ControlSurfaceAssignment(
            model: "HUI",
            inputPort: "Other Input",
            outputPort: "Other Output"
        ),
        expected,
    ])

    #expect(configuration.state == .configured)
    #expect(configuration.assignments == [expected])
}

@Test(
    "split duplicate and wrong-model connector assignments are conflicting",
    arguments: [
        [
            ControlSurfaceAssignment(
                model: "Mackie Control",
                inputPort: "Logic LLM Connector Out",
                outputPort: nil
            ),
            ControlSurfaceAssignment(
                model: "Mackie Control",
                inputPort: nil,
                outputPort: "Logic LLM Connector In"
            ),
        ],
        [
            ControlSurfaceAssignment(
                model: "Mackie Control",
                inputPort: "Logic LLM Connector Out",
                outputPort: "Logic LLM Connector In"
            ),
            ControlSurfaceAssignment(
                model: "HUI",
                inputPort: "Logic LLM Connector Out",
                outputPort: nil
            ),
        ],
        [
            ControlSurfaceAssignment(
                model: "HUI",
                inputPort: "Logic LLM Connector Out",
                outputPort: "Logic LLM Connector In"
            ),
        ],
    ]
)
func invalidConnectorAssignmentsAreConflicting(
    _ assignments: [ControlSurfaceAssignment]
) {
    let configuration = MackieControlConfigurationClassifier.classify(assignments)

    #expect(configuration.state == .conflicting)
    #expect(configuration.assignments == assignments)
}
