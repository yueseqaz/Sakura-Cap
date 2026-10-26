#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Sakura-Cap}"
APP="${1:-build/$APP_NAME.app}"
if [ ! -d "$APP" ]; then
    echo "App not found: $APP. Run ./build.sh first." >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUTPUT="$PWD/build/$APP_NAME-$VERSION.dmg"
TOOLS="$PWD/.build/dmg-tools"
PYTHON="${DMG_PYTHON:-$TOOLS/bin/python3}"
if [ -z "${DMG_PYTHON:-}" ]; then
    if [ ! -x "$PYTHON" ]; then python3 -m venv "$TOOLS"; fi
    "$PYTHON" -m pip install --disable-pip-version-check -r Scripts/dmg-requirements.txt
fi
"$PYTHON" -c 'import ds_store, mac_alias'
codesign --verify --strict "$APP"
if [ ! -f "$APP/Contents/Resources/DMGBackground.tiff" ]; then
    echo "Installer background missing. Rebuild the app with ./build.sh first." >&2
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sakura-dmg.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
MOUNT="$WORK/mount"
MOUNTED=0
mkdir -p "$MOUNT"
cleanup() {
    if [ "$MOUNTED" = 1 ]; then
        if ! hdiutil detach "$MOUNT" -quiet && ! hdiutil detach "$MOUNT" -force -quiet; then
            echo "Could not unmount $MOUNT; preserving $WORK for safe cleanup." >&2
            return
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/stage"
ditto "$APP" "$WORK/stage/$APP_NAME.app"
cp Resources/DMG/安装前必看.txt "$WORK/stage/安装前必看.txt"
ln -s /Applications "$WORK/stage/Applications"

echo "==> Create writable DMG"
hdiutil create -ov -fs HFS+ -format UDRW -volname "$APP_NAME" \
    -srcfolder "$WORK/stage" "$WORK/writable.dmg"
hdiutil attach -readwrite -nobrowse -noautoopen -mountpoint "$MOUNT" "$WORK/writable.dmg"
MOUNTED=1
"$PYTHON" Scripts/dmg_layout.py "$MOUNT" "$APP_NAME"
sync
hdiutil detach "$MOUNT" -quiet
MOUNTED=0

echo "==> Compress DMG"
hdiutil convert "$WORK/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$WORK/final.dmg"
hdiutil verify "$WORK/final.dmg"
mv -f "$WORK/final.dmg" "$OUTPUT"
(cd "$(dirname "$OUTPUT")" && shasum -a 256 "$(basename "$OUTPUT")") > "$OUTPUT.sha256"
echo "==> DMG ready: $OUTPUT"
