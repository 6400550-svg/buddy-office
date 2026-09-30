import AppKit
import BuddyCore
import BuddyArt
import BuddyStage

/// 菜单栏图标：18 pt 像素模板图（正常 / 有人在忙）；有人等你时换成彩色的举手图标（不做模板）。
/// 菜单：每个 buddy 一行（状态图标、标题、当前动作，点击跳转）→ 各形态开关 → 演示模式 → 设置… → 退出。
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var lastKind: MenuBarIcon.Kind?
    weak var model: AppModel?
    var onJump: ((BuddySnapshot) -> Void)?

    func setVisible(_ v: Bool) {
        if v && item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item?.button?.imagePosition = .imageOnly
            let menu = NSMenu(); menu.delegate = self
            item?.menu = menu
            lastKind = nil; lastTip = ""
        } else if !v, let i = item { NSStatusBar.system.removeStatusItem(i); item = nil }
    }

    /// 当前菜单栏图标的种类名（自检日志用）。
    var currentKindName: String { lastKind.map { "\($0)" } ?? "无" }

    /// 菜单栏图标该是哪一种：有人等你 → 彩色举手；有人在忙 → 忙；否则正常。
    static func iconKind(waiting: Int, busy: Int) -> MenuBarIcon.Kind { waiting > 0 ? .waiting : (busy > 0 ? .busy : .normal) }
    static func tooltip(waiting: Int, busy: Int) -> String { waiting > 0 ? "\(waiting) 位同事在等你" : (busy > 0 ? "\(busy) 位同事在忙" : "Buddy 办公室") }
    private var lastTip = ""

    func update(waiting: Int, busy: Int) {
        guard let b = item?.button else { return }
        let kind = Self.iconKind(waiting: waiting, busy: busy)
        if kind != lastKind, let cg = MenuBarIcon.image(kind) {
            let img = NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
            img.isTemplate = (kind != .waiting)
            b.image = img
            lastKind = kind
        }
        let tip = Self.tooltip(waiting: waiting, busy: busy)
        if tip != lastTip { b.toolTip = tip; lastTip = tip }          // 只在变化时赋值（原来每 ≥ 0.09 秒赋一次）
    }

    // MARK: 菜单
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let m = model else { return }
        let people = m.present
        if people.isEmpty {
            let it = NSMenuItem(title: "今天还没人上班", action: nil, keyEquivalent: ""); it.isEnabled = false; menu.addItem(it)
        }
        for s in people {
            let glyph: String
            switch s.activity.phase { case .waiting: glyph = "🙋"; case .busy: glyph = "⌨️"; case .idle: glyph = s.unread ? "🚩" : "☕️" }
            let text = PlateCopy.activity(s, now: Date(), privacy: m.privacy)
            let it = ClosureMenuItem("\(glyph) \(AlertText.title(s.title, privacy: m.privacy))　\(text)") { [weak self] in self?.onJump?(s) }
            menu.addItem(it)
        }
        menu.addItem(.separator())
        func toggle(_ title: String, _ key: String) {
            let it = ClosureMenuItem(title) { [weak m] in guard let m = m else { return }; m.settings.set(!m.settings.bool(key), key) }
            it.state = m.settings.bool(key) ? .on : .off
            menu.addItem(it)
        }
        toggle("办公室窗口", "office.visible")
        toggle("小鱼缸", "tank.visible")
        toggle("桌面宠物", "strip.visible")
        toggle("菜单栏图标", "ui.menuBarIcon")
        toggle("Dock 图标", "ui.dockIcon")
        menu.addItem(.separator())
        let demo = ClosureMenuItem("演示模式（看看所有动作）") { [weak m] in m?.setDemo(!(m?.demo ?? false)) }
        demo.state = m.demo ? .on : .off
        menu.addItem(demo)
        menu.addItem(ClosureMenuItem("设置…", key: ",") { [weak m] in m?.showSettings() })
        menu.addItem(ClosureMenuItem("退出 Buddy 办公室", key: "q") { NSApp.terminate(nil) })
    }
}
