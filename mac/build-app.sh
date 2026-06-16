#!/usr/bin/env bash
# Builds FineClipboard.app (and a zip) from the SwiftPM executable.
#   ./build-app.sh [version]
# Set UNIVERSAL=1 to build a universal (arm64 + x86_64) binary.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-0.10.0}"
APP="dist/FineClipboard.app"
BUNDLE_ID="com.cassian.fineclipboard"

if [ "${UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/FineClipboard"
else
  swift build -c release
  BIN=".build/release/FineClipboard"
fi

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FineClipboard"
chmod +x "$APP/Contents/MacOS/FineClipboard"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FineClipboard</string>
    <key>CFBundleDisplayName</key><string>FineClipboard</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>FineClipboard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>FineClipboard</string>
    <key>NSAppleEventsUsageDescription</key><string>FineClipboard 通过模拟 Cmd+V 把所选内容粘贴到当前应用。</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the app has a stable identity (needed for the Accessibility grant to stick).
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: ad-hoc codesign skipped"

# Zip for distribution (preserves the bundle + symlinks).
( cd dist && ditto -c -k --sequesterRsrc --keepParent "FineClipboard.app" "FineClipboard-${VERSION}-mac.zip" )

echo "Built $APP  +  dist/FineClipboard-${VERSION}-mac.zip  (version ${VERSION})"
