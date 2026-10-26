#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DMG="${1:?Usage: verify_dmg.sh path/to/Sakura-Cap-VERSION.dmg}"
APP="${2:-build/Sakura-Cap.app}"
PYTHON="${DMG_PYTHON:-$PWD/.build/dmg-tools/bin/python3}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sakura-dmg-test.XXXXXX")"
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
hdiutil verify "$DMG"
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" -quiet
MOUNTED=1
codesign --verify --strict --deep "$MOUNT/Sakura-Cap.app"
cmp "$APP/Contents/Resources/DMGBackground.tiff" "$MOUNT/Sakura-Cap.app/Contents/Resources/DMGBackground.tiff"
cmp Resources/DMG/安装前必看.txt "$MOUNT/安装前必看.txt"
test "$(readlink "$MOUNT/Applications")" = /Applications
"$PYTHON" - "$MOUNT" <<'PY'
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias
volume = Path(sys.argv[1])
with DSStore.open(str(volume / ".DS_Store"), "r") as store:
    assert store["."]["bwsp"]["WindowBounds"] == "{{120, 120}, {780, 480}}"
    assert store["."]["icvp"]["backgroundType"] == 2
    alias = Alias.from_bytes(store["."]["icvp"]["backgroundImageAlias"])
    assert alias.target.filename == "DMGBackground.tiff"
    assert store["Sakura-Cap.app"]["Iloc"] == (88, 155)
    assert store["Applications"]["Iloc"] == (650, 155)
    assert store["安装前必看.txt"]["Iloc"] == (88, 295)
assert sorted(path.name for path in volume.iterdir() if not path.name.startswith(".")) == [
    "Applications", "Sakura-Cap.app", "安装前必看.txt"]
assert not (volume / ".background").exists()
guide = (volume / "安装前必看.txt").read_text()
assert 'xattr -dr com.apple.quarantine "/Applications/Sakura-Cap.app"' in guide
assert "sudo spctl" not in guide
assert "codesign --verify" in guide
print("DMG contents and Finder layout passed: 14 assertions")
PY
hdiutil detach "$MOUNT" -quiet
MOUNTED=0
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    Sources/SakuraCap/Support/UpdatePackage.swift Scripts/verify_update_package.swift \
    -o "$WORK/verify-update-package"
"$WORK/verify-update-package" "$DMG" "$APP"
