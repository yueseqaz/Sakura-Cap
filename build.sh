#!/bin/bash
set -euo pipefail

# ============================================================
# Sakura-Cap 一键构建：swift build → 组装 .app → codesign
# 可用环境变量覆盖：APP_NAME / BUILD_DIR / BUNDLE_ID / VERSION / SIGN_IDENTITY
#   SIGN_IDENTITY=-       强制 ad-hoc 签名（每次重编译后 TCC 权限可能失效）
#   SIGN_IDENTITY=auto    默认：自动查找名字含 sakura-cap 的本地证书，找不到退回 ad-hoc
#   SIGN_IDENTITY="名称"  使用指定证书（推荐本地自签代码签名证书）
# ============================================================

APP_NAME="${APP_NAME:-Sakura-Cap}"
BUNDLE_ID="${BUNDLE_ID:-com.sakura.sakuracap}"
EXECUTABLE="SakuraCap"
BUILD_NUMBER="1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 版本默认跟随 Cask 的已发布版本（本地构建不再停留在 2.0.0），仍可用 VERSION 环境变量覆盖；
# 发版流水线传入的 VERSION（来自 tag）优先级最高
if [ -z "${VERSION:-}" ]; then
    VERSION="$(sed -nE 's/^  version "([^"]+)"/\1/p' Casks/sakura-cap.rb | head -1)"
fi
VERSION="${VERSION:-2.0.0}"

BUILD_DIR="${BUILD_DIR:-build}"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> swift build -c release"
swift build -c release

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

# Info.plist：由模板替换占位符生成（改名只需改这里的环境变量）
sed -e "s/@APP_NAME@/$APP_NAME/g" \
    -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" \
    -e "s/@EXECUTABLE@/$EXECUTABLE/g" \
    -e "s/@VERSION@/$VERSION/g" \
    -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/g" \
    Config/Info.plist.template > "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

# ---- 图标：优先使用 Resources/AppIcon.png；否则用脚本绘制默认图标 ----
ICON_PNG="Resources/AppIcon.png"
if [ ! -f "$ICON_PNG" ]; then
    echo "==> 未找到 Resources/AppIcon.png，绘制默认图标"
    mkdir -p Resources
    swift Scripts/make_default_icon.swift "$ICON_PNG"
fi

echo "==> 生成 icns"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET" "$CONTENTS/Resources/AppIcon.icns"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

# ---- 本地化资源（*.lproj/Localizable.strings）----
find Resources -maxdepth 1 -name '*.lproj' -exec cp -R {} "$CONTENTS/Resources/" \;

# Keep installer art inside the signed bundle: the DMG then has only three items,
# even when Finder is configured to show hidden files. TIFF DPI sets display size
# to 770 x 421.4 points without cropping or resampling the original 1100 x 602 pixels.
sips -s format tiff -s formatOptions lzw \
    -s dpiWidth 102.857142857 -s dpiHeight 102.857142857 \
    Resources/DMG/background.png --out "$CONTENTS/Resources/DMGBackground.tiff" >/dev/null

# WebP 静态链接进主程序，随包保留上游版权与专利授权声明。
mkdir -p "$CONTENTS/Resources/ThirdParty/libwebp"
cp ThirdParty/libwebp/{COPYING,PATENTS,AUTHORS} "$CONTENTS/Resources/ThirdParty/libwebp/"

# ---- 签名 ----
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"
if [ "$SIGN_IDENTITY" = "auto" ]; then
    FOUND="$(security find-identity -v -p codesigning 2>/dev/null | grep -i 'sakura-cap' | head -1 | sed -E 's/^\s*[0-9A-F]{40}\s+"(.*)"$/\1/' || true)"
    if [ -n "${FOUND}" ]; then
        SIGN_IDENTITY="$FOUND"
    else
        SIGN_IDENTITY="-"
    fi
fi
echo "==> codesign（identity: ${SIGN_IDENTITY}）"
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements Config/SakuraCap.entitlements \
    --timestamp=none \
    "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "==> 构建完成: $SCRIPT_DIR/$APP_DIR"
echo "    提示：ad-hoc 签名在每次重编译后 TCC 权限可能失效，重置命令："
echo "      tccutil reset ScreenCapture $BUNDLE_ID"
echo "      tccutil reset Microphone    $BUNDLE_ID"
echo "      tccutil reset ListenEvent   $BUNDLE_ID"
