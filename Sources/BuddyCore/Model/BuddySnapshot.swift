import Foundation

/// 会话从哪里来的。
public enum SessionOrigin: String, Sendable, Equatable, Codable {
    case desktop   // entrypoint: claude-desktop / claude-desktop-3p / local-agent
    case vscode    // entrypoint: claude-vscode
    case terminal  // 其余
}

/// 模型系列（悬停卡片里的来源标识）。由会话记录里 assistant 的 message.model 前缀判断。
public enum ModelFamily: String, Sendable, Equatable, Codable {
    case claude, deepseek, glm, other
}

/// 在不在场。
public enum Presence: Sendable, Equatable {
    /// 会话进程活着。
    case present
    /// 已确认离场（登记文件消失 / PID 已死或被复用，且防抖 3 秒之后）。
    /// dormant == true：桌面会话、元数据还在、没归档 → 该显示「下班工位」；
    /// dormant == false：8 秒后收回工位（到时这条快照会从列表里消失）。
    case away(since: Date, dormant: Bool)
}

public struct TokenBreakdown: Sendable, Equatable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheWrite: Int = 0
    public var cacheRead: Int = 0
    /// 四项之和（饱和加法：账本被写坏、数字是天文数字时也不会溢出 trap）。
    public var total: Int {
        @inline(__always) func add(_ a: Int, _ b: Int) -> Int {
            let (r, o) = a.addingReportingOverflow(b)
            return o ? (b < 0 ? Int.min : Int.max) : r
        }
        return add(add(add(input, output), cacheWrite), cacheRead)
    }
    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

/// 小助手（子代理）。
public struct HelperSnapshot: Sendable, Equatable, Identifiable {
    public var id: String                 // agent-<hex>
    public var description: String        // meta.json 里的 description
    public var agentType: String?
    public var foreground: Bool           // requestShape == foreground
    public var active: Bool               // 最近 90 秒有写入且没完成
    public var done: Bool                 // 最后一条 assistant 是 end_turn 且没有未完成的工具
    public var currentTool: ToolCall?     // 它最后一个还没有结果的 tool_use
    public init(id: String, description: String = "", agentType: String? = nil, foreground: Bool = false,
                active: Bool = false, done: Bool = false, currentTool: ToolCall? = nil) {
        self.id = id; self.description = description; self.agentType = agentType; self.foreground = foreground
        self.active = active; self.done = done; self.currentTool = currentTool
    }
}

/// 表现层拿到的一切：一个 buddy（= 一个 Claude Code 会话）此刻的完整状态。
/// 时间相关的量都给绝对时间戳，表现层自己用「现在」去减，这样心跳之间也能平滑推进。
public struct BuddySnapshot: Sendable, Equatable, Identifiable {
    // —— 身份 ——
    /// 桌面会话 "d:" + hostSessionId；其他 "t:" + 第一次见到的 sessionId。
    public var key: String
    public var id: String { key }
    /// 工位编号（0 起，稳定，持久化）。
    public var seat: Int
    /// 外观种子盐（持久化；「换个造型」会换新的）。
    public var salt: UInt64

    // —— 标签 ——
    public var title: String
    public var cwd: String?
    public var origin: SessionOrigin
    public var modelFamily: ModelFamily
    public var modelName: String?
    public var effort: String?
    public var permissionMode: String?
    public var cliVersion: String?
    public var sessionId: String
    public var hostSessionId: String?
    public var pid: Int32?
    public var sessionStartedAt: Date?

    // —— 状态 ——
    public var presence: Presence
    /// App 启动之后才新出现的（走进来坐下）；false = App 启动时就在（直接坐好、屏幕依次开机）。
    public var appearedAfterLaunch: Bool
    public var phase: Phase
    public var activity: Activity
    /// 当前 activity 从什么时候开始。
    public var activitySince: Date
    /// 本轮开始时间（busy / waiting 时有值）。
    public var turnStartedAt: Date?
    /// 最近一轮做完花了多久，以及什么时候结束的。
    public var lastTurnDuration: TimeInterval?
    public var lastTurnEndedAt: Date?
    /// 变成 idle 的时间（用于打盹 / 睡着的计时）。
    public var idleSince: Date?
    /// 未读：一轮做完后亮起；跳转到该会话 / 桌面 lastFocusedAt 更晚 / 下一轮开始时清掉。
    public var unread: Bool
    /// 做完了但需要你处理（桌面 postTurnSummary blocked）；保持到下一轮开始。
    public var blocked: Bool
    /// 桌面 postTurnSummary.status_detail（英文，只在悬停卡片里显示）。
    public var statusDetail: String?
    /// busy 但 10 分钟内 hook 和会话记录都没有增长。只是换种画法，绝不代表会话死了。
    public var quiet: Bool
    public var helpers: [HelperSnapshot]

    // —— 用量 ——
    public var tokens: TokenBreakdown
    /// 当前上下文大小（最后一次 assistant usage 的 input + cacheWrite + cacheRead）。
    public var contextTokens: Int?

    // —— 诊断 ——
    /// 这个会话有没有在收到 ccmon 的 hook 事件（ts ≥ startedAt − 5s）。
    public var hookActive: Bool

    public init(key: String, seat: Int, salt: UInt64, title: String, sessionId: String,
                origin: SessionOrigin = .desktop, activity: Activity = .idle, now: Date = Date()) {
        self.key = key; self.seat = seat; self.salt = salt; self.title = title; self.sessionId = sessionId
        self.origin = origin
        self.cwd = nil; self.modelFamily = .claude; self.modelName = nil; self.effort = nil
        self.permissionMode = nil; self.cliVersion = nil; self.hostSessionId = nil; self.pid = nil
        self.sessionStartedAt = nil
        self.presence = .present; self.appearedAfterLaunch = false
        self.phase = activity.phase; self.activity = activity; self.activitySince = now
        self.turnStartedAt = nil; self.lastTurnDuration = nil; self.lastTurnEndedAt = nil; self.idleSince = nil
        self.unread = false; self.blocked = false; self.statusDetail = nil; self.quiet = false
        self.helpers = []; self.tokens = TokenBreakdown(); self.contextTokens = nil; self.hookActive = false
    }

    /// 项目文件夹名（cwd 的最后一段）。
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "" }
        return (cwd as NSString).lastPathComponent
    }
}

/// 一次性的事件（提醒、白板计数、进出场统计用）；和快照流并行送出。
public enum AttentionKind: Sendable, Equatable {
    case approval(ToolCall?)
    case question
    case planReview
    case other(String)
}

public struct BuddyEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case arrived(freshAfterLaunch: Bool)
        case departed(dormant: Bool)
        case turnStarted
        /// 一轮正常做完 / 被打断 / 出错。用时秒数（可能没有）。
        case turnFinished(duration: TimeInterval?, interrupted: Bool, errored: Bool)
        /// 开始等你（已持续满去抖时间，由 SessionStore 自己按 0 延迟给出；「满 1.5 秒才提醒」由 App 层判断）。
        case needsUser(AttentionKind)
        /// 不再等你了。
        case needsUserCleared
        /// 做完了但 blocked。
        case blocked
    }
    public var key: String
    public var at: Date
    public var kind: Kind
    public init(key: String, at: Date, kind: Kind) { self.key = key; self.at = at; self.kind = kind }
}

/// 「数据源诊断」页要的信息。
public struct DiagnosticsInfo: Sendable, Equatable {
    public struct SessionDiag: Sendable, Equatable {
        public var key: String
        public var title: String
        public var pid: Int32?
        public var cliVersion: String?
        public var hookActive: Bool
        public var lastHookEventAt: Date?
        public var origin: SessionOrigin
    }
    public var liveSessionCount: Int = 0
    public var hookDetectedInSettings: Bool = false
    public var lastHookEventAt: Date?
    public var sessions: [SessionDiag] = []
    /// 每个数据源的降级状态说明，例如 "hook: 正常"、"会话记录: 正常"、"FSEvents: 不可用，改用轮询"。
    public var sourceStatus: [String] = []
    public init() {}
}

/// 数据提供者：真实的 SessionStore、演示用的 MockSource、回放用的都实现它。App 只认这个协议。
public protocol SnapshotProvider: AnyObject {
    /// 有新快照列表（按工位号排序）。在主线程回调，最多每秒 20 次，另有每秒 1 次心跳。
    var onUpdate: (([BuddySnapshot]) -> Void)? { get set }
    var onEvent: ((BuddyEvent) -> Void)? { get set }
    func start()
    func stop()
    /// 用户跳转 / 查看了这个 buddy：清掉未读标记。
    func markSeen(key: String)
    /// 「换个造型」：换新的外观 salt 并持久化。
    func rerollAppearance(key: String)
    func diagnostics() -> DiagnosticsInfo
}
