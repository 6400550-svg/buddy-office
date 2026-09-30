import Foundation

/// ccmon 的一条 hook 事件（`~/.claude/.monitor/<sessionId>.events.jsonl` 的一行）。
///
/// 隐私：UserPromptSubmit 的 `extra` 是用户输入的前 200 字，**在解析时就丢掉**（置空），保证它不会流到下游任何地方。
public struct HookEvent: Sendable, Equatable {
    public var ts: Date
    public var ev: String
    /// 工具名。hook 会把名字截成 40 字符加 `…`，这里已经去掉 `…`（用 `toolTruncated` 记住）。
    public var tool: String
    public var toolTruncated: Bool
    /// hook 的 detail（最多 160 字）。AskUserQuestion 的 detail 不是问题本身（是第一个选项的 description），解析时置空。
    public var detail: String
    public var extra: String
    /// true = JSON 没解析成功，只用正则抠出了 ts / ev / tool。
    public var degraded: Bool

    public init(ts: Date, ev: String, tool: String = "", toolTruncated: Bool = false,
                detail: String = "", extra: String = "", degraded: Bool = false) {
        self.ts = ts; self.ev = ev; self.tool = tool; self.toolTruncated = toolTruncated
        self.detail = detail; self.extra = extra; self.degraded = degraded
    }

    public var isPre: Bool { ev == HookEvent.pre }
    public var isPost: Bool { ev == HookEvent.post }

    public static let pre = "PreToolUse"
    public static let post = "PostToolUse"
    public static let stop = "Stop"
    public static let prompt = "UserPromptSubmit"
    public static let sessionStart = "SessionStart"
    public static let sessionEnd = "SessionEnd"
    public static let notification = "Notification"
    public static let subagentStop = "SubagentStop"
    public static let preCompact = "PreCompact"
    public static let postCompact = "PostCompact"
}

/// 一行字节 → 干净的字符串 / hook 事件。
///
/// hook.sh 用 zsh 按字符截断字段：超过一半的 Claude 事件文件里有被截断的中文 UTF-8 字节，
/// 还可能把 `\uXXXX` 转义从中间截断。所以：
/// 1. 每一行先用 `String(decoding:as: UTF8.self)` 清洗（非法字节 → U+FFFD）；
/// 2. 再做 JSON 解析；
/// 3. 解析失败就用扫描的办法只抠出 `ts`、`ev`、`tool` 三个字段；
/// 4. 实在解析不了的行直接跳过，不能让整个文件都失败。
public enum LineSanitizer {
    /// 非法 UTF-8 → U+FFFD。
    public static func string(from bytes: UnsafeBufferPointer<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    public static func parseHookLine(_ bytes: UnsafeBufferPointer<UInt8>) -> HookEvent? {
        let text = string(from: bytes)
        return parseHookLine(text)
    }

    public static func parseHookLine(_ text: String) -> HookEvent? {
        if let ev = parseStrict(text) { return finalize(ev) }
        if let ev = parseDegraded(text) { return finalize(ev) }
        return nil
    }

    // MARK: - 严格解析

    private static func parseStrict(_ text: String) -> HookEvent? {
        // ts 必须是合理范围里的毫秒数（布尔、天文数字、0、负数都当坏行）：见 TimeUtil.saneMinMs
        guard let data = text.data(using: .utf8),
              let obj = SafeJSON.object(data),
              let tsNum = obj["ts"] as? NSNumber, !TimeUtil.isBool(tsNum),
              let ts = TimeUtil.date(saneMs: tsNum.doubleValue),
              let ev = obj["ev"] as? String, !ev.isEmpty, ev.utf8.count <= 64                    // 事件名最长 "UserPromptSubmit"
        else { return nil }
        // 字符串字段有长度上限（hook 自己就把 detail 截到 160 字；坏行里可以有几 MB 长的字符串，不能全留在内存里）
        let (tool, truncated) = splitTool(SafeJSON.string(obj["tool"], max: 200) ?? "")
        return HookEvent(ts: ts, ev: ev, tool: tool, toolTruncated: truncated,
                         detail: SafeJSON.string(obj["detail"], max: SafeJSON.maxDetailLength) ?? "",
                         extra: SafeJSON.string(obj["extra"], max: SafeJSON.maxDetailLength) ?? "")
    }

    // MARK: - 降级解析（正则式扫描，只要 ts / ev / tool）

    private static func parseDegraded(_ text: String) -> HookEvent? {
        guard let tsStr = scanNumber(after: "\"ts\":", in: text), let tsVal = Double(tsStr),
              let ts = TimeUtil.date(saneMs: tsVal),
              let ev = scanString(after: "\"ev\":\"", in: text, limit: 64, rejectIfLonger: true), !ev.isEmpty else { return nil }
        let rawTool = scanString(after: "\"tool\":\"", in: text, limit: 200) ?? ""
        let (tool, truncated) = splitTool(rawTool)
        return HookEvent(ts: ts, ev: ev, tool: tool, toolTruncated: truncated, degraded: true)
    }

    /// 抠出 marker 后面的一个整数（可以带小数部分）。数字后面必须紧跟 `,` `}` `]` 或空白：
    /// `1759100000123e5`、`123abc`、`12.3.4` 这类不是合法数字的写法当作抠不出来（否则会把 1e5 之类当成一个别的数）。
    private static func scanNumber(after marker: String, in text: String) -> String? {
        guard let r = text.range(of: marker) else { return nil }
        var digits = ""
        var fraction = false
        var terminated = false
        for ch in text[r.upperBound...] {
            if ch == " " && digits.isEmpty { continue }
            if digits.utf8.count > 20 { return nil }                  // 真正的毫秒时间戳是 13 位；几百位的数字是坏数据
            if ch.isASCII, ch.isNumber { if !fraction { digits.append(ch) }; continue }
            if ch == ".", !digits.isEmpty, !fraction { fraction = true; continue }
            terminated = ch == "," || ch == "}" || ch == "]" || ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
            break
        }
        return (terminated && !digits.isEmpty) ? digits : nil
    }

    /// 抠出 marker 后面的一个字符串（到收尾引号，或者行尾；最多取 `limit` 个字符，多的不再往后扫）。
    /// `rejectIfLonger`：超过 limit 还没有收尾引号就返回 nil（事件名这类不能截断着用）；否则截到 limit 为止。
    private static func scanString(after marker: String, in text: String, limit: Int, rejectIfLonger: Bool = false) -> String? {
        guard let r = text.range(of: marker) else { return nil }
        var out = ""
        var count = 0
        var escaped = false
        for ch in text[r.upperBound...] {
            if count >= limit {
                if ch == "\"" && !escaped { return out }                  // 刚好 limit 个字符、后面就是收尾引号
                return rejectIfLonger ? nil : out
            }
            if escaped { out.append(ch); count += 1; escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { return out }
            out.append(ch)
            count += 1
        }
        return out   // 没有收尾引号（整行被截断）：取到行尾
    }

    // MARK: - 收尾

    /// 去掉 hook 截断留下的 `…`；返回是否被截断过。
    static func splitTool(_ raw: String) -> (String, Bool) {
        var s = raw
        var truncated = false
        while s.hasSuffix("…") { s.removeLast(); truncated = true }
        // 名字被按字节截断时，结尾可能是 U+FFFD
        while s.hasSuffix("\u{FFFD}") { s.removeLast(); truncated = true }
        return (s, truncated)
    }

    private static func finalize(_ ev: HookEvent) -> HookEvent {
        var e = ev
        // 隐私：用户输入绝不留下
        if e.ev == HookEvent.prompt { e.extra = "" }
        // AskUserQuestion 的 detail 是第一个选项的 description，不是问题本身，绝不能拿来显示
        if e.tool == "AskUserQuestion" { e.detail = "" }
        return e
    }
}
