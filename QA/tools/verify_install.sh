#!/bin/bash
# 重装之后的检查（QA ⑥）：装好的 App 是不是修好的那一版、在不在跑、签名 / hook / 句柄 / 数据文件有没有异常。
#   QA/tools/verify_install.sh [安装前 settings.json 的 sha256 文件，可选]        要在沙箱外跑；全程只读
APP="$HOME/Applications/Buddy 办公室.app"
BIN="$APP/Contents/MacOS/BuddyOffice"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ok=1; say() { echo "$*"; }
bad() { ok=0; say "✗ $*"; }
say "# 安装检查 $(date '+%Y-%m-%d %H:%M:%S')"
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null); B=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null)
WANT=$(tr -d '[:space:]' < "$ROOT/VERSION")
say "版本：$V（build $B）；项目 VERSION 文件：$WANT"; [ "$V" = "$WANT" ] || bad "版本和 VERSION 文件不一致"
BID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null); say "Bundle id：$BID"; [ "$BID" = "local.buddy-office" ] || bad "bundle id 不对"
if codesign --verify --strict "$APP" 2>/dev/null; then say "codesign --verify --strict：通过（$(codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature' | tr '\n' ' ')）"; else bad "签名校验没通过"; fi
say "可执行文件：$(ls -la "$BIN" | awk '{print $5" 字节，"$6" "$7" "$8}')；build 时间戳 $B"
NEWER=$(find "$ROOT/Sources" "$ROOT/Package.swift" -newer "$BIN" -type f 2>/dev/null | head -3)
[ -z "$NEWER" ] && say "源码里没有比装好的可执行文件更新的文件（装好的就是当前源码编出来的）" || bad "有源码比装好的可执行文件更新：$NEWER"
PID=$(pgrep -f "^$BIN" | head -1)
if [ -n "$PID" ]; then say "在运行：pid $PID，启动于 $(ps -o lstart= -p $PID)，路径 $(ps -o command= -p $PID | cut -c1-120)"; else bad "没在运行"; fi
if [ -n "$PID" ]; then
  L=$(lsof -p "$PID" -n -P 2>/dev/null)
  say "文件句柄：$(echo "$L" | tail -n +2 | wc -l | tr -d ' ') 个；类型 $(echo "$L" | tail -n +2 | awk '{print $5}' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')"
  echo "$L" | grep -qiE '\.key( |$)|\.sock( |$)' && bad "有 .key / .sock 句柄" || say "没有 .key / .sock 句柄"
  echo "$L" | grep -qE 'IPv4|IPv6' && bad "有网络连接" || say "没有网络连接（没有 IPv4 / IPv6 句柄）"
  say "线程数：$(ps -M -p $PID | tail -n +2 | wc -l | tr -d ' ')；RSS $(ps -o rss= -p $PID | awk '{printf "%.1f MB", $1/1024}')；CPU 累计 $(ps -o time= -p $PID)"
fi
python3 "$ROOT/scripts/hook-merge.py" status > /tmp/.hm-status.$$ 2>&1; rc=$?; say "hook-merge status：$(cat /tmp/.hm-status.$$)（退出码 $rc）"; rm -f /tmp/.hm-status.$$
[ $rc -eq 0 ] || bad "settings.json 里没有 hook"
if [ -n "$1" ] && [ -f "$1" ]; then
  A=$(shasum -a 256 "$HOME/.claude/settings.json" | awk '{print $1}'); Bf=$(cat "$1")
  [ "$A" = "$Bf" ] && say "settings.json 和安装前逐字节相同（sha256 一致）：install 是幂等的，什么都没改" || say "settings.json 和安装前不同（sha256：$Bf → $A）——如果不是 hook-merge 改的，要查是谁改的"
fi
CNT=$(mdfind "kMDItemCFBundleIdentifier == 'local.buddy-office'" 2>/dev/null | wc -l | tr -d ' '); say "mdfind：bundle id local.buddy-office 对应 $CNT 个 App（应为 1：装好的这个）"; [ "$CNT" = 1 ] || say "  （不是 1，列出来：$(mdfind "kMDItemCFBundleIdentifier == 'local.buddy-office'" 2>/dev/null | tr '\n' ' ')）"
say "$( [ $ok = 1 ] && echo '结论：✅ 装好的是修好的那一版，在运行，签名 / hook / 句柄都正常' || echo '结论：✗ 有问题，见上面')"
