import Foundation

/// 子代理事件的归属（DESIGN.md 5.3）。
///
/// hook 事件里没有 agent_id，子代理的工具调用也记在父会话的文件里，所以要猜这个 PreToolUse 是谁发的。
/// 按顺序判断：
/// 1. 主会话是 idle（没有临时 busy）→ 归后台小助手；
/// 2. 主线程有一个前台 Agent / Task 正开着，并且事件比它晚 0.15 秒以上 → 归小助手；
/// 3. 有后台小助手正在活跃 → 先把事件扣住，最多 400 ms；在这段时间里拿"工具名 + 第一个输入字段"
///    去和小助手会话记录、主会话记录里最近的 tool_use 比对：比对上的归那一方，比对不上就归主线程；
/// 4. 其他情况 → 归主线程。
///
/// 小助手显示的动作直接取自它自己的会话记录，所以即使归属判错，也只会影响主 buddy，
/// 而且到下一个轮次边界就会纠正。
public struct HelperAttributor {
    public enum Decision: Equatable {
        case main
        case helper
        /// 先扣住，到这个时间还没比对上就归主线程。
        case hold(until: Date)
    }

    public struct ToolUseRecord: Equatable {
        public var id: String
        public var name: String
        public var key: String
        public var at: Date
        public init(id: String, name: String, key: String, at: Date) {
            self.id = id; self.name = name; self.key = key; self.at = at
        }
    }

    public struct Context {
        /// 主会话是 idle（没有临时 busy）。
        public var mainIdle: Bool
        /// 主线程正开着的前台 Agent / Task 的 Pre 时间（没有就是 nil）。
        public var foregroundAgentOpenSince: Date?
        /// 有没有后台小助手正在活跃。
        public var hasActiveBackgroundHelper: Bool
        public var helperUses: [ToolUseRecord]
        public var mainUses: [ToolUseRecord]
        public init(mainIdle: Bool, foregroundAgentOpenSince: Date? = nil, hasActiveBackgroundHelper: Bool = false,
                    helperUses: [ToolUseRecord] = [], mainUses: [ToolUseRecord] = []) {
            self.mainIdle = mainIdle
            self.foregroundAgentOpenSince = foregroundAgentOpenSince
            self.hasActiveBackgroundHelper = hasActiveBackgroundHelper
            self.helperUses = helperUses
            self.mainUses = mainUses
        }
    }

    /// 前台 Agent 的 Pre 之后多久（秒）的事件才算小助手的（同一批并行的主线程调用会紧贴着它）。
    public static let foregroundGap: TimeInterval = 0.15
    /// 扣住的最长时间（秒）。
    public static let holdLimit: TimeInterval = 0.4
    /// 会话记录里的 tool_use 和 hook 事件的时间差容忍范围（主线程的整条消息写盘会晚，所以往前放得宽）。
    static let windowBefore: TimeInterval = 90
    static let windowAfter: TimeInterval = 10

    /// 已经被某个 hook 事件配对过的 tool_use id（同一个 tool_use 只配一次）。
    private var claimed: [String: Date] = [:]
    /// 正在扣留的那个事件（限制扣留时长用）。
    private var held: (ts: Date, tool: String, since: Date)?

    public init() {}

    public mutating func decide(event: HookEvent, context c: Context, now: Date) -> Decision {
        let d = decideImpl(event: event, context: c, now: now)
        if case .hold = d {} else { held = nil }          // 只有连续的"扣留"才算同一次扣留
        return d
    }

    private mutating func decideImpl(event: HookEvent, context c: Context, now: Date) -> Decision {
        // 1. 主会话是 idle → 小助手
        if c.mainIdle { return .helper }
        // 2. 前台 Agent / Task 开着，事件比它晚 0.15 秒以上 → 小助手
        // （按毫秒取整比较：hook 的时间戳是毫秒，0.15 秒恰好算"晚 0.15 秒以上"，不能被浮点误差挡在门外）
        // （全程用 Double 比较：不做 Int(…) 换算——时间戳再离谱也不会 trap；NaN 比较为 false）
        if let since = c.foregroundAgentOpenSince,
           (event.ts.timeIntervalSince(since) * 1000).rounded() >= (HelperAttributor.foregroundGap * 1000).rounded() {
            return .helper
        }
        // 3. 有后台小助手活跃 → 用会话记录比对，最多扣住 400 ms
        if c.hasActiveBackgroundHelper {
            let h = firstMatch(in: c.helperUses, for: event)
            let m = firstMatch(in: c.mainUses, for: event)
            switch (h, m) {
            case let (h?, nil): claimed[h.id] = now; return .helper
            case let (nil, m?): claimed[m.id] = now; return .main
            case let (_, m?): claimed[m.id] = now; return .main      // 两边都对得上：无法区分，归主线程
            case (nil, nil):
                // 扣留最多 holdLimit：从事件的时间戳算起，但也不超过"第一次扣它"的那一刻起算的 holdLimit——
                // 时间戳在未来（时钟被拨回 / 坏数据）的事件不能一直扣下去，那样整个 hook 队列都会被卡死。
                let firstSeen: Date
                if let h = held, h.ts == event.ts, h.tool == event.tool { firstSeen = h.since } else {
                    firstSeen = now
                    held = (event.ts, event.tool, now)
                }
                let deadline = min(event.ts, firstSeen).addingTimeInterval(HelperAttributor.holdLimit)
                return now < deadline ? .hold(until: deadline) : .main
            }
        }
        // 4. 其他 → 主线程
        return .main
    }

    private func firstMatch(in uses: [ToolUseRecord], for event: HookEvent) -> ToolUseRecord? {
        for u in uses where claimed[u.id] == nil {
            let dt = u.at.timeIntervalSince(event.ts)
            if dt < -HelperAttributor.windowBefore || dt > HelperAttributor.windowAfter { continue }
            guard ToolTracker.namesMatch(event.tool, aTruncated: event.toolTruncated, u.name, bTruncated: false) else { continue }
            if ToolDetail.matches(hookDetail: event.detail, transcriptKey: u.key) { return u }
        }
        return nil
    }

    /// 丢掉太旧的配对记录。
    public mutating func prune(now: Date) {
        claimed = claimed.filter { now.timeIntervalSince($0.value) < 600 }
    }
}
