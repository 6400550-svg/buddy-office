import Foundation
import PixelKit
import BuddyArt

/// 显示器屏幕里显示什么（24×15 像素）。每一种都由（种类, 时间）决定，纯函数，没有内部状态。
public enum ScreenKind: Hashable {
    case off
    case ide                       // 思考：IDE，光标静止（缓慢呼吸）
    case doc(String)               // Read：文档滚动，颜色随扩展名
    case results                   // Grep：结果列表
    case tree                      // Glob / LS：文件树展开
    case diffEdit                  // Edit：一行高亮 + 字符逐个出现 + 绿色 diff 标记
    case notebook                  // Write / NotebookEdit：一行行出现 / 单元格
    case terminal                  // Bash（短）
    case terminalLong              // Bash（长）：进度条按 1-e^(-t/τ)，永远不会满
    case browser                   // WebFetch
    case search                    // WebSearch
    case helpers                   // Agent：小助手列表 + 进度
    case checklist                 // TodoWrite：清单逐项打勾
    case manual                    // Skill：手册页
    case iconGrid                  // ToolSearch：图标网格，高亮在动
    case mcpBrowser                // MCP 浏览器：指针在动，点击处有扩散圈（只用调色板变暗，不闪）
    case desktop                   // computer-use：桌面上有窗口和指针
    case mcpApp(String)            // 其他 MCP：带 server 首字母的应用面板
    case permission                // 等批准：权限对话框
    case question                  // 提问：带选项的对话框
    case plan                      // 计划待审 / 做计划：计划文档
    case compact                   // 整理上下文：一行行被压成一块
    case retry(Int, Int)           // 重试中：转圈 + 像素数字
    case warning                   // 出错：橙色三角
    case stop                      // 被打断：停止标志
    case done                      // 做完了：绿色 ✓
    case idleDesktop               // 空闲：暗色桌面
    case screensaver               // 打盹：慢速屏保
    case gear                      // 未知工具：带齿轮的通用窗口
    case outbox                    // SendUserFile：文件滑进盘里
    case clock                     // 定时：钟面
    case log                       // Monitor：日志滚动
}

public enum ScreenContent {
    static func P(_ n: String) -> UInt8 { Pal.dx(n) }
    static func hash(_ a: Int, _ b: Int = 0) -> Int {
        var h = UInt64(bitPattern: Int64(a &* 73856093 ^ b &* 19349663)) &* 0x9E3779B97F4A7C15
        h ^= h >> 31
        return Int(h & 0x7FFFFFFF)
    }

    /// 连续滚动的屏幕（文档 / 终端 / 日志）按「整数个渲染帧」一步。办公室稳态是 15 fps（一帧 66.7 ms）：一步 150 ms = 2.25 帧时，
    /// 节奏变成 2、3、2、3 帧的不均匀，滚起来一顿一顿（DESIGN 第 7 节给打字专门解决过同样的问题）。
    /// 时刻加 20 ms 的偏移，让帧落在一步的中间而不是压在边界上：浮点误差 / 计时抖动不会让某一步多一帧或少一帧。
    static func rhythm(_ t: Double, every: Double) -> Int { Int(((t + 0.02) / every).rounded(.down)) }
    static let docScrollEvery = 2.0 / 15          // 2 帧（133 ms）
    static let terminalScrollEvery = 0.4          // 6 帧
    static let logScrollEvery = 1.0 / 3           // 5 帧

    /// 屏幕内容里第几行以下会被人的头挡住（`buddyctl screens` 的红框）：关键信息要放在它上面。
    static let headOcclusionTopRow = 12
    /// Bash 长任务的进度条在屏幕里的第几行（2 像素高）。
    static let longBashBarY = 5

    /// 「其他 MCP」屏幕上画的 server 首字母：名字里第一个 4×6 像素字体画得出来的字母（大写）；没有（全是中文 / 数字 / 符号）就用 M（MCP）。
    static func mcpInitial(_ name: String) -> Character {
        name.uppercased().first { $0.isLetter && PixelFont.small.hasGlyph($0) } ?? "M"
    }

    struct StaticKey: Hashable { var kind: ScreenKind; var seed: Int }
    nonisolated(unsafe) static var staticCache: [StaticKey: Bool] = [:]
    private static let staticLock = NSLock()
    /// 这种屏幕内容会不会随时间变？在几个差得很远的时刻各画一遍比较：完全相同就当作静态
    /// （局部重绘时静态屏幕不用每帧重画来比较）。结果按（种类, 种子）缓存。
    public static func isStatic(_ k: ScreenKind, seed: Int) -> Bool {
        let key = StaticKey(kind: k, seed: seed)
        staticLock.lock()
        if let r = staticCache[key] { staticLock.unlock(); return r }
        staticLock.unlock()
        let day = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        let c = Canvas(width: 24, height: 18)
        let rect = IntRect(0, 0, 24, 18)
        var first: UInt64 = 0
        var same = true
        for (i, tg) in [(0.0, 0.0), (0.37, 0.41), (2.9, 5.1), (13.3, 31.7), (60.1, 99.9), (301.7, 1234.5), (1.05, 1.1), (7.77, 8.8), (0.6, 2.3)].enumerated() {
            c.clear()
            draw(k, on: c, rect: rect, t: tg.0, gt: tg.1, seed: seed, style: day)
            let h = c.contentHash()
            if i == 0 { first = h } else if h != first { same = false; break }
        }
        staticLock.lock()
        if staticCache.count > 4096 { staticCache.removeAll() }          // ScreenKind 里带 .doc(扩展名) / .mcpApp(server 名)，理论上无界：超过 4096 条整体清空（再算一遍很便宜）
        staticCache[key] = same
        staticLock.unlock()
        return same
    }

    /// 屏幕发出的光的主色（夜里染在头发和肩膀上）。
    public static func glowColor(_ k: ScreenKind) -> RGBA8? {
        switch k {
        case .off, .idleDesktop, .screensaver: return nil
        case .terminal, .terminalLong, .log: return RGBA8(hex: 0x7DF0A0)
        case .permission, .warning: return RGBA8(hex: 0xFFC857)
        case .stop: return RGBA8(hex: 0xFF7676)
        case .done: return RGBA8(hex: 0x7DF0A0)
        case .diffEdit, .ide, .notebook: return RGBA8(hex: 0x6FE3FF)
        default: return RGBA8(hex: 0xBFD8FF)
        }
    }

    /// 画进屏幕区 r（24×15）。t = 这个内容已经显示了多久（秒）；gt = 全局时间（呼吸、光标用）。
    public static func draw(_ k: ScreenKind, on c: Canvas, rect r: IntRect, t: Double, gt: Double, seed: Int, style: Resolved) {
        // 底色
        let bg: UInt8
        switch k {
        case .terminal, .terminalLong, .log: bg = P("scr.term")
        case .idleDesktop, .screensaver: bg = P("scr.bg")
        case .off: bg = P("plastic.sh")
        default: bg = P("scr.bg2")
        }
        c.fillRect(r, value: bg, style: style)
        if k == .off {
            // 关屏：一点点暗的反光，待机灯在显示器外框上（由座位渲染画）
            for i in 0..<4 { c.set(r.x + 2 + i, r.y + 2, value: P("plastic.base"), style: style) }
            return
        }
        func px(_ x: Int, _ y: Int, _ n: String) { c.set(r.x + x, r.y + y, value: P(n), style: style) }
        func hl(_ x: Int, _ y: Int, _ w: Int, _ n: String) { if w > 0 { c.hLine(x: r.x + x, y: r.y + y, length: w, value: P(n), style: style) } }
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ n: String) { c.fillRect(IntRect(r.x + x, r.y + y, w, h), value: P(n), style: style) }
        func titleBar() { rect(0, 0, r.w, 2, "scr.bg3"); px(1, 0, "scr.red"); px(3, 0, "scr.amber"); px(5, 0, "scr.green") }
        // 光标：3 个色阶之间 0.5 Hz 缓慢呼吸，不是开关式闪烁
        func cursorColor() -> String {
            let ph = breathPhase(gt, period: 2.0)
            return ph < 0.34 ? "scr.dark" : (ph < 0.67 ? "scr.dim" : "scr.white")
        }
        let codeColors = ["scr.cyan", "scr.green", "scr.amber", "scr.pink", "scr.purple", "scr.white"]

        switch k {
        case .ide:
            titleBar()
            for y in 0..<6 { hl(1, 3 + y * 2, 1, "scr.dark") }                       // 行号槽
            for y in 0..<6 {
                let indent = [0, 2, 2, 4, 2, 0][y]
                let len = 4 + hash(seed, y) % 9
                hl(3 + indent, 3 + y * 2, min(len, r.w - 5 - indent), codeColors[(hash(seed, y + 7)) % codeColors.count])
            }
            rect(3 + 4, 3 + 2 * 3, 1, 1, cursorColor())                               // 光标静止在一行末
        case .doc(let ext):
            titleBar()
            let hue: String
            switch ext {
            case "swift": hue = "scr.orange"; case "py": hue = "scr.green"; case "js", "ts", "jsx", "tsx": hue = "scr.amber"
            case "md", "txt": hue = "scr.white"; case "json", "yaml", "yml", "toml": hue = "scr.cyan"
            case "html", "css": hue = "scr.pink"; case "sh", "zsh": hue = "scr.green"; default: hue = "scr.blue" }
            let scroll = Self.rhythm(t, every: Self.docScrollEvery)
            for row in 0..<6 {
                let line = (row + scroll / 2) % 64
                let len = 5 + hash(seed, line) % 13
                let ind = hash(seed, line + 100) % 3 * 2
                hl(2 + ind, 3 + row * 2 - (scroll % 2), min(len, r.w - 4 - ind), (hash(seed, line + 3) % 5 == 0) ? "scr.dim" : hue)
            }
            rect(0, 2, r.w, 1, "scr.bg2")      // 挡住标题栏下的溢出
            titleBar()
        case .results:
            titleBar()
            let sel = Int(smoothstep((t.truncatingRemainder(dividingBy: 2.4)) / 1.2) * 3.0 + (t.truncatingRemainder(dividingBy: 2.4) > 1.2 ? 0 : 0))
            for i in 0..<4 {
                let y = 3 + i * 3
                if i == sel % 4 { rect(1, y - 1, r.w - 2, 3, "scr.bg3") }              // 高亮条（缓动）
                px(2, y, ["scr.amber", "scr.cyan", "scr.green", "scr.pink"][i])
                hl(4, y, 6 + hash(seed, i) % 9, "scr.dim")
            }
        case .tree:
            titleBar()
            let open = min(5, 1 + Int(t / 0.35))
            for i in 0..<open {
                let depth = [0, 1, 1, 2, 1][i % 5]
                px(1 + depth * 2, 3 + i * 2, i % 5 == 0 ? "scr.amber" : "scr.cyan")
                hl(3 + depth * 2, 3 + i * 2, 4 + hash(seed, i) % 7, "scr.dim")
            }
        case .diffEdit:
            titleBar()
            for y in 0..<6 { hl(3, 3 + y * 2, 3 + hash(seed, y) % 11, y == 3 ? "scr.white" : "scr.dim") }
            rect(1, 3 + 3 * 2 - 0, 1, 1, "scr.green"); rect(0, 3 + 3 * 2, 2, 1, "scr.green")
            rect(2, 3 + 3 * 2 - 1, r.w - 4, 3, "scr.bg3")                             // 高亮的那一行
            let chars = min(14, Int(t * 6))                                            // 字符逐个出现
            hl(3, 3 + 3 * 2, chars, "scr.white")
            px(3 + chars, 3 + 3 * 2, cursorColor())
            for y in [1, 5] { hl(3, 3 + y * 2, 4 + hash(seed, y + 30) % 8, "scr.green") }
            px(1, 3 + 2, "scr.red")
        case .notebook:
            titleBar()
            let rows = min(6, 1 + Int(t / 0.28))
            for i in 0..<rows { hl(2, 3 + i * 2, 4 + hash(seed, i) % 14, codeColors[hash(seed, i + 9) % 6]) }
            if rows < 6 { px(2 + 4, 3 + (rows - 1) * 2, cursorColor()) }
        case .terminal, .terminalLong:
            px(1, 1, "scr.green"); px(2, 2, "scr.green"); px(1, 3, "scr.green")           // > 提示符
            hl(4, 2, 5, "scr.white")
            // 屏幕第 12 行以下会被人的头挡住：进度条放在提示符下面（第 5–6 行），输出行往下让（只剩两行），不然 Bash 长任务的进度条只露出最左边一小段
            let long = k == .terminalLong
            let lines = long ? 2 : 4
            let scroll = Self.rhythm(t, every: Self.terminalScrollEvery)
            for i in 0..<lines {
                let li = i + scroll
                let len = 3 + hash(seed, li) % 14
                hl(1, (long ? 8 : 5) + i * 2, len, hash(seed, li + 5) % 4 == 0 ? "scr.dim" : "scr.green")
            }
            if long {
                // 进度条：1 - e^(-t/τ)，τ = 30 秒，永远不会假装跑满
                let p = 1 - exp(-t / 30)
                rect(1, Self.longBashBarY, r.w - 2, 2, "scr.dark")
                rect(1, Self.longBashBarY, max(1, Int(Double(r.w - 2) * min(0.94, p))), 2, "scr.green")
            } else { px(1 + (hash(seed, scroll) % 4), r.h - 3, cursorColor()) }
        case .browser:
            rect(1, 1, r.w - 2, 2, "scr.white"); rect(2, 1, 1, 2, "scr.dim")
            hl(3, 2, 8, "scr.dark")
            let blocks = min(4, 1 + Int(t / 0.5))
            for i in 0..<blocks {
                let bx = 2 + (i % 2) * 11, by = 4 + (i / 2) * 5
                rect(bx, by, 9, 4, i == 0 ? "scr.blue" : "scr.bg3")
                hl(bx + 1, by + 1, 5, "scr.dim")
            }
        case .search:
            rect(1, 1, r.w - 2, 2, "scr.white")
            px(3, 1, "scr.dark"); px(4, 2, "scr.dark")                                  // 放大镜
            hl(6, 2, min(9, 2 + Int(t * 4)), "scr.dark")
            for i in 0..<3 {
                let y = 5 + i * 3
                hl(2, y, 8 + hash(seed, i) % 8, "scr.blue")
                hl(2, y + 1, 5 + hash(seed, i + 4) % 10, "scr.dim")
            }
        case .helpers:
            titleBar()
            for i in 0..<3 {
                let y = 3 + i * 4
                rect(1, y, 3, 3, ["scr.cyan", "scr.pink", "scr.amber"][i])
                rect(5, y + 1, r.w - 7, 1, "scr.dark")
                let p = min(1.0, (t * (0.25 + Double(i) * 0.07)).truncatingRemainder(dividingBy: 1.3))
                rect(5, y + 1, max(1, Int(Double(r.w - 7) * min(1, p))), 1, "scr.green")
            }
        case .checklist:
            titleBar()
            let ticked = Int(t / 0.7)
            for i in 0..<5 {
                let y = 3 + i * 2
                rect(2, y, 2, 1, i < ticked % 6 ? "scr.green" : "scr.dark")
                hl(5, y, 5 + hash(seed, i) % 10, i < ticked % 6 ? "scr.dim" : "scr.white")
            }
        case .manual:
            rect(1, 1, 10, 13, "scr.white"); rect(12, 1, 10, 13, "scr.white"); rect(11, 1, 1, 13, "scr.dim")
            let flip = Int(t / 1.6) % 2
            for i in 0..<5 { hl(2, 3 + i * 2, 6, "scr.dark"); hl(13, 3 + i * 2, 5 + hash(seed, i + flip) % 4, "scr.dark") }
            hl(2, 2, 4, "scr.orange")
        case .iconGrid:
            let hi = Int(t / 0.5) % 6
            for i in 0..<6 {
                let gx = 2 + (i % 3) * 7, gy = 2 + (i / 3) * 7
                if i == hi { rect(gx - 1, gy - 1, 7, 7, "scr.bg3") }
                rect(gx, gy, 5, 5, ["scr.cyan", "scr.amber", "scr.pink", "scr.green", "scr.purple", "scr.orange"][i])
                px(gx + 2, gy + 2, "scr.bg2")
            }
        case .mcpBrowser:
            rect(1, 1, r.w - 2, 2, "scr.white"); hl(3, 2, 8, "scr.dark")
            rect(2, 4, 9, 4, "scr.blue"); rect(12, 4, 9, 4, "scr.bg3"); rect(2, 9, 19, 4, "scr.bg3")
            // 指针沿一条环形小路走，每隔一会儿点一下（点击处用更暗的一圈，不闪白）
            let cyc = t.truncatingRemainder(dividingBy: 3.0) / 3.0
            let a = cyc * 2 * Double.pi
            let cx = 11 + Int((sin(a) * 6).rounded()), cy = 8 + Int((cos(a * 2) * 2).rounded())
            if cyc > 0.5 && cyc < 0.62 {
                for (dx, dy) in [(-2, 0), (2, 0), (0, -2), (0, 2)] { px(cx + dx, cy + dy, "scr.dark") }
            }
            px(cx, cy, "scr.white"); px(cx + 1, cy + 1, "scr.white"); px(cx, cy + 1, "scr.white")
        case .desktop:
            rect(0, 0, r.w, r.h, "scr.bg")
            rect(2, 2, 11, 7, "scr.bg3"); rect(2, 2, 11, 1, "scr.dim")
            rect(9, 6, 12, 7, "scr.bg2"); rect(9, 6, 12, 1, "scr.blue")
            rect(0, r.h - 1, r.w, 1, "scr.dark")
            let a = t * 0.9
            let cx = 12 + Int((sin(a) * 7).rounded()), cy = 8 + Int((cos(a * 0.7) * 3).rounded())
            px(cx, cy, "scr.white"); px(cx + 1, cy + 1, "scr.white"); px(cx, cy + 1, "scr.white")
        case .mcpApp(let name):
            titleBar()
            let letter = String(Self.mcpInitial(name))
            let w = PixelFont.small.width(of: letter)
            rect(2, 3, r.w - 4, r.h - 5, "scr.bg3")
            PixelFont.small.draw(letter, x: r.x + (r.w - w) / 2, y: r.y + 5, value: P("scr.cyan"), style: style, on: c, container: r)
            hl(4, 12, 4 + Int(t * 3) % 10, "scr.dim")
        case .permission:
            // 对话框：窗口 + 钥匙 + 两个按钮（灰=拒绝，绿=允许）
            rect(2, 1, r.w - 4, r.h - 2, "scr.white")
            rect(2, 1, r.w - 4, 2, "scr.blue")
            rect(4, 4, 3, 3, "scr.amber"); px(5, 7, "scr.amber"); px(5, 8, "scr.amber")
            hl(9, 5, 10, "scr.dark"); hl(9, 7, 7, "scr.dim")
            rect(4, 10, 7, 3, "scr.dim"); rect(13, 10, 7, 3, "scr.green")
        case .question:
            rect(2, 1, r.w - 4, r.h - 2, "scr.white")
            rect(2, 1, r.w - 4, 2, "scr.blue")
            PixelFont.tiny.draw("?", x: r.x + 4, y: r.y + 4, value: P("scr.blue"), style: style, on: c, container: r)
            hl(8, 4, 11, "scr.dark")
            for i in 0..<3 { px(5, 8 + i * 2, "scr.blue"); hl(7, 8 + i * 2, 6 + hash(seed, i) % 8, "scr.dim") }
        case .plan:
            rect(3, 1, r.w - 6, r.h - 2, "scr.white")
            hl(5, 3, 8, "scr.blue")
            for i in 0..<4 { px(5, 6 + i * 2, "scr.dark"); hl(7, 6 + i * 2, 5 + hash(seed, i) % 8, "scr.dim") }
        case .compact:
            titleBar()
            // 一行行被压成一块：行越来越短、越来越挤
            let p = min(1.0, (t.truncatingRemainder(dividingBy: 3.0)) / 2.4)
            for i in 0..<6 {
                let target = 3 + 7 + i / 2
                let y = Int(Double(3 + i * 2) * (1 - p) + Double(target) * p)
                let len = Int(Double(4 + hash(seed, i) % 12) * (1 - p * 0.5))
                hl(2, y, max(2, len), i % 2 == 0 ? "scr.dim" : "scr.cyan")
            }
            if p > 0.8 { rect(2, 10, 8, 3, "scr.dark") }
        case .retry(let a, let b):
            // 缓慢转动的循环箭头（4 帧，约 0.6 Hz）+ 像素数字
            let f = Int(t / 0.42) % 4
            let pts: [[(Int, Int)]] = [[(10, 3), (11, 3), (12, 4), (12, 5)], [(12, 6), (12, 7), (11, 8), (10, 8)], [(9, 8), (8, 8), (7, 7), (7, 6)], [(7, 5), (7, 4), (8, 3), (9, 3)]]
            // 箭头在左、数字在右，都放在屏幕上半部分（第 12 行以下会被人的头挡住，数字放在下面就只剩半个）；
            // 「10/10」一行放不下（箭头 6 + 数字 19 > 屏幕宽 24）：换成 3×3 的小转圈（8 个点里亮着一个，顺时针走）+ 数字。
            let s = "\(a)/\(b)"
            let w = PixelFont.tiny.width(of: s)
            let wide = w > 15
            if wide {
                let ring = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]
                let k = Int(t / 0.21) % 8
                for (i, q) in ring.enumerated() { px(q.0, 5 + q.1, i == k ? "scr.amber" : "scr.dark") }
            } else {
                for (i, arr) in pts.enumerated() { for p in arr { px(p.0 - 5, p.1, i == f ? "scr.amber" : "scr.dark") } }
            }
            PixelFont.tiny.draw(s, x: r.x + (wide ? r.w - w - 1 : min(9, r.w - w - 1)), y: r.y + 4, value: P("scr.white"), style: style, on: c, container: r)
        case .warning:
            // 橙色三角警告，静止
            for i in 0..<9 { hl(11 - i / 2 - (i > 0 ? 0 : 0), 2 + i, 1 + i, "scr.orange") }
            for y in 4..<8 { px(11, y, "scr.bg2") }
            px(11, 9, "scr.bg2")
        case .stop:
            rect(8, 3, 8, 8, "scr.red"); rect(9, 2, 6, 10, "scr.red"); rect(7, 4, 10, 6, "scr.red")
            rect(9, 6, 6, 2, "scr.white")
        case .done:
            // 绿色 ✓
            let pts = [(6, 8), (7, 9), (8, 10), (9, 9), (10, 8), (11, 7), (12, 6), (13, 5), (14, 4)]
            for p in pts { px(p.0, p.1, "scr.green"); px(p.0, p.1 - 1, "scr.green") }
        case .idleDesktop:
            // 暗色桌面：几个小图标 + 一条暗任务栏
            for i in 0..<3 { rect(2 + i * 4, 2, 2, 2, "scr.dark") }
            rect(0, r.h - 2, r.w, 2, "scr.bg3")
        case .screensaver:
            // 慢速屏保：一个小方块沿边慢慢移动（每 0.8 秒挪 1 格）
            let step = Int(t / 0.8) % 40
            let x = step < 20 ? step : 39 - step
            px(1 + min(20, x), 3 + (step % 7), "scr.dark"); px(2 + min(20, x), 3 + (step % 7), "scr.dark")
        case .gear:
            titleBar()
            // 齿轮：中心圆 + 8 个齿，慢速转（2 帧）
            let f = Int(t / 0.6) % 2
            let cx = 12, cy = 8
            for (dx, dy) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)] { px(cx + dx * 2, cy + dy * 2, "scr.dim") }
            let teeth = f == 0 ? [(0, -4), (4, 0), (0, 4), (-4, 0)] : [(3, -3), (3, 3), (-3, 3), (-3, -3)]
            for tt in teeth { px(cx + tt.0, cy + tt.1, "scr.amber") }
            rect(cx - 1, cy - 1, 3, 3, "scr.amber")
        case .outbox:
            titleBar()
            rect(3, 10, 18, 3, "scr.dark")
            let p = min(1.0, t.truncatingRemainder(dividingBy: 2.4) / 1.6)
            rect(6 + Int(p * 5), 3 + Int(p * 6), 8, 5, "scr.white")
            hl(7 + Int(p * 5), 5 + Int(p * 6), 5, "scr.dim")
        case .clock:
            rect(6, 1, 12, 13, "scr.bg3")
            // 时钟：一根时针一根分针，随时间慢慢转
            let a = t * 0.6
            for i in 0...3 { px(12 + Int((sin(a) * Double(i)).rounded()), 7 - Int((cos(a) * Double(i)).rounded()), "scr.white") }
            for i in 0...2 { px(12 + Int((sin(a / 12) * Double(i)).rounded()), 7 - Int((cos(a / 12) * Double(i)).rounded()), "scr.amber") }
        case .log:
            let scroll = Self.rhythm(t, every: Self.logScrollEvery)
            for i in 0..<6 {
                let li = i + scroll
                hl(1, 2 + i * 2, 3 + hash(seed, li) % 16, hash(seed, li + 3) % 5 == 0 ? "scr.amber" : "scr.dim")
            }
        case .off: break
        }
    }
}
