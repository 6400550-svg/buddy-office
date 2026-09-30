import Foundation

/// 面板出现的顺序（任务书 6.6「窗口出现时先渲染好第一帧再显示」）。
enum PanelShow {
    /// 这一帧要不要渲染：面板在屏幕上就渲染；还没出现的面板只有「要出第一帧」（force）才渲染。
    static func shouldRender(isVisible: Bool, force: Bool) -> Bool { isVisible || force }

    /// 显示一个面板：还没在屏幕上就先渲染好第一帧、再 orderFront（不然会先露出一帧底色）；已经在屏幕上不重复 orderFront。
    static func show(isVisible: Bool, renderFirstFrame: () -> Void, orderFront: () -> Void) {
        guard !isVisible else { return }
        renderFirstFrame()
        orderFront()
    }
}
