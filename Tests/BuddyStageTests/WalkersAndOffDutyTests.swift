import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 任务书 5.5：进场（从门口走到工位坐下，约 2.5 秒）、离场（起身、推椅子、挥手、走出门，门在身后关上）、下班工位（关屏、椅子推进去、外套挂在门口的衣帽架上、桌牌变暗）。
/// 之前这一层只有金图哈希（锁像素，不锁语义），这里断言语义：时间线、座位状态、谁能被点、外套。
@Suite struct WalkersAndOffDutyTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func snap(_ i: Int, afterLaunch: Bool) -> BuddySnapshot {
        var s = AuditFixtures.snapshots(count: i + 1, titles: .normal, states: .demo, base: Self.base)[i]
        s.appearedAfterLaunch = afterLaunch
        return s
    }
    private func makeScene() -> (OfficeScene, VisualDirector, SceneOptions) {
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 2; o.directorIsExternal = true; o.animateWalkers = true; o.retained = false; o.emptySign = false
        return (sc, d, o)
    }
    private func step(_ sc: OfficeScene, _ d: VisualDirector, _ o: SceneOptions, t: Double, present: [BuddySnapshot], dormant: [BuddySnapshot] = []) -> Frame {
        d.update(snapshots: present, now: Self.base.addingTimeInterval(t), time: t, privacy: false)
        return sc.render(viewportW: 336, viewportH: 340, present: present, dormant: dormant, now: Self.base.addingTimeInterval(t), time: t, options: o)
    }

    /// 近的座位走 2.5 秒；远的座位走路速度封顶 70 像素 / 秒（不是无限快）。
    @Test func walkingInTakesAboutTwoAndAHalfSecondsAndFarSeatsAreSpeedCapped() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 340, maxSeat: 8)
        let ws = WalkerSystem()
        let door = IntPoint(20, 60)
        for seat in 0..<9 {
            ws.startEntering(key: "k\(seat)", appearance: Appearance.generate(seed: 1), seat: seat, layout: lay, door: door, time: 0)
            let w = ws.walkers["k\(seat)"]!
            let route = WalkerSystem.length(w.points)
            let expectedWalk = max(route / 70, 2.5)          // 速度 = clamp(路程 / 2.5 s, 28, 70)
            #expect(w.speed >= 28 && w.speed <= 70)
            #expect(abs(w.walkTime - min(expectedWalk, route / 28)) < 0.01, "座位 \(seat)：路程 \(route)，走路时间 \(w.walkTime)")
            let done = ws.finishedEntering("k\(seat)", time: 100)
            #expect(done != nil && abs(done! - (WalkerSystem.lead + w.walkTime + WalkerSystem.sitTime)) < 1e-9)
            #expect(ws.finishedEntering("k\(seat)", time: 0.5) == nil, "才走了半秒，还没坐下")
        }
    }

    /// 启动之后才出现的会话：座位先是空的（椅子拉出来，人在路上），走完坐下才是「有人」；启动时就在的会话直接坐好。
    @Test func aSessionThatArrivesAfterLaunchWalksInAndSitsDownWhileOnesPresentAtLaunchAreAlreadySeated() {
        let (sc, d, o) = makeScene()
        let early = snap(0, afterLaunch: false)
        let late = snap(1, afterLaunch: true)
        _ = step(sc, d, o, t: 0, present: [early])
        #expect(sc.lastSeatViews.first { $0.seat == early.seat }?.mode == .occupied, "启动时就在的：直接坐好")
        var t = 0.5, seatedAt: Double? = nil, sawChairOutWhileWalking = false
        while t < 9 {
            _ = step(sc, d, o, t: t, present: [early, late])
            let v = sc.lastSeatViews.first { $0.seat == late.seat }!
            if v.mode != .occupied { sawChairOutWhileWalking = sawChairOutWhileWalking || v.chairOut }
            else if seatedAt == nil { seatedAt = t }
            t += 1.0 / 30
        }
        #expect(sawChairOutWhileWalking, "人在路上时椅子拉出来")
        #expect(seatedAt != nil, "走完之后要坐下")
        if let s = seatedAt { #expect(s - 0.5 >= 2.0 && s - 0.5 <= 5.5, "从出现到坐下 \(s - 0.5) 秒，应该在 2–5.5 秒之间（约 2.5 秒 + 远座位封顶）") }
        #expect(sc.walkers.isIdle, "坐下之后走路的人收掉")
    }

    /// 离场：起身（0.3 s）→ 挥手（0.7 s）→ 走进门洞 → 门关上（0.16 s）；整个过程里那个座位是空的、椅子拉出来，之后归零。
    @Test func leavingStandsWavesWalksOutAndTheDoorClosesBehindThem() {
        let (sc, d, o) = makeScene()
        let a = snap(0, afterLaunch: false), b = snap(1, afterLaunch: false)
        for i in 0..<20 { _ = step(sc, d, o, t: Double(i) / 10, present: [a, b]) }
        let t0 = 2.0
        var t = t0, busyUntil = t0
        while t < t0 + 9 {
            _ = step(sc, d, o, t: t, present: [a])                 // b 离场
            if !sc.walkers.isIdle { busyUntil = t }
            let v = sc.lastSeatViews.first { $0.seat == b.seat }!
            #expect(v.mode != .occupied, "离场之后座位不再是「有人」")
            t += 1.0 / 30
        }
        let total = busyUntil - t0
        #expect(total >= WalkerSystem.standTime + WalkerSystem.waveTime + 1.0, "离场动画只有 \(total) 秒")
        #expect(total <= WalkerSystem.standTime + WalkerSystem.waveTime + 6 + WalkerSystem.tail + 0.2)
        #expect(sc.walkers.isIdle)
    }

    /// 下班工位：桌牌变暗、椅子推进去、显示器关着、点不到；外套挂在门口的衣帽架上；有人来上班（占用同一座位）时外套拿走。
    @Test func anOffDutyDeskIsDimSilentAndUnclickableAndTheCoatHangsByTheDoor() {
        let (sc, d, o) = makeScene()
        var o2 = o; o2.animateWalkers = false
        let all = AuditFixtures.snapshots(count: 4, titles: .normal, states: .demo, base: Self.base).map { s -> BuddySnapshot in var x = s; x.appearedAfterLaunch = false; return x }
        let present = Array(all.prefix(2))
        var off = all[3]; off.presence = .away(since: Self.base, dormant: true); off.seat = 3
        for i in 0..<15 { _ = step(sc, d, o2, t: Double(i) / 10, present: present, dormant: [off]) }
        let f = step(sc, d, o2, t: 2, present: present, dormant: [off])
        guard let v = sc.lastSeatViews.first(where: { $0.seat == 3 }) else { Issue.record("没有座位 3"); return }
        #expect(v.mode == .dormant && v.dim, "下班工位：桌牌变暗")
        #expect(!v.chairOut, "椅子推进去（不是拉出来）")
        #expect(v.hitID == 0, "下班工位点不到（没有对象 ID）")
        // 下班工位的桌牌文字用浅色字（深胡桃木牌）
        let plate = f.texts.filter { $0.tag.hasPrefix("plate") }.first { t in
            let org = sc.layout.cellOrigin(seat: 3); return abs(t.x - Double(org.x + Metrics.cellW / 2)) < 2 && t.y >= Double(org.y + Metrics.cellH) }
        #expect(plate != nil && plate!.style.color == OfficeScene.dormantTitleInk, "下班桌牌用浅色字")
        // 外套：衣帽架上有外套（把这一帧和「没有下班工位」的同一帧比，衣帽架那块像素不同）
        let slot = sc.room.coatSlots.first
        #expect(slot != nil)
        if let p = slot {
            let cs = HelperArt.sprite("coat")
            var withCoat: [UInt32] = []
            for y in p.y..<(p.y + cs.height) { for x in p.x..<(p.x + cs.width) { withCoat.append(f.canvas.rgba[y * f.canvas.width + x]) } }
            let (sc2, d2, _) = makeScene()
            var f2: Frame?
            for i in 0..<16 { f2 = step(sc2, d2, o2, t: Double(i) / 10, present: present, dormant: []) }
            var without: [UInt32] = []
            for y in p.y..<(p.y + cs.height) { for x in p.x..<(p.x + cs.width) { without.append(f2!.canvas.rgba[y * f2!.canvas.width + x]) } }
            #expect(withCoat != without, "衣帽架上应该挂着下班同事的外套")
        }
    }
}
