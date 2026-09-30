import Testing
import AppKit
import Foundation
@testable import BuddyCore
import BuddyStage
import PixelKit
@testable import BuddyOffice

/// 收尾前的独立复查（QA/review-R2.md）新发现的应用层问题的回归测试。编号对应 QA/issues-review.md。
/// 面板 / 视图对象只建不显示（不弹窗口）。
@MainActor @Suite struct ReviewRegressionAppTests {
    typealias AC = AlertCoordinatorTests
    let cfg = AlertConfig()
    let nobody: (BuddySnapshot) -> Bool = { _ in false }

    // MARK: R2-001 缩放变了但画布没变：图像层不跟着变大小

    @Test("R2-001 PixelView：画布没变、只有缩放变了（局部重绘的场景知道「没变」）时，图像层也要跟着新缩放变大小")
    func r2001_theImageLayerFollowsTheZoomWhenOnlyTheZoomChanged() {
        let canvas = Canvas(width: 40, height: 30)
        var f = Frame(canvas: canvas)
        f.changeKnown = true; f.canvasChanged = true
        let pv = PixelView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        pv.show(f, zoom: 2)
        func imageWidth() -> CGFloat? { pv.layer?.sublayers?.first?.frame.width }
        #expect(imageWidth() == 80, "2 倍：40 × 2")
        f.canvasChanged = false                                                  // 局部重绘：什么都没变
        pv.show(f, zoom: 1)
        #expect(imageWidth() == 40, "缩放改成 1 倍：图像层该是 40，实际 \(String(describing: imageWidth()))")
        pv.show(f, zoom: 3)
        #expect(imageWidth() == 120, "缩放改成 3 倍：图像层该是 120，实际 \(String(describing: imageWidth()))")
        // 场景不知道变没变（要自己哈希）时也一样
        var g = Frame(canvas: canvas)
        let pv2 = PixelView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        pv2.show(g, zoom: 2)
        g.changeKnown = false
        pv2.show(g, zoom: 1)
        #expect(pv2.layer?.sublayers?.first?.frame.width == 40, "不知道变没变的场景：缩放变了图像层也要变")
    }

    @Test("R2-001 真实的小鱼缸控制器：运行中把缩放从 2 改成 1，下一拍图像层就是新大小（不是等画布下一次变化）")
    func r2001_theTankFollowsAZoomChangeOnTheNextRender() {
        let store = Fx.Store(); defer { store.cleanUp() }
        let p = FakeProvider()
        let m = AppModel(provider: p, args: [], settings: store.settings)
        p.onUpdate?((0..<3).map { Fx.snap("t:\($0)", seat: $0, activity: .idle) })
        let tank = m.tank
        _ = tank.render(model: m, force: true)
        tank.zoom = 1
        _ = tank.render(model: m, force: true)
        let viewW = tank.pixelView.frame.width
        let imageW = tank.pixelView.layer?.sublayers?.first?.frame.width
        #expect(imageW == viewW, "小鱼缸缩放 2 → 1：窗口内容 \(viewW) 宽，图像层却是 \(String(describing: imageW))")
        tank.hide()
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame BuddyOfficeTankPanel")
    }

    // MARK: R2-002 提示卡先闪在终点位置

    @Test("R2-002 提示卡出现：orderFront 的那一刻面板已经在屏幕外的起点，不能先出现在终点位置再跳走；新提示卡到来时已有的不被拽回终点")
    func r2002_aToastIsOffscreenWhenItIsOrderedFrontAndNeighboursAreNotYanked() {
        let tc = ToastController()
        var atOrderFront: [NSRect] = []
        tc.orderFront = { atOrderFront.append($0.frame) }                          // 不真的显示窗口
        tc.show(key: "a", kind: .approval, title: "Buddy 办公室", body: "有个权限请求（等你批准）")
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 800)
        #expect(atOrderFront.count == 1)
        #expect((atOrderFront.first?.minX ?? 0) >= vf.maxX, "orderFront 时提示卡在 x=\(atOrderFront.first?.minX ?? 0)，屏幕右边缘是 \(vf.maxX)：不该先出现在终点位置")
        // 让第一张滑到位（弹簧跑几百拍），然后来第二张：第一张的 x 不能被拽回终点或起点
        for _ in 0..<400 { tc.step() }
        let settledX = tc.toasts.first?.panel.frame.minX
        tc.show(key: "b", kind: .finished, title: "Buddy 办公室", body: "做完了")
        let a = tc.toasts.first { $0.key == "a" }
        #expect(a != nil && abs((a?.panel.frame.minX ?? 0) - (settledX ?? 0)) < 1, "新提示卡到来时，已经滑到位的那张 x 从 \(String(describing: settledX)) 变成了 \(String(describing: a?.panel.frame.minX))")
        let b = atOrderFront.last
        #expect((b?.minX ?? 0) >= vf.maxX, "第二张 orderFront 时也该在屏幕外：\(String(describing: b?.minX))")
        for t in tc.toasts { t.panel.orderOut(nil) }
        tc.dismiss(key: "a"); tc.dismiss(key: "b")
    }

    // MARK: R2-003 合并提醒里含 blocked：先发出又立刻撤掉

    @Test("R2-003 两个会话先后「做完了要你处理」（blocked）：合并出来的「N 位同事有事找你」要留着，不能在同一次判定里被撤掉")
    func r2003_aMergedAlertWithBlockedSessionsIsNotClearedImmediately() {
        let c = AlertCoordinator()
        func obs(_ t: Double, _ ss: [BuddySnapshot]) -> [AlertCoordinator.Output] { c.observe(ss, now: AC.at(t), config: cfg, isLooking: nobody, privacy: false) }
        func multiPosted(_ out: [AlertCoordinator.Output]) -> Bool { out.contains { if case .post(let k, _, _, _) = $0, k == AlertCoordinator.multiKey { return true } else { return false } } }
        func multiCleared(_ out: [AlertCoordinator.Output]) -> Bool { out.contains { if case .clear(let k) = $0, k == AlertCoordinator.multiKey { return true } else { return false } } }
        let blockedA = AC.finished("d:a", origin: .desktop, duration: 60, blocked: true, seat: 0)
        let blockedB = AC.finished("d:b", origin: .desktop, duration: 60, blocked: true, seat: 1)
        _ = obs(0, [AC.busy("d:a", origin: .desktop, seat: 0), AC.busy("d:b", origin: .desktop, seat: 1)])
        var posted = false, cleared = false
        for (t, ss) in [(1.0, [blockedA, AC.busy("d:b", origin: .desktop, seat: 1)]), (2.0, [blockedA, blockedB])] {
            let out = obs(t, ss)
            posted = posted || multiPosted(out); cleared = cleared || multiCleared(out)
        }
        for t in stride(from: 2.09, through: 6.0, by: 0.09) {
            let out = obs(t, [blockedA, blockedB])
            cleared = cleared || multiCleared(out)
        }
        #expect(posted, "两个 blocked 会话应该合并出一条提醒")
        #expect(!cleared, "合并出来的提醒被撤掉了（用户什么都看不到）")
    }

    // MARK: R2-004 被 20 秒节流挡掉的「等你」提醒整段丢弃

    @Test("R2-004 「等你」提醒被 20 秒节流挡住之后：这段等待没有提醒过，节流窗口一过、还在等就补发一条（不再重复）")
    func r2004_aThrottledWaitingAlertIsDeliveredWhenTheWindowPasses() {
        let c = AlertCoordinator()
        var posts: [Double] = []
        func obs(_ t: Double, _ s: BuddySnapshot) {
            if !AC.posts(c.observe([s], now: AC.at(t), config: cfg, isLooking: nobody, privacy: false)).isEmpty { posts.append(t) }
        }
        obs(0, AC.waiting("t:a"))
        for t in stride(from: 0.09, through: 1.6, by: 0.09) { obs(t, AC.waiting("t:a")) }        // 第一条在 1.5 秒左右
        for t in stride(from: 1.7, through: 3.0, by: 0.1) { obs(t, AC.busy("t:a")) }             // 用户批准了
        for t in stride(from: 4.0, through: 120.0, by: 0.09) { obs(t, AC.waiting("t:a")) }       // 第二次请求，用户走开了，一直等
        #expect(posts.count == 2, "第一条 + 节流窗口过去之后补发的一条，实际 \(posts.map { String(format: "%.2f", $0) })")
        if posts.count >= 2 {
            #expect(posts[0] < 2, "第一条在等待 1.5 秒左右：\(posts[0])")
            #expect(posts[1] >= 20 && posts[1] < 24, "补发的一条在节流窗口（第一条 + 20 秒）刚过的时候：\(posts[1])")
        }
    }

    // MARK: R2-006 隐私模式没盖住设置页诊断和深链回执里的会话标题

    @Test("R2-006 隐私模式：「数据源诊断」文字和「测试深链」回执里不显示会话标题（共享屏幕时打开设置页不会露标题）")
    func r2006_privacyModeHidesSessionTitlesInTheDiagnosticsAndTheDeepLinkReceipt() {
        var d = DiagnosticsInfo()
        d.liveSessionCount = 1
        d.sessions = [DiagnosticsInfo.SessionDiag(key: "t:a", title: "帮我转账到 6222-秘密账号", pid: 42, cliVersion: "2.1.0", hookActive: true, lastHookEventAt: nil, origin: .terminal)]
        let shown = DiagnosticsFormatter.text(d, notifierStatus: "x", deepLinkDisabled: false, deepLinkFailures: 0, privacy: false)
        let hidden = DiagnosticsFormatter.text(d, notifierStatus: "x", deepLinkDisabled: false, deepLinkFailures: 0, privacy: true)
        #expect(shown.contains("秘密账号"), "不开隐私模式时照旧显示标题")
        #expect(!hidden.contains("秘密账号") && hidden.contains("· 会话　pid 42"), "隐私模式下诊断文字泄露了标题：\(hidden)")
        // 默认参数（不传 privacy）= 不隐藏，老的调用方不受影响
        #expect(DiagnosticsFormatter.text(d, notifierStatus: "x", deepLinkDisabled: false, deepLinkFailures: 0).contains("秘密账号"))
        #expect(AppModel.deepLinkReceipt(title: "帮我转账到 6222-秘密账号", privacy: true) == "已向「会话」发出深链跳转；2.5 秒后如果没生效会自动改为直接打开 Claude。")
        #expect(AppModel.deepLinkReceipt(title: "论文", privacy: false).hasPrefix("已向「论文」发出深链跳转"))
    }

    // MARK: R2-007 测试进程里 DebugTools.enabled 恒为真

    @Test("R2-007 测试宿主进程的 --test-bundle-path 不算开发开关：测试里 DebugTools.enabled 必须是 false（不然被测代码里加一行 DebugTools.log 就会往用户真实的日志文件里写）")
    func r2007_theTestHostsOwnArgumentsAreNotDevelopmentFlags() {
        #expect(!DebugTools.devFlagsPresent(["/x/swiftpm-testing-helper", "--test-bundle-path", "/x/BuddyOfficePackageTests.xctest/Contents/MacOS/BuddyOfficePackageTests"]))
        #expect(!DebugTools.enabled, "测试进程里日志开关是开着的（命令行：\(CommandLine.arguments)）")
        // 真正的开发开关仍然有效
        for f in ["--test-jump", "--test-autoquit", "--test-titlebar", "--test-minimize", "--test-tank-click", "--test-hotkey", "--dump-window", "--dump-settings", "--dump-titlebar", "--dump-panels", "--log-ui", "--prof", "--self-test", "--probe-pid"] {
            #expect(DebugTools.devFlagsPresent([f]), "\(f)")
        }
    }

    // MARK: R2-008 DesktopMeta 不认 --data-root

    @Test("R2-008 用 --data-root 起的开发副本：应用层读桌面元数据的根目录也跟着换成假 home（不再读真实的桌面会话元数据）")
    func r2008_theDataRootArgumentAlsoMovesTheDesktopMetaBase() {
        DesktopMetaGate.exclusive {                                   // baseOverride 是进程全局的：和别的写它的测试互斥（R3b-01）
            #expect(DesktopMeta.base.hasSuffix("/Library/Application Support/Claude/claude-code-sessions"))
            #expect(DesktopMeta.base.hasPrefix(NSHomeDirectory()))
            let store = Fx.Store(); defer { store.cleanUp() }
            _ = RealProvider.make(args: ["--data-root", "/x/fake-home", "--poll"], settings: store.settings)
            #expect(DesktopMeta.baseOverride == "/x/fake-home/Library/Application Support/Claude/claude-code-sessions", "\(String(describing: DesktopMeta.baseOverride))")
        }
    }

    // MARK: R2-014 系统时钟往回拨时，去抖 / 节流把提醒压住

    @Test("R2-014 系统时钟被往回拨（手动改时间 / NTP 校正）：节流记录里「来自未来」的时间当作已过期，新的一段等待照常提醒")
    func r2014_aClockThatWentBackwardsDoesNotSuppressAlerts() {
        let c = AlertCoordinator()
        var posts: [Double] = []
        func obs(_ t: Double, _ s: BuddySnapshot) {
            if !AC.posts(c.observe([s], now: AC.at(t), config: cfg, isLooking: nobody, privacy: false)).isEmpty { posts.append(t) }
        }
        obs(1000, AC.waiting("t:a"))
        for t in stride(from: 1000.09, through: 1002.0, by: 0.09) { obs(t, AC.waiting("t:a")) }        // 第一条在 1001.5 秒左右
        for t in stride(from: 1002.1, through: 1003.0, by: 0.1) { obs(t, AC.busy("t:a")) }             // 批准
        // 时钟被拨回 900 秒：新的一段等待从 t=100 开始
        obs(100, AC.waiting("t:a"))
        for t in stride(from: 100.09, through: 104.0, by: 0.09) { obs(t, AC.waiting("t:a")) }
        #expect(posts.count == 2, "两段等待各该有一条提醒：\(posts.map { String(format: "%.2f", $0) })")
        if posts.count == 2 { #expect(posts[1] < 103, "拨回之后的那段等待该在 ≈101.5 提醒，实际 \(posts[1])（被压了约 \(posts[1] - 101.5) 秒）") }
    }

    // MARK: R2-016 每次改窗口尺寸都新建 3 块 IOSurface（CoreAnimation 长期保留用过的）

    /// 拖窗口边缘时每一步的视口都不一样：原来每一步都新建 3 块 IOSurface，而 CoreAnimation 会长期保留用过的 surface
    /// （复查实测：可见窗口里随机尺寸 300 次，测试宿主里物理占用 57 → 261 MB 不回落；真实开发副本 +21 MB，一次 60 秒内回落、一次 2 分钟没回落）。
    /// 现在 surface 的宽高向上取整到 64 像素的「桶」，只在跨桶时才重建，用 `contentsRect` 裁出视口那一块。
    @Test("R2-016 拖窗口边缘（视口宽度一步一步变）：IOSurface 只在跨 64 像素的桶时才重建，不是每一步都新建一组")
    func r2016_resizingDoesNotAllocateANewSurfaceSetForEverySmallStep() {
        let canvas = Canvas(width: 400, height: 300)
        let pv = PixelView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var seen = Set<ObjectIdentifier>()
        for w in 200...299 {                                                        // 100 步，宽度每步 +1（跨 64 的倍数 256 一次）
            var f = Frame(canvas: canvas, viewport: IntRect(0, 0, w, 150))
            f.changeKnown = true; f.canvasChanged = true
            pv.show(f, zoom: 1)
            if let surf = pv.layer?.sublayers?.first?.contents as? IOSurface { seen.insert(ObjectIdentifier(surf)) }
        }
        #expect(seen.count > 0 && seen.count <= 6, "100 步里用过 \(seen.count) 块不同的 IOSurface（应该 ≤ 6：一个桶 3 块，跨了一次桶边界）")
    }

    @Test("R2-016 用桶（比视口大）的 surface 时，显示出来的部分正好是视口：contentsRect 是 视口 / surface，图层尺寸 = 视口 × 缩放，左上角的像素就是画布的像素")
    func r2016_theShownPartOfABucketedSurfaceIsExactlyTheViewport() {
        let canvas = Canvas(width: 100, height: 80)
        canvas.fillAll(color: RGBA8(10, 20, 30, 255))
        for y in 0..<3 { for x in 0..<3 { canvas.setRaw(x, y, color: RGBA8(200, 100, 50, 255)) } }       // 左上角三个像素见方做标记
        let pv = PixelView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        var f = Frame(canvas: canvas, viewport: IntRect(0, 0, 70, 50))
        f.changeKnown = true; f.canvasChanged = true
        pv.show(f, zoom: 3)
        guard let layer = pv.layer?.sublayers?.first, let surf = layer.contents as? IOSurface else { Issue.record("图像层没有 IOSurface 内容"); return }
        #expect(layer.frame.size == CGSize(width: 210, height: 150), "图层 = 视口 × 缩放：\(layer.frame.size)")
        let sw = CGFloat(surf.width), sh = CGFloat(surf.height)
        #expect(sw >= 70 && sh >= 50 && Int(sw) % 64 == 0 && Int(sh) % 64 == 0, "surface 向上取整到 64 的倍数：\(surf.width) × \(surf.height)")
        #expect(abs(layer.contentsRect.width - 70 / sw) < 1e-9 && abs(layer.contentsRect.height - 50 / sh) < 1e-9 && layer.contentsRect.origin == .zero, "contentsRect \(layer.contentsRect)")
        surf.lock(options: .readOnly, seed: nil); defer { surf.unlock(options: .readOnly, seed: nil) }
        let base = surf.baseAddress.assumingMemoryBound(to: UInt8.self)
        func px(_ x: Int, _ y: Int) -> [UInt8] { let o = y * surf.bytesPerRow + x * 4; return [base[o], base[o + 1], base[o + 2], base[o + 3]] }
        #expect(px(0, 0) == [50, 100, 200, 255], "BGRA：左上角标记 \(px(0, 0))")
        #expect(px(69, 49) == [30, 20, 10, 255], "视口右下角的像素是画布的底色 \(px(69, 49))")
        // 视口变到同一个桶里的另一个大小（70×50 和 100×60 都落在 128×64 的桶里）：仍然是同一批 surface（不重建），contentsRect 跟着变
        var g = Frame(canvas: canvas, viewport: IntRect(0, 0, 100, 60)); g.changeKnown = true; g.canvasChanged = true
        pv.show(g, zoom: 3)
        let layer2 = pv.layer?.sublayers?.first
        #expect(layer2?.frame.size == CGSize(width: 300, height: 180))
        #expect((layer2?.contents as? IOSurface).map { $0.width == surf.width && $0.height == surf.height } == true, "同一个桶：surface 的尺寸不变")
        #expect(abs((layer2?.contentsRect.width ?? 0) - 100 / sw) < 1e-9 && abs((layer2?.contentsRect.height ?? 0) - 60 / sh) < 1e-9, "同一个桶里视口变了，contentsRect 跟着变：\(String(describing: layer2?.contentsRect))")
    }

    @Test("R2-016 分桶的 surface 渲染出来和「按缩放放大的画布」逐像素一致：contentsRect 裁得正好，不偏一个像素、边上没有混色")
    func r2016_aBucketedSurfaceRendersPixelIdenticallyToTheScaledCanvas() {
        let w = 70, h = 50, z = 3                                           // 70×50 的视口落在 128×64 的桶里：surface 比视口大，真的走裁剪
        func col(_ x: Int, _ y: Int) -> RGBA8 { RGBA8(UInt8((x * 5 + 20) % 251), UInt8((y * 11 + 40) % 241), UInt8((x * 3 + y * 7) % 239), 255) }
        let canvas = Canvas(width: 100, height: 80)
        for y in 0..<80 { for x in 0..<100 { canvas.setRaw(x, y, color: col(x, y)) } }
        let pv = PixelView(frame: NSRect(x: 0, y: 0, width: w * z, height: h * z))
        var f = Frame(canvas: canvas, viewport: IntRect(0, 0, w, h)); f.changeKnown = true; f.canvasChanged = true
        pv.show(f, zoom: z)
        guard let layer = pv.layer, let surf = layer.sublayers?.first?.contents as? IOSurface else { Issue.record("图像层没有 IOSurface 内容"); return }
        #expect(surf.width > w && surf.height > h, "这个用例要真的走「surface 比视口大」的裁剪：\(surf.width)×\(surf.height)")
        let pw = w * z, ph = h * z
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let data = ctx.data else { Issue.record("建不了位图"); return }
        layer.render(in: ctx)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        // CALayer.render(in:) 放大时是插值的（不看 magnificationFilter），只有每个 z×z 方块正中间的那个像素等于画布像素本身：
        // 所以逐块比中心像素——裁剪偏了一个像素，中心像素就会是邻居的颜色。图层朝上还是朝下由 AppKit 决定：两种朝向各比一遍，整张图必须在其中一种朝向下全部一致
        func mismatches(flipped: Bool) -> Int {
            var bad = 0
            for cy in 0..<h { for cx in 0..<w {
                let px = cx * z + z / 2, py = (flipped ? h - 1 - cy : cy) * z + z / 2       // 翻转时位图第 0 行是画布最下面一行
                let e = col(cx, cy), o = py * pw * 4 + px * 4
                if bytes[o] != e.b || bytes[o + 1] != e.g || bytes[o + 2] != e.r || bytes[o + 3] != 255 { bad += 1 }
            } }
            return bad
        }
        let up = mismatches(flipped: false), down = mismatches(flipped: true)
        #expect(min(up, down) == 0, "渲染结果和画布不一致：正向 \(up) 个方块的中心像素不同、翻转 \(down) 个不同（共 \(w * h) 个方块）")
    }

    // MARK: R3c-01 合并提醒的人数 / R3c-02 通知授权运行期间被关掉

    /// A 在 1.5 秒提醒、B 在 1.9 秒提醒（合并成「2 位」，A、B 各自的卡被撤掉），C 在 3.5 秒提醒（比 B 晚 1.6 秒、比 A 晚 2.0 秒）：
    /// 原来的合并卡只数最近 2 秒里发出的条数（B、C），写成「2 位同事在等你」，A 没有任何卡盖着了，而三个人都在等。
    @Test("R3c-01 三个人的等待提醒先后到（相邻两条 < 2 秒、首尾 ≥ 2 秒）：最后一张合并卡写「3 位同事在等你」，A 不能被落下")
    func r3c01_theMergedCountIncludesEveryoneAlreadyFoldedIntoTheCard() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        var lastMulti: String?
        for t in 0...40 {
            let sec = Double(t) / 10
            var ss = [AC.waiting("t:a", seat: 0)]                                                 // A 从 0 开始等 → 1.5 提醒
            if sec >= 0.4 { ss.append(AC.waiting("t:b", seat: 1)) }                               // B 从 0.4 开始等 → 1.9 提醒
            if sec >= 2.0 { ss.append(AC.waiting("t:c", seat: 2)) }                               // C 从 2.0 开始等 → 3.5 提醒
            for o in c.observe(ss, now: AC.at(sec), config: cfg, isLooking: nobody, privacy: false) {
                if case .post(let k, _, _, let body) = o, k == AlertCoordinator.multiKey { lastMulti = body }
            }
        }
        #expect(c.waitingKeys.count == 3)
        #expect(lastMulti == "3 位同事在等你", "三个人都在等，最后一张合并卡写的是「\(lastMulti ?? "无")」")
    }

    @Test("R3c-01 合并卡只带「还在等」的人：A 在 C 到之前已经处理掉了，最后一张合并卡就是「2 位同事在等你」（B、C）")
    func r3c01_aPersonWhoStoppedWaitingIsNotCarriedIntoTheNextMergedCard() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        var lastMulti: String?
        for t in 0...40 {
            let sec = Double(t) / 10
            var ss: [BuddySnapshot] = []
            if sec < 2.5 { ss.append(AC.waiting("t:a", seat: 0)) }                                // A 在 2.5 秒被批准了
            if sec >= 0.4 { ss.append(AC.waiting("t:b", seat: 1)) }
            if sec >= 2.0 { ss.append(AC.waiting("t:c", seat: 2)) }
            for o in c.observe(ss, now: AC.at(sec), config: cfg, isLooking: nobody, privacy: false) {
                if case .post(let k, _, _, let body) = o, k == AlertCoordinator.multiKey { lastMulti = body }
            }
        }
        #expect(lastMulti == "2 位同事在等你", "A 已经不在等了，合并卡写的是「\(lastMulti ?? "无")」")
    }

    /// 缓存里的授权状态是启动 / 窗口出现 / 设置页打开时读的：用户在「系统设置 → 通知」里把它关了而 Buddy 一直在后台，
    /// `post` 仍把提醒交给系统，被系统悄悄吞掉，兜底的像素提示卡永远不出现。
    @Test("R3c-02 系统通知授权在运行期间被关掉：发出系统通知后再读一次真实状态，已经被拒了就补一张兜底提示卡；仍然授权的不补")
    func r3c02_aRevokedSystemAuthorizationStillGetsTheFallbackToast() {
        Fx.withSettings { _, d in
            let center = FakeCenter(status: .authorized), toast = FakeToast()
            let n = NotificationService(client: center, toast: toast, playSound: { _, _ in }, available: true, defaults: d)
            #expect(n.systemAllowed)
            n.post(key: "t:ok", kind: .approval, title: "t", body: "b", sound: "none")           // 一直授权着：只走系统通知，没有提示卡
            #expect(center.added.count == 1 && toast.shown.isEmpty, "已授权：系统通知 \(center.added.count) 条、提示卡 \(toast.shown.count) 张")
            center.status = .denied                                                              // 用户把「通知」关了
            n.post(key: "t:a", kind: .approval, title: "t", body: "b", sound: "none")
            #expect(toast.shown.count == 1 && toast.shown.first?.key == "t:a", "系统通知已被拒绝，兜底提示卡应该补上：\(toast.shown.count) 张")
            #expect(!n.systemAllowed, "缓存的授权状态也应该更新成已拒绝")
            n.post(key: "t:b", kind: .approval, title: "t", body: "b", sound: "none")            // 之后的提醒直接走兜底（不再交给系统）
            #expect(toast.shown.count == 2 && center.added.count == 2, "之后的提醒直接走兜底：提示卡 \(toast.shown.count) 张、系统通知 \(center.added.count) 条")
        }
    }

    // MARK: R4a-01 应用层读桌面元数据的未来时间戳

    /// R3a-02 只修了引擎侧的读取器；应用层（提醒判定的「你正在看这个会话吗」、点击跳转前后的 lastFocusedAt）有自己的第二份读取 + 解析，走的是原始值：
    /// 一个 lastFocusedAt 在 30 天以后的会话永远是「最近聚焦的」——它的等批准 / 做完了被当成「你一直在看」而不提醒，真正在看的那个会话反而照样弹提示卡。
    @Test("R4a-01 应用层读桌面元数据：某个会话的 lastFocusedAt 在 30 天以后（桌面 App 的时钟被拨快过）→ 丢掉它，「最近聚焦的」仍是真正在看的那个")
    func r4a01_theAppLayerDropsAFutureLastFocusedAt() {
        DesktopMetaGate.exclusive {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("r4a01-\(UUID().uuidString)")
            let dir = root.appendingPathComponent("acct/org")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let nowMs = Date().timeIntervalSince1970 * 1000
            try? #"{"sessionId":"local_x","lastFocusedAt":\#(nowMs + 30 * 86_400_000)}"#.write(to: dir.appendingPathComponent("local_x.json"), atomically: true, encoding: .utf8)
            try? #"{"sessionId":"local_y","lastFocusedAt":\#(nowMs - 5_000)}"#.write(to: dir.appendingPathComponent("local_y.json"), atomically: true, encoding: .utf8)
            DesktopMeta.baseOverride = root.path
            let all = DesktopMeta.readAll()
            #expect(all["local_x"] == nil && all["local_y"] != nil, "未来的聚焦时间应该被丢掉：\(all)")
            #expect(DesktopMeta.mostRecentHost(all) == "local_y")
            #expect(DesktopMeta.isMostRecentlyFocused(host: "local_y") && !DesktopMeta.isMostRecentlyFocused(host: "local_x"), "未来的那个不能永远是「最近聚焦的」")
        }
    }

    // MARK: R5a-01 出错提醒漏了两道闸

    /// 出错提醒原来只看「出错时也提醒」开关和节流；等待类和做完了都还要过「桌面 App 里的会话也提醒」和「你正在看那个会话时不提醒」两道闸（使用说明.txt 也是这么写的）。
    @Test("R5a-01 出错提醒也过两道闸：桌面会话在「桌面 App 里的会话也提醒」关着时不提醒；你正在看那个会话时不提醒；都不挡时照常提醒")
    func r5a01_errorAlertsRespectTheDesktopAndLookingGates() {
        func errorPosts(origin: SessionOrigin, includeDesktop: Bool, suppress: Bool, looking: Bool) -> Int {
            var cfg = AlertConfig(); cfg.error = true; cfg.includeDesktop = includeDesktop; cfg.suppressWhenFocused = suppress
            let c = AlertCoordinator()
            let busy = Fx.snap("t:a", origin: origin, activity: .thinking), err = Fx.snap("t:a", origin: origin, activity: .errored)
            _ = c.observe([busy], now: AC.at(0), config: cfg, isLooking: { _ in looking }, privacy: false)
            return AC.posts(c.observe([err], now: AC.at(1), config: cfg, isLooking: { _ in looking }, privacy: false)).count
        }
        #expect(errorPosts(origin: .desktop, includeDesktop: false, suppress: true, looking: false) == 0, "桌面会话 + 「桌面会话也提醒」关着：不该提醒")
        #expect(errorPosts(origin: .terminal, includeDesktop: false, suppress: true, looking: true) == 0, "你正在看这个会话：不该提醒")
        #expect(errorPosts(origin: .desktop, includeDesktop: true, suppress: true, looking: true) == 0, "桌面会话、你正在看：不该提醒")
        #expect(errorPosts(origin: .terminal, includeDesktop: false, suppress: true, looking: false) == 1, "终端会话、没人在看：照常提醒（includeDesktop 只管桌面会话）")
        #expect(errorPosts(origin: .desktop, includeDesktop: true, suppress: true, looking: false) == 1, "桌面会话、开着、没在看：照常提醒")
        #expect(errorPosts(origin: .terminal, includeDesktop: true, suppress: false, looking: true) == 1, "「正在看时不提醒」关着：你在看也照常提醒")
    }

    // MARK: R2-017 办公室窗口没关 animationBehavior（B-010 的同类）

    @Test("R2-017 办公室窗口（普通 NSWindow）也关掉 AppKit 的窗口出现 / 消失动画：快速 show / hide 时动画线程不会一路涨（B-010 的同类）")
    func r2017_theOfficeWindowHasWindowAnimationsTurnedOff() {
        let wc = OfficeWindowController()
        #expect(wc.window?.animationBehavior == NSWindow.AnimationBehavior.none, "办公室窗口：\(String(describing: wc.window?.animationBehavior))")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame BuddyOfficeMainWindow")
    }
}
