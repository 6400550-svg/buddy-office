import Foundation
import PixelKit

/// App 图标：铺满的圆角方形（macOS 26 以后旧式带边距的图标会被套上灰框），一间夜里的小办公室——
/// 亮着的显示器、背对你的小人、桌上的台灯。16 px 和 32 px 两个尺寸都是手工摆的像素；
/// 更大的尺寸（64…1024）按整数倍最近邻放大，所以放大后仍然是干净的大像素。
public enum AppIconArt {
    // MARK: 调色（直接 RGB，不走主调色板）
    static func C(_ hex: UInt32) -> RGBA8 { RGBA8(hex: hex) }
    static let wall0 = C(0x232852), wall1 = C(0x2B3160), wall2 = C(0x343B72), wall3 = C(0x3F4787)
    static let frame = C(0x14172E), frameHi = C(0x2C3258), screen = C(0x0D1125)
    static let cyan = C(0x6FE3FF), green = C(0x7DF0A0), amber = C(0xFFC857), pink = C(0xFF8FB8), white = C(0xF4F1E8), dim = C(0x4B5A8F)
    static let hair = C(0x6A4331), hairHi = C(0x91644A), hairSh = C(0x3F261B)
    static let tee = C(0xE05656), teeHi = C(0xF27B73), teeSh = C(0xA43A44), teeDk = C(0x7A2733)
    static let skin = C(0xE9B590), skinSh = C(0xC98F6E)
    static let deskTop = C(0xC99461), deskHi = C(0xDFAE7B), deskFace = C(0x8F5F3F), deskSh = C(0x6C4530), deskDk = C(0x4A2E22)
    static let lamp = C(0xFFB454), lampHi = C(0xFFE3A0), lampDk = C(0xC97A2E)
    static let keyboard = C(0xB9C2E6), keyboardSh = C(0x7F89B5)
    static let mug = C(0x7A5BD6), mugHi = C(0x9C82F0), mugSh = C(0x553B9E)

    /// 圆角方形蒙版：像素中心落在圆角内才保留（整数像素的圆弧）。
    static func maskOK(_ x: Int, _ y: Int, _ n: Int, _ r: Int) -> Bool {
        let px = Double(x) + 0.5, py = Double(y) + 0.5, N = Double(n), R = Double(r)
        let cx = min(max(px, R), N - R), cy = min(max(py, R), N - R)
        let dx = px - cx, dy = py - cy
        return dx * dx + dy * dy <= R * R
    }

    /// 圆角方形边缘的一圈斜面：左上的边提亮、右下的边压暗（1 像素），图标在浅色背景上也有清楚的边。
    static func bevel(_ c: Canvas, _ n: Int, _ r: Int) {
        func alpha(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n && (c.pixel(x, y) >> 24) != 0 }
        var edits: [(Int, Int, RGBA8)] = []
        for y in 0..<n { for x in 0..<n where alpha(x, y) {
            let p = c.pixel(x, y)
            let base = RGBA8(UInt8(p & 0xFF), UInt8((p >> 8) & 0xFF), UInt8((p >> 16) & 0xFF), 255)
            let up = !alpha(x, y - 1), left = !alpha(x - 1, y), down = !alpha(x, y + 1), right = !alpha(x + 1, y)
            if up || left { edits.append((x, y, base.mixed(with: RGBA8(255, 255, 255, 255), 0.16))) }
            else if down || right { edits.append((x, y, base.mixed(with: RGBA8(8, 10, 30, 255), 0.30))) }
        } }
        for (x, y, col) in edits { c.setRaw(x, y, color: col) }
    }

    // MARK: 32 × 32
    static func draw32() -> Canvas {
        let n = 32
        let c = Canvas(width: n, height: n)
        func px(_ x: Int, _ y: Int, _ col: RGBA8) { if x >= 0 && y >= 0 && x < n && y < n { c.setRaw(x, y, color: col) } }
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ col: RGBA8) { for j in y..<(y + h) { for i in x..<(x + w) { px(i, j, col) } } }
        // 墙：三档，档与档之间隔行抖动
        for y in 0..<n {
            let base: RGBA8 = y < 5 ? wall0 : (y < 11 ? wall1 : (y < 17 ? wall2 : wall3))
            for x in 0..<n { px(x, y, base) }
        }
        for (y, hi, lo) in [(5, wall1, wall0), (11, wall2, wall1), (17, wall3, wall2)] { for x in 0..<n { px(x, y, (x + y) % 2 == 0 ? hi : lo) } }
        // 显示器：外框 + 高光边 + 屏幕
        rect(6, 2, 20, 16, frame)
        rect(6, 2, 20, 1, frameHi); rect(6, 2, 1, 16, frameHi)
        rect(8, 4, 16, 12, screen)
        // 屏幕里的代码行
        func line(_ y: Int, _ x: Int, _ len: Int, _ col: RGBA8) { rect(9 + x, y, len, 1, col) }
        line(5, 0, 3, cyan); line(5, 4, 2, green); line(5, 7, 4, cyan)
        line(7, 2, 5, amber); line(7, 8, 3, white)
        line(9, 2, 3, pink); line(9, 6, 5, cyan); line(9, 12, 1, dim)
        line(11, 0, 4, green); line(11, 5, 3, dim)
        // 显示器光：屏幕下沿一圈淡淡的亮边落在墙上
        for x in 7..<25 { px(x, 18, (x % 2 == 0) ? wall3 : C(0x4C5798)) }
        // 支架
        rect(14, 18, 4, 2, frameHi); rect(11, 20, 10, 1, frameHi)
        // 台灯（右边）：灯罩 + 光圈（隔点抖动）
        for (dx, dy) in [(-3, -3), (-2, -4), (-1, -4), (0, -4), (1, -4), (2, -4), (3, -3), (-3, -2), (3, -2), (-2, -1), (2, -1)] where (dx + dy) % 2 == 0 { px(28 + dx, 15 + dy, C(0x59619F)) }
        rect(26, 13, 5, 2, lamp); px(25, 14, lampDk); px(31, 14, lampDk); rect(27, 12, 3, 1, lampHi)
        rect(28, 15, 1, 6, lampDk)
        // 桌面：一条亮边 + 桌面 + 桌沿
        rect(0, 21, n, 1, deskHi); rect(0, 22, n, 3, deskTop); rect(0, 25, n, 1, deskSh)
        rect(0, 26, n, 6, deskFace); rect(0, 26, n, 1, deskHi.mixed(with: deskFace, 0.5)); rect(0, 30, n, 2, deskSh)
        // 键盘、鼠标、杯子
        rect(8, 22, 12, 2, keyboard); for x in stride(from: 9, to: 19, by: 2) { px(x, 23, keyboardSh) }
        rect(22, 22, 2, 2, keyboard)
        rect(2, 19, 4, 5, mug); rect(2, 19, 4, 1, mugHi); rect(2, 23, 4, 1, mugSh); px(6, 20, mug); px(6, 21, mugSh)
        // 小人（背影）：头发圆顶 + 高光 + 描边 + 后颈 + T 恤肩膀
        func hairRow(_ y: Int, _ x0: Int, _ x1: Int) { rect(x0, y, x1 - x0 + 1, 1, hair) }
        let hs: [(Int, Int, Int)] = [(11, 13, 18), (12, 11, 20), (13, 10, 21), (14, 9, 22), (15, 9, 22), (16, 9, 22), (17, 9, 22), (18, 9, 22), (19, 10, 21), (20, 10, 21), (21, 11, 20), (22, 13, 18)]
        for (y, a, b) in hs { hairRow(y, a, b) }
        // 高光（左上）/ 阴影（右下）/ 描边
        for (y, a, b) in hs { px(a, y, hairSh); px(b, y, hairSh) }
        rect(13, 10, 6, 1, hairSh)                         // 顶上的描边
        for x in 12...19 { px(x, 22, hairSh) }
        for (x, y) in [(12, 12), (13, 12), (11, 13), (12, 13), (10, 14), (11, 14), (10, 15), (10, 16), (13, 11), (14, 11)] { px(x, y, hairHi) }
        for (x, y) in [(20, 17), (20, 18), (19, 19), (20, 19), (19, 20), (18, 21), (19, 21)] { px(x, y, hair.mixed(with: hairSh, 0.55)) }
        // 后颈
        rect(14, 23, 4, 1, skin); rect(14, 24, 4, 1, skinSh)
        // 肩膀 / T 恤
        let ts: [(Int, Int, Int)] = [(24, 11, 20), (25, 8, 23), (26, 6, 25), (27, 5, 26), (28, 5, 26), (29, 5, 26), (30, 5, 26), (31, 5, 26)]
        for (y, a, b) in ts { rect(a, y, b - a + 1, 1, tee); px(a, y, teeHi); px(b, y, teeSh) }
        rect(13, 24, 6, 1, teeSh)                          // 领口的阴影
        for y in 25...31 { px(6, y, teeHi) }
        for y in 26...31 { px(25, y, teeSh); px(24, y, teeSh) }
        rect(8, 27, 3, 1, teeHi); rect(14, 29, 5, 1, teeSh.mixed(with: tee, 0.5))   // 衣褶
        // 圆角方形蒙版（半径 7）
        for y in 0..<n { for x in 0..<n where !maskOK(x, y, n, 7) { c.setRaw(x, y, color: RGBA8(0, 0, 0, 0)) } }
        bevel(c, n, 7)
        return c
    }

    /// 16 × 16（不是缩小 32，是重新摆的像素：更少的线条、更大的块）
    static func draw16() -> Canvas {
        let n = 16
        let c = Canvas(width: n, height: n)
        func px(_ x: Int, _ y: Int, _ col: RGBA8) { if x >= 0 && y >= 0 && x < n && y < n { c.setRaw(x, y, color: col) } }
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ col: RGBA8) { for j in y..<(y + h) { for i in x..<(x + w) { px(i, j, col) } } }
        for y in 0..<n { let b: RGBA8 = y < 3 ? wall0 : (y < 6 ? wall1 : (y < 9 ? wall2 : wall3)); for x in 0..<n { px(x, y, b) } }
        // 显示器
        rect(3, 1, 10, 8, frame); rect(4, 2, 8, 6, screen)
        rect(4, 2, 3, 1, cyan); rect(8, 2, 2, 1, green)
        rect(5, 4, 3, 1, amber); rect(9, 4, 2, 1, pink)
        rect(4, 6, 2, 1, green); rect(7, 6, 3, 1, cyan)
        rect(7, 9, 2, 1, frameHi)
        // 桌子
        rect(0, 10, n, 1, deskHi); rect(0, 11, n, 2, deskTop); rect(0, 13, n, 3, deskFace); rect(0, 15, n, 1, deskSh)
        // 台灯
        rect(13, 6, 2, 1, lamp); px(14, 7, lampDk); px(14, 8, lampDk); px(13, 5, lampHi)
        // 小人
        rect(6, 6, 4, 1, hair); rect(5, 7, 6, 3, hair); rect(6, 10, 4, 1, hair)
        px(5, 7, hairHi); px(6, 6, hairHi); px(10, 9, hairSh); px(6, 10, hairSh); px(9, 10, hairSh); px(5, 9, hairSh); px(5, 8, hair)
        rect(7, 11, 2, 1, skinSh)
        rect(5, 12, 6, 1, tee); rect(3, 13, 10, 3, tee)
        px(3, 13, teeHi); px(3, 14, teeHi); rect(11, 13, 2, 3, teeSh); rect(7, 12, 2, 1, teeSh)
        for y in 0..<n { for x in 0..<n where !maskOK(x, y, n, 3) { c.setRaw(x, y, color: RGBA8(0, 0, 0, 0)) } }
        bevel(c, n, 3)
        return c
    }

    public static func canvas(size: Int) -> Canvas { size <= 16 ? draw16() : draw32() }
}
