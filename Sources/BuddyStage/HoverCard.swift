import Foundation
import BuddyCore
import PixelKit
import BuddyArt

/// 悬停卡片：像素边框的牌子 + 清晰的中文文字。办公室里直接画进场景；小鱼缸 / 桌面宠物条用单独的 HoverPanel 显示同一张卡。
public enum HoverCard {
    public struct Card {
        public var canvas: Canvas
        public var texts: [TextItem]            // 坐标相对卡片左上角（美术像素）
        public var size: IntPoint
    }

    static func originName(_ s: BuddySnapshot) -> String {
        var t: String
        switch s.origin { case .desktop: t = "Claude 桌面 App"; case .vscode: t = "VS Code"; case .terminal: t = "终端" }
        switch s.modelFamily { case .deepseek: t += " · DeepSeek"; case .glm: t += " · GLM"; case .other: t += " · 其他模型"; case .claude: break }
        return t
    }

    static func ago(_ d: TimeInterval) -> String {
        let s = PlateCopy.wholeSeconds(d)
        if s < 60 { return "\(s) 秒" }
        if s < 3600 { return "\(s / 60) 分钟" }
        return "\(s / 3600) 小时 \((s % 3600) / 60) 分钟"
    }

    /// - Parameters:
    ///   - maxWidth: 卡片文字的最大宽度（点）；窗口很窄时要传小一点，超出的行用省略号。
    ///   - maxHeight: 卡片整体的最大高度（点）；放不下时按优先级去掉次要的行（状态说明 > 上下文 > token 明细 > 时间 > 模型 > 路径）。
    public static func make(_ s: BuddySnapshot, now: Date, zoom: Int, privacy: Bool, maxWidth: CGFloat = 250, maxHeight: CGFloat? = nil) -> Card {
        let ink = RGBA8(hex: 0x2E2230), dim = RGBA8(hex: 0x6E5A66), accent = RGBA8(hex: 0x3C6FB0)
        let title = TextStyle(size: 12, color: ink, weight: .semibold)
        let body = TextStyle(size: 10.5, color: ink)
        let small = TextStyle(size: 10, color: dim)
        // priority：数字越大越先被去掉
        var lines: [(String, TextStyle)] = []
        var priority: [Int] = []
        func add(_ text: String, _ st: TextStyle, drop: Int = 0) { lines.append((text, st)); priority.append(drop) }
        let shownTitle = privacy ? "会话" : PlateCopy.displayTitle(s.title)
        add(shownTitle, title)
        if !privacy, let cwd = s.cwd, !cwd.isEmpty { add((cwd as NSString).abbreviatingWithTildeInPath, small, drop: 1) }
        add(originName(s), TextStyle(size: 10, color: accent), drop: 2)
        var model = [String]()
        if let m = s.modelName, !m.isEmpty { model.append(m) }
        if let e = s.effort, !e.isEmpty { model.append(e) }
        if let p = s.permissionMode, !p.isEmpty { model.append(p) }
        if !model.isEmpty { add(model.joined(separator: " · "), small, drop: 3) }
        add(PlateCopy.activity(s, now: now, privacy: privacy), body)
        var times = [String]()
        if let t0 = s.turnStartedAt, s.phase != .idle { times.append("本轮 " + PlateCopy.duration(now.timeIntervalSince(t0))) }
        if let st = s.sessionStartedAt { times.append("会话已开 " + ago(now.timeIntervalSince(st))) }
        if !times.isEmpty { add(times.joined(separator: " · "), small, drop: 4) }
        let t = s.tokens
        if t.total > 0 {
            add("输入 \(PlateCopy.tokens(t.input).replacingOccurrences(of: " tok", with: "")) · 输出 \(PlateCopy.tokens(t.output).replacingOccurrences(of: " tok", with: ""))", small, drop: 5)
            add("缓存写 \(PlateCopy.tokens(t.cacheWrite).replacingOccurrences(of: " tok", with: "")) · 缓存读 \(PlateCopy.tokens(t.cacheRead).replacingOccurrences(of: " tok", with: ""))", small, drop: 5)
        }
        if let c = s.contextTokens, c > 0 { add("当前上下文 \(PlateCopy.tokens(c))", small, drop: 6) }
        if let d = s.statusDetail, !d.isEmpty, !privacy { add(d, small, drop: 7) }
        let tr = TextRenderer.shared
        let maxW: CGFloat = max(40, maxWidth)
        // 高度放不下：按 drop 从大到小去掉次要的行，直到放得下（标题和当前动作永远留着）
        if let mh = maxHeight {
            func totalH() -> CGFloat { lines.reduce(CGFloat(12)) { $0 + tr.measure($1.0, style: $1.1, maxWidth: maxW).height - 1 } }
            while totalH() > mh, let worst = priority.enumerated().filter({ $0.element > 0 }).max(by: { $0.element < $1.element }) {
                lines.remove(at: worst.offset); priority.remove(at: worst.offset)
            }
        }
        var w: CGFloat = 0, h: CGFloat = 10
        var metrics: [(CGFloat, CGFloat)] = []
        for (txt, st) in lines {
            let m = tr.measure(txt, style: st, maxWidth: maxW)
            metrics.append((m.width, m.height)); w = max(w, m.width); h += m.height - 1
        }
        let padPt: CGFloat = 9
        let wPt = min(maxW, w) + padPt * 2, hPt = h + 2
        let z = CGFloat(zoom)
        let aw = Int((wPt / z).rounded(.up)) + 1, ah = Int((hPt / z).rounded(.up)) + 1
        let c = Canvas(width: aw, height: ah)
        let st = Lighting.resolved(map: nil, state: LightState(a: .day))
        c.plate(IntRect(0, 0, aw, ah), border: Pal.dx("bubble.line"), fill: Pal.dx("bubble.fill"), light: Pal.dx("white.hi"), shade: Pal.dx("bubble.sh"), style: st)
        var items: [TextItem] = []
        var y = (padPt - 2) / z
        for (i, (txt, style)) in lines.enumerated() {
            items.append(TextItem(txt, style: style, x: Double(padPt / z), y: Double(y), align: .left, maxWidth: maxW,
                                  container: IntRect(0, 0, aw, ah), tag: i == 0 ? "card.title" : "card.line"))
            y += (metrics[i].1 - 1) / z
        }
        return Card(canvas: c, texts: items, size: IntPoint(aw, ah))
    }
}
