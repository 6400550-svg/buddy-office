import Foundation
import PixelKit

/// 气泡和 7×7 图标。气泡 3 帧由小变大弹出（7 → 11 → 15，整数尺寸，不做非整数缩放）。
public enum BubbleArt {
    public static let book: SpriteBook = {
        let b = SpriteBook()
        for size in [7, 11, 15] { b.add(makeBody(size)) }
        buildIcons(b)
        return b
    }()
    public static func sprite(_ n: String) -> IndexedSprite { book[n] }

    static func P(_ n: String) -> UInt8 { Pal.dx(n) }

    /// 气泡身体：圆角方块 + 左下角一条小尾巴。锚点 tail = 尾巴尖，icon = 7×7 图标的左上角（仅 15 尺寸）。
    static func makeBody(_ size: Int) -> IndexedSprite {
        let tail = size >= 11 ? 3 : 2
        var g = Grid(w: size, h: size + tail)
        let cut = size >= 15 ? 2 : 1
        let fill = P("bubble.fill"), line = P("bubble.line"), sh = P("bubble.sh")
        for y in 0..<size { for x in 0..<size {
            let dx = min(x, size - 1 - x), dy = min(y, size - 1 - y)
            if dx + dy < cut { continue }
            let edge = x == 0 || y == 0 || x == size - 1 || y == size - 1 || (dx + dy == cut)
            g[x, y] = edge ? line : ((y >= size - 3 && size >= 11) ? sh : fill)
        } }
        // 尾巴
        let tx = size >= 11 ? 3 : 2
        for i in 0..<tail {
            g[tx + i * 0, size + i] = line
            if i < tail - 1 { g[tx + 1, size - 1 + i] = fill; g[tx - 1, size + i] = (i == 0 ? line : 0); g[tx + 1, size + i] = line; }
        }
        g[tx, size - 1] = fill
        return IndexedSprite(name: "bubble.\(size)", width: size, height: size + tail, pixels: g.v,
                             anchors: ["tail": IntPoint(tx, size + tail - 1), "icon": IntPoint((size - 7) / 2, (size - 7) / 2)])
    }

    static func icon(_ b: SpriteBook, _ name: String, _ rows: String) {
        b.add(name, rows, legend: PropLegend.legend)
    }

    static func buildIcons(_ b: SpriteBook) {
        icon(b, "icon.key", """
        .$$$...
        $...$..
        $...$..
        .$$$$$$
        .....$.
        .....$$
        .......
        """)
        icon(b, "icon.question", """
        ..}}}..
        .}...}.
        .....}.
        ...}}..
        ...}...
        .......
        ...}...
        """)
        icon(b, "icon.exclaim", """
        ...>...
        ...>...
        ...>...
        ...>...
        .......
        ...>...
        .......
        """)
        icon(b, "icon.board", """
        ..'g'..
        .'''''.
        .'p.p'.
        .'ppp'.
        .'p.p'.
        .'ppp'.
        ..'''..
        """)
        icon(b, "icon.magnifier", """
        .'''...
        '...'..
        '...'..
        '...'..
        .'''...
        .....'.
        ......'
        """)
        icon(b, "icon.book", """
        '''''''
        'c'''c'
        'c'.'c'
        'c'''c'
        'c'.'c'
        'c'''c'
        '''''''
        """)
        icon(b, "icon.toolbox", """
        ..'''..
        ..'.'..
        '''''''
        'rrrrr'
        'r$$$r'
        'rrrrr'
        '''''''
        """)
        icon(b, "icon.note", """
        +++++++
        +++++++
        ++>>+++
        ++>>+++
        +++++++
        +++>+++
        +++++++
        """)
        icon(b, "icon.gear", """
        ...'...
        .'''''.
        .'...'.
        '''.'''
        .'...'.
        .'''''.
        ...'...
        """)
        icon(b, "icon.mug", """
        .'''''.
        '''''''
        ''.'.'.
        '''''.'
        '''''.'
        .'''''.
        ..'''..
        """)
        icon(b, "icon.paper", """
        .'''''.
        .'ppp'.
        .'p.p'.
        .'ppp'.
        .'p.p'.
        .'ppp'.
        .'''''.
        """)
        // 工具图标（等批准气泡里跟在钥匙后面）
        icon(b, "icon.tool.bash", """
        .......
        '.'....
        .'.....
        '.'''..
        .......
        .......
        .......
        """)
        icon(b, "icon.tool.edit", """
        ....''.
        ...'g'.
        ..'g'..
        .'g'...
        'r'....
        'rr....
        .......
        """)
        icon(b, "icon.tool.web", """
        .'''''.
        '.'.'.'
        '.'.'.'
        '''''''
        '.'.'.'
        '.'.'.'
        .'''''.
        """)
        icon(b, "icon.tool.file", """
        .''''..
        .'ppp'.
        .'p.p'.
        .'ppp'.
        .'p.p'.
        .'ppp'.
        .'''''.
        """)
        icon(b, "icon.tool.other", """
        ..'''..
        .'...'.
        '.'''.'
        '.'.'.'
        '.'''.'
        .'...'.
        ..'''..
        """)
        icon(b, "icon.helper", """
        ..'''..
        .'ppp'.
        .'p.p'.
        ..'''..
        .'''''.
        '.'''.'
        .......
        """)
    }
}
