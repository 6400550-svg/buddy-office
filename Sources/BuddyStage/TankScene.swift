import Foundation
import BuddyCore
import PixelKit
import BuddyArt

/// 小鱼缸：置顶小窗里的紧凑办公室。顶部一条窄墙（窗户 + 挂钟），工位格 48×56，1–2 排，最多 8 个人，更多显示 "+N"。
public final class TankScene {
    public static let cellW = 48, cellH = 56, wallH = 26, margin = 4
    public private(set) var lastHits: [Int: Int] = [:]      // 格子号 → 座位号
    /// 闪烁扫描用：这一帧在过渡（转身等）的格子的对象 ID；眨眼的头盒子矩形（画布坐标）。
    public private(set) var transitionIDs: Set<UInt16> = []
    public private(set) var blinkRects: [IntRect] = []
    var canvas = Canvas(width: 8, height: 8)
    var scratch = Canvas(width: SeatGeometry.cellW, height: SeatGeometry.cellH + SeatGeometry.plateH)
    var bg = Canvas(width: 8, height: 8)
    var bgKey = ""
    var prevSlotSeats: [Int] = []

    public init() {}

    public struct Layout: Equatable {
        public var cols: Int, rows: Int, shown: Int, extra: Int
        public var w: Int { cols * TankScene.cellW + 2 * TankScene.margin }
        public var h: Int { TankScene.wallH + rows * TankScene.cellH + 8 }
    }
    public static func layout(count: Int) -> Layout {
        let shown = min(8, max(count, 2))
        let cols = shown <= 4 ? shown : 4
        let rows = (shown + cols - 1) / cols
        return Layout(cols: cols, rows: rows, shown: shown, extra: max(0, count - 8))
    }

    public static func hitID(slot: Int) -> UInt16 { UInt16(2000 + slot) }

    // 局部重绘的状态（做法同 OfficeScene）
    var slotSigs: [Int: UInt64] = [:]
    var dynSig: UInt64 = 0
    var badgeSig = 0
    var retainedReady = false
    var slotCaches: [Int: SeatCache] = [:]
    func slotCache(_ i: Int) -> SeatCache { if let c = slotCaches[i] { return c }; let c = SeatCache(); slotCaches[i] = c; return c }
    public var retained = true
    public private(set) var lastCanvasChanged = true

    static func skyRects(_ lay: Layout) -> [IntRect] {
        let wx = lay.w / 2 - 22
        return [IntRect(wx + 3, 4, 30, 15), IntRect(wx + 42, 4, 13, 13)]      // 天空玻璃；钟面（指针在里面）
    }

    /// 「今天还没人上班」牌子在小鱼缸里的位置（美术像素）：地板正中。牌子大小按文字宽度和当前缩放定。
    static func signRect(_ lay: Layout, zoom: Int) -> IntRect {
        let z = Double(max(1, zoom))
        let m = TextRenderer.shared.measure(OfficeScene.signText, style: OfficeScene.signMeasureStyle)
        let w = Int(ceil(Double(m.width) / z)) + 16, h = max(11, Int(ceil(Double(m.height) / z)) + 8)
        return IntRect((lay.w - w) / 2, wallH + (lay.h - wallH - h) / 2, w, h)
    }

    /// zoom：这个窗口的缩放倍数（只有「今天还没人上班」那块牌子按它定大小）。
    public func render(director: VisualDirector, present: [BuddySnapshot], now: Date, time: Double, privacy: Bool, zoom: Int = 2, emptySign: Bool = true) -> Frame {
        let lay = Self.layout(count: present.count)
        let light = SceneClock.at(now).light
        let signZoom = (emptySign && present.isEmpty) ? max(1, zoom) : 0
        let key = "\(lay.cols)x\(lay.rows)|\(light.a)\(light.b)\(light.level)|sign\(signZoom)"
        var rebuilt = false
        if key != bgKey || canvas.width != lay.w || canvas.height != lay.h {
            canvas = Canvas(width: lay.w, height: lay.h); bg = Canvas(width: lay.w, height: lay.h)
            bake(lay, light: light)
            if signZoom > 0 { OfficeScene.drawSign(Self.signRect(lay, zoom: signZoom), on: bg, light: light) }
            bgKey = key
            rebuilt = true; retainedReady = false
        }
        lastHits = [:]
        transitionIDs = []; blinkRects = []
        // 有人进出（这一格换人了）：那一格算过渡（小鱼缸里没有走路动画，人是直接出现 / 消失的）
        let seatsNow = present.prefix(8).map { $0.seat }
        for i in 0..<max(seatsNow.count, prevSlotSeats.count) where (i < seatsNow.count ? seatsNow[i] : -1) != (i < prevSlotSeats.count ? prevSlotSeats[i] : -1) { transitionIDs.insert(Self.hitID(slot: i)) }
        prevSlotSeats = seatsNow
        // 先算出每个格子这一帧要画什么（视图 + 指纹），再决定重画哪些地方
        struct Slot { var i: Int; var v: SeatView; var rect: IntRect; var x0: Int; var y0: Int; var sig: UInt64 }
        var slots: [Slot] = []
        for (i, s) in present.prefix(8).enumerated() {
            guard let p = director.performers[s.key] else { continue }
            let col = i % lay.cols, row = i / lay.cols
            let x0 = Self.margin + col * Self.cellW, y0 = Self.wallH + row * Self.cellH
            let mirror = (x0 + Self.cellW / 2) >= lay.w / 2
            let v = p.seatView(origin: IntPoint(0, 0), time: time, now: now, light: light, hitID: Self.hitID(slot: i), privacy: privacy, mirror: mirror)
            var k = KeyHasher(); k.add(SeatRenderer.signature(v, light: light, gt: time, plateStyle: .none) as UInt64); k.add(x0); k.add(y0)
            slots.append(Slot(i: i, v: v, rect: IntRect(x0, y0, Self.cellW, Self.cellH), x0: x0, y0: y0, sig: k.h))
            lastHits[i] = s.seat
            if v.transition { transitionIDs.insert(Self.hitID(slot: i)) }
            if v.blink { let lo = SeatGeometry.layerOrigin; blinkRects.append(IntRect(x0 - 4 + lo.x + BuddyRig.headX - 2, y0 - 2 + lo.y + BuddyRig.headY - 2, 16, 18)) }
        }
        let hour = SceneClock.at(now).hour
        var dk = KeyHasher(); dk.add(Int((hour * 60).rounded())); dk.add(RoomRenderer.cloudStep(time))
        let newDyn = dk.h
        let badgeRect = IntRect(lay.w - 40, lay.h - 12, 40, 12)
        let full = !retained || !retainedReady || rebuilt
        var dirty: [IntRect] = []
        if !full {
            for sl in slots where slotSigs[sl.i] != sl.sig { dirty.append(sl.rect) }
            for i in slots.count..<max(slots.count, slotSigs.count) where slotSigs[i] != nil { dirty.append(IntRect(Self.margin + (i % lay.cols) * Self.cellW, Self.wallH + (i / lay.cols) * Self.cellH, Self.cellW, Self.cellH)) }
            if newDyn != dynSig { dirty += Self.skyRects(lay) }
            if badgeSig != lay.extra { dirty.append(badgeRect) }
        }
        let st = Lighting.resolved(appearance: nil, state: light)
        func compose(_ region: IntRect?) {
            if let r = region { canvas.copyRegion(from: bg, rect: r); canvas.setClip(r) } else { canvas.copy(from: bg); canvas.setClip(nil) }
            defer { canvas.setClip(nil) }
            if Self.skyRects(lay).contains(where: { canvas.mayTouch($0) }) { drawSky(lay, now: now, time: time, light: light) }
            for sl in slots where canvas.mayTouch(sl.rect) {
                scratch.clear()
                SeatRenderer.draw(sl.v, on: scratch, light: light, gt: time, plateStyle: .none, cache: slotCache(sl.i))
                canvas.blitCanvas(scratch, x: sl.x0 - 4, y: sl.y0 - 2, clip: sl.rect)
            }
            if lay.extra > 0, canvas.mayTouch(badgeRect) {
                let s = "+\(lay.extra)"
                let w = PixelFont.small.width(of: s)
                let plateR = IntRect(lay.w - w - 8, lay.h - 11, w + 6, 9)
                canvas.plate(plateR, border: Pal.dx("woodOak.out"), fill: Pal.dx("woodOak.hi"), style: st)
                PixelFont.small.draw(s, x: lay.w - w - 5, y: lay.h - 10, value: Pal.dx("ink1"), style: st, on: canvas, container: plateR)
            }
        }
        var composed = false
        if full { compose(nil); composed = true }
        else if !dirty.isEmpty { for r in OfficeScene.merged(dirty) { compose(r) }; composed = true }
        slotSigs = [:]
        for sl in slots { slotSigs[sl.i] = sl.sig }
        dynSig = newDyn; badgeSig = lay.extra; retainedReady = true
        lastCanvasChanged = composed || rebuilt
        var f = Frame(canvas: canvas)
        f.canvasChanged = lastCanvasChanged; f.changeKnown = true
        if signZoom > 0 {
            let r = Self.signRect(lay, zoom: signZoom), z = Double(signZoom)
            let st = TextStyle(size: 11, color: OfficeScene.signInk, weight: .semibold)
            let hpt = Double(TextRenderer.shared.measure("测", style: st).height)
            f.texts = [TextItem(OfficeScene.signText, style: st, x: Double(r.x) + Double(r.w) / 2, y: Double(r.y) + max(0, (Double(r.h) * z - hpt) / 2 - 1) / z,
                                align: .center, maxWidth: CGFloat(r.w) * CGFloat(z))]
        }
        return f
    }

    func bake(_ lay: Layout, light: LightState) {
        let c = bg
        let st = Lighting.resolved(appearance: nil, state: light)
        func P(_ n: String) -> UInt8 { Pal.dx(n) }
        // 墙
        c.fillRect(IntRect(0, 0, lay.w, Self.wallH), value: P("wall.base"), style: st)
        for y in 0..<Self.wallH { for x in 0..<lay.w where (x % 8 == 3 && y % 8 == 3) || (x % 8 == 7 && y % 8 == 7) { c.set(x, y, value: P("wall.sh"), style: st) } }
        c.hLine(x: 0, y: 0, length: lay.w, value: P("trim.hi"), style: st)
        c.hLine(x: 0, y: 1, length: lay.w, value: P("trim.base"), style: st)
        c.fillRect(IntRect(0, Self.wallH - 8, lay.w, 5), value: P("dado.base"), style: st)
        c.hLine(x: 0, y: Self.wallH - 9, length: lay.w, value: P("trim.hi"), style: st)
        c.hLine(x: 0, y: Self.wallH - 3, length: lay.w, value: P("trim.base"), style: st)
        c.hLine(x: 0, y: Self.wallH - 2, length: lay.w, value: P("trim.sh"), style: st)
        // 地板
        for y in Self.wallH - 1..<lay.h { for x in 0..<lay.w {
            let row = (y - Self.wallH) / 8, seam = (x + row * 13) % 32
            var v = P("floor.base")
            if (y - Self.wallH) % 8 == 0 || seam == 0 { v = P("floor.gap") }
            else if (x * 7 + y * 13 + row * 5) % 47 == 0 { v = P("floor.sh") }
            c.set(x, y, value: v, style: st)
        } }
        // 窗框（玻璃区 14×14 动态画天空）+ 挂钟
        let wx = lay.w / 2 - 22
        c.blit(RoomArt.sprite("room.window").cropped(IntRect(0, 0, 36, 23), name: "tank.window"), x: wx, y: 1, style: st)
        c.blit(RoomArt.sprite("room.clock"), x: wx + 42, y: 4, style: st)
    }

    func drawSky(_ lay: Layout, now: Date, time: Double, light: LightState) {
        let hour = SceneClock.at(now).hour
        let wx = lay.w / 2 - 22
        SkyRenderer.draw(on: canvas, rect: IntRect(wx + 3, 4, 30, 15), hour: hour, time: time)
        // 钟的指针
        let st = Lighting.resolved(appearance: nil, state: light)
        let cx = wx + 42 + 6, cy = 4 + 6
        let minute = hour.truncatingRemainder(dividingBy: 1) * 60
        func hand(_ a: Double, _ len: Double, _ v: UInt8) {
            for i in 0...Int(len.rounded(.up)) { canvas.set(cx + Int((sin(a) * Double(i)).rounded()), cy - Int((cos(a) * Double(i)).rounded()), value: v, style: st) }
        }
        hand(hour.truncatingRemainder(dividingBy: 12) / 12 * 2 * Double.pi, 2.5, Pal.dx("ink0"))
        hand(minute / 60 * 2 * Double.pi, 4.2, Pal.dx("ink1"))
    }
}
