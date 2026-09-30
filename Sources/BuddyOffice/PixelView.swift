import AppKit
import IOSurface
import PixelKit
import BuddyStage

/// 像素画布的显示视图：layer-backed，layer.contents 是按逻辑分辨率画好的 CGImage，
/// 用最近邻放大（magnificationFilter = .nearest），关掉隐式动画（否则系统会在两帧之间做交叉淡化，产生重影）。
/// 中文文字放在上面一层清晰的文字层里，按设备分辨率渲染。
final class PixelView: NSView {
    private let imageLayer = CALayer()
    private var textLayers: [CALayer] = []
    private struct TextKey: Equatable { var text = ""; var size: CGFloat = 0; var color = RGBA8(0, 0, 0, 0); var weight = FontWeightKind.regular; var scale: CGFloat = 0; var maxWidth: CGFloat = 0 }
    private var textKeys: [TextKey] = []
    private var textFrames: [CGRect] = []
    private var textShown: [Bool] = []
    private var lastTexts: [TextItem] = []
    private var lastTextViewport = IntRect(0, 0, 0, 0)
    private var lastTextZoom = 0
    private var lastTextScale: CGFloat = 0
    // 画布 → 屏幕：用 IOSurface（BGRA、共享内存）当图层内容，不再每帧建 CGImage 让 Core Animation 复制一遍。
    // 三块轮换，写之前确认没被合成器占用（isInUse），所以不会撕裂。窗口色彩空间已设为 sRGB，像素值原样显示。
    private var surfaces: [IOSurface] = []
    private var surfaceW = 0, surfaceH = 0, surfaceNext = 0
    /// 一共新建过几组（3 块一组）IOSurface：`--test-resize` 数这个（R2-016）。
    private(set) static var surfaceSetsAllocated = 0
    static let useSurfaces = !CommandLine.arguments.contains("--cgimage")
    private var lastHash: UInt64 = 0
    private var lastViewport = IntRect(0, 0, 0, 0)
    private var lastImageZoom = 0            // 缩放变了图像层的大小也要跟着变：局部重绘的场景画布没变时不会重新出图（R2-001）
    var zoom: Int = 3
    var backing: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// 当前帧的画布（命中测试用）和视口。
    private(set) var frame_: Frame?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.17, green: 0.13, blue: 0.16, alpha: 1).cgColor
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.contentsGravity = .resize
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        imageLayer.anchorPoint = .zero
        layer?.addSublayer(imageLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    /// 窗口的色彩空间设成 sRGB：我们出的图就是 sRGB，系统不用每帧在 CPU 上做颜色转换（这是实测里最大的一笔开销）。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.colorSpace = NSColorSpace.sRGB
    }
    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 桌面宠物条要完全透明（背景是用户自己的壁纸）。
    func makeTransparent() { layer?.backgroundColor = nil; layer?.isOpaque = false }

    // 鼠标事件统一从这里转给使用者（窗口 / 面板各自决定怎么处理）。坐标是视图坐标（左上原点，点）。
    var onHover: ((NSPoint?) -> Void)?
    var onClick: ((NSPoint, Int) -> Void)?
    var onRightClick: ((NSPoint, NSEvent) -> Void)?
    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseMoved(with event: NSEvent) { onHover?(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { onHover?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    /// 鼠标按下不许被 AppKit 当成「窗口拖动」：`mouseDownCanMoveWindow` 默认等于 !isOpaque（= true），在 isMovableByWindowBackground 的面板里，
    /// 落在这种视图上的左键按下会被当成拖动的起点、视图的 mouseDown 根本收不到——点小人跳转、双击回办公室都会失灵。
    override var mouseDownCanMoveWindow: Bool { false }
    /// 小鱼缸「按住背景拖动」：不再靠 isMovableByWindowBackground，改成在这里手动做——按下的地方不是小人（对象 ID 为 0）、又是单击，才把这次按下交给窗口去拖；
    /// 点到小人 / 双击照常走 onClick（跳转 / 回办公室）。
    var dragsWindowOnBackground = false
    /// 测试可以替换（默认 window?.performDrag）。
    var performDrag: ((NSEvent) -> Void)?
    enum MouseDownAction: Equatable { case click, dragWindow }
    static func mouseDownAction(hitID: UInt16, clickCount: Int, dragsWindowOnBackground: Bool) -> MouseDownAction {
        (dragsWindowOnBackground && hitID == 0 && clickCount == 1) ? .dragWindow : .click
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if Self.mouseDownAction(hitID: hitID(at: p), clickCount: event.clickCount, dragsWindowOnBackground: dragsWindowOnBackground) == .dragWindow {
            if let f = performDrag { f(event) } else { window?.performDrag(with: event) }
            return
        }
        onClick?(p, event.clickCount)
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(convert(event.locationInWindow, from: nil), event) }

    /// 显示一帧。没变化就跳过（不重建 CGImage）。返回是否真的更新了。
    @discardableResult
    func show(_ frame: Frame, zoom z: Int, force: Bool = false) -> Bool {
        frame_ = frame
        zoom = z
        let vp = frame.viewport
        var changed = force
        // 一次事务里做完图和文字：Core Animation 每提交一次事务就要给渲染服务发一次消息
        var inTx = false
        func begin() { if !inTx { CATransaction.begin(); CATransaction.setDisableActions(true); inTx = true } }
        var needImage = false
        var newHash: UInt64 = 0
        if frame.changeKnown {
            // 局部重绘的场景已经知道这一帧变没变：不用再哈希
            needImage = frame.canvasChanged || vp != lastViewport || lastHash == 0 || z != lastImageZoom
        } else {
            var pt = Prof.begin()
            newHash = frame.canvas.contentHash() ^ UInt64(bitPattern: Int64(vp.x &* 31 &+ vp.y &* 131 &+ vp.w &* 7 &+ vp.h))
            Prof.end("show.hash", pt)
            needImage = newHash != lastHash || vp != lastViewport || z != lastImageZoom
            pt = 0
        }
        if needImage {
            let pt = Prof.begin()
            if PixelView.useSurfaces, let surf = nextSurface(w: PixelView.bucket(vp.w), h: PixelView.bucket(vp.h)) {
                surf.lock(options: [], seed: nil)
                frame.canvas.writeBGRA(into: surf.baseAddress, bytesPerRow: surf.bytesPerRow, crop: vp)     // 只写左上角 vp.w × vp.h 这一块（surface 可能比视口大）
                surf.unlock(options: [], seed: nil)
                Prof.end("show.image", pt)
                begin()
                imageLayer.contents = surf
                imageLayer.contentsRect = CGRect(x: 0, y: 0, width: CGFloat(vp.w) / CGFloat(surf.width), height: CGFloat(vp.h) / CGFloat(surf.height))     // 只显示视口那一块
                imageLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(vp.w * z), height: CGFloat(vp.h * z))
                imageLayer.contentsScale = 1
                lastHash = newHash == 0 ? 1 : newHash; lastViewport = vp; lastImageZoom = z; changed = true
            } else if let img = frame.canvas.makeDisplayImage(crop: vp) {
                Prof.end("show.image", pt)
                begin()
                imageLayer.contents = img
                imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                imageLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(vp.w * z), height: CGFloat(vp.h * z))
                imageLayer.contentsScale = 1
                lastHash = newHash == 0 ? 1 : newHash; lastViewport = vp; lastImageZoom = z; changed = true
            }
        }
        let pt = Prof.begin()
        if updateTexts(frame.texts, viewport: vp, begin: begin) { changed = true }
        Prof.end("show.texts", pt)
        if inTx { let pc = Prof.begin(); CATransaction.commit(); Prof.end("show.commit", pc) }
        return changed
    }

    /// surface 的宽高向上取整到 64 的倍数（「桶」）：拖窗口边缘时视口每一步都不一样，原来每一步都新建 3 块 IOSurface（一次拖动上百组内核对象；
    /// 复查员在测试宿主进程里还量到 CoreAnimation 长期保留用过的 surface：300 步 57 → 261 MB）；现在只在跨桶时才重建（约 1/10），用 `contentsRect` 裁出视口那一块。
    /// 真实 App 里复测（`--test-resize`，QA/evidence/resize）没有看到保留：占用与新建组数无关，这一改动是降开销 / 防万一（R2-016）。
    static func bucket(_ n: Int) -> Int { max(64, (n + 63) / 64 * 64) }

    /// 下一块可以写的 IOSurface（尺寸变了就重建）；三块都还在被合成器用着时返回 nil，这一帧退回 CGImage 路径。
    private func nextSurface(w: Int, h: Int) -> IOSurface? {
        if surfaceW != w || surfaceH != h || surfaces.isEmpty {
            surfaces = (0..<3).compactMap { _ in
                IOSurface(properties: [.width: w, .height: h, .bytesPerElement: 4, .pixelFormat: 0x42475241 as UInt32])
            }
            surfaceW = w; surfaceH = h; surfaceNext = 0
            PixelView.surfaceSetsAllocated += 1
            if surfaces.count < 3 { surfaces = [] ; return nil }
        }
        for i in 0..<surfaces.count {
            let k = (surfaceNext + i) % surfaces.count
            if !surfaces[k].isInUse { surfaceNext = (k + 1) % surfaces.count; return surfaces[k] }
        }
        return nil
    }

    /// 文字层：每段文字一个 CALayer。文字、样式、位置都没变时什么都不做（不开事务、不碰图层）。
    @discardableResult
    private func updateTexts(_ texts: [TextItem], viewport vp: IntRect, begin: () -> Void) -> Bool {
        let scale = backing
        // 先按「排版输入」判断有没有变：文字内容 / 位置 / 视口 / 缩放都一样就整段跳过
        if vp == lastTextViewport, zoom == lastTextZoom, scale == lastTextScale, texts.count == lastTexts.count {
            var same = true
            for i in 0..<texts.count {
                let a = texts[i], b = lastTexts[i]
                if a.text != b.text || a.x != b.x || a.y != b.y || a.maxWidth != b.maxWidth || a.align != b.align || a.style != b.style { same = false; break }
            }
            if same { return false }
        }
        lastTexts = texts; lastTextViewport = vp; lastTextZoom = zoom; lastTextScale = scale
        begin()
        // 图层数量对齐
        while textLayers.count < texts.count {
            let l = CALayer()
            l.anchorPoint = .zero
            l.magnificationFilter = .nearest
            l.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
            layer?.addSublayer(l); textLayers.append(l); textKeys.append(TextKey()); textFrames.append(.zero); textShown.append(false)
        }
        for i in 0..<textLayers.count {
            if i >= texts.count {
                if textShown[i] { textLayers[i].isHidden = true; textShown[i] = false }
                continue
            }
            let t = texts[i]
            guard let ti = TextRenderer.shared.image(t.text, style: t.style, scale: scale, maxWidth: t.maxWidth) else {
                if textShown[i] { textLayers[i].isHidden = true; textShown[i] = false }
                continue
            }
            if !textShown[i] { textLayers[i].isHidden = false; textShown[i] = true }
            // 位置由 TextLayout.place 算（设备像素取整）；这里换回点。窗口和 text-audit 用的是同一个函数
            let p = TextLayout.place(t, imageSize: ti.size, viewport: vp, zoom: zoom, scale: Int(scale.rounded()))
            let f = CGRect(x: p.minX / scale, y: p.minY / scale, width: ti.size.width, height: ti.size.height)
            let key = TextKey(text: t.text, size: t.style.size, color: t.style.color, weight: t.style.weight, scale: scale, maxWidth: t.maxWidth)
            if key != textKeys[i] { textLayers[i].contents = ti.image; textLayers[i].contentsScale = scale; textKeys[i] = key }
            if f != textFrames[i] { textLayers[i].frame = f; textFrames[i] = f }
        }
        return true
    }

    /// 视图坐标（点，左上原点）→ 画布美术像素。
    func artPoint(_ p: NSPoint) -> (Int, Int)? {
        guard let f = frame_, zoom > 0 else { return nil }
        let x = Int((p.x / CGFloat(zoom)).rounded(.down)) + f.viewport.x
        let y = Int((p.y / CGFloat(zoom)).rounded(.down)) + f.viewport.y
        return (x, y)
    }

    /// 命中：返回这个位置的对象 ID（外扩 1 像素）。
    func hitID(at p: NSPoint, dilate: Bool = true) -> UInt16 {
        guard let f = frame_, let (x, y) = artPoint(p) else { return 0 }
        return f.canvas.hitID(x: x, y: y, dilate: dilate)
    }
}
