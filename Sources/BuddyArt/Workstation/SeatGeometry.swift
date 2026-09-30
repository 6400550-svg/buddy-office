import Foundation
import PixelKit

/// 工位格里各件东西的位置（工位格坐标，原点在格子左上角，56×64，桌牌带在其下 10 px）。
/// 这些数字是「比例」的定稿：改动会影响整个场景。
public enum SeatGeometry {
    /// 桌牌带 12 像素（任务书写 10）：两行字（11 pt + 10 pt，笔画共约 23 pt）在 3 倍下要 24 pt 以上的内部高度，10 像素的带子里放不下（text-audit 量出来的）。
    public static let cellW = 56, cellH = 64, plateH = 12
    public static let deskX = 2, deskY = 22
    public static let monX = 14, monY = 2                 // 显示器外框 28×20；屏幕区 24×15 在 (monX+2, monY+2)
    public static let standX = 22, standY = 22
    public static let kbX = 13, kbY = 25                  // 键盘 20×6
    public static let mouseX = 37, mouseY = 27
    public static let mugX = 5, mugY = 26
    public static let lampX = 41, lampY = 12
    public static let ornX = 6, ornY = 17
    public static let buddyCx = 29                        // 人物中心（略偏右：左手落在键盘左半，右手够得到鼠标）
    public static let headTopY = 16                       // 头盒子上沿
    public static let chairY = 35
    /// buddy 图层左上角在工位格里的位置。
    public static var layerOrigin: IntPoint { IntPoint(buddyCx - BuddyRig.cx, headTopY - BuddyRig.headY) }
    public static var screenRect: IntRect { IntRect(monX + 2, monY + 2, 24, 15) }
}
