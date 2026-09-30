#!/bin/bash
# 开发用：包一层 swift build / swift test，补上命令行工具下找不到 Swift Testing 的那几个参数。
#
#   scripts/dev.sh build [swift build 的参数…]
#   scripts/dev.sh test  [swift test 的参数…]
#   scripts/dev.sh run   <product> [参数…]
#
# 注意（Claude Code 沙箱里）：SwiftPM 写文件要用到系统的用户临时目录，沙箱不允许，
# 所以 build / test 这两条要用 dangerouslyDisableSandbox 运行；产出的可执行文件本身可以在沙箱里跑。
#
# 环境变量：
#   BUDDY_PKG      要编译的包目录（默认项目根目录；数据层隔离包是 .dev/core）
#   BUDDY_SCRATCH  指定 --scratch-path（默认 .build），让两个人同时编译时互不锁死
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${BUDDY_PKG:-$ROOT}" || exit 1
CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
SCRATCH=()
[ -n "$BUDDY_SCRATCH" ] && SCRATCH=(--scratch-path "$BUDDY_SCRATCH")
cmd="$1"; shift
case "$cmd" in
  build)
    exec swift build "${SCRATCH[@]}" "$@" ;;
  test)
    exec swift test "${SCRATCH[@]}" \
      -Xswiftc -F$FW -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing \
      -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib "$@" ;;
  run)
    exec swift run "${SCRATCH[@]}" "$@" ;;
  *)
    echo "用法：scripts/dev.sh build|test|run [参数…]"; exit 2 ;;
esac
