import Foundation

// Codex（OpenAI）本机数据的只读读取。
//
// 只读两样：
//   · `~/.codex/session_index.jsonl`                        线程标题（一行一个线程：id / thread_name / updated_at）
//   · `~/.codex/sessions/YYYY/MM/DD/rollout-<时间>-<线程 id>.jsonl`   会话记录（一行一个事件）
// 同目录下的 auth.json（登录凭据）、sqlite 数据库、config.toml 一概不碰（`FileIO.isForbidden` 还会挡掉 auth.json）。
// 和 Claude 的会话记录一样**不留对话内容**：解析时只保留事实（事件类型、工具名、时间、token 数）。

public enum CodexNames {
    /// `rollout-2026-09-29T21-12-46-01a0f083-d304-7420-b1e2-8305fec5add2.jsonl` → 线程 id（结尾的 UUID）；名字不合规返回 nil。
    public static func threadId(fromRolloutName name: String) -> String? {
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
        let stem = name.dropLast(6)
        guard stem.utf8.count > 36 else { return nil }
        let id = String(stem.suffix(36))
        return isUUID(id) ? id : nil
    }

    /// 8-4-4-4-12 的十六进制 UUID（同时保证它能安全地拼进文件名 / 深链）。
    public static func isUUID(_ s: String) -> Bool {
        let b = Array(s.utf8)
        guard b.count == 36 else { return false }
        for (i, c) in b.enumerated() {
            if i == 8 || i == 13 || i == 18 || i == 23 { if c != 45 { return false }; continue }
            let hex = (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
            if !hex { return false }
        }
        return true
    }
}

/// 线程索引：标题 + 「线程 id → 会话记录路径」。
public final class CodexIndex {
    public struct Entry: Sendable, Equatable {
        public var id: String
        public var title: String
        public var updatedAt: Date?
    }

    private let paths: Paths
    private var indexSig: FileStat?
    private var entries: [String: Entry] = [:]
    public private(set) var indexReadable = true

    private var tree: [String: String] = [:]
    private var treeBuiltAt: Date?
    private var treeMissAt: Date?
    public private(set) var sessionsReadable = true

    public init(paths: Paths) { self.paths = paths }

    // MARK: 标题

    /// 索引文件变了才重读（几十 KB～几 MB，一行一个线程）。
    public func refreshTitles() {
        guard let st = FileIO.stat(paths.codexIndexFile) else { indexReadable = false; entries = [:]; indexSig = nil; return }
        indexReadable = true
        if let old = indexSig, old.mtimeNs == st.mtimeNs, old.size == st.size, old.ino == st.ino { return }
        indexSig = st
        guard let data = FileIO.readAll(paths.codexIndexFile, maxBytes: 16 << 20) else { return }
        var out: [String: Entry] = [:]
        data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self)
            var start = 0
            let n = buf.count
            while start < n {
                var end = start
                while end < n, buf[end] != 0x0A { end += 1 }
                if end > start, end - start <= 64 << 10,
                   let obj = SafeJSON.object(UnsafeBufferPointer(rebasing: buf[start..<end])),
                   let id = SafeJSON.id(obj["id"]), CodexNames.isUUID(id) {
                    let title = SafeJSON.string(obj["thread_name"], max: 200)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let at = (obj["updated_at"] as? String).flatMap { TimeUtil.parseISO($0) }
                    if let old = out[id], let a = old.updatedAt, let b = at, a > b { /* 保留更新的那条 */ } else {
                        out[id] = Entry(id: id, title: title, updatedAt: at)
                    }
                }
                start = end + 1
            }
        }
        entries = out
    }

    public func title(for id: String) -> String? {
        guard let t = entries[id]?.title, !t.isEmpty else { return nil }
        return t
    }

    /// 索引里最近有更新的线程 id。
    public func idsUpdated(since: Date) -> [String] {
        entries.values.filter { ($0.updatedAt ?? .distantPast) >= since }.map { $0.id }
    }

    // MARK: 会话记录文件

    /// 整棵树列一遍：`sessions/YYYY/MM/DD/rollout-*.jsonl` → [线程 id: 路径]。一两千个文件也只是几次 readdir。
    private func rebuildTree(now: Date) {
        var out: [String: String] = [:]
        treeBuiltAt = now
        guard let years = FileIO.listDirectory(paths.codexSessionsDir) else { sessionsReadable = false; tree = [:]; return }
        sessionsReadable = true
        for y in years where isDigits(y, 4) {
            let yp = paths.codexSessionsDir + "/" + y
            for m in FileIO.listDirectory(yp) ?? [] where isDigits(m, 2) {
                let mp = yp + "/" + m
                for d in FileIO.listDirectory(mp) ?? [] where isDigits(d, 2) {
                    let dp = mp + "/" + d
                    for f in FileIO.listDirectory(dp) ?? [] {
                        if let id = CodexNames.threadId(fromRolloutName: f) { out[id] = dp + "/" + f }
                    }
                }
            }
        }
        tree = out
    }

    private func isDigits(_ s: String, _ n: Int) -> Bool { s.utf8.count == n && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }

    /// 线程 id → 会话记录路径。树 60 秒重建一次；找不到时（新线程刚创建）最多每 3 秒重建一次。
    public func rolloutPath(for id: String, now: Date) -> String? {
        if treeBuiltAt == nil || now.timeIntervalSince(treeBuiltAt!) >= 60 { rebuildTree(now: now) }
        if let p = tree[id] { return p }
        if treeMissAt == nil || now.timeIntervalSince(treeMissAt!) >= 3 {
            treeMissAt = now
            rebuildTree(now: now)
        }
        return tree[id]
    }

    /// 最新几天的目录里、最近改过的会话记录（不依赖索引：新线程还没进索引时也能发现）。
    public func recentRollouts(since: Date, now: Date, days: Int = 3) -> [(id: String, path: String, mtime: Date)] {
        var dayDirs: [String] = []
        let root = paths.codexSessionsDir
        guard let years = FileIO.listDirectory(root) else { sessionsReadable = false; return [] }
        sessionsReadable = true
        outer: for y in years.filter({ isDigits($0, 4) }).sorted(by: >) {
            let yp = root + "/" + y
            for m in (FileIO.listDirectory(yp) ?? []).filter({ isDigits($0, 2) }).sorted(by: >) {
                let mp = yp + "/" + m
                for d in (FileIO.listDirectory(mp) ?? []).filter({ isDigits($0, 2) }).sorted(by: >) {
                    dayDirs.append(mp + "/" + d)
                    if dayDirs.count >= days { break outer }
                }
            }
        }
        var out: [(String, String, Date)] = []
        for dp in dayDirs {
            for f in FileIO.listDirectory(dp) ?? [] {
                guard let id = CodexNames.threadId(fromRolloutName: f) else { continue }
                let p = dp + "/" + f
                if let st = FileIO.stat(p), st.mtime >= since { out.append((id, p, st.mtime)) }
            }
        }
        return out
    }
}

// MARK: - 会话记录

/// 一个还没有结果的工具调用。
public struct CodexOpenCall: Sendable, Equatable {
    public var callId: String
    public var name: String
    public var detail: String
    public var startedAt: Date
}

/// 从一个线程的会话记录里读出来的事实（不含任何对话内容）。
public struct CodexFacts: Sendable, Equatable {
    // 会话头（session_meta，文件的第一行）
    public var cwd: String?
    public var cliVersion: String?
    public var originator: String?
    public var startedAt: Date?
    /// 子代理 / guardian 线程（source 是对象而不是字符串）：不当作独立的同事。
    public var isSubagent = false
    // 最近一次 turn_context
    public var model: String?
    public var effort: String?
    public var approvalPolicy: String?
    // 轮次
    public var turnOpen = false
    public var turnStartedAt: Date?
    public var lastTurnEndedAt: Date?
    public var lastTurnDuration: TimeInterval?
    public var lastTurnInterrupted = false
    /// 已经见过至少一次轮次边界（task_started / task_complete / turn_aborted）。
    public var sawTurnBoundary = false
    // 工具
    public var open: [CodexOpenCall] = []
    // 其他
    public var lastEventAt: Date?
    public var compactedAt: Date?
    public var tokens: TokenBreakdown?
    public var contextTokens: Int?
}

/// 一个 rollout 文件的增量读取器。启动时先读文件头（session_meta），再从尾部 4 MiB 处开始读到末尾。
public final class CodexRolloutReader {
    public let path: String
    public private(set) var facts = CodexFacts()
    public private(set) var totalLines = 0
    public private(set) var skippedLines = 0
    private let tailer: JSONLTailer
    private var bootstrapped = false

    static let maxOpenCalls = 64
    static let bootstrapWindow = 4 << 20
    static let headBytes = 2 << 20

    public init(path: String) {
        self.path = path
        self.tailer = JSONLTailer(path: path, config: .init(maxLineBytes: 8 << 20, chunkBytes: 512 << 10))
    }

    /// 第一次读。返回文件存不存在。
    @discardableResult
    public func bootstrap() -> Bool {
        guard FileIO.stat(path) != nil else { return false }
        readHead()
        tailer.seekToTail(window: CodexRolloutReader.bootstrapWindow)
        bootstrapped = true
        _ = poll()
        return true
    }

    /// 增量读；有新内容返回 true。文件被截断 / 轮转时状态作废、重新读。
    @discardableResult
    public func poll() -> Bool {
        if !bootstrapped { return bootstrap() }
        let before = totalLines
        let r = tailer.poll { [self] bytes in handle(bytes) }
        if r.reset {
            let old = facts
            facts = CodexFacts()
            facts.cwd = old.cwd; facts.cliVersion = old.cliVersion; facts.originator = old.originator
            facts.startedAt = old.startedAt; facts.isSubagent = old.isSubagent
        }
        return totalLines != before || r.reset
    }

    // MARK: 文件头

    private func readHead() {
        guard let head = FileIO.readPrefix(path, maxBytes: CodexRolloutReader.headBytes) else { return }
        guard let nl = head.firstIndex(of: 0x0A) else { return }              // 第一行比 2 MiB 还长：放弃，靠 turn_context 补
        head.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            guard let obj = SafeJSON.object(UnsafeBufferPointer(rebasing: p[0..<(nl - head.startIndex)])),
                  (obj["type"] as? String) == "session_meta", let pl = obj["payload"] as? [String: Any] else { return }
            facts.cwd = SafeJSON.string(pl["cwd"], max: 1024)
            facts.cliVersion = SafeJSON.string(pl["cli_version"], max: 64)
            facts.originator = SafeJSON.string(pl["originator"], max: 64)
            facts.startedAt = (pl["timestamp"] as? String).flatMap { TimeUtil.parseISO($0) }
            if let src = pl["source"], !(src is String) { facts.isSubagent = true }
            if let ts = pl["thread_source"] as? String, ts != "user" { facts.isSubagent = true }
        }
    }

    // MARK: 一行

    private func handle(_ bytes: UnsafeBufferPointer<UInt8>) {
        totalLines += 1
        // 超大行（compacted 会带一整段被压缩的历史）：不解析，只认出它是 compacted
        if bytes.count > 1 << 20 {
            if CodexRolloutReader.prefixContains(bytes, "\"type\":\"compacted\"") { facts.compactedAt = facts.lastEventAt }
            return
        }
        guard let obj = SafeJSON.object(bytes), let type = obj["type"] as? String else { skippedLines += 1; return }
        let ts = (obj["timestamp"] as? String).flatMap { TimeUtil.parseISO($0) }
        if let ts { facts.lastEventAt = max(facts.lastEventAt ?? ts, ts) }
        let pl = obj["payload"] as? [String: Any] ?? [:]
        let pt = pl["type"] as? String
        switch type {
        case "turn_context":
            if let m = SafeJSON.string(pl["model"], max: 128), !m.isEmpty { facts.model = m }
            if let e = SafeJSON.string(pl["effort"], max: 32) { facts.effort = e }
            if let a = SafeJSON.string(pl["approval_policy"], max: 32) { facts.approvalPolicy = a }
            if let c = SafeJSON.string(pl["cwd"], max: 1024), !c.isEmpty { facts.cwd = c }
        case "compacted":
            facts.compactedAt = ts
        case "event_msg":
            handleEvent(pt, pl, ts)
        case "response_item":
            handleItem(pt, pl, ts)
        default:
            break
        }
    }

    private func handleEvent(_ pt: String?, _ pl: [String: Any], _ ts: Date?) {
        switch pt {
        case "task_started":
            facts.turnOpen = true
            facts.sawTurnBoundary = true
            facts.turnStartedAt = seconds(pl["started_at"]) ?? ts
            facts.open.removeAll()
        case "task_complete":
            endTurn(pl, ts, interrupted: false)
        case "turn_aborted":
            endTurn(pl, ts, interrupted: true)
        case "token_count":
            guard let info = pl["info"] as? [String: Any] else { return }
            if let t = info["total_token_usage"] as? [String: Any] {
                let input = intValue(t["input_tokens"]), cached = intValue(t["cached_input_tokens"])
                facts.tokens = TokenBreakdown(input: max(0, input - cached), output: intValue(t["output_tokens"]),
                                              cacheWrite: intValue(t["cache_write_input_tokens"]), cacheRead: cached)
            }
            if let l = info["last_token_usage"] as? [String: Any] { facts.contextTokens = intValue(l["input_tokens"]) }
        default:
            break
        }
    }

    private func endTurn(_ pl: [String: Any], _ ts: Date?, interrupted: Bool) {
        facts.turnOpen = false
        facts.sawTurnBoundary = true
        facts.lastTurnInterrupted = interrupted
        facts.lastTurnEndedAt = seconds(pl["completed_at"]) ?? ts
        if let ms = (pl["duration_ms"] as? NSNumber)?.doubleValue, ms.isFinite, ms >= 0, ms < 1e10 {
            facts.lastTurnDuration = ms / 1000
        } else if let s = facts.turnStartedAt, let e = facts.lastTurnEndedAt {
            facts.lastTurnDuration = max(0, e.timeIntervalSince(s))
        } else {
            facts.lastTurnDuration = nil
        }
        facts.turnStartedAt = nil
        facts.open.removeAll()
    }

    private func handleItem(_ pt: String?, _ pl: [String: Any], _ ts: Date?) {
        switch pt {
        case "function_call", "custom_tool_call":
            guard let id = SafeJSON.id(pl["call_id"]), let name = SafeJSON.string(pl["name"], max: 128), !name.isEmpty else { return }
            let raw = (pl["arguments"] as? String) ?? (pl["input"] as? String) ?? ""
            let call = CodexOpenCall(callId: id, name: name, detail: CodexRolloutReader.detail(tool: name, raw: raw), startedAt: ts ?? facts.lastEventAt ?? Date())
            facts.open.removeAll { $0.callId == id }
            facts.open.append(call)
            if facts.open.count > CodexRolloutReader.maxOpenCalls { facts.open.removeFirst(facts.open.count - CodexRolloutReader.maxOpenCalls) }
        case "function_call_output", "custom_tool_call_output":
            guard let id = SafeJSON.id(pl["call_id"]) else { return }
            facts.open.removeAll { $0.callId == id }
        default:
            break
        }
    }

    // MARK: 小工具

    private func seconds(_ v: Any?) -> Date? {
        guard let n = v as? NSNumber, !TimeUtil.isBool(n) else { return nil }
        return TimeUtil.date(saneMs: n.doubleValue * 1000)
    }

    private func intValue(_ v: Any?) -> Int {
        guard let n = v as? NSNumber, !TimeUtil.isBool(n) else { return 0 }
        let d = n.doubleValue
        return d.isFinite && d >= 0 && d < 1e15 ? Int(d) : 0
    }

    static func prefixContains(_ bytes: UnsafeBufferPointer<UInt8>, _ needle: String, within n: Int = 256) -> Bool {
        let head = String(decoding: UnsafeBufferPointer(rebasing: bytes[0..<min(n, bytes.count)]), as: UTF8.self)
        return head.contains(needle)
    }

    /// 给桌牌 / 悬停卡片看的一句话（和 Claude 那边 hook 的 detail 同一类信息：命令、文件路径），最多 160 字。
    /// 参数原文里别的内容一概不留。
    static func detail(tool: String, raw: String) -> String {
        var s = ""
        switch tool {
        case "exec_command", "shell", "local_shell", "container.exec":
            if let d = raw.data(using: .utf8), let o = SafeJSON.object(d) {
                if let c = o["cmd"] as? String { s = c }
                else if let c = o["command"] as? String { s = c }
                else if let a = o["command"] as? [String] { s = a.joined(separator: " ") }
            }
        case "exec":
            // exec 的参数是一段 JS，里面用 tools.exec_command({cmd: "…"}) 跑命令：抠出第一个 cmd 字符串
            if let r = raw.range(of: #"cmd\s*:\s*"((?:\\.|[^"\\])*)""#, options: .regularExpression) {
                let m = String(raw[r])
                if let q = m.firstIndex(of: "\"") { s = unescape(String(m[m.index(after: q)...].dropLast())) }
            }
        case "apply_patch":
            if let r = raw.range(of: #"\*\*\* (Update|Add|Delete) File: [^\n"\\]+"#, options: .regularExpression) {
                let m = String(raw[r])
                if let c = m.range(of: "File: ") { s = String(m[c.upperBound...]) }
            }
        case "view_image":
            if let d = raw.data(using: .utf8), let o = SafeJSON.object(d), let p = o["path"] as? String { s = p }
        default:
            break
        }
        s = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return SafeJSON.clip(s, max: 160)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Codex 在不在运行

public protocol CodexProcessProbing {
    /// Codex（桌面 App 的 app-server / CLI）或 ChatGPT 桌面 App 有没有在运行。
    func isRunning() -> Bool
}

/// 真实的探测：`sysctl(KERN_PROC_ALL)` 看进程名（p_comm，最多 16 个字符）：`codex`（app-server / CLI）、`ChatGPT`（桌面 App）。
public final class SystemCodexProbe: CodexProcessProbing {
    public init() {}

    public func isRunning() -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return true }          // 探测不了就当它在运行（不误伤）
        var buf = [UInt8](repeating: 0, count: size + size / 8 + 4096)
        var got = buf.count
        guard sysctl(&mib, 3, &buf, &got, nil, 0) == 0 else { return true }
        let stride = MemoryLayout<kinfo_proc>.stride
        var off = 0
        while off + stride <= got {
            let hit: Bool = buf.withUnsafeBytes { raw in
                let kp = raw.load(fromByteOffset: off, as: kinfo_proc.self)
                var comm = kp.kp_proc.p_comm
                let name = withUnsafePointer(to: &comm) { p in
                    p.withMemoryRebound(to: CChar.self, capacity: 17) { String(cString: $0) }
                }
                return name == "codex" || name == "ChatGPT" || name == "Codex"
            }
            if hit { return true }
            off += stride
        }
        return false
    }
}

/// 测试用：固定答案。
public final class FixedCodexProbe: CodexProcessProbing {
    public var running: Bool
    public init(_ running: Bool = true) { self.running = running }
    public func isRunning() -> Bool { running }
}
