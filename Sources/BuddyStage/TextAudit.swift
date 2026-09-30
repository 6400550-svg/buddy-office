import Foundation
import CoreGraphics
import PixelKit
import BuddyCore
import BuddyArt

/// 文字审计（`buddyctl text-audit`）：按 CoreText 渲染出来的真实笔画（扫描 alpha，不是估算）检查一帧画面里的文字，8 类问题：
///  1 文字互相重叠（笔画像素相交，不是包围盒相交）
///  2 超出容器或被裁切（超出它该待的矩形 / 超出窗口 / 笔画碰到文字图片的边缘）
///  3 该省略没省略（自然宽度超过了可用宽度，却没有用「…」截断）
///  4 盖住脸、屏幕、气泡或别的卡片
///  5 字号小于 9 pt
///  6 对比度低于 4.5:1（文字色 vs 文字底下真实的画布像素）
///  7 没有对齐到整数像素（设备像素）
///  8 像素数字粘连（缺字形、贴边 / 出界、被人物盖住、两串数字贴在一起）
public enum TextAudit {
    public enum Kind: Int, CaseIterable, Sendable {
        case overlap = 1, clipped, ellipsis, covers, fontSize, contrast, alignment, pixelDigits
        public var title: String {
            switch self {
            case .overlap: return "文字互相重叠"
            case .clipped: return "超出容器或被裁切"
            case .ellipsis: return "该省略没省略"
            case .covers: return "盖住脸/屏幕/气泡/卡片"
            case .fontSize: return "字号小于 9 pt"
            case .contrast: return "对比度低于 4.5:1"
            case .alignment: return "没有对齐到整数像素"
            case .pixelDigits: return "像素数字粘连"
            }
        }
    }

    public struct Violation: Sendable, CustomStringConvertible {
        public var kind: Kind
        public var scene: String
        public var combo: String
        public var detail: String
        /// 出问题的地方（设备像素，左上原点，相对这一帧的视口）；没有就是 nil。
        public var rect: CGRect?
        /// 哪一类文字（TextItem.tag，像素字是 "pixel"，卡片和区域类是空）——报告里按它分组。
        public var tag: String = ""
        public var description: String {
            let at = rect.map { " @(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)))" } ?? ""
            return "[\(kind.rawValue)·\(kind.title)] \(scene) \(combo)：\(detail)\(at)"
        }
    }

    public struct Input {
        public var frame: Frame
        public var zoom: Int
        public var scale: Int
        public var regions: [AuditRegion] = []
        public var pixelDraws: [PixelFont.DrawRecord] = []
        public var scene: String
        public var combo: String
        /// 文字要求的最低对比度、最小字号（默认 4.5:1 和 9 pt）。
        public var minContrast = 4.5
        public var minFontSize: CGFloat = 9
        /// 测试用：换掉文字的摆放函数，检查「对齐」这一类能不能抓到没取整的摆放。
        public var place: ((TextItem, CGSize, IntRect, Int, Int) -> CGRect)? = nil
        public init(frame: Frame, zoom: Int, scale: Int, regions: [AuditRegion] = [], pixelDraws: [PixelFont.DrawRecord] = [], scene: String, combo: String) {
            self.frame = frame; self.zoom = zoom; self.scale = scale; self.regions = regions; self.pixelDraws = pixelDraws; self.scene = scene; self.combo = combo
        }
    }

    struct Placed {
        var i: Int
        var item: TextItem
        var ink: TextInk
        var origin: CGPoint          // 文字图片左上角（设备像素，相对视口）
        var rect: CGRect?            // 笔画的最小矩形（设备像素，相对视口）
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            let lx = x - Int(origin.x), ly = y - Int(origin.y)
            if lx < 0 || ly < 0 || lx >= ink.pixelWidth || ly >= ink.pixelHeight { return 0 }
            return ink.alpha[ly * ink.pixelWidth + lx]
        }
    }

    // MARK: 颜色

    static func linear(_ v: UInt8) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double { 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) }
    public static func contrastRatio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    /// 向下取整的整数除法：文字有一部分在窗口上边 / 左边外面时，设备像素坐标是负的，Swift 的 `/` 向零取整会把它映射到错的画布行（差一行）。
    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    // MARK: 检查

    public static func check(_ input: Input) -> [Violation] {
        let f = input.frame, vp = f.viewport
        let k = input.zoom * input.scale
        var out: [Violation] = []
        func add(_ kind: Kind, _ detail: String, _ rect: CGRect? = nil, tag: String = "") { out.append(Violation(kind: kind, scene: input.scene, combo: input.combo, detail: detail, rect: rect, tag: tag)) }
        func label(_ p: Placed) -> String { "「\(p.item.text.prefix(14))」\(p.item.tag.isEmpty ? "" : "(\(p.item.tag))")" }
        let place = input.place ?? { t, s, vp, z, sc in TextLayout.place(t, imageSize: s, viewport: vp, zoom: z, scale: sc) }

        // 把每段文字渲染出来并摆好
        var placed: [Placed] = []
        for (i, t) in f.texts.enumerated() {
            guard let ink = TextRenderer.shared.ink(t.text, style: t.style, scale: CGFloat(input.scale), maxWidth: t.maxWidth) else { continue }
            let pl = place(t, ink.image.size, vp, input.zoom, input.scale)
            var r: CGRect? = nil
            if let b = ink.bbox { r = CGRect(x: pl.minX + Double(b.x), y: pl.minY + Double(b.y), width: Double(b.w), height: Double(b.h)) }
            placed.append(Placed(i: i, item: t, ink: ink, origin: pl.origin, rect: r))
        }
        let viewDev = CGRect(x: 0, y: 0, width: vp.w * k, height: vp.h * k)

        for p in placed {
            // 5. 字号
            if p.item.style.size < input.minFontSize { add(.fontSize, "\(label(p)) 字号 \(p.item.style.size) pt < \(input.minFontSize) pt", p.rect, tag: p.item.tag) }
            // 7. 对齐到整数设备像素：位置、图片大小 × scale 都必须是整数
            let sizeDev = (Double(p.ink.image.size.width) * Double(input.scale), Double(p.ink.image.size.height) * Double(input.scale))
            let frac = { (v: Double) in abs(v - v.rounded()) > 1e-6 }
            if frac(Double(p.origin.x)) || frac(Double(p.origin.y)) || frac(sizeDev.0) || frac(sizeDev.1) {
                add(.alignment, "\(label(p)) 位置 (\(p.origin.x), \(p.origin.y)) 大小 (\(sizeDev.0), \(sizeDev.1)) 设备像素不是整数", p.rect, tag: p.item.tag)
            }
            guard let r = p.rect else { continue }
            // 2. 被文字图片自己的边界裁掉
            if p.ink.touchesBorder { add(.clipped, "\(label(p)) 笔画碰到了文字图片的边缘（字形被裁）", r, tag: p.item.tag) }
            // 2. 超出窗口：桌牌 / 牌子在窗口里只露出一部分（世界比窗口大，镜头在滚动）是正常的，只检查「桌牌整块都在窗口里、字却不在」和没有容器的文字；
            //    悬停卡片必须整张都在窗口里。
            var checkViewport = true
            if let c = p.item.container, p.item.tag.hasPrefix("plate") || p.item.tag == "sign" {
                checkViewport = c.x >= vp.x && c.y >= vp.y && c.maxX <= vp.maxX && c.maxY <= vp.maxY
            }
            if p.item.tag.hasPrefix("card"), let c = p.item.container, !(c.x >= vp.x && c.y >= vp.y && c.maxX <= vp.maxX && c.maxY <= vp.maxY) {
                add(.clipped, "悬停卡片 \(c.x),\(c.y) \(c.w)×\(c.h) 没有整张显示在窗口 \(vp.x),\(vp.y) \(vp.w)×\(vp.h) 里", r, tag: p.item.tag)
            }
            if checkViewport, r.minX < viewDev.minX - 0.5 || r.minY < viewDev.minY - 0.5 || r.maxX > viewDev.maxX + 0.5 || r.maxY > viewDev.maxY + 0.5 {
                add(.clipped, "\(label(p)) 超出了窗口 / 画面（笔画 \(fmt(r)) 不在 \(fmt(viewDev)) 里）", r, tag: p.item.tag)
            }
            // 2. 超出容器（容器四周各留 1 个美术像素给边框）
            if let c = p.item.container {
                let inner = CGRect(x: (c.x - vp.x + 1) * k, y: (c.y - vp.y + 1) * k, width: max(0, c.w - 2) * k, height: max(0, c.h - 2) * k)
                if r.minX < inner.minX - 0.5 || r.minY < inner.minY - 0.5 || r.maxX > inner.maxX + 0.5 || r.maxY > inner.maxY + 0.5 {
                    add(.clipped, "\(label(p)) 超出了容器（笔画 \(fmt(r)) 不在容器内部 \(fmt(inner)) 里）", r, tag: p.item.tag)
                }
            }
            // 3. 该省略没省略：可用宽度 = maxWidth（有的话）或容器内部宽度
            var limit: CGFloat = p.item.maxWidth
            if limit <= 0, let c = p.item.container { limit = CGFloat(max(0, c.w - 2) * input.zoom) }
            if limit > 0 {
                let natural = TextRenderer.shared.naturalWidth(p.item.text, style: p.item.style)
                if natural > limit + 0.5 && !p.ink.image.truncated {
                    add(.ellipsis, "\(label(p)) 自然宽度 \(Int(natural)) pt > 可用宽度 \(Int(limit)) pt，却没有用「…」截断", r, tag: p.item.tag)
                }
            }
            // 6. 对比度：文字色 vs 文字底下真实的画布像素（只看笔画核心，alpha ≥ 200）
            let tc = p.item.style.color
            let lt = luminance(tc.r, tc.g, tc.b)
            var total = 0, bad = 0
            var worst = Double.infinity
            let canvas = f.canvas
            for dy in Int(r.minY)..<Int(r.maxY) { for dx in Int(r.minX)..<Int(r.maxX) where p.alpha(dx, dy) >= 200 {
                let ax = vp.x + floorDiv(dx, k), ay = vp.y + floorDiv(dy, k)
                guard ax >= 0, ay >= 0, ax < canvas.width, ay < canvas.height else { continue }
                let px = canvas.rgba[ay * canvas.width + ax]
                let a = Double((px >> 24) & 0xFF)
                guard a > 0 else { continue }
                // 预乘 → 直通
                let rr = UInt8(min(255, Double(px & 0xFF) * 255 / a)), gg = UInt8(min(255, Double((px >> 8) & 0xFF) * 255 / a)), bb = UInt8(min(255, Double((px >> 16) & 0xFF) * 255 / a))
                let cr = contrastRatio(lt, luminance(rr, gg, bb))
                total += 1
                if cr < input.minContrast { bad += 1 }
                worst = min(worst, cr)
            } }
            if total > 0 && Double(bad) / Double(total) > 0.10 {
                add(.contrast, "\(label(p)) 对比度最差 \(String(format: "%.2f", worst)):1 < \(input.minContrast):1（\(bad)/\(total) 个笔画像素不达标）", r, tag: p.item.tag)
            }
        }

        // 1. 文字互相重叠：包围盒相交再逐像素比 alpha
        for a in 0..<placed.count { for b in (a + 1)..<max(a + 1, placed.count) {
            guard let ra = placed[a].rect, let rb = placed[b].rect, let inter = optionalIntersection(ra, rb) else { continue }
            var hit = 0
            for y in Int(inter.minY)..<Int(inter.maxY) { for x in Int(inter.minX)..<Int(inter.maxX) where placed[a].alpha(x, y) >= 64 && placed[b].alpha(x, y) >= 64 { hit += 1 } }
            if hit > 0 { add(.overlap, "\(label(placed[a])) 和 \(label(placed[b])) 有 \(hit) 个笔画像素重叠", inter, tag: placed[a].item.tag + "×" + placed[b].item.tag) }
        } }

        // 4. 盖住脸 / 屏幕 / 气泡 / 别的卡片
        func dev(_ r: IntRect) -> CGRect { CGRect(x: (r.x - vp.x) * k, y: (r.y - vp.y) * k, width: r.w * k, height: r.h * k) }
        for p in placed {
            guard let r = p.rect else { continue }
            let isLabel = p.item.tag.hasPrefix("plate") || p.item.tag == "sign"
            for reg in input.regions {
                let applies: Bool
                switch reg.kind {
                case .face, .screen, .bubble: applies = isLabel
                case .card: applies = isLabel                     // 桌牌 / 牌子的字不许浮在悬停卡片上
                }
                guard applies, let inter = optionalIntersection(r, dev(reg.rect)) else { continue }
                var hit = 0
                for y in Int(inter.minY)..<Int(inter.maxY) { for x in Int(inter.minX)..<Int(inter.maxX) where p.alpha(x, y) >= 64 { hit += 1 } }
                if hit > 0 { add(.covers, "\(label(p)) 盖住了座位 \(reg.seat) 的\(regionName(reg.kind))（\(hit) 个笔画像素）", inter, tag: p.item.tag + "→" + reg.kind.rawValue) }
            }
        }
        // 悬停卡片本身不许盖住被悬停那个人的头 / 屏幕 / 气泡
        for card in input.regions where card.kind == .card {
            for reg in input.regions where reg.seat == card.seat && reg.kind != .card {
                if let inter = card.rect.intersection(reg.rect) {
                    add(.covers, "悬停卡片盖住了座位 \(card.seat) 自己的\(regionName(reg.kind))（\(inter.w)×\(inter.h) 像素）", dev(inter), tag: "card→" + reg.kind.rawValue)
                }
            }
        }

        // 8. 像素数字
        let own = ObjectIdentifier(f.canvas)
        let draws = input.pixelDraws.filter { $0.canvasID == own }
        for d in draws {
            let r = d.rect
            let name = "像素字「\(d.text)」(\(d.font))"
            if d.missingGlyph { add(.pixelDigits, "\(name) 有字符没有字形（落到了「?」占位字形）", dev(r), tag: "pixel") }
            if d.spacing < 1 { add(.pixelDigits, "\(name) 字距 \(d.spacing) < 1 像素，字和字粘在一起", dev(r), tag: "pixel") }
            if let c = d.container {
                let inner = c.insetBy(1)
                if r.x < inner.x || r.y < inner.y || r.maxX > inner.maxX || r.maxY > inner.maxY {
                    add(.pixelDigits, "\(name) \(r.x),\(r.y) \(r.w)×\(r.h) 贴边 / 超出容器 \(c.x),\(c.y) \(c.w)×\(c.h)（四周要留 1 像素）", dev(r), tag: "pixel:" + d.text)
                }
            }
            // 被后画的东西（人、气泡……）盖住：写下的像素在最终画面里的调色板索引变了。悬停卡片盖住是临时的、正常的，不算。
            var covered = 0
            for px in d.pixels where px.x >= 0 && px.y >= 0 && px.x < f.canvas.width && px.y < f.canvas.height {
                if f.canvas.idx[px.y * f.canvas.width + px.x] != px.idx, !input.regions.contains(where: { $0.kind == .card && $0.rect.contains(px.x, px.y) }) { covered += 1 }
            }
            if covered > 0 { add(.pixelDigits, "\(name) 被后画的东西（人物 / 气泡…）盖住了 \(covered)/\(d.pixels.count) 个像素", dev(r), tag: "pixel:" + d.text) }
        }
        for a in 0..<draws.count { for b in (a + 1)..<max(a + 1, draws.count) {
            let ra = draws[a].rect.insetBy(-1), rb = draws[b].rect
            if ra.intersection(rb) != nil { add(.pixelDigits, "像素字「\(draws[a].text)」和「\(draws[b].text)」贴在一起（间隔 < 1 像素）", dev(draws[a].rect), tag: "pixel:" + draws[a].text) }
        } }
        return out
    }

    static func regionName(_ k: AuditRegion.Kind) -> String {
        switch k { case .face: return "脸"; case .screen: return "屏幕"; case .bubble: return "气泡"; case .card: return "悬停卡片" }
    }
    static func fmt(_ r: CGRect) -> String { "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))" }
    static func optionalIntersection(_ a: CGRect, _ b: CGRect) -> CGRect? {
        let r = a.intersection(b)
        return r.isNull || r.width <= 0 || r.height <= 0 ? nil : r
    }
}
