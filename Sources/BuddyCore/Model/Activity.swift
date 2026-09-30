import Foundation

/// 登记表里的 status：busy 在干活 / waiting 在等用户 / idle 这一轮结束了。
public enum Phase: String, Sendable, Equatable {
    case busy, waiting, idle
}

/// 工具归类（见 DESIGN.md「工具归类」，规则在 ToolCatalog）。
public enum ToolCategory: String, Sendable, Equatable, CaseIterable {
    case read, search, edit, write, bash, monitor, web, browser, computer
    case delegate, todo, skill, planEnter, planExit, sendFile, schedule, mcp, unknown
}

/// 一次工具调用（主线程或小助手的）。
public struct ToolCall: Sendable, Equatable {
    /// 完整工具名；hook 里被截断的名字已去掉结尾的 `…`。
    public var name: String
    public var category: ToolCategory
    /// hook 的 detail（Bash 命令、文件路径、搜索词、URL……，最多 160 字）；没有就是空串。
    /// 注意：AskUserQuestion 的 detail 不是问题本身，绝不能拿来显示。
    public var detail: String
    /// category == .mcp / .browser / .computer 时的 server 名（`mcp__<server>__tool` 里的 server）。
    public var server: String?
    public var startedAt: Date

    public init(name: String, category: ToolCategory, detail: String = "", server: String? = nil, startedAt: Date) {
        self.name = name; self.category = category; self.detail = detail; self.server = server; self.startedAt = startedAt
    }
}

/// ActivityResolver 的输出：一个 buddy 此刻「在做什么」。只由（信号, 当前时间）决定。
public enum Activity: Sendable, Equatable {
    // —— busy ——
    /// 没有打开的工具，也没有别的特殊情况。
    case thinking
    /// 显示最新的那个主线程工具；parallel 是同时打开的主线程工具个数（≥1）。
    case tool(ToolCall, parallel: Int)
    /// 上下文压缩中。
    case compacting
    /// API 重试中：第几次 / 共几次。
    case retrying(attempt: Int, max: Int)

    // —— waiting ——
    /// 等批准；tool 是最新一个打开的主线程调用（或从 Notification 文本里解析出来的工具名）。
    case waitingApproval(tool: ToolCall?)
    /// AskUserQuestion 或对话框。
    case asking
    /// ExitPlanMode 正开着且在等你。
    case planReview
    /// 其他等待，附原始文本（waitingFor）。
    case waitingOther(String)

    // —— idle ——
    /// 被用户打断（持续约 3 秒）。
    case interrupted
    /// 一轮做完（持续约 5 秒）。
    case finished
    /// 出错：重试到上限，或最后一条 assistant 是合成的 API 错误。
    case errored
    /// 空闲。
    case idle
    /// 空闲超过 idle.dozeMinutes（默认 10 分钟）。
    case dozing
    /// 空闲超过 idle.sleepMinutes（默认 45 分钟）。
    case sleeping

    public var phase: Phase {
        switch self {
        case .thinking, .tool, .compacting, .retrying: return .busy
        case .waitingApproval, .asking, .planReview, .waitingOther: return .waiting
        case .interrupted, .finished, .errored, .idle, .dozing, .sleeping: return .idle
        }
    }

    /// 是不是「在等你」（会触发提醒、转身举手）。
    public var needsUser: Bool {
        switch self {
        case .waitingApproval, .asking, .planReview, .waitingOther: return true
        default: return false
        }
    }
}
