#!/bin/bash
# Builds ChordChart.app (the web app + Apple Vision text recognition) - macOS 13+, Xcode command line tools.
set -e
cd "$(dirname "$0")"
APP="ChordChart.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macos13.0" ChordChartMac.swift -o "$APP/Contents/MacOS/ChordChart"

# the web app itself
cp ../index.html ../manifest.json ../sw.js ../icon-192.png ../icon-512.png "$APP/Contents/Resources/web/"
cp -R ../vendor "$APP/Contents/Resources/web/vendor"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ChordChart</string>
  <key>CFBundleDisplayName</key><string>コード譜</string>
  <key>CFBundleIdentifier</key><string>local.chordchart.mac</string>
  <key>CFBundleExecutable</key><string>ChordChart</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $(pwd)/$APP"
echo "open it with:  open \"$(pwd)/$APP\""
