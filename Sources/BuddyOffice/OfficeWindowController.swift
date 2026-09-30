import AppKit
import BuddyCore
import PixelKit
import BuddyStage

/// 办公室窗口：普通 NSWindow（可缩放，标题栏透明，内容铺满）。关闭只是隐藏，App 继续运行。
final class OfficeWindowController: NSWindowController, NSWindowDelegate {
    let pixelView = PixelView(frame: NSRect(x: 0, y: 0, width: 672, height: 678))
    let scene = OfficeScene()
    var zoom = 3
    var onClickSeat: ((Int) -> Void)?
    var onRightClick: ((Int?, NSEvent, NSView) -> Void)?
    /// 标题栏右侧的三个像素按钮（缩成小鱼缸 / 桌面宠物 / 设置）。
    let titleBar = TitleBarButtonsController()
    /// 上次退出时有没有存下窗口位置：有就按存的放，没有（第一次运行）才居中。
    private(set) var hadSavedFrame = false
    private var hoverSeat: Int?
    private var hoverSince = 0.0
    private var lastMouse: NSPoint?
    var forceRender = false
    var onWake: (() -> Void)?
    private var settingsGen = -1
    private var zoomSetting = 0
    private var labelMode = LabelMode.always
    private var appliedZoom = 0
    /// 现在需要出画面吗（窗口可见且没被完全挡住）。
    var wantsFrames: Bool {
        guard let w = window else { return false }
        return w.isVisible && (w.occlusionState.contains(.visible) || forceRender)
    }

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 672, height: 678),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: true)
        w.title = "Buddy 办公室"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentMinSize = NSSize(width: 200, height: 220)
        w.addTitlebarAccessoryViewController(titleBar)
        let frameName = "BuddyOfficeMainWindow"
        let saved = UserDefaults.standard.string(forKey: "NSWindow Frame \(frameName)") != nil
        w.setFrameAutosaveName(frameName)
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none            // AppKit 的窗口出现 / 消失动画在工作线程上跑 NSAnimation：快速 show / hide 时线程一路涨（B-010 的同类，R2-017）
        w.acceptsMouseMovedEvents = true
        super.init(window: w)
        hadSavedFrame = saved
        w.delegate = self
        pixelView.autoresizingMask = [.width, .height]
        w.contentView = pixelView
        w.backgroundColor = NSColor(calibratedRed: 0.17, green: 0.13, blue: 0.16, alpha: 1)
        pixelView.onHover = { [weak self] p in self?.lastMouse = p; self?.onWake?() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in self?.onWake?() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in self?.onWake?() }
        pixelView.onClick = { [weak self] p, _ in
            guard let self = self, let seat = OfficeScene.seat(fromHitID: self.pixelView.hitID(at: p)) else { return }
            self.onClickSeat?(seat)
        }
        pixelView.onRightClick = { [weak self] p, e in
            guard let self = self else { return }
            self.onRightClick?(OfficeScene.seat(fromHitID: self.pixelView.hitID(at: p)), e, self.pixelView)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        Settings.shared.set(false, "office.visible")
        return false
    }

    /// 内容区（点）→ 视口（美术像素）+ 缩放。返回这一帧画面有没有变化。
    @discardableResult
    func render(model: AppModel, force: Bool = false) -> Bool {
        guard let w = window else { return false }
        guard force || wantsFrames else { return false }
        let size = pixelView.bounds.size
        scene.director = model.director
        let present = model.present, dormant = model.dormant
        if settingsGen != model.settingsGen {
            settingsGen = model.settingsGen
            zoomSetting = model.settings.int("office.zoom")
            labelMode = { switch model.settings.string("ui.labels") { case "off": return .off; case "hover": return .hover; default: return .always } }()
        }
        let maxSeat = (present + dormant).map { $0.seat }.max() ?? -1
        let z = OfficeLayout.effectiveZoom(setting: zoomSetting, contentW: Double(size.width), contentH: Double(size.height), maxSeat: maxSeat, allowOne: (w.backingScaleFactor >= 2))
        zoom = z
        if appliedZoom != z { w.contentResizeIncrements = NSSize(width: CGFloat(z), height: CGFloat(z)); appliedZoom = z }
        let vw = max(40, Int(size.width) / z), vh = max(40, Int(size.height) / z)
        var opts = SceneOptions()
        opts.zoom = z
        opts.privacy = model.privacy
        opts.tally = model.settings.tallyToday()
        opts.directorIsExternal = true
        opts.emptySign = model.gotData
        opts.labels = labelMode
        // 悬停：鼠标停在某个人身上 250 ms 之后出卡片
        let seat = lastMouse.flatMap { OfficeScene.seat(fromHitID: pixelView.hitID(at: $0)) }
        if seat != hoverSeat { hoverSeat = seat; hoverSince = model.time }
        opts.hoverSeat = seat
        if let s = seat, model.time - hoverSince >= 0.25 { opts.hoverSnapshot = present.first { $0.seat == s } }
        let frame = scene.render(viewportW: vw, viewportH: vh, present: present, dormant: dormant, now: Date(), time: model.time, options: opts)
        return pixelView.show(frame, zoom: z)
    }
}
