import Testing
import AppKit
@testable import BuddyOffice

/// B-007：桌面宠物「指定某块屏幕（按 ID 和名字记住）」——设置页原来只有「主屏幕」「鼠标所在的屏幕」，代码只认 id:<n> 且没有入口（spec-trace-ui U26c）。
@Suite struct ScreenPickerTests {
    static let main = ScreenInfo(id: 1, name: "内建视网膜显示器", frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
    static let left = ScreenInfo(id: 22, name: "DELL U2723QE", frame: NSRect(x: -2560, y: 0, width: 2560, height: 1440))
    static let right = ScreenInfo(id: 33, name: "LG HDR 4K", frame: NSRect(x: 1440, y: -200, width: 3840, height: 2160))
    static let all = [main, left, right]

    @Test func mainAndUnknownValuesUseThePrimaryScreen() {
        for pref in ["main", "", "xyz", "id:", "id:abc", "id:99999999999", "ID:1", "mouse2"] {
            #expect(StripScreenPicker.pick(pref: pref, screens: Self.all, mouse: NSPoint(x: 100, y: 100)) == 0, "\(pref)")
        }
        #expect(StripScreenPicker.pick(pref: "main", screens: [], mouse: .zero) == 0, "没有屏幕：调用方自己兜底，这里不越界")
    }

    @Test func mouseFollowsTheScreenTheMouseIsOn() {
        #expect(StripScreenPicker.pick(pref: "mouse", screens: Self.all, mouse: NSPoint(x: 100, y: 100)) == 0)
        #expect(StripScreenPicker.pick(pref: "mouse", screens: Self.all, mouse: NSPoint(x: -500, y: 300)) == 1)
        #expect(StripScreenPicker.pick(pref: "mouse", screens: Self.all, mouse: NSPoint(x: 3000, y: 500)) == 2)
        #expect(StripScreenPicker.pick(pref: "mouse", screens: Self.all, mouse: NSPoint(x: 99_999, y: 99_999)) == 0, "不在任何屏幕上：主屏幕")
    }

    @Test func aChosenScreenIsFoundByIDThenByNameAndFallsBackToThePrimaryWhenUnplugged() {
        let byID = StripScreenPicker.choice(id: 33, name: "LG HDR 4K")
        #expect(byID == "id:33|LG HDR 4K")
        #expect(StripScreenPicker.pick(pref: byID, screens: Self.all, mouse: .zero) == 2)
        // 重新插拔之后 ID 变了，名字还在：按名字找回来
        #expect(StripScreenPicker.pick(pref: "id:77|LG HDR 4K", screens: Self.all, mouse: .zero) == 2)
        // 旧版本只存了 ID
        #expect(StripScreenPicker.pick(pref: "id:22", screens: Self.all, mouse: .zero) == 1)
        // 被拔掉了：回到主屏幕
        #expect(StripScreenPicker.pick(pref: byID, screens: [Self.main, Self.left], mouse: .zero) == 0)
        #expect(StripScreenPicker.pick(pref: "id:77|不存在的显示器", screens: Self.all, mouse: .zero) == 0)
        // 名字里带竖线也没事（只在第一个 | 处切）
        #expect(StripScreenPicker.parse("id:5|A|B")?.name == "A|B")
        #expect(StripScreenPicker.parse("id:5")?.name == nil)
        #expect(StripScreenPicker.parse("main") == nil)
    }

    /// 设置页的选项：主屏幕 / 鼠标所在的屏幕 / 每块已连接的显示器；当前存的那块被拔掉了就多一项「（未连接）」，选择器不会指向不存在的选项。
    @Test func settingsPageOptionsAlwaysContainTheCurrentValue() {
        for current in ["main", "mouse", "id:33|LG HDR 4K", "id:22", "id:77|已拔掉的显示器", "id:99"] {
            let opts = StripScreenPicker.options(current: current, screens: Self.all)
            #expect(opts.contains { $0.tag == current }, "\(current) 不在选项里：\(opts.map { $0.tag })")
            #expect(Set(opts.map { $0.tag }).count == opts.count, "tag 不能重复（SwiftUI 选择器要求）")
        }
        let base = StripScreenPicker.options(current: "main", screens: Self.all)
        #expect(base.map { $0.title } == ["主屏幕", "鼠标所在的屏幕", "显示器：内建视网膜显示器", "显示器：DELL U2723QE", "显示器：LG HDR 4K"])
        let gone = StripScreenPicker.options(current: "id:77|已拔掉的显示器", screens: Self.all)
        #expect(gone.last?.title == "显示器：已拔掉的显示器（未连接）")
        #expect(StripScreenPicker.options(current: "id:99", screens: Self.all).last?.title == "显示器：ID 99（未连接）")
    }
}
