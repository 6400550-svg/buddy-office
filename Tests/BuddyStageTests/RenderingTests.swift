import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 渲染：局部重绘和整张重画逐像素一致、金图哈希固定、闪烁扫描（3 个场景 × 1–3 倍缩放）干净、命中缓冲、画布剪裁、布局、走路 / 开门的时间线。
@Suite struct RenderingTests {
    // MARK: 局部重绘 == 整张重画
    @Test(arguments: ["office", "tank", "strip"])
    func retainedRenderingMatchesFullRedrawPixelForPixel(scene: String) {
        for (clock, mode) in [("12:00", "demo"), ("22:30", "busy6"), ("05:30:20", "idle6")] {
            let r = StageRun.compareRetained(scene: scene, clock: clock, mode: mode, seconds: 40, viewport: (224, 226), hover: scene == "office")
            #expect(r.firstBad == nil, "[\(scene)] \(clock) \(mode)：第 \(r.firstBad?.frame ?? -1) 帧不一致（\(r.firstBad?.count ?? 0) 个像素，\(String(describing: r.firstBad?.bbox))）")
            #expect(r.frames > 1000)
        }
    }

    /// 12 个人（小鱼缸 / 宠物条只画 8 个、剩下的显示「+N」）、一号位带 5 个小助手（只画 3 个 +「+2」）。
    @Test(arguments: ["office", "tank", "strip"])
    func retainedRenderingMatchesFullRedrawWithNobodyAtAll(scene: String) {
        let r = StageRun.compareRetained(scene: scene, clock: "12:00", mode: "empty", seconds: 6, viewport: (224, 226))
        #expect(r.firstBad == nil, "[\(scene)] empty：第 \(r.firstBad?.frame ?? -1) 帧不一致")
    }

    @Test(arguments: ["office", "tank", "strip"])
    func retainedRenderingMatchesFullRedrawWithMoreThanEightPeople(scene: String) {
        let r = StageRun.compareRetained(scene: scene, clock: "12:00", mode: "crowd12", seconds: 20, viewport: (336, 300), hover: scene == "office")
        #expect(r.firstBad == nil, "[\(scene)] crowd12：第 \(r.firstBad?.frame ?? -1) 帧不一致（\(r.firstBad?.count ?? 0) 个像素，\(String(describing: r.firstBad?.bbox))）")
        #expect(r.frames > 400)
    }

    /// 小鱼缸和宠物条最多画 8 个人；再多的用一块「+N」牌子告诉用户。宠物条的牌子占最右边额外的一小列，8 个以内不多这一列。
    @Test func tankAndStripShowAnOverflowBadgeBeyondEightPeople() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for n in [6, 8, 9, 12] {
            let s = DemoScript.snapshots(mode: "crowd\(n)", t: 5, base: base).present
            #expect(s.count == n)
            let director = VisualDirector()
            for step in 0..<30 { director.update(snapshots: s, now: base.addingTimeInterval(Double(step) / 15), time: Double(step) / 15, privacy: false) }
            let now = base.addingTimeInterval(2)
            let strip = StripScene().render(director: director, present: s, now: now, time: 2, privacy: false)
            #expect(strip.canvas.width == min(8, n) * Metrics.cellW + (n > 8 ? StripScene.badgeColW : 0), "宠物条 \(n) 个人的宽度 \(strip.canvas.width)")
            #expect(TankScene.layout(count: n).extra == max(0, n - 8))
        }
    }

    /// 宠物条靠右时窗口右边缘固定、来一个新人窗口就向左长一格：已经坐着的人必须一动不动（画面逐像素相同，只是整体在画布里右移一格），
    /// 否则每来一个人整排人会瞬间往左跳一格。
    @Test func stripKeepsSeatedBuddiesStillWhenSomeoneNewArrives() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let all = DemoScript.snapshots(mode: "crowd6", t: 41, base: base).present
        #expect(all.count == 6)
        let five = Array(all.prefix(5))
        let dA = VisualDirector(), dB = VisualDirector()
        let sA = StripScene(), sB = StripScene()
        var fA: Frame?, fB: Frame?
        var t = 0.0
        while t <= 6 {
            let now = base.addingTimeInterval(t)
            dA.update(snapshots: five, now: now, time: t, privacy: false)
            dB.update(snapshots: all, now: now, time: t, privacy: false)
            fA = sA.render(director: dA, present: five, now: now, time: t, privacy: false)
            fB = sB.render(director: dB, present: all, now: now, time: t, privacy: false)
            t += 1.0 / 15
        }
        guard let a = fA?.canvas, let b = fB?.canvas else { Issue.record("没有画面"); return }
        #expect(b.width == a.width + Metrics.cellW && b.height == a.height)
        var diff = 0
        for y in 0..<a.height { for x in 0..<a.width where a.rgba[y * a.width + x] != b.rgba[y * b.width + x + Metrics.cellW] { diff += 1 } }
        #expect(diff == 0, "来了第 6 个人之后，原来 5 个人的画面有 \(diff) 个像素变了（应该一动不动）")
    }

    /// 任务书 6.2：一个会话都没有时，办公室里显示一块「今天还没人上班」的牌子（小鱼缸里也一样）；有人在场、或者有下班工位时不显示。
    @Test func emptyOfficeAndTankShowTheNobodyIsInSign() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let demo = DemoScript.snapshots(mode: "crowd6", t: 41, base: base)
        let director = VisualDirector()
        director.update(snapshots: demo.present, now: base, time: 0, privacy: false)
        func hasSign(_ f: Frame) -> Bool { f.texts.contains { $0.text == OfficeScene.signText } }
        var opts = SceneOptions(); opts.directorIsExternal = true; opts.zoom = 3
        let office = OfficeScene(); office.director = director
        #expect(hasSign(office.render(viewportW: 224, viewportH: 226, present: [], dormant: [], now: base, time: 1, options: opts)))
        #expect(!hasSign(office.render(viewportW: 224, viewportH: 226, present: Array(demo.present.prefix(2)), dormant: [], now: base, time: 2, options: opts)), "有人在场时不该有牌子")
        var away = demo.present[0]; away.presence = .away(since: base, dormant: true)
        #expect(!hasSign(office.render(viewportW: 224, viewportH: 226, present: [], dormant: [away], now: base, time: 3, options: opts)), "有下班工位时不算「今天还没人上班」")
        #expect(hasSign(office.render(viewportW: 224, viewportH: 226, present: [], dormant: [], now: base, time: 4, options: opts)), "人走光了牌子又回来")
        var early = opts; early.emptySign = false          // App 刚启动、第一批数据还没到：空办公室不是「今天还没人上班」，不能先闪一下牌子
        let earlyOffice = OfficeScene(); earlyOffice.director = director
        #expect(!hasSign(earlyOffice.render(viewportW: 224, viewportH: 226, present: [], dormant: [], now: base, time: 1, options: early)))
        let tank = TankScene()
        #expect(!hasSign(TankScene().render(director: director, present: [], now: base, time: 1, privacy: false, zoom: 2, emptySign: false)))
        #expect(hasSign(tank.render(director: director, present: [], now: base, time: 1, privacy: false, zoom: 2)))
        #expect(!hasSign(tank.render(director: director, present: Array(demo.present.prefix(2)), now: base, time: 2, privacy: false, zoom: 2)))
    }

    @Test func retainedRenderingMatchesAtOtherWindowSizes() {
        for vp in [(120, 200), (336, 339), (672, 678)] {
            let r = StageRun.compareRetained(scene: "office", clock: "12:00", mode: "demo", seconds: 20, viewport: vp)
            #expect(r.firstBad == nil, "视口 \(vp)：第 \(r.firstBad?.frame ?? -1) 帧不一致")
        }
    }

    // MARK: 金图
    /// 演示剧本里几个关键时刻的画布哈希（Tests/BuddyStageTests/golden.txt）。改了画法之后要重新生成：`buddyctl golden --update`，并且亲眼看过新的画面。
    @Test func goldenFrameHashesAreStable() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("golden.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var expected: [String: String] = [:]
        for l in text.split(separator: "\n") { let p = l.split(separator: " "); if p.count == 2 { expected[String(p[0])] = String(p[1]) } }
        #expect(expected.count == StageRun.goldenPlan.count)
        for (name, h) in StageRun.goldenHashes() {
            #expect(expected[name] == String(format: "%016llx", h), "金图 \(name) 变了：期望 \(expected[name] ?? "无") 实际 \(String(format: "%016llx", h))。如果是有意的改动，运行 buddyctl golden --update")
        }
    }

    @Test func renderingIsDeterministic() {
        let a = StageRun.frameHash(scene: "office", at: 41, clock: "12:00")
        let b = StageRun.frameHash(scene: "office", at: 41, clock: "12:00")
        #expect(a == b)
        #expect(a != StageRun.frameHash(scene: "office", at: 41, clock: "22:30"), "白天和夜里的画面应该不一样")
    }

    // MARK: 闪烁扫描
    @Test(arguments: [1, 2, 3])
    func officeHasNoFlickerAtEveryZoom(zoom: Int) {
        let r = StageRun.flicker(scene: "office", zoom: zoom, clock: "12:00", from: 0, to: 79.9)
        #expect(r.findings.isEmpty, "办公室 \(zoom) 倍：\(r.findings.prefix(5).map { $0.description })")
        #expect(r.frames >= 2390)
    }

    @Test(arguments: ["tank", "strip"])
    func tankAndStripHaveNoFlicker(scene: String) {
        for clock in ["12:00", "22:30"] {
            let r = StageRun.flicker(scene: scene, zoom: 3, clock: clock, from: 0, to: 79.9)
            #expect(r.findings.isEmpty, "\(scene) \(clock)：\(r.findings.prefix(5).map { $0.description })")
        }
    }

    @Test func officeHasNoFlickerAtNightAndDuringLightTransition() {
        for clock in ["22:30", "05:30:20", "18:49:30"] {
            let r = StageRun.flicker(scene: "office", zoom: 3, clock: clock, from: 0, to: 79.9)
            #expect(r.findings.isEmpty, "办公室 \(clock)：\(r.findings.prefix(5).map { $0.description })")
        }
    }

    // MARK: 命中缓冲
    @Test func personPixelsCarryTheirSeatIDAndTheWallCarriesNone() {
        let d = VisualDirector()
        let scene = OfficeScene(); scene.director = d
        var opts = SceneOptions(); opts.directorIsExternal = true; opts.animateWalkers = false
        let base = StageRun.fixedBase(clock: "12:00")
        let s = DemoScript.snapshots(mode: "busy6", t: 10, base: base)
        var frame: Frame? = nil
        for i in 0..<60 {
            let t = Double(i) / 30
            d.update(snapshots: s.present, now: base.addingTimeInterval(t), time: t, privacy: false)
            frame = scene.render(viewportW: 224, viewportH: 226, present: s.present, dormant: s.dormant, now: base.addingTimeInterval(t), time: t, options: opts)
        }
        let c = frame!.canvas
        var seen = Set<UInt16>()
        for v in scene.lastSeatViews where v.mode == .occupied {
            var hit = 0
            for y in v.origin.y..<(v.origin.y + Metrics.cellH) { for x in v.origin.x..<(v.origin.x + Metrics.cellW) where c.objectID(x, y) == OfficeScene.hitID(seat: v.seat) { hit += 1 } }
            #expect(hit > 100, "工位 \(v.seat) 的人只有 \(hit) 个命中像素")
            seen.insert(OfficeScene.hitID(seat: v.seat))
        }
        #expect(seen.count == 6)
        for x in 0..<c.width { #expect(c.objectID(x, 5) == 0, "后墙不应该有命中对象") }
    }

    // MARK: 屏幕内容：静态判定必须和真实一致
    @Test func staticScreenClassificationMatchesWhatIsActuallyDrawn() {
        let day = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        let kinds: [ScreenKind] = [.off, .ide, .doc("swift"), .doc("md"), .results, .tree, .diffEdit, .notebook, .terminal, .terminalLong, .browser, .search, .helpers, .checklist, .manual,
                                   .iconGrid, .mcpBrowser, .desktop, .mcpApp("N"), .permission, .question, .plan, .compact, .retry(2, 10), .warning, .stop, .done, .idleDesktop, .screensaver, .gear, .outbox, .clock, .log]
        var staticKinds: [String] = []
        for k in kinds {
            var hashes = Set<UInt64>()
            for i in 0..<60 {
                let c = Canvas(width: 24, height: 18)
                ScreenContent.draw(k, on: c, rect: IntRect(0, 0, 24, 18), t: Double(i) * 0.37 + 0.11, gt: Double(i) * 1.13 + 0.2, seed: 5, style: day)
                hashes.insert(c.contentHash())
            }
            let claimed = ScreenContent.isStatic(k, seed: 5)
            if claimed { #expect(hashes.count == 1, "\(k) 被判成静态，但 60 个时刻里画出了 \(hashes.count) 种") ; staticKinds.append("\(k)") }
            else { #expect(hashes.count > 1, "\(k) 被判成动态，但 60 个时刻里画出来都一样") }
        }
        #expect(ScreenContent.isStatic(.off, seed: 1))
        #expect(!ScreenContent.isStatic(.terminalLong, seed: 1))
        #expect(!ScreenContent.isStatic(.ide, seed: 1), "光标在呼吸")
    }

    // MARK: 画布：剪裁、区域还原、哈希
    @Test func clipRestrictsEveryDrawingPrimitive() {
        let c = Canvas(width: 40, height: 40)
        let st = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        let v = Pal.dx("ink1")
        c.withClip(IntRect(10, 10, 10, 10)) {
            c.fillRect(IntRect(0, 0, 40, 40), value: v, style: st)
            c.hLine(x: 0, y: 12, length: 40, value: v, style: st)
            c.fillEllipse(cx: 15, cy: 15, rx: 30, ry: 30, value: v, style: st)
            c.fillDither(IntRect(0, 0, 40, 40), value: v, level: 16, style: st)
            c.blit(PropArt.book["keyboard"], x: 5, y: 12, style: st)
            c.blitCanvas(c, x: 0, y: 0)
            c.set(0, 0, value: v, style: st)
            c.setRaw(1, 1, color: RGBA8(255, 0, 0, 255))
        }
        for y in 0..<40 { for x in 0..<40 {
            let inside = x >= 10 && x < 20 && y >= 10 && y < 20
            #expect(inside || c.pixel(x, y) == 0, "剪裁之外的 (\(x),\(y)) 被画了")
        } }
        #expect(c.pixel(15, 15) != 0)
        #expect(c.clipRect == c.bounds, "withClip 结束后应该还原")
    }

    @Test func copyRegionAndClearRegionTouchOnlyTheirRectangle() {
        let bg = Canvas(width: 20, height: 20), w = Canvas(width: 20, height: 20)
        for i in 0..<400 { bg.rgba[i] = 0xFF112233; bg.idx[i] = 7; bg.ids[i] = 3; w.rgba[i] = 0xFF445566; w.idx[i] = 9; w.ids[i] = 4 }
        w.copyRegion(from: bg, rect: IntRect(5, 5, 4, 4))
        for y in 0..<20 { for x in 0..<20 {
            let inside = x >= 5 && x < 9 && y >= 5 && y < 9
            #expect(w.pixel(x, y) == (inside ? 0xFF112233 : 0xFF445566))
            #expect(w.masterIndex(x, y) == (inside ? 7 : 9) && w.objectID(x, y) == (inside ? 3 : 4))
        } }
        w.clearRegion(IntRect(0, 0, 3, 3))
        #expect(w.pixel(1, 1) == 0 && w.pixel(3, 3) != 0)
    }

    @Test func contentHashDistinguishesSingleBitChangesAndIgnoresNothing() {
        let a = Canvas(width: 37, height: 11)              // 故意用奇数尺寸：尾部不足 32 字节的部分也要参与哈希
        let h0 = a.contentHash()
        var seen = Set<UInt64>([h0])
        for i in stride(from: 0, to: a.count, by: 13) {
            a.rgba[i] ^= 1
            #expect(seen.insert(a.contentHash()).inserted, "改了第 \(i) 个像素，哈希没变")
            a.rgba[i] ^= 1
        }
        #expect(a.contentHash() == h0)
    }

    // MARK: 布局
    @Test func layoutDeskCountAndColumnHysteresis() {
        #expect(OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: -1).deskCount == 4)
        #expect(OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 2).deskCount == 4)
        #expect(OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 5).deskCount == 7)
        // 列数：宽度刚好够下一列时不立刻换（要多出 8 px），拖回来也一样
        let usable = { (cols: Int) in cols * Metrics.cellW + 2 * Metrics.sideMargin }
        let three = OfficeLayout.compute(viewportW: usable(3), viewportH: 300, maxSeat: 8)
        #expect(three.cols == 3)
        let a = OfficeLayout.compute(viewportW: usable(4) + 2, viewportH: 300, maxSeat: 8, prevCols: 3)
        #expect(a.cols == 3, "多出 2 px 不该换列")
        let b = OfficeLayout.compute(viewportW: usable(4) + 9, viewportH: 300, maxSeat: 8, prevCols: 3)
        #expect(b.cols == 4)
        let c = OfficeLayout.compute(viewportW: usable(4) - 3, viewportH: 300, maxSeat: 8, prevCols: 4)
        #expect(c.cols == 4, "少 3 px 不该换回去")
    }

    // MARK: 走路 + 开门
    @Test func walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 339, maxSeat: 5)
        let room = RoomRenderer(layout: lay)
        let w = WalkerSystem(); w.doorInterior = room.doorInterior
        let ap = Appearance.generate(seed: 42)
        w.startLeaving(key: "k", appearance: ap, seat: 0, layout: lay, door: room.doorFeet, time: 0)
        let c = Canvas(width: lay.worldW, height: lay.worldH)
        var sawDoorOpen = false, endedClosed = false
        var t = 0.0
        while t < 12 {
            c.clear()
            w.draw(on: c, light: LightState(a: .day), time: t)
            if !w.motionRects.isEmpty { sawDoorOpen = sawDoorOpen || w.motionRects.contains(room.doorInterior) }
            // 脚在门槛之上的时候，门洞之外的墙不能有人
            for r in w.lastRects where r.rect.maxY < room.doorFeet.y {
                for y in 0..<(room.doorInterior.y) { for x in 0..<c.width { #expect(c.pixel(x, y) == 0, "门楣之上 (\(x),\(y)) 有人") } }
            }
            if t > 11 { endedClosed = w.isIdle }
            w.cleanup(time: t)
            t += 1.0 / 30
        }
        #expect(sawDoorOpen, "离场的时候门应该开过")
        #expect(endedClosed, "走完之后走路系统应该清空（门关上）")
    }

    @Test func enteringWalkerAppearsOnlyAfterTheDoorStartedOpening() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 339, maxSeat: 5)
        let room = RoomRenderer(layout: lay)
        let w = WalkerSystem(); w.doorInterior = room.doorInterior
        w.startEntering(key: "k", appearance: Appearance.generate(seed: 7), seat: 1, layout: lay, door: room.doorFeet, time: 0)
        let c = Canvas(width: lay.worldW, height: lay.worldH)
        w.draw(on: c, light: LightState(a: .day), time: 0.02)
        #expect(w.lastRects.isEmpty, "门刚开始开的时候人还没出来")
        #expect(w.motionRects.contains(room.doorInterior), "门应该在动")
        w.draw(on: c, light: LightState(a: .day), time: 0.3)
        #expect(!w.lastRects.isEmpty, "0.3 秒时人应该已经出来了")
        #expect(w.finishedEntering("k", time: 1.0) == nil)
        #expect(w.finishedEntering("k", time: 6.0) != nil)
    }

    // MARK: 画面指纹
    @Test func seatSignatureChangesExactlyWhenPixelsCanChange() {
        let d = VisualDirector()
        let base = StageRun.fixedBase(clock: "12:00")
        let s = DemoScript.snapshots(mode: "busy6", t: 10, base: base)
        d.update(snapshots: s.present, now: base, time: 3, privacy: false)
        let light = LightState(a: .day)
        let p = d.performers[s.present[0].key]!
        let v1 = p.seatView(origin: IntPoint(0, 0), time: 3, now: base, light: light, hitID: 1, privacy: false, mirror: false)
        let v2 = p.seatView(origin: IntPoint(0, 0), time: 3, now: base, light: light, hitID: 1, privacy: false, mirror: false)
        #expect(SeatRenderer.signatures(v1, light: light, gt: 3) == SeatRenderer.signatures(v2, light: light, gt: 3), "同样的输入指纹必须相同")
        var v3 = v1; v3.mirror.toggle()
        #expect(SeatRenderer.signatures(v3, light: light, gt: 3).rest != SeatRenderer.signatures(v1, light: light, gt: 3).rest)
        var v4 = v1; v4.lampOn.toggle()
        #expect(SeatRenderer.signatures(v4, light: light, gt: 3).rest != SeatRenderer.signatures(v1, light: light, gt: 3).rest)
        var v5 = v1; v5.rig?.headDy += 1
        let s5 = SeatRenderer.signatures(v5, light: light, gt: 3), s1 = SeatRenderer.signatures(v1, light: light, gt: 3)
        #expect(s5.person != s1.person && s5.rest == s1.rest && s5.screen == s1.screen, "只有人变了：只有人的指纹变")
        #expect(SeatRenderer.signatures(v1, light: LightState(a: .night), gt: 3).rest != s1.rest, "光照变了指纹要变")
    }
}
