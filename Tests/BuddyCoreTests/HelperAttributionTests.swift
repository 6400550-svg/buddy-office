import Foundation
import Testing
@testable import BuddyCore

@Suite struct HelperAttributorTests {
    let t0 = Harness.epoch
    func at(_ s: Double) -> Date { Harness.at(s) }
    func pre(_ tool: String, _ detail: String, at s: Double) -> HookEvent {
        HookEvent(ts: at(s), ev: "PreToolUse", tool: tool, detail: detail)
    }
    func rec(_ id: String, _ name: String, _ key: String, at s: Double) -> HelperAttributor.ToolUseRecord {
        .init(id: id, name: name, key: key, at: at(s))
    }
    /// 扣住的截止时间（允许 1 ms 的浮点误差）；不是 hold 返回 nil。
    func holdUntil(_ d: HelperAttributor.Decision) -> Double? {
        if case .hold(let u) = d { return u.timeIntervalSince(t0) }
        return nil
    }
    func isHold(_ d: HelperAttributor.Decision, until s: Double) -> Bool {
        guard let u = holdUntil(d) else { return false }
        return abs(u - s) < 0.001
    }

    @Test func rule1MainIdleMeansBackgroundHelper() {
        var a = HelperAttributor()
        let d = a.decide(event: pre("Bash", "ls", at: 0), context: .init(mainIdle: true), now: at(0))
        #expect(d == .helper)
    }

    @Test func rule2ForegroundAgentOpenAndEventLaterThan150ms() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, foregroundAgentOpenSince: at(10))
        #expect(a.decide(event: pre("Read", "/x", at: 10.05), context: ctx, now: at(10.05)) == .main)      // 同一批并行的主线程调用
        #expect(a.decide(event: pre("Read", "/x", at: 10.15), context: ctx, now: at(10.15)) == .helper)    // 恰好 0.15 s
        #expect(a.decide(event: pre("Read", "/x", at: 12), context: ctx, now: at(12)) == .helper)
    }

    @Test func rule3MatchesHelperTranscriptAndIsAttributedToTheHelper() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true,
                                           helperUses: [rec("h1", "Bash", "npm test", at: 4.9)],
                                           mainUses: [rec("m1", "Read", "/x", at: 4.8)])
        #expect(a.decide(event: pre("Bash", "npm test", at: 5), context: ctx, now: at(5.05)) == .helper)
        #expect(a.decide(event: pre("Read", "/x", at: 5), context: ctx, now: at(5.05)) == .main)
    }

    @Test func rule3NoMatchHoldsFor400msThenGoesToMain() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true)
        let e = pre("Bash", "unknown command", at: 5)
        #expect(isHold(a.decide(event: e, context: ctx, now: at(5.0)), until: 5.4))
        #expect(isHold(a.decide(event: e, context: ctx, now: at(5.39)), until: 5.4))
        #expect(a.decide(event: e, context: ctx, now: at(5.41)) == .main)
    }

    @Test func rule3HoldEndsEarlyWhenTheTranscriptCatchesUp() {
        var a = HelperAttributor()
        let e = pre("Grep", "foo", at: 5)
        var ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true)
        #expect(isHold(a.decide(event: e, context: ctx, now: at(5.05)), until: 5.4))
        ctx.helperUses = [rec("h1", "Grep", "foo", at: 5.06)]                  // 小助手的会话记录追上来了
        #expect(a.decide(event: e, context: ctx, now: at(5.1)) == .helper)
    }

    @Test func rule3AmbiguousMatchGoesToMain() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true,
                                           helperUses: [rec("h1", "Read", "/same", at: 4.9)],
                                           mainUses: [rec("m1", "Read", "/same", at: 4.9)])
        #expect(a.decide(event: pre("Read", "/same", at: 5), context: ctx, now: at(5.05)) == .main)
    }

    @Test func eachToolUseIsClaimedOnlyOnce() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true,
                                           helperUses: [rec("h1", "Read", "/a", at: 4.9), rec("h2", "Read", "/a", at: 4.95)])
        #expect(a.decide(event: pre("Read", "/a", at: 5), context: ctx, now: at(5.05)) == .helper)     // 配 h1
        #expect(a.decide(event: pre("Read", "/a", at: 5.01), context: ctx, now: at(5.06)) == .helper)  // 配 h2
        // 第三个同样的调用没有对应的 tool_use 了：扣住
        #expect(isHold(a.decide(event: pre("Read", "/a", at: 5.02), context: ctx, now: at(5.07)), until: 5.42))
    }

    @Test func truncatedHookDetailMatchesByPrefix() {
        var a = HelperAttributor()
        let long = String(repeating: "x", count: 200)
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true,
                                           helperUses: [rec("h1", "Bash", String(long.prefix(160)), at: 4.9)])
        let hookDetail = String(long.prefix(160)) + "…"
        #expect(a.decide(event: pre("Bash", hookDetail, at: 5), context: ctx, now: at(5.05)) == .helper)
    }

    @Test func noBackgroundHelperMeansMain() {
        var a = HelperAttributor()
        #expect(a.decide(event: pre("Read", "/x", at: 5), context: .init(mainIdle: false), now: at(5)) == .main)
    }

    @Test func toolUsesFarInThePastDoNotMatch() {
        var a = HelperAttributor()
        let ctx = HelperAttributor.Context(mainIdle: false, hasActiveBackgroundHelper: true,
                                           helperUses: [rec("h1", "Read", "/a", at: -200)])
        #expect(a.decide(event: pre("Read", "/a", at: 5), context: ctx, now: at(5.5)) == .main)       // 过了保持期直接归主线程
    }
}

/// 引擎里的归属场景（有真实的子代理文件和会话记录）。
@Suite struct HelperAttributionEngineTests {
    /// 造一个 busy 的桌面会话，主会话记录已有文件。
    func setup(status: String = "busy") -> (Harness, DesktopFixture) {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.tree.writeRegistry(f.session, status: "idle")
        h.poll()
        h.advance(1)
        h.tree.writeRegistry(f.session, status: status)
        if status == "busy" { h.tree.hook(f.sid, "UserPromptSubmit") }
        h.poll()
        return (h, f)
    }

    @Test func foregroundAgentHelpersDoNotStealTheMainThreadActivity() {
        let (h, f) = setup()
        h.advance(0.5)
        let t = h.now
        h.tree.hook(f.sid, "PreToolUse", tool: "Agent", detail: "研究", at: t)
        h.tree.writeSubagentMeta(f.sid, agentId: "aa11", foreground: true, description: "研究")
        h.poll()
        h.advance(0.4)                                            // 比 Agent 的 Pre 晚 0.4 秒：归小助手
        h.tree.appendSubagent(f.sid, agentId: "aa11", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m", block: TL.toolUse(id: "th1", name: "Bash", input: ["command": "ls"]), stopReason: nil, agentId: "aa11")])
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "ls")
        h.poll()
        guard case .tool(let c, 1)? = h.snap(DesktopFixture.key)?.activity else { Issue.record("主线程应该还是 Agent：\(String(describing: h.snap(DesktopFixture.key)?.activity))"); return }
        #expect(c.name == "Agent")
        let helper = h.snap(DesktopFixture.key)?.helpers.first
        #expect(helper?.foreground == true)
        #expect(helper?.active == true)
        #expect(helper?.currentTool?.name == "Bash")
        #expect(h.engine.openMainTools(key: DesktopFixture.key).map { $0.call.name } == ["Agent"])
        // Post 到来时按名字 + detail 关掉小助手名下的记录
        h.advance(0.3)
        h.tree.hook(f.sid, "PostToolUse", tool: "Bash", detail: "ls")
        h.poll()
        #expect(h.engine.openMainTools(key: DesktopFixture.key).map { $0.call.name } == ["Agent"])
    }

    @Test func idleMainSessionsBackgroundHelperEventsGoToTheHelper() {
        let (h, f) = setup()
        // 一轮结束，主会话 idle；后台小助手还在干活
        h.advance(1)
        h.tree.hook(f.sid, "Stop")
        h.tree.writeRegistry(f.session, status: "idle")
        h.tree.writeSubagentMeta(f.sid, agentId: "bg01", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg01", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb", block: TL.toolUse(id: "tb1", name: "Read", input: ["file_path": "/x"]), stopReason: nil, agentId: "bg01")])
        h.poll()
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/x")
        h.poll()
        h.run(for: 1)
        let s = h.snap(DesktopFixture.key)
        #expect(s?.phase == .idle)                                   // 主会话的动作不受影响
        #expect(h.engine.openMainTools(key: DesktopFixture.key).isEmpty)
        #expect(s?.helpers.first?.currentTool?.name == "Read")
    }

    @Test func busyMainWithBackgroundHelperUsesTranscriptsToTellThemApart() {
        let (h, f) = setup()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg02", foreground: false)
        h.advance(1)
        let t = h.now
        h.tree.appendSubagent(f.sid, agentId: "bg02", [TL.assistant(sessionId: f.sid, at: t, messageId: "mb2", block: TL.toolUse(id: "tb2", name: "Bash", input: ["command": "sleep 30"]), stopReason: nil, agentId: "bg02")])
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: t, messageId: "mm2", block: TL.toolUse(id: "tm2", name: "Read", input: ["file_path": "/main.swift"]))])
        h.poll()
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 30", at: t)              // 小助手的
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/main.swift", at: t.addingTimeInterval(0.05))   // 主线程的
        h.poll()
        guard case .tool(let c, 1)? = h.snap(DesktopFixture.key)?.activity else { Issue.record("x \(String(describing: h.snap(DesktopFixture.key)?.activity))"); return }
        #expect(c.name == "Read")
        #expect(h.snap(DesktopFixture.key)?.helpers.first?.currentTool?.name == "Bash")
    }

    @Test func unmatchedEventIsHeldFor400msThenAttributedToTheMainThread() {
        let (h, f) = setup()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg03", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg03", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb3", block: TL.text("hi"), stopReason: nil, agentId: "bg03")])
        h.advance(0.5)
        h.poll()
        // 主线程的 Bash：它的 tool_use 还没写盘（主会话记录写入有延迟），后台小助手又在活跃 → 先扣住
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make build")
        h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)         // 被扣住，主线程动作还没变
        #expect(h.lastOutput?.nextWake != nil)
        h.advance(0.2); h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)         // 还没到 400 ms
        h.advance(0.25); h.poll()
        guard case .tool(let c, 1)? = h.snap(DesktopFixture.key)?.activity else { Issue.record("扣满 400 ms 后应该归主线程"); return }
        #expect(c.name == "Bash")
    }

    @Test func heldEventIsReleasedAsSoonAsTheTranscriptMatches() {
        let (h, f) = setup()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg04", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg04", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb4", block: TL.text("hi"), stopReason: nil, agentId: "bg04")])
        h.advance(0.5); h.poll()
        h.tree.hook(f.sid, "PreToolUse", tool: "Grep", detail: "needle")
        h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)
        h.advance(0.1)
        // 60 ms 之后小助手的 tool_use 落盘 → 这个事件归小助手，主线程动作不变
        h.tree.appendSubagent(f.sid, agentId: "bg04", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb4", block: TL.toolUse(id: "tb4", name: "Grep", input: ["pattern": "needle"]), stopReason: nil, agentId: "bg04")])
        h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)
        #expect(h.engine.openMainTools(key: DesktopFixture.key).isEmpty)
        #expect(h.snap(DesktopFixture.key)?.helpers.first?.currentTool?.name == "Grep")
    }

    @Test func workflowSubagentsInNestedDirectoriesAreDiscovered() {
        let (h, f) = setup()
        let dir = h.tree.subagentDir(f.sid) + "/workflows/wf_abc"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let meta: [String: Any] = ["agentType": "workflow-subagent", "description": "review:x", "requestShape": "foreground"]
        FakeClaudeTree.writeInPlace(dir + "/agent-wf01.meta.json", try! JSONSerialization.data(withJSONObject: meta))
        FakeClaudeTree.appendBytes(dir + "/agent-wf01.jsonl", FakeClaudeTree.jsonLine(TL.assistant(sessionId: f.sid, at: h.now, messageId: "mw", block: TL.toolUse(id: "tw", name: "Read", input: ["file_path": "/w"]), stopReason: nil, agentId: "wf01")))
        FakeClaudeTree.appendBytes(dir + "/journal.jsonl", Data("{\"type\":\"launched\"}\n".utf8))     // 不是 agent-* 的不算
        h.advance(1); h.poll(); h.advance(1); h.poll()
        let helpers = h.snap(DesktopFixture.key)?.helpers ?? []
        #expect(helpers.count == 1)
        #expect(helpers.first?.agentType == "workflow-subagent")
        #expect(helpers.first?.description == "review:x")
    }

    @Test func helperIsDoneWhenLastAssistantIsEndTurnWithNoOpenTool() {
        let (h, f) = setup()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg05", foreground: false)
        let id = "agent-bg05"
        h.tree.appendSubagent(f.sid, agentId: "bg05", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m5", block: TL.toolUse(id: "t5", name: "Bash", input: ["command": "x"]), stopReason: nil, agentId: "bg05")])
        h.advance(1); h.poll(); h.advance(1); h.poll()
        var hs = h.snap(DesktopFixture.key)?.helpers ?? []
        #expect(hs.first?.id == id)
        #expect(hs.first?.active == true && hs.first?.done == false)
        h.tree.appendSubagent(f.sid, agentId: "bg05", [
            TL.userToolResult(sessionId: f.sid, at: h.now, toolUseId: "t5", agentId: "bg05"),
            TL.assistant(sessionId: f.sid, at: h.now, messageId: "m6", block: TL.text("done"), stopReason: "end_turn", agentId: "bg05")])
        h.advance(1); h.poll()
        hs = h.snap(DesktopFixture.key)?.helpers ?? []
        #expect(hs.first?.done == true && hs.first?.active == false)
        #expect(hs.first?.currentTool == nil)
        // 完成后继续报告 30 秒，之后从列表里消失
        h.advance(31); h.poll()
        let remaining = h.snap(DesktopFixture.key)?.helpers ?? []             // 拿到宏外面（宏展开会给 `(a?.b ?? []).isEmpty` 报编译警告）
        #expect(remaining.isEmpty)
    }

    @Test func helperStopsBeingActiveAfter90SecondsWithoutWrites() {
        let (h, f) = setup()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg06", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg06", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m7", block: TL.toolUse(id: "t7", name: "Bash", input: ["command": "sleep 500"]), stopReason: nil, agentId: "bg06")])
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(DesktopFixture.key)?.helpers.first?.active == true)
        h.advance(87); h.poll()                                   // 距最后一次写入共 89 秒
        #expect(h.snap(DesktopFixture.key)?.helpers.first?.active == true)
        h.advance(2); h.poll()                                    // 91 秒
        let shown = h.snap(DesktopFixture.key)?.helpers ?? []                 // 拿到宏外面：宏展开会给 `(a?.b ?? []).isEmpty` 报两条编译警告
        #expect(shown.isEmpty)                                                // 没完成但 90 秒没动静：不显示
    }
}
