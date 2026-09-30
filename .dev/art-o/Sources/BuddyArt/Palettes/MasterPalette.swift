import Foundation
import PixelKit

/// 一组色阶（主调色板索引）：高光 / 基色 / 阴影 / 描边（选择性描边用的深色，不是纯黑）。
public struct Ramp: Sendable {
    public var hi: UInt16, base: UInt16, sh: UInt16, out: UInt16
}

/// 主调色板 + 时段 LUT + 人物色阶表。所有颜色都在这里，别处只引用名字或索引。
///
/// 设计取舍（记在 DESIGN.md）：任务书要求主调色板「不超过 48 色」。人物有 5 种肤色 + 8 种发色 + 10 种衣服色，
/// 每组还要 3–4 阶，硬压到 48 是做不到的。所以做法是：场景核心色刻意收得很紧（约 70 个），人物色阶另放一段，
/// 一个 buddy 同屏只会用到 1 肤色 + 1 发色 + 1 衣色 + 1 裤色的色阶。总量控制在 256 以内（UInt8 索引）。
public enum Pal {
    struct Built {
        var master = MasterPalette()
        var skin: [Ramp] = [], hair: [Ramp] = [], cloth: [Ramp] = [], pants: [Ramp] = []
        var chair: [Ramp] = [], accent: [Ramp] = [], wood: [Ramp] = []
    }
    // 一次性整体建好，避免「色阶数组先于调色板被读到」的初始化顺序问题。
    private static let built: Built = build()

    public static var master: MasterPalette { built.master }
    public static var skinRamps: [Ramp] { built.skin }
    public static var hairRamps: [Ramp] { built.hair }
    public static var clothRamps: [Ramp] { built.cloth }
    public static var pantsRamps: [Ramp] { built.pants }
    public static var chairRamps: [Ramp] { built.chair }
    public static var accentRamps: [Ramp] { built.accent }
    public static var woodRamps: [Ramp] { built.wood }

    /// 名字 → 主调色板索引。
    public static func ix(_ name: String) -> UInt16 { built.master.index(name) }
    /// 直接存索引的精灵用（必须 < 256）。
    public static func dx(_ name: String) -> UInt8 { built.master.direct(name) }

    private static func build() -> Built {
        var b = Built()
        var p = MasterPalette()
        func c(_ hex: UInt32) -> RGBA8 { RGBA8(hex: hex) }
        func ramp(_ name: String, _ hi: UInt32, _ base: UInt32, _ sh: UInt32, _ out: UInt32) -> Ramp {
            Ramp(hi: p.add("\(name).hi", c(hi)), base: p.add("\(name).base", c(base)),
                 sh: p.add("\(name).sh", c(sh)), out: p.add("\(name).out", c(out)))
        }

        // —— 深色中性（描边、字、缝隙）：暖调，不用纯黑 ——
        p.add("ink0", c(0x1B1620)); p.add("ink1", c(0x2A2230)); p.add("ink2", c(0x3C3244)); p.add("ink3", c(0x574B5E))

        // 人物固定色
        p.add("eye", c(0x2A2230)); p.add("eyeWhite", c(0xFFF8F0)); p.add("mouth", c(0xB4504C))
        p.add("spark", c(0xFFFFFF)); p.add("lens", c(0xBFE6FF)); p.add("shoe", c(0x3B2A26))

        // —— 墙、地、家具（场景核心色）——
        // 墙纸（奶油）
        p.add("wall.hi", c(0xFAF0DA)); p.add("wall.base", c(0xEEDFC0)); p.add("wall.sh", c(0xD8C6A2)); p.add("wall.deep", c(0xBEA984))
        // 护墙板（鼠尾草绿）
        p.add("dado.hi", c(0x9CC2B2)); p.add("dado.base", c(0x7EA595)); p.add("dado.sh", c(0x628A7A)); p.add("dado.deep", c(0x486C60))
        // 踢脚线 / 窗框 / 白色木作
        p.add("trim.hi", c(0xFFFBF0)); p.add("trim.base", c(0xF3EAD6)); p.add("trim.sh", c(0xCBBEA4))
        // 地板（暖木）
        p.add("floor.hi", c(0xDDB27F)); p.add("floor.base", c(0xC99A68)); p.add("floor.sh", c(0xAC7D4F)); p.add("floor.gap", c(0x8B6240))
        // 地毯（雾蓝）
        p.add("rug.hi", c(0x86A6C8)); p.add("rug.base", c(0x6588B0)); p.add("rug.sh", c(0x4C6C94)); p.add("rug.line", c(0xEAC97A))
        // 金属 / 塑料
        p.add("metal.hi", c(0xD4D9E4)); p.add("metal.base", c(0xA1A9BB)); p.add("metal.sh", c(0x717A90)); p.add("metal.deep", c(0x4E566B))
        p.add("plastic.hi", c(0x4E5366)); p.add("plastic.base", c(0x363A4A)); p.add("plastic.sh", c(0x232632))
        p.add("white.hi", c(0xFFFFFF)); p.add("white.base", c(0xF3F0F6)); p.add("white.sh", c(0xC9C4D2))
        p.add("paper.base", c(0xFFF6E0)); p.add("paper.sh", c(0xE2D3B0))
        // 植物 / 花盆
        p.add("leaf.hi", c(0x8BDB8E)); p.add("leaf.base", c(0x4FB06B)); p.add("leaf.sh", c(0x2F8258)); p.add("leaf.deep", c(0x1D5842))
        p.add("pot.hi", c(0xEC9468)); p.add("pot.base", c(0xC96C46)); p.add("pot.sh", c(0x9A4B30)); p.add("soil", c(0x4A2F26))
        // 窗外 / 天空基色（真正的天空按时间直接算 RGB，这里放窗玻璃反光、云的底色）
        p.add("glass.hi", c(0xE8F6FF)); p.add("cloud.hi", c(0xFFFFFF)); p.add("cloud.sh", c(0xDCE8F6))
        // 杂物用的几个暖色 / 冷色（书、海报、手办、小鸭……）
        p.add("duck.hi", c(0xFFEC8A)); p.add("duck.base", c(0xFFD23F)); p.add("duck.sh", c(0xD9A21E)); p.add("beak", c(0xFF8B3D))
        p.add("red.hi", c(0xF58A7E)); p.add("red.base", c(0xD9534F)); p.add("red.sh", c(0x9E2F3A))
        p.add("blue.hi", c(0x8EBAF0)); p.add("blue.base", c(0x4F80CB)); p.add("blue.sh", c(0x32549A))
        p.add("gold.hi", c(0xFFE58A)); p.add("gold.base", c(0xF0BA3C)); p.add("gold.sh", c(0xB98421))
        p.add("pink.base", c(0xF29AB8)); p.add("pink.sh", c(0xC0688C))
        p.add("shadow", c(0x2A2230)); // 地面软影用（配合抖动）

        // —— 自发光（不受时段 LUT 影响）：屏幕、灯、指示灯、UI 提示 ——
        p.add("scr.bg", c(0x1A1F2E), emissive: true); p.add("scr.bg2", c(0x232A3C), emissive: true); p.add("scr.bg3", c(0x2E3650), emissive: true)
        p.add("scr.white", c(0xF2F6FF), emissive: true); p.add("scr.dim", c(0x8B95B0), emissive: true); p.add("scr.dark", c(0x4A5470), emissive: true)
        p.add("scr.cyan", c(0x6FE3FF), emissive: true); p.add("scr.green", c(0x7DF0A0), emissive: true)
        p.add("scr.amber", c(0xFFC857), emissive: true); p.add("scr.red", c(0xFF7676), emissive: true)
        p.add("scr.blue", c(0x74A8FF), emissive: true); p.add("scr.pink", c(0xFF8AD8), emissive: true)
        p.add("scr.purple", c(0xB48CFF), emissive: true); p.add("scr.orange", c(0xFF9A4A), emissive: true)
        p.add("scr.term", c(0x0E1A14), emissive: true)
        p.add("led.on", c(0x7DFFB0), emissive: true); p.add("led.wait", c(0xFFB454), emissive: true); p.add("led.off", c(0x3A4054), emissive: true)
        p.add("lamp.core", c(0xFFF3C4), emissive: true); p.add("lamp.glow", c(0xFFDD8A), emissive: true)
        p.add("ui.ok", c(0x66E08A), emissive: true); p.add("ui.info", c(0x5FB0FF), emissive: true)
        p.add("ui.warn", c(0xFFB13C), emissive: true); p.add("ui.danger", c(0xFF6B6B), emissive: true)
        p.add("ui.key", c(0xFFCB4D), emissive: true); p.add("ui.note", c(0xFFE873), emissive: true)
        p.add("bubble.fill", c(0xFFFDF6), emissive: true); p.add("bubble.line", c(0x3A3040), emissive: true); p.add("bubble.sh", c(0xD9D2E4), emissive: true)
        // —— 木头 ×2（桌面浅橡木 / 深胡桃木）——
        b.wood = [
            ramp("woodOak", 0xE6BB86, 0xCB9560, 0xA0704A, 0x6C4A30),
            ramp("woodWalnut", 0xA47252, 0x7E5540, 0x5C3D2E, 0x3A241B),
        ]
        precondition(p.count <= 256, "场景色（含自发光）必须排在前 256 项里，现在有 \(p.count) 项")

        // —— 肤色 ×5（浅 → 深）——
        b.skin = [
            ramp("skin1", 0xFCDCC6, 0xF0BC9E, 0xCB8E7A, 0x94605A),
            ramp("skin2", 0xF6CBA4, 0xE3A97E, 0xBC7F60, 0x83503F),
            ramp("skin3", 0xDDA77B, 0xC48963, 0x976450, 0x673D31),
            ramp("skin4", 0xB07553, 0x8F5E40, 0x6D4333, 0x452A22),
            ramp("skin5", 0x80503A, 0x64392A, 0x482920, 0x2C1A14),
        ]
        // —— 发色 ×8 ——
        b.hair = [
            ramp("hairBlack",  0x554E66, 0x352F42, 0x231E2E, 0x161221),
            ramp("hairBrown",  0x8A5E41, 0x664330, 0x472D22, 0x281810),
            ramp("hairChest",  0xB87C48, 0x94582F, 0x683C22, 0x3E2314),
            ramp("hairBlond",  0xF6DC94, 0xE1BA60, 0xB48D42, 0x725623),
            ramp("hairRed",    0xEE9560, 0xCC6633, 0x94441F, 0x5B2810),
            ramp("hairSilver", 0xEAEAF1, 0xBDBECB, 0x8D8FA4, 0x565870),
            ramp("hairRose",   0xF8A9C6, 0xE477A3, 0xB34E7E, 0x702E4E),
            ramp("hairTeal",   0x78D6E4, 0x45A6C2, 0x2D7794, 0x184960),
        ]
        // —— 衣服色 ×10（背影要靠它认人，所以色相拉开）——
        b.cloth = [
            ramp("clothRed",    0xF27A6E, 0xD64C4C, 0xA13040, 0x64202E),
            ramp("clothOrange", 0xFFB170, 0xF08434, 0xB95A22, 0x763714),
            ramp("clothYellow", 0xFFE384, 0xF2C244, 0xBE922A, 0x7B5A18),
            ramp("clothGreen",  0x8EDC8A, 0x54B764, 0x338648, 0x1E532F),
            ramp("clothTeal",   0x74D9CB, 0x38AFA5, 0x237E7C, 0x134C50),
            ramp("clothSky",    0x9CCBFF, 0x5F9BEB, 0x3F6CB4, 0x274270),
            ramp("clothIndigo", 0x8F94E8, 0x5D62C4, 0x40449A, 0x272866),
            ramp("clothPurple", 0xC896E8, 0x9D62C7, 0x72429A, 0x462766),
            ramp("clothPink",   0xFFB2CE, 0xEE7FAA, 0xB85585, 0x772F55),
            ramp("clothCream",  0xFFF8E8, 0xE9DCC0, 0xB9A98E, 0x776B5A),
        ]
        // —— 裤子 ×4 ——
        b.pants = [
            ramp("pantsDenim", 0x6A88B8, 0x4C6796, 0x364A74, 0x222F4E),
            ramp("pantsCharcoal", 0x5C5C6C, 0x43434F, 0x2E2E38, 0x1C1C24),
            ramp("pantsKhaki", 0xD4BD8A, 0xB89C68, 0x8E7448, 0x5A4A2C),
            ramp("pantsBrown", 0x86603F, 0x68462E, 0x4A3122, 0x2C1C14),
        ]
        // —— 椅子 ×6（网面灰 / 黑 / 竞技红 / 竞技蓝 / 木 / 奶油）——
        b.chair = [
            ramp("chairGrey",  0x8E94A6, 0x6C7286, 0x4C5164, 0x2E3141),
            ramp("chairBlack", 0x4E5264, 0x393C4C, 0x282A36, 0x181920),
            ramp("chairRed",   0xB4525A, 0x8F3C48, 0x682A36, 0x3F1822),
            ramp("chairBlue",  0x5C7CA8, 0x445E86, 0x30456A, 0x1D2A44),
            ramp("chairWood",  0xB88C5C, 0x966C42, 0x724E2E, 0x4A301C),
            ramp("chairCream", 0xE2D6BC, 0xC6B896, 0x9E8F70, 0x625744),
        ]
        // —— 点缀色 ×6（马克杯、耳机、发带、围巾）——
        b.accent = [
            ramp("accRed",    0xFF8E7E, 0xE85A4F, 0xB03838, 0x6E2030),
            ramp("accYellow", 0xFFE690, 0xF7C948, 0xC29A2A, 0x7B5E18),
            ramp("accMint",   0xA6EFCB, 0x5FD1A0, 0x3AA07C, 0x1F6650),
            ramp("accSky",    0xA8DCFF, 0x62B4F0, 0x3F82BE, 0x244F7C),
            ramp("accLilac",  0xDCB8FF, 0xB07FE8, 0x8455B8, 0x513278),
            ramp("accWhite",  0xFFFFFF, 0xF0EEF4, 0xC4C0CE, 0x8A8494),
        ]

        b.master = p
        return b
    }
}
