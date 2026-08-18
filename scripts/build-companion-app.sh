#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_path="$repo_root/native/LogicCompanion"
app_path="$repo_root/build/Logic Companion.app"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/logic-companion-app.XXXXXX")
temporary_app="$temporary_root/Logic Companion.app"
signing_identity=${LOGIC_COMPANION_SIGNING_IDENTITY:-"Apple Development: jm547ster@gmail.com (ZMR8R9BPJK)"}

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

swift build --package-path "$package_path"
mkdir -p "$temporary_app/Contents/MacOS"
install -m 0755 \
  "$package_path/.build/debug/logic-companion" \
  "$temporary_app/Contents/MacOS/logic-companion"
install -m 0644 \
  "$package_path/Resources/Info.plist" \
  "$temporary_app/Contents/Info.plist"

codesign --force --sign "$signing_identity" \
  --identifier dev.cotyledonlab.logic-llm-connector.companion \
  --options runtime \
  --timestamp=none \
  "$temporary_app"

mkdir -p "$repo_root/build"
rm -rf "$app_path"
mv "$temporary_app" "$app_path"
