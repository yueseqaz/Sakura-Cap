#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    Sources/SakuraCap/Support/ImageStitching.swift \
    Sources/SakuraCap/Platform/WindowPresentation.swift \
    Sources/SakuraCap/UI/ImageStitchWindow.swift \
    Scripts/verify_image_stitch.swift -o "$TEMP_DIR/verify-image-stitch"
for language in zh en; do
    completion="$TEMP_DIR/completed-$language"
    SAKURA_TEST_LANGUAGE="$language" SAKURA_TEST_COMPLETION_FILE="$completion" "$TEMP_DIR/verify-image-stitch"
    test -s "$completion" || { echo "Stitch checks exited without completing ($language)" >&2; exit 1; }
done
