import Testing
import Foundation
@testable import BuddyOffice

/// M13b：小鱼缸 / 宠物条 show() 原来先 orderFront 再渲染第一帧（render 开头的 guard panel.isVisible 也要等窗口出现之后的下一个节拍才画），
/// 小鱼缸会先露出一帧底色。任务书 6.6：窗口出现时先渲染好第一帧再显示。
@Suite struct PanelShowTests {
    @Test func aPanelThatIsNotOnScreenGetsItsFirstFrameBeforeItAppears() {
        var log: [String] = []
        PanelShow.show(isVisible: false, renderFirstFrame: { log.append("render") }, orderFront: { log.append("orderFront") })
        #expect(log == ["render", "orderFront"])
    }

    @Test func aPanelThatIsAlreadyOnScreenIsNotOrderedFrontAgain() {
        var log: [String] = []
        PanelShow.show(isVisible: true, renderFirstFrame: { log.append("render") }, orderFront: { log.append("orderFront") })
        #expect(!log.contains("orderFront"), "重复 orderFront 会把被别的窗口盖住的面板又提到前面")
    }

    @Test func aHiddenPanelIsRenderedOnlyWhenItsFirstFrameIsRequested() {
        #expect(PanelShow.shouldRender(isVisible: true, force: false))
        #expect(!PanelShow.shouldRender(isVisible: false, force: false), "没出现的面板：普通节拍不渲染（省 CPU）")
        #expect(PanelShow.shouldRender(isVisible: false, force: true), "出第一帧的时候必须渲染（原来 guard panel.isVisible 直接返回）")
    }
}
