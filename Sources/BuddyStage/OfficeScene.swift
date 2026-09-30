import Foundation
import BuddyCore
import PixelKit
import BuddyArt

public enum LabelMode { case always, hover, off }

public struct SceneOptions {
    public var privacy = false
    public var labels = LabelMode.always
    public var zoom = 3                // 只影响文字排版（几行、用不用省略号）
    public var tally = 0
    public var hoverSeat: Int? = nil
    /// 悬停 250 ms 之后要显示卡片的那个人（卡片直接画进场景）。
    public var hoverSnapshot: BuddySnapshot? = nil
    /// director 由外部（AppModel）统一 update，场景只负责画。
    public var directorIsExternal = false
    /// 进场 / 离场走路动画（快照 / 演示里可以关掉）。
    public var animateWalkers = true
    /// 局部重绘：只重画「指纹变了」的工位和动态元素（false = 每帧整张重画，用来和局部重绘逐像素对比）。
    public var retained = true
    /// 一个会话都没有时要不要显示「今天还没人上班」牌子。App 启动后、第一批数据到来之前传 false（不然每次启动都会先闪一下这块牌子）。
    public var emptySign = true
    /// text-audit 用：渲染完之后把脸 / 屏幕 / 气泡 / 悬停卡片的矩形记进 OfficeScene.auditRegions。平时关着（零开销）。
    public var audit = false
    public init() {}
}

/// text-audit 用的「文字不许盖住」的区域（世界坐标，美术像素）。
public struct AuditRegion: Sendable {
    public enum Kind: String, Sendable { case face, screen, bubble, card }
    public var kind: Kind
    public var rect: IntRect
    public var seat: Int
}

/// 办公室场景：把房间 + 全部工位 + 人组合成一帧（Canvas + 文字层）。
public final class OfficeScene {
    public var director = VisualDirector()
    var room: RoomRenderer
    var bg: Canvas
    var bgBuilt = false
    var work: Canvas
    var lastCols: Int? = nil
    public private(set) var layout: OfficeLayout
    public private(set) var lastSeatViews: [SeatView] = []
    public let walkers = WalkerSystem()
    /// 闪烁扫描用：这一帧哪些工位在过渡 / 眨眼（世界坐标的头盒子矩形）。
    public private(set) var transitionSeats: Set<Int> = []
    public private(set) var blinkRects: [IntRect] = []
    var prevKeys: Set<String>? = nil
    var seatedAt: [String: Double] = [:]
    /// 显示器关机：每个座位上一次有人时屏幕的内容（人一走就拿它来做 300 ms 的熄灭渐变），和正在熄灭的座位（开始时刻 + 内容）。
    static let screenFadeSeconds = 0.3
    /// 启动时已在的会话：显示器依次开机的间隔（100 ms）和总延迟上限（1.5 s，人很多时后面的不用等太久）。
    static let launchStaggerStep = 0.1, launchStaggerMax = 1.5
    var screenMemory: [Int: (kind: ScreenKind, seed: Int, t: Double)] = [:]
    var screenFade: [Int: (start: Double, kind: ScreenKind, seed: Int, t: Double)] = [:]
    var lastApp: [String: (Appearance, Int)] = [:]
    // 局部重绘的状态：上一次合成时每个工位 / 动态元素 / 外套的指纹
    var seatSigs: [Int: SeatSigs] = [:]
    var seatCaches: [Int: SeatCache] = [:]
    func cache(for seat: Int) -> SeatCache {
        if let c = seatCaches[seat] { return c }
        let c = SeatCache(); seatCaches[seat] = c; return c
    }
    var dynSig: UInt64 = 0
    var coatSig: UInt64 = 0
    var retainedReady = false
    var prevSteady = false
    /// 这一帧有没有重画过画布（false = 和上一帧逐像素相同，窗口可以跳过哈希和出图）。
    public private(set) var lastCanvasChanged = true
    public var cameraY = 0.0
    var camSpring = PixelSpring(period: 0.5)
    var lastCamTime = -1.0

    public init() {
        layout = OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 5)
        room = RoomRenderer(layout: layout)
        bg = Canvas(width: 8, height: 8); work = Canvas(width: 8, height: 8)
    }

    var bgLight = LightState(a: .day)
    /// options.audit 打开时，最近一帧里不许被文字盖住的区域。
    public internal(set) var auditRegions: [AuditRegion] = []
    /// 「今天还没人上班」牌子：一个会话都没有（也没有下班工位）时才有，画在背景里（牌子按文字宽度和缩放定大小、按视口中心摆），状态变了才重新烘焙。
    /// 样子和下班工位的桌牌一样（深色胡桃木 + 浅色字），只是大一号——「没人上班」和「下班了」是同一种意思。
    var bakedSign = -1
    var bakedSignVH = 0
    var signRect = IntRect(0, 0, 0, 0)
    static let signText = "今天还没人上班"
    static let signMeasureStyle = TextStyle(size: 11, color: RGBA8(0, 0, 0, 255), weight: .semibold)
    static let signInk = RGBA8(hex: 0xF8EFDD)
    /// 牌子的位置：摆在最后一张桌子后面那个空格子的地毯上（那里本来就是给下一个同事留的空位）；桌子正好排满一整排、没有空格子时，摆在视口正中。
    static func signGeometry(zoom: Int, layout lay: OfficeLayout, viewportH: Int) -> IntRect {
        let z = Double(max(1, zoom))
        let m = TextRenderer.shared.measure(signText, style: signMeasureStyle)
        let w = Int(ceil(Double(m.width) / z)) + 16, h = max(11, Int(ceil(Double(m.height) / z)) + 8)
        if lay.deskCount < lay.cols * lay.rows {
            let o = lay.cellOrigin(seat: lay.deskCount)
            return IntRect(o.x + Metrics.cellW / 2 - w / 2, o.y + 30 - h / 2, w, h)
        }
        return IntRect((lay.worldW - w) / 2, min(viewportH, lay.worldH) / 2 - h / 2, w, h)
    }
    static func drawSign(_ r: IntRect, on c: Canvas, light: LightState) {
        let st = Lighting.resolved(appearance: nil, state: light)
        c.plate(r, border: Pal.dx("woodWalnut.out"), fill: Pal.dx("woodWalnut.base"), light: Pal.dx("woodWalnut.hi"), shade: Pal.dx("woodWalnut.sh"), style: st)
    }

    var emptyApps: [Int: Appearance] = [:]
    func emptyAppearance(_ seat: Int) -> Appearance {
        if let a = emptyApps[seat] { return a }
        let a = Appearance.generate(seed: UInt64(seat) &* 0x9E3779B97F4A7C15 &+ 12345)
        emptyApps[seat] = a
        return a
    }

    /// 办公室的对象 ID 是 1000…1999（2000 起是小鱼缸、3000 起是宠物条）：座位号夹在 0…999，永远不会溢出 UInt16、也不会撞进别的范围。
    public static func hitID(seat: Int) -> UInt16 { UInt16(1000 + max(0, min(seat, 999))) }
    public static func seat(fromHitID id: UInt16) -> Int? { (id >= 1000 && id < 2000) ? Int(id) - 1000 : nil }

    /// - Parameters:
    ///   - present: 在场的 buddy 快照；away: 已离场（下班工位 / 空位）
    static func merged(_ rects: [IntRect]) -> [IntRect] {
        var out: [IntRect] = []
        for r in rects {
            var cur = r
            var i = 0
            while i < out.count {
                // 相交或相邻就合并（相邻合并是为了少做几遍）
                let o = out[i]
                if cur.x <= o.maxX && o.x <= cur.maxX && cur.y <= o.maxY && o.y <= cur.maxY { cur = cur.union(o); out.remove(at: i); i = 0 } else { i += 1 }
            }
            out.append(cur)
        }
        return out
    }

    /// - Parameters:
    ///   - present: 在场的 buddy 快照；away: 已离场（下班工位 / 空位）
    public func render(viewportW: Int, viewportH: Int, present: [BuddySnapshot], dormant: [BuddySnapshot], now: Date, time: Double,
                       options: SceneOptions) -> Frame {
        var maxSeat = -1
        for s in present { maxSeat = max(maxSeat, s.seat) }
        for s in dormant { maxSeat = max(maxSeat, s.seat) }
        let lay = OfficeLayout.compute(viewportW: viewportW, viewportH: viewportH, maxSeat: maxSeat, prevCols: lastCols)
        lastCols = lay.cols
        let rd = SceneClock.at(now)
        let light = rd.light, hour = rd.hour, day = rd.day
        let signZoom = (options.emptySign && present.isEmpty && dormant.isEmpty) ? max(1, options.zoom) : 0
        var rebuilt = false
        if !bgBuilt || bgLight != light || lay != layout || bakedSign != signZoom || (signZoom > 0 && bakedSignVH != viewportH) {
            layout = lay
            room = RoomRenderer(layout: lay)
            walkers.doorInterior = room.doorInterior
            bg = Canvas(width: lay.worldW, height: lay.worldH)
            work = Canvas(width: lay.worldW, height: lay.worldH)
            room.bake(into: bg, light: light)
            if signZoom > 0 { signRect = Self.signGeometry(zoom: signZoom, layout: lay, viewportH: viewportH) }        // 牌子在 compose 里画在工位上面（不烘进背景：怕被桌椅盖住）
            bakedSign = signZoom; bakedSignVH = viewportH
            bgLight = light; bgBuilt = true
            rebuilt = true
            retainedReady = false
        }
        let dyn = RoomRenderer.DynamicState(hour: hour, time: time, day: day, tally: options.tally)

        if !options.directorIsExternal { director.update(snapshots: present, now: now, time: time, privacy: options.privacy) }

        // 进场 / 离场：和上一帧比较在场的人（人员没变的帧只更新外观 / 座位记录，不建集合）
        var sameCrowd = prevKeys != nil && prevKeys!.count == present.count
        if sameCrowd { for s in present where !prevKeys!.contains(s.key) { sameCrowd = false; break } }
        if !sameCrowd {
            let nowKeys = Set(present.map { $0.key })
            if let pk = prevKeys {
                let gone = pk.subtracting(nowKeys)
                if options.animateWalkers {
                    for s in present where !pk.contains(s.key) && s.appearedAfterLaunch {
                        walkers.startEntering(key: s.key, appearance: director.appearance(for: s), seat: s.seat, layout: lay, door: room.doorFeet, time: time)
                    }
                    for k in gone {
                        if let (ap, seat) = lastApp[k] { walkers.startLeaving(key: k, appearance: ap, seat: seat, layout: lay, door: room.doorFeet, time: time) }
                    }
                }
                // 离场的人：清掉他的「坐下时刻」和外观记录。seatedAt 不清的话，他再次走进来时座位上直接坐着人（用的还是上一次的旧时刻），
                // 门口又走进来一个「分身」；而且每个见过的会话在这两个字典里都留一条，没有上界。
                for k in gone { seatedAt.removeValue(forKey: k); lastApp.removeValue(forKey: k) }
            }
            prevKeys = nowKeys
        }
        for s in present {
            let ap = director.appearance(for: s)
            if let l = lastApp[s.key], l.0 == ap, l.1 == s.seat { continue }
            lastApp[s.key] = (ap, s.seat)
        }
        walkers.cleanup(time: time)
        for s in present { if seatedAt[s.key] == nil, let t = walkers.finishedEntering(s.key, time: time) { seatedAt[s.key] = t } }
        // 下班的人：外套挂在门口的衣帽架上（先算好外套的外观 / 指纹，画的时候再用）
        var coats: [(Appearance, IntPoint)] = []
        var ck = KeyHasher()
        for (i, s) in dormant.prefix(room.coatSlots.count).enumerated() {
            let ap = director.appearance(for: s)
            coats.append((ap, room.coatSlots[i]))
            ck.add(ap); ck.add(i)
        }
        ck.add(coats.count)
        var views: [SeatView] = []
        var texts: [TextItem] = []
        var sigs: [SeatSigs] = []
        // 座位号 → 快照下标（不建字典）
        var presentAt = [Int](repeating: -1, count: lay.deskCount), dormantAt = [Int](repeating: -1, count: lay.deskCount)
        for (i, s) in present.enumerated() where s.seat >= 0 && s.seat < lay.deskCount { presentAt[s.seat] = i }
        for (i, s) in dormant.enumerated() where s.seat >= 0 && s.seat < lay.deskCount { dormantAt[s.seat] = i }
        for seat in 0..<lay.deskCount {
            let o = lay.cellOrigin(seat: seat)
            let origin = IntPoint(o.x, o.y)
            var v: SeatView
            let sp: BuddySnapshot? = presentAt[seat] >= 0 ? present[presentAt[seat]] : nil
            let sd: BuddySnapshot? = dormantAt[seat] >= 0 ? dormant[dormantAt[seat]] : nil
            if let s = sp, walkers.isBusy(s.key), seatedAt[s.key] == nil {
                let ap = director.appearance(for: s)
                v = SeatView(seat: seat, origin: origin, mode: .empty, appearance: ap)
                v.chairOut = true
            } else if let s = sp, let p = director.performers[s.key] {
                let mirror = (o.x + Metrics.cellW / 2) >= lay.worldW / 2          // 朝过道一侧转：右半边的人向左转
                let pv = Prof.begin()
                v = p.seatView(origin: origin, time: time, now: now, light: light, hitID: Self.hitID(seat: seat), privacy: options.privacy, mirror: mirror)
                Prof.end("office.seatView", pv)
                // App 启动时就在的会话：直接坐好，显示器从左到右（按座位号）依次开机，每台间隔 100 ms（任务书 5.5）；启动之后才来的人是走进来坐下再开机，没有间隔
                var stagger = 0.0
                if !s.appearedAfterLaunch, seatedAt[s.key] == nil, time - p.appearedAt < Self.launchStaggerMax + 0.4 {
                    stagger = min(Self.launchStaggerMax, Double(present.filter { !$0.appearedAfterLaunch && $0.seat < s.seat }.count) * Self.launchStaggerStep)
                }
                v.boot = min(1, max(0, (time - (seatedAt[s.key] ?? p.appearedAt) - stagger) / 0.3))
                if let st = seatedAt[s.key], time - st < 0.5 { v.transition = true }
            } else if let s = sd {
                let ap = director.appearance(for: s)
                v = SeatView(seat: seat, origin: origin, mode: .dormant, appearance: ap)
                v.title = s.title; v.dim = true
            } else {
                let ap = emptyAppearance(seat)
                v = SeatView(seat: seat, origin: origin, mode: .empty, appearance: ap)
            }
            if v.mode != .occupied && walkers.chairOut(seat: seat, time: time) { v.chairOut = true }
            // 显示器关机（任务书 5.6：开机 / 关机都是 300 ms 渐变）：人一离开，工位不再是「有人」，屏幕上最后的内容用 Bayer 抖动倒放熄灭，
            // 而不是一帧硬切成黑屏。座位号是字典的键，字典最多有「座位数」这么多项，不会无限长。
            if v.mode == .occupied {
                screenMemory[seat] = v.screen == .off ? nil : (v.screen, v.screenSeed, v.screenT)
                screenFade[seat] = nil
            } else {
                if screenFade[seat] == nil, let m = screenMemory[seat] { screenFade[seat] = (time, m.kind, m.seed, m.t); screenMemory[seat] = nil }
                if let f = screenFade[seat] {
                    let p = (time - f.start) / Self.screenFadeSeconds
                    if p >= 1 { screenFade[seat] = nil } else { v.fade = (f.kind, f.t + max(0, time - f.start), f.seed, max(0, p)) }
                }
            }
            views.append(v)
            let pk = Prof.begin()
            sigs.append(SeatRenderer.signatures(v, light: light, gt: time))
            Prof.end("office.signature", pk)
            let pp = Prof.begin()
            if v.mode != .empty { texts += cachedPlateTexts(v, options: options, seat: seat) }
            Prof.end("office.plateTexts", pp)
        }
        lastSeatViews = views

        // 镜头：世界比视口高时，用弹簧按整像素滚动到「有人要你」或最后一行；否则 0
        var vp = IntRect(0, 0, min(viewportW, lay.worldW), min(viewportH, lay.worldH))
        if lay.worldH > viewportH {
            var want = camSpring.target
            if let s = present.first(where: { $0.activity.needsUser }) { want = Double(lay.cellOrigin(seat: s.seat).y - 20) }
            want = max(0, min(Double(lay.worldH - viewportH), want))
            camSpring.target = want
            camSpring.step(lastCamTime < 0 ? 1.0 / 30 : max(0, min(0.25, time - lastCamTime)))
            vp.y = max(0, min(lay.worldH - vp.h, camSpring.shown))
        }
        lastCamTime = time

        // 悬停卡片的位置（整张重画时才用）：整张卡都在窗口里、不盖住被悬停那个人自己的头 / 屏幕 / 气泡，并把被它盖住的桌牌文字收起来。
        // 窗口太小、怎么放都会盖住他时，先去掉次要的行把卡片缩小再试；还是不行就不画卡片（桌牌上有标题和状态）。
        var hoverPlacementValue: (card: HoverCard.Card, rect: IntRect)? = nil
        if let hs = options.hoverSnapshot {
            let z = CGFloat(options.zoom)
            // 文字最宽 250 pt（更长的行用省略号），窗口很窄时更窄
            // 卡片宽 = ceil((文字宽 + 18) / z) + 1 个美术像素，要 ≤ 窗口宽 - 4（左右各留 2）：反推出文字最宽多少点；高同理
            let maxWpt = max(40, min(250, CGFloat(vp.w - 5) * z - 18)), maxHpt = max(40, CGFloat(vp.h - 5) * z)
            let o = lay.cellOrigin(seat: hs.seat)
            let oo = IntPoint(o.x, o.y)
            let hv = views.first { $0.seat == hs.seat }
            var avoid = [SeatRenderer.headRect(origin: oo), SeatRenderer.screenRegion(oo)]
            if let b = hv?.bubble { avoid.append(SeatRenderer.bubbleRect(origin: oo, size: SeatRenderer.bubbleSize(age: b.age))) }
            let factors = [1.0, 0.7, 0.5, 0.35]
            var cardCache: [Double: HoverCard.Card] = [:]
            func cardFor(_ f: Double) -> HoverCard.Card {
                if let c = cardCache[f] { return c }
                let c = HoverCard.make(hs, now: now, zoom: options.zoom, privacy: options.privacy, maxWidth: maxWpt, maxHeight: maxHpt * CGFloat(f))
                cardCache[f] = c
                return c
            }
            // 整张都在窗口里、且不盖住他自己的头 / 屏幕 / 气泡
            func fits(_ r: IntRect) -> Bool {
                r.x >= vp.x + 2 && r.y >= vp.y + 2 && r.maxX <= vp.maxX - 2 && r.maxY <= vp.maxY - 2 && !avoid.contains { r.intersection($0) != nil }
            }
            search: for f in factors {
                let card = cardFor(f)
                let w = card.size.x, h = card.size.y
                // 候选位置：先在他右下 / 左下（贴着他），再在他正上方 / 正下方（横向夹进窗口——窗口窄的时候只有上下有地方），最后两侧
                struct Cand { var p: IntPoint; var clampX: Bool }
                let cellBottom = o.y + Metrics.cellH + Metrics.plateH + 2
                let candidates = [Cand(p: IntPoint(o.x + 38, o.y + 21), clampX: false), Cand(p: IntPoint(o.x + 18 - w, o.y + 21), clampX: false),
                                  Cand(p: IntPoint(o.x + 20, o.y - h - 2), clampX: true), Cand(p: IntPoint(o.x + 20, cellBottom), clampX: true),
                                  Cand(p: IntPoint(o.x + Metrics.cellW + 2, o.y + 6), clampX: false), Cand(p: IntPoint(o.x - w - 2, o.y + 6), clampX: false)]
                for c in candidates {
                    let x = c.clampX ? max(vp.x + 2, min(c.p.x, vp.maxX - w - 2)) : c.p.x
                    let r = IntRect(x, c.p.y, w, h)
                    if fits(r) { hoverPlacementValue = (card, r); break search }
                }
            }
            // 兜底（窗口小到上面的位置都放不下，比如最小窗口 + 大缩放）：在窗口里每隔 2 个像素找一个离首选位置最近、又不盖住他头 / 屏幕 / 气泡的地方。
            // 卡片可以压在他的身体 / 椅子 / 桌牌上（桌牌文字会被收起来）——有信息总比只剩桌牌上被省略的一行强。
            if hoverPlacementValue == nil {
                let anchor = IntPoint(o.x + 38, o.y + 21)
                var best: (IntRect, Int)? = nil, bestCard: HoverCard.Card? = nil
                for f in factors {
                    let card = cardFor(f)
                    let w = card.size.x, h = card.size.y
                    guard vp.w - 4 >= w, vp.h - 4 >= h else { continue }
                    var y = vp.y + 2
                    while y + h <= vp.maxY - 2 {
                        var x = vp.x + 2
                        while x + w <= vp.maxX - 2 {
                            let r = IntRect(x, y, w, h)
                            if fits(r) {
                                let d = (x - anchor.x) * (x - anchor.x) + (y - anchor.y) * (y - anchor.y)
                                if best == nil || d < best!.1 { best = (r, d); bestCard = card }
                            }
                            x += 2
                        }
                        y += 2
                    }
                    if best != nil { break }                      // 先让卡片尽量大：这一档放得下就不再缩小
                }
                if let b = best, let c = bestCard { hoverPlacementValue = (c, b.0) }
            }
            // 被卡片盖住的桌牌文字收起来（文字层在画布上面，不收的话会浮在卡片上和卡片的字叠在一起）
            if let hp = hoverPlacementValue { texts.removeAll { $0.tag.hasPrefix("plate") && (Self.artBounds($0, zoom: options.zoom).intersection(hp.rect) != nil) } }
        }

        // ---- 要重画哪些地方 ----
        // 走路的人、悬停卡片是跨工位的浮层：有的时候（以及它们消失的那一帧）整张重画，最省心也最不容易错
        let steady = walkers.isIdle && options.hoverSnapshot == nil && screenFade.isEmpty
        let full = !options.retained || !retainedReady || !steady || !prevSteady || rebuilt
        let newDynSig = room.dynamicSignature(dyn)
        var dirty: [IntRect] = []
        if !full {
            for (i, v) in views.enumerated() {
                guard let old = seatSigs[i] else { dirty.append(SeatRenderer.seatRegion(v.origin)); continue }
                let new = sigs[i]
                if old.rest != new.rest { dirty.append(SeatRenderer.seatRegion(v.origin)); continue }        // 其余部分变了：整个工位重画
                if old.screen != new.screen { dirty.append(SeatRenderer.screenRegion(v.origin)) }            // 只有屏幕变了：只重画屏幕那一小块
                if old.person != new.person { dirty.append(SeatRenderer.personRegion(v.origin)) }            // 只有人变了：只重画人所在的矩形
            }
            if newDynSig != dynSig { dirty += room.dynamicRects }
            if ck.h != coatSig, !room.coatSlots.isEmpty {
                let cs = HelperArt.sprite("coat")
                for p in room.coatSlots { dirty.append(IntRect(p.x, p.y, cs.width, cs.height)) }
            }
        }

        func compose(_ region: IntRect?) {
            if let r = region { work.copyRegion(from: bg, rect: r); work.setClip(r) } else { work.copy(from: bg); work.setClip(nil) }
            defer { work.setClip(nil) }
            if room.dynamicRects.contains(where: { work.mayTouch($0) }) { room.drawDynamic(on: work, state: dyn, light: light) }
            for (ap, p) in coats {
                let cs = HelperArt.sprite("coat")
                if work.mayTouch(IntRect(p.x, p.y, cs.width, cs.height)) { work.blit(cs, x: p.x, y: p.y, style: Lighting.resolved(appearance: ap, state: light)) }
            }
            for v in views where work.mayTouch(SeatRenderer.seatRegion(v.origin)) { SeatRenderer.draw(v, on: work, light: light, gt: time, cache: cache(for: v.seat)) }
            if signZoom > 0, work.mayTouch(signRect) { Self.drawSign(signRect, on: work, light: light) }        // 「今天还没人上班」牌子：在桌椅上面
            if region == nil {
                walkers.draw(on: work, light: light, time: time)
                // 悬停卡片：放在这个人右下方（不盖住他自己的头、屏幕、气泡），放不下就换左边 / 别处，再夹进视口；卡片下面的桌牌文字收起来
                if let placed = hoverPlacementValue {
                    work.blitCanvas(placed.card.canvas, x: placed.rect.x, y: placed.rect.y)
                    for t in placed.card.texts {
                        var t2 = t; t2.x += Double(placed.rect.x); t2.y += Double(placed.rect.y)
                        if let c = t.container { t2.container = IntRect(c.x + placed.rect.x, c.y + placed.rect.y, c.w, c.h) }
                        texts.append(t2)
                    }
                }
            }
            // 夜里天花板灯：地上的光斑（在整幅画完之后二次着色）
            if light.darkness > 0.4 {
                for v in views where work.mayTouch(SeatRenderer.seatRegion(v.origin)) {
                    work.applyLightPool(cx: v.origin.x + Metrics.cellW / 2, cy: v.origin.y + 58, rx: 26, ry: 9, lut: Lighting.luts.ceiling, strength: 0.7 * light.darkness)
                }
            }
        }
        let pc = Prof.begin()
        var composed = false
        if full { compose(nil); composed = true }
        else if !dirty.isEmpty { for r in Self.merged(dirty) { compose(r) }; composed = true }
        Prof.end("office.compose", pc)
        if signZoom > 0 {
            let z = Double(signZoom)
            let st = TextStyle(size: 11, color: Self.signInk, weight: .semibold)
            let hpt = Double(TextRenderer.shared.measure("测", style: st).height)
            texts.append(TextItem(Self.signText, style: st, x: Double(signRect.x) + Double(signRect.w) / 2,
                                  y: Double(signRect.y) + max(0, (Double(signRect.h) * z - hpt) / 2 - 1) / z, align: .center, maxWidth: CGFloat(signRect.w) * CGFloat(z),
                                  container: signRect, tag: "sign"))
        }
        // 悬停卡片的文字（局部重绘时卡片不存在，整张重画时上面已经加进 texts）
        for (i, sg) in sigs.enumerated() { seatSigs[i] = sg }
        dynSig = newDynSig; coatSig = ck.h
        retainedReady = true; prevSteady = steady
        lastCanvasChanged = composed || rebuilt

        var trans = Set(views.filter { $0.transition }.map { $0.seat })
        for (seat, r) in walkers.lastRects {
            trans.insert(seat)                                                    // 正在走进 / 走出的座位
            for v in views {                                                      // 被走路的人挡住的座位
                let cell = IntRect(v.origin.x, v.origin.y, Metrics.cellW, Metrics.cellH)
                if cell.intersection(r) != nil { trans.insert(v.seat) }
            }
        }
        transitionSeats = trans
        blinkRects = views.filter { $0.blink }.map { v in
            let lo = SeatGeometry.layerOrigin
            return IntRect(v.origin.x + lo.x + BuddyRig.headX - 2, v.origin.y + lo.y + BuddyRig.headY - 2, 16, 18)
        }
        if options.audit {
            var regs: [AuditRegion] = []
            for v in views where v.mode == .occupied {
                regs.append(AuditRegion(kind: .face, rect: SeatRenderer.headRect(origin: v.origin), seat: v.seat))
                regs.append(AuditRegion(kind: .screen, rect: SeatRenderer.screenRegion(v.origin), seat: v.seat))
                if let b = v.bubble { regs.append(AuditRegion(kind: .bubble, rect: SeatRenderer.bubbleRect(origin: v.origin, size: SeatRenderer.bubbleSize(age: b.age)), seat: v.seat)) }
            }
            if let hs = options.hoverSnapshot, let hp = hoverPlacementValue { regs.append(AuditRegion(kind: .card, rect: hp.rect, seat: hs.seat)) }
            auditRegions = regs
        }
        var f = Frame(canvas: work, viewport: vp, texts: texts)
        f.canvasChanged = lastCanvasChanged; f.changeKnown = true
        return f
    }

    /// 一段文字大致占的矩形（美术像素，世界坐标）：收起被卡片盖住的桌牌文字时用。
    static func artBounds(_ t: TextItem, zoom: Int) -> IntRect {
        let m = TextRenderer.shared.measure(t.text, style: t.style, maxWidth: t.maxWidth)
        let z = Double(max(1, zoom))
        let w = Double(m.width) / z, h = Double(m.height) / z
        var x = t.x
        switch t.align { case .left: break; case .center: x -= w / 2; case .right: x -= w }
        return IntRect(Int(x.rounded(.down)), Int(t.y.rounded(.down)), Int(w.rounded(.up)) + 1, Int(h.rounded(.up)) + 1)
    }

    // MARK: 桌牌文字
    struct PlateKey: Equatable {
        var origin: IntPoint; var mode: SeatView.Mode; var title: String; var status: String; var cands: [String]
        var dim: Bool; var zoom: Int; var privacy: Bool; var labels: Int; var hovered: Bool
    }
    var plateCache: [Int: (PlateKey, [TextItem])] = [:]

    /// 桌牌文字用深色：桌牌的木板白天亮（L≈0.55）、夜里被时段 LUT 压暗但仍然是中灰（L≈0.26），深色字在两种情况下（以及抖动过渡中间那种半亮半暗的棋盘格）
    /// 对比度都 ≥ 4.5:1；浅色字压在夜里的中灰木板上只有 2.6:1（text-audit 量出来的，之前的「夜里换浅色字」是错的）。下班工位的桌牌是深胡桃木，用浅色字。
    static let plateTitleInk = RGBA8(hex: 0x1E1518), plateStatusInk = RGBA8(hex: 0x261A20)
    static let dormantTitleInk = RGBA8(hex: 0xF8EFDD), dormantStatusInk = RGBA8(hex: 0xF0E2CB)

    /// 桌牌文字一秒才变一次（状态行里的时间只到秒），其余时候直接复用上一次的排版结果。
    func cachedPlateTexts(_ v: SeatView, options: SceneOptions, seat: Int) -> [TextItem] {
        let lm: Int = { switch options.labels { case .always: return 0; case .hover: return 1; case .off: return 2 } }()
        let key = PlateKey(origin: v.origin, mode: v.mode, title: v.title, status: v.status, cands: v.statusCandidates, dim: v.dim,
                           zoom: options.zoom, privacy: options.privacy, labels: lm, hovered: options.hoverSeat == seat)
        if let c = plateCache[seat], c.0 == key { return c.1 }
        let items = plateTexts(v, options: options, seat: seat)
        plateCache[seat] = (key, items)
        return items
    }

    /// 一种字体样式的笔画范围（相对文字图片顶部，单位点）：用「测Agpy」量——中文、带上伸的拉丁字母、带下伸的拉丁字母都算进去，
    /// 所以按它排版，任何标题 / 状态文字的笔画都在这个范围之内。
    struct InkExtent { var top: Double; var height: Double }
    nonisolated(unsafe) static var inkExtentCache: [TextStyle: InkExtent] = [:]
    static let inkExtentLock = NSLock()
    static func inkExtent(_ style: TextStyle) -> InkExtent {
        inkExtentLock.lock(); defer { inkExtentLock.unlock() }
        var key = style; key.color = RGBA8(0, 0, 0, 255)
        if let e = inkExtentCache[key] { return e }
        var e = InkExtent(top: 2, height: Double(style.size))
        if let ink = TextRenderer.shared.ink("测Agpy", style: key, scale: 4), let b = ink.bbox { e = InkExtent(top: Double(b.y) / 4, height: Double(b.h) / 4) }
        inkExtentCache[key] = e
        return e
    }

    func plateTexts(_ v: SeatView, options: SceneOptions, seat: Int) -> [TextItem] {
        guard options.labels != .off, options.labels == .always || options.hoverSeat == seat else { return [] }
        guard options.zoom >= 2 else { return [] }                 // 1 倍时桌牌只有 12 pt 高，字放不进去（悬停卡片里有全部信息）
        let o = v.origin
        let zoom = Double(options.zoom)
        let dim = v.dim || v.mode == .dormant
        let titleStyle = TextStyle(size: 11, color: dim ? Self.dormantTitleInk : Self.plateTitleInk, weight: .semibold)
        let statusStyle = TextStyle(size: 10, color: dim ? Self.dormantStatusInk : Self.plateStatusInk, weight: .regular)
        let singleStyle = TextStyle(size: 10, color: dim ? Self.dormantTitleInk : Self.plateTitleInk, weight: .medium)
        let maxW = CGFloat(Metrics.cellW - 8) * CGFloat(zoom)
        let cx = Double(o.x + Metrics.cellW / 2)
        let plateTop = Double(o.y + Metrics.cellH)
        let plateRect = IntRect(o.x + 2, o.y + Metrics.cellH, Metrics.cellW - 4, Metrics.plateH)         // 桌牌底板（含 1 像素边框），SeatRenderer.drawPlate 画的就是它
        // 桌牌内部（去掉上下各 1 个美术像素的边框），单位点
        let interiorTop = zoom, interiorH = Double(Metrics.plateH - 2) * zoom
        let tr = TextRenderer.shared
        let title = options.privacy ? "会话" : PlateCopy.displayTitle(v.title)
        var items: [TextItem] = []
        func y(_ ptFromPlateTop: Double) -> Double { plateTop + ptFromPlateTop / zoom }
        if options.zoom >= 3 && v.mode == .occupied {
            // 两行：标题在上、状态在下，按真实笔画范围把这一块在桌牌内部里垂直居中，两行之间留 1.5 pt
            let et = Self.inkExtent(titleStyle), es = Self.inkExtent(statusStyle)
            let gap = 1.5
            let block = et.height + gap + es.height
            let margin = max(0, (interiorH - block) / 2)
            items.append(TextItem(title, style: titleStyle, x: cx, y: y(interiorTop + margin - et.top), align: .center, maxWidth: maxW, container: plateRect, tag: "plate.title"))
            // 放得下最详细的就用最详细的
            let cands = v.statusCandidates.isEmpty ? [v.status] : v.statusCandidates
            var chosen = cands.last ?? ""
            for c in cands where tr.measure(c, style: statusStyle).width <= maxW { chosen = c; break }
            items.append(TextItem(chosen, style: statusStyle, x: cx, y: y(interiorTop + margin + et.height + gap - es.top), align: .center, maxWidth: maxW, container: plateRect, tag: "plate.status"))
        } else if options.zoom >= 3 {
            let et = Self.inkExtent(titleStyle)
            items.append(TextItem(title, style: titleStyle, x: cx, y: y(interiorTop + max(0, (interiorH - et.height) / 2) - et.top), align: .center, maxWidth: maxW, container: plateRect, tag: "plate.title"))
        } else {
            // 放不下两行（2 倍）：忙 / 等你的时候显示状态，其余显示标题
            let text = (v.mode == .occupied && !v.status.isEmpty) ? (v.statusCandidates.last ?? v.status) : title
            let e = Self.inkExtent(singleStyle)
            items.append(TextItem(text, style: singleStyle, x: cx, y: y(interiorTop + max(0, (interiorH - e.height) / 2) - e.top), align: .center, maxWidth: maxW, container: plateRect, tag: "plate.single"))
        }
        return items
    }
}
