import Testing
import Foundation
import AppKit
import SwiftUI
import QuartzCore
import UserNotifications
@testable import BuddyCore
import BuddyArt
import BuddyStage
import PixelKit
@testable import BuddyOffice

/// 规格追踪定稿（QA/spec-trace-ui-final.md）新增的应用层测试：任务书 7.1–7.5 里原来只有「读代码」证据的行。
/// 原则：能在进程内跑的就真的跑（面板 / 窗口对象只建不显示，绝不 orderFront，不弹任何窗口、不碰真实数据、不写用户偏好）；
/// 真的没法自动化的（真实鼠标点击 → 窗口服务器、系统通知授权弹窗、终端自动化授权、Dock / 菜单栏的真实外观、最小化 / 全屏……）
/// 只做「源码钉住」：断言那几行关键代码（常数、调用、顺序）还在——这是间接证据，在 spec-trace-ui-final.md 的「间接验证清单」里逐条列出，不冒充行为测试。
enum SPA {
    /// 一个带假数据源的 AppModel（不 start()），喂进 n 个会话并让 director 跑一拍。
    @MainActor static func rig(buddies n: Int = 2, activity: Activity = .thinking, origin: SessionOrigin = .terminal) -> AppModelTests.Rig {
        let r = AppModelTests.Rig()
        r.real.onUpdate?((0..<n).map { Fx.snap("t:\($0)", seat: $0, origin: origin, activity: activity, pid: Int32(100 + $0)) })
        r.model.director.update(snapshots: r.model.present, now: Date(), time: r.model.time, privacy: false)
        return r
    }
    static func src(_ name: String) throws -> String { try SourceAudit.read(name) }
    /// 字符串 a 出现在 b 之前（都得存在）。
    static func before(_ a: String, _ b: String, in s: String) -> Bool {
        guard let x = s.range(of: a), let y = s.range(of: b) else { return false }
        return x.lowerBound < y.lowerBound
    }
    static var projectRoot: URL { SourceAudit.file("x").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    /// 测试进程自己的偏好里，AppKit 会替面板 / 窗口自动记位置：用完清掉（这是测试宿主进程的域，不是 App 的）。
    static func forgetAutosavedFrames() {
        for n in ["BuddyOfficeMainWindow", "BuddyOfficeTankPanel"] { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(n)") }
    }
    static func mouse(_ type: NSEvent.EventType, _ p: NSPoint, count: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
    }
}

// MARK: - 7.5 设置
@Suite struct SpecTraceSettingsTests {
    /// 7.5「配置项（UserDefaults）」：任务书列出的每一个键都存在、默认值对，设置页里都有对应的控件（@AppStorage 绑定同一个键）。
    @Test func everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage() throws {
        let keys = ["office.visible", "office.zoom", "tank.visible", "tank.zoom", "tank.opacity", "strip.visible", "strip.zoom", "strip.screen", "strip.align", "strip.level", "strip.fullscreen",
                    "ui.menuBarIcon", "ui.dockIcon", "ui.labels", "notify.permission", "notify.question", "notify.finished", "notify.finishedMinSeconds", "notify.includeDesktop",
                    "notify.suppressWhenFocused", "notify.sound", "idle.dozeMinutes", "idle.sleepMinutes", "dormant.max", "dormant.recentHours", "privacy.hideDetails",
                    "autoQuitWithClaude", "login.enabled", "hotkey.enabled"]
        let view = try SPA.src("SettingsView.swift")
        Fx.withSettings { s, d in
            for k in keys {
                #expect(d.object(forKey: k) != nil, "\(k) 没有默认值 / 不存在")
                #expect(view.contains("@AppStorage(\"\(k)\")"), "设置页里没有 \(k) 的控件")
            }
            // 任务书写明的默认值
            #expect(s.int("office.zoom") == 0, "office.zoom：0 = 自动")
            #expect(s.int("notify.finishedMinSeconds") == 30 && s.int("idle.dozeMinutes") == 10 && s.int("idle.sleepMinutes") == 45)
            #expect(s.int("dormant.max") == 4 && s.int("dormant.recentHours") == 3)
            #expect(s.bool("autoQuitWithClaude") && !s.bool("login.enabled"), "autoQuitWithClaude = true、login.enabled = false")
            #expect(s.bool("notify.permission") && s.bool("notify.question") && s.bool("notify.finished") && s.bool("notify.includeDesktop") && s.bool("notify.suppressWhenFocused"), "提醒：默认全开")
            #expect(!s.bool("notify.error"), "出错提醒默认关闭")
            #expect(s.bool("ui.dockIcon"), "默认显示 Dock 图标")
            #expect(s.string("strip.align") == "right" && s.string("strip.level") == "floating" && !s.bool("strip.fullscreen"), "宠物条：默认靠右、浮在窗口上面、全屏空间里默认不显示")
            #expect(s.string("notify.sound") == "8bit" && !s.bool("hotkey.enabled"))
        }
        // 设置窗口：NSWindow + NSHostingController(SettingsView)，四页
        #expect(view.contains("TabView") && view.contains("Form") && view.contains(".formStyle(.grouped)"))
        for tab in ["形态", "提醒", "其他", "数据源诊断"] { #expect(view.contains(".tabItem { Text(\"\(tab)\") }"), "设置页少了「\(tab)」这一页") }
        #expect(view.contains("NSHostingController(rootView: SettingsView(model: model))") && view.contains("NSWindow(contentViewController: host)"))
    }

    /// 7.5 提醒的 7 项设置真的进了判定：AlertConfig 是从设置读的（逐项改、逐项看）。
    @Test func everyNotifySettingReachesTheAlertConfig() {
        Fx.withSettings { s, d in
            let base = AlertConfig(settings: s)
            #expect(base == AlertConfig() && base.permission && base.question && base.finished && !base.error && base.finishedMinSeconds == 30 && base.includeDesktop && base.suppressWhenFocused)
            d.set(false, forKey: "notify.permission"); #expect(!AlertConfig(settings: s).permission)
            d.set(false, forKey: "notify.question"); #expect(!AlertConfig(settings: s).question)
            d.set(false, forKey: "notify.finished"); #expect(!AlertConfig(settings: s).finished)
            d.set(true, forKey: "notify.error"); #expect(AlertConfig(settings: s).error)
            d.set(90, forKey: "notify.finishedMinSeconds"); #expect(AlertConfig(settings: s).finishedMinSeconds == 90)
            d.set(false, forKey: "notify.includeDesktop"); #expect(!AlertConfig(settings: s).includeDesktop)
            d.set(false, forKey: "notify.suppressWhenFocused"); #expect(!AlertConfig(settings: s).suppressWhenFocused)
        }
    }

    /// 7.5 设置窗口：NSWindow（标题栏 + 关闭）里装一个 NSHostingController（只建不显示）。
    @MainActor @Test func theSettingsWindowHostsTheSwiftUIForm() {
        let r = SPA.rig(buddies: 0)
        defer { UserDefaults.standard.removeObject(forKey: "login.enabled") }          // 设置页一出现就会把「开机启动」的真实状态写进偏好（测试宿主进程的域）：清掉
        let wc = SettingsWindowController(model: r.model)
        let w = wc.window!
        #expect(w.contentViewController is NSHostingController<SettingsView>, "内容是 NSHostingController(SettingsView)")
        #expect(w.styleMask.contains(.titled) && w.styleMask.contains(.closable) && !w.isVisible)
    }
}

// MARK: - 7.1 面板 / 窗口
@MainActor @Suite struct SpecTracePanelTests {
    /// 7.1 小鱼缸 / 桌面宠物条：「NSPanel，无边框、不抢焦点（nonactivating），level = .floating，collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]，canBecomeKey = false」；
    /// 宠物条「背景透明（isOpaque = false，.clear），没有阴影」；悬停卡片「用单独的 HoverPanel 显示」（永远不拦截鼠标）。
    @Test func thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent() {
        let p = FloatingPanel(size: NSSize(width: 100, height: 50))
        #expect(!p.styleMask.contains(.titled) && p.styleMask.contains(.nonactivatingPanel), "无边框（没有标题栏）、不抢焦点（nonactivatingPanel）")
        #expect(!p.canBecomeKey && !p.canBecomeMain && !p.hidesOnDeactivate)
        #expect(p.level == .floating && p.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary])
        let tank = TankPanelController()
        #expect(tank.panel.level == .floating && tank.panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary] && !tank.panel.canBecomeKey)
        let strip = StripPanelController()
        #expect(!strip.panel.isOpaque && strip.panel.backgroundColor == .clear && !strip.panel.hasShadow, "宠物条：透明背景，没有阴影")
        #expect(strip.panel.styleMask.contains(.nonactivatingPanel) && !strip.panel.canBecomeKey)
        let hover = HoverPanelController()
        #expect(hover.panel.ignoresMouseEvents && hover.panel.level == .statusBar && hover.panel !== tank.panel, "悬停卡片是单独的面板，不拦截鼠标")
        #expect(tank.hover.panel !== strip.hover.panel && tank.hover.panel.ignoresMouseEvents, "小鱼缸 / 宠物条各有自己的 HoverPanel")
        #expect(PixelView(frame: .zero).acceptsFirstMouse(for: nil), "acceptsFirstMouse = true：点一下不用先激活")
        SPA.forgetAutosavedFrames()
    }

    /// 7.1 小鱼缸「按住背景可以拖动」：不用 AppKit 的 isMovableByWindowBackground（它会吞掉小人的点击），由 PixelView 在背景上单击时交给窗口拖（A-002）。
    @Test func theTankIsDraggedByItsBackgroundThroughThePixelViewNotAppKitsBackgroundDrag() {
        let tank = TankPanelController()
        #expect(!tank.panel.isMovableByWindowBackground && tank.pixelView.dragsWindowOnBackground)
        #expect(PixelView.mouseDownAction(hitID: 0, clickCount: 1, dragsWindowOnBackground: true) == .dragWindow, "按住背景（单击）→ 拖窗口")
        #expect(!tank.pixelView.mouseDownCanMoveWindow, "点小人 / 双击不被 AppKit 当成拖动吞掉")
        SPA.forgetAutosavedFrames()
    }

    /// 7.1 小鱼缸「双击回到办公室」+「左键点击跳到会话」：在进程内真的渲染一张小鱼缸，找到小人和背景的像素，走 TankPanelController.click。
    @Test func doubleClickingTheTanksBackgroundGoesBackAndClickingABuddyJumps() throws {
        let r = SPA.rig(buddies: 2)
        let tank = TankPanelController()
        var buddyClicks: [String] = [], doubles = 0
        tank.onClickBuddy = { buddyClicks.append($0.key) }
        tank.onDoubleClickBackground = { doubles += 1 }
        tank.render(model: r.model, force: true)
        let pv = tank.pixelView
        var buddy: NSPoint?, background: NSPoint?
        for vy in stride(from: 4, to: Int(pv.bounds.height) - 4, by: 2) { for vx in stride(from: 4, to: Int(pv.bounds.width) - 4, by: 2) {
            let p = NSPoint(x: vx, y: vy), id = pv.hitID(at: p)
            if buddy == nil, id >= 2000, id < 3000 { buddy = p }
            if background == nil, id == 0, vy > Int(pv.bounds.height) / 2 { background = p }
        } }
        let b = try #require(buddy), bg = try #require(background)
        tank.click(bg, count: 1)
        #expect(doubles == 0 && buddyClicks.isEmpty, "背景单击：什么都不发生（交给拖动）")
        tank.click(bg, count: 2)
        #expect(doubles == 1, "双击背景：回到办公室")
        tank.click(b, count: 1)
        #expect(buddyClicks.count == 1 && ["t:0", "t:1"].contains(buddyClicks[0]), "点小人：把那一刻画在那里的会话交给跳转")
        tank.click(b, count: 2)
        #expect(doubles == 1 && buddyClicks.count == 2, "双击在小人身上不算「回办公室」")
        tank.hide(); SPA.forgetAutosavedFrames()
    }

    /// 7.1 宠物条「点穿：对象 ID 缓冲做命中测试，命中范围向外扩 1 像素，据此切换 ignoresMouseEvents」「左键点击跳到会话」。
    @Test func theStripInterceptsBuddyPixelsWithAOnePixelHaloAndLetsEverythingElseThrough() throws {
        let r = SPA.rig(buddies: 2)
        let strip = StripPanelController()
        var clicked: [String] = []
        strip.onClickBuddy = { clicked.append($0.key) }
        strip.render(model: r.model, force: true)
        strip.model = nil                                    // 不让 evaluate 去弹悬停卡片（那是一个真的窗口）
        let c = try #require(strip.pixelView.frame_).canvas
        let z = strip.zoom, f = strip.panel.frame
        func point(_ x: Int, _ y: Int) -> NSPoint { NSPoint(x: f.minX + CGFloat(x * z) + CGFloat(z) / 2, y: f.maxY - CGFloat(y * z) - CGFloat(z) / 2) }
        func near(_ x: Int, _ y: Int, _ r: Int) -> Bool { (-r...r).contains { dy in (-r...r).contains { dx in c.objectID(x + dx, y + dy) != 0 } } }
        var solid: (Int, Int)?, halo: (Int, Int)?, twoAway: (Int, Int)?, empty: (Int, Int)?
        for y in 0..<c.height { for x in 0..<c.width {
            let id = c.objectID(x, y)
            if id >= 3000 && id < 4000 && solid == nil { solid = (x, y) }
            if id == 0 && halo == nil && near(x, y, 1) { halo = (x, y) }
            if id == 0 && twoAway == nil && !near(x, y, 1) && near(x, y, 2) { twoAway = (x, y) }
            if empty == nil && !near(x, y, 3) { empty = (x, y) }
        } }
        let s = try #require(solid), h = try #require(halo), t = try #require(twoAway), e = try #require(empty)
        #expect(strip.panel.ignoresMouseEvents, "一开始点穿")
        #expect(strip.evaluate(at: point(s.0, s.1)) == false && !strip.panel.ignoresMouseEvents, "鼠标在小人身上：拦截")
        #expect(strip.evaluate(at: point(h.0, h.1)) == false, "小人边上 1 像素：还算命中（向外扩 1 像素）")
        #expect(strip.evaluate(at: point(t.0, t.1)) == true && strip.panel.ignoresMouseEvents, "2 像素外：点穿")
        #expect(strip.evaluate(at: point(e.0, e.1)) == true, "空白处：点穿")
        #expect(strip.evaluate(at: NSPoint(x: f.minX - 500, y: f.minY - 500)) == true, "离得很远：点穿")
        #expect(strip.toggles == 2, "点穿 → 拦截 → 点穿：一共切换 \(strip.toggles) 次（状态没变的时候不重复设置）")
        // 点小人：点到的是画面里那个人的快照
        let p = NSPoint(x: CGFloat(s.0 * z) + CGFloat(z) / 2, y: CGFloat(s.1 * z) + CGFloat(z) / 2)
        strip.pixelView.onClick?(p, 1)
        #expect(clicked.count == 1 && ["t:0", "t:1"].contains(clicked[0]))
        strip.hide(); SPA.forgetAutosavedFrames()
    }

    /// 7.5 设置 → 面板行为：小鱼缸缩放 1–2 / 不透明度，宠物条缩放 1–3 / 位置 / 层级 / 全屏，7.1 宠物条尺寸（高 = (64 + 20 + 56) × 缩放，宽 = 人数 × 56 × 缩放）。
    @Test func settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize() throws {
        // 小鱼缸
        for (opacity, zoom, wantAlpha, wantZoom) in [(0.5, 1, 0.5, 1), (1.0, 2, 1.0, 2), (0.1, 9, 0.3, 2)] as [(Double, Int, Double, Int)] {
            let r = SPA.rig(buddies: 3)
            r.store.defaults.set(opacity, forKey: "tank.opacity"); r.store.defaults.set(zoom, forKey: "tank.zoom")
            let tank = TankPanelController()
            tank.render(model: r.model, force: true)
            #expect(abs(tank.panel.alphaValue - wantAlpha) < 1e-9 && tank.zoom == wantZoom, "小鱼缸：不透明度 \(opacity) → \(tank.panel.alphaValue)，缩放 \(zoom) → \(tank.zoom)")
            let cv = try #require(tank.pixelView.frame_).canvas
            #expect(tank.panel.frame.size == NSSize(width: cv.width * wantZoom, height: cv.height * wantZoom), "小鱼缸窗口 = 画布 × 缩放")
            tank.hide()
        }
        // 宠物条
        guard let scr = NSScreen.screens.first else { return }
        for zoom in [1, 2, 3, 7] {
            let r = SPA.rig(buddies: 3)
            r.store.defaults.set(zoom, forKey: "strip.zoom")
            let strip = StripPanelController()
            strip.render(model: r.model, force: true)
            let want = max(1, min(3, zoom))
            #expect(strip.zoom == want)
            let size = strip.panel.frame.size
            #expect(size == NSSize(width: 3 * 56 * want, height: (64 + 20 + 56) * want), "宠物条 \(zoom) 倍：窗口 \(size)（高 = (64 + 20 + 56) × 倍数，宽 = 人数 × 56 × 倍数）")
            #expect(strip.panel.frame.minY == strip.targetScreen(r.model).visibleFrame.minY, "底边贴着 visibleFrame.minY（Dock 上方）")
            strip.hide()
        }
        for (align, right) in [("right", true), ("left", false), ("center", false)] {
            let r = SPA.rig(buddies: 3)
            r.store.defaults.set(align, forKey: "strip.align")
            let strip = StripPanelController()
            strip.render(model: r.model, force: true)
            let vf = strip.targetScreen(r.model).visibleFrame
            #expect(strip.panel.frame.origin == StripPanelController.origin(align: align, visibleFrame: vf, panelSize: strip.panel.frame.size), "位置 \(align) 立刻生效")
            #expect(strip.scene.alignRight == right)
            strip.hide()
        }
        _ = scr
        // 层级 / 全屏
        let d = SPA.rig(buddies: 1)
        let strip = StripPanelController()
        strip.render(model: d.model, force: true)
        #expect(strip.panel.level == .floating && strip.panel.collectionBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle], "默认：浮在窗口上面、全屏空间里不显示")
        d.store.defaults.set("desktop", forKey: "strip.level"); d.store.defaults.set(true, forKey: "strip.fullscreen")
        strip.applyLevel(d.model)
        #expect(strip.panel.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1, "桌面层级")
        #expect(strip.panel.collectionBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary], "打开「全屏里也显示」")
        strip.hide(); SPA.forgetAutosavedFrames()
    }

    /// 7.1 办公室窗口：「普通 NSWindow：带标题栏、可以缩放，内容铺满，标题栏透明。窗口位置自动保存。」「窗口出现时先渲染好第一帧再显示」「悬停 / 点击」。
    @Test func theOfficeWindowIsAnOrdinaryTitledResizableWindowThatRendersItsFirstFrameBeforeItIsShown() throws {
        let r = SPA.rig(buddies: 2)
        let wc = OfficeWindowController()
        let w = try #require(wc.window)
        #expect(w.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]), "带标题栏、可缩放、内容铺满")
        #expect(w.titlebarAppearsTransparent && w.titleVisibility == .hidden, "标题栏透明")
        #expect(w.contentView === wc.pixelView && !w.isReleasedWhenClosed)
        #expect(w.frameAutosaveName == "BuddyOfficeMainWindow", "窗口位置自动保存")
        #expect(w.titlebarAccessoryViewControllers.contains { $0 === wc.titleBar } && wc.titleBar.layoutAttribute == .trailing, "标题栏右侧放像素按钮")
        #expect(!w.isVisible && wc.pixelView.frame_ == nil)
        wc.render(model: r.model, force: true)
        #expect(!w.isVisible && wc.pixelView.frame_ != nil, "窗口还没显示，第一帧已经渲染好了")
        // 点小人 → 座位号；右键 → 座位号
        let fr = try #require(wc.pixelView.frame_), c = fr.canvas
        var art: (Int, Int)?
        for y in 0..<c.height { for x in 0..<c.width where art == nil { if OfficeScene.seat(fromHitID: c.objectID(x, y)) != nil { art = (x, y) } } }
        let a = try #require(art)
        let p = NSPoint(x: CGFloat((a.0 - fr.viewport.x) * wc.pixelView.zoom) + 1, y: CGFloat((a.1 - fr.viewport.y) * wc.pixelView.zoom) + 1)
        var seats: [Int] = [], rights: [Int?] = []
        wc.onClickSeat = { seats.append($0) }
        wc.onRightClick = { s, _, _ in rights.append(s) }
        wc.pixelView.onClick?(p, 1)
        wc.pixelView.onRightClick?(p, SPA.mouse(.rightMouseDown, p))
        #expect(seats.count == 1 && (0...1).contains(seats[0]) && rights == [seats[0]], "左键点小人 = 跳转、右键 = 菜单，都拿到那个人的座位号")
        SPA.forgetAutosavedFrames()
    }

    /// 7.1 办公室窗口「悬停卡片直接画在场景里」「悬停 250 ms 后出卡片」：用真实时钟——鼠标刚停到小人身上没有卡片，停满 250 ms 之后卡片画进场景，移开就收起。
    /// （只在两次渲染之间隔得很近时才断言「还没有」：测试进程被挂起超过 200 ms 的话，这一半不作数，「之后有」那一半照常断言。）
    @Test func theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms() throws {
        let r = SPA.rig(buddies: 2)
        let wc = OfficeWindowController()
        wc.render(model: r.model, force: true)
        let fr = try #require(wc.pixelView.frame_), c = fr.canvas
        var art: (Int, Int)?
        for y in 0..<c.height { for x in 0..<c.width where art == nil { if OfficeScene.seat(fromHitID: c.objectID(x, y)) != nil { art = (x, y) } } }
        let a = try #require(art)
        let p = NSPoint(x: CGFloat((a.0 - fr.viewport.x) * wc.pixelView.zoom) + 1, y: CGFloat((a.1 - fr.viewport.y) * wc.pixelView.zoom) + 1)
        func hasCard() -> Bool { wc.pixelView.frame_?.texts.contains { $0.tag == "card.title" } ?? false }
        #expect(!hasCard())
        let t0 = CACurrentMediaTime()                                   // 先取时间再悬停：两句之间被挂起时保护也不会失效（R5b-P3-01）
        wc.pixelView.onHover?(p)
        wc.render(model: r.model, force: true)
        if CACurrentMediaTime() - t0 < 0.2 { #expect(!hasCard(), "鼠标刚停到小人身上：还没有卡片") }
        Thread.sleep(forTimeInterval: 0.35)
        wc.render(model: r.model, force: true)
        #expect(hasCard(), "停满 250 ms 之后：卡片直接画在场景里")
        wc.pixelView.onHover?(nil)
        wc.render(model: r.model, force: true)
        #expect(!hasCard(), "鼠标移开：卡片收起")
        SPA.forgetAutosavedFrames()
    }

    /// 7.1 办公室窗口「点关闭只是隐藏窗口，App 继续运行」：关闭按钮调用的就是 windowShouldClose——返回 false（窗口不真的关掉）、把「办公室窗口没开」记进设置。
    @Test func closingTheOfficeWindowOnlyHidesItAndRemembersThatItIsClosed() throws {
        let wc = OfficeWindowController()
        let w = try #require(wc.window)
        UserDefaults.standard.removeObject(forKey: "office.visible")
        defer { UserDefaults.standard.removeObject(forKey: "office.visible"); SPA.forgetAutosavedFrames() }
        #expect(wc.windowShouldClose(w) == false, "返回 false：窗口对象还在，只是被 orderOut")
        #expect(UserDefaults.standard.object(forKey: "office.visible") as? Bool == false, "记成「办公室窗口没开」（下次启动按这个形态出现）")
        #expect(!w.isVisible && !w.isReleasedWhenClosed)
        #expect(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false, "关掉最后一个窗口，App 继续运行")
    }

    /// 7.1 桌面宠物条「监听 didChangeScreenParametersNotification」：屏幕参数变了 → 宠物条重新定位到 Dock 上方。发一条同名通知（进程内，没有真的换显示器）看它有没有动。
    @Test func aScreenParametersChangeRepositionsTheStrip() {
        let r = SPA.rig(buddies: 2)
        let strip = StripPanelController()
        strip.render(model: r.model, force: true)
        let placed = strip.panel.frame.origin
        strip.panel.setFrameOrigin(NSPoint(x: placed.x - 137, y: placed.y + 91))
        #expect(strip.panel.frame.origin != placed)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(strip.panel.frame.origin == placed, "收到屏幕参数变化的通知：重新定位回原来的位置")
        strip.hide(); SPA.forgetAutosavedFrames()
    }

    /// 7.5 界面：ui.labels（总是 / 悬停 / 关闭）、office.zoom（0 = 自动）真的进了办公室的渲染。
    @Test func labelsAndZoomSettingsReachTheOfficeRendering() {
        func plateTexts(_ labels: String, zoom: Int) -> (Int, Int) {
            let r = SPA.rig(buddies: 2)
            r.store.defaults.set(labels, forKey: "ui.labels"); r.store.defaults.set(zoom, forKey: "office.zoom")
            let wc = OfficeWindowController()
            wc.render(model: r.model, force: true)
            return (wc.pixelView.frame_?.texts.filter { $0.tag.hasPrefix("plate") }.count ?? -1, wc.zoom)
        }
        #expect(plateTexts("always", zoom: 0).0 >= 2, "总是显示桌牌文字")
        #expect(plateTexts("off", zoom: 0).0 == 0, "关闭")
        #expect(plateTexts("hover", zoom: 0).0 == 0, "悬停时才显示：没悬停就没有")
        #expect(plateTexts("always", zoom: 2).1 == 2 && plateTexts("always", zoom: 3).1 == 3, "office.zoom 指定倍数")
        #expect(plateTexts("always", zoom: 0).1 >= 2, "0 = 自动")
        SPA.forgetAutosavedFrames()
    }
}

// MARK: - 7.1 标题栏 / 菜单栏
@MainActor @Suite struct SpecTraceChromeTests {
    /// 7.1 标题栏像素按钮（缩成小鱼缸 / 打开桌面宠物 / 设置）：三个按钮 24 pt 见方，按下并在按钮里抬起才算点击；点了「缩成小鱼缸」：小鱼缸开、办公室关。
    @Test func theThreeTitleBarButtonsClickOnlyWhenReleasedInsideAndShrinkingSwapsTheOfficeForTheTank() {
        let bar = TitleBarButtonBar()
        let buttons = [bar.tank, bar.strip, bar.settings]
        #expect(buttons.allSatisfy { $0.frame.size == NSSize(width: 24, height: 24) } && buttons.map(\.icon) == ["chrome.tank", "chrome.strip", "chrome.gear"], "三个 24 pt 的按钮：小鱼缸 / 宠物 / 设置")
        #expect(bar.tank.toolTip?.contains("小鱼缸") == true && bar.strip.toolTip?.contains("桌面宠物") == true && bar.settings.toolTip?.contains("设置") == true)
        bar.update(tankOn: true, stripOn: false)
        #expect(bar.tank.on && !bar.strip.on, "对应的形态开着：按钮亮着")
        let b = PixelButton(icon: "chrome.gear", tip: "设置…")
        var n = 0
        b.onClick = { n += 1 }
        let inside = b.convert(NSPoint(x: 12, y: 12), to: nil), outside = b.convert(NSPoint(x: 200, y: 200), to: nil)
        b.mouseDown(with: SPA.mouse(.leftMouseDown, inside)); b.mouseUp(with: SPA.mouse(.leftMouseUp, inside))
        #expect(n == 1, "按下 + 在里面抬起 = 一次点击")
        b.mouseDown(with: SPA.mouse(.leftMouseDown, inside)); b.mouseUp(with: SPA.mouse(.leftMouseUp, outside))
        #expect(n == 1, "拖到外面再松开不算点击")
        b.mouseUp(with: SPA.mouse(.leftMouseUp, inside))
        #expect(n == 1, "没有按下过：不算")
        b.mouseDown(with: SPA.mouse(.leftMouseDown, inside)); b.mouseExited(with: SPA.mouse(.mouseMoved, outside)); b.mouseUp(with: SPA.mouse(.leftMouseUp, inside))
        #expect(n == 1, "移出再移回来：要重新按")
        // 点「缩成小鱼缸」的效果：小鱼缸开、办公室关 → 应用设置的计划里办公室收起、小鱼缸出现
        let r = SPA.rig(buddies: 0)
        let on = FormInputs(office: true, tank: false, strip: false, menu: true, dock: true, hotkey: false)
        func inputs(_ s: BuddyOffice.Settings) -> FormInputs { FormInputs(office: s.bool("office.visible"), tank: s.bool("tank.visible"), strip: s.bool("strip.visible"), menu: s.bool("ui.menuBarIcon"), dock: s.bool("ui.dockIcon"), hotkey: s.bool("hotkey.enabled")) }
        #expect(inputs(r.store.settings) == on, "默认形态：办公室开、小鱼缸 / 宠物关")
        r.model.shrinkToTank()
        let plan = ApplyPlanner.plan(previous: on, current: inputs(r.store.settings), window: WindowState(isVisible: true, isMiniaturized: false, appHidden: false))
        #expect(r.store.settings.bool("tank.visible") && !r.store.settings.bool("office.visible"), "缩成小鱼缸：小鱼缸开、办公室关")
        #expect(plan.office == EntryAction.hide, "应用设置：办公室窗口收起")
        #expect(plan.tank == EntryAction.show, "应用设置：小鱼缸出现")
        #expect(plan.strip == nil, "宠物条不动")
    }

    /// 7.1 标题栏像素按钮的美术：12×12 的木牌底板 4 种状态（普通 / 悬停 / 按下 / 开着）+ 10×10 的图标。
    @Test func titleBarButtonArtIsTwelveByTwelveWithFourStatesAndTenByTenIcons() {
        for n in ["plate.normal", "plate.hover", "plate.pressed", "plate.on"] { let s = ChromeArt.book[n]; #expect(s.width == 12 && s.height == 12, "\(n)") }
        for n in ChromeArt.iconNames { let s = ChromeArt.book[n]; #expect(s.width == 10 && s.height == 10, "\(n)") }
        for icon in ChromeArt.iconNames {
            let hashes = ChromeArt.State.allCases.map { ChromeArt.button(icon: icon, state: $0).contentHash() }
            #expect(Set(hashes).count == 4 && ChromeArt.State.allCases.count == 4, "\(icon)：4 种状态各不相同")
            #expect(ChromeArt.button(icon: icon, state: .normal).width == 12)
        }
    }

    /// 7.1 菜单栏图标：「18 pt 的像素模板图标，有「正常 / 有人在忙」两种；有人等你时换成彩色的举手图标，这一张不做成模板图」。
    @Test func menuBarIconsAreEighteenPointTemplatesExceptTheColouredWaitingOne() throws {
        func rgba(_ k: MenuBarIcon.Kind) throws -> (w: Int, h: Int, px: [UInt8]) {
            let img = try #require(MenuBarIcon.image(k))
            let w = img.width, h = img.height
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try #require(CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return (w, h, buf)
        }
        var seen: [MenuBarIcon.Kind: [UInt8]] = [:]
        for k in MenuBarIcon.Kind.allCases {
            let (w, h, px) = try rgba(k)
            #expect(w == 36 && h == 36, "\(k)：18 美术像素 × 2 倍最近邻 = 36 px，按 18 pt 用（Retina 下每个美术像素正好 2 个设备像素）")
            var colours = Set<[UInt8]>()
            for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] != 0 { colours.insert(Array(px[i..<(i + 3)])) }
            if k == .waiting { #expect(colours.count >= 4 && colours.contains { $0 != [0, 0, 0] && $0[0] > 200 }, "举手图标是彩色的（\(colours.count) 种颜色）") }
            else { #expect(colours == [[0, 0, 0]], "\(k)：模板图只用黑色 + 透明：\(colours)") }
            seen[k] = px
        }
        #expect(Set(seen.values).count == 3, "三种图标互不相同")
        #expect(StatusItemController.iconKind(waiting: 1, busy: 0) == .waiting && StatusItemController.iconKind(waiting: 0, busy: 2) == .busy && StatusItemController.iconKind(waiting: 0, busy: 0) == .normal)
        let src = try SPA.src("StatusItemController.swift")
        #expect(src.contains("NSSize(width: 18, height: 18)") && src.contains("img.isTemplate = (kind != .waiting)"), "18 pt；只有等你的那张不是模板图")
    }

    /// 7.1 菜单栏菜单：从上到下 = 每个 buddy 一行（状态图标、标题、当前动作，点击跳转）→ 开关（办公室窗口 / 小鱼缸 / 桌面宠物 / 菜单栏图标 / Dock 图标）→ 演示模式 → 设置… → 退出。
    @Test func theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit() throws {
        let r = AppModelTests.Rig()
        var tool = Fx.snap("t:0", seat: 0, activity: .waitingApproval(tool: Fx.call("Bash", "git push")), title: "重构登录", pid: 100)
        tool.turnStartedAt = Fx.base
        var unread = Fx.snap("t:2", seat: 2, activity: .idle, title: "论文", pid: 102); unread.unread = true
        r.real.onUpdate?([tool, Fx.snap("t:1", seat: 1, activity: .thinking, title: "健身", pid: 101), unread, Fx.snap("t:3", seat: 3, activity: .idle, title: "空闲的", pid: 103)])
        let sc = StatusItemController(); sc.model = r.model
        var jumped: [String] = []
        sc.onJump = { jumped.append($0.key) }
        let menu = NSMenu()
        sc.menuNeedsUpdate(menu)
        let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
        #expect(titles.count == 4 + 1 + 5 + 1 + 3, "4 个 buddy 行 + 分隔 + 5 个开关 + 分隔 + 演示 / 设置 / 退出：\(titles)")
        #expect(titles[0].hasPrefix("🙋 重构登录") && titles[0].contains("等你批准 Bash"), "等你：举手的人 + 标题 + 当前动作：\(titles[0])")
        #expect(titles[1].hasPrefix("⌨️ 健身") && titles[1].contains("思考中"), "在忙：键盘：\(titles[1])")
        #expect(titles[2].hasPrefix("🚩 论文") && titles[2].contains("空闲"), "做完了未读：小旗：\(titles[2])")
        #expect(titles[3].hasPrefix("☕️ 空闲的"), "空闲：咖啡杯：\(titles[3])")
        #expect(titles[4] == "—" && Array(titles[5..<10]) == ["办公室窗口", "小鱼缸", "桌面宠物", "菜单栏图标", "Dock 图标"] && titles[10] == "—", "开关的顺序：\(titles)")
        #expect(titles[11].hasPrefix("演示模式") && titles[12] == "设置…" && titles[13].hasPrefix("退出"), "演示模式 / 设置… / 退出：\(titles)")
        // 点一行 = 跳转到那个会话
        _ = (menu.items[0].target as? NSObject)?.perform(menu.items[0].action)
        #expect(jumped == ["t:0"])
        // 开关：勾选状态取自设置，点一下就翻转
        let keys = ["office.visible", "tank.visible", "strip.visible", "ui.menuBarIcon", "ui.dockIcon"]
        for (i, k) in keys.enumerated() {
            let item = menu.items[5 + i]
            #expect((item.state == .on) == r.store.settings.bool(k), "\(item.title) 的勾选状态取自 \(k)")
            let before = r.store.settings.bool(k)
            _ = (item.target as? NSObject)?.perform(item.action)
            #expect(r.store.settings.bool(k) == !before, "点「\(item.title)」翻转 \(k)")
        }
        // 演示模式：点一下切到演示数据源
        #expect(!r.model.demo)
        _ = (menu.items[11].target as? NSObject)?.perform(menu.items[11].action)
        #expect(r.model.demo && r.demoProviders.count == 1, "演示模式：换成演示数据源")
        // 隐私模式：不带标题和命令
        r.store.defaults.set(true, forKey: "privacy.hideDetails")
        let m2 = NSMenu(); sc.menuNeedsUpdate(m2)
        #expect(!m2.items.contains { $0.title.contains("重构登录") || $0.title.contains("git push") }, "隐私模式：菜单栏里不出现标题 / 命令")
        // 没人：一行灰色的「今天还没人上班」
        let empty = AppModelTests.Rig()
        let sc2 = StatusItemController(); sc2.model = empty.model
        let m3 = NSMenu(); sc2.menuNeedsUpdate(m3)
        #expect(m3.items.first?.title == "今天还没人上班" && m3.items.first?.isEnabled == false)
    }
}

// MARK: - 7.2 提醒（补：通知服务 / 提示音 / 时间常数）
@MainActor @Suite struct SpecTraceAlertTests {
    /// 7.2 系统通知「只有 bundleURL.pathExtension == "app" 且有 bundle id 才调 UNUserNotificationCenter」+ 点提示卡 / 通知 → 把 key 交给跳转。
    @Test func theSystemNotificationGateIsTheAppBundleAndAClickCarriesTheKey() {
        let store = Fx.Store(); defer { store.cleanUp() }
        let toast = FakeToast()
        let n = NotificationService(client: FakeCenter(status: .authorized), toast: toast, playSound: { _, _ in }, defaults: store.defaults)
        #expect(n.available == (Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil), "默认的判断就是 .app + bundle id（测试宿主不是 App：不可用）")
        var clicked: [String] = []
        n.onClick = { clicked.append($0) }
        toast.onClick?("t:a"); toast.onClick?("multi")
        #expect(clicked == ["t:a", "multi"], "点提示卡：把 key 交给点击处理")
    }

    /// 7.2 提示音「可以设置成：无 / 系统提示音 / 8-bit」：设置里的取值原样交给播放，种类按提醒类别选。
    @Test func theSoundModeFromTheSettingsReachesThePlayerAndEachKindHasItsOwnSound() {
        let store = Fx.Store(); defer { store.cleanUp() }
        var played: [(SoundSynth.Kind, String)] = []
        let n = NotificationService(client: FakeCenter(status: .denied), toast: FakeToast(), playSound: { played.append(($0, $1)) }, available: true, defaults: store.defaults)
        for mode in ["none", "system", "8bit"] { n.post(key: "k", kind: .approval, title: "t", body: "b", sound: mode) }
        #expect(played.map(\.1) == ["none", "system", "8bit"])
        played = []
        for k in [ToastCard.Kind.approval, .blocked, .question, .plan, .finished, .info, .error] { n.post(key: "k", kind: k, title: "t", body: "b", sound: "8bit") }
        #expect(played.map { "\($0.0)" } == ["approval", "approval", "question", "question", "finished", "finished", "error"])
    }

    /// 7.2「提示音：在运行时合成 8-bit 的 WAV 数据，不需要外部文件」。
    @Test func theSoundsAreSynthesisedAsEightBitMonoWavDataWithoutAnyFile() throws {
        let notes: [SoundSynth.Kind: Double] = [.approval: 0.09 + 0.13, .question: 0.09 + 0.13, .finished: 0.08 + 0.08 + 0.14, .error: 0.1 + 0.18]
        for (k, seconds) in notes {
            let d = SoundSynth.wav(k)
            func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
            func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
            #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF" && String(decoding: d[8..<12], as: UTF8.self) == "WAVE" && String(decoding: d[36..<40], as: UTF8.self) == "data")
            #expect(u16(20) == 1 && u16(22) == 1 && u32(24) == 22_050 && u16(34) == 8, "\(k)：PCM、单声道、22050 Hz、8 位")
            #expect(u32(4) == d.count - 8 && u32(40) == d.count - 44, "\(k)：块长度对得上")
            #expect(abs(Double(d.count - 44) / 22_050 - seconds) < 0.001, "\(k)：时长 \(Double(d.count - 44) / 22_050) 秒，应为 \(seconds)")
            let samples = Array(d[44...])
            var crossings = 0
            for i in 1..<samples.count where (samples[i - 1] >= 128) != (samples[i] >= 128) { crossings += 1 }
            #expect(samples.max()! > 128 + 10 && samples.min()! < 128 - 10 && crossings >= 50, "\(k)：有振幅、有振荡（\(crossings) 次过零），不是静音")
        }
        for (name, text) in try SourceAudit.allOfficeSources() { #expect(!text.contains("forResource") && !text.contains(".wav\"") && !text.contains(".aiff\"") && !text.contains(".mp3\""), "\(name) 不该读外部声音文件") }
    }

    /// 7.2 通知的维护 / 兜底 / 场景气泡：identifier 用 `buddy.<key>`、点击的 key 放 userInfo、撤销按 identifier、Dock 弹跳用 informationalRequest、提示卡「从右上角弹簧滑入」（最多 3 张、6 秒收回）。
    /// 真实的系统通知 / Dock / 窗口动画没法在单测里跑：这里钉住关键代码。
    @Test func notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays() throws {
        let n = try SPA.src("NotificationService.swift")
        #expect(n.contains("UNNotificationRequest(identifier: \"buddy.\\(key)\"") && n.contains("c.userInfo = [\"buddyKey\": key]") && n.contains("removeDeliveredNotifications(withIdentifiers: [\"buddy.\\(key)\"])"))
        #expect(n.contains("r.notification.request.content.userInfo[\"buddyKey\"] as? String") && n.contains("self.onClick?(k)"), "点通知：取出 key 交给跳转")
        #expect(n.contains("Bundle.main.bundleURL.pathExtension == \"app\" && Bundle.main.bundleIdentifier != nil"))
        let sys = try SPA.src("SystemHelpers.swift")
        #expect(sys.contains("NSApp.requestUserAttention(.informationalRequest)") && sys.contains("NSApp.dockTile.badgeLabel = $0"))
        let toast = try SPA.src("ToastController.swift")
        #expect(toast.contains("PixelSpring(value: 60, period: 0.36)") && toast.contains("toasts.count > 3") && toast.contains("now - t.born > 6"), "弹簧滑入、最多 3 张、6 秒后收回")
        #expect(toast.contains("vf.maxY - 10") && toast.contains("vf.maxX - t.size.width - 12"), "靠 visibleFrame 的右上角")
    }
}

// MARK: - 7.3 跳转 / 7.4 跟着 Claude 开收 / 7.5 诊断 —— 补充
@MainActor @Suite struct SpecTraceJumpAndLifecycleTests {
    /// 7.3 终端里的会话：AppleScript「找到 tty of tab 等于这个 tty 的标签页，选中它，把它所在的窗口提到最前、取消最小化，再激活 Terminal」。
    @Test func theTerminalScriptFollowsTheSpecifiedSteps() throws {
        let script = try #require(JumpResolver.terminalTabScript(tty: "/dev/ttys012"))
        let steps = ["tell application \"Terminal\"", "repeat with w in windows", "repeat with tb in tabs of w", "if (tty of tb) is \"/dev/ttys012\"", "set selected of tb to true",
                     "set miniaturized of w to false", "set index of w to 1", "activate"]
        var last = script.startIndex
        for s in steps {
            let r = try #require(script.range(of: s, range: last..<script.endIndex), "脚本里缺「\(s)」或顺序不对")
            last = r.upperBound
        }
    }

    /// 7.3 终端里的会话：sysctl 读进程信息（父进程 / 控制终端）、沿父进程链找宿主 App（最多 12 层，跳过 CLI 包和纯后台 App）。
    @Test func theProcessHelpersReadTheProcessTableAndTheHostLookupSkipsBackgroundApps() throws {
        let me = getpid()
        #expect(ProcessInfoHelper.parent(of: me) == getppid(), "sysctl(KERN_PROC_PID) 读到的父进程 = getppid()")
        if let tty = ProcessInfoHelper.ttyName(of: me) { #expect(JumpResolver.isValidTTY(tty), "读到的 tty 名 \(tty) 必须是 /dev/tty…") }
        #expect(ProcessInfoHelper.parent(of: 999_999) == nil && ProcessInfoHelper.ttyName(of: 999_999) == nil, "不存在的进程：nil")
        #expect(JumpService.shared.hostApp(of: 0) == nil && JumpService.shared.hostApp(of: 1) == nil, "到 launchd 为止就没有宿主")
        if let host = JumpService.shared.hostApp(of: me) { #expect(host.activationPolicy == .regular && host.bundleIdentifier != "com.anthropic.claude-code", "找到的宿主是普通 App，不是 CLI 包") }
        let j = try SPA.src("JumpService.swift")
        #expect(j.contains("for _ in 0..<12") && j.contains("app.activationPolicy == .regular, app.bundleIdentifier != \"com.anthropic.claude-code\"") && j.contains("kp_eproc.e_tdev") && j.contains("devname(dev_t(dev), mode_t(S_IFCHR))"))
    }

    /// 7.3 桌面 / VS Code / 其他宿主 / 激活的坑：深链用 NSWorkspace.open、2.5 秒后判定、连续 2 次失败停用、VS Code 用 open([cwd], withApplicationAt:)、激活一律 openApplication(at:configuration:) + activates = true。
    /// 真实的深链 / 激活 / 终端标签页选择要真实的 Claude 和 Terminal：这里钉住关键代码，判定逻辑本身见 JumpTests。
    @Test func theJumpServiceKeepsTheSpecifiedMechanisms() throws {
        let j = try SPA.src("JumpService.swift")
        #expect(j.contains("NSWorkspace.shared.open(url)") && j.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 2.5)"), "深链：NSWorkspace.open，2.5 秒后判定")
        #expect(j.contains("self.deepLinkFailures >= 2 && !self.deepLinkDisabled") && j.contains("self.deepLinkDisabled = true") && j.contains("self.onNotice?(Self.deepLinkDisabledNotice.title"), "连续失败 2 次：停用并给出提示")
        #expect(j.contains("NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: url"), "VS Code：用它打开 cwd")
        #expect(j.contains("cfg.activates = true") && j.contains("NSWorkspace.shared.openApplication(at: url, configuration: cfg"), "激活：openApplication + activates = true")
        let jumpCode = SourceAuditTests.code(j).map(\.line).joined(separator: "\n")
        #expect(!jumpCode.contains(".activate(options") && !jumpCode.contains(".activate()") && !jumpCode.contains("activate(ignoringOtherApps"), "不用会悄悄失败的 NSRunningApplication.activate()")
        #expect(j.contains("app.bundleIdentifier == \"com.apple.Terminal\", let tty = tty") && j.contains("} else { self.activate(appAt: url) }"), "Terminal 选标签页，其他宿主直接激活")
        let m = try SPA.src("AppModel.swift")
        #expect(SPA.before("JumpService.shared.jump(to: fresh)", "provider.markSeen(key: fresh.key)", in: m), "先跳转，再清未读")
        let s = JumpService()
        s.resetDeepLink()
        #expect(s.deepLinkFailures == 0 && !s.deepLinkDisabled && JumpService.claudeBundleID == "com.anthropic.claudefordesktop")
    }

    /// 7.3 自动化授权：Info.plist 里要有 NSAppleEventsUsageDescription，文案「点小人跳转到「终端」里对应的标签页时才会用到。」；重新编译会再问一遍，要写进使用说明。
    /// 7.2 重复提醒：设置里「桌面 App 会话也提醒」默认开着，使用说明里讲清楚。
    @Test func theBuildScriptAndTheManualSayWhatTheSpecRequires() throws {
        let script = try String(contentsOf: SPA.projectRoot.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("<key>NSAppleEventsUsageDescription</key><string>点小人跳转到「终端」里对应的标签页时才会用到。</string>"), "Info.plist 里的文案逐字一致")
        let manual = try String(contentsOf: SPA.projectRoot.appendingPathComponent("使用说明.txt"), encoding: .utf8)
        #expect(manual.contains("「自动化」授权在重新编译（重新安装）之后会再问一次"), "自动化授权每次重新编译会再问：写进了使用说明")
        #expect(manual.contains("可能和这里的提醒重复") && manual.contains("桌面 App 里的会话也提醒"), "使用说明讲清了桌面 App 自己也会发通知")
        let s = try SPA.src("SettingsView.swift")
        #expect(s.contains("@AppStorage(\"notify.includeDesktop\") var nDesktop = true") && s.contains("桌面 App 里的会话也提醒"))
    }

    /// 7.4 自动收起「监听 NSWorkspace.didTerminateApplicationNotification」（并且 Claude 重新打开要取消：didLaunch）。用一个记录订阅的假通知中心。
    @Test func autoQuitListensForApplicationTermination() {
        final class Recording: NotificationCenter, @unchecked Sendable {
            var names: [Notification.Name] = []
            override func addObserver(_ observer: Any, selector aSelector: Selector, name aName: NSNotification.Name?, object anObject: Any?) {
                if let n = aName { names.append(n) }
                super.addObserver(observer, selector: aSelector, name: aName, object: anObject)
            }
        }
        let c = Recording()
        let q = AutoQuit(center: c, scheduler: { _, _ in {} }, terminate: {}, log: { _ in })
        q.start()
        #expect(c.names.contains(NSWorkspace.didTerminateApplicationNotification) && c.names.contains(NSWorkspace.didLaunchApplicationNotification), "订阅了应用退出 / 启动：\(c.names)")
        #expect(AutoQuit.delayAfterClaudeQuits == 60)
    }

    /// 7.5「数据源诊断」页：活会话数、有没有检测到 hook + 最后一个事件的时间、各会话的 Claude Code version、深链测试、系统通知授权状态、各数据来源的降级状态。
    @Test func theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime() throws {
        var d = DiagnosticsInfo()
        d.liveSessionCount = 3; d.hookDetectedInSettings = true
        d.lastHookEventAt = Date(timeIntervalSince1970: 1_800_000_000)
        d.sessions = [DiagnosticsInfo.SessionDiag(key: "t:a", title: "重构", pid: 42, cliVersion: "2.1.284", hookActive: true, lastHookEventAt: nil, origin: .terminal)]
        d.sourceStatus = ["登记表: 正常", "FSEvents: 不可用，改用轮询"]
        let t = DiagnosticsFormatter.text(d, notifierStatus: "已拒绝", deepLinkDisabled: false, deepLinkFailures: 0)
        let stamp = DateFormatter.localizedString(from: d.lastHookEventAt!, dateStyle: .none, timeStyle: .medium)
        #expect(t.contains("活会话数：3") && t.contains("已在 settings.json 里注册，最后一个事件 \(stamp)"), "活会话数、hook、最后一个事件的时间：\(t)")
        #expect(t.contains("v2.1.284") && t.contains("系统通知：已拒绝") && t.contains("深链：可用") && t.contains("　FSEvents: 不可用，改用轮询"), "版本、通知授权、深链、每个来源的降级状态")
        let none = DiagnosticsFormatter.text(DiagnosticsInfo(), notifierStatus: "x", deepLinkDisabled: true, deepLinkFailures: 2)
        #expect(none.contains("没有检测到") && none.contains("深链：已停用（连续 2 次没生效）"))
        // 深链测试按钮：没有在场的桌面会话时只给一句说明，不会真的去跳
        let r = SPA.rig(buddies: 1, origin: .terminal)
        #expect(r.model.testDeepLink() == "没有在场的桌面 App 会话可以测试。")
        let v = try SPA.src("SettingsView.swift")
        #expect(v.contains("Button(\"测试深链（跳到当前会话）\")") && v.contains("Button(\"重新启用深链\")") && v.contains("Text(\"授权状态：\\(authText)\")") && v.contains("model.diagnosticsText"), "诊断页的按钮和授权状态")
    }

    /// 7.5 开机启动「默认关；优先 SMAppService.mainApp.register()，不行写 ~/Library/LaunchAgents/local.buddy-office.plist（运行 /usr/bin/open -b local.buddy-office）；只有用户打开开关才写」。
    /// 真的注册会往用户的登录项里加东西：单测不跑，钉住路径 / 参数 / 先后顺序 / 唯一调用点。
    @Test func loginItemUsesTheServiceManagementFirstThenTheSpecifiedLaunchAgentAndOnlyFromTheSwitch() throws {
        #expect(LoginItem.agentURL.path.hasSuffix("/Library/LaunchAgents/local.buddy-office.plist"))
        let s = try SPA.src("SystemHelpers.swift")
        #expect(SPA.before("try SMAppService.mainApp.register()", "\"Label\": \"local.buddy-office\"", in: s), "先 SMAppService，不行才写 LaunchAgent")
        #expect(s.contains("\"ProgramArguments\": [\"/usr/bin/open\", \"-g\", \"-b\", \"local.buddy-office\"]") && s.contains("\"RunAtLoad\": true"), "运行 /usr/bin/open -b local.buddy-office（多一个 -g，后台打开）")
        var callers: [String] = []
        for (name, text) in try SourceAudit.allOfficeSources() where name != "SystemHelpers.swift" {
            for (_, line) in SourceAuditTests.code(text) where line.contains("LoginItem.set(") { callers.append("\(name): \(line.trimmingCharacters(in: .whitespaces))") }
        }
        #expect(callers.count == 2 && callers.contains { $0.hasPrefix("SettingsView.swift") && $0.contains("LoginItem.set(on)") } && callers.contains { $0.hasPrefix("main.swift") && $0.contains("LoginItem.set(false)") },
                "只有设置页的开关（用户打开 / 关闭）和卸载脚本用的 --unregister-login（只会关）调用 LoginItem.set：\(callers)")
    }
}

// MARK: - 7.1 / 7.4 源码钉住（真正的 AppKit 行为没法在单测里做）
@Suite struct SpecTraceSourcePinTests {
    /// 7.1 宠物条点穿「不需要辅助功能权限」：没有任何辅助功能 / 全局事件监听 API。
    @Test func noAccessibilityPermissionAPIsAreUsed() throws {
        let bad = SourceAuditTests.offenders([#"AXIsProcessTrusted"#, #"AXUIElement"#, #"AXObserver"#, #"CGEvent\.tapCreate"#, #"CGEventTap"#, #"addGlobalMonitorForEvents"#, #"kAXTrustedCheckOptionPrompt"#],
                                             in: try SourceAudit.allOfficeSources())
        #expect(bad.isEmpty, "\(bad)")
        #expect(try SPA.src("StripPanelController.swift").contains("NSEvent.mouseLocation"), "点穿只读 NSEvent.mouseLocation")
    }

    /// 7.1 宠物条「每秒 30 次读 NSEvent.mouseLocation；鼠标离得超过 100 pt 降到每秒 10 次」「每 2 秒检查一次 visibleFrame」「监听 didChangeScreenParametersNotification」。
    /// （实际每 0.5 秒查一次 visibleFrame，比要求的 2 秒更勤。）
    @Test func theStripPollingRatesAndDistancesStayAsSpecified() throws {
        let s = try SPA.src("StripPanelController.swift")
        #expect(s.contains("Timer(timeInterval: 1.0 / 30, repeats: true)"), "30 Hz")
        #expect(s.contains("panel.frame.insetBy(dx: -100, dy: -100).contains(loc)") && s.contains("if !near && pollTick % 3 != 0 { return }"), "离得超过 100 pt：每 3 次只做 1 次 = 10 Hz")
        #expect(s.contains("if pollTick % 15 == 0 { repositionIfNeeded() }"), "30 Hz × 每 15 次 = 每 0.5 秒查一次 visibleFrame（≤ 2 秒）")
        #expect(s.contains("NSApplication.didChangeScreenParametersNotification"), "监听屏幕参数变化")
    }

    /// 7.1 悬停 250 ms 出卡片（办公室 / 小鱼缸 / 宠物条三个面都一样）。
    @Test func hoverCardsAppearAfter250msOnAllThreeSurfaces() throws {
        for f in ["OfficeWindowController.swift", "TankPanelController.swift", "StripPanelController.swift"] {
            #expect(try SPA.src(f).contains("hoverSince >= 0.25"), "\(f)：悬停 250 ms")
        }
    }

    /// 7.1 右键菜单：跳转、换个造型、隐藏这个 buddy、打开办公室（顺序）。菜单弹出是模态的，单测不去弹；每一项背后的行为（跳转 / 换造型 / 隐藏）各有测试。
    @Test func theContextMenuOffersJumpRerollHideAndOpenOfficeInThatOrder() throws {
        let m = try SPA.src("AppModel.swift")
        let items = ["ClosureMenuItem(\"跳转到「", "ClosureMenuItem(\"换个造型\")", "ClosureMenuItem(\"隐藏这个 buddy\")", "ClosureMenuItem(\"打开办公室\")"]
        for i in 1..<items.count { #expect(SPA.before(items[i - 1], items[i], in: m), "\(items[i - 1]) 应该在 \(items[i]) 之前") }
        #expect(m.contains("self?.provider.rerollAppearance(key: s.key); self?.director.reroll(key: s.key)") && m.contains("h.insert(s.key); self.settings.hiddenKeys = h"))
    }

    /// 7.1 Dock「默认显示 Dock 图标；隐藏时切换成 .accessory」「从 Dock 重新打开 App 时显示办公室窗口」「关闭只是隐藏，App 继续运行」；可选的全局快捷键 ⌃⌥⌘B（Carbon，不需要辅助功能权限）。
    @Test func dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified() throws {
        let a = try SPA.src("AppDelegate.swift"), m = try SPA.src("AppModel.swift"), w = try SPA.src("OfficeWindowController.swift"), h = try SPA.src("SystemHelpers.swift")
        #expect(m.contains("NSApp.setActivationPolicy(regular ? .regular : .accessory)"), "Dock 图标：.regular / .accessory")
        #expect(a.contains("func applicationShouldHandleReopen") && SPA.before("model.showOffice()", "return true", in: String(a[a.range(of: "func applicationShouldHandleReopen")!.lowerBound...])), "从 Dock 重新打开：显示办公室窗口")
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared), "关掉最后一个窗口 App 继续运行")
        let close = String(w[w.range(of: "func windowShouldClose")!.lowerBound...])
        #expect(close.contains("sender.orderOut(nil)") && close.contains("return false"), "点关闭只是隐藏窗口")
        #expect(h.contains("RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey)"), "⌃⌥⌘B")
        #expect(SPA.before("office.render(model: self, force: true)", "office.showWindow(nil)", in: m), "先渲染好第一帧，再把办公室窗口显示出来")
        // App 关掉之后的窗口位置 / 跟着 Claude 开收的形态：启动时按上次的形态出现（office / tank / strip.visible 从设置读）
        #expect(m.contains("FormInputs(office: settings.bool(\"office.visible\"), tank: settings.bool(\"tank.visible\"), strip: settings.bool(\"strip.visible\")"))
    }

    /// 7.1 标题栏三个按钮各自接到：缩成小鱼缸 / 开关桌面宠物（不动办公室）/ 设置。（接线在 AppModel.start()，单测不起真窗口，钉住接线。）
    @Test func theTitleBarButtonsAreWiredToTheThreeActions() throws {
        let m = try SPA.src("AppModel.swift")
        #expect(m.contains("tb.tank.onClick = { [weak self] in self?.shrinkToTank() }"), "缩成小鱼缸")
        #expect(m.contains("tb.strip.onClick = { [weak self] in guard let self = self else { return }; self.settings.set(!self.settings.bool(\"strip.visible\"), \"strip.visible\") }"), "桌面宠物是开关，不动办公室")
        #expect(m.contains("tb.settings.onClick = { [weak self] in self?.showSettings() }"), "设置")
        #expect(m.contains("office.titleBar.bar.update(tankOn: cur.tank, stripOn: cur.strip)"), "对应形态开着的时候按钮亮着")
    }

    /// 7.2 不打扰（桌面会话）：「Claude.app 在最前面，而且这个会话的 lastFocusedAt 是所有会话里最新的」。判定拆成两半：前台 App 的 bundle id 是 Claude、这个会话是最近聚焦的（后一半有纯函数测试）。
    @Test func theDesktopLookingRuleUsesTheFrontmostClaudeAndTheMostRecentlyFocusedSession() throws {
        let m = try SPA.src("AppModel.swift")
        #expect(m.contains("guard front?.bundleIdentifier == JumpService.claudeBundleID, let h = s.hostSessionId else { return false }") && m.contains("DesktopMeta.cache.isMostRecentlyFocused(host: h)"))
        #expect(DesktopMeta.mostRecentHost(["local_a": 5, "local_b": 9, "local_c": 7]) == "local_b", "lastFocusedAt 最新的那个")
    }
}
