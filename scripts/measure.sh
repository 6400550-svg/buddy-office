#!/bin/bash
# 开发用：启动开发版 App，预热后测一段时间的 CPU（cputime 差）和内存（RSS），再关掉。
#   scripts/measure.sh <标签> <秒数> [App 参数…]
# 例：scripts/measure.sh "演示 3 个形态" 20 --demo --show --tank --strip --force-render
# 要在沙箱外跑（open / ps 需要）。用 BUDDY_APP 指定 .app（默认 dist/dev/Buddy 办公室 release.app）。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${BUDDY_APP:-$ROOT/dist/dev/Buddy 办公室 release.app}"
LABEL="$1"; SECS="${2:-20}"; shift 2
# 不按路径子串 pkill（并行跑多个测量 / QA 时会误杀别人用同一个路径起的副本，BUDDY_APP 指到装好的 App 时还会杀掉用户的 App）：
# 已经有同路径的副本在跑就退出；只记下 / 关掉自己起的那个 pid（R2-013）
BEFORE=" $(pgrep -f "^$APP/Contents/MacOS" | tr '\n' ' ')"
[ "$BEFORE" != " " ] && { echo "$LABEL: 已经有一个同路径的副本在跑（pid$BEFORE），先别重复量（别人的进程我不杀）"; exit 1; }
open -g -n "$APP" --args "$@"
sleep "${WARM:-9}"                                  # 预热：启动时的首次扫描 / 首帧渲染不算
PID=$(pgrep -f "^$APP/Contents/MacOS" | head -1)
[ -z "$PID" ] && { echo "$LABEL: 没找到进程"; exit 1; }
cpu() { ps -o cputime= -p "$PID" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
c0=$(cpu); sleep "$SECS"; c1=$(cpu)
rss=$(ps -o rss= -p "$PID" | awk '{printf "%d", $1/1024}')
awk -v a="$c0" -v b="$c1" -v s="$SECS" -v l="$LABEL" -v r="$rss" 'BEGIN { printf "%s: CPU %.2f%% 单核，RSS %d MB（%d 秒）\n", l, (b-a)/s*100, r, s }'
[ -n "$KEEP" ] || kill "$PID" 2>/dev/null
