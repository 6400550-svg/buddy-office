import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// 「跟着 Claude 一起收」：Claude 退出且没有活会话 60 秒后退出（任务书 7.4）。
@Suite struct AutoQuitTests {
    /// A-010：用户「隐藏」的 buddy 也是活会话（只是不在办公室里显示）——终端里的 claude 还在跑，不能因此自动退出。
    @Test func hiddenBuddiesStillCountAsLiveSessions() {
        let snaps = [Fx.snap("t:hidden", seat: 0, activity: .thinking)]
        // 所有在场的 buddy 都被用户隐藏了：办公室里是空的（derive 后 present 为空），但会话还活着
        #expect(AppModel.derive(snapshots: snaps, hidden: ["t:hidden"], dormantMax: 4).present.isEmpty)
        #expect(AppModel.hasLiveSessions(snapshots: snaps))
    }

    @Test func noPresentSessionsMeansNothingIsLive() {
        #expect(!AppModel.hasLiveSessions(snapshots: []))
        // 只有下班工位（away）不算活会话
        #expect(!AppModel.hasLiveSessions(snapshots: [Fx.dormant("d:a", seat: 0), Fx.dormant("d:b", seat: 1)]))
        #expect(AppModel.hasLiveSessions(snapshots: [Fx.dormant("d:a", seat: 0), Fx.snap("t:x", seat: 1)]))
    }

    // MARK: 60 秒的逻辑（假定时器 + 假的「退出自己」）
    static let claude = JumpService.claudeBundleID

    static func make(enabled: Bool = true, live: @escaping () -> Bool = { false }) -> (AutoQuit, FakeScheduler, Box) {
        let fs = FakeScheduler(), box = Box()
        let q = AutoQuit(center: NotificationCenter(), scheduler: fs.scheduler, terminate: { box.terminated += 1 }, log: { box.logs.append($0) })
        q.isEnabled = { enabled }; q.hasLiveSessions = live
        return (q, fs, box)
    }
    final class Box { var terminated = 0; var logs: [String] = [] }

    @Test func claudeQuitsAndNobodyIsLeftSoWeQuitAfterSixtySeconds() {
        let (q, fs, box) = Self.make()
        q.appTerminated(bundleID: Self.claude)
        #expect(fs.jobs.count == 1 && fs.jobs[0].delay == 60)
        #expect(box.terminated == 0, "60 秒到之前不退")
        fs.fire(0)
        #expect(box.terminated == 1)
        #expect(!q.isScheduled)
    }

    /// 有活会话（含被隐藏的）：到点不退。
    @Test func liveSessionsIncludingHiddenOnesKeepUsAlive() {
        let hiddenButAlive = [Fx.snap("t:h", activity: .thinking)]
        let (q, fs, box) = Self.make(live: { AppModel.hasLiveSessions(snapshots: hiddenButAlive) })
        q.appTerminated(bundleID: Self.claude)
        fs.fire(0)
        #expect(box.terminated == 0)
        #expect(box.logs.last?.contains("不退出") == true)
        // 会话都结束了之后再有 Claude 退出：这次会退
        var alive = true
        let (q2, fs2, box2) = Self.make(live: { alive })
        q2.appTerminated(bundleID: Self.claude); fs2.fire(0)
        #expect(box2.terminated == 0)
        alive = false
        q2.appTerminated(bundleID: Self.claude); fs2.fire(1)
        #expect(box2.terminated == 1)
    }

    @Test func onlyClaudeQuittingStartsTheCountdown() {
        let (q, fs, _) = Self.make()
        for id in ["com.apple.Safari", "com.anthropic.claude-code", "local.buddy-office", nil] as [String?] { q.appTerminated(bundleID: id) }
        #expect(fs.jobs.isEmpty)
    }

    @Test func theSwitchIsHonouredBothWhenClaudeQuitsAndWhenTheTimerFires() {
        let (off, fsOff, _) = Self.make(enabled: false)
        off.appTerminated(bundleID: Self.claude)
        #expect(fsOff.jobs.isEmpty, "开关关着：根本不倒计时")
        var enabled = true
        let fs = FakeScheduler(), box = Box()
        let q = AutoQuit(center: NotificationCenter(), scheduler: fs.scheduler, terminate: { box.terminated += 1 }, log: { _ in })
        q.isEnabled = { enabled }
        q.appTerminated(bundleID: Self.claude)
        enabled = false                                             // 倒计时期间用户把开关关了
        fs.fire(0)
        #expect(box.terminated == 0)
    }

    @Test func claudeComingBackCancelsTheCountdownAndANewQuitReplacesTheOld() {
        let (q, fs, box) = Self.make()
        q.appTerminated(bundleID: Self.claude)
        q.appLaunched(bundleID: "com.apple.Safari")
        #expect(!fs.jobs[0].cancelled, "别的 App 启动不影响")
        q.appLaunched(bundleID: Self.claude)
        #expect(fs.jobs[0].cancelled && !q.isScheduled)
        fs.fire(0)
        #expect(box.terminated == 0)
        q.appTerminated(bundleID: Self.claude); q.appTerminated(bundleID: Self.claude)
        #expect(fs.jobs.count == 3 && fs.jobs[1].cancelled && !fs.jobs[2].cancelled, "再退出一次：老的倒计时被替换")
    }

    /// --test-autoquit N 用的入口：直接倒计时 N 秒（不需要 Claude 真的退出）。
    @Test func theTestEntryPointCountsDownTheGivenSeconds() {
        let (q, fs, box) = Self.make()
        q.scheduleQuit(after: 5)
        #expect(fs.jobs.first?.delay == 5)
        fs.fire(0)
        #expect(box.terminated == 1)
    }

    /// 只会退出我们自己：AutoQuit 里没有任何去退出别的 App 的调用（terminate 闭包默认是 NSApp.terminate）。
    @Test func autoQuitNeverQuitsAnotherApp() throws {
        let src = try SourceAudit.read("SystemHelpers.swift")
        #expect(!src.contains("forceTerminate"))
        #expect(src.range(of: #"(?<!self)\.terminate\(\)"#, options: .regularExpression) == nil, "只有 self.terminate()（我们自己的退出闭包）；NSRunningApplication.terminate() 会去退出别的 App")
        #expect(src.contains("NSApp.terminate(nil)"), "默认的退出动作是退出我们自己")
    }
}
