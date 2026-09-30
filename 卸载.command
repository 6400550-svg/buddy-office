#!/bin/bash
# Buddy 办公室 —— 卸载（双击运行，或在终端里 bash 卸载.command [--yes]）
# --yes：所有问题按默认回答（保留偏好设置），结尾不等回车。
cd "$(dirname "$0")" || exit 1

YES=0; [ "$1" = "--yes" ] && YES=1
NAME="Buddy 办公室"
DEST="$HOME/Applications/$NAME.app"

say() { printf "\n\033[1m%s\033[0m\n" "$1"; }
echo "========================================"
echo "   Buddy 办公室 · 卸载"
echo "========================================"

say "① 退出 App"
if pgrep -x BuddyOffice >/dev/null 2>&1; then
  osascript -e 'tell application id "local.buddy-office" to quit' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do pgrep -x BuddyOffice >/dev/null 2>&1 || break; sleep 0.5; done
  pkill -x BuddyOffice >/dev/null 2>&1
fi
echo "   已退出"

say "② 注销开机启动项"
[ -x "$DEST/Contents/MacOS/BuddyOffice" ] && "$DEST/Contents/MacOS/BuddyOffice" --unregister-login 2>/dev/null
launchctl bootout "gui/$(id -u)/local.buddy-office" >/dev/null 2>&1
rm -f "$HOME/Library/LaunchAgents/local.buddy-office.plist"
echo "   已注销"

say "③ 删除 App"
rm -rf "$DEST"
echo "   已删除 $DEST"

say "④ 从 ~/.claude/settings.json 里去掉「会话启动」hook"
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/hook-merge.py uninstall || echo "   没成功（上面有原因）。settings.json 没有被改动。"
else
  echo "   没找到 python3，跳过。可以手动打开 ~/.claude/settings.json，删掉 command 里带 local.buddy-office 的那一项。"
fi

say "⑤ 偏好设置和数据"
DEL=0
if [ "$YES" != 1 ]; then
  printf "   同时删除偏好设置和 ~/Library/Application Support/BuddyOffice？[y/N] "
  read -r yn
  [ "$yn" = "y" ] || [ "$yn" = "Y" ] && DEL=1
fi
if [ "$DEL" = 1 ]; then
  defaults delete local.buddy-office >/dev/null 2>&1
  rm -f "$HOME/Library/Preferences/local.buddy-office.plist"
  rm -rf "$HOME/Library/Application Support/BuddyOffice"
  echo "   已删除"
else
  echo "   保留（重新安装后设置还在）"
fi

echo
echo "卸载完成。项目文件夹本身没有动，不需要的话可以自己删掉。"
[ "$YES" = 1 ] || { printf "\n按回车键关闭…"; read -r _; }
