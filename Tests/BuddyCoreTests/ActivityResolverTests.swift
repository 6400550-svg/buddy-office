import Foundation
import Testing
@testable import BuddyCore

/// ActivityResolver 是纯函数：输出只由（信号, 当前时间）决定。
@Suite struct ActivityResolverTests {
    let t0 = Harness.epoch
    func at(_ s: Double) -> Date { Harness.at(s) }
    func call(_ name: String, _ detail: String = "", at s: Double = 0) -> ToolCall {
        ToolCatalog.makeCall(name: name, detail: detail, at: at(s))
    }
    func sig(_ status: Phase?, since: Double = 0, waitingFor: String? = nil) -> SessionSignals {
        var s = SessionSignals()
        s.registryStatus = status
        s.statusUpdatedAt = at(since)
        s.waitingFor = waitingFor
        s.hookActive = true
        return s
    }

    // MARK: busy

    @Test func busyWithoutToolsIsThinking() {
        #expect(ActivityResolver.resolve(sig(.busy), now: at(5)) == .thinking)
    }

    @Test func busyShowsTheNewestOpenToolWithParallelCount() {
        var s = sig(.busy)
        s.openTools = [call("Grep", "a", at: 1), call("Glob", "b", at: 1.1), call("Read", "c", at: 1.2)]
        guard case .tool(let c, let n) = ActivityResolver.resolve(s, now: at(2)) else { Issue.record("应该是 .tool"); return }
        #expect(c.name == "Read")
        #expect(n == 3)
    }

    @Test func compactingWhenPreCompactHasNoPostCompact() {
        var s = sig(.busy)
        s.preCompactAt = at(10)
        #expect(ActivityResolver.resolve(s, now: at(11)) == .compacting)
        s.postCompactAt = at(20)
        #expect(ActivityResolver.resolve(s, now: at(21)) == .thinking)
        // 又一次压缩：PreCompact 比上一个 PostCompact 新
        s.preCompactAt = at(100)
        #expect(ActivityResolver.resolve(s, now: at(101)) == .compacting)
        // 压缩优先于工具
        s.openTools = [call("Bash", "x")]
        #expect(ActivityResolver.resolve(s, now: at(101)) == .compacting)
    }

    @Test func compactingExpiresIfPostCompactNeverArrives() {
        var s = sig(.busy)
        s.preCompactAt = at(0)
        #expect(ActivityResolver.resolve(s, now: at(14 * 60)) == .compacting)
        #expect(ActivityResolver.resolve(s, now: at(16 * 60)) == .thinking)
    }

    @Test func compactingFromTranscriptBoundary() {
        var s = sig(.busy)
        s.compactBoundaryAt = at(50)
        s.lastAssistantOrUserAt = at(40)
        #expect(ActivityResolver.resolve(s, now: at(55)) == .compacting)
        s.lastAssistantOrUserAt = at(56)                         // 边界之后有新行了
        #expect(ActivityResolver.resolve(s, now: at(57)) == .thinking)
    }

    @Test func retryingWithinRetryInMsPlus15Seconds() {
        var s = sig(.busy)
        s.apiError = .init(at: at(100), attempt: 2, max: 10, retryInMs: 4000)
        s.lastAssistantOrUserAt = at(90)
        #expect(ActivityResolver.resolve(s, now: at(101)) == .retrying(attempt: 2, max: 10))
        #expect(ActivityResolver.resolve(s, now: at(118.9)) == .retrying(attempt: 2, max: 10))   // 4 + 15 = 19 秒内
        #expect(ActivityResolver.resolve(s, now: at(119.1)) == .thinking)
        // 之后有新的 assistant / user 行：不再是重试
        s.lastAssistantOrUserAt = at(103)
        #expect(ActivityResolver.resolve(s, now: at(105)) == .thinking)
    }

    @Test func retryingBeatsOpenTools() {
        var s = sig(.busy)
        s.apiError = .init(at: at(10), attempt: 1, max: 5, retryInMs: 1000)
        s.openTools = [call("Bash", "x")]
        #expect(ActivityResolver.resolve(s, now: at(11)) == .retrying(attempt: 1, max: 5))
    }

    @Test func aSessionBusyForAnHourIsStillBusy() {
        // 没有心跳：一个会话可能连续 busy 67 分钟以上，statusUpdatedAt 一直不变。绝不能因为时间戳旧就判死。
        var s = sig(.busy, since: 0)
        s.openTools = [call("Bash", "sleep 4000", at: 5)]
        for minutes in [1.0, 10, 30, 60, 67, 120, 600] {
            let r = ActivityResolver.evaluate(s, now: at(minutes * 60))
            #expect(r.phase == .busy)
            guard case .tool(let c, 1) = r.activity, c.name == "Bash" else { Issue.record("\(minutes) 分钟后动作变了：\(r.activity)"); continue }
        }
        s.openTools = []
        #expect(ActivityResolver.resolve(s, now: at(67 * 60)) == .thinking)
    }

    // MARK: waiting

    @Test func permissionPromptIsApprovalWithTheNewestOpenTool() {
        var s = sig(.waiting, waitingFor: "permission prompt")
        s.openTools = [call("Read", "a", at: 1), call("Bash", "git push", at: 2)]
        guard case .waitingApproval(let t?) = ActivityResolver.resolve(s, now: at(5)) else { Issue.record("应该是等批准"); return }
        #expect(t.name == "Bash")
        #expect(t.detail == "git push")
    }

    @Test func sandboxRequestIsApproval() {
        var s = sig(.waiting, waitingFor: "sandbox request")
        s.openTools = [call("Bash", "curl x")]
        guard case .waitingApproval = ActivityResolver.resolve(s, now: at(1)) else { Issue.record("sandbox request 应该算等批准"); return }
    }

    @Test func inputNeededAndDialogOpenAreQuestions() {
        var s = sig(.waiting, waitingFor: "input needed")
        s.openTools = [call("AskUserQuestion", "")]
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
        s.waitingFor = "dialog open"                                   // 终端会话才有
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
        s.openTools = []
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
    }

    @Test func exitPlanModeWhileWaitingIsPlanReview() {
        for wf in ["input needed", "dialog open", "permission prompt"] {
            var s = sig(.waiting, waitingFor: wf)
            s.openTools = [call("Read", "x", at: 1), call("ExitPlanMode", "", at: 2)]
            #expect(ActivityResolver.resolve(s, now: at(5)) == .planReview, "waitingFor=\(wf)")
        }
    }

    @Test func askUserQuestionNotificationSaysPermissionButItIsAQuestion() {
        // 真实日志里 AskUserQuestion 的 Notification 文本也是 "needs your permission to use AskUserQuestion"
        var s = sig(.waiting, waitingFor: "permission prompt")
        s.openTools = [call("AskUserQuestion", "")]
        s.notificationText = "Claude needs your permission to use AskUserQuestion"
        s.notificationAt = at(3)
        #expect(ActivityResolver.resolve(s, now: at(5)) == .asking)
    }

    @Test func nonPermissionWaitsFromTerminalSessions() {
        // 非权限类等待只有终端会话才有：goal proposal / worker request → 其他等待，附原始文本
        for raw in ["goal proposal", "worker request"] {
            let s = sig(.waiting, waitingFor: raw)
            #expect(ActivityResolver.resolve(s, now: at(1)) == .waitingOther(raw))
        }
    }

    @Test func unknownWaitingTextIsClassifiedByKeywords() {
        var s = sig(.waiting, waitingFor: "Waiting for permission to run tool")
        #expect({ if case .waitingApproval = ActivityResolver.resolve(s, now: at(1)) { return true } else { return false } }())
        s.waitingFor = "Allow this action?"
        #expect({ if case .waitingApproval = ActivityResolver.resolve(s, now: at(1)) { return true } else { return false } }())
        s.waitingFor = "awaiting user input"
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
        s.waitingFor = "an elicitation is open"
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
        s.waitingFor = "a question for you"
        #expect(ActivityResolver.resolve(s, now: at(1)) == .asking)
        s.waitingFor = "something else entirely"
        #expect(ActivityResolver.resolve(s, now: at(1)) == .waitingOther("something else entirely"))
    }

    @Test func approvalToolComesFromTheNotificationWhenNothingIsOpen() {
        var s = sig(.waiting, since: 10, waitingFor: "permission prompt")
        s.notificationText = "Claude needs your permission to use Bash"
        s.notificationAt = at(10.2)
        guard case .waitingApproval(let t?) = ActivityResolver.resolve(s, now: at(12)) else { Issue.record("应该带工具"); return }
        #expect(t.name == "Bash")
        #expect(t.category == .bash)
        // 通知比这次等待旧：不能用
        s.notificationAt = at(5)
        #expect(ActivityResolver.resolve(s, now: at(12)) == .waitingApproval(tool: nil))
    }

    @Test func notificationNamesTheToolAmongParallelOnes() {
        var s = sig(.waiting, since: 10, waitingFor: "permission prompt")
        s.openTools = [call("Bash", "rm -rf x", at: 9), call("Read", "y", at: 9.1)]
        s.notificationText = "Claude needs your permission to use Bash"
        s.notificationAt = at(16)
        guard case .waitingApproval(let t?) = ActivityResolver.resolve(s, now: at(17)) else { Issue.record("x"); return }
        #expect(t.name == "Bash")                                       // 不是最新的 Read，而是通知点名的 Bash
    }

    @Test func missingWaitingForFallsBackToNotificationText() {
        var s = sig(.waiting, since: 10, waitingFor: nil)
        s.notificationText = "Claude needs your permission to use Edit"
        s.notificationAt = at(10.5)
        guard case .waitingApproval(let t?) = ActivityResolver.resolve(s, now: at(11)) else { Issue.record("x"); return }
        #expect(t.name == "Edit")
        s.notificationText = nil
        #expect(ActivityResolver.resolve(s, now: at(11)) == .waitingOther(""))
    }

    // MARK: idle

    @Test func interruptedLasts3SecondsThenIdle() {
        var s = sig(.idle, since: 100)
        s.idleSince = at(100); s.turnEnd = .interrupted
        #expect(ActivityResolver.resolve(s, now: at(101)) == .interrupted)
        #expect(ActivityResolver.resolve(s, now: at(102.9)) == .interrupted)
        #expect(ActivityResolver.resolve(s, now: at(103.1)) == .idle)
    }

    @Test func finishedLasts5SecondsThenIdle() {
        var s = sig(.idle, since: 100)
        s.idleSince = at(100); s.turnEnd = .finished
        #expect(ActivityResolver.resolve(s, now: at(104.9)) == .finished)
        #expect(ActivityResolver.resolve(s, now: at(105.1)) == .idle)
    }

    @Test func erroredStaysUntilDozing() {
        var s = sig(.idle, since: 100)
        s.idleSince = at(100); s.turnEnd = .errored
        #expect(ActivityResolver.resolve(s, now: at(101)) == .errored)
        #expect(ActivityResolver.resolve(s, now: at(100 + 599)) == .errored)
        #expect(ActivityResolver.resolve(s, now: at(100 + 601)) == .dozing)
    }

    @Test func idleThenDozingThenSleepingAtTheThresholds() {
        var s = sig(.idle, since: 0)
        s.idleSince = at(0); s.turnEnd = .none
        #expect(ActivityResolver.resolve(s, now: at(1)) == .idle)
        #expect(ActivityResolver.resolve(s, now: at(9 * 60 + 59)) == .idle)
        #expect(ActivityResolver.resolve(s, now: at(10 * 60)) == .dozing)
        #expect(ActivityResolver.resolve(s, now: at(44 * 60 + 59)) == .dozing)
        #expect(ActivityResolver.resolve(s, now: at(45 * 60)) == .sleeping)
        #expect(ActivityResolver.resolve(s, now: at(24 * 3600)) == .sleeping)
        // 两个时间都可以在设置里改
        s.dozeAfter = 60; s.sleepAfter = 120
        #expect(ActivityResolver.resolve(s, now: at(61)) == .dozing)
        #expect(ActivityResolver.resolve(s, now: at(121)) == .sleeping)
    }

    @Test func unknownIdleSinceIsPlainIdle() {
        var s = sig(.idle)
        s.idleSince = nil; s.turnEnd = .finished
        #expect(ActivityResolver.resolve(s, now: at(1)) == .idle)
    }

    // MARK: 阶段的两个临时修正

    @Test func registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds() {
        var s = sig(.idle, since: 100)
        s.lastPromptAt = at(100.5)
        s.idleSince = at(100); s.turnEnd = .none
        #expect(ActivityResolver.effectivePhase(s, now: at(101)) == .busy)
        #expect(ActivityResolver.resolve(s, now: at(101)) == .thinking)
        #expect(ActivityResolver.effectivePhase(s, now: at(103.4)) == .busy)
        #expect(ActivityResolver.effectivePhase(s, now: at(103.6)) == .idle)          // 最多 3 秒
        // 提示比登记表的 statusUpdatedAt 还旧：不修正
        s.lastPromptAt = at(99)
        #expect(ActivityResolver.effectivePhase(s, now: at(100.5)) == .idle)
        // 提示之后又有 Stop：这一轮已经结束了
        s.lastPromptAt = at(100.5); s.lastStopAt = at(100.8)
        #expect(ActivityResolver.effectivePhase(s, now: at(101)) == .idle)
    }

    @Test func registryBusyButNewerStopIsTemporarilyIdle() {
        var s = sig(.busy, since: 100)
        s.lastPromptAt = at(100.1)
        s.lastStopAt = at(160)
        #expect(ActivityResolver.effectivePhase(s, now: at(160.03)) == .idle)
        // Stop 之后马上又来了一条提示（排队的下一轮）：还是 busy
        s.lastPromptAt = at(160.1)
        #expect(ActivityResolver.effectivePhase(s, now: at(160.2)) == .busy)
        // Stop 比登记表 busy 还旧：不修正
        var s2 = sig(.busy, since: 100)
        s2.lastStopAt = at(90)
        #expect(ActivityResolver.effectivePhase(s2, now: at(101)) == .busy)
    }

    @Test func waitingIsNeverOverriddenByHooks() {
        var s = sig(.waiting, since: 100, waitingFor: "permission prompt")
        s.lastStopAt = at(101)
        s.lastPromptAt = at(50)
        #expect(ActivityResolver.effectivePhase(s, now: at(102)) == .waiting)
    }

    @Test func missingRegistryStatusFallsBackToHooks() {
        var s = sig(nil)
        s.lastPromptAt = at(10)
        #expect(ActivityResolver.effectivePhase(s, now: at(500)) == .busy)             // 有提示没有 Stop
        s.lastStopAt = at(20)
        #expect(ActivityResolver.effectivePhase(s, now: at(500)) == .idle)
        s.hookActive = false; s.lastStopAt = nil
        #expect(ActivityResolver.effectivePhase(s, now: at(500)) == .idle)             // 没有 hook：没法知道
    }

    // MARK: nextChange

    @Test func nextChangeTellsWhenTimeWillChangeTheResult() {
        var s = sig(.idle, since: 100)
        s.idleSince = at(100); s.turnEnd = .finished
        #expect(ActivityResolver.evaluate(s, now: at(101)).nextChange == at(105))
        #expect(ActivityResolver.evaluate(s, now: at(106)).nextChange == at(100 + 600))
        s.turnEnd = .interrupted
        #expect(ActivityResolver.evaluate(s, now: at(101)).nextChange == at(103))
        var b = sig(.busy)
        #expect(ActivityResolver.evaluate(b, now: at(5)).nextChange == nil)             // busy 没有时间驱动的变化
        b.apiError = .init(at: at(10), attempt: 1, max: 3, retryInMs: 1000)
        #expect(ActivityResolver.evaluate(b, now: at(11)).nextChange == at(26))         // 10 + 1 + 15
    }

    @Test func toolNameParsingFromNotification() {
        #expect(ActivityResolver.toolName(fromNotification: "Claude needs your permission to use Bash") == "Bash")
        #expect(ActivityResolver.toolName(fromNotification: "Claude needs your permission to use mcp__x__y.") == "mcp__x__y")
        #expect(ActivityResolver.toolName(fromNotification: "something without the phrase") == nil)
    }
}
