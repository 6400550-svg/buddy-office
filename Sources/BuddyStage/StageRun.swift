import Foundation
import CoreGraphics
import PixelKit
import BuddyArt
import BuddyCore

/// 测试和命令行共用的「跑一遍演示剧本」的入口：闪烁扫描、金图哈希。
public enum StageRun {
    /// 固定的日期（2026-06-15）+ 给定的钟点：墙上日历的日期数字、白板计数都不随运行日期变，金图才稳定。
    public static func fixedBase(clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        let hour = (parts.first ?? 12) + (parts.count > 1 ? parts[1] / 60 : 0)
        var dc = DateComponents()
        dc.year = 2026; dc.month = 6; dc.day = 15
        dc.hour = Int(hour); dc.minute = Int((hour - Double(Int(hour))) * 60); dc.second = parts.count > 2 ? Int(parts[2]) : 0
        return Calendar.current.date(from: dc) ?? Date()
    }

    /// 办公室视口：窗口内容区 672×678 点，按缩放倍数换成美术像素（1 倍时会排成一整行 / 两排，3 倍是 224×226）。
    public static func officeViewport(zoom: Int) -> (w: Int, h: Int) { (672 / max(1, zoom), 678 / max(1, zoom)) }

    public struct FlickerResult {
        public var frames = 0
        public var findings: [FlickerScan.Finding] = []
        public var tolerated = 0
        /// dump = true 时：检查 2 抓到的每一处（含被容忍的）的条带图（第几帧、几个像素、图）。
        public var strips: [(frame: Int, count: Int, tolerated: Bool, image: CGImage)] = []
    }

    /// 对一个场景跑闪烁扫描。分段（画布尺寸变了另起一段：跨尺寸的逐像素比较没有意义）。
    public static func flicker(scene: String, zoom: Int = 3, clock: String = "12:00", mode: String = "demo",
                               from: Double = 0, to: Double = 79.9, fps: Double = 30, strict: Bool = false,
                               viewport: (w: Int, h: Int)? = nil, dump: Bool = false) -> FlickerResult {
        let base = fixedBase(clock: clock)
        let director = VisualDirector()
        let office = OfficeScene(); office.director = director
        let tank = TankScene(), strip = StripScene()
        var opts = SceneOptions(); opts.zoom = zoom; opts.tally = 7; opts.directorIsExternal = true
        let vp = viewport ?? officeViewport(zoom: zoom)
        var scan = FlickerScan(fps: fps)
        if strict { scan.tolerance = 0 }
        var res = FlickerResult()
        var frameOffset = 0
        var lastSize = (0, 0)
        var t = from
        var i = 0
        while t <= to + 1e-9 {
            let s = DemoScript.snapshots(mode: mode, t: t, base: base)
            let nt = base.addingTimeInterval(t)
            director.update(snapshots: s.present, now: nt, time: t, privacy: false)
            var canvas: Canvas
            var meta = FlickerScan.FrameMeta()
            switch scene {
            case "tank":
                canvas = tank.render(director: director, present: s.present, now: nt, time: t, privacy: false).canvas
                meta.transitionIDs = tank.transitionIDs; meta.allowRects = tank.blinkRects
            case "strip":
                canvas = strip.render(director: director, present: s.present, now: nt, time: t, privacy: false).canvas
                meta.transitionIDs = strip.transitionIDs; meta.allowRects = strip.blinkRects
            default:
                canvas = office.render(viewportW: vp.w, viewportH: vp.h, present: s.present, dormant: s.dormant, now: nt, time: t, options: opts).canvas
                meta.transitionIDs = Set(office.transitionSeats.map { OfficeScene.hitID(seat: $0) })
                meta.allowRects = office.blinkRects + office.walkers.motionRects       // 走路的人、门本来就在动
            }
            if lastSize != (0, 0) && lastSize != (canvas.width, canvas.height) {
                for f in scan.analyze() { var g = f; g.frame += frameOffset; res.findings.append(g) }
                res.tolerated += scan.tolerated
                if dump { for sp in scan.spots { if let img = scan.strip(frame: sp.frame, bbox: sp.bbox) { res.strips.append((sp.frame + frameOffset, sp.count, sp.tolerated, img)) } } }
                frameOffset = i
                let fresh = FlickerScan(fps: fps); fresh.tolerance = scan.tolerance; scan = fresh
            }
            lastSize = (canvas.width, canvas.height)
            scan.add(canvas, meta: meta)
            t += 1.0 / fps; i += 1
        }
        for x in scan.analyze() { var g = x; g.frame += frameOffset; res.findings.append(g) }
        res.tolerated += scan.tolerated
        if dump { for sp in scan.spots { if let img = scan.strip(frame: sp.frame, bbox: sp.bbox) { res.strips.append((sp.frame + frameOffset, sp.count, sp.tolerated, img)) } } }
        res.frames = i
        return res
    }

    /// 某个场景在演示剧本第 t 秒的画布哈希（从 t-6 秒开始按 30 fps 推进，让弹簧 / 停留状态和真实运行一致）。
    public static func frameHash(scene: String, at t: Double, clock: String, mode: String = "demo") -> UInt64 {
        frame(scene: scene, at: t, clock: clock, mode: mode)?.canvas.contentHash() ?? 0
    }

    /// 同一条路径算出来的整帧（画布 + 文字层），金图 `--dump` 用它出图，方便亲眼看过再 `--update`。
    public static func frame(scene: String, at t: Double, clock: String, mode: String = "demo") -> Frame? {
        let base = fixedBase(clock: clock)
        let director = VisualDirector()
        let office = OfficeScene(); office.director = director
        let tank = TankScene(), strip = StripScene()
        var opts = SceneOptions(); opts.zoom = 3; opts.tally = 7; opts.directorIsExternal = true
        let vp = officeViewport(zoom: 3)
        var last: Frame? = nil
        var tt = max(0, t - 6)
        while tt <= t + 1e-9 {
            let s = DemoScript.snapshots(mode: mode, t: tt, base: base)
            let nt = base.addingTimeInterval(tt)
            director.update(snapshots: s.present, now: nt, time: tt, privacy: false)
            switch scene {
            case "tank": last = tank.render(director: director, present: s.present, now: nt, time: tt, privacy: false)
            case "strip": last = strip.render(director: director, present: s.present, now: nt, time: tt, privacy: false)
            default: last = office.render(viewportW: vp.w, viewportH: vp.h, present: s.present, dormant: s.dormant, now: nt, time: tt, options: opts)
            }
            tt += 1.0 / 30
        }
        return last
    }

    /// 金图：演示剧本里几个关键时刻（走进来、思考、等批准、提问、计划待审、做完……）× 三个场景 × 白天 / 夜里的画布哈希。
    /// 哈希只由像素决定（不含文字层，和字体无关），同一份代码永远得到同一个值。改了画法之后要重新生成：buddyctl golden --update。
    public static let goldenPlan: [(scene: String, clock: String, t: Double)] = [
        ("office", "12:00", 5), ("office", "12:00", 20), ("office", "12:00", 41), ("office", "12:00", 52), ("office", "12:00", 59), ("office", "12:00", 66),
        ("office", "22:30", 20), ("office", "22:30", 41), ("office", "06:50", 30), ("office", "18:55", 45),
        ("tank", "12:00", 20), ("tank", "12:00", 41), ("tank", "12:00", 59), ("tank", "22:30", 41),
        ("strip", "12:00", 20), ("strip", "12:00", 41), ("strip", "12:00", 59),
    ]
    public static func goldenName(_ p: (scene: String, clock: String, t: Double)) -> String { "\(p.scene)@\(p.clock)/t=\(Int(p.t))" }
    public static func goldenHashes() -> [(name: String, hash: UInt64)] {
        goldenPlan.map { (goldenName($0), frameHash(scene: $0.scene, at: $0.t, clock: $0.clock)) }
    }

    // MARK: 局部重绘 vs 整张重画

    public struct RetainedComparison {
        public var frames = 0
        /// 局部重绘判定「没变」而直接跳过的帧数。
        public var skipped = 0
        public struct Bad { public var frame: Int; public var time: Double; public var count: Int; public var bbox: IntRect; public var retained: Frame; public var full: Frame; public var note: String }
        public var firstBad: Bad? = nil
    }

    static func samePixels(_ a: Canvas, _ b: Canvas) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        let n = a.count
        return memcmp(a.rgba, b.rgba, n * 4) == 0 && memcmp(a.idx, b.idx, n * 2) == 0 && memcmp(a.ids, b.ids, n * 2) == 0
    }

    /// 同样的输入喂给两份场景：一份局部重绘（retained），一份每帧整张重画；逐帧逐像素（rgba / 调色板索引 / 对象 ID 三个平面）比较。
    /// 第一个不一致的帧就停下来（返回的两个 Frame 还保持着那一帧的样子，可以拿去出图）。
    public static func compareRetained(scene: String, clock: String, mode: String, seconds: Double,
                                       viewport: (w: Int, h: Int), hover: Bool = false) -> RetainedComparison {
        let base = fixedBase(clock: clock)
        let dA = VisualDirector(), dB = VisualDirector()
        let sA = OfficeScene(), sB = OfficeScene()
        sA.director = dA; sB.director = dB
        let tA = TankScene(), tB = TankScene(); tB.retained = false
        let pA = StripScene(), pB = StripScene(); pB.retained = false
        var oA = SceneOptions(); oA.zoom = 3; oA.tally = 7; oA.directorIsExternal = true; oA.retained = true
        var oB = oA; oB.retained = false
        var res = RetainedComparison()
        var t = 0.0
        while t <= seconds {
            let s = DemoScript.snapshots(mode: mode, t: t, base: base)
            let nt = base.addingTimeInterval(t)
            dA.update(snapshots: s.present, now: nt, time: t, privacy: false)
            dB.update(snapshots: s.present, now: nt, time: t, privacy: false)
            // 悬停：每 10 秒里有 2 秒在第一个人身上悬停（卡片出现 / 消失都会走整张重画的分支）
            if hover, let f = s.present.first, Int(t) % 10 >= 4 && Int(t) % 10 < 6 { oA.hoverSnapshot = f; oB.hoverSnapshot = f; oA.hoverSeat = f.seat; oB.hoverSeat = f.seat }
            else { oA.hoverSnapshot = nil; oB.hoverSnapshot = nil; oA.hoverSeat = nil; oB.hoverSeat = nil }
            let fa: Frame, fb: Frame
            switch scene {
            case "tank":
                fa = tA.render(director: dA, present: s.present, now: nt, time: t, privacy: false)
                fb = tB.render(director: dB, present: s.present, now: nt, time: t, privacy: false)
            case "strip":
                fa = pA.render(director: dA, present: s.present, now: nt, time: t, privacy: false)
                fb = pB.render(director: dB, present: s.present, now: nt, time: t, privacy: false)
            default:
                fa = sA.render(viewportW: viewport.w, viewportH: viewport.h, present: s.present, dormant: s.dormant, now: nt, time: t, options: oA)
                fb = sB.render(viewportW: viewport.w, viewportH: viewport.h, present: s.present, dormant: s.dormant, now: nt, time: t, options: oB)
            }
            if !fa.canvasChanged { res.skipped += 1 }
            if !samePixels(fa.canvas, fb.canvas) {
                var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, cnt = 0
                let ca = fa.canvas, cb = fb.canvas
                if ca.width == cb.width && ca.height == cb.height {
                    for y in 0..<ca.height { for x in 0..<ca.width {
                        let i = y * ca.width + x
                        if ca.rgba[i] != cb.rgba[i] || ca.idx[i] != cb.idx[i] || ca.ids[i] != cb.ids[i] {
                            cnt += 1; minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                        }
                    } }
                }
                res.firstBad = .init(frame: res.frames, time: t, count: cnt, bbox: cnt > 0 ? IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1) : IntRect(0, 0, 0, 0),
                                     retained: fa, full: fb, note: "canvasChanged=\(fa.canvasChanged)")
                res.frames += 1
                return res
            }
            res.frames += 1
            t += 1.0 / 30
        }
        return res
    }
}
