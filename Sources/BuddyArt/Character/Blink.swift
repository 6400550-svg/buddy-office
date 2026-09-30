import Foundation
import PixelKit

extension CharacterArt {
    /// 眨眼：程序生成的脸覆盖层（正面 / 3/4 正面 / 侧面），只动眼睛。
    ///  blinkHalf   眼睛被眼皮盖住上面一半；
    ///  blinkClosed 眼睛闭成一条线。
    /// 覆盖层用肤色把底下睁着的眼睛盖掉，再画上眼皮线；肤色明暗和头精灵的脸一致（眼睛那一带都在脸的内部，是基色）。
    static func buildBlink(_ book: SpriteBook) {
        func make(_ facing: Facing, eyes: [(x: Int, w: Int)], half: Bool) -> IndexedSprite {
            var g = Grid(w: 12, h: 13)
            for e in eyes {
                for y in 7...9 { for x in e.x..<(e.x + e.w) { g[x, y] = Role.skin } }
                if half {
                    for x in e.x..<(e.x + e.w) { g[x, 8] = Role.outSkin; g[x, 9] = Role.eye }
                    if e.w == 2 { g[e.x, 9] = Role.eye; g[e.x + 1, 9] = Role.eye }
                } else {
                    for x in e.x..<(e.x + e.w) { g[x, 8] = Role.eye }
                }
            }
            return g.sprite(name: "face.\(half ? "blinkHalf" : "blinkClosed").\(facing.name)")
        }
        // 眼睛位置（见 Heads.swift 里的中性脸）：front 第 3–4、7–8 列；q34front 第 4–5 列和第 8 列；side 第 8–9 列
        let layouts: [(Facing, [(x: Int, w: Int)])] = [
            (.front, [(3, 2), (7, 2)]),
            (.threeQuarterFront, [(4, 2), (8, 1)]),
            (.side, [(8, 2)]),
        ]
        for (f, eyes) in layouts {
            book.add(make(f, eyes: eyes, half: true))
            book.add(make(f, eyes: eyes, half: false))
        }
    }
}
