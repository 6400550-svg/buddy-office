import Foundation
import Testing
@testable import BuddyCore

/// Codex（OpenAI）线程：从 ~/.codex 的会话记录里读出「谁在忙、在干什么、什么时候做完」，和 Claude 会话一起坐在办公室里。
/// 假的 ~/.codex 树里放一个**蜜罐 auth.json**：数据层无论如何不能打开它。
struct CodexFixture {
    static let id = "01a0f083-d304-7420-b1e2-8305fec5add2"
    static let key = "x:" + id
    let h: Harness
    let id: String
    let path: String
    let dir: String

    init(h: Harness, id: String = CodexFixture.id, title: String? = "Codex 测试线程", subagent: Bool = false, model: String = "gpt-6-luna") {
        self.h = h; self.id = id
        let home = h.tree.paths.home
        dir = home + "/.codex/sessions/2026/09/29"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        path = dir + "/rollout-2026-09-29T04-00-00-\(id).jsonl"
        try? "{\"auth\":\"HONEYPOT\"}".write(toFile: home + "/.codex/auth.json", atomically: true, encoding: .utf8)
        var meta: [String: Any] = ["id": id, "cwd": "/Users/demo/proj", "cli_version": "0.158.0", "originator": "Codex Desktop", "timestamp": TL.iso(h.now),
                                   "source": "vscode", "thread_source": "user"]
        if subagent { meta["source"] = ["subagent": ["thread_spawn": ["parent": "x"]]]; meta["thread_source"] = "subagent" }
        line("session_meta", meta)
        if let t = title { writeIndex(title: t) }
        _ = model
    }

    func writeIndex(title: String) {
        let s = "{\"id\":\"\(id)\",\"thread_name\":\"\(title)\",\"updated_at\":\"\(TL.iso(h.now))\"}\n"
        try? s.write(toFile: h.tree.paths.home + "/.codex/session_index.jsonl", atomically: true, encoding: .utf8)
    }

    /// 追加一行（type + payload），时间戳 = 虚拟时钟；同时把文件 mtime 设成虚拟时钟（数据层看的是真实文件的 mtime）。
    func line(_ type: String, _ payload: [String: Any], at: Date? = nil) {
        let d = at ?? h.now
        var obj: [String: Any] = ["timestamp": TL.iso(d), "type": type, "payload": payload]
        obj["ordinal"] = 1
        FakeClaudeTree.appendBytes(path, FakeClaudeTree.jsonLine(obj))
        try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: path)
    }
    func event(_ t: String, _ extra: [String: Any] = [:]) { var p = extra; p["type"] = t; line("event_msg", p) }
    func item(_ t: String, _ extra: [String: Any]) { var p = extra; p["type"] = t; line("response_item", p) }

    func startTurn(model: String = "gpt-6-luna") {
        event("task_started", ["turn_id": "t1", "started_at": Int(h.now.timeIntervalSince1970)])
        line("turn_context", ["model": model, "effort": "high", "approval_policy": "never", "cwd": "/Users/demo/proj"])
    }
    func openExec(_ cmd: String, call: String = "call_1") {
        item("custom_tool_call", ["call_id": call, "name": "exec", "input": "const r = await tools.exec_command({cmd:\"\(cmd)\", yield_time_ms: 1000});"])
    }
    func closeTool(_ call: String = "call_1") { item("custom_tool_call_output", ["call_id": call, "output": "ok"]) }
    func endTurn(durationMs: Int = 42_000) {
        event("task_complete", ["turn_id": "t1", "completed_at": Int(h.now.timeIntervalSince1970), "duration_ms": durationMs,
                                "last_agent_message": "绝不能出现的对话内容"])
    }
}

@Suite struct CodexTests {
    func harness(running: Bool = true, persist: Bool = false) -> Harness {
        Harness(persist: persist) { $0.codexProbe = FixedCodexProbe(running) }
    }

    @Test func rolloutNames() {
        #expect(CodexNames.threadId(fromRolloutName: "rollout-2026-09-29T21-12-46-\(CodexFixture.id).jsonl") == CodexFixture.id)
        #expect(CodexNames.threadId(fromRolloutName: "rollout-x.jsonl") == nil)
        #expect(CodexNames.threadId(fromRolloutName: "notes-\(CodexFixture.id).jsonl") == nil)
        #expect(CodexNames.threadId(fromRolloutName: "rollout-2026-09-29T21-12-46-\(CodexFixture.id).json") == nil)
        #expect(CodexNames.isUUID(CodexFixture.id))
        #expect(!CodexNames.isUUID("../../etc/passwd"))
        #expect(!CodexNames.isUUID(CodexFixture.id + "x"))
    }

    @Test func credentialsAreForbidden() {
        #expect(FileIO.isForbidden(path: "/Users/x/.codex/auth.json"))
        #expect(FileIO.isForbidden(path: "/Users/x/.codex/AUTH.JSON"))
        #expect(!FileIO.isForbidden(path: "/Users/x/.codex/session_index.jsonl"))
    }

    @Test func busyThreadShowsToolAndDetail() {
        let h = harness()
        let f = CodexFixture(h: h)
        f.startTurn()
        f.openExec("npm test -- --watch")
        h.advance(1.1); h.poll()
        let s = h.snap(CodexFixture.key)
        #expect(s != nil)
        #expect(s?.origin == .codex)
        #expect(s?.title == "Codex 测试线程")
        #expect(s?.modelFamily == .gpt)
        #expect(s?.modelName == "gpt-6-luna")
        #expect(s?.effort == "high")
        #expect(s?.cwd == "/Users/demo/proj")
        #expect(s?.presence == .present)
        #expect(s?.phase == .busy)
        guard case .tool(let call, let n)? = s?.activity else { Issue.record("应该是 .tool，实际 \(String(describing: s?.activity))"); return }
        #expect(call.name == "exec")
        #expect(call.category == .bash)
        #expect(call.detail == "npm test -- --watch")
        #expect(n == 1)
        // 工具结束 → 思考
        h.advance(1); f.closeTool(); h.poll()
        expectActivity(h.snap(CodexFixture.key), .thinking)
    }

    @Test func finishedThenIdleThenDozing() {
        let h = harness()
        let f = CodexFixture(h: h)
        f.startTurn(); f.openExec("ls"); 
        h.advance(1.1); h.poll()
        h.advance(30); f.closeTool(); f.endTurn(durationMs: 31_000)
        h.poll()
        var s = h.snap(CodexFixture.key)
        expectActivity(s, .finished)
        #expect(s?.unread == true)
        #expect(s?.lastTurnDuration == 31)
        let fin = h.kinds(CodexFixture.key).compactMap { k -> (TimeInterval?, Bool, Bool)? in if case .turnFinished(let d, let i, let e) = k { return (d, i, e) } else { return nil } }
        #expect(fin.count == 1 && fin[0].0 == 31 && fin[0].1 == false && fin[0].2 == false)
        h.advance(6); h.poll()
        expectActivity(h.snap(CodexFixture.key), .idle)
        h.advance(10 * 60); h.poll()
        s = h.snap(CodexFixture.key)
        expectActivity(s, .dozing)
        #expect(s?.presence == .present)
    }

    @Test func interruptedTurn() {
        let h = harness()
        let f = CodexFixture(h: h)
        f.startTurn(); f.openExec("sleep 100")
        h.advance(1.1); h.poll()
        h.advance(2); f.event("turn_aborted", ["turn_id": "t1", "reason": "interrupted"]); h.poll()
        expectActivity(h.snap(CodexFixture.key), .interrupted)
        #expect(h.snap(CodexFixture.key)?.unread == false)
    }

    @Test func askingQuestionRaisesHand() {
        let h = harness()
        let f = CodexFixture(h: h)
        f.startTurn()
        h.advance(1.1); h.poll()
        h.advance(1); f.item("function_call", ["call_id": "q1", "name": "request_user_input_async", "arguments": "{}"]); h.poll()
        expectActivity(h.snap(CodexFixture.key), .asking)
        #expect(h.snap(CodexFixture.key)?.phase == .waiting)
        #expect(h.kinds(CodexFixture.key).contains(.needsUser(.question)))
        h.advance(1); f.closeTool("q1"); f.item("function_call_output", ["call_id": "q1", "output": "x"]); h.poll()
        expectActivity(h.snap(CodexFixture.key), .thinking)
        #expect(h.kinds(CodexFixture.key).contains(.needsUserCleared))
    }

    @Test func subagentThreadsAreNotColleagues() {
        let h = harness()
        let f = CodexFixture(h: h, subagent: true)
        f.startTurn(); f.openExec("ls")
        h.advance(1.1); h.poll()
        #expect(h.snap(CodexFixture.key) == nil)
    }

    @Test func nothingWhenCodexIsNotRunning() {
        let h = harness(running: false)
        let f = CodexFixture(h: h)
        f.startTurn(); f.openExec("ls")
        h.advance(1.1); h.poll()
        #expect(h.snap(CodexFixture.key) == nil)
        (h.engine.options.codexProbe as? FixedCodexProbe)?.running = true
        h.advance(2.5); h.poll()
        #expect(h.snap(CodexFixture.key)?.presence == .present)
    }

    @Test func leavesAfterLingerAndIsRemoved() {
        let h = harness()
        let f = CodexFixture(h: h)
        f.startTurn(); f.endTurn()
        h.advance(1.1); h.poll()
        #expect(h.snap(CodexFixture.key)?.presence == .present)
        h.advance(31 * 60); h.poll()                     // 安静超过 30 分钟：进入离场防抖
        h.advance(3.5); h.poll()
        if case .away(_, let dormant)? = h.snap(CodexFixture.key)?.presence { #expect(dormant == false) } else { Issue.record("应该已经离场") }
        #expect(h.kinds(CodexFixture.key).contains(.departed(dormant: false)))
        h.advance(9); h.poll()
        #expect(h.snap(CodexFixture.key) == nil)                                     // 8 秒后收回工位
        // 又有动静：回来
        h.advance(1); f.startTurn(); f.openExec("ls"); h.advance(1.5); h.poll()
        #expect(h.snap(CodexFixture.key)?.presence == .present)
    }

    @Test func seatsDoNotCollideWithClaudeSessions() {
        let h = harness()
        let d = DesktopFixture(h: h)
        h.tree.writeRegistry(d.session, status: "idle")
        let f = CodexFixture(h: h)
        f.startTurn(); f.openExec("ls")
        h.advance(1.1); h.poll()
        let seats = h.snapshots.map { $0.seat }
        #expect(h.snapshots.count == 2)
        #expect(Set(seats).count == 2)
        #expect(h.snap(CodexFixture.key)?.origin == .codex)
        #expect(h.snap(DesktopFixture.key)?.origin == .desktop)
    }

    @Test func neverOpensCredentialsAndNeverKeepsConversation() {
        let h = harness()
        var opened: [String] = []
        let lock = NSLock()
        let hits0 = FileIO.forbiddenHits
        FileIO.openObserver = { p in if p.hasPrefix(h.root) { lock.lock(); opened.append(p); lock.unlock() } }
        defer { FileIO.openObserver = nil }
        let f = CodexFixture(h: h)
        f.event("token_count", ["info": ["total_token_usage": ["input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 50, "total_tokens": 1050],
                                         "last_token_usage": ["input_tokens": 900]]])
        f.item("message", ["role": "user", "content": [["type": "input_text", "text": "绝不能出现的对话内容"]]])
        f.startTurn(); f.openExec("ls"); f.closeTool(); f.endTurn()
        h.advance(1.1); h.poll(); h.advance(1); h.poll()
        lock.lock(); let paths = opened; lock.unlock()
        #expect(!paths.isEmpty)
        #expect(paths.allSatisfy { !$0.hasSuffix("auth.json") })
        #expect(FileIO.forbiddenHits == hits0)
        let s = h.snap(CodexFixture.key)
        #expect(s != nil)
        #expect(!String(describing: s as Any).contains("绝不能出现的对话内容"))
        #expect(s?.tokens.input == 600 && s?.tokens.cacheRead == 400 && s?.tokens.output == 50)
        #expect(s?.contextTokens == 900)
    }

    @Test func disabledInOptionsMeansNoCodex() {
        let h = Harness { $0.codexEnabled = false; $0.codexProbe = FixedCodexProbe(true) }
        let f = CodexFixture(h: h)
        f.startTurn(); f.openExec("ls")
        h.advance(1.1); h.poll()
        #expect(h.snap(CodexFixture.key) == nil)
    }
}
