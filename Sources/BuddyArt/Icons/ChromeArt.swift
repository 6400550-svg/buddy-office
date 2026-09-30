import Foundation
import PixelKit

/// 办公室窗口标题栏里的像素按钮：12×12 的木牌底板（4 种状态）+ 10×10 的图标（缩成小鱼缸 / 桌面宠物 / 设置）。
/// 底板的画法和桌牌一致（橡木、选择性描边）；「亮着」的状态用金色描边表示这个形态现在开着。
public enum ChromeArt {
    public enum State: Int, CaseIterable, Sendable { case normal, hover, pressed, on }
    public static let iconNames = ["chrome.tank", "chrome.strip", "chrome.gear"]

    public static let book: SpriteBook = {
        let b = SpriteBook()
        let L = PropLegend.legend
        // 底板 12×12：X 描边、O 高光、o 基色、x 阴影；四个角切掉
        func plate(_ name: String, edge: Character, top: Character, fill: Character, bottom: Character) {
            var rows: [String] = []
            for y in 0..<12 {
                var r = ""
                for x in 0..<12 {
                    let corner = (x == 0 || x == 11) && (y == 0 || y == 11)
                    if corner { r += "."; continue }
                    if y == 0 || y == 11 || x == 0 || x == 11 { r += String(edge); continue }
                    if y == 1 { r += String(top) } else if y == 10 { r += String(bottom) } else { r += String(fill) }
                }
                rows.append(r)
            }
            b.add(name, rows.joined(separator: "\n"), legend: L)
        }
        plate("plate.normal", edge: "X", top: "O", fill: "o", bottom: "x")
        plate("plate.hover", edge: "X", top: "W", fill: "O", bottom: "o")
        plate("plate.pressed", edge: "X", top: "x", fill: "x", bottom: "x")
        plate("plate.on", edge: "g", top: "G", fill: "o", bottom: "x")

        // 小鱼缸：玻璃缸（蓝色的水，亮边），一条橙色的小鱼，一丛水草，缸底的沙
        b.add("chrome.tank", """
        .########.
        #UUUUUUUU#
        #cccccccc#
        #ccc:::cc#
        #cc:Z::::#
        #ccc:::cc#
        #cccccccc#
        #lcLccccc#
        #SSSSSSSS#
        .########.
        """, legend: L)
        // 桌面宠物：一块屏幕，桌面蓝色，最下面一条任务栏，任务栏上站着一只小黄鸭
        b.add("chrome.strip", """
        .########.
        #cccccccc#
        #cccccccc#
        #ccccQjcc#
        #cccjjjjc#
        #ccjjjjjc#
        #oooooooo#
        .########.
        ...mmmm...
        ..mmmmmm..
        """, legend: L)
        // 设置：8 个齿的齿轮（4 个正方向的宽齿 + 4 个斜方向的窄齿），左上高光、右下阴影，中间一个 2×2 的孔
        b.add("chrome.gear", """
        ....##....
        ..##MM##..
        .#M#Mm#m#.
        .##Mmmm##.
        #MMm##mmn#
        #Mmm##mnn#
        .##mmmn##.
        .#m#mn#n#.
        ..##nn##..
        ....##....
        """, legend: L)
        return b
    }()

    /// 一个按钮画成一块画布（12×12）：底板 + 图标；按下去时图标下沉 1 像素。
    public static func button(icon: String, state: State) -> Canvas {
        let c = Canvas(width: 12, height: 12)
        let style = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        let plate = book["plate.\(String(describing: state))"]
        c.blit(plate, x: 0, y: 0, style: style)
        c.blit(book[icon], x: 1, y: state == .pressed ? 2 : 1, style: style)
        return c
    }
}
