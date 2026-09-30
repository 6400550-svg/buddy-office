import Testing
import Foundation
import PixelKit
@testable import BuddyArt

/// 精灵网格校验（行宽、角色是否合法、锚点是否落在图内 —— 解析器会把这些错误记进 book.errors）+ 朝向是否齐全 + 调色板对比度。
@Suite struct SpriteAndPaletteTests {
    @Test func spriteBooksHaveNoErrors() {
        #expect(CharacterArt.book.errors.isEmpty, "\(CharacterArt.book.errors.map { $0.description })")
        #expect(PropArt.book.errors.isEmpty, "\(PropArt.book.errors.map { $0.description })")
        #expect(RoomArt.book.errors.isEmpty, "\(RoomArt.book.errors.map { $0.description })")
        #expect(BubbleArt.book.errors.isEmpty, "\(BubbleArt.book.errors.map { $0.description })")
        #expect(HelperArt.book.errors.isEmpty, "\(HelperArt.book.errors.map { $0.description })")
    }

    @Test func everyHairOutfitAndHeadHasAllFiveFacings() {
        let book = CharacterArt.book
        var missing: [String] = []
        for f in Facing.allCases {
            if book.get("head.\(f.name)") == nil { missing.append("head.\(f.name)") }
            for h in HairStyle.allCases where book.get("hair.\(h.name).\(f.name)") == nil { missing.append("hair.\(h.name).\(f.name)") }
            for o in Outfit.allCases where book.get("torso.\(o.name).\(f.name)") == nil { missing.append("torso.\(o.name).\(f.name)") }
        }
        #expect(missing.isEmpty, "缺少：\(missing)")
    }

    @Test func spritesAreNotEmptyAndAnchorsInside() {
        for book in [CharacterArt.book, PropArt.book, RoomArt.book, BubbleArt.book, HelperArt.book] {
            for name in book.order {
                let s = book[name]
                #expect(s.opaqueCount > 0, "精灵 \(name) 是空的")
                for (k, p) in s.anchors { #expect(p.x >= 0 && p.y >= 0 && p.x < s.width && p.y < s.height, "\(name) 的锚点 \(k) 出界") }
            }
        }
    }

    // MARK: 调色板
    struct Lab { var L: Double, a: Double, b: Double }
    static func lab(_ c: RGBA8) -> Lab {
        func lin(_ v: UInt8) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return Lab(L: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)))
    }
    static func color(_ i: UInt16) -> RGBA8 { Pal.master.base[Int(i)] }
    static func dE(_ p: RGBA8, _ q: RGBA8) -> Double {
        let a = lab(p), b = lab(q)
        return ((a.L - b.L) * (a.L - b.L) + (a.a - b.a) * (a.a - b.a) + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    /// 描边和填充的亮度差 ΔL ≥ 0.15（L 按 0…1 算）：选择性描边的轮廓才读得出来。
    @Test func outlineIsDarkerThanFillByAtLeastPointOneFive() {
        let groups: [(String, [Ramp])] = [("肤色", Pal.skinRamps), ("发色", Pal.hairRamps), ("衣服", Pal.clothRamps), ("裤子", Pal.pantsRamps),
                                          ("椅子", Pal.chairRamps), ("点缀", Pal.accentRamps)]
        for (name, ramps) in groups {
            for (i, r) in ramps.enumerated() {
                let dl = abs(Self.lab(Self.color(r.base)).L - Self.lab(Self.color(r.out)).L) / 100
                #expect(dl >= 0.15, "\(name) #\(i) 描边和填充的 ΔL = \(String(format: "%.3f", dl)) < 0.15")
            }
        }
    }

    /// 不同发色之间 ΔE ≥ 12：同时在场的人靠发色区分。
    @Test func hairColorsAreFarApart() {
        let hairs = Pal.hairRamps.map { Self.color($0.base) }
        for i in 0..<hairs.count { for j in (i + 1)..<hairs.count {
            let d = Self.dE(hairs[i], hairs[j])
            #expect(d >= 12, "发色 #\(i) 和 #\(j) 的 ΔE = \(String(format: "%.1f", d)) < 12")
        } }
    }

    /// 直接存索引的道具精灵要求这些颜色的主调色板索引 < 256。
    @Test func directIndexedPaletteEntriesFitInOneByte() {
        for name in ["ink0", "ink1", "floor.base", "wall.base", "woodOak.base", "bubble.fill", "woodWalnut.base"] {
            #expect(Pal.master.index(name) < 256, "\(name) 索引 ≥ 256")
        }
    }
}
