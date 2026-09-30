#!/bin/bash
# 长时间运行测试：启动开发版 App，每 30 秒记一次 RSS 和 CPU（utime+stime 的增量），结束后给出汇总。
#   scripts/soak.sh <标签> <分钟> [App 参数…]      例：scripts/soak.sh 演示6忙碌 35 --demo --demo-mode busy6 --show --force-render
# 环境变量 SOAK_PID=<pid>：附着到已在运行的进程（不启动、不杀）。要在沙箱外跑。结果写到 /tmp/soak-<标签>.log；内存不应该持续上涨（看首尾和最大值）。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${BUDDY_APP:-$ROOT/dist/dev/Buddy 办公室 release.app}"
LABEL="$1"; MIN="$2"; shift 2
LOG="/tmp/soak-$LABEL.log"
if [ -n "$SOAK_PID" ]; then       # 附着到一个已经在运行的进程（例如正式安装的那个，真实数据）：不启动、不杀
  PID="$SOAK_PID"
else
  # 不按路径子串 pkill（会误杀并行的别人 / 用户的 App）：已经有同路径的副本在跑就退出，只关自己起的那个 pid（R2-013）
  BEFORE=" $(pgrep -f "^$APP/Contents/MacOS" | tr '\n' ' ')"
  [ "$BEFORE" != " " ] && { echo "$LABEL: 已经有一个同路径的副本在跑（pid$BEFORE），先别重复跑（别人的进程我不杀）" | tee "$LOG"; exit 1; }
  open -g -n "$APP" --args "$@"
  sleep 8
  PID=$(pgrep -f "^$APP/Contents/MacOS" | head -1)
fi
[ -z "$PID" ] && { echo "$LABEL: 没找到进程" | tee "$LOG"; exit 1; }
cpu() { ps -o utime=,stime= -p "$PID" 2>/dev/null | awk '{ split($1,a,/[:.]/); split($2,b,/[:.]/); print (a[1]*60+a[2])+a[3]/100 + (b[1]*60+b[2])+b[3]/100 }'; }
echo "# $LABEL pid=$PID 开始 $(date '+%H:%M:%S')  参数: $*" > "$LOG"
echo "# 秒  RSS(MB)  CPU%(近30秒)" >> "$LOG"
prev=$(cpu); t0=$(date +%s); n=$((MIN * 2))
for i in $(seq 1 $n); do
  sleep 30
  if ! kill -0 "$PID" 2>/dev/null; then echo "# 进程在第 $((i*30)) 秒退出了！" >> "$LOG"; break; fi
  cur=$(cpu); rss=$(ps -o rss= -p "$PID" | awk '{printf "%.1f", $1/1024}')
  awk -v c="$cur" -v p="$prev" -v t="$((i*30))" -v r="$rss" 'BEGIN{ printf "%d  %s  %.2f\n", t, r, (c-p)/30*100 }' >> "$LOG"
  prev=$cur
done
awk 'NR>2 && $1+0>0 { rss[NR]=$2; cpu[NR]=$3; if($2>mx)mx=$2; sum+=$3; n++ } END { printf "# 汇总：%d 个采样；RSS 首 %s MB → 末 %s MB，最大 %.1f MB；CPU 平均 %.2f%%\n", n, rss[3], rss[NR], mx, (n?sum/n:0) }' "$LOG" >> "$LOG"
[ -n "$SOAK_PID" ] || kill "$PID" 2>/dev/null
tail -3 "$LOG"
