import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// QA 应用层修复的回归测试（BuddyStage / PixelKit 一侧）：白板计数越界（A-005）、画布输出越界（A-009）、座位号无上限（A-011）、
/// 同一会话再次走进办公室（A-008）、「换个造型」三处一致（A-007）、只增不减的字典（A-018 / A-027）。
@Suite struct AppLayerFixTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func snap(_ key: String, seat: Int, later: Bool = true, salt: UInt64 = 1, activity: Activity = .idle) -> BuddySnapshot {
        var s = BuddySnapshot(key: key, seat: seat, salt: salt, title: "会话 \(key)", sessionId: key, origin: .terminal, activity: activity, now: base)
        s.appearedAfterLaunch = later
        return s
    }

    // MARK: A-005 白板计数
    /// 计数 ≤ -5 时 drawTally 的区间是 0..<负数，运行时陷阱；负数应当和 0 画得一模一样，巨大值不崩。
    @Test func whiteboardTallyNeverTrapsAndNegativeCountsAsZero() {
        let lay = OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 3)
        let room = RoomRenderer(layout: lay)
        let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        func draw(_ n: Int) -> UInt64 {
            let c = Canvas(width: 60, height: 40)
            room.drawTally(c, IntRect(0, 0, 60, 40), n, st)
            return c.contentHash()
        }
        let zero = draw(0)
        for n in [-1, -4, -5, -6, -100, Int.min, Int.min + 1] { #expect(draw(n) == zero, "tally = \(n)") }
        #expect(draw(75) == draw(Int.max), "满 15 个「正」字之后画不下：再多也一样")
        #expect(draw(5) != zero)
    }

    // MARK: A-009 writeBGRA
    /// crop 和画布不相交（或宽高为 0）时，原来会退化成「整张画布」写进目标内存——目标是按 crop 大小分配的 IOSurface，就越界了。应该什么都不写。
    @Test func writeBGRAWithACropOutsideTheCanvasWritesNothing() {
        let w = 8, h = 6
        let c = Canvas(width: w, height: h)
        let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        c.fillRect(IntRect(0, 0, w, h), value: Pal.dx("floor.base"), style: st)
        let sentinel: UInt32 = 0xDEAD_BEEF
        for crop in [IntRect(100, 100, 4, 4), IntRect(-50, 0, 4, 4), IntRect(2, 2, 0, 4), IntRect(2, 2, 4, 0), IntRect(2, 2, -3, 5), IntRect(w, 0, 3, 3)] {
            var buf = [UInt32](repeating: sentinel, count: (w + 2) * (h + 2))
            buf.withUnsafeMutableBytes { c.writeBGRA(into: $0.baseAddress!, bytesPerRow: (w + 2) * 4, crop: crop) }
            #expect(buf.allSatisfy { $0 == sentinel }, "crop \(crop) 和画布不相交：目标内存一个字节都不该动")
        }
    }

    /// 部分相交：只写相交的那一块，落在目标左上角；其余不动。
    @Test func writeBGRAWithAPartlyOutsideCropWritesOnlyTheOverlap() {
        let w = 8, h = 6
        let c = Canvas(width: w, height: h)
        let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        c.fillRect(IntRect(0, 0, w, h), value: Pal.dx("floor.base"), style: st)
        let sentinel: UInt32 = 0xDEAD_BEEF
        let stride = w + 2
        var buf = [UInt32](repeating: sentinel, count: stride * (h + 2))
        buf.withUnsafeMutableBytes { c.writeBGRA(into: $0.baseAddress!, bytesPerRow: stride * 4, crop: IntRect(6, 4, 10, 10)) }
        for y in 0..<(h + 2) { for x in 0..<stride {
            let inside = x < 2 && y < 2                       // 相交部分是 2×2
            #expect((buf[y * stride + x] != sentinel) == inside, "(\(x),\(y))")
        } }
        // stride 比一行像素还小：宁可不写也不越行
        var tiny = [UInt32](repeating: sentinel, count: 64)
        tiny.withUnsafeMutableBytes { c.writeBGRA(into: $0.baseAddress!, bytesPerRow: 4, crop: nil) }
        #expect(tiny.allSatisfy { $0 == sentinel })
    }

    // MARK: A-011 座位号
    @Test func layoutCapsTheDeskCountWhateverTheSeatNumberIs() {
        let l = OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 1_000_000_000)
        #expect(l.deskCount <= Metrics.maxSeats + 2, "deskCount = \(l.deskCount)")
        #expect(l.worldH < 100_000)
        #expect(OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: Metrics.maxSeats - 1).deskCount == Metrics.maxSeats + 1, "正常范围内的座位号不受影响")
        #expect(OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 5).deskCount == 7)
    }

    @Test func layoutSurvivesTheLargestSeatNumbers() {
        for m in [Int.max, Int.max - 1, Int.min, -1] {
            let l = OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: m)
            #expect(l.deskCount >= Metrics.minDesks && l.deskCount <= Metrics.maxSeats + 2)
        }
    }

    @Test func hitIDsNeverOverflowAndStayInTheOfficeRange() {
        #expect(OfficeScene.hitID(seat: 5) == 1005)
        #expect(OfficeScene.seat(fromHitID: 1005) == 5)
        for s in [70_000, Int.max, 100_000, 999, 1000, -1, Int.min] {
            let id = OfficeScene.hitID(seat: s)
            #expect(id >= 1000 && id < 2000, "seat \(s) → \(id)：办公室的对象 ID 是 1000…1999，2000 起是小鱼缸、3000 起是宠物条")
        }
        #expect(OfficeScene.seat(fromHitID: 0) == nil)
        #expect(OfficeScene.seat(fromHitID: 999) == nil)
        #expect(OfficeScene.seat(fromHitID: 2003) == nil, "小鱼缸的 ID 不是办公室的座位")
        #expect(OfficeScene.seat(fromHitID: 3001) == nil)
    }

    /// 座位号是天文数字 / 负数的快照：整场景照样能渲染（Int.max 时原来 maxSeat + 2 直接溢出陷阱）。
    @Test func officeSceneRendersWithWildSeatNumbers() {
        let scene = OfficeScene()
        var opts = SceneOptions(); opts.zoom = 3; opts.animateWalkers = false
        let present = [Self.snap("t:a", seat: 0), Self.snap("t:max", seat: Int.max), Self.snap("t:neg", seat: -3), Self.snap("t:big", seat: 5_000_000_000)]
        let f = scene.render(viewportW: 224, viewportH: 226, present: present, dormant: [], now: Self.base, time: 1, options: opts)
        #expect(f.canvas.width >= 64)
        #expect(f.canvas.height < 20_000)
        #expect(scene.layout.deskCount <= Metrics.maxSeats + 2)
        #expect(scene.lastSeatViews.first { $0.seat == 0 }?.mode == .occupied, "正常座位照常画")
    }

    // MARK: A-008 同一会话第二次走进办公室
    /// 出现 → 走完 → 消失 → 走完 → 再出现：再出现的第一帧人还在路上（空座位 + 拉出的椅子），不是「已经坐着」；走完之后才坐好。
    /// 原来 seatedAt 只在 nil 时写、从不清：第二次进场时座位直接画成坐好的人，门口又走进来一个「分身」。
    @Test func aSessionThatComesBackWalksInAgainInsteadOfSittingDownAtOnce() {
        let scene = OfficeScene()
        var opts = SceneOptions(); opts.zoom = 3; opts.emptySign = false
        let k = Self.snap("t:K", seat: 1)
        func frame(_ t: Double, _ present: [BuddySnapshot]) {
            _ = scene.render(viewportW: 336, viewportH: 339, present: present, dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: opts)
        }
        func seatView() -> SeatView? { scene.lastSeatViews.first { $0.seat == 1 } }
        var t = 0.0
        while t < 0.5 { frame(t, []); t += 1.0 / 30 }
        // 第一次进场
        frame(t, [k])
        #expect(seatView()?.mode == .empty && seatView()?.chairOut == true, "第一次进场：人在路上")
        let t1 = t
        while t < t1 + 9 { t += 1.0 / 30; frame(t, [k]) }
        #expect(scene.walkers.isIdle)
        #expect(seatView()?.mode == .occupied, "走完之后坐好")
        // 离场
        let t2 = t
        while t < t2 + 9 { t += 1.0 / 30; frame(t, []) }
        #expect(scene.walkers.isIdle, "离场动画走完")
        #expect(seatView()?.mode == .empty)
        // 第二次进场：第一帧
        t += 1.0 / 30
        frame(t, [k])
        #expect(scene.walkers.isBusy("t:K"), "门口应该有人在走进来")
        #expect(seatView()?.mode == .empty, "座位上不该已经坐着人（分身）")
        #expect(seatView()?.chairOut == true)
        // 走完之后才坐好
        let t3 = t
        while t < t3 + 9 { t += 1.0 / 30; frame(t, [k]) }
        #expect(scene.walkers.isIdle)
        #expect(seatView()?.mode == .occupied)
    }

    // MARK: A-018 只增不减
    /// 人离场之后，seatedAt / lastApp 里他的记录要清掉（否则每个见过的会话在进程里留一条，没有上界；seatedAt 不清还是 A-008 的根因）。
    @Test(arguments: [true, false])
    func departedSessionsAreForgottenByTheScene(animate: Bool) {
        let scene = OfficeScene()
        var opts = SceneOptions(); opts.zoom = 3; opts.emptySign = false; opts.animateWalkers = animate
        func frame(_ t: Double, _ present: [BuddySnapshot]) { _ = scene.render(viewportW: 336, viewportH: 339, present: present, dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: opts) }
        let a = Self.snap("t:a", seat: 0), b = Self.snap("t:b", seat: 1)
        frame(0, [a, b]); frame(0.1, [a, b])
        scene.seatedAt["t:a"] = 2.0; scene.seatedAt["t:b"] = 3.0         // 模拟「走进来坐下」记下的时刻
        #expect(scene.lastApp["t:a"] != nil && scene.lastApp["t:b"] != nil)
        frame(0.2, [b])                                                     // a 走了
        #expect(scene.seatedAt["t:a"] == nil, "离场的人不该留在 seatedAt 里")
        #expect(scene.lastApp["t:a"] == nil, "离场的人不该留在 lastApp 里")
        #expect(scene.seatedAt["t:b"] == 3.0 && scene.lastApp["t:b"] != nil, "还在的人不动")
        frame(0.3, [])
        #expect(scene.seatedAt.isEmpty && scene.lastApp.isEmpty)
    }

    // MARK: A-007 换个造型
    /// 换个造型：数据层（异步）把盐 +1 并持久化，UI 要等新盐到了再换，且换成「按新盐算出来的」外观——
    /// 坐着的人、走路的人 / 外套（director.appearance）、重启后（读到 salt+1）三处一致。原来是立刻换一个和盐无关的随机造型。
    @Test func rerollWaitsForTheNewSaltAndThenEveryPlaceAgrees() {
        let d = VisualDirector()
        var s = Self.snap("t:R", seat: 0, salt: 1)
        d.update(snapshots: [s], now: Self.base, time: 0, privacy: false)
        let before = d.performers["t:R"]!.appearance
        #expect(before == Appearance.generate(seed: AppearanceSeed.seed(key: "t:R", salt: 1)))
        d.reroll(key: "t:R")
        d.update(snapshots: [s], now: Self.base.addingTimeInterval(0.1), time: 0.1, privacy: false)
        #expect(d.performers["t:R"]!.appearance == before, "新盐还没到：外观不许乱变（原来立刻换成随机造型）")
        s.salt = 2
        d.update(snapshots: [s], now: Self.base.addingTimeInterval(0.2), time: 0.2, privacy: false)
        let after = d.performers["t:R"]!.appearance
        let restart = Appearance.generate(seed: AppearanceSeed.seed(key: "t:R", salt: 2))
        #expect(after == restart, "换完之后坐着的人 = 重启后（salt 2）的样子")
        #expect(d.appearance(for: s) == after, "走进 / 走出的人、衣帽架上的外套用的是同一个外观")
        #expect(after != before)
    }

    /// 只有被点了「换个造型」的那一个人换；别人不受影响。
    @Test func rerollOnlyTouchesTheChosenBuddy() {
        let d = VisualDirector()
        var a = Self.snap("t:A", seat: 0, salt: 1), b = Self.snap("t:B", seat: 1, salt: 1)
        d.update(snapshots: [a, b], now: Self.base, time: 0, privacy: false)
        let bBefore = d.performers["t:B"]!.appearance
        d.reroll(key: "t:A")
        a.salt = 2
        d.update(snapshots: [a, b], now: Self.base.addingTimeInterval(0.2), time: 0.2, privacy: false)
        #expect(d.performers["t:B"]!.appearance == bBefore)
        // 盐没变（数据层不认 / 离场了）就一直等，不会瞎换
        d.reroll(key: "t:B")
        for i in 1...10 { d.update(snapshots: [a, b], now: Self.base.addingTimeInterval(1 + Double(i)), time: 1 + Double(i), privacy: false) }
        #expect(d.performers["t:B"]!.appearance == bBefore)
    }

    // MARK: A-027 外观缓存
    /// 已经离场的人不该继续占着「不撞衫」的名额，缓存也不该无限增长。
    @Test func appearanceCacheIsBoundedByWhoIsHereNotByWhoWasEverSeen() {
        let d = VisualDirector()
        var t = 0.0
        for i in 0..<400 {
            let s = Self.snap("t:\(i)", seat: 0, salt: UInt64(i))
            d.update(snapshots: [s], now: Self.base.addingTimeInterval(t), time: t, privacy: false)
            t += 0.1
        }
        #expect(d.appearances.count <= 100, "appearances = \(d.appearances.count)")
        #expect(d.performers.count == 1)
    }

    // MARK: A-020 Int(Double)
    @Test func safeIntNeverTraps() {
        #expect(safeInt(.nan) == 0)
        #expect(safeInt(.infinity) == 9_007_199_254_740_992 && safeInt(-.infinity) == -9_007_199_254_740_992)
        #expect(safeInt(1e300) == 9_007_199_254_740_992 && safeInt(-1e300) == -9_007_199_254_740_992)
        #expect(safeInt(1e19) == 9_007_199_254_740_992)
        #expect(safeInt(3.9) == 3 && safeInt(-3.9) == -3 && safeInt(0) == 0 && safeInt(12345.0) == 12345)
    }

    /// 被写坏的时间戳（工具开始时间在 10^22 秒之后）：原来 Int(elapsed / 3) 直接陷阱。
    @Test func aPerformerSurvivesInsaneToolTimestamps() {
        for start in [1e22, -1e22, 1e19, Double.greatestFiniteMagnitude / 4] {
            for name in ["mcp__x__y", "SomeUnknownTool"] {
                let call = ToolCatalog.makeCall(name: name, detail: "", at: Date(timeIntervalSince1970: start))
                let s = Self.snap("t:x", seat: 0, activity: .tool(call, parallel: 1))
                let p = Performer(key: "t:x", snapshot: s, appearance: Appearance.generate(seed: 1), time: 0)
                _ = p.targetPose(now: Self.base, time: 1)
            }
        }
    }

    // MARK: A-029 开发参数
    @Test func demoModesWithNonsenseParametersDoNotCrashOrExplode() {
        let base = Self.base
        let a = DemoScript.snapshots(mode: "crowd5d-3", t: 1, base: base)                       // away = -3 原来是 8..<5 崩溃
        #expect(a.present.count == 5 && a.dormant.isEmpty)
        #expect(DemoScript.snapshots(mode: "crowd99999999", t: 1, base: base).present.count <= 200, "原来会分配几十 GB")
        #expect(DemoScript.snapshots(mode: "crowd0", t: 1, base: base).present.count == 1)
        for t in [-7.0, -0.001, .nan, .infinity, 1e300] { _ = DemoScript.snapshots(mode: "busy6", t: t, base: base); _ = DemoScript.snapshots(mode: "idle6", t: t, base: base) }
    }

    @Test func aMockSourceWithNonsenseSpeedStaysSane() {
        for sp in [-1.0, 0, .nan, .infinity, -.infinity, 1e300] {
            let m = MockSource(speed: sp)
            #expect(m.speed >= 0.05 && m.speed <= 16, "speed \(sp) → \(m.speed)")
            #expect(m.scriptTime >= 0 && m.scriptTime.isFinite)
            m.tick()
        }
        #expect(MockSource(speed: 2).speed == 2)
    }

    /// 第一次「换个造型」在演示模式里也有效：演示数据的盐叠加偏移量。
    @Test func rerollingInTheDemoBumpsTheSaltOfThatBuddyOnly() {
        let m = MockSource(speed: 1)
        var got: [BuddySnapshot] = []
        m.onUpdate = { got = $0 }
        m.tick()
        let a = got.first!.key
        let before = Dictionary(uniqueKeysWithValues: got.map { ($0.key, $0.salt) })
        m.rerollAppearance(key: a)
        m.tick()
        let after = Dictionary(uniqueKeysWithValues: got.map { ($0.key, $0.salt) })
        #expect(after[a] == before[a]! &+ 1)
        #expect(got.filter { $0.key != a }.allSatisfy { after[$0.key] == before[$0.key] })
    }

    /// --fps 1：滑窗 win = 1，`f0 += win / 2` = 0，原来永远不前进（死循环）。
    @Test func flickerScanWithATinyOrInsaneFrameRateTerminates() {
        for fps in [1.0, 0.0, -5.0, .nan, .infinity, 2.0, 3.0] {
            let scan = FlickerScan(fps: fps)
            let c = Canvas(width: 40, height: 40)
            let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
            for i in 0..<12 {
                c.clear()
                c.fillRect(IntRect(5 + i % 3, 5, 10, 10), value: Pal.dx("floor.base"), style: st, id: 1001)
                scan.add(c)
            }
            _ = scan.analyze()
        }
    }

    // MARK: A-025 悬停卡片按内容缓存（BuddyOffice 一侧的 CardKey 见 BuddyOfficeTests）

    // MARK: A-018 屏幕内容的「是不是静态」缓存
    /// ScreenKind 里带扩展名 / server 名，见过的组合越来越多：缓存超过 4096 条整体清空，不会无限增长。
    @Test func theStaticScreenCacheIsBounded() {
        for i in 0..<5000 { _ = ScreenContent.isStatic(.mcpApp("server-\(i)"), seed: i % 977) }
        #expect(ScreenContent.staticCache.count <= 4097, "staticCache = \(ScreenContent.staticCache.count)")
    }
}
