import Foundation
import PixelKit

extension PropArt {
    /// 桌面小件。马克杯颜色随人（角色精灵，经 RoleMap），其余是直接颜色。
    static func buildDeskProps(_ b: SpriteBook) {
        // 马克杯 8×6：用角色 a/A（点缀色）+ n（高光），走角色路径，所以放进 CharacterArt.book 更合适——
        // 这里先放在 props 里，用 legend 把 a/A/n 映射到固定色仅用于预览；真正的杯子在 CharacterArt.buildMug。
        // ---------- 小黄鸭 8×8 ----------
        add(b, "orn.duck", """
        ..###...
        .#JjK#..
        .#jjj##.
        ..#jj#Q#
        ..#jjjK#
        .#jjjjK#
        .#jjjjK#
        ..#KKK#.
        """)
        // ---------- 仙人掌 9×11 ----------
        add(b, "orn.cactus", """
        ...##....
        ..#LL#...
        .#LlL#...
        .#LlL#.#.
        #L#LlL#L#
        #LLLlLLl#
        .##LlL#l#
        ...#lL##.
        ..#TTTT#.
        ..#ttttu#
        ...#uuu#.
        """)
        // ---------- 相框 9×8 ----------
        add(b, "orn.frame", """
        .#######.
        #OOOOOOX#
        #OcUUUcX#
        #OUjUUkX#
        #OUJjUUX#
        #OccccoX#
        #oxxxxxX#
        .#######.
        """)
        // ---------- 招财猫 9×10 ----------
        add(b, "orn.cat", """
        .#.....#.
        #W#####W#
        #WWWWWWW#
        #WeWWWeW#
        #WWWPWWW#
        .#WWWWW#.
        #WWWWWWv#
        #WWGgGWv#
        #WWWWWWv#
        .#######.
        """)
        // ---------- 手办 6×12 ----------
        add(b, "orn.figure", """
        ..##..
        .#RR#.
        .#WW#.
        ..##..
        .#cc#.
        #cccc#
        #cccc#
        .#cc#.
        .#kk#.
        .#kk#.
        ##kk##
        #NNNN#
        """)
    }
}
