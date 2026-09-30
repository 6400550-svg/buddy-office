#!/bin/bash
# 重新编译 A / B / C 三个变体并打包成 dev app（各自的 bundle id）
cd "$(dirname "$0")" || exit 1
ROOT=~/Desktop/编程项目/Buddy办公室
for V in A B C; do
  cp PixelView.$V.swift Sources/BuddyOffice/PixelView.swift
  swift build -c release --product BuddyOffice --scratch-path .build-exp > build-$V.log 2>&1 || { echo "build $V failed"; tail -20 build-$V.log; exit 1; }
  grep -ci warning build-$V.log | sed "s/^/warnings $V: /"
  cp .build-exp/release/BuddyOffice bin/BuddyOffice-$V
  BUDDY_BUNDLE_ID=local.buddy-office.dev.rsz-$V "$ROOT/scripts/dev-app.sh" "$PWD/bin/BuddyOffice-$V" "$PWD/apps/rsz-$V.app" | tail -1
done
cp PixelView.B.swift Sources/BuddyOffice/PixelView.swift
