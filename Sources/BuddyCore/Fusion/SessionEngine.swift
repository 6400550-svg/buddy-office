import Foundation

/// 数据层的核心：把登记表、hook 事件、会话记录、子代理、桌面元数据、token 账本融合成 `[BuddySnapshot]`。
///
/// 引擎本身**不带线程、不带定时器**：每调用一次 `poll()` 就把所有数据源读一遍（都是 stat 比较 + 增量读取，很便宜），
/// 返回快照、一次性事件，以及"如果没有新信号，最早什么时候需要再 poll 一次"（`nextWake`）。
/// 所有和时间有关的判断都用注入的时钟 `options.now`，测试里可以喂"带时间戳的事件脚本"。
/// 线程由外面的 `SessionStore` 管；引擎只能在一个串行队列上使用。
public final class SessionEngine {
    public struct Options {
        public var paths: Paths
        public var now: () -> Date
        public var probe: ProcessProbing
        /// 空闲超过多久打盹 / 睡着（秒）。
        public var dozeAfter: TimeInterval = 10 * 60
        public var sleepAfter: TimeInterval = 45 * 60
        /// 下班工位：最多几个、启动时取多近的桌面会话、多久后移除。
        public var dormantMax = 4
        public var dormantRecent: TimeInterval = 3 * 3600
        public var dormantExpire: TimeInterval = 12 * 3600
        /// 离场防抖（桌面 App 重启时会带着同一个 host id 回来）与非下班工位收回的延迟。
        public var awayDebounce: TimeInterval = 3
        public var awayLinger: TimeInterval = 8
        /// 进程存活检查间隔 / 重新列目录（桌面元数据、子代理目录）的间隔。
        public var livenessInterval: TimeInterval = 1
        public var listInterval: TimeInterval = 0.5
        /// 会话在忙（或有小助手）时重新列子代理目录的间隔，闲着时用 `helperListIdleInterval`。
        public var helperListInterval: TimeInterval = 0.15
        public var helperListIdleInterval: TimeInterval = 1
        /// busy → idle 之后等多久看有没有 Stop 事件（没有就判为被打断）。
        public var stopGrace: TimeInterval = 0.4
        /// busy 但这么久 hook 和会话记录都没有增长 → quiet（只是换种画法，绝不代表会话死了）。
        public var quietAfter: TimeInterval = 10 * 60
        /// 是否读写 identities.json / ledger.json。
        public var persist = true
        /// 是否统计 token（关掉可以省掉后台线程）。
        public var scanTokens = true
        /// 账本扫描队列（nil = 默认的后台低优先级队列）；测试注入更高优先级的队列，机器满载时才不会被饿死（R4b-01）。
        public var ledgerQueue: DispatchQueue?
        public var hookTailWindow = 256 << 10
        public var transcriptTailWindow = 512 << 10
        /// 是否把 Codex（OpenAI）的线程也读进来（设置页里的开关；`~/.codex` 不存在时什么都不会发生）。
        public var codexEnabled = true
        /// Codex 线程安静多久后走出办公室 / 最多同时坐几个 / 探测「Codex 在不在运行」的对象（测试注入）。
        public var codexLinger: TimeInterval = 30 * 60
        public var codexMaxThreads = 6
        public var codexProbe: CodexProcessProbing = SystemCodexProbe()

        public init(paths: Paths = .real, now: @escaping () -> Date = Date.init,
                    probe: ProcessProbing = SystemProcessProbe()) {
            self.paths = paths
            self.now = now
            self.probe = probe
        }
    }

    public struct Output {
        public var snapshots: [BuddySnapshot]
        public var events: [BuddyEvent]
        /// 没有新信号时，最早什么时候需要再 poll（nil = 没有时间驱动的变化）。
        public var nextWake: Date?
        /// token 账本的版本（变了说明后台扫描有新结果）。
        public var tokenVersion: Int
    }

    private struct LivenessEntry {
        var liveness: ProcessLiveness
        var checkedAt: Date
        var sig: String
    }

    public let options: Options
    public let ledger: TokenLedger?
    let registry: RegistryScanner
    let metaReader: DesktopMetaReader
    let identities: IdentityResolver
    /// Codex 线程（独立的一条数据源，共用身份 / 工位）。
    let codex: CodexEngine?

    /// 一条登记记录里和身份有关的字段：没变就不用重新归属（登记表每次状态变化只改 status 之类的字段）。
    private struct IdentitySig: Equatable {
        var pid: Int32
        var sessionId: String
        var host: String?
        var procStart: Date?
        var metaVersion: Int
    }

    private var buddies: [String: BuddyState] = [:]
    private var resolvedKeys: [Int32: (sig: IdentitySig, key: String)] = [:]
    private var metaVersion = 0
    private var metaRefreshHint = false
    private var livenessCache: [Int32: LivenessEntry] = [:]
    private var transcriptPathCache: [String: String] = [:]
    /// 没找到会话记录文件的会话：2 秒内不再重试（每次都要列 projects/ 下几十个目录，很贵）。
    private var transcriptMissAt: [String: Date] = [:]
    private var lastCachePruneAt: Date?
    private var firstPoll = true
    private var lastMetaRefreshAt: Date?
    private var pendingEvents: [BuddyEvent] = []
    private var wake: Date?
    private var registryReadable = true
    private var registryFileCount = 0
    private var hookInSettings: Bool?
    private var lastSettingsCheckAt: Date?

    public init(options: Options) {
        self.options = options
        let p = options.paths
        self.registry = RegistryScanner(dir: p.sessionsDir)
        self.metaReader = DesktopMetaReader(rootDir: p.desktopSessionsDir, now: options.now)
        self.identities = IdentityResolver(path: options.persist ? p.identitiesFile : nil, now: options.now)
        if options.codexEnabled {
            var co = CodexEngine.Options(paths: p, now: options.now, probe: options.codexProbe)
            co.linger = options.codexLinger
            co.maxThreads = options.codexMaxThreads
            co.dozeAfter = options.dozeAfter
            co.sleepAfter = options.sleepAfter
            self.codex = CodexEngine(options: co, identities: self.identities)
        } else {
            self.codex = nil
        }
        self.ledger = options.scanTokens
            ? TokenLedger(ledgerPath: options.persist ? p.ledgerFile : nil, now: options.now, queue: options.ledgerQueue)
            : nil
    }

    // MARK: - 对外

    /// 引擎正在跟踪的 sessionId（文件监听器用它过滤事件，不相干的文件事件直接忽略）。
    public var trackedSessionIds: Set<String> {
        var s = Set<String>()
        for st in buddies.values {
            if !st.sessionId.isEmpty { s.insert(st.sessionId) }
            if let m = st.meta { m.allCliSessionIds.forEach { if !$0.isEmpty { s.insert($0) } } }
        }
        return s
    }

    public func markSeen(key: String) {
        if let cx = codex, cx.owns(key: key) { cx.markSeen(key: key); return }
        buddies[key]?.unread = false
    }

    public func rerollAppearance(key: String) {
        if let cx = codex, cx.owns(key: key) { cx.rerollAppearance(key: key); return }
        guard let salt = identities.reroll(key: key) else { return }
        buddies[key]?.salt = salt
    }

    /// 立即把身份和 token 账本写盘（退出时调用）。
    public func flush() {
        identities.saveIfNeeded(force: true)
        ledger?.flush()
    }

    public func shutdown() {
        ledger?.cancel()          // 先叫后台扫描停下，再写盘（不用等它把大文件扫完）
        flush()
    }

    // MARK: - poll

    public func poll() -> Output {
        let now = options.now()
        pendingEvents = []
        wake = nil

        // 桌面元数据：限速重新列目录
        if metaRefreshHint || lastMetaRefreshAt == nil || now.timeIntervalSince(lastMetaRefreshAt!) >= options.listInterval {
            if !metaReader.refresh().isEmpty { metaVersion += 1 }
            lastMetaRefreshAt = now
            metaRefreshHint = false
        }

        // 登记表 → 存活的记录
        let scan = registry.scan(now: now)
        registryReadable = scan.directoryReadable
        registryFileCount = scan.fileCount
        if let t = scan.nextRetry { wakeAt(t) }
        let alive = aliveRecords(scan.records, now: now)

        reconcile(alive: alive, now: now)
        if firstPoll {
            bootstrapDormants(now: now)
            compressSeats()
        }
        for st in buddies.values where st.isLive { update(st, now: now) }
        maintainAway(now: now)
        // 下班工位的桌牌也要有 token 数
        for st in buddies.values where st.isDormant {
            st.meta = st.hostSessionId.flatMap { metaReader.meta(host: $0) } ?? st.meta
            updateTokenGroup(st)
        }
        pruneCaches(now: now)
        identities.saveIfNeeded()

        var snaps = buddies.values.map { snapshot($0, now: now) }
        var outEvents = pendingEvents
        if let cx = codex {
            // Codex 线程：工位要避开 Claude 会话占着的，反过来 `occupiedSeats()` 也会避开 Codex 的
            let out = cx.poll(occupied: Set(snaps.map { $0.seat }.filter { $0 >= 0 }))
            snaps += out.snapshots
            outEvents += out.events
            wakeAt(out.nextWake)
        }
        snaps.sort { ($0.seat, $0.key) < ($1.seat, $1.key) }
        firstPoll = false
        return Output(snapshots: snaps, events: outEvents, nextWake: wake, tokenVersion: ledger?.version ?? 0)
    }

    /// 按会话 id 累积的缓存要定期清理（会话来来去去，不清理会一直涨）：
    /// "没找到会话记录"的节流记录只管 2 秒，过了 10 秒的没用了；会话记录路径缓存只留还有 buddy 在用的会话。
    private func pruneCaches(now: Date) {
        if let l = lastCachePruneAt, now.timeIntervalSince(l) < 30 { return }
        lastCachePruneAt = now
        for (sid, t) in transcriptMissAt where now.timeIntervalSince(t) > 10 { transcriptMissAt[sid] = nil }
        if !transcriptPathCache.isEmpty {
            let live = trackedSessionIds
            for sid in Array(transcriptPathCache.keys) where !live.contains(sid) { transcriptPathCache[sid] = nil }
        }
    }

    private func wakeAt(_ t: Date?) {
        guard let t else { return }
        wake = min(wake ?? t, t)
    }

    private func emit(_ key: String, at: Date, _ kind: BuddyEvent.Kind) {
        pendingEvents.append(BuddyEvent(key: key, at: at, kind: kind))
    }

    // MARK: - 进程存活

    private func aliveRecords(_ records: [Int32: RegistryRecord], now: Date) -> [RegistryRecord] {
        var out: [RegistryRecord] = []
        for (pid, rec) in records {
            let sig = "\(rec.sessionId)|\(rec.procStartRaw ?? "")"
            var entry = livenessCache[pid]
            if entry == nil || entry!.sig != sig || now.timeIntervalSince(entry!.checkedAt) >= options.livenessInterval {
                // 只看进程，绝不因为时间戳旧就判死
                let st = options.probe.probe(pid: pid)
                entry = LivenessEntry(liveness: ProcessProbe.classify(st, procStart: rec.procStart), checkedAt: now, sig: sig)
                livenessCache[pid] = entry
            }
            wakeAt(entry!.checkedAt.addingTimeInterval(options.livenessInterval))
            if entry!.liveness == .alive { out.append(rec) }
        }
        for pid in Array(livenessCache.keys) where records[pid] == nil { livenessCache[pid] = nil }
        return out
    }

    // MARK: - 在场 / 离场

    private func occupiedSeats() -> Set<Int> {
        Set(buddies.values.map { $0.seat }.filter { $0 >= 0 }).union(codex?.seats ?? [])
    }

    private func reconcile(alive: [RegistryRecord], now: Date) {
        // 一个 buddy 只认最新的一条记录（同一个会话不会有两个活进程，万一有就取后启动的）
        var chosen: [String: RegistryRecord] = [:]
        for rec in alive.sorted(by: { ($0.startedAt ?? .distantPast, $0.pid) < ($1.startedAt ?? .distantPast, $1.pid) }) {
            let sig = IdentitySig(pid: rec.pid, sessionId: rec.sessionId, host: rec.hostSessionId, procStart: rec.procStart,
                                  metaVersion: metaVersion)
            if let c = resolvedKeys[rec.pid], c.sig == sig {
                chosen[c.key] = rec                                    // 身份相关的字段没变：沿用上次的归属
                continue
            }
            let m = identities.resolve(rec, metaLookup: { [metaReader] in metaReader.find(cliSessionId: $0) })
            resolvedKeys[rec.pid] = (sig, m.identity.key)
            chosen[m.identity.key] = rec
        }
        for pid in Array(resolvedKeys.keys) where !alive.contains(where: { $0.pid == pid }) { resolvedKeys[pid] = nil }

        for (key, rec) in chosen {
            let hostId = rec.hostSessionId ?? metaReader.find(cliSessionId: rec.sessionId)?.hostSessionId
            if let st = buddies[key] {
                switch st.lifecycle {
                case .live:
                    break
                case .pendingAway:
                    st.lifecycle = .live                              // 防抖期内回来了：什么都没发生
                case .away:
                    // 同一个身份回来了：走回原来的工位
                    st.lifecycle = .live
                    st.appearedAfterLaunch = true
                    st.phase = nil
                    st.resetSessionScope(newSessionId: rec.sessionId)
                    emit(key, at: now, .arrived(freshAfterLaunch: true))
                }
                if st.sessionId != rec.sessionId { st.resetSessionScope(newSessionId: rec.sessionId) }
                st.record = rec
                st.hostSessionId = hostId
            } else {
                let identity = identities.identity(forKey: key)
                let seat = firstPoll ? -1 : identities.assignSeat(forKey: key, occupied: occupiedSeats())
                let st = BuddyState(key: key, seat: seat, salt: identity?.salt ?? 0, sessionId: rec.sessionId,
                                    appearedAfterLaunch: !firstPoll, now: now)
                st.record = rec
                st.hostSessionId = hostId
                buddies[key] = st
                emit(key, at: now, .arrived(freshAfterLaunch: !firstPoll))
            }
        }

        // 记录没了 / 进程死了 / PID 被复用：先防抖 3 秒
        for st in buddies.values where chosen[st.key] == nil {
            switch st.lifecycle {
            case .live:
                st.lifecycle = .pendingAway(since: now)
                wakeAt(now.addingTimeInterval(options.awayDebounce))
            case .pendingAway(let since):
                if now.timeIntervalSince(since) >= options.awayDebounce {
                    confirmAway(st, since: since, now: now)
                } else {
                    wakeAt(since.addingTimeInterval(options.awayDebounce))
                }
            case .away:
                break
            }
        }
    }

    private func confirmAway(_ st: BuddyState, since: Date, now: Date) {
        // 桌面会话，而且它的元数据还在、没有归档 → 下班工位
        var dormant = false
        if let host = st.hostSessionId, let m = metaReader.meta(host: host), !m.isArchived { dormant = true }
        st.lifecycle = .away(since: since, dormant: dormant, removeAt: dormant ? nil : now.addingTimeInterval(options.awayLinger))
        emit(st.key, at: now, .departed(dormant: dormant))
        if !dormant { wakeAt(now.addingTimeInterval(options.awayLinger)) }
        // 释放读取器
        st.hookReader = nil; st.transcript = nil; st.helpers = nil; st.inbox = []
        st.tracker = ToolTracker()
        st.attention = nil
        st.activity = .idle
        st.activitySince = now
        st.quiet = false
        st.turnStartedAt = nil
        st.pendingEnd = nil
        st.phase = .idle
        if dormant { st.idleSince = since }
    }

    /// 维护下班工位：满 12 小时 / 归档 / 被删除时移除；最多 4 个，超出时先移走最久没活动的；非下班工位到点收回。
    private func maintainAway(now: Date) {
        var dormants: [(BuddyState, Date)] = []
        for st in Array(buddies.values) {
            guard case .away(let since, let dormant, let removeAt) = st.lifecycle else { continue }
            if !dormant {
                if let r = removeAt {
                    if now >= r { remove(st) } else { wakeAt(r) }
                }
                continue
            }
            let meta = st.hostSessionId.flatMap { metaReader.meta(host: $0) }
            if meta == nil || meta!.isArchived || now.timeIntervalSince(since) >= options.dormantExpire {
                remove(st); continue
            }
            wakeAt(since.addingTimeInterval(options.dormantExpire))
            dormants.append((st, max(since, meta?.lastActivityAt ?? since)))
        }
        if dormants.count > options.dormantMax {
            for (st, _) in dormants.sorted(by: { $0.1 > $1.1 }).dropFirst(options.dormantMax) { remove(st) }
        }
    }

    private func remove(_ st: BuddyState) {
        buddies[st.key] = nil
        ledger?.removeGroup(key: st.key)
    }

    /// App 启动时：`lastActivityAt` 在 3 小时以内、没归档、当前没有活进程的桌面会话 → 下班工位。
    private func bootstrapDormants(now: Date) {
        let liveHosts = Set(buddies.values.compactMap { $0.hostSessionId })
        let cands = metaReader.all
            .filter { !$0.isArchived && !liveHosts.contains($0.hostSessionId)
                && now.timeIntervalSince($0.lastActivityAt ?? .distantPast) <= options.dormantRecent }
            .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
            .prefix(options.dormantMax)
        for m in cands {
            let match = identities.desktopIdentity(host: m.hostSessionId, cliSessionIds: m.allCliSessionIds)
            let key = match.identity.key
            guard buddies[key] == nil else { continue }
            let st = BuddyState(key: key, seat: -1, salt: match.identity.salt, sessionId: m.cliSessionId ?? "",
                                appearedAfterLaunch: false, now: now)
            st.hostSessionId = m.hostSessionId
            st.meta = m
            st.lifecycle = .away(since: m.lastActivityAt ?? now, dormant: true, removeAt: nil)
            st.phase = .idle
            st.idleSince = m.lastActivityAt
            buddies[key] = st
        }
    }

    /// 启动时压缩工位：按上次的工位顺序排好，重新从 0 起依次编号（运行中工位永远不动）。
    private func compressSeats() {
        let ordered = buddies.values.sorted { a, b in
            let sa = identities.identity(forKey: a.key)?.seat ?? -1, sb = identities.identity(forKey: b.key)?.seat ?? -1
            let ka = sa >= 0 ? sa : Int.max, kb = sb >= 0 ? sb : Int.max
            if ka != kb { return ka < kb }
            let ta = a.record?.startedAt ?? a.meta?.createdAt ?? .distantPast
            let tb = b.record?.startedAt ?? b.meta?.createdAt ?? .distantPast
            if ta != tb { return ta < tb }
            return a.key < b.key
        }
        for (i, st) in ordered.enumerated() {
            st.seat = i
            identities.setSeat(i, forKey: st.key)
        }
    }

    // MARK: - 每个在场 buddy 的更新

    private func update(_ st: BuddyState, now: Date) {
        guard st.record != nil else { return }
        st.meta = st.hostSessionId.flatMap { metaReader.meta(host: $0) }
        if firstPoll || now.timeIntervalSince(st.lastTouchAt ?? .distantPast) > 600 {
            identities.touch(key: st.key); st.lastTouchAt = now
        }

        var growth = false
        let justOpened = openReaders(st, now: now)

        // 增量读取
        if let h = st.hookReader, !justOpened.hook {
            let r = h.poll()
            if r.reset { resetHookState(st) }
            if ingestHook(st, r.events, incremental: true) { growth = true }
        }
        if let t = st.transcript, !justOpened.transcript {
            if t.poll() { growth = true }
        }
        if let hp = st.helpers {
            let busyish = st.phase != .idle || hp.hasActive(now: now) || !st.tracker.open.isEmpty
            let every = busyish ? options.helperListInterval : options.helperListIdleInterval
            let due = st.lastHelperListAt.map { now.timeIntervalSince($0) >= every } ?? true
            if due { st.lastHelperListAt = now }
            if hp.poll(now: now, list: due) && !justOpened.transcript { growth = true }
        }
        if growth {
            st.lastGrowthAt = now
            ledger?.poke()
        }
        refreshCustomTitleFile(st, now: now)

        processInbox(st, now: now)
        // 会话记录里出现 stop_hook_summary：一轮结束 → 主线程不可能还有开着的调用
        if let sh = st.transcript?.facts.stopHookSummaryAt, sh != st.lastStopMarkerSeen {
            st.lastStopMarkerSeen = sh
            st.tracker.turnBoundary(at: sh)
        }
        st.attributor.prune(now: now)
        st.tracker.expireStale(now: now, registryIdle: st.record?.status == .idle)

        // 信号 → 阶段 → 轮次 → 动作
        var sig = buildSignals(st, now: now)
        let phase = ActivityResolver.effectivePhase(sig, now: now)
        transition(st, to: phase, signals: sig, now: now)
        finalizePendingEnd(st, signals: sig, now: now)
        sig.idleSince = st.idleSince
        sig.turnEnd = st.turnEnd
        let res = ActivityResolver.evaluate(sig, now: now)
        wakeAt(res.nextChange)
        applyActivity(st, res.activity, signals: sig, now: now)

        // 叠加标记
        updateOverlays(st, phase: phase, now: now)
        st.quiet = phase == .busy && now.timeIntervalSince(st.lastGrowthAt) >= options.quietAfter
        // 只在「还没 quiet」时登记「变 quiet 的那一刻」：quiet 之后这个时间永远在过去，登记了 `SessionStore.arm` 就每 5 ms 空转一次（R1a-01）
        if phase == .busy && !st.quiet { wakeAt(st.lastGrowthAt.addingTimeInterval(options.quietAfter)) }

        updateTokenGroup(st)
    }

    // MARK: 读取器

    /// 打开（或补开）这个会话的读取器。返回这次是不是刚刚打开（刚打开的已经读过一遍尾部窗口）。
    private func openReaders(_ st: BuddyState, now: Date) -> (hook: Bool, transcript: Bool) {
        var opened = (hook: false, transcript: false)
        if st.hookReader == nil, let path = options.paths.hookLogPath(sessionId: st.sessionId) {
            let r = HookLogReader(path: path)
            st.hookReader = r
            let res = r.bootstrap(tailWindow: options.hookTailWindow)
            _ = ingestHook(st, res.events, incremental: false)
            opened.hook = true
        }
        if st.transcript == nil, st.lastLocateAt.map({ now.timeIntervalSince($0) >= 1.0 }) ?? true {
            st.lastLocateAt = now
            if let path = locateTranscript(sessionId: st.sessionId) {
                let r = TranscriptReader(path: path, clock: options.now)
                r.bootstrap(tailWindow: options.transcriptTailWindow)
                st.transcript = r
                st.transcriptPath = path
                let hp = SubagentReader(sessionDir: TranscriptLocator.sessionDir(forTranscript: path), clock: options.now)
                hp.poll(now: now, list: true)
                st.helpers = hp
                st.lastHelperListAt = now
                st.lastGrowthAt = initialGrowth(st, now: now)
                opened.transcript = true
            }
        }
        return opened
    }

    private func locateTranscript(sessionId: String) -> String? {
        if let p = transcriptPathCache[sessionId] { return p }
        let now = options.now()
        if let miss = transcriptMissAt[sessionId], now.timeIntervalSince(miss) < 2 { return nil }
        guard let p = TranscriptLocator.find(sessionId: sessionId, projectsDir: options.paths.projectsDir) else {
            transcriptMissAt[sessionId] = now
            return nil
        }
        transcriptMissAt[sessionId] = nil
        transcriptPathCache[sessionId] = p
        return p
    }

    /// 刚打开时，"最近一次增长"取文件里最新的时间戳（hook 事件 / 会话记录），没有就用现在。
    private func initialGrowth(_ st: BuddyState, now: Date) -> Date {
        var c: [Date] = []
        if let t = st.lastHookEventAt { c.append(t) }
        if let t = st.transcript?.facts.lastLineAt { c.append(t) }
        return min(c.max() ?? now, now)
    }

    private func resetHookState(_ st: BuddyState) {
        st.inbox = []
        st.tracker.reset()
        st.hookMaxTs = nil
        st.lastPromptAt = nil; st.lastStopAt = nil
        st.preCompactAt = nil; st.postCompactAt = nil
        st.notificationText = nil; st.notificationAt = nil
    }

    /// 新 hook 事件入队。返回有没有新事件。
    private func ingestHook(_ st: BuddyState, _ rawEvents: [HookEvent], incremental: Bool) -> Bool {
        guard !rawEvents.isEmpty else { return false }
        // 时间戳比现在晚一天以上的事件（时钟被拨快过 / 坏数据）按"现在"算：
        // 一条远在未来的 Stop 会让登记表明明是 busy 的会话永远被当成 idle，一条未来的事件还会让归属扣留一直扣下去
        let now = options.now()
        let cap = now.addingTimeInterval(86400)
        let events = rawEvents.map { e -> HookEvent in
            guard e.ts > cap else { return e }
            var x = e; x.ts = now; return x
        }
        st.inbox.append(contentsOf: events)
        st.hookEventsSeen += events.count
        for e in events {
            st.hookMaxTs = max(st.hookMaxTs ?? e.ts, e.ts)
            st.lastHookEventAt = max(st.lastHookEventAt ?? e.ts, e.ts)
        }
        return incremental
    }

    private func refreshCustomTitleFile(_ st: BuddyState, now: Date) {
        guard let path = st.transcriptPath else { return }
        if let last = st.lastTitleCheckAt, now.timeIntervalSince(last) < 3 { return }
        st.lastTitleCheckAt = now
        let file = TranscriptLocator.sessionDir(forTranscript: path) + "/custom-title.json"
        guard let stt = FileIO.stat(file) else { st.customTitleFileTitle = nil; st.customTitleSig = nil; return }
        if st.customTitleSig == stt { return }
        st.customTitleSig = stt
        if let data = FileIO.readAll(file, maxBytes: 1 << 16),
           let obj = SafeJSON.object(data),
           let t = SafeJSON.string(obj["customTitle"]), !t.isEmpty {
            st.customTitleFileTitle = t
        }
    }

    // MARK: hook 事件 → ToolTracker

    /// hook 在不在工作：当前会话有 `ts ≥ startedAt − 5s` 的事件。
    /// 另外，如果 hook 已经安静了很久、会话记录却一直在增长（用户中途卸掉了 ccmon），就当作 hook 掉线，
    /// 退回用会话记录判断工具（不能崩，也不能一直显示"思考中"）。
    static let hookDropoutGap: TimeInterval = 15

    private func hookActive(_ st: BuddyState) -> Bool {
        guard let maxTs = st.hookMaxTs else { return false }
        if let started = st.record?.startedAt, maxTs < started.addingTimeInterval(-5) { return false }
        if let last = st.transcript?.facts.lastLineAt, last.timeIntervalSince(maxTs) > SessionEngine.hookDropoutGap { return false }
        return true
    }

    private func processInbox(_ st: BuddyState, now: Date) {
        while let ev = st.inbox.first {
            switch ev.ev {
            case HookEvent.pre:
                let ctx = attributionContext(st, at: ev.ts, now: now)
                let d = st.attributor.decide(event: ev, context: ctx, now: now)
                if case .hold(let until) = d { wakeAt(until); return }     // 先扣住（≤ 400 ms）
                st.tracker.pre(name: ev.tool, truncated: ev.toolTruncated, detail: ev.detail, at: ev.ts,
                               owner: d == .helper ? .helper : .main)
            case HookEvent.post:
                st.tracker.post(name: ev.tool, truncated: ev.toolTruncated, detail: ev.detail, at: ev.ts)
            case HookEvent.stop:
                st.lastStopAt = ev.ts
                st.tracker.turnBoundary(at: ev.ts)
            case HookEvent.prompt:
                st.lastPromptAt = ev.ts
                st.tracker.turnBoundary(at: ev.ts)
            case HookEvent.sessionStart:
                st.tracker.turnBoundary(at: ev.ts)
                if ev.extra == "compact" { st.postCompactAt = ev.ts }     // 压缩完成后的 SessionStart 相当于 PostCompact
            case HookEvent.sessionEnd:
                st.tracker.turnBoundary(at: ev.ts)
            case HookEvent.notification:
                st.notificationText = ev.extra
                st.notificationAt = ev.ts
            case HookEvent.preCompact:
                st.preCompactAt = ev.ts
            case HookEvent.postCompact:
                st.postCompactAt = ev.ts
            case HookEvent.subagentStop:
                // 大多是桌面 App 生成"本轮总结"的内部代理，不代表小助手做完了；只当作"总结已生成"的提示：
                // 让下一次 poll 马上重读桌面元数据（postTurnSummary 大概刚写好）
                st.summaryHintAt = ev.ts
                metaRefreshHint = true
            default:
                break
            }
            st.inbox.removeFirst()
        }
    }

    private func attributionContext(_ st: BuddyState, at ts: Date, now: Date) -> HelperAttributor.Context {
        var s = baseSignals(st)
        s.openTools = []
        let mainIdle = ActivityResolver.effectivePhase(s, now: ts) == .idle
        let fg = st.tracker.mainOpen
            .filter { $0.call.name == "Agent" || $0.call.name == "Task" }
            .map { $0.call.startedAt }.max()
        let hasBg = st.helpers?.hasActiveBackground(now: now) ?? false
        let helperUses = (st.helpers?.recentToolUses ?? []).map {
            HelperAttributor.ToolUseRecord(id: $0.use.id, name: $0.use.name, key: $0.use.key, at: $0.use.at)
        }
        let mainUses = (st.transcript?.facts.recentToolUses ?? []).map {
            HelperAttributor.ToolUseRecord(id: $0.id, name: $0.name, key: $0.key, at: $0.at)
        }
        return HelperAttributor.Context(mainIdle: mainIdle, foregroundAgentOpenSince: fg,
                                        hasActiveBackgroundHelper: hasBg, helperUses: helperUses, mainUses: mainUses)
    }

    // MARK: 信号

    private func baseSignals(_ st: BuddyState) -> SessionSignals {
        var s = SessionSignals()
        s.registryStatus = st.record?.status
        s.statusUpdatedAt = st.record?.statusUpdatedAt
        s.waitingFor = st.record?.waitingFor
        s.hookActive = hookActive(st)
        s.lastPromptAt = st.lastPromptAt
        s.lastStopAt = st.lastStopAt
        s.preCompactAt = st.preCompactAt
        s.postCompactAt = st.postCompactAt
        s.notificationText = st.notificationText
        s.notificationAt = st.notificationAt
        s.dozeAfter = options.dozeAfter
        s.sleepAfter = options.sleepAfter
        return s
    }

    private func buildSignals(_ st: BuddyState, now: Date) -> SessionSignals {
        var s = baseSignals(st)
        if s.hookActive {
            s.openTools = st.tracker.mainOpen.map { $0.call }
        } else if let f = st.transcript?.facts {
            // 没有 hook：退回用会话记录里"没有结果的 tool_use"判断工具
            let since = f.lastPromptAt ?? .distantPast
            s.openTools = f.openToolUses.filter { $0.at >= since }
                .map { ToolCatalog.makeCall(name: $0.name, detail: $0.key, at: $0.at) }
        }
        if let f = st.transcript?.facts {
            s.apiError = f.apiError
            s.lastAssistantOrUserAt = f.lastAssistantOrUserAt
            s.compactBoundaryAt = f.compactBoundaryAt
        }
        return s
    }

    // MARK: 轮次

    private func transition(_ st: BuddyState, to newPhase: Phase, signals sig: SessionSignals, now: Date) {
        guard let old = st.phase else {
            initialState(st, phase: newPhase, signals: sig, now: now)
            st.phase = newPhase
            return
        }
        if newPhase == old { return }
        if old == .idle {
            // 新一轮开始
            if st.pendingEnd != nil { forceFinishPendingEnd(st, signals: sig, now: now) }
            st.turnStartedAt = estimateTurnStart(st, signals: sig, now: now)
            st.idleSince = nil
            st.unread = false
            st.blocked = false
            st.statusDetail = nil
            st.suppressedSummaryFor = st.meta?.postTurnSummaryFor
            emit(st.key, at: st.turnStartedAt ?? now, .turnStarted)
        } else if newPhase == .idle {
            // 一轮结束（等一小会儿再判定是正常做完、被打断还是出错）
            st.tracker.turnBoundary(at: now)
            let ended = endedAt(st, signals: sig, now: now)
            st.idleSince = ended
            st.lastTurnEndedAt = ended
            st.lastTurnDuration = max(0, ended.timeIntervalSince(st.turnStartedAt ?? ended))
            st.pendingEnd = BuddyState.PendingEnd(endedAt: ended, startedAt: st.turnStartedAt)
            st.turnStartedAt = nil
            // 证据还不够时（宽限期内：还没有 Stop / 打断标记 / 错误行）先不说这一轮是怎么结束的：
            // 不能先报「做完了」再改口成「被打断」/「出错」——提醒（AlertCoordinator）看到 .finished 就会发「做完了」。
            // 证据够了会在同一次 update 里由 finalizePendingEnd → complete() 立刻定下来；宽限期满还没有证据也会定下来。
            st.turnEnd = .none
        }
        // busy ↔ waiting：还在同一轮里
        st.phase = newPhase
    }

    private func endedAt(_ st: BuddyState, signals sig: SessionSignals, now: Date) -> Date {
        if sig.registryStatus == .idle, let t = sig.statusUpdatedAt, t <= now { return t }
        if let s = sig.lastStopAt, s <= now { return s }
        return now
    }

    private func initialState(_ st: BuddyState, phase: Phase, signals sig: SessionSignals, now: Date) {
        switch phase {
        case .idle:
            let ended = endedAt(st, signals: sig, now: now)
            st.idleSince = ended
            // 只有确有"一轮刚结束"的证据才算（否则刚进场的新会话会误显示"做完了"）
            if hasTurnEndEvidence(st, signals: sig, endedAt: ended) {
                st.lastTurnEndedAt = ended
                st.turnEnd = classify(st, signals: sig, endedAt: ended, startedAt: nil, now: now, force: true) ?? .finished
            } else {
                st.turnEnd = .none
            }
            if let m = st.meta {
                st.blocked = m.isBlocked
                st.statusDetail = m.summaryIsCurrent ? m.postTurnSummary?.statusDetail : nil
            }
        case .busy, .waiting:
            st.turnStartedAt = estimateTurnStart(st, signals: sig, now: now)
        }
    }

    /// 第一次看见一个 idle 的会话时：这一刻附近有没有"一轮刚结束"的证据（Stop 事件、stop_hook_summary、打断、出错）。
    private func hasTurnEndEvidence(_ st: BuddyState, signals sig: SessionSignals, endedAt: Date) -> Bool {
        let f = st.transcript?.facts
        let near = endedAt.addingTimeInterval(-2)
        if let m = [sig.lastStopAt, f?.stopHookSummaryAt].compactMap({ $0 }).max(), m >= near { return true }
        if let i = f?.interruptAt, i >= near { return true }
        if let f {
            if let e = f.apiError, e.max > 0, e.attempt >= e.max, e.at >= near { return true }
            if let s = f.syntheticErrorAt, s >= near { return true }
            if let e = f.endTurnAt, e >= near { return true }
        }
        return false
    }

    /// 本轮开始时间：取"人的输入"和"登记表变 busy"里最早的那个（都必须比上一轮结束的证据晚）。
    private func estimateTurnStart(_ st: BuddyState, signals sig: SessionSignals, now: Date) -> Date {
        let f = st.transcript?.facts
        let boundary = [sig.lastStopAt, f?.stopHookSummaryAt, f?.endTurnAt].compactMap { $0 }.max()
        var c: [Date] = []
        if let p = sig.lastPromptAt, p <= now, boundary.map({ p > $0 }) ?? true { c.append(p) }
        if let p = f?.lastPromptAt, p <= now, boundary.map({ p > $0 }) ?? true { c.append(p) }
        if sig.registryStatus == .busy, let su = sig.statusUpdatedAt, su <= now, su >= (st.idleSince ?? .distantPast) {
            c.append(su)
        }
        return c.min() ?? now
    }

    /// 判定一轮是怎么结束的。返回 nil = 证据还不够，再等等（宽限期内）。
    private func classify(_ st: BuddyState, signals sig: SessionSignals, endedAt: Date, startedAt: Date?,
                          now: Date, force: Bool) -> TurnEndKind? {
        let f = st.transcript?.facts
        let ts0 = startedAt ?? [sig.lastPromptAt, f?.lastPromptAt].compactMap { $0 }.max() ?? .distantPast
        let floor = ts0.addingTimeInterval(-0.5)
        let stopMarker = [sig.lastStopAt, f?.stopHookSummaryAt].compactMap { $0 }.max()

        // 被打断：会话记录里出现打断，且比上一次轮次结束更晚
        if let i = f?.interruptAt, i >= floor, i > (stopMarker ?? .distantPast) { return .interrupted }
        // 出错：重试到上限（之后没有新行），或最后一条 assistant 是合成的 API 错误
        if let f {
            if let e = f.apiError, e.max > 0, e.attempt >= e.max, e.at >= floor,
               (f.lastAssistantOrUserAt ?? .distantPast) <= e.at { return .errored }
            if let s = f.syntheticErrorAt, s >= floor, s == f.lastAssistantAt { return .errored }
        }
        // 正常结束的证据：这一轮结束时刻附近有 Stop 事件 / stop_hook_summary
        if let m = stopMarker, m >= endedAt.addingTimeInterval(-2), m >= floor { return .finished }
        // 宽限期过了还没有 Stop：hook 正常工作 → 被打断；没有 hook 就没法判断，当作做完了
        if force || now >= endedAt.addingTimeInterval(options.stopGrace) {
            return sig.hookActive ? .interrupted : .finished
        }
        return nil
    }

    private func finalizePendingEnd(_ st: BuddyState, signals sig: SessionSignals, now: Date) {
        guard let pe = st.pendingEnd else { return }
        if let kind = classify(st, signals: sig, endedAt: pe.endedAt, startedAt: pe.startedAt, now: now, force: false) {
            complete(st, kind: kind, endedAt: pe.endedAt)
        } else {
            wakeAt(pe.endedAt.addingTimeInterval(options.stopGrace))
        }
    }

    private func forceFinishPendingEnd(_ st: BuddyState, signals sig: SessionSignals, now: Date) {
        guard let pe = st.pendingEnd else { return }
        let kind = classify(st, signals: sig, endedAt: pe.endedAt, startedAt: pe.startedAt, now: now, force: true) ?? .finished
        complete(st, kind: kind, endedAt: pe.endedAt)
    }

    private func complete(_ st: BuddyState, kind: TurnEndKind, endedAt: Date) {
        st.turnEnd = kind
        st.pendingEnd = nil
        // 终端会话的 turn_duration 更准
        if let f = st.transcript?.facts, let at = f.turnDurationAt, let ms = f.turnDurationMs,
           abs(at.timeIntervalSince(endedAt)) < 5 {
            st.lastTurnDuration = ms / 1000
        }
        if kind != .interrupted { st.unread = true }                 // 一轮做完后亮起（被自己打断的不算）
        emit(st.key, at: endedAt, .turnFinished(duration: st.lastTurnDuration, interrupted: kind == .interrupted,
                                                errored: kind == .errored))
    }

    // MARK: 动作与叠加标记

    private func applyActivity(_ st: BuddyState, _ activity: Activity, signals sig: SessionSignals, now: Date) {
        if activity != st.activity {
            st.activity = activity
            st.activitySince = since(for: activity, st: st, signals: sig, now: now)
        }
        // 一次性事件：开始等你 / 不再等你
        let kind = attentionKind(activity)
        switch (kind, st.attention) {
        case let (k?, nil):
            emit(st.key, at: st.activitySince, .needsUser(k))
        case (nil, .some):
            emit(st.key, at: now, .needsUserCleared)
        case let (k?, old?) where !k.sameCase(as: old):
            emit(st.key, at: st.activitySince, .needsUser(k))
        default:
            break
        }
        st.attention = kind
    }

    private func attentionKind(_ a: Activity) -> AttentionKind? {
        switch a {
        case .waitingApproval(let t): return .approval(t)
        case .asking: return .question
        case .planReview: return .planReview
        case .waitingOther(let s): return .other(s)
        default: return nil
        }
    }

    /// 一个动作"从什么时候开始"：尽量用有精确时间的信号，这样 App 中途启动时也对得上。
    private func since(for a: Activity, st: BuddyState, signals sig: SessionSignals, now: Date) -> Date {
        func clamp(_ d: Date?) -> Date { min(d ?? now, now) }
        switch a {
        case .tool(let c, _): return clamp(c.startedAt)
        case .waitingApproval, .asking, .planReview, .waitingOther:
            return clamp(sig.statusUpdatedAt ?? st.turnStartedAt)
        case .compacting: return clamp(sig.preCompactAt ?? sig.compactBoundaryAt)
        case .retrying: return clamp(sig.apiError?.at)
        case .interrupted, .finished, .errored, .idle: return clamp(st.idleSince)
        case .dozing: return clamp(st.idleSince?.addingTimeInterval(options.dozeAfter))
        case .sleeping: return clamp(st.idleSince?.addingTimeInterval(options.sleepAfter))
        case .thinking:
            if st.activity.phase == .busy { return now }
            return clamp(st.turnStartedAt)
        }
    }

    private func updateOverlays(_ st: BuddyState, phase: Phase, now: Date) {
        // 未读：跳转到这个会话 / 桌面 lastFocusedAt 晚于这一轮结束 / 下一轮开始时清掉
        if st.unread, let f = st.meta?.lastFocusedAt, let e = st.lastTurnEndedAt, f > e { st.unread = false }
        // 桌面 postTurnSummary：blocked = "做完了但需要你处理"，保持到下一轮开始
        var blockedNow = false
        var detail: String?
        if phase == .idle, let m = st.meta, m.summaryIsCurrent, m.postTurnSummaryFor != st.suppressedSummaryFor {
            blockedNow = m.isBlocked
            detail = m.postTurnSummary?.statusDetail
        }
        if blockedNow && !st.blocked { emit(st.key, at: now, .blocked) }
        st.blocked = blockedNow
        st.statusDetail = detail
    }

    // MARK: token

    private func updateTokenGroup(_ st: BuddyState) {
        guard let ledger else { return }
        // 只有会话 / 元数据 / 子代理文件个数变了才需要重新算文件集合
        let gate = "\(st.sessionId)|\(st.meta?.cliSessionId ?? "")|\(st.meta?.priorCliSessionIds.count ?? 0)|\(st.helpers?.jsonlPaths.count ?? 0)|\(st.transcriptPath ?? "")"
        if gate == st.tokenGate { return }
        // 桌面会话：cliSessionId 和 priorCliSessionIds 对应的会话记录加在一起；终端会话只算当前的 sessionId
        var sids = [st.sessionId]
        if let m = st.meta {
            sids = m.allCliSessionIds
            if !sids.contains(st.sessionId) && !st.sessionId.isEmpty { sids.append(st.sessionId) }
        }
        var transcripts: [String] = []
        var helperPaths: [String] = []
        for sid in sids where !sid.isEmpty {
            guard let p = locateTranscript(sessionId: sid) else { continue }
            transcripts.append(p)
            if sid == st.sessionId, let hp = st.helpers {
                helperPaths.append(contentsOf: hp.jsonlPaths)
            } else {
                helperPaths.append(contentsOf: SubagentReader.listJSONL(sessionDir: TranscriptLocator.sessionDir(forTranscript: p)))
            }
        }
        let sig = (transcripts + ["|"] + helperPaths).joined(separator: "\n")
        if sig != st.tokenGroupSig {
            st.tokenGroupSig = sig
            ledger.setGroup(key: st.key, transcripts: transcripts, helpers: helperPaths)
        }
        // 会话记录文件还没找到（新会话刚开始）时不要锁死，下一次 poll 继续找
        if transcripts.count == sids.filter({ !$0.isEmpty }).count { st.tokenGate = gate }
    }

    // MARK: - 快照

    private func title(_ st: BuddyState) -> String {
        // 标题优先级：登记表的 name → 桌面的 title → custom-title → ai-title → cwd 文件夹名 → "会话 <sid 前 8 位>"
        if let n = st.record?.name { return n }
        if let t = st.meta?.title { return t }
        if let t = st.transcript?.facts.customTitle ?? st.customTitleFileTitle { return t }
        if let t = st.transcript?.facts.aiTitle { return t }
        let cwd = st.record?.cwd ?? st.meta?.cwd
        if let cwd, !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            if !last.isEmpty && last != "/" { return last }
        }
        return "会话 " + String(st.sessionId.prefix(8))
    }

    static func modelFamily(_ model: String?) -> ModelFamily {
        guard let m = model?.lowercased(), !m.isEmpty else { return .claude }
        if m.hasPrefix("claude") { return .claude }
        if m.hasPrefix("deepseek") { return .deepseek }
        if m.hasPrefix("glm") { return .glm }
        return .other
    }

    private func snapshot(_ st: BuddyState, now: Date) -> BuddySnapshot {
        var s = BuddySnapshot(key: st.key, seat: st.seat, salt: st.salt, title: title(st), sessionId: st.sessionId,
                              origin: st.record?.origin ?? .desktop, activity: st.activity, now: st.activitySince)
        let facts = st.transcript?.facts
        s.cwd = st.record?.cwd ?? st.meta?.cwd
        let model = facts?.model ?? st.meta?.model
        s.modelName = model
        s.modelFamily = SessionEngine.modelFamily(model)
        s.effort = st.meta?.effort ?? facts?.effort
        s.permissionMode = st.meta?.permissionMode ?? facts?.permissionMode
        s.cliVersion = st.record?.version
        s.hostSessionId = st.hostSessionId
        s.pid = st.record?.pid
        s.sessionStartedAt = st.record?.startedAt ?? st.meta?.createdAt
        switch st.lifecycle {
        case .live, .pendingAway: s.presence = .present
        case .away(let since, let dormant, _): s.presence = .away(since: since, dormant: dormant)
        }
        s.appearedAfterLaunch = st.appearedAfterLaunch
        s.phase = st.activity.phase
        s.turnStartedAt = st.turnStartedAt
        s.lastTurnDuration = st.lastTurnDuration
        s.lastTurnEndedAt = st.lastTurnEndedAt
        s.idleSince = st.idleSince
        s.unread = st.unread
        s.blocked = st.blocked
        s.statusDetail = st.statusDetail
        s.quiet = st.quiet
        s.helpers = st.isLive || st.isPendingAway ? (st.helpers?.snapshots(now: now) ?? []) : []
        if let ledger { s.tokens = ledger.totals(forKey: st.key).breakdown }
        s.contextTokens = facts?.contextTokens
        s.hookActive = hookActive(st)
        return s
    }

    // MARK: - 诊断

    public func diagnostics() -> DiagnosticsInfo {
        let now = options.now()
        var d = DiagnosticsInfo()
        let live = buddies.values.filter { $0.isLive || $0.isPendingAway }
        d.liveSessionCount = live.count
        if lastSettingsCheckAt == nil || now.timeIntervalSince(lastSettingsCheckAt!) > 30 {
            hookInSettings = SessionEngine.detectHookInSettings(path: options.paths.settingsFile)
            lastSettingsCheckAt = now
        }
        d.hookDetectedInSettings = hookInSettings ?? false
        d.lastHookEventAt = live.compactMap { $0.lastHookEventAt }.max()
        d.sessions = live.sorted { $0.seat < $1.seat }.map {
            DiagnosticsInfo.SessionDiag(key: $0.key, title: title($0), pid: $0.record?.pid, cliVersion: $0.record?.version,
                                        hookActive: hookActive($0), lastHookEventAt: $0.lastHookEventAt,
                                        origin: $0.record?.origin ?? .desktop)
        }
        let hookOK = live.filter { hookActive($0) }.count
        d.sourceStatus = [
            registryReadable ? "登记表: 正常（\(registryFileCount) 个文件）" : "登记表: 目录读不了",
            live.isEmpty ? "hook: 没有活会话" :
                (hookOK == live.count ? "hook: 正常（\(hookOK)/\(live.count) 个会话有事件）"
                 : (d.hookDetectedInSettings ? "hook: 部分会话没有事件（\(hookOK)/\(live.count)）" : "hook: 没检测到（settings.json 里没有注册 hook.sh），退回用会话记录判断工具")),
            live.allSatisfy({ $0.transcript != nil }) ? "会话记录: 正常" : "会话记录: 有 \(live.filter { $0.transcript == nil }.count) 个会话没找到文件",
            metaReader.directoryReadable ? "桌面元数据: 正常（\(metaReader.fileCount) 个）" : "桌面元数据: 不可用",
        ]
        if let l = ledger {
            let scanning = l.isScanning ? "，扫描中" : ""
            d.sourceStatus.append("token 统计: 正常\(scanning)")
            if l.persistenceOK == false { d.sourceStatus.append("token 账本: 写不了磁盘，只在内存里") }
        }
        if identities.persistenceOK == false { d.sourceStatus.append("身份: 写不了磁盘，只在内存里") }
        if let cx = codex {
            d.sourceStatus += cx.diagnosticLines()
            d.sessions += cx.diagnosticSessions()
            d.liveSessionCount += cx.liveCount
        } else {
            d.sourceStatus.append("Codex: 已在设置里关闭")
        }
        return d
    }

    static func detectHookInSettings(path: String) -> Bool {
        guard let data = FileIO.readAll(path, maxBytes: 4 << 20),
              let obj = SafeJSON.object(data),
              let hooks = obj["hooks"] as? [String: Any] else { return false }
        for (_, groups) in hooks {
            guard let arr = groups as? [Any] else { continue }
            for case let g as [String: Any] in arr {
                for case let h as [String: Any] in (g["hooks"] as? [Any]) ?? [] {
                    if let c = h["command"] as? String, c.contains("hook.sh") { return true }
                }
            }
        }
        return false
    }

    // MARK: - 测试 / 工具用的只读访问

    /// 内部缓存的大小（测试 / 诊断用）：会话记录路径缓存、"没找到"的记录、进程存活缓存、身份归属缓存。
    var cacheSizes: (transcriptPaths: Int, transcriptMisses: Int, liveness: Int, resolvedKeys: Int, buddies: Int) {
        (transcriptPathCache.count, transcriptMissAt.count, livenessCache.count, resolvedKeys.count, buddies.count)
    }

    /// 某个 buddy 当前的主线程工具调用（测试用）。
    func openMainTools(key: String) -> [OpenTool] { buddies[key]?.tracker.mainOpen ?? [] }
    func closedTools(key: String) -> [ClosedTool] { buddies[key]?.tracker.closed ?? [] }
    func debugState(key: String) -> BuddyState? { buddies[key] }
}

// MARK: - 调试 / dump 用的只读视图

/// `buddyctl dump` / `buddydump` 一行要的全部信息（含快照里没有的登记表原始字段）。
public struct BuddyDebugRow {
    public var snapshot: BuddySnapshot
    /// 登记表原始的 status / waitingFor / statusUpdatedAt。
    public var registryStatus: String?
    public var waitingFor: String?
    public var statusUpdatedAt: Date?
    /// alive / dead / reused / away / unknown
    public var liveness: String
    public var hookEventsSeen: Int
    public var lastHookEventAt: Date?
    public var hookDegradedLines: Int
    public var hookSkippedLines: Int
    public var openMainTools: [ToolCall]
    public var openHelperTools: [ToolCall]
    public var transcriptPath: String?
    public var lastTranscriptLineAt: Date?
    public var tokenMessages: Int
    public var tokenScanComplete: Bool
    public var helperFiles: Int
}

public extension SessionEngine {
    func debugRows() -> [BuddyDebugRow] {
        let now = options.now()
        return (buddies.values.map { st in
            let snap = snapshot(st, now: now)
            var liveness = "away"
            if st.isLive || st.isPendingAway, let pid = st.record?.pid {
                switch livenessCache[pid]?.liveness {
                case .alive?: liveness = st.isPendingAway ? "away?" : "alive"
                case .dead?: liveness = "dead"
                case .reused?: liveness = "reused"
                case nil: liveness = "unknown"
                }
            }
            let totals = ledger?.totals(forKey: st.key)
            return BuddyDebugRow(
                snapshot: snap,
                registryStatus: st.record?.statusRaw, waitingFor: st.record?.waitingFor,
                statusUpdatedAt: st.record?.statusUpdatedAt, liveness: liveness,
                hookEventsSeen: st.hookEventsSeen, lastHookEventAt: st.lastHookEventAt,
                hookDegradedLines: st.hookReader?.degradedLines ?? 0, hookSkippedLines: st.hookReader?.skippedLines ?? 0,
                openMainTools: st.tracker.mainOpen.map { $0.call }, openHelperTools: st.tracker.helperOpen.map { $0.call },
                transcriptPath: st.transcriptPath, lastTranscriptLineAt: st.transcript?.facts.lastLineAt,
                tokenMessages: totals?.messages ?? 0, tokenScanComplete: totals?.scannedAllFiles ?? true,
                helperFiles: st.helpers?.helperCount ?? 0)
        } + (codex?.debugRows() ?? [])).sorted { ($0.snapshot.seat, $0.snapshot.key) < ($1.snapshot.seat, $1.snapshot.key) }
    }
}
