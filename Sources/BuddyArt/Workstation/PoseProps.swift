import Foundation
import PixelKit

extension PropArt {
    /// 姿势会用到的桌面道具。
    static func buildPoseProps(_ b: SpriteBook) {
        // 便签本 10×8（列计划 / 做计划时放在键盘右边）
        add(b, "prop.notepad", """
        .%%%%%%%%.
        %pppppppp%
        %p11111pp%
        %pppppppp%
        %p11111pp%
        %pppppppp%
        %p11ppppp%
        .%%%%%%%%.
        """)
        // 一摞纸 10×6
        add(b, "prop.papers", """
        .%%%%%%%%.
        %WWWWWWWv%
        %WqqqqqqW%
        %WWWWWWWv%
        %wwwwwwwv%
        .%%%%%%%%.
        """)
        // 纸箱 12×8（整理上下文）
        add(b, "prop.box", """
        .###########.
        #ooooooooooX#
        #oOOOOOOOOoX#
        #ooooooooooX#
        #oxxxxxxxxoX#
        #ooooooooooX#
        #xxxxxxxxxxX#
        .###########.
        """)
        // 发件盘 14×6
        add(b, "prop.tray", """
        .############.
        #mmmmmmmmmmmm#
        #MnnnnnnnnnnM#
        #NNNNNNNNNNNN#
        #nnnnnnnnnnnn#
        .############.
        """)
        // 闹钟 9×9
        add(b, "prop.alarm", """
        .##...##.
        #rr###rr#
        .#WWWWW#.
        #WWWWWWW#
        #WWWWWWW#
        #WWWWWWW#
        .#WWWWW#.
        ..#####..
        .#.....#.
        """)
        // 写字板 16×11（计划待审时举着）：夹子 + 纸 + 几行字
        add(b, "prop.clipboard", """
        ....########....
        ...#gggggggg#...
        .##############.
        #dppppppppppppd#
        #dp1111pppppppd#
        #dppppppppppppd#
        #dp11111111pppd#
        #dppppppppppppd#
        #dp1111111ppppd#
        #dppppppppppppd#
        .##############.
        """)
        // 显示器上的小旗 6×8（一轮做完、你还没看：未读标记）
        add(b, "prop.flag", """
        #.....
        #rrrr.
        #RRrrr
        #rrrr.
        #.....
        #.....
        #.....
        ##....
        """)
    }
}
