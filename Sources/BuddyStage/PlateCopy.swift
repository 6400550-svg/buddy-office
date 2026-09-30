import Foundation
import BuddyCore

/// 桌牌 / 悬停卡片 / 通知里用的中文文案与缩写规则。永远不显示 prompt；隐私模式下隐藏全部细节。
public enum PlateCopy {
    /// Bash：去掉开头的 `cd … &&`，只保留前 1–2 个词（第二个词是选项 / 路径就不要）。
    public static func shortCommand(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("cd ") || s.hasPrefix("cd\t") {
            if let r = s.range(of: "&&") { s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces) } else { break }
        }
        // 取第一段（; | && 之前）
        for sep in ["&&", "||", ";", "|"] { if let r = s.range(of: sep) { s = String(s[s.startIndex..<r.lowerBound]) } }
        let words = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let w0 = words.first else { return "" }
        var out = (w0 as NSString).lastPathComponent
        if words.count > 1, !words[1].hasPrefix("-"), !words[1].contains("/"), !words[1].contains("\""), !words[1].contains("'"), words[1].count <= 14 {
            out += " " + words[1]
        }
        return out
    }

    public static func fileName(_ path: String) -> String {
        let n = (path as NSString).lastPathComponent
        return n.isEmpty ? path : n
    }
    public static func fileExtension(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }

    public static func domain(_ urlOrQuery: String) -> String {
        if let u = URL(string: urlOrQuery), let h = u.host { return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h }
        return clip(urlOrQuery, 12)
    }

    /// 搜索词最多 12 个字。
    public static func clip(_ s: String, _ n: Int = 12) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n)) + "…"
    }

    /// 秒数取整：NaN / 无穷 / 天文数字先夹到 0…10 亿（约 31 年）——`Int(x)` 遇到超出范围的值会 trap（数据层保证不会给出这种值，但表现层自己也夹一下，是双保险）。
    public static func wholeSeconds(_ x: Double) -> Int { x.isFinite ? max(0, min(safeInt(x), 1_000_000_000)) : 0 }

    public static func duration(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    /// "3分12秒" 这种读法（做完了 / 通知用）。
    public static func spoken(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        if s < 60 { return "\(s)秒" }
        if s < 3600 { return "\(s / 60)分\(s % 60)秒" }
        return "\(s / 3600)小时\((s % 3600) / 60)分"
    }
    public static func waitSpoken(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分钟"
    }

    /// 桌牌 / 卡片 / 菜单上显示的标题：空白标题（数据层不会给出，但显示层不能因此出一块空牌子）用占位。
    public static func displayTitle(_ t: String) -> String {
        t.unicodeScalars.allSatisfy(isInvisible) ? "（没有标题）" : t
    }

    /// 画出来什么也看不见的字符：空白 / 控制字符 / 零宽字符 / 方向控制字符 / 字节序标记 / 软连字符（只有这些的标题会画成一块空桌牌）。
    private static func isInvisible(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x00AD, 0x180E, 0x200B...0x200F, 0x2028, 0x2029, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF: return true
        default: return CharacterSet.whitespacesAndNewlines.contains(u) || CharacterSet.controlCharacters.contains(u)
        }
    }

    public static func tokens(_ n: Int) -> String {
        if n >= 999_950_000 { return String(format: "%.1fB tok", Double(n) / 1_000_000_000) }      // 十亿以上写 B（1827.2M 太长，也不好读）
        if n >= 1_000_000 { return String(format: "%.1fM tok", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.0fK tok", Double(n) / 1000) }
        return "\(n) tok"
    }

    public static func toolLabel(_ c: ToolCall) -> String {
        switch c.category {
        case .mcp, .browser, .computer: return c.server.map { clip($0, 10) } ?? "MCP"
        default: return c.name
        }
    }

    /// 动作文案（桌牌状态行的第一段）。
    public static func activity(_ s: BuddySnapshot, now: Date, privacy: Bool) -> String {
        switch s.activity {
        case .thinking: return "思考中"
        case .compacting: return "在整理记忆"
        case .retrying(let a, let m): return "网络不稳，重试中 \(a)/\(m)"
        case .tool(let call, let par):
            var t = toolText(call, snapshot: s, now: now, privacy: privacy)
            if par > 1 { t += " ×\(par)" }
            return t
        case .waitingApproval(let call):
            let w = now.timeIntervalSince(s.activitySince)
            let tl = call.map { privacy ? "" : " " + toolLabel($0) } ?? ""
            return "等你批准\(tl) · \(waitSpoken(w))"
        case .asking: return "有问题问你"
        case .planReview: return "计划好了，等你看"
        case .waitingOther: return "在等你"
        case .interrupted: return "被你打断了"
        case .finished:
            return "做完了" + (s.lastTurnDuration.map { " · " + spoken($0) } ?? "")
        case .errored: return "出错了"
        case .idle: return s.blocked ? "需要你处理" : "空闲"
        case .dozing: return "打盹 " + idleMinutes(s, now: now)
        case .sleeping: return "睡着了"
        }
    }

    static func idleMinutes(_ s: BuddySnapshot, now: Date) -> String {
        guard let t = s.idleSince else { return "" }
        let m = wholeSeconds(now.timeIntervalSince(t)) / 60
        return m >= 60 ? "\(m / 60) 小时" : "\(m) 分钟"
    }

    static func toolText(_ c: ToolCall, snapshot s: BuddySnapshot, now: Date, privacy: Bool) -> String {
        let elapsed = now.timeIntervalSince(c.startedAt)
        func d(_ x: String) -> String { privacy ? "" : x }
        func with(_ prefix: String, _ detail: String, else generic: String) -> String { detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? generic : prefix + detail }
        func quoted(_ x: String) -> String { let t = clip(x); return t.isEmpty ? "" : "\"\(t)\"" }
        switch c.category {
        // 详情为空（hook 行被截断走降级解析时会出现）就退回没有细节的说法，不要出现「在读 」「在找 ""」这种半截话（R2-015 / A-019）
        case .read: return privacy ? "在读文件" : with("在读 ", fileName(c.detail), else: "在读文件")
        case .search:
            if c.name == "Grep" { return privacy ? "在找东西" : with("在找 ", quoted(c.detail), else: "在找东西") }
            return "在翻文件"
        case .edit: return privacy ? "在改代码" : with("在改 ", fileName(c.detail), else: "在改代码")
        case .write: return privacy ? "在写文件" : with("在写 ", fileName(c.detail), else: "在写文件")
        case .bash:
            let cmd = shortCommand(c.detail)
            if elapsed > 8 { return privacy || cmd.isEmpty ? "运行中 · \(duration(elapsed))" : "运行中 \(cmd) · \(duration(elapsed))" }
            return privacy ? "在运行命令" : with("运行 ", cmd, else: "在运行命令")
        case .monitor: return "在盯日志"
        case .web:
            if c.name == "WebSearch" { return privacy ? "在搜索" : with("在搜 ", quoted(c.detail), else: "在搜索") }
            return privacy ? "在看网页" : with("在看 ", domain(c.detail), else: "在看网页")
        case .browser: return "在操作浏览器"
        case .computer: return "在操作电脑"
        case .delegate:
            let n = s.helpers.filter { !$0.done }.count
            if s.helpers.contains(where: { $0.foreground && !$0.done }) { return "派了 \(max(1, n)) 个帮手" }
            return n > 0 ? "帮手在后台干活" : "派了帮手"
        case .todo: return "在列计划"
        case .skill: return c.name == "ToolSearch" ? "在翻工具箱" : "在看技能手册"
        case .planEnter: return "在做计划"
        case .planExit: return "计划好了，等你看"
        case .sendFile: return "发给你一个文件"
        case .schedule: return "定了闹钟"
        case .mcp: return privacy ? "在用外部工具" : "在用 " + (c.server.map { clip($0, 10) } ?? "MCP")       // server 名常常就是内部系统 / 客户 / 项目名（R1b-03）
        case .unknown: return privacy ? "在用工具" : "在用 " + clip(c.name, 14)
        }
    }

    /// 桌牌状态行的候选（由详细到简略）：放不下时用短的。action 是已经过最短停留处理的动作文案。
    public static func statusCandidates(action a: String, _ s: BuddySnapshot, now: Date) -> [String] {
        var out: [String] = []
        if s.phase != .idle, let t0 = s.turnStartedAt {
            let t = "本轮 " + duration(now.timeIntervalSince(t0))
            if s.tokens.total > 0 { out.append("\(a) · \(t) · \(tokens(s.tokens.total))") }
            out.append("\(a) · \(t)")
        }
        out.append(a)
        return out
    }

    /// 桌牌状态行：动作 · 本轮用时 · token 数。
    public static func statusLine(_ s: BuddySnapshot, now: Date, privacy: Bool) -> String {
        var parts = [activity(s, now: now, privacy: privacy)]
        if s.phase != .idle, let t0 = s.turnStartedAt { parts.append("本轮 " + duration(now.timeIntervalSince(t0))) }
        if s.tokens.total > 0 && s.phase != .idle { parts.append(tokens(s.tokens.total)) }
        return parts.joined(separator: " · ")
    }
}
