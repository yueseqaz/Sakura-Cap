#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
swift build --product SakuraWebP
BIN_DIR="$(swift build --show-bin-path)"
cp "$BIN_DIR/libSakuraWebP.a" "$TEMP_DIR/libSakuraWebP.a"
sources=()
while IFS= read -r source; do
    sources+=("$source")
done < <(find Sources/SakuraCap -name '*.swift' ! -name main.swift | sort)
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    -framework SwiftUI -I ThirdParty/libwebp/include \
    "${sources[@]}" Scripts/verify_inline_screenshot.swift \
    "$TEMP_DIR/libSakuraWebP.a" -o "$TEMP_DIR/verify-inline-screenshot"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$TEMP_DIR/"
for language in zh-Hans en; do
    preview="${SAKURA_INLINE_PREVIEW_DIR:+$SAKURA_INLINE_PREVIEW_DIR/$language}"
    SAKURA_INLINE_PREVIEW_DIR="$preview" SAKURA_UI_TEST_COMPLETION="$TEMP_DIR/completed-$language" \
        "$TEMP_DIR/verify-inline-screenshot" -AppleLanguages "($language)"
    test -s "$TEMP_DIR/completed-$language"
done
