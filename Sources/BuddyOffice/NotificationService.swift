import AppKit
import UserNotifications
import BuddyStage
import PixelKit

/// 系统通知中心的最小接口：真实实现包 UNUserNotificationCenter；测试用假的（不碰系统、不弹授权框）。
protocol NotificationCenterClient: AnyObject {
    func authorizationStatus(_ done: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(_ done: @escaping () -> Void)
    func add(key: String, title: String, body: String)
    func removeDelivered(key: String)
}

final class SystemNotificationCenter: NotificationCenterClient {
    func authorizationStatus(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { done($0.authorizationStatus) }
    }
    func requestAuthorization(_ done: @escaping () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in done() }
    }
    func add(key: String, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        c.userInfo = ["buddyKey": key]
        c.threadIdentifier = "buddy.\(key)"
        let req = UNNotificationRequest(identifier: "buddy.\(key)", content: c, trigger: nil)     // 相同 identifier 直接替换旧的
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
    func removeDelivered(key: String) { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["buddy.\(key)"]) }
}

/// 系统通知 + 像素提示面板兜底。只有 App 包（.app + bundle id）才调用 UNUserNotificationCenter，否则裸跑的可执行文件会崩。
/// 系统通知没授权 / 被拒 / 还没问过：改用像素提示面板（Dock 角标、菜单栏图标由 AlertPipeline 的 sink 另外负责，始终开着）。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// 「已经发过一次授权请求」的标记：被拒 / 已答复 / 问过没答复之后都不再自动弹（设置页的按钮不受限制）。
    static let askedKey = "notify.authRequested"
    var onClick: ((String) -> Void)?
    private(set) var status: UNAuthorizationStatus = .notDetermined
    let toast: ToastPresenting
    let available: Bool
    private let client: NotificationCenterClient
    private let playSound: (SoundSynth.Kind, String) -> Void
    private let defaults: UserDefaults

    init(client: NotificationCenterClient = SystemNotificationCenter(), toast: ToastPresenting = ToastController(),
         playSound: @escaping (SoundSynth.Kind, String) -> Void = { SoundSynth.play($0, mode: $1) },
         available: Bool = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil,
         defaults: UserDefaults = .standard) {
        self.client = client; self.toast = toast; self.playSound = playSound; self.available = available; self.defaults = defaults
        super.init()
        if available && client is SystemNotificationCenter { UNUserNotificationCenter.current().delegate = self }
        if available { refresh() }
        toast.onClick = { [weak self] key in self?.onClick?(key) }
    }

    func refresh(_ done: ((UNAuthorizationStatus) -> Void)? = nil) {
        guard available else { done?(.denied); return }
        client.authorizationStatus { [weak self] s in
            let apply = { self?.status = s; done?(s) }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    /// 设置页的「请求通知授权」按钮：系统里还是「没问过」才发；发出去就记一笔（之后自动的那条路不再弹）。
    func requestAuthorizationIfNeeded(done: (() -> Void)? = nil) {
        guard available, status == .notDetermined else { done?(); return }
        defaults.set(true, forKey: Self.askedKey)
        client.requestAuthorization { [weak self] in self?.refresh { _ in done?() } }
    }

    /// DESIGN §2 M0：授权请求放在「用户第一次主动打开办公室窗口」的时候发（后台启动的 App 不一定会弹授权框）。
    /// 条件：系统里还是「没问过」、我们也没问过（拒绝 / 已答复 / 问过没答复之后都不再反复弹）、App 在前台、办公室窗口可见。
    static func shouldRequestOnOfficeOpen(status: UNAuthorizationStatus, alreadyAsked: Bool, appActive: Bool, officeVisible: Bool, available: Bool) -> Bool {
        available && status == .notDetermined && !alreadyAsked && appActive && officeVisible
    }
    /// 办公室窗口出现了 / App 变成前台了：先读一次系统里的真实状态，再按上面的条件决定要不要问。
    func officeMayHaveOpened(appActive: @escaping () -> Bool, officeVisible: @escaping () -> Bool) {
        guard available else { return }
        refresh { [weak self] st in
            guard let self = self, Self.shouldRequestOnOfficeOpen(status: st, alreadyAsked: self.defaults.bool(forKey: Self.askedKey),
                                                                  appActive: appActive(), officeVisible: officeVisible(), available: self.available) else { return }
            self.requestAuthorizationIfNeeded()
        }
    }

    var statusText: String {
        guard available else { return "不可用（不是 App 包）" }
        switch status { case .authorized, .provisional, .ephemeral: return "已授权"; case .denied: return "已拒绝（系统设置 → 通知 里可以打开）"; case .notDetermined: return "还没询问"; @unknown default: return "未知" }
    }
    var systemAllowed: Bool { available && (status == .authorized || status == .provisional) }

    /// 现在还有效的（发出去了、没被撤掉的）提醒 key：系统通知发出后要再核对授权状态，核对回来之前这条提醒可能已经被撤掉了。
    private var liveKeys: Set<String> = []

    func post(key: String, kind: ToastCard.Kind, title: String, body: String, sound: String) {
        if liveKeys.count > 200 { liveKeys.removeAll() }                 // 有界（做完了 / 出错的提醒不会被撤掉；key 数本来就只有会话数那么多）
        liveKeys.insert(key)
        if systemAllowed {
            client.add(key: key, title: title, body: body)
            // 缓存的授权状态可能过期：用户在 App 运行期间把「通知」关了，系统会把这条悄悄吞掉，而缓存里还是「已授权」，兜底的像素提示卡就永远不出现（R3c-02）。
            // 发出去之后读一次真实状态；已经被关了就补一张提示卡（之后的提醒直接走兜底，因为缓存已经更新）。
            refresh { [weak self] _ in
                guard let self = self, !self.systemAllowed, self.liveKeys.contains(key) else { return }
                self.toast.show(key: key, kind: kind, title: title, body: body)
            }
        } else {
            // 兜底：系统通知没授权 / 被拒 / 还没问过 → 自己的像素提示面板
            let t0 = DispatchTime.now().uptimeNanoseconds
            toast.show(key: key, kind: kind, title: title, body: body)
            if Prof.enabled { DebugTools.log(String(format: "toast.show %.1f ms", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)) }
        }
        let sk: SoundSynth.Kind
        switch kind { case .approval, .blocked: sk = .approval; case .question, .plan: sk = .question; case .finished, .info: sk = .finished; case .error: sk = .error }
        playSound(sk, sound)
    }

    func clear(key: String) {
        liveKeys.remove(key)
        toast.dismiss(key: key)
        if available { client.removeDelivered(key: key) }
    }

    // 前台时也显示横幅
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner]) }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
        if let k = r.notification.request.content.userInfo["buddyKey"] as? String { DispatchQueue.main.async { self.onClick?(k) } }
        h()
    }
}
