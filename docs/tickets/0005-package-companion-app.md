# 0005 — Package the signed Companion app

Status: Complete
Depends on: 0004

## Outcome

The native executable is packaged as a macOS app with a stable bundle identity
that can retain Accessibility and Apple Events permissions.

## Scope

- Reproducible local app-bundle build
- Stable bundle identifier and version metadata
- Code-signing strategy suitable for development
- Default private socket location
- Minimal lifecycle suitable for later status and emergency-stop UI

## Acceptance criteria

- Package test verifies bundle metadata and signature identity.
- Doctor integration runs through the packaged executable.
- Rebuilding does not change the bundle identifier or install path.
- Build output is ignored by git.
- Installation and launch instructions are documented.
