import Foundation

public struct IntPoint: Equatable, Hashable, Sendable {
    public var x: Int, y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

/// 索引色精灵：一张 width×height 的值格子（0 = 透明）。
/// 角色精灵里的值是 Role 号，道具精灵里的值是主调色板索引（由 SpriteLegend 决定）。
public struct IndexedSprite: Sendable {
    public let name: String
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    public let anchors: [String: IntPoint]

    public init(name: String, width: Int, height: Int, pixels: [UInt8], anchors: [String: IntPoint] = [:]) {
        self.name = name; self.width = width; self.height = height; self.pixels = pixels; self.anchors = anchors
    }

    @inline(__always) public func value(_ x: Int, _ y: Int) -> UInt8 {
        (x >= 0 && y >= 0 && x < width && y < height) ? pixels[y * width + x] : 0
    }

    /// 水平翻转（锚点一起镜像）。
    public func flippedH(name newName: String? = nil) -> IndexedSprite {
        var out = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height { for x in 0..<width { out[y * width + (width - 1 - x)] = pixels[y * width + x] } }
        var an: [String: IntPoint] = [:]
        for (k, p) in anchors { an[k] = IntPoint(width - 1 - p.x, p.y) }
        return IndexedSprite(name: newName ?? name + "~", width: width, height: height, pixels: out, anchors: an)
    }

    /// 不透明像素个数。
    public var opaqueCount: Int { pixels.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }

    /// 不透明像素的包围盒（相对精灵左上角）；全透明返回 nil。
    public var bounds: IntRect? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height { for x in 0..<width where pixels[y * width + x] != 0 {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
        } }
        return x1 < 0 ? nil : IntRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    }

    /// 裁掉指定行范围 / 列范围，得到子精灵（锚点平移，越界的锚点丢掉）。
    public func cropped(_ r: IntRect, name newName: String? = nil) -> IndexedSprite {
        var out = [UInt8](repeating: 0, count: r.w * r.h)
        for y in 0..<r.h { for x in 0..<r.w { out[y * r.w + x] = value(r.x + x, r.y + y) } }
        var an: [String: IntPoint] = [:]
        for (k, p) in anchors {
            let q = IntPoint(p.x - r.x, p.y - r.y)
            if q.x >= 0, q.y >= 0, q.x < r.w, q.y < r.h { an[k] = q }
        }
        return IndexedSprite(name: newName ?? name, width: r.w, height: r.h, pixels: out, anchors: an)
    }
}

public struct SpriteError: Error, CustomStringConvertible, Sendable {
    public var sprite: String
    public var message: String
    public var description: String { "精灵「\(sprite)」：\(message)" }
}

public enum SpriteParser {
    /// 把多行字符串解析成精灵。空行（首尾）会被丢掉；每行宽度必须一致；字符必须在字符表里；锚点必须落在图内。
    public static func parse(name: String, _ text: String, legend: SpriteLegend = .roles,
                             anchors: [String: IntPoint] = [:]) throws -> IndexedSprite {
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        while let f = rows.first, f.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeFirst() }
        while let l = rows.last, l.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
        guard !rows.isEmpty else { throw SpriteError(sprite: name, message: "没有内容") }
        let w = rows[0].count
        var px = [UInt8](); px.reserveCapacity(w * rows.count)
        for (yi, row) in rows.enumerated() {
            if row.count != w { throw SpriteError(sprite: name, message: "第 \(yi + 1) 行宽度 \(row.count)，应为 \(w)") }
            for (xi, ch) in row.enumerated() {
                guard let v = legend.map[ch] else {
                    throw SpriteError(sprite: name, message: "第 \(yi + 1) 行第 \(xi + 1) 列的字符「\(ch)」不认识")
                }
                px.append(v)
            }
        }
        for (k, p) in anchors where p.x < 0 || p.y < 0 || p.x >= w || p.y >= rows.count {
            throw SpriteError(sprite: name, message: "锚点「\(k)」(\(p.x),\(p.y)) 在图外（\(w)×\(rows.count)）")
        }
        return IndexedSprite(name: name, width: w, height: rows.count, pixels: px, anchors: anchors)
    }
}

/// 精灵注册表：启动时把全部精灵解析进来，错误集中收集，测试里断言为空。
public final class SpriteBook: @unchecked Sendable {
    public private(set) var sprites: [String: IndexedSprite] = [:]
    public private(set) var order: [String] = []
    public private(set) var errors: [SpriteError] = []
    private let lock = NSLock()
    public init() {}

    @discardableResult
    public func add(_ name: String, _ text: String, legend: SpriteLegend = .roles,
                    anchors: [String: IntPoint] = [:]) -> IndexedSprite? {
        lock.lock(); defer { lock.unlock() }
        do {
            let s = try SpriteParser.parse(name: name, text, legend: legend, anchors: anchors)
            if sprites[name] == nil { order.append(name) }
            sprites[name] = s
            return s
        } catch let e as SpriteError {
            errors.append(e); return nil
        } catch {
            errors.append(SpriteError(sprite: name, message: "\(error)")); return nil
        }
    }

    public func add(_ s: IndexedSprite) {
        lock.lock(); defer { lock.unlock() }
        if sprites[s.name] == nil { order.append(s.name) }
        sprites[s.name] = s
    }

    public subscript(name: String) -> IndexedSprite {
        guard let s = sprites[name] else { preconditionFailure("找不到精灵「\(name)」") }
        return s
    }
    public func get(_ name: String) -> IndexedSprite? { sprites[name] }
}
