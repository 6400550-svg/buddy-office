#!/bin/bash
# text-audit 总览图：从压力矩阵里挑 12 个有代表性的组合（办公室 / 悬停卡片 / 小鱼缸 / 宠物条 / 提示卡，各种缩放、窗口、时段、标题），
# 各出一张画面（这些组合的违规数都是 0，所以没有红框），拼成一张网格图，用来亲眼看一遍。
#   QA/tools/make_audit_overview.sh [buddyctl 路径] [输出.png]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$ROOT/.build/release/buddyctl}"
OUT="${2:-$ROOT/QA/img/text-audit-overview.png}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/audit-overview.XXXXXX")"
mkdir -p "$(dirname "$OUT")"
# 场景 | 过滤串 | 说明
COMBOS=(
"office|默认窗口 缩放2× 12人 标题:mixed 状态:demo 12:00|办公室 默认窗口 2× 12 人 混排标题 白天"
"office|默认窗口 缩放3× 8人 标题:longZh 状态:all 23:00|办公室 默认窗口 3× 8 人 40 字长标题 所有状态 夜里"
"office|默认窗口 缩放4× 4人 标题:emoji 状态:demo 12:00|办公室 默认窗口 4× 4 人 emoji 标题"
"office|很窄窗口 缩放3× 12人 标题:longEn 状态:demo 12:00|办公室 很窄窗口(260 pt) 无空格长英文标题"
"office|最小窗口 缩放2× 4人 标题:mixed 状态:demo 12:00 隐私|办公室 最小窗口(200×220) 隐私模式"
"office|默认窗口 缩放4× 0人 标题:normal 状态:demo 12:00|办公室 4× 没有会话（牌子）"
"hover|默认窗口 缩放3× 12人 座位0 标题:mixed 状态:demo 12:00|悬停卡片 默认窗口 3× 左上角座位"
"hover|最小窗口 缩放2× 8人 座位0 标题:longZh 状态:demo 12:00|悬停卡片 最小窗口 2×（兜底位置）"
"hover|矮宽窗口 缩放3× 8人|悬停卡片 矮宽窗口(900×260) 3×"
"tank|缩放2× 12人 标题:mixed 状态:all+0 12:00|小鱼缸 2× 12 人（+N 牌子）"
"strip|缩放3× 8人 标题:mixed 状态:all+8|桌面宠物 3× 8 人 所有状态"
"cards|缩放3× 标题:longZh 状态:等批准 Bash|悬停卡片(单独) 3× 40 字标题 等批准"
)
ARGS=()
i=0
for c in "${COMBOS[@]}"; do
  IFS='|' read -r scene filt cap <<< "$c"
  case "$scene" in
    office) sc=office ;; hover) sc=hover ;; tank) sc=tank ;; strip) sc=strip ;; cards) sc=cards ;;
  esac
  d="$TMP/$i"; mkdir -p "$d"
  "$BIN" text-audit --scene "$sc" --filter "$filt" --images "$d" --all-images --max-images 1 > "$d/log.txt" 2>&1
  img=$(ls "$d"/*.png 2>/dev/null | head -1)
  if [ -z "$img" ]; then echo "没出图：$scene / $filt"; else ARGS+=("$cap" "$img"); fi
  i=$((i+1))
done
swift "$ROOT/QA/tools/compose_grid.swift" "$OUT" "text-audit 总览：12 个压力组合（全部 0 违规）" 3 420 "${ARGS[@]}"
rm -rf "$TMP"
