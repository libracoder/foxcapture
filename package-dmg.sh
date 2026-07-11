#!/bin/bash
set -e

cd "$(dirname "$0")"

APP="build/FoxCapture.app"
if [ ! -d "$APP" ]; then
    echo "App not found at $APP — run ./build.sh first." >&2
    exit 1
fi

# Strip any inherited quarantine before signing.
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc sign so the app launches without a "damaged" warning (CI has no
# signing identity).
codesign --force --deep --sign - "$APP"

# Version: explicit env var wins (CI passes the tag); otherwise Info.plist.
if [ -z "${VERSION:-}" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "dev")
fi
DMG="build/FoxCapture-${VERSION}.dmg"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "FoxCapture" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"
rm -rf "$STAGING"

echo "Done! DMG is at $DMG"
