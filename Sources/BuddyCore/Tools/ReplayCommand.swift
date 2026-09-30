import Foundation

/// `buddyctl replay --root <临时目录> [--fsevents] [--keep] [--verbose]`
/// （`buddydump` 目标只依赖 BuddyCore，所以 replay 也只依赖 BuddyCore。）
///
/// 按时间把带时间戳的合成数据写进一个假的 `~/.claude` 目录树，让**真实的 SessionStore**
/// （文件监听 / 轮询链路 + 引擎）去读，断言每一步的动作时间线。整条时序：
/// 进场 → 思考 → 读 → 并行搜索 → 改代码 → 长 Bash → 等批准 → 提问 → 计划待审 →
/// 派 3 个前台子代理 → 后台子代理 → 压缩 → API 重试 → 出错 → 被打断 → 做完(blocked) →
/// 空闲 → 打盹 → 睡着 → 进程被回收离场 → 同一个身份回来（外加一个终端会话的进出场）。
///
/// 时间用虚拟时钟：真实时间照常流逝，"打盹 10 分钟、睡着 45 分钟"这类用跳时钟的办法瞬间过去。
/// "进程"用假 pid（`FakeProcessProbe`）。默认走纯轮询（沙箱里 FSEvents 也许不工作）；`--fsevents` 走 FSEvents 链路。
public func runReplayCommand(arguments: [String]) -> Int32 {
    var root: String?
    var keep = false
    var fsevents = false
    var verbose = false
    var keepGoing = false
    var latencyRuns = 0
    var i = 0
    func usage() -> Int32 {
        print("用法：replay --root <空目录> [--fsevents] [--keep] [--verbose] [--continue] [--latency N]")
        return 2
    }
    while i < arguments.count {
        switch arguments[i] {
        case "--root":
            i += 1
            guard i < arguments.count else { return usage() }
            root = arguments[i]
        case "--keep": keep = true
        case "--fsevents": fsevents = true
        case "--verbose": verbose = true
        case "--continue": keepGoing = true      // 有步骤失败也继续往下跑（默认第一个失败就停，后面的步骤依赖前面的状态）
        case "--latency":                          // 回放完再单独测 N 次"登记表变化 → 快照回调"的延迟（孤立的变化，不受 20 Hz 限速影响）
            i += 1
            guard i < arguments.count, let n = Int(arguments[i]), n > 0 else { return usage() }
            latencyRuns = n
        case "-h", "--help": _ = usage(); return 0
        default: return usage()
        }
        i += 1
    }
    let rootPath = root ?? (FileIO.temporaryDirectory + "buddy-replay-\(getpid())")
    // 安全：root 必须是不存在或空目录（绝不往真实的 home 里写假数据）
    if let names = FileIO.listDirectory(rootPath), !names.isEmpty {
        print("✗ --root 必须是空目录或不存在的目录：\(rootPath)")
        return 2
    }
    do { try FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true) } catch {
        print("✗ 建不了目录 \(rootPath)：\(error.localizedDescription)")
        return 2
    }
    defer { if !keep && root == nil { try? FileManager.default.removeItem(atPath: rootPath) } }

    let replay = Replay(root: rootPath, useFSEvents: fsevents, verbose: verbose, keepGoing: keepGoing, latencyRuns: latencyRuns)
    let ok = replay.run()
    if keep || root != nil { print("假数据留在：\(rootPath)") }
    return ok ? 0 : 1
}

// MARK: - 记录器

private final class Recorder {
    private let lock = NSLock()
    private var _snapshots: [BuddySnapshot] = []
    private var _events: [BuddyEvent] = []
    private(set) var updateCount = 0

    func record(_ s: [BuddySnapshot]) { lock.lock(); _snapshots = s; updateCount += 1; lock.unlock() }
    func record(_ e: BuddyEvent) { lock.lock(); _events.append(e); lock.unlock() }
    var snapshots: [BuddySnapshot] { lock.lock(); defer { lock.unlock() }; return _snapshots }
    var events: [BuddyEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    func snap(_ key: String) -> BuddySnapshot? { snapshots.first { $0.key == key } }
}

// MARK: - 回放

private final class Replay {
    struct Result {
        var name: String
        var ok: Bool
        var latencyMs: Double?
        var note: String
        var isRegistryChange: Bool
    }

    let root: String
    let verbose: Bool
    let keepGoing: Bool
    let latencyRuns: Int
    var aborted = false
    let clock = VirtualClock()
    let probe = FakeProcessProbe()
    let tree: FakeClaudeTree
    let store: SessionStore
    let rec = Recorder()
    var results: [Result] = []

    // 假会话
    let sid1 = "5e1a0000-0000-4000-8000-000000000001"
    let host1 = "local_5e1a0000-0000-4000-8000-0000000000a1"
    var key1: String { "d:" + host1 }
    lazy var main = FakeClaudeTree.Session(pid: 91001, sessionId: sid1, host: host1, name: "回放·主会话", startedAt: clock.now())
    var toolCounter = 0
    var seatBefore = -1
    var saltBefore: UInt64 = 0

    init(root: String, useFSEvents: Bool, verbose: Bool, keepGoing: Bool, latencyRuns: Int) {
        self.root = root
        self.verbose = verbose
        self.keepGoing = keepGoing
        self.latencyRuns = latencyRuns
        tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        var eo = SessionEngine.Options(paths: tree.paths, now: { [clock] in clock.now() }, probe: probe)
        eo.persist = true
        eo.scanTokens = true
        var so = SessionStore.Options(engine: eo)
        so.usePolling = !useFSEvents
        so.callbackQueue = DispatchQueue(label: "replay.callback")
        store = SessionStore(options: so)
    }

    // MARK: 步骤执行

    /// 写数据（action）→ 等到 expect 返回 nil（满足）或超时。返回是否通过。
    @discardableResult
    func step(_ name: String, registry: Bool = false, timeout: TimeInterval = 6, measure: Bool = true,
              action: () -> Void, expect: () -> String?) -> Bool {
        if aborted { return false }               // 前面失败了：后面的步骤依赖前面的状态，不跑了
        if measure { Thread.sleep(forTimeInterval: 0.12) }     // 让上一次回调过去，量到的是"孤立的变化"的延迟（不受 20 Hz 限速影响）
        let t0 = Date()
        action()
        var msg: String? = "没等到"
        let deadline = t0.addingTimeInterval(timeout)
        while Date() < deadline {
            msg = expect()
            if msg == nil { break }
            Thread.sleep(forTimeInterval: 0.004)
        }
        let latency = Date().timeIntervalSince(t0) * 1000
        let ok = msg == nil
        results.append(Result(name: name, ok: ok, latencyMs: (ok && measure) ? latency : nil, note: msg ?? "", isRegistryChange: registry))
        let mark = ok ? "✓" : "✗"
        let lat = (ok && measure) ? String(format: "  %5.0f ms", latency) : "         "
        print("  \(mark) \(name)\(lat)" + (ok ? "" : "  ← \(msg ?? "")"))
        if !ok && !keepGoing { aborted = true; print("  （后面的步骤依赖这一步的状态，已跳过；加 --continue 可以继续跑）") }
        return ok
    }

    func act(_ a: Activity?) -> String { a.map { DumpFormatter.describe($0).0 } ?? "无" }

    func expectActivity(_ key: String, _ label: String, _ pred: @escaping (Activity) -> Bool) -> () -> String? {
        return { [self] in
            guard let s = rec.snap(key) else { return "没有这个 buddy" }
            return pred(s.activity) ? nil : "动作是「\(act(s.activity))」，想要「\(label)」"
        }
    }

    func hook(_ ev: String, tool: String = "", detail: String = "", extra: String = "", at: Date? = nil) {
        tree.hook(sid1, ev, tool: tool, detail: detail, extra: extra, at: at)
    }

    func toolId() -> String { toolCounter += 1; return "toolu_replay_\(toolCounter)" }

    func hasEvent(_ key: String, _ match: (BuddyEvent.Kind) -> Bool) -> Bool {
        rec.events.contains { $0.key == key && match($0.kind) }
    }

    // MARK: 整条时序

    func run() -> Bool {
        print("回放开始（根目录 \(root)）")
        tree.prepare()
        guard FileIO.stat(tree.paths.sessionsDir) != nil else {
            print("✗ 假目录树建不起来（\(tree.paths.sessionsDir) 不存在），检查 --root 是不是可写")
            return false
        }
        store.onUpdate = { [rec] s in rec.record(s) }
        store.onEvent = { [rec] e in rec.record(e) }
        store.start()
        Thread.sleep(forTimeInterval: 0.2)
        print("  \(store.diagnostics().sourceStatus.first ?? "")")

        step("启动时办公室是空的", measure: false, action: {}, expect: { [self] in
            rec.snapshots.isEmpty ? nil : "有 \(rec.snapshots.count) 个 buddy"
        })
        let k = key1
        let s1 = sid1

        // ① 进场
        step("进场：新会话走进办公室（登记表 idle）", registry: true, action: { [self] in
            tree.writeMeta(.init(host: host1, cliSessionId: s1, lastActivityAt: clock.now()))
            tree.appendTranscript(s1, [TL.customTitle(sessionId: s1, "回放·主会话"),
                                       TL.userPrompt(sessionId: s1, at: clock.now(), text: "开始")])
            hook("SessionStart", extra: "startup")
            _ = tree.writeRegistry(main, status: "idle", statusUpdatedAt: clock.now())
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "buddy 还没出现" }
            guard s.presence == .present, s.appearedAfterLaunch else { return "presence/appearedAfterLaunch 不对" }
            guard s.activity == .idle else { return "动作是「\(act(s.activity))」，想要「空闲」" }
            guard hasEvent(k, { $0 == .arrived(freshAfterLaunch: true) }) else { return "没有 arrived 事件" }
            return nil
        })
        seatBefore = rec.snap(k)?.seat ?? -1
        saltBefore = rec.snap(k)?.salt ?? 0

        // ② 思考
        step("思考：一轮开始（登记表 busy + UserPromptSubmit）", registry: true, action: { [self] in
            clock.advance(by: 1)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("UserPromptSubmit", extra: "这段用户输入绝不能出现在任何地方")
            tree.appendTranscript(s1, [TL.userPrompt(sessionId: s1, at: clock.now(), text: "这段用户输入绝不能出现在任何地方")])
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "没有 buddy" }
            guard s.phase == .busy, s.activity == .thinking else { return "动作是「\(act(s.activity))」，想要「思考中」" }
            guard s.turnStartedAt != nil else { return "没有 turnStartedAt" }
            guard hasEvent(k, { $0 == .turnStarted }) else { return "没有 turnStarted 事件" }
            return nil
        })

        // ③ 读
        step("读：Read app.swift", action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "Read", detail: "/fake/project/app.swift")
        }, expect: expectActivity(k, "工具 Read") { a in
            if case .tool(let c, 1) = a { return c.category == .read && c.detail == "/fake/project/app.swift" }
            return false
        })
        step("读完：回到思考", action: { [self] in
            clock.advance(by: 0.3)
            hook("PostToolUse", tool: "Read", detail: "/fake/project/app.swift", extra: "len=42")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ④ 并行搜索
        step("并行搜索：Grep + Glob 同一毫秒（×2）", action: { [self] in
            clock.advance(by: 0.5)
            let t = clock.now()
            hook("PreToolUse", tool: "Grep", detail: "TODO", at: t)
            hook("PreToolUse", tool: "Glob", detail: "**/*.swift", at: t)
        }, expect: expectActivity(k, "搜索 ×2") { a in
            if case .tool(let c, 2) = a { return c.category == .search }
            return false
        })
        step("搜索完：回到思考", action: { [self] in
            clock.advance(by: 0.4)
            hook("PostToolUse", tool: "Glob", detail: "**/*.swift", extra: "len=10")
            hook("PostToolUse", tool: "Grep", detail: "TODO", extra: "len=10")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑤ 改代码
        step("改代码：Edit", action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "Edit", detail: "/fake/project/app.swift")
        }, expect: expectActivity(k, "工具 Edit") { a in
            if case .tool(let c, 1) = a { return c.category == .edit }
            return false
        })
        step("改完：回到思考", action: { [self] in
            clock.advance(by: 0.3)
            hook("PostToolUse", tool: "Edit", detail: "/fake/project/app.swift", extra: "len=5")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑥ 长 Bash（不因时间判死）
        step("长 Bash 开始", action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "Bash", detail: "npm test")
        }, expect: expectActivity(k, "工具 Bash") { a in
            if case .tool(let c, 1) = a { return c.category == .bash && c.detail == "npm test" }
            return false
        })
        step("长 Bash 跑了 61 分钟：依然是 busy + Bash（不因时间判死）", measure: false, action: { [self] in
            clock.advance(by: 61 * 60)
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "buddy 没了" }
            guard s.presence == .present, s.phase == .busy else { return "presence/phase 不对：\(s.phase)" }
            guard case .tool(let c, _) = s.activity, c.category == .bash else { return "动作是「\(act(s.activity))」" }
            guard s.quiet else { return "超过 10 分钟没有任何增长，应该是 quiet" }
            return nil
        })
        step("长 Bash 结束", action: { [self] in
            hook("PostToolUse", tool: "Bash", detail: "npm test", extra: "len=900")
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .thinking else { return "动作不是思考中" }
            return s.quiet ? "quiet 应该在有新事件后清掉" : nil
        })

        // ⑦ 等批准
        step("等批准：Bash git push（permission prompt）", registry: true, action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "Bash", detail: "git push origin main")
            _ = tree.writeRegistry(main, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: clock.now())
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "没有 buddy" }
            guard case .waitingApproval(let t?) = s.activity, t.category == .bash, t.detail == "git push origin main" else {
                return "动作是「\(act(s.activity))」，想要「等批准 Bash」"
            }
            guard hasEvent(k, { if case .needsUser(.approval) = $0 { return true } else { return false } }) else { return "没有 needsUser 事件" }
            return nil
        })
        step("批准了：回到 busy，不再等你", registry: true, action: { [self] in
            clock.advance(by: 2)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("PostToolUse", tool: "Bash", detail: "git push origin main", extra: "len=50")
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .thinking else { return "动作不是思考中" }
            guard hasEvent(k, { $0 == .needsUserCleared }) else { return "没有 needsUserCleared 事件" }
            return nil
        })

        // ⑧ 提问
        step("提问：AskUserQuestion（detail 是选项描述，不能当问题）", registry: true, action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "AskUserQuestion", detail: "这是第一个选项的 description，不是问题")
            _ = tree.writeRegistry(main, status: "waiting", waitingFor: "input needed", statusUpdatedAt: clock.now())
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .asking else { return "动作不是提问" }
            guard hasEvent(k, { $0 == .needsUser(.question) }) else { return "没有 needsUser(question)" }
            return nil
        })
        step("回答了：回到 busy", registry: true, action: { [self] in
            clock.advance(by: 3)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("PostToolUse", tool: "AskUserQuestion", detail: "这是第一个选项的 description，不是问题", extra: "len=300")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑨ 计划待审
        step("计划待审：ExitPlanMode", registry: true, action: { [self] in
            clock.advance(by: 0.5)
            hook("PreToolUse", tool: "ExitPlanMode", detail: "")
            _ = tree.writeRegistry(main, status: "waiting", waitingFor: "input needed", statusUpdatedAt: clock.now())
        }, expect: expectActivity(k, "计划待审") { $0 == .planReview })
        step("计划批准了：回到 busy", registry: true, action: { [self] in
            clock.advance(by: 2)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("PostToolUse", tool: "ExitPlanMode", extra: "len=100")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑩ 派 3 个前台子代理
        let fg = ["fga1", "fga2", "fga3"].map { "aa" + $0 + "0000000000" }
        step("派 3 个前台子代理：主线程 Agent ×3", action: { [self] in
            clock.advance(by: 0.5)
            let t = clock.now()
            var lines: [[String: Any]] = []
            for (n, a) in fg.enumerated() {
                let id = "toolu_fg\(n)"
                lines.append(TL.assistant(sessionId: s1, at: t, messageId: "msg_fg", block: TL.toolUse(id: id, name: "Agent", input: ["description": "研究\(n)"])))
                hook("PreToolUse", tool: "Agent", detail: "研究\(n)", at: t)
                tree.writeSubagentMeta(s1, agentId: a, foreground: true, description: "研究\(n)")
            }
            tree.appendTranscript(s1, lines)
        }, expect: expectActivity(k, "Agent ×3") { a in
            if case .tool(let c, 3) = a { return c.category == .delegate }
            return false
        })
        step("前台小助手干活：它们的工具调用不算主线程的", action: { [self] in
            clock.advance(by: 0.4)
            let t = clock.now()
            let tools = [("Bash", ["command": "ls -la"], "ls -la"), ("Read", ["file_path": "/fake/project/x.swift"], "/fake/project/x.swift"),
                         ("Grep", ["pattern": "foo"], "foo")]
            for (n, a) in fg.enumerated() {
                let (name, input, detail) = tools[n]
                tree.appendSubagent(s1, agentId: a, [TL.assistant(sessionId: s1, at: t, messageId: "msg_h\(n)",
                                                                  block: TL.toolUse(id: "toolu_h\(n)", name: name, input: input),
                                                                  stopReason: nil, agentId: a)])
                hook("PreToolUse", tool: name, detail: detail, at: t)
            }
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "没有 buddy" }
            guard case .tool(let c, 3) = s.activity, c.category == .delegate else { return "主线程动作被小助手的工具抢了：「\(act(s.activity))」" }
            let active = s.helpers.filter { $0.foreground && $0.active && $0.currentTool != nil }
            guard active.count == 3 else { return "小助手活跃数 \(active.count)，想要 3" }
            return nil
        })
        step("前台小助手做完、Agent 返回：回到思考", action: { [self] in
            clock.advance(by: 1)
            let t = clock.now()
            for (n, a) in fg.enumerated() {
                tree.appendSubagent(s1, agentId: a, [
                    TL.userToolResult(sessionId: s1, at: t, toolUseId: "toolu_h\(n)", agentId: a),
                    TL.assistant(sessionId: s1, at: t, messageId: "msg_hd\(n)", block: TL.text("done"), stopReason: "end_turn", agentId: a)])
                hook("PostToolUse", tool: ["Bash", "Read", "Grep"][n], detail: ["ls -la", "/fake/project/x.swift", "foo"][n], at: t)
            }
            clock.advance(by: 0.2)
            for n in 0..<3 { hook("PostToolUse", tool: "Agent", detail: "研究\(n)", extra: "len=200") }
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .thinking else { return "动作不是思考中：「\(act(rec.snap(k)?.activity))」" }
            guard s.helpers.filter({ $0.done }).count == 3 else { return "3 个小助手应该都 done" }
            return nil
        })

        // ⑪ 后台子代理
        let bg = "bgb1000000000000"
        step("后台子代理：Agent 立刻返回，主线程继续读文件，小助手在自己跑 Bash", action: { [self] in
            clock.advance(by: 2)
            let t = clock.now()
            hook("PreToolUse", tool: "Agent", detail: "后台任务", at: t)
            hook("PostToolUse", tool: "Agent", detail: "后台任务", extra: "len=90", at: t.addingTimeInterval(0.096))
            tree.writeSubagentMeta(s1, agentId: bg, foreground: false, description: "后台任务")
            clock.advance(by: 1)
            let t2 = clock.now()
            // 小助手的 tool_use 先落盘（子代理按 block 实时写入），随后 hook 事件才到
            tree.appendSubagent(s1, agentId: bg, [TL.assistant(sessionId: s1, at: t2, messageId: "msg_bg1",
                                                               block: TL.toolUse(id: "toolu_bg1", name: "Bash", input: ["command": "sleep 30"]),
                                                               stopReason: nil, agentId: bg)])
            // 主线程的 tool_use 在主会话记录里
            tree.appendTranscript(s1, [TL.assistant(sessionId: s1, at: t2, messageId: "msg_m1",
                                                    block: TL.toolUse(id: "toolu_m1", name: "Read", input: ["file_path": "/fake/project/main.swift"]))])
            hook("PreToolUse", tool: "Bash", detail: "sleep 30", at: t2)
            hook("PreToolUse", tool: "Read", detail: "/fake/project/main.swift", at: t2.addingTimeInterval(0.05))
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "没有 buddy" }
            guard case .tool(let c, 1) = s.activity, c.category == .read else { return "主线程应该是 Read，实际「\(act(s.activity))」" }
            guard let h = s.helpers.first(where: { !$0.foreground && $0.active }), h.currentTool?.name == "Bash" else {
                return "后台小助手应该在跑 Bash"
            }
            return nil
        })
        step("主线程读完", action: { [self] in
            clock.advance(by: 0.3)
            hook("PostToolUse", tool: "Read", detail: "/fake/project/main.swift", extra: "len=9")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑫ 压缩
        step("压缩：PreCompact → 整理上下文", action: { [self] in
            clock.advance(by: 0.5)
            hook("PreCompact", extra: "auto")
        }, expect: expectActivity(k, "整理上下文") { $0 == .compacting })
        step("压缩完：PostCompact → 回到思考", action: { [self] in
            clock.advance(by: 4)
            hook("PostCompact")
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑬ API 重试
        step("API 重试：第 2 次 / 共 10 次", action: { [self] in
            clock.advance(by: 0.5)
            tree.appendTranscript(s1, [TL.apiError(sessionId: s1, at: clock.now(), attempt: 2, max: 10, retryInMs: 1200)])
        }, expect: expectActivity(k, "重试中 2/10") { $0 == .retrying(attempt: 2, max: 10) })
        step("重试窗口（retryInMs + 15 秒）过后没有新行：不再显示重试", measure: false, action: { [self] in
            clock.advance(by: 20)
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })

        // ⑭ 出错
        step("出错：重试到上限 + 合成的 API 错误，登记表 idle", registry: true, action: { [self] in
            clock.advance(by: 0.5)
            let t = clock.now()
            tree.appendTranscript(s1, [TL.apiError(sessionId: s1, at: t, attempt: 10, max: 10),
                                       TL.assistant(sessionId: s1, at: t.addingTimeInterval(0.01), messageId: "syn1", block: TL.text("API Error"),
                                                    stopReason: "stop_sequence", model: "<synthetic>", apiErrorMessage: true)])
            _ = tree.writeRegistry(main, status: "idle", statusUpdatedAt: t.addingTimeInterval(0.02))
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .errored else { return "动作不是出错：「\(act(rec.snap(k)?.activity))」" }
            guard hasEvent(k, { if case .turnFinished(_, _, true) = $0 { return true } else { return false } }) else { return "没有 turnFinished(errored)" }
            return nil
        })

        // ⑮ 被打断
        step("被打断：新一轮开始", registry: true, action: { [self] in
            clock.advance(by: 30)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("UserPromptSubmit", extra: "x")
            tree.appendTranscript(s1, [TL.userPrompt(sessionId: s1, at: clock.now(), text: "x")])
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })
        step("被打断：用户按了停止（没有 Stop 事件）", registry: true, action: { [self] in
            clock.advance(by: 2)
            let t = clock.now()
            tree.appendTranscript(s1, [TL.userInterrupt(sessionId: s1, at: t)])
            _ = tree.writeRegistry(main, status: "idle", statusUpdatedAt: t.addingTimeInterval(0.01))
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .interrupted else { return "动作不是被打断：「\(act(rec.snap(k)?.activity))」" }
            guard hasEvent(k, { if case .turnFinished(_, true, _) = $0 { return true } else { return false } }) else { return "没有 turnFinished(interrupted)" }
            return nil
        })
        step("3 秒后：被打断的状态消退，回到空闲", measure: false, action: { [self] in
            clock.advance(by: 3.5)
        }, expect: expectActivity(k, "空闲") { $0 == .idle })

        // ⑯ 做完（blocked）
        let uuidLast = "0b10c4ed-0000-4000-8000-00000000beef"
        step("做完：新一轮开始", registry: true, action: { [self] in
            clock.advance(by: 5)
            _ = tree.writeRegistry(main, status: "busy", statusUpdatedAt: clock.now())
            hook("UserPromptSubmit", extra: "x")
            tree.appendTranscript(s1, [TL.userPrompt(sessionId: s1, at: clock.now(), text: "x")])
        }, expect: expectActivity(k, "思考中") { $0 == .thinking })
        step("做完：Stop + 登记表 idle → 做完了（未读）", registry: true, action: { [self] in
            clock.advance(by: 4)
            let t = clock.now()
            tree.appendTranscript(s1, [TL.assistant(sessionId: s1, at: t, messageId: "msg_end", block: TL.text("done"), stopReason: "end_turn"),
                                       TL.stopHookSummary(sessionId: s1, at: t.addingTimeInterval(0.02))])
            hook("Stop", at: t.addingTimeInterval(0.02))
            _ = tree.writeRegistry(main, status: "idle", statusUpdatedAt: t.addingTimeInterval(0.06))
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .finished else { return "动作不是做完了：「\(act(rec.snap(k)?.activity))」" }
            guard s.unread else { return "应该未读" }
            guard hasEvent(k, { if case .turnFinished(_, false, false) = $0 { return true } else { return false } }) else { return "没有 turnFinished(正常)" }
            return nil
        })
        step("做完：桌面的本轮总结是 blocked（需要你处理）", action: { [self] in
            clock.advance(by: 1)
            var m = FakeClaudeTree.Meta(host: host1, cliSessionId: s1, lastActivityAt: clock.now())
            m.lastAssistantUuid = uuidLast
            m.summaryFor = uuidLast
            m.summaryCategory = "blocked"
            m.summaryDetail = "waiting for you to confirm the deploy"
            tree.writeMeta(m)
        }, expect: { [self] in
            guard let s = rec.snap(k), s.blocked else { return "blocked 应该亮起" }
            guard s.statusDetail == "waiting for you to confirm the deploy" else { return "statusDetail 不对：\(s.statusDetail ?? "nil")" }
            guard hasEvent(k, { $0 == .blocked }) else { return "没有 blocked 事件" }
            return nil
        })
        step("6 秒后：做完了消退成空闲，但 blocked / 未读保持", measure: false, action: { [self] in
            clock.advance(by: 6)
        }, expect: { [self] in
            guard let s = rec.snap(k), s.activity == .idle else { return "动作不是空闲：「\(act(rec.snap(k)?.activity))」" }
            return (s.blocked && s.unread) ? nil : "blocked/未读没有保持"
        })

        // ⑰ 空闲 → 打盹 → 睡着
        step("空闲超过 10 分钟：打盹", measure: false, action: { [self] in
            clock.advance(by: 11 * 60)
        }, expect: expectActivity(k, "打盹") { $0 == .dozing })
        step("空闲超过 45 分钟：睡着", measure: false, action: { [self] in
            clock.advance(by: 35 * 60)
        }, expect: expectActivity(k, "睡着") { $0 == .sleeping })

        // ⑱ 离场（进程被回收）
        step("进程被回收：登记文件消失，先防抖 3 秒（还在场）", measure: false, action: { [self] in
            tree.endProcess(pid: main.pid)
            Thread.sleep(forTimeInterval: 0.3)                 // 让引擎先看到文件消失，再跳时钟
        }, expect: { [self] in
            guard let s = rec.snap(k), s.presence == .present else { return "防抖期内应该还在场" }
            return nil
        })
        step("防抖 3 秒后：离场，下班工位（桌面会话、元数据还在）", registry: true, measure: false, action: { [self] in
            clock.advance(by: 3.2)
        }, expect: { [self] in
            guard let s = rec.snap(k) else { return "buddy 不该消失（下班工位）" }
            guard case .away(_, true) = s.presence else { return "presence 是 \(s.presence)，想要 away(dormant: true)" }
            guard hasEvent(k, { $0 == .departed(dormant: true) }) else { return "没有 departed(dormant) 事件" }
            return nil
        })

        // ⑲ 同一个身份回来
        let sid1b = "5e1a0000-0000-4000-8000-000000000002"
        step("同一个身份回来：新进程带着同一个 hostSessionId", registry: true, action: { [self] in
            clock.advance(by: 30)
            tree.writeMeta(.init(host: host1, cliSessionId: sid1b, lastActivityAt: clock.now()))
            let back = FakeClaudeTree.Session(pid: 91002, sessionId: sid1b, host: host1, name: "回放·主会话", startedAt: clock.now())
            _ = tree.writeRegistry(back, status: "idle", statusUpdatedAt: clock.now())
        }, expect: { [self] in
            guard let s = rec.snap(k), s.presence == .present else { return "还没回来" }
            guard s.seat == seatBefore, s.salt == saltBefore else { return "座位/外观变了：seat \(s.seat) vs \(seatBefore)" }
            guard s.pid == 91002, s.appearedAfterLaunch else { return "pid / appearedAfterLaunch 不对" }
            guard rec.snapshots.filter({ $0.key == k }).count == 1 else { return "出现了重复的 buddy" }
            let arrivals = rec.events.filter { $0.key == k && $0.kind == .arrived(freshAfterLaunch: true) }.count
            return arrivals >= 2 ? nil : "没有第二次 arrived 事件"
        })

        // ⑳ 终端会话进出场
        let sidT = "7e57e2a0-0000-4000-8000-000000000003"
        let term = FakeClaudeTree.Session(pid: 91003, sessionId: sidT, host: nil, name: nil, startedAt: clock.now())
        step("终端会话（无 hostSessionId）进场：key 是 t:<sessionId>", registry: true, action: { [self] in
            tree.appendTranscript(sidT, [TL.customTitle(sessionId: sidT, "终端里的会话")])
            _ = tree.writeRegistry(term, status: "idle", statusUpdatedAt: clock.now())
        }, expect: { [self] in
            guard let s = rec.snap("t:" + sidT) else { return "终端 buddy 没出现" }
            guard s.origin == .terminal, s.title == "终端里的会话" else { return "来源/标题不对：\(s.origin) \(s.title)" }
            return nil
        })
        step("终端会话进程结束：离场后不是下班工位", registry: true, measure: false, action: { [self] in
            tree.endProcess(pid: term.pid)
            Thread.sleep(forTimeInterval: 0.3)
            clock.advance(by: 3.2)
        }, expect: { [self] in
            guard let s = rec.snap("t:" + sidT), case .away(_, false) = s.presence else { return "应该是 away(dormant: false)" }
            return nil
        })
        step("8 秒后收回工位", measure: false, action: { [self] in
            clock.advance(by: 8.2)
        }, expect: { [self] in
            rec.snap("t:" + sidT) == nil ? nil : "终端 buddy 还在"
        })

        // 延迟基准：孤立的登记表变化 → 快照回调
        var benchLats: [Double] = []
        if latencyRuns > 0 && !aborted {
            print("  延迟基准：\(latencyRuns) 次孤立的登记表变化（busy ↔ waiting）…")
            var status = "busy"
            let back = FakeClaudeTree.Session(pid: 91002, sessionId: sid1b, host: host1, name: "回放·主会话", startedAt: main.startedAt)
            _ = tree.writeRegistry(back, status: "busy", statusUpdatedAt: clock.now())
            Thread.sleep(forTimeInterval: 0.3)
            for n in 0..<latencyRuns {
                Thread.sleep(forTimeInterval: 0.12 + Double(n % 7) * 0.013)       // 错开相位，不和轮询节拍同步
                status = status == "busy" ? "waiting" : "busy"
                let want: (Activity) -> Bool = status == "busy" ? { $0 == .thinking } : { $0 == .asking }
                let t0 = Date()
                _ = tree.writeRegistry(back, status: status, waitingFor: status == "waiting" ? "input needed" : nil, statusUpdatedAt: clock.now())
                var got = false
                while Date().timeIntervalSince(t0) < 2 {
                    if let s = rec.snap(k), want(s.activity) { got = true; break }
                    Thread.sleep(forTimeInterval: 0.001)
                }
                if got { benchLats.append(Date().timeIntervalSince(t0) * 1000) }
            }
            benchLats.sort()
        }

        // 收尾
        let diag = store.diagnostics()
        print("  诊断：" + diag.sourceStatus.joined(separator: " | "))
        if verbose { for r in results { print("    \(r.ok ? "✓" : "✗") \(r.name) \(r.note)") } }
        store.stop()

        let failed = results.filter { !$0.ok }
        let lats = results.compactMap { $0.latencyMs }.sorted()
        let regLats = results.filter { $0.isRegistryChange }.compactMap { $0.latencyMs }.sorted()
        func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
        print("")
        print(String(format: "步骤 %d 个，通过 %d，失败 %d", results.count, results.count - failed.count, failed.count))
        print(String(format: "写文件 → 快照回调延迟（全部步骤）：p50 %.0f ms  p95 %.0f ms  max %.0f ms", pct(lats, 0.5), pct(lats, 0.95), lats.last ?? 0))
        print(String(format: "登记表变化 → 快照回调延迟（%d 步）：p50 %.0f ms  p95 %.0f ms  max %.0f ms", regLats.count, pct(regLats, 0.5), pct(regLats, 0.95), regLats.last ?? 0))
        if !benchLats.isEmpty {
            print(String(format: "孤立变化的延迟基准（%d 次）：p50 %.0f ms  p95 %.0f ms  max %.0f ms", benchLats.count, pct(benchLats, 0.5), pct(benchLats, 0.95), benchLats.last ?? 0))
        }
        if failed.isEmpty { print("✓ 回放通过") } else { for f in failed { print("✗ \(f.name)：\(f.note)") } }
        return failed.isEmpty
    }
}
