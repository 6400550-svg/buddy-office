// 列出某个进程的窗口（层级 / 是否在屏幕上 / 位置 / 大小），不需要任何权限（只读窗口几何，不读内容）。
// 编译：CLANG_MODULE_CACHE_PATH=$TMPDIR/clang-mc swiftc -O scripts/winlist.swift -o /tmp/winlist    用法：winlist <pid>（pid 用 pgrep 在沙箱外查）
import Foundation
import CoreGraphics
// 列出属于某个 pid 的窗口（层级、位置、大小）。不需要任何权限（只读窗口的几何信息，不读内容）。
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { print("no list"); exit(1) }
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int32) == pid else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let x = b["X"] as? Double ?? 0, y = b["Y"] as? Double ?? 0, ww = b["Width"] as? Double ?? 0, hh = b["Height"] as? Double ?? 0
    if ww < 30 || hh < 30 { continue }
    print("layer=\(layer) onscreen=\(onscreen) x=\(Int(x)) y=\(Int(y)) w=\(Int(ww)) h=\(Int(hh))")
}
