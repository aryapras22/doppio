#!/bin/bash
# Wraps the Doppio executable in an .app so launch at login (SMAppService) and the bundled font work.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Doppio
APP=build/Doppio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Doppio "$APP/Contents/MacOS/"
cp App/Resources/VT323-Regular.ttf App/Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.arya.doppio</string>
  <key>CFBundleName</key><string>Doppio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Doppio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Doppio selects the iTerm2 tab of the session you click.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
