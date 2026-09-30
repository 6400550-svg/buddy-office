import Foundation

/// 虚拟时钟：真实时间照常流逝，另外可以"跳"一大段（模拟 10 分钟、45 分钟的空闲）。
/// 引擎的 `options.now` 用它，回放 / 测试写进假数据的时间戳也用它，所以两边的时间是一致的。
public final class VirtualClock {
    private let lock = NSLock()
    private var offset: TimeInterval = 0
    private let frozenBase: Date?
    /// `frozenAt` 不为 nil 时时间完全冻结（只随 advance 前进），单元测试用；否则真实时间照常流逝。
    public init(frozenAt: Date? = nil) { frozenBase = frozenAt }
    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return (frozenBase ?? Date()).addingTimeInterval(offset)
    }
    /// 往前跳（虚拟时间）。
    public func advance(by seconds: TimeInterval) {
        lock.lock(); offset += seconds; lock.unlock()
    }
}

/// 会话记录（transcript）行的构造器：造出和真实数据同形的 JSON 字典。
public enum TL {
    public static func iso(_ d: Date) -> String { TimeUtil.formatISO(d) }

    public static func toolUse(id: String, name: String, input: [String: Any] = [:]) -> [String: Any] {
        ["type": "tool_use", "id": id, "name": name, "input": input]
    }

    /// 一条 assistant 行（每行只有一个 content block）。`stopReason == nil` 写成 JSON null。
    public static func assistant(sessionId: String, at: Date, messageId: String, block: [String: Any],
                                 stopReason: String? = "tool_use", model: String = "claude-opus-5-5",
                                 usage: [String: Any]? = nil, aborted: Bool = false, apiErrorMessage: Bool = false,
                                 agentId: String? = nil) -> [String: Any] {
        var msg: [String: Any] = ["id": messageId, "model": model, "role": "assistant", "type": "message",
                                  "content": [block], "stop_reason": stopReason as Any? ?? NSNull()]
        if let u = usage { msg["usage"] = u }
        var line: [String: Any] = ["type": "assistant", "uuid": UUID().uuidString, "timestamp": iso(at),
                                   "sessionId": sessionId, "isSidechain": agentId != nil, "message": msg]
        if aborted { line["isAbortedMidStream"] = true }
        if apiErrorMessage { line["isApiErrorMessage"] = true }
        if let a = agentId { line["agentId"] = a }
        return line
    }

    public static func thinking() -> [String: Any] { ["type": "thinking", "thinking": ""] }
    public static func text(_ t: String = "ok") -> [String: Any] { ["type": "text", "text": t] }

    public static func usage(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0,
                             write5m: Int? = nil, write1h: Int? = nil) -> [String: Any] {
        var u: [String: Any] = ["input_tokens": input, "output_tokens": output,
                                "cache_creation_input_tokens": cacheWrite, "cache_read_input_tokens": cacheRead]
        if let a = write5m, let b = write1h {
            u["cache_creation"] = ["ephemeral_5m_input_tokens": a, "ephemeral_1h_input_tokens": b]
        }
        return u
    }

    public static func userPrompt(sessionId: String, at: Date, text: String = "hello") -> [String: Any] {
        ["type": "user", "uuid": UUID().uuidString, "timestamp": iso(at), "sessionId": sessionId, "isSidechain": false,
         "message": ["role": "user", "content": text]]
    }

    public static func userToolResult(sessionId: String, at: Date, toolUseId: String, isError: Bool = false,
                                      agentId: String? = nil) -> [String: Any] {
        var l: [String: Any] = ["type": "user", "uuid": UUID().uuidString, "timestamp": iso(at), "sessionId": sessionId,
                                "isSidechain": agentId != nil,
                                "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": toolUseId,
                                                                          "is_error": isError, "content": "ok"]]]]
        if let a = agentId { l["agentId"] = a }
        return l
    }

    public static func userInterrupt(sessionId: String, at: Date, forToolUse: Bool = false) -> [String: Any] {
        let t = forToolUse ? "[Request interrupted by user for tool use]" : "[Request interrupted by user]"
        return ["type": "user", "uuid": UUID().uuidString, "timestamp": iso(at), "sessionId": sessionId, "isSidechain": false,
                "message": ["role": "user", "content": [["type": "text", "text": t]]]]
    }

    public static func system(sessionId: String, at: Date, subtype: String, extra: [String: Any] = [:]) -> [String: Any] {
        var l: [String: Any] = ["type": "system", "subtype": subtype, "uuid": UUID().uuidString, "timestamp": iso(at),
                                "sessionId": sessionId, "isSidechain": false]
        for (k, v) in extra { l[k] = v }
        return l
    }

    public static func stopHookSummary(sessionId: String, at: Date) -> [String: Any] {
        system(sessionId: sessionId, at: at, subtype: "stop_hook_summary",
               extra: ["hookCount": 1, "hookInfos": [["command": "hook.sh", "durationMs": 20]], "hookErrors": []])
    }

    public static func apiError(sessionId: String, at: Date, attempt: Int, max: Int, retryInMs: Double = 1000) -> [String: Any] {
        system(sessionId: sessionId, at: at, subtype: "api_error",
               extra: ["retryAttempt": attempt, "maxRetries": max, "retryInMs": retryInMs, "level": "error",
                       "error": ["message": "Connection error."]])
    }

    public static func customTitle(sessionId: String, _ title: String) -> [String: Any] {
        ["type": "custom-title", "customTitle": title, "sessionId": sessionId]
    }
}

/// 一棵假的 home 树：`.claude/{sessions,.monitor,projects}` + 桌面元数据目录，
/// 用来给引擎 / replay / 测试喂"带时间的合成数据"。文件的写法和真实数据一致
/// （登记表原地重写、hook 事件和会话记录追加）。
public final class FakeClaudeTree {
    public struct Session {
        public var pid: Int32
        public var sessionId: String
        public var host: String?          // 桌面会话的 local_<uuid>；终端会话为 nil
        public var cwd = "/fake/project"
        public var name: String?
        public var entrypoint = "claude-desktop"
        public var version = "2.1.284"
        public var startedAt: Date
        public init(pid: Int32, sessionId: String, host: String? = nil, name: String? = nil, startedAt: Date,
                    entrypoint: String? = nil) {
            self.pid = pid; self.sessionId = sessionId; self.host = host; self.name = name; self.startedAt = startedAt
            self.entrypoint = entrypoint ?? (host == nil ? "cli" : "claude-desktop")
        }
    }

    public let root: String
    public let paths: Paths
    public let clock: VirtualClock
    public let probe: FakeProcessProbe
    /// 假会话记录放在这个项目目录下（目录名以 `-` 开头，和真实数据一样）。
    public let projectDir = "-fake-project"
    public var accountDir = "acct"
    public var orgDir = "org"

    public init(root: String, clock: VirtualClock = VirtualClock(), probe: FakeProcessProbe = FakeProcessProbe()) {
        self.root = root
        self.paths = Paths(home: root)
        self.clock = clock
        self.probe = probe
    }

    /// 建好目录，写一份注册了 hook.sh 的 settings.json。
    public func prepare(registerHook: Bool = true) {
        let fm = FileManager.default
        for d in [paths.sessionsDir, paths.monitorDir, paths.projectsDir + "/" + projectDir, metaDir] {
            try? fm.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
        if registerHook {
            let settings: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "*", "hooks": [["type": "command",
                                                     "command": "$HOME/.claude/monitor/hook.sh", "timeout": 5]]]]]]
            if let data = try? JSONSerialization.data(withJSONObject: settings) {
                _ = FileIO.writeAtomically(data, to: paths.settingsFile)
            }
        }
    }

    public var metaDir: String { paths.desktopSessionsDir + "/" + accountDir + "/" + orgDir }

    // MARK: - 底层写文件

    static func writeInPlace(_ path: String, _ data: Data) {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    static func appendBytes(_ path: String, _ data: Data) {
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    static func jsonLine(_ obj: [String: Any]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data()
        d.append(0x0A)
        return d
    }

    // MARK: - 登记表

    /// 写（原地重写）一份登记表。`status` 是 busy / waiting / idle。
    /// 默认让假 pid "活着"，启动时间 = session.startedAt。
    @discardableResult
    public func writeRegistry(_ s: Session, status: String, waitingFor: String? = nil, statusUpdatedAt: Date? = nil,
                              extra: [String: Any] = [:], markAlive: Bool = true) -> String {
        let now = clock.now()
        let su = statusUpdatedAt ?? now
        var obj: [String: Any] = [
            "pid": Int(s.pid), "sessionId": s.sessionId, "cwd": s.cwd,
            "startedAt": TimeUtil.millis(s.startedAt), "procStart": TimeUtil.formatProcStart(s.startedAt),
            "version": s.version, "peerProtocol": 1, "kind": "interactive", "entrypoint": s.entrypoint,
            "pidDomain": "darwin", "status": status,
            "updatedAt": TimeUtil.millis(now), "statusUpdatedAt": TimeUtil.millis(su),
        ]
        if let h = s.host { obj["hostSessionId"] = h }
        if let n = s.name { obj["name"] = n; obj["nameSource"] = "user"; obj["nameSince"] = TimeUtil.millis(s.startedAt) }
        if let w = waitingFor { obj["waitingFor"] = w }
        for (k, v) in extra { obj[k] = v }
        let path = paths.sessionsDir + "/\(s.pid).json"
        FakeClaudeTree.writeInPlace(path, (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
        if markAlive { probe.setAlive(s.pid, start: s.startedAt) }
        return path
    }

    /// 让进程"死掉"并删掉登记文件（桌面 App 回收空闲会话进程）。
    public func endProcess(pid: Int32, removeFile: Bool = true) {
        probe.kill(pid)
        if removeFile { try? FileManager.default.removeItem(atPath: paths.sessionsDir + "/\(pid).json") }
    }

    // MARK: - hook 事件

    /// 追加一条 ccmon 事件（格式和 hook.sh 一致）。
    public func hook(_ sessionId: String, _ ev: String, tool: String = "", detail: String = "", extra: String = "", at: Date? = nil) {
        let ts = TimeUtil.millis(at ?? clock.now())
        let obj: [String: Any] = ["ts": ts, "ev": ev, "tool": tool, "detail": detail, "extra": extra]
        appendHook(sessionId, FakeClaudeTree.jsonLine(obj))
    }

    /// 追加原始字节（测试非法 UTF-8 / 截断转义用）。
    public func appendHook(_ sessionId: String, _ data: Data) {
        guard let p = paths.hookLogPath(sessionId: sessionId) else { return }
        FakeClaudeTree.appendBytes(p, data)
    }

    // MARK: - 会话记录

    public func transcriptPath(_ sessionId: String) -> String {
        paths.projectsDir + "/" + projectDir + "/" + sessionId + ".jsonl"
    }

    public func appendTranscript(_ sessionId: String, _ lines: [[String: Any]]) {
        var d = Data()
        for l in lines { d.append(FakeClaudeTree.jsonLine(l)) }
        FakeClaudeTree.appendBytes(transcriptPath(sessionId), d)
    }

    public func appendTranscriptRaw(_ sessionId: String, _ data: Data) {
        FakeClaudeTree.appendBytes(transcriptPath(sessionId), data)
    }

    // MARK: - 子代理

    public func subagentDir(_ sessionId: String) -> String {
        paths.projectsDir + "/" + projectDir + "/" + sessionId + "/subagents"
    }

    public func writeSubagentMeta(_ sessionId: String, agentId: String, foreground: Bool, description: String = "helper",
                                  agentType: String = "general-purpose") {
        let dir = subagentDir(sessionId)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let meta: [String: Any] = ["agentType": agentType, "description": description, "toolUseId": "toolu_\(agentId)",
                                   "spawnDepth": 1, "requestShape": foreground ? "foreground" : "background"]
        FakeClaudeTree.writeInPlace(dir + "/agent-\(agentId).meta.json", (try? JSONSerialization.data(withJSONObject: meta)) ?? Data())
    }

    public func appendSubagent(_ sessionId: String, agentId: String, _ lines: [[String: Any]]) {
        let dir = subagentDir(sessionId)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var d = Data()
        for l in lines { d.append(FakeClaudeTree.jsonLine(l)) }
        FakeClaudeTree.appendBytes(dir + "/agent-\(agentId).jsonl", d)
    }

    // MARK: - 桌面元数据

    public struct Meta {
        public var host: String
        public var cliSessionId: String
        public var priors: [String] = []
        public var title = "假会话"
        public var lastActivityAt: Date
        public var lastFocusedAt: Date?
        public var archived = false
        public var lastAssistantUuid: String?
        public var summaryFor: String?
        public var summaryCategory: String?
        public var summaryDetail: String?
        public var model = "claude-opus-5-5"
        public var effort = "high"
        public var permissionMode = "default"
        public init(host: String, cliSessionId: String, lastActivityAt: Date) {
            self.host = host; self.cliSessionId = cliSessionId; self.lastActivityAt = lastActivityAt
        }
    }

    public func writeMeta(_ m: Meta) {
        try? FileManager.default.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        var obj: [String: Any] = [
            "sessionId": m.host, "cliSessionId": m.cliSessionId, "priorCliSessionIds": m.priors,
            "cwd": "/fake/project", "originCwd": "/fake/project", "title": m.title, "titleSource": "auto",
            "model": m.model, "effort": m.effort, "permissionMode": m.permissionMode, "isArchived": m.archived,
            "createdAt": TimeUtil.millis(m.lastActivityAt.addingTimeInterval(-3600)),
            "lastActivityAt": TimeUtil.millis(m.lastActivityAt),
            "completedTurns": 1,
            "remoteMcpServersConfig": [],       // 真实文件里这个字段很大，这里留空
        ]
        if let f = m.lastFocusedAt { obj["lastFocusedAt"] = TimeUtil.millis(f) }
        if let u = m.lastAssistantUuid { obj["lastAssistantUuid"] = u }
        if let f = m.summaryFor { obj["postTurnSummaryFor"] = f }
        if let c = m.summaryCategory {
            obj["postTurnSummary"] = ["status_category": c, "status_detail": m.summaryDetail ?? "", "needs_action": "",
                                      "summarizes_uuid": m.summaryFor ?? ""]
        }
        FakeClaudeTree.writeInPlace(metaDir + "/\(m.host).json", (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }

    public func removeMeta(host: String) {
        try? FileManager.default.removeItem(atPath: metaDir + "/\(host).json")
    }
}
