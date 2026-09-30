import AppKit
import BuddyStage
import PixelKit

/// 提示面板的最小接口（NotificationService 只认它，测试用假的记录调用）。
protocol ToastPresenting: AnyObject {
    var onClick: ((String) -> Void)? { get set }
    func show(key: String, kind: ToastCard.Kind, title: String, body: String)
    func dismiss(key: String)
}

/// 像素提示面板：系统通知没授权 / 被拒时的兜底。从右上角弹簧滑入，最多叠 3 张，6 秒后收回；点一下跳到对应会话。
final class ToastController: ToastPresenting {
    final class Toast {
        let key: String
        let panel = FloatingPanel(size: NSSize(width: 240, height: 60), level: .statusBar)
        let view = PixelView(frame: .zero)
        var born = CACurrentMediaTime()
        var spring = PixelSpring(value: 60, period: 0.36)
        var targetX = 0.0
        var leaving = false
        var size = NSSize.zero
        init(key: String) { self.key = key; panel.contentView = view }
    }
    private(set) var toasts: [Toast] = []
    private var timer: Timer?
    var onClick: ((String) -> Void)?
    var zoom = 2
    /// 把面板显示出来的动作（测试里换成只记录的，不真的弹窗口）。
    var orderFront: (NSPanel) -> Void = { $0.orderFrontRegardless() }

    func show(key: String, kind: ToastCard.Kind, title: String, body: String) { show(key: key, kind: kind, title: title, body: body, screen: nil) }
    func show(key: String, kind: ToastCard.Kind, title: String, body: String, screen: NSScreen?) {
        // 同一个 key 的旧提示直接替换
        toasts.filter { $0.key == key }.forEach { close($0) }
        let card = ToastCard.make(kind: kind, title: title, body: body, zoom: zoom)
        let t = Toast(key: key)
        t.size = NSSize(width: CGFloat(card.size.x * zoom), height: CGFloat(card.size.y * zoom))
        t.panel.setContentSize(t.size)
        t.view.frame = NSRect(origin: .zero, size: t.size)
        t.view.show(Frame(canvas: card.canvas, texts: card.texts), zoom: zoom)
        t.view.onClick = { [weak self, weak t] _, _ in if let t = t { self?.onClick?(t.key); self?.dismiss(t) } }
        t.panel.hasShadow = true
        t.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        toasts.insert(t, at: 0)
        if toasts.count > 3 { close(toasts.removeLast()) }
        // 起点在屏幕外右侧，弹簧滑到目标位置：先定弹簧的起点、再摆位置、最后才显示——不然面板会先出现在终点，要等下一拍 step 才跳到起点（闪一下，R2-002）
        t.spring.snap(to: Double(t.size.width) + 20)
        t.spring.target = 0
        layout(screen: screen)
        orderFront(t.panel)
        startTimer()
    }

    func dismiss(key: String) { toasts.filter { $0.key == key }.forEach { dismiss($0) } }
    func dismiss(_ t: Toast) { t.leaving = true; t.spring.target = Double(t.size.width) + 20 }
    private func close(_ t: Toast) { t.panel.orderOut(nil); toasts.removeAll { $0 === t } }

    private func layout(screen: NSScreen?) {
        let vf = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 800)
        var y = vf.maxY - 10
        // x 带上弹簧当前的偏移：重新排版（新提示卡到来）时不把正在滑入 / 离场的提示卡拽回终点
        for t in toasts { y -= t.size.height; t.targetX = Double(vf.maxX - t.size.width - 12); t.panel.setFrameOrigin(NSPoint(x: CGFloat(t.targetX + t.spring.value), y: y)); y -= 8 }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let tm = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(tm, forMode: .common); timer = tm
    }

    func step() {
        let now = CACurrentMediaTime()
        for t in toasts {
            if !t.leaving && now - t.born > 6 { dismiss(t) }
            let x = t.spring.step(1.0 / 60)
            t.panel.setFrameOrigin(NSPoint(x: CGFloat(t.targetX + Double(x)), y: t.panel.frame.minY))
            if t.leaving && abs(Double(x) - Double(t.size.width + 20)) < 2 { close(t) }
        }
        if toasts.isEmpty { timer?.invalidate(); timer = nil }
    }
}
