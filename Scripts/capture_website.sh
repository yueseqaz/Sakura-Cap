#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build/website-capture"
APP="$BUILD/Sakura-Cap Website.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/media"
swift build --product SakuraWebP
BIN_DIR="$(swift build --show-bin-path)"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files Sources/SakuraCap -g '*.swift' -g '!main.swift' | sort)
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    -framework SwiftUI -I ThirdParty/libwebp/include \
    "${sources[@]}" Scripts/capture_website.swift "$BIN_DIR/libSakuraWebP.a" \
    -o "$APP/Contents/MacOS/WebsiteCapture"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.sakura.sakuracap.websitecapture</string>
<key>CFBundleName</key><string>Sakura-Cap Website</string>
<key>CFBundleExecutable</key><string>WebsiteCapture</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Capture app: $APP"
echo "Scenes: Command-1 inline, 2 editor, 3 stitching, 4 video, 5 conversion, 6 recording HUD."
echo "Scenes automatically export their native views after layout. Command-Shift-P saves again."
echo "Only this process's views and your desktop wallpaper are read. Command-Q quits."
echo "Images: $ROOT/docs/assets/screenshots"
if [[ "${1:-}" != "--build-only" ]]; then
    "$APP/Contents/MacOS/WebsiteCapture" "$ROOT" -AppleLanguages '(zh-Hans)'
fi
