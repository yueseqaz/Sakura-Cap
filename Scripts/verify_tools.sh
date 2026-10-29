#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
swift build --product SakuraWebP
BIN_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -framework SwiftUI -I ThirdParty/libwebp/include \
    Sources/SakuraCap/Platform/WindowPresentation.swift \
    Sources/SakuraCap/UI/ImageConvertWindow.swift \
    Sources/SakuraCap/UI/ColorPickerOverlay.swift \
    Sources/SakuraCap/Support/ImageConversion.swift \
    Sources/SakuraCap/Platform/ScreenCoordinateKit.swift \
    Sources/SakuraCap/Platform/PermissionCenter.swift \
    Sources/SakuraCap/Support/Logger.swift \
    Scripts/verify_tools.swift "$BIN_DIR/libSakuraWebP.a" -o "$TEMP_DIR/verify-tools"
for language in zh en; do
    completion="$TEMP_DIR/completed-$language"
    SAKURA_TEST_LANGUAGE="$language" SAKURA_TEST_COMPLETION_FILE="$completion" "$TEMP_DIR/verify-tools"
    test -s "$completion" || { echo "Regression checks exited without completing ($language)" >&2; exit 1; }
done
