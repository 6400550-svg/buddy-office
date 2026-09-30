import Testing
import Foundation
import UserNotifications
import BuddyCore
import BuddyArt
import BuddyStage
@testable import BuddyOffice

/// 系统通知被拒时的兜底提醒（任务书 7.2「兜底，任何时候都开着」）：自己的像素提示卡 + Dock 角标 / 弹跳 + 菜单栏图标变化。
/// 用户已经拒绝了通知权限（DESIGN §2 M0 第 2 项），所以这条链路是他实际用的那条。
@MainActor @Suite struct AlertFallbackTests {
    final class Rig {
        let store = Fx.Store()
        let center: FakeCenter, toast = FakeToast(), dock = FakeDock()
        var icons: [MenuBarIcon.Kind] = [], sounds: [(SoundSynth.Kind, String)] = []
        let notifier: NotificationService
        let pipeline: AlertPipeline
        init(status: UNAuthorizationStatus, available: Bool = true) {
            center = FakeCenter(status: status)
            let t = toast, s = store.settings
            var iconsRef: ((MenuBarIcon.Kind) -> Void)?
            var soundsRef: ((SoundSynth.Kind, String) -> Void)?
            notifier = NotificationService(client: center, toast: t, playSound: { soundsRef?($0, $1) }, available: available, defaults: store.defaults)
            let n = notifier, d = DockTileController(env: dock.env)
            pipeline = AlertPipeline(sink: LiveAlertSink(notifier: n, dock: d, updateStatus: { iconsRef?(StatusItemController.iconKind(waiting: $0, busy: $1)) }, settings: s))
            iconsRef = { [unowned self] in icons.append($0) }
            soundsRef = { [unowned self] in sounds.append(($0, $1)) }
        }
        deinit { store.cleanUp() }
        /// 跑一次提醒流水线：t 是假时钟（秒）；everything = 数据层给的全部快照；hidden = 用户隐藏的。
        func run(_ t: Double, _ everything: [BuddySnapshot], hidden: Set<String> = [], demo: Bool = false) {
            let present = AppModel.derive(snapshots: everything, hidden: hidden, dormantMax: 4).present
            pipeline.run(snapshots: everything, present: present, hidden: hidden, now: Fx.base.addingTimeInterval(t), config: AlertConfig(settings: store.settings),
                         isLooking: { _ in false }, privacy: false, demo: demo)
        }
    }

    static func waiting(_ key: String = "t:a") -> BuddySnapshot { AlertCoordinatorTests.waiting(key) }
    static func busy(_ key: String = "t:a") -> BuddySnapshot { AlertCoordinatorTests.busy(key) }

    @Test func testsRunOnTheMainThread() { #expect(Thread.isMainThread) }

    /// 授权被拒：1.5 秒后提示卡出现（不走系统通知），Dock 角标 / 菜单栏图标一开始等就变；等待结束后全部恢复。
    @Test func whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear() {
        let r = Rig(status: .denied)
        #expect(r.notifier.status == .denied)
        r.run(0, [Self.waiting()])
        #expect(r.icons.last == .waiting, "菜单栏图标：变成举手")
        #expect(r.dock.badge == "1", "Dock 角标：1 位在等你")
        #expect(r.toast.shown.isEmpty, "还没满 1.5 秒，不弹")
        r.run(1.49, [Self.waiting()])
        #expect(r.toast.shown.isEmpty)
        r.run(1.5, [Self.waiting()])
        #expect(r.toast.shown.count == 1, "满 1.5 秒：像素提示卡")
        #expect(r.toast.shown.first?.key == "t:a" && r.toast.shown.first?.kind == .approval)
        #expect(r.toast.shown.first?.body == "想用 Bash：git push（等你批准）")
        #expect(r.center.added.isEmpty, "被拒：一条系统通知都不能发")
        #expect(r.dock.attention == 1, "Dock 图标弹一下（App 不在前台）")
        #expect(r.sounds.count == 1 && r.sounds.first?.0 == .approval && r.sounds.first?.1 == "8bit", "提示音照响")
        r.run(2.0, [Self.waiting()]); r.run(5.0, [Self.waiting()])
        #expect(r.toast.shown.count == 1 && r.dock.attention == 1 && r.sounds.count == 1, "同一段等待只提醒一次")
        // 批准了：提示卡收回、系统通知（没有）也撤、角标和菜单栏图标恢复
        r.run(6.0, [Self.busy()])
        #expect(r.toast.dismissed == ["t:a"])
        #expect(r.center.removed == ["t:a"])
        #expect(r.dock.badge == nil)
        #expect(r.icons.last == .busy, "有人在忙的图标")
        r.run(7.0, [Fx.snap("t:a", activity: .idle)])
        #expect(r.icons.last == .normal)
    }

    /// 授权了：走系统通知，不弹提示卡；兜底（Dock / 菜单栏）照样开着。
    @Test func whenAuthorizedTheSystemNotificationIsUsedInsteadOfTheToast() {
        let r = Rig(status: .authorized)
        r.run(0, [Self.waiting()]); r.run(1.5, [Self.waiting()])
        #expect(r.center.added.count == 1 && r.center.added.first?.key == "t:a")
        #expect(r.toast.shown.isEmpty)
        #expect(r.dock.badge == "1" && r.icons.last == .waiting)
    }

    /// 还没问过（notDetermined）和不是 App 包（裸跑的可执行文件）：同样走兜底，绝不碰系统通知。
    @Test(arguments: [(UNAuthorizationStatus.notDetermined, true), (UNAuthorizationStatus.authorized, false)])
    func notYetAskedOrNotAnAppBundleAlsoFallsBack(status: UNAuthorizationStatus, available: Bool) {
        let r = Rig(status: status, available: available)
        r.run(0, [Self.waiting()]); r.run(1.5, [Self.waiting()])
        #expect(r.toast.shown.count == 1)
        #expect(r.center.added.isEmpty)
    }

    @Test func theDockDoesNotBounceWhileTheAppIsAlreadyInFront() {
        let r = Rig(status: .denied)
        r.dock.active = true
        r.run(0, [Self.waiting()]); r.run(1.5, [Self.waiting()])
        #expect(r.dock.attention == 0)
        #expect(r.dock.badge == "1")
    }

    /// 两个人同时在等：角标是 2，提示卡合并成一条「2 位同事在等你」。
    @Test func severalWaitersAreCountedAndMergedInTheFallbackToo() {
        let r = Rig(status: .denied)
        let a = AlertCoordinatorTests.waiting("t:a", seat: 0), b = AlertCoordinatorTests.waiting("t:b", seat: 1)
        r.run(0, [a, AlertCoordinatorTests.busy("t:b", seat: 1)])
        r.run(1.0, [a, b])
        r.run(1.5, [a, b])
        r.run(2.5, [a, b])
        #expect(r.dock.badge == "2")
        #expect(r.toast.shown.last?.key == AlertCoordinator.multiKey && r.toast.shown.last?.body == "2 位同事在等你")
        #expect(Set(r.toast.dismissed) == ["t:a", "t:b"], "各自的提示卡收回，换成合并的一张")
    }

    /// 隐藏 = 不打扰：被隐藏的 buddy 在等你，提示卡 / 角标 / 菜单栏图标 / Dock 弹跳全都没有；
    /// 但他仍算活会话（自动收起不能把他当成没有会话）。
    @Test func aHiddenBuddyDisturbsNobodyButStillCountsAsALiveSession() {
        let r = Rig(status: .denied)
        let all = [Self.waiting("t:h")]
        r.run(0, all, hidden: ["t:h"]); r.run(1.5, all, hidden: ["t:h"]); r.run(5, all, hidden: ["t:h"])
        #expect(r.toast.shown.isEmpty && r.center.added.isEmpty && r.sounds.isEmpty)
        #expect(r.dock.badge == nil && r.dock.attention == 0)
        #expect(r.icons.last == .normal)
        #expect(AppModel.hasLiveSessions(snapshots: all))
    }

    /// 演示模式的「做完了」不计入真实的今日白板；真实数据的照常计。
    @Test func demoModeNeverAddsToTheRealTally() {
        let real = Rig(status: .denied), demo = Rig(status: .denied)
        for (rig, isDemo) in [(real, false), (demo, true)] {
            rig.run(0, [Self.busy()], demo: isDemo)
            rig.run(1, [AlertCoordinatorTests.finished("t:a", duration: 5)], demo: isDemo)
        }
        #expect(real.store.settings.tallyToday() == 1)
        #expect(demo.store.settings.tallyToday() == 0)
    }

    // MARK: 菜单栏图标 / Dock 角标 的小规则
    @Test func menuBarIconKindAndDockBadgeLabels() {
        #expect(StatusItemController.iconKind(waiting: 1, busy: 5) == .waiting, "有人等你压过有人在忙")
        #expect(StatusItemController.iconKind(waiting: 0, busy: 1) == .busy)
        #expect(StatusItemController.iconKind(waiting: 0, busy: 0) == .normal)
        #expect(StatusItemController.tooltip(waiting: 3, busy: 1) == "3 位同事在等你")
        #expect(StatusItemController.tooltip(waiting: 0, busy: 2) == "2 位同事在忙")
        #expect(StatusItemController.tooltip(waiting: 0, busy: 0) == "Buddy 办公室")
        #expect(DockTileController.badgeLabel(waiting: 0) == nil)
        #expect(DockTileController.badgeLabel(waiting: 7) == "7")
        let fake = FakeDock(), d = DockTileController(env: fake.env)
        d.update(waiting: 2, newlyWaiting: false); d.update(waiting: 2, newlyWaiting: false)
        #expect(fake.badge == "2" && fake.attention == 0)
        d.update(waiting: 0, newlyWaiting: false)
        #expect(fake.badge == nil)
    }
}
