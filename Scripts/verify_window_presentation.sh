#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    Sources/SakuraCap/Platform/WindowPresentation.swift \
    Sources/SakuraCap/Support/ModalAlert.swift \
    Scripts/verify_window_presentation.swift -o "$TEMP_DIR/verify-window-presentation"
"$TEMP_DIR/verify-window-presentation"
