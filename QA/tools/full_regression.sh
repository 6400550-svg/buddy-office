#!/bin/bash
# 最后一次完整回归（QA ⑦ 要报的数字）：干净编译 debug / release（数警告）、全部 Swift 测试 + hook 脚本测试、text-audit 全矩阵、
# 局部重绘 vs 整张重画、金图、闪烁扫描（标准 + 严格）。全部用全新的编译目录，所以警告一条不漏。
#   [REG_JOBS=4] QA/tools/full_regression.sh [输出目录]      （要在沙箱外跑；耗时约 30–40 分钟；REG_JOBS 是编译并行数，内存吃紧时调小）
# 结果：<输出目录>/summary.txt（人读的汇总）+ 每一步的完整日志。
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/QA/evidence/regression-final}"
mkdir -p "$OUT"; cd "$ROOT" || exit 1
CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
TESTFLAGS="-Xswiftc -F$FW -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib"
SUM="$OUT/summary.txt"; : > "$SUM"
say() { echo "$*" | tee -a "$SUM"; }
say "# 完整回归 $(date '+%Y-%m-%d %H:%M')  $(swift --version 2>&1 | head -1)"

# 1) debug：干净编译（含测试目标），数警告
rm -rf .build-reg
swift build --build-tests --scratch-path .build-reg -j "${REG_JOBS:-4}" $TESTFLAGS > "$OUT/build-debug.log" 2>&1; rc=$?
w=$(grep -ci "warning" "$OUT/build-debug.log")      # 不只数 "warning:"：宏展开里的警告（比如 #expect(true)）只打印成 "note: … to silence this warning"
say "debug 构建：退出码 $rc，警告 $w 条（$(grep -E 'Build complete|error:' "$OUT/build-debug.log" | tail -1)）"

# 2) release：干净编译，数警告
rm -rf .build-reg-rel
swift build -c release --scratch-path .build-reg-rel -j "${REG_JOBS:-4}" > "$OUT/build-release.log" 2>&1; rc=$?
w=$(grep -ci "warning" "$OUT/build-release.log")
say "release 构建：退出码 $rc，警告 $w 条（$(grep -E 'Build complete|error:' "$OUT/build-release.log" | tail -1)）"

# 3) 全部 Swift 测试（Swift Testing）
swift test --skip-build --scratch-path .build-reg $TESTFLAGS > "$OUT/tests.log" 2>&1
say "Swift 测试：$(grep -E '^(✔|✘) Test run with' "$OUT/tests.log" | tail -1)"
say "  失败的断言：$(grep -c '^✘ Test .* recorded an issue' "$OUT/tests.log") 条；被跳过的测试：$(grep -cE ' (was )?skipped( |:|\.|$)' "$OUT/tests.log") 条；已知问题（withKnownIssue）：$(grep -E '^(✔|✘) Test run with' "$OUT/tests.log" | tail -1 | grep -oE 'with [0-9]+ known issues?' | grep -oE '[0-9]+' || echo 0) 条"

say "  FSEvents 不可用而被跳过的监听断言：$(grep -c 'FSEvents 不可用' "$OUT/tests.log") 处（应为 0：完整回归在沙箱外跑，FSEvents 必须可用）"
say "  测试痕迹：swiftpm-testing-helper.plist 里的 NSWindow Frame 键 $(plutil -p "$HOME/Library/Preferences/swiftpm-testing-helper.plist" 2>/dev/null | grep -c 'NSWindow Frame') 个；~/Library/Preferences 里的 local.buddy-office.tests.* 文件 $(ls "$HOME/Library/Preferences" 2>/dev/null | grep -c '^local\.buddy-office\.tests\.') 个（都应为 0）"

# 3b) 会抢全局 FileIO 计数器 / 观察口的测试组合连跑 20 次（R2-005：原来 80 次里 56 次失败；SAN-02：open 审计被并行的 replay 测试污染；R3a-01 / R3b-01：登记表诱饵测试、DesktopMeta 全局量），要求 0 次失败
fails=0
for i in $(seq 1 20); do
  swift test --skip-build --scratch-path .build-reg $TESTFLAGS --filter "safetyNetRefusesKeyAndSocketPaths|keyFilesAreNeverOpened|DesktopMetaFileIOTests|EngineConfigTests|ReviewRegressionAppTests|fuzz_registryScannerWithDecoyFiles|openAudit|ReplayTests" > "$OUT/race-combo.log" 2>&1 || fails=$((fails+1))
done
say "  全局 FileIO 计数器 / 观察口竞争组合（safetyNet… / keyFilesAreNeverOpened / DesktopMetaFileIOTests / EngineConfigTests / ReviewRegressionAppTests / 登记表诱饵 / openAudit / ReplayTests）连跑 20 次：失败 $fails 次（应为 0）"

# 4) hook-merge 脚本测试
python3 Tests/hook_merge_test.py > "$OUT/hook-merge-test.log" 2>&1
say "hook-merge 脚本测试：$(grep -E '^Ran ' "$OUT/hook-merge-test.log") $(grep -E '^(OK|FAILED)' "$OUT/hook-merge-test.log" | tail -1)"

BIN=.build-reg-rel/release/buddyctl
# 5) text-audit 全矩阵
$BIN text-audit --max 0 > "$OUT/text-audit.log" 2>&1
say "text-audit：$(grep -E '^text-audit：[0-9]+ 个组合' "$OUT/text-audit.log")"
for k in 1 2 3 4 5 6 7 8; do say "  $(grep -E "^  $k " "$OUT/text-audit.log")"; done
say "  $(grep -E '没画出卡片' "$OUT/text-audit.log")"
say "  结论：$(grep -E '^text-audit：(违规|共|✗)' "$OUT/text-audit.log" | tail -1)"

# 6) 局部重绘 vs 整张重画（3 个场景，每个 90 秒的剧本 × 4 个时段 × 3 种视口 × 4 种数据，带悬停）
for sc in office tank strip; do
  $BIN verify --scene $sc --seconds 90 --modes demo,busy6,idle6,crowd12 --hover > "$OUT/verify-$sc.log" 2>&1
  say "verify[$sc]：$(grep -E '^verify:' "$OUT/verify-$sc.log")"
done

# 7) 金图
$BIN golden > "$OUT/golden.log" 2>&1
say "金图：$(tail -1 "$OUT/golden.log")"

# 8) 闪烁扫描：标准（3 个场景 × 3 个缩放，0–79.9 秒）+ 严格（容忍度 0，办公室 3×）
: > "$OUT/flicker.log"
for sc in office tank strip; do for z in 1 2 3; do
  $BIN flicker --scene $sc --zoom $z --from 0 --to 79.9 2>&1 | tail -1 | tee -a "$OUT/flicker.log" | sed 's/^/闪烁扫描：/' >> "$SUM"
done; done
$BIN flicker --scene office --zoom 3 --strict --from 0 --to 79.9 > "$OUT/flicker-strict.log" 2>&1
say "闪烁扫描（严格，容忍度 0，办公室 3×）：$(grep -E '^flicker' "$OUT/flicker-strict.log" | head -1)"
# 9) 独立核对（真实数据，只读）：token 交叉核对（独立实现 / 用量表 parse_line / ledger.json / dump 四个口径，冻结快照）、dump 与登记表逐会话核对
python3 QA/tools/token_crosscheck.py --selftest > "$OUT/token-crosscheck-selftest.log" 2>&1
say "token 交叉核对自检：$(tail -1 "$OUT/token-crosscheck-selftest.log")"
SNAP="$(mktemp -d "${TMPDIR:-/tmp}/tc-snap.XXXXXX")"
python3 QA/tools/token_crosscheck.py --run-dump --snapshot "$SNAP" --buddyctl "$BIN" > "$OUT/token-crosscheck-real.log" 2>&1
say "token 交叉核对（真实数据）：$(grep -c '→ 一致' "$OUT/token-crosscheck-real.log") 项一致，$(grep -c '不一致' "$OUT/token-crosscheck-real.log") 项不一致；$(grep -E '^结论' "$OUT/token-crosscheck-real.log" | tail -1)"
rm -rf "$SNAP"
python3 QA/tools/dump_vs_registry.py --selftest > "$OUT/dump-vs-registry-selftest.log" 2>&1
say "dump 与登记表核对自检：$(tail -1 "$OUT/dump-vs-registry-selftest.log")"
python3 QA/tools/dump_vs_registry.py --buddyctl "$BIN" > "$OUT/dump-vs-registry-real.log" 2>&1
say "dump 与登记表核对（真实数据）：$(grep -E '^  dump 共' "$OUT/dump-vs-registry-real.log")；$(grep -E '^结论' "$OUT/dump-vs-registry-real.log" | tail -1)"

# 10) 「绝不打开密钥文件 / socket」在真实环境里的证据：数据层只读地跑 60 秒（FSEvents 模式），汇总一共打开过哪些类别的文件
$BIN dump --audit-opens 60 > "$OUT/open-audit-real-60s.txt" 2>&1; rc=$?
say "open 审计（真实 ~/.claude，60 秒）：退出码 $rc；$(grep -E '^  合计' "$OUT/open-audit-real-60s.txt")；$(grep -E '^  结论' "$OUT/open-audit-real-60s.txt")"
say "# 完成 $(date '+%H:%M')"
