import Foundation
import BuddyCore

/// A-012：主线程上的「同步等后台队列」（退出时 provider.stop() → queue.sync → 当前一次 poll + token 扫描 + 写盘；最坏约等于一个大文件的扫描批次）
/// 不能无限等：放到后台跑，主线程最多等 timeout 秒。
enum BoundedWait {
    /// 在后台队列上跑 work，最多等 timeout 秒；超时返回 false（work 还会在后台继续跑，调用方接着往下走，比如进程马上就退出了）。
    @discardableResult
    static func run(timeout: TimeInterval, _ work: @escaping () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { work(); done.signal() }
        return done.wait(timeout: .now() + timeout) == .success
    }
}

/// 「数据源诊断」页的文字（纯函数：拿到数据层的诊断信息 + 主线程上读到的通知 / 深链状态）。
enum DiagnosticsFormatter {
    static func text(_ d: DiagnosticsInfo, notifierStatus: String, deepLinkDisabled: Bool, deepLinkFailures: Int, privacy: Bool = false) -> String {
        var lines = ["活会话数：\(d.liveSessionCount)"]
        lines.append("ccmon hook：\(d.hookDetectedInSettings ? "已在 settings.json 里注册" : "没有检测到")\(d.lastHookEventAt.map { "，最后一个事件 " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "")")
        for s in d.sessions { lines.append("· \(privacy ? "会话" : s.title)　pid \(s.pid.map(String.init) ?? "-")　v\(s.cliVersion ?? "?")　hook \(s.hookActive ? "有" : "无")") }
        lines.append("系统通知：\(notifierStatus)")
        lines.append("深链：\(deepLinkDisabled ? "已停用（连续 \(deepLinkFailures) 次没生效）" : "可用")")
        lines.append("数据来源：")
        lines += d.sourceStatus.map { "　" + $0 }
        return lines.joined(separator: "\n")
    }
}
