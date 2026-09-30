import Foundation
import Testing
@testable import BuddyCore

/// QA（逻辑线）：任务书第 4.1 / 5 节的状态机规则，逐条用假时钟回放验证。
///
/// 每个测试的名字以规则字母开头（a…n 对应任务书里的规则清单），断言的都是具体数字（0.25 秒、3 秒、5 秒、
/// 30 分钟、10 分钟 / 45 分钟、2 小时、8 秒……）。已有测试已经覆盖的规则，这里只补「精确边界」或「引擎层」的版本，
/// 不重复造轮子；哪条规则由哪个测试验证，见 QA/issues-logic.md 里的对照表。
enum StateRuleKit {
    static let key = DesktopFixture.key

    /// 已经在场的空闲会话（App 启动时就在）：hook 已注册，登记表 idle，40 秒前变的。
    static func idleSession(hooks: Bool = true, tokens: Bool = false,
                            configure: ((inout SessionEngine.Options) -> Void)? = nil) -> (Harness, DesktopFixture) {
        let h = Harness(tokens: tokens, registerHook: hooks, configure: configure)
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.customTitle(sessionId: f.sid, "会话标题"),
                                        TL.userPrompt(sessionId: f.sid, at: h.now.addingTimeInterval(-50))])
        if hooks { h.tree.hook(f.sid, "SessionStart", extra: "startup", at: h.now.addingTimeInterval(-50)) }
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-40))
        h.poll()
        h.clearEvents()
        return (h, f)
    }

    /// 开始一轮：登记表 busy（先），随后 hook 的 UserPromptSubmit（后 90 ms，和真实数据一致）。
    static func startTurn(_ h: Harness, _ f: DesktopFixture, hooks: Bool = true) {
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        if hooks { h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(0.09)) }
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now.addingTimeInterval(0.09))])
        h.advance(0.1)
        h.poll()
    }

    /// 虚拟时钟现在离 epoch 多少秒。
    static func secs(_ h: Harness) -> Double { h.now.timeIntervalSince(Harness.epoch) }
    /// 把虚拟时钟推进到 epoch + s。
    static func goto(_ h: Harness, _ s: Double) { h.advance(s - secs(h)) }

    static func tool(_ s: BuddySnapshot?) -> (call: ToolCall, parallel: Int)? {
        if case .tool(let c, let n)? = s?.activity { return (c, n) }
        return nil
    }

    static func turnFinishedEvents(_ h: Harness) -> [(interrupted: Bool, errored: Bool)] {
        h.kinds(key).compactMap { k in
            if case .turnFinished(_, let i, let e) = k { return (i, e) }
            return nil
        }
    }

    static func count(_ kinds: [BuddyEvent.Kind], _ k: BuddyEvent.Kind) -> Int { kinds.filter { $0 == k }.count }
}

@Suite struct StateRuleTests {
    typealias K = StateRuleKit
    let key = DesktopFixture.key
    func at(_ s: Double) -> Date { Harness.at(s) }

    // MARK: - (a) 并行工具

    @Test("a1 同一毫秒的三个并行 Read：同一批，Post 按 名字+detail 优先、先进先出配对")
    func a1_sameMillisecondParallelReadsPairFirstInFirstOut() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(2)
        let t = h.now
        for d in ["/same", "/same", "/other"] { h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: d, at: t) }
        h.poll()
        guard let (c, n) = K.tool(h.snap(key)) else { Issue.record("应该是 .tool，实际 \(String(describing: h.snap(key)?.activity))"); return }
        #expect(c.detail == "/other")                                   // 最新打开的那个
        #expect(n == 3)                                                 // 并行个数 ×3
        let open = h.engine.openMainTools(key: key)
        #expect(open.map { $0.seq } == [0, 1, 2])
        #expect(Set(open.map { $0.batch }).count == 1)                  // 同一毫秒 = 同一批

        h.advance(0.1); h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/same", extra: "len=1"); h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.seq } == [1, 2])   // 名字+detail 相同的两个里，最早的先关
        #expect(K.tool(h.snap(key))?.parallel == 2)
        h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/same", extra: "len=1"); h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.seq } == [2])
        // detail 谁也对不上：退回「只按工具名关最早的那个」
        h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/nothing-like-it", extra: "len=1"); h.poll()
        #expect(h.engine.openMainTools(key: key).isEmpty)
        expectActivity(h.snap(key), .thinking)
        #expect(h.engine.closedTools(key: key).map { $0.call.detail } == ["/same", "/same", "/other"])
        #expect(h.engine.closedTools(key: key).allSatisfy { $0.reason == .post })
    }

    @Test("a2 批次间隔恰好 0.25 秒：不算新批；再多 1 毫秒的 0.251 秒才算，并把旧批次悬空的调用关掉")
    func a2_batchGapIsExactly250ms() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(2)
        let t = h.now
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "A", at: t)
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "B", at: t.addingTimeInterval(0.25))       // 距上一个 Pre 恰好 0.25 秒
        h.poll()
        var open = h.engine.openMainTools(key: key)
        #expect(open.map { $0.call.detail } == ["A", "B"])                      // 没有超过 0.25 秒：同一批
        #expect(Set(open.map { $0.batch }).count == 1)
        #expect(K.tool(h.snap(key))?.parallel == 2)
        h.tree.hook(f.sid, "PreToolUse", tool: "Grep", detail: "C", at: t.addingTimeInterval(0.25 + 0.251))   // 距上一个 Pre 0.251 秒
        h.poll()
        open = h.engine.openMainTools(key: key)
        #expect(open.map { $0.call.detail } == ["C"])                           // 超过 0.25 秒：新的一批，A 和 B 被取代
        let superseded = h.engine.closedTools(key: key).filter { $0.reason == .superseded }.map { $0.call.detail }
        #expect(superseded == ["A", "B"])
        #expect(K.tool(h.snap(key))?.parallel == 1)
    }

    @Test("a3 Post 的 detail 谁也对不上时，退回按工具名关「最早」的那个，之后没有可关的就忽略")
    func a3_postFallsBackToTheEarliestOpenCallOfTheSameName() {
        var t = ToolTracker()
        t.pre(name: "Read", detail: "/a", at: at(0), owner: .main)
        t.pre(name: "Read", detail: "/b", at: at(0), owner: .main)
        t.pre(name: "Grep", detail: "/a", at: at(0.1), owner: .main)
        t.post(name: "Read", detail: "/zzz", at: at(1))
        #expect(t.mainOpen.map { $0.call.detail } == ["/b", "/a"])              // 关掉的是最早的 Read（/a），不是 Grep
        t.post(name: "Read", detail: "/zzz", at: at(1))
        t.post(name: "Read", detail: "/zzz", at: at(1))                         // 已经没有 Read 了：忽略
        #expect(t.mainOpen.map { $0.call.name } == ["Grep"])
        #expect(t.closed.count == 2)
    }

    // MARK: - (b) 悬空工具与轮次边界

    /// 一轮里开着一个主线程 Bash（没有 Post）。
    func withDanglingBash() -> (Harness, DesktopFixture) {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 99")
        h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Bash"])
        return (h, f)
    }

    func expectClosedByBoundary(_ h: Harness, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(h.engine.openMainTools(key: key).isEmpty, "主线程的打开调用应该被关掉", sourceLocation: sourceLocation)
        #expect(h.engine.closedTools(key: key).contains { $0.call.name == "Bash" && $0.reason == .turnBoundary },
                "应该以 turnBoundary 关掉：\(h.engine.closedTools(key: key).map { $0.reason })", sourceLocation: sourceLocation)
    }

    @Test("b1 悬空的调用：Stop 事件关掉主线程全部打开调用")
    func b1_stopEventClosesDanglingMainCalls() {
        let (h, f) = withDanglingBash()
        h.advance(3); h.tree.hook(f.sid, "Stop"); h.poll()
        expectClosedByBoundary(h)
        expectActivity(h.snap(key), .finished)
    }

    @Test("b2 悬空的调用：UserPromptSubmit 关掉主线程全部打开调用")
    func b2_userPromptSubmitClosesDanglingMainCalls() {
        let (h, f) = withDanglingBash()
        h.advance(3); h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()          // 排队的下一条输入
        expectClosedByBoundary(h)
        expectActivity(h.snap(key), .thinking)
    }

    @Test("b3 悬空的调用：SessionStart（/clear、resume 之类）关掉主线程全部打开调用")
    func b3_sessionStartClosesDanglingMainCalls() {
        let (h, f) = withDanglingBash()
        h.advance(3); h.tree.hook(f.sid, "SessionStart", extra: "clear"); h.poll()
        expectClosedByBoundary(h)
    }

    @Test("b9 悬空的调用：SessionEnd 也是轮次边界（任务书清单之外，引擎当边界用）")
    func b9_sessionEndClosesDanglingMainCalls() {
        let (h, f) = withDanglingBash()
        h.advance(3); h.tree.hook(f.sid, "SessionEnd", extra: "other"); h.poll()
        expectClosedByBoundary(h)
    }

    @Test("b4 悬空的调用：登记表变成 idle 关掉主线程全部打开调用")
    func b4_registryTurningIdleClosesDanglingMainCalls() {
        let (h, f) = withDanglingBash()
        h.advance(3)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()       // 没有 Stop：光靠登记表翻 idle
        expectClosedByBoundary(h)
        #expect(h.snap(key)?.phase == .idle)
    }

    @Test("b5 悬空的调用：会话记录里的 stop_hook_summary 关掉在它之前开始的调用，比它新的调用不受影响")
    func b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt() {
        let (h, f) = withDanglingBash()
        h.advance(3)
        h.tree.appendTranscript(f.sid, [TL.stopHookSummary(sessionId: f.sid, at: h.now)])
        h.poll()                                                                 // 登记表仍是 busy：只有会话记录说这一轮结束了
        expectClosedByBoundary(h)
        #expect(h.snap(key)?.phase == .busy)

        // 另一个：会话记录里的 stop_hook_summary 比当前开着的调用旧（写盘有延迟）——不能误关
        let (h2, f2) = withDanglingBash()
        h2.advance(3)
        h2.tree.appendTranscript(f2.sid, [TL.stopHookSummary(sessionId: f2.sid, at: h2.now.addingTimeInterval(-30))])
        h2.poll()
        #expect(h2.engine.openMainTools(key: key).map { $0.call.name } == ["Bash"])
    }

    @Test("b6 没有 PostToolUseFailure / 权限被拒：悬空的调用被下一批（>0.25 秒）取代，晚到的 Post 忽略")
    func b6_danglingCallIsSupersededByTheNextBatch() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Write", detail: "/etc/x")        // 权限被拒 / 失败：永远没有 Post
        h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Write"])
        h.advance(12)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "ls")            // 模型换了个办法
        h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Bash"])
        #expect(h.engine.closedTools(key: key).contains { $0.call.name == "Write" && $0.reason == .superseded })
        h.advance(0.2); h.tree.hook(f.sid, "PostToolUse", tool: "Write", detail: "/etc/x"); h.poll()   // 已经被取代的 Write 不会再来 Post；来了也无害
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Bash"])
    }

    @Test("b7 兜底：登记表 idle 而调用已开超过 30 分钟才强制关（恰好 30 分钟不关，多 1 毫秒关）")
    func b7_staleCallIsForceClosedOnlyAfterMoreThan30MinutesWhileRegistryIdle() {
        var t = ToolTracker()
        t.pre(name: "Monitor", detail: "", at: at(0), owner: .main)
        t.expireStale(now: at(30 * 60), registryIdle: true)
        #expect(t.mainOpen.count == 1)                                          // 恰好 30 分钟：还没「超过」
        t.expireStale(now: at(30 * 60 + 0.001), registryIdle: false)
        #expect(t.mainOpen.count == 1)                                          // 登记表不是 idle：绝不强制关
        t.expireStale(now: at(30 * 60 + 0.001), registryIdle: true)
        #expect(t.mainOpen.isEmpty)
        #expect(t.closed.last?.reason == .stale)
    }

    @Test("b8 兜底（引擎）：空闲期间归到小助手名下的记录，开着超过 30 分钟被丢掉；29 分钟时还在")
    func b8_helperOwnedRecordsExpireAfter30Minutes() {
        let (h, f) = K.idleSession()                                            // 登记表 idle：hook 事件归后台小助手
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "background job")
        h.poll()
        guard let st = h.engine.debugState(key: key) else { Issue.record("没有 buddy"); return }
        #expect(st.tracker.helperOpen.count == 1)
        #expect(st.tracker.mainOpen.isEmpty)
        h.advance(29 * 60); h.poll()
        #expect(st.tracker.helperOpen.count == 1)
        h.advance(2 * 60); h.poll()
        #expect(st.tracker.helperOpen.isEmpty)
        #expect(h.engine.closedTools(key: key).contains { $0.reason == .stale && $0.owner == .helper })
    }

    // MARK: - (c) 重试

    @Test("c1 api_error：显示 第 3 次 / 共 10 次，到 retryInMs(2.5 秒) + 15 秒后没有新行就不再显示")
    func c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        let t = h.now
        h.tree.appendTranscript(f.sid, [TL.apiError(sessionId: f.sid, at: t, attempt: 3, max: 10, retryInMs: 2500)])
        h.advance(0.05); h.poll()
        expectActivity(h.snap(key), .retrying(attempt: 3, max: 10))
        h.advance(17.35); h.poll()                                              // api_error 之后 17.40 秒：还在 2.5 + 15 = 17.5 秒内
        expectActivity(h.snap(key), .retrying(attempt: 3, max: 10))
        h.advance(0.2); h.poll()                                                // 17.60 秒：过了
        expectActivity(h.snap(key), .thinking)
    }

    @Test("c2 api_error 之后出现新的 user 行（或 assistant 行）就不再显示重试")
    func c2_aNewUserLineEndsTheRetryDisplay() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.appendTranscript(f.sid, [TL.apiError(sessionId: f.sid, at: h.now, attempt: 2, max: 5, retryInMs: 1000)])
        h.advance(0.05); h.poll()
        expectActivity(h.snap(key), .retrying(attempt: 2, max: 5))
        h.advance(3)
        h.tree.appendTranscript(f.sid, [TL.userToolResult(sessionId: f.sid, at: h.now, toolUseId: "toolu_x")])
        h.advance(0.05); h.poll()
        expectActivity(h.snap(key), .thinking)
    }

    // MARK: - (d) 出错

    /// 一轮 busy 之后 3 秒：会话记录里写入 `lines(t)`，（可选）随后 Stop，登记表 20 ms 后翻 idle。返回 t。
    @discardableResult
    func endTurn(_ h: Harness, _ f: DesktopFixture, stop: Bool = false, lines: (Date) -> [[String: Any]]) -> Date {
        h.advance(3)
        let t = h.now
        h.tree.appendTranscript(f.sid, lines(t))
        if stop { h.tree.hook(f.sid, "Stop", at: t.addingTimeInterval(0.005)) }
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: t.addingTimeInterval(0.02))
        h.advance(0.03); h.poll()
        return t
    }

    @Test("d1 出错：只有「重试到上限」（10/10，之后没有新行），没有合成消息，也是出错，并保持不闪")
    func d1_erroredByExhaustedRetriesAlone() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f) { [TL.apiError(sessionId: f.sid, at: $0, attempt: 10, max: 10)] }
        expectActivity(h.snap(key), .errored)
        #expect(K.turnFinishedEvents(h).map { $0.errored } == [true])
        #expect(h.snap(key)?.unread == true)
    }

    @Test("d2 出错：只有「最后一条 assistant 是合成的 API 错误消息」（isApiErrorMessage）")
    func d2_erroredBySyntheticApiErrorMessageAlone() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f) { [TL.assistant(sessionId: f.sid, at: $0, messageId: "syn", block: TL.text("API Error"),
                                      stopReason: "stop_sequence", model: "<synthetic>", apiErrorMessage: true)] }
        expectActivity(h.snap(key), .errored)
    }

    @Test("d3 不算出错：重试没到上限（5/10）且之后又有正常的 assistant 输出，Stop 之后是「做完了」")
    func d3_notErroredWhenRetriesRecovered() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f, stop: true) {
            [TL.apiError(sessionId: f.sid, at: $0, attempt: 5, max: 10),
             TL.assistant(sessionId: f.sid, at: $0.addingTimeInterval(0.5), messageId: "ok", block: TL.text("恢复了"), stopReason: "end_turn")]
        }
        expectActivity(h.snap(key), .finished)
        #expect(K.turnFinishedEvents(h).map { $0.errored } == [false])
    }

    @Test("d4 不算出错：重试到了上限，但之后又有 assistant 输出（api_error 不是最后一条）")
    func d4_notErroredWhenAnAssistantLineFollowsTheLastRetry() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f, stop: true) {
            [TL.apiError(sessionId: f.sid, at: $0, attempt: 10, max: 10),
             TL.assistant(sessionId: f.sid, at: $0.addingTimeInterval(0.5), messageId: "later", block: TL.text("还是说了点什么"), stopReason: "end_turn")]
        }
        expectActivity(h.snap(key), .finished)
    }

    @Test("d5 打断之后的 \"No response requested.\"（合成，但不是 API 错误）不算出错，还是被打断")
    func d5_noResponseRequestedAfterAnInterruptIsNotAnError() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f) {
            [TL.userInterrupt(sessionId: f.sid, at: $0),
             TL.assistant(sessionId: f.sid, at: $0.addingTimeInterval(0.01), messageId: "nr", block: TL.text("No response requested."),
                          stopReason: "stop_sequence", model: "<synthetic>")]
        }
        expectActivity(h.snap(key), .interrupted)
    }

    @Test("d6 出错优先于做完了：重试到上限（之后没有新行）又有 Stop 证据时，是出错，不是先闪一下做完了")
    func d6_erroredWinsOverFinishedWhenBothEvidencesExist() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        endTurn(h, f, stop: true) { [TL.apiError(sessionId: f.sid, at: $0, attempt: 10, max: 10)] }
        expectActivity(h.snap(key), .errored)
        #expect(K.turnFinishedEvents(h).map { $0.errored } == [true])
        h.advance(2); h.poll()
        expectActivity(h.snap(key), .errored)                                       // 中途也没有变成做完了
    }

    // MARK: - (e) 被打断

    @Test("e1 被打断（会话记录里的 [Request interrupted by user）：从登记表 idle 那一刻起显示 3 秒（2.9 秒还在，3.1 秒消退）")
    func e1_transcriptInterruptLastsThreeSeconds() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(4)
        let t = h.now
        h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: t)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: t); h.poll()
        expectActivity(h.snap(key), .interrupted)
        #expect(near(h.snap(key)?.idleSince, t))
        h.advance(2.9); h.poll()
        expectActivity(h.snap(key), .interrupted)
        h.advance(0.2); h.poll()
        expectActivity(h.snap(key), .idle)
        #expect(h.snap(key)?.unread == false)                                   // 自己打断的不亮未读
        #expect(K.turnFinishedEvents(h).map { $0.interrupted } == [true])
    }

    @Test("e2 被打断（hook 正常，busy→idle 没有 Stop）：不能先报「做完了」，0.4 秒后判为被打断，登记表 idle 起 3 秒内消退")
    func e2_hookInferredInterruptNeverShowsFinished() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(4)
        let t = h.now
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: t); h.poll()
        #expect(h.snap(key)?.activity != Activity.finished, "还没有 Stop、也还没到判定时间：不能显示「做完了」（提醒会据此发出去）")
        #expect(K.turnFinishedEvents(h).isEmpty)
        h.advance(0.5); h.poll()
        expectActivity(h.snap(key), .interrupted)
        #expect(K.turnFinishedEvents(h).map { $0.interrupted } == [true])
        h.advance(2.4); h.poll()                                                // 登记表 idle 后 2.9 秒
        expectActivity(h.snap(key), .interrupted)
        h.advance(0.2); h.poll()                                                // 3.1 秒
        expectActivity(h.snap(key), .idle)
        #expect(h.snap(key)?.unread == false)
    }

    @Test("e3 没有 hook 的会话：busy→idle 没有打断标记也没法判断，0.4 秒后当作做完了（不是被打断）")
    func e3_withoutHooksTheEndOfATurnIsFinishedNotInterrupted() {
        let (h, f) = K.idleSession(hooks: false)
        K.startTurn(h, f, hooks: false)
        h.advance(4)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(0.5); h.poll()
        expectActivity(h.snap(key), .finished)
        #expect(h.snap(key)?.hookActive == false)
        #expect(K.turnFinishedEvents(h).map { $0.interrupted } == [false])
    }

    @Test("e4 登记表先翻 idle、Stop 在 0.4 秒宽限期内到：是「做完了」，不是被打断")
    func e4_aStopWithinTheGraceKeepsFinished() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(4)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(0.2); h.tree.hook(f.sid, "Stop"); h.poll()
        expectActivity(h.snap(key), .finished)
        h.advance(1); h.poll()
        expectActivity(h.snap(key), .finished)
        #expect(K.turnFinishedEvents(h).map { $0.interrupted } == [false])
        #expect(h.snap(key)?.unread == true)
    }

    @Test("e5 一轮结束的证据（Stop / 打断标记 / 都没有）以任何顺序、在 0.4 秒宽限期内的任何时刻到达：结论都对，而且中途绝不先显示错误的结论")
    func e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst() {
        struct Case { var stop: Double?; var marker: Double?; var want: Activity; var never: [Activity] }
        // 偏移量是相对「登记表翻 idle」那一刻（负数 = 比登记表早，真实数据里 Stop 早 40–60 ms）
        let cases: [Case] = [
            Case(stop: -0.06, marker: nil, want: .finished, never: [.interrupted, .errored]),
            Case(stop: 0, marker: nil, want: .finished, never: [.interrupted, .errored]),
            Case(stop: 0.15, marker: nil, want: .finished, never: [.interrupted, .errored]),
            Case(stop: 0.35, marker: nil, want: .finished, never: [.interrupted, .errored]),
            Case(stop: nil, marker: -0.05, want: .interrupted, never: [.finished, .errored]),
            Case(stop: nil, marker: 0, want: .interrupted, never: [.finished, .errored]),
            Case(stop: nil, marker: 0.15, want: .interrupted, never: [.finished, .errored]),
            Case(stop: nil, marker: 0.35, want: .interrupted, never: [.finished, .errored]),
            Case(stop: nil, marker: nil, want: .interrupted, never: [.finished, .errored]),
        ]
        for c in cases {
            let (h, f) = K.idleSession()
            K.startTurn(h, f)
            h.advance(4)
            let t = h.now
            var pending: [(Double, () -> Void)] = [(0, { h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: t) })]
            if let o = c.stop { pending.append((o, { h.tree.hook(f.sid, "Stop", at: t.addingTimeInterval(o)) })) }
            if let o = c.marker { pending.append((o, { h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: t.addingTimeInterval(o))]) })) }
            var seen: [Activity] = []
            for i in 0..<50 {                                                    // 0 … 2.45 秒，每 50 ms 一次
                let dt = Double(i) * 0.05
                pending.removeAll { p in
                    if p.0 <= dt + 1e-9 { p.1(); return true }
                    return false
                }
                if i > 0 { h.advance(0.05) }
                h.poll()
                if let a = h.snap(key)?.activity { seen.append(a) }
            }
            for bad in c.never { #expect(!seen.contains(bad), "Stop \(String(describing: c.stop)) / 打断标记 \(String(describing: c.marker))：中途出现了不该出现的 \(bad)") }
            #expect(seen.last == c.want, "Stop \(String(describing: c.stop)) / 打断标记 \(String(describing: c.marker))：最终应为 \(c.want)，实际 \(String(describing: seen.last))")
            #expect(K.turnFinishedEvents(h).count == 1, "只发一次一轮结束事件")
        }
    }

    // MARK: - (f) 做完一轮

    @Test("f1 做完了：从 Stop 那一刻起显示 5 秒（4.9 秒还在，5.1 秒消退），未读一直保留")
    func f1_finishedLastsFiveSeconds() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(3)
        let stopAt = h.now
        h.tree.hook(f.sid, "Stop", at: stopAt); h.poll()
        expectActivity(h.snap(key), .finished)
        #expect(near(h.snap(key)?.idleSince, stopAt))
        h.advance(0.056); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()   // 登记表晚 56 ms 翻 idle
        h.advance(4.85); h.poll()                                               // Stop 之后 4.906 秒
        expectActivity(h.snap(key), .finished)
        h.advance(0.2); h.poll()                                                // 5.106 秒
        expectActivity(h.snap(key), .idle)
        #expect(h.snap(key)?.unread == true)
        #expect(near(h.snap(key)?.idleSince, stopAt))
    }

    @Test("f2 未读标记恰好三个清除条件：跳转（markSeen）/ 桌面 lastFocusedAt 严格晚于本轮结束 / 下一轮开始；早于或等于都不清")
    func f2_unreadClearsInExactlyThreeWays() {
        // 条件 1：跳转 = markSeen
        do {
            let (h, _) = finishedDesktopTurn()
            #expect(h.snap(key)?.unread == true)
            h.engine.markSeen(key: key); h.poll()
            #expect(h.snap(key)?.unread == false)
            h.advance(60); h.poll()
            #expect(h.snap(key)?.unread == false)                               // 不会自己再亮起来
        }
        // 条件 2：lastFocusedAt 严格晚于本轮结束；更早 / 相等都不清
        do {
            let (h, f) = finishedDesktopTurn()
            guard let end = h.snap(key)?.lastTurnEndedAt else { Issue.record("没有 lastTurnEndedAt"); return }
            func focus(_ d: Date) {
                var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
                m.lastFocusedAt = d
                h.tree.writeMeta(m)
                h.advance(1); h.poll(); h.advance(1); h.poll()
            }
            focus(end.addingTimeInterval(-1))
            #expect(h.snap(key)?.unread == true, "早于本轮结束的聚焦不清")
            focus(end)
            #expect(h.snap(key)?.unread == true, "等于本轮结束不算「晚于」")
            focus(end.addingTimeInterval(0.001))
            #expect(h.snap(key)?.unread == false, "晚 1 毫秒就算")
        }
        // 条件 3：下一轮开始
        do {
            let (h, f) = finishedDesktopTurn()
            #expect(h.snap(key)?.unread == true)
            K.startTurn(h, f)
            #expect(h.snap(key)?.unread == false)
        }
    }

    /// 一个做完了一轮、登记表 idle 的桌面会话（未读亮着；桌面 lastFocusedAt 是 500 秒前）。
    func finishedDesktopTurn() -> (Harness, DesktopFixture) {
        let (h, f) = K.idleSession()
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastFocusedAt = h.now.addingTimeInterval(-500)
        h.tree.writeMeta(m)
        K.startTurn(h, f)
        h.advance(3); h.tree.hook(f.sid, "Stop"); h.poll()
        h.advance(0.056); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        return (h, f)
    }

    @Test("f3 桌面本轮总结：completed 不亮 blocked；blocked 落盘得晚（7 秒后，做完了已消退）也亮，只发一次事件，保持到下一轮")
    func f3_blockedOverlayFollowsTheDesktopSummary() {
        let (h, f) = K.idleSession()
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastAssistantUuid = "u1"
        h.tree.writeMeta(m)
        K.startTurn(h, f)
        h.advance(3)
        m.lastAssistantUuid = "u2"; h.tree.writeMeta(m)
        h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        #expect(h.snap(key)?.blocked == false)
        // 第 7 秒：总结落盘，是 completed
        h.advance(7)
        m.summaryFor = "u2"; m.summaryCategory = "completed"; m.summaryDetail = "all done"
        h.tree.writeMeta(m)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(key)?.blocked == false)
        #expect(h.snap(key)?.statusDetail == "all done")
        expectActivity(h.snap(key), .idle)                                      // 「做完了」5 秒早就过去了
        // 换成 blocked（同一条 assistant 消息的总结被更新）
        m.summaryCategory = "blocked"; m.summaryDetail = "needs you"
        h.tree.writeMeta(m)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(key)?.blocked == true)
        #expect(K.count(h.kinds(key), .blocked) == 1)
        h.advance(3600); h.poll()
        #expect(h.snap(key)?.blocked == true)                                   // 保持到下一轮
        #expect(h.snap(key)?.unread == true)                                    // 叠加标记互不影响
        K.startTurn(h, f)
        #expect(h.snap(key)?.blocked == false)
        #expect(K.count(h.kinds(key), .blocked) == 1)
    }

    // MARK: - (g) 打盹 / 睡着

    @Test("g1 空闲 10 分钟打盹、45 分钟睡着（默认值；从这一轮结束那一刻起算）")
    func g1_dozeAt10MinutesSleepAt45Minutes() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(3)
        h.tree.hook(f.sid, "Stop"); h.poll()
        h.advance(0.056); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        guard let idleSince = h.snap(key)?.idleSince else { Issue.record("没有 idleSince"); return }
        let s0 = idleSince.timeIntervalSince(Harness.epoch)
        let steps: [(Double, Activity)] = [(6.0, .idle), (599.9, .idle), (600.1, .dozing), (2699.9, .dozing), (2700.1, .sleeping), (86400, .sleeping)]
        for (dt, want) in steps {
            K.goto(h, s0 + dt); h.poll()
            expectActivity(h.snap(key), want)
        }
    }

    // MARK: - (h) 忙了 2 小时也不会被判死

    @Test("h1 busy 连续 2 小时（一次推进 2 小时 + 反复心跳）：还在场、还是 busy、还是那个工具，只是 quiet")
    func h1_twoHoursOfBusyIsQuietNotDead() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 7200")
        h.poll()
        let su = h.snap(key)?.turnStartedAt
        h.clearEvents()
        h.advance(2 * 3600)                                                     // 一次推进 2 小时
        for i in 0..<60 {                                                       // 反复心跳（登记表的 statusUpdatedAt 一直不变，hook 和会话记录都没有新内容）
            if i > 0 { h.advance(1) }
            h.poll()
            let s = h.snap(key)
            #expect(s?.presence == .present, "第 \(i) 次心跳")
            #expect(s?.phase == .busy)
            #expect(s?.quiet == true)
            #expect(K.tool(s)?.call.name == "Bash" && K.tool(s)?.parallel == 1)
            #expect(s?.hookActive == true)
            #expect(s?.turnStartedAt == su)
        }
        #expect(h.kinds(key).isEmpty, "不该有任何离场 / 结束事件：\(h.kinds(key))")
        #expect(h.snapshots.count == 1)
    }

    @Test("h2 quiet 恰好是「10 分钟没有增长」：9 分 59 秒不是、10 分 01 秒是；hook 或会话记录任何一个有新内容都会立刻清掉")
    func h2_quietThresholdAndItsResets() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 9999"); h.poll()
        let growth = K.secs(h)
        K.goto(h, growth + 599); h.poll()
        #expect(h.snap(key)?.quiet == false)
        K.goto(h, growth + 601); h.poll()
        #expect(h.snap(key)?.quiet == true)
        // 会话记录长了一行（hook 没有动静）：清掉
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "grow", block: TL.text("…"), stopReason: "tool_use")])
        h.poll()
        #expect(h.snap(key)?.quiet == false)
        let g2 = K.secs(h)
        K.goto(h, g2 + 599); h.poll()
        #expect(h.snap(key)?.quiet == false)
        K.goto(h, g2 + 601); h.poll()
        #expect(h.snap(key)?.quiet == true)
        // hook 有新事件：清掉
        h.tree.hook(f.sid, "PostToolUse", tool: "Bash", detail: "sleep 9999"); h.poll()
        #expect(h.snap(key)?.quiet == false)
        #expect(h.snap(key)?.presence == .present)
    }
}

// MARK: - (i) 进程被回收 / 离场 / 下班工位

extension StateRuleTests {
    func terminalSession(_ h: Harness, n: Int = 1) -> (FakeClaudeTree.Session, String) {
        let sid = String(format: "aaaaaaaa-0000-4000-8000-%012d", n)
        let s = FakeClaudeTree.Session(pid: Int32(1000 + n), sessionId: sid, host: nil, name: "会话\(n)", startedAt: h.now.addingTimeInterval(-600))
        return (s, "t:" + sid)
    }

    @Test("i1 登记文件消失：先防抖 3 秒（2.95 秒时仍在场，3.05 秒离场，事件只发一次），非下班工位确认离场后 8 秒收回")
    func i1_departureDebounceThenReclaimAfter8Seconds() {
        let h = Harness()
        let (s, k) = terminalSession(h)
        h.tree.writeRegistry(s, status: "idle"); h.poll(); h.clearEvents()
        h.tree.endProcess(pid: s.pid)                                            // 登记文件消失，进程也没了
        h.poll()                                                                 // 这次 poll 发现：防抖开始
        #expect(h.snap(k)?.presence == .present)
        h.advance(2.95); h.poll()
        #expect(h.snap(k)?.presence == .present)
        #expect(h.kinds(k).isEmpty)
        h.advance(0.1); h.poll()                                                 // 3.05 秒
        guard case .away(_, let dormant)? = h.snap(k)?.presence else { Issue.record("3.05 秒时应该已经离场"); return }
        #expect(!dormant)
        #expect(h.kinds(k) == [.departed(dormant: false)])
        let confirmed = K.secs(h)
        K.goto(h, confirmed + 7.9); h.poll()
        #expect(h.snapshots.count == 1, "确认离场后 7.9 秒工位还没收回")
        K.goto(h, confirmed + 8.1); h.poll()
        #expect(h.snapshots.isEmpty, "8 秒后收回工位")
        #expect(h.kinds(k) == [.departed(dormant: false)])
    }

    @Test("i2 桌面会话 + 元数据还在 + 没归档：离场后是下班工位（不会 8 秒后收回）；归档了就是普通离场")
    func i2_dormantSeatOnlyForDesktopSessionsWithLiveUnarchivedMetadata() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        let g = FakeClaudeTree.Session(pid: 1002, sessionId: "aaaaaaaa-0000-4000-8000-000000000002", host: "local_arch", name: "归档的", startedAt: h.now.addingTimeInterval(-600))
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        h.tree.writeMeta(m)
        m = FakeClaudeTree.Meta(host: "local_arch", cliSessionId: g.sessionId, lastActivityAt: h.now)
        m.archived = true
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle"); h.tree.writeRegistry(g, status: "idle"); h.poll(); h.clearEvents()
        h.tree.endProcess(pid: f.session.pid); h.tree.endProcess(pid: g.pid)
        h.poll(); h.advance(3.05); h.poll()
        #expect(h.kinds(key) == [.departed(dormant: true)])
        #expect(h.kinds("d:local_arch") == [.departed(dormant: false)])
        h.advance(60); h.poll()
        #expect(h.snapshots.map { $0.key } == [key], "下班工位一直留着（12 小时之内），归档的那个 8 秒后收回")
        guard case .away(_, true)? = h.snap(key)?.presence else { Issue.record("应该是下班工位"); return }
        expectActivity(h.snap(key), .idle)
    }

    @Test("i3 同一个身份（同一个人）在 8 秒收回之前带着新进程回来：坐回原来的工位，发一次「进场」")
    func i3_theSameIdentityComingBackDuringTheLingerSitsInTheSameSeat() {
        let h = Harness()
        let (a, ka) = terminalSession(h, n: 1)
        let (b, kb) = terminalSession(h, n: 2)
        h.tree.writeRegistry(a, status: "idle"); h.tree.writeRegistry(b, status: "idle"); h.poll()
        let before = h.snap(ka)!
        h.tree.endProcess(pid: a.pid)
        h.run(for: 3.2)
        guard case .away? = h.snap(ka)?.presence else { Issue.record("应该已经离场"); return }
        h.clearEvents()
        h.advance(2)                                                             // 还在 8 秒收回之前
        let back = FakeClaudeTree.Session(pid: 4321, sessionId: a.sessionId, host: nil, name: "会话1", startedAt: h.now)
        h.tree.writeRegistry(back, status: "idle"); h.poll()
        #expect(h.snap(ka)?.presence == .present)
        #expect(h.snap(ka)?.seat == before.seat && h.snap(ka)?.salt == before.salt)
        #expect(h.snap(ka)?.pid == 4321)
        #expect(h.kinds(ka) == [.arrived(freshAfterLaunch: true)])
        #expect(h.snap(kb)?.seat == 1)
        #expect(h.snapshots.count == 2)
    }

    @Test("i4 PID 被复用：procStart 和进程实际启动时间相差恰好 2 秒还算同一个进程，超过 2 秒（哪怕 1 毫秒）就是别的进程")
    func i4_pidReuseToleranceIsExactlyTwoSeconds() {
        let start = Date(timeIntervalSince1970: 1_790_654_597)
        for (delta, want) in [(0.0, ProcessLiveness.alive), (1.999, .alive), (2.0, .alive), (2.001, .reused),
                              (-2.0, .alive), (-2.001, .reused), (600, .reused)] as [(Double, ProcessLiveness)] {
            let got = ProcessProbe.classify(.init(state: .alive, startTime: start.addingTimeInterval(delta)), procStart: start)
            #expect(got == want, "相差 \(delta) 秒应该是 \(want)，实际 \(got)")
        }
        #expect(ProcessProbe.classify(.init(state: .dead, startTime: start), procStart: start) == .dead)
        #expect(ProcessProbe.classify(.init(state: .unknown), procStart: start) == .alive)               // sysctl 失败 = 未知 = 活着
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: nil), procStart: start) == .alive)   // kill 成功但读不到启动时间
    }

    @Test("i5 引擎：kill 成功但 sysctl 读不到启动时间（startTime = nil）当作活着，而且一直活着")
    func i5_aliveWithoutAStartTimeStaysPresent() {
        let h = Harness()
        let (s, k) = terminalSession(h)
        h.tree.writeRegistry(s, status: "busy", markAlive: false)
        h.probe.setAlive(s.pid, start: nil)
        h.poll(); h.run(for: 10)
        #expect(h.snap(k)?.presence == .present)
        #expect(h.kinds(k) == [.arrived(freshAfterLaunch: false)])
    }

    @Test("i6 引擎：PID 被复用（登记文件还在、pid 也还活着，但启动时间差 3 秒）算离场，同样先防抖 3 秒")
    func i6_pidReuseGoesThroughTheSameDebounce() {
        let h = Harness()
        let (s, k) = terminalSession(h)
        h.tree.writeRegistry(s, status: "busy"); h.poll(); h.clearEvents()
        h.probe.setAlive(s.pid, start: s.startedAt.addingTimeInterval(3))
        h.advance(1.1); h.poll()                                                 // 存活检查每 1 秒一次：这次发现，防抖开始
        #expect(h.snap(k)?.presence == .present)
        h.advance(2.9); h.poll()
        #expect(h.snap(k)?.presence == .present, "发现后 2.9 秒仍在场")
        h.advance(0.2); h.poll()
        guard case .away? = h.snap(k)?.presence else { Issue.record("发现后 3.1 秒应该离场"); return }
    }
}

// MARK: - (j) /clear、--resume 之后还认得是同一个人

extension StateRuleTests {
    @Test("j1 桌面会话在同一个进程里 /clear：key、工位、盐不变，旧会话的东西不带过来，token = 新旧两份会话记录之和")
    func j1_desktopClearInTheSameProcessKeepsTheBuddy() {
        let h = Harness(tokens: true)
        let f = DesktopFixture(h: h)
        let s1 = f.sid, s2 = "cccccccc-0000-4000-8000-00000000000b"
        var meta = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: s1, lastActivityAt: h.now)
        h.tree.writeMeta(meta)
        h.tree.appendTranscript(s1, [TL.assistant(sessionId: s1, at: h.now, messageId: "a1", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 1000))])
        h.tree.hook(s1, "UserPromptSubmit"); h.tree.hook(s1, "PreToolUse", tool: "Bash", detail: "old session tool")
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        #expect(K.tool(h.snap(key))?.call.detail == "old session tool")
        h.advance(3); h.tree.hook(s1, "Stop"); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(60); h.poll()
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60); h.advance(0.2); h.poll()
        #expect(h.snap(key)?.tokens.output == 1000)
        let seat = h.snap(key)!.seat, salt = h.snap(key)!.salt
        h.clearEvents()

        // /clear：同一个进程（pid 和启动时间不变）、同一个 hostSessionId，登记表里的 sessionId 换了；桌面元数据把旧的记进 priorCliSessionIds
        h.advance(5)
        meta.cliSessionId = s2; meta.priors = [s1]
        h.tree.writeMeta(meta)
        h.tree.appendTranscript(s2, [TL.assistant(sessionId: s2, at: h.now, messageId: "b1", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 7))])
        h.tree.hook(s2, "SessionStart", extra: "clear")
        var cleared = f.session; cleared.sessionId = s2
        h.tree.writeRegistry(cleared, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(1); h.poll(); _ = h.engine.ledger?.waitUntilIdle(timeout: 60); h.advance(0.2); h.poll()
        let s = h.snap(key)
        #expect(h.snapshots.count == 1)
        #expect(s?.sessionId == s2)
        #expect(s?.seat == seat && s?.salt == salt)
        #expect(s?.phase == .idle)
        #expect(h.engine.openMainTools(key: key).isEmpty)
        #expect(s?.tokens.output == 1000 + 7, "桌面会话要把 priorCliSessionIds 对应的会话记录加起来")
        #expect(!h.kinds(key).contains { if case .departed = $0 { return true } else { return false } })
    }

    @Test("j2 终端会话的 key 是 \"t:\" + 第一次见到的 sessionId：/clear、进程退出后在新进程里 --resume 新的 sessionId，还是同一个人")
    func j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume() {
        let h = Harness()
        let (s1, k) = terminalSession(h)
        h.tree.writeRegistry(s1, status: "idle"); h.poll()
        #expect(k == "t:" + s1.sessionId)
        let before = h.snap(k)!
        #expect(before.key == k)
        // /clear：同一个进程，sessionId 换成 s2
        let s2 = "cccccccc-0000-4000-8000-00000000000c"
        h.tree.hook(s2, "SessionStart", extra: "clear")
        var cleared = s1; cleared.sessionId = s2
        h.tree.writeRegistry(cleared, status: "idle"); h.poll()
        #expect(h.only()?.key == k)
        #expect(h.only()?.sessionId == s2)
        // 进程退出，工位收回；之后在新进程里 --resume 现在的会话（s2）
        h.tree.endProcess(pid: s1.pid)
        h.run(for: 12)
        #expect(h.snapshots.isEmpty)
        let resumed = FakeClaudeTree.Session(pid: 4321, sessionId: s2, host: nil, name: "会话1", startedAt: h.now)
        h.tree.writeRegistry(resumed, status: "idle"); h.poll()
        #expect(h.only()?.key == k, "key 永远是第一次见到的 sessionId，不是现在的")
        #expect(h.only()?.seat == before.seat)
        #expect(h.only()?.salt == before.salt)
    }

    @Test("j3 桌面会话在新进程里 resume、登记表里没有 hostSessionId：靠桌面元数据的 cliSessionId / priorCliSessionIds 认出是谁")
    func j3_desktopResumeIsRecognizedThroughTheMetadataCliSessionIds() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        let s2 = "cccccccc-0000-4000-8000-00000000000d"
        var meta = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        h.tree.writeMeta(meta)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        let before = h.snap(key)!
        h.tree.endProcess(pid: f.session.pid)
        h.run(for: 3.2)
        h.advance(60)
        // 用户再次打开：新进程、新 sessionId，登记表里没有 hostSessionId；桌面元数据说 s2 是这个窗口的当前会话，旧的在 prior 里
        meta.cliSessionId = s2; meta.priors = [f.sid]
        meta.lastActivityAt = h.now
        h.tree.writeMeta(meta)
        let resumed = FakeClaudeTree.Session(pid: 3001, sessionId: s2, host: nil, name: nil, startedAt: h.now, entrypoint: "claude-desktop")
        h.tree.writeRegistry(resumed, status: "idle"); h.advance(1); h.poll()
        #expect(h.only()?.key == key)
        #expect(h.only()?.presence == .present)
        #expect(h.only()?.seat == before.seat && h.only()?.salt == before.salt)
        #expect(h.only()?.hostSessionId == f.session.host)
    }
}

// MARK: - (k) 子代理事件归属

extension StateRuleTests {
    /// 一个 busy 的桌面会话，主会话记录已有文件（和 HelperAttributionEngineTests.setup 一样）。
    func busySession() -> (Harness, DesktopFixture) {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.tree.writeRegistry(f.session, status: "idle")
        h.poll()
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.poll()
        return (h, f)
    }

    @Test("k1 前台 Task（不只是 Agent）开着：比它晚 0.15 秒以上的事件归小助手，0.149 秒的同批并行调用还是主线程的")
    func k1_foregroundTaskAttributionBoundaryAt150ms() {
        let (h, f) = busySession()
        h.advance(0.5)
        let t = h.now
        h.tree.hook(f.sid, "PreToolUse", tool: "Task", detail: "研究", at: t)
        h.tree.writeSubagentMeta(f.sid, agentId: "tk01", foreground: true, description: "研究")
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/sibling", at: t.addingTimeInterval(0.149))
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "helper-cmd", at: t.addingTimeInterval(0.15))
        h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Task", "Read"])
        #expect(h.engine.debugState(key: key)?.tracker.helperOpen.map { $0.call.name } == ["Bash"])
        // 前台 Task 结束（Post）之后，主线程的新调用不再被当成小助手的
        h.advance(1)
        h.tree.hook(f.sid, "PostToolUse", tool: "Task", detail: "研究")
        h.tree.hook(f.sid, "PreToolUse", tool: "Grep", detail: "after")
        h.poll()
        #expect(h.engine.openMainTools(key: key).map { $0.call.name } == ["Grep"])
    }

    @Test("k2 SubagentStop 只当「总结已生成」的提示：让下一次 poll 马上重读桌面元数据，不改变工具和阶段")
    func k2_subagentStopIsOnlyASummaryHint() {
        let (h, f) = K.idleSession()
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastAssistantUuid = "u1"
        h.tree.writeMeta(m)
        K.startTurn(h, f)
        h.advance(3)
        m.lastAssistantUuid = "u2"; h.tree.writeMeta(m)
        h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        // 总结落盘了，但离上一次读元数据只过了 0.1 秒（数据层每 0.5 秒才重新列一次目录）
        h.advance(0.1)
        m.summaryFor = "u2"; m.summaryCategory = "blocked"; m.summaryDetail = "needs you"
        h.tree.writeMeta(m)
        h.poll()
        #expect(h.snap(key)?.blocked == false, "限速内不重读")
        h.tree.hook(f.sid, "SubagentStop"); h.advance(0.01); h.poll(); h.advance(0.01); h.poll()
        #expect(h.snap(key)?.blocked == true, "SubagentStop 之后应马上重读元数据")

        // SubagentStop 不代表小助手做完了，也不影响主线程的工具 / 阶段
        let (h2, f2) = K.idleSession()
        K.startTurn(h2, f2)
        h2.advance(1); h2.tree.hook(f2.sid, "PreToolUse", tool: "Bash", detail: "long job"); h2.poll()
        h2.advance(1); h2.tree.hook(f2.sid, "SubagentStop"); h2.poll()
        #expect(h2.engine.openMainTools(key: key).map { $0.call.name } == ["Bash"])
        #expect(h2.snap(key)?.phase == .busy)
        #expect(K.tool(h2.snap(key))?.call.name == "Bash")
    }

    @Test("k3 有后台小助手活跃、事件对不上任何 tool_use：扣住 0.4 秒（0.39 秒还扣着，0.41 秒归主线程）")
    func k3_unmatchedEventIsHeldForExactly400ms() {
        let (h, f) = busySession()
        h.tree.writeSubagentMeta(f.sid, agentId: "bg03", foreground: false)
        h.tree.appendSubagent(f.sid, agentId: "bg03", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "mb3", block: TL.text("hi"), stopReason: nil, agentId: "bg03")])
        h.advance(0.5); h.poll()
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make build")
        h.poll()
        expectActivity(h.snap(key), .thinking)
        h.advance(0.39); h.poll()
        expectActivity(h.snap(key), .thinking)
        h.advance(0.02); h.poll()
        #expect(K.tool(h.snap(key))?.call.name == "Bash", "扣满 0.4 秒后归主线程")
    }
}

// MARK: - (l) 等待类的判定（引擎层）

extension StateRuleTests {
    func waitingSession(_ waitingFor: String, tools: [(String, String)] = [], notification: String? = nil) -> (Harness, DesktopFixture) {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        let t = h.now
        for (i, (name, detail)) in tools.enumerated() {
            h.tree.hook(f.sid, "PreToolUse", tool: name, detail: detail, at: t.addingTimeInterval(Double(i) * 0.01))
        }
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: waitingFor, statusUpdatedAt: t.addingTimeInterval(0.1))
        if let n = notification { h.tree.hook(f.sid, "Notification", extra: n, at: t.addingTimeInterval(0.5)) }
        h.advance(0.6); h.poll()
        return (h, f)
    }

    func needsUserKinds(_ h: Harness) -> [AttentionKind] {
        h.kinds(key).compactMap { if case .needsUser(let a) = $0 { return a } else { return nil } }
    }

    @Test("l1 等批准：没有打开的主线程调用时，工具从 Notification 文本里的 `use <T>` 解析")
    func l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen() {
        let (h, _) = waitingSession("permission prompt", notification: "Claude needs your permission to use Bash")
        guard case .waitingApproval(let t?)? = h.snap(key)?.activity else { Issue.record("应该是等批准，实际 \(String(describing: h.snap(key)?.activity))"); return }
        #expect(t.name == "Bash" && t.category == .bash)
        #expect(h.snap(key)?.phase == .waiting)
        #expect(needsUserKinds(h).count == 1)
        // 有打开的调用时取「最新打开的那个」
        let (h2, _) = waitingSession("permission prompt", tools: [("Read", "/a"), ("Bash", "git push")])
        guard case .waitingApproval(let t2?)? = h2.snap(key)?.activity else { Issue.record("应该是等批准"); return }
        #expect(t2.name == "Bash" && t2.detail == "git push")
        // sandbox request 同样是等批准
        let (h3, _) = waitingSession("sandbox request", tools: [("Bash", "curl x")])
        guard case .waitingApproval? = h3.snap(key)?.activity else { Issue.record("sandbox request 应该算等批准"); return }
    }

    @Test("l2 提问：input needed / dialog open → 提问；ExitPlanMode 开着 → 计划待审（两种等待文字都一样）")
    func l2_questionsAndPlanReview() {
        for wf in ["input needed", "dialog open"] {
            let (h, _) = waitingSession(wf, tools: [("AskUserQuestion", "第一个选项的 description，不是问题本身")])
            expectActivity(h.snap(key), .asking)
            #expect(h.engine.openMainTools(key: key).first?.call.detail == "", "AskUserQuestion 的 detail 永远不保留")
            #expect(needsUserKinds(h).count == 1)
            if case .question? = needsUserKinds(h).first {} else { Issue.record("\(wf) 的提醒类型应该是提问") }
        }
        for wf in ["input needed", "permission prompt"] {
            let (h, _) = waitingSession(wf, tools: [("Read", "x"), ("ExitPlanMode", "")], notification: "Claude needs your permission to use ExitPlanMode")
            expectActivity(h.snap(key), .planReview)
            if case .planReview? = needsUserKinds(h).first {} else { Issue.record("\(wf) + ExitPlanMode 的提醒类型应该是计划待审") }
        }
        // AskUserQuestion 的 Notification 文本也叫 permission，但它是提问
        let (h, _) = waitingSession("permission prompt", tools: [("AskUserQuestion", "")], notification: "Claude needs your permission to use AskUserQuestion")
        expectActivity(h.snap(key), .asking)
    }

    @Test("l3 其他等待：goal proposal / worker request 等，附原始文本；批准之后回到 busy 发「不再等你」")
    func l3_otherWaitsCarryTheRawText() {
        for raw in ["goal proposal", "worker request"] {
            let (h, f) = waitingSession(raw)
            expectActivity(h.snap(key), .waitingOther(raw))
            if case .other(let text)? = needsUserKinds(h).first { #expect(text == raw) } else { Issue.record("提醒类型应该是 other") }
            h.advance(2); h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now); h.poll()
            #expect(h.kinds(key).contains(.needsUserCleared))
            #expect(h.snap(key)?.phase == .busy)
        }
    }
}

// MARK: - (m) phase 的两个临时修正

extension StateRuleTests {
    @Test("m1 登记表还是 idle 但有更新的 UserPromptSubmit：暂时当 busy，最多 3 秒（2.9 秒还是 busy，3.1 秒回 idle），只开始一轮")
    func m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds() {
        let (h, f) = K.idleSession()
        h.advance(1)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now)                        // 登记表一直是 idle（比如本地处理的斜杠命令）
        h.poll()
        #expect(h.snap(key)?.phase == .busy)
        expectActivity(h.snap(key), .thinking)
        h.advance(2.9); h.poll()
        #expect(h.snap(key)?.phase == .busy)
        h.advance(0.2); h.poll()
        #expect(h.snap(key)?.phase == .idle)
        #expect(K.count(h.kinds(key), .turnStarted) == 1)
    }

    @Test("m2 登记表还是 busy 但有更新的 Stop：暂时当 idle；随后又来一条更新的提示（排队的下一轮）就又是 busy")
    func m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(3)
        h.tree.hook(f.sid, "Stop"); h.poll()                                     // 登记表还是 busy
        #expect(h.snap(key)?.phase == .idle)
        expectActivity(h.snap(key), .finished)
        h.advance(0.1)
        h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
        #expect(h.snap(key)?.phase == .busy)
        #expect(K.count(h.kinds(key), .turnStarted) == 2)
        #expect(K.turnFinishedEvents(h).count == 1)
        #expect(h.snap(key)?.unread == false)
    }
}

// MARK: - (n) 4.1 登记表读取规则

extension StateRuleTests {
    @Test("n1 登记表写到一半（原地重写）：保留上一份好记录，每 50 ms 重试，读满 5 次后不再读，会话不离场；写完整了立刻更新")
    func n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        expectActivity(h.snap(key), .thinking)
        let path = h.tree.paths.sessionsDir + "/1001.json"
        guard let good = FileManager.default.contents(atPath: path) else { Issue.record("读不到登记表"); return }
        FakeClaudeTree.writeInPlace(path, good.prefix(30))
        h.advance(0.01); h.poll()
        #expect(h.snap(key)?.presence == .present)
        expectActivity(h.snap(key), .thinking)
        let wake = h.lastOutput?.nextWake
        #expect(wake != nil && wake!.timeIntervalSince(h.now) <= 0.0501 && wake!.timeIntervalSince(h.now) > 0, "50 ms 后要再读一次")
        for _ in 0..<12 {                                                        // 超过 5 次重试的时间（0.6 秒）：仍在场、仍是上一份好记录
            h.advance(0.05); h.poll()
            #expect(h.snap(key)?.presence == .present)
            expectActivity(h.snap(key), .thinking)
            #expect(h.snap(key)?.pid == 1001)
        }
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "input needed", statusUpdatedAt: h.now); h.poll()
        expectActivity(h.snap(key), .asking)
    }

    @Test("n2 只打开文件名匹配 ^\\d+\\.json$ 的文件：.key、.bak、非数字名、多段名一个都不碰（连 stat 也不做）")
    func n2_onlyPidJsonFilesAreOpened() {
        let dir = "/fake/sessions"
        let names = ["1001.json", "1001.abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789.key", "abc.json", "12a.json",
                     "1002.json.bak", "1003.json", ".json", "1004.json.key", "1005.sha.json", "1006.key"]
        var opened: [String] = [], statted: [String] = []
        let sc = RegistryScanner(dir: dir,
                                 listDir: { _ in names },
                                 statFile: { p in statted.append(p); return FileStat(dev: 1, ino: 1, size: 40, mtimeNs: 1, isDirectory: p == dir) },
                                 readFile: { p in opened.append(p); return Data(#"{"pid":1,"sessionId":"s"}"#.utf8) })
        let r = sc.scan(now: Harness.epoch)
        #expect(Set(opened) == [dir + "/1001.json", dir + "/1003.json"])
        #expect(!statted.contains { $0.hasSuffix(".key") || $0.hasSuffix(".bak") || $0.contains("abc") }, "\(statted)")
        #expect(r.fileCount == 2)
    }
}

// MARK: - (o) 整理上下文（清单外：真实日志里出现了 PreCompact / PostCompact / compact_boundary，按真实时序验证）

extension StateRuleTests {
    /// 真实日志（这台机器，20c4bcc8 那个会话的 3 次自动压缩）里的时序：
    ///   PreCompact(auto) → 88–104 秒后 → 会话记录先写一行 isCompactSummary 的 user 行（比边界早 0.3–0.4 秒）→
    ///   hook 的 SessionStart(source=compact)（比 compact_boundary 早约 0.04 秒）→ PostCompact（早约 0.02 秒）→ compact_boundary（压缩结束时才写）→
    ///   3–5 秒后第一条 assistant 行 / 第一个 PreToolUse。
    @Test("o1 整理上下文：真实时序里 compact_boundary 是压缩「结束」时才写的——hook 已经说压缩结束之后，不能再靠它显示整理上下文，压缩完的第一个工具要马上显示")
    func o1_compactionEndsWhenTheHooksSayItEnded() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(0.1)
        h.tree.hook(f.sid, "PreCompact", extra: "auto")
        h.poll()
        expectActivity(h.snap(key), .compacting)
        h.advance(100); h.poll()
        expectActivity(h.snap(key), .compacting)                                  // 压缩进行中（会话记录里什么都没有）：靠 hook 的 PreCompact
        let end = h.now                                                           // 压缩结束
        var summary = TL.userPrompt(sessionId: f.sid, at: end.addingTimeInterval(-0.4))
        summary["isCompactSummary"] = true
        h.tree.appendTranscript(f.sid, [summary, TL.system(sessionId: f.sid, at: end.addingTimeInterval(0.04), subtype: "compact_boundary")])
        h.tree.hook(f.sid, "SessionStart", extra: "compact", at: end)
        h.tree.hook(f.sid, "PostCompact", at: end.addingTimeInterval(0.02))
        h.advance(0.1); h.poll()
        #expect(h.snap(key)?.activity != Activity.compacting, "SessionStart(compact) / PostCompact 都来了，不能还显示整理上下文（compact_boundary 是压缩结束时写的）")
        expectActivity(h.snap(key), .thinking)
        h.advance(4.6)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "npm test"); h.poll()      // 真实数据里压缩结束后 3–5 秒第一个工具
        #expect(K.tool(h.snap(key))?.call.name == "Bash", "压缩结束后第一个工具应该马上显示，而不是被「整理上下文」盖住")
    }

    @Test("o2 hook 说「压缩结束」的口径：PostCompact / SessionStart(compact) 不早于 compact_boundary 前 5 秒才算；更早的是上一次压缩的，没有 hook 就照旧用会话记录")
    func o2_boundaryHookSlackIsFiveSeconds() {
        func sig(postCompact: Double?) -> SessionSignals {
            var s = SessionSignals()
            s.registryStatus = .busy; s.statusUpdatedAt = at(0); s.hookActive = true
            s.compactBoundaryAt = at(200); s.lastAssistantOrUserAt = at(199.6)
            s.postCompactAt = postCompact.map { at($0) }
            return s
        }
        #expect(ActivityResolver.resolve(sig(postCompact: 199.98), now: at(201)) == .thinking)       // 真实时序：PostCompact 比边界早 0.02 秒
        #expect(ActivityResolver.resolve(sig(postCompact: 200.5), now: at(201)) == .thinking)         // 顺序反过来也算
        #expect(ActivityResolver.resolve(sig(postCompact: 195.1), now: at(201)) == .thinking)         // 边界前 4.9 秒
        #expect(ActivityResolver.resolve(sig(postCompact: 194.9), now: at(201)) == .compacting)       // 边界前 5.1 秒：是更早那次压缩的 PostCompact
        #expect(ActivityResolver.resolve(sig(postCompact: nil), now: at(201)) == .compacting)         // 没有 hook：只有会话记录这一个信号
        #expect(ActivityResolver.resolve(sig(postCompact: nil), now: at(200 + 120.1)) == .thinking)   // 120 秒兜底
    }
}
