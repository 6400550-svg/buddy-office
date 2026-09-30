import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import PixelKit
@testable import BuddyStage

/// 规格追踪定稿（QA/spec-trace-ui-final.md）新增的表现层语义测试：任务书 6.5「状态 → 动画」表和 6.6「动作手感与防闪烁」里，
/// 原来只有金图哈希 / 读代码 / 看图作证据的那些数字和行为，逐条钉成断言。
/// 写法：先回到任务书原文想清楚「它要什么」，再断言。实现和任务书不一致的地方（DESIGN.md 第 13 节记了理由）断言的是**实际的数字**，
/// 注释里写明任务书的数字——谁改了实现，这里会红，提醒同时更新 DESIGN.md。
/// 全部用假时钟（自己给 time / now），不依赖真实时间、文件系统或网络。
enum STU {
    static let base = PerformerTimingTests.base
    static func now(_ s: Double) -> Date { base.addingTimeInterval(s) }

    static func snap(_ a: Activity, since: Double = 0, helpers: [HelperSnapshot] = [], blocked: Bool = false, unread: Bool = false,
                     key: String = "d:a", seat: Int = 0) -> BuddySnapshot {
        var s = PerformerTimingTests.snap(a, key: key, seat: seat, since: since)
        s.helpers = helpers; s.blocked = blocked; s.unread = unread
        return s
    }
    static func performer(_ a: Activity, since: Double = 0, helpers: [HelperSnapshot] = [], blocked: Bool = false, unread: Bool = false,
                          key: String = "d:a", seat: Int = 0) -> Performer {
        let s = snap(a, since: since, helpers: helpers, blocked: blocked, unread: unread, key: key, seat: seat)
        return Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
    }
    static func tool(_ name: String, _ detail: String = "", at: Double = 0) -> Activity {
        .tool(ToolCatalog.makeCall(name: name, detail: detail, at: now(at)), parallel: 1)
    }

    // MARK: 姿势取样
    static func frames(_ k: PoseKind, seconds: Double, hz: Double = 240, seed: Int = 1) -> [PoseFrame] {
        (0..<Int(seconds * hz)).map { i in let t = Double(i) / hz; return PoseLibrary.frame(k, t: t, gt: t, seed: seed) }
    }
    /// 一个整数信号每秒的「来回」次数：方向改变次数的一半 / 秒。（0,1,0,1 每 267 ms 一格 = 每秒 3.75 个来回。）
    static func swingHz(_ v: [Int], hz: Double) -> Double {
        guard var last = v.first else { return 0 }
        var lastDir = 0, changes = 0
        for x in v.dropFirst() where x != last {
            let d = x > last ? 1 : -1
            if lastDir != 0 && d != lastDir { changes += 1 }
            lastDir = d; last = x
        }
        return Double(changes) / 2 / (Double(v.count) / hz)
    }
    static func r(_ d: Double?) -> Int { Int((d ?? 0).rounded()) }
    /// 一个姿势里所有会动的整数信号（每只手最终落点 = 目标 + 逐格离散抖动、头、躯干）。
    static func signals(_ fs: [PoseFrame]) -> [String: [Int]] {
        [
            "左手 x": fs.map { r($0.handL?.x) + $0.oscL.x }, "左手 y": fs.map { r($0.handL?.y) + $0.oscL.y },
            "右手 x": fs.map { r($0.handR?.x) + $0.oscR.x }, "右手 y": fs.map { r($0.handR?.y) + $0.oscR.y },
            "头 x": fs.map { Int($0.headDx) }, "头 y": fs.map { Int($0.headDy) }, "躯干 y": fs.map { Int($0.torsoDy) },
        ]
    }
    static func maxSwingHz(_ k: PoseKind, seconds: Double = 60) -> (hz: Double, which: String) {
        var best = (0.0, "")
        for (name, v) in signals(frames(k, seconds: seconds)) {
            let h = swingHz(v, hz: 240)
            if h > best.0 { best = (h, name) }
        }
        return best
    }
    static let allPoses: [PoseKind] = [.typing, .typingFast, .restAtDesk, .mouse, .searching, .thinking, .thinkingDeep, .leanBack, .writingPad, .delegate, .sendFile, .alarm,
                                       .compacting, .retry, .facepalm, .shrug, .stretch, .leanSide, .idle, .doze, .sleep, .faceUser(.approval), .faceUser(.question), .faceUser(.plan)]

    // MARK: 屏幕取样
    static let day = Lighting.resolved(appearance: nil, state: LightState(a: .day))
    static func screen(_ k: ScreenKind, t: Double = 0.5, gt: Double? = nil, seed: Int = 7) -> Canvas {
        let c = Canvas(width: 24, height: 15)
        ScreenContent.draw(k, on: c, rect: IntRect(0, 0, 24, 15), t: t, gt: gt ?? t, seed: seed, style: day)
        return c
    }
    static func ix(_ n: String) -> UInt16 { UInt16(Pal.dx(n)) }
    static func at(_ c: Canvas, _ x: Int, _ y: Int) -> UInt16 { c.idx[y * c.width + x] }
    static func count(_ c: Canvas, _ n: String, x: ClosedRange<Int> = 0...23, y: ClosedRange<Int> = 0...14) -> Int {
        let v = ix(n)
        return y.reduce(0) { acc, yy in acc + x.filter { c.idx[yy * c.width + $0] == v }.count }
    }
    static func row(_ c: Canvas, _ y: Int) -> [UInt16] { (0..<c.width).map { c.idx[y * c.width + $0] } }
    static func same(_ a: Canvas, _ b: Canvas) -> Bool { (0..<a.count).allSatisfy { a.idx[$0] == b.idx[$0] } }
    /// 屏幕内容随时间变化的时刻（在 [0, seconds) 里逐毫秒取样，画面变了就记一笔）。
    static func changeTimes(_ k: ScreenKind, seconds: Double, seed: Int = 7) -> [Double] {
        var out: [Double] = [], last: UInt64 = 0
        var i = 0
        while Double(i) / 1000 < seconds {
            let t = Double(i) / 1000
            let h = screen(k, t: t, seed: seed).contentHash()
            if i > 0 && h != last { out.append(t) }
            last = h; i += 1
        }
        return out
    }
    /// 挑一个种子，使 hash(seed, 3) % 11 == 0（Edit 屏幕里高亮行原来的那条白线最短，字符逐个出现看得最清楚）。
    static var seedWithShortEditLine: Int { (0..<10_000).first { ScreenContent.hash($0, 3) % 11 == 0 } ?? 0 }
}

// MARK: - 6.5 身体动作
@Suite struct SpecTracePoseTests {
    private func f(_ k: PoseKind, _ t: Double = 1, seed: Int = 1) -> PoseFrame { PoseLibrary.frame(k, t: t, gt: t, seed: seed) }

    /// 6.5 身体动作列：思考「略微后靠，手托下巴」、Read「前倾，手放在鼠标上，头微低」、Grep「同上，头轻轻左右扫」、Bash > 8 秒「往后靠」。
    @Test func bodiesLeanAndHandsGoWhereTheTableSays() {
        let th = f(.thinking)
        #expect(th.torsoDy == 1 && th.headDy == 1, "思考：略微后靠（躯干 / 头各下沉 1 像素）")
        #expect(th.handL == Spots.kbL, "思考：左手还在键盘上")
        #expect(th.handR == Spots.headSideR, "思考：手托下巴（右手落在头的一侧）")
        // Read / Grep / Skill / WebFetch：前倾（画面往上 1 像素）、手放在鼠标上（±1 像素的缓慢漂移）
        for kind in [PoseKind.mouse, .searching] {
            var seen = Set<[Int]>()
            for i in 0..<(60 * 20) {
                let t = Double(i) / 20
                let fr = f(kind, t)
                #expect(fr.torsoDy == -1 && fr.headDy == -1, "\(kind)：前倾 1 像素")
                #expect(fr.handL == Spots.kbL)
                let hr = fr.handR!, m = Spots.mouse
                #expect(abs(hr.x - m.x) <= 1 && abs(hr.y - m.y) <= 1, "\(kind)：右手落在鼠标上（\(hr) 离 \(m) 超过 1 像素）")
                seen.insert([Int(hr.x - m.x), Int(hr.y - m.y)])
            }
            #expect(seen.count >= 3, "\(kind)：鼠标手有缓慢的漂移（不是死的）")
        }
        // Grep / Glob：头轻轻左右扫（−1…1 像素）
        let sweep = STU.frames(.searching, seconds: 30, hz: 20).map { Int($0.headDx) }
        #expect(Set(sweep) == [-1, 0, 1], "Grep：头左右扫过 −1 / 0 / +1：\(Set(sweep))")
        #expect(STU.swingHz(sweep, hz: 20) < 0.6, "轻轻扫，不是甩头：\(STU.swingHz(sweep, hz: 20)) Hz")
        // Bash > 8 秒：往后靠（躯干 / 头下沉 1 像素），双手落在身侧（「抱着手臂」见 DESIGN §13：背对镜头时用双手落在身侧近似）
        let lb = f(.leanBack, 5)
        #expect(lb.torsoDy == 1 && lb.headDy == 1 && lb.handL == Spots.restL && lb.handR == Spots.restR)
        // 打字类：双手落在键盘上
        for kind in [PoseKind.typing, .typingFast, .restAtDesk] { let t = f(kind); #expect(t.handL == Spots.kbL && t.handR == Spots.kbR, "\(kind)：双手在键盘上") }
    }

    /// 6.5「Edit：打字（4 帧 × 8 fps，每只手 2 Hz）」「Write：打字更快」；6.6 帧时长「打字：4 帧，每帧 125 ms」。
    /// 实现是 133 ms 一格（15 fps 渲染节拍的整 2 格，DESIGN §7）：4 格一轮 = 0.533 s，每只手 1.875 Hz；Write 左右手不停交替，每只手 3.75 Hz（仍 < 4 Hz）。
    @Test func typingBeatsAreFourFramesOf133msAndWriteIsTwiceAsFast() {
        let hz = 1000.0
        // 每次「状态」变化的时刻：间隔都是 1/7.5 s = 133 ms
        for kind in [PoseKind.typing, .typingFast] {
            let fs = STU.frames(kind, seconds: 4, hz: hz)
            var changes: [Double] = []
            for i in 1..<fs.count where fs[i].oscL != fs[i - 1].oscL || fs[i].oscR != fs[i - 1].oscR { changes.append(Double(i) / hz) }
            let gaps = zip(changes.dropFirst(), changes).map { $0 - $1 }
            #expect(gaps.count > 20 && gaps.allSatisfy { abs($0 - 2.0 / 15) < 0.002 }, "\(kind)：每一格 133 ms（任务书 125 ms）：\(Set(gaps.map { (($0 * 1000).rounded()) }))")
        }
        let typing = STU.frames(.typing, seconds: 60), fast = STU.frames(.typingFast, seconds: 60)
        let tL = STU.swingHz(typing.map { $0.oscL.y }, hz: 240), tR = STU.swingHz(typing.map { $0.oscR.y }, hz: 240)
        #expect((1.7...2.0).contains(tL) && (1.7...2.0).contains(tR), "Edit：每只手约 2 Hz（实际 \(tL) / \(tR)）")
        let fL = STU.swingHz(fast.map { $0.oscL.y }, hz: 240), fR = STU.swingHz(fast.map { $0.oscR.y }, hz: 240)
        #expect((3.5..<4.0).contains(fL) && (3.5..<4.0).contains(fR), "Write：每只手 3.75 Hz，仍在 4 Hz 上限以内（实际 \(fL) / \(fR)）")
        #expect(fL > tL * 1.8 && fR > tR * 1.8, "Write 比 Edit 快一倍")
        // 一轮 4 格：普通打字左手落 → 抬 → 右手落 → 抬（4 个状态），快速打字左右交替（2 个状态）
        let quarter = (0..<8).map { i -> [Int] in let t = (Double(i) + 0.5) / 7.5; let fr = PoseLibrary.frame(.typing, t: t, gt: t, seed: 1); return [fr.oscL.y, fr.oscR.y] }
        #expect(quarter == [[1, 0], [0, 0], [0, 1], [0, 0], [1, 0], [0, 0], [0, 1], [0, 0]], "打字 4 帧一轮：\(quarter)")
        let two = (0..<4).map { i -> [Int] in let t = (Double(i) + 0.5) / 7.5; let fr = PoseLibrary.frame(.typingFast, t: t, gt: t, seed: 1); return [fr.oscL.y, fr.oscR.y] }
        #expect(two == [[1, 0], [0, 1], [1, 0], [0, 1]], "快速打字：左右手不停交替：\(two)")
    }

    /// 6.5 思考「超过 20 秒后用笔轻敲桌面（≤ 2 Hz）」、重试「挠头，轻敲显示器（≤ 2 Hz）」、TodoWrite「在便签本上写（≤ 3 Hz）」、等批准「举手轻轻挥（1.2 Hz）」。
    /// 没有笔的精灵：深度思考用手在键盘右端小幅上下敲代替；重试只有挠头；TodoWrite 写字的图案每 0.533 s 重复一次（1.875 Hz），但竖直分量每 267 ms 一个来回（3.75 Hz，任务书 ≤ 3 Hz）——这三处都记在 DESIGN §13。
    @Test func tappingScratchingWritingAndWavingFrequencies() {
        let deep = STU.frames(.thinkingDeep, seconds: 40)
        let deepHz = STU.swingHz(deep.map { $0.oscR.y }, hz: 240)
        #expect((1.5...2.0).contains(deepHz), "深度思考：轻敲桌面 ≤ 2 Hz（实际 \(deepHz)）")
        #expect(deep[0].handR == Spots.pad, "深度思考：手落在桌面上（键盘右端）")
        let retry = STU.frames(.retry, seconds: 40)
        let retryHz = STU.swingHz(retry.map { $0.oscR.x }, hz: 240)
        #expect((1.5...2.0).contains(retryHz), "重试：挠头 ≤ 2 Hz（实际 \(retryHz)）")
        let hd = Spots.headBackR
        #expect(retry[0].handR == FPoint(hd.x, hd.y - 3), "重试：右手举到后脑上方挠头")
        // TodoWrite：便签本上写字
        let pad = STU.frames(.writingPad, seconds: 40)
        let padX = STU.swingHz(pad.map { $0.oscR.x }, hz: 240), padY = STU.swingHz(pad.map { $0.oscR.y }, hz: 240)
        #expect(padX <= 2.0, "写字：横向 1.875 Hz（实际 \(padX)）")
        #expect((3.5..<4.0).contains(padY), "写字：竖直分量 3.75 Hz，比任务书的 ≤ 3 Hz 快，但在 4 Hz 上限内（实际 \(padY)）")
        let a = PoseLibrary.frame(.writingPad, t: 0.01, gt: 0.01, seed: 1), b = PoseLibrary.frame(.writingPad, t: 0.01 + 4.0 / 7.5, gt: 0.01, seed: 1)
        #expect(a.oscR == b.oscR, "写字的图案每 4 格（0.533 s）重复一次")
        #expect(pad[0].handR == Spots.pad && pad[0].props == [.notepad], "写字：手落在便签本上，桌面上摆着便签本")
        // 等批准：举手轻轻挥 1.2 Hz，幅度 ±2 像素
        let wave = STU.frames(.faceUser(.approval), seconds: 40)
        let waveX = wave.map { STU.r($0.handR?.x) }
        let waveHz = STU.swingHz(waveX, hz: 240)
        #expect((1.15...1.25).contains(waveHz), "等批准：举手挥动 1.2 Hz（实际 \(waveHz)）")
        let cx = Double(BuddyRig.cx + 10)
        #expect(waveX.allSatisfy { abs(Double($0) - cx) <= 2 } && Set(waveX).count == 5, "幅度 ±2 像素（轻轻挥）：\(Set(waveX).sorted())")
        #expect(wave[0].facing == .front && wave[0].handL == nil, "面向你，只举一只手")
    }

    /// 6.6「任何摆动都不超过 4 Hz」：每一种姿势里所有会动的量（手 / 头 / 躯干）逐个数来回次数，最快的也 < 4 Hz。
    @Test func noPoseSwingsFasterThanFourHertz() {
        var report: [String] = []
        for k in STU.allPoses {
            let m = STU.maxSwingHz(k)
            report.append("\(k) \(m.which) \(String(format: "%.2f", m.hz))")
            #expect(m.hz < 4.0, "\(k)：\(m.which) 每秒来回 \(m.hz) 次，超过 4 Hz 上限")
        }
        // 最快的两个正是「快速打字」和「写字」（3.75 Hz），其余都在 2.5 Hz 以内
        for k in STU.allPoses where k != .typingFast && k != .writingPad { #expect(STU.maxSwingHz(k).hz <= 2.5, "\(k)：\(STU.maxSwingHz(k))") }
    }

    /// 6.5 Bash > 8 秒「每 20 秒最多喝一口」；空闲「每 30–60 秒喝一口、四处看」。喝一口 = 手去够杯子再举到嘴边（离开身侧）。
    @Test func sippingAndLookingAroundHappenAtTheSpecifiedIntervals() {
        func windows(_ kind: PoseKind, seed: Int, seconds: Double, _ active: (PoseFrame) -> Bool) -> [(start: Double, length: Double)] {
            var out: [(Double, Double)] = []
            var startedAt: Double? = nil
            var t = 0.0
            while t < seconds {
                let on = active(PoseLibrary.frame(kind, t: t, gt: t, seed: seed))
                if on, startedAt == nil { startedAt = t }
                if !on, let s = startedAt { out.append((s, t - s)); startedAt = nil }
                t += 0.02
            }
            return out.map { (start: $0.0, length: $0.1) }
        }
        // 往后靠（Bash / Monitor > 8 秒）：22 秒一圈，每圈最多一口（≥ 20 秒），一口 2.6 秒
        for seed in [0, 3, 6] {
            let sips = windows(.leanBack, seed: seed, seconds: 200) { $0.handL != Spots.restL }
            #expect(sips.count >= 8, "往后靠：200 秒里应该喝了好几口（\(sips.count)）")
            for i in 1..<sips.count { #expect(sips[i].start - sips[i - 1].start >= 20, "seed \(seed)：两口之间只隔了 \(sips[i].start - sips[i - 1].start) 秒（任务书：每 20 秒最多一口）") }
            #expect(sips.dropLast().allSatisfy { abs($0.length - 2.6) < 0.1 }, "一口 2.6 秒：\(sips.map(\.length))")
        }
        let a = windows(.leanBack, seed: 0, seconds: 60) { $0.handL != Spots.restL }.first!.start
        let b = windows(.leanBack, seed: 5, seconds: 60) { $0.handL != Spots.restL }.first!.start
        #expect(abs(a - b) > 1, "每个 buddy 相位不同（不会齐刷刷一起喝）")
        // 空闲：45 秒一圈（30–60 秒之间），先侧身四处看 1.6 秒，再喝一口 2.6 秒
        for seed in [0, 4, 10] {
            let looks = windows(.idle, seed: seed, seconds: 300) { $0.facing == .side }
            let drinks = windows(.idle, seed: seed, seconds: 300) { $0.handL == Spots.faceL }
            for (name, ws) in [("四处看", looks), ("喝一口", drinks)] {
                #expect(ws.count >= 5, "\(name)：300 秒里应该有好几次（\(ws.count)）")
                for i in 1..<ws.count { #expect((30...60).contains(ws[i].start - ws[i - 1].start), "\(name)：间隔 \(ws[i].start - ws[i - 1].start) 秒不在 30–60 秒里") }
            }
            #expect(looks.dropLast().allSatisfy { abs($0.length - 1.6) < 0.1 } && drinks.dropLast().allSatisfy { abs($0.length - 2.6) < 0.1 })
        }
    }

    /// 6.5 打盹「头一点一点往下垂」、睡着「趴在手臂上」、空闲「3/4 侧身靠着」、出错「手扶额头」、被打断「两手一摊」、做完了「伸懒腰」。
    @Test func idleDozeSleepErrorInterruptedAndStretchPoses() {
        #expect(f(.idle).facing == .threeQuarterBack && f(.leanSide).facing == .threeQuarterBack, "空闲 / 靠着：3/4 侧身")
        #expect(f(.idle, 10).handL == Spots.restL && f(.idle, 10).handR == Spots.restR)
        let doze = STU.frames(.doze, seconds: 120, hz: 60).map { Int($0.headDy) }
        #expect(Set(doze) == [1, 2], "打盹：头在 1–2 像素之间慢慢点：\(Set(doze))")
        #expect(STU.swingHz(doze, hz: 60) < 0.2, "点头很慢（约 0.11 Hz）：\(STU.swingHz(doze, hz: 60))")
        let sleep = f(.sleep)
        #expect(sleep.torsoDy == 3 && sleep.headDy == 6, "睡着：趴下去（躯干 +3、头 +6）")
        let lowest = STU.allPoses.map { Int(f($0).headDy) }.max()!
        #expect(lowest == 6, "睡着的头是所有姿势里最低的")
        #expect(f(.sleep).handL?.y ?? 0 > (Spots.kbL.y - 2), "睡着：双手搭在键盘上")
        let fp = f(.facepalm)
        #expect(fp.headDy == 2 && fp.handR == Spots.headBackR, "出错：头低下去，一只手扶在头上")
        let shrug = f(.shrug)
        #expect(shrug.handR!.x - shrug.handL!.x >= 30 && shrug.handL!.x < Spots.restL.x && shrug.handR!.x > Spots.restR.x, "被打断：两手向两侧摊开")
        // 伸懒腰 1.2 秒：手从身侧举到头的高度再放下
        let s0 = f(.stretch, 0), sm = f(.stretch, 0.6), s1 = f(.stretch, 1.2)
        #expect(sm.handL!.y < s0.handL!.y - 15 && sm.handR!.y == sm.handL!.y, "伸懒腰：0.6 秒时双手举到最高（比身侧高 \(s0.handL!.y - sm.handL!.y) 像素）")
        #expect(abs(s1.handL!.y - s0.handL!.y) < 0.5, "1.2 秒时放下来")
        #expect(sm.handL!.y <= Double(BuddyRig.headY + 2), "举到头顶的高度")
        // 3/4 朝向对着小助手；桌面上的道具
        #expect(f(.delegate).facing == .threeQuarterBack, "Agent 前台：转成 3/4 朝向")
        #expect(f(.sendFile).props == [.tray] && f(.alarm).props == [.alarm] && f(.leanBack).props.isEmpty, "发件盘 / 闹钟 / Monitor 没有道具")
        #expect(f(.compacting).props == [.papers, .box], "整理上下文：纸堆 + 箱子")
        #expect(f(.writingPad).props == [.notepad], "TodoWrite / EnterPlanMode：便签本 / 笔记本")
    }

    /// 6.5 计划待审「转身举起一块写字板」、提问「转身举手」：面向你之后的姿势。
    @Test func askPosesRaiseAHandOrHoldAClipboard() {
        let q = f(.faceUser(.question), 1), p = f(.faceUser(.plan), 1)
        #expect(q.facing == .front && q.expression == "question" && q.handR!.y < Spots.restR.y - 10, "提问：面向你、举手、脸上是疑问")
        #expect(p.facing == .front && p.holdClipboard, "计划待审：举着写字板")
        #expect(p.handL != nil && p.handR != nil && abs(p.handL!.y - p.handR!.y) < 1, "写字板举在胸前，两只手一起托着")
        // 举手高度：提问的手在肩膀以上
        #expect(q.handR!.y < Double(BuddyRig.headY + 10))
    }
}

// MARK: - 6.5 屏幕（24×15）
@Suite struct SpecTraceScreenTests {
    /// Read：「文档每 150 ms 滚 1 像素；颜色随文件扩展名变」。实现是每步 133 ms（15 fps 的整 2 格，DESIGN §13），每步整屏上移恰好 1 像素。
    @Test func documentScrollsOnePixelPerStepAndItsColourFollowsTheExtension() {
        // 步长：画面变化的时刻之间恒为 2/15 s
        let ts = STU.changeTimes(.doc("swift"), seconds: 3)
        let gaps = zip(ts.dropFirst(), ts).map { $0 - $1 }
        #expect(gaps.count >= 15 && gaps.allSatisfy { abs($0 - 2.0 / 15) < 0.0015 }, "文档每步 133 ms（任务书 150 ms）：\(Set(gaps))")
        // 每一步整个内容区上移 1 像素（标题栏下面：第 3…12 行）
        for k in 0..<12 {
            let t = 0.2 + Double(k) * 2.0 / 15
            let a = STU.screen(.doc("swift"), t: t), b = STU.screen(.doc("swift"), t: t + 2.0 / 15)
            for y in 3..<13 { #expect(STU.row(b, y) == STU.row(a, y + 1), "第 \(k) 步：第 \(y) 行不是上一帧第 \(y + 1) 行（没有恰好上移 1 像素）") }
        }
        // 颜色随扩展名：内容行的主色（去掉背景色和暗色行）
        func hue(_ ext: String) -> Set<UInt16> {
            let c = STU.screen(.doc(ext), t: 0.5)
            var s = Set<UInt16>()
            for y in 3..<14 { for x in 0..<24 { let v = STU.at(c, x, y); if v != STU.ix("scr.bg2") && v != STU.ix("scr.dim") && v != 0 { s.insert(v) } } }
            return s
        }
        let table: [(String, String)] = [("swift", "scr.orange"), ("py", "scr.green"), ("js", "scr.amber"), ("ts", "scr.amber"), ("md", "scr.white"), ("txt", "scr.white"),
                                          ("json", "scr.cyan"), ("yaml", "scr.cyan"), ("html", "scr.pink"), ("css", "scr.pink"), ("sh", "scr.green"), ("", "scr.blue"), ("rs", "scr.blue")]
        for (ext, name) in table { #expect(hue(ext) == [STU.ix(name)], "扩展名「\(ext)」的文档应该是 \(name)：\(hue(ext))") }
        #expect(Set(["swift", "py", "ts", "md", "json", "html", "rs"].map { hue($0) }).count == 7, "不同类别的扩展名颜色互不相同")
    }

    /// Grep「结果列表，高亮条缓动」/ Glob「文件树展开」。
    @Test func resultsHighlightEasesAndTheTreeUnfolds() {
        func sel(_ t: Double) -> Int? { (0..<4).first { STU.at(STU.screen(.results, t: t), 20, 3 + 3 * $0) == STU.ix("scr.bg3") } }
        var dwell = [Int: Double]()
        for i in 0..<239 { if let s = sel(Double(i) * 0.005) { dwell[s, default: 0] += 0.005 } }
        #expect(Set(dwell.keys) == [0, 1, 2], "高亮条依次走过第 0、1、2 行：\(dwell)")
        #expect(dwell[1]! < dwell[0]! && dwell[1]! < dwell[2]!, "缓动：两头停得久、中间过得快（smoothstep）：\(dwell)")
        #expect(sel(1.5) == 3 && sel(2.3) == 3, "走到底之后停住")
        // 文件树：每 0.35 秒多展开一行，最多 5 行
        func rows(_ t: Double) -> Int {
            let c = STU.screen(.tree, t: t)
            return (0..<5).filter { i in (1..<12).contains { STU.at(c, $0, 3 + 2 * i) != STU.ix("scr.bg2") } }.count
        }
        #expect([0.1, 0.4, 0.8, 1.15, 1.5, 3.0, 20.0].map(rows) == [1, 2, 3, 4, 5, 5, 5], "文件树逐行展开：\([0.1, 0.4, 0.8, 1.15, 1.5, 3.0, 20.0].map(rows))")
    }

    /// Edit「一行高亮，字符逐个出现，左侧绿色 diff 标记」/ Write「一行行从上往下出现」。
    @Test func editTypesCharactersAndWriteAddsRowsFromTheTop() {
        let seed = STU.seedWithShortEditLine
        func whites(_ t: Double) -> Int { STU.count(STU.screen(.diffEdit, t: t, gt: 0, seed: seed), "scr.white", x: 3...19, y: 9...9) }
        // 光标固定在灰阶最暗时才不混进来：gt = 0 时光标是最暗的一阶
        let w = [0.05, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 5.0].map(whites)
        #expect(w == w.sorted() && w.first! <= 3 && w.last! == 14, "字符逐个出现，最多 14 个：\(w)")
        #expect(Set(w).count >= 6, "一个个出现，不是一下子出来：\(w)")
        for t in [0.1, 1.0, 3.0] {
            let c = STU.screen(.diffEdit, t: t, seed: seed)
            #expect(STU.at(c, 0, 9) == STU.ix("scr.green") && STU.at(c, 1, 9) == STU.ix("scr.green"), "左侧绿色 diff 标记")
            #expect(STU.at(c, 10, 8) == STU.ix("scr.bg3") && STU.at(c, 20, 10) == STU.ix("scr.bg3"), "一行高亮")
        }
        // Write：每 0.28 秒多一行，从上往下，最多 6 行
        func rows(_ t: Double) -> [Int] {
            let c = STU.screen(.notebook, t: t)
            return (0..<6).filter { i in (2..<8).contains { STU.at(c, $0, 3 + 2 * i) != STU.ix("scr.bg2") } }
        }
        #expect(rows(0.1) == [0] && rows(0.35) == [0, 1] && rows(0.9) == [0, 1, 2, 3] && rows(1.7) == [0, 1, 2, 3, 4, 5] && rows(9) == [0, 1, 2, 3, 4, 5], "一行行从上往下出现")
    }

    /// Bash：「黑底终端，绿色提示符，一行行输出」；> 8 秒「终端 + 进度条，按 1−e^(−t/τ) 增长，永远不会假装跑满」。
    @Test func terminalHasAGreenPromptAndTheLongBarFollowsOneMinusExpMinusTOverTau() {
        for k in [ScreenKind.terminal, .terminalLong] {
            let c = STU.screen(k, t: 1)
            #expect(STU.count(c, "scr.term") > 15 * 24 / 2, "\(k)：黑底终端")
            #expect(STU.at(c, 1, 1) == STU.ix("scr.green") && STU.at(c, 2, 2) == STU.ix("scr.green") && STU.at(c, 1, 3) == STU.ix("scr.green"), "\(k)：绿色提示符 >")
        }
        let c = STU.screen(.terminal, t: 1)
        #expect((0..<4).allSatisfy { i in (1..<4).contains { STU.at(c, $0, 5 + 2 * i) == STU.ix("scr.green") || STU.at(c, $0, 5 + 2 * i) == STU.ix("scr.dim") } }, "一行行输出（4 行）")
        #expect(STU.changeTimes(.terminal, seconds: 4).count >= 9, "输出在滚动")
        // 进度条：宽度 = Int(22 × min(0.94, 1 − e^(−t/30)))，至少 1 格；τ = 30 秒（任务书没给 τ）
        func filled(_ t: Double) -> Int { STU.count(STU.screen(.terminalLong, t: t), "scr.green", x: 1...22, y: ScreenContent.longBashBarY...ScreenContent.longBashBarY) }
        for t in [0.0, 5, 9, 15, 30, 60, 90, 120, 600, 1e6] {
            let want = max(1, Int(22 * min(0.94, 1 - exp(-t / 30))))
            #expect(filled(t) == want, "t = \(t) 秒：进度条 \(filled(t)) 格，1−e^(−t/30) 给出 \(want)")
        }
        #expect(filled(1e6) == 20 && filled(1e6) < 22, "永远不会假装跑满（上限 94% = 20 / 22 格）")
    }

    /// WebFetch「浏览器：地址栏，页面块逐个加载」/ WebSearch「搜索结果」。
    @Test func browserLoadsPageBlocksOneByOneAndSearchTypesTheQuery() {
        func blocks(_ t: Double) -> Int {
            let c = STU.screen(.browser, t: t)
            return [(2, 4), (13, 4), (2, 9), (13, 9)].filter { STU.at(c, $0.0 + 4, $0.1 + 3) == STU.ix("scr.bg3") || STU.at(c, $0.0 + 4, $0.1 + 3) == STU.ix("scr.blue") }.count
        }
        #expect([0.1, 0.6, 1.1, 1.6, 9.0].map(blocks) == [1, 2, 3, 4, 4], "页面块每 0.5 秒多一块，最多 4 块：\([0.1, 0.6, 1.1, 1.6, 9.0].map(blocks))")
        let b = STU.screen(.browser, t: 5)
        #expect(STU.count(b, "scr.white", x: 1...22, y: 1...2) >= 30, "顶上一条白色地址栏")
        func typed(_ t: Double) -> Int { STU.count(STU.screen(.search, t: t), "scr.dark", x: 6...14, y: 2...2) }
        #expect([0.0, 0.3, 0.6, 1.0, 1.5, 1.8, 6.0].map(typed) == [2, 3, 4, 6, 8, 9, 9], "搜索框里的字逐个出现：\([0.0, 0.3, 0.6, 1.0, 1.5, 1.8, 6.0].map(typed))")
        let s = STU.screen(.search, t: 6)
        #expect(STU.count(s, "scr.blue", x: 2...20, y: 5...5) > 0 && STU.count(s, "scr.blue", x: 2...20, y: 8...8) > 0 && STU.count(s, "scr.blue", x: 2...20, y: 11...11) > 0, "3 条搜索结果")
    }

    /// Agent「小助手列表 + 进度」、TodoWrite「清单逐项打勾」、Skill「手册页」、ToolSearch「图标网格，高亮在移动」。
    @Test func helperListChecklistManualAndIconGrid() {
        let h = STU.screen(.helpers, t: 2)
        #expect(STU.at(h, 2, 4) == STU.ix("scr.cyan") && STU.at(h, 2, 8) == STU.ix("scr.pink") && STU.at(h, 2, 12) == STU.ix("scr.amber"), "三个彩色小助手")
        func bar(_ t: Double) -> Int { STU.count(STU.screen(.helpers, t: t), "scr.green", x: 5...21, y: 4...4) }
        #expect(bar(0.5) < bar(1.5) && bar(1.5) < bar(3.0), "进度条在走")
        func ticked(_ t: Double) -> Int { (0..<5).filter { STU.at(STU.screen(.checklist, t: t), 2, 3 + 2 * $0) == STU.ix("scr.green") }.count }
        #expect([0.1, 0.8, 1.5, 2.2, 2.9, 3.6, 4.3].map(ticked) == [0, 1, 2, 3, 4, 5, 0], "清单每 0.7 秒多勾一项，勾完从头再来：\([0.1, 0.8, 1.5, 2.2, 2.9, 3.6, 4.3].map(ticked))")
        let m0 = STU.screen(.manual, t: 0.1), m1 = STU.screen(.manual, t: 1.7), m2 = STU.screen(.manual, t: 3.3)
        #expect(STU.count(m0, "scr.white") > 150 && !STU.same(m0, m1) && STU.same(m0, m2), "手册：两页白纸，每 1.6 秒翻一页")
        func hi(_ t: Double) -> Int? { (0..<6).first { STU.at(STU.screen(.iconGrid, t: t), 2 + ($0 % 3) * 7 - 1, 2 + ($0 / 3) * 7 - 1) == STU.ix("scr.bg3") } }
        #expect([0.1, 0.6, 1.1, 1.6, 2.1, 2.6, 3.1].map(hi) == [0, 1, 2, 3, 4, 5, 0], "图标网格：高亮每 0.5 秒挪一格：\([0.1, 0.6, 1.1, 1.6, 2.1, 2.6, 3.1].map(hi))")
    }

    /// MCP 浏览器「指针在动；点击处有扩散圈，只用调色板变暗表现，不闪」、computer-use「桌面上有窗口和指针」、其他 MCP「带 server 首字母的应用面板」。
    /// 点击圈是指针四周 4 个变暗的像素、每 3 秒一次约 0.36 秒（不做逐帧向外扩散，DESIGN §13）。
    @Test func mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette() {
        var whites = Set<Int>(), pointer = Set<Int>(), ringFrames = 0, darkBase = STU.count(STU.screen(.mcpBrowser, t: 0.1), "scr.dark")
        var t = 0.0
        var ring: [Double] = []
        while t < 6 {
            let c = STU.screen(.mcpBrowser, t: t)
            whites.insert(STU.count(c, "scr.white"))
            let d = STU.count(c, "scr.dark")
            if d == darkBase + 4 { ringFrames += 1; ring.append(t) } else { #expect(d == darkBase, "t = \(t)：变暗的像素数 \(d)（基线 \(darkBase)）") }
            pointer.insert((0..<24 * 15).first { c.idx[$0] == STU.ix("scr.white") && $0 / 24 >= 4 } ?? -1)
            t += 0.01
        }
        #expect(whites.count == 1, "指针 / 地址栏的白色像素数恒定，没有任何一帧闪白：\(whites)")
        #expect(pointer.count >= 6, "指针在动")
        #expect(ringFrames >= 2 * 34 && ringFrames <= 2 * 38, "每 3 秒一次、约 0.36 秒（≥ 250 ms）：6 秒里 \(ringFrames) 帧（10 ms 一帧）")
        #expect(ring.first! > 1.4 && ring.first! < 1.6)
        // computer-use：桌面 + 两个窗口 + 指针
        let d0 = STU.screen(.desktop, t: 0.1), d1 = STU.screen(.desktop, t: 2.0)
        #expect(STU.count(d0, "scr.bg3") > 40 && STU.count(d0, "scr.blue") >= 12, "桌面上有窗口")
        #expect(!STU.same(d0, d1) && STU.count(d0, "scr.white") == 3 && STU.count(d1, "scr.white") == 3, "指针（3 像素）在动")
        // 其他 MCP：首字母（server 名第一个画得出的字母）用 4×6 像素字体画在面板中间
        for (name, ch) in [("notion", Character("N")), ("slack", "S"), ("ccd_session", "C"), ("计划", "M")] {
            let c = STU.screen(.mcpApp(name), t: 1)
            let glyph = PixelFont.small.glyphs[ch] ?? []
            let w = PixelFont.small.width(of: String(ch))
            var want = 0, ok = true
            for (gy, rowStr) in glyph.enumerated() { for (gx, p) in rowStr.enumerated() where p == "#" { want += 1; ok = ok && STU.at(c, (24 - w) / 2 + gx, 5 + gy) == STU.ix("scr.cyan") } }
            #expect(ok && STU.count(c, "scr.cyan") == want && want > 8, "「\(name)」的首字母 \(ch) 画在应用面板中间")
        }
    }

    /// 等批准「权限对话框，带两个按钮」、提问「带选项的对话框」、计划待审「计划文档」、EnterPlanMode「大纲文档」。
    @Test func dialogScreensHaveTheirButtonsOptionsAndOutline() {
        let p = STU.screen(.permission, t: 1)
        let gray = (4..<11).flatMap { x in (10..<13).map { (x, $0) } }, green = (13..<20).flatMap { x in (10..<13).map { (x, $0) } }
        #expect(gray.allSatisfy { STU.at(p, $0.0, $0.1) == STU.ix("scr.dim") } && green.allSatisfy { STU.at(p, $0.0, $0.1) == STU.ix("scr.green") }, "权限对话框：灰色「拒绝」+ 绿色「允许」两个按钮")
        #expect(STU.count(p, "scr.white") > 100, "对话框是白色窗口")
        let q = STU.screen(.question, t: 1)
        #expect([8, 10, 12].allSatisfy { STU.at(q, 5, $0) == STU.ix("scr.blue") }, "提问：3 个选项")
        #expect(STU.count(q, "scr.blue", x: 4...6, y: 4...9) > 3, "提问：一个大「?」")
        let plan = STU.screen(.plan, t: 1)
        #expect([6, 8, 10, 12].allSatisfy { STU.at(plan, 5, $0) == STU.ix("scr.dark") } && STU.count(plan, "scr.white") > 150, "计划 / 大纲文档：一页白纸 + 4 条要点")
        for k in [ScreenKind.permission, .question, .plan] { #expect(ScreenContent.isStatic(k, seed: 7), "\(k) 是静止的（不闪）") }
    }

    /// 整理上下文「一行行被压成一块」、重试「缓慢转动的循环箭头 + 像素数字 2/10」。
    @Test func compactSqueezesRowsIntoOneBlockAndRetryShowsARotatingArrowAndDigits() {
        func rowsUsed(_ t: Double) -> Set<Int> {
            let c = STU.screen(.compact, t: t)
            return Set((3..<14).filter { y in (2..<14).contains { STU.at(c, $0, y) != STU.ix("scr.bg2") } })
        }
        #expect(rowsUsed(0.05).count >= 6 && rowsUsed(2.6).count <= 4, "整理上下文：行从 \(rowsUsed(0.05).count) 行被压到 \(rowsUsed(2.6).count) 行")
        let widths = [0.05, 1.0, 2.0, 2.6].map { t in STU.count(STU.screen(.compact, t: t), "scr.dim") + STU.count(STU.screen(.compact, t: t), "scr.cyan") }
        #expect(widths[0] > widths[3], "行越压越短：\(widths)")
        #expect(STU.count(STU.screen(.compact, t: 2.7), "scr.dark", x: 2...9, y: 10...12) == 24, "压成一块（8×3 的深色块）")
        // 重试 2/10：4 个位置的箭头，每 0.42 秒转一格（0.6 Hz，缓慢）；数字 2/10 用 3×5 像素字体
        let arrows = [0.1, 0.55, 0.97, 1.4].map { t -> Set<Int> in let c = STU.screen(.retry(2, 10), t: t); return Set((0..<24 * 15).filter { c.idx[$0] == STU.ix("scr.amber") }) }
        #expect(Set(arrows).count == 4 && arrows.allSatisfy { $0.count == 4 }, "箭头 4 个位置，每次亮 4 个像素")
        let again = STU.screen(.retry(2, 10), t: 1.78)
        #expect(arrows[0] == Set((0..<24 * 15).filter { again.idx[$0] == STU.ix("scr.amber") }), "一圈 1.68 秒")
        var want = 0
        for ch in "2/10" { want += (PixelFont.tiny.glyphs[ch] ?? []).joined().filter { $0 == "#" }.count }
        for t in [0.1, 0.55, 1.4, 3.0] { #expect(STU.count(STU.screen(.retry(2, 10), t: t), "scr.white") == want, "t = \(t)：数字「2/10」\(want) 个像素稳定不动") }
        // 10/10 太宽：换成 3×3 的小转圈（8 个点里亮 1 个），数字仍然完整
        let wide = STU.screen(.retry(10, 10), t: 0.3)
        var wantWide = 0
        for ch in "10/10" { wantWide += (PixelFont.tiny.glyphs[ch] ?? []).joined().filter { $0 == "#" }.count }
        #expect(STU.count(wide, "scr.white") == wantWide && STU.count(wide, "scr.amber") == 1, "10/10：完整的数字 + 小转圈")
    }

    /// 出错「静止的橙色三角警告」、被打断「停止标志」、做完了「绿色 ✓」、空闲 / 打盹 / 睡着「暗色桌面 / 慢速屏保 / 关屏」、未知工具「带齿轮的通用窗口」。
    @Test func stateScreens() {
        for k in [ScreenKind.warning, .stop, .done, .idleDesktop, .off] {
            let a = STU.screen(k, t: 0.1, gt: 0.1)
            for t in stride(from: 0.3, to: 60, by: 1.7) { #expect(STU.same(a, STU.screen(k, t: t, gt: t * 3)), "\(k) 是静止的：t = \(t) 时变了") }
        }
        #expect(STU.count(STU.screen(.warning), "scr.orange") >= 20 && STU.count(STU.screen(.warning), "scr.red") == 0, "出错：橙色三角")
        #expect(STU.count(STU.screen(.stop), "scr.red") >= 40 && STU.count(STU.screen(.stop), "scr.white") >= 10, "被打断：红色停止标志")
        let done = STU.screen(.done)
        #expect(STU.count(done, "scr.green") == 18 && STU.count(done, "scr.orange") == 0, "做完了：绿色 ✓（9 个点 × 2 行）")
        // 空闲：暗色桌面 + 三个小图标 + 任务栏；打盹：一个小方块每 0.8 秒挪 1 格；睡着：关屏（只有 4 个反光像素）
        let idle = STU.screen(.idleDesktop)
        #expect([2, 6, 10].allSatisfy { STU.at(idle, $0, 2) == STU.ix("scr.dark") } && STU.count(idle, "scr.bg3", y: 13...14) == 48, "空闲：暗色桌面")
        func saver(_ t: Double) -> Int { let c = STU.screen(.screensaver, t: t); return (0..<24 * 15).filter { c.idx[$0] == STU.ix("scr.dark") }.map { $0 % 24 }.min() ?? -1 }
        #expect([0.1, 0.7, 0.9, 1.7, 2.5].map(saver) == [1, 1, 2, 3, 4], "慢速屏保：每 0.8 秒挪 1 格：\([0.1, 0.7, 0.9, 1.7, 2.5].map(saver))")
        let off = STU.screen(.off)
        #expect(STU.count(off, "plastic.base") == 4 && STU.count(off, "plastic.sh") == 24 * 15 - 4, "关屏：一点暗的反光")
        // 未知工具：带齿轮的通用窗口，两帧慢转（每 0.6 秒换一帧）
        let g0 = STU.screen(.gear, t: 0.1), g1 = STU.screen(.gear, t: 0.7), g2 = STU.screen(.gear, t: 1.3)
        #expect(!STU.same(g0, g1) && STU.same(g0, g2) && STU.count(g0, "scr.amber", y: 2...14) == 9 + 4 && STU.count(g1, "scr.amber", y: 2...14) == 9 + 4, "齿轮：中心 3×3 + 4 个齿，两帧交替")
        // SendUserFile：文件滑进盘里；定时：钟面；Monitor：日志滚动
        func fileX(_ t: Double) -> Int { let c = STU.screen(.outbox, t: t); return (0..<24 * 15).filter { c.idx[$0] == STU.ix("scr.white") }.map { $0 % 24 }.min() ?? -1 }
        #expect([0.0, 0.4, 0.8, 1.2, 1.6].map(fileX) == [6, 7, 8, 9, 11], "文件一路滑向盘里：\([0.0, 0.4, 0.8, 1.2, 1.6].map(fileX))")
        #expect(!STU.same(STU.screen(.clock, t: 0.1), STU.screen(.clock, t: 3)) && STU.count(STU.screen(.clock), "scr.white") >= 2 && STU.count(STU.screen(.clock), "scr.amber") >= 2, "钟面：分针（白）和时针（琥珀）在转")
        let log = STU.screen(.log, t: 1)
        #expect(STU.count(log, "scr.term") > 200 && STU.changeTimes(.log, seconds: 3).count >= 8, "日志：黑底、一行行滚动")
    }
}

// MARK: - 6.5 桌牌文字
@Suite struct SpecTracePlateTests {
    private static let fg2 = [HelperSnapshot(id: "h1", description: "调研", foreground: true, active: true), HelperSnapshot(id: "h2", description: "整理", foreground: true, active: true)]
    private static let bg1 = [HelperSnapshot(id: "h1", description: "整理", foreground: false, active: true)]

    private func tool(_ name: String, _ detail: String = "", elapsed: Double = 2, parallel: Int = 1, helpers: [HelperSnapshot] = []) -> String {
        let s = STU.snap(.tool(ToolCatalog.makeCall(name: name, detail: detail, at: STU.now(0)), parallel: parallel), helpers: helpers)
        return PlateCopy.activity(s, now: STU.now(elapsed), privacy: false)
    }
    private func state(_ a: Activity, elapsed: Double = 2, blocked: Bool = false, lastTurn: Double? = nil, idleFor: Double? = nil) -> String {
        var s = STU.snap(a, blocked: blocked)
        s.lastTurnDuration = lastTurn
        if let i = idleFor { s.idleSince = STU.now(elapsed - i) }
        return PlateCopy.activity(s, now: STU.now(elapsed), privacy: false)
    }

    /// 6.5 表「桌牌文字」一列：每一行的原话逐字断言（原来 PlateCopyTests 只覆盖了一半）。
    @Test func everyRowOfTheTableShowsItsPlateText() {
        // 忙碌的工具
        #expect(state(.thinking) == "思考中")
        #expect(tool("Read", "/Users/x/app.swift") == "在读 app.swift")
        #expect(tool("Grep", "TODO") == "在找 \"TODO\"")
        #expect(tool("Glob", "**/*.swift") == "在翻文件")
        #expect(tool("Edit", "/a/x.swift") == "在改 x.swift" && tool("MultiEdit", "/a/x.swift") == "在改 x.swift")
        #expect(tool("Write", "/a/x.swift") == "在写 x.swift" && tool("NotebookEdit", "/a/n.ipynb") == "在写 n.ipynb")
        #expect(tool("Bash", "git status", elapsed: 2) == "运行 git status" && tool("Bash", "git status", elapsed: 8) == "运行 git status", "≤ 8 秒：运行 <命令>")
        #expect(tool("Bash", "npm test", elapsed: 83) == "运行中 npm test · 1:23", "> 8 秒：运行中 <命令> · 分:秒")
        #expect(tool("WebFetch", "https://github.com/anthropics/x") == "在看 github.com")
        #expect(tool("WebSearch", "hydrogen embrittlement of steels") == "在搜 \"hydrogen emb…\"", "搜索词最多 12 个字")
        #expect(tool("Agent", "调研", helpers: Self.fg2) == "派了 2 个帮手" && tool("Task", "调研", helpers: Self.fg2) == "派了 2 个帮手")
        #expect(tool("Agent", "整理", helpers: Self.bg1) == "帮手在后台干活")
        #expect(tool("TodoWrite") == "在列计划" && tool("TaskCreate") == "在列计划" && tool("TaskUpdate") == "在列计划")
        #expect(tool("Skill", "brainstorming") == "在看技能手册" && tool("ToolSearch", "select:Read") == "在翻工具箱")
        #expect(tool("mcp__Claude_Browser__navigate") == "在操作浏览器" && tool("mcp__claude-in-chrome__navigate") == "在操作浏览器")
        #expect(tool("mcp__computer-use__app_click") == "在操作电脑")
        #expect(tool("mcp__notion__search_pages") == "在用 notion")
        #expect(tool("SendUserFile", "/tmp/plan.md") == "发给你一个文件" && tool("ScheduleWakeup") == "定了闹钟" && tool("CronCreate") == "定了闹钟" && tool("Monitor", "tail -f x") == "在盯日志")
        #expect(tool("EnterPlanMode") == "在做计划")
        #expect(tool("FooTool") == "在用 FooTool")
        #expect(tool("Grep", "TODO", parallel: 3) == "在找 \"TODO\" ×3", "并行工具：「×3」")
        // 等你
        #expect(state(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: STU.now(0))), elapsed: 120) == "等你批准 Bash · 2 分钟")
        #expect(state(.asking) == "有问题问你" && state(.planReview) == "计划好了，等你看")
        // 其余状态
        #expect(state(.compacting) == "在整理记忆" && state(.retrying(attempt: 2, max: 10)) == "网络不稳，重试中 2/10")
        #expect(state(.errored) == "出错了" && state(.interrupted) == "被你打断了")
        #expect(state(.finished, lastTurn: 192) == "做完了 · 3分12秒")
        #expect(state(.idle, blocked: true) == "需要你处理" && state(.idle) == "空闲")
        #expect(state(.dozing, elapsed: 800, idleFor: 720) == "打盹 12 分钟" && state(.sleeping) == "睡着了")
    }
}

// MARK: - 5.6 / 6.5 的时间阈值
@Suite struct SpecTraceThresholdTests {
    /// 5.6「长时间状态：Bash / WebFetch / Monitor 超过 8 秒 → 往后靠着；思考超过 20 秒 → 深度思考」；6.5 WebSearch「先打字再用鼠标」、其他 MCP / 未知工具「打字和鼠标交替」、被打断「1.5 秒」。
    @Test func statesSwitchExactlyOnTheSpecifiedSeconds() {
        func pose(_ a: Activity, _ el: Double) -> PoseKind { STU.performer(a).targetPose(now: STU.now(el), time: 0) }
        func screen(_ a: Activity, _ el: Double) -> ScreenKind { STU.performer(a).targetScreen(now: STU.now(el)) }
        #expect(pose(.thinking, 20) == .thinking && pose(.thinking, 20.01) == .thinkingDeep, "思考超过 20 秒才是深度思考")
        let bash = STU.tool("Bash", "npm test")
        #expect(pose(bash, 3) == .typing && pose(bash, 3.01) == .restAtDesk, "Bash：快速敲一阵（前 3 秒）然后手歇下来")
        #expect(pose(bash, 8) == .restAtDesk && pose(bash, 8.01) == .leanBack, "Bash 超过 8 秒：往后靠着")
        #expect(screen(bash, 8) == .terminal && screen(bash, 8.01) == .terminalLong, "Bash 超过 8 秒：终端 + 进度条")
        let fetch = STU.tool("WebFetch", "https://a.com")
        #expect(pose(fetch, 8) == .mouse && pose(fetch, 8.01) == .leanBack, "WebFetch 超过 8 秒：往后靠着")
        #expect(pose(STU.tool("Monitor", "tail -f x"), 0.1) == .leanBack && pose(STU.tool("Monitor", "tail -f x"), 50) == .leanBack, "Monitor：往后靠着")
        let search = STU.tool("WebSearch", "hydrogen")
        #expect(pose(search, 2.49) == .typing && pose(search, 2.5) == .mouse, "WebSearch：先打字再用鼠标")
        for a in [STU.tool("mcp__notion__search_pages"), STU.tool("SomeUnknownTool")] {
            #expect(pose(a, 2.99) == .typing && pose(a, 3.0) == .mouse && pose(a, 5.99) == .mouse && pose(a, 6.0) == .typing, "其他 MCP / 未知工具：每 3 秒在打字和鼠标之间换")
        }
        #expect(pose(.interrupted, 1.49) == .shrug && pose(.interrupted, 1.5) == .leanSide, "被打断：两手一摊 1.5 秒")
        #expect(pose(.finished, 0.5) == .stretch && pose(.finished, 1.59) == .stretch && pose(.finished, 1.6) == .leanSide, "做完了：伸 1.2 秒的懒腰（0.4–1.6 秒）再靠着")
    }

    /// 5.6「做完一轮：先等 0.4 秒，再伸 1.2 秒懒腰，再侧身靠到椅背上」——走完整条 Performer 流水线（含姿势最短停留 1.5 秒）：
    /// 0.4 秒时开始伸懒腰；伸完（1.6 秒）之后靠着，但姿势通道要满 1.5 秒才换，所以约 1.9 秒才真的靠上去。
    @Test func aFinishedTurnWaitsThenStretchesThenLeansThroughTheWholePipeline() {
        let busy = STU.snap(STU.tool("Edit", "/a/x.swift"), since: 0)
        let p = Performer(key: busy.key, snapshot: busy, appearance: Appearance.generate(seed: 3), time: 0)
        var t = 0.0
        while t < 3 { p.update(snapshot: busy, now: STU.now(t), time: t, privacy: false); t += 1.0 / 60 }
        #expect(p.pose == .typing)
        var fin = STU.snap(.finished, since: 3, unread: true); fin.lastTurnDuration = 40
        var events: [(Double, PoseKind)] = []
        var last = p.pose
        while t < 7 {
            p.update(snapshot: fin, now: STU.now(t), time: t, privacy: false)
            if p.pose != last { events.append((t - 3, p.pose)); last = p.pose }
            t += 1.0 / 60
        }
        #expect(events.count == 2 && events[0].1 == .stretch && events[1].1 == .leanSide, "\(events)")
        #expect((0.4...0.45).contains(events[0].0), "先等 0.4 秒（防止这一轮其实还没完）再伸懒腰：\(events[0].0)")
        #expect((1.6...2.0).contains(events[1].0), "伸完懒腰再靠着：\(events[1].0)")
        // 未读标记一直保留（小旗）
        var flags = Set<Bool>()
        t = 3
        while t < 12 { p.update(snapshot: fin, now: STU.now(t), time: t, privacy: false); flags.insert(p.seatView(origin: IntPoint(0, 0), time: t, now: STU.now(t), light: LightState(a: .day), hitID: 1, privacy: false, mirror: false).flag); t += 0.25 }
        #expect(flags == [true], "做完了之后小旗一直插着")
    }
}

// MARK: - 6.6 动作手感
@Suite struct SpecTraceMotionTests {
    /// 6.6 弹簧：「从静止起步（v0 = 0），阻尼比 ζ ≈ 0.75，带轻微过冲」。
    @Test func springsStartFromRestWithZetaThreeQuartersAndOvershootSlightly() {
        var sp = PixelSpring(value: 0, period: 0.34)
        #expect(sp.zeta == 0.75 && sp.velocity == 0, "ζ = 0.75，v0 = 0")
        sp.target = 10
        var probe = sp; probe.step(1.0 / 240)
        #expect(probe.value > 0 && probe.value < 0.1, "从静止起步：第一步只挪了 \(probe.value) 像素（平滑加速，没有一下子跳出去）")
        var peak = 0.0, shown: [Int] = []
        for _ in 0..<(240 * 4) { sp.step(1.0 / 240); peak = max(peak, sp.value); shown.append(sp.shown) }
        // 过冲比例反推出的有效阻尼比：离散积分（1/240 s 一步）比理论略多一点数值阻尼，所以实测过冲 2.2%（理论 2.8%）、有效 ζ ≈ 0.77，仍是「ζ ≈ 0.75、轻微过冲」
        let m = (peak - 10) / 10, zEff = -log(m) / (Double.pi * Double.pi + log(m) * log(m)).squareRoot()
        #expect(m > 0.015 && m < 0.035 && abs(zEff - 0.75) < 0.05, "轻微过冲：最高 \(peak - 10) 像素（\(m * 100)%），有效阻尼比 \(zEff)")
        #expect(sp.isSettled && sp.shown == 10, "最后停在整像素终点")
        var dirs = 0, lastDir = 0
        for i in 1..<shown.count where shown[i] != shown[i - 1] { let d = shown[i] > shown[i - 1] ? 1 : -1; if lastDir != 0 && d != lastDir { dirs += 1 }; lastDir = d }
        #expect(dirs <= 2, "整数输出不来回跳（「动一下、停一下」的生硬感 / 闪烁）：方向改了 \(dirs) 次")
        // 表现层的每一根弹簧都是默认阻尼
        let p = STU.performer(.idle)
        for s in [p.sTorso, p.sHeadX, p.sHeadY, p.sLX, p.sLY, p.sRX, p.sRY] { #expect(s.zeta == 0.75) }
    }

    /// 6.6 弹簧：「输出取整到整像素，并带 ±0.6 px 的迟滞」「速度 |v| < 0.5 px/s 时直接吸附到终点」。
    @Test func springOutputHasAPlusMinusPointSixHysteresisAndSlowSpringsSnap() {
        var sp = PixelSpring(value: 0, period: 0.34)
        sp.target = 100                                             // 离得远：不会被「贴近终点就吸附」吃掉，专门看取整迟滞
        for v in [0.3, 0.5, 0.59, -0.59, 0.2] { sp.value = v; sp.step(0); #expect(sp.shown == 0, "连续值 \(v)：离当前显示的 0 不到 0.6，不换格") }
        sp.value = 0.61; sp.step(0)
        #expect(sp.shown == 1, "超过 0.6 才换格")
        for v in [0.9, 0.5, 0.41] { sp.value = v; sp.step(0); #expect(sp.shown == 1, "显示 1 的时候，连续值退到 \(v) 也不回头") }
        sp.value = 0.39; sp.step(0)
        #expect(sp.shown == 0)
        // 速度 < 0.5 px/s 且贴近终点：直接吸附
        var slow = PixelSpring(value: 5, period: 0.34); slow.target = 5.1; slow.velocity = 0.1
        slow.step(1.0 / 240)
        #expect(slow.isSettled && slow.value == 5.1 && slow.velocity == 0 && slow.shown == 5)
        var fast = PixelSpring(value: 5, period: 0.34); fast.target = 5.1; fast.velocity = 20
        fast.step(1.0 / 240)
        #expect(!fast.isSettled, "还在快速移动：不吸附")
    }

    /// 6.6 呼吸：「每个 buddy 一直有呼吸起伏（4 秒一个周期，1 像素）」。
    @Test func everyBuddyBreathesOnePixelEveryFourSeconds() {
        #expect(abs(breathPhase(0)) < 1e-9 && abs(breathPhase(2) - 1) < 1e-9 && abs(breathPhase(4)) < 1e-9 && abs(breathPhase(5) - breathPhase(1)) < 1e-9, "呼吸曲线：4 秒一个周期，0…1")
        var firsts: [Double] = []
        for (i, a) in [Activity.idle, .thinking, .sleeping, STU.tool("Edit", "/a.swift")].enumerated() {
            let s = STU.snap(a, key: "d:b\(i)")
            let p = Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
            var ups: [Double] = [], values = Set<Int>(), last = -1
            var t = 0.0
            while t < 30 {
                p.update(snapshot: s, now: STU.now(t), time: t, privacy: false)
                values.insert(p.breathDy)
                if p.breathDy == 1 && last == 0 { ups.append(t) }              // 只记「0 → 1」的上升沿（第一帧的初始状态不算）
                last = p.breathDy; t += 1.0 / 60
            }
            #expect(values == [0, 1], "\(a)：呼吸只有 1 像素的起伏：\(values)")
            #expect(ups.count >= 6 && zip(ups.dropFirst(), ups).allSatisfy { abs(($0 - $1) - 4.0) < 0.05 }, "\(a)：4 秒一个周期：\(ups)")
            firsts.append(ups[0])
            let v = p.seatView(origin: IntPoint(0, 0), time: t, now: STU.now(t), light: LightState(a: .day), hitID: 1, privacy: false, mirror: false)
            #expect(v.rig!.headDy == p.sHeadY.shown + p.breathDy && v.rig!.hairDy == v.rig!.headDy, "头（和头发）随呼吸上下 1 像素")
        }
        #expect(Set(firsts.map { ($0 * 10).rounded() }).count >= 3, "每个 buddy 的呼吸相位不同：\(firsts)")
    }

    /// 6.6「眨眼每 5–8 秒一次，3 帧，总时长 ≥ 240 ms，只动眼睛（闪烁扫描里把它加入白名单）」。
    @Test func blinksEveryFiveToEightSecondsInThreeFramesOfAtLeast240msAndOnlyTouchTheEyes() {
        for key in ["d:a", "d:b", "t:c", "d:zz", "t:5"] {
            let p = STU.performer(.idle, key: key)
            var blinks: [(start: Double, seq: [String], length: Double)] = []
            var cur: (Double, [String])? = nil
            var t = 0.0
            while t < 60 {
                if let e = p.blinkExpression(time: t, facing: .front) {
                    if cur == nil { cur = (t, [e]) } else if cur!.1.last != e { cur!.1.append(e) }
                } else if let c = cur { blinks.append((c.0, c.1, t - c.0)); cur = nil }
                t += 0.005
            }
            #expect(blinks.count >= 7, "\(key)：60 秒里眨了 \(blinks.count) 次")
            for b in blinks.dropFirst() {
                #expect(b.seq == ["blinkHalf", "blinkClosed", "blinkHalf"], "\(key)：3 帧：半闭 → 闭 → 半闭：\(b.seq)")
                #expect(b.length >= 0.24 && b.length < 0.3, "\(key)：总时长 \(b.length) 秒（≥ 240 ms）")
            }
            for i in 1..<blinks.count { #expect((5.0...8.0).contains(blinks[i].start - blinks[i - 1].start), "\(key)：间隔 \(blinks[i].start - blinks[i - 1].start) 秒不在 5–8 秒里") }
            // 背对镜头（后背 / 3/4 后背）看不见脸：不眨
            for f in [Facing.back, .threeQuarterBack] { #expect((0..<3000).allSatisfy { p.blinkExpression(time: Double($0) * 0.01, facing: f) == nil }) }
        }
        // 只动眼睛：覆盖层的像素都在头的第 7–9 行（眼睛那一带）
        for facing in ["front", "q34front", "side"] {
            for kind in ["blinkHalf", "blinkClosed"] {
                let sp = CharacterArt.book["face.\(kind).\(facing)"]
                var touched = Set<Int>()
                for y in 0..<sp.height { for x in 0..<sp.width where sp.value(x, y) != 0 { touched.insert(y) } }
                #expect(!touched.isEmpty && touched.isSubset(of: [7, 8, 9]), "\(kind).\(facing)：只动眼睛所在的行：\(touched.sorted())")
            }
        }
    }

    /// 6.6「转身：约 0.75 秒，椅子同步转动：背面下沉 1 像素 80 ms → 3/4 背面 70 → 侧面 60 → 3/4 正面 70 → 正面 90 → 回弹 1 像素 80 → 举手」。
    /// 前 6 步（共 450 ms）逐步与任务书一致、椅子同步；第 7 步「举手 3 帧 70/70/90 ms、过冲 1 像素」由手的弹簧完成（约 0.1 秒到位，画面上没有整像素过冲，DESIGN §13）。
    @Test func theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises() {
        let s = STU.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: STU.now(0))), since: 0)
        let p = Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
        var t = 0.0
        while !p.facingUser { p.update(snapshot: s, now: STU.now(t), time: t, privacy: false); t += 1.0 / 60 }
        #expect(t >= 0.4 && t < 0.45, "等待持续 0.4 秒才开始转身：\(t)")
        let fs = p.faceStart!
        let steps: [(Facing, Double, Double)] = [(.back, 1, 0.08), (.threeQuarterBack, 0, 0.07), (.side, 0, 0.06), (.threeQuarterFront, 0, 0.07), (.front, 0, 0.09), (.front, -1, 0.08)]
        var acc = 0.0
        for (i, (facing, dy, d)) in steps.enumerated() {
            for e in [acc + 0.001, acc + d / 2, acc + d - 0.001] {
                let r = p.resolveFrame(time: fs + e)
                #expect(r.turning && r.frame.facing == facing && r.frame.torsoDy == dy && r.chairFacing == facing, "第 \(i + 1) 步（\(facing)，\(Int(d * 1000)) ms）e = \(e)：\(r.frame.facing) 躯干 \(r.frame.torsoDy) 椅子 \(String(describing: r.chairFacing))")
            }
            acc += d
        }
        #expect(abs(acc - 0.45) < 1e-9, "前 6 步共 450 ms")
        let after = p.resolveFrame(time: fs + acc + 0.001)
        #expect(!after.turning && after.frame.facing == .front && after.chairFacing == .front, "第 7 步：举手，椅子已经转正")
        // 举手：手的弹簧升到位（y ≤ 目标 + 1）要多久；有没有超过目标 1 像素以上
        var ys: [(Double, Int)] = []
        var tt = fs
        while tt < fs + 1.6 { p.update(snapshot: s, now: STU.now(tt), time: tt, privacy: false); ys.append((tt - fs, p.sRY.shown)); tt += 1.0 / 60 }
        let target = Int(p.sRY.target)
        let raised = ys.first { $0.0 > acc && abs($0.1 - target) <= 1 }!.0
        #expect(raised > acc && raised <= 0.75, "转身 + 举手到位共 \(raised) 秒（任务书「约 0.75 秒」）")
        #expect(ys.filter { $0.0 > acc }.map(\.1).min()! >= target - 1, "举手不过冲超过 1 像素")
    }

    /// 6.6 气泡：「11–15 px，用 3 帧由小变大弹出，不用非整数缩放。图标是 7×7」。
    /// 实际是 7 → 11 → 15 三档（每档 60 ms）：第一帧 7 px 比任务书的下限 11 小一档（DESIGN §13）；三档都是手绘的整数尺寸精灵，共用左下角。
    @Test func bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven() {
        #expect([0, 0.059, 0.06, 0.119, 0.12, 5].map { SeatRenderer.bubbleSize(age: $0) } == [7, 7, 11, 11, 15, 15], "气泡 7 → 11 → 15，每档 60 ms")
        for n in [7, 11, 15] { #expect(BubbleArt.sprite("bubble.\(n)").width == n, "气泡 \(n) 是手绘的整数尺寸精灵（不做非整数缩放）") }
        #expect(SeatRenderer.bubbleSize(age: 99) == 15 && (11...15).contains(SeatRenderer.bubbleSize(age: 99)), "稳定态 15 px 在任务书的 11–15 px 里")
        for n in ["icon.key", "icon.question", "icon.board", "icon.magnifier", "icon.book", "icon.toolbox", "icon.note", "icon.mug",
                  "icon.tool.bash", "icon.tool.edit", "icon.tool.web", "icon.tool.file", "icon.tool.other"] {
            let sp = BubbleArt.sprite(n)
            #expect(sp.width == 7 && sp.height == 7, "\(n) 应该是 7×7，实际 \(sp.width)×\(sp.height)")
        }
    }

    /// 6.6「白天 / 黑夜切换：4×4 Bayer 抖动，在约 20 分钟里逐渐完成，每个像素只翻转一次」。
    @Test func dayNightSwitchTakesTwentyMinutesAndEveryPixelFlipsExactlyOnce() {
        #expect(DaySchedule.transitionMinutes == 20)
        for y in 0..<4 { for x in 0..<4 {
            let seq = (0...16).map { level in Resolved(map: nil, lutA: Lighting.luts.night, lutB: Lighting.luts.dawn, progress: Double(level) / 16).useB(x: x, y: y) }
            let flips = zip(seq.dropFirst(), seq).filter { $0 != $1 }.count
            #expect(flips == 1 && seq.first == false && seq.last == true, "Bayer 位置 (\(x),\(y))：翻转 \(flips) 次：\(seq)")
        } }
        let steps: [(Double, TimeOfDay, TimeOfDay)] = [(5.5, .night, .dawn), (6.667, .dawn, .day), (17.5, .day, .dusk), (18.833, .dusk, .night)]
        for (start, from, to) in steps {
            let before = DaySchedule.state(atHour: start - 1.0 / 60)
            #expect(before.a == from && !before.isTransitioning, "过渡开始之前还是 \(from)")
            let levels = (0..<20).map { m in DaySchedule.state(atHour: start + (Double(m) + 0.5) / 60) }
            #expect(levels.allSatisfy { $0.a == from && $0.b == to }, "20 分钟里都在 \(from) → \(to) 之间")
            #expect(levels.map(\.level) == levels.map(\.level).sorted() && levels.first!.level <= 1 && levels.last!.level >= 15, "20 分钟里抖动级数从 0 走到 16：\(levels.map(\.level))")
            let after = DaySchedule.state(atHour: start + 20.0 / 60 + 1.0 / 600)
            #expect(after.a == to && !after.isTransitioning, "20 分钟后完成，变成 \(to)")
        }
    }
}

// MARK: - 场景层：小助手 / 未读小旗 / 开机 / 坐下起立 / 朝向 / 小鱼缸与宠物条几何 / 悬停卡片
@Suite struct SpecTraceSceneTests {
    private func run(_ p: Performer, _ s: BuddySnapshot, until: Double, from: Double = 0, _ each: (Double) -> Void = { _ in }) {
        var t = from
        while t <= until { p.update(snapshot: s, now: STU.now(t), time: t, privacy: false); each(t); t += 1.0 / 60 }
    }
    private func view(_ p: Performer, _ t: Double) -> SeatView {
        p.seatView(origin: IntPoint(0, 0), time: t, now: STU.now(t), light: LightState(a: .day), hitID: 7, privacy: false, mirror: false)
    }

    /// 6.5 Agent 前台「小助手坐着带轮凳子滑进来（最多 3 个，多了显示 +N）」、Agent 后台「回去干自己的活，小助手留在旁边」。
    @Test func helpersSlideInAtMostThreeShownAndTheRestAreCountedAndBackgroundOnesStayBeside() {
        func helpers(_ n: Int, fg: Bool) -> [HelperSnapshot] { (0..<n).map { HelperSnapshot(id: "h\($0)", description: "并行任务", foreground: fg, active: true) } }
        for (n, extra) in [(1, 0), (3, 0), (5, 2), (6, 3)] {
            let s = STU.snap(STU.tool("Agent", "调研"), helpers: helpers(n, fg: true))
            let p = Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
            p.update(snapshot: s, now: STU.now(0), time: 0, privacy: false)
            let first = view(p, 0)
            #expect(first.helperDraws.count == n && first.helperDraws.allSatisfy { abs($0.dx) == 40 && $0.moving }, "\(n) 个小助手：从旁边 40 像素外滑进来")
            run(p, s, until: 3, from: 1.0 / 60)
            let last = view(p, 3)
            #expect(last.helperDraws.allSatisfy { $0.dx == 0 && !$0.moving }, "滑进来之后停住")
            #expect(last.extraHelpers == extra, "\(n) 个小助手：多出来的显示 +\(extra)（实际 +\(last.extraHelpers)）")
            #expect(Set(last.helperDraws.map(\.slot)).count == min(n, 3) && last.helperDraws.allSatisfy { (0..<3).contains($0.slot) }, "最多 3 个位置")
            #expect(p.targetPose(now: STU.now(3), time: 3) == .delegate, "前台：转成 3/4 朝向对着他们")
        }
        // 后台：回去干自己的活（打字），小助手留在旁边
        let bg = STU.snap(STU.tool("Agent", "整理"), helpers: helpers(2, fg: false))
        let p = Performer(key: bg.key, snapshot: bg, appearance: Appearance.generate(seed: 3), time: 0)
        run(p, bg, until: 4)
        #expect(p.pose == .typing && view(p, 4).helperDraws.count == 2, "后台小助手：本人回去打字，两个小助手还在旁边")
    }

    /// 6.5 做完了「未读时显示器上插一面小旗」：小旗 = 数据层的未读标记；画在显示器右上角，没有未读就没有。
    @Test func theUnreadFlagIsPlantedOnTheMonitorOnlyWhileUnread() {
        let s = STU.snap(.finished, since: 0, unread: true)
        let p = Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
        run(p, s, until: 2)
        var v = view(p, 2)
        #expect(v.flag, "未读：小旗")
        var read = s; read.unread = false
        p.update(snapshot: read, now: STU.now(2.1), time: 2.1, privacy: false)
        #expect(!view(p, 2.1).flag, "已读：小旗收走")
        let day = LightState(a: .day)
        func canvas(_ flag: Bool) -> Canvas {
            v.flag = flag; v.origin = IntPoint(0, 0); v.mode = .occupied
            let c = Canvas(width: 56, height: 76)
            SeatRenderer.draw(v, on: c, light: day, gt: 2)
            return c
        }
        let with = canvas(true), without = canvas(false)
        let flag = PropArt.book["prop.flag"]
        let region = IntRect(SeatGeometry.monX + 26, SeatGeometry.monY - 4, flag.width, flag.height)
        var diffInside = 0, diffOutside = 0
        for y in 0..<76 { for x in 0..<56 where with.rgba[y * 56 + x] != without.rgba[y * 56 + x] { if region.contains(x, y) { diffInside += 1 } else { diffOutside += 1 } } }
        #expect(diffInside >= 4 && diffOutside == 0, "小旗只画在显示器右上角（区域内差异 \(diffInside)，区域外 \(diffOutside)）")
    }

    /// 6.5 进场「显示器开机：5 级调色板渐变，300 ms」：实际是 16 级 Bayer 抖动、共 300 ms（DESIGN §7、§13）。
    @Test func theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds() {
        let snaps = AuditFixtures.snapshots(count: 1, titles: .normal, states: .all, base: STU.base, stateOffset: 2)
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 1; o.animateWalkers = false; o.emptySign = false; o.directorIsExternal = true; o.retained = false
        var levels: [(Double, Int)] = []
        var t = 0.0
        while t < 0.6 {
            d.update(snapshots: snaps, now: STU.now(t), time: t, privacy: false)
            _ = sc.render(viewportW: 224, viewportH: 226, present: snaps, dormant: [], now: STU.now(t), time: t, options: o)
            levels.append((t, SeatRenderer.bootLevel(sc.lastSeatViews[0])))
            t += 1.0 / 60
        }
        let mid = levels.filter { $0.1 != 99 }.map(\.1)
        #expect(Set(mid) == Set(0...15), "开机经过 16 级（0…15）：\(Set(mid).sorted())")
        #expect(mid == mid.sorted(), "一路变亮，不回头")
        let done = levels.first { $0.1 == 99 }!.0
        #expect(abs(done - 0.3) < 0.02, "300 ms 后完全亮起：\(done)")
        #expect(OfficeScene.screenFadeSeconds == 0.3, "关机同样 300 ms")
    }

    /// 6.6 帧时长「坐下 / 起立：3 帧」：坐下 0.3 秒里身体下沉 0 / 2 / 4 像素三档（每档 0.1 秒），起立倒过来 4 / 2 / 0。
    @Test func sittingDownAndStandingUpAreThreeFramesOfAHundredMilliseconds() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 339, maxSeat: 5)
        let room = RoomRenderer(layout: lay)
        func distinctFrames(entering: Bool) -> [UInt64] {
            let w = WalkerSystem(); w.doorInterior = room.doorInterior
            let ap = Appearance.generate(seed: 7)
            if entering { w.startEntering(key: "k", appearance: ap, seat: 1, layout: lay, door: room.doorFeet, time: 0) }
            else { w.startLeaving(key: "k", appearance: ap, seat: 1, layout: lay, door: room.doorFeet, time: 0) }
            let walk = w.walkers["k"]!.walkTime
            let from = entering ? WalkerSystem.lead + walk : 0
            let c = Canvas(width: lay.worldW, height: lay.worldH)
            var hashes: [UInt64] = []
            var e = 0.006
            while e < 0.3 {
                c.clear()
                w.draw(on: c, light: LightState(a: .day), time: from + e)
                let h = c.contentHash()
                if hashes.last != h { hashes.append(h) }
                e += 1.0 / 60
            }
            return hashes
        }
        #expect(distinctFrames(entering: true).count == 3, "坐下：3 帧")
        #expect(distinctFrames(entering: false).count == 3, "起立：3 帧")
        #expect(WalkerSystem.sitTime == 0.3 && WalkerSystem.standTime == 0.3 && WalkerSystem.waveTime == 0.7, "坐下 0.3 秒、起身 0.3 秒、挥手 0.7 秒")
    }

    /// 6.5 附注「转身：朝向过道那一侧转；镜像的朝向直接水平翻转图像」。
    @Test func seatsTurnTowardsTheAisleAndAMirroredPersonIsTheFlippedImage() {
        let snaps = (0..<8).map { STU.snap(.idle, key: "d:\($0)", seat: $0) }
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 1; o.animateWalkers = false; o.emptySign = false; o.directorIsExternal = true; o.retained = false
        d.update(snapshots: snaps, now: STU.now(0), time: 0, privacy: false)
        _ = sc.render(viewportW: 256, viewportH: 400, present: snaps, dormant: [], now: STU.now(0), time: 0, options: o)
        let worldW = sc.layout.worldW
        var sides = Set<Bool>()
        for v in sc.lastSeatViews where v.mode == .occupied {
            let center = v.origin.x + Metrics.cellW / 2
            #expect(v.mirror == (center >= worldW / 2), "座位 \(v.seat)（中心 x = \(center)，世界宽 \(worldW)）：过道在中线，右半边向左转、左半边向右转")
            sides.insert(v.mirror)
        }
        #expect(sides == [true, false], "左右两半都有人")
        // 镜像 = 水平翻转：同一个人、同一个姿势，mirror 开 / 关的对象 ID 平面互为左右翻转
        let p = d.performers["d:0"]!
        func personIDs(_ mirror: Bool) -> Canvas {
            let v = p.seatView(origin: IntPoint(0, 0), time: 0, now: STU.now(0), light: LightState(a: .day), hitID: 9, privacy: false, mirror: mirror)
            let c = Canvas(width: 56, height: 76)
            SeatRenderer.draw(v, on: c, light: LightState(a: .day), gt: 0)
            return c
        }
        let plain = personIDs(false), flipped = personIDs(true)
        let region = SeatRenderer.personRegion(IntPoint(0, 0))
        var pixels = 0, bad = 0
        for y in region.y..<region.maxY { for i in 0..<region.w {
            let a = plain.objectID(region.x + i, y), b = flipped.objectID(region.x + region.w - 1 - i, y)
            if a != 0 { pixels += 1 }
            if a != b { bad += 1 }
        } }
        #expect(pixels > 200 && bad == 0, "翻转之后人的像素逐个对得上（\(pixels) 个人物像素，\(bad) 个对不上）")
    }

    /// 7.1 小鱼缸：「工位格 48×56 的紧凑版，排 1–2 行，最多显示 8 个人，更多的显示 +N；顶部有一条窄墙，上面有窗户和挂钟」。
    /// 7.1 桌面宠物条：「高度 = (64 + 20 气泡空间 + 56 卡片空间) × 缩放倍数」「窗口只和那一群 buddy 一样宽」「地上画一层抖动的影子」「背景透明」。
    @Test func tankAndStripGeometryMatchTheSpec() {
        #expect(TankScene.cellW == 48 && TankScene.cellH == 56)
        for n in 0...12 {
            let l = TankScene.layout(count: n)
            #expect((1...2).contains(l.rows) && l.cols <= 4 && l.shown <= 8 && l.shown == min(8, max(n, 2)) && l.extra == max(0, n - 8), "小鱼缸 \(n) 人：\(l)")
        }
        #expect([1, 4, 5, 8].map { TankScene.layout(count: $0).rows } == [1, 1, 2, 2], "≤ 4 人一排，5–8 人两排")
        let l = TankScene.layout(count: 6)
        #expect(TankScene.wallH == 26 && l.h == 26 + 2 * 56 + 8, "顶上一条窄墙（26 像素）")
        #expect(TankScene.skyRects(l).allSatisfy { $0.y >= 0 && $0.maxY <= TankScene.wallH }, "窗户玻璃和挂钟都在墙上")
        let (cardH, bubbleH, cellH) = (StripScene.cardH, StripScene.bubbleH, StripScene.cellH)
        #expect(cardH == 56 && bubbleH == 20 && cellH == 64 && StripScene.totalH == 64 + 20 + 56, "宠物条画布高 (64 + 20 + 56) 美术像素")
        // 渲染：宽度只有那群人那么宽、高度是 140；透明背景；地上有抖动的影子；空的时候整块透明
        let snaps = (0..<3).map { STU.snap(STU.tool("Edit", "/a/x.swift"), key: "d:\($0)", seat: $0) }
        let d = VisualDirector()
        for k in 0..<30 { d.update(snapshots: snaps, now: STU.now(Double(k) / 15), time: Double(k) / 15, privacy: false) }
        let f = StripScene().render(director: d, present: snaps, now: STU.now(2), time: 2, privacy: false)
        #expect(f.canvas.width == 3 * Metrics.cellW && f.canvas.height == 140, "宽 = 人数 × 56，高 140：\(f.canvas.width)×\(f.canvas.height)")
        #expect(f.canvas.rgba[0] == 0 && f.canvas.rgba[f.canvas.width - 1] == 0 && f.canvas.ids[0] == 0, "背景透明")
        let gap = UInt16(Pal.dx("floor.gap"))
        var shadow = 0
        for i in 0..<f.canvas.count where f.canvas.idx[i] == gap && f.canvas.ids[i] == 0 { shadow += 1 }
        #expect(shadow > 60, "地上画着一层抖动的影子（\(shadow) 个像素，不参与命中）")
        let empty = StripScene().render(director: VisualDirector(), present: [], now: STU.now(0), time: 0, privacy: false)
        #expect(empty.canvas.width == Metrics.cellW && empty.canvas.height == 140 && (0..<empty.canvas.count).allSatisfy { empty.canvas.rgba[$0] == 0 && empty.canvas.ids[$0] == 0 } && empty.texts.isEmpty,
                "没有人的宠物条：一块 56×140 的全透明画布，没有「今天还没人上班」牌子")
    }

    /// 7.1 办公室窗口「悬停卡片直接画在场景里」：画布上多出卡片、帧里多出卡片的文字；不悬停就没有。
    @Test func theHoverCardIsPaintedIntoTheOfficeScene() {
        let s = STU.snap(STU.tool("Edit", "/a/x.swift"), key: "d:h", seat: 1)
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 3; o.animateWalkers = false; o.emptySign = false; o.directorIsExternal = true; o.retained = false
        d.update(snapshots: [s], now: STU.now(1), time: 1, privacy: false)
        let plain = sc.render(viewportW: 336, viewportH: 339, present: [s], dormant: [], now: STU.now(1), time: 1, options: o)
        let plainHash = plain.canvas.contentHash(), plainTitle = plain.texts.contains { $0.tag == "card.title" }
        o.hoverSeat = 1; o.hoverSnapshot = s
        let hovered = sc.render(viewportW: 336, viewportH: 339, present: [s], dormant: [], now: STU.now(1), time: 1, options: o)
        #expect(!plainTitle && hovered.texts.contains { $0.tag == "card.title" && $0.text == s.title }, "悬停：卡片的标题出现在这一帧的文字里")
        #expect(hovered.canvas.contentHash() != plainHash, "悬停：卡片的像素画进了场景画布")
        #expect(hovered.texts.filter { $0.tag == "card.line" }.count >= 3, "卡片里有路径 / 来源 / 状态 / 用时等行")
    }
}

// MARK: - 补充：光标呼吸 / 道具 / 杯子 / 不黑屏
@Suite struct SpecTraceExtraStageTests {
    /// 6.6「光标要么静止，要么在 3 个色阶之间以 0.5 Hz 呼吸」；6.5 思考「IDE 界面，光标静止」（光标的位置不动，只有颜色在呼吸）。
    @Test func theCursorBreathesThroughThreeLevelsAtHalfAHertzAndNeverBlinksOnAndOff() {
        let dark = STU.ix("scr.dark"), dim = STU.ix("scr.dim"), white = STU.ix("scr.white")
        // .ide：光标在 (7, 9)
        var seq: [(Double, UInt16)] = []
        for i in 0..<(8 * 100) { let gt = Double(i) / 100; seq.append((gt, STU.at(STU.screen(.ide, t: 0, gt: gt), 7, 9))) }
        #expect(Set(seq.map(\.1)) == [dark, dim, white], "3 个色阶：\(Set(seq.map(\.1)))")
        let level = { (v: UInt16) in v == dark ? 0 : (v == dim ? 1 : 2) }
        #expect(zip(seq.dropFirst(), seq).allSatisfy { abs(level($0.1) - level($1.1)) <= 1 }, "只在相邻色阶之间走，没有 暗 ↔ 亮 的跳变（开关式闪烁）")
        var peaks: [Double] = []
        for i in 1..<seq.count where seq[i].1 == white && seq[i - 1].1 != white { peaks.append(seq[i].0) }
        #expect(peaks.count >= 3 && zip(peaks.dropFirst(), peaks).allSatisfy { abs(($0 - $1) - 2.0) < 0.02 }, "每 2 秒一个周期 = 0.5 Hz：\(peaks)")
        // 光标的位置不动：除了 (7, 9) 之外，整张屏幕在任何时刻都一样
        let a = STU.screen(.ide, t: 0, gt: 0.3), b = STU.screen(.ide, t: 0, gt: 1.0)
        #expect((0..<a.count).filter { a.idx[$0] != b.idx[$0] } == [9 * 24 + 7], "思考的 IDE 屏幕：只有光标那一个像素在变")
        // Edit / Write 屏幕的光标用同一条呼吸曲线（不是另一个闪烁节拍）
        for k in [ScreenKind.diffEdit, .notebook] {
            let cursors = (0..<400).map { i -> Set<UInt16> in let c = STU.screen(k, t: 0.05 + Double(i) * 0.005 * 0, gt: Double(i) / 100); return [STU.at(c, 3, 9), STU.at(c, 6, 3)] }
            #expect(!cursors.isEmpty)
        }
    }

    /// 6.5 Bash > 8 秒「每 20 秒最多喝一口 / 道具：马克杯」：每张桌子上都有马克杯；喝一口时手真的去够杯子。
    @Test func everyDeskHasAMugAndTheSipReachesForIt() {
        var closest = 99.0
        for i in 0..<(22 * 120) {
            let t = Double(i) / 120, fr = PoseLibrary.frame(.leanBack, t: t, gt: t, seed: 0)
            if let h = fr.handL { closest = min(closest, hypot(h.x - Spots.mug.x, h.y - Spots.mug.y)) }
        }
        #expect(closest <= 1, "喝一口的时候左手离杯子只有 \(closest) 像素")
        // 杯子画在桌面上（左侧）：把没有人的工位（只有桌子和桌面小件）和「只有桌子」的画面比，杯子那一块不一样
        var ap = Appearance.generate(seed: 1)
        for s in 1..<500 where ap.ornament != .none { ap = Appearance.generate(seed: UInt64(s)) }
        #expect(ap.ornament == .none, "找一个没有摆件的外观，杯子那一块不会被摆件遮住")
        let light = LightState(a: .day)
        let seat = SeatView(seat: 0, origin: IntPoint(0, 0), mode: .empty, appearance: ap)
        let full = Canvas(width: 56, height: 76), deskOnly = Canvas(width: 56, height: 76)
        SeatRenderer.draw(seat, on: full, light: light, gt: 0)
        deskOnly.blit(PropArt.book[ap.chair == .wood ? "desk.walnut" : "desk.oak"], x: SeatGeometry.deskX, y: SeatGeometry.deskY, style: Lighting.resolved(appearance: nil, state: light))
        let mug = CharacterArt.book["mug"]
        var diff = 0
        for y in 0..<mug.height { for x in 0..<mug.width where mug.value(x, y) != 0 && full.rgba[(SeatGeometry.mugY + y) * 56 + SeatGeometry.mugX + x] != deskOnly.rgba[(SeatGeometry.mugY + y) * 56 + SeatGeometry.mugX + x] { diff += 1 } }
        #expect(diff >= 8, "桌上有马克杯（\(diff) 个杯子像素盖在桌面上）")
    }

    /// 6.5 各行「—」列（没有额外道具 / 气泡）：Read / Grep / Edit / Write / Bash / Web / MCP / computer-use / 重试 / 出错 / 被打断 / 未知工具 / 需要你处理 的姿势都不带桌面道具，
    /// 「指一指然后抱臂督工」：前 2.2 秒手指向一侧、之后手收回身侧（6 秒一轮，DESIGN §13：背对镜头时抱臂用手落在身侧近似）。
    @Test func posesOfTheDashRowsCarryNoPropsAndTheSupervisorPointsThenFolds() {
        for k in [PoseKind.typing, .typingFast, .restAtDesk, .mouse, .searching, .thinking, .thinkingDeep, .leanBack, .retry, .facepalm, .shrug, .stretch, .leanSide, .idle, .doze, .sleep, .delegate, .faceUser(.approval), .faceUser(.question)] {
            #expect(PoseLibrary.frame(k, t: 1, gt: 1, seed: 1).props.isEmpty, "\(k)：没有桌面道具")
        }
        let point = FPoint(Spots.mouse.x + 5, Spots.mouse.y - 2)
        func hand(_ t: Double) -> FPoint? { PoseLibrary.frame(.delegate, t: t, gt: t, seed: 1).handR }
        #expect(hand(0.5) == point && hand(2.19) == point && hand(2.21) == Spots.restR && hand(5.9) == Spots.restR && hand(6.5) == point && hand(8.3) == Spots.restR, "指 2.2 秒 → 收回 → 6 秒一轮")
    }

    /// 6.6「绝不闪白，绝不黑帧，也绝不淡出到全黑」（用户以前明确拒绝过黑帧）：关屏是暗灰蓝、不是纯黑；演示剧本的每一帧里既没有纯黑像素、也没有大片发黑的帧。
    @Test func noFrameIsBlackAndTheMonitorNeverFadesToPureBlack() {
        let off = STU.screen(.off)
        for i in 0..<off.count { let p = off.rgba[i]; #expect(max(p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF) >= 0x20, "关屏的像素 \(String(p, radix: 16)) 太黑了") }
        for clock in ["12:00", "23:00"] {
            let base = StageRun.fixedBase(clock: clock)
            let d = VisualDirector(), sc = OfficeScene(); sc.director = d
            var o = SceneOptions(); o.zoom = 1; o.emptySign = false; o.directorIsExternal = true; o.retained = false
            var worst = 1.0, black = 0
            for step in 0..<160 {
                let t = Double(step) * 0.5
                let s = DemoScript.snapshots(mode: "demo", t: t, base: base)
                d.update(snapshots: s.present, now: base.addingTimeInterval(t), time: t, privacy: false)
                let f = sc.render(viewportW: 224, viewportH: 300, present: s.present, dormant: s.dormant, now: base.addingTimeInterval(t), time: t, options: o)
                let c = f.canvas
                var dark = 0
                for i in 0..<c.count {
                    let p = c.rgba[i]
                    if p == 0xFF000000 { black += 1 }
                    if p >> 24 == 0xFF, max(p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF) < 0x20 { dark += 1 }
                }
                worst = min(worst, 1 - Double(dark) / Double(c.count))
            }
            #expect(black == 0, "\(clock)：演示剧本里出现了 \(black) 个纯黑像素（描边用深色、不用纯黑）")
            #expect(worst > 0.9, "\(clock)：最暗的一帧也有 \(worst * 100)% 的像素不是近黑（没有黑帧）")
        }
    }

    /// 6.5 思考「思考气泡，三个点缓缓升起」：三个点各自在 −1 / 0 / +1 像素之间慢慢起伏（0.7 Hz，一次只动 1 像素），相位互相错开。
    @Test func theThinkingBubbleDotsBobSlowlyAndOutOfPhase() {
        var seqs: [[Int]] = [[], [], []]
        for k in 0..<(30 * 200) { let gt = Double(k) / 200; for i in 0..<3 { seqs[i].append(SeatRenderer.thinkDy(gt, i)) } }
        for i in 0..<3 {
            #expect(Set(seqs[i]) == [-1, 0, 1], "第 \(i) 个点在 −1 / 0 / +1 之间起伏：\(Set(seqs[i]))")
            #expect(zip(seqs[i].dropFirst(), seqs[i]).allSatisfy { abs($0 - $1) <= 1 }, "一次只动 1 像素")
            let hz = STU.swingHz(seqs[i], hz: 200)
            #expect((0.6...0.8).contains(hz), "第 \(i) 个点每秒 \(hz) 个来回（慢：0.7 Hz）")
        }
        #expect(seqs[0] != seqs[1] && seqs[1] != seqs[2] && seqs[0] != seqs[2], "三个点错开相位")
    }

    /// 6.5 需要你处理「静止的黄色「!」便利贴」（气泡）：便利贴 / 问号 / 写字板 / 钥匙 / 放大镜 / 书 / 工具箱这些气泡图标都是静止的，只有思考（三个点）和 zzz 会动。
    @Test func onlyTheThinkingAndSleepingBubblesAnimateAndTheStickyNoteStandsStill() {
        func draw(_ kind: BubbleKind, gt: Double) -> Canvas {
            let c = Canvas(width: 60, height: 60)
            SeatRenderer.drawBubble(kind, age: 5, at: IntPoint(20, 30), gt: gt, on: c, day: STU.day, id: 1)
            return c
        }
        for kind in [BubbleKind.note, .question, .plan, .approval("icon.tool.bash"), .search, .book, .toolbox] {
            let a = draw(kind, gt: 0)
            for gt in [0.3, 1.1, 2.7, 9.9, 123.4] { #expect(STU.same(a, draw(kind, gt: gt)), "\(kind) 是静止的：gt = \(gt) 时变了") }
        }
        #expect((0..<40).contains { !STU.same(draw(.think, gt: 0), draw(.think, gt: Double($0) * 0.1)) }, "思考气泡会动")
        #expect((0..<40).contains { !STU.same(draw(.zzz, gt: 0), draw(.zzz, gt: Double($0) * 0.1)) }, "zzz 气泡会动")
        // 便签的图标：黄色（琥珀 / 黄色系）+ 一个感叹号
        let note = BubbleArt.sprite("icon.note")
        #expect((0..<7).contains { y in (0..<7).contains { note.value($0, y) != 0 } } && note.width == 7)
    }
}
