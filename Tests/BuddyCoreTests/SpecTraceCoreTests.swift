import Foundation
import Testing
@testable import BuddyCore

/// QA 定稿（规格追踪：任务书第 4、5 节）：`QA/spec-trace-core-final.md` 里原来「没有专门测试」的条目在这里逐条补上断言。
///
/// 写法：每个测试先按任务书原文写要求（数字、取值），再断言；已经有测试钉住的条目不重复。
/// 名字前面的 `4.x` / `5.x` 是追踪表里的编号。全部用假时钟 / 临时目录，不碰真实的 ~/.claude，不依赖真实时间（只有 QoS 那一条要真的起一次后台队列）。
@Suite struct SpecTraceCoreTests {
    typealias K = StateRuleKit
    let sid = "dddddddd-0000-4000-8000-000000000042"
    func at(_ s: Double) -> Date { Harness.at(s) }

    /// 项目根目录（测试文件往上三层），源码审计用。
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func source(_ rel: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/" + rel), encoding: .utf8)
    }
    /// 去掉整行 // 注释和行尾 // 注释之后的代码行。
    static func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { l -> String? in
            var s = String(l)
            if let r = s.range(of: "//") { s = String(s[..<r.lowerBound]) }
            return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s
        }
    }
    /// Sources/<target> 下所有 .swift 文件的（相对路径, 去掉注释的代码行）。
    static func swiftFiles(_ targets: [String]) throws -> [(name: String, code: [String])] {
        var out: [(String, [String])] = []
        for t in targets {
            let dir = root.appendingPathComponent("Sources/" + t)
            guard let e = FileManager.default.enumerator(atPath: dir.path) else { continue }
            for case let rel as String in e where rel.hasSuffix(".swift") {
                out.append(("\(t)/\(rel)", codeLines(try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8))))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - 4.1 登记表

    @Test("4.1-13 pidDomain / nameSource / nameSince / updatedAt / peerProtocol / peerFeatures 存在时照常解析；messagingSocketPath 不留下")
    func registryOtherFieldsAreToleratedAndTheSocketPathIsNeverKept() throws {
        let json = #"{"pid":4242,"sessionId":"aaaaaaaa-0000-4000-8000-000000000001","cwd":"/x","startedAt":1790654400123,"procStart":"Tue Sep 29 04:00:00 2026","pidDomain":"darwin","version":"2.1.284","kind":"interactive","entrypoint":"claude-desktop","hostSessionId":"local_abc","name":"n","nameSource":"user","nameSince":1790654400456,"status":"busy","updatedAt":1790654401000,"statusUpdatedAt":1790654400999,"peerProtocol":1,"peerFeatures":["a","b"],"messagingSocketPath":"/tmp/cc-socks/x.sock"}"#
        let r = try #require(RegistryScanner.parse(Data(json.utf8)).flatMap { $0 })
        #expect(r.pid == 4242 && r.status == .busy && r.kind == "interactive")
        #expect(r.pidDomain == "darwin")
        #expect(r.nameSource == "user")
        #expect(abs((r.nameSince ?? .distantPast).timeIntervalSince1970 - 1790654400.456) < 0.0005)
        #expect(abs((r.updatedAt ?? .distantPast).timeIntervalSince1970 - 1790654401.0) < 0.0005)
        #expect(abs((r.statusUpdatedAt ?? .distantPast).timeIntervalSince1970 - 1790654400.999) < 0.0005)
        // messagingSocketPath：不要使用——记录里根本没有存它的字段（peerProtocol / peerFeatures 也没有）
        let labels = Mirror(reflecting: r).children.compactMap { $0.label?.lowercased() }
        #expect(!labels.contains { $0.contains("socket") || $0.contains("messaging") || $0.contains("peer") }, "\(labels)")
    }

    @Test("4.1-28 延迟的实测值（waiting 约 49 ms、idle 约 8 ms）套进状态机：时间线对，中间不闪错误的状态")
    func theObservedRegistryLatenciesProduceTheRightTimeline() {
        // 权限请求：Pre 先到，登记表约 49 ms 之后才变 waiting
        do {
            let (h, f) = K.idleSession()
            K.startTurn(h, f)
            h.advance(2)
            let t = h.now
            h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "git push", at: t)
            h.advance(0.02); h.poll()
            guard case .tool(let c, 1)? = h.snap(K.key)?.activity else { Issue.record("登记表还没变时应该还是 Bash：\(String(describing: h.snap(K.key)?.activity))"); return }
            #expect(c.name == "Bash")
            h.advance(0.029)                                                                   // t + 49 ms
            h.tree.hook(f.sid, "Notification", extra: "Claude needs your permission to use Bash", at: h.now)
            h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: h.now)
            h.advance(0.001); h.poll()
            guard case .waitingApproval(let tool)? = h.snap(K.key)?.activity else { Issue.record("登记表变 waiting 后应该是等批准：\(String(describing: h.snap(K.key)?.activity))"); return }
            #expect(tool?.name == "Bash" && tool?.detail == "git push")
            #expect(near(h.snap(K.key)?.activitySince, t.addingTimeInterval(0.049)))
            #expect(h.kinds(K.key).filter { if case .needsUser = $0 { return true } else { return false } }.count == 1)
        }
        // 一轮结束：Stop 先到，登记表约 8 ms 之后才翻 idle
        do {
            let (h, f) = K.idleSession()
            K.startTurn(h, f)
            h.advance(3)
            let t = h.now
            h.clearEvents()
            h.tree.hook(f.sid, "Stop", at: t)
            h.advance(0.004); h.poll()
            expectActivity(h.snap(K.key), .finished)                                          // Stop 一到就是「做完了」，不等登记表
            h.advance(0.004)
            h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now)            // t + 8 ms
            h.poll()
            expectActivity(h.snap(K.key), .finished)                                          // 登记表翻过来之后不闪回别的状态
            h.run(for: 0.3)
            expectActivity(h.snap(K.key), .finished)
            #expect(K.turnFinishedEvents(h).count == 1)
        }
    }

    // MARK: - 4.2 hook

    @Test("4.2-04 任务书列出的 10 个 hook 事件都认得；没见过的事件名被忽略")
    func allTenRegisteredHookEventsAreRecognised() {
        let names = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SubagentStop", "PreCompact", "PostCompact"]
        let consts = [HookEvent.sessionStart, HookEvent.sessionEnd, HookEvent.prompt, HookEvent.pre, HookEvent.post, HookEvent.notification,
                      HookEvent.stop, HookEvent.subagentStop, HookEvent.preCompact, HookEvent.postCompact]
        #expect(consts == names)
        for n in names {
            let e = LineSanitizer.parseHookLine(#"{"ts":1790654400000,"ev":"\#(n)","tool":"","detail":"","extra":""}"#)
            #expect(e?.ev == n, "\(n) 应该被解析出来")
        }
        // 引擎：十个事件按一个会话的真实次序依次进来，每一个都有对应的处理、不崩；最后不留悬空的调用
        let (h, f) = K.idleSession()
        K.startTurn(h, f)                                                                     // UserPromptSubmit（SessionStart 在 idleSession 里）
        h.advance(1); h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/a.swift"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/a.swift", extra: "len=3"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make"); h.poll()
        h.advance(0.1); h.tree.hook(f.sid, "Notification", extra: "Claude needs your permission to use Bash"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "PreCompact", extra: "auto"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "PostCompact"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "SubagentStop"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "FutureEventNobodyKnows"); h.poll()                // 没见过的事件名：忽略
        h.advance(0.2); h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "SessionEnd", extra: "other"); h.poll()
        #expect(h.snap(K.key) != nil)
        #expect(h.engine.openMainTools(key: K.key).isEmpty)
        #expect(h.snap(K.key)?.phase == .idle)
    }

    @Test("4.2 extra：Notification / PreCompact / SessionStart / SessionEnd / PostToolUse 的 extra 原样保留；UserPromptSubmit 的 extra（用户输入）一律丢掉")
    func hookExtraPayloadsFollowTheTaskBook() {
        func extra(_ ev: String, _ x: String) -> String? {
            LineSanitizer.parseHookLine(#"{"ts":1790654400000,"ev":"\#(ev)","tool":"","detail":"","extra":"\#(x)"}"#)?.extra
        }
        #expect(extra("Notification", "Claude needs your permission to use Bash") == "Claude needs your permission to use Bash")
        #expect(extra("PreCompact", "auto") == "auto" && extra("PreCompact", "manual") == "manual")
        for src in ["startup", "resume", "clear", "compact", "fork"] { #expect(extra("SessionStart", src) == src) }
        #expect(extra("SessionEnd", "logout") == "logout")
        #expect(extra("PostToolUse", "len=1234") == "len=1234")
        #expect(extra("UserPromptSubmit", "请帮我改掉这个 bug（这是用户输入，绝不能留下）") == "")
    }

    @Test("4.2 detail：按工具取不同的参数；MultiEdit / NotebookEdit / TodoWrite 的 detail 永远是空")
    func toolDetailKeyFollowsEveryRuleOfTheTaskBook() {
        typealias Case = (name: String, input: [String: Any], want: String)
        let cases: [Case] = [
            ("Bash", ["command": "npm test", "description": "run the tests"], "npm test"),
            ("Read", ["file_path": "/a/b.swift", "offset": 3], "/a/b.swift"),
            ("Edit", ["file_path": "/a/e.swift", "old_string": "x", "new_string": "y"], "/a/e.swift"),
            ("Write", ["file_path": "/a/w.swift", "content": "c"], "/a/w.swift"),
            ("Grep", ["pattern": "TODO", "path": "/a"], "TODO"),
            ("Glob", ["pattern": "**/*.swift"], "**/*.swift"),
            ("WebFetch", ["url": "https://x.dev/a", "prompt": "p"], "https://x.dev/a"),
            ("WebSearch", ["query": "swift testing"], "swift testing"),
            ("Task", ["description": "调研三篇文献", "prompt": "p"], "调研三篇文献"),
            ("Agent", ["description": "整理笔记", "prompt": "p"], "整理笔记"),
            ("Skill", ["skill": "brainstorming"], "brainstorming"),
            ("mcp__x__y", ["description": "first description", "other": 1], "first description"),
            ("MultiEdit", ["file_path": "/a/m.swift", "edits": [["old_string": "a", "new_string": "b"]]], ""),
            ("NotebookEdit", ["notebook_path": "/a/n.ipynb", "new_source": "x"], ""),
            ("TodoWrite", ["todos": [["content": "a", "status": "pending"]]], ""),
        ]
        for c in cases { #expect(ToolDetail.key(name: c.name, input: c.input) == c.want, "\(c.name)") }
        // 超长截到 160 字
        #expect(ToolDetail.key(name: "Bash", input: ["command": String(repeating: "x", count: 300)]).count == 160)
        // WebFetch 同时有 url 和 query 时取 url
        #expect(ToolDetail.key(name: "WebFetch", input: ["url": "U", "query": "Q"]) == "U")
    }

    @Test("4.2-17 桌面 App 里的会话也触发这些 hook：桌面会话和终端会话喂同一串 hook，动作时间线完全一样")
    func desktopAndTerminalSessionsAreDrivenByTheSameHookStream() {
        func timeline(desktop: Bool) -> [String] {
            let h = Harness()
            let s = FakeClaudeTree.Session(pid: 4242, sessionId: sid, host: desktop ? "local_22222222-0000-4000-8000-000000000042" : nil,
                                           name: "x", startedAt: h.now.addingTimeInterval(-60))
            h.tree.appendTranscript(sid, [TL.userPrompt(sessionId: sid, at: h.now.addingTimeInterval(-50))])
            h.tree.hook(sid, "SessionStart", extra: "startup", at: h.now.addingTimeInterval(-50))
            h.tree.writeRegistry(s, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-40))
            h.poll()
            var out: [String] = []
            func note(_ tag: String) { out.append(tag + " " + String(describing: h.only()?.activity)) }
            note("空闲")
            h.advance(1); h.tree.writeRegistry(s, status: "busy", statusUpdatedAt: h.now); h.tree.hook(sid, "UserPromptSubmit", at: h.now.addingTimeInterval(0.09))
            h.advance(0.1); h.poll(); note("提交")
            h.advance(1); h.tree.hook(sid, "PreToolUse", tool: "Read", detail: "/a.swift"); h.poll(); note("Read")
            h.advance(0.5); h.tree.hook(sid, "PostToolUse", tool: "Read", detail: "/a.swift", extra: "len=9"); h.poll(); note("Read 完")
            h.advance(1); h.tree.hook(sid, "PreToolUse", tool: "Bash", detail: "git push"); h.poll(); note("Bash")
            h.advance(0.05); h.tree.hook(sid, "Notification", extra: "Claude needs your permission to use Bash")
            h.tree.writeRegistry(s, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: h.now); h.poll(); note("等批准")
            h.advance(30); h.tree.hook(sid, "PostToolUse", tool: "Bash", detail: "git push", extra: "len=2")
            h.tree.writeRegistry(s, status: "busy", statusUpdatedAt: h.now); h.poll(); note("批准之后")
            h.advance(2); h.tree.hook(sid, "Stop"); h.tree.writeRegistry(s, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(0.05))
            h.advance(0.1); h.poll(); note("做完了")
            return out
        }
        let d = timeline(desktop: true), t = timeline(desktop: false)
        #expect(d == t)
        #expect(d.count == 8 && d.last?.contains("finished") == true, "\(d)")
    }

    // MARK: - 4.3 会话记录

    @Test("4.3-02 目录名以 - 开头也照常找到会话记录（不经过 shell 通配）")
    func transcriptLocatorHandlesDirectoryNamesStartingWithADash() throws {
        let root = FileIO.temporaryDirectory + "buddy-spec-dash-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let projects = root + "/projects"
        for d in ["--weird-dir", "-Users-USER-Desktop-proj", "plain"] {
            try FileManager.default.createDirectory(atPath: projects + "/" + d, withIntermediateDirectories: true)
        }
        let file = projects + "/-Users-USER-Desktop-proj/" + sid + ".jsonl"
        FakeClaudeTree.writeInPlace(file, Data("{}\n".utf8))
        #expect(TranscriptLocator.find(sessionId: sid, projectsDir: projects) == file)
        #expect(TranscriptLocator.find(sessionId: "eeeeeeee-0000-4000-8000-000000000042", projectsDir: projects) == nil)
    }

    @Test("4.3-04 流式读取的默认参数是每次最多 1 MiB、单行上限 4 MiB；跨 1 MiB 块边界的行完整交付")
    func tailerDefaultsAndLinesAcrossTheMiBBoundary() {
        let cfg = JSONLTailer.Config()
        #expect(cfg.chunkBytes == 1_048_576)
        #expect(cfg.maxLineBytes == 4_194_304)
        let mib = 1 << 20
        // 第一行到块边界前 4 字节结束（含换行）；第二行 2,000,000 字节，跨过 1 MiB 和 2 MiB 两个块边界；第三行很短
        let f = TempFile(name: "mib")
        f.write(String(repeating: "a", count: mib - 5) + "\n" + String(repeating: "b", count: 2_000_000) + "\n" + "cc\n")
        let t = JSONLTailer(path: f.path)
        let r = collect(t)
        #expect(r.lines.map { $0.utf8.count } == [mib - 5, 2_000_000, 2])
        #expect(r.lines.count == 3 && Set(r.lines[0]) == ["a"] && Set(r.lines[1]) == ["b"] && r.lines[2] == "cc")
        #expect(r.result.bytesRead == (mib - 4) + 2_000_001 + 3)
        #expect(t.committedOffset == UInt64(r.result.bytesRead))
        // 第一行恰好在 1 MiB 处结束（换行是第 1 MiB 个字节）
        let g = TempFile(name: "mib2")
        g.write(String(repeating: "x", count: mib - 1) + "\n" + "yy\n")
        let r2 = collect(JSONLTailer(path: g.path))
        #expect(r2.lines.map { $0.utf8.count } == [mib - 1, 2])
    }

    @Test("4.3-17 turn_duration（终端会话才有）：会话记录里有它时，「本轮用时」以它为准")
    func turnDurationFromTheTranscriptCorrectsTheShownTurnLength() {
        func lastDuration(withTurnDuration: Bool) -> TimeInterval? {
            let (h, f) = K.idleSession()
            K.startTurn(h, f)
            h.advance(8)
            let end = h.now
            var lines: [[String: Any]] = []
            if withTurnDuration { lines.append(TL.system(sessionId: f.sid, at: end, subtype: "turn_duration", extra: ["durationMs": 4012])) }
            lines.append(TL.stopHookSummary(sessionId: f.sid, at: end.addingTimeInterval(0.01)))
            h.tree.appendTranscript(f.sid, lines)
            h.tree.hook(f.sid, "Stop", at: end)
            h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: end.addingTimeInterval(0.05))
            h.advance(0.1); h.poll()
            return h.snap(K.key)?.lastTurnDuration
        }
        let corrected = lastDuration(withTurnDuration: true), observed = lastDuration(withTurnDuration: false)
        #expect(abs((corrected ?? 0) - 4.012) < 0.001, "有 turn_duration：\(String(describing: corrected))")
        #expect((observed ?? 0) > 7.5, "对照（没有 turn_duration）是观察到的 ≈ 8 秒：\(String(describing: observed))")
    }

    @Test("4.3-18 cost-state 是进程退出时才写的记账行：不参与任何判断、不计入 token")
    func costStateLinesAreIgnored() {
        let assistant = FakeClaudeTree.jsonLine(TL.assistant(sessionId: sid, at: at(1), messageId: "c1", block: TL.text(), stopReason: "end_turn",
                                                             usage: TL.usage(output: 77)))
        // cost-state 里带着看起来很像 usage / assistant 的字段（能通过字节预过滤），但它的 type 不是 assistant
        let cost = FakeClaudeTree.jsonLine(["type": "cost-state", "costState": ["role": "assistant", "usage": ["input_tokens": 999_999, "output_tokens": 999_999]]])
        let withCost = TempFile(name: "cost1"), without = TempFile(name: "cost0")
        withCost.write(assistant + cost)
        without.write(assistant)
        let l = TokenLedger(ledgerPath: nil, queue: DispatchQueue(label: "spec.cost"))
        l.setGroup(key: "k", transcripts: [withCost.path], helpers: [])
        _ = l.waitUntilIdle(timeout: 60)
        #expect(l.totals(forKey: "k").breakdown == TokenBreakdown(input: 0, output: 77, cacheWrite: 0, cacheRead: 0))
        let a = TranscriptReader(path: withCost.path), b = TranscriptReader(path: without.path)
        a.bootstrap(); b.bootstrap()
        var fa = a.facts, fb = b.facts
        fa.linesSeen = 0; fb.linesSeen = 0                                                    // 只有「读过几行」不同
        #expect(fa == fb)
    }

    @Test("4.3-36 token 预过滤：先在字节里找 \"usage\" 和 \"assistant\"，命中了才解码——转义拼写的键连解码都轮不到")
    func theByteFilterRunsBeforeAnyDecoding() throws {
        func line(_ id: String, output: Int) -> String {
            String(decoding: FakeClaudeTree.jsonLine(TL.assistant(sessionId: sid, at: at(1), messageId: id, block: TL.text(), stopReason: "end_turn",
                                                                  usage: TL.usage(output: output))), as: UTF8.self)
        }
        let plain1 = line("m1", output: 10), plain2 = line("m4", output: 5)
        // 同一行内容，只把 "usage" 写成 "us\u0061ge"、把 "assistant" 写成 "\u0061ssistant"：JSON 解码器看到的键和值和原来一样，原始字节里却找不到这两个词
        let escapedUsage = line("m2", output: 1000).replacingOccurrences(of: "\"usage\"", with: "\"us\\u0061ge\"")
        let escapedAssistant = line("m3", output: 2000).replacingOccurrences(of: "\"assistant\"", with: "\"\\u0061ssistant\"")
        #expect(!escapedUsage.contains("\"usage\"") && !escapedAssistant.contains("\"assistant\""))
        // 对照：转义拼写的行确实是合法的 assistant + usage 行，解码器认得（所以没被计入的唯一原因是预过滤）
        for (text, out) in [(escapedUsage, 1000), (escapedAssistant, 2000)] {
            let parsed = try #require(Array(text.utf8).withUnsafeBufferPointer { TranscriptLineParser.parse($0) })
            #expect(parsed.kind == .assistant && parsed.usage?.output == out && parsed.messageId != nil)
        }
        let f = TempFile(name: "prefilter")
        f.write(plain1 + escapedUsage + escapedAssistant + plain2)
        let ledger = TokenLedger(ledgerPath: nil, queue: DispatchQueue(label: "spec.prefilter"))
        ledger.setGroup(key: "k", transcripts: [f.path], helpers: [])
        _ = ledger.waitUntilIdle(timeout: 60)
        #expect(ledger.totals(forKey: "k").breakdown.output == 15, "只有两行原样的算数：\(ledger.totals(forKey: "k").breakdown)")
    }

    /// 轮询直到条件成立（账本的 `pass()` 在把「扫描中」标记清掉之后才写盘，所以读文件前要等一小会儿）。
    func eventually(timeout: TimeInterval = 30, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; Thread.sleep(forTimeInterval: 0.005) }
        return cond()
    }
    /// 等账本的一次扫描（含它末尾的写盘）完全结束：自己的串行队列上排一个空块。
    func settle(_ l: TokenLedger, _ q: DispatchQueue) {
        _ = l.waitUntilIdle(timeout: 60)
        q.sync {}
    }

    /// 读账本文件里某个会话记录的输出 token 计数。
    func ledgerOutput(_ ledgerPath: String, file: String) -> Int? {
        guard let data = FileIO.readAll(ledgerPath, maxBytes: 1 << 20), let obj = SafeJSON.object(data),
              let files = obj["files"] as? [String: Any], let d = files[file] as? [String: Any] else { return nil }
        return (d["output"] as? NSNumber)?.intValue
    }

    func assistantLine(_ id: String, output: Int, at s: Double = 1) -> Data {
        FakeClaudeTree.jsonLine(TL.assistant(sessionId: sid, at: at(s), messageId: id, block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: output)))
    }

    @Test("4.3-40 账本文件最多 30 秒写一次（虚拟时钟：10 秒、29.9 秒都不写，30.1 秒才写）")
    func theLedgerFileIsWrittenAtMostOnceEvery30Seconds() {
        let clock = VirtualClock(frozenAt: Harness.epoch)
        let ledgerFile = TempFile(name: "l30"), f = TempFile(name: "t30")
        f.write(assistantLine("m1", output: 10))
        let q = DispatchQueue(label: "spec.l30")
        let l = TokenLedger(ledgerPath: ledgerFile.path, now: { clock.now() }, queue: q)
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        settle(l, q)
        #expect(ledgerOutput(ledgerFile.path, file: f.path) == 10, "第一次统计完马上写一次")
        f.append(assistantLine("m2", output: 20))
        clock.advance(by: 10); l.poke(); settle(l, q)
        #expect(l.totals(forKey: "k").breakdown.output == 30, "内存里已经是新的")
        #expect(ledgerOutput(ledgerFile.path, file: f.path) == 10, "10 秒：还在节流窗口里，不写盘")
        clock.advance(by: 19.9); l.poke(); settle(l, q)
        #expect(ledgerOutput(ledgerFile.path, file: f.path) == 10, "距上次写盘 29.9 秒：仍然不写")
        clock.advance(by: 0.2); l.poke(); settle(l, q)
        #expect(ledgerOutput(ledgerFile.path, file: f.path) == 30, "距上次写盘 30.1 秒：写")
    }

    @Test("4.3-41 退出时也写一次：SessionStore.stop() 把还在 30 秒节流窗口里的增量落盘")
    func stoppingTheStoreWritesTheLedgerOneLastTime() {
        let root = FileIO.temporaryDirectory + "buddy-spec-exit-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let clock = VirtualClock(frozenAt: Harness.epoch)
        let probe = FakeProcessProbe()
        let tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        tree.prepare()
        var eo = SessionEngine.Options(paths: tree.paths, now: { clock.now() }, probe: probe)
        eo.ledgerQueue = testLedgerQueue()
        eo.persist = true; eo.scanTokens = true
        var so = SessionStore.Options(engine: eo)
        so.usePolling = true
        so.callbackQueue = DispatchQueue(label: "spec.exit.callback")
        let store = SessionStore(options: so)
        let session = FakeClaudeTree.Session(pid: 1001, sessionId: DesktopFixture.sid, host: DesktopFixture.host, name: "退出测试",
                                             startedAt: clock.now().addingTimeInterval(-30))
        let transcript = tree.transcriptPath(DesktopFixture.sid)
        let ledgerPath = tree.paths.ledgerFile
        tree.appendTranscriptRaw(DesktopFixture.sid, assistantLine("e1", output: 1000))
        tree.writeRegistry(session, status: "idle", statusUpdatedAt: clock.now().addingTimeInterval(-20))
        store.start()
        _ = store.pollNow(); store.waitForTokenScan(timeout: 60)
        #expect(eventually { ledgerOutput(ledgerPath, file: transcript) == 1000 }, "第一次统计完就写了一次")
        // 追加一条：账本扫到了，但 30 秒内不写盘
        tree.appendTranscriptRaw(DesktopFixture.sid, assistantLine("e2", output: 500, at: 2))
        clock.advance(by: 1)
        _ = store.pollNow(); store.waitForTokenScan(timeout: 60)
        _ = store.pollNow()
        #expect(eventually { store.currentSnapshots.first?.tokens.output == 1500 }, "内存里已经是 1500")
        Thread.sleep(forTimeInterval: 0.3)                                                    // 给一次（不该发生的）写盘留够时间
        #expect(ledgerOutput(ledgerPath, file: transcript) == 1000, "退出之前，节流窗口里的增量只在内存里")
        store.stop()
        #expect(ledgerOutput(ledgerPath, file: transcript) == 1500, "stop() 之后账本里已经有这一条")
    }

    @Test("4.3-42 第一次扫大文件放到后台低优先级：默认扫描队列跑在 .background（从最低优先级提交，测到的是队列自己的 QoS）")
    func theDefaultScanQueueRunsAtBackgroundQoS() {
        let f = TempFile(name: "qos")
        f.write(assistantLine("q1", output: 1))
        // 队列本身的 QoS 属性（同步读，不用等它被调度）：默认扫描队列就是 .background
        #expect(TokenLedger.makeDefaultQueue().qos.qosClass == .background, "默认扫描队列的 QoS 应该是 .background")
        // 再看真的跑在什么 QoS 上：机器被别的进程占满时 .background 队列会被饿死几十秒（R4b-01），等不到回调时不下结论（上面那条已经钉住了属性）
        let l = TokenLedger(ledgerPath: nil)                                                   // 默认队列
        let sem = DispatchSemaphore(value: 0)
        var seen = QOS_CLASS_UNSPECIFIED
        l.onChange = { seen = qos_class_self(); sem.signal() }
        DispatchQueue.global(qos: .background).async { l.setGroup(key: "k", transcripts: [f.path], helpers: []) }
        if sem.wait(timeout: .now() + 90) == .success { #expect(seen == QOS_CLASS_BACKGROUND, "扫描线程的 QoS 是 \(seen)") }
    }

    @Test("4.3-43 一次只扫一个文件：所有扫描都在同一条串行后台队列上、pass() 里按顺序逐个 scan，没有任何并发原语")
    func theLedgerScansOneFileAtATimeOnOneSerialQueue() throws {
        let code = Self.codeLines(try Self.source("BuddyCore/Ingest/TokenLedger.swift")).joined(separator: "\n")
        #expect(code.contains(#"DispatchQueue(label: "buddy.tokenscan", qos: .background)"#), "默认队列必须是 .background 的串行队列")
        for banned in [".concurrent", "concurrentPerform", "DispatchQueue.global", "OperationQueue", "Task {", "Task.detached", "Thread(", "DispatchGroup", "async(group"] {
            #expect(!code.contains(banned), "账本里不该出现并发原语 \(banned)")
        }
        // pass()：先取出「还有人在用」的文件列表，再逐个 scan
        let start = try #require(code.range(of: "private func pass()")), end = try #require(code.range(of: "private func refreshDetached()"))
        let body = String(code[start.upperBound..<end.lowerBound])
        #expect(body.contains("for f in list") && body.contains("scan(f)"))
        #expect(body.components(separatedBy: "scan(").count == 2, "pass() 里只有一处 scan 调用")
    }

    // MARK: - 4.4 桌面元数据

    @Test("4.4-03/04/05 桌面会话元数据：任务书列出的字段全部读出来；blocked = status_category 是 blocked 且 postTurnSummaryFor 等于 lastAssistantUuid")
    func desktopMetadataParsesEveryListedField() throws {
        let json = #"{"sessionId":"local_aaaa","cliSessionId":"cli-2","priorCliSessionIds":["cli-0","cli-1"],"cwd":"/w/p","originCwd":"/w/o","title":"标题","titleSource":"auto","model":"claude-opus-5","effort":"high","permissionMode":"acceptEdits","isArchived":true,"createdAt":1790650800000,"lastActivityAt":1790654300000,"lastFocusedAt":1790654350000,"completedTurns":7,"lastAssistantUuid":"uuid-9","postTurnSummary":{"status_category":"blocked","needs_action":"yes","status_detail":"Waiting for you to confirm the deploy"},"postTurnSummaryFor":"uuid-9","remoteMcpServersConfig":[{"x":1}]}"#
        let m = try #require(DesktopMetaReader.parse(Data(json.utf8), path: "/x/local_aaaa.json"))
        #expect(m.hostSessionId == "local_aaaa" && m.cliSessionId == "cli-2")
        #expect(m.priorCliSessionIds == ["cli-0", "cli-1"] && m.allCliSessionIds == ["cli-0", "cli-1", "cli-2"])
        #expect(m.cwd == "/w/p" && m.originCwd == "/w/o" && m.title == "标题" && m.titleSource == "auto")
        #expect(m.model == "claude-opus-5" && m.effort == "high" && m.permissionMode == "acceptEdits" && m.isArchived)
        #expect(m.createdAt == Date(timeIntervalSince1970: 1790650800) && m.lastActivityAt == Date(timeIntervalSince1970: 1790654300))
        #expect(m.lastFocusedAt == Date(timeIntervalSince1970: 1790654350) && m.completedTurns == 7)
        #expect(m.lastAssistantUuid == "uuid-9" && m.postTurnSummaryFor == "uuid-9")
        #expect(m.postTurnSummary?.statusCategory == "blocked" && m.postTurnSummary?.needsAction == "yes")
        #expect(m.postTurnSummary?.statusDetail == "Waiting for you to confirm the deploy")
        #expect(m.summaryIsCurrent && m.isBlocked)
        // completed 不算 blocked；总结不是针对最新一条 assistant 消息的（旧总结）也不算
        let completed = try #require(DesktopMetaReader.parse(Data(json.replacingOccurrences(of: "\"blocked\"", with: "\"completed\"").utf8), path: "/x"))
        #expect(!completed.isBlocked)
        let stale = try #require(DesktopMetaReader.parse(Data(json.replacingOccurrences(of: "\"postTurnSummaryFor\":\"uuid-9\"", with: "\"postTurnSummaryFor\":\"uuid-8\"").utf8), path: "/x"))
        #expect(!stale.isBlocked)
    }

    @Test("4.4-06 元数据里没有表示「运行中」的字段：就算文件里多出这样的键，也不能把 idle 的会话变成 busy")
    func desktopMetadataCannotMakeAnIdleSessionBusy() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-40))
        let json = #"{"sessionId":"\#(DesktopFixture.host)","cliSessionId":"\#(f.sid)","title":"t","status":"running","isRunning":true,"running":true,"lastActivityAt":\#(TimeUtil.millis(h.now))}"#
        try? FileManager.default.createDirectory(atPath: h.tree.metaDir, withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(h.tree.metaDir + "/" + DesktopFixture.host + ".json", Data(json.utf8))
        h.poll(); h.run(for: 2)
        #expect(h.snap(DesktopFixture.key)?.phase == .idle)
        expectActivity(h.snap(DesktopFixture.key), .idle)
    }

    // MARK: - 4.0 / 4.6 只读与安全红线

    @Test("4.0-02 旧笔记 DATA-SOURCES.md 只是参考：代码里没有任何地方读它，也不依赖 ~/.claude/monitor 下的脚本")
    func theOldDataSourcesNoteIsNeverRead() throws {
        var bad: [String] = []
        // FakeTree 是往假 home 里写测试数据的夹具：它写的假 settings.json 里模仿 ccmon 的 hook 注册（命令是 $HOME/.claude/monitor/hook.sh），不是读
        for file in try Self.swiftFiles(["BuddyCore", "BuddyStage", "BuddyOffice", "buddyctl", "buddydump"]) where file.name != "BuddyCore/Tools/FakeTree.swift" {
            for line in file.code where line.range(of: #"DATA-SOURCES|\.claude/monitor/|monitor/hook\.sh|close-by-tty"#, options: .regularExpression) != nil {
                bad.append("\(file.name)：\(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    /// 递归列出 home 下所有文件的（大小, 修改时间）；`skip` 前缀下的不算。
    func fileTree(_ home: String, skip: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let e = FileManager.default.enumerator(atPath: home) else { return out }
        for case let rel as String in e {
            if rel.hasPrefix(skip) { continue }
            guard let st = FileIO.stat(home + "/" + rel) else { continue }
            out[rel] = st.isDirectory ? "dir" : "\(st.size)@\(st.mtimeNs)"
        }
        return out
    }

    @Test("4.6-04/05/06 只读：完整跑一遍引擎（含持久化和 token 账本），假 home 里 ~/.claude、桌面 App 的数据、用量表、Claude.app 一个字节都没变，只有自己的 Application Support/BuddyOffice 里有文件")
    func theEngineOnlyWritesInsideItsOwnSupportFolder() throws {
        let h = Harness(persist: true, tokens: true)
        let f = DesktopFixture(h: h)
        let home = h.tree.paths.home
        // 「别人的东西」：桌面 App 的元数据、用量表、Claude.app
        var meta = FakeClaudeTree.Meta(host: DesktopFixture.host, cliSessionId: f.sid, lastActivityAt: h.now)
        meta.title = "别人的元数据"
        h.tree.writeMeta(meta)
        for (rel, body) in [(".token-meter/plugins/tokens.1m.py", "print('meter')\n"), ("Applications/Claude.app/Contents/Info.plist", "<plist/>\n"),
                            (".claude/monitor/hook.sh", "#!/bin/zsh\n")] {
            let path = home + "/" + rel
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FakeClaudeTree.writeInPlace(path, Data(body.utf8))
        }
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now),
                                        TL.assistant(sessionId: f.sid, at: h.now, messageId: "w1", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 5))])
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        let skip = "Library/Application Support/BuddyOffice"
        let before = fileTree(home, skip: skip)
        for i in 0..<20 {
            h.advance(0.5)
            if i == 5 { h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "ls") }
            if i == 10 { h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle") }
            h.poll()
        }
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60)
        h.engine.flush()
        let after = fileTree(home, skip: skip)
        // hook / 会话记录是往里追加的（那是「测试在扮演 Claude」）：只看没被测试动过的文件和目录
        let touchedByTheTest: Set<String> = [".claude/.monitor/\(f.sid).events.jsonl", ".claude/projects/-fake-project/\(f.sid).jsonl", ".claude/sessions/\(f.session.pid).json"]
        for (k, v) in before where !touchedByTheTest.contains(k) { #expect(after[k] == v, "\(k) 被改了：\(v) → \(String(describing: after[k]))") }
        #expect(Set(after.keys).subtracting(before.keys).isEmpty, "多出来的文件 / 目录：\(Set(after.keys).subtracting(before.keys))")
        // 自己的数据只在 Application Support/BuddyOffice 里
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: h.tree.paths.appSupportDir)) ?? [])
        #expect(names.isSubset(of: ["identities.json", "ledger.json"]) && names.contains("identities.json"), "\(names)")
    }

    @Test("4.6-12 不联网、没有第三方依赖：Package.swift 里没有任何 .package 依赖，所有源码只 import 系统框架和自己的四个库")
    func thereAreNoThirdPartyDependencies() throws {
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!Self.codeLines(manifest).joined(separator: "\n").contains(".package("), "Package.swift 不该有任何第三方包依赖")
        let allowed: Set<String> = ["Foundation", "Darwin", "CoreServices", "CoreGraphics", "ImageIO", "CoreText", "AppKit", "SwiftUI", "UserNotifications", "ServiceManagement",
                                    "QuartzCore", "IOSurface", "Carbon", "AVFoundation", "BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"]
        var bad: [String] = []
        for file in try Self.swiftFiles(["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage", "BuddyOffice", "buddyctl", "buddydump"]) {
            for line in file.code where line.hasPrefix("import ") || line.hasPrefix("@testable import ") {
                let module = line.replacingOccurrences(of: "@testable ", with: "").dropFirst(7).trimmingCharacters(in: .whitespaces)
                if !allowed.contains(module) { bad.append("\(file.name)：\(line)") }
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test("4.6-05/06 写文件的地方是一份短名单：只有身份和账本两处用 FileIO.writeAtomically，路径都在 Application Support/BuddyOffice 下")
    func writeAPIsAreConfinedToTheReviewedFiles() throws {
        var users: Set<String> = []
        for file in try Self.swiftFiles(["BuddyCore"]) where file.code.contains(where: { $0.contains("writeAtomically(") }) { users.insert(file.name) }
        #expect(users == ["BuddyCore/Util/FileIO.swift", "BuddyCore/Fusion/IdentityResolver.swift", "BuddyCore/Ingest/TokenLedger.swift", "BuddyCore/Tools/FakeTree.swift"], "\(users)")
        let p = Paths(home: "/Users/someone")
        #expect(p.identitiesFile == "/Users/someone/Library/Application Support/BuddyOffice/identities.json")
        #expect(p.ledgerFile == "/Users/someone/Library/Application Support/BuddyOffice/ledger.json")
        #expect(!p.identitiesFile.contains("/.claude") && !p.ledgerFile.contains("/.claude"))
    }

    // MARK: - 5.3 子代理归属

    /// 主会话 idle、有一个后台小助手正在活跃（刚有写入、没完成）。
    func idleMainWithABackgroundHelper() -> (Harness, DesktopFixture) {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-40))
        h.tree.writeSubagentMeta(f.sid, agentId: "bg01", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg01", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb", block: TL.text("hi"), stopReason: nil, agentId: "bg01")])
        h.poll(); h.advance(1); h.poll()
        return (h, f)
    }

    @Test("5.3-02 规则 1 的「没有临时 busy」：登记表 idle 但刚提交了提示（临时 busy）时，后台小助手的事件不能直接归小助手")
    func aTemporaryBusyIsNotIdleForRuleOne() {
        // 对照：主会话真的 idle → 事件立刻归后台小助手
        do {
            let (h, f) = idleMainWithABackgroundHelper()
            h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make one")
            h.poll()
            let row = h.engine.debugRows().first
            #expect(row?.openHelperTools.map { $0.name } == ["Bash"] && row?.openMainTools.isEmpty == true, "真 idle：归小助手")
        }
        // 登记表还是 idle，但有比 statusUpdatedAt 更新的 UserPromptSubmit：临时 busy（最多 3 秒），不算 idle
        let (h, f) = idleMainWithABackgroundHelper()
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.advance(0.05)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make two")
        h.poll()
        var row = h.engine.debugRows().first
        #expect(row?.openHelperTools.isEmpty == true, "临时 busy 不是 idle：不能按规则 1 归小助手")
        #expect(row?.openMainTools.isEmpty == true, "走规则 3：先扣住（≤ 400 ms）")
        #expect(h.lastOutput?.nextWake != nil)
        h.advance(0.5); h.poll()
        row = h.engine.debugRows().first
        #expect(row?.openMainTools.map { $0.name } == ["Bash"] && row?.openHelperTools.isEmpty == true, "扣满 400 ms 比对不上：归主线程")
    }

    @Test("5.3-10 归属判错只影响主 buddy，到下一个轮次边界就纠正；小助手自己的动作始终取自它自己的会话记录")
    func aWronglyAttributedToolIsCorrectedAtTheNextTurnBoundary() {
        let (h, f) = idleMainWithABackgroundHelper()
        // 主会话开始忙（登记表 busy + 提示）；小助手的 Bash 的 Pre 事件先到，它的 tool_use 还没落盘 → 扣满 400 ms 后被误判给主线程
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(0.09))
        h.advance(0.2); h.poll()
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 30")
        h.poll(); h.advance(0.5); h.poll()
        guard case .tool(let wrong, 1)? = h.snap(K.key)?.activity else { Issue.record("误判之后主线程会显示 Bash：\(String(describing: h.snap(K.key)?.activity))"); return }
        #expect(wrong.name == "Bash")                                                          // 判错了：这其实是小助手的
        // 小助手自己的会话记录随后落盘：它显示的动作是对的（不受判错影响）
        h.tree.appendSubagent(f.sid, agentId: "bg01", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb2", block: TL.toolUse(id: "tb2", name: "Bash", input: ["command": "sleep 30"]),
                                                                    stopReason: nil, agentId: "bg01")])
        h.advance(0.3); h.poll()
        #expect(h.snap(K.key)?.helpers.first?.currentTool?.name == "Bash")
        // 下一个轮次边界（Stop + 登记表 idle）：主线程被误判的记录清掉，回到空闲；小助手照旧
        h.advance(1)
        h.tree.hook(f.sid, "Stop")
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(0.05))
        h.advance(0.1); h.poll()
        #expect(h.engine.openMainTools(key: K.key).isEmpty)
        expectActivity(h.snap(K.key), .finished)
        #expect(h.snap(K.key)?.helpers.first?.currentTool?.name == "Bash")
    }

    // MARK: - 5.4 动作判定

    @Test("5.4-20 busy 的判断顺序是 压缩 → 重试 → 工具 → 思考：同时满足时前面的赢")
    func busyRulesAreCheckedInTheOrderCompactRetryToolThinking() {
        let t0 = Harness.epoch
        func base() -> SessionSignals {
            var s = SessionSignals()
            s.registryStatus = .busy; s.statusUpdatedAt = t0; s.hookActive = true
            s.openTools = [ToolCatalog.makeCall(name: "Bash", detail: "ls", at: t0.addingTimeInterval(1.5))]
            s.apiError = TranscriptFacts.ApiError(at: t0.addingTimeInterval(2), attempt: 2, max: 10, retryInMs: 1000)
            return s
        }
        let now = t0.addingTimeInterval(3)
        // 四样都有：PreCompact 还没有 PostCompact
        var s = base(); s.preCompactAt = t0.addingTimeInterval(1)
        #expect(ActivityResolver.resolve(s, now: now) == .compacting)
        // 会话记录里的压缩边界（没有 hook 说压缩已结束）同样排在重试和工具前面
        var b = base(); b.compactBoundaryAt = t0.addingTimeInterval(2.5)
        #expect(ActivityResolver.resolve(b, now: now) == .compacting)
        // 没有压缩：重试排在工具前面
        #expect(ActivityResolver.resolve(base(), now: now) == .retrying(attempt: 2, max: 10))
        // 没有压缩、没有重试：工具排在思考前面
        var tool = base(); tool.apiError = nil
        guard case .tool(let c, 1) = ActivityResolver.resolve(tool, now: now) else { Issue.record("应该是 .tool"); return }
        #expect(c.name == "Bash")
        // 什么都没有：思考中
        var none = base(); none.apiError = nil; none.openTools = []
        #expect(ActivityResolver.resolve(none, now: now) == .thinking)
    }

    // MARK: - 5.5 下班工位

    func desktopMeta(_ h: Harness, n: Int, ago: TimeInterval, archived: Bool = false) -> String {
        let host = String(format: "local_33333333-0000-4000-8000-%012d", n)
        var m = FakeClaudeTree.Meta(host: host, cliSessionId: String(format: "cccccccc-0000-4000-8000-%012d", n), lastActivityAt: h.now.addingTimeInterval(-ago))
        m.archived = archived
        h.tree.writeMeta(m)
        return "d:" + host
    }

    @Test("5.5-13 App 启动时 lastActivityAt 在 3 小时以内的桌面会话才成为下班工位（2:59:59 进、3:00:01 不进）")
    func dormantSeatsAtLaunchUseAThreeHourWindow() {
        let h = Harness()
        let inside = desktopMeta(h, n: 1, ago: 3 * 3600 - 1)
        let outside = desktopMeta(h, n: 2, ago: 3 * 3600 + 1)
        h.poll()
        #expect(h.snapshots.map { $0.key } == [inside])
        #expect(h.snap(outside) == nil)
        if case .away(_, let dormant)? = h.snap(inside)?.presence { #expect(dormant) } else { Issue.record("应该是下班工位") }
    }

    @Test("5.5-15 下班工位超过 4 个时先移走最久没活动的（运行中依次离场 6 个：留下的是最后走的 4 个）")
    func whenMoreThanFourAreOffDutyTheLeastRecentlyActiveGoFirst() {
        let h = Harness()
        var keys: [String] = []
        var sessions: [FakeClaudeTree.Session] = []
        for n in 1...6 {
            let sidN = String(format: "cccccccc-0000-4000-8000-%012d", n)
            let host = String(format: "local_33333333-0000-4000-8000-%012d", n)
            let s = FakeClaudeTree.Session(pid: Int32(2000 + n), sessionId: sidN, host: host, name: "会话\(n)", startedAt: h.now.addingTimeInterval(-600))
            keys.append(desktopMeta(h, n: n, ago: 100 - Double(n)))
            h.tree.writeRegistry(s, status: "idle")
            sessions.append(s)
        }
        h.poll()
        #expect(h.snapshots.count == 6)
        for (n, s) in sessions.enumerated() {                                                  // 1 号先走，6 号最后走：活动时间依次更晚
            h.advance(2)
            _ = desktopMeta(h, n: n + 1, ago: 0)
            h.tree.endProcess(pid: s.pid)
            h.run(for: 3.5)                                                                    // 防抖 3 秒之后成为下班工位（超过 4 个时当场移走最久没活动的）
        }
        h.run(for: 1)
        #expect(Set(h.snapshots.map { $0.key }) == Set(keys[2...]), "留下的应该是 3…6 号：\(h.snapshots.map { $0.key })")
        #expect(h.snap(keys[0]) == nil && h.snap(keys[1]) == nil)
    }

    // MARK: - 5.7 工具归类

    @Test("5.7 工具归类：任务书表里的每个工具名都落在对应类别（含被 hook 截断的名字），mcp 类带 server 名")
    func toolCatalogFollowsTheTaskBookTable() {
        let table: [(ToolCategory, [String])] = [
            (.read, ["Read", "NotebookRead"]),
            (.search, ["Grep", "Glob", "LS"]),
            (.edit, ["Edit", "MultiEdit"]),
            (.write, ["Write", "NotebookEdit"]),
            (.bash, ["Bash", "BashOutput", "KillShell"]),
            (.monitor, ["Monitor"]),
            (.web, ["WebFetch", "WebSearch"]),
            (.browser, ["mcp__Claude_Browser__navigate", "mcp__Claude_Browser__computer", "mcp__claude-in-chrome__navigate", "mcp__claude-in-chrome__read_page"]),
            (.computer, ["mcp__computer-use__app_click", "mcp__computer-use__screenshot"]),
            (.delegate, ["Agent", "Task", "Workflow", "SendMessage"]),
            (.todo, ["TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet"]),
            (.skill, ["Skill", "ToolSearch", "ListSkills"]),
            (.planEnter, ["EnterPlanMode"]),
            (.planExit, ["ExitPlanMode"]),
            (.sendFile, ["SendUserFile"]),
            (.schedule, ["ScheduleWakeup", "CronCreate"]),
            (.mcp, ["mcp__ccd_session_mgmt__search_session_transcripts", "mcp__notion__search_pages", "mcp__x__y"]),
            (.unknown, ["AskUserQuestion", "StructuredOutput", "SomethingNew", ""]),
        ]
        #expect(Set(table.map { $0.0 }) == Set(ToolCategory.allCases), "表要覆盖全部 18 个类别")
        for (cat, names) in table {
            for n in names {
                #expect(ToolCatalog.category(of: n) == cat, "\(n) 应该是 \(cat)")
                #expect(ToolCatalog.category(of: n + "…") == cat, "被 hook 截断的 \(n)… 也应该是 \(cat)")
            }
        }
        // mcp 类显示 server 名（浏览器 / computer-use 也带）；内置工具没有 server
        #expect(ToolCatalog.makeCall(name: "mcp__notion__search_pages", at: at(0)).server == "notion")
        #expect(ToolCatalog.makeCall(name: "mcp__ccd_session_mgmt__search_session_tr…", at: at(0)).server == "ccd_session_mgmt")
        #expect(ToolCatalog.makeCall(name: "mcp__claude-in-chrome__navigate", at: at(0)).server == "claude-in-chrome")
        #expect(ToolCatalog.makeCall(name: "mcp__computer-use__app_click", at: at(0)).server == "computer-use")
        #expect(ToolCatalog.makeCall(name: "Read", at: at(0)).server == nil)
        // 表外的新名字（DESIGN.md 第 5 节记录：TaskOutput / TaskStop 是 BashOutput / KillShell 的新名字，Cron* 同属定时）
        for n in ["TaskOutput", "TaskStop"] { #expect(ToolCatalog.category(of: n) == .bash) }
        for n in ["CronDelete", "CronList"] { #expect(ToolCatalog.category(of: n) == .schedule) }
    }
}
