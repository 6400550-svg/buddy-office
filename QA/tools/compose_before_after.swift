// 把「修复前 / 修复后」的 PNG 两两并排拼成一张对比图（每对一行，左边写编号和说明）。
// 用法：swift QA/tools/compose_before_after.swift <输出.png> <标题> <说明1> <前1.png> <后1.png> [<说明2> <前2.png> <后2.png> …]
// 只依赖 CoreGraphics / ImageIO / CoreText（不需要 AppKit），沙箱里也能跑。
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func drawText(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, maxWidth: CGFloat = 10_000, bold: Bool = false) -> CGFloat {
    let font = CTFontCreateWithName((bold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color]
    let astr = NSAttributedString(string: s, attributes: attrs)
    let setter = CTFramesetterCreateWithAttributedString(astr)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: x, y: y - 400, width: maxWidth, height: 400), transform: nil), nil)
    // 框架顶对齐 y：用行数估算高度
    let lines = CTFrameGetLines(frame) as! [CTLine]
    var h: CGFloat = 0
    for (i, line) in lines.enumerated() {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        ctx.textPosition = CGPoint(x: x, y: y - ascent - CGFloat(i) * (size * 1.35))
        CTLineDraw(line, ctx)
        h = CGFloat(i + 1) * size * 1.35
    }
    return h
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 5, (args.count - 2) % 3 == 0 else {
    FileHandle.standardError.write("用法：compose_before_after.swift 输出.png 标题 (说明 前.png 后.png)…\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[0], title = args[1]
struct Pair { var caption: String; var before: CGImage?; var after: CGImage? }
var pairs: [Pair] = []
var i = 2
while i + 2 < args.count + 0 {
    pairs.append(Pair(caption: args[i], before: loadImage(args[i + 1]), after: loadImage(args[i + 2])))
    i += 3
}

let colW: CGFloat = 640, gap: CGFloat = 16, capW: CGFloat = 200, margin: CGFloat = 20, headH: CGFloat = 64, labelH: CGFloat = 28
func scaled(_ im: CGImage?) -> CGSize {
    guard let im = im else { return CGSize(width: colW, height: 60) }
    let k = min(1.0, colW / CGFloat(im.width))
    return CGSize(width: CGFloat(im.width) * k, height: CGFloat(im.height) * k)
}
let rowHeights = pairs.map { max(scaled($0.before).height, scaled($0.after).height) + labelH + 18 }
let W = Int(margin * 2 + capW + colW * 2 + gap * 2), H = Int(headH + rowHeights.reduce(0, +) + margin)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let ink = CGColor(srgbRed: 0.12, green: 0.09, blue: 0.11, alpha: 1)
let red = CGColor(srgbRed: 0.75, green: 0.12, blue: 0.12, alpha: 1), green = CGColor(srgbRed: 0.10, green: 0.50, blue: 0.25, alpha: 1)
_ = drawText(ctx, title, x: margin, y: CGFloat(H) - 16, size: 20, color: ink, bold: true)
var y = CGFloat(H) - headH
for (n, p) in pairs.enumerated() {
    let rowH = rowHeights[n]
    _ = drawText(ctx, p.caption, x: margin, y: y - 6, size: 13, color: ink, maxWidth: capW - 12)
    let x1 = margin + capW, x2 = x1 + colW + gap
    _ = drawText(ctx, "修复前", x: x1, y: y - 2, size: 13, color: red, bold: true)
    _ = drawText(ctx, "修复后", x: x2, y: y - 2, size: 13, color: green, bold: true)
    for (im, x) in [(p.before, x1), (p.after, x2)] {
        let sz = scaled(im)
        let rect = CGRect(x: x, y: y - labelH - sz.height, width: sz.width, height: sz.height)
        if let im = im {
            ctx.interpolationQuality = .high
            ctx.draw(im, in: rect)
            ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 1)); ctx.setLineWidth(1); ctx.stroke(rect)
        } else {
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1)); ctx.fill(rect)
            _ = drawText(ctx, "（这种情况修复前根本没有画面）", x: x + 8, y: y - labelH - 8, size: 12, color: ink)
        }
    }
    y -= rowH
}
guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("写入 \(outPath) \(W)×\(H)")
