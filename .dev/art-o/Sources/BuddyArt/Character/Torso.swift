import Foundation
import PixelKit

extension CharacterArt {
    /// 躯干精灵 14 宽。第 0 行 = 肩线上沿；头盒子的下巴行 (row 12) 要落在躯干第 0 行的上一行。
    /// 锚点：neck = 脖子中心，shoulderL / shoulderR = 手臂接上去的位置。
    static func buildTorso(_ book: SpriteBook) {
        // ---------- T 恤 ----------
        // 背面：12 宽，肩部略斜，两侧 1 列袖口（手臂另画）
        var teeBack = ShadeKit.shade(Bitmap("""
        ..##########..
        .############.
        ##############
        ##############
        ##############
        .############.
        .############.
        .############.
        .############.
        .############.
        """), .cloth)
        // 领口（背面是一道浅浅的弧）
        teeBack.overlay("""
        ..............
        .....tttt.....
        ..............
        """)
        // 后背褶皱：两道很淡的阴影
        teeBack.overlay("""
        ..............
        ..............
        ..............
        ..............
        ...t..........
        ...t......t...
        ..........t...
        """)
        book.add(teeBack.sprite(name: "torso.tee.back", anchors: ["neck": IntPoint(7, 0), "shoulderL": IntPoint(1, 3), "shoulderR": IntPoint(12, 3)]))

        // 正面
        var teeFront = ShadeKit.shade(Bitmap("""
        ..##########..
        .############.
        ##############
        ##############
        ##############
        .############.
        .############.
        .############.
        .############.
        .############.
        """), .cloth)
        teeFront.overlay("""
        ..............
        .....kkkk.....
        .....2KK2.....
        ......22......
        """)
        book.add(teeFront.sprite(name: "torso.tee.front", anchors: ["neck": IntPoint(7, 0), "shoulderL": IntPoint(1, 3), "shoulderR": IntPoint(12, 3)]))

        // 3/4 背面（朝右）：右肩略靠前，左肩略靠后
        var teeQ34B = ShadeKit.shade(Bitmap("""
        ..##########..
        .############.
        ##############
        ##############
        .#############
        ..############
        ..############
        ..############
        ..############
        ..############
        """), .cloth)
        teeQ34B.overlay("""
        ..............
        ......tttt....
        ..............
        """)
        book.add(teeQ34B.sprite(name: "torso.tee.q34back", anchors: ["neck": IntPoint(8, 0), "shoulderL": IntPoint(1, 3), "shoulderR": IntPoint(12, 3)]))
        // 侧面（朝右）：身体最窄，8 宽
        var teeSide = ShadeKit.shade(Bitmap("""
        ....######....
        ...########...
        ...########...
        ...########...
        ...########...
        ...########...
        ...########...
        ...########...
        ...########...
        ...########...
        """), .cloth)
        teeSide.overlay("""
        ..............
        ..............
        ..............
        ..............
        ..............
        ..............
        ..............
        ..............
        ...t..........
        ...t..........
        """)
        book.add(teeSide.sprite(name: "torso.tee.side", anchors: ["neck": IntPoint(7, 0), "shoulderL": IntPoint(6, 3), "shoulderR": IntPoint(7, 3)]))
        // 3/4 正面（朝右）
        var teeQ34F = ShadeKit.shade(Bitmap("""
        ..##########..
        .############.
        ##############
        ##############
        #############.
        ############..
        ############..
        ############..
        ############..
        ############..
        """), .cloth)
        teeQ34F.overlay("""
        ..............
        ......kkk.....
        ......2KK2....
        .......22.....
        """)
        book.add(teeQ34F.sprite(name: "torso.tee.q34front", anchors: ["neck": IntPoint(8, 0), "shoulderL": IntPoint(1, 3), "shoulderR": IntPoint(12, 3)]))

        // ---------- 卫衣（背面能看到兜帽）----------
        // 兜帽在最上面 4 行：像一个软软的半圆包住脖子；后面接肩膀
        var hoodBack = ShadeKit.shade(Bitmap("""
        ...########...
        ..##########..
        .############.
        .############.
        ##############
        ##############
        ##############
        ##############
        .############.
        .############.
        .############.
        .############.
        """), .cloth)
        hoodBack.overlay("""
        ..............
        ....tttttt....
        ...t......t...
        ...t..hh..t...
        ..............
        .....tt.tt....
        ......t..t....
        """)
        book.add(hoodBack.sprite(name: "torso.hoodie.back", anchors: ["neck": IntPoint(7, 2), "shoulderL": IntPoint(1, 5), "shoulderR": IntPoint(12, 5)]))

        var hoodFront = ShadeKit.shade(Bitmap("""
        ..##########..
        .############.
        ##############
        ##############
        ##############
        .############.
        .############.
        .############.
        .############.
        .############.
        """), .cloth)
        hoodFront.overlay("""
        ..............
        ....t2KK2t....
        ....t.22.t....
        ....t....t....
        .....t..t.....
        ......tt......
        """)
        book.add(hoodFront.sprite(name: "torso.hoodie.front", anchors: ["neck": IntPoint(7, 0), "shoulderL": IntPoint(1, 3), "shoulderR": IntPoint(12, 3)]))
    }

    // ---------- 手臂（背面，左臂朝内倾；右臂水平翻转）----------
    /// 手臂精灵 5×11：上端是手，下端是肩。袖子取衣服色，手取肤色。下半截整体向外偏 1 列 = 手比肩更靠内。
    static func buildArms(_ book: SpriteBook) {
        let up = Grid.from("""
        ..22.
        .2KK2
        .2KK2
        .3ss3
        .3SS3
        .3SS3
        3SSt3.
        3SSt3.
        3StS3.
        3ttt3.
        .333..
        """)
        book.add(up.sprite(name: "arm.typeUp", anchors: ["hand": IntPoint(2, 1), "shoulder": IntPoint(2, 10)]))
        let down = Grid.from("""
        .....
        ..22.
        .2KK2
        .3ss3
        .3SS3
        .3SS3
        3SSt3.
        3SSt3.
        3StS3.
        3ttt3.
        .333..
        """)
        book.add(down.sprite(name: "arm.typeDown", anchors: ["hand": IntPoint(2, 2), "shoulder": IntPoint(2, 10)]))
    }
}
