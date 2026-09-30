#!/bin/bash
# ThreadSanitizer 下把「有真实线程」的数据层测试跑一遍（QA ②：数据竞争 / 线程安全）：SessionStore、TokenLedger、FileWatcher、
# 解析线程的模糊测试、状态机的进程级测试、hook 日志、JSONL 尾随读取；再把表现层 + 应用层里有线程 / 全局钩子的套件跑一遍。（纯函数的数据层测试没有线程，不需要。）
#   QA/tools/tsan_run.sh [输出目录，默认 QA/evidence/tsan]      要在沙箱外跑；会自己编一份带 TSan 的 debug 构建（.build-tsan）
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT" || exit 1
OUT="${1:-$ROOT/QA/evidence/tsan}"; mkdir -p "$OUT"; SUM="$OUT/summary.txt"; : > "$SUM"
say() { echo "$*" | tee -a "$SUM"; }
CLT=/Library/Developer/CommandLineTools; FW=$CLT/Library/Developer/Frameworks
TESTFLAGS="-Xswiftc -F$FW -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib"
FILTER='StoreTests|TokenLedgerTests|FuzzWatcherTests|RobustnessTests|StateRuleProcessTests|HookLogTests|JSONLTailerTests|FuzzTailerTests|FuzzReadersTests|EngineScenarioTests'
say "# TSan 运行 $(date '+%Y-%m-%d %H:%M')  filter=$FILTER"
t0=$(date +%s)
export TSAN_OPTIONS="halt_on_error=0:second_deadlock_stack=1"
swift test --sanitize=thread --scratch-path .build-tsan $TESTFLAGS --filter "$FILTER" > "$OUT/tests.log" 2>&1; rc=$?
races=$(grep -c "WARNING: ThreadSanitizer" "$OUT/tests.log")
say "退出码 $rc；TSan 报告 $races 处；$(( $(date +%s) - t0 )) 秒；$(grep -E '^(✔|✘) Test run with' "$OUT/tests.log" | tail -1)"
grep -A12 "WARNING: ThreadSanitizer" "$OUT/tests.log" | head -120 > "$OUT/reports-head.txt"

# 表现层 / 应用层里有线程 / 全局钩子的测试也在 TSan 下跑一遍（ASan 抓到过 text-audit 像素字钩子的数据竞争，SAN-01；这两层有全局钩子和并行套件）
mkdir -p "$OUT/ui"
t1=$(date +%s)
# 只挑有线程 / 全局钩子 / 并行竞争的套件：整个表现层 + 应用层套件在 TSan 下 15 分钟还没跑完（text-audit 矩阵、局部重绘对比这类 CPU 密集的测试慢 10 倍以上），
# 所以不跑 TextAuditMatrixTests（矩阵本身在 ASan 下用 buddyctl 全量跑过，`asan_run.sh`）。
UI_FILTER='ReviewRegressionStageTests|TextAuditDetectorTests|TextAuditRegressionTests|PixelViewTests|PixelViewDragTests|AutoQuitTests|HousekeepingTests|PanelAnimationTests|AlertCoordinatorTests|AlertFallbackTests|NotificationAuthTests|DebugLogTests|DesktopMetaFileIOTests|ToastTextTests|SpecTraceAlertTests|SpecTracePanelTests'
swift test --sanitize=thread --scratch-path .build-tsan $TESTFLAGS --filter "$UI_FILTER" > "$OUT/ui/tests.log" 2>&1; rc=$?
races=$(grep -c "WARNING: ThreadSanitizer" "$OUT/ui/tests.log")
say "表现层 + 应用层测试：退出码 $rc；TSan 报告 $races 处；$(( $(date +%s) - t1 )) 秒；$(grep -E '^(✔|✘) Test run with' "$OUT/ui/tests.log" | tail -1)"
grep -A14 "WARNING: ThreadSanitizer" "$OUT/ui/tests.log" | head -160 > "$OUT/ui/reports-head.txt"
say "# 完成 $(date '+%H:%M')"
