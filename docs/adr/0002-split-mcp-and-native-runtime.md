# Split MCP and native runtime

TypeScript owns the public MCP interface because the official TypeScript SDK is
the stable Tier-1 implementation, while Swift owns the Companion because it can
directly use macOS Accessibility, CoreMIDI, AppKit, and Apple Events. The two
participants communicate through a small versioned JSON-RPC interface over a
permission-restricted Unix socket, accepting an extra process seam in exchange
for protocol currency and native integration quality.
