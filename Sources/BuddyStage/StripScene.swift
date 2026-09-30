import Foundation
import BuddyCore
import PixelKit
import BuddyArt

/// 桌面宠物条：透明画布，一排小工位（只有桌子、显示器、人；没有墙和地板），脚下一层抖动的影子。
/// 画布高度 = 卡片空间 56 + 气泡空间 20 + 工位 64；鼠标只有碰到 buddy（或气泡）时才被拦下，靠对象 ID 缓冲做像素级命中。
public final class StripScene {
    public static let cardH = 56, bubbleH = 20, cellH = 64
    /// 超过 8 个人时，最右边多出一小列放「+N」（只是一块牌子，没有对象 ID，鼠标穿过去）。
    static let badgeColW = 24
    public static var totalH: Int { cardH + bubbleH + cellH }
    public private(set) var slots: [Int] = []       // 槽位 → 座位号
    public private(set) var transitionIDs: Set<UInt16> = []
    var prevSlotSeats: [Int] = []
    public private(set) var blinkRects: [IntRect] = []
    var canvas = Canvas(width: 8, height: 8)
    var scratch = Canvas(width: SeatGeometry.cellW, height: SeatGeometry.cellH + SeatGeometry.plateH)

    public init() {}
    public static func hitID(slot: Int) -> UInt16 { UInt16(3000 + slot) }
    public static func slot(fromHitID id: UInt16) -> Int? { (id >= 3000 && id < 4000) ? Int(id) - 3000 : nil }

    var slotSigs: [Int: UInt64] = [:]
    var badgeSig = 0
    var retainedReady = false
    var slotCaches: [Int: SeatCache] = [:]
    func slotCache(_ i: Int) -> SeatCache { if let c = slotCaches[i] { return c }; let c = SeatCache(); slotCaches[i] = c; return c }
    public var retained = true
    public private(set) var lastCanvasChanged = true
    /// 靠右摆放（默认，和「宠物条默认靠右」一致）：第 0 个人在最右边，新来的人从左边长出来——窗口右边缘固定时，
    /// 已经坐着的人在屏幕上一动不动（不靠右的话，每来一个人整排人会瞬间往左跳一格）。靠左 / 居中时按从左到右摆。
    public var alignRight = true
    public private(set) var slotCount = 1
    /// 槽位 i 在画布里的横坐标（美术像素）。
    public func slotX(_ i: Int) -> Int { (alignRight ? slotCount - 1 - i : i) * Metrics.cellW }

    public func render(director: VisualDirector, present: [BuddySnapshot], now: Date, time: Double, privacy: Bool) -> Frame {
        let n = max(1, min(8, present.count))
        slotCount = n
        let extra = max(0, present.count - 8)
        let badgeCol = IntRect(n * Metrics.cellW, 0, extra > 0 ? Self.badgeColW : 0, Self.totalH)
        let w = n * Metrics.cellW + badgeCol.w, h = Self.totalH
        var rebuilt = false
        if canvas.width != w || canvas.height != h { canvas = Canvas(width: w, height: h); rebuilt = true; retainedReady = false }
        let light = LightState(a: .day)         // 桌面上不染夜色：背景是用户自己的壁纸
        slots = []
        transitionIDs = []; blinkRects = []
        let seatsNow = present.prefix(8).map { $0.seat }
        for i in 0..<max(seatsNow.count, prevSlotSeats.count) where (i < seatsNow.count ? seatsNow[i] : -1) != (i < prevSlotSeats.count ? prevSlotSeats[i] : -1) { transitionIDs.insert(StripScene.hitID(slot: i)) }
        prevSlotSeats = seatsNow
        struct Slot { var i: Int; var v: SeatView; var x0: Int; var y0: Int; var sig: UInt64 }
        var views: [Slot] = []
        for (i, s) in present.prefix(8).enumerated() {
            guard let p = director.performers[s.key] else { continue }
            let x0 = slotX(i), y0 = Self.cardH + Self.bubbleH
            // 朝向（转身 / 侧身靠着往哪边）只由槽位的奇偶决定：宠物条上没有过道，而且按画布中线算的话，
            // 每来一个人中线就挪一下，靠近中线的人会突然翻个面。
            let mirror = i % 2 == 1
            let v = p.seatView(origin: IntPoint(0, 0), time: time, now: now, light: light, hitID: StripScene.hitID(slot: i), privacy: privacy, mirror: mirror)
            var k = KeyHasher(); k.add(SeatRenderer.signature(v, light: light, gt: time, plateStyle: .none) as UInt64); k.add(x0); k.add(y0)
            views.append(Slot(i: i, v: v, x0: x0, y0: y0, sig: k.h))
            // 地上抖动的影子（画在人物之后，不参与命中）
            slots.append(s.seat)
            if v.transition { transitionIDs.insert(StripScene.hitID(slot: i)) }
            if v.blink { let lo = SeatGeometry.layerOrigin; blinkRects.append(IntRect(x0 + lo.x + BuddyRig.headX - 2, y0 + lo.y + BuddyRig.headY - 2, 16, 18)) }
        }
        let full = !retained || !retainedReady || rebuilt
        var dirty: [IntRect] = []
        if !full {
            for sl in views where slotSigs[sl.i] != sl.sig { dirty.append(IntRect(sl.x0, 0, Metrics.cellW, h)) }
            for i in views.count..<max(views.count, slotSigs.count) where slotSigs[i] != nil { dirty.append(IntRect(slotX(i), 0, Metrics.cellW, h)) }
            if badgeSig != extra { dirty.append(badgeCol) }
        }
        func compose(_ region: IntRect?) {
            let r = region ?? canvas.bounds
            canvas.clearRegion(r)
            canvas.setClip(r)
            defer { canvas.setClip(nil) }
            for sl in views where canvas.mayTouch(IntRect(sl.x0, 0, Metrics.cellW, h)) {
                scratch.clear()
                SeatRenderer.draw(sl.v, on: scratch, light: light, gt: time, plateStyle: .none, cache: slotCache(sl.i))
                canvas.blitCanvas(scratch, x: sl.x0, y: sl.y0, clip: IntRect(sl.x0, 0, Metrics.cellW, h))
            }
            if extra > 0, canvas.mayTouch(badgeCol) {
                let st = Lighting.resolved(appearance: nil, state: light)
                let text = "+\(extra)"
                let tw = PixelFont.small.width(of: text)
                let bx = badgeCol.x + max(1, (badgeCol.w - (tw + 6)) / 2), by = h - 30
                let plateR = IntRect(bx, by, tw + 6, 9)
                canvas.plate(plateR, border: Pal.dx("woodOak.out"), fill: Pal.dx("woodOak.hi"), style: st)
                PixelFont.small.draw(text, x: bx + 3, y: by + 1, value: Pal.dx("ink1"), style: st, on: canvas, container: plateR)
            }
        }
        var composed = false
        if full { compose(nil); composed = true }
        else if !dirty.isEmpty { for r in OfficeScene.merged(dirty) { compose(r) }; composed = true }
        slotSigs = [:]
        for sl in views { slotSigs[sl.i] = sl.sig }
        badgeSig = extra
        retainedReady = true
        lastCanvasChanged = composed || rebuilt
        var f = Frame(canvas: canvas)
        f.canvasChanged = lastCanvasChanged; f.changeKnown = true
        return f
    }
}
