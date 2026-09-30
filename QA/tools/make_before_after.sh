#!/bin/bash
# 文字重叠 / 遮挡 修复前后对比图：同一个组合，用「撤销了全部修复的 buddyctl」（QA/tools/verify_fail_before.py --build-before 编出来的）
# 和「修好后的 buddyctl」各出一张（修复前的画面上有 text-audit 画的红框 = 它抓到的违规），并排拼起来。
#   QA/tools/make_before_after.sh <修复前的 buddyctl> <修复后的 buddyctl> [输出.png]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BEFORE="$1"; AFTER="$2"; OUT="${3:-$ROOT/QA/img/text-overlap-before-after.png}"
[ -x "$BEFORE" ] && [ -x "$AFTER" ] || { echo "用法：make_before_after.sh <修复前 buddyctl> <修复后 buddyctl> [输出.png]"; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/before-after.XXXXXX")"
mkdir -p "$(dirname "$OUT")"
ARGS=()

# 一对图：text-audit 的一个组合（违规的画面带红框）
audit_pair() {   # 序号 说明 场景 过滤串
  local n="$1" cap="$2" scene="$3" filt="$4"
  for side in before after; do
    local bin="$BEFORE"; [ "$side" = after ] && bin="$AFTER"
    mkdir -p "$TMP/$n-$side"
    "$bin" text-audit --scene "$scene" --filter "$filt" --images "$TMP/$n-$side" --all-images --max-images 1 > "$TMP/$n-$side/log.txt" 2>&1
  done
  local b a; b=$(ls "$TMP/$n-before"/*.png 2>/dev/null | head -1); a=$(ls "$TMP/$n-after"/*.png 2>/dev/null | head -1)
  local nb; nb=$(grep -E "^text-audit：共 [0-9]+ 处违规" "$TMP/$n-before/log.txt" | head -1 | sed -E 's/（.*//; s/^text-audit：//')
  [ -n "$a" ] && ARGS+=("$cap｜修复前 text-audit ${nb:-未报违规}" "${b:-/nonexistent}" "$a") || echo "没出图：$cap"
}
# 一对图：buddyctl snapshot（放大的单帧 / 连续帧总览）
snap_pair() {    # 序号 说明 输出文件 snapshot 参数…
  local n="$1" cap="$2" file="$3"; shift 3
  for side in before after; do
    local bin="$BEFORE"; [ "$side" = after ] && bin="$AFTER"
    "$bin" snapshot "$@" --out "$TMP/$n-$side" > /dev/null 2>&1
  done
  ARGS+=("$cap" "$TMP/$n-before/$file" "$TMP/$n-after/$file")
}

audit_pair 1 "TA-001 / TA-002 桌牌文字：夜里对比度只有 1.5–2:1、第二行被切（缩放 3×，4 人，所有状态）" office "默认窗口 缩放3× 4人 标题:normal 状态:all 23:00"
audit_pair 2 "TA-001 白天状态行对比度 2.91:1（缩放 3×，混排标题）" office "默认窗口 缩放3× 4人 标题:mixed 状态:demo 12:00"
audit_pair 3 "TA-003 emoji 标题顶出桌牌（缩放 4×）" office "默认窗口 缩放4× 4人 标题:emoji 状态:demo 12:00"
audit_pair 4 "TA-005 空办公室的牌子：字太暗、被桌椅盖住（缩放 4×）" office "默认窗口 缩放4× 0人 标题:normal 状态:demo 12:00"
audit_pair 5 "TA-006 / 007 / 008 悬停卡片（最小窗口 200×220，缩放 2×）：修复前没有任何位置既放得进窗口又不盖住那个人，鼠标悬停没有任何反应（修复前的「未报违规」是因为根本没有卡片）；修复后用兜底位置画出来，不盖住脸 / 屏幕 / 气泡" hover "最小窗口 缩放2× 4人 座位0 标题:mixed 状态:demo 12:00"
snap_pair 6 "TA-012 「其他 MCP」屏幕的首字母：notion 画成「?」→「N」（放大 8 倍）" f0000.png --scene office --from 26 --to 26 --fps 15 --zoom 8 --scale 1 --w 224 --h 300 --crop 138,58,60,78
snap_pair 7 "TA-013 Bash 长任务的进度条：被头挡住只露一小段 → 移到上面完整可见（放大 8 倍）" f0000.png --scene office --from 36 --to 36 --fps 15 --zoom 8 --scale 1 --w 224 --h 300 --crop 26,58,60,78
snap_pair 8 "SP-01 显示器关机：一帧硬切成黑屏 → Bayer 抖动倒放 300 ms（离场，t=59.95–60.45，30 fps）" contact.png --scene office --from 59.95 --to 60.45 --fps 30 --zoom 4 --scale 1 --w 224 --h 300 --crop 138,132,60,78 --cells 12 --cols 6

swift "$ROOT/QA/tools/compose_before_after.swift" "$OUT" "文字重叠 / 遮挡 / 关键信息看不清：修复前 vs 修复后（同一个组合，text-audit 红框 = 抓到的违规）" "${ARGS[@]}"
rm -rf "$TMP"
