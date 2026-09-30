#!/bin/bash
# Buddy 办公室 —— 一键安装（双击运行，或在终端里 bash 安装.command [--yes]）
# --yes：所有问题默认同意，结尾也不等回车（自动化运行用）。
cd "$(dirname "$0")" || exit 1

YES=0; [ "$1" = "--yes" ] && YES=1
NAME="Buddy 办公室"
DEST="$HOME/Applications/$NAME.app"
STAGE="$HOME/Applications/.$NAME.new.app"
# 预编译发行包（Releases 里下载的 zip）：App 就在本脚本旁边、没有源码，跳过编译；从源码克隆的仓库则现场编译到 dist/
PREBUILT=0; [ -d "$NAME.app" ] && [ ! -f Package.swift ] && PREBUILT=1
if [ "$PREBUILT" = 1 ]; then SRC="$NAME.app"; else SRC="dist/$NAME.app"; fi

say() { printf "\n\033[1m%s\033[0m\n" "$1"; }
fail() {
  printf "\n\033[31m%s\033[0m\n\n" "$1"
  [ "$YES" = 1 ] || { printf "按回车键关闭…"; read -r _; }
  exit 1
}
ask() {                     # ask "问题"：默认 Y；--yes 直接同意
  [ "$YES" = 1 ] && return 0
  printf "%s [Y/n] " "$1"; read -r a
  case "$a" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

echo "========================================"
echo "   Buddy 办公室 · 安装"
echo "========================================"

# ---------- ① 开发工具 ----------
if [ "$PREBUILT" = 1 ]; then
  say "① 使用预编译版本（不需要开发工具）"
  ARCH_APP="$(lipo -archs "$SRC/Contents/MacOS/BuddyOffice" 2>/dev/null)"
  case " $ARCH_APP " in *" $(uname -m) "*) ;; *) fail "这个预编译版本只支持 $ARCH_APP，你的 Mac 是 $(uname -m)。请改用源码安装：git clone 仓库后运行 bash 安装.command。" ;; esac
  echo "   $ARCH_APP"
else
say "① 检查开发工具"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1
  fail "没装「命令行开发者工具」。已弹出安装窗口，装好之后再运行一次本安装程序。"
fi
SWIFT_V="$(swift --version 2>&1 | head -1)" || fail "找不到 swift。请先装好「命令行开发者工具」（终端里运行 xcode-select --install），再运行一次。"
echo "   $(xcode-select -p)"
echo "   $SWIFT_V"

# ---------- ② ③ 编译、图标、打包 ----------
say "② 编译（第一次大约 1～3 分钟）· ③ 生成图标并打包"
bash scripts/build-app.sh || fail "编译或打包失败，上面是出错信息。"
fi
[ -d "$SRC" ] || fail "没有找到 $SRC。"

# ---------- ④ 安装 ----------
say "④ 安装到 ~/Applications"
if pgrep -x BuddyOffice >/dev/null 2>&1; then
  echo "   先退出正在运行的旧版本…"
  osascript -e 'tell application id "local.buddy-office" to quit' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do pgrep -x BuddyOffice >/dev/null 2>&1 || break; sleep 0.5; done
  pkill -x BuddyOffice >/dev/null 2>&1
  sleep 0.5
fi
mkdir -p "$HOME/Applications" || fail "没法创建 ~/Applications。"
rm -rf "$STAGE"
ditto "$SRC" "$STAGE" || fail "复制失败。"
xattr -cr "$STAGE" 2>/dev/null
OLD="$HOME/Applications/.$NAME.old.app"
rm -rf "$OLD"
[ -d "$DEST" ] && { mv "$DEST" "$OLD" || fail "没法移走旧版本。"; }
if ! mv "$STAGE" "$DEST"; then
  [ -d "$OLD" ] && mv "$OLD" "$DEST"          # 装不上就把旧版本放回去，不能落得一个 App 都没有
  fail "没法把 App 放进 ~/Applications（已恢复旧版本）。"
fi
rm -rf "$OLD"
codesign --verify --strict "$DEST" >/dev/null 2>&1 || fail "安装后的签名校验没通过。"
echo "   已安装：$DEST"
# 项目里 dist/ 下的编译产物和装好的 App 是同一个 bundle id：留着的话，系统（LaunchServices）可能在 hook 的 `open -g -b local.buddy-office`
# 里挑中它而不是 ~/Applications 里这个。所以先把它注销、删掉，再把装好的这个登记一下（下次要用就重新编译一遍，很快）。
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
if [ "$PREBUILT" != 1 ] && [ -d "dist/$NAME.app" ]; then
  [ -x "$LSREG" ] && "$LSREG" -u "dist/$NAME.app" >/dev/null 2>&1
  rm -rf "dist/$NAME.app"
fi
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" >/dev/null 2>&1

# ---------- ⑤ 跟着 Claude 自动打开 ----------
say "⑤ 跟着 Claude 自动打开"
echo "   在 ~/.claude/settings.json 里加一条「会话启动」hook：每次开 Claude Code 会话时，"
echo "   如果 Buddy 办公室没在运行，就在后台把它打开。只加这一条，改之前会先备份，卸载时会删掉。"
if command -v python3 >/dev/null 2>&1; then
  if ask "要不要让 Buddy 办公室跟着 Claude 自动打开？"; then
    python3 scripts/hook-merge.py install || fail "写 settings.json 没成功（上面有原因）。App 已经装好了，只是不会自动打开；改好之后可以再运行一次安装。"
  else
    echo "   已跳过。之后想开启，再运行一次安装并回答 Y。"
  fi
else
  echo "   没找到 python3，跳过这一步（其余都装好了）。"
fi

# ---------- ⑥ 打开 ----------
say "⑥ 打开 Buddy 办公室"
open "$DEST"
echo "   第一次会遇到两个系统授权提示："
echo "   · 通知：允许的话，有人等你批准 / 做完了会弹系统通知；不允许也行，会改用屏幕右上角的像素提示。"
echo "   · 自动化（控制「终端」）：第一次点小人跳到终端里对应的标签页时才会问。重新编译之后会再问一次。"

echo
echo "========================================"
echo " 装好了！屏幕上应该出现一间像素办公室，"
echo " 每个正在运行的 Claude Code 会话是一个坐在工位上的小人。"
echo " 用法见「使用说明.txt」。"
echo "========================================"
[ "$YES" = 1 ] || { printf "\n按回车键关闭…"; read -r _; }
