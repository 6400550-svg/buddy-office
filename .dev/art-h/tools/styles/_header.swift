import Foundation
import PixelKit

// 七种发型 × 五个朝向（back / q34back / side / q34front / front，全部朝向画面右侧）：
//   ponytail 高马尾 · bun 单丸子头 · twinBuns 双丸子 · long 长直发 · messy 凌乱短发 · buzz 寸头 · curly 蓬松卷发
//
// 写法：每行带标签，坐标全是头盒子坐标（x=0…11 是头盒子，画布可以往左右各伸 2 列 x=−2…13、往上 3 行 y=−3…16）：
//     `5| .####.###.#.`   第 5 行，第一个字符在 x=0
//     `5@3| gHHg`         第 5 行，第一个字符在 x=3（稀疏细节用，不用数前面的点）
// 蒙版里任何非 '.' 的字符都算头发；ShadeKit 自动上描边 + 高光 + 阴影；细节再用 ASCII 盖上去（'.' 不动，'_' 擦成透明）。
// 细节里用到的角色：h H g（发高光/基/影）· 1（发描边）· a A u（点缀色：发圈）
//   · r（夜间屏幕反光：画在背面头顶最上沿的两三格，白天等于发高光色，夜里被屏幕光染色，兼作暗色头发在深色显示器前的勾边）
//   · j（肤色阴影：刘海在额头上的投影，只画在第 5 行、脸的禁区之外）。
// 约定：背面 / 3/4 背面盖住整个后脑（除了寸头、短发露出耳朵和后颈）；3/4 背面右侧第 10–11 列第 8–10 行永远留给耳朵和脸颊；
//       正面 / 3/4 正面 / 侧面不盖第 6–12 行的脸区域；侧面耳朵 (3–4, 8–10) 只有长发和卷发会盖住。

extension CharacterArt {
    /// 一行画布内容：第 y 行、从第 x 列（头盒子坐标）开始的一段字符。
    struct HairFullRow { var y: Int; var x: Int; var text: String }

    /// 解析「带标签」的行：`5| .####.###.#.` 表示 y=5、从 x0 开始；`5@3| gHHg` 表示 y=5、从 x=3 开始；
    /// 没有标签的行接着上一行的 y + 1。行首行尾的空行忽略。标签让蒙版和细节都不用数空行。
    static func hairFullRows(_ s: String, x0: Int, y0: Int) -> [HairFullRow] {
        var ls = s.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        while let f = ls.first, f.isEmpty { ls.removeFirst() }
        while let l = ls.last, l.isEmpty { ls.removeLast() }
        var out: [HairFullRow] = []
        var y = y0
        for line in ls {
            var x = x0
            var body = line
            if let bar = line.firstIndex(of: "|") {
                let head = line[..<bar].trimmingCharacters(in: .whitespaces)
                body = line[line.index(after: bar)...].trimmingCharacters(in: .whitespaces)
                let parts = head.split(separator: "@").map { String($0) }
                if let yy = Int(parts[0]) { y = yy }
                if parts.count > 1, let xx = Int(parts[1]) { x = xx }
            }
            if !body.isEmpty { out.append(HairFullRow(y: y, x: x, text: body)) }
            y += 1
        }
        return out
    }

    /// 整画布写法：蒙版 → ShadeKit 自动描边/高光/阴影 → 细节 ASCII 盖上去。坐标一律是头盒子坐标。
    static func hairFullSprite(name: String, x0: Int, y0: Int, mask: String, detail: String) -> IndexedSprite {
        var m = Bitmap(w: hairW, h: hairH)
        for r in hairFullRows(mask, x0: x0, y0: y0) {
            for (i, c) in r.text.enumerated() where c != "." && c != " " {
                let px = r.x + i + hairPad.x, py = r.y + hairPad.y
                precondition(px >= 0 && px < hairW && py >= 0 && py < hairH, "\(name) 蒙版 (x=\(r.x + i), y=\(r.y)) 超出 16×20 画布")
                m[px, py] = true
            }
        }
        var g = ShadeKit.shade(m, .hair)
        for r in hairFullRows(detail, x0: x0, y0: y0) {
            for (i, _) in r.text.enumerated() {
                let px = r.x + i + hairPad.x, py = r.y + hairPad.y
                precondition(px >= 0 && px < hairW && py >= 0 && py < hairH, "\(name) 细节 (x=\(r.x + i), y=\(r.y)) 超出 16×20 画布")
            }
            g.overlay(r.text, dx: r.x + hairPad.x, dy: r.y + hairPad.y)
        }
        return g.sprite(name: name, anchors: ["head": hairPad])
    }

    static func addHairFull(_ book: SpriteBook, _ style: String, _ facing: Facing, x0: Int = 0, y0: Int = 0, mask: String, detail: String = "") {
        book.add(hairFullSprite(name: "hair.\(style).\(facing.name)", x0: x0, y0: y0, mask: mask, detail: detail))
    }

    static func buildHairStyles(_ book: SpriteBook) {
        buildPonytail(book)
        buildBun(book)
        buildTwinBuns(book)
        buildLong(book)
        buildMessy(book)
        buildBuzz(book)
        buildCurly(book)
    }

