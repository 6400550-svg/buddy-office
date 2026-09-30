#!/bin/bash
# AddressSanitizer 下跑「碰得到原始指针 / 画布」的测试（QA ②：越界 / 释放后使用）：BuddyStageTests（画布的 clip / blit / crop / 文字审计 / 极端值）
# 和 BuddyOfficeTests（PixelView / IOSurface 写入 / 提示卡 / 设置的极端值）。
#   QA/tools/asan_tests.sh [输出目录，默认 QA/evidence/asan-tests]      要在沙箱外跑；会自己编一份带 ASan 的 debug 构建（.build-asan-t）
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT" || exit 1
OUT="${1:-$ROOT/QA/evidence/asan-tests}"; mkdir -p "$OUT"; SUM="$OUT/summary.txt"; : > "$SUM"
say() { echo "$*" | tee -a "$SUM"; }
CLT=/Library/Developer/CommandLineTools; FW=$CLT/Library/Developer/Frameworks
TESTFLAGS="-Xswiftc -F$FW -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib"
say "# ASan 测试 $(date '+%Y-%m-%d %H:%M')"
t0=$(date +%s)
export ASAN_OPTIONS="detect_leaks=0:halt_on_error=1"
swift test --sanitize=address --scratch-path .build-asan-t $TESTFLAGS --filter "BuddyStageTests|BuddyOfficeTests" > "$OUT/tests.log" 2>&1; rc=$?
errs=$(grep -c "ERROR: AddressSanitizer" "$OUT/tests.log")
say "退出码 $rc；ASan 报错 $errs 处；$(( $(date +%s) - t0 )) 秒；$(grep -E '^(✔|✘) Test run with' "$OUT/tests.log" | tail -1)"
grep -B2 -A14 "ERROR: AddressSanitizer" "$OUT/tests.log" | head -80 > "$OUT/errors-head.txt"
say "# 完成 $(date '+%H:%M')"
