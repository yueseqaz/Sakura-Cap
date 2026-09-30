#!/bin/bash
set -euo pipefail
# 构建并启动 Sakura-Cap。用法：./run.sh [--log]
# 必须以 .app 形态启动（裸二进制没有 Info.plist，TCC/SCK 身份不成立）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/build.sh"
APP="$SCRIPT_DIR/build/Sakura-Cap.app"
echo "==> 启动 $APP"
open "$APP"
if [ "${1:-}" = "--log" ]; then
    echo "==> 实时日志（Ctrl-C 退出）："
    log stream --predicate 'process == "SakuraCap"' --level debug
fi
