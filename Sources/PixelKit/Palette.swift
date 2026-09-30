import Foundation

/// 字符 → 精灵格子里的值。角色精灵（人物、头发、衣服……）里存的是「角色号」，
/// 经每个 buddy 自己的 RoleMap 才变成主调色板索引；道具/房间精灵直接存主调色板索引。
public enum Role {
    public static let transparent: UInt8 = 0
    public static let skinHi: UInt8 = 1, skin: UInt8 = 2, skinSh: UInt8 = 3          // k K j
    public static let hairHi: UInt8 = 4, hair: UInt8 = 5, hairSh: UInt8 = 6          // h H g
    public static let clothHi: UInt8 = 7, cloth: UInt8 = 8, clothSh: UInt8 = 9       // s S t
    public static let pants: UInt8 = 10, pantsSh: UInt8 = 11                          // p P
    public static let outHair: UInt8 = 12, outSkin: UInt8 = 13, outCloth: UInt8 = 14 // 1 2 3
    public static let eye: UInt8 = 15, eyeWhite: UInt8 = 16, mouth: UInt8 = 17       // e w m
    public static let accent: UInt8 = 18, accentSh: UInt8 = 19                        // a A
    public static let chair: UInt8 = 20, chairSh: UInt8 = 21                          // c C
    public static let reflect: UInt8 = 22                                              // r 夜间屏幕反光候选
    public static let blush: UInt8 = 23                                                // b 腮红
    public static let shoe: UInt8 = 24                                                 // o 鞋
    public static let spark: UInt8 = 25                                                // n 高光白点
    public static let accent2: UInt8 = 26                                              // u 第二点缀色（发带、耳机罩……）
    public static let lens: UInt8 = 27                                                 // l 镜片
    public static let count = 28

    public static let chars: [Character: UInt8] = [
        ".": transparent,
        "k": skinHi, "K": skin, "j": skinSh,
        "h": hairHi, "H": hair, "g": hairSh,
        "s": clothHi, "S": cloth, "t": clothSh,
        "p": pants, "P": pantsSh,
        "1": outHair, "2": outSkin, "3": outCloth,
        "e": eye, "w": eyeWhite, "m": mouth,
        "a": accent, "A": accentSh,
        "c": chair, "C": chairSh,
        "r": reflect, "b": blush, "o": shoe, "n": spark, "u": accent2, "l": lens,
    ]
    /// 反查（画总表标签、调试用）
    public static let names: [UInt8: String] = [
        0: "透明", 1: "肤高光", 2: "肤", 3: "肤影", 4: "发高光", 5: "发", 6: "发影", 7: "衣高光", 8: "衣", 9: "衣影",
        10: "裤", 11: "裤影", 12: "发描边", 13: "肤描边", 14: "衣描边", 15: "眼", 16: "眼白", 17: "嘴", 18: "点缀", 19: "点缀影",
        20: "椅", 21: "椅影", 22: "反光", 23: "腮红", 24: "鞋", 25: "高光点", 26: "点缀2", 27: "镜片",
    ]
}

/// 精灵的字符表。
public struct SpriteLegend: Sendable {
    public var map: [Character: UInt8]
    public init(_ map: [Character: UInt8]) { self.map = map }
    /// 人物角色字符表。
    public static let roles = SpriteLegend(Role.chars)
}

/// 每个 buddy 自己的「角色 → 主调色板索引」映射（外观随机的结果）。
public struct RoleMap: Sendable, Equatable {
    public var table: [UInt16]   // 长度 256；角色号 → 主调色板索引（16 位：人物色阶排在 256 之后）
    public init() { table = [UInt16](repeating: 0, count: 256) }
    public subscript(role: UInt8) -> UInt16 {
        get { table[Int(role)] }
        set { table[Int(role)] = newValue }
    }
    /// 恒等映射（道具精灵直接存主调色板索引）。
    public static let identity: RoleMap = {
        var m = RoleMap(); for i in 0..<256 { m.table[i] = UInt16(i) }; return m
    }()
}

/// 主调色板：每一项有名字、白天的基础颜色、是否「自发光」（屏幕、灯，不受时段 LUT 影响）。
public struct MasterPalette: Sendable {
    public private(set) var names: [String] = ["透明"]
    public private(set) var base: [RGBA8] = [.clear]
    public private(set) var emissive: [Bool] = [false]
    private var lookup: [String: UInt16] = [:]
    public init() {}

    /// 索引是 16 位。直接存索引的精灵（道具、房间，格子里是 UInt8）只能用前 256 项，
    /// 所以场景色要先建，人物色阶（只经 RoleMap 引用）排在后面。
    @discardableResult
    public mutating func add(_ name: String, _ color: RGBA8, emissive: Bool = false) -> UInt16 {
        precondition(names.count < 65535, "主调色板超过 65535 项")
        if let i = lookup[name] { base[Int(i)] = color; return i }
        let i = UInt16(names.count)
        names.append(name); base.append(color); self.emissive.append(emissive); lookup[name] = i
        return i
    }
    public func index(_ name: String) -> UInt16 {
        guard let i = lookup[name] else { preconditionFailure("主调色板里没有「\(name)」") }
        return i
    }
    /// 给「格子里直接存索引」的精灵用：必须落在前 256 项里。
    public func direct(_ name: String) -> UInt8 {
        let i = index(name)
        precondition(i < 256, "「\(name)」的索引 \(i) 超出直接索引范围（<256）；场景色要排在人物色阶前面")
        return UInt8(i)
    }
    public func has(_ name: String) -> Bool { lookup[name] != nil }
    public var count: Int { names.count }
}

/// 时段 LUT：主调色板索引 → 打包 RGBA。黎明 / 白天 / 黄昏 / 夜晚 / 台灯光圈各一张。
public struct PaletteLUT: Sendable {
    private static let counter = LockedCounter()
    public let id: Int
    public var table: [UInt32]   // 长度 = 调色板项数（至少 256）

    public init(table: [UInt32]) {
        self.id = PaletteLUT.counter.next()
        var t = table
        if t.count < 256 { t += [UInt32](repeating: 0, count: 256 - t.count) }
        self.table = t
    }

    /// 由主调色板 + 变换生成。emissive 项默认原样保留。
    public static func make(from palette: MasterPalette, keepEmissive: Bool = true,
                            transform: (_ index: Int, _ color: RGBA8) -> RGBA8) -> PaletteLUT {
        var t = [UInt32](repeating: 0, count: max(256, palette.count))
        for i in 0..<palette.count {
            let c = palette.base[i]
            if i == 0 { t[0] = 0; continue }
            let out = (keepEmissive && palette.emissive[i]) ? c : transform(i, c)
            t[i] = out.packed
        }
        return PaletteLUT(table: t)
    }
    /// 不做任何变换（白天）。
    public static func identity(_ palette: MasterPalette) -> PaletteLUT { make(from: palette) { $1 } }
}

final class LockedCounter: @unchecked Sendable {
    private var v = 0
    private let lock = NSLock()
    func next() -> Int { lock.lock(); defer { lock.unlock() }; v += 1; return v }
}

/// 解析好的着色表：精灵里的值 → 打包 RGBA（A/B 两个时段 LUT，用于白天黑夜的抖动过渡）。
/// 同一个 buddy、同一个光照状态只需要建一次。
public final class Resolved: @unchecked Sendable {
    public let master: [UInt16]  // 值 → 主调色板索引
    public let a: [UInt32]       // 值 → 时段 A 的颜色
    public let b: [UInt32]       // 值 → 时段 B 的颜色
    /// 0 = 全用 A，1 = 全用 B，中间按 4×4 Bayer 抖动，每个像素只翻转一次。
    public let progress: Double
    let threshold: Int           // 0…16：bayer 值 < threshold 的像素用 B

    /// - Parameters:
    ///   - map: nil = 值本身就是主调色板索引（道具、房间精灵）
    ///   - glow: 夜间屏幕反光：把 `reflect` 角色的颜色朝这个颜色混合
    public init(map: RoleMap?, lutA: PaletteLUT, lutB: PaletteLUT? = nil, progress: Double = 0,
                glow: RGBA8? = nil, glowAmount: Double = 0.5, reflectBase: UInt8 = Role.hairHi) {
        var m = [UInt16](repeating: 0, count: 256)
        var ta = [UInt32](repeating: 0, count: 256)
        var tb = [UInt32](repeating: 0, count: 256)
        let lb = lutB ?? lutA
        for v in 1..<256 {
            let mi = map?.table[v] ?? UInt16(v)
            m[v] = mi
            ta[v] = lutA.table[Int(mi)]
            tb[v] = lb.table[Int(mi)]
        }
        if let g = glow, let map = map {
            let baseIdx = Int(map.table[Int(reflectBase)])
            func mixPacked(_ p: UInt32) -> UInt32 {
                let c = RGBA8(UInt8(p & 0xFF), UInt8((p >> 8) & 0xFF), UInt8((p >> 16) & 0xFF), 255)
                return c.mixed(with: g, glowAmount).packed
            }
            m[Int(Role.reflect)] = UInt16(baseIdx)
            ta[Int(Role.reflect)] = mixPacked(lutA.table[baseIdx])
            tb[Int(Role.reflect)] = mixPacked(lb.table[baseIdx])
        } else if let map = map {
            // 没有光晕：reflect 就是它落在的那个材质的高光色
            let baseIdx = Int(map.table[Int(reflectBase)])
            m[Int(Role.reflect)] = UInt16(baseIdx)
            ta[Int(Role.reflect)] = lutA.table[baseIdx]
            tb[Int(Role.reflect)] = lb.table[baseIdx]
        }
        master = m; a = ta; b = tb
        let p = max(0, min(1, progress))
        self.progress = p
        threshold = Int((p * 16).rounded(.down))
    }

    @inline(__always) func useB(x: Int, y: Int) -> Bool {
        if threshold <= 0 { return false }
        if threshold >= 16 { return true }
        return Resolved.bayer4[(y & 3) * 4 + (x & 3)] < threshold
    }

    /// 标准 4×4 Bayer 矩阵（0…15）。
    public static let bayer4: [Int] = [
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5,
    ]
}
