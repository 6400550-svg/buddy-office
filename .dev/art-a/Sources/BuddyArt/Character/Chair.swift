import Foundation
import PixelKit

extension CharacterArt {
    /// 椅子（角色精灵：c = 椅面色，C = 阴影/金属色，全套用 chair 材质做选择性描边）。
    /// 精灵 22×26：靠背（第 0–10 行，低于肩膀）+ 座面（11–14）+ 气弹杆 + 五星脚 + 滚轮。
    static func buildChairs(_ book: SpriteBook) {
        func base(back: Bitmap, seat: Bitmap, seatY: Int, name: String, meshDots: Bool, wings: Bool = false, slats: Bool = false) {
            var g = Grid(w: 22, h: 26)
            var b = ShadeKit.shade(back, .chair)
            let outC = Role.chairSh
            if meshDots {
                // 网面：靠背中间的稀疏点阵 + 中间一道竖梁；边框保持实色
                for y in 2..<(back.h - 2) { for x in 4..<(back.w - 4) where (x + y) % 2 == 0 && b[x, y] == Role.chair { b[x, y] = outC } }
                for y in 1..<(back.h - 1) { b[10, y] = outC; b[11, y] = outC }
            }
            if wings {
                // 电竞椅：中间一条明色带 + 两侧护翼的暗线
                for y in 1..<(back.h - 1) { b[9, y] = Role.chair; b[10, y] = Role.chair; b[11, y] = Role.chair; b[12, y] = Role.chair }
                for y in 2..<(back.h - 2) { b[5, y] = outC; b[16, y] = outC }
            }
            if slats {
                // 木椅：三根竖条
                for y in 2..<(back.h - 1) { for x in [6, 10, 11, 15] { b[x, y] = outC } }
                for x in 3..<(back.w - 3) { b[x, 3] = outC }
            }
            g.overlay(b)
            g.overlay(ShadeKit.shade(seat, .chair), dx: 0, dy: seatY)
            // 气弹杆、五星脚、滚轮（用椅子的阴影色）
            let C = Role.chairSh
            for y in (seatY + 4)..<(seatY + 7) { g[10, y] = C; g[11, y] = C }
            for x in 5...16 { g[x, seatY + 7] = C }
            g[4, seatY + 8] = C; g[5, seatY + 8] = C; g[16, seatY + 8] = C; g[17, seatY + 8] = C
            g[3, seatY + 9] = C; g[4, seatY + 9] = C; g[17, seatY + 9] = C; g[18, seatY + 9] = C
            for (x, y) in [(2, seatY + 10), (3, seatY + 10), (18, seatY + 10), (19, seatY + 10), (2, seatY + 11), (3, seatY + 11), (18, seatY + 11), (19, seatY + 11)] { g[x, y] = C }
            book.add(g.sprite(name: name, anchors: ["seatTop": IntPoint(11, seatY), "backTop": IntPoint(11, 0)]))
        }
        // ---- 网面椅 ----
        base(back: Bitmap("""
        ....############....
        ..################..
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        ..################..
        ..################..
        ...##############...
        """).offset(dx: 1, dy: 0, w: 22, h: 11), seat: Bitmap("""
        ..##################..
        .####################.
        ######################
        .####################.
        """), seatY: 11, name: "chair.mesh.back", meshDots: true)
        // ---- 电竞椅 ----
        base(back: Bitmap("""
        ....############....
        ..################..
        .##################.
        ####################
        ####################
        ####################
        .##################.
        .##################.
        ..################..
        ..################..
        ...##############...
        """).offset(dx: 1, dy: 0, w: 22, h: 11), seat: Bitmap("""
        ..##################..
        .####################.
        ######################
        .####################.
        """), seatY: 11, name: "chair.gaming.back", meshDots: false, wings: true)
        // ---- 木椅 ----
        base(back: Bitmap("""
        ..################..
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        .##################.
        ..################..
        ....############....
        """).offset(dx: 1, dy: 0, w: 22, h: 11), seat: Bitmap("""
        ..##################..
        ######################
        ######################
        .####################.
        """), seatY: 11, name: "chair.wood.back", meshDots: false, slats: true)
    }

    /// 马克杯 8×6（杯身用点缀色 a/A，n 是高光）。
    static func buildMug(_ book: SpriteBook) {
        let mug = Grid.from("""
        .AAAAA..
        AnaaaAAA
        AnaaaA.A
        AaaaaA.A
        AaaaaAAA
        .AAAAA..
        """)
        book.add(mug.sprite(name: "mug", anchors: ["top": IntPoint(3, 0)]))
    }
}
