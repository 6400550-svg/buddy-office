import Testing
import AppKit
import PixelKit
import BuddyArt
@testable import BuddyOffice

/// A-002：小鱼缸「按住背景拖动」改成手动 performDrag 之后，单击小人 / 双击背景（回办公室）必须仍然收得到点击。
@MainActor @Suite struct PixelViewDragTests {
    @Test func onlyASingleClickOnTheBackgroundStartsAWindowDrag() {
        typealias A = PixelView.MouseDownAction
        #expect(PixelView.mouseDownAction(hitID: 0, clickCount: 1, dragsWindowOnBackground: true) == A.dragWindow)
        #expect(PixelView.mouseDownAction(hitID: 0, clickCount: 2, dragsWindowOnBackground: true) == A.click, "双击背景 = 回办公室，不是拖动")
        #expect(PixelView.mouseDownAction(hitID: 0, clickCount: 3, dragsWindowOnBackground: true) == A.click)
        #expect(PixelView.mouseDownAction(hitID: 2001, clickCount: 1, dragsWindowOnBackground: true) == A.click, "点到小人 = 跳转")
        #expect(PixelView.mouseDownAction(hitID: 0, clickCount: 1, dragsWindowOnBackground: false) == A.click, "办公室 / 宠物条 / 提示卡从来不拖")
    }

    /// 用合成的 NSEvent 走 PixelView.mouseDown（不需要窗口）：背景单击 → 交给窗口拖；小人 / 背景双击 → onClick。
    @Test func mouseDownRoutesBackgroundDragsAndBuddyClicksTheRightWay() throws {
        let view = PixelView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        view.dragsWindowOnBackground = true
        let c = Canvas(width: 20, height: 20)
        let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        c.fillRect(IntRect(2, 2, 6, 6), value: Pal.dx("floor.base"), style: st, id: 2001)        // 一个「小人」：美术像素 (2,2)–(8,8)
        view.show(Frame(canvas: c), zoom: 2)
        var dragged = 0
        var clicks: [Int] = []
        view.performDrag = { _ in dragged += 1 }
        view.onClick = { _, n in clicks.append(n) }
        func down(_ x: CGFloat, _ y: CGFloat, count: Int) throws {
            let loc = view.convert(NSPoint(x: x, y: y), to: nil)
            let ev = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: loc, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                      context: nil, eventNumber: 0, clickCount: count, pressure: 1))
            view.mouseDown(with: ev)
        }
        #expect(view.hitID(at: NSPoint(x: 10, y: 10)) == 2001)
        #expect(view.hitID(at: NSPoint(x: 30, y: 30)) == 0)
        try down(30, 30, count: 1)
        #expect(dragged == 1 && clicks.isEmpty, "背景单击：拖窗口，不算点击")
        try down(10, 10, count: 1)
        #expect(dragged == 1 && clicks == [1], "点到小人：走 onClick（跳转）")
        try down(30, 30, count: 2)
        #expect(dragged == 1 && clicks == [1, 2], "背景双击：走 onClick（回办公室）")
        view.dragsWindowOnBackground = false
        try down(30, 30, count: 1)
        #expect(dragged == 1 && clicks == [1, 2, 1], "不拖的视图：背景单击照常走 onClick")
    }
}
