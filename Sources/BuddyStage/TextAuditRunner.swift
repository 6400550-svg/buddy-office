import Foundation
import CoreGraphics
import BuddyCore
import PixelKit
import BuddyArt

/// text-audit 的压力组合：办公室 / 小鱼缸 / 宠物条 × 所有缩放 × 会话数 0/1/4/8/12/20 × 标题（长中文 / 长英文 / emoji / 空）×
/// 所有状态同时出现 × 白天夜晚 × 隐私模式 × 最小 / 很窄 / 矮宽的窗口 × 悬停卡片在四个边缘 × 提示卡。
public enum TextAuditRunner {
    public struct Window: Sendable {
        public var name: String; public var wPt: Int; public var hPt: Int
        public init(name: String, wPt: Int, hPt: Int) { self.name = name; self.wPt = wPt; self.hPt = hPt }
        public static let standard = Window(name: "默认", wPt: 672, hPt: 678)
        /// 办公室窗口的最小内容尺寸（OfficeWindowController.contentMinSize）。
        public static let smallest = Window(name: "最小", wPt: 200, hPt: 220)
        public static let narrow = Window(name: "很窄", wPt: 260, hPt: 700)
        public static let short = Window(name: "矮宽", wPt: 900, hPt: 260)
    }

    public struct Config: Sendable {
        public var scenes: Set<String> = ["office", "hover", "tank", "strip", "cards", "toast"]
        public var counts = [0, 1, 4, 8, 12, 20]
        /// 「所有状态同时出现」需要的座位数（每种状态一个座位）：办公室 / 悬停只对 .all 状态模式额外跑这个人数。
        public var allStatesCount = AuditFixtures.allStatesCount
        public var titles: [AuditFixtures.TitleMode] = [.normal, .longZh, .longEn, .emoji, .empty, .mixed]
        public var states: [AuditFixtures.StateMode] = [.demo, .all]
        public var clocks = ["12:00", "23:00"]
        public var privacy = [false, true]
        public var officeZooms = [1, 2, 3, 4, 5]
        public var tankZooms = [1, 2]
        public var stripZooms = [1, 2, 3]
        public var cardZooms = [1, 2, 3, 4, 5]
        public var windows: [Window] = [.standard, .smallest, .narrow, .short]
        public var scale = 2
        /// 违规的画面存成 PNG（画红框）的目录；nil = 不存。
        public var imageDir: String? = nil
        public var maxImages = 40
        /// 只处理「场景 + 组合描述」里包含这段文字的组合（调试用）；saveAll = 不管有没有违规都把符合的画面存下来。
        public var filter: String? = nil
        public var saveAll = false
        public init() {}
        /// 测试里用的缩减版（几十秒变成几秒）。
        public static var quick: Config {
            var c = Config()
            c.counts = [0, 1, 4, 12]
            c.titles = [.longZh, .emoji, .mixed]
            c.clocks = ["12:00", "23:00"]
            c.privacy = [false, true]
            c.officeZooms = [2, 3, 5]
            c.windows = [.standard, .smallest]
            c.cardZooms = [2, 3]
            return c
        }
    }

    public struct Report: Sendable {
        public var combos = 0
        public var frames = 0
        public var violations: [TextAudit.Violation] = []
        public var texts = 0                          // 检查过的文字段数
        public var pixelStrings = 0                   // 检查过的像素字串数
        public var seconds = 0.0
        public var savedImages: [String] = []
        public var perScene: [String: (combos: Int, violations: Int)] = [:]
        /// 悬停卡片没画出来的组合数（按窗口名分组）：应该始终是 0——窗口小到候选位置都放不下时会走兜底的网格搜索，压在身体 / 椅子上也要画出来。
        public var hoverWithoutCard: [String: Int] = [:]
        public var hoverTotal = 0
        public var hoverMissingExamples: [String] = []
        public var hoverCardsMissing: Int { hoverWithoutCard.values.reduce(0, +) }
        public func count(_ k: TextAudit.Kind) -> Int { violations.filter { $0.kind == k }.count }
    }

    /// 全局锁：像素字审计钩子是全局的，同一时刻只允许一个 runner 在渲染（并行跑的测试会互相干扰）。
    static let renderLock = NSLock()

    final class Box<T>: @unchecked Sendable {
        var value: T
        let lock = NSLock()
        init(_ v: T) { value = v }
        func with(_ f: (inout T) -> Void) { lock.lock(); f(&value); lock.unlock() }
        /// 在锁里取一份拷贝：`setAuditSink(nil)` 之后，别的线程里已经取到 sink 的那次 draw 还可能在往里 append。
        func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: 入口

    public static func run(_ cfg: Config, log: ((String) -> Void)? = nil) -> Report {
        let t0 = Date()
        var rep = Report()
        var savedImages = 0
        let record: Recorder = { scene, combo, frame, zoom, regions, draws in
            if let f = cfg.filter, !("\(scene) \(combo)".contains(f)) { return }
            rep.combos += 1; rep.frames += 1
            rep.texts += frame.texts.count
            let own = ObjectIdentifier(frame.canvas)
            rep.pixelStrings += draws.filter { $0.canvasID == own }.count
            let input = TextAudit.Input(frame: frame, zoom: zoom, scale: cfg.scale, regions: regions, pixelDraws: draws, scene: scene, combo: combo)
            let v = TextAudit.check(input)
            var s = rep.perScene[scene] ?? (combos: 0, violations: 0)
            s.combos += 1; s.violations += v.count
            rep.perScene[scene] = s
            rep.violations += v
            if (!v.isEmpty || cfg.saveAll), let dir = cfg.imageDir, savedImages < cfg.maxImages {
                if let path = saveImage(dir: dir, name: "\(scene)-\(rep.frames)", frame: frame, zoom: zoom, scale: cfg.scale, violations: v) { rep.savedImages.append(path); savedImages += 1 }
            }
        }

        hoverStats = { win, combo, drawn in rep.hoverTotal += 1; if !drawn { rep.hoverWithoutCard[win, default: 0] += 1; if rep.hoverMissingExamples.count < 600 { rep.hoverMissingExamples.append(combo) } } }
        defer { hoverStats = nil }
        if cfg.scenes.contains("office") { officeMatrix(cfg, record: record, log: log) }
        if cfg.scenes.contains("hover") { hoverMatrix(cfg, record: record, log: log) }
        if cfg.scenes.contains("tank") { tankMatrix(cfg, record: record, log: log) }
        if cfg.scenes.contains("strip") { stripMatrix(cfg, record: record, log: log) }
        if cfg.scenes.contains("cards") { cardMatrix(cfg, record: record, log: log) }
        if cfg.scenes.contains("toast") { toastMatrix(cfg, record: record, log: log) }
        rep.seconds = Date().timeIntervalSince(t0)
        return rep
    }

    typealias Recorder = (String, String, Frame, Int, [AuditRegion], [PixelFont.DrawRecord]) -> Void
    /// 悬停组合里有没有画出卡片，登记到 report（runner 里的 hoverStats 闭包）。
    nonisolated(unsafe) static var hoverStats: ((String, String, Bool) -> Void)? = nil

    // MARK: 渲染一帧（带像素字收集）

    static func withDraws<T>(_ body: () -> T) -> (T, [PixelFont.DrawRecord]) {
        renderLock.lock(); defer { renderLock.unlock() }
        let box = Box<[PixelFont.DrawRecord]>([])
        PixelFont.setAuditSink { r in box.with { $0.append(r) } }
        let v = body()
        PixelFont.setAuditSink(nil)
        return (v, box.get())              // 不能直接读 box.value：那样和别的线程里晚到的 append 是数据竞争（ASan 抓到过 heap-use-after-free，SAN-01）
    }

    static func settle(_ director: VisualDirector, _ snaps: [BuddySnapshot], base: Date, seconds: Double = 6) {
        var t = 0.0
        while t <= seconds { director.update(snapshots: snaps, now: base.addingTimeInterval(t), time: t, privacy: false); t += 0.25 }
    }

    // MARK: 单个办公室场景（矩阵和测试共用同一条渲染路径）

    /// 渲染出来的一帧，带上审计要用的全部材料。
    public struct Rendered {
        public var frame: Frame
        public var regions: [AuditRegion]
        public var draws: [PixelFont.DrawRecord]
        public var zoom: Int
        /// 用 8 类检查审计这一帧。
        public func audit(scene: String = "办公室", combo: String = "", scale: Int = 2, configure: ((inout TextAudit.Input) -> Void)? = nil) -> [TextAudit.Violation] {
            var input = TextAudit.Input(frame: frame, zoom: zoom, scale: scale, regions: regions, pixelDraws: draws, scene: scene, combo: combo)
            configure?(&input)
            return TextAudit.check(input)
        }
    }

    /// 一个办公室场景的审计会话：固定的会话 / 导演 / 镜头，可以反复渲染（悬停不同的座位）。
    public final class OfficeSession {
        public let snapshots: [BuddySnapshot]
        /// 实际生效的缩放（窗口太小时比请求的小）。
        public let zoom: Int
        public let window: Window
        public let scene = OfficeScene()
        public let base: Date
        let director = VisualDirector()
        var options = SceneOptions()
        public private(set) var t = 6.0
        public private(set) var viewport = IntRect(0, 0, 0, 0)
        var vw: Int { max(40, window.wPt / zoom) }
        var vh: Int { max(40, window.hPt / zoom) }

        public init(count: Int, titles: AuditFixtures.TitleMode = .normal, states: AuditFixtures.StateMode = .demo, requestedZoom: Int,
                    window: Window = .standard, clock: String = "12:00", privacy: Bool = false, snapshots custom: [BuddySnapshot]? = nil) {
            self.window = window
            base = StageRun.fixedBase(clock: clock)
            snapshots = custom ?? AuditFixtures.snapshots(count: count, titles: titles, states: states, base: base)
            let maxSeat = (custom.map { $0.map(\.seat).max() ?? -1 } ?? count - 1)
            zoom = OfficeLayout.effectiveZoom(setting: requestedZoom, contentW: Double(window.wPt), contentH: Double(window.hPt), maxSeat: maxSeat, allowOne: true)
            TextAuditRunner.settle(director, snapshots, base: base)
            scene.director = director
            options.zoom = zoom; options.privacy = privacy; options.directorIsExternal = true; options.animateWalkers = false
            options.retained = false; options.audit = true; options.tally = 7
        }

        func renderFrame(hover seat: Int?) -> Frame {
            var o = options
            if let s = seat { o.hoverSeat = s; o.hoverSnapshot = snapshots.first { $0.seat == s } }
            let f = scene.render(viewportW: vw, viewportH: vh, present: snapshots, dormant: [], now: base.addingTimeInterval(t), time: t, options: o)
            viewport = f.viewport
            return f
        }

        /// 让镜头稳定下来（弹簧一秒多）：悬停之前先做，否则镜头还在滚，「窗口里看得见哪些座位」不准。
        public func settleCamera() {
            _ = renderFrame(hover: nil)
            for _ in 0..<12 { t += 0.25; _ = renderFrame(hover: nil) }
        }

        /// 鼠标能悬停到的座位：窗口里至少露出 minVisible（默认 40%）的（占用中的）座位。窗口比一个工位还矮 / 窄时，工位只露出一部分，也照样能悬停。
        public func hoverableSeats(minVisible: Double = 0.4) -> [SeatView] {
            let vp = viewport
            return scene.lastSeatViews.filter { v in
                guard v.mode == .occupied else { return false }
                let cell = IntRect(v.origin.x, v.origin.y, Metrics.cellW, Metrics.cellH + Metrics.plateH)
                guard let inter = cell.intersection(vp) else { return false }
                return Double(inter.w * inter.h) >= minVisible * Double(cell.w * cell.h)
            }
        }

        /// 离窗口四个角最近的（悬停得到的）座位。
        public var cornerSeats: [Int] {
            let vp = viewport, visible = hoverableSeats()
            func nearest(_ cx: Int, _ cy: Int) -> Int? {
                visible.min { hypot(Double($0.origin.x - cx), Double($0.origin.y - cy)) < hypot(Double($1.origin.x - cx), Double($1.origin.y - cy)) }?.seat
            }
            return Array(Set([nearest(vp.x, vp.y), nearest(vp.maxX, vp.y), nearest(vp.x, vp.maxY), nearest(vp.maxX, vp.maxY)].compactMap { $0 })).sorted()
        }

        /// 渲染一帧（带像素字收集）。advance = 先把时间推进 0.25 秒（连续悬停几个座位时用）。
        public func render(hover seat: Int? = nil, advance: Bool = false) -> Rendered {
            if advance { t += 0.25 }
            let (frame, draws) = TextAuditRunner.withDraws { renderFrame(hover: seat) }
            return Rendered(frame: frame, regions: scene.auditRegions, draws: draws, zoom: zoom)
        }
    }

    // MARK: 办公室

    static func officeMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        for clock in cfg.clocks { for priv in cfg.privacy {
            for win in cfg.windows {
                var seenZoom = Set<String>()
                for reqZoom in cfg.officeZooms {
                    for count in cfg.counts + [cfg.allStatesCount] {
                        let z = OfficeLayout.effectiveZoom(setting: reqZoom, contentW: Double(win.wPt), contentH: Double(win.hPt), maxSeat: count - 1, allowOne: true)
                        if !seenZoom.insert("\(z)/\(count)").inserted { continue }
                        var variants: [(AuditFixtures.TitleMode, AuditFixtures.StateMode)] = count == 0 ? [(.normal, .demo)]
                            : cfg.titles.flatMap { t in cfg.states.map { (t, $0) } }
                        if count == cfg.allStatesCount { variants = variants.filter { $0.1 == .all } }               // 每种状态一个座位：只有「所有状态」模式有意义
                        for (tm, sm) in variants {
                            let session = OfficeSession(count: count, titles: tm, states: sm, requestedZoom: reqZoom, window: win, clock: clock, privacy: priv)
                            let r = session.render()
                            record("办公室", "\(win.name)窗口 缩放\(z)× \(count)人 标题:\(tm.rawValue) 状态:\(sm.rawValue) \(clock)\(priv ? " 隐私" : "")", r.frame, z, r.regions, r.draws)
                        }
                    }
                }
            }
            log?("办公室 \(clock)\(priv ? " 隐私" : "") 完成")
        } }
    }

    /// 悬停卡片出现在窗口的四个边缘：先把镜头稳定下来，在「至少露出 40%」的座位里挑离窗口四个角最近的四个来悬停（鼠标只能悬停在看得见的人身上）。
    static func hoverMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        for clock in cfg.clocks {
            for win in cfg.windows {
                var seen = Set<String>()
                for reqZoom in cfg.officeZooms { for count in cfg.counts + [cfg.allStatesCount] where count >= 4 {
                    let z = OfficeLayout.effectiveZoom(setting: reqZoom, contentW: Double(win.wPt), contentH: Double(win.hPt), maxSeat: count - 1, allowOne: true)
                    if !seen.insert("\(z)/\(count)").inserted { continue }
                    for tm in [AuditFixtures.TitleMode.mixed, .longZh] { for sm in cfg.states where count != cfg.allStatesCount || sm == .all {
                        let session = OfficeSession(count: count, titles: tm, states: sm, requestedZoom: reqZoom, window: win, clock: clock)
                        session.settleCamera()
                        for seat in session.cornerSeats {
                            let r = session.render(hover: seat, advance: true)
                            let comboName = "\(win.name)窗口 缩放\(z)× \(count)人 座位\(seat) 标题:\(tm.rawValue) 状态:\(sm.rawValue) \(clock)"
                            hoverStats?(win.name, comboName, r.regions.contains { $0.kind == .card })
                            record("悬停卡片", comboName, r.frame, z, r.regions, r.draws)
                        }
                    } }
                } }
            }
        }
        log?("悬停卡片（四个边缘）完成")
    }

    // MARK: 小鱼缸 / 宠物条

    static func tankMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        for clock in cfg.clocks {
            let base = StageRun.fixedBase(clock: clock)
            for z in cfg.tankZooms { for count in cfg.counts {
                let variants: [(AuditFixtures.TitleMode, AuditFixtures.StateMode)] = count == 0 ? [(.normal, .demo)] : [(.mixed, .all), (.longZh, .demo)]
                for (tm, sm) in variants {
                    // 小鱼缸只画前 8 个人：「所有状态」模式把状态依次错开，40 种状态每一种都要出现在某一帧里
                    for offset in (sm == .all ? stride(from: 0, to: AuditFixtures.allStatesCount, by: 8).map { $0 } : [0]) {
                        let snaps = AuditFixtures.snapshots(count: count, titles: tm, states: sm, base: base, stateOffset: offset)
                        let director = VisualDirector(); settle(director, snaps, base: base)
                        let scene = TankScene()
                        let (frame, draws) = withDraws { scene.render(director: director, present: snaps, now: base.addingTimeInterval(6), time: 6, privacy: false, zoom: z) }
                        record("小鱼缸", "缩放\(z)× \(count)人 标题:\(tm.rawValue) 状态:\(sm.rawValue)+\(offset) \(clock)", frame, z, [], draws)
                    }
                }
            } }
        }
        log?("小鱼缸 完成")
    }

    static func stripMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        let base = StageRun.fixedBase(clock: "12:00")
        for z in cfg.stripZooms { for count in cfg.counts {
            for (tm, sm) in [(AuditFixtures.TitleMode.mixed, AuditFixtures.StateMode.all), (.normal, .demo)] {
                for offset in (sm == .all ? stride(from: 0, to: AuditFixtures.allStatesCount, by: 8).map { $0 } : [0]) {
                    let snaps = AuditFixtures.snapshots(count: count, titles: tm, states: sm, base: base, stateOffset: offset)
                    let director = VisualDirector(); settle(director, snaps, base: base)
                    let scene = StripScene()
                    let (frame, draws) = withDraws { scene.render(director: director, present: snaps, now: base.addingTimeInterval(6), time: 6, privacy: false) }
                    record("桌面宠物", "缩放\(z)× \(count)人 标题:\(tm.rawValue) 状态:\(sm.rawValue)+\(offset)", frame, z, [], draws)
                }
            }
        } }
        log?("桌面宠物 完成")
    }

    // MARK: 悬停卡片本身（小鱼缸 / 宠物条用单独的 HoverPanel 显示同一张卡）

    static func cardMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        let base = StageRun.fixedBase(clock: "12:00")
        for priv in cfg.privacy { for tm in cfg.titles { for z in cfg.cardZooms {
            let snaps = AuditFixtures.snapshots(count: AuditFixtures.states.count, titles: tm, states: .all, base: base)
            for s in snaps {
                let card = HoverCard.make(s, now: base.addingTimeInterval(6), zoom: z, privacy: priv)
                let frame = Frame(canvas: card.canvas, texts: card.texts)
                record("悬停卡片(单独)", "缩放\(z)× 标题:\(tm.rawValue) 状态:\(AuditFixtures.stateNames[s.seat % AuditFixtures.stateNames.count])\(priv ? " 隐私" : "")", frame, z, [], [])
            }
        } } }
        log?("悬停卡片(单独) 完成")
    }

    static func toastMatrix(_ cfg: Config, record: Recorder, log: ((String) -> Void)?) {
        let kinds: [ToastCard.Kind] = [.approval, .question, .plan, .finished, .blocked, .error, .info]
        let titles = [AuditFixtures.title(.normal, index: 0), AuditFixtures.longZh, AuditFixtures.longEn, AuditFixtures.emoji, "", "Buddy 办公室"]
        let bodies = ["想用 Bash：git push origin main（等你批准）", "有个问题要问你", "做完了（用时 3分12秒）", "3 位同事在等你", AuditFixtures.longZh + AuditFixtures.longZh, ""]
        for k in kinds { for t in titles { for b in bodies { for z in [1, 2, 3] {
            let card = ToastCard.make(kind: k, title: t, body: b, zoom: z)
            record("提示卡", "缩放\(z)× \(k) 标题:\(t.prefix(6)) 内容:\(b.prefix(6))", Frame(canvas: card.canvas, texts: card.texts), z, [], [])
        } } } }
        log?("提示卡 完成")
    }

    // MARK: 存图（画红框）

    static func saveImage(dir: String, name: String, frame: Frame, zoom: Int, scale: Int, violations: [TextAudit.Violation]) -> String? {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let base = FrameRenderer.render(frame, zoom: zoom, scale: scale),
              let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 1)); ctx.setLineWidth(2)
        for v in violations {
            guard var r = v.rect else { continue }
            r = r.insetBy(dx: -2, dy: -2)
            ctx.stroke(CGRect(x: r.minX, y: CGFloat(base.height) - r.maxY, width: r.width, height: r.height))
        }
        guard var img = ctx.makeImage() else { return nil }
        // 画面很大（一个很高的窗口把整个办公室看全）时，只留第一处违规位置周围的一块（四周多留 160 设备像素的上下文），不然图太大没法看
        let boxes = violations.compactMap { $0.rect }
        if img.height > 1800 || img.width > 1800, let first = boxes.first {
            let u = first.insetBy(dx: -160, dy: -160)
            let crop = CGRect(x: 0, y: 0, width: img.width, height: img.height).intersection(u)
            if !crop.isNull, let c = img.cropping(to: CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: crop.height)) { img = c }
        }
        let path = "\(dir)/\(name).png"
        do { try PNGExport.write(img, to: URL(fileURLWithPath: path)) } catch { return nil }
        return path
    }
}
