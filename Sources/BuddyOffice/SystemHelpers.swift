import AppKit
import Carbon
import ServiceManagement
import BuddyCore

// MARK: - Dock 图标：角标 = 正在等你的人数；有新的人等你时弹一下
final class DockTileController {
    /// 和 AppKit 打交道的三件事（测试用假的记录调用，不碰真的 NSApp）。
    struct Env {
        var setBadge: (String?) -> Void
        var requestAttention: () -> Void
        var isAppActive: () -> Bool
        static let live = Env(setBadge: { NSApp.dockTile.badgeLabel = $0 },
                              requestAttention: { NSApp.requestUserAttention(.informationalRequest) },
                              isAppActive: { NSApp.isActive })
    }
    private let env: Env
    private var lastCount = 0
    init(env: Env = .live) { self.env = env }

    static func badgeLabel(waiting: Int) -> String? { waiting > 0 ? "\(waiting)" : nil }

    func update(waiting: Int, newlyWaiting: Bool) {
        if waiting != lastCount { env.setBadge(Self.badgeLabel(waiting: waiting)); lastCount = waiting }
        if newlyWaiting && !env.isAppActive() { env.requestAttention() }
    }
}

// MARK: - 自动收起：Claude 退出且没有活着的会话 → 60 秒后自己退出；期间有会话出现或 Claude 重新打开就取消
/// 只会退出「我们自己」（terminate 闭包默认是 NSApp.terminate）：绝不去退出用户的 Claude。
/// 时钟 / 通知中心 / 退出动作都可以注入（测试用假的）；「有没有活会话」由 AppModel 提供（被用户隐藏的 buddy 也算活着）。
final class AutoQuit {
    /// 定时器：seconds 秒后执行 block；返回取消闭包。
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    static let liveScheduler: Scheduler = { seconds, block in
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in block() }
        return { t.invalidate() }
    }
    /// Claude 退出之后等多久（任务书 7.4）。
    static let delayAfterClaudeQuits: TimeInterval = 60

    var isEnabled: () -> Bool = { true }
    var hasLiveSessions: () -> Bool = { false }
    private let center: NotificationCenter
    private let scheduler: Scheduler
    private let terminate: () -> Void
    private let log: (String) -> Void
    private var cancelPending: (() -> Void)?
    var isScheduled: Bool { cancelPending != nil }

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter, scheduler: @escaping Scheduler = AutoQuit.liveScheduler,
         terminate: @escaping () -> Void = { NSApp.terminate(nil) }, log: @escaping (String) -> Void = { DebugTools.log($0) }) {
        self.center = center; self.scheduler = scheduler; self.terminate = terminate; self.log = log
    }

    func start() {
        center.addObserver(self, selector: #selector(terminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(launched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    }
    private static func bundleID(of n: Notification) -> String? { (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier }
    @objc private func terminated(_ n: Notification) { appTerminated(bundleID: Self.bundleID(of: n)) }
    @objc private func launched(_ n: Notification) { appLaunched(bundleID: Self.bundleID(of: n)) }

    /// 某个 App 退出了：是 Claude 桌面 App、开关开着 → 60 秒后判断要不要退出。
    func appTerminated(bundleID: String?) {
        guard bundleID == JumpService.claudeBundleID, isEnabled() else { return }
        scheduleQuit(after: Self.delayAfterClaudeQuits)
    }
    /// Claude 重新打开了：取消。
    func appLaunched(bundleID: String?) { if bundleID == JumpService.claudeBundleID { cancel() } }

    /// seconds 秒之后，如果开关还开着、并且没有任何活会话（含被隐藏的），就退出自己；期间 Claude 重新打开会取消（appLaunched）。
    func scheduleQuit(after seconds: TimeInterval) {
        cancelPending?()
        cancelPending = scheduler(seconds) { [weak self] in
            guard let self = self else { return }
            self.cancelPending = nil
            guard self.isEnabled(), !self.hasLiveSessions() else { self.log("autoquit: 条件不满足（开关关了或还有会话），不退出"); return }
            self.log("autoquit: 没有会话了，退出")
            self.terminate()
        }
    }
    func cancel() { cancelPending?(); cancelPending = nil }
}

// MARK: - 全局快捷键 ⌃⌥⌘B（Carbon RegisterEventHotKey，不需要辅助功能权限）
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onFire: (() -> Void)?
    private static var current: HotKey?

    func register() {
        unregister()
        HotKey.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let hs = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in HotKey.current?.onFire?(); return noErr }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x42444F46), id: 1)          // 'BDOF'
        let rs = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        // -9878 = 这个组合键已经被别的 App 占了；这种情况下开关不生效，但不影响其余功能
        DebugTools.log("hotkey: ⌃⌥⌘B 注册\(hs == noErr && rs == noErr ? "成功" : "失败（handler \(hs)，hotkey \(rs)）")")
    }
    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }
}

// MARK: - 开机启动：先试 SMAppService，不行（ad-hoc 签名下状态是 notFound）就写 LaunchAgent
enum LoginItem {
    static var agentURL: URL { URL(fileURLWithPath: NSHomeDirectory() + "/Library/LaunchAgents/local.buddy-office.plist") }

    /// register() 之后的状态 → 给用户的说明；nil = 这条路没成（改用 LaunchAgent）。
    static func note(afterRegister status: SMAppService.Status) -> String? {
        switch status {
        case .enabled: return "已用登录项开启"
        case .requiresApproval: return "已提交登录项，还需要在「系统设置 → 通用 → 登录项与扩展」里允许"      // 原来也说「已开启」，其实还没生效
        default: return nil
        }
    }
    /// 开关该显示成开还是关：开启失败（说明是「开启失败：…」）时回退成关；原来失败了开关仍显示开。
    static func switchState(requested on: Bool, note: String) -> Bool { on && !note.hasPrefix("开启失败") }

    static func set(_ on: Bool) -> (note: String, isOn: Bool) {
        let note = apply(on)
        return (note, switchState(requested: on, note: note))
    }

    private static func apply(_ on: Bool) -> String {
        if on {
            do {
                try SMAppService.mainApp.register()
                if let n = note(afterRegister: SMAppService.mainApp.status) { return n }
            } catch { /* 改用 LaunchAgent */ }
            let plist: [String: Any] = ["Label": "local.buddy-office", "ProgramArguments": ["/usr/bin/open", "-g", "-b", "local.buddy-office"], "RunAtLoad": true]
            do {
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: agentURL)
                return "已用 LaunchAgent 开启"
            } catch { return "开启失败：\(error.localizedDescription)" }
        } else {
            try? SMAppService.mainApp.unregister()
            try? FileManager.default.removeItem(at: agentURL)
            return "已关闭"
        }
    }
    static var isOn: Bool { SMAppService.mainApp.status == .enabled || FileManager.default.fileExists(atPath: agentURL.path) }
}
