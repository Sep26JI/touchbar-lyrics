#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/TouchBarLyrics.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -swift-version 5 -O Sources/*.swift -o "$APP/Contents/MacOS/TouchBarLyrics" -framework Cocoa -framework ServiceManagement
cp Resources/*.py "$APP/Contents/Resources/"
/usr/bin/ditto vendor/media-control "$APP/Contents/Resources/media-control"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.touchbar.lyrics</string>
<key>CFBundleName</key><string>TouchBarLyrics</string>
<key>CFBundleDisplayName</key><string>Touch Bar 歌词</string>
<key>CFBundleExecutable</key><string>TouchBarLyrics</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>4.4</string>
<key>CFBundleVersion</key><string>44</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
