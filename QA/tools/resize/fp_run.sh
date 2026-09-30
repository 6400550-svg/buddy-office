#!/bin/bash
# fp_run.sh <variant> <tag> [extra args…]：起一个变体（先清掉它自己的偏好设置域），在 4 秒 / 每轮之后 / 结束后 1 秒 / 结束后 12 秒各用 footprint 量一次分类
V="$1"; TAG="$2"; shift 2
defaults delete "local.buddy-office.dev.rsz-$V" > /dev/null 2>&1
APP="$PWD/apps/rsz-$V.app/Contents/MacOS/BuddyOffice"
LOG="run-$V-$TAG.log"
"$APP" --demo --no-persist --force-render --show "$@" > "$LOG" 2>&1 &
PID=$!
sleep 4; footprint -p $PID > "fp-$V-$TAG-1-base.txt" 2>&1
SECONDS=0
until grep -q "全部做完后 1 秒" "$LOG" 2>/dev/null || ! kill -0 $PID 2>/dev/null || [ $SECONDS -gt 150 ]; do sleep 1; done
footprint -p $PID > "fp-$V-$TAG-2-after.txt" 2>&1
until grep -q "全部做完后 10 秒" "$LOG" 2>/dev/null || ! kill -0 $PID 2>/dev/null || [ $SECONDS -gt 170 ]; do sleep 1; done
footprint -p $PID > "fp-$V-$TAG-3-later.txt" 2>&1
wait $PID 2>/dev/null
defaults delete "local.buddy-office.dev.rsz-$V" > /dev/null 2>&1
cat "$LOG"
