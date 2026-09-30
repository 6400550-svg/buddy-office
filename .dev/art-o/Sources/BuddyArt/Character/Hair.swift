import Foundation
import PixelKit

extension CharacterArt {
    /// 头发精灵 16×20，头盒子(12×13)的左上角在 hairPad=(2,3)：
    /// 头发可以往上伸 3 行（丸子头、马尾扎点）、往下伸 4 行（长发、马尾）、往两边各伸 2 列。
    /// 下面所有蒙版都用「头盒子坐标」写：第一行对应头盒子的第 yStart 行，第一列对应 xStart 列。
    static func hairMask(_ rows: String, yStart: Int = 0, xStart: Int = 0) -> Bitmap {
        let m = Bitmap(rows)
        var b = Bitmap(w: hairW, h: hairH)
        for y in 0..<m.h { for x in 0..<m.w where m[x, y] { b[hairPad.x + xStart + x, hairPad.y + yStart + y] = true } }
        return b
    }

    static func addHair(_ book: SpriteBook, _ style: String, _ facing: Facing, mask: Bitmap, detail: String? = nil,
                        hi: [(Int, Int)] = [], sh: [(Int, Int)] = []) {
        var g = ShadeKit.shade(mask, .hair)
        for (x, y) in hi { g[hairPad.x + x, hairPad.y + y] = Role.hairHi }
        for (x, y) in sh { g[hairPad.x + x, hairPad.y + y] = Role.hairSh }
        if let d = detail { g.overlay(d, dx: hairPad.x, dy: hairPad.y) }
        book.add(g.sprite(name: "hair.\(style).\(facing.name)", anchors: ["head": hairPad]))
    }

    static func buildHair(_ book: SpriteBook) {
        buildBob(book)
    }

    // ============ 波波头 bob ============
    static func buildBob(_ book: SpriteBook) {
        addHair(book, "bob", .back, mask: hairMask("""
        ...######...
        ..########..
        .##########.
        ############
        ############
        ############
        ############
        ############
        ############
        ############
        ############
        .####..####.
        ..##....##..
        """),
        hi: [(4, 1), (5, 1), (3, 2), (4, 2), (2, 3), (2, 4), (2, 5), (3, 3)],
        sh: [(4, 5), (4, 6), (4, 7), (8, 4), (8, 5), (8, 6), (8, 7), (8, 8), (3, 9), (4, 9), (5, 9), (6, 9), (7, 9), (8, 9), (6, 3), (6, 4)])
        addHair(book, "bob", .front, mask: hairMask("""
        ...######...
        ..########..
        .##########.
        ############
        ############
        ###.####.###
        ###......###
        ##........##
        ##........##
        ##........##
        ##........##
        .#........#.
        """),
        hi: [(4, 1), (5, 1), (3, 2), (4, 2), (3, 3), (4, 3), (2, 5), (1, 6), (1, 7), (1, 8)],
        sh: [(6, 3), (7, 3), (7, 4), (9, 6), (10, 7), (10, 8), (10, 9)])
        addHair(book, "bob", .side, mask: hairMask("""
        ...######...
        ..########..
        .##########.
        ############
        ############
        #########...
        ########....
        #######.....
        #######.....
        #######.....
        ######......
        .####.......
        ..##........
        """),
        hi: [(4, 1), (5, 1), (3, 2), (4, 2), (2, 3), (2, 4), (1, 5), (1, 6)],
        sh: [(5, 5), (5, 6), (5, 7), (4, 9), (3, 9), (8, 3), (8, 4)])
        addHair(book, "bob", .threeQuarterFront, mask: hairMask("""
        ...######...
        ..########..
        .##########.
        ############
        ############
        ####.####.##
        ###.......##
        ###.......#.
        ###.......#.
        ###.......#.
        ###.......#.
        .##.......#.
        """),
        hi: [(4, 1), (5, 1), (3, 2), (4, 2), (3, 3), (2, 5), (1, 6), (1, 7)],
        sh: [(6, 3), (7, 3), (8, 4), (10, 6), (10, 7), (10, 8)])
        addHair(book, "bob", .threeQuarterBack, mask: hairMask("""
        ...######...
        ..########..
        .##########.
        ############
        ############
        ############
        ############
        ###########.
        ##########..
        ##########..
        ###########.
        .####..####.
        ..##....##..
        """),
        hi: [(4, 1), (5, 1), (3, 2), (4, 2), (2, 3), (2, 4), (2, 5), (3, 3)],
        sh: [(5, 5), (5, 6), (5, 7), (8, 4), (8, 5), (8, 6), (4, 9), (5, 9), (6, 9), (7, 9), (7, 3)])
    }
}
