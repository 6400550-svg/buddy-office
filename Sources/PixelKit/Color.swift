import Foundation

/// 8 位 RGBA。像素画里透明度只用 0 / 255（阴影等半透明用少数固定值）。
public struct RGBA8: Equatable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    /// 0xRRGGBB
    public init(hex: UInt32, a: UInt8 = 255) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF), a)
    }
    public static let clear = RGBA8(0, 0, 0, 0)

    /// 预乘 alpha 后打包成内存顺序 R,G,B,A 的 UInt32（小端下是 A<<24|B<<16|G<<8|R）。
    @inline(__always) public var packed: UInt32 {
        if a == 255 { return UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000 }
        if a == 0 { return 0 }
        let aa = UInt32(a)
        let pr = (UInt32(r) * aa + 127) / 255, pg = (UInt32(g) * aa + 127) / 255, pb = (UInt32(b) * aa + 127) / 255
        return pr | pg << 8 | pb << 16 | aa << 24
    }

    /// 线性 sRGB 相对亮度（0…1），闪烁扫描的亮度差就用它。
    public var luminance: Double {
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// CIE L*a*b*（D65），测试里算 ΔL / ΔE 用。
    public var lab: (L: Double, a: Double, b: Double) {
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(b)
        let X = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
        let Y = (0.2126729 * R + 0.7151522 * G + 0.0721750 * B)
        let Z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(X), fy = f(Y), fz = f(Z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// CIE76 ΔE。
    public func deltaE(to o: RGBA8) -> Double {
        let p = lab, q = o.lab
        return sqrt((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b))
    }

    /// 线性插值（t 0…1）。
    public func mixed(with o: RGBA8, _ t: Double) -> RGBA8 {
        let u = max(0, min(1, t))
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(a) + (Double(b) - Double(a)) * u).rounded()))) }
        return RGBA8(m(r, o.r), m(g, o.g), m(b, o.b), m(a, o.a))
    }

    // HSV 互转（做色阶、色相偏移用）
    public var hsv: (h: Double, s: Double, v: Double) {
        let R = Double(r) / 255, G = Double(g) / 255, B = Double(b) / 255
        let mx = max(R, G, B), mn = min(R, G, B), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == R { h = ((G - B) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == G { h = (B - R) / d + 2 } else { h = (R - G) / d + 4 }
            h *= 60; if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
    public init(h: Double, s: Double, v: Double, a: UInt8 = 255) {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let ss = max(0, min(1, s)), vv = max(0, min(1, v))
        let c = vv * ss, x = c * (1 - abs((hh / 60).truncatingRemainder(dividingBy: 2) - 1)), m = vv - c
        let (r1, g1, b1): (Double, Double, Double)
        switch hh {
        case 0..<60: (r1, g1, b1) = (c, x, 0)
        case 60..<120: (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, ((v + m) * 255).rounded()))) }
        self.init(q(r1), q(g1), q(b1), a)
    }
}

/// 整数矩形（美术像素坐标）。
public struct IntRect: Equatable, Hashable, Sendable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
    public func contains(_ px: Int, _ py: Int) -> Bool { px >= x && py >= y && px < maxX && py < maxY }
    public func intersection(_ o: IntRect) -> IntRect? {
        let nx = max(x, o.x), ny = max(y, o.y), mx = min(maxX, o.maxX), my = min(maxY, o.maxY)
        return (mx > nx && my > ny) ? IntRect(nx, ny, mx - nx, my - ny) : nil
    }
    public func offsetBy(_ dx: Int, _ dy: Int) -> IntRect { IntRect(x + dx, y + dy, w, h) }
    public func insetBy(_ d: Int) -> IntRect { IntRect(x + d, y + d, max(0, w - 2 * d), max(0, h - 2 * d)) }
    public func union(_ o: IntRect) -> IntRect {
        let nx = min(x, o.x), ny = min(y, o.y)
        return IntRect(nx, ny, max(maxX, o.maxX) - nx, max(maxY, o.maxY) - ny)
    }
}
