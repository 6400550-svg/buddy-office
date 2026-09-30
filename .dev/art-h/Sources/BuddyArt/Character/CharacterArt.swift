import Foundation
import PixelKit

/// 全部人物精灵的注册表。启动时构建一次（代码形式的美术）。
/// 命名：head.<朝向> / hair.<发型>.<朝向> / torso.<衣服>.<朝向> / arm.<姿势> / leg.<姿势> / chair.<款式>.<朝向> …
/// 朝向 back / q34back / side / q34front / front 是「朝向画面右侧」的版本；朝左直接水平翻转。
public enum CharacterArt {
    public static let book: SpriteBook = {
        let b = SpriteBook()
        buildHeads(b)
        buildHair(b)
        buildTorso(b)
        buildArms(b)
        buildChairs(b)
        buildMug(b)
        return b
    }()
    public static func sprite(_ name: String) -> IndexedSprite { book[name] }

    /// 头部盒子尺寸（头 + 头发共 13 高）。
    public static let headW = 12, headH = 13
    /// 头发精灵的画布比头盒子大一圈（马尾、丸子头、长发会伸出去），头盒子左上角在这里：
    public static let hairPad = IntPoint(2, 3)
    public static let hairW = 16, hairH = 20
}

extension CharacterArt {
    /// 把几个角色精灵叠成一个（后面的盖住前面的），锚点丢掉。调试总表和整套部件预览用。
    static func flatten(name: String, parts: [(IndexedSprite, Int, Int)], size: (Int, Int)) -> IndexedSprite {
        var g = Grid(w: size.0, h: size.1)
        for (s, dx, dy) in parts {
            for y in 0..<s.height { for x in 0..<s.width {
                let v = s.pixels[y * s.width + x]
                if v != 0 { g[x + dx, y + dy] = v }
            } }
        }
        return g.sprite(name: name)
    }

    /// 头 + 发 的合成预览（每个发型 × 每个朝向），只用来看。
    public static let previewBook: SpriteBook = {
        let out = SpriteBook()
        for style in HairStyle.allCases {
            for f in Facing.allCases {
                guard let hair = book.get("hair.\(style.name).\(f.name)") else { continue }
                let head = book["head.\(f.name)"]
                let s = flatten(name: "look.\(style.name).\(f.name)", parts: [(head, hairPad.x, hairPad.y), (hair, 0, 0)], size: (hairW, hairH))
                out.add(s)
            }
        }
        return out
    }()
}
