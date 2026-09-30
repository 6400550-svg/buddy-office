import Foundation

/// 一轮是怎么结束的。
public enum TurnEndKind: Sendable, Equatable {
    /// 没有一轮刚结束（比如刚进场的新会话：登记表一出现就是 idle，不能显示"做完了"）。
    case none
    /// 正常做完。
    case finished
    /// 被用户打断（会话记录里有打断标记，或者 hook 正常工作但 busy → idle 时没有 Stop 事件）。
    case interrupted
    /// 出错（重试到上限，或最后一条 assistant 是合成的 API 错误）。
    case errored
}

/// ActivityResolver 的输入：一个 buddy 此刻所有已知信号（不含任何对话内容）。
/// `ActivityResolver.resolve(signals, now)` 只由它们和当前时间决定输出，不依赖其他状态。
public struct SessionSignals: Sendable, Equatable {
    // —— 登记表 ——
    /// 登记表的 status；nil = 没有 / 不认识。
    public var registryStatus: Phase?
    public var statusUpdatedAt: Date?
    /// 只在 waiting 时存在。
    public var waitingFor: String?

    // —— ccmon hook ——
    /// 这个会话有没有在收到 hook 事件（ts ≥ startedAt − 5s）。
    public var hookActive = false
    /// 最近一条 UserPromptSubmit / Stop 的时间。
    public var lastPromptAt: Date?
    public var lastStopAt: Date?
    public var preCompactAt: Date?
    public var postCompactAt: Date?
    /// 最近一条 Notification 的文本（如 "Claude needs your permission to use Bash"）。
    public var notificationText: String?
    public var notificationAt: Date?
    /// 主线程还开着的工具，按开始顺序（最新的在最后）。hook 不工作时来自会话记录里没结果的 tool_use。
    public var openTools: [ToolCall] = []

    // —— 会话记录 ——
    public var apiError: TranscriptFacts.ApiError?
    /// 最近一条 assistant 或 user 行的时间（判断 api_error 之后有没有新内容）。
    public var lastAssistantOrUserAt: Date?
    public var compactBoundaryAt: Date?

    // —— 轮次（引擎观察出来的）——
    /// 变成 idle 的时间；不在 idle 时无意义。
    public var idleSince: Date?
    /// 这一轮是怎么结束的（只在 idle 时有意义）。
    public var turnEnd: TurnEndKind = .none

    // —— 配置 ——
    public var dozeAfter: TimeInterval = 10 * 60
    public var sleepAfter: TimeInterval = 45 * 60

    public init() {}
}

/// ActivityResolver 的输出：动作 + 阶段 + 这个结果最早什么时候可能因为时间流逝而变化。
public struct Resolution: Sendable, Equatable {
    public var activity: Activity
    /// 修正之后的阶段（登记表 status + 两个临时修正）。
    public var phase: Phase
    /// 如果没有新信号，结果最早会在什么时候因为时间到了而变（打断 3 秒、做完 5 秒、打盹、睡着……）。
    public var nextChange: Date?
}
