import Foundation
import PixelKit

extension PropArt {
    /// 桌子 52×24：桌面（俯视 13 行）+ 桌沿 + 前脸 + 两条桌腿。
    /// 用代码生成（木纹按固定规则撒，所以永远逐像素一样）。
    static func buildDesk(_ b: SpriteBook, name: String, wood: (hi: String, base: String, sh: String, out: String), legHi: String, legBase: String) {
        let w = 52, h = 24
        var g = Grid(w: w, h: h)
        let hi = Pal.dx(wood.hi), base = Pal.dx(wood.base), sh = Pal.dx(wood.sh), out = Pal.dx(wood.out)
        let legH = Pal.dx(legHi), legB = Pal.dx(legBase)
        // 桌腿（先画，桌面盖在上面）
        for y in 17..<24 {
            for x in 3...5 { g[x, y] = (x == 3) ? legH : legB }
            for x in 46...48 { g[x, y] = (x == 46) ? legH : legB }
        }
        for x in [2, 6, 45, 49] { for y in 17..<24 { g[x, y] = out } }
        for x in 2...6 { g[x, 23] = out }
        for x in 45...49 { g[x, 23] = out }
        // 桌面：第 0 行是后沿，1…12 是桌面，13 是桌沿高光，14…15 前脸，16 前脸下沿
        for x in 1...50 { g[x, 0] = out }
        for y in 1...12 {
            g[0, y] = out; g[51, y] = out
            for x in 1...50 {
                var c = base
                if y == 1 { c = hi }                          // 后沿受光
                if x == 1 { c = hi }                          // 左沿受光
                if x == 50 || y == 12 { c = sh }              // 右、前边缘压暗
                g[x, y] = c
            }
        }
        // 木纹：浅色细线，位置由简单的确定性规则决定
        for y in stride(from: 3, through: 11, by: 3) {
            var x = 3 + (y * 7) % 9
            while x < 49 {
                let len = 4 + ((x * 3 + y) % 5)
                for k in 0..<len where x + k < 49 { g[x + k, y] = sh }
                x += len + 6 + ((x + y) % 5)
            }
        }
        for x in 0...51 { g[x, 13] = out }
        for x in 1...50 { g[x, 14] = hi }
        for x in 1...50 { g[x, 15] = base }
        for x in 1...50 { g[x, 16] = sh }
        g[0, 14] = out; g[0, 15] = out; g[0, 16] = out; g[51, 14] = out; g[51, 15] = out; g[51, 16] = out
        for x in 1...50 { g[x, 17] = out }
        // 右侧前脸压一点影
        for y in 14...16 { g[50, y] = sh }
        b.add(g.sprite(name: name, anchors: ["top": IntPoint(0, 1), "topBottom": IntPoint(0, 12), "front": IntPoint(0, 14)]))
    }

    static func buildDesks(_ b: SpriteBook) {
        buildDesk(b, name: "desk.oak", wood: ("woodOak.hi", "woodOak.base", "woodOak.sh", "woodOak.out"), legHi: "metal.base", legBase: "metal.sh")
        buildDesk(b, name: "desk.walnut", wood: ("woodWalnut.hi", "woodWalnut.base", "woodWalnut.sh", "woodWalnut.out"), legHi: "metal.base", legBase: "metal.sh")
    }
}
