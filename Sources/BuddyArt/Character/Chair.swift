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


    /// 椅子转过去的样子：q34（转 45°）和 side（侧面）。前朝向 front / q34front 直接沿用 back 的精灵，只是画在人物之前（靠背在人物身后）。
    static func buildChairsRotated(_ book: SpriteBook) {
        for style in ["mesh", "gaming", "wood"] {
            let meshDots = style == "mesh", wings = style == "gaming", slats = style == "wood"
            let C = Role.chairSh
            // ---- 3/4：靠背窄一点靠左，右边露出一条厚度；座面斜着 ----
            var g = Grid(w: 22, h: 26)
            var back = ShadeKit.shade(Bitmap("""
            ...###########....
            .###############..
            ################..
            ################..
            ################..
            ################..
            ################..
            .###############..
            .###############..
            ..#############...
            ...###########....
            """).offset(dx: 0, dy: 0, w: 22, h: 11), .chair)
            if meshDots { for y in 2..<9 { for x in 3..<14 where (x + y) % 2 == 0 && back[x, y] == Role.chair { back[x, y] = C } } }
            if wings { for y in 1..<10 { back[7, y] = Role.chair; back[8, y] = Role.chair; back[9, y] = Role.chair } }
            if slats { for y in 2..<10 { for x in [5, 8, 11] { back[x, y] = C } } }
            // 右侧厚度
            for y in 1..<10 { back[16, y] = C; back[17, y] = Role.chairSh }
            g.overlay(back)
            g.overlay(ShadeKit.shade(Bitmap("""
            ..################....
            .##################...
            ####################..
            .##################...
            """), .chair), dx: 1, dy: 11)
            for y in 15..<18 { g[10, y] = C; g[11, y] = C }
            for x in 5...16 { g[x, 18] = C }
            for (x, y) in [(4, 19), (5, 19), (16, 19), (17, 19), (3, 20), (4, 20), (17, 20), (18, 20), (2, 21), (3, 21), (18, 21), (19, 21), (2, 22), (3, 22), (18, 22), (19, 22)] { g[x, y] = C }
            book.add(g.sprite(name: "chair.\(style).q34", anchors: ["seatTop": IntPoint(11, 11), "backTop": IntPoint(9, 0)]))

            // ---- 侧面：靠背是一片薄板（在人物身后靠左），座面 16 宽 ----
            var s2 = Grid(w: 22, h: 26)
            var sb = ShadeKit.shade(Bitmap("""
            ..####
            .#####
            #####.
            ####..
            ####..
            ####..
            ####..
            ####..
            ####..
            .####.
            ..###.
            """), .chair)
            if slats { for y in 2..<9 { sb[2, y] = C } }
            s2.overlay(sb, dx: 1, dy: 0)
            s2.overlay(ShadeKit.shade(Bitmap("""
            ################
            ################
            ################
            .##############.
            """), .chair), dx: 2, dy: 11)
            for y in 15..<18 { s2[9, y] = C; s2[10, y] = C }
            for x in 4...15 { s2[x, 18] = C }
            for (x, y) in [(3, 19), (4, 19), (15, 19), (16, 19), (2, 20), (3, 20), (16, 20), (17, 20), (2, 21), (3, 21), (16, 21), (17, 21), (2, 22), (3, 22), (16, 22), (17, 22)] { s2[x, y] = C }
            book.add(s2.sprite(name: "chair.\(style).side", anchors: ["seatTop": IntPoint(10, 11), "backTop": IntPoint(3, 0)]))
        }
    }

    /// 坐姿的腿（正面 / 3/4 / 侧面）：程序画：大腿朝镜头方向缩短成一块，小腿垂下，鞋。宽 14，锚点 hip = 大腿根中心。
    static func buildLegs(_ book: SpriteBook) {
        // 正面坐姿：两条腿并排，大腿 3 行（透视缩短），小腿 5 行，鞋 2 行
        var front = Grid(w: 14, h: 11)
        let thigh = ShadeKit.shade(Bitmap("""
        ##############
        ##############
        ##############
        """), .pants)
        front.overlay(thigh)
        for (x0, _) in [(1, 0), (8, 0)] {
            let shin = ShadeKit.shade(Bitmap("""
            ####
            ####
            ####
            ####
            ####
            """), .pants)
            front.overlay(shin, dx: x0 + 1, dy: 3)
            let shoe = ShadeKit.shade(Bitmap("""
            #####
            #####
            """), Material(hi: Role.shoe, base: Role.shoe, sh: Role.shoe, out: Role.shoe))
            front.overlay(shoe, dx: x0, dy: 8)
        }
        book.add(front.sprite(name: "leg.sit.front", anchors: ["hip": IntPoint(7, 0)]))
        // 3/4 正面：两条腿略错开
        var q = Grid(w: 14, h: 11)
        q.overlay(ShadeKit.shade(Bitmap("""
        .#############
        ##############
        ##############
        """), .pants))
        q.overlay(ShadeKit.shade(Bitmap("""
        ####
        ####
        ####
        ####
        ####
        """), .pants), dx: 3, dy: 3)
        q.overlay(ShadeKit.shade(Bitmap("""
        ####
        ####
        ####
        ####
        """), .pants), dx: 9, dy: 3)
        let shoe = Material(hi: Role.shoe, base: Role.shoe, sh: Role.shoe, out: Role.shoe)
        q.overlay(ShadeKit.shade(Bitmap("#####\n#####"), shoe), dx: 2, dy: 8)
        q.overlay(ShadeKit.shade(Bitmap("#####\n#####"), shoe), dx: 8, dy: 7)
        book.add(q.sprite(name: "leg.sit.q34front", anchors: ["hip": IntPoint(7, 0)]))
        // 侧面：大腿水平向前（右），小腿垂下
        var sd = Grid(w: 14, h: 11)
        sd.overlay(ShadeKit.shade(Bitmap("""
        ..############
        ..############
        ..############
        ..############
        """), .pants))
        sd.overlay(ShadeKit.shade(Bitmap("""
        ####
        ####
        ####
        ####
        """), .pants), dx: 9, dy: 3)
        sd.overlay(ShadeKit.shade(Bitmap("######\n######"), shoe), dx: 8, dy: 8)
        book.add(sd.sprite(name: "leg.sit.side", anchors: ["hip": IntPoint(3, 0)]))
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
