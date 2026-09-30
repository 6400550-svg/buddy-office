import Foundation
import PixelKit

/// 窗外的天空：颜色、太阳/月亮的位置都由真实钟点决定；云每 3 秒挪 1 个像素；星星是静止的。
/// 直接写 RGB（不经过主调色板 / LUT，所以不受 LUT 和台灯光圈影响）。
public enum SkyRenderer {
    struct Keyframe { var hour: Double; var top: RGBA8; var bottom: RGBA8; var cloud: RGBA8; var cloudSh: RGBA8 }
    // 一天里的关键帧（本地时间）；之间线性插值
    static let keys: [Keyframe] = [
        Keyframe(hour: 0,     top: RGBA8(hex: 0x0E1230), bottom: RGBA8(hex: 0x232E5C), cloud: RGBA8(hex: 0x3A4778), cloudSh: RGBA8(hex: 0x2B3660)),
        Keyframe(hour: 5.0,   top: RGBA8(hex: 0x141A3E), bottom: RGBA8(hex: 0x2D3A6C), cloud: RGBA8(hex: 0x44507F), cloudSh: RGBA8(hex: 0x333F6A)),
        Keyframe(hour: 6.2,   top: RGBA8(hex: 0x5A5F9E), bottom: RGBA8(hex: 0xF0A48C), cloud: RGBA8(hex: 0xF9CBB8), cloudSh: RGBA8(hex: 0xC98FA0)),
        Keyframe(hour: 7.5,   top: RGBA8(hex: 0x6CB4F0), bottom: RGBA8(hex: 0xBFE4F8), cloud: RGBA8(hex: 0xFFFFFF), cloudSh: RGBA8(hex: 0xDCE8F6)),
        Keyframe(hour: 12.5,  top: RGBA8(hex: 0x5BAAF0), bottom: RGBA8(hex: 0xBDE8FF), cloud: RGBA8(hex: 0xFFFFFF), cloudSh: RGBA8(hex: 0xD7E6F7)),
        Keyframe(hour: 17.0,  top: RGBA8(hex: 0x6AAEEA), bottom: RGBA8(hex: 0xF6D9A8), cloud: RGBA8(hex: 0xFFF0DC), cloudSh: RGBA8(hex: 0xE6C6A6)),
        Keyframe(hour: 18.6,  top: RGBA8(hex: 0x5A4C8C), bottom: RGBA8(hex: 0xF08A5B), cloud: RGBA8(hex: 0xF7A57E), cloudSh: RGBA8(hex: 0xB86A6E)),
        Keyframe(hour: 19.6,  top: RGBA8(hex: 0x1A2048), bottom: RGBA8(hex: 0x3B3A78), cloud: RGBA8(hex: 0x4C5488), cloudSh: RGBA8(hex: 0x363E70)),
        Keyframe(hour: 21.0,  top: RGBA8(hex: 0x0E1230), bottom: RGBA8(hex: 0x232E5C), cloud: RGBA8(hex: 0x3A4778), cloudSh: RGBA8(hex: 0x2B3660)),
        Keyframe(hour: 24,    top: RGBA8(hex: 0x0E1230), bottom: RGBA8(hex: 0x232E5C), cloud: RGBA8(hex: 0x3A4778), cloudSh: RGBA8(hex: 0x2B3660)),
    ]

    static func sample(_ hour: Double) -> (top: RGBA8, bottom: RGBA8, cloud: RGBA8, cloudSh: RGBA8) {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        for i in 0..<(keys.count - 1) where h >= keys[i].hour && h <= keys[i + 1].hour {
            let a = keys[i], b = keys[i + 1]
            let t = (h - a.hour) / max(0.0001, b.hour - a.hour)
            return (a.top.mixed(with: b.top, t), a.bottom.mixed(with: b.bottom, t), a.cloud.mixed(with: b.cloud, t), a.cloudSh.mixed(with: b.cloudSh, t))
        }
        let k = keys[0]; return (k.top, k.bottom, k.cloud, k.cloudSh)
    }

    /// 夜色程度 0…1（星星、月亮的亮度）。
    static func nightAmount(_ hour: Double) -> Double {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        if h >= 20.2 || h < 5.0 { return 1 }
        if h >= 19.0 { return (h - 19.0) / 1.2 }
        if h >= 5.0 && h < 6.2 { return 1 - (h - 5.0) / 1.2 }
        return 0
    }

    static let stars: [(Int, Int)] = [(3, 2), (9, 6), (14, 3), (21, 5), (26, 2), (6, 12), (18, 10), (27, 11), (12, 14), (24, 16), (4, 18), (16, 19), (28, 20), (10, 21)]
    // 云：起始 x、y、形状（0/1/2）
    static let clouds: [(Int, Int, Int)] = [(4, 5, 0), (20, 12, 1), (34, 17, 2)]
    static let cloudShapes: [[String]] = [
        ["..###...", ".#####..", "########"],
        ["...##....", ".######..", "#########", ".#######."],
        ["..##...", "#####..", "#######"],
    ]

    /// 把天空画进 rect（窗玻璃区，30×24）。hour 是本地钟点（小数），t 是单调时间（云的漂移用）。
    public static func draw(on c: Canvas, rect: IntRect, hour: Double, time t: Double) {
        let s = sample(hour)
        let night = nightAmount(hour)
        // 渐变：每 3 行一档，档与档之间的边界用 Bayer 抖动过渡（不出现半透明，也不闪）
        let bands = max(2, rect.h / 3)
        for y in 0..<rect.h {
            let fy = Double(y) / Double(max(1, rect.h - 1)) * Double(bands - 1)
            let lo = Int(fy.rounded(.down)), frac = fy - Double(lo)
            func band(_ i: Int) -> RGBA8 { s.top.mixed(with: s.bottom, Double(i) / Double(bands - 1)) }
            for x in 0..<rect.w {
                let useNext = frac > Double(Resolved.bayer4[((rect.y + y) & 3) * 4 + ((rect.x + x) & 3)]) / 16.0 + 0.03
                c.setRaw(rect.x + x, rect.y + y, color: band(min(bands - 1, lo + (useNext ? 1 : 0))))
            }
        }
        // 星星（静止）
        if night > 0.05 {
            let sc = RGBA8(hex: 0xFFF6D8)
            for (i, p) in stars.enumerated() where p.0 < rect.w && p.1 < rect.h {
                if Double(i % 7) / 7.0 < night { c.setRaw(rect.x + p.0, rect.y + p.1, color: sc) }
            }
        }
        // 太阳 / 月亮：按钟点沿一条弧走。太阳 6.5–18.5，月亮 19–5.5
        func arc(_ u: Double) -> (Int, Int) {   // u: 0…1
            let x = Int((2 + u * Double(rect.w - 9)).rounded())
            let y = Int((Double(rect.h) * 0.72 - sin(u * Double.pi) * Double(rect.h) * 0.55).rounded())
            return (x, y)
        }
        let sunU = (hour - 6.5) / 12.0
        if sunU > -0.04 && sunU < 1.04 {
            let (sx, sy) = arc(max(0, min(1, sunU)))
            let core = RGBA8(hex: 0xFFE27A), hi = RGBA8(hex: 0xFFF6C8), rim = RGBA8(hex: 0xF7B94A)
            let low = abs(sunU - 0.5) > 0.4   // 近地平线偏橙
            let coreC = low ? RGBA8(hex: 0xFFB463) : core
            for (dx, dy, k) in [(1, 0, 0), (2, 0, 0), (3, 0, 0), (0, 1, 0), (1, 1, 1), (2, 1, 1), (3, 1, 0), (4, 1, 0), (0, 2, 0), (1, 2, 1), (2, 2, 1), (3, 2, 0), (4, 2, 0),
                                (0, 3, 0), (1, 3, 0), (2, 3, 0), (3, 3, 0), (4, 3, 0), (1, 4, 2), (2, 4, 2), (3, 4, 2)] {
                let col = k == 1 ? hi : (k == 2 ? rim : coreC)
                if sx + dx >= 0 && sx + dx < rect.w && sy + dy >= 0 && sy + dy < rect.h { c.setRaw(rect.x + sx + dx, rect.y + sy + dy, color: col) }
            }
        }
        var moonU = (hour - 19.0) / 10.5          // 19:00 → 5:30 共 10.5 小时
        if hour < 12 { moonU = (hour + 5.0) / 10.5 }
        if night > 0.05 && moonU >= 0 && moonU <= 1 {
            let (mx, my) = arc(moonU)
            let body = RGBA8(hex: 0xF4EFD6), shade = RGBA8(hex: 0xC9C6B0)
            // 弯月：5×5，右侧被咬掉一块
            for (dx, dy, k) in [(1, 0, 0), (2, 0, 0), (0, 1, 0), (1, 1, 0), (0, 2, 0), (1, 2, 1), (0, 3, 0), (1, 3, 0), (2, 3, 1), (1, 4, 0), (2, 4, 0), (3, 4, 1)] {
                if mx + dx >= 0 && mx + dx < rect.w && my + dy >= 0 && my + dy < rect.h {
                    c.setRaw(rect.x + mx + dx, rect.y + my + dy, color: k == 1 ? shade : body)
                }
            }
        }
        // 云：每 3 秒往右挪 1 像素，循环
        let drift = Int((t / 3.0).rounded(.down))
        for (i, cl) in clouds.enumerated() {
            let shape = cloudShapes[cl.2]
            let span = rect.w + 14
            let x0 = ((cl.0 + drift + i * 3) % span) - 9
            for (yy, row) in shape.enumerated() { for (xx, ch) in row.enumerated() where ch == "#" {
                let px = x0 + xx, py = cl.1 + yy
                if px >= 0 && px < rect.w && py >= 0 && py < rect.h {
                    c.setRaw(rect.x + px, rect.y + py, color: yy == shape.count - 1 ? s.cloudSh : s.cloud)
                }
            } }
        }
    }
}
