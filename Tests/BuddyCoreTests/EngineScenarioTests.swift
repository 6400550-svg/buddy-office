import Foundation
import Testing
@testable import BuddyCore

/// 带时间的事件脚本 → 断言期望的动作时间线（冻结的虚拟时钟，完全确定）。
@Suite struct EngineScenarioTests {
    let key = DesktopFixture.key

    /// 已经在场的空闲会话（App 启动时就在）。
    func idleSession(persist: Bool = false, tokens: Bool = false, registerHook: Bool = true) -> (Harness, DesktopFixture) {
        let h = Harness(persist: persist, tokens: tokens, registerHook: registerHook)
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.customTitle(sessionId: f.sid, "会话标题"), TL.userPrompt(sessionId: f.sid, at: h.now.addingTimeInterval(-50))])
        if registerHook { h.tree.hook(f.sid, "SessionStart", extra: "startup", at: h.now.addingTimeInterval(-50)) }
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-40))
        h.poll()
        h.clearEvents()
        return (h, f)
    }

    /// 开始一轮：登记表 busy（先），随后 hook 的 UserPromptSubmit（后 90 ms，和真实数据一致）。
    func startTurn(_ h: Harness, _ f: DesktopFixture) {
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(0.09))
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now.addingTimeInterval(0.09))])
        h.advance(0.1)
        h.poll()
    }

    // MARK: 一轮的完整时间线

    @Test func aNormalTurnProducesTheExpectedActivitiesAndEvents() {
        let (h, f) = idleSession()
        startTurn(h, f)
        expectActivity(h.snap(key), .thinking)
        #expect(h.snap(key)?.turnStartedAt != nil)
        #expect(h.kinds(key) == [.turnStarted])

        h.advance(2); h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "npm test"); h.poll()
        guard case .tool(let c, 1)? = h.snap(key)?.activity else { Issue.record("应该是 Bash"); return }
        #expect(c.category == .bash)
        h.advance(30); h.tree.hook(f.sid, "PostToolUse", tool: "Bash", detail: "npm test", extra: "len=99"); h.poll()
        expectActivity(h.snap(key), .thinking)

        // 真实数据里 Stop 比登记表翻成 idle 早 40–60 ms（Stop hook 是同步的）
        h.advance(5)
        let stopAt = h.now
        h.tree.hook(f.sid, "Stop", at: stopAt); h.poll()
        expectActivity(h.snap(key), .finished)
        #expect(h.snap(key)?.phase == .idle)
        #expect(h.snap(key)?.unread == true)
        #expect(h.snap(key)?.turnStartedAt == nil)
        var finishedEvents = h.kinds(key).filter { if case .turnFinished = $0 { return true } else { return false } }
        #expect(finishedEvents.count == 1)
        guard case .turnFinished(let dur?, false, false) = finishedEvents[0] else { Issue.record("turnFinished 参数不对：\(finishedEvents)"); return }
        #expect(abs(dur - 37.1) < 0.2)                                          // 0.1 + 2 + 30 + 5 秒左右（从登记表翻 busy 起算）

        h.advance(0.056)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()   // 登记表随后也翻成 idle
        expectActivity(h.snap(key), .finished)
        finishedEvents = h.kinds(key).filter { if case .turnFinished = $0 { return true } else { return false } }
        #expect(finishedEvents.count == 1)                                       // 没有重复的一轮结束事件

        h.advance(5.2); h.poll()
        expectActivity(h.snap(key), .idle)                                       // 做完了持续 5 秒
        #expect(h.snap(key)?.unread == true)                                     // 未读一直保留
        #expect(abs((h.snap(key)?.idleSince ?? .distantPast).timeIntervalSince(stopAt)) < 0.001)
        h.engine.markSeen(key: key); h.poll()
        #expect(h.snap(key)?.unread == false)
    }

    @Test func startingTheNextTurnClearsUnread() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(3); h.tree.hook(f.sid, "Stop"); h.poll()
        #expect(h.snap(key)?.unread == true)
        startTurn(h, f)
        #expect(h.snap(key)?.unread == false)
    }

    @Test func promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce() {
        let (h, f) = idleSession()
        h.advance(1)
        h.tree.hook(f.sid, "UserPromptSubmit")                                   // hook 比登记表快
        h.poll()
        expectActivity(h.snap(key), .thinking)                                   // 临时修正：暂时当作 busy
        #expect(h.kinds(key) == [.turnStarted])
        h.advance(0.05)
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        expectActivity(h.snap(key), .thinking)
        #expect(h.kinds(key) == [.turnStarted])                                  // 登记表随后翻 busy 不会再发一次
    }

    @Test func aPromptThatNeverBecomesBusyExpiresAfter3Seconds() {
        // 比如本地处理的斜杠命令：有 UserPromptSubmit，但登记表一直是 idle
        let (h, f) = idleSession()
        h.advance(1)
        h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
        expectActivity(h.snap(key), .thinking)
        h.run(for: 3.2)
        #expect(h.snap(key)?.phase == .idle)
    }

    @Test func aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(4)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()    // busy → idle，没有 Stop
        #expect(h.kinds(key).filter { if case .turnFinished = $0 { return true } else { return false } }.isEmpty)   // 还在等 Stop
        h.advance(0.5); h.poll()
        expectActivity(h.snap(key), .interrupted)
        let ev = h.kinds(key).compactMap { k -> Bool? in if case .turnFinished(_, let i, _) = k { return i } else { return nil } }
        #expect(ev == [true])
        #expect(h.snap(key)?.unread == false)                                    // 自己打断的不算未读
        h.advance(3); h.poll()
        expectActivity(h.snap(key), .idle)
    }

    @Test func interruptDetectedFromTheTranscriptWithoutAnyHook() {
        let (h, f) = idleSession(registerHook: false)
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.poll()
        #expect(h.snap(key)?.hookActive == false)
        expectActivity(h.snap(key), .thinking)
        h.advance(3)
        h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: h.now)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(0.01)); h.poll()
        expectActivity(h.snap(key), .interrupted)
    }

    @Test func abortedMidStreamAlsoCountsAsAnInterrupt() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(2)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "half", block: TL.text("被打断的半句话"), stopReason: nil, aborted: true)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(0.02)); h.poll()
        expectActivity(h.snap(key), .interrupted)
    }

    @Test func aNormalStopAfterAnEarlierInterruptIsNotInterrupted() {
        // 上一轮被打断；这一轮正常做完：打断标记比这一轮的 Stop 旧，不能算数
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(2)
        h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: h.now)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(20); h.poll()
        startTurn(h, f)
        h.advance(5)
        h.tree.hook(f.sid, "Stop"); h.tree.appendTranscript(f.sid, [TL.stopHookSummary(sessionId: f.sid, at: h.now)])
        h.poll()
        expectActivity(h.snap(key), .finished)
    }

    @Test func erroredTurnStaysErroredUntilItStartsDozing() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(3)
        h.tree.appendTranscript(f.sid, [
            TL.apiError(sessionId: f.sid, at: h.now, attempt: 10, max: 10),
            TL.assistant(sessionId: f.sid, at: h.now.addingTimeInterval(0.01), messageId: "syn", block: TL.text("API Error: Connection error."),
                         stopReason: "stop_sequence", model: "<synthetic>", apiErrorMessage: true)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(0.02)); h.poll()
        expectActivity(h.snap(key), .errored)
        let ev = h.kinds(key).compactMap { k -> Bool? in if case .turnFinished(_, _, let e) = k { return e } else { return nil } }
        #expect(ev == [true])
        #expect(h.snap(key)?.unread == true)
        h.advance(9 * 60); h.poll()
        expectActivity(h.snap(key), .errored)
        h.advance(61); h.poll()
        expectActivity(h.snap(key), .dozing)
    }

    @Test func retryingThenBackToThinkingWhenTheRetryWindowPasses() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(1)
        h.tree.appendTranscript(f.sid, [TL.apiError(sessionId: f.sid, at: h.now, attempt: 2, max: 10, retryInMs: 1200)]); h.poll()
        expectActivity(h.snap(key), .retrying(attempt: 2, max: 10))
        h.advance(16); h.poll()
        expectActivity(h.snap(key), .retrying(attempt: 2, max: 10))              // 1.2 + 15 = 16.2 秒内
        h.advance(0.5); h.poll()
        expectActivity(h.snap(key), .thinking)
        // 重试成功：之后有新的 assistant 行
        h.advance(1)
        h.tree.appendTranscript(f.sid, [TL.apiError(sessionId: f.sid, at: h.now, attempt: 3, max: 10, retryInMs: 1200)]); h.poll()
        expectActivity(h.snap(key), .retrying(attempt: 3, max: 10))
        h.advance(2)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "ok", block: TL.text("恢复了"), stopReason: "tool_use")]); h.poll()
        expectActivity(h.snap(key), .thinking)
    }

    // MARK: 不因时间判死

    @Test func aSessionBusyForAnHourNeverDies() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(1); h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 4000"); h.poll()
        var sawQuiet = false
        for minute in 1...62 {
            h.advance(60); h.poll()
            let s = h.snap(key)
            #expect(s?.presence == .present, "第 \(minute) 分钟")
            #expect(s?.phase == .busy, "第 \(minute) 分钟")
            guard case .tool(let c, 1)? = s?.activity, c.name == "Bash" else { Issue.record("第 \(minute) 分钟动作变了：\(String(describing: s?.activity))"); return }
            if minute < 9 { #expect(s?.quiet == false, "第 \(minute) 分钟不该是 quiet") }
            if minute >= 11 { #expect(s?.quiet == true, "第 \(minute) 分钟应该是 quiet"); sawQuiet = true }
        }
        #expect(sawQuiet)
        #expect(h.kinds(key).contains(.departed(dormant: true)) == false)
        // 有新的 hook 事件：quiet 立刻清掉
        h.tree.hook(f.sid, "PostToolUse", tool: "Bash", detail: "sleep 4000"); h.poll()
        #expect(h.snap(key)?.quiet == false)
        expectActivity(h.snap(key), .thinking)
    }

    @Test func aWaitingSessionStaysWaitingNoMatterHowLong() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(1); h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "rm -rf build")
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: h.now); h.poll()
        for _ in 0..<12 {
            h.advance(600); h.poll()                                            // 两个小时
            guard case .waitingApproval(let t?)? = h.snap(key)?.activity else { Issue.record("不再等批准了"); return }
            #expect(t.detail == "rm -rf build")
        }
        #expect(h.snap(key)?.quiet == false)                                    // 等你的会话不是"安静"
    }

    // MARK: 没有 hook 的退路

    @Test func withoutHooksToolsComeFromDanglingToolUsesInTheTranscript() {
        let (h, f) = idleSession(registerHook: false)
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now),
                                        TL.assistant(sessionId: f.sid, at: h.now.addingTimeInterval(1), messageId: "m", block: TL.toolUse(id: "tu1", name: "Bash", input: ["command": "make"]))])
        h.advance(1.1); h.poll()
        guard case .tool(let c, 1)? = h.snap(key)?.activity else { Issue.record("应该是 Bash：\(String(describing: h.snap(key)?.activity))"); return }
        #expect(c.name == "Bash" && c.detail == "make")
        h.tree.appendTranscript(f.sid, [TL.userToolResult(sessionId: f.sid, at: h.now, toolUseId: "tu1")]); h.advance(0.1); h.poll()
        expectActivity(h.snap(key), .thinking)
        let d = h.engine.diagnostics()
        #expect(d.hookDetectedInSettings == false)
        #expect(d.sourceStatus.contains { $0.contains("hook: 没检测到") })
    }

    @Test func aDanglingToolFromAnInterruptedTurnDoesNotLeakIntoTheNextOne() {
        let (h, f) = idleSession(registerHook: false)
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now),
                                        TL.assistant(sessionId: f.sid, at: h.now.addingTimeInterval(0.5), messageId: "m", block: TL.toolUse(id: "tu9", name: "Bash", input: ["command": "hang"]))])
        h.advance(1); h.poll()
        h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: h.now)])
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll()
        h.advance(30); h.poll()
        // 下一轮：新的输入 → 旧的悬空 tool_use（比这次输入旧）不能显示
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.advance(0.2); h.poll()
        expectActivity(h.snap(key), .thinking)
    }

    // MARK: 等待

    @Test func waitingVariantsThroughTheEngine() {
        let cases: [(String, (Activity) -> Bool, AttentionKind)] = [
            ("permission prompt", { if case .waitingApproval = $0 { return true } else { return false } }, .approval(nil)),
            ("sandbox request", { if case .waitingApproval = $0 { return true } else { return false } }, .approval(nil)),
            ("input needed", { $0 == .asking }, .question),
            ("dialog open", { $0 == .asking }, .question),
            ("goal proposal", { $0 == .waitingOther("goal proposal") }, .other("goal proposal")),
            ("worker request", { $0 == .waitingOther("worker request") }, .other("worker request")),
        ]
        for (raw, pred, kind) in cases {
            let (h, f) = idleSession()
            startTurn(h, f)
            h.advance(1)
            h.tree.writeRegistry(f.session, status: "waiting", waitingFor: raw, statusUpdatedAt: h.now); h.poll()
            #expect(pred(h.snap(key)?.activity ?? .idle), "\(raw) → \(String(describing: h.snap(key)?.activity))")
            let needs = h.kinds(key).compactMap { k -> AttentionKind? in if case .needsUser(let a) = k { return a } else { return nil } }
            #expect(needs.count == 1 && needs[0].sameCase(as: kind), "\(raw) 的 needsUser 事件：\(needs)")
            #expect(h.snap(key)?.phase == .waiting)
            h.advance(2)
            h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now); h.poll()
            #expect(h.kinds(key).contains(.needsUserCleared), "\(raw)")
        }
    }

    @Test func attentionKindChangesWhileStillWaitingEmitAFreshEvent() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: h.now); h.poll()
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "input needed", statusUpdatedAt: h.now); h.poll()
        let needs = h.kinds(key).compactMap { k -> AttentionKind? in if case .needsUser(let a) = k { return a } else { return nil } }
        #expect(needs.count == 2)
        #expect(!h.kinds(key).contains(.needsUserCleared))
    }

    @Test func waitingAtStartupIsReportedImmediately() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(-300))
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "git push", at: h.now.addingTimeInterval(-40))
        h.tree.writeRegistry(f.session, status: "waiting", waitingFor: "permission prompt", statusUpdatedAt: h.now.addingTimeInterval(-30))
        h.poll()
        guard case .waitingApproval(let t?)? = h.snap(key)?.activity else { Issue.record("应该在等批准"); return }
        #expect(t.detail == "git push")
        #expect(near(h.snap(key)?.activitySince, h.now.addingTimeInterval(-30)))       // 精确的开始时间，不是"启动那一刻"
        #expect(h.kinds(key).contains { if case .needsUser(.approval) = $0 { return true } else { return false } })
        // 本轮开始时间取 hook 里的 UserPromptSubmit（比登记表的 waiting 时间早）
        #expect(near(h.snap(key)?.turnStartedAt, h.now.addingTimeInterval(-300)))
        #expect(!h.kinds(key).contains(.turnStarted))                              // 启动时的初始状态不发 turnStarted
    }

    // MARK: 压缩

    @Test func compactionThroughHooks() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(1); h.tree.hook(f.sid, "PreCompact", extra: "auto"); h.poll()
        expectActivity(h.snap(key), .compacting)
        h.advance(8); h.tree.hook(f.sid, "PostCompact"); h.poll()
        expectActivity(h.snap(key), .thinking)
        // 压缩完成后 SessionStart(source=compact) 也相当于 PostCompact
        h.advance(1); h.tree.hook(f.sid, "PreCompact", extra: "manual"); h.poll()
        expectActivity(h.snap(key), .compacting)
        h.advance(5); h.tree.hook(f.sid, "SessionStart", extra: "compact"); h.poll()
        expectActivity(h.snap(key), .thinking)
    }

    // MARK: 启动时中途接手

    @Test func attachingMidTurnEstimatesTheTurnStartFromHooks() {
        let h = Harness()
        let f = DesktopFixture(h: h, startedAgo: 1000)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(-300))
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/a", at: h.now.addingTimeInterval(-290))
        h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/a", at: h.now.addingTimeInterval(-289))
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "npm test", at: h.now.addingTimeInterval(-100))
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now.addingTimeInterval(-300.1))
        h.poll()
        guard case .tool(let c, 1)? = h.snap(key)?.activity else { Issue.record("应该是 Bash"); return }
        #expect(c.name == "Bash")
        #expect(near(h.snap(key)?.turnStartedAt, h.now.addingTimeInterval(-300.1)))
        #expect(near(h.snap(key)?.activitySince, h.now.addingTimeInterval(-100)))
    }

    @Test func attachingToAnIdleSessionThatJustFinishedShowsFinishedForTheRemainingTime() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(-30))
        h.tree.hook(f.sid, "Stop", at: h.now.addingTimeInterval(-2.056))
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-2))
        h.poll()
        expectActivity(h.snap(key), .finished)                                      // 2 秒前刚做完：还有 3 秒的"做完了"
        h.advance(3.1); h.poll()
        expectActivity(h.snap(key), .idle)
        #expect(h.snap(key)?.unread == false)                                       // 启动时不知道有没有看过：不亮未读
    }

    @Test func attachingToALongIdleSessionShowsTheRightSleepState() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-50 * 60))
        h.poll()
        expectActivity(h.snap(key), .sleeping)
        h.tree.writeRegistry(FakeClaudeTree.Session(pid: 1002, sessionId: "eeeeeeee-0000-4000-8000-000000000002", host: "local_2", name: "b", startedAt: h.now.addingTimeInterval(-9000)),
                             status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-15 * 60))
        h.poll()
        expectActivity(h.snap("d:local_2"), .dozing)
    }

    // MARK: 时间驱动的唤醒

    @Test func nextWakeIsScheduledForTimeDrivenChanges() {
        let (h, f) = idleSession()
        startTurn(h, f)
        h.advance(3)
        h.tree.hook(f.sid, "Stop"); h.poll()
        let idleSince = h.snap(key)!.idleSince!
        // 做完了 5 秒 → 之后要在 idleSince+5 醒来
        let wake = h.lastOutput?.nextWake
        #expect(wake != nil)
        #expect(wake! <= idleSince.addingTimeInterval(5.001))
        h.advance(5.2); h.poll()
        #expect(h.lastOutput?.nextWake != nil)                                      // 下一个是打盹（10 分钟）
    }

    @Test func dozeAndSleepThresholdsAreConfigurable() {
        let h = Harness(configure: { $0.dozeAfter = 30; $0.sleepAfter = 90 })
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now)
        h.poll()
        expectActivity(h.snap(key), .idle)
        h.advance(31); h.poll()
        expectActivity(h.snap(key), .dozing)
        h.advance(60); h.poll()
        expectActivity(h.snap(key), .sleeping)
    }
}

@Suite struct HookDropoutTests {
    let key = DesktopFixture.key

    @Test func ifCcmonIsUninstalledMidSessionToolsFallBackToTheTranscript() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now.addingTimeInterval(-40))])
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(-40))
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/a", at: h.now.addingTimeInterval(-39))
        h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/a", at: h.now.addingTimeInterval(-38.9))
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now.addingTimeInterval(-40))
        h.poll()
        #expect(h.snap(key)?.hookActive == true)
        // 之后 hook 不再有事件，但会话记录里继续出现工具调用
        h.advance(20)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m1", block: TL.toolUse(id: "tu1", name: "Bash", input: ["command": "make"]))])
        h.advance(0.5); h.poll()
        #expect(h.snap(key)?.hookActive == false)                                   // hook 掉线
        guard case .tool(let c, 1)? = h.snap(key)?.activity else { Issue.record("应该退回用会话记录判断：\(String(describing: h.snap(key)?.activity))"); return }
        #expect(c.name == "Bash" && c.detail == "make")
    }

    @Test func aBusyHookSessionWithAQuietTranscriptStaysOnHooks() {
        // 长时间的工具调用：会话记录里没有新行，hook 也没有新事件——不能误判成 hook 掉线
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.hook(f.sid, "UserPromptSubmit", at: h.now.addingTimeInterval(-40))
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 3000", at: h.now.addingTimeInterval(-39))
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now.addingTimeInterval(-39.5), messageId: "m", block: TL.toolUse(id: "tu", name: "Bash", input: ["command": "sleep 3000"]))])
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now.addingTimeInterval(-40))
        h.poll()
        h.advance(1800); h.poll()
        #expect(h.snap(key)?.hookActive == true)
        guard case .tool(let c, 1)? = h.snap(key)?.activity else { Issue.record("x"); return }
        #expect(c.name == "Bash")
    }
}
