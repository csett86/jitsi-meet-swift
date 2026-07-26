#!/bin/bash
# Assemble the runnable macOS app bundle for the SwiftPM `JitsiApp` executable.
#
# Why a script instead of an Xcode project: everything in this repo builds with
# `swift build`, and the only things a bundle adds are an Info.plist, the
# embedded WebRTC framework, and a signature. Keeping that here means no
# .pbxproj to maintain and no Xcode-only build path.
#
# The Info.plist is load-bearing: without NSCameraUsageDescription /
# NSMicrophoneUsageDescription macOS refuses (and, for an unbundled binary,
# kills) any capture attempt.
#
#   ./Tools/mac-app/make-app.sh [debug|release]   # default: release
#   open build/JitsiMeetSwift.app
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/build/JitsiMeetSwift.app"
BUNDLE_ID="org.jitsi.swift.meet"

cd "$ROOT"
swift build -c "$CONFIG" --product JitsiApp
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp "$BIN_DIR/JitsiApp" "$APP/Contents/MacOS/JitsiApp"
# WebRTC ships as a dynamic framework; the binary looks it up via @rpath.
cp -R "$BIN_DIR/WebRTC.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/JitsiApp" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Jitsi Meet Swift</string>
    <key>CFBundleDisplayName</key>          <string>Jitsi Meet Swift</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>           <string>JitsiApp</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>0.1</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSCameraUsageDescription</key>
    <string>Jitsi Meet Swift sends your camera to the conference you join.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Jitsi Meet Swift sends your microphone to the conference you join.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local runs and for TCC to remember the app's
# camera/microphone decision. Frameworks must be signed before the bundle.
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/WebRTC.framework" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP/Contents/Frameworks/WebRTC.framework"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run:  open '$APP'"
