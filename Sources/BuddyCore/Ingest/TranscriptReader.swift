import Foundation

/// 从一个会话记录文件（主会话或子代理）增量累积出来的"事实"。不含任何对话内容。
public struct TranscriptFacts: Sendable, Equatable {
    public struct OpenToolUse: Sendable, Equatable {
        public var id: String
        public var name: String
        public var key: String
        public var at: Date
    }
    public struct ApiError: Sendable, Equatable {
        public var at: Date
        public var attempt: Int
        public var max: Int
        public var retryInMs: Double
    }
    public struct RecentToolUse: Sendable, Equatable {
        public var id: String
        public var name: String
        public var key: String
        public var at: Date
    }

    /// 读过多少行（用来判断尾部窗口里有没有读到东西）。
    public var linesSeen = 0
    /// 最后一条带时间戳的行（任意类型）。
    public var lastLineAt: Date?
    /// 最后一条 assistant / user 行（不含 meta、不含 attachment 等）。
    public var lastAssistantAt: Date?
    public var lastUserAt: Date?
    /// 人的最近一次输入（一轮的开始）。
    public var lastPromptAt: Date?
    /// 最近一条 `stop_hook_summary`（一轮结束）。
    public var stopHookSummaryAt: Date?
    /// 最近一条 `stop_reason == end_turn` 的 assistant。
    public var endTurnAt: Date?
    /// 终端会话才有的 `turn_duration`。
    public var turnDurationAt: Date?
    public var turnDurationMs: Double?
    /// 最近一次打断（用户行 `[Request interrupted by user…` 或 assistant 的 isAbortedMidStream）。
    public var interruptAt: Date?
    public var apiError: ApiError?
    /// 最近一条"合成的 API 错误"assistant（isApiErrorMessage）。
    public var syntheticErrorAt: Date?
    public var compactBoundaryAt: Date?
    /// 还没有 tool_result 的 tool_use，按出现顺序。
    public var openToolUses: [OpenToolUse] = []
    /// 最近的一批 tool_use（给子代理归属比对用）。
    public var recentToolUses: [RecentToolUse] = []
    public var customTitle: String?
    public var aiTitle: String?
    public var model: String?
    public var effort: String?
    public var permissionMode: String?
    /// 最近一条 assistant 的 stop_reason；最后一条 assistant/user 是不是 end_turn 的 assistant。
    public var lastAssistantStopReason: String?
    public var lastMessageWasEndTurn = false
    /// 当前上下文大小：最近一次（主线程）assistant usage 的 input + 缓存写 + 缓存读。
    public var contextTokens: Int?

    public init() {}

    /// 最近一条 assistant 或 user 行的时间（判断 api_error 之后有没有新内容）。
    public var lastAssistantOrUserAt: Date? {
        switch (lastAssistantAt, lastUserAt) {
        case let (a?, u?): return max(a, u)
        case let (a?, nil): return a
        case let (nil, u?): return u
        default: return nil
        }
    }

    static let maxOpen = 64
    static let maxRecent = 32

    mutating func apply(_ line: TranscriptLine, includeSidechain: Bool) {
        linesSeen += 1
        if line.isSidechain && !includeSidechain { return }
        if let ts = line.timestamp { lastLineAt = max(lastLineAt ?? ts, ts) }
        switch line.kind {
        case .customTitle:
            if let t = line.text, !t.isEmpty { customTitle = t }
        case .aiTitle:
            if let t = line.text, !t.isEmpty { aiTitle = t }
        case .permissionMode:
            if let t = line.text, !t.isEmpty { permissionMode = t }
        case .assistant:
            guard let ts = line.timestamp else { return }
            lastAssistantAt = max(lastAssistantAt ?? ts, ts)
            if line.model == "<synthetic>" {
                if line.isApiErrorMessage { syntheticErrorAt = max(syntheticErrorAt ?? ts, ts) }
                lastMessageWasEndTurn = false
            } else {
                if let m = line.model, !m.isEmpty { model = m }
                if let e = line.effort, !e.isEmpty { effort = e }
                if let u = line.usage, u.input + u.cacheWriteTotal + u.cacheRead > 0 {
                    contextTokens = u.input + u.cacheWriteTotal + u.cacheRead
                }
                lastAssistantStopReason = line.stopReason
                lastMessageWasEndTurn = (line.stopReason == "end_turn")
                if line.stopReason == "end_turn" { endTurnAt = max(endTurnAt ?? ts, ts) }
            }
            if line.isAbortedMidStream { interruptAt = max(interruptAt ?? ts, ts) }
            for tu in line.toolUses {
                if !openToolUses.contains(where: { $0.id == tu.id }) {
                    openToolUses.append(.init(id: tu.id, name: tu.name, key: tu.key, at: ts))
                    if openToolUses.count > TranscriptFacts.maxOpen { openToolUses.removeFirst() }
                }
                recentToolUses.append(.init(id: tu.id, name: tu.name, key: tu.key, at: ts))
                if recentToolUses.count > TranscriptFacts.maxRecent { recentToolUses.removeFirst() }
            }
        case .user:
            if line.isMeta { return }
            guard let ts = line.timestamp else { return }
            lastUserAt = max(lastUserAt ?? ts, ts)
            lastMessageWasEndTurn = false
            for r in line.toolResults { openToolUses.removeAll { $0.id == r.id } }
            if line.isInterrupt { interruptAt = max(interruptAt ?? ts, ts) }
            if line.isPrompt { lastPromptAt = max(lastPromptAt ?? ts, ts) }
        case .system:
            guard let ts = line.timestamp else { return }
            switch line.subtype {
            case "stop_hook_summary":
                stopHookSummaryAt = max(stopHookSummaryAt ?? ts, ts)
            case "api_error":
                if apiError == nil || ts >= apiError!.at {
                    apiError = ApiError(at: ts, attempt: line.retryAttempt ?? 0, max: line.maxRetries ?? 0,
                                        retryInMs: line.retryInMs ?? 0)
                }
            case "compact_boundary":
                compactBoundaryAt = max(compactBoundaryAt ?? ts, ts)
            case "turn_duration":
                if let ms = line.durationMs { turnDurationAt = ts; turnDurationMs = ms }
            default: break
            }
        case .other:
            break
        }
    }

    /// 一轮结束 / 新一轮开始时，主线程不可能还有没结果的 tool_use（写盘延迟导致的残留要清掉）。
    mutating func closeAllOpenToolUses() { openToolUses.removeAll() }
}

/// 一个会话记录文件的增量读取器：只读尾部窗口 + 之后新增的部分，绝不整文件读。
public final class TranscriptReader {
    public let path: String
    /// 子代理文件里每一行都带 isSidechain=true，要包含；主会话文件里的 sidechain 行属于别人，要跳过。
    public let includeSidechain: Bool
    public private(set) var facts = TranscriptFacts()
    public private(set) var jsonErrors = 0
    private let tailer: JSONLTailer
    /// 时钟（引擎传它的 `options.now`）。给了的话，比"现在"晚超过 `futureSlack` 的行时间戳按"现在"算：
    /// 事实里到处是"取最大时间"，一条时间戳在很远的未来的坏行（时钟被拨快过 / 数据写坏）会把它们永远毒化。
    private let clock: (() -> Date)?
    /// 允许比现在晚多久（时钟误差、写盘延迟之类）。
    static let futureSlack: TimeInterval = 86400

    public init(path: String, includeSidechain: Bool = false, clock: (() -> Date)? = nil) {
        self.path = path
        self.includeSidechain = includeSidechain
        self.clock = clock
        self.tailer = JSONLTailer(path: path)
    }

    public var fileSize: UInt64 { tailer.lastSize }
    public var resetCount: Int { tailer.resetCount }

    /// 第一次读：从尾部窗口开始。窗口里一行都没读到（整个窗口落在一条超长行里）就放大窗口重试。
    public func bootstrap(tailWindow: Int = 512 << 10) {
        var window = max(1, tailWindow)                       // ≤ 0 会让下面的 window *= 4 永远是 0：死循环
        while true {
            tailer.seekToTail(window: window)
            facts = TranscriptFacts()
            pollInternal()
            let size = tailer.lastSize
            if facts.linesSeen > 0 || size <= UInt64(window) || window >= (8 << 20) { break }
            window *= 4
        }
    }

    /// 读新增内容。返回文件有没有增长（或被重写）。
    @discardableResult
    public func poll() -> Bool {
        pollInternal()
    }

    @discardableResult
    private func pollInternal() -> Bool {
        var seenResets = tailer.resetCount
        let r = tailer.poll { [self] bytes in
            if tailer.resetCount != seenResets {
                // 文件被重写 / 轮转：旧事实作废，从新内容重新累积
                seenResets = tailer.resetCount
                facts = TranscriptFacts()
            }
            autoreleasepool {
                if var line = TranscriptLineParser.parse(bytes) {
                    if let clock, let ts = line.timestamp {
                        let now = clock()
                        if ts > now.addingTimeInterval(TranscriptReader.futureSlack) { line.timestamp = now }
                    }
                    facts.apply(line, includeSidechain: includeSidechain)
                } else {
                    jsonErrors += 1
                }
            }
        }
        if r.reset && r.lines == 0 { facts = TranscriptFacts() }
        return r.changed
    }
}

/// 找会话记录文件：`~/.claude/projects/<编码后的cwd>/<sessionId>.jsonl`。
/// cwd 的编码有信息丢失，所以**不要自己拼目录名**，而是逐个子目录看有没有这个文件。
public enum TranscriptLocator {
    public static func find(sessionId: String, projectsDir: String) -> String? {
        guard Paths.isSafeID(sessionId), let dirs = FileIO.listDirectory(projectsDir) else { return nil }
        let file = sessionId + ".jsonl"
        for d in dirs {
            let p = projectsDir + "/" + d + "/" + file
            if let st = FileIO.stat(p), !st.isDirectory { return p }
        }
        return nil
    }

    /// 会话记录文件对应的"会话目录"（放 subagents/ 的地方）：去掉 `.jsonl`。
    public static func sessionDir(forTranscript path: String) -> String {
        path.hasSuffix(".jsonl") ? String(path.dropLast(6)) : path
    }
}
