import AppKit
import BuddyCore
import BuddyStage

/// 提醒流水线的出口：系统通知 / 提示卡、白板计数、菜单栏图标 + Dock 角标 / 弹跳。测试用假的记录调用。
protocol AlertSink: AnyObject {
    func post(key: String, kind: ToastCard.Kind, title: String, body: String)
    func clear(key: String)
    func addTally()
    /// 等你的人数 / 在忙的人数：菜单栏图标和 Dock 角标；newlyWaiting = 有一段等待刚满 1.5 秒（Dock 弹一下）。
    func update(waiting: Int, busy: Int, newlyWaiting: Bool)
}

/// AppModel.tick 里「提醒」那一段：判定（AlertCoordinator）→ 出口（AlertSink）。
/// 兜底提醒（Dock 角标 / 弹跳、菜单栏图标）任何时候都开着，和系统通知有没有授权无关；系统通知被拒时提示卡由 NotificationService 补上。
final class AlertPipeline {
    let coordinator = AlertCoordinator()
    private let sink: AlertSink
    init(sink: AlertSink) { self.sink = sink }

    /// - snapshots：数据层给出的全部快照（含被隐藏的：他们的白板计数照数）；hidden：用户隐藏的 buddy（不提醒、不进角标）。
    /// - present：在办公室里显示的（去掉隐藏的）——菜单栏「在忙」的人数按它数。
    /// - demo：演示模式不计入真实的今日白板。
    func run(snapshots: [BuddySnapshot], present: [BuddySnapshot], hidden: Set<String>, now: Date, config: AlertConfig,
             isLooking: (BuddySnapshot) -> Bool, privacy: Bool, demo: Bool) {
        let outs = coordinator.observe(snapshots, now: now, config: config, muted: hidden, isLooking: isLooking, privacy: privacy)
        if !demo { for _ in 0..<coordinator.finishedTurns { sink.addTally() } }
        for o in outs {
            switch o {
            case .post(let key, let kind, let title, let body): sink.post(key: key, kind: kind, title: title, body: body)
            case .clear(let key): sink.clear(key: key)
            }
        }
        sink.update(waiting: coordinator.waitingKeys.count, busy: present.filter { $0.phase == .busy }.count, newlyWaiting: coordinator.newlyWaiting)
    }
}

/// 真实的出口：NotificationService（系统通知 + 提示卡 + 提示音）、菜单栏图标、Dock。
final class LiveAlertSink: AlertSink {
    private let notifier: NotificationService
    private let dock: DockTileController
    private let updateStatus: (Int, Int) -> Void
    private let settings: Settings
    init(notifier: NotificationService, dock: DockTileController, updateStatus: @escaping (Int, Int) -> Void, settings: Settings) {
        self.notifier = notifier; self.dock = dock; self.updateStatus = updateStatus; self.settings = settings
    }
    func post(key: String, kind: ToastCard.Kind, title: String, body: String) { notifier.post(key: key, kind: kind, title: title, body: body, sound: settings.string("notify.sound")) }
    func clear(key: String) { notifier.clear(key: key) }
    func addTally() { settings.addTally() }
    func update(waiting: Int, busy: Int, newlyWaiting: Bool) {
        updateStatus(waiting, busy)
        dock.update(waiting: waiting, newlyWaiting: newlyWaiting)
    }
}
