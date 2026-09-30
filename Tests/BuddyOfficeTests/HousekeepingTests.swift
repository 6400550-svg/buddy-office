import Testing
import Foundation
import ServiceManagement
@testable import BuddyCore
@testable import BuddyOffice

/// 退出不无限等（A-012）、诊断文字、只增不减的偏好键（A-018）、开机启动开关和实际状态一致（A-023）。
@Suite struct HousekeepingTests {
    // MARK: A-012
    @Test func aStuckStopCannotHoldTheMainThreadForLongerThanTheTimeout() {
        let t0 = Date()
        var finished = false
        let lock = NSLock()
        let ok = BoundedWait.run(timeout: 0.2) { Thread.sleep(forTimeInterval: 1.0); lock.lock(); finished = true; lock.unlock() }
        let waited = Date().timeIntervalSince(t0)
        #expect(!ok, "超时要返回 false")
        #expect(waited < 0.6, "只等了 \(waited) 秒（不是 1 秒）")
        lock.lock(); #expect(!finished); lock.unlock()
    }

    @Test func fastWorkFinishesBeforeWeReturn() {
        var n = 0
        let ok = BoundedWait.run(timeout: 2) { n += 1 }
        #expect(ok && n == 1)
    }

    // MARK: 诊断文字
    @Test func diagnosticsTextListsEverythingTheSettingsPageShows() {
        var d = DiagnosticsInfo()
        d.liveSessionCount = 2; d.hookDetectedInSettings = true
        d.sessions = [DiagnosticsInfo.SessionDiag(key: "t:a", title: "重构登录", pid: 123, cliVersion: "2.1.0", hookActive: true, lastHookEventAt: nil, origin: .terminal),
                      DiagnosticsInfo.SessionDiag(key: "d:b", title: "论文", pid: nil, cliVersion: nil, hookActive: false, lastHookEventAt: nil, origin: .desktop)]
        d.sourceStatus = ["登记表: 正常", "hook: 正常"]
        let t = DiagnosticsFormatter.text(d, notifierStatus: "已拒绝（系统设置 → 通知 里可以打开）", deepLinkDisabled: true, deepLinkFailures: 2)
        #expect(t.contains("活会话数：2") && t.contains("ccmon hook：已在 settings.json 里注册"))
        #expect(t.contains("· 重构登录　pid 123　v2.1.0　hook 有") && t.contains("· 论文　pid -　v?　hook 无"))
        #expect(t.contains("系统通知：已拒绝") && t.contains("深链：已停用（连续 2 次没生效）"))
        #expect(t.contains("　登记表: 正常") && t.contains("　hook: 正常"))
        let ok = DiagnosticsFormatter.text(DiagnosticsInfo(), notifierStatus: "已授权", deepLinkDisabled: false, deepLinkFailures: 0)
        #expect(ok.contains("深链：可用") && ok.contains("没有检测到"))
    }

    // MARK: A-018 白板计数键
    @Test func tallyKeysOlderThanThirtyDaysAreStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)                   // 2027-01-15
        let day: (Int) -> String = { "tally." + Settings.dayString(now.addingTimeInterval(-Double($0) * 86_400), locale: Locale(identifier: "en_US_POSIX"), timeZone: .autoupdatingCurrent) }
        let keys = [day(0), day(1), day(29), day(31), day(400), "tally.not-a-date", "tally.2027-13-40", "hidden.keys", "office.zoom", "tallyx.2000-01-01"]
        #expect(Settings.staleTallyKeys(keys, now: now) == [day(400), day(31), "tally.2027-13-40", "tally.not-a-date"].sorted())
        #expect(Settings.staleTallyKeys([day(0), day(2)], now: now).isEmpty)
        #expect(Settings.staleTallyKeys([], now: now).isEmpty)
        let future = "tally." + Settings.dayString(now.addingTimeInterval(5 * 86_400), locale: Locale(identifier: "en_US_POSIX"), timeZone: .autoupdatingCurrent)
        #expect(Settings.staleTallyKeys([future], now: now).isEmpty, "时钟往前跳过的（未来的日期）不删")
    }

    @Test func pruningRemovesOnlyOurStaleTallyKeys() {
        Fx.withSettings { s, d in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            d.set(5, forKey: "tally.2026-01-01"); d.set(6, forKey: "tally." + Settings.dayString(now)); d.set(3, forKey: "office.zoom")
            s.pruneOldTallies(now: now)
            #expect(d.object(forKey: "tally.2026-01-01") == nil)
            #expect(d.object(forKey: "tally." + Settings.dayString(now)) != nil)
            #expect(d.object(forKey: "office.zoom") != nil)
        }
    }

    // MARK: A-023 开机启动
    @Test func theLoginSwitchFallsBackToOffWhenEnablingFailed() {
        #expect(LoginItem.switchState(requested: true, note: "已用登录项开启"))
        #expect(LoginItem.switchState(requested: true, note: "已用 LaunchAgent 开启"))
        #expect(!LoginItem.switchState(requested: true, note: "开启失败：The file couldn’t be saved."), "失败了：开关不能还显示开")
        #expect(!LoginItem.switchState(requested: false, note: "已关闭"))
        #expect(!LoginItem.switchState(requested: false, note: "开启失败：x"))
    }

    @Test func aPendingApprovalIsNotReportedAsEnabled() {
        #expect(LoginItem.note(afterRegister: .enabled) == "已用登录项开启")
        #expect(LoginItem.note(afterRegister: .requiresApproval)?.contains("还需要") == true, "要用户去系统设置批准，不能说已开启")
        #expect(LoginItem.note(afterRegister: .notFound) == nil, "ad-hoc 签名下是 notFound：改用 LaunchAgent")
        #expect(LoginItem.note(afterRegister: .notRegistered) == nil)
    }
}
