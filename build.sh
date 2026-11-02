#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
DEST="$ROOT/outputs/SetTop Remote.app"
mkdir -p "$DEST/Contents/MacOS"

clang++ -std=c++17 -fobjc-arc -O2 -Wall -Wextra \
  -framework Cocoa -framework QuartzCore \
  "$ROOT/src/SetTopRemote.mm" -o "$DEST/Contents/MacOS/SetTopRemote"

cat > "$DEST/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SetTopRemote</string>
  <key>CFBundleIdentifier</key><string>app.settop.remote</string>
  <key>CFBundleName</key><string>SetTop Remote</string>
  <key>CFBundleDisplayName</key><string>SetTop Remote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Find Android TVs and Google TVs on your local Wi-Fi network.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_googlecast._tcp</string>
    <string>_androidtvremote2._tcp</string>
    <string>_adb-tls-connect._tcp</string>
    <string>_adb-tls-pairing._tcp</string>
    <string>_adb._tcp</string>
  </array>
</dict></plist>
EOF

codesign --force --sign - "$DEST"
echo "Built: $DEST"
ls -lh "$DEST/Contents/MacOS/SetTopRemote"
