#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/MenuPup.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MenuPup" "$APP/Contents/MacOS/MenuPup"
# SwiftTerm explicitly probes the app's Contents/Resources when packaged.
cp -R "$(swift build -c release --show-bin-path)/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/"
cp -R "$(swift build -c release --show-bin-path)/MenuPup_MenuPup.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.menupup</string>
<key>CFBundleName</key><string>MenuPup</string>
<key>CFBundleDisplayName</key><string>MenuPup</string>
<key>CFBundleExecutable</key><string>MenuPup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp .build/checkouts/SwiftTerm/LICENSE "$APP/Contents/Resources/SwiftTerm-LICENSE"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
