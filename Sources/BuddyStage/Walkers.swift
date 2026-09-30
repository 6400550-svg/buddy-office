import Foundation
import BuddyCore
import PixelKit
import BuddyArt

/// 进场 / 离场的走路动画（任务书 5.5）：
///  进场：门开一条缝（0.1 秒）→ 人从门洞里走出来，走到工位（约 2.5 秒，走路 + 转弯），坐下（0.3 秒），显示器再开机；
///  离场：起身（0.3 秒）、把椅子推好、面向你挥手（0.7 秒）、走进门洞，门在他身后关上（人不会凭空消失）。
///  门洞：人在门洞里的时候只画在门洞里面（门洞外面被墙挡住），门扇按开度 0 / 1 / 2 三档画（关 / 半开 / 全开）。
/// 路线：门 → 沿左边空地往下走 → 沿这一排工位前面的地面往右 → 从椅子前面走进座位。走到哪个方向就用哪个朝向（下：正面，右 / 左：侧面，上：背面）。
public final class WalkerSystem {
    public enum Phase { case walkingIn, sitting, standing, waving, walkingOut }

    struct Walker {
        var key: String
        var appearance: Appearance
        var seat: Int
        var start: Double
        var entering: Bool
        var points: [FPoint]          // 世界坐标的脚点，进场的方向（门洞里面 → 门槛 → 座位前）
        var door: IntPoint = IntPoint(0, 0)      // 门槛的脚点（世界坐标）
        var length: Double
        var speed: Double
        var walkTime: Double { length / speed }
    }
    /// 门洞：人从门洞里走出来 / 走进去的那一段路（美术像素，垂直方向）。
    static let doorway = 14.0
    /// 进场时门先开这么久，人才从门洞里出现。
    static let lead = 0.10
    /// 离场时人走进门洞之后，门关上要多久。
    static let tail = 0.16
    var walkers: [String: Walker] = [:]
    private let layerScratch = Canvas(width: BuddyRig.layerW, height: BuddyRig.layerH)
    /// 上一次 draw 时每个走路的人占的矩形（世界坐标）；闪烁扫描用来判断哪些工位被挡住 / 在过渡。
    public private(set) var lastRects: [(seat: Int, rect: IntRect)] = []
    /// 这一帧「本来就在动」的区域（走路的人、门洞）：闪烁扫描不把这里面的像素摆动当成闪烁。
    public private(set) var motionRects: [IntRect] = []
    /// 门洞里面的矩形（世界坐标；场景在布局变化时设置）。
    public var doorInterior = IntRect(0, 0, 0, 0)
    public init() {}

    static let sitTime = 0.3, standTime = 0.3, waveTime = 0.7

    public func isBusy(_ key: String) -> Bool { walkers[key] != nil }
    /// 现在没有人在走进 / 走出。
    public var isIdle: Bool { walkers.isEmpty }

    static func route(door: IntPoint, seatOrigin o: IntPoint, layout: OfficeLayout) -> [FPoint] {
        let laneX = Double(max(6, layout.gridX0 - 12))
        let rowY = Double(o.y + 62)
        let seatX = Double(o.x + SeatGeometry.buddyCx)
        return [FPoint(Double(door.x), Double(door.y) - doorway),          // 门洞里面（人从这里走出来 / 走进去）
                FPoint(Double(door.x), Double(door.y)),                     // 门槛
                FPoint(laneX, Double(door.y) + 6),
                FPoint(laneX, rowY),
                FPoint(seatX, rowY),
                FPoint(seatX, Double(o.y + 54))]
    }

    static func length(_ p: [FPoint]) -> Double {
        var l = 0.0
        for i in 1..<p.count { l += ((p[i].x - p[i - 1].x) * (p[i].x - p[i - 1].x) + (p[i].y - p[i - 1].y) * (p[i].y - p[i - 1].y)).squareRoot() }
        return l
    }

    public func startEntering(key: String, appearance: Appearance, seat: Int, layout: OfficeLayout, door: IntPoint, time: Double) {
        let pts = Self.route(door: door, seatOrigin: layout.cellOrigin(seat: seat), layout: layout)
        let len = Self.length(pts)
        walkers[key] = Walker(key: key, appearance: appearance, seat: seat, start: time, entering: true, points: pts, door: door, length: len, speed: max(28, min(70, len / 2.5)))
    }

    public func startLeaving(key: String, appearance: Appearance, seat: Int, layout: OfficeLayout, door: IntPoint, time: Double) {
        let pts = Self.route(door: door, seatOrigin: layout.cellOrigin(seat: seat), layout: layout)
        let len = Self.length(pts)
        walkers[key] = Walker(key: key, appearance: appearance, seat: seat, start: time, entering: false, points: pts, door: door, length: len, speed: max(28, min(70, len / 2.5)))
    }

    /// 沿路线走了 d 个像素的位置和朝向。reverse = 从座位往门走。
    static func sample(_ w: Walker, distance d: Double, reverse: Bool) -> (pos: FPoint, dir: FPoint) {
        var pts = w.points
        if reverse { pts.reverse() }
        var remain = max(0, d)
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let seg = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            if seg < 0.0001 { continue }
            if remain <= seg { let t = remain / seg; return (FPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t), FPoint((b.x - a.x) / seg, (b.y - a.y) / seg)) }
            remain -= seg
        }
        let last = pts[pts.count - 1], prev = pts[pts.count - 2]
        let seg = max(0.0001, ((last.x - prev.x) * (last.x - prev.x) + (last.y - prev.y) * (last.y - prev.y)).squareRoot())
        return (last, FPoint((last.x - prev.x) / seg, (last.y - prev.y) / seg))
    }

    /// 这个座位现在要不要显示「椅子拉出来」（进场路上 / 坐下前；离场起身时）。
    public func chairOut(seat: Int, time: Double) -> Bool {
        for w in walkers.values where w.seat == seat {
            let e = time - w.start
            if w.entering { return true }
            if e < Self.standTime { return true }
        }
        return false
    }

    /// 进场是否已经走完并坐下（之后座位交给 Performer）。返回坐下的时刻。
    public func finishedEntering(_ key: String, time: Double) -> Double? {
        guard let w = walkers[key], w.entering else { return nil }
        let end = w.start + Self.lead + w.walkTime + Self.sitTime
        return time >= end ? end : nil
    }

    public func cleanup(time: Double) {
        for (k, w) in walkers {
            let total = w.entering ? Self.lead + w.walkTime + Self.sitTime : Self.standTime + Self.waveTime + w.walkTime + Self.tail
            if time - w.start > total + 0.05 { walkers.removeValue(forKey: k) }
        }
    }

    /// 门开度：0 关 / 1 半开 / 2 全开。进场：先开一条缝，人出来、走开一段之后关上；离场：人走近时开，走进门洞之后关上。
    func doorState(_ w: Walker, e: Double) -> Int {
        if w.entering {
            if e < Self.lead { return 1 }
            let clear = Self.doorway + 22                                  // 走出门洞再多走 22 像素，门开始关
            let tClose = Self.lead + clear / w.speed
            if e < tClose { return 2 }
            return e < tClose + 0.08 ? 1 : 0
        }
        let walkStart = Self.standTime + Self.waveTime
        if e < walkStart { return 0 }
        let d = (e - walkStart) * w.speed
        let remaining = w.length - d
        if remaining > Self.doorway + 30 { return 0 }
        if remaining > Self.doorway + 22 { return 1 }
        if d < w.length { return 2 }
        let te = e - walkStart - w.walkTime                                 // 已经在门洞最里面：门在他身后关上
        return te < 0.08 ? 2 : (te < Self.tail ? 1 : 0)
    }

    /// 门扇（半开 / 全开）：先把门洞里面涂成暗色，再在左边（铰链侧）画一扇变窄的门。关着的门就是背景里烘焙好的那张。
    func drawDoor(on c: Canvas, state: Int, light: LightState) {
        guard state > 0, doorInterior.w > 0 else { return }
        let st = Lighting.resolved(appearance: nil, state: light)
        func P(_ n: String) -> UInt8 { Pal.dx(n) }
        let r = doorInterior
        c.fillRect(r, value: P("ink1"), style: st)
        c.fillRect(IntRect(r.x, r.y, r.w, 3), value: P("ink0"), style: st)                    // 门楣的阴影
        c.fillRect(IntRect(r.x, r.maxY - 3, r.w, 3), value: P("ink2"), style: st)             // 门槛里面地上透出的一点光
        let leafW = state == 1 ? 9 : 4
        c.fillRect(IntRect(r.x, r.y, leafW, r.h), value: P("woodWalnut.base"), style: st)
        c.vLine(x: r.x, y: r.y, length: r.h, value: P("woodWalnut.hi"), style: st)
        c.vLine(x: r.x + leafW - 1, y: r.y, length: r.h, value: P("woodWalnut.out"), style: st)
        if leafW >= 7 {
            c.fillRect(IntRect(r.x + 2, r.y + 5, leafW - 4, 12), value: P("woodWalnut.sh"), style: st)
            c.fillRect(IntRect(r.x + 2, r.y + 22, leafW - 4, 16), value: P("woodWalnut.sh"), style: st)
        }
    }
    /// 门开着的时候，门洞里还能看见的那一块（门扇之外）。
    func visibleInterior(state: Int) -> IntRect {
        let leafW = state == 1 ? 9 : (state == 2 ? 4 : doorInterior.w)
        return IntRect(doorInterior.x + leafW, doorInterior.y, max(0, doorInterior.w - leafW), doorInterior.h)
    }

    /// 把所有走路中的人画到世界画布上（在全部工位之后、悬停卡片之前）。
    public func draw(on c: Canvas, light: LightState, time: Double) {
        lastRects = []; motionRects = []
        let ordered = walkers.values.sorted(by: { ($0.start, $0.key) < ($1.start, $1.key) })       // 固定顺序：走路的人互相遮挡时不能随字典顺序变
        var open = 0
        for w in ordered { open = max(open, doorState(w, e: time - w.start)) }
        if open > 0 { drawDoor(on: c, state: open, light: light); motionRects.append(doorInterior) }
        for w in ordered {
            let e = time - w.start
            var pos: FPoint, facing: Facing = .front, mirror = false
            var moving = true, sink = 0, wave = 0
            var phase = (e * 1.6).truncatingRemainder(dividingBy: 1)
            if w.entering {
                let ew = e - Self.lead
                if ew < 0 { continue }                                      // 门还在开，人还没出来
                if ew <= w.walkTime {
                    let s = Self.sample(w, distance: ew * w.speed, reverse: false)
                    pos = s.pos
                    (facing, mirror) = Self.facing(of: s.dir)
                } else {
                    // 坐下：站在椅子前面，背对镜头，身体逐步下沉
                    let s = Self.sample(w, distance: w.length, reverse: false)
                    pos = s.pos; facing = .back; moving = false
                    let k = (ew - w.walkTime) / Self.sitTime
                    sink = k < 0.34 ? 0 : (k < 0.67 ? 2 : 4)
                    pos.y -= Double(sink) * 0.5
                }
            } else {
                if e < Self.standTime {
                    let s = Self.sample(w, distance: 0, reverse: true)
                    pos = s.pos; facing = .back; moving = false
                    let k = e / Self.standTime
                    sink = k < 0.34 ? 4 : (k < 0.67 ? 2 : 0)
                } else if e < Self.standTime + Self.waveTime {
                    let s = Self.sample(w, distance: 0, reverse: true)
                    pos = s.pos; facing = .front; moving = false
                    wave = 1 + Int((e - Self.standTime) / 0.22) % 2
                } else {
                    let d = (e - Self.standTime - Self.waveTime) * w.speed
                    if d >= w.length {
                        // 站在门洞最里面，等门在身后关上（关上之后就看不见了，不是凭空消失）
                        if e - Self.standTime - Self.waveTime - w.walkTime >= Self.tail { continue }
                        let s = Self.sample(w, distance: w.length, reverse: true)
                        pos = s.pos; facing = .back; moving = false
                    } else {
                        let s = Self.sample(w, distance: d, reverse: true)
                        pos = s.pos
                        (facing, mirror) = Self.facing(of: s.dir)
                    }
                }
            }
            phase = moving ? phase : 0
            let layer = layerScratch                       // 复用一张草稿（原来每个走路的人每帧新建一张 48×62 的 Canvas）
            layer.clear()
            let rm = Lighting.resolved(appearance: w.appearance, state: light)
            BuddyRig.renderStanding(appearance: w.appearance, facing: facing, phase: phase, moving: moving, sink: sink, waveArm: wave, style: rm, into: layer)
            let footY = BuddyRig.headY + CharacterArt.headH + 10 + 9
            // 脚在门槛之上 = 人在门洞里：只画在门洞里面（还没被门扇挡住的那一块），门洞外面是墙
            var clip: IntRect? = nil
            if doorInterior.w > 0, pos.y < Double(w.door.y) - 0.5 { clip = visibleInterior(state: doorState(w, e: e)) }
            c.blitCanvas(layer, x: Int(pos.x.rounded()) - BuddyRig.cx, y: Int(pos.y.rounded()) - footY, flipH: mirror, clip: clip)
            let rect = IntRect(Int(pos.x.rounded()) - 12, Int(pos.y.rounded()) - 36, 24, 38)
            lastRects.append((w.seat, rect))
            motionRects.append(rect)
        }
    }

    static func facing(of d: FPoint) -> (Facing, Bool) {
        if abs(d.x) > abs(d.y) { return (.side, d.x < 0) }
        return (d.y > 0 ? .front : .back, false)
    }
}
