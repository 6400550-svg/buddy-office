import AppKit

/// 一块显示器的身份（ID 和名字）+ 位置。
struct ScreenInfo: Equatable {
    var id: UInt32
    var name: String
    var frame: NSRect
}

/// 桌面宠物的「显示在哪块屏幕」（任务书 7.1：主屏幕 / 鼠标所在的屏幕 / 指定某块屏幕，按 ID 和名字记住；被拔掉就回到主屏幕）。纯函数，测试直接喂。
/// 设置值：`main`（默认）、`mouse`、`id:<NSScreenNumber>|<名字>`（旧版本只写 `id:<n>` 也认）。
enum StripScreenPicker {
    static func choice(id: UInt32, name: String) -> String { "id:\(id)|\(name)" }

    static func parse(_ pref: String) -> (id: UInt32, name: String?)? {
        guard pref.hasPrefix("id:") else { return nil }
        let body = pref.dropFirst(3)
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let id = UInt32(first) else { return nil }
        return (id, parts.count > 1 ? String(parts[1]) : nil)
    }

    /// 选哪块屏幕（返回 screens 里的下标；screens 是 NSScreen.screens，第 0 块是主屏幕）：
    /// mouse → 鼠标所在的那块，找不到用主屏幕；id:… → 先按 ID 找，ID 变了（重新插拔显示器时可能变）就按名字找，都找不到（被拔掉了）→ 主屏幕；其余 → 主屏幕。
    static func pick(pref: String, screens: [ScreenInfo], mouse: NSPoint) -> Int {
        if pref == "mouse" { return screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0 }
        if let p = parse(pref) {
            if let i = screens.firstIndex(where: { $0.id == p.id }) { return i }
            if let n = p.name, !n.isEmpty, let i = screens.firstIndex(where: { $0.name == n }) { return i }
        }
        return 0
    }

    /// 设置页选择器的选项（标题, 值）。当前存的指定屏幕不在已连接的里面时保留一项「（未连接）」，这样选择器不会指向不存在的选项。
    static func options(current: String, screens: [ScreenInfo]) -> [(title: String, tag: String)] {
        var o: [(String, String)] = [("主屏幕", "main"), ("鼠标所在的屏幕", "mouse")]
        for s in screens { o.append(("显示器：\(s.name)", choice(id: s.id, name: s.name))) }
        if let p = parse(current), !o.contains(where: { $0.1 == current }) {
            // 同一块屏幕（ID 或名字对得上）换了写法（旧版本只存 ID）：也算已连接，不加「未连接」
            if let i = screens.firstIndex(where: { $0.id == p.id || ($0.name == p.name && p.name != nil) }) { o.append(("显示器：\(screens[i].name)", current)) }
            else { o.append(("显示器：\(p.name ?? "ID \(p.id)")（未连接）", current)) }
        }
        return o
    }
}
