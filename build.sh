#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="HZLAPaste.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/HZLAPaste" "$APP/Contents/MacOS/HZLAPaste"
cp "Sources/HZLAPaste/Info.plist" "$APP/Contents/Info.plist"
cp "Sources/HZLAPaste/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable local identity (not ad-hoc "-") so TCC grants like
# Accessibility survive rebuilds instead of resetting every time.
SIGNING_IDENTITY="HZLAPaste Local Dev"
if security find-identity -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    codesign --force --sign "$SIGNING_IDENTITY" "$APP"
else
    echo "warning: signing identity '$SIGNING_IDENTITY' not found, falling back to ad-hoc signing" >&2
    codesign --force --sign - "$APP"
fi

echo "Built $APP — drag it to /Applications, then launch it (or: open $APP)."
