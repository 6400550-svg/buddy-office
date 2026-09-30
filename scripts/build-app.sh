#!/bin/bash
# 编译 → 生成图标 → 组装 .app → ad-hoc 签名。产物：dist/Buddy 办公室.app
#   scripts/build-app.sh
# 环境变量：BUDDY_SCRATCH 指定 SwiftPM 的 --scratch-path（默认 .build）。
# 在 Claude Code 的沙箱里 swift build 写不了临时目录，要用 dangerouslyDisableSandbox 运行；平时在终端里直接跑就行。
set -eo pipefail      # swift build ... | tail -4 里编译失败也要让脚本失败（不然会把旧的 .build/release 二进制打包安装）
cd "$(dirname "$0")/.."
NAME="Buddy 办公室"
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"; VERSION="${VERSION:-1.0.0}"
BUILD="$(date +%Y%m%d%H%M)"
APP="dist/$NAME.app"
SCRATCH="${BUDDY_SCRATCH:-.build}"
say() { printf "\033[1m%s\033[0m\n" "$1"; }

say "① 编译（release）…"
swift build -c release --disable-sandbox --manifest-cache local --scratch-path "$SCRATCH" 2>&1 | tail -4
BIN="$SCRATCH/release/BuddyOffice"; CTL="$SCRATCH/release/buddyctl"
[ -x "$BIN" ] && [ -x "$CTL" ] || { echo "编译失败：找不到 $BIN 或 $CTL"; exit 1; }

say "② 生成图标…"
rm -rf dist/AppIcon.iconset dist/AppIcon.icns
"$CTL" icon --out dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns

say "③ 组装 App…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BuddyOffice"
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIdentifier</key><string>local.buddy-office</string>
  <key>CFBundleName</key><string>Buddy 办公室</string>
  <key>CFBundleDisplayName</key><string>Buddy 办公室</string>
  <key>CFBundleExecutable</key><string>BuddyOffice</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSAppleEventsUsageDescription</key><string>点小人跳转到「终端」里对应的标签页时才会用到。</string>
</dict></plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

say "④ 签名（ad-hoc，不开 hardened runtime）…"
codesign --force --sign - --timestamp=none --identifier local.buddy-office "$APP" 2>&1 | tail -1
codesign --verify --strict "$APP" && echo "   签名校验通过"
echo "   $APP（$VERSION，build $BUILD）"
