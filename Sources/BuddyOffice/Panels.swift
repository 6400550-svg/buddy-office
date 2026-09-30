import AppKit
import BuddyCore
import PixelKit
import BuddyStage

/// 不抢焦点的浮动面板：无边框、nonactivating，永远不会成为 key / main 窗口。
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(size: NSSize, level: NSWindow.Level = .floating) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        // 关掉 AppKit 的窗口出现 / 消失动画：这些面板（提示卡、悬停卡、小鱼缸、宠物条）自己用弹簧滑动 / 直接显示隐藏，
        // 而 AppKit 的 order-in / order-out 动画在 GCD 工作线程上跑 `-[NSAnimation _runBlocking]`，面板被反复 setFrameOrigin 时它永远不返回——
        // 每弹一张提示卡就永久占住一个线程（replay 长跑里线程数 14 → 53 一路涨，QA 抓到）。
        animationBehavior = .none
    }
}

/// 小鱼缸、桌面宠物条用的悬停卡片窗口：永远不拦截鼠标。
final class HoverPanelController {
    let panel = FloatingPanel(size: NSSize(width: 200, height: 100), level: .statusBar)
    let view = PixelView(frame: .zero)
    /// 卡片内容由这几样决定（时间只到秒：卡片里的用时 / 已开多久每秒才变一次）：没变就不重建整张卡片（小鱼缸每个 tick / 宠物条 30 Hz 轮询都会调 show）。
    struct CardKey: Equatable {
        var snapshot: BuddySnapshot
        var second: Int
        var zoom: Int
        var privacy: Bool
        init(_ s: BuddySnapshot, now: Date, zoom: Int, privacy: Bool) { snapshot = s; second = safeInt(now.timeIntervalSince1970); self.zoom = zoom; self.privacy = privacy }
    }
    private var lastKey: CardKey?
    private var lastSize = NSSize.zero
    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = view
        view.wantsLayer = true
        view.makeTransparent()
    }
    /// anchor：被悬停的东西在屏幕上的矩形（屏幕坐标，左下原点）。卡片放在它上方，越界就翻到下方 / 收回屏幕内。
    func show(_ s: BuddySnapshot, now: Date, zoom: Int, privacy: Bool, anchor: NSRect, screen: NSScreen?) {
        let key = CardKey(s, now: now, zoom: zoom, privacy: privacy)
        var size = lastSize
        if key != lastKey {
            let card = HoverCard.make(s, now: now, zoom: zoom, privacy: privacy)
            size = NSSize(width: CGFloat(card.size.x * zoom), height: CGFloat(card.size.y * zoom))
            if panel.frame.size != size { panel.setContentSize(size) }
            view.frame = NSRect(origin: .zero, size: size)
            view.show(Frame(canvas: card.canvas, texts: card.texts), zoom: zoom)
            lastKey = key; lastSize = size
        }
        let vf = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 800)
        var x = anchor.midX - size.width / 2
        var y = anchor.maxY + 6
        if y + size.height > vf.maxY { y = anchor.minY - size.height - 6 }
        x = max(vf.minX + 4, min(x, vf.maxX - size.width - 4))
        y = max(vf.minY + 4, min(y, vf.maxY - size.height - 4))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { if panel.isVisible { panel.orderOut(nil) }; lastKey = nil }
}

/// 一个简单的「点击就执行闭包」的菜单项。
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
