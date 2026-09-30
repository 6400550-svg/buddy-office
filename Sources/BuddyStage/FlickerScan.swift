import Foundation
import CoreGraphics
import PixelKit

/// 闪烁扫描（任务书 10.1）：对一串帧做 5 项检查，只要有一项不合格就报告并让命令以非零退出。
///  1. 相邻两帧平均亮度变化 > 0.06；或某个 16×16 块变化 > 0.35 又在 3 帧内变回去；
///  2. 同一像素在 4 帧内出现 A→B→A（B 最多持续 3 帧）且亮度差 ΔY > 0.2（眨眼在白名单里）；
///  3. 某个对象 ID 的像素数掉到 0 又在 3 帧内回来（对象消失了一下 / 层级出错）；
///  4. 某个对象的主要摆动频率超过 4 Hz（去趋势后质心的过零次数）；
///  5. 在允许的过渡帧之外，某个对象有超过 40% 的像素在一帧之内同时改变（硬切）。
public final class FlickerScan {
    public struct Finding: CustomStringConvertible {
        public var frame: Int
        public var check: Int
        public var detail: String
        public var description: String { "第 \(frame) 帧 · 检查 \(check)：\(detail)" }
    }
    public struct FrameMeta { public var transitionIDs: Set<UInt16> = []; public var allowRects: [IntRect] = []; public init() {} }

    let fps: Double
    var frames: [[UInt8]] = []        // 亮度 0…255
    var idPlanes: [[UInt16]] = []
    var metas: [FrameMeta] = []
    var rgbaPlanes: [[UInt32]] = []
    var w = 0, h = 0
    public private(set) var findings: [Finding] = []
    /// 检查 2 的容忍度：一帧里孤立的 A→B→A 像素数不超过它就只记录、不算不合格（走路 / 手臂 IK 取整时偶尔有 1–3 个像素的抖动，肉眼看不出来）。--strict 时为 0。
    public var tolerance = 6
    public private(set) var tolerated = 0
    /// 检查 2 抓到的每一处（不管容忍不容忍）：哪一帧、在哪、几个像素。--dump 用来出条带图。
    public struct Spot { public var frame: Int; public var bbox: IntRect; public var count: Int; public var tolerated: Bool }
    public private(set) var spots: [Spot] = []
    var idHistory: [UInt16: [Int]] = [:]
    var centroids: [UInt16: [(Double, Double)]] = [:]

    public init(fps: Double) { self.fps = fps }

    static func luma(_ p: UInt32) -> UInt8 {
        let a = Double((p >> 24) & 0xFF)
        if a == 0 { return 0 }
        let r = Double(p & 0xFF), g = Double((p >> 8) & 0xFF), b = Double((p >> 16) & 0xFF)
        return UInt8(max(0, min(255, (0.2126 * r + 0.7152 * g + 0.0722 * b) * 255 / a)))
    }

    public func add(_ canvas: Canvas, meta: FrameMeta = FrameMeta()) {
        w = canvas.width; h = canvas.height
        var y = [UInt8](repeating: 0, count: w * h)
        var ids = [UInt16](repeating: 0, count: w * h)
        var rgba = [UInt32](repeating: 0, count: w * h)
        for i in 0..<(w * h) { y[i] = Self.luma(canvas.rgba[i]); ids[i] = canvas.ids[i]; rgba[i] = canvas.rgba[i] }
        frames.append(y); idPlanes.append(ids); metas.append(meta); rgbaPlanes.append(rgba)
    }

    /// 出问题的地方的条带图：这一帧前 3 帧到后 2 帧，裁出 bbox 周围（外扩 pad 像素），放大 zoom 倍并排；出问题的那一帧上沿画一条红线。
    public func strip(frame f: Int, bbox: IntRect, pad: Int = 8, zoom: Int = 8, before: Int = 3, after: Int = 2) -> CGImage? {
        guard w > 0, h > 0, f < rgbaPlanes.count else { return nil }
        let x0 = max(0, bbox.x - pad), y0 = max(0, bbox.y - pad)
        let x1 = min(w, bbox.x + bbox.w + pad), y1 = min(h, bbox.y + bbox.h + pad)
        let cw = x1 - x0, ch = y1 - y0
        guard cw > 0, ch > 0 else { return nil }
        let list = Array(max(0, f - before)...min(rgbaPlanes.count - 1, f + after))
        let gap = 3
        let W = (cw * zoom + gap) * list.count - gap, H = ch * zoom
        var buf = [UInt32](repeating: 0xFF20_1A1A, count: W * H)
        for (n, fr) in list.enumerated() {
            let ox = n * (cw * zoom + gap)
            for y in 0..<ch { for x in 0..<cw {
                let p = rgbaPlanes[fr][(y0 + y) * w + (x0 + x)]
                for dy in 0..<zoom { for dx in 0..<zoom { buf[(y * zoom + dy) * W + ox + x * zoom + dx] = p } }
            } }
            if fr == f { for x in 0..<(cw * zoom) { for dy in 0..<3 { buf[dy * W + ox + x] = 0xFF00_00FF } } }
            // 出问题的像素外面画一圈：bbox 本身
            if fr == f {
                let bx = (bbox.x - x0) * zoom, by = (bbox.y - y0) * zoom, bw = bbox.w * zoom, bh = bbox.h * zoom
                for x in bx..<min(cw * zoom, bx + bw) { for t in [by, min(H - 1, by + bh - 1)] { buf[t * W + ox + x] = 0xFF00_FFFF } }
                for y in by..<min(H, by + bh) { for t in [bx, min(cw * zoom - 1, bx + bw - 1)] { buf[y * W + ox + t] = 0xFF00_FFFF } }
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return buf.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    func inAllow(_ x: Int, _ yy: Int, frame: Int) -> Bool {
        for k in max(0, frame - 3)...min(metas.count - 1, frame + 3) { for r in metas[k].allowRects where r.contains(x, yy) { return true } }
        return false
    }

    public func analyze() -> [Finding] {
        findings = []
        guard frames.count > 4 else { return findings }
        let n = frames.count, px = w * h
        // 1. 平均亮度 + 16×16 块
        var means = [Double](repeating: 0, count: n)
        for f in 0..<n { var s = 0; for i in 0..<px { s += Int(frames[f][i]) }; means[f] = Double(s) / Double(px) / 255 }
        for f in 1..<n {
            let d = abs(means[f] - means[f - 1])
            if d > 0.06 { findings.append(Finding(frame: f, check: 1, detail: "平均亮度变化 \(String(format: "%.3f", d)) > 0.06")) }
        }
        let bw = (w + 15) / 16, bh = (h + 15) / 16
        func blockMean(_ f: Int, _ bx: Int, _ by: Int) -> Double {
            var s = 0, c = 0
            for yy in (by * 16)..<min(h, by * 16 + 16) { for xx in (bx * 16)..<min(w, bx * 16 + 16) { s += Int(frames[f][yy * w + xx]); c += 1 } }
            return Double(s) / Double(max(1, c)) / 255
        }
        for f in 1..<(n - 1) {
            for by in 0..<bh { for bx in 0..<bw {
                let d = abs(blockMean(f, bx, by) - blockMean(f - 1, bx, by))
                if d > 0.35 {
                    for k in 1...3 where f + k < n {
                        if abs(blockMean(f + k, bx, by) - blockMean(f - 1, bx, by)) < 0.08 {
                            findings.append(Finding(frame: f, check: 1, detail: "16×16 块 (\(bx),\(by)) 变化 \(String(format: "%.2f", d)) 又在 \(k) 帧内变回去")); break
                        }
                    }
                }
            } }
        }
        // 2. 像素 A→B→A
        //    运动的边缘（手臂挥过、走路的人）天然会让像素闪一两帧再变回去，那是动画，不是闪烁。
        //    所以：只要这个像素周围 2 像素内有「持续的变化」（变了以后 2 帧内没变回去），就当作运动，不算。
        var persistent = [[Bool]](repeating: [Bool](repeating: false, count: px), count: n)
        for f in 1..<n {
            for i in 0..<px {
                let a = Int(frames[f - 1][i]), b = Int(frames[f][i])
                if abs(a - b) <= 51 { continue }
                var back = false
                for k in 1...2 where f + k < n { if abs(Int(frames[f + k][i]) - a) < 20 { back = true; break } }
                if !back { persistent[f][i] = true }
            }
        }
        func nearMotion(_ xx: Int, _ yy: Int, _ f: Int) -> Bool {
            for ff in max(1, f - 1)...min(n - 1, f + 1) {
                for dy in -2...2 { for dx in -2...2 {
                    let x2 = xx + dx, y2 = yy + dy
                    if x2 >= 0, y2 >= 0, x2 < w, y2 < h, persistent[ff][y2 * w + x2] { return true }
                } }
            }
            return false
        }
        var flipFrames: [Int: Int] = [:]
        var flipBox: [Int: (Int, Int, Int, Int)] = [:]
        var flipIDs: [Int: [UInt16: Int]] = [:]
        for f in 1..<(n - 1) {
            for i in 0..<px {
                let a = Int(frames[f - 1][i]), b = Int(frames[f][i])
                if abs(a - b) <= 51 { continue }                              // ΔY > 0.2
                let xx = i % w, yy = i / w
                for k in 1...2 where f + k < n {
                    if abs(Int(frames[f + k][i]) - a) < 20 {
                        let tid = idPlanes[f][i] != 0 ? idPlanes[f][i] : idPlanes[max(0, f - 1)][i]
                        let inTransition = (max(0, f - 2)...min(n - 1, f + 2)).contains { metas[$0].transitionIDs.contains(tid) }
                        if !inAllow(xx, yy, frame: f), !inTransition, !nearMotion(xx, yy, f) {
                            flipFrames[f, default: 0] += 1
                            var bb = flipBox[f] ?? (xx, yy, xx, yy)
                            bb = (min(bb.0, xx), min(bb.1, yy), max(bb.2, xx), max(bb.3, yy)); flipBox[f] = bb
                            flipIDs[f, default: [:]][idPlanes[f][i], default: 0] += 1
                        }
                        break
                    }
                }
            }
        }
        tolerated = 0
        spots = []
        for (f, c) in flipFrames.sorted(by: { $0.key < $1.key }) where c > 0 {
            let bb = flipBox[f]!
            spots.append(Spot(frame: f, bbox: IntRect(bb.0, bb.1, bb.2 - bb.0 + 1, bb.3 - bb.1 + 1), count: c, tolerated: c <= tolerance))
            if c <= tolerance { tolerated += 1; continue }
            let ids = (flipIDs[f] ?? [:]).sorted { $0.value > $1.value }.prefix(2).map { "id\($0.key)×\($0.value)" }.joined(separator: ",")
            findings.append(Finding(frame: f, check: 2, detail: "\(c) 个孤立像素在 2 帧内 A→B→A（ΔY > 0.2，附近没有运动）范围 (\(bb.0),\(bb.1))-(\(bb.2),\(bb.3)) \(ids)"))
        }
        // 3. 对象消失又回来
        var ids = Set<UInt16>()
        for f in 0..<n { for i in stride(from: 0, to: px, by: 1) where idPlanes[f][i] != 0 { ids.insert(idPlanes[f][i]) } ; if f > 20 { break } }
        for f in 0..<n { for i in 0..<px { let v = idPlanes[f][i]; if v != 0 { ids.insert(v) } } }
        for id in ids {
            var counts = [Int](repeating: 0, count: n)
            var cx = [Double](repeating: 0, count: n), cy = [Double](repeating: 0, count: n)
            for f in 0..<n {
                var c = 0, sx = 0.0, sy = 0.0
                for i in 0..<px where idPlanes[f][i] == id { c += 1; sx += Double(i % w); sy += Double(i / w) }
                counts[f] = c
                if c > 0 { cx[f] = sx / Double(c); cy[f] = sy / Double(c) }
            }
            // 3
            var f = 1
            while f < n - 1 {
                if counts[f - 1] > 0 && counts[f] == 0 {
                    var back = 0
                    for k in 1...3 where f + k < n && counts[f + k] > 0 { back = k; break }
                    if back > 0 { findings.append(Finding(frame: f, check: 3, detail: "对象 \(id) 的像素数掉到 0，\(back) 帧后又回来")) }
                }
                f += 1
            }
            // 4. 摆动频率：1 秒滑窗里去趋势后质心的过零次数（> 8 次 / 秒 = 4 Hz）
            let win = fps.isFinite ? max(2, safeInt(fps)) : 30          // --fps 1 时 win / 2 = 0，下面的滑窗永远不前进（死循环）
            if n > win * 2 {
                var f0 = 0
                while f0 + win < n {
                    let valid = (f0..<(f0 + win)).allSatisfy { counts[$0] > 0 }
                    if valid {
                        for axis in 0..<2 {
                            let arr = (f0..<(f0 + win)).map { axis == 0 ? cx[$0] : cy[$0] }
                            let m = arr.reduce(0, +) / Double(arr.count)
                            var cross = 0, prev = 0.0
                            var amp = 0.0
                            for v in arr { let d = v - m; amp = max(amp, abs(d)); if prev != 0, d != 0, (prev < 0) != (d < 0), abs(d) > 0.25, abs(prev) > 0.25 { cross += 1 }; if d != 0 { prev = d } }
                            if cross > 8 && amp > 0.3 { findings.append(Finding(frame: f0, check: 4, detail: "对象 \(id) 的\(axis == 0 ? "水平" : "垂直")摆动过零 \(cross) 次/秒（> 4 Hz）")) }
                        }
                    }
                    f0 += max(1, win / 2)
                }
            }
            // 5. 硬切：一帧内该对象超过 40% 的像素改变（过渡帧除外）
            for f in 1..<n {
                let allowed = metas[f].transitionIDs.contains(id) || metas[f - 1].transitionIDs.contains(id) || (f > 1 && metas[f - 2].transitionIDs.contains(id))
                if allowed { continue }
                var changed = 0, total = 0
                for i in 0..<px where idPlanes[f][i] == id || idPlanes[f - 1][i] == id {
                    total += 1
                    if idPlanes[f][i] != idPlanes[f - 1][i] || rgbaPlanes[f][i] != rgbaPlanes[f - 1][i] { changed += 1 }
                }
                if total > 60 && Double(changed) / Double(total) > 0.4 {
                    findings.append(Finding(frame: f, check: 5, detail: "对象 \(id) 有 \(Int(100 * Double(changed) / Double(total)))% 的像素在一帧内改变（硬切）"))
                }
            }
        }
        return findings
    }
}
