import Foundation
import PixelKit

/// 道具 / 房间精灵的字符表：字符 → 主调色板名（格子里直接存主调色板索引，必须落在前 256 项）。
/// 所有道具共用这一张表，所以同一个字符在任何精灵里都是同一种颜色。
///
///   #  ink1 描边        @ ink0 最深        %  ink2 中深        1 ink3 浅描边
///   B/b/y 塑料 高光/基/影     M/m/n/N 金属 高光/基/影/最深      W/w/v 白 高光/基/影      p/q 纸 基/影
///   O/o/x/X 橡木 高光/基/影/边      D/d/f/F 胡桃木 高光/基/影/边
///   L/l/e/E 叶 高光/基/影/深       T/t/u/S 花盆 高光/基/影 + 土
///   R/r/s 红 高光/基/影         U/c/k 蓝 高光/基/影         G/g/h 金 高光/基/影
///   J/j/K 小黄鸭 高光/基/影     Q 鸭嘴橙           P/z 粉 基/影
///   墙：0 高光 9 基 8 影 7 深    护墙板：6 高光 5 基 4 影 3 深    踢脚/窗框：2 高光 ( 基 ) 影
///   地板：^ 高光 = 基 v? 见下   （地板/地毯多用图元直接画，不走精灵）
///   屏幕（自发光）：a bg  A bg2  C bg3  V 白  Y 暗字  Z 深字  i 青  I 绿  H 琥珀  ! 红  * 蓝  ? 粉  ~ 紫  : 橙  ; 终端黑
///   灯：* 用 lamp.core → `[`  lamp.glow → `]`    提示：`{` ui.ok  `}` ui.info  `<` ui.warn  `>` ui.danger  `$` ui.key  `+` ui.note
///   气泡：`"` fill  `'` line  `,` sh          led：`|` on  `/` wait  `\` off
public enum PropLegend {
    public static let table: [Character: String] = [
        "#": "ink1", "@": "ink0", "%": "ink2", "1": "ink3",
        "B": "plastic.hi", "b": "plastic.base", "y": "plastic.sh",
        "M": "metal.hi", "m": "metal.base", "n": "metal.sh", "N": "metal.deep",
        "W": "white.hi", "w": "white.base", "v": "white.sh", "p": "paper.base", "q": "paper.sh",
        "O": "woodOak.hi", "o": "woodOak.base", "x": "woodOak.sh", "X": "woodOak.out",
        "D": "woodWalnut.hi", "d": "woodWalnut.base", "f": "woodWalnut.sh", "F": "woodWalnut.out",
        "L": "leaf.hi", "l": "leaf.base", "e": "leaf.sh", "E": "leaf.deep",
        "T": "pot.hi", "t": "pot.base", "u": "pot.sh", "S": "soil",
        "R": "red.hi", "r": "red.base", "s": "red.sh",
        "U": "blue.hi", "c": "blue.base", "k": "blue.sh",
        "G": "gold.hi", "g": "gold.base", "h": "gold.sh",
        "J": "duck.hi", "j": "duck.base", "K": "duck.sh", "Q": "beak",
        "P": "pink.base", "z": "pink.sh",
        "0": "wall.hi", "9": "wall.base", "8": "wall.sh", "7": "wall.deep",
        "6": "dado.hi", "5": "dado.base", "4": "dado.sh", "3": "dado.deep",
        "2": "trim.hi", "(": "trim.base", ")": "trim.sh",
        "a": "scr.bg", "A": "scr.bg2", "C": "scr.bg3", "V": "scr.white", "Y": "scr.dim", "Z": "scr.dark",
        "i": "scr.cyan", "I": "scr.green", "H": "scr.amber", "!": "scr.red", "*": "scr.blue", "?": "scr.pink",
        "~": "scr.purple", ":": "scr.orange", ";": "scr.term",
        "[": "lamp.core", "]": "lamp.glow",
        "{": "ui.ok", "}": "ui.info", "<": "ui.warn", ">": "ui.danger", "$": "ui.key", "+": "ui.note",
        "\"": "bubble.fill", "'": "bubble.line", ",": "bubble.sh",
        "|": "led.on", "/": "led.wait", "\\": "led.off",
    ]

    public static let legend: SpriteLegend = {
        var m: [Character: UInt8] = [".": 0]
        for (ch, name) in table { m[ch] = Pal.dx(name) }
        return SpriteLegend(m)
    }()

    /// 给 Grid.overlay 用的字符表（其中 `_` 保留作「擦除」，所以这里不含）。
    static var gridLegend: [Character: UInt8] { legend.map }
}
