import Foundation
import PixelKit

/// 工位与房间的道具精灵（格子里直接存主调色板索引，见 PropLegend）。
public enum PropArt {
    public static let book: SpriteBook = {
        let b = SpriteBook()
        buildWorkstation(b)
        buildDesks(b)
        buildDeskProps(b)
        return b
    }()
    public static func sprite(_ name: String) -> IndexedSprite { book[name] }

    static func add(_ b: SpriteBook, _ name: String, _ rows: String, anchors: [String: IntPoint] = [:]) {
        b.add(name, rows, legend: PropLegend.legend, anchors: anchors)
    }

    static func grid(_ rows: String) -> Grid { Grid.from(rows, legend: PropLegend.gridLegend) }

    /// 复古 CRT 34×26：米白机身，屏幕凹槽 26×20，屏幕区 24×18 在 (5,3)。
    static func buildCRT(_ b: SpriteBook) {
        let w = 34, h = 26
        var g = Grid(w: w, h: h)
        let body = Pal.dx("white.base"), hi = Pal.dx("white.hi"), sh = Pal.dx("white.sh"), out = Pal.dx("ink1")
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h - 1 else { return false }
            let cx = min(x, w - 1 - x), cy = min(y, h - 2 - y)
            return !(cx + cy < 2)          // 四角各削掉一小块
        }
        for y in 0..<h { for x in 0..<w where inside(x, y) {
            let edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
            if edge { g[x, y] = out; continue }
            var c = body
            if y <= 2 || x <= 2 { c = hi }
            if x >= w - 3 || y >= h - 4 { c = sh }
            g[x, y] = c
        } }
        // 屏幕凹槽
        for y in 2..<22 { for x in 4..<30 { g[x, y] = out } }
        for y in 3..<21 { for x in 5..<29 { g[x, y] = 0 } }
        // 下巴：喇叭槽 + 指示灯位置
        for x in stride(from: 8, through: 16, by: 2) { g[x, 23] = sh; g[x, 24] = sh }
        b.add(g.sprite(name: "monitor.crt", anchors: ["screen": IntPoint(5, 3), "led": IntPoint(26, 23)]))
    }

    static func buildWorkstation(_ b: SpriteBook) {
        // ---------- 显示器外框 28×20，屏幕区 24×15 在 (2,2) ----------
        add(b, "monitor.bezel", """
        .##########################.
        #BBBBBBBBBBBBBBBBBBBBBBBBBB#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #b........................y#
        #bbbbbbbbbbbbbbbbbbbbbbbbby#
        #bbbbbbbbbbbbbbbbbbbbbbbbyy#
        .##########################.
        """, anchors: ["screen": IntPoint(2, 2), "led": IntPoint(23, 18)])
        // ---------- 支架 12×5 ----------
        add(b, "monitor.stand", """
        ....MmmN....
        ....MmmN....
        ....MmmN....
        .MMMMmmmnNN.
        .#NNNNNNNN#.
        """)
        buildCRT(b)
        // ---------- 键盘 20×6 ----------
        add(b, "keyboard", """
        .%%%%%%%%%%%%%%%%%%.
        %WwWwWwWwWwWwWwWwWv%
        %wWwWwWwWwWwWwWwWwv%
        %WwWwWwWwWwWwWwWwWv%
        %vvvvvvvvvvvvvvvvvv%
        .%%%%%%%%%%%%%%%%%%.
        """)
        // ---------- 鼠标 4×5 ----------
        add(b, "mouse", """
        .%%.
        %WW%
        %Ww%
        %ww%
        .%%.
        """)
        // ---------- 台灯 10×13（关 / 开）----------
        add(b, "lamp.off", """
        ...####...
        ..#MMMM#..
        .#Mmmmmn#.
        .#mnnnnN#.
        ..#NNNN#..
        ....m.....
        ...m......
        ..m.......
        ..m.......
        .nn.......
        nnnn......
        NNNN......
        """)
        add(b, "lamp.on", """
        ...####...
        ..#MMMM#..
        .#Mmmmmn#.
        .#[]]]]N#.
        ..#[[[[#..
        ....m.....
        ...m......
        ..m.......
        ..m.......
        .nn.......
        nnnn......
        NNNN......
        """)
    }
}
