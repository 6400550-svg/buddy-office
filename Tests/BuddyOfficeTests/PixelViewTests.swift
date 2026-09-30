import Testing
import AppKit
@testable import BuddyOffice

/// A-002：PixelView / PixelButton 上的鼠标按下不许被 AppKit 当成「窗口拖动」吞掉（isMovableByWindowBackground 的面板里，
/// mouseDownCanMoveWindow 默认等于 !isOpaque = true，视图的 mouseDown 收不到）。
@MainActor @Suite struct PixelViewTests {
    @Test func pixelViewAndTitleBarButtonsNeverLetAppKitStartAWindowDrag() {
        #expect(PixelView(frame: .zero).mouseDownCanMoveWindow == false)
        #expect(PixelButton(icon: "chrome.gear", tip: "设置").mouseDownCanMoveWindow == false)
        let bar = TitleBarButtonBar()
        for b in [bar.tank, bar.strip, bar.settings] { #expect(b.mouseDownCanMoveWindow == false) }
    }
}
