import Foundation
import BuddyCore
import BuddyStage

/// applySettings 的输入：决定「显示哪些入口」的那几项设置（已经套上命令行开发开关）。
struct FormInputs: Equatable {
    var office = false, tank = false, strip = false, menu = false, dock = false, hotkey = false
}

/// 办公室窗口此刻的状态（最小化 / 被 ⌘H 隐藏的窗口 isVisible 也是 false，但那不是「被关掉」）。
struct WindowState: Equatable {
    var isVisible = false, isMiniaturized = false, appHidden = false
}

enum EntryAction: Equatable { case show, hide }

/// 一次「应用设置」要做的事。
struct ApplyPlan: Equatable {
    var activationRegular: Bool?
    var office: EntryAction?
    var tank: EntryAction?
    var strip: EntryAction?
    var menuBar: EntryAction?
    var hotkey: EntryAction?
}

enum ApplyPlanner {
    /// 入口兜底：办公室 / 小鱼缸 / 菜单栏 / Dock 至少留一个，都关了就补上 Dock 图标。
    /// 只剩桌面宠物时：宠物条里有人才算入口（右键菜单里有「打开办公室」「设置…」）；一个人都没有时宠物条是一块点穿的空白，没有任何可点的地方，也补上 Dock 图标。
    /// initial（启动那一刻，第一批数据还没到）不按「宠物条是空的」处理——否则纯宠物用法每次启动都会多出一个 Dock 图标。快捷键不算入口（默认关）。
    static func entryFallback(_ f: FormInputs, stripHasBuddies: Bool, initial: Bool) -> FormInputs {
        var r = f
        let stripIsEntry = r.strip && (stripHasBuddies || initial)
        if !(r.office || r.tank || stripIsEntry || r.menu || r.dock) { r.dock = true }
        return r
    }

    /// 入口被强制补上 Dock 图标时，设置也要改过来：否则设置页显示「Dock 图标：关」而 Dock 里其实有图标（spec-trace-ui 疑点 11）。
    static func settingsWriteBack(raw: FormInputs, effective: FormInputs) -> [(key: String, value: Bool)] {
        effective.dock && !raw.dock ? [("ui.dockIcon", true)] : []
    }

    /// 相对上一次应用的设置，这一次要做什么：只处理有变化的部分（previous 为 nil = 启动时第一次，全做一遍）。
    /// 办公室窗口尤其如此：最小化 / 被隐藏的窗口 isVisible 也是 false，不能因为「没在显示」就把它弹回来——只有 office.visible 这个开关自己变了才去动窗口。
    /// window 只在这里留作接口（判定不再依赖窗口状态；测试用它证明最小化 / 隐藏都不会触发）。
    static func plan(previous: FormInputs?, current c: FormInputs, window: WindowState) -> ApplyPlan {
        _ = window
        func act(_ old: Bool?, _ new: Bool) -> EntryAction? { old == new ? nil : (new ? .show : .hide) }
        var p = ApplyPlan()
        if previous?.dock != c.dock { p.activationRegular = c.dock }
        p.office = act(previous?.office, c.office)
        p.tank = act(previous?.tank, c.tank)
        p.strip = act(previous?.strip, c.strip)
        p.menuBar = act(previous?.menu, c.menu)
        p.hotkey = act(previous?.hotkey, c.hotkey)
        return p
    }
}

/// A-011（App 层）：数据层给出的座位号必须落在 0..<64。
enum SeatSanitizer {
    static let maxSeats = Metrics.maxSeats

    /// 座位号不在 0..<64 的（被写坏的持久化座位号）改成最小的空位：按 key 排序依次拿，结果是确定的；其余人的座位不动。
    /// 空位不够（超过 64 个同时在场，几乎不可能）就保持原样——办公室不画他们，小鱼缸 / 宠物条 / 菜单仍然有。
    static func sanitize(_ snaps: [BuddySnapshot]) -> [BuddySnapshot] {
        let valid = 0..<maxSeats
        guard snaps.contains(where: { !valid.contains($0.seat) }) else { return snaps }
        var used = Set(snaps.filter { valid.contains($0.seat) }.map { $0.seat })
        var fixed: [String: Int] = [:]
        for s in snaps.filter({ !valid.contains($0.seat) }).sorted(by: { $0.key < $1.key }) {
            guard let free = valid.first(where: { !used.contains($0) }) else { break }
            used.insert(free); fixed[s.key] = free
        }
        return snaps.map { s in
            guard let seat = fixed[s.key] else { return s }
            var c = s; c.seat = seat; return c
        }
    }
}
