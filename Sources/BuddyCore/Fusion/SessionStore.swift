import Foundation

/// 真实的数据提供者：把 `SessionEngine` 放到 ingest 串行队列（utility）上，配上文件监听和定时器，
/// 往外送 `[BuddySnapshot]`（最多每秒 20 次，另有每秒 1 次心跳）和一次性的 `BuddyEvent`。
///
/// - 文件监听：默认 FSEvents（监听 `~/.claude` 和 `claude-code-sessions`，事件按路径过滤）；
///   `usePolling` 或 FSEvents 起不来时退回纯轮询（`--poll`，测试和沙箱用）；
///   两种模式下都有兜底轮询：FSEvents 模式每秒一次，纯轮询模式默认每 50 ms 一次；
/// - 引擎给出 `nextWake`（"没有新信号时最早什么时候要再看一次"），定时器会在那一刻醒来，
///   所以打断 3 秒、做完 5 秒、防抖 3 秒这些时间点是准的，不用等心跳；
/// - token 统计在 tokenscan 后台队列里，有新结果时会 poke 一次；
/// - 回调都投递到 `callbackQueue`（默认主线程）。
public final class SessionStore: SnapshotProvider {
    public struct Options {
        public var engine: SessionEngine.Options
        /// 纯轮询（不用 FSEvents）。
        public var usePolling = false
        /// 纯轮询模式下的轮询间隔（有会话在忙时）；所有会话都空闲时退到 `idlePollInterval`；
        /// FSEvents 模式下的兜底间隔是 `fallbackInterval`。
        public var pollInterval: TimeInterval = 0.05
        public var idlePollInterval: TimeInterval = 0.1
        public var fallbackInterval: TimeInterval = 1.0
        /// 文件事件触发的 poll 之间至少隔这么久（几个忙会话同时写文件时，不至于每毫秒 poll 一次）。
        public var minPollSpacing: TimeInterval = 0.04
        /// 快照回调的最小间隔（20 Hz）与心跳间隔（1 Hz）。
        public var minEmitInterval: TimeInterval = 0.05
        public var heartbeatInterval: TimeInterval = 1.0
        public var callbackQueue: DispatchQueue = .main

        public init(engine: SessionEngine.Options) { self.engine = engine }
    }

    public var onUpdate: (([BuddySnapshot]) -> Void)?
    public var onEvent: ((BuddyEvent) -> Void)?

    public let options: Options
    private let queue = DispatchQueue(label: "buddy.ingest", qos: .utility)
    private var engine: SessionEngine?
    private var timer: DispatchSourceTimer?
    private var watcher: FileWatcher?
    private var running = false
    private var pokeScheduled = false
    private var lastSnapshots: [BuddySnapshot] = []
    private var dirty = false
    private var lastEmit = DispatchTime(uptimeNanoseconds: 0)
    private var lastPoll = DispatchTime(uptimeNanoseconds: 0)
    private var allIdle = false
    private var watchNote = "文件监听: 未启动"
    private var watchedPrefixes: (sessions: String, desktop: String, monitor: String, projects: String)?

    private let latestLock = NSLock()
    private var latestSnapshots: [BuddySnapshot] = []

    public init(options: Options) { self.options = options }

    /// App 用的便捷构造：`dataRoot` 为 nil 用真实的 home，否则换到一个假的 home 树（`--data-root`）。
    /// `usePolling` 对应 `--poll`。回调默认在主线程。
    public convenience init(dataRoot: String? = nil, usePolling: Bool = false, persist: Bool = true) {
        let paths = dataRoot.map { Paths(home: $0) } ?? .real
        var eo = SessionEngine.Options(paths: paths)
        eo.persist = persist
        var o = Options(engine: eo)
        o.usePolling = usePolling
        self.init(options: o)
    }

    // MARK: - SnapshotProvider

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let e = SessionEngine(options: options.engine)
            engine = e
            e.ledger?.onChange = { [weak self] in self?.poke() }
            startWatcher(e)
            tick()
        }
    }

    public func stop() {
        queue.sync { [self] in
            guard running else { return }
            running = false
            timer?.cancel(); timer = nil
            watcher?.stop(); watcher = nil
            engine?.shutdown()
        }
    }

    public func markSeen(key: String) {
        queue.async { [self] in engine?.markSeen(key: key); poke() }
    }

    public func rerollAppearance(key: String) {
        queue.async { [self] in engine?.rerollAppearance(key: key); poke() }
    }

    public func diagnostics() -> DiagnosticsInfo {
        queue.sync { [self] in
            var d = engine?.diagnostics() ?? DiagnosticsInfo()
            d.sourceStatus.insert(watchNote, at: 0)
            return d
        }
    }

    /// 最近一次算出来的快照（线程安全；测试和 replay 断言用）。
    public var currentSnapshots: [BuddySnapshot] {
        latestLock.lock(); defer { latestLock.unlock() }
        return latestSnapshots
    }

    /// 立即在 ingest 队列上 poll 一次并返回结果（测试用；不影响正常的定时轮询）。
    public func pollNow() -> SessionEngine.Output? {
        queue.sync { [self] in
            guard let e = engine else { return nil }
            let out = e.poll()
            process(out)
            return out
        }
    }

    /// dump 用的每个 buddy 的详细调试信息（含登记表原始字段）。
    public func debugRows() -> [BuddyDebugRow] {
        queue.sync { [self] in engine?.debugRows() ?? [] }
    }

    /// 等 token 后台扫描告一段落（dump --once 用）。
    public func waitForTokenScan(timeout: TimeInterval) {
        let ledger: TokenLedger? = queue.sync { engine?.ledger }
        _ = ledger?.waitUntilIdle(timeout: timeout)
    }

    // MARK: - 调度

    /// 有变化的提示：合并短时间内的多次提示，10 ms 后 poll 一次。
    public func poke() {
        queue.async { [self] in
            guard running, !pokeScheduled else { return }
            pokeScheduled = true
            // 合并短时间内的多次提示；两次 poll 之间至少隔 minPollSpacing
            let since = Double(DispatchTime.now().uptimeNanoseconds &- lastPoll.uptimeNanoseconds) / 1e9
            let delay = max(0.005, options.minPollSpacing - since)
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                pokeScheduled = false
                if running { tick() }
            }
        }
    }

    private func tick() {
        guard running, let e = engine else { return }
        lastPoll = DispatchTime.now()
        let out = e.poll()
        allIdle = out.snapshots.allSatisfy { $0.phase == .idle }
        process(out)
        arm(nextWake: out.nextWake)
    }

    private var baseInterval: TimeInterval {
        if options.usePolling || watcher == nil { return allIdle ? options.idlePollInterval : options.pollInterval }
        return options.fallbackInterval
    }

    private func arm(nextWake: Date?) {
        var delay = baseInterval
        if let w = nextWake {
            let d = w.timeIntervalSince(options.engine.now())
            delay = min(delay, max(0.005, d))
        }
        if dirty {   // 有改动在等着送出：到点（20 Hz 限速）就送
            let since = Double(DispatchTime.now().uptimeNanoseconds &- lastEmit.uptimeNanoseconds) / 1e9
            delay = min(delay, max(0.002, options.minEmitInterval - since))
        }
        let t = timer ?? DispatchSource.makeTimerSource(queue: queue)
        if timer == nil {
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
        t.schedule(deadline: .now() + delay, leeway: .milliseconds(1))
    }

    private func process(_ out: SessionEngine.Output) {
        if !out.events.isEmpty {
            let evs = out.events
            options.callbackQueue.async { [weak self] in
                guard let self, let cb = self.onEvent else { return }
                for e in evs { cb(e) }
            }
        }
        if out.snapshots != lastSnapshots {
            lastSnapshots = out.snapshots
            dirty = true
            latestLock.lock(); latestSnapshots = out.snapshots; latestLock.unlock()
        }
        let now = DispatchTime.now()
        let since = Double(now.uptimeNanoseconds &- lastEmit.uptimeNanoseconds) / 1e9
        if (dirty && since >= options.minEmitInterval) || (!dirty && since >= options.heartbeatInterval) {
            dirty = false
            lastEmit = now
            let snaps = lastSnapshots
            options.callbackQueue.async { [weak self] in self?.onUpdate?(snaps) }
        }
    }

    // MARK: - 文件监听

    private func startWatcher(_ e: SessionEngine) {
        let p = options.engine.paths
        watchedPrefixes = (FileWatcher.resolved(p.sessionsDir), FileWatcher.resolved(p.desktopSessionsDir),
                           FileWatcher.resolved(p.monitorDir), FileWatcher.resolved(p.projectsDir))
        if options.usePolling {
            watchNote = "文件监听: 纯轮询（每 \(Int(options.pollInterval * 1000)) ms）"
            return
        }
        let roots = [p.claudeDir, p.desktopSessionsDir].map { FileWatcher.resolved($0) }
        let w = FileWatcher(roots: roots, queue: queue, latency: 0.05) { [weak self] paths in self?.fsEvents(paths) }
        if w.start() {
            watcher = w
            watchNote = "文件监听: FSEvents（兜底每秒轮询）"
        } else {
            watchNote = "文件监听: FSEvents 不可用，改用纯轮询"
        }
    }

    /// 按路径前缀分流：sessions/、.monitor/、projects/、claude-code-sessions/，其余全部忽略。
    private func fsEvents(_ paths: [String]) {
        guard running, let pre = watchedPrefixes else { return }
        if SessionStore.shouldPoke(paths: paths, prefixes: pre, tracked: engine?.trackedSessionIds ?? []) { poke() }
    }

    /// 一批文件事件里有没有值得 poll 一次的（纯函数，方便测试）。
    /// - sessions/（登记表）和 claude-code-sessions/（桌面元数据）下的任何变化都算；
    /// - .monitor/ 和 projects/ 下只认正在跟踪的会话的文件（别的会话、Codex 的文件变化不用管），根目录本身变了也算；
    /// - 路径要按"目录边界"匹配：`~/.claude/sessions-old/…` 不是 sessions 目录下的东西。
    static func shouldPoke(paths: [String], prefixes pre: (sessions: String, desktop: String, monitor: String, projects: String),
                           tracked: Set<String>) -> Bool {
        func under(_ path: String, _ dir: String) -> Bool { path == dir || path.hasPrefix(dir.hasSuffix("/") ? dir : dir + "/") }
        for path in paths {
            if under(path, pre.sessions) || under(path, pre.desktop) { return true }
            if under(path, pre.monitor) || under(path, pre.projects) {
                if path == pre.monitor || path == pre.projects || tracked.contains(where: { !$0.isEmpty && path.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }
}
