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
    "${sources[@]}" Scripts/verify_chat_appearance.swift \
    "$TEMP_DIR/libSakuraWebP.a" -o "$TEMP_DIR/verify-chat-appearance"
SAKURA_UI_TEST_COMPLETION="$TEMP_DIR/completed" "$TEMP_DIR/verify-chat-appearance"
test -s "$TEMP_DIR/completed"
