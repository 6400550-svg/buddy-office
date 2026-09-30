import AppKit
import BuddyCore

/// 点 buddy → 跳到那个会话（任务书 7.3）。
///  · 桌面 App 会话：深链 claude://code/(needs-input|continue)?session=<hostSessionId>（未公开的内部链接，
///    2.5 s 内 lastFocusedAt 没变就当失败、改为直接激活 Claude，连续失败 2 次后停用深链）；
///  · 终端会话：沿父进程链找宿主 App；Terminal 用 osascript 按 tty 选中标签页；其余直接激活宿主 App；
///  · VS Code：用它打开 cwd。
///  · 激活一律用 NSWorkspace.openApplication(at:configuration:)（activates = true）：协作式激活下 NSRunningApplication.activate() 会悄悄失败（M0 实测）。
final class JumpService {
    static let shared = JumpService()
    /// 查宿主 App / 读 tty（sysctl，很快）和跑 AppleScript 分成两条队列：脚本卡在自动化授权弹窗上（最长约 2 分钟）时不拖住别的终端跳转。
    private let queue = DispatchQueue(label: "jump", qos: .userInitiated)
    private let scriptQueue = DispatchQueue(label: "jump.script", qos: .userInitiated)
    private(set) var deepLinkFailures = 0
    private(set) var deepLinkDisabled = false
    /// 给用户看的一条说明（标题 + 一句话；提示卡单行放不下就会被省略号截掉，所以要短）。
    var onNotice: ((_ title: String, _ body: String) -> Void)?
    static let claudeBundleID = "com.anthropic.claudefordesktop"
    static let codexBundleID = "com.openai.codex"
    /// 深链连续失败 2 次后停用，给用户的说明（提示卡单行最宽 220 pt：标题 12 pt、正文 11 pt，两行都必须放得下——有测试量过）。
    static let deepLinkDisabledNotice = (title: "深链跳转没有生效", body: "已改为直接打开 Claude，可在设置里重试")

    static func validHostID(_ s: String) -> Bool {
        s.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil
    }

    func jump(to s: BuddySnapshot) {
        switch JumpResolver.target(for: s, deepLinkDisabled: deepLinkDisabled) {
        case .desktopDeepLink(let host, let url): jumpDesktop(host: host, url: url)
        case .activateClaude: activateClaude()
        case .vscode(let cwd): jumpVSCode(cwd: cwd)
        case .terminal(let pid): jumpTerminal(pid: pid)
        case .codexThread(let url): NSWorkspace.shared.open(url)
        case .none: break
        }
    }

    // MARK: 桌面 App
    private func jumpDesktop(host: String, url: URL) {
        let all = DesktopMeta.readAll()                                    // 一次读完：跳之前 lastFocusedAt 和「是不是最近聚焦的」都从这里取
        let before = all[host]
        let wasLatest = DesktopMeta.mostRecentHost(all) == host
        NSWorkspace.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            let after = DesktopMeta.readAll()[host]
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.claudeBundleID
            let v = JumpResolver.deepLinkVerdict(wasLatest: wasLatest, before: before, after: after, claudeFrontmost: frontmost)
            if v.succeeded { self.deepLinkFailures = 0 } else { self.deepLinkFailures += 1 }
            if v.activateClaude { self.activateClaude() }
            if self.deepLinkFailures >= 2 && !self.deepLinkDisabled {
                self.deepLinkDisabled = true
                self.onNotice?(Self.deepLinkDisabledNotice.title, Self.deepLinkDisabledNotice.body)
            }
        }
    }

    func resetDeepLink() { deepLinkFailures = 0; deepLinkDisabled = false }

    func activateClaude() { activate(bundleID: Self.claudeBundleID) }

    func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        activate(appAt: url)
    }
    func activate(appAt url: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }

    // MARK: VS Code
    private func jumpVSCode(cwd: String?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else { return }
        if let cwd = cwd {
            let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: url, configuration: cfg, completionHandler: nil)
        } else { activate(appAt: url) }
    }

    // MARK: 终端
    private func jumpTerminal(pid: Int32) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let host = self.hostApp(of: pid)
            let tty = ProcessInfoHelper.ttyName(of: pid)
            DispatchQueue.main.async {
                guard let app = host, let url = app.bundleURL else { return }
                if app.bundleIdentifier == "com.apple.Terminal", let tty = tty {
                    self.selectTerminalTab(tty: tty) { self.activate(appAt: url) }
                } else { self.activate(appAt: url) }
            }
        }
    }

    /// 沿父进程链往上找宿主 App（最多 12 层）；跳过 bundle id 是 com.anthropic.claude-code 的 CLI 包，也跳过纯后台的 App。
    func hostApp(of pid: Int32) -> NSRunningApplication? {
        var cur = pid
        for _ in 0..<12 {
            guard let ppid = ProcessInfoHelper.parent(of: cur), ppid > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: ppid),
               app.activationPolicy == .regular, app.bundleIdentifier != "com.anthropic.claude-code" { return app }
            cur = ppid
        }
        return nil
    }

    func selectTerminalTab(tty: String, then: @escaping () -> Void) {
        guard let src = JumpResolver.terminalTabScript(tty: tty) else { DispatchQueue.main.async(execute: then); return }
        scriptQueue.async {
            var err: NSDictionary?
            _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
            if let e = err { NSLog("%@", "BuddyOffice: 终端跳转 AppleScript 出错 \(e)") }       // 不能把插值后的字符串当格式串（里面有 % 时 NSLog 会去读不存在的参数）
            DispatchQueue.main.async(execute: then)
        }
    }
}

/// 用 sysctl 读进程信息（在沙箱里可能失败，调用方要容忍 nil）。
enum ProcessInfoHelper {
    static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let r = mib.withUnsafeMutableBufferPointer { sysctl($0.baseAddress, 4, &info, &size, nil, 0) }
        return (r == 0 && size > 0) ? info : nil
    }
    static func parent(of pid: Int32) -> Int32? { kinfo(pid).map { $0.kp_eproc.e_ppid } }
    static func ttyName(of pid: Int32) -> String? {
        guard let k = kinfo(pid) else { return nil }
        let dev = k.kp_eproc.e_tdev
        if dev == UInt32.max || dev == 0 { return nil }
        guard let c = devname(dev_t(dev), mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: c)
    }
}

/// 桌面 App 的会话元数据（~/Library/Application Support/Claude/claude-code-sessions/<acct>/<org>/local_<uuid>.json）。
enum DesktopMeta {
    /// 测试用：把桌面元数据目录换成一个假的（nil = 真实的 ~/Library/Application Support/Claude/claude-code-sessions）。
    nonisolated(unsafe) static var baseOverride: String? = nil
    static var base: String { baseOverride ?? NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions" }
    /// 读目录 / 读文件都走 BuddyCore 的 FileIO 统一入口（它拒绝 `*.key` / `*.sock`、命名管道、符号链接绕过，并限制文件大小）——
    /// 之前这里直接用 FileManager，虽然文件名过滤本身碰不到 .key，但和「所有读都经 FileIO」的约定不一致（QA C-032）。
    static func files() -> [String] {
        var out: [String] = []
        for a in FileIO.listDirectory(base) ?? [] {
            for o in FileIO.listDirectory(base + "/" + a) ?? [] {
                let dir = base + "/" + a + "/" + o
                for f in FileIO.listDirectory(dir) ?? [] where f.hasPrefix("local_") && f.hasSuffix(".json") { out.append(dir + "/" + f) }
            }
        }
        return out
    }
    static func lastFocused(path: String, now: Date = Date()) -> Double? {
        guard let d = FileIO.readAll(path), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        guard let v = j["lastFocusedAt"] as? Double, v.isFinite else { return nil }
        // 比现在晚一天以上（桌面 App 的时钟被拨快过 / 坏数据）：没有意义，当作没有——不然这个会话永远是「最近聚焦的」：
        // 它的等批准 / 做完了被当成「你一直在看」而不提醒，真正在看的那个会话反而照样弹提示卡（R4a-01；引擎侧 `DesktopMetaReader.clampingFuture` 同一个取向）
        return v > now.timeIntervalSince1970 * 1000 + 86_400_000 ? nil : v
    }
    /// 全部会话的 lastFocusedAt：hostSessionId（= 文件名去掉 .json）→ 毫秒时间戳。
    static func readAll() -> [String: Double] {
        var out: [String: Double] = [:]
        for f in files() { if let v = lastFocused(path: f) { out[((f as NSString).lastPathComponent as NSString).deletingPathExtension] = v } }
        return out
    }
    /// lastFocusedAt 最新的那个会话（并列时取 id 字典序最小的，结果是确定的）。
    static func mostRecentHost(_ all: [String: Double]) -> String? {
        all.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
    static func lastFocusedAt(host: String) -> Double? { readAll()[host] }
    static func isMostRecentlyFocused(host: String) -> Bool { mostRecentHost(readAll()) == host }

    /// 提醒判定（每个 tick 都可能问）用的带缓存的版本：maxAge 秒内直接用上一次读的（原来每次都重新列目录、读并解析全部 local_*.json，主线程上 3–8 ms）。
    final class Cache {
        private let read: () -> [String: Double]
        private let clock: () -> TimeInterval
        private let maxAge: TimeInterval
        private var stamp: TimeInterval?
        private var value: [String: Double] = [:]
        init(maxAge: TimeInterval = 1, read: @escaping () -> [String: Double] = DesktopMeta.readAll, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.maxAge = maxAge; self.read = read; self.clock = clock
        }
        func all() -> [String: Double] {
            let now = clock()
            if let s = stamp, now - s < maxAge, now >= s { return value }
            value = read(); stamp = now
            return value
        }
        func isMostRecentlyFocused(host: String) -> Bool { DesktopMeta.mostRecentHost(all()) == host }
    }
    static let cache = Cache()
}
