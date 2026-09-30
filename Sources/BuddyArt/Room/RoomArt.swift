import Foundation
import PixelKit

/// 房间陈设的精灵（直接存主调色板索引，用 PropLegend）。
public enum RoomArt {
    public static let book: SpriteBook = {
        let b = SpriteBook()
        buildDoor(b); buildCoatRack(b); buildWindow(b); buildClock(b); buildCalendar(b)
        buildWhiteboard(b); buildPosters(b); buildPlants(b); buildCooler(b); buildBin(b)
        return b
    }()
    public static func sprite(_ n: String) -> IndexedSprite { book[n] }

    static func P(_ name: String) -> UInt8 { Pal.dx(name) }
    static func add(_ b: SpriteBook, _ name: String, _ rows: String, anchors: [String: IntPoint] = [:]) {
        b.add(name, rows, legend: PropLegend.legend, anchors: anchors)
    }

    // ---------- 门 22×46 ----------
    static func buildDoor(_ b: SpriteBook) {
        let w = 22, h = 46
        var g = Grid(w: w, h: h)
        let trimHi = P("trim.hi"), trim = P("trim.base"), trimSh = P("trim.sh")
        let dHi = P("woodWalnut.hi"), d = P("woodWalnut.base"), dSh = P("woodWalnut.sh"), dOut = P("woodWalnut.out")
        // 门框
        for y in 0..<h { for x in 0..<w { g[x, y] = (x < 2 || x >= w - 2 || y < 2) ? ((x == 0 || y == 0) ? trimHi : (x >= w - 2 ? trimSh : trim)) : d } }
        // 门扇：左受光
        for y in 2..<h { for x in 2..<(w - 2) {
            var c = d
            if x == 2 { c = dHi }
            if x >= w - 4 { c = dSh }
            g[x, y] = c
        } }
        // 两块嵌板（上小下大）：外圈暗、内圈亮
        func panel(_ x0: Int, _ y0: Int, _ pw: Int, _ ph: Int) {
            for y in y0..<(y0 + ph) { for x in x0..<(x0 + pw) {
                var c = dSh
                if y == y0 || x == x0 { c = dOut }                 // 上/左边缘暗（凹进去）
                else if y == y0 + ph - 1 || x == x0 + pw - 1 { c = dHi }
                else { c = d }
                g[x, y] = c
            } }
        }
        panel(5, 6, 12, 14); panel(5, 23, 12, 18)
        // 门把手 + 底部门槛
        g[16, 26] = P("gold.base"); g[17, 26] = P("gold.hi"); g[16, 27] = P("gold.sh"); g[17, 27] = P("gold.base")
        for x in 0..<w { g[x, h - 1] = trimSh }
        // 外轮廓压一圈深色
        for y in 0..<h { g[0, y] = dOut; g[w - 1, y] = dOut }
        for x in 0..<w { g[x, 0] = dOut }
        b.add(g.sprite(name: "room.door", anchors: ["knob": IntPoint(16, 26)]))
    }

    // ---------- 衣帽架 12×40 ----------
    static func buildCoatRack(_ b: SpriteBook) {
        add(b, "room.coatrack", """
        ..#......#..
        .#f#....#f#.
        ..f#.##.#f..
        ...f#dD#f...
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ....#dD#....
        ...#ddDf#...
        ..#ddDDff#..
        .#ddD..Dff#.
        #ddD....Dff#
        ##F......F##
        """, anchors: ["hookL": IntPoint(2, 2), "hookR": IntPoint(9, 2), "hookM": IntPoint(5, 3)])
    }

    // ---------- 窗 36×32：玻璃区 30×24 在 (3,3)，十字窗棂，窗台 ----------
    static func buildWindow(_ b: SpriteBook) {
        let w = 36, h = 32
        var g = Grid(w: w, h: h)
        let hi = P("trim.hi"), base = P("trim.base"), sh = P("trim.sh"), out = P("wall.deep")
        // 外框 3px
        for y in 0..<29 { for x in 0..<w {
            let inGlass = x >= 3 && x < 33 && y >= 3 && y < 27
            if inGlass { continue }
            var c = base
            if x == 0 || y == 0 { c = out } else if x == 1 || y == 1 { c = hi }
            else if x == w - 1 || y == 28 { c = out } else if x == w - 2 || y == 27 { c = sh }
            g[x, y] = c
        } }
        // 窗棂：竖 2px、横 2px
        for y in 3..<27 { g[17, y] = base; g[18, y] = sh }
        for x in 3..<33 { g[x, 14] = hi; g[x, 15] = base }
        // 玻璃内缘一圈暗线（凹进去的感觉）
        for x in 3..<33 { g[x, 3] = sh }
        for y in 3..<27 { g[3, y] = sh }
        // 窗台：比窗框宽 2px
        for x in 0..<w { g[x, 29] = hi; g[x, 30] = base; g[x, 31] = out }
        g[0, 29] = out; g[w - 1, 29] = out
        b.add(g.sprite(name: "room.window", anchors: ["glass": IntPoint(3, 3)]))
    }

    // ---------- 挂钟 14×14（指针动态画）----------
    static func buildClock(_ b: SpriteBook) {
        add(b, "room.clock", """
        ....######....
        ..##dddddd##..
        .#dWWWWWWWWd#.
        .dWWWWWWWWWWd.
        #dWWWWWWWWWWd#
        #dWWWWWWWWWWd#
        dWWWWWWWWWWWWd
        dWWWWWWWWWWWWd
        #dWWWWWWWWWWd#
        #dWWWWWWWWWWd#
        .dWWWWWWWWWWd.
        .#dWWWWWWWWd#.
        ..##dfffffd##.
        ....######....
        """, anchors: ["center": IntPoint(6, 6)])
    }

    // ---------- 日历 14×18（日期动态画）----------
    static func buildCalendar(_ b: SpriteBook) {
        add(b, "room.calendar", """
        .%..........%.
        %%##########%%
        #rrrrrrrrrrrr#
        #rRRRRRRRRRRr#
        #rrrrrrrrrrrr#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #WWWWWWWWWWWv#
        #wwwwwwwwwwwv#
        #vvvvvvvvvvvv#
        .############.
        """, anchors: ["date": IntPoint(3, 7)])
    }

    // ---------- 白板 40×28：板面 36×22 在 (2,2)，托盘和笔 ----------
    static func buildWhiteboard(_ b: SpriteBook) {
        let w = 40, h = 28
        var g = Grid(w: w, h: h)
        let hi = P("metal.hi"), base = P("metal.base"), sh = P("metal.sh"), deep = P("metal.deep"), board = P("white.hi"), boardSh = P("white.base")
        for y in 0..<25 { for x in 0..<w {
            var c = base
            if x == 0 || y == 0 { c = deep } else if x == 1 || y == 1 { c = hi }
            else if x == w - 1 || y == 24 { c = deep } else if x == w - 2 || y == 23 { c = sh }
            g[x, y] = c
        } }
        for y in 2..<23 { for x in 2..<(w - 2) { g[x, y] = (y > 19) ? boardSh : board } }
        // 板面阴影（左上内缘）
        for x in 2..<(w - 2) { g[x, 2] = boardSh }
        for y in 2..<23 { g[2, y] = boardSh }
        // 笔托盘
        for x in 4..<(w - 4) { g[x, 25] = base; g[x, 26] = sh }
        for x in 4..<(w - 4) { g[x, 27] = deep }
        // 三支笔
        for (x, c) in [(8, "red.base"), (11, "blue.base"), (14, "leaf.base")] { for dx in 0..<2 { g[x + dx, 24] = P(c) } }
        b.add(g.sprite(name: "room.whiteboard", anchors: ["face": IntPoint(2, 2)]))
    }

    // ---------- 海报 14×18 ×3 ----------
    static func buildPosters(_ b: SpriteBook) {
        // 山与太阳
        add(b, "room.poster.mountain", """
        ##############
        #OOOOOOOOOOOO#
        #O0000000000O#
        #O0000JJ0000O#
        #O000JjjJ000O#
        #O0000JJ0000O#
        #O00000000L0O#
        #O0000M0000LO#
        #O000MMM00lLO#
        #O00MMmMM0lLO#
        #O0MMmmnMMlLO#
        #OMMmmnnnMMLO#
        #OlllllllllLO#
        #OeeeeeeeeeeO#
        #OOOOOOOOOOOO#
        #xxxxxxxxxxxX#
        ##############
        ..............
        """)
        // 咖啡
        add(b, "room.poster.coffee", """
        ##############
        #ddddddddddd@#
        #dDDDDDDDDDd@#
        #dDppppppppDd#
        #dDppMMMMppDd#
        #dDpMwwwwMpDd#
        #dDpMwooowMpD#
        #dDpMwwwwMMpD#
        #dDppMwwwMpDd#
        #dDpppMMMppDd#
        #dDppppppppDd#
        #dDpuuuupppDd#
        #dDppppppppDd#
        #dDDDDDDDDDDd#
        #ffffffffffff#
        #F@@@@@@@@@@F#
        ##############
        ..............
        """)
        // 星球
        add(b, "room.poster.planet", """
        ##############
        #cccccccccccc#
        #ckkkkkkkkkkc#
        #ckkGkkkkkGkc#
        #ckkkkkkkkkkc#
        #ckkkkRRRkkkc#
        #ckkkRrrrRkkc#
        #ckGRrrsrrRkc#
        #ckkRrrrsrRkc#
        #ckkkRrrrRkkc#
        #ckkkkRRRkkkc#
        #ckkkkkkkkGkc#
        #ckkkkkkkkkkc#
        #ckkkkkkkkkkc#
        #cccccccccccc#
        #kkkkkkkkkkkk#
        ##############
        ..............
        """)
    }

    // ---------- 落地绿植：花盆 14×10 + 叶子 18×26（叶子单独，好摆动）----------
    static func buildPlants(_ b: SpriteBook) {
        add(b, "room.plant.pot", """
        ..#TTTTTTTT#..
        .#TttttttttT#.
        .#tttttttttu#.
        ..#SSSSSSSS#..
        ..#ttttttttu#.
        ..#ttttttttu#.
        ...#tttttuu#..
        ...#tttuuuu#..
        ....#uuuuuu#..
        .....######...
        """)
        add(b, "room.plant.leaves", """
        .......##.........
        ......#LL#....##..
        ..##..#LlL#..#LL#.
        .#LL#.#LlL#.#LlL#.
        #LlLL#.#lL#.#LlL#.
        #LllLL#.#l#.#LlL#.
        .#LllL##.#.#LlLL#.
        ..#LllL#.#.#lLL#..
        ...#LlL#.#.#LL#...
        .###.#lL#.##LL#...
        #LLL#.#l#.#lLl#...
        #LlLL#.#.#lLL#....
        .#LlL#.##lLL#.....
        ..#lLL#.#LL#......
        ...#lLL##L#.......
        ....#lLLlL#.......
        .....#lLl#........
        ......#l#.........
        ......#e#.........
        ......#e#.........
        ......#e#.........
        ......#e#.........
        """)
        // 小桌绿植（多肉）
        add(b, "room.plant.small", """
        ..##..##..
        .#LL##LL#.
        #LlLLLLlL#
        .#eLLLLe#.
        ..#TTTT#..
        ..#tttu#..
        ...#uu#...
        """)
    }

    // ---------- 饮水机 12×26 ----------
    static func buildCooler(_ b: SpriteBook) {
        add(b, "room.cooler", """
        ...######...
        ..#UUUUUU#..
        .#UccccccU#.
        .#UcUUUUcU#.
        .#UcUUUUcU#.
        .#UcccccUU#.
        ..#UUUUUU#..
        ..#WWWWWv#..
        .#WWWWWWWv#.
        .#WWNNNNWv#.
        .#WWNNNNWv#.
        .#WWWWWWWv#.
        .#WWRWWBWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#WWMMMMWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#WWWWWWWv#.
        .#vvvvvvvv#.
        .#vvvvvvvv#.
        .#NNNNNNNN#.
        ..########..
        """)
    }

    // ---------- 垃圾桶 9×11 ----------
    static func buildBin(_ b: SpriteBook) {
        add(b, "room.bin", """
        .#######.
        #NNNNNNN#
        .#mmmmm#.
        .#MmmmnN#
        .#MmmmnN#
        .#MmmmnN#
        .#MmmmnN#
        .#MmmmnN#
        .#mmmmnN#
        ..#nnnN#.
        ...####..
        """)
    }
}
