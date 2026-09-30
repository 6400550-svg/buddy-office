import Foundation

/// 引擎里每个 buddy 的内部状态（只在 ingest 队列上访问，不是线程安全的）。
final class BuddyState {
    enum Lifecycle: Equatable {
        /// 进程活着。
        case live
        /// 登记文件消失 / PID 已死或被复用，正在防抖（3 秒）。
        case pendingAway(since: Date)
        /// 已确认离场。dormant = 下班工位；否则 removeAt 时收回工位。
        case away(since: Date, dormant: Bool, removeAt: Date?)
    }

    struct PendingEnd {
        var endedAt: Date
        var startedAt: Date?
    }

    // —— 身份 ——
    var key: String
    var seat: Int
    var salt: UInt64
    var lifecycle: Lifecycle = .live
    var appearedAfterLaunch: Bool

    // —— 登记表 / 桌面元数据 ——
    var record: RegistryRecord?
    var meta: DesktopMeta?
    var sessionId: String
    var hostSessionId: String?

    // —— 读取器（换会话时重建）——
    var hookReader: HookLogReader?
    var transcript: TranscriptReader?
    var transcriptPath: String?
    var lastLocateAt: Date?
    var helpers: SubagentReader?
    var lastHelperListAt: Date?
    var customTitleFileTitle: String?
    var customTitleSig: FileStat?
    var lastTitleCheckAt: Date?
    var tokenGroupSig = ""
    var tokenGate = ""

    // —— hook 状态 ——
    var inbox: [HookEvent] = []
    var tracker = ToolTracker()
    var attributor = HelperAttributor()
    var hookMaxTs: Date?
    var lastHookEventAt: Date?
    var lastPromptAt: Date?
    var lastStopAt: Date?
    var preCompactAt: Date?
    var postCompactAt: Date?
    var notificationText: String?
    var notificationAt: Date?
    var summaryHintAt: Date?
    var hookEventsSeen = 0

    // —— 轮次 ——
    var phase: Phase?
    var turnStartedAt: Date?
    var idleSince: Date?
    var lastTurnEndedAt: Date?
    var lastTurnDuration: TimeInterval?
    var turnEnd: TurnEndKind = .none
    var pendingEnd: PendingEnd?
    var unread = false
    var blocked = false
    var statusDetail: String?
    var suppressedSummaryFor: String?
    var attention: AttentionKind?
    var activity: Activity = .idle
    var activitySince: Date
    var quiet = false
    var lastGrowthAt: Date
    var lastStopMarkerSeen: Date?
    var lastTouchAt: Date?

    init(key: String, seat: Int, salt: UInt64, sessionId: String, appearedAfterLaunch: Bool, now: Date) {
        self.key = key
        self.seat = seat
        self.salt = salt
        self.sessionId = sessionId
        self.appearedAfterLaunch = appearedAfterLaunch
        self.activitySince = now
        self.lastGrowthAt = now
    }

    var isLive: Bool { if case .live = lifecycle { return true } else { return false } }
    var isPendingAway: Bool { if case .pendingAway = lifecycle { return true } else { return false } }
    var isDormant: Bool { if case .away(_, true, _) = lifecycle { return true } else { return false } }
    var isAway: Bool { if case .away = lifecycle { return true } else { return false } }

    /// 换了会话（`/clear`、在新进程里 resume 后 sessionId 变了）：会话相关的读取器和 hook 状态全部作废。
    func resetSessionScope(newSessionId: String) {
        sessionId = newSessionId
        hookReader = nil
        transcript = nil
        transcriptPath = nil
        lastLocateAt = nil
        helpers = nil
        lastHelperListAt = nil
        customTitleFileTitle = nil
        customTitleSig = nil
        tokenGroupSig = ""
        tokenGate = ""
        inbox = []
        tracker = ToolTracker()
        attributor = HelperAttributor()
        hookMaxTs = nil
        lastHookEventAt = nil
        lastPromptAt = nil
        lastStopAt = nil
        preCompactAt = nil
        postCompactAt = nil
        notificationText = nil
        notificationAt = nil
        summaryHintAt = nil
        hookEventsSeen = 0
    }
}

extension AttentionKind {
    /// 同一类等待（忽略里面的工具 / 文本细节）。
    func sameCase(as other: AttentionKind) -> Bool {
        switch (self, other) {
        case (.approval, .approval), (.question, .question), (.planReview, .planReview), (.other, .other): return true
        default: return false
        }
    }
}
