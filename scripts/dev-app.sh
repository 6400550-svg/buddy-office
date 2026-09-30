#!/bin/bash
# 开发用：把一个编译好的 BuddyOffice 可执行文件包成 ad-hoc 签名的 .app（默认放在 dist/dev/）。可在沙箱内运行。
#   scripts/dev-app.sh <可执行文件路径> [输出的.app路径]
set -e
cd "$(dirname "$0")/.."
BIN="$1"; APP="${2:-dist/dev/Buddy 办公室.app}"
# 开发版用单独的 bundle id：正式版的 hook 是 `open -g -b local.buddy-office`，不能让它挑中开发版；偏好设置也因此互不干扰。
BID="${BUDDY_BUNDLE_ID:-local.buddy-office.dev}"
[ -x "$BIN" ] || { echo "找不到可执行文件：$BIN"; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BuddyOffice"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>__BID__</string>
  <key>CFBundleName</key><string>Buddy 办公室</string>
  <key>CFBundleDisplayName</key><string>Buddy 办公室</string>
  <key>CFBundleExecutable</key><string>BuddyOffice</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0-dev</string>
  <key>CFBundleVersion</key><string>202609290000</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSAppleEventsUsageDescription</key><string>点小人跳转到「终端」里对应的标签页时才会用到。</string>
</dict></plist>
PLIST
sed -i '' "s/__BID__/$BID/" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --timestamp=none --identifier "$BID" "$APP" 2>&1 | tail -1
echo "packaged: $APP"
