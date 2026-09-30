import Foundation
import CoreGraphics

/// 像素画布：三张同尺寸的平面 ——
///   rgba：预乘 RGBA（内存顺序 R,G,B,A），
///   idx ：这个像素来自哪个主调色板索引（16 位；0 = 没画过；灯光、光晕的二次着色要用），
///   ids ：对象 ID 缓冲（命中测试、闪烁扫描按对象检查都靠它；0 = 不属于任何对象）。
/// 全部整数坐标，没有任何亚像素或缩放：所以同样的输入永远得到逐像素相同的输出。
public final class Canvas: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let rgba: UnsafeMutablePointer<UInt32>
    public let idx: UnsafeMutablePointer<UInt16>
    public let ids: UnsafeMutablePointer<UInt16>
    public var count: Int { width * height }
    /// 剪裁矩形：之后所有绘制（精灵、图元、光圈）都只落在这个矩形里；默认是整张画布。
    /// 局部重绘用它：把「这一小块」还原成背景，再把碰到它的东西按原来的顺序重画一遍，结果和整张重画逐像素相同。
    public private(set) var clipX0 = 0, clipY0 = 0, clipX1: Int, clipY1: Int
    public var clipRect: IntRect { IntRect(clipX0, clipY0, max(0, clipX1 - clipX0), max(0, clipY1 - clipY0)) }
    /// 设置剪裁（nil = 整张）。返回旧的剪裁，方便还原。
    @discardableResult
    public func setClip(_ r: IntRect?) -> IntRect {
        let old = clipRect
        if let r = r, let c = r.intersection(bounds) { clipX0 = c.x; clipY0 = c.y; clipX1 = c.maxX; clipY1 = c.maxY }
        else if r != nil { clipX0 = 0; clipY0 = 0; clipX1 = 0; clipY1 = 0 }
        else { clipX0 = 0; clipY0 = 0; clipX1 = width; clipY1 = height }
        return old
    }
    /// 在剪裁 r 之内执行 body，结束后还原。
    public func withClip<T>(_ r: IntRect, _ body: () throws -> T) rethrows -> T {
        let old = setClip(r)
        defer { setClip(old) }
        return try body()
    }
    /// 这个矩形有没有可能画到东西（和当前剪裁相交）。局部重绘时用它跳过不相干的工位。
    @inline(__always) public func mayTouch(_ r: IntRect) -> Bool {
        r.x < clipX1 && r.maxX > clipX0 && r.y < clipY1 && r.maxY > clipY0
    }

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "画布尺寸必须为正")
        self.width = width; self.height = height
        clipX1 = width; clipY1 = height
        let n = width * height
        rgba = .allocate(capacity: n); rgba.initialize(repeating: 0, count: n)
        idx = .allocate(capacity: n); idx.initialize(repeating: 0, count: n)
        ids = .allocate(capacity: n); ids.initialize(repeating: 0, count: n)
    }
    deinit { rgba.deallocate(); idx.deallocate(); ids.deallocate() }

    public var bounds: IntRect { IntRect(0, 0, width, height) }

    public func clear() {
        rgba.update(repeating: 0, count: count); idx.update(repeating: 0, count: count); ids.update(repeating: 0, count: count)
    }
    /// 整张铺一个颜色（不透明底，比如窗口底色）。
    public func fillAll(color: RGBA8, master: UInt16 = 0) {
        rgba.update(repeating: color.packed, count: count); idx.update(repeating: master, count: count)
        ids.update(repeating: 0, count: count)
    }
    /// 三个平面整块复制（静态背景缓存 → 工作画布）。
    public func copy(from o: Canvas) {
        precondition(o.width == width && o.height == height, "尺寸不一致")
        rgba.update(from: o.rgba, count: count); idx.update(from: o.idx, count: count); ids.update(from: o.ids, count: count)
    }

    /// 只清空一块区域（没有静态背景的画布，局部重绘的第一步）。
    public func clearRegion(_ rect: IntRect) {
        guard let r = rect.intersection(bounds) else { return }
        for y in r.y..<r.maxY {
            let i = y * width + r.x
            (rgba + i).update(repeating: 0, count: r.w); (idx + i).update(repeating: 0, count: r.w); (ids + i).update(repeating: 0, count: r.w)
        }
    }
    /// 只还原一块区域（局部重绘的第一步：把这块地方恢复成静态背景）。
    public func copyRegion(from o: Canvas, rect: IntRect) {
        precondition(o.width == width && o.height == height, "尺寸不一致")
        guard let r = rect.intersection(bounds) else { return }
        for y in r.y..<r.maxY {
            let i = y * width + r.x
            (rgba + i).update(from: o.rgba + i, count: r.w)
            (idx + i).update(from: o.idx + i, count: r.w)
            (ids + i).update(from: o.ids + i, count: r.w)
        }
    }

    // MARK: 单点
    @inline(__always) public func pixel(_ x: Int, _ y: Int) -> UInt32 {
        (x >= 0 && y >= 0 && x < width && y < height) ? rgba[y * width + x] : 0
    }
    @inline(__always) public func objectID(_ x: Int, _ y: Int) -> UInt16 {
        (x >= 0 && y >= 0 && x < width && y < height) ? ids[y * width + x] : 0
    }
    @inline(__always) public func masterIndex(_ x: Int, _ y: Int) -> UInt16 {
        (x >= 0 && y >= 0 && x < width && y < height) ? idx[y * width + x] : 0
    }
    @inline(__always) public func set(_ x: Int, _ y: Int, value v: UInt8, style: Resolved, id: UInt16 = 0) {
        guard v != 0, x >= clipX0, y >= clipY0, x < clipX1, y < clipY1 else { return }
        let i = y * width + x
        rgba[i] = style.useB(x: x, y: y) ? style.b[Int(v)] : style.a[Int(v)]
        idx[i] = style.master[Int(v)]
        if id != 0 { ids[i] = id }
    }
    /// 直接写一个已经算好的像素（预乘 RGBA + 主调色板索引），受剪裁约束。
    @inline(__always) public func setPixel(_ x: Int, _ y: Int, rgba p: UInt32, master m: UInt16) {
        guard x >= clipX0, y >= clipY0, x < clipX1, y < clipY1 else { return }
        let i = y * width + x
        rgba[i] = p; idx[i] = m
    }
    /// 直接写一个颜色（不经过调色板；UI 文字底、调试标记用）。
    @inline(__always) public func setRaw(_ x: Int, _ y: Int, color: RGBA8, id: UInt16 = 0) {
        guard x >= clipX0, y >= clipY0, x < clipX1, y < clipY1 else { return }
        let i = y * width + x
        rgba[i] = color.packed; idx[i] = 0
        if id != 0 { ids[i] = id }
    }

    /// 命中测试：先看这个像素，再看上下左右和四个斜角（外扩 1 像素）。
    public func hitID(x: Int, y: Int, dilate: Bool = true) -> UInt16 {
        let c = objectID(x, y)
        if c != 0 || !dilate { return c }
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let v = objectID(x + dx, y + dy)
            if v != 0 { return v }
        }
        return 0
    }

    // MARK: 精灵
    /// 贴一个精灵。(x, y) 是精灵左上角在画布里的位置；超出画布的部分自动裁掉；clip 可以再收紧。
    public func blit(_ s: IndexedSprite, x: Int, y: Int, flipH: Bool = false, style: Resolved,
                     id: UInt16 = 0, clip: IntRect? = nil) {
        var cx0 = clipX0, cy0 = clipY0, cx1 = clipX1, cy1 = clipY1
        if let c = clip { cx0 = max(cx0, c.x); cy0 = max(cy0, c.y); cx1 = min(cx1, c.maxX); cy1 = min(cy1, c.maxY) }
        let sx0 = max(0, cx0 - x), sy0 = max(0, cy0 - y)
        let sx1 = min(s.width, cx1 - x), sy1 = min(s.height, cy1 - y)
        if sx0 >= sx1 || sy0 >= sy1 { return }
        let dither = style.threshold > 0 && style.threshold < 16
        let useAllB = style.threshold >= 16
        s.pixels.withUnsafeBufferPointer { src in
            style.a.withUnsafeBufferPointer { ta in
                style.b.withUnsafeBufferPointer { tb in
                    style.master.withUnsafeBufferPointer { tm in
                        for sy in sy0..<sy1 {
                            let dy = y + sy
                            let rowSrc = sy * s.width
                            let rowDst = dy * width
                            for sx in sx0..<sx1 {
                                let v = Int(src[rowSrc + (flipH ? s.width - 1 - sx : sx)])
                                if v == 0 { continue }
                                let dx = x + sx
                                let i = rowDst + dx
                                if useAllB { rgba[i] = tb[v] }
                                else if dither, Resolved.bayer4[(dy & 3) * 4 + (dx & 3)] < style.threshold { rgba[i] = tb[v] }
                                else { rgba[i] = ta[v] }
                                idx[i] = tm[v]
                                if id != 0 { ids[i] = id }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 把另一张画布当图层贴上来（三个平面一起复制；源里 alpha = 0 的像素跳过）。可水平翻转。
    /// ids 只有 id != 0 时才会覆盖成给定的对象号（例如整个 buddy 图层统一成一个对象 ID）。
    public func blitCanvas(_ src: Canvas, x: Int, y: Int, flipH: Bool = false, id: UInt16 = 0, clip: IntRect? = nil, srcRect: IntRect? = nil) {
        if let sr = srcRect { blitCanvas(src.cropped(sr), x: x, y: y, flipH: flipH, id: id, clip: clip); return }
        var cx0 = clipX0, cy0 = clipY0, cx1 = clipX1, cy1 = clipY1
        if let c = clip { cx0 = max(cx0, c.x); cy0 = max(cy0, c.y); cx1 = min(cx1, c.maxX); cy1 = min(cy1, c.maxY) }
        let sx0 = max(0, cx0 - x), sy0 = max(0, cy0 - y)
        let sx1 = min(src.width, cx1 - x), sy1 = min(src.height, cy1 - y)
        if sx0 >= sx1 || sy0 >= sy1 { return }
        for sy in sy0..<sy1 {
            let dy = y + sy
            for sx in sx0..<sx1 {
                let srcX = flipH ? src.width - 1 - sx : sx
                let si = sy * src.width + srcX
                let px = src.rgba[si]
                if (px >> 24) == 0 { continue }
                let di = dy * width + (x + sx)
                rgba[di] = px
                idx[di] = src.idx[si]
                if id != 0 { ids[di] = id } else if src.ids[si] != 0 { ids[di] = src.ids[si] }
            }
        }
    }

    // MARK: 基本图元（v 是「值」：角色精灵里是 Role 号，直接样式里是主调色板索引）
    public func fillRect(_ r: IntRect, value v: UInt8, style: Resolved, id: UInt16 = 0) {
        guard v != 0, let c = r.intersection(clipRect) else { return }
        for y in c.y..<c.maxY { for x in c.x..<c.maxX { set(x, y, value: v, style: style, id: id) } }
    }
    public func hLine(x: Int, y: Int, length: Int, value v: UInt8, style: Resolved, id: UInt16 = 0) {
        fillRect(IntRect(x, y, length, 1), value: v, style: style, id: id)
    }
    public func vLine(x: Int, y: Int, length: Int, value v: UInt8, style: Resolved, id: UInt16 = 0) {
        fillRect(IntRect(x, y, 1, length), value: v, style: style, id: id)
    }
    /// 1 像素空心矩形。
    public func strokeRect(_ r: IntRect, value v: UInt8, style: Resolved, id: UInt16 = 0) {
        guard r.w > 0, r.h > 0 else { return }
        hLine(x: r.x, y: r.y, length: r.w, value: v, style: style, id: id)
        hLine(x: r.x, y: r.maxY - 1, length: r.w, value: v, style: style, id: id)
        vLine(x: r.x, y: r.y, length: r.h, value: v, style: style, id: id)
        vLine(x: r.maxX - 1, y: r.y, length: r.h, value: v, style: style, id: id)
    }
    /// 4×4 Bayer 抖动填充：level 0…16 表示 v 所占的比例（16 = 全 v，0 = 全 v2 / 不画）。
    public func fillDither(_ r: IntRect, value v: UInt8, other v2: UInt8 = 0, level: Int, style: Resolved, id: UInt16 = 0) {
        guard let c = r.intersection(clipRect) else { return }
        for y in c.y..<c.maxY { for x in c.x..<c.maxX {
            let on = Resolved.bayer4[(y & 3) * 4 + (x & 3)] < level
            let val = on ? v : v2
            if val != 0 { set(x, y, value: val, style: style, id: id) }
        } }
    }
    /// 实心椭圆（中心 cx,cy，半轴 rx,ry）；用于地毯、光斑、影子。
    public func fillEllipse(cx: Int, cy: Int, rx: Int, ry: Int, value v: UInt8, style: Resolved, id: UInt16 = 0, dither: Int = 16) {
        guard rx > 0, ry > 0 else { return }
        let ya = max(cy - ry, clipY0), yb = min(cy + ry, clipY1 - 1), xa = max(cx - rx, clipX0), xb = min(cx + rx, clipX1 - 1)
        if ya > yb || xa > xb { return }
        for y in ya...yb { for x in xa...xb {
            let dx = Double(x - cx) / (Double(rx) + 0.35), dy = Double(y - cy) / (Double(ry) + 0.35)
            if dx * dx + dy * dy <= 1 {
                if dither >= 16 || Resolved.bayer4[(y & 3) * 4 + (x & 3)] < dither { set(x, y, value: v, style: style, id: id) }
            }
        } }
    }
    /// 圆角「牌子」：1 像素外框（四角抹掉一个点）+ 内侧 1 像素高光 + 填充。桌牌、气泡、提示卡都用它。
    public func plate(_ r: IntRect, border: UInt8, fill: UInt8, light: UInt8? = nil, shade: UInt8? = nil,
                      style: Resolved, id: UInt16 = 0) {
        guard r.w >= 3, r.h >= 3 else { return }
        fillRect(r.insetBy(1), value: fill, style: style, id: id)
        hLine(x: r.x + 1, y: r.y, length: r.w - 2, value: border, style: style, id: id)
        hLine(x: r.x + 1, y: r.maxY - 1, length: r.w - 2, value: border, style: style, id: id)
        vLine(x: r.x, y: r.y + 1, length: r.h - 2, value: border, style: style, id: id)
        vLine(x: r.maxX - 1, y: r.y + 1, length: r.h - 2, value: border, style: style, id: id)
        if let l = light, r.w >= 5, r.h >= 4 {
            hLine(x: r.x + 2, y: r.y + 1, length: r.w - 4, value: l, style: style, id: id)
        }
        if let s = shade, r.w >= 5, r.h >= 4 {
            hLine(x: r.x + 2, y: r.maxY - 2, length: r.w - 4, value: s, style: style, id: id)
        }
    }

    // MARK: 灯光
    /// 光圈：椭圆范围内、已画过（idx ≠ 0）的像素，改用另一张 LUT 重新着色（台灯、夜里的天花板灯光斑）。
    /// 边缘用 Bayer 抖动做两圈渐变，所以没有半透明，也不会闪。strength 0…1 整体强度。
    public func applyLightPool(cx: Int, cy: Int, rx: Int, ry: Int, lut: PaletteLUT, strength: Double = 1) {
        guard rx > 0, ry > 0, strength > 0 else { return }
        let x0 = max(clipX0, cx - rx), x1 = min(clipX1 - 1, cx + rx), y0 = max(clipY0, cy - ry), y1 = min(clipY1 - 1, cy + ry)
        if x0 > x1 || y0 > y1 { return }
        for y in y0...y1 { for x in x0...x1 {
            let dx = Double(x - cx) / Double(rx), dy = Double(y - cy) / Double(ry)
            let d = dx * dx + dy * dy
            if d > 1 { continue }
            // 内圈全亮；中圈 12/16；外圈 5/16
            let level = d < 0.36 ? 16.0 : (d < 0.72 ? 12.0 : 5.0)
            let lv = Int((level * strength).rounded())
            if Resolved.bayer4[(y & 3) * 4 + (x & 3)] >= lv { continue }
            let i = y * width + x
            let m = idx[i]
            if m == 0 { continue }
            let c = lut.table[Int(m)]
            if c != 0 { rgba[i] = c }
        } }
    }

    // MARK: 输出
    /// 转成 CGImage（预乘 RGBA、sRGB）。crop 为 nil 时输出整张。数据是复制出来的，画布之后可以继续改。
    public func makeCGImage(crop: IntRect? = nil) -> CGImage? {
        let r = (crop ?? bounds).intersection(bounds) ?? bounds
        var buf = [UInt32](repeating: 0, count: r.w * r.h)
        for y in 0..<r.h {
            let src = rgba + ((r.y + y) * width + r.x)
            buf.withUnsafeMutableBufferPointer { dst in
                (dst.baseAddress! + y * r.w).update(from: src, count: r.w)
            }
        }
        let data = buf.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        guard let prov = CGDataProvider(data: data), let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: r.w, height: r.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: r.w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 取一块像素拷成新画布（测试、局部放大用）。
    public func cropped(_ rect: IntRect) -> Canvas {
        let r = rect.intersection(bounds) ?? IntRect(0, 0, 1, 1)
        let c = Canvas(width: r.w, height: r.h)
        for y in 0..<r.h {
            (c.rgba + y * r.w).update(from: rgba + ((r.y + y) * width + r.x), count: r.w)
            (c.idx + y * r.w).update(from: idx + ((r.y + y) * width + r.x), count: r.w)
            (c.ids + y * r.w).update(from: ids + ((r.y + y) * width + r.x), count: r.w)
        }
        return c
    }

    /// 整帧内容的哈希（金图测试、窗口「这一帧变了没有」都用它）。四路并行的 64 位乘法混合，一次吃 32 字节；
    /// 同样的像素永远得到同样的值（不含地址、不含随机种子）。
    public func contentHash() -> UInt64 {
        let k: UInt64 = 0x9E3779B97F4A7C15
        var h0: UInt64 = 0x243F6A8885A308D3, h1: UInt64 = 0x13198A2E03707344, h2: UInt64 = 0xA4093822299F31D0, h3: UInt64 = 0x082EFA98EC4E6C89
        let raw = UnsafeRawPointer(rgba)
        let words = (count * 4) / 8
        let quads = words / 4
        var i = 0
        while i < quads {
            let o = i * 32
            h0 = (h0 ^ raw.loadUnaligned(fromByteOffset: o, as: UInt64.self)) &* k; h0 ^= h0 >> 29
            h1 = (h1 ^ raw.loadUnaligned(fromByteOffset: o + 8, as: UInt64.self)) &* k; h1 ^= h1 >> 29
            h2 = (h2 ^ raw.loadUnaligned(fromByteOffset: o + 16, as: UInt64.self)) &* k; h2 ^= h2 >> 29
            h3 = (h3 ^ raw.loadUnaligned(fromByteOffset: o + 24, as: UInt64.self)) &* k; h3 ^= h3 >> 29
            i += 1
        }
        var j = quads * 4
        while j < words {
            h0 = (h0 ^ raw.loadUnaligned(fromByteOffset: j * 8, as: UInt64.self)) &* k; h0 ^= h0 >> 29
            j += 1
        }
        if (count & 1) == 1 { h1 = (h1 ^ UInt64(rgba[count - 1])) &* k; h1 ^= h1 >> 29 }
        var h = h0 ^ (h1 &* 3) ^ (h2 &* 5) ^ (h3 &* 7)
        h = (h ^ (h >> 32)) &* k
        return h ^ (h >> 29)
    }

    /// 把一块区域按 BGRA（预乘、小端）写进目标内存：这是 Core Animation 直接使用的像素格式，不用再转换。
    /// crop 和画布不相交（或宽高 ≤ 0）时什么都不写：目标内存是调用方按 crop 的大小分配的（IOSurface），不能退化成「整张画布」去写——那会越界写合成器正在读的共享内存。
    /// 一行放不下（bytesPerRow < 相交宽度 × 4）也不写。
    public func writeBGRA(into dst: UnsafeMutableRawPointer, bytesPerRow: Int, crop: IntRect? = nil) {
        guard let r = (crop ?? bounds).intersection(bounds), bytesPerRow >= r.w * 4 else { return }
        for y in 0..<r.h {
            let src = rgba + ((r.y + y) * width + r.x)
            let d = (dst + y * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            for x in 0..<r.w {
                let p = src[x]
                d[x] = (p & 0xFF00FF00) | ((p & 0xFF) << 16) | ((p >> 16) & 0xFF)
            }
        }
    }

    /// 转成 Core Animation 直接吃的 CGImage：BGRA、预乘、sRGB。窗口的色彩空间也设成 sRGB，系统就不用每帧在 CPU 上转换颜色。
    public func makeDisplayImage(crop: IntRect? = nil) -> CGImage? {
        let r = (crop ?? bounds).intersection(bounds) ?? bounds
        let bpr = r.w * 4
        guard let cs = Canvas.sRGB else { return nil }
        let data = NSMutableData(length: bpr * r.h)!
        writeBGRA(into: data.mutableBytes, bytesPerRow: bpr, crop: r)
        guard let prov = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: r.w, height: r.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    /// 平均亮度（0…1，按不透明像素；闪烁扫描用）。
    public func meanLuminance(in rect: IntRect? = nil) -> Double {
        let r = (rect ?? bounds).intersection(bounds) ?? bounds
        var sum = 0.0
        for y in r.y..<r.maxY { for x in r.x..<r.maxX {
            let p = rgba[y * width + x]
            let a = Double((p >> 24) & 0xFF) / 255
            if a == 0 { continue }
            // 预乘 → 还原后取亮度，再乘以覆盖率
            let rr = Double(p & 0xFF) / 255, gg = Double((p >> 8) & 0xFF) / 255, bb = Double((p >> 16) & 0xFF) / 255
            sum += 0.2126 * rr + 0.7152 * gg + 0.0722 * bb   // 预乘值本身就是「亮度×覆盖」
        } }
        return sum / Double(max(1, r.w * r.h))
    }
}
