#!/bin/bash
set -euo pipefail
# ============================================================
# 录像文件质量自检：用 ffprobe 输出分辨率、码率、pix_fmt、
# color_space / color_transfer / color_primaries，并检查非 unknown
# 依赖：ffprobe（brew install ffmpeg）
# 用法：./verify.sh <录像.mp4>
# ============================================================

FILE="${1:-}"
if [ -z "$FILE" ]; then
    # 不带参数时自动检查输出目录里最新的录像
    DIR="$(defaults read com.sakura.sakuracap outputDirectory 2>/dev/null || true)"
    if [ -n "$DIR" ] && ls "$DIR"/SakuraCap*.mp4 >/dev/null 2>&1; then
        FILE="$(ls -t "$DIR"/SakuraCap*.mp4 | head -1)"
    else
        echo "用法: ./verify.sh <录像.mp4>"; exit 1
    fi
fi
echo "检查文件: $FILE"

command -v ffprobe >/dev/null 2>&1 || {
    echo "❌ 未安装 ffprobe，请先: brew install ffmpeg"; exit 1
}

echo "== 流信息 =="
ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,avg_frame_rate,bit_rate,pix_fmt,color_space,color_transfer,color_primaries \
    -of default=noprint_wrappers=1 "$FILE"

echo "== 容器码率（含音频） =="
ffprobe -v error -show_entries format=bit_rate,duration -of default=noprint_wrappers=1 "$FILE"

echo "== 色彩标注检查 =="
UNKNOWN=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=color_space,color_transfer,color_primaries \
    -of csv=p=0 "$FILE" | grep -ci "unknown" || true)
if [ "$UNKNOWN" -eq 0 ]; then
    echo "✅ color_space / color_transfer / color_primaries 均已标注（BT.709）"
else
    echo "⚠️ 存在 unknown 色彩字段：播放器会自行猜测矩阵/范围，可能发灰——检查 AVVideoColorPropertiesKey 是否生效"
fi

echo ""
echo "判读提示："
echo "  · pix_fmt 应为 yuv420p（H.264）/ yuv420p10le（HEVC 默认）"
echo "  · bit_rate 应接近设置档位（高: ~0.15bpp × 像素 × 帧率）"
echo "  · 三个色彩字段应为 bt709 / bt709 / bt709（ smpte170m 等则说明标注丢失）"
