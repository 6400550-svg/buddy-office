import Foundation
import PixelKit

extension CharacterArt {
    // MARK: 表情（脸的覆盖层）
    //
    // face.<表情>.<朝向> —— 12×13（头盒子大小，和 head.* 同一个原点），画在头精灵之上、头发之下。
    // 表情：happy / question / worried / sleepy / wow；朝向只有 front / q34front / side（朝向画面右侧的版本）。
    //
    // 做法：头精灵里已经有中性的眼睛 / 腮红 / 嘴。每个表情精灵先用「同一份肤色明暗」（ShadeKit.shade(skull, .skin)，
    // 也就是头精灵去掉五官后的样子）把这些中性五官占的格子盖成肤色（cover），再把这个表情自己的眉、眼、嘴、腮红画上去，
    // 所以和头精灵是无缝的一张脸。cover 的位置（coverFront / coverQ34 / coverSide）就是 Heads.swift 里中性五官的位置——
    // 头精灵的五官位置改了，这三张 cover 要同步改。
    //
    // 字符：e 眼  w 眼白/高光  n 白点  m 嘴  b 腮红  1 眉（发描边色）  l 水滴  K k j 肤色
    // 几个要点：
    //  · 脸的可见范围被波波头的刘海挡着：正面只有第 6 行（3–8 列）和第 7–11 行（2–9 列）看得到，眉毛画在第 6–7 行。
    //  · 侧面：嘴要伸到 (10,11)（脸前缘外面一格，中性嘴也在那里）；cover 盖不掉「空」，所以每个侧面表情都自己在 (10,11) 画点东西。
    //  · 汗滴（worried）：正面画在脸右边缘（9,8）（9,9），3/4 正面和侧面画在头外面（第 11 列），因为这几个朝向的脸边缘被头发盖住了。
    //  · 腮红 b 目前在调色板里就是肤色阴影色，所以只有「肤色比阴影色亮得多」时才看得出来；happy 用了两行来补。

    /// 只有肤色明暗的头（没有五官）：所有表情的「盖底」都从它取。
    private static func bareSkin() -> Grid { ShadeKit.shade(Bitmap(skullRows), .skin) }

    /// 逐行检查过宽度的 12 列 ASCII（从第 y0 行开始写，其余行留空），得到 12×13 的格子。
    private static func faceRows(_ rows: String, y0: Int, _ what: String) -> Grid {
        var ls = rows.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let f = ls.first, f.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeFirst() }
        while let l = ls.last, l.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeLast() }
        var g = Grid(w: 12, h: 13)
        for (i, l) in ls.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            precondition(t.count == 12, "\(what) 第 \(y0 + i) 行宽度是 \(t.count)，应为 12：\(t)")
            precondition(y0 + i < 13, "\(what) 行数超出")
            for (x, c) in t.enumerated() where c != "." {
                guard let r = Role.chars[c] else { preconditionFailure("\(what) 里有不认识的字符「\(c)」") }
                g[x, y0 + i] = r
            }
        }
        return g
    }

    /// 一个表情精灵 = 盖底（cover 里非 . 的格子取 bare 的肤色；cover 从第 7 行开始写）+ 表情本身（art 从第 5 行开始写）。
    private static func addFace(_ book: SpriteBook, _ name: String, _ facing: Facing, cover: String, art: String) {
        let what = "face.\(name).\(facing.name)"
        let base = bareSkin()
        let cov = faceRows(cover.replacingOccurrences(of: "#", with: "K"), y0: 7, what + " cover")
        var g = Grid(w: 12, h: 13)
        for y in 0..<13 { for x in 0..<12 where cov[x, y] != 0 { g[x, y] = base[x, y] } }
        g.overlay(faceRows(art, y0: 5, what))
        book.add(g.sprite(name: what))
    }

    static func buildFaces(_ book: SpriteBook) {
        buildFacesFront(book)
        buildFacesQ34(book)
        buildFacesSide(book)
    }

    // 中性五官占的格子（从第 7 行起）
    private static let coverFront = """
    ...##..##...
    ...##..##...
    ...##..##...
    ..##....##..
    .....##.....
    """
    private static let coverQ34 = """
    ....##..#...
    ....##..#...
    ....##..#...
    ...##....#..
    ......##....
    """
    private static let coverSide = """
    ........##..
    ........##..
    ........##..
    .........#..
    .........##.
    """

    static func buildFacesFront(_ book: SpriteBook) {
        func add(_ name: String, _ art: String) { addFace(book, name, .front, cover: coverFront, art: art) }

        // ---------- happy ----------
        add("happy", """
        ............
        ............
        ...ee..ee...
        ..e......e..
        ..bb....bb..
        ..bbmwwmbb..
        .....mm.....
        """)
        // ---------- question ----------
        add("question", """
        ............
        .......11...
        ....11......
        ....we..we..
        ....ee..ee..
        ....ee.mee..
        ......m.....
        """)
        // ---------- worried ----------
        add("worried", """
        ............
        ...11..11...
        ..1ne..ne1..
        ...ee..eel..
        ...ew..wel..
        ......m.....
        .....mm.....
        """)
        // ---------- sleepy ----------
        add("sleepy", """
        ............
        ............
        ............
        ...jj..jj...
        ...ee..ee...
        ..b......b..
        ......m.....
        """)
        // ---------- wow ----------
        add("wow", """
        ............
        ...11..11...
        ..www..www..
        ..wew..wew..
        ..www..www..
        .....mm.....
        .....mm.....
        """)
    }

    static func buildFacesQ34(_ book: SpriteBook) {
        func add(_ name: String, _ art: String) { addFace(book, name, .threeQuarterFront, cover: coverQ34, art: art) }
        // 近侧眼（左，宽）x=4..5，远侧眼（右，窄）x=8；嘴中心在 6.5
        add("happy", """
        ............
        ............
        ....ee..ee..
        ...e..e.....
        ...bb....b..
        ...bbmwwmb..
        ......mm....
        """)
        add("question", """
        ............
        ........11..
        .....11.....
        .....we..w..
        .....ee..e..
        .....ee.me..
        .......m....
        """)
        add("worried", """
        ............
        ....11..11..
        ...1ne..n1.l
        ....ee..e..l
        ....ew..w...
        .......m....
        ......mm....
        """)
        add("sleepy", """
        ............
        ............
        ............
        ....jj..j...
        ....ee.ee...
        ...b.....b..
        .......m....
        """)
        add("wow", """
        ............
        ....11..1...
        ...www.ww...
        ...wew.we...
        ...www.ww...
        ......mm....
        ......mm....
        """)
    }

    static func buildFacesSide(_ book: SpriteBook) {
        func add(_ name: String, _ art: String) { addFace(book, name, .side, cover: coverSide, art: art) }
        // 眼在 x=8..9，脸前缘（描边）在 x=10，嘴在 (9,11)(10,11)。(10,11) 在盖底里是空的，所以每个表情的嘴都要自己把它画出来。
        add("happy", """
        ............
        ............
        ........ee..
        .......e.e..
        ......bb....
        ......bbmw..
        .........mm.
        """)
        add("question", """
        ............
        ............
        ........11..
        ........we..
        ........ee..
        ........ee..
        ..........m.
        """)
        add("worried", """
        ...........l
        ........11.l
        ........ne..
        ........ee..
        ........ew..
        ..........m.
        .........mm.
        """)
        add("sleepy", """
        ............
        ............
        ............
        ........jj..
        ........ee..
        .........b..
        ..........m.
        """)
        add("wow", """
        ............
        ........11..
        .......www..
        .......wwe..
        .......www..
        ..........m.
        .........mm.
        """)
    }
}
