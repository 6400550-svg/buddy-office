import AppKit
import BuddyCore
import PixelKit
import BuddyStage

/// 小鱼缸：置顶的小窗，紧凑的办公室。按住背景可拖动；双击回到办公室；不抢焦点。
final class TankPanelController: NSObject {
    let panel = FloatingPanel(size: NSSize(width: 200, height: 140))
    let pixelView = PixelView(frame: .zero)
    let scene = TankScene()
    let hover = HoverPanelController()
    var zoom = 2
    var onClickBuddy: ((BuddySnapshot) -> Void)?
    var onDoubleClickBackground: (() -> Void)?
    var onRightClick: ((Int?, NSEvent, NSView) -> Void)?
    private var hoverSlot: Int?
    private var hoverSince = 0.0
    private var lastMouse: NSPoint?
    private var seatsBySlot: [Int: BuddySnapshot] = [:]
    private var settingsGen = -1
    /// 上次有没有存下位置（有就用存的；没有 = 第一次，放在屏幕右上角）。只在第一次出画面时放置一次。
    private var hadSavedFrame = false
    private var placed = false

    override init() {
        super.init()
        let frameName = "BuddyOfficeTankPanel"
        hadSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(frameName)") != nil
        panel.setFrameAutosaveName(frameName)
        panel.isMovableByWindowBackground = false           // 不用 AppKit 的「按住背景拖动」（它会吞掉视图的点击），由 PixelView 在背景上手动 performDrag
        pixelView.dragsWindowOnBackground = true
        panel.hasShadow = true
        panel.contentView = pixelView
        pixelView.wantsLayer = true
        pixelView.layer?.cornerRadius = 8
        pixelView.layer?.masksToBounds = true
        pixelView.onHover = { [weak self] p in self?.lastMouse = p }
        pixelView.onClick = { [weak self] p, n in self?.click(p, count: n) }
        pixelView.onRightClick = { [weak self] p, e in
            guard let self = self else { return }
            self.onRightClick?(self.slot(at: p).flatMap { self.seatsBySlot[$0]?.seat }, e, self.pixelView)
        }
    }

    var isVisible: Bool { panel.isVisible }
    /// 先渲染好第一帧再把面板显示出来（不然会先露出一帧底色；任务书 6.6）。
    func show(model: AppModel) {
        PanelShow.show(isVisible: panel.isVisible, renderFirstFrame: { render(model: model, force: true) }, orderFront: { panel.orderFrontRegardless() })
    }
    func hide() { panel.orderOut(nil); hover.hide() }

    func slot(at p: NSPoint) -> Int? {
        let id = pixelView.hitID(at: p, dilate: true)
        return id >= 2000 && id < 3000 ? Int(id) - 2000 : nil
    }

    func click(_ p: NSPoint, count: Int) {
        if let s = slot(at: p), let snap = seatsBySlot[s] { onClickBuddy?(snap) }
        else if count >= 2 { onDoubleClickBackground?() }
    }

    @discardableResult
    func render(model: AppModel, force: Bool = false) -> Bool {
        guard PanelShow.shouldRender(isVisible: panel.isVisible, force: force) else { return false }
        if settingsGen != model.settingsGen {
            settingsGen = model.settingsGen
            zoom = max(1, min(2, model.settings.int("tank.zoom")))
            let a = CGFloat(max(0.3, min(1, model.settings.double("tank.opacity"))))
            if panel.alphaValue != a { panel.alphaValue = a }
        }
        let present = model.present
        seatsBySlot = Dictionary(uniqueKeysWithValues: present.prefix(8).enumerated().map { ($0.offset, $0.element) })
        let frame = scene.render(director: model.director, present: present, now: Date(), time: model.time, privacy: model.privacy, zoom: zoom, emptySign: model.gotData)
        let size = NSSize(width: CGFloat(frame.canvas.width * zoom), height: CGFloat(frame.canvas.height * zoom))
        if pixelView.frame.size != size {
            // 人数变了、窗口跟着变大 / 变小：上边缘不动；靠右的窗口右边缘不动（向左长），靠左的左边缘不动；不许长出屏幕
            let old = panel.frame
            let vf = (panel.screen ?? NSScreen.main)?.visibleFrame
            panel.setContentSize(size)
            let nw = panel.frame.width, nh = panel.frame.height
            var x = old.minX, y = old.maxY - nh
            if let vf = vf {
                if old.midX > vf.midX { x = old.maxX - nw }
                x = max(vf.minX, min(x, vf.maxX - nw)); y = max(vf.minY, min(y, vf.maxY - nh))
            }
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            pixelView.frame = NSRect(origin: .zero, size: size)
        }
        if !placed {
            placed = true
            // 第一次：放在主屏幕右上角（菜单栏下面）；存过的位置如果已经不在任何屏幕上（拔掉了外接屏），也放回右上角
            let f = panel.frame
            let visible = NSScreen.screens.contains { let r = $0.visibleFrame.intersection(f); return r.width >= 40 && r.height >= 40 }
            if (!hadSavedFrame || !visible), let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: vf.maxX - f.width - 16, y: vf.maxY - f.height - 16))
            }
        }
        let changed = pixelView.show(frame, zoom: zoom)
        // 悬停：停 250 ms 出卡片
        let slotNow = lastMouse.flatMap { slot(at: $0) }
        if slotNow != hoverSlot { hoverSlot = slotNow; hoverSince = model.time; hover.hide() }
        if let s = hoverSlot, let snap = seatsBySlot[s], model.time - hoverSince >= 0.25 {
            let f = panel.frame
            let x = f.minX + CGFloat((TankScene.margin + (s % max(1, TankScene.layout(count: present.count).cols)) * TankScene.cellW) * zoom)
            let anchor = NSRect(x: x, y: f.minY, width: CGFloat(TankScene.cellW * zoom), height: f.height)
            hover.show(snap, now: Date(), zoom: 2, privacy: model.privacy, anchor: anchor, screen: panel.screen)
        }
        return changed
    }
}
