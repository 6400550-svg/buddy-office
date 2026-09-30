import Testing
import Foundation
@testable import BuddyOffice

/// A-003 / A-016 / A-024：应用设置只处理「相对上一次有变化」的部分；最小化 / 隐藏的办公室窗口不会被弹回来；入口兜底。
@Suite struct ApplyPlanTests {
    static let on = FormInputs(office: true, tank: false, strip: false, menu: true, dock: true, hotkey: false)
    static let gone = WindowState(isVisible: false, isMiniaturized: false, appHidden: false)
    static let shown = WindowState(isVisible: true, isMiniaturized: false, appHidden: false)

    // MARK: A-003
    /// 办公室窗口最小化到 Dock（office.visible 仍是 true，isVisible 却是 false）：之后任何一次设置写入（白板计数、窗口位置、别的设置）都不许把它弹回来。
    @Test func aMinimizedOfficeWindowIsNotBroughtBackByAnUnrelatedSettingsWrite() {
        let plan = ApplyPlanner.plan(previous: Self.on, current: Self.on, window: WindowState(isVisible: false, isMiniaturized: true, appHidden: false))
        #expect(plan.office == nil)
    }

    /// 整个 App 被 ⌘H / Dock「隐藏」时窗口也不是 visible：同理。
    @Test func aHiddenAppDoesNotGetItsOfficeWindowPoppedBackEither() {
        let plan = ApplyPlanner.plan(previous: Self.on, current: Self.on, window: WindowState(isVisible: false, isMiniaturized: false, appHidden: true))
        #expect(plan.office == nil)
    }

    /// 用户明确把「办公室窗口」从关打开：窗口要出来（最小化的也要恢复——showOffice 里处理）。
    @Test func turningTheOfficeOnShowsItEvenIfItIsMinimized() {
        var off = Self.on; off.office = false
        let plan = ApplyPlanner.plan(previous: off, current: Self.on, window: WindowState(isVisible: false, isMiniaturized: true, appHidden: false))
        #expect(plan.office == .show)
    }

    @Test func turningTheOfficeOffHidesIt() {
        var off = Self.on; off.office = false
        #expect(ApplyPlanner.plan(previous: Self.on, current: off, window: Self.shown).office == .hide)
    }

    // MARK: A-016
    /// 没有任何相关设置变化（比如 AppKit 自己写的窗口位置、白板计数）：什么都不做——尤其不重新注册热键。
    @Test func nothingChangedMeansNothingToDo() {
        for w in [Self.shown, Self.gone] {
            #expect(ApplyPlanner.plan(previous: Self.on, current: Self.on, window: w) == ApplyPlan())
        }
        var hot = Self.on; hot.hotkey = true
        #expect(ApplyPlanner.plan(previous: hot, current: hot, window: Self.shown).hotkey == nil, "热键开着时，无关的设置写入不能反复注销 / 重新注册")
    }

    @Test func onlyTheChangedEntriesAreTouched() {
        var n = Self.on; n.tank = true; n.hotkey = true
        let p = ApplyPlanner.plan(previous: Self.on, current: n, window: Self.shown)
        #expect(p == ApplyPlan(tank: .show, hotkey: .show))
        var m = n; m.dock = false; m.strip = true
        let q = ApplyPlanner.plan(previous: n, current: m, window: Self.shown)
        #expect(q == ApplyPlan(activationRegular: false, strip: .show))
    }

    /// 启动时第一次：全做一遍（没有上一次可比）。
    @Test func theFirstApplyDoesEverything() {
        let p = ApplyPlanner.plan(previous: nil, current: Self.on, window: Self.gone)
        #expect(p.activationRegular == true)
        #expect(p.office == .show)
        #expect(p.tank == .hide && p.strip == .hide)
        #expect(p.menuBar == .show)
        #expect(p.hotkey == .hide)
    }

    // MARK: A-024
    @Test func aLoneEmptyPetStripIsNotAnEntryPoint() {
        let strip = FormInputs(strip: true)
        #expect(ApplyPlanner.entryFallback(strip, stripHasBuddies: false, initial: false).dock, "宠物条是一块点穿的空白，没有入口：补上 Dock 图标")
        #expect(!ApplyPlanner.entryFallback(strip, stripHasBuddies: true, initial: false).dock, "有人的宠物条可以点（右键菜单里有「打开办公室」「设置…」）")
        #expect(!ApplyPlanner.entryFallback(strip, stripHasBuddies: false, initial: true).dock, "启动那一刻数据还没到：不因此强行补 Dock 图标（纯宠物用法每次启动都会多出一个图标）")
    }

    @Test func atLeastOneEntryIsAlwaysKept() {
        #expect(ApplyPlanner.entryFallback(FormInputs(), stripHasBuddies: false, initial: false).dock)
        #expect(ApplyPlanner.entryFallback(FormInputs(), stripHasBuddies: true, initial: true).dock)
        for one in [FormInputs(office: true), FormInputs(tank: true), FormInputs(menu: true), FormInputs(dock: true)] {
            #expect(ApplyPlanner.entryFallback(one, stripHasBuddies: false, initial: false) == one, "其他入口还开着，不动用户的选择")
        }
        // 热键不算入口
        #expect(ApplyPlanner.entryFallback(FormInputs(hotkey: true), stripHasBuddies: false, initial: false).dock)
    }

    // MARK: 设置页显示和实际一致（spec-trace-ui 疑点 11）
    @Test func aForcedDockIconIsWrittenBackSoTheSettingsPageDoesNotSayOff() {
        let raw = FormInputs()                                                   // 五个入口全关（设置页里 Dock 图标显示「关」）
        let eff = ApplyPlanner.entryFallback(raw, stripHasBuddies: false, initial: false)
        #expect(eff.dock)
        let wb = ApplyPlanner.settingsWriteBack(raw: raw, effective: eff)
        #expect(wb.count == 1 && wb[0].key == "ui.dockIcon" && wb[0].value == true)
        // 真的写进设置之后，设置页读到的（@AppStorage("ui.dockIcon") 读的就是这个键）是「开」
        Fx.withSettings { s, d in
            d.set(false, forKey: "ui.dockIcon")
            for w in wb { s.set(w.value, w.key) }
            #expect(s.bool("ui.dockIcon"))
        }
        // 没被强制的时候不写：用户关掉 Dock 图标、办公室还开着——尊重用户的选择
        var kept = FormInputs(office: true); kept.dock = false
        #expect(ApplyPlanner.settingsWriteBack(raw: kept, effective: ApplyPlanner.entryFallback(kept, stripHasBuddies: false, initial: false)).isEmpty)
        #expect(ApplyPlanner.settingsWriteBack(raw: FormInputs(dock: true), effective: FormInputs(dock: true)).isEmpty)
    }
}
