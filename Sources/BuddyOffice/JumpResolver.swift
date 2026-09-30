import Foundation
import BuddyCore

/// 点 buddy → 跳到哪个会话：座位号 / key → 快照 → 跳转目标。纯函数，不碰 AppKit（JumpService 只负责执行）。
enum JumpTarget: Equatable {
    /// 桌面 App 会话：深链 claude://code/(needs-input|continue)?session=<hostSessionId>
    case desktopDeepLink(host: String, url: URL)
    /// 深链不可用（连续失败被停用 / host id 不合法）：直接激活 Claude
    case activateClaude
    case vscode(cwd: String?)
    case terminal(pid: Int32)
    /// Codex 线程：深链 codex://threads/<线程 id>（Codex 桌面 App 自己的链接）
    case codexThread(url: URL)
    /// 跳不了（比如终端会话没有 pid）
    case none
}

enum JumpResolver {
    /// 点座位号 seat：只认「在场（present）」的会话——下班工位 / 空座位 / 悬空的座位号点了什么都不发生。
    static func snapshot(forSeat seat: Int, in snapshots: [BuddySnapshot]) -> BuddySnapshot? {
        snapshots.first { $0.seat == seat && $0.presence == .present }
    }

    /// 按 key 找最新的那份快照（提示卡 / 通知 / 菜单栏 / 小鱼缸 / 宠物条拿到的是「那一刻」的快照，会话已经走了或换了座位就以现在的为准）；已经不在场就没有。
    static func snapshot(forKey key: String, in snapshots: [BuddySnapshot]) -> BuddySnapshot? {
        snapshots.first { $0.key == key && $0.presence == .present }
    }

    static func validHostID(_ s: String) -> Bool { JumpService.validHostID(s) }

    static func deepLinkURL(host: String, needsInput: Bool) -> URL? {
        guard validHostID(host) else { return nil }
        return URL(string: "claude://code/\(needsInput ? "needs-input" : "continue")?session=\(host)")
    }

    /// codex://threads/<线程 id>：id 必须是 UUID（拼进链接之前守一道）。
    static func codexURL(threadId: String) -> URL? {
        guard CodexNames.isUUID(threadId) else { return nil }
        return URL(string: "codex://threads/\(threadId)")
    }

    static func target(for s: BuddySnapshot, deepLinkDisabled: Bool) -> JumpTarget {
        switch s.origin {
        case .desktop:
            guard let host = s.hostSessionId, !deepLinkDisabled, let url = deepLinkURL(host: host, needsInput: s.activity.needsUser) else { return .activateClaude }
            return .desktopDeepLink(host: host, url: url)
        case .vscode:
            return .vscode(cwd: (s.cwd?.isEmpty ?? true) ? nil : s.cwd)
        case .terminal:
            return s.pid.map { .terminal(pid: $0) } ?? .none
        case .codex:
            return codexURL(threadId: s.sessionId).map { .codexThread(url: $0) } ?? .none
        }
    }

    /// 点通知 / 提示卡：合并提醒（「N 位同事在等你」）没有对应的会话 → 打开办公室；认得的 key → 跳；会话已经走了 → 什么都不做。
    enum NotificationClick: Equatable { case openOffice, jump(String), nothing }
    static func notificationClick(key: String, in snapshots: [BuddySnapshot]) -> NotificationClick {
        if key == AlertCoordinator.multiKey { return .openOffice }
        return snapshot(forKey: key, in: snapshots) != nil ? .jump(key) : .nothing
    }

    /// 深链发出后 2.5 秒的判定（M0 实测：目标本来就是最近聚焦的会话时 lastFocusedAt 不会变，那不算失败；
    /// 但这时候深链有没有把 Claude 带到前台没法从 lastFocusedAt 看出来，所以 Claude 不在最前面就补一次激活）。
    struct DeepLinkVerdict: Equatable { var succeeded: Bool; var activateClaude: Bool }
    static func deepLinkVerdict(wasLatest: Bool, before: Double?, after: Double?, claudeFrontmost: Bool) -> DeepLinkVerdict {
        let changed = (after != nil && before != nil && after! > before!) || (before == nil && after != nil)
        if changed { return DeepLinkVerdict(succeeded: true, activateClaude: false) }
        if wasLatest { return DeepLinkVerdict(succeeded: true, activateClaude: !claudeFrontmost) }
        return DeepLinkVerdict(succeeded: false, activateClaude: true)
    }

    /// 终端跳转脚本要用的 tty：只认 /dev/tty… 设备名（来自 sysctl + devname，本来就不含引号 / 换行；这里再守一道，脚本里是字符串插值）。
    static func isValidTTY(_ tty: String) -> Bool { tty.range(of: #"^/dev/tty[A-Za-z0-9]{1,16}$"#, options: .regularExpression) != nil }

    /// 在 Terminal 里按 tty 选中标签页的 AppleScript；tty 不合法返回 nil。整段包在 with timeout 里：自动化授权弹窗没人答复时不会卡满 2 分钟。
    static let scriptTimeoutSeconds = 5
    static func terminalTabScript(tty: String) -> String? {
        guard isValidTTY(tty) else { return nil }
        return """
        with timeout of \(scriptTimeoutSeconds) seconds
          tell application "Terminal"
            repeat with w in windows
              repeat with tb in tabs of w
                if (tty of tb) is "\(tty)" then
                  set selected of tb to true
                  set miniaturized of w to false
                  set index of w to 1
                  activate
                  return "found"
                end if
              end repeat
            end repeat
            return "notfound"
          end tell
        end timeout
        """
    }
}
