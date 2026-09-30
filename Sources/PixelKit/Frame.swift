import Foundation
import CoreGraphics

public enum TextAlign: Sendable { case left, center, right }

/// 叠在像素画布上的一段清晰文字（中文用苹方）。位置用美术像素表示（画布坐标）。
public struct TextItem: Sendable {
    public var text: String
    public var style: TextStyle
    public var x: Double
    public var y: Double
    public var align: TextAlign
    /// 最大宽度（点）；超出用省略号。0 = 不限。
    public var maxWidth: CGFloat
    /// 这段文字应该待在哪个矩形里（美术像素，和 x / y 同一个坐标系；含边框）。只给 text-audit 检查用，不影响出图。
    public var container: IntRect?
    /// 这段文字是什么（"plate.title" / "plate.status" / "sign" / "card" …），text-audit 报告和规则匹配用。
    public var tag: String
    public init(_ text: String, style: TextStyle, x: Double, y: Double, align: TextAlign = .left, maxWidth: CGFloat = 0,
                container: IntRect? = nil, tag: String = "") {
        self.text = text; self.style = style; self.x = x; self.y = y; self.align = align; self.maxWidth = maxWidth
        self.container = container; self.tag = tag
    }
}

/// 一段文字在设备像素里的位置：窗口（PixelView）、无头出图（FrameRenderer）、text-audit 三处共用这一个函数，
/// 所以审计看到的就是屏幕上真实的位置。x / y 都取整到设备像素（文字不会落在半个像素上而发虚）。
public enum TextLayout {
    /// - Returns: 设备像素，左上原点；宽高 = 文字图片的宽高（点）× scale。
    public static func place(_ t: TextItem, imageSize size: CGSize, viewport vp: IntRect, zoom: Int, scale: Int) -> CGRect {
        var xPt = (t.x - Double(vp.x)) * Double(zoom)
        let yPt = (t.y - Double(vp.y)) * Double(zoom)
        switch t.align {
        case .left: break
        case .center: xPt -= Double(size.width) / 2
        case .right: xPt -= Double(size.width)
        }
        let s = Double(scale)
        return CGRect(x: (xPt * s).rounded(), y: (yPt * s).rounded(), width: Double(size.width) * s, height: Double(size.height) * s)
    }
}

/// 一帧完整画面：像素画布 + 文字层。窗口和无头快照都从它出图。
public struct Frame: @unchecked Sendable {
    public let canvas: Canvas
    public var viewport: IntRect
    public var texts: [TextItem]
    /// 画布内容和上一帧相比有没有变过（false = 逐像素相同，显示层可以跳过哈希和出图）。默认 true（不知道就当变了）。
    public var canvasChanged = true
    /// 场景是不是明确知道「变了 / 没变」（局部重绘的场景知道；工具卡片这类不知道，显示层要自己哈希比较）。
    public var changeKnown = false
    public init(canvas: Canvas, viewport: IntRect? = nil, texts: [TextItem] = []) {
        self.canvas = canvas; self.viewport = viewport ?? canvas.bounds; self.texts = texts
    }
}

public enum FrameRenderer {
    /// 合成成一张位图：先把画布按整数倍最近邻放大，再把文字按设备分辨率贴上去。
    /// - zoom：1 个美术像素 = zoom 个点；scale：1 点 = scale 个设备像素（Retina = 2）。
    /// - background：放在最底下的底色（透明场景预览时用）。
    public static func render(_ frame: Frame, zoom: Int, scale: Int = 1, background: RGBA8? = nil) -> CGImage? {
        let vp = frame.viewport
        let k = zoom * scale
        let W = vp.w * k, H = vp.h * k
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = frame.canvas.makeCGImage(crop: vp) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        if let bg = background {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: W, height: H))
        drawTexts(frame.texts, into: ctx, viewport: vp, zoom: zoom, scale: scale, height: H)
        return ctx.makeImage()
    }

    static func drawTexts(_ texts: [TextItem], into ctx: CGContext, viewport vp: IntRect, zoom: Int, scale: Int, height H: Int) {
        ctx.setShouldAntialias(true)
        for t in texts {
            guard let ti = TextRenderer.shared.image(t.text, style: t.style, scale: CGFloat(scale), maxWidth: t.maxWidth) else { continue }
            let p = TextLayout.place(t, imageSize: ti.size, viewport: vp, zoom: zoom, scale: scale)
            let rect = CGRect(x: p.minX, y: Double(H) - p.minY - p.height, width: p.width, height: p.height)      // CGContext 的原点在左下
            ctx.draw(ti.image, in: rect)
        }
    }
}
