import Foundation
import PixelKit

/// 布尔位图：用来先画「轮廓」，再交给 ShadeKit 自动上描边 + 高光 + 阴影。
struct Bitmap {
    let w: Int, h: Int
    var bits: [Bool]
    init(w: Int, h: Int) { self.w = w; self.h = h; bits = [Bool](repeating: false, count: w * h) }
    /// 任何不是 '.' 和空格的字符都算「有」。
    init(_ rows: String) {
        let lines = rows.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        var ls = Array(lines)
        while let l = ls.last, l.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeLast() }
        let ww = ls.map { $0.count }.max() ?? 1
        self.init(w: ww, h: max(1, ls.count))
        for (y, l) in ls.enumerated() { for (x, c) in l.enumerated() where c != "." && c != " " { bits[y * w + x] = true } }
    }
    subscript(x: Int, y: Int) -> Bool {
        get { (x >= 0 && y >= 0 && x < w && y < h) ? bits[y * w + x] : false }
        set { if x >= 0, y >= 0, x < w, y < h { bits[y * w + x] = newValue } }
    }
    func offset(dx: Int, dy: Int, w nw: Int, h nh: Int) -> Bitmap {
        var b = Bitmap(w: nw, h: nh)
        for y in 0..<h { for x in 0..<w where self[x, y] { b[x + dx, y + dy] = true } }
        return b
    }
    mutating func fillRect(_ x0: Int, _ y0: Int, _ ww: Int, _ hh: Int, _ v: Bool = true) {
        for y in y0..<(y0 + hh) { for x in x0..<(x0 + ww) { self[x, y] = v } }
    }
    mutating func fillEllipse(cx: Double, cy: Double, rx: Double, ry: Double, _ v: Bool = true) {
        for y in 0..<h { for x in 0..<w {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1 { self[x, y] = v }
        } }
    }
    func union(_ o: Bitmap) -> Bitmap { var b = self; for y in 0..<min(h, o.h) { for x in 0..<min(w, o.w) where o[x, y] { b[x, y] = true } }; return b }
    func subtracting(_ o: Bitmap) -> Bitmap { var b = self; for y in 0..<min(h, o.h) { for x in 0..<min(w, o.w) where o[x, y] { b[x, y] = false } }; return b }
    var flippedH: Bitmap { var b = Bitmap(w: w, h: h); for y in 0..<h { for x in 0..<w where self[x, y] { b[w - 1 - x, y] = true } }; return b }
}

/// 一格一格的角色值（Role 号）网格；做精灵的中间形态。
struct Grid {
    let w: Int, h: Int
    var v: [UInt8]
    init(w: Int, h: Int) { self.w = w; self.h = h; v = [UInt8](repeating: 0, count: w * h) }
    subscript(x: Int, y: Int) -> UInt8 {
        get { (x >= 0 && y >= 0 && x < w && y < h) ? v[y * w + x] : 0 }
        set { if x >= 0, y >= 0, x < w, y < h { v[y * w + x] = newValue } }
    }
    /// 把 other 盖上来（other 里非 0 的覆盖）。
    mutating func overlay(_ o: Grid, dx: Int = 0, dy: Int = 0) {
        for y in 0..<o.h { for x in 0..<o.w where o.v[y * o.w + x] != 0 { self[x + dx, y + dy] = o.v[y * o.w + x] } }
    }
    /// 用 ASCII 覆盖细节（'.' 不动；'_' 表示擦成透明）。
    mutating func overlay(_ rows: String, legend: [Character: UInt8] = Role.chars, dx: Int = 0, dy: Int = 0) {
        var ls = rows.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let f = ls.first, f.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeFirst() }
        while let l = ls.last, l.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeLast() }
        for (y, l) in ls.enumerated() { for (x, c) in l.enumerated() {
            if c == "." || c == " " { continue }
            if c == "_" { self[x + dx, y + dy] = 0; continue }
            if let r = legend[c] { self[x + dx, y + dy] = r } else { preconditionFailure("overlay 里有不认识的字符「\(c)」") }
        } }
    }
    func sprite(name: String, anchors: [String: IntPoint] = [:]) -> IndexedSprite {
        IndexedSprite(name: name, width: w, height: h, pixels: v, anchors: anchors)
    }
    var flippedH: Grid { var g = Grid(w: w, h: h); for y in 0..<h { for x in 0..<w { g[w - 1 - x, y] = self[x, y] } }; return g }
    static func from(_ rows: String, legend: [Character: UInt8] = Role.chars) -> Grid {
        var ls = rows.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let f = ls.first, f.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeFirst() }
        while let l = ls.last, l.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeLast() }
        let ww = ls.map { $0.count }.max() ?? 1
        var g = Grid(w: ww, h: max(1, ls.count))
        for (y, l) in ls.enumerated() { for (x, c) in l.enumerated() {
            if c == "." || c == " " { continue }
            guard let r = legend[c] else { preconditionFailure("网格里有不认识的字符「\(c)」") }
            g[x, y] = r
        } }
        return g
    }
}

/// 一种材质的四个角色：高光 / 基色 / 阴影 / 描边。
struct Material {
    var hi: UInt8, base: UInt8, sh: UInt8, out: UInt8
    static let skin = Material(hi: Role.skinHi, base: Role.skin, sh: Role.skinSh, out: Role.outSkin)
    static let hair = Material(hi: Role.hairHi, base: Role.hair, sh: Role.hairSh, out: Role.outHair)
    static let cloth = Material(hi: Role.clothHi, base: Role.cloth, sh: Role.clothSh, out: Role.outCloth)
    static let pants = Material(hi: Role.pants, base: Role.pants, sh: Role.pantsSh, out: Role.pantsSh)
    static let chair = Material(hi: Role.chair, base: Role.chair, sh: Role.chairSh, out: Role.chairSh)
}

enum ShadeKit {
    /// 光从左上来：
    ///  · 轮廓：右下边缘用最深的描边色；左上边缘用比它浅一级的阴影色（选择性描边，不是一圈死黑）；
    ///  · 内部：贴着左上边缘的一圈是高光，贴着右下边缘的一圈是阴影，其余基色；
    /// 不做「枕头式」阴影（阴影不是从四周往中间收的）。
    static func shade(_ m: Bitmap, _ mat: Material, outline: Bool = true, hiBand: Bool = true, shBand: Bool = true) -> Grid {
        var g = Grid(w: m.w, h: m.h)
        func boundary(_ x: Int, _ y: Int) -> Bool {
            m[x, y] && (!m[x, y - 1] || !m[x, y + 1] || !m[x - 1, y] || !m[x + 1, y])
        }
        // 质心，用来限定高光只出现在左上半边、阴影只出现在右下半边
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in 0..<m.h { for x in 0..<m.w where m[x, y] { sx += Double(x); sy += Double(y); n += 1 } }
        let cx = n > 0 ? sx / n : 0, cy = n > 0 ? sy / n : 0
        for y in 0..<m.h { for x in 0..<m.w where m[x, y] {
            let top = !m[x, y - 1], bottom = !m[x, y + 1], left = !m[x - 1, y], right = !m[x + 1, y]
            if outline && (top || bottom || left || right) {
                g[x, y] = (bottom || right) ? mat.out : mat.sh
                continue
            }
            let upperLeft = (Double(x) - cx) + (Double(y) - cy) < 0.5
            if hiBand && upperLeft && (boundary(x, y - 1) || boundary(x - 1, y)) { g[x, y] = mat.hi }
            else if shBand && !upperLeft && (boundary(x, y + 1) || boundary(x + 1, y)) { g[x, y] = mat.sh }
            else { g[x, y] = mat.base }
        } }
        return g
    }
}
