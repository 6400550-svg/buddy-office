#!/bin/bash
# 编译 M0 小样并组装成 dist/m0/Buddy 办公室.app（ad-hoc 签名）。可在沙箱内运行。
set -e
cd "$(dirname "$0")/../.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/clang-mc"; mkdir -p "$CLANG_MODULE_CACHE_PATH"
APP="dist/m0/Buddy 办公室.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macosx14.0 scripts/m0/proto.swift -o "$APP/Contents/MacOS/BuddyOffice"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.buddy-office</string>
  <key>CFBundleName</key><string>Buddy 办公室</string>
  <key>CFBundleDisplayName</key><string>Buddy 办公室</string>
  <key>CFBundleExecutable</key><string>BuddyOffice</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0-m0</string>
  <key>CFBundleVersion</key><string>202609282100</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSAppleEventsUsageDescription</key><string>点小人跳转到「终端」里对应的标签页时才会用到。</string>
</dict></plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none --identifier local.buddy-office "$APP"
codesign --verify --verbose "$APP" 2>&1
echo "built: $APP"
