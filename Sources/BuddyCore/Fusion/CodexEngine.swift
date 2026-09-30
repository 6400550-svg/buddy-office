import Foundation

/// Codex（OpenAI）线程 → `[BuddySnapshot]`。和 `SessionEngine` 并排工作、由它调用（共用身份 / 工位）：
///
/// - **谁算「在场」**：Codex（app-server / ChatGPT 桌面 App）在运行，并且这个线程正在跑一轮、或最近 `linger`（默认 30 分钟）内有过动静。
///   Codex 没有「一个会话一个进程」的登记表，所以在场与否只能靠这两条；线程一旦安静超过 linger（或 Codex 退出了）就走出办公室。
/// - **在做什么**：从会话记录（rollout）里读：`task_started / task_complete / turn_aborted` 是一轮的边界，
///   `function_call / custom_tool_call` 到对应的 `*_output` 之间是「正在用一个工具」，`request_user_input*` 开着就是在问你。
///   动作最后交给 `ActivityResolver`（和 Claude 会话同一套「做完了 5 秒 → 空闲 → 打盹 → 睡着」的规则）。
/// - **不读什么**：对话内容（只留事件类型、工具名、时间、token 数）、auth.json、数据库。
/// - **看不到什么**：Codex 的「等你批准」不会写进会话记录，所以只有「在问你问题」（request_user_input）会让小人转身举手；
///   等批准时他会显示成正在用那个工具。这是数据源的限制，不是漏了。
///
/// 和 SessionEngine 一样没有线程、没有定时器：调用一次 `poll` 就把所有数据读一遍（stat + 增量读取）。
public final class CodexEngine {
    public struct Options {
        public var paths: Paths
        public var now: () -> Date
        public var probe: CodexProcessProbing
        /// 一个线程安静多久之后走出办公室（正在跑一轮的线程不受限制）。
        public var linger: TimeInterval = 30 * 60
        /// 最多同时坐几个 Codex 线程（再多的按「正在跑 > 最近有动静」排序，排不上的先不坐）。
        public var maxThreads = 6
        public var dozeAfter: TimeInterval = 10 * 60
        public var sleepAfter: TimeInterval = 45 * 60
        /// 离场防抖 / 离场动画后收回工位的延迟。
        public var awayDebounce: TimeInterval = 3
        public var awayLinger: TimeInterval = 8
        /// 一轮开着、但这么久文件没有任何新内容 → 不再当作在忙（Codex 被强退、会话记录没写 task_complete 的情况）。
        public var staleTurn: TimeInterval = 15 * 60
        /// 「Codex 在不在运行」的探测间隔 / 发现候选线程的间隔。
        public var probeInterval: TimeInterval = 2
        public var discoverInterval: TimeInterval = 1

        public init(paths: Paths = .real, now: @escaping () -> Date = Date.init, probe: CodexProcessProbing = SystemCodexProbe()) {
            self.paths = paths; self.now = now; self.probe = probe
        }
    }

    public struct Output {
        public var snapshots: [BuddySnapshot]
        public var events: [BuddyEvent]
        public var nextWake: Date?
    }

    private enum Life: Equatable {
        case live
        case pendingAway(since: Date)
        case away(since: Date, removeAt: Date)
    }

    private final class Buddy {
        let id: String
        let key: String
        var seat: Int
        var salt: UInt64
        let reader: CodexRolloutReader
        var life: Life = .live
        var appearedAfterLaunch: Bool
        var phase: Phase?
        var phaseSince: Date
        var turnStartedAt: Date?
        var idleSince: Date?
        var lastTurnEndedAt: Date?
        var lastTurnDuration: TimeInterval?
        var turnEnd: TurnEndKind = .none
        var unread = false
        var attention: AttentionKind?
        var activity: Activity = .idle
        var activitySince: Date
        var lastFacts = CodexFacts()

        init(id: String, seat: Int, salt: UInt64, reader: CodexRolloutReader, appearedAfterLaunch: Bool, now: Date) {
            self.id = id; self.key = "x:" + id; self.seat = seat; self.salt = salt; self.reader = reader
            self.appearedAfterLaunch = appearedAfterLaunch
            self.phaseSince = now; self.activitySince = now
        }
        var isLive: Bool { if case .live = life { return true } else { return false } }
        var isPendingAway: Bool { if case .pendingAway = life { return true } else { return false } }
    }

    public let options: Options
    let index: CodexIndex
    private let identities: IdentityResolver
    private var buddies: [String: Buddy] = [:]
    private var readers: [String: CodexRolloutReader] = [:]
    private var candidateIds: [String] = []
    private var lastDiscoverAt: Date?
    private var lastProbeAt: Date?
    private var running = true
    private var firstPoll = true
    private var events: [BuddyEvent] = []
    private var wake: Date?

    public init(options: Options, identities: IdentityResolver) {
        self.options = options
        self.index = CodexIndex(paths: options.paths)
        self.identities = identities
    }

    // MARK: - 对外

    /// 已经占着的工位（SessionEngine 分配新工位时要避开）。
    public var seats: Set<Int> { Set(buddies.values.map { $0.seat }.filter { $0 >= 0 }) }

    public func owns(key: String) -> Bool { key.hasPrefix("x:") }

    public func markSeen(key: String) { buddies[String(key.dropFirst(2))]?.unread = false }

    public func rerollAppearance(key: String) {
        guard let salt = identities.reroll(key: key) else { return }
        buddies[String(key.dropFirst(2))]?.salt = salt
    }

    // MARK: - poll

    /// `occupied`：别人（Claude 的会话）已经占了的工位。
    public func poll(occupied: Set<Int>) -> Output {
        let now = options.now()
        events = []
        wake = nil

        // 1. Codex 在不在运行
        if lastProbeAt == nil || now.timeIntervalSince(lastProbeAt!) >= options.probeInterval {
            running = options.probe.isRunning()
            lastProbeAt = now
        }
        wakeAt(lastProbeAt!.addingTimeInterval(options.probeInterval))

        // 2. 候选线程：索引里最近更新过的 + 最新几天目录里最近改过的 + 已经在跟踪的
        index.refreshTitles()
        if lastDiscoverAt == nil || now.timeIntervalSince(lastDiscoverAt!) >= options.discoverInterval {
            lastDiscoverAt = now
            let since = now.addingTimeInterval(-options.linger)
            var ids = Set(index.idsUpdated(since: since))
            for r in index.recentRollouts(since: since, now: now) { ids.insert(r.id) }
            for k in buddies.keys { ids.insert(k) }
            candidateIds = Array(ids)
        }
        wakeAt((lastDiscoverAt ?? now).addingTimeInterval(options.discoverInterval))

        // 3. 读每个候选线程的会话记录；判断谁该在场
        var eligible: [(id: String, active: Bool, activity: Date)] = []
        var live = Set<String>()
        for id in candidateIds {
            let reader: CodexRolloutReader
            if let r = readers[id] {
                reader = r
                r.poll()
            } else {
                guard let path = index.rolloutPath(for: id, now: now) else { continue }
                // 文件很久没动过的线程不值得读：先看 mtime
                guard let st = FileIO.stat(path), now.timeIntervalSince(st.mtime) <= options.linger || buddies[id] != nil else { continue }
                reader = CodexRolloutReader(path: path)
                guard reader.bootstrap() else { continue }
                readers[id] = reader
            }
            live.insert(id)
            let f = reader.facts
            if f.isSubagent { continue }
            let mtime = FileIO.stat(reader.path)?.mtime ?? .distantPast
            let last = max(mtime, f.lastEventAt ?? .distantPast)
            let active = f.turnOpen && now.timeIntervalSince(last) < options.staleTurn
            if active || now.timeIntervalSince(last) <= options.linger {
                eligible.append((id, active, last))
            }
        }
        // 不再是候选、也没人坐着的读取器释放掉
        for id in Array(readers.keys) where !live.contains(id) && buddies[id] == nil { readers[id] = nil }

        // 4. 在场 / 离场
        reconcile(eligible: eligible, now: now, occupied: occupied)

        // 5. 每个在场的线程：状态 → 动作
        for b in buddies.values where b.isLive || b.isPendingAway { update(b, now: now) }

        let snaps = buddies.values.map { snapshot($0, now: now) }.sorted { ($0.seat, $0.key) < ($1.seat, $1.key) }
        firstPoll = false
        return Output(snapshots: snaps, events: events, nextWake: wake)
    }

    private func wakeAt(_ t: Date?) {
        guard let t else { return }
        wake = min(wake ?? t, t)
    }

    private func emit(_ key: String, at: Date, _ kind: BuddyEvent.Kind) {
        events.append(BuddyEvent(key: key, at: at, kind: kind))
    }

    // MARK: - 在场 / 离场

    private func reconcile(eligible: [(id: String, active: Bool, activity: Date)], now: Date, occupied: Set<Int>) {
        let ok = running
        let wanted = Set(eligible.map { $0.id })
        var taken = occupied.union(seats)

        // 新来的：按「正在跑 > 最近有动静」排序，坐满 maxThreads 为止
        let liveCount = buddies.values.filter { $0.isLive || $0.isPendingAway }.count
        var room = max(0, options.maxThreads - liveCount)
        if ok {
            for e in eligible.sorted(by: { ($0.active ? 1 : 0, $0.activity) > ($1.active ? 1 : 0, $1.activity) }) {
                if let b = buddies[e.id] {
                    switch b.life {
                    case .live: break
                    case .pendingAway: b.life = .live                                  // 防抖期内回来了：什么都没发生
                    case .away:                                                        // 走到一半又有动静：回来
                        b.life = .live; b.appearedAfterLaunch = true; b.phase = nil
                        emit(b.key, at: now, .arrived(freshAfterLaunch: true))
                    }
                    continue
                }
                guard room > 0, let reader = readers[e.id] else { continue }
                room -= 1
                let identity = identities.codexIdentity(threadId: e.id)
                let seat = identities.assignSeat(forKey: identity.key, occupied: taken)
                taken.insert(seat)
                let b = Buddy(id: e.id, seat: seat, salt: identity.salt, reader: reader, appearedAfterLaunch: !firstPoll, now: now)
                buddies[e.id] = b
                emit(b.key, at: now, .arrived(freshAfterLaunch: !firstPoll))
            }
        }

        // 走的：不再符合条件 / Codex 退出了
        for b in Array(buddies.values) {
            let stays = ok && wanted.contains(b.id)
            switch b.life {
            case .live:
                if !stays { b.life = .pendingAway(since: now); wakeAt(now.addingTimeInterval(options.awayDebounce)) }
            case .pendingAway(let since):
                if stays { b.life = .live }
                else if now.timeIntervalSince(since) >= options.awayDebounce {
                    b.life = .away(since: since, removeAt: now.addingTimeInterval(options.awayLinger))
                    emit(b.key, at: now, .departed(dormant: false))
                    if b.attention != nil { emit(b.key, at: now, .needsUserCleared); b.attention = nil }
                    b.activity = .idle; b.activitySince = now; b.phase = .idle; b.turnStartedAt = nil; b.idleSince = since
                    wakeAt(now.addingTimeInterval(options.awayLinger))
                } else {
                    wakeAt(since.addingTimeInterval(options.awayDebounce))
                }
            case .away(_, let removeAt):
                if stays { continue }                                                  // 上面已经处理了「回来」
                if now >= removeAt { buddies[b.id] = nil; readers[b.id] = nil } else { wakeAt(removeAt) }
            }
        }
    }

    // MARK: - 状态

    private static func isQuestionTool(_ name: String) -> Bool { name.hasPrefix("request_user_input") }

    private func update(_ b: Buddy, now: Date) {
        let f = b.reader.facts
        b.lastFacts = f
        let mtime = FileIO.stat(b.reader.path)?.mtime ?? .distantPast
        let last = max(mtime, f.lastEventAt ?? .distantPast)
        let active = f.turnOpen && now.timeIntervalSince(last) < options.staleTurn
        if f.turnOpen && active { wakeAt(last.addingTimeInterval(options.staleTurn)) }
        let asking = active && f.open.contains { Self.isQuestionTool($0.name) }
        let phase: Phase = active ? (asking ? .waiting : .busy) : .idle

        if let old = b.phase {
            if old != phase {
                if old == .idle {
                    // 新一轮开始
                    b.turnStartedAt = min(f.turnStartedAt ?? now, now)
                    b.idleSince = nil
                    b.unread = false
                    b.turnEnd = .none
                    emit(b.key, at: b.turnStartedAt ?? now, .turnStarted)
                    b.phaseSince = now
                } else if phase == .idle {
                    // 一轮结束
                    if f.turnOpen {
                        // 一轮一直没有 task_complete、文件也没动静了：悄悄当作空闲，不报「做完了」
                        b.idleSince = last; b.turnEnd = .none; b.turnStartedAt = nil
                    } else {
                        let ended = min(f.lastTurnEndedAt ?? now, now)
                        let start = b.turnStartedAt ?? f.turnStartedAt
                        b.idleSince = ended
                        b.lastTurnEndedAt = ended
                        b.lastTurnDuration = f.lastTurnDuration ?? max(0, ended.timeIntervalSince(start ?? ended))
                        b.turnEnd = f.lastTurnInterrupted ? .interrupted : .finished
                        b.unread = !f.lastTurnInterrupted
                        b.turnStartedAt = nil
                        emit(b.key, at: now, .turnFinished(duration: b.lastTurnDuration, interrupted: f.lastTurnInterrupted, errored: false))
                    }
                    b.phaseSince = now
                } else {
                    b.phaseSince = now                                                  // busy ↔ waiting：还在同一轮里
                }
                b.phase = phase
            }
        } else {
            // 第一次看到：不能凭空报「做完了」；空闲的计时从最近一次动静算起
            b.phase = phase
            b.phaseSince = active ? min(f.turnStartedAt ?? now, now) : min(last, now)
            if active { b.turnStartedAt = min(f.turnStartedAt ?? now, now); b.idleSince = nil }
            else {
                b.idleSince = f.lastTurnEndedAt.map { min($0, now) } ?? min(last, now)
                b.turnEnd = .none
                if let e = f.lastTurnEndedAt { b.lastTurnEndedAt = min(e, now); b.lastTurnDuration = f.lastTurnDuration }
            }
        }

        // 信号 → 动作（和 Claude 会话同一个解析器）
        var sig = SessionSignals()
        sig.registryStatus = phase
        sig.statusUpdatedAt = b.phaseSince
        sig.waitingFor = phase == .waiting ? "input needed" : nil
        sig.openTools = f.open.filter { !Self.isQuestionTool($0.name) }
            .map { ToolCatalog.makeCall(name: $0.name, detail: $0.detail, at: $0.startedAt) }
        sig.idleSince = b.idleSince
        sig.turnEnd = b.turnEnd
        sig.dozeAfter = options.dozeAfter
        sig.sleepAfter = options.sleepAfter
        let res = ActivityResolver.evaluate(sig, now: now)
        wakeAt(res.nextChange)
        apply(b, res.activity, signals: sig, now: now)
    }

    private func apply(_ b: Buddy, _ activity: Activity, signals sig: SessionSignals, now: Date) {
        if activity != b.activity {
            b.activity = activity
            b.activitySince = since(for: activity, b: b, signals: sig, now: now)
        }
        let kind: AttentionKind? = {
            switch activity {
            case .waitingApproval(let t): return .approval(t)
            case .asking: return .question
            case .planReview: return .planReview
            case .waitingOther(let s): return .other(s)
            default: return nil
            }
        }()
        switch (kind, b.attention) {
        case let (k?, nil): emit(b.key, at: b.activitySince, .needsUser(k))
        case (nil, .some): emit(b.key, at: now, .needsUserCleared)
        case let (k?, old?) where !k.sameCase(as: old): emit(b.key, at: b.activitySince, .needsUser(k))
        default: break
        }
        b.attention = kind
    }

    private func since(for a: Activity, b: Buddy, signals sig: SessionSignals, now: Date) -> Date {
        func clamp(_ d: Date?) -> Date { min(d ?? now, now) }
        switch a {
        case .tool(let c, _): return clamp(c.startedAt)
        case .waitingApproval, .asking, .planReview, .waitingOther: return clamp(sig.statusUpdatedAt ?? b.turnStartedAt)
        case .compacting, .retrying: return now
        case .interrupted, .finished, .errored, .idle: return clamp(b.idleSince)
        case .dozing: return clamp(b.idleSince?.addingTimeInterval(options.dozeAfter))
        case .sleeping: return clamp(b.idleSince?.addingTimeInterval(options.sleepAfter))
        case .thinking:
            if b.activity.phase == .busy { return now }
            return clamp(b.turnStartedAt)
        }
    }

    // MARK: - 快照

    static func modelFamily(_ model: String?) -> ModelFamily {
        guard let m = model?.lowercased(), !m.isEmpty else { return .gpt }
        if m.hasPrefix("gpt") || m.hasPrefix("codex") || m.hasPrefix("chatgpt") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .gpt }
        if m.hasPrefix("claude") { return .claude }
        if m.hasPrefix("deepseek") { return .deepseek }
        if m.hasPrefix("glm") { return .glm }
        return .other
    }

    private func title(_ b: Buddy) -> String {
        if let t = index.title(for: b.id) { return t }
        if let cwd = b.lastFacts.cwd, !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            if !last.isEmpty && last != "/" { return last }
        }
        return "Codex " + String(b.id.prefix(8))
    }

    private func snapshot(_ b: Buddy, now: Date) -> BuddySnapshot {
        let f = b.lastFacts
        var s = BuddySnapshot(key: b.key, seat: b.seat, salt: b.salt, title: title(b), sessionId: b.id,
                              origin: .codex, activity: b.activity, now: b.activitySince)
        s.cwd = f.cwd
        s.modelName = f.model
        s.modelFamily = CodexEngine.modelFamily(f.model)
        s.effort = f.effort
        s.permissionMode = f.approvalPolicy
        s.cliVersion = f.cliVersion
        s.sessionStartedAt = f.startedAt
        switch b.life {
        case .live, .pendingAway: s.presence = .present
        case .away(let since, _): s.presence = .away(since: since, dormant: false)
        }
        s.appearedAfterLaunch = b.appearedAfterLaunch
        s.phase = b.activity.phase
        s.turnStartedAt = b.turnStartedAt
        s.lastTurnDuration = b.lastTurnDuration
        s.lastTurnEndedAt = b.lastTurnEndedAt
        s.idleSince = b.idleSince
        s.unread = b.unread
        s.blocked = false
        s.quiet = false
        if let t = f.tokens { s.tokens = t }
        s.contextTokens = f.contextTokens
        s.hookActive = false
        return s
    }

    // MARK: - 诊断

    public func diagnosticLines() -> [String] {
        let live = buddies.values.filter { $0.isLive || $0.isPendingAway }
        var out: [String] = []
        if !index.sessionsReadable { out.append("Codex: 没找到 ~/.codex/sessions（没装 Codex？）") }
        else if !running { out.append("Codex: 没在运行（\(live.count) 个线程会在它启动后出现）") }
        else { out.append("Codex: 正常（\(live.count) 个线程在场，索引 \(index.indexReadable ? "可读" : "读不了")）") }
        return out
    }

    public func diagnosticSessions() -> [DiagnosticsInfo.SessionDiag] {
        buddies.values.filter { $0.isLive || $0.isPendingAway }.sorted { $0.seat < $1.seat }.map {
            DiagnosticsInfo.SessionDiag(key: $0.key, title: title($0), pid: nil, cliVersion: $0.lastFacts.cliVersion,
                                        hookActive: false, lastHookEventAt: nil, origin: .codex)
        }
    }

    /// `buddydump` 一行要的信息（Codex 没有登记表 / hook，对应的列留空）。
    func debugRows() -> [BuddyDebugRow] {
        let now = options.now()
        return buddies.values.map { b in
            let f = b.lastFacts
            return BuddyDebugRow(
                snapshot: snapshot(b, now: now), registryStatus: b.phase?.rawValue, waitingFor: nil, statusUpdatedAt: b.phaseSince,
                liveness: b.isLive ? "alive" : (b.isPendingAway ? "away?" : "away"),
                hookEventsSeen: 0, lastHookEventAt: nil, hookDegradedLines: 0, hookSkippedLines: b.reader.skippedLines,
                openMainTools: f.open.map { ToolCatalog.makeCall(name: $0.name, detail: $0.detail, at: $0.startedAt) }, openHelperTools: [],
                transcriptPath: b.reader.path, lastTranscriptLineAt: f.lastEventAt, tokenMessages: 0, tokenScanComplete: true, helperFiles: 0)
        }
    }

    public var liveCount: Int { buddies.values.filter { $0.isLive || $0.isPendingAway }.count }
}
