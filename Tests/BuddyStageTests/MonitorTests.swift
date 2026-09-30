import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 显示器：关机是 300 ms 的抖动渐变（不是一帧硬切成黑屏）、待机灯 / 等待灯是 3 个色阶的呼吸（不是开关式闪烁）。
@Suite struct MonitorTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// 一个座位上的人在 leaveAt 秒离开（present 变空），返回离开前后每一帧屏幕区域里「和熄灭的屏幕不同」的像素数。
    /// retained = true 时同时跑一份局部重绘的场景，逐帧比对整个画布（关机渐变期间也必须和整张重画逐像素一致）。
    private func fadeCurve(retained: Bool, leaveAt: Double = 4, until: Double = 6) -> (lit: [(t: Double, lit: Int)], mismatches: Int) {
        // Edit：屏幕是「一行高亮 + 字符逐个出现」，内容在动
        let snaps = AuditFixtures.snapshots(count: 1, titles: .normal, states: .all, base: Self.base, stateOffset: 3)
        var full: [OfficeScene] = [OfficeScene()]
        if retained { full.append(OfficeScene()) }
        var options = SceneOptions(); options.zoom = 1; options.animateWalkers = false; options.emptySign = false; options.directorIsExternal = true
        let director = VisualDirector()                  // 两份场景共用一个导演（和 buddyctl verify 一样），表演者完全相同
        for s in full { s.director = director }
        var o0 = options; o0.retained = false
        var o1 = options; o1.retained = true
        func render(_ t: Double, present: [BuddySnapshot]) -> [Frame] {
            director.update(snapshots: present, now: Self.base.addingTimeInterval(t), time: t, privacy: false)
            return full.enumerated().map { i, s in
                s.render(viewportW: 224, viewportH: 226, present: present, dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: i == 0 ? o0 : o1)
            }
        }
        var t = 0.0
        var shots: [(t: Double, pixels: [UInt32])] = []
        var mismatches = 0
        let step = 1.0 / 30
        while t <= until {
            let present = t < leaveAt ? snaps : []
            let fs = render(t, present: present)
            if fs.count == 2 {
                let a = fs[0].canvas, b = fs[1].canvas
                if !StageRun.samePixels(a, b) { mismatches += 1 }
            }
            // 场景每帧复用同一块画布：屏幕区域的像素要当场拷下来
            let o = full[0].layout.cellOrigin(seat: 0)
            let region = SeatRenderer.screenRegion(IntPoint(o.x, o.y))
            let c = fs[0].canvas
            var px: [UInt32] = []
            for y in region.y..<region.maxY { for x in region.x..<region.maxX { px.append(c.rgba[y * c.width + x]) } }
            shots.append((t, px))
            t += step
        }
        let off = shots.last!.pixels                    // 最后一帧：早已熄灭
        return (shots.map { (t: $0.t, lit: zip($0.pixels, off).filter { $0 != $1 }.count) }, mismatches)
    }

    @Test func theMonitorFadesOutOver300msInsteadOfCuttingToBlack() {
        let (curve, _) = fadeCurve(retained: false)
        let before = curve.filter { $0.t > 3 && $0.t < 3.9 }.map(\.lit)
        #expect((before.min() ?? 0) > 60, "离开前屏幕应该是亮着有内容的（亮像素 \(before.min() ?? 0)）")
        let after = curve.filter { $0.t >= 4 }
        // 人离开后的第一帧：屏幕还亮着大半（不是一帧硬切成黑）
        #expect((after.first?.lit ?? 0) > Int(Double(before.max() ?? 0) * 0.6), "离开后第一帧屏幕就变黑了：\(after.first?.lit ?? -1) 个亮像素")
        // 逐格熄灭：亮像素数（大体）不增加，最多回弹几个像素（内容在动），并且 0.3 秒里熄灭
        var prev: Int? = nil
        for p in after where p.t < 4.3 {
            if let q = prev { #expect(p.lit <= q + 6, "t=\(p.t) 亮像素从 \(q) 又涨到 \(p.lit)") }
            prev = min(prev ?? p.lit, p.lit)
        }
        #expect((after.first { $0.t > 4.0 + OfficeScene.screenFadeSeconds + 0.1 }?.lit ?? -1) == 0, "0.4 秒后屏幕还没熄灭")
        // 中间过程至少有 5 个不同的亮度档（16 级抖动，不是两三档）
        let levels = Set(after.filter { $0.t < 4.35 }.map { $0.lit })
        #expect(levels.count >= 5, "关机渐变只有 \(levels.count) 档亮度")
    }

    @Test func retainedRenderingStaysIdenticalWhileTheMonitorFadesOut() {
        let (_, mismatches) = fadeCurve(retained: true)
        #expect(mismatches == 0, "\(mismatches) 帧的局部重绘和整张重画不一致")
    }

    /// 座位上没人、也从没有过人：不会凭空出现关机动画。
    @Test func anEmptySeatNeverFades() {
        let scene = OfficeScene(); let director = VisualDirector(); scene.director = director
        var o = SceneOptions(); o.animateWalkers = false; o.emptySign = false; o.directorIsExternal = true; o.retained = false
        for i in 0..<20 { let t = Double(i) / 10; _ = scene.render(viewportW: 224, viewportH: 226, present: [], dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: o) }
        #expect(scene.screenFade.isEmpty && scene.screenMemory.isEmpty)
    }

    /// 任务书 5.5：App 启动时就在的会话直接坐好，显示器从左到右依次开机，每台间隔 100 ms（原来是全部同时开机）。
    @Test func monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() {
        let snaps = AuditFixtures.snapshots(count: 4, titles: .normal, states: .all, base: Self.base, stateOffset: 2)     // Read / Edit / Write / Bash：屏幕都有内容
        #expect(snaps.allSatisfy { !$0.appearedAfterLaunch })
        let director = VisualDirector(), scene = OfficeScene(); scene.director = director
        var o = SceneOptions(); o.zoom = 1; o.animateWalkers = false; o.emptySign = false; o.directorIsExternal = true; o.retained = false
        var regionFirst: [[UInt32]] = [], firstLit: [Int: Double] = [:]
        var t = 0.0
        while t <= 1.2 {
            director.update(snapshots: snaps, now: Self.base.addingTimeInterval(t), time: t, privacy: false)
            let f = scene.render(viewportW: 224, viewportH: 226, present: snaps, dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: o)
            for (i, s) in snaps.enumerated() {
                let org = scene.layout.cellOrigin(seat: s.seat)
                let r = SeatRenderer.screenRegion(IntPoint(org.x, org.y))
                var px: [UInt32] = []
                for y in r.y..<r.maxY { for x in r.x..<r.maxX { px.append(f.canvas.rgba[y * f.canvas.width + x]) } }
                if regionFirst.count <= i { regionFirst.append(px) }
                else if firstLit[i] == nil, px != regionFirst[i] { firstLit[i] = t }
            }
            t += 1.0 / 30
        }
        #expect(firstLit.count == 4, "四台显示器都应该开机：\(firstLit)")
        #expect((firstLit[0] ?? 9) < 0.15, "第一台一启动就该开始开机（原来要等 0.8 秒）：\(firstLit[0] ?? -1)")
        for i in 1..<4 { if let a = firstLit[i - 1], let b = firstLit[i] { #expect(abs((b - a) - 0.1) < 0.045, "座位 \(i - 1) → \(i) 开机间隔 \(b - a) 秒，应为 0.1 秒") } }
    }

    // MARK: 指示灯

    private func ledSequence(_ led: Int, seconds: Double, step: Double = 0.05) -> [(t: Double, name: String)] {
        var v = SeatView(seat: 0, origin: IntPoint(0, 0), mode: .occupied, appearance: Appearance.generate(seed: 1))
        v.led = led
        return stride(from: 0.0, through: seconds, by: step).map { ($0, SeatRenderer.ledName(v, gt: $0)) }
    }
    private func transitions(_ seq: [(t: Double, name: String)]) -> [(t: Double, from: String, to: String)] {
        var out: [(Double, String, String)] = []
        for i in 1..<seq.count where seq[i].name != seq[i - 1].name { out.append((seq[i].t, seq[i - 1].name, seq[i].name)) }
        return out.map { (t: $0.0, from: $0.1, to: $0.2) }
    }

    /// 任务书 6.6：不许开关式闪烁——待机灯要在 3 个色阶之间呼吸（原来只有 灭 / 亮 两档，2 秒亮 2 秒灭）。
    @Test func theStandbyLightBreathesThroughThreeLevelsSlowly() {
        let seq = ledSequence(3, seconds: 16)
        #expect(Set(seq.map(\.name)) == ["led.off", "led.mid", "led.on"])
        let tr = transitions(seq)
        for t in tr { #expect(!(t.from == "led.off" && t.to == "led.on") && !(t.from == "led.on" && t.to == "led.off"), "t=\(t.t) 灯从 \(t.from) 直接跳到 \(t.to)（没有中间色阶）") }
        for i in 1..<tr.count { #expect(tr[i].t - tr[i - 1].t >= 0.95, "灯的两次变化只隔了 \(tr[i].t - tr[i - 1].t) 秒（要 ≥ 1 秒，0.25 Hz）") }
    }

    /// 任务书 6.6：等待时的光晕在 3 个相邻色阶之间以 0.8 Hz 循环（原来是一个固定的琥珀色）。
    @Test func theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz() {
        let seq = ledSequence(2, seconds: 10)
        #expect(Set(seq.map(\.name)) == ["led.wait.lo", "led.wait", "led.wait.hi"])
        let tr = transitions(seq)
        #expect(tr.count >= 30 && tr.count <= 34, "10 秒里应该变化 32 次左右（0.8 Hz × 4 档）：\(tr.count)")
        for t in tr { #expect(!(t.from == "led.wait.lo" && t.to == "led.wait.hi") && !(t.from == "led.wait.hi" && t.to == "led.wait.lo"), "t=\(t.t) 跳过了中间色阶") }
        let period = seq.count > 0 ? tr.filter { $0.to == "led.wait.hi" }.map(\.t) : []
        for i in 1..<period.count { #expect(abs((period[i] - period[i - 1]) - 1.25) < 0.08, "一个循环 \(period[i] - period[i - 1]) 秒，应为 1.25 秒") }
    }

    @Test func activeAndAbsentLightsStayPut() {
        #expect(Set(ledSequence(1, seconds: 8).map(\.name)) == ["led.on"])
        #expect(Set(ledSequence(0, seconds: 8).map(\.name)) == ["led.off"])
        var v = SeatView(seat: 0, origin: IntPoint(0, 0), mode: .dormant, appearance: Appearance.generate(seed: 1)); v.led = 2
        #expect(SeatRenderer.ledName(v, gt: 3) == "led.off", "没人的工位灯是灭的")
    }
}
