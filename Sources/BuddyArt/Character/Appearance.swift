import Foundation
import PixelKit

public enum Facing: Int, Sendable, CaseIterable {
    case back = 0, threeQuarterBack, side, threeQuarterFront, front
    public var isFrontish: Bool { self == .side || self == .threeQuarterFront || self == .front }
    public var name: String { ["back", "q34back", "side", "q34front", "front"][rawValue] }
}

public enum Outfit: Int, Sendable, CaseIterable { case tee = 0, hoodie, cardigan, shirt, vest, jacket
    public var name: String { ["tee", "hoodie", "cardigan", "shirt", "vest", "jacket"][rawValue] }
}
public enum HairStyle: Int, Sendable, CaseIterable { case ponytail = 0, bun, twinBuns, longHair, bob, messy, buzz, curly
    public var name: String { ["ponytail", "bun", "twinBuns", "long", "bob", "messy", "buzz", "curly"][rawValue] }
}
public enum Accessory: Int, Sendable, CaseIterable { case none = 0, headphones, glasses, beanie, hairpin, scarf
    public var name: String { ["none", "headphones", "glasses", "beanie", "hairpin", "scarf"][rawValue] }
}
public enum ChairStyle: Int, Sendable, CaseIterable { case mesh = 0, gaming, wood
    public var name: String { ["mesh", "gaming", "wood"][rawValue] }
}
public enum DeskOrnament: Int, Sendable, CaseIterable { case duck = 0, figure, photoFrame, cactus, luckyCat, none }
public enum MonitorKind: Int, Sendable { case flat = 0, crt }

/// 一个 buddy 的全部外观选择（由种子确定性地抽出来）。
public struct Appearance: Sendable, Equatable, Hashable {
    public var skin: Int          // 0..4
    public var hairStyle: HairStyle
    public var hairColor: Int     // 0..7
    public var outfit: Outfit
    public var clothColor: Int    // 0..9
    public var pants: Int         // 0..3
    public var accessory: Accessory
    public var accessoryColor: Int // 0..5（耳机、发夹、围巾颜色）
    public var chair: ChairStyle
    public var chairColor: Int    // 0..5
    public var mugColor: Int      // 0..5
    public var ornament: DeskOrnament
    public var monitor: MonitorKind
    public var plant: Int         // 0..2 桌边小植物变体（仅装饰）

    /// 用 SplitMix64 按固定顺序逐个抽取。顺序就是接口：改顺序会让所有人的外观变掉。
    public static func generate(seed: UInt64) -> Appearance {
        var r = PixelRNG(seed: seed)
        let skin = r.below(5)
        let hairStyle = HairStyle(rawValue: r.below(HairStyle.allCases.count))!
        let hairColor = r.below(8)
        let outfit = Outfit(rawValue: r.below(Outfit.allCases.count))!
        let clothColor = r.below(10)
        let pants = r.below(4)
        // 配饰：一半的人没有
        let accRoll = r.below(10)
        let accessory: Accessory = accRoll < 4 ? .none : Accessory(rawValue: 1 + (accRoll - 4) % 5)!
        var accessoryColor = r.below(6)
        // 背心 / 开衫 / 衬衫的里层用点缀色：衣服色和点缀色同色系时只剩深色描边分层，对比很弱，换一个
        if outfit == .vest || outfit == .cardigan || outfit == .shirt {
            var n = 0
            while Appearance.sameFamily(cloth: clothColor, accent: accessoryColor) && n < 6 { accessoryColor = (accessoryColor + 1) % 6; n += 1 }
        }
        // 点缀色（耳机、帽子、发夹、围巾）避开和头发 / 衣服同色系的：白配银发、黄配金发 / 黄衣服都会糊成一团
        if accessory != .none {
            var n = 0
            while Appearance.accentBlends(accent: accessoryColor, hair: hairColor, cloth: clothColor) && n < 6 { accessoryColor = (accessoryColor + 1) % 6; n += 1 }
        }
        let chair = ChairStyle(rawValue: r.below(3))!
        let chairColor = r.below(6)
        let mugColor = r.below(6)
        let ornament = DeskOrnament(rawValue: r.below(6))!
        let monitor: MonitorKind = r.below(10) == 0 ? .crt : .flat
        let plant = r.below(3)
        return Appearance(skin: skin, hairStyle: hairStyle, hairColor: hairColor, outfit: outfit, clothColor: clothColor,
                          pants: pants, accessory: accessory, accessoryColor: accessoryColor, chair: chair,
                          chairColor: chairColor, mugColor: mugColor, ornament: ornament, monitor: monitor, plant: plant)
    }

    /// 点缀色阶（红 黄 薄荷 天蓝 淡紫 白）和头发（黑 棕 栗 金 红 银 玫红 青）/ 衣服是不是撞色系。
    static func accentBlends(accent: Int, hair: Int, cloth: Int) -> Bool {
        if sameFamily(cloth: cloth, accent: accent) { return true }
        switch accent {
        case 0: return hair == 4 || hair == 6
        case 1: return hair == 3 || hair == 2
        case 3: return hair == 7
        case 5: return hair == 5
        default: return false
        }
    }

    /// 衣服色阶（红 橙 黄 绿 青 天蓝 靛 紫 粉 奶油）和点缀色阶（红 黄 薄荷 天蓝 淡紫 白）是不是同一个色系。
    static func sameFamily(cloth: Int, accent: Int) -> Bool {
        switch accent {
        case 0: return cloth == 0 || cloth == 1 || cloth == 8
        case 1: return cloth == 2 || cloth == 1
        case 2: return cloth == 3 || cloth == 4
        case 3: return cloth == 5 || cloth == 4 || cloth == 6
        case 4: return cloth == 7 || cloth == 6 || cloth == 8
        default: return cloth == 9
        }
    }

    /// 不撞衫：「发型 + 发色」或「衣服 + 颜色」至少有一组和已有的人不同。
    public func collides(with o: Appearance) -> Bool {
        (hairStyle == o.hairStyle && hairColor == o.hairColor) || (outfit == o.outfit && clothColor == o.clothColor)
    }

    /// 给一组已在场的外观，为这个 key 找一个不撞衫的：撞了就用 salt+1 重抽（最多试 24 次）。
    /// seedForSalt 把 salt 变成种子（BuddyStage 里用 BuddyCore 的 AppearanceSeed）。返回最终的（salt, 外观）。
    public static func resolve(salt: UInt64, existing: [Appearance], seedForSalt: (UInt64) -> UInt64) -> (salt: UInt64, appearance: Appearance) {
        var s = salt
        for _ in 0..<24 {
            let a = generate(seed: seedForSalt(s))
            if !existing.contains(where: { a.collides(with: $0) }) { return (s, a) }
            s &+= 1
        }
        return (s, generate(seed: seedForSalt(s)))
    }

    // MARK: 角色 → 主调色板索引
    public var roleMap: RoleMap {
        var m = RoleMap()
        let sk = Pal.skinRamps[skin]
        m[Role.skinHi] = sk.hi; m[Role.skin] = sk.base; m[Role.skinSh] = sk.sh; m[Role.outSkin] = sk.out
        // 腮红：肤色朝红色偏一点，落在色阶里最近的暖色——这里直接用 accRed 的高光级（很淡）不合适，所以取肤色阴影
        m[Role.blush] = Pal.blushColors[skin]
        let hr = Pal.hairRamps[hairColor]
        m[Role.hairHi] = hr.hi; m[Role.hair] = hr.base; m[Role.hairSh] = hr.sh; m[Role.outHair] = hr.out
        let cl = Pal.clothRamps[clothColor]
        m[Role.clothHi] = cl.hi; m[Role.cloth] = cl.base; m[Role.clothSh] = cl.sh; m[Role.outCloth] = cl.out
        let pn = Pal.pantsRamps[pants]
        m[Role.pants] = pn.base; m[Role.pantsSh] = pn.sh
        let ac = Pal.accentRamps[accessoryColor]
        m[Role.accent] = ac.base; m[Role.accentSh] = ac.sh
        m[Role.accent2] = ac.hi
        let ch = Pal.chairRamps[chairColor]
        m[Role.chair] = ch.base; m[Role.chairSh] = ch.sh
        m[Role.eye] = Pal.ix("eye"); m[Role.eyeWhite] = Pal.ix("eyeWhite"); m[Role.mouth] = Pal.ix("mouth")
        m[Role.spark] = Pal.ix("spark"); m[Role.lens] = Pal.ix("lens"); m[Role.shoe] = Pal.ix("shoe")
        m[Role.reflect] = hr.hi
        return m
    }
}
