import AppKit
import BuddyCore
import PixelKit
import BuddyStage

/// 桌面宠物条：透明、无边框、不抢焦点，坐在屏幕底部（Dock 上方）。
/// 点穿：宠物条显示时每秒 30 次读 NSEvent.mouseLocation（鼠标离得远于 100 pt 降到 10 次），
/// 用对象 ID 缓冲做像素级命中（外扩 1 像素）来切换 ignoresMouseEvents。不需要辅助功能权限。
final class StripPanelController: NSObject {
    let panel = FloatingPanel(size: NSSize(width: 336, height: 280))
    let pixelView = PixelView(frame: .zero)
    let scene = StripScene()
    let hover = HoverPanelController()
    var zoom = 2
    var onClickBuddy: ((BuddySnapshot) -> Void)?
    var onRightClick: ((Int?, NSEvent, NSView) -> Void)?
    private var timer: Timer?
    private var hoverSlot: Int?
    private var hoverSince = 0.0
    private var slotSeats: [Int: BuddySnapshot] = [:]
    private var lastFar = true
    private var pollTick = 0
    private var lastFrameSize = NSSize.zero
    private(set) var toggles = 0
    var model: AppModel?
    private var settingsGen = -1

    override init() {
        super.init()
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.contentView = pixelView
        pixelView.makeTransparent()
        pixelView.onClick = { [weak self] p, _ in
            guard let self = self, let s = self.slot(at: p), let snap = self.slotSeats[s] else { return }
            self.onClickBuddy?(snap)
        }
        pixelView.onRightClick = { [weak self] p, e in
            guard let self = self else { return }
            self.onRightClick?(self.slot(at: p).flatMap { self.slotSeats[$0]?.seat }, e, self.pixelView)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    var isVisible: Bool { panel.isVisible }
    /// 先渲染好第一帧再把面板显示出来（任务书 6.6）。
    func show(model: AppModel) {
        PanelShow.show(isVisible: panel.isVisible, renderFirstFrame: { render(model: model, force: true) }, orderFront: { panel.orderFrontRegardless() })
        startPolling()
    }
    func hide() { panel.orderOut(nil); hover.hide(); timer?.invalidate(); timer = nil }

    @objc func screensChanged() { reposition() }

    func slot(at p: NSPoint) -> Int? {
        let id = pixelView.hitID(at: p, dilate: true)
        return StripScene.slot(fromHitID: id)
    }

    // MARK: 点穿
    func startPolling() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        guard panel.isVisible else { return }
        pollTick += 1
        if pollTick % 15 == 0 { repositionIfNeeded() }        // 每 0.5 秒看一眼：鼠标换了屏幕（「鼠标所在的屏幕」）/ Dock 改了大小或挪了位置
        let loc = NSEvent.mouseLocation
        let near = panel.frame.insetBy(dx: -100, dy: -100).contains(loc)
        // 远处降到 10 次/秒
        if !near && pollTick % 3 != 0 { return }
        _ = evaluate(at: loc)
    }

    /// 给定屏幕坐标下的鼠标位置：命中不透明像素（外扩 1 像素）就拦截，否则点穿；同时驱动悬停卡片。返回是否点穿。
    @discardableResult
    func evaluate(at loc: NSPoint) -> Bool {
        let f = panel.frame
        var id: UInt16 = 0
        var hovered: Int? = nil
        if f.insetBy(dx: -2, dy: -2).contains(loc) {
            let p = NSPoint(x: loc.x - f.minX, y: f.maxY - loc.y)     // 视图坐标（左上原点）
            id = pixelView.hitID(at: p, dilate: true)
            hovered = StripScene.slot(fromHitID: id)
        }
        let shouldIgnore = (id == 0)
        if panel.ignoresMouseEvents != shouldIgnore { panel.ignoresMouseEvents = shouldIgnore; toggles += 1 }
        // 悬停卡片
        let t = model?.time ?? 0
        if hovered != hoverSlot { hoverSlot = hovered; hoverSince = t; hover.hide() }
        if let s = hoverSlot, let snap = slotSeats[s], t - hoverSince >= 0.25, let m = model {
            let x = f.minX + CGFloat(scene.slotX(s) * zoom)
            let anchor = NSRect(x: x, y: f.minY, width: CGFloat(Metrics.cellW * zoom), height: CGFloat((StripScene.cellH + 8) * zoom))
            hover.show(snap, now: Date(), zoom: 2, privacy: m.privacy, anchor: anchor, screen: panel.screen)
        }
        return shouldIgnore
    }

    // MARK: 位置（Dock 上方；多屏；Dock 移动 / 改大小）
    static func info(_ s: NSScreen) -> ScreenInfo {
        ScreenInfo(id: (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0, name: s.localizedName, frame: s.frame)
    }
    func targetScreen(_ model: AppModel) -> NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main ?? NSScreen() }
        return screens[StripScreenPicker.pick(pref: model.settings.string("strip.screen"), screens: screens.map(Self.info), mouse: NSEvent.mouseLocation)]
    }

    /// 宠物条左下角在屏幕上的位置：贴着 visibleFrame 的底边（正好在 Dock 上方）；靠右 / 靠左留 margin，居中对齐 visibleFrame 的中线，认不出的取值按靠右。
    static func origin(align: String, visibleFrame vf: NSRect, panelSize: NSSize, margin: CGFloat = 8) -> NSPoint {
        let x: CGFloat
        switch align {
        case "left": x = vf.minX + margin
        case "center": x = vf.midX - panelSize.width / 2
        default: x = vf.maxX - panelSize.width - margin
        }
        return NSPoint(x: x, y: vf.minY)
    }

    /// 宠物条位置由这些量决定：它们变了才需要重新定位。
    struct Placement: Equatable {
        var align: String
        var screenFrame: NSRect
        var visibleFrame: NSRect
        var size: NSSize
    }
    static func needsReposition(last: Placement?, now: Placement) -> Bool { last != now }
    private var lastPlacement: Placement?
    private func placement(on scr: NSScreen, _ m: AppModel) -> Placement {
        Placement(align: m.settings.string("strip.align"), screenFrame: scr.frame, visibleFrame: scr.visibleFrame, size: panel.frame.size)
    }

    func reposition() {
        guard let m = model else { return }
        let scr = targetScreen(m)
        panel.setFrameOrigin(Self.origin(align: m.settings.string("strip.align"), visibleFrame: scr.visibleFrame, panelSize: panel.frame.size))
        lastPlacement = placement(on: scr, m)
    }
    /// 定位依据变了才重新定位：设置里改了「位置 / 显示在」、鼠标所在的屏幕换了、Dock 改了大小 / 挪了位置（这些时候屏幕参数通知不一定会来）。
    func repositionIfNeeded() {
        guard let m = model else { return }
        if Self.needsReposition(last: lastPlacement, now: placement(on: targetScreen(m), m)) { reposition() }
    }

    func applyLevel(_ model: AppModel) {
        if model.settings.string("strip.level") == "desktop" {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        } else { panel.level = .floating }
        var cb: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if model.settings.bool("strip.fullscreen") { cb.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = cb
    }

    @discardableResult
    func render(model: AppModel, force: Bool = false) -> Bool {
        guard PanelShow.shouldRender(isVisible: panel.isVisible, force: force) else { return false }
        self.model = model
        if settingsGen != model.settingsGen {
            settingsGen = model.settingsGen
            zoom = max(1, min(3, model.settings.int("strip.zoom")))
            applyLevel(model)
            repositionIfNeeded()          // 「位置」「显示在」改了立刻生效（原来只有条的大小变了才会重新定位）
        }
        let present = model.present
        slotSeats = Dictionary(uniqueKeysWithValues: present.prefix(8).enumerated().map { ($0.offset, $0.element) })
        scene.alignRight = model.settings.string("strip.align") == "right"        // 靠右：新来的人从左边长出来，已经坐着的人不动
        let frame = scene.render(director: model.director, present: present, now: Date(), time: model.time, privacy: model.privacy)
        let size = NSSize(width: CGFloat(frame.canvas.width * zoom), height: CGFloat(frame.canvas.height * zoom))
        if size != lastFrameSize {
            lastFrameSize = size
            panel.setContentSize(size)
            pixelView.frame = NSRect(origin: .zero, size: size)
            reposition()
        }
        return pixelView.show(frame, zoom: zoom)
    }
}
