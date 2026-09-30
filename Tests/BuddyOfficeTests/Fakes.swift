import Foundation
import UserNotifications
import BuddyStage
import BuddyCore
@testable import BuddyOffice

/// 假的系统通知中心：状态可以设，记录 add / remove / 授权请求；请求之后状态变成 statusAfterRequest。所有回调同步（测试在主线程）。
final class FakeCenter: NotificationCenterClient {
    var status: UNAuthorizationStatus
    var statusAfterRequest: UNAuthorizationStatus = .denied
    var added: [(key: String, title: String, body: String)] = []
    var removed: [String] = []
    var requests = 0
    init(status: UNAuthorizationStatus) { self.status = status }
    func authorizationStatus(_ done: @escaping (UNAuthorizationStatus) -> Void) { done(status) }
    func requestAuthorization(_ done: @escaping () -> Void) { requests += 1; status = statusAfterRequest; done() }
    func add(key: String, title: String, body: String) { added.append((key, title, body)) }
    func removeDelivered(key: String) { removed.append(key) }
}

/// 假的像素提示面板。
final class FakeToast: ToastPresenting {
    var onClick: ((String) -> Void)?
    var shown: [(key: String, kind: ToastCard.Kind, title: String, body: String)] = []
    var dismissed: [String] = []
    func show(key: String, kind: ToastCard.Kind, title: String, body: String) { shown.append((key, kind, title, body)) }
    func dismiss(key: String) { dismissed.append(key) }
}

/// 假的 Dock 环境：记录角标和「弹一下」。
final class FakeDock {
    var badge: String?
    var attention = 0
    var active = false
    var env: DockTileController.Env {
        DockTileController.Env(setBadge: { [self] in badge = $0 }, requestAttention: { [self] in attention += 1 }, isAppActive: { [self] in active })
    }
}

/// 假的定时器：记录 (延迟, 回调, 是否被取消)；fire 按下标触发（被取消的不触发，和真 Timer.invalidate 一样）。
final class FakeScheduler {
    final class Job { let delay: TimeInterval; let block: () -> Void; var cancelled = false; init(_ d: TimeInterval, _ b: @escaping () -> Void) { delay = d; block = b } }
    private(set) var jobs: [Job] = []
    var scheduler: AutoQuit.Scheduler {
        { [self] delay, block in
            let j = Job(delay, block); jobs.append(j)
            return { j.cancelled = true }
        }
    }
    func fire(_ i: Int) { let j = jobs[i]; if !j.cancelled { j.block() } }
}

/// 假的数据源：记录 start / stop / markSeen / rerollAppearance，回调由测试手动触发。
final class FakeProvider: SnapshotProvider {
    var onUpdate: (([BuddySnapshot]) -> Void)?
    var onEvent: ((BuddyEvent) -> Void)?
    var started = 0, stopped = 0
    var seen: [String] = [], rerolled: [String] = []
    func start() { started += 1 }
    func stop() { stopped += 1 }
    func markSeen(key: String) { seen.append(key) }
    func rerollAppearance(key: String) { rerolled.append(key) }
    func diagnostics() -> DiagnosticsInfo { DiagnosticsInfo() }
}
