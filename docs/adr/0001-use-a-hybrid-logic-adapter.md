# Use a hybrid Logic adapter

Logic Pro exposes no comprehensive public project object model, so the
connector will place one semantic operation interface over CoreMIDI control
surfaces, Accessibility and key commands, Apple Events, and supported file
interchange. A single adapter cannot provide the required breadth, while this
hybrid keeps adapter choice and recovery logic out of MCP callers.
