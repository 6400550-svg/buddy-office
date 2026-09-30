#!/bin/bash
# AddressSanitizer 下把像素引擎 / 表现层的全部「压力矩阵」跑一遍（QA ②：越界 / 释放后使用 / 溢出类问题）：
#   text-audit 全矩阵（8000+ 个组合，每个都要出图、量文字）、局部重绘 vs 整张重画、金图、闪烁扫描。
# 要先编出带 ASan 的 buddyctl：swift build -c release --sanitize=address --scratch-path .build-asan --product buddyctl
#   QA/tools/asan_run.sh [buddyctl 路径，默认 .build-asan/release/buddyctl] [输出目录，默认 QA/evidence/asan]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT" || exit 1
BIN="${1:-$ROOT/.build-asan/release/buddyctl}"; OUT="${2:-$ROOT/QA/evidence/asan}"
mkdir -p "$OUT"; SUM="$OUT/summary.txt"; : > "$SUM"
say() { echo "$*" | tee -a "$SUM"; }
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:halt_on_error=1"
say "# ASan 运行 $(date '+%Y-%m-%d %H:%M')  $BIN"
nm "$BIN" 2>/dev/null | grep -q "__asan_init" && say "确认：这个 buddyctl 带 AddressSanitizer（有 __asan_init 符号）" || say "警告：没找到 __asan_init 符号，这个 buddyctl 可能没带 ASan"
run() {   # 名字 命令…
  local name="$1"; shift
  local t0=$(date +%s)
  "$@" > "$OUT/$name.log" 2>&1; local rc=$?
  local errs; errs=$(grep -c "ERROR: AddressSanitizer" "$OUT/$name.log")
  say "$name：退出码 $rc，ASan 报错 $errs 处，$(( $(date +%s) - t0 )) 秒；$(tail -1 "$OUT/$name.log" | cut -c1-200)"
}
run golden          "$BIN" golden
run verify-office   "$BIN" verify --scene office --seconds 60 --modes demo,busy6,idle6,crowd12 --hover
run verify-tank     "$BIN" verify --scene tank   --seconds 60 --modes demo,busy6,idle6,crowd12 --hover
run verify-strip    "$BIN" verify --scene strip  --seconds 60 --modes demo,busy6,idle6,crowd12 --hover
for sc in office tank strip; do run flicker-$sc "$BIN" flicker --scene $sc --zoom 3 --from 0 --to 79.9; done
run text-audit      "$BIN" text-audit --max 0
say "# 完成 $(date '+%H:%M')"
