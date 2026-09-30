import Foundation

/// 子代理（小助手）读取器：`<会话目录>/subagents/agent-<hex>.jsonl`（按 block 实时写入），
/// 旁边的 `.meta.json` 有 agentType / description / toolUseId / spawnDepth / requestShape。
/// 工作流的子代理在 `subagents/workflows/wf_*/agent-<hex>.jsonl`，也一并读。
///
/// - 子代理当前的工具 = 它最后一个还没有结果的 tool_use；
/// - 最后一条 assistant 是 end_turn 且没有未完成的工具 = 已完成；
/// - 最近 90 秒内有写入且还没完成 = 活跃。
public final class SubagentReader {
    public struct Meta: Sendable, Equatable {
        public var agentType: String?
        public var description: String?
        public var toolUseId: String?
        public var spawnDepth: Int?
        public var requestShape: String?
        public var workflowPhase: String?
        /// requestShape == "background" 才算后台；缺省（老版本）当作前台。
        public var isForeground: Bool { requestShape != "background" }
    }

    /// 活跃窗口：最近这么久有写入且没完成。
    public static let activeWindow: TimeInterval = 90
    /// 完成后还继续报告多久（给表现层留出"小助手离开"的时间）。
    public static let doneLinger: TimeInterval = 30
    /// 发现文件时，修改时间早于这么久（真实时钟）的直接当作早就结束了，不读内容。
    static let staleAtDiscovery: TimeInterval = 600

    final class Helper {
        let id: String
        let jsonlPath: String
        let metaPath: String
        var meta: Meta?
        var reader: TranscriptReader?
        var firstSeenAt: Date
        var lastGrowthAt: Date
        var sizeAtLastCheck: UInt64 = 0
        var doneObservedAt: Date?
        init(id: String, jsonlPath: String, metaPath: String, now: Date) {
            self.id = id; self.jsonlPath = jsonlPath; self.metaPath = metaPath
            self.firstSeenAt = now; self.lastGrowthAt = now
        }
    }

    public let sessionDir: String
    private let clock: (() -> Date)?
    private var helpers: [String: Helper] = [:]
    private var order: [String] = []
    public private(set) var lastListAt: Date?

    public init(sessionDir: String, clock: (() -> Date)? = nil) { self.sessionDir = sessionDir; self.clock = clock }

    /// 所有已发现的子代理会话记录路径（token 统计用，含已结束的）。
    public var jsonlPaths: [String] { order.compactMap { helpers[$0]?.jsonlPath } }

    /// 最近一次任何子代理文件增长的时间（判断"安静"用）。
    public var lastGrowthAt: Date? { helpers.values.map { $0.lastGrowthAt }.max() }

    /// 扫描目录并读增量。`list == true` 时重新列目录（发现新文件）。返回有没有变化。
    @discardableResult
    public func poll(now: Date, list: Bool) -> Bool {
        var changed = false
        if list || lastListAt == nil {
            lastListAt = now
            if discover(now: now) { changed = true }
        }
        for id in order {
            guard let h = helpers[id] else { continue }
            if h.meta == nil && list { loadMeta(h) }          // meta 文件可能一直不存在：只在列目录的节拍上重试，别每次 poll 都 open 一遍
            // 早就结束的（没读内容的旧文件 / 完成超过 60 秒的）只在列目录的节拍上看一眼，省掉每次 poll 对几十个文件的 stat
            let cold = h.reader == nil || (isDone(h) && now.timeIntervalSince(writeTime(h)) > 60)
            if cold && !list { continue }
            guard let r = h.reader else {
                // 之前因为太旧没读：文件长大了才读
                if let st = FileIO.stat(h.jsonlPath), st.size != h.sizeAtLastCheck {
                    let rd = TranscriptReader(path: h.jsonlPath, includeSidechain: true, clock: clock)
                    rd.bootstrap(tailWindow: 256 << 10)
                    h.reader = rd
                    h.sizeAtLastCheck = st.size
                    h.lastGrowthAt = now
                    changed = true
                }
                continue
            }
            if r.poll() { h.lastGrowthAt = now; changed = true }
        }
        return changed
    }

    /// 一个会话目录下所有放子代理记录的目录：`subagents/` 和 `subagents/workflows/wf_*/`。
    static func helperDirectories(sessionDir: String) -> [String] {
        var dirs = [sessionDir + "/subagents"]
        if let sub = FileIO.listDirectory(dirs[0]), sub.contains("workflows") {
            let wfDir = dirs[0] + "/workflows"
            if let wfs = FileIO.listDirectory(wfDir) { for wf in wfs.sorted() { dirs.append(wfDir + "/" + wf) } }
        }
        return dirs
    }

    /// 列出一个会话目录下所有子代理会话记录的路径（token 统计里给 prior 会话用，不读内容）。
    public static func listJSONL(sessionDir: String) -> [String] {
        var out: [String] = []
        for dir in helperDirectories(sessionDir: sessionDir) {
            for n in (FileIO.listDirectory(dir) ?? []).sorted() where n.hasPrefix("agent-") && n.hasSuffix(".jsonl") {
                out.append(dir + "/" + n)
            }
        }
        return out
    }

    private func discover(now: Date) -> Bool {
        var found = false
        for dir in SubagentReader.helperDirectories(sessionDir: sessionDir) {
            guard let names = FileIO.listDirectory(dir) else { continue }
            for n in names.sorted() where n.hasPrefix("agent-") && n.hasSuffix(".jsonl") {
                let id = String(n.dropLast(6))
                if helpers[id] != nil { continue }
                let jsonl = dir + "/" + n
                let h = Helper(id: id, jsonlPath: jsonl, metaPath: dir + "/" + id + ".meta.json", now: now)
                if let st = FileIO.stat(jsonl) {
                    h.sizeAtLastCheck = st.size
                    // 真实时钟下太旧的文件：早就结束了，不读内容（省启动时间）
                    if Date().timeIntervalSince(st.mtime) <= SubagentReader.staleAtDiscovery {
                        let rd = TranscriptReader(path: jsonl, includeSidechain: true, clock: clock)
                        rd.bootstrap(tailWindow: 256 << 10)
                        h.reader = rd
                    }
                }
                loadMeta(h)
                helpers[id] = h
                order.append(id)
                found = true
            }
        }
        return found
    }

    private func loadMeta(_ h: Helper) {
        guard let data = FileIO.readAll(h.metaPath, maxBytes: 1 << 20),
              let obj = SafeJSON.object(data) else { return }
        var m = Meta()
        m.agentType = SafeJSON.string(obj["agentType"], max: SafeJSON.maxIdLength)
        m.description = SafeJSON.string(obj["description"])
        m.toolUseId = SafeJSON.id(obj["toolUseId"])
        m.spawnDepth = (obj["spawnDepth"] as? NSNumber).flatMap { $0.doubleValue.isFinite && abs($0.doubleValue) < 1e6 ? $0.intValue : nil }
        m.requestShape = SafeJSON.string(obj["requestShape"], max: 64)
        m.workflowPhase = SafeJSON.string(obj["workflowPhase"], max: 64)
        h.meta = m
    }

    // MARK: - 状态

    private func writeTime(_ h: Helper) -> Date {
        h.reader?.facts.lastLineAt ?? h.lastGrowthAt
    }

    private func isDone(_ h: Helper) -> Bool {
        guard let r = h.reader else { return true }     // 没读内容的旧文件 = 早就结束了
        return r.facts.lastMessageWasEndTurn && r.facts.openToolUses.isEmpty
    }

    func isActive(_ h: Helper, now: Date) -> Bool {
        !isDone(h) && now.timeIntervalSince(writeTime(h)) <= SubagentReader.activeWindow
    }

    /// 有没有后台小助手正在活跃（归属规则第 3 条用）。
    public func hasActiveBackground(now: Date) -> Bool {
        helpers.values.contains { !($0.meta?.isForeground ?? true) && isActive($0, now: now) }
    }

    public func hasActive(now: Date) -> Bool {
        helpers.values.contains { isActive($0, now: now) }
    }

    /// 给表现层的快照：活跃的 + 刚完成不久的。
    public func snapshots(now: Date) -> [HelperSnapshot] {
        var out: [HelperSnapshot] = []
        for id in order {
            guard let h = helpers[id], let r = h.reader else { continue }
            let done = isDone(h)
            let active = !done && now.timeIntervalSince(writeTime(h)) <= SubagentReader.activeWindow
            if !active {
                if !done { continue }                                        // 没完成但已 90 秒没动静：不显示
                if now.timeIntervalSince(writeTime(h)) > SubagentReader.doneLinger { continue }
            }
            var current: ToolCall?
            if let t = r.facts.openToolUses.last {
                current = ToolCatalog.makeCall(name: t.name, detail: t.key, at: t.at)
            }
            out.append(HelperSnapshot(id: h.id, description: h.meta?.description ?? "", agentType: h.meta?.agentType,
                                      foreground: h.meta?.isForeground ?? true, active: active, done: done,
                                      currentTool: current))
        }
        return out
    }

    /// 所有子代理最近的 tool_use（归属比对用）：(小助手 id, 记录)。
    public var recentToolUses: [(helper: String, use: TranscriptFacts.RecentToolUse)] {
        var out: [(String, TranscriptFacts.RecentToolUse)] = []
        for id in order {
            guard let r = helpers[id]?.reader else { continue }
            for u in r.facts.recentToolUses { out.append((id, u)) }
        }
        return out
    }

    /// 早于 `date` 才结束的、还在报告的小助手个数（测试 / 诊断用）。
    public var helperCount: Int { helpers.count }
}
