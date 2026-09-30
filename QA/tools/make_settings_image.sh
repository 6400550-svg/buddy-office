#!/bin/bash
# 设置窗口 4 页 × 浅色 / 深色，渲染成 PNG（BuddyOffice 的 --dump-settings，不需要屏幕录制权限）再拼成一张 QA/img/settings-light-dark.png。
#   QA/tools/make_settings_image.sh <BuddyOffice 可执行文件> [输出.png]      （要在沙箱外跑：会起一个 GUI 进程；用演示数据，不碰真实的 ~/.claude）
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$ROOT/.build/release/BuddyOffice}"; OUT="${2:-$ROOT/QA/img/settings-light-dark.png}"
[ -x "$BIN" ] || { echo "找不到 $BIN"; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/settings-img.XXXXXX")"
APP="$TMP/settings-dump.app"
BUDDY_BUNDLE_ID=local.buddy-office.dev.settings-dump "$ROOT/scripts/dev-app.sh" "$BIN" "$APP" > /dev/null 2>&1
"$APP/Contents/MacOS/BuddyOffice" --demo --no-windows --no-persist --dump-settings "$TMP/s" > "$TMP/run.log" 2>&1 &
PID=$!
for _ in $(seq 1 60); do [ -f "$TMP/s-dark-3.png" ] && break; kill -0 $PID 2>/dev/null || break; sleep 1; done
sleep 1; kill $PID 2>/dev/null; wait $PID 2>/dev/null
defaults delete local.buddy-office.dev.settings-dump > /dev/null 2>&1
ARGS=()
i=0; for mode in light dark; do for tab in 0 1 2 3; do
  names=(形态 提醒 其他 数据源诊断); name="${names[$tab]}"
  f="$TMP/s-$mode-$tab.png"; [ -f "$f" ] || { echo "缺 $f"; continue; }
  ARGS+=("$( [ $mode = light ] && echo 浅色 || echo 深色 )｜第 $((tab + 1)) 页 $name" "$f")
done; done
mkdir -p "$(dirname "$OUT")"
swift "$ROOT/QA/tools/compose_grid.swift" "$OUT" "设置窗口 4 页 × 浅色 / 深色（开发副本、演示数据）" 4 420 "${ARGS[@]}"
echo "已写 $OUT"; rm -rf "$TMP"
