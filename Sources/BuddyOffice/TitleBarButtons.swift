import AppKit
import BuddyArt
import PixelKit

/// 办公室窗口标题栏右侧的三个像素按钮（任务书 7.1）：缩成小鱼缸 / 桌面宠物 / 设置。
/// 每个按钮 12×12 美术像素（一个美术像素 = 2 pt，所以 24 pt 见方），木牌底板 + 10×10 的图标；
/// 悬停变亮、按下去图标下沉一格、对应的形态开着的时候底板是金色描边。
final class TitleBarButtonsController: NSTitlebarAccessoryViewController {
    let bar = TitleBarButtonBar()
    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
        view = bar
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class TitleBarButtonBar: NSView {
    static let buttonSize: CGFloat = 24, gap: CGFloat = 4, margin: CGFloat = 10, barHeight: CGFloat = 28
    let tank = PixelButton(icon: "chrome.tank", tip: "缩成小鱼缸（置顶小窗；双击小鱼缸的背景可以回到办公室）")
    let strip = PixelButton(icon: "chrome.strip", tip: "桌面宠物：在屏幕底部（Dock 上方）开 / 关")
    let settings = PixelButton(icon: "chrome.gear", tip: "设置…")

    init() {
        let w = Self.margin * 2 + Self.buttonSize * 3 + Self.gap * 2
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: Self.barHeight))
        for (i, b) in [tank, strip, settings].enumerated() {
            b.frame = NSRect(x: Self.margin + CGFloat(i) * (Self.buttonSize + Self.gap), y: (Self.barHeight - Self.buttonSize) / 2,
                             width: Self.buttonSize, height: Self.buttonSize)
            b.autoresizingMask = [.minYMargin, .maxYMargin]          // 标题栏比 28 pt 高（32 pt）时按钮仍然垂直居中
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 对应的形态现在开着吗：开着的按钮底板是金色描边。
    func update(tankOn: Bool, stripOn: Bool) {
        if tank.on != tankOn { tank.on = tankOn }
        if strip.on != stripOn { strip.on = stripOn }
    }
}

/// 一个像素按钮：自己画（最近邻放大，不糊），悬停 / 按下 / 亮着三种状态。
final class PixelButton: NSView {
    let icon: String
    var on = false { didSet { if on != oldValue { needsDisplay = true } } }
    var onClick: (() -> Void)?
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }

    init(icon: String, tip: String) {
        self.icon = icon
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 标题栏里的按钮：按下就是点击，不许被 AppKit 当成「窗口拖动」吞掉（NSView 默认 mouseDownCanMoveWindow == !isOpaque == true）。
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let fire = pressed && inside
        pressed = false
        if fire { onClick?() }
    }

    private static var cache: [String: NSImage] = [:]
    static func image(icon: String, state: ChromeArt.State, scale: CGFloat) -> NSImage? {
        let key = "\(icon)/\(state.rawValue)/\(scale)"
        if let c = cache[key] { return c }
        let canvas = ChromeArt.button(icon: icon, state: state)
        guard let cg = FrameRenderer.render(Frame(canvas: canvas), zoom: 2, scale: Int(scale.rounded())) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: 24, height: 24))
        cache[key] = img
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        let state: ChromeArt.State = pressed ? .pressed : (on ? .on : (hovering ? .hover : .normal))
        guard let img = Self.image(icon: icon, state: state, scale: window?.backingScaleFactor ?? 2) else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
}
