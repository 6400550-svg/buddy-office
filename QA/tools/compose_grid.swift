// 把一批 PNG 拼成一张总览图（网格，每格下面写说明）。
// 用法：swift QA/tools/compose_grid.swift <输出.png> <标题> <列数> <格宽> <说明1> <图1.png> [<说明2> <图2.png> …]
// 只依赖 CoreGraphics / ImageIO / CoreText。
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func drawText(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, maxWidth: CGFloat, bold: Bool = false) {
    let font = CTFontCreateWithName((bold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color]
    let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: x, y: y - 200, width: maxWidth, height: 200), transform: nil), nil)
    for (i, line) in (CTFrameGetLines(frame) as! [CTLine]).enumerated() {
        var ascent: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &d, &l)
        ctx.textPosition = CGPoint(x: x, y: y - ascent - CGFloat(i) * size * 1.35)
        CTLineDraw(line, ctx)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 6, (args.count - 4) % 2 == 0, let cols = Int(args[2]), let cellW = Double(args[3]) else {
    FileHandle.standardError.write("用法：compose_grid.swift 输出.png 标题 列数 格宽 (说明 图.png)…\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[0], title = args[1]
var items: [(String, CGImage?)] = []
var i = 4
while i + 1 < args.count { items.append((args[i], loadImage(args[i + 1]))); i += 2 }

let cw = CGFloat(cellW), gap: CGFloat = 14, margin: CGFloat = 18, headH: CGFloat = 54, capH: CGFloat = 40
func size(_ im: CGImage?) -> CGSize {
    guard let im = im else { return CGSize(width: cw, height: 60) }
    let k = cw / CGFloat(im.width)
    return CGSize(width: cw, height: CGFloat(im.height) * k)
}
let rows = (items.count + cols - 1) / cols
var rowH: [CGFloat] = []
for r in 0..<rows { rowH.append(items[(r * cols)..<min(items.count, (r + 1) * cols)].map { size($0.1).height }.max()! + capH + gap) }
let W = Int(margin * 2 + CGFloat(cols) * cw + CGFloat(cols - 1) * gap), H = Int(headH + rowH.reduce(0, +) + margin)
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let ink = CGColor(srgbRed: 0.12, green: 0.09, blue: 0.11, alpha: 1)
drawText(ctx, title, x: margin, y: CGFloat(H) - 14, size: 18, color: ink, maxWidth: CGFloat(W) - 2 * margin, bold: true)
var y = CGFloat(H) - headH
for r in 0..<rows {
    for c in 0..<cols {
        let idx = r * cols + c
        guard idx < items.count else { break }
        let x = margin + CGFloat(c) * (cw + gap)
        let sz = size(items[idx].1)
        let rect = CGRect(x: x, y: y - sz.height, width: sz.width, height: sz.height)
        if let im = items[idx].1 { ctx.interpolationQuality = .high; ctx.draw(im, in: rect) }
        else { ctx.setFillColor(CGColor(gray: 0.88, alpha: 1)); ctx.fill(rect) }
        ctx.setStrokeColor(CGColor(gray: 0.72, alpha: 1)); ctx.setLineWidth(1); ctx.stroke(rect)
        drawText(ctx, items[idx].0, x: x, y: y - sz.height - 4, size: 11, color: ink, maxWidth: cw)
    }
    y -= rowH[r]
}
guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("写入 \(outPath) \(W)×\(H)")
