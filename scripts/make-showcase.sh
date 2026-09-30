#!/bin/bash
# 重新生成 dist/展示/：动图（演示剧本 0–80 秒完整一遍）+ 各时段快照 + 图标。
#   scripts/make-showcase.sh            要先有 .build/release/buddyctl（BUDDY_SCRATCH=.build scripts/dev.sh build -c release）
# 全部是无头渲染，可以在沙箱里跑。画法有改动之后，先亲眼看过新画面再交付。
cd "$(dirname "$0")/.." || exit 1
CTL=".build/release/buddyctl"
OUT="dist/展示"
[ -x "$CTL" ] || { echo "没有 $CTL"; exit 1; }
mkdir -p "$OUT"
say() { printf "\033[1m%s\033[0m\n" "$1"; }

say "① 动图（12.5 帧/秒，每帧 80 ms，演示剧本 0–80 秒）"
"$CTL" gif --scene office --from 0 --to 80 --fps 12.5 --zoom 3 --w 256 --h 226 --clock 12:00 --out "$OUT/办公室-白天.gif"
"$CTL" gif --scene office --from 0 --to 80 --fps 12.5 --zoom 3 --w 256 --h 226 --clock 22:30 --out "$OUT/办公室-夜晚.gif"
"$CTL" gif --scene tank   --from 0 --to 80 --fps 12.5 --zoom 3 --clock 12:00 --out "$OUT/小鱼缸.gif"
"$CTL" gif --scene strip  --from 0 --to 80 --fps 12.5 --zoom 3 --clock 12:00 --out "$OUT/桌面宠物.gif"

# 一帧快照：snap <场景> <剧本秒> <钟点> <输出名> [额外参数…]
snap() {
  local scene="$1" t="$2" clock="$3" name="$4"; shift 4
  local tmp="$OUT/.tmp-$$"; mkdir -p "$tmp"
  "$CTL" snapshot --scene "$scene" --from "$t" --to "$t" --fps 1 --zoom 3 --scale 2 --w 256 --h 226 --clock "$clock" --out "$tmp" "$@" >/dev/null \
    && cp "$tmp/f0000.png" "$OUT/$name.png" && echo "   $name.png"
  rm -rf "$tmp"
}

say "② 办公室四个时段（剧本 41 秒：有人等批准、有人重试、有人做完、有人打盹）"
snap office 41 07:00 "快照-办公室-0700"
snap office 41 12:00 "快照-办公室-1200"
snap office 41 18:30 "快照-办公室-1830"
snap office 41 23:00 "快照-办公室-2300"

say "③ 几个关键时刻"
snap office 20 12:00 "快照-办公室-派小助手"
snap office 52 12:00 "快照-办公室-提问与计划待审"
snap office 66 12:00 "快照-办公室-下班工位"
snap office 41 12:00 "快照-悬停卡片" --hover 3
snap office 5 12:00 "快照-空办公室" --mode empty

say "④ 小鱼缸 / 桌面宠物"
snap tank 41 12:00 "快照-小鱼缸-1200"
snap tank 41 23:00 "快照-小鱼缸-2300"
snap strip 41 12:00 "快照-桌面宠物"

say "⑤ 图标"
"$CTL" icon --preview "$OUT/图标.png" --out "$OUT/.tmp-$$/AppIcon.iconset" >/dev/null && echo "   图标.png"; rm -rf "$OUT/.tmp-$$"
ls -la "$OUT"
