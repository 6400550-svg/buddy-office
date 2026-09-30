import Foundation
import PixelKit

/// 袖子样式：哪种材质、长袖还是短袖。手臂由「肩 → 肘 → 手」两段粗线画出来（程序生成，所以任何姿势都是一个手的目标位置，
/// 可以用弹簧平滑地动），袖子那一段用衣服材质，露出来的前臂和手用肤色。
public struct SleeveStyle: Sendable, Equatable {
    public enum Mat: Sendable { case cloth, accent }
    public var mat: Mat
    public var long: Bool
    public init(mat: Mat = .cloth, long: Bool = false) { self.mat = mat; self.long = long }
}

public enum Limbs {
    static func line(_ a: IntPoint, _ b: IntPoint) -> [IntPoint] {
        var pts: [IntPoint] = []
        var x0 = a.x, y0 = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            pts.append(IntPoint(x0, y0))
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        return pts
    }

    /// 肘的位置：两段等长，手够不到就画直线；bend = +1 肘向外/向下弯，-1 向内/向上弯（方向由 outward 指定，+1 = 画面右侧）。
    static func elbow(from s: IntPoint, to h: IntPoint, segment: Double, bend: Int, outward: Int) -> IntPoint {
        let dx = Double(h.x - s.x), dy = Double(h.y - s.y)
        let d = max(0.001, (dx * dx + dy * dy).squareRoot())
        let mx = Double(s.x) + dx / 2, my = Double(s.y) + dy / 2
        if d >= segment * 2 - 0.5 { return IntPoint(Int(mx.rounded()), Int(my.rounded())) }
        let hgt = (segment * segment - (d / 2) * (d / 2)).squareRoot()
        // 垂直于 s→h 的两个方向
        var px = -dy / d, py = dx / d
        // 让 (px,py) 朝向「外侧」：外侧 = outward 指定的水平方向；bend<0 取反
        if px * Double(outward) < 0 { px = -px; py = -py }
        let sign = Double(bend >= 0 ? 1 : -1)
        return IntPoint(Int((mx + px * hgt * sign).rounded()), Int((my + py * hgt * sign).rounded()))
    }

    /// 生成一条手臂的角色网格。返回 (网格, 网格左上角相对肩点的偏移)。
    /// - Parameters:
    ///   - hand: 手相对肩点的位置（美术像素，y 向下）
    ///   - outward: 肘朝哪侧弯（左臂 -1，右臂 +1）
    static func armGrid(hand: IntPoint, bend: Int = 1, outward: Int, sleeve: SleeveStyle, width: Int = 4) -> (grid: Grid, dx: Int, dy: Int) {
        let s = IntPoint(0, 0)
        let seg = max(4.0, (Double(hand.x * hand.x + hand.y * hand.y).squareRoot()) * 0.55)
        let e = elbow(from: s, to: hand, segment: seg, bend: bend, outward: outward)
        var path = line(s, e)
        let second = line(e, hand)
        path += second.dropFirst()
        let n = path.count
        let cuff = min(n - 1, max(1, Int(Double(n) * (sleeve.long ? 0.86 : 0.46))))
        // 画布范围
        let pad = width + 2
        let minX = (path.map { $0.x }.min() ?? 0) - pad, maxX = (path.map { $0.x }.max() ?? 0) + pad
        let minY = (path.map { $0.y }.min() ?? 0) - pad, maxY = (path.map { $0.y }.max() ?? 0) + pad
        let w = maxX - minX + 1, h = maxY - minY + 1
        var sleeveM = Bitmap(w: w, h: h), skinM = Bitmap(w: w, h: h)
        func stamp(_ m: inout Bitmap, _ p: IntPoint, size: Int) {
            let o = size / 2 - (size % 2 == 0 ? 1 : 0)
            for yy in 0..<size { for xx in 0..<size { m[p.x - minX + xx - o, p.y - minY + yy - o] = true } }
        }
        for (i, p) in path.enumerated() {
            if i <= cuff { stamp(&sleeveM, p, size: width) }
            if i >= cuff { stamp(&skinM, p, size: max(2, width - 1)) }
        }
        // 手：比前臂略宽的一小块
        stamp(&skinM, hand, size: width)
        let sleeveMat: Material = sleeve.mat == .cloth ? .cloth
            : Material(hi: Role.accent, base: Role.accent, sh: Role.accentSh, out: Role.accentSh)
        var g = ShadeKit.shade(sleeveM, sleeveMat)
        g.overlay(ShadeKit.shade(skinM, .skin))
        return (g, minX, minY)
    }

    /// 直接把一条手臂画到画布上。shoulder 是肩点（画布坐标）。
    public static func drawArm(on c: Canvas, shoulder: IntPoint, hand: IntPoint, bend: Int = 1, outward: Int,
                               sleeve: SleeveStyle, style: Resolved, id: UInt16 = 0) {
        let r = armGrid(hand: hand, bend: bend, outward: outward, sleeve: sleeve)
        let spr = r.grid.sprite(name: "arm.dyn")
        c.blit(spr, x: shoulder.x + r.dx, y: shoulder.y + r.dy, style: style, id: id)
    }

    /// 一条腿：髋 (0,0) → 膝 → 脚 foot（相对髋）。裤子材质整条腿，脚上一块鞋。返回 (网格, 左上角相对髋的偏移)。
    static func legGrid(foot: IntPoint, kneeBend: Int = 1, width: Int = 4) -> (grid: Grid, dx: Int, dy: Int) {
        let hip = IntPoint(0, 0)
        let dist = (Double(foot.x * foot.x + foot.y * foot.y)).squareRoot()
        let seg = max(3.0, dist * 0.535)          // 几乎伸直，只有一点膝盖弯曲
        let knee = elbow(from: hip, to: foot, segment: seg, bend: 1, outward: kneeBend)
        var path = line(hip, knee)
        path += line(knee, foot).dropFirst()
        let pad = width + 2
        let minX = (path.map { $0.x }.min() ?? 0) - pad, maxX = (path.map { $0.x }.max() ?? 0) + pad
        let minY = (path.map { $0.y }.min() ?? 0) - pad, maxY = (path.map { $0.y }.max() ?? 0) + pad + 2
        let w = maxX - minX + 1, h = maxY - minY + 1
        var legM = Bitmap(w: w, h: h), shoeM = Bitmap(w: w, h: h)
        for p in path { for yy in 0..<width { for xx in 0..<width { legM[p.x - minX + xx - width / 2, p.y - minY + yy - width / 2] = true } } }
        // 鞋：脚尖朝右（朝向由调用方翻转），4×2，落在脚点
        for yy in 0..<2 { for xx in 0..<4 { shoeM[foot.x - minX - 1 + xx, foot.y - minY - 1 + yy] = true } }
        var g = ShadeKit.shade(legM, .pants)
        g.overlay(ShadeKit.shade(shoeM, Material(hi: Role.shoe, base: Role.shoe, sh: Role.shoe, out: Role.shoe)))
        return (g, minX, minY)
    }

    static func drawLeg(on c: Canvas, hip: IntPoint, foot: IntPoint, kneeBend: Int = 1, style: Resolved) {
        let r = legGrid(foot: IntPoint(foot.x - hip.x, foot.y - hip.y), kneeBend: kneeBend)
        c.blit(r.grid.sprite(name: "leg.dyn"), x: hip.x + r.dx, y: hip.y + r.dy, style: style)
    }
}
