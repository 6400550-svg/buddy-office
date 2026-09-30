import Testing
import Foundation
import BuddyCore
import BuddyStage
@testable import BuddyOffice

/// 提醒判定（任务书 7.2）：假时钟（observe 的 now 参数）逐条验证去抖 1.5 s、20 s 节流、2 s 合并、8 s 等待、不打扰规则。
@Suite struct AlertCoordinatorTests {
    typealias Post = (key: String, kind: ToastCard.Kind, title: String, body: String)
    static func at(_ s: Double) -> Date { Fx.base.addingTimeInterval(s) }
    static func posts(_ out: [AlertCoordinator.Output]) -> [Post] {
        out.compactMap { if case .post(let k, let kind, let t, let b) = $0 { return (k, kind, t, b) }; return nil }
    }
    static func clears(_ out: [AlertCoordinator.Output]) -> [String] {
        out.compactMap { if case .clear(let k) = $0 { return k }; return nil }
    }
    static func waiting(_ key: String, origin: SessionOrigin = .terminal, activity: Activity? = nil, seat: Int = 0) -> BuddySnapshot {
        Fx.snap(key, seat: seat, origin: origin, activity: activity ?? .waitingApproval(tool: Fx.call("Bash", "git push")),
                host: origin == .desktop ? "local_" + key.dropFirst(2) : nil, pid: 100)
    }
    /// 一轮刚做完的会话（lastTurnDuration = 用时）。
    static func finished(_ key: String, origin: SessionOrigin = .terminal, duration: Double = 45, blocked: Bool = false, seat: Int = 0) -> BuddySnapshot {
        var s = Fx.snap(key, seat: seat, origin: origin, activity: .finished, host: origin == .desktop ? "local_" + key.dropFirst(2) : nil, pid: 100)
        s.lastTurnDuration = duration; s.blocked = blocked
        return s
    }
    static func busy(_ key: String, origin: SessionOrigin = .terminal, seat: Int = 0) -> BuddySnapshot {
        Fx.snap(key, seat: seat, origin: origin, activity: .thinking, host: origin == .desktop ? "local_" + key.dropFirst(2) : nil, pid: 100)
    }
    let nobodyLooks: (BuddySnapshot) -> Bool = { _ in false }
    let everyoneLooks: (BuddySnapshot) -> Bool = { _ in true }

    // MARK: 等待类：1.5 秒去抖
    @Test func approvalAlertWaitsExactlyOneAndAHalfSecondThenFiresOnce() {
        let c = AlertCoordinator(), cfg = AlertConfig(), s = Self.waiting("t:a")
        #expect(Self.posts(c.observe([s], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        #expect(Self.posts(c.observe([s], now: Self.at(1.49), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        let p = Self.posts(c.observe([s], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false))
        #expect(p.count == 1)
        #expect(p.first?.key == "t:a")
        #expect(p.first?.kind == .approval)
        #expect(p.first?.title == "会话 t:a")
        #expect(p.first?.body == "想用 Bash：git push（等你批准）")
        #expect(Self.posts(c.observe([s], now: Self.at(2.0), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty, "同一段等待只提醒一次")
        #expect(Self.posts(c.observe([s], now: Self.at(60), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
    }

    @Test func questionPlanAndOtherWaitsHaveTheirOwnWording() {
        let cases: [(Activity, ToastCard.Kind, String)] = [
            (.asking, .question, "有个问题要问你"), (.planReview, .plan, "计划好了，等你看"), (.waitingOther("input needed"), .approval, "在等你"),
            (.waitingApproval(tool: nil), .approval, "有个权限请求（等你批准）"),
        ]
        for (act, kind, body) in cases {
            let c = AlertCoordinator(), s = Self.waiting("t:a", activity: act)
            _ = c.observe([s], now: Self.at(0), config: AlertConfig(), isLooking: nobodyLooks, privacy: false)
            let p = Self.posts(c.observe([s], now: Self.at(1.5), config: AlertConfig(), isLooking: nobodyLooks, privacy: false))
            #expect(p.first?.kind == kind && p.first?.body == body, "\(act)")
        }
    }

    @Test func privacyModeHidesTheTitleAndTheCommand() {
        let c = AlertCoordinator(), s = Self.waiting("t:a")
        _ = c.observe([s], now: Self.at(0), config: AlertConfig(), isLooking: nobodyLooks, privacy: true)
        let p = Self.posts(c.observe([s], now: Self.at(1.5), config: AlertConfig(), isLooking: nobodyLooks, privacy: true))
        #expect(p.first?.title == "会话")
        #expect(p.first?.body == "有个权限请求（等你批准）")
    }

    @Test func settingsSwitchesTurnTheKindsOff() {
        var cfg = AlertConfig(); cfg.permission = false
        var c = AlertCoordinator()
        _ = c.observe([Self.waiting("t:a")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([Self.waiting("t:a")], now: Self.at(2), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        cfg = AlertConfig(); cfg.question = false
        c = AlertCoordinator()
        for act in [Activity.asking, .planReview] {
            _ = c.observe([Self.waiting("t:q", activity: act)], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
            #expect(Self.posts(c.observe([Self.waiting("t:q", activity: act)], now: Self.at(2), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        }
    }

    @Test func aWaitBlipShorterThanTheDebounceNeverAlertsAndClearsItsNotification() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        _ = c.observe([Self.waiting("t:a")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        let out = c.observe([Self.busy("t:a")], now: Self.at(1.0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(out).isEmpty)
        #expect(Self.clears(out) == ["t:a"])
        #expect(Self.posts(c.observe([Self.busy("t:a")], now: Self.at(5), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        #expect(c.waitingKeys.isEmpty)
    }

    /// 连续等待中换了种类（等批准 → 提问）：重新计时。
    @Test func changingTheKindOfWaitRestartsTheDebounce() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        _ = c.observe([Self.waiting("t:a")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([Self.waiting("t:a", activity: .asking)], now: Self.at(1.0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([Self.waiting("t:a", activity: .asking)], now: Self.at(2.0), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty, "提问从 1.0 起算，2.0 才 1 秒")
        #expect(Self.posts(c.observe([Self.waiting("t:a", activity: .asking)], now: Self.at(2.5), config: cfg, isLooking: nobodyLooks, privacy: false)).count == 1)
    }

    // MARK: 20 秒节流
    /// 同一个 buddy 的同一类提醒 20 秒内最多一条（这里的时刻都是 0.5 的整数倍，Double 算术是精确的，边界不会抖）。
    @Test func sameBuddySameKindIsThrottledForTwentySeconds() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        func obs(_ t: Double, _ s: BuddySnapshot) -> [Post] { Self.posts(c.observe([s], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false)) }
        _ = obs(0, Self.waiting("t:a"))
        #expect(obs(1.5, Self.waiting("t:a")).count == 1, "第一条")
        _ = obs(3, Self.busy("t:a")); _ = obs(4, Self.waiting("t:a"))
        #expect(obs(5.5, Self.waiting("t:a")).isEmpty, "距上一条 4 秒：节流")
        _ = obs(6, Self.busy("t:a")); _ = obs(18, Self.waiting("t:a"))
        #expect(obs(19.5, Self.waiting("t:a")).isEmpty, "距上一条 18 秒：还在节流")
        _ = obs(20, Self.busy("t:a")); _ = obs(20.5, Self.waiting("t:a"))
        #expect(obs(21.5, Self.waiting("t:a")).isEmpty, "距上一条 20 秒 -0：这次 20.5 才开始等，21.5 只等了 1 秒")
        #expect(obs(22, Self.waiting("t:a")).count == 1, "22 - 1.5 = 20.5 秒了：可以再提醒")
    }

    @Test func differentKindsAndDifferentBuddiesAreNotThrottledAgainstEachOther() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        func obs(_ t: Double, _ ss: [BuddySnapshot]) -> [Post] { Self.posts(c.observe(ss, now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false)) }
        _ = obs(0, [Self.waiting("t:a")])
        #expect(obs(1.5, [Self.waiting("t:a")]).count == 1)
        _ = obs(5, [Self.waiting("t:a", activity: .asking)])                       // 同一个人，换成提问
        #expect(obs(6.5, [Self.waiting("t:a", activity: .asking)]).count == 1, "等批准和提问是两类，各自节流")
        _ = obs(10, [Self.waiting("t:b")])
        #expect(obs(11.5, [Self.waiting("t:b")]).count == 1, "别的 buddy 不受影响（离上一条已经超过 2 秒，也不合并）")
    }

    // MARK: 2 秒合并
    @Test func alertsWithinTwoSecondsOfEachOtherMergeIntoOne() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        let a = Self.waiting("t:a", seat: 0)
        func obs(_ t: Double, b: BuddySnapshot) -> [AlertCoordinator.Output] { c.observe([a, b], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false) }
        _ = obs(0, b: Self.busy("t:b", seat: 1))
        _ = obs(1.0, b: Self.waiting("t:b", seat: 1))                         // B 从 1.0 才开始等
        let first = obs(1.5, b: Self.waiting("t:b", seat: 1))
        #expect(Self.posts(first).map { $0.key } == ["t:a"], "A 先满 1.5 秒；B 还差 1 秒")
        let merged = obs(2.5, b: Self.waiting("t:b", seat: 1))
        let mp = Self.posts(merged)
        #expect(mp.count == 1 && mp[0].key == AlertCoordinator.multiKey)
        #expect(mp[0].body == "2 位同事在等你" && mp[0].kind == .approval && mp[0].title == "Buddy 办公室")
        #expect(Set(Self.clears(merged)) == ["t:a", "t:b"], "各自的旧提醒要撤掉，换成合并的一条")
    }

    @Test func threeBuddiesMergeIntoThree() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        let from: [String: Double] = ["t:a": 0, "t:b": 0.5, "t:c": 1.0]                 // 各自在 1.5 / 2.0 / 2.5 满 1.5 秒
        func snaps(_ t: Double) -> [BuddySnapshot] {
            ["t:a", "t:b", "t:c"].enumerated().map { i, n in (from[n] ?? .infinity) <= t ? Self.waiting(n, seat: i) : Self.busy(n, seat: i) }
        }
        var last: [AlertCoordinator.Output] = []
        for t in stride(from: 0.0, through: 2.5, by: 0.25) { last = c.observe(snaps(t), now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false) }
        let mp = Self.posts(last)
        #expect(mp.count == 1 && mp[0].key == AlertCoordinator.multiKey && mp[0].body == "3 位同事在等你", "\(mp)")
        #expect(Set(Self.clears(last)) == ["t:a", "t:b", "t:c"])
    }

    @Test func alertsTwoSecondsOrMoreApartStayApart() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        let a = Self.waiting("t:a", seat: 0)
        func obs(_ t: Double, b: BuddySnapshot) -> [AlertCoordinator.Output] { c.observe([a, b], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false) }
        _ = obs(0, b: Self.busy("t:b", seat: 1))
        #expect(Self.posts(obs(1.5, b: Self.busy("t:b", seat: 1))).map { $0.key } == ["t:a"])
        _ = obs(2.0, b: Self.waiting("t:b", seat: 1))
        let out = obs(3.5, b: Self.waiting("t:b", seat: 1))
        #expect(Self.posts(out).map { $0.key } == ["t:b"], "A 在 1.5 提醒过，B 在 3.5（正好隔了 2 秒）：各是各的")
        #expect(Self.clears(out).isEmpty)
    }

    @Test func theSameBuddyAlertingTwiceIsNotAMerge() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        _ = c.observe([Self.waiting("t:a")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        let first = Self.posts(c.observe([Self.waiting("t:a")], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false))
        _ = c.observe([Self.waiting("t:a", activity: .asking)], now: Self.at(1.8), config: cfg, isLooking: nobodyLooks, privacy: false)
        let second = Self.posts(c.observe([Self.waiting("t:a", activity: .asking)], now: Self.at(3.3), config: cfg, isLooking: nobodyLooks, privacy: false))
        #expect(first.first?.key == "t:a" && second.first?.key == "t:a", "同一个 buddy 连着两条不合并成「2 位同事」")
    }

    /// A-022 ②：合并出来的「N 位同事在等你」在所有被合并的人都不再等之后要撤掉（原来永远留在通知中心里）。
    @Test func theMergedNotificationIsClearedWhenNobodyIsWaitingAnymore() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        let a = Self.waiting("t:a", seat: 0)
        _ = c.observe([a, Self.busy("t:b", seat: 1)], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([a, Self.waiting("t:b", seat: 1)], now: Self.at(1.0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([a, Self.waiting("t:b", seat: 1)], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false)
        let merged = c.observe([a, Self.waiting("t:b", seat: 1)], now: Self.at(2.5), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(merged).first?.key == AlertCoordinator.multiKey)
        // A 批准了，B 还在等：合并的那条留着
        let oneLeft = c.observe([Self.busy("t:a", seat: 0), Self.waiting("t:b", seat: 1)], now: Self.at(4), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(!Self.clears(oneLeft).contains(AlertCoordinator.multiKey))
        // B 也批准了：撤掉
        let none = c.observe([Self.busy("t:a", seat: 0), Self.busy("t:b", seat: 1)], now: Self.at(5), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.clears(none).contains(AlertCoordinator.multiKey), "所有被合并的人都不再等了：合并那条也要撤")
        let again = c.observe([Self.busy("t:a", seat: 0), Self.busy("t:b", seat: 1)], now: Self.at(6), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(!Self.clears(again).contains(AlertCoordinator.multiKey), "只撤一次")
    }

    /// A-022 ②：合并的对象是「做完了」时，文案不能说「在等你」；混着来就说「有事找你」。
    @Test func mergedFinishedAndMixedNotificationsUseTheirOwnWords() {
        let cfg = AlertConfig()
        // 两个终端会话 2 秒内先后做完
        var c = AlertCoordinator()
        _ = c.observe([Self.busy("t:a", seat: 0), Self.busy("t:b", seat: 1)], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        let f1 = c.observe([Self.finished("t:a", seat: 0), Self.busy("t:b", seat: 1)], now: Self.at(1), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(f1).first?.key == "t:a")
        let f2 = c.observe([Self.finished("t:a", seat: 0), Self.finished("t:b", seat: 1)], now: Self.at(1.75), config: cfg, isLooking: nobodyLooks, privacy: false)
        let m = Self.posts(f2)
        #expect(m.count == 1 && m[0].key == AlertCoordinator.multiKey && m[0].body == "2 位同事做完了" && m[0].kind == .finished, "\(m)")
        // 一个做完、一个在等
        c = AlertCoordinator()
        _ = c.observe([Self.busy("t:a", seat: 0), Self.waiting("t:b", seat: 1)], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([Self.finished("t:a", seat: 0), Self.waiting("t:b", seat: 1)], now: Self.at(1.0), config: cfg, isLooking: nobodyLooks, privacy: false)
        let mixed = c.observe([Self.finished("t:a", seat: 0), Self.waiting("t:b", seat: 1)], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false)
        let mp = Self.posts(mixed)
        #expect(mp.count == 1 && mp[0].key == AlertCoordinator.multiKey && mp[0].body == "2 位同事有事找你", "\(mp)")
    }

    // MARK: 做完了
    @Test func finishedAlertNeedsAnUninterruptedTurnOfAtLeast30Seconds() {
        let cfg = AlertConfig()
        func run(_ s: BuddySnapshot, config: AlertConfig = cfg) -> [Post] {
            let c = AlertCoordinator()
            _ = c.observe([Self.busy(s.key)], now: Self.at(0), config: config, isLooking: nobodyLooks, privacy: false)
            return Self.posts(c.observe([s], now: Self.at(1), config: config, isLooking: nobodyLooks, privacy: false))
        }
        #expect(run(Self.finished("t:a", duration: 29.9)).isEmpty, "不到 30 秒不提醒")
        let p = run(Self.finished("t:a", duration: 30))
        #expect(p.count == 1 && p[0].kind == .finished && p[0].body == "做完了（用时 30秒）")
        #expect(run(Self.finished("t:a", duration: 192)).first?.body == "做完了（用时 3分12秒）")
        var interrupted = Fx.snap("t:a", activity: .interrupted); interrupted.lastTurnDuration = 300
        #expect(run(interrupted).isEmpty, "被打断的一轮不提醒")
        var off = cfg; off.finished = false
        #expect(run(Self.finished("t:a", duration: 300), config: off).isEmpty)
        var five = cfg; five.finishedMinSeconds = 5
        #expect(run(Self.finished("t:a", duration: 6), config: five).count == 1, "最短用时可调")
    }

    @Test func everyNormallyFinishedTurnIsCountedForTheWhiteboardEvenWhenNoAlertIsSent() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        _ = c.observe([Self.busy("t:a")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([Self.finished("t:a", duration: 3)], now: Self.at(1), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(c.finishedTurns == 1)
        _ = c.observe([Self.finished("t:a", duration: 3)], now: Self.at(2), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(c.finishedTurns == 0, "同一次做完只数一次")
        var interrupted = Fx.snap("t:a", activity: .interrupted); interrupted.lastTurnDuration = 3
        _ = c.observe([interrupted], now: Self.at(3), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(c.finishedTurns == 0, "被打断不算做完")
        // 第一次看到就是做完了（没有上一个状态）：不数（可能是启动时就已经在做完状态）
        let d = AlertCoordinator()
        _ = d.observe([Self.finished("t:z")], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(d.finishedTurns == 0)
    }

    /// 桌面会话：「本轮总结」大约 7 秒后才落盘，最多等 8 秒看会不会变成 blocked（→「需要你处理」）。
    @Test func aDesktopSessionWaitsEightSecondsForTheTurnSummary() {
        let cfg = AlertConfig()
        let c = AlertCoordinator()
        func obs(_ t: Double, _ s: BuddySnapshot) -> [Post] { Self.posts(c.observe([s], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false)) }
        _ = obs(0, Self.busy("d:a", origin: .desktop))
        #expect(obs(1, Self.finished("d:a", origin: .desktop, duration: 60)).isEmpty)
        #expect(obs(8.9, Self.finished("d:a", origin: .desktop, duration: 60)).isEmpty, "还没到 8 秒")
        let p = obs(9, Self.finished("d:a", origin: .desktop, duration: 60))
        #expect(p.count == 1 && p[0].kind == .finished && p[0].body == "做完了（用时 1分0秒）")
        // blocked 立刻改成「需要你处理」
        let c2 = AlertCoordinator()
        _ = c2.observe([Self.busy("d:b", origin: .desktop)], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c2.observe([Self.finished("d:b", origin: .desktop, duration: 60)], now: Self.at(1), config: cfg, isLooking: nobodyLooks, privacy: false)
        let b = Self.posts(c2.observe([Self.finished("d:b", origin: .desktop, duration: 60, blocked: true)], now: Self.at(3), config: cfg, isLooking: nobodyLooks, privacy: false))
        #expect(b.count == 1 && b[0].kind == .blocked && b[0].body == "需要你处理")
    }

    /// 疑点 12：等了 8 秒之后才发「做完了」，这 8 秒里下一轮已经开始了——不能在一个正忙着的会话上冒出「做完了」。
    @Test func aPendingFinishedAlertIsDroppedIfTheNextTurnAlreadyStarted() {
        let cfg = AlertConfig(), c = AlertCoordinator()
        func obs(_ t: Double, _ s: BuddySnapshot) -> [Post] { Self.posts(c.observe([s], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false)) }
        _ = obs(0, Self.busy("d:a", origin: .desktop))
        #expect(obs(1, Self.finished("d:a", origin: .desktop, duration: 60)).isEmpty)
        #expect(obs(5, Self.busy("d:a", origin: .desktop)).isEmpty, "用户很快回了下一句，会话又开始忙了")
        #expect(obs(9, Self.busy("d:a", origin: .desktop)).isEmpty, "8 秒到了：不该再发「做完了」")
        #expect(obs(20, Self.busy("d:a", origin: .desktop)).isEmpty)
    }

    // MARK: 不打扰
    @Test func desktopSessionYouAreLookingAtNeverAlertsForThatWholeWait() {
        let c = AlertCoordinator(), cfg = AlertConfig(), s = Self.waiting("d:a", origin: .desktop)
        _ = c.observe([s], now: Self.at(0), config: cfg, isLooking: everyoneLooks, privacy: false)
        #expect(Self.posts(c.observe([s], now: Self.at(1.5), config: cfg, isLooking: everyoneLooks, privacy: false)).isEmpty)
        #expect(Self.posts(c.observe([s], now: Self.at(5), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty, "这一段等待整个不提醒（你看过了）")
        // 关掉「你正在看那个会话时不提醒」之后照常提醒
        var cfg2 = cfg; cfg2.suppressWhenFocused = false
        let c2 = AlertCoordinator()
        _ = c2.observe([s], now: Self.at(0), config: cfg2, isLooking: everyoneLooks, privacy: false)
        #expect(Self.posts(c2.observe([s], now: Self.at(1.5), config: cfg2, isLooking: everyoneLooks, privacy: false)).count == 1)
    }

    /// 终端会话：宿主 App 在最前面，先等 8 秒再判断一次；8 秒后你走开了就提醒，还在看就整段不提醒。
    @Test func terminalSessionWaitsEightSecondsThenChecksAgainWhetherYouAreStillLooking() {
        let cfg = AlertConfig(), s = Self.waiting("t:a")
        var looking = true
        let c = AlertCoordinator()
        func obs(_ t: Double) -> [Post] { Self.posts(c.observe([s], now: Self.at(t), config: cfg, isLooking: { _ in looking }, privacy: false)) }
        _ = obs(0)
        #expect(obs(1.5).isEmpty, "在看：先不提醒，8 秒后再看一次")
        #expect(obs(5).isEmpty)
        #expect(obs(9.4).isEmpty)
        looking = false
        let p = obs(9.5)
        #expect(p.count == 1, "1.5 + 8 = 9.5：这时你已经走开了，提醒")
        // 还在看：整段都不提醒
        looking = true
        let c2 = AlertCoordinator()
        _ = c2.observe([s], now: Self.at(0), config: cfg, isLooking: { _ in looking }, privacy: false)
        _ = c2.observe([s], now: Self.at(1.5), config: cfg, isLooking: { _ in looking }, privacy: false)
        #expect(Self.posts(c2.observe([s], now: Self.at(9.5), config: cfg, isLooking: { _ in looking }, privacy: false)).isEmpty)
    }

    /// N07b：终端会话的「做完了」也一样——宿主 App 在最前面就先等 8 秒再判断一次（原来立刻判断，在看就直接丢掉）。
    @Test func aTerminalFinishedAlertAlsoWaitsEightSecondsWhenYouAreLooking() {
        let cfg = AlertConfig()
        var looking = true
        let c = AlertCoordinator()
        func obs(_ t: Double, _ s: BuddySnapshot) -> [Post] { Self.posts(c.observe([s], now: Self.at(t), config: cfg, isLooking: { _ in looking }, privacy: false)) }
        _ = obs(0, Self.busy("t:a"))
        #expect(obs(1, Self.finished("t:a")).isEmpty, "在看终端：先不提醒")
        #expect(obs(5, Self.finished("t:a")).isEmpty)
        looking = false
        let p = obs(9, Self.finished("t:a"))
        #expect(p.count == 1 && p[0].kind == .finished, "8 秒后你已经不在看了：提醒")
        // 不在看：立刻提醒（不多等）
        looking = false
        let c2 = AlertCoordinator()
        _ = c2.observe([Self.busy("t:b")], now: Self.at(0), config: cfg, isLooking: { _ in false }, privacy: false)
        #expect(Self.posts(c2.observe([Self.finished("t:b")], now: Self.at(1), config: cfg, isLooking: { _ in false }, privacy: false)).count == 1)
        // 8 秒后还在看：不提醒
        let c3 = AlertCoordinator()
        _ = c3.observe([Self.busy("t:c")], now: Self.at(0), config: cfg, isLooking: { _ in true }, privacy: false)
        _ = c3.observe([Self.finished("t:c")], now: Self.at(1), config: cfg, isLooking: { _ in true }, privacy: false)
        #expect(Self.posts(c3.observe([Self.finished("t:c")], now: Self.at(9), config: cfg, isLooking: { _ in true }, privacy: false)).isEmpty)
    }

    @Test func desktopSessionsAreSkippedWhenIncludeDesktopIsOff() {
        var cfg = AlertConfig(); cfg.includeDesktop = false
        let c = AlertCoordinator()
        let w = Self.waiting("d:a", origin: .desktop)
        _ = c.observe([w], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([w], now: Self.at(2), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        #expect(c.waitingKeys == ["d:a"], "Dock 角标 / 菜单栏仍然数着他（兜底任何时候都开着）")
        _ = c.observe([Self.busy("d:b", origin: .desktop)], now: Self.at(3), config: cfg, isLooking: nobodyLooks, privacy: false)
        _ = c.observe([Self.finished("d:b", origin: .desktop)], now: Self.at(4), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([Self.finished("d:b", origin: .desktop)], now: Self.at(20), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
    }

    // MARK: 出错
    @Test func errorAlertsAreOffByDefaultAndThrottledWhenOn() {
        let c = AlertCoordinator(), on = { var x = AlertConfig(); x.error = true; return x }()
        _ = c.observe([Self.busy("t:a")], now: Self.at(0), config: AlertConfig(), isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([Fx.snap("t:a", activity: .errored)], now: Self.at(1), config: AlertConfig(), isLooking: nobodyLooks, privacy: false)).isEmpty, "默认关")
        let d = AlertCoordinator()
        _ = d.observe([Self.busy("t:a")], now: Self.at(0), config: on, isLooking: nobodyLooks, privacy: false)
        let p = Self.posts(d.observe([Fx.snap("t:a", activity: .errored)], now: Self.at(1), config: on, isLooking: nobodyLooks, privacy: false))
        #expect(p.count == 1 && p[0].kind == .error && p[0].body == "出错了")
        _ = d.observe([Self.busy("t:a")], now: Self.at(2), config: on, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(d.observe([Fx.snap("t:a", activity: .errored)], now: Self.at(3), config: on, isLooking: nobodyLooks, privacy: false)).isEmpty, "20 秒内不重复")
    }

    // MARK: Dock 角标 / 菜单栏用的状态
    @Test func waitingKeysAreImmediateButTheDockBounceUsesTheSameDebounce() {
        let c = AlertCoordinator(), cfg = AlertConfig(), s = Self.waiting("t:a")
        _ = c.observe([s], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(c.waitingKeys == ["t:a"], "角标 / 菜单栏举手图标：一开始等就数")
        #expect(!c.newlyWaiting, "Dock 弹跳要等满 1.5 秒（一闪而过的等待不该让 Dock 图标弹一下）")
        _ = c.observe([s], now: Self.at(1.49), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(!c.newlyWaiting)
        _ = c.observe([s], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(c.newlyWaiting)
        _ = c.observe([s], now: Self.at(2), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(!c.newlyWaiting, "同一段等待只弹一次")
        // 一闪而过的等待：整个过程都没弹
        let d = AlertCoordinator()
        var bounced = false
        for (t, snap) in [(0.0, s), (0.5, s), (1.0, Self.busy("t:a"))] {
            _ = d.observe([snap], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false)
            bounced = bounced || d.newlyWaiting
        }
        #expect(!bounced)
    }

    // MARK: 隐藏 = 不打扰
    /// 用户「隐藏」的 buddy 不弹窗、不响铃、不计入 Dock 角标 / 菜单栏「N 位同事在等你」、不让 Dock 弹跳（任务书没写；按「隐藏 = 不打扰」处理）。
    @Test func hiddenBuddiesAreMutedNoAlertNoBadgeNoBounce() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        let h = Self.waiting("t:h", seat: 0), v = Self.waiting("t:v", seat: 1)
        func obs(_ t: Double, _ ss: [BuddySnapshot]) -> [AlertCoordinator.Output] { c.observe(ss, now: Self.at(t), config: cfg, muted: ["t:h"], isLooking: nobodyLooks, privacy: false) }
        _ = obs(0, [h, v])
        #expect(c.waitingKeys == ["t:v"], "被隐藏的不计入角标 / 菜单栏")
        let out = obs(1.5, [h, v])
        #expect(Self.posts(out).map { $0.key } == ["t:v"], "只有没隐藏的那个提醒")
        #expect(c.newlyWaiting, "没隐藏的那个照常让 Dock 弹一下")
        // 只有隐藏的在等：什么都没有
        let d = AlertCoordinator()
        _ = d.observe([h], now: Self.at(0), config: cfg, muted: ["t:h"], isLooking: nobodyLooks, privacy: false)
        let o2 = d.observe([h], now: Self.at(2), config: cfg, muted: ["t:h"], isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(o2).isEmpty && d.waitingKeys.isEmpty && !d.newlyWaiting)
    }

    /// 提醒已经发出去之后才把他隐藏：撤掉那条提醒；重新显示时当作一段新的等待重新计时。
    @Test func hidingABuddyWhoIsAlreadyAlertingClearsTheAlert() {
        let c = AlertCoordinator(), cfg = AlertConfig(), s = Self.waiting("t:a")
        _ = c.observe([s], now: Self.at(0), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([s], now: Self.at(1.5), config: cfg, isLooking: nobodyLooks, privacy: false)).count == 1)
        let hidden = c.observe([s], now: Self.at(3), config: cfg, muted: ["t:a"], isLooking: nobodyLooks, privacy: false)
        #expect(Self.clears(hidden) == ["t:a"] && Self.posts(hidden).isEmpty)
        #expect(c.waitingKeys.isEmpty)
        // 重新显示：从头计时（不会立刻补发，也不会因为老的 episode 直接跳过去重）
        _ = c.observe([s], now: Self.at(100), config: cfg, isLooking: nobodyLooks, privacy: false)
        #expect(Self.posts(c.observe([s], now: Self.at(101), config: cfg, isLooking: nobodyLooks, privacy: false)).isEmpty)
        #expect(Self.posts(c.observe([s], now: Self.at(101.5), config: cfg, isLooking: nobodyLooks, privacy: false)).count == 1)
    }

    /// 隐藏的 buddy 做完一轮：不提醒，但白板上的「正」字照常记（那是「今天做完了几轮」）。
    @Test func aHiddenBuddysFinishedTurnsStillCountForTheWhiteboardButNeverAlert() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        _ = c.observe([Self.busy("t:h")], now: Self.at(0), config: cfg, muted: ["t:h"], isLooking: nobodyLooks, privacy: false)
        let out = c.observe([Self.finished("t:h", duration: 120)], now: Self.at(1), config: cfg, muted: ["t:h"], isLooking: nobodyLooks, privacy: false)
        #expect(c.finishedTurns == 1)
        #expect(Self.posts(out).isEmpty)
    }

    // MARK: 记账字典有界
    @Test func bookkeepingDoesNotGrowWithEverySessionEverSeen() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        var t = 0.0
        for i in 0..<1500 {
            let k = "t:\(i)"
            _ = c.observe([Self.busy(k)], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false); t += 1
            _ = c.observe([Self.waiting(k)], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false); t += 1
            _ = c.observe([Self.waiting(k)], now: Self.at(t + 1.5), config: cfg, isLooking: nobodyLooks, privacy: false); t += 2
            _ = c.observe([Self.finished(k)], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false); t += 1
            _ = c.observe([], now: Self.at(t), config: cfg, isLooking: nobodyLooks, privacy: false); t += 1      // 会话走了
        }
        let n = c.bookkeepingCounts
        #expect(n.prevActivity <= 1, "prevActivity = \(n.prevActivity)")
        #expect(n.finished <= 1, "finished = \(n.finished)")
        #expect(n.episodes <= 1, "episodes = \(n.episodes)")
        #expect(n.lastAlert <= 12, "lastAlert = \(n.lastAlert)：20 秒之前的节流记录没有用了，不该留着")
    }

    /// A-022 ①：等待分支里的提前 continue 不许跳过同一轮里后面的记账（prevActivity / 做完了计数）。
    @Test func waitingBranchNeverSkipsThePerSnapshotBookkeeping() {
        let c = AlertCoordinator(), cfg = AlertConfig()
        var looking = true
        func obs(_ t: Double, _ s: BuddySnapshot) { _ = c.observe([s], now: Self.at(t), config: cfg, isLooking: { _ in looking }, privacy: false) }
        obs(0, Self.busy("t:a"))
        obs(1, Self.finished("t:a"))
        #expect(c.finishedTurns == 1)
        obs(2, Self.waiting("t:a")); obs(3.6, Self.waiting("t:a")); obs(4, Self.waiting("t:a"))       // 终端在前：被延迟（continue 那条路）
        looking = false
        obs(5, Self.busy("t:a"))
        obs(6, Self.finished("t:a"))
        #expect(c.finishedTurns == 1, "第二轮做完也要数上")
    }

    // MARK: 标题显示（A-019）
    @Test func titlesAreAlwaysDisplayable() {
        #expect(AlertText.title("  \n\t ", privacy: false) == "（没有标题）")
        #expect(AlertText.title("", privacy: false) == "（没有标题）")
        #expect(AlertText.title("重构登录模块", privacy: false) == "重构登录模块")
        #expect(AlertText.title("第一行\n第二行\r\n\n第三行", privacy: false) == "第一行 第二行 第三行", "换行换成空格")
        #expect(AlertText.title("🚀 发布 v2.0 ✨ 上线", privacy: false) == "🚀 发布 v2.0 ✨ 上线")
        #expect(AlertText.title(String(repeating: "长", count: 100), privacy: false) == String(repeating: "长", count: 40) + "…", "最多 40 个字")
        #expect(AlertText.title(String(repeating: "x", count: 40), privacy: false).count == 40)
        #expect(AlertText.title("秘密标题", privacy: true) == "会话")
    }
}
