import Foundation
import CoreGraphics
import ImageIO

public enum ExportError: Error, CustomStringConvertible {
    case destination(String), finalize(String)
    public var description: String {
        switch self { case .destination(let s): return "无法创建输出：\(s)"; case .finalize(let s): return "写出失败：\(s)" }
    }
}

public enum PNGExport {
    public static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ExportError.destination(url.path)
        }
        CGImageDestinationAddImage(d, image, nil)
        if !CGImageDestinationFinalize(d) { throw ExportError.finalize(url.path) }
    }
}

public enum GIFExport {
    /// 导出循环 GIF。delays 是每帧秒数（GIF 精度是 1/100 秒，会取整）。
    public static func write(frames: [CGImage], delays: [Double], to url: URL, loop: Bool = true) throws {
        precondition(!frames.isEmpty && frames.count == delays.count, "帧数和时长个数要一致")
        let w = try Writer(url: url, frameCount: frames.count, loop: loop)
        for (img, dl) in zip(frames, delays) { w.add(img, delay: dl) }
        try w.finish()
    }

    /// 一帧一帧写的 GIF 写入器：不用把所有帧都攥在内存里（1000 帧 × 2 MB）。创建时要给出总帧数。
    public final class Writer {
        let dest: CGImageDestination
        let url: URL
        public init(url: URL, frameCount: Int, loop: Bool = true) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let d = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frameCount, nil) else {
                throw ExportError.destination(url.path)
            }
            let fileProps: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: loop ? 0 : 1]]
            CGImageDestinationSetProperties(d, fileProps as CFDictionary)
            dest = d; self.url = url
        }
        public func add(_ img: CGImage, delay: Double) {
            let props: [String: Any] = [kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: max(0.02, (delay * 100).rounded() / 100),
            ]]
            CGImageDestinationAddImage(dest, img, props as CFDictionary)
        }
        public func finish() throws {
            if !CGImageDestinationFinalize(dest) { throw ExportError.finalize(url.path) }
            // ImageIO 写出的头是 GIF87a，但里面有 89a 才有的图形控制扩展（帧延迟）和循环扩展：严格的解析器会不认，头改成 89a
            if var data = try? Data(contentsOf: url), data.count > 6, data.prefix(6) == Data("GIF87a".utf8) {
                data.replaceSubrange(0..<6, with: Data("GIF89a".utf8))
                try data.write(to: url)
            }
        }
    }
}

/// 总表：把一堆（图, 标签）排成网格，棋盘格底，标签用苹方。
public enum ContactSheet {
    public struct Cell {
        public var image: CGImage
        public var label: String
        public init(image: CGImage, label: String) { self.image = image; self.label = label }
    }

    public static func render(cells: [Cell], columns: Int, cellSize: (w: Int, h: Int)? = nil, padding: Int = 10,
                              labelHeight: Int = 18, checker: Int = 8, title: String? = nil) -> CGImage? {
        guard !cells.isEmpty, columns > 0 else { return nil }
        let cw = cellSize?.w ?? (cells.map { $0.image.width }.max() ?? 1)
        let ch = cellSize?.h ?? (cells.map { $0.image.height }.max() ?? 1)
        let rows = (cells.count + columns - 1) / columns
        let titleH = title == nil ? 0 : 30
        let W = columns * (cw + padding) + padding
        let H = rows * (ch + labelHeight + padding) + padding + titleH
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let label = TextStyle(size: 11, color: RGBA8(0xE8, 0xE8, 0xEE))
        if let t = title, let ti = TextRenderer.shared.image(t, style: TextStyle(size: 16, color: RGBA8(0xFF, 0xFF, 0xFF), weight: .semibold), scale: 1) {
            ctx.draw(ti.image, in: CGRect(x: padding, y: H - 6 - Int(ti.size.height), width: Int(ti.size.width), height: Int(ti.size.height)))
        }
        for (i, c) in cells.enumerated() {
            let col = i % columns, row = i / columns
            let x0 = padding + col * (cw + padding)
            let yTop = titleH + padding + row * (ch + labelHeight + padding)
            let yBottom = H - yTop - ch                       // 该格图片区左下角（CG 坐标）
            // 棋盘格底
            let tile1 = CGColor(srgbRed: 0.30, green: 0.30, blue: 0.33, alpha: 1)
            let tile2 = CGColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 1)
            var ty = 0
            while ty < ch {
                var tx = 0
                while tx < cw {
                    ctx.setFillColor(((tx / checker + ty / checker) % 2 == 0) ? tile1 : tile2)
                    ctx.fill(CGRect(x: x0 + tx, y: yBottom + ty, width: min(checker, cw - tx), height: min(checker, ch - ty)))
                    tx += checker
                }
                ty += checker
            }
            let iw = c.image.width, ih = c.image.height
            ctx.draw(c.image, in: CGRect(x: x0 + (cw - iw) / 2, y: yBottom + (ch - ih) / 2, width: iw, height: ih))
            if let li = TextRenderer.shared.image(c.label, style: label, scale: 1, maxWidth: CGFloat(cw)) {
                ctx.draw(li.image, in: CGRect(x: x0, y: yBottom - labelHeight + 3, width: Int(li.size.width), height: Int(li.size.height)))
            }
        }
        return ctx.makeImage()
    }
}
