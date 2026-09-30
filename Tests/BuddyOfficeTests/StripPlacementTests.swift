import Testing
import AppKit
@testable import BuddyOffice

/// A-006：桌面宠物「位置 / 显示在」改了立即生效；Dock 改大小 / 挪位置、鼠标换屏幕也要跟着挪（任务书 7.1：每 2 秒检查一次 visibleFrame）。
@Suite struct StripPlacementTests {
    static let vf = NSRect(x: 0, y: 80, width: 1400, height: 800)
    static let size = NSSize(width: 336, height: 280)

    @Test func rightLeftCenterAndUnknownAlignments() {
        let vf = Self.vf, sz = Self.size
        #expect(StripPanelController.origin(align: "right", visibleFrame: vf, panelSize: sz) == NSPoint(x: 1400 - 336 - 8, y: 80))
        #expect(StripPanelController.origin(align: "left", visibleFrame: vf, panelSize: sz) == NSPoint(x: 8, y: 80))
        #expect(StripPanelController.origin(align: "center", visibleFrame: vf, panelSize: sz) == NSPoint(x: 700 - 168, y: 80))
        #expect(StripPanelController.origin(align: "xyz", visibleFrame: vf, panelSize: sz) == StripPanelController.origin(align: "right", visibleFrame: vf, panelSize: sz))
        #expect(StripPanelController.origin(align: "", visibleFrame: vf, panelSize: sz) == StripPanelController.origin(align: "right", visibleFrame: vf, panelSize: sz))
        #expect(StripPanelController.origin(align: "left", visibleFrame: vf, panelSize: sz, margin: 20).x == 20)
        // 左边那块屏幕（原点是负数）、Dock 在左边（visibleFrame 的 minX 不为 0）、Dock 在下面很高
        let left = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        #expect(StripPanelController.origin(align: "right", visibleFrame: left, panelSize: sz) == NSPoint(x: -1440 + 1440 - 336 - 8, y: 0))
        let dockLeft = NSRect(x: 72, y: 0, width: 1328, height: 880)
        #expect(StripPanelController.origin(align: "left", visibleFrame: dockLeft, panelSize: sz).x == 80)
        #expect(StripPanelController.origin(align: "right", visibleFrame: NSRect(x: 0, y: 200, width: 1400, height: 700), panelSize: sz).y == 200)
    }

    /// 定位依据（位置 / 所在屏幕 / Dock 占掉的区域 / 条的大小）任何一个变了都要重新定位；什么都没变就不动（不每次都 setFrameOrigin）。
    @Test func anyChangeOfThePlacementInputsTriggersARepositionAndNothingElseDoes() {
        let base = StripPanelController.Placement(align: "right", screenFrame: NSRect(x: 0, y: 0, width: 1400, height: 900), visibleFrame: Self.vf, size: Self.size)
        #expect(StripPanelController.needsReposition(last: nil, now: base))
        #expect(!StripPanelController.needsReposition(last: base, now: base))
        var a = base; a.align = "left"
        #expect(StripPanelController.needsReposition(last: base, now: a), "设置里改了「位置」")
        var b = base; b.screenFrame = NSRect(x: 1400, y: 0, width: 1920, height: 1080); b.visibleFrame = NSRect(x: 1400, y: 60, width: 1920, height: 1000)
        #expect(StripPanelController.needsReposition(last: base, now: b), "改了「显示在」/ 鼠标换了一块屏幕")
        var c = base; c.visibleFrame = NSRect(x: 0, y: 40, width: 1400, height: 840)
        #expect(StripPanelController.needsReposition(last: base, now: c), "Dock 改了大小")
        var d = base; d.size = NSSize(width: 392, height: 280)
        #expect(StripPanelController.needsReposition(last: base, now: d), "来了新人，条变宽")
    }
}
