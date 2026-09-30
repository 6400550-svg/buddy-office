#!/bin/bash
# 长跑同时开（QA ②：演示 / 真实数据 / replay，每种至少 30 分钟；再加一路「全部空闲」量空闲 CPU）：
#   演示    (a) 开发副本 + `--demo --demo-mode busy6 --show --force-render`（只开办公室窗口、6 个人都在忙：任务书 8.5 的预算按办公室窗口算，≤3%）；
#            (b) 同上再加 `--tank --strip`（三种形态全开：最重的情形，每个面各自渲染、CPU 叠加，只看有没有泄漏 / 增长，预算放宽到 ≤5%）
#   空闲    开发副本 + `--demo --demo-mode idle6 --show --force-render`（只开办公室窗口——任务书 8.5 的预算按办公室窗口算；6 个人都空闲：预算 ≤1%）
#   真实数据  (a) 开发副本 + `--show --force-render --no-persist`：读你真实的 ~/.claude（只读），强制渲染，不写 identities / ledger，不碰装好的那个 App 的数据；
#            (b) 顺带附着到已经装好的 ~/Applications/Buddy 办公室.app（你真实在用的那个），原样监视，不启动、不杀
#   replay   往一个假 home 持续写像真的一样的会话数据（QA/tools/replay_soak.py，带蜜罐 .key 文件），开发副本 `--data-root` 读它：
#            (a) replay：6 个会话、接近真实的节奏（一轮忙 1–5 分钟）、坏数据噪声、约 1% 的工具调用要等批准（预算 ≤3%）；
#            (b) replay 压力：8 个会话、压缩的节奏（一轮 20–120 秒）、6% 的工具调用要等批准 = 每约 10 秒一次提醒 + 提示音 + 提示卡，
#                远比真实用法密，只看有没有泄漏 / 崩溃 / 线程增长，不判 CPU 预算
# 每个进程用 QA/tools/soak_watch.py 盯：RSS、footprint、CPU%、线程数、句柄数、.key / .sock 句柄、崩溃报告。
#   QA/tools/run_soaks.sh [分钟，默认 35] [App 可执行文件，默认 .build/release/BuddyOffice] [输出目录]
# 要在沙箱外跑。只 kill 自己起的开发副本（路径含 soak-*.app），绝不动装好的 App、Claude。
MIN="${1:-35}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${2:-$ROOT/.build/release/BuddyOffice}"
OUT="${3:-$ROOT/QA/evidence/soak}"
mkdir -p "$OUT"; cd "$ROOT" || exit 1
[ -x "$BIN" ] || { echo "找不到 $BIN"; exit 2; }
HOME_FAKE=/private/tmp/bosoak/home
HOME_FAKE2=/private/tmp/bosoak/home2
rm -rf /private/tmp/bosoak; mkdir -p /private/tmp/bosoak
for k in demo demo3 idle real replay replay2; do scripts/dev-app.sh "$BIN" "dist/dev/Buddy 办公室 soak-$k.app" > /dev/null 2>&1; done
pid_of() { pgrep -f "^$ROOT/dist/dev/Buddy 办公室 soak-$1.app/Contents/MacOS/BuddyOffice" | head -1; }
INSTALLED=$(pgrep -f "^$HOME/Applications/Buddy 办公室.app/Contents/MacOS/BuddyOffice" | head -1)
echo "开始 $(date '+%Y-%m-%d %H:%M:%S')，$MIN 分钟；二进制 $BIN；已装好的 App pid=${INSTALLED:-无}" | tee "$OUT/run.log"

python3 QA/tools/replay_soak.py --root "$HOME_FAKE" --minutes $((MIN + 2)) --sessions 6 --seed 11 --calm --wait-prob 0.01 --report "$OUT/replay-generator.json" > "$OUT/replay-generator.log" 2>&1 &
GEN=$!
python3 QA/tools/replay_soak.py --root "$HOME_FAKE2" --minutes $((MIN + 2)) --sessions 8 --seed 12 --report "$OUT/replay2-generator.json" > "$OUT/replay2-generator.log" 2>&1 &
GEN2=$!
sleep 3
open -g -n "dist/dev/Buddy 办公室 soak-demo.app" --args --demo --demo-mode busy6 --show --force-render
open -g -n "dist/dev/Buddy 办公室 soak-demo3.app" --args --demo --demo-mode busy6 --show --tank --strip --force-render
open -g -n "dist/dev/Buddy 办公室 soak-idle.app" --args --demo --demo-mode idle6 --show --force-render
open -g -n "dist/dev/Buddy 办公室 soak-real.app" --args --show --force-render --no-persist
open -g -n "dist/dev/Buddy 办公室 soak-replay.app" --args --data-root "$HOME_FAKE" --show --force-render
open -g -n "dist/dev/Buddy 办公室 soak-replay2.app" --args --data-root "$HOME_FAKE2" --show --force-render
sleep 10
P_DEMO=$(pid_of demo); P_DEMO3=$(pid_of demo3); P_IDLE=$(pid_of idle); P_REAL=$(pid_of real); P_REPLAY=$(pid_of replay); P_REPLAY2=$(pid_of replay2)
echo "pid：演示 $P_DEMO  演示三种形态 $P_DEMO3  空闲 $P_IDLE  真实数据(开发副本) $P_REAL  replay $P_REPLAY  replay 压力 $P_REPLAY2  已装好 ${INSTALLED:-无}" | tee -a "$OUT/run.log"
for x in "$P_DEMO" "$P_DEMO3" "$P_IDLE" "$P_REAL" "$P_REPLAY" "$P_REPLAY2"; do [ -z "$x" ] && { echo "有进程没起来，中止"; kill $GEN $GEN2 2>/dev/null; exit 3; }; done

W=()
python3 QA/tools/soak_watch.py --pid "$P_DEMO"   --minutes "$MIN" --label "演示（busy6，办公室窗口）"           --cpu-budget 3 --out "$OUT/soak-demo.log" & W+=($!)
python3 QA/tools/soak_watch.py --pid "$P_DEMO3"  --minutes "$MIN" --label "演示（busy6，办公室 + 小鱼缸 + 宠物条）" --cpu-budget 5 --out "$OUT/soak-demo-3forms.log" & W+=($!)
python3 QA/tools/soak_watch.py --pid "$P_IDLE"   --minutes "$MIN" --label "空闲（idle6，只开办公室窗口）"       --cpu-budget 1 --out "$OUT/soak-idle.log" & W+=($!)
python3 QA/tools/soak_watch.py --pid "$P_REAL"   --minutes "$MIN" --label "真实数据（开发副本，只读）"       --cpu-budget 3 --out "$OUT/soak-real-dev.log" & W+=($!)
python3 QA/tools/soak_watch.py --pid "$P_REPLAY2" --minutes "$MIN" --label "replay 压力（8 个会话，每约 10 秒一次提醒 + 提示音）" --out "$OUT/soak-replay-stress.log" & W+=($!)
python3 QA/tools/soak_watch.py --pid "$P_REPLAY" --minutes "$MIN" --label "replay（假 home，6 个会话，接近真实的节奏 + 噪声）" --cpu-budget 3 --out "$OUT/soak-replay.log" & W+=($!)
[ -n "$INSTALLED" ] && { python3 QA/tools/soak_watch.py --pid "$INSTALLED" --minutes "$MIN" --label "已装好的 App（真实数据，原样）" --cpu-budget 3 --out "$OUT/soak-real-installed.log" & W+=($!); }
wait "${W[@]}"
# 长跑结束、进程杀掉之前：用系统的 leaks 工具扫一遍（找不可达的内存 / 循环引用；只读，进程会被停几秒）
for pair in "demo:$P_DEMO" "demo-3forms:$P_DEMO3" "idle:$P_IDLE" "real-dev:$P_REAL" "replay:$P_REPLAY" "replay-stress:$P_REPLAY2" "installed:$INSTALLED"; do
  n="${pair%%:*}"; p="${pair##*:}"; [ -z "$p" ] && continue
  leaks "$p" > "$OUT/leaks-$n.txt" 2>&1
  echo "leaks[$n pid $p]：$(grep -E 'nodes malloced|leaks for' "$OUT/leaks-$n.txt" | tr '\n' ' ')" | tee -a "$OUT/run.log"
done
kill "$P_DEMO" "$P_DEMO3" "$P_IDLE" "$P_REAL" "$P_REPLAY" "$P_REPLAY2" 2>/dev/null
sleep 2; kill $GEN $GEN2 2>/dev/null; wait $GEN $GEN2 2>/dev/null
for k in demo demo3 idle real replay replay2; do rm -rf "dist/dev/Buddy 办公室 soak-$k.app"; done
echo "结束 $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$OUT/run.log"
for f in "$OUT"/soak-*.log; do echo "== $f"; grep -E "^# (汇总|采样|线程数|CPU|RSS|内存|文件句柄|\.key|崩溃|结果|物理占用)" "$f"; done | tee -a "$OUT/run.log"
echo "replay 发生器：$(tail -1 "$OUT/replay-generator.log" | cut -c1-400)" | tee -a "$OUT/run.log"
echo "replay 压力发生器：$(tail -1 "$OUT/replay2-generator.log" | cut -c1-400)" | tee -a "$OUT/run.log"
