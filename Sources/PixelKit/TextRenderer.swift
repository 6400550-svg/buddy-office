import Foundation
import CoreGraphics
import CoreText

public enum FontWeightKind: Int, Sendable { case regular, medium, semibold }

/// 文字样式（点为单位）。
public struct TextStyle: Hashable, Sendable {
    public var size: CGFloat
    public var color: RGBA8
    public var weight: FontWeightKind
    public init(size: CGFloat, color: RGBA8, weight: FontWeightKind = .regular) {
        self.size = size; self.color = color; self.weight = weight
    }
}

public struct TextImage: @unchecked Sendable {
    public let image: CGImage
    /// 文字盒的大小（点）。
    public let size: CGSize
    public let scale: CGFloat
    /// 太宽、被 maxWidth 用省略号截断了。
    public let truncated: Bool
}

/// text-audit 用：一段文字真正画出来的笔画（按 CoreText 渲染出的图片扫描 alpha，不是估算）。
public struct TextInk: @unchecked Sendable {
    public let image: TextImage
    public let pixelWidth: Int, pixelHeight: Int
    /// alpha，行优先（宽 pixelWidth、高 pixelHeight，左上原点）。
    public let alpha: [UInt8]
    /// 有笔画的最小矩形（图片坐标，设备像素）；没有任何笔画时为 nil。
    public let bbox: IntRect?
    /// 笔画碰到了图片的最外一圈像素：字形被图片的边界裁掉了（或者刚好贴边）。
    public let touchesBorder: Bool
}

/// 用 CoreText + 系统苹方，把中文按设备分辨率渲染成 CGImage 并缓存。
/// 无头快照和窗口里的文字层用的是同一个函数，所以两边看到的字完全一样。
public final class TextRenderer: @unchecked Sendable {
    public static let shared = TextRenderer()
    private struct Key: Hashable { var text: String; var style: TextStyle; var scale: CGFloat; var maxWidth: CGFloat }
    private var cache: [Key: TextImage] = [:]
    private var order: [Key] = []
    private var sizes: [Key: CGSize] = [:]
    private let lock = NSLock()
    private let limit = 600

    func font(_ style: TextStyle) -> CTFont {
        let psName: String
        switch style.weight {
        case .regular: psName = "PingFangSC-Regular"
        case .medium: psName = "PingFangSC-Medium"
        case .semibold: psName = "PingFangSC-Semibold"
        }
        let f = CTFontCreateWithName(psName as CFString, style.size, nil)
        // 万一系统没有苹方，回退到系统 UI 字体（保证中文能显示）
        if (CTFontCopyFamilyName(f) as String).contains("PingFang") { return f }
        return CTFontCreateUIFontForLanguage(.system, style.size, "zh-Hans" as CFString) ?? f
    }

    private func makeLine(_ text: String, style: TextStyle, maxWidth: CGFloat) -> (CTLine, CGFloat, CGFloat, CGFloat, Bool) {
        let f = font(style)
        let cg = CGColor(srgbRed: CGFloat(style.color.r) / 255, green: CGFloat(style.color.g) / 255,
                         blue: CGFloat(style.color.b) / 255, alpha: CGFloat(style.color.a) / 255)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg,
        ]
        let astr = NSMutableAttributedString(string: text, attributes: attrs)
        // emoji 缩小到 0.78 倍：系统回退到 Apple Color Emoji 时，同样的字号下它的字形比苹方高出一截（上下各多出 1–2 pt），
        // 会顶出桌牌 / 卡片的上下边（text-audit 量出来的）。缩小之后笔画落在苹方的行盒里。
        var emojiFont: CTFont? = nil
        var idx = 0
        for ch in text {
            let len = String(ch).utf16.count
            if ch.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) || ch.unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
                if emojiFont == nil { emojiFont = CTFontCreateWithName("AppleColorEmoji" as CFString, style.size * 0.78, nil) }
                astr.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: emojiFont!, range: NSRange(location: idx, length: len))
            }
            idx += len
        }
        var line = CTLineCreateWithAttributedString(astr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        var w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var truncated = false
        if maxWidth > 0, w > maxWidth {
            let tokenAttrs = attrs
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: tokenAttrs))
            if let t = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) {
                line = t
                w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                truncated = true
            }
        }
        // 行高只按主字体（苹方）算：字符串里有 emoji / 符号时，系统会回退到别的字体，它们的 ascent / descent 更大，
        // 用整行的数值会把基线整体往下挪、盖到下面一行文字上。回退字体的字形多出来的一点点会被图片边缘裁掉（emoji 略小一圈，看不出来）。
        ascent = CTFontGetAscent(f); descent = CTFontGetDescent(f)
        return (line, w, ascent, descent, truncated)
    }

    /// 文字盒大小（点）。maxWidth > 0 时按省略号截断后的宽度。
    public func measure(_ text: String, style: TextStyle, maxWidth: CGFloat = 0) -> CGSize {
        let key = Key(text: text, style: style, scale: 0, maxWidth: maxWidth)
        lock.lock()
        if let c = sizes[key] { lock.unlock(); return c }
        lock.unlock()
        let (_, w, a, d, _) = makeLine(text, style: style, maxWidth: maxWidth)
        let out = CGSize(width: ceil(w), height: ceil(a + d))
        lock.lock()
        if sizes.count > 4000 { sizes.removeAll(keepingCapacity: true) }      // 文案是有限的一批；万一失控就整个丢掉重来
        sizes[key] = out
        lock.unlock()
        return out
    }

    /// 这段文字的自然宽度（点，不截断）。
    public func naturalWidth(_ text: String, style: TextStyle) -> CGFloat { measure(text, style: style, maxWidth: 0).width }

    /// text-audit 用：渲染出图片，再扫描 alpha 得到真正的笔画范围（笔画 = alpha ≥ 32 的像素）。
    public func ink(_ text: String, style: TextStyle, scale: CGFloat, maxWidth: CGFloat = 0) -> TextInk? {
        guard let ti = image(text, style: style, scale: scale, maxWidth: maxWidth) else { return nil }
        let w = ti.image.width, h = ti.image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(ti.image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // CGContext 的数据是左上原点（第 0 行 = 图片最上面一行），和 CGImage 一致
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        var border = false
        for y in 0..<h { for x in 0..<w where buf[y * w + x] >= 32 {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 { border = true }
        } }
        let bbox: IntRect? = x1 >= 0 ? IntRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1) : nil
        return TextInk(image: ti, pixelWidth: w, pixelHeight: h, alpha: buf, bbox: bbox, touchesBorder: border)
    }

    public func image(_ text: String, style: TextStyle, scale: CGFloat, maxWidth: CGFloat = 0) -> TextImage? {
        guard !text.isEmpty else { return nil }
        let key = Key(text: text, style: style, scale: scale, maxWidth: maxWidth)
        lock.lock()
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        let (line, w, ascent, descent, truncated) = makeLine(text, style: style, maxWidth: maxWidth)
        let pw = max(1, Int(ceil(w * scale)) + 2), ph = max(1, Int(ceil((ascent + descent) * scale)) + 2)
        // BGRA 预乘 + sRGB：Core Animation 直接使用这种格式，不用每次换算
        guard let cs = Canvas.sRGB,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(false); ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(false); ctx.setShouldSubpixelPositionFonts(false)
        ctx.scaleBy(x: scale, y: scale)
        ctx.textPosition = CGPoint(x: 1 / scale, y: descent + 1 / scale)
        CTLineDraw(line, ctx)
        guard let img = ctx.makeImage() else { return nil }
        let out = TextImage(image: img, size: CGSize(width: CGFloat(pw) / scale, height: CGFloat(ph) / scale), scale: scale, truncated: truncated)
        lock.lock()
        cache[key] = out; order.append(key)
        if order.count > limit { let k = order.removeFirst(); cache.removeValue(forKey: k) }
        lock.unlock()
        return out
    }
}
