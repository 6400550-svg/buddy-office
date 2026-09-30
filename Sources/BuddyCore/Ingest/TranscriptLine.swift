import Foundation

/// 一条会话记录（transcript）行里我们关心的事实。**绝不保留任何对话内容**（用户输入、助手文字都不留）。
struct TranscriptLine {
    enum Kind { case assistant, user, system, customTitle, aiTitle, permissionMode, other }

    struct ToolUse: Equatable {
        var id: String
        var name: String
        /// 与 hook 的 detail 同一套规则取出的第一个输入字段（最多 160 字）。
        var key: String
    }
    struct ToolResult: Equatable {
        var id: String
        var isError: Bool
    }
    struct Usage: Equatable {
        var input = 0
        var output = 0
        var cacheWriteTotal = 0     // cache_creation_input_tokens
        var cacheWrite5m = 0
        var cacheWrite1h = 0
        var cacheRead = 0
    }

    var kind: Kind = .other
    var timestamp: Date?
    var isSidechain = false
    var isMeta = false

    // assistant
    var messageId: String?
    var model: String?
    var stopReason: String?
    var isAbortedMidStream = false
    var isApiErrorMessage = false
    var toolUses: [ToolUse] = []
    var usage: Usage?
    var effort: String?

    // user
    var toolResults: [ToolResult] = []
    var isInterrupt = false
    /// 人的一次输入（开始新一轮）：content 是字符串，或数组里有 text / image 块且没有 tool_result。
    var isPrompt = false

    // system
    var subtype: String?
    var retryAttempt: Int?
    var maxRetries: Int?
    var retryInMs: Double?
    var durationMs: Double?

    // 标题 / 模式
    var text: String?
}

enum TranscriptLineParser {
    static let interruptPrefix = "[Request interrupted by user"

    /// 解析一行。JSON 不合法返回 nil。
    static func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> TranscriptLine? {
        guard let obj = SafeJSON.object(bytes) else { return nil }
        return parse(object: obj)
    }

    static func parse(object obj: [String: Any]) -> TranscriptLine? {
        guard let type = obj["type"] as? String else { return nil }
        var line = TranscriptLine()
        if let ts = obj["timestamp"] as? String { line.timestamp = TimeUtil.parseISO(ts) }
        line.isSidechain = (obj["isSidechain"] as? Bool) ?? false
        line.isMeta = (obj["isMeta"] as? Bool) ?? false

        switch type {
        case "assistant":
            line.kind = .assistant
            line.isAbortedMidStream = (obj["isAbortedMidStream"] as? Bool) ?? false
            line.isApiErrorMessage = (obj["isApiErrorMessage"] as? Bool) ?? false
            line.effort = SafeJSON.string(obj["perTurnEffort"], max: 64) ?? SafeJSON.string(obj["effort"], max: 64)
            guard let msg = obj["message"] as? [String: Any] else { return line }
            line.messageId = SafeJSON.id(msg["id"])
            line.model = SafeJSON.string(msg["model"], max: SafeJSON.maxIdLength)
            line.stopReason = SafeJSON.string(msg["stop_reason"], max: 64)
            if let content = msg["content"] as? [Any] {
                for case let block as [String: Any] in content {
                    guard (block["type"] as? String) == "tool_use",
                          let id = SafeJSON.id(block["id"]),
                          let name = SafeJSON.string(block["name"], max: SafeJSON.maxIdLength) else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]
                    line.toolUses.append(.init(id: id, name: name, key: ToolDetail.key(name: name, input: input)))
                }
            }
            if let u = msg["usage"] as? [String: Any], !u.isEmpty {
                var usage = TranscriptLine.Usage()
                usage.input = intValue(u["input_tokens"])
                usage.output = intValue(u["output_tokens"])
                usage.cacheWriteTotal = intValue(u["cache_creation_input_tokens"])
                usage.cacheRead = intValue(u["cache_read_input_tokens"])
                if let cc = u["cache_creation"] as? [String: Any] {
                    usage.cacheWrite1h = intValue(cc["ephemeral_1h_input_tokens"])
                    usage.cacheWrite5m = intValue(cc["ephemeral_5m_input_tokens"])
                }
                // 用量表的规则：没有细分（或细分加起来对不上总数）时全部当 5m
                if usage.cacheWrite1h + usage.cacheWrite5m != usage.cacheWriteTotal {
                    usage.cacheWrite5m = usage.cacheWriteTotal
                    usage.cacheWrite1h = 0
                }
                line.usage = usage
            }

        case "user":
            line.kind = .user
            guard let msg = obj["message"] as? [String: Any] else { return line }
            let content = msg["content"]
            if let s = content as? String {
                if s.hasPrefix(interruptPrefix) { line.isInterrupt = true } else { line.isPrompt = !line.isMeta }
            } else if let arr = content as? [Any] {
                var hasText = false, hasResult = false
                for case let block as [String: Any] in arr {
                    switch block["type"] as? String {
                    case "tool_result":
                        hasResult = true
                        if let id = SafeJSON.id(block["tool_use_id"]) {
                            line.toolResults.append(.init(id: id, isError: (block["is_error"] as? Bool) ?? false))
                        }
                    case "text":
                        hasText = true
                        if let t = block["text"] as? String, t.hasPrefix(interruptPrefix) { line.isInterrupt = true }
                    case "image":
                        hasText = true
                    default: break
                    }
                }
                line.isPrompt = hasText && !hasResult && !line.isInterrupt && !line.isMeta
            }

        case "system":
            line.kind = .system
            line.subtype = SafeJSON.string(obj["subtype"], max: 64)
            switch line.subtype {
            case "api_error":
                // 这些数字最后会显示在界面上（"重试中 2/10"、"做完了 · 3 分 12 秒"），表现层里有 Int(秒数) 这类换算，
                // 天文数字 / 负数会让它们 trap：所以在这里夹到合理范围，范围外的当作没有
                line.retryAttempt = TranscriptLineParser.boundedInt(obj["retryAttempt"], 0...1000)
                line.maxRetries = TranscriptLineParser.boundedInt(obj["maxRetries"], 0...1000)
                line.retryInMs = TranscriptLineParser.boundedDouble(obj["retryInMs"], 0...3_600_000)          // 最多 1 小时
            case "turn_duration":
                line.durationMs = TranscriptLineParser.boundedDouble(obj["durationMs"], 0...(1e9 * 1000))       // 最多约 11.5 天
            default: break
            }

        case "custom-title":
            line.kind = .customTitle
            line.text = SafeJSON.string(obj["customTitle"])
        case "ai-title":
            line.kind = .aiTitle
            line.text = SafeJSON.string(obj["aiTitle"])
        case "permission-mode":
            line.kind = .permissionMode
            line.text = SafeJSON.string(obj["permissionMode"], max: 64)
        default:
            line.kind = .other
        }
        return line
    }

    /// JSON 数字 → 范围内的 Int（不是数字 / 布尔 / 小数部分被截掉 / 范围外 → nil）。
    static func boundedInt(_ v: Any?, _ range: ClosedRange<Int>) -> Int? {
        guard let n = v as? NSNumber, !TimeUtil.isBool(n) else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d >= Double(range.lowerBound), d <= Double(range.upperBound) else { return nil }
        return Int(d)
    }

    /// JSON 数字 → 范围内的 Double（不是数字 / 布尔 / 范围外 / NaN / 无穷 → nil）。
    static func boundedDouble(_ v: Any?, _ range: ClosedRange<Double>) -> Double? {
        guard let n = v as? NSNumber, !TimeUtil.isBool(n) else { return nil }
        let d = n.doubleValue
        guard d.isFinite, range.contains(d) else { return nil }
        return d
    }

    /// 单个 token 计数的上限（2^40 ≈ 1.1 万亿，比任何真实的单条消息都大几个数量级）。
    /// 夹在这里是为了后面 input + cacheWrite + cacheRead 这类相加、以及账本累计都不可能溢出（Int.max 相加会直接 trap）。
    static let maxTokenValue = 1 << 40

    /// JSON 里的计数 → 非负 Int，最大夹到 `maxTokenValue`（负数、NaN、非数字都是 0）。
    static func intValue(_ v: Any?) -> Int {
        guard let n = v as? NSNumber else { return 0 }
        let d = n.doubleValue
        guard d > 0 else { return 0 }                     // 负数 / 0 / NaN
        return d >= Double(maxTokenValue) ? maxTokenValue : Int(d)
    }
}

/// 从工具输入里取"第一个输入字段"，规则和 ccmon 的 hook.sh 的 detail 一致：
/// Bash → command；Read/Edit/Write → file_path；Grep/Glob → pattern；WebFetch/WebSearch → url 或 query；
/// Task/Agent → description；Skill → skill；其余（或上面的取不到）→ 第一个 description。
/// 最多 160 字。
public enum ToolDetail {
    public static let maxLength = 160

    public static func key(name rawName: String, input: [String: Any]) -> String {
        let name = ToolCatalog.cleanName(rawName)
        // AskUserQuestion 的 detail 不是问题本身（hook 里是第一个选项的 description）：无论 input 里有什么都不留
        if name == "AskUserQuestion" { return "" }
        func s(_ k: String) -> String? {
            guard let v = input[k] as? String, !v.isEmpty else { return nil }
            return v
        }
        var out: String?
        switch name {
        case "Bash": out = s("command")
        case "Read", "Edit", "Write": out = s("file_path")
        case "Grep", "Glob": out = s("pattern")
        case "WebFetch", "WebSearch": out = s("url") ?? s("query")
        case "Task", "Agent": out = s("description")
        case "Skill": out = s("skill")
        default: break
        }
        if out == nil { out = s("description") }
        guard let v = out else { return "" }
        return String(v.prefix(maxLength))
    }

    /// hook 的 detail 与会话记录里取出的 key 是不是指同一次调用（前缀比较：detail 可能被截断 / 带 `…`）。
    public static func matches(hookDetail: String, transcriptKey: String) -> Bool {
        func norm(_ s: String) -> String {
            var t = s
            while t.hasSuffix("…") || t.hasSuffix("\u{FFFD}") { t.removeLast() }
            return String(t.prefix(maxLength))
        }
        let a = norm(hookDetail), b = norm(transcriptKey)
        if a.isEmpty && b.isEmpty { return true }
        if a.isEmpty || b.isEmpty { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }
}
