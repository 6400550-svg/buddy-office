import Foundation

/// 所有数据路径集中在这里，可以整体换根（`--data-root <目录>` 就是把 home 换成一个假的 home 树）。
///
/// 全部用 String 路径（POSIX），直接喂给 open / stat，不绕 URL。
public struct Paths: Sendable, Equatable {
    public let home: String

    public init(home: String) {
        // 去掉结尾的 /，避免拼出 "//"（先转成字节数组再从后往前数，O(n)；原来每次循环都 `count` 一遍，几万个斜杠就是 O(n²)）
        let b = Array(home.utf8)
        var end = b.count
        while end > 1, b[end - 1] == 0x2F { end -= 1 }
        self.home = end == b.count ? home : String(decoding: b[0..<end], as: UTF8.self)
    }

    /// 真实的 home。
    public static var real: Paths { Paths(home: NSHomeDirectory()) }

    // ~/.claude 下（只读）
    public var claudeDir: String { home + "/.claude" }
    /// 活会话登记表：`<pid>.json`（同目录的 `<pid>.<sha256>.key` 是密钥，绝不能打开）
    public var sessionsDir: String { claudeDir + "/sessions" }
    /// ccmon 的 hook 事件流
    public var monitorDir: String { claudeDir + "/.monitor" }
    /// 会话记录
    public var projectsDir: String { claudeDir + "/projects" }
    public var settingsFile: String { claudeDir + "/settings.json" }

    /// Claude 桌面 App 的会话元数据：`<acct>/<org>/local_<uuid>.json`
    public var desktopSessionsDir: String { home + "/Library/Application Support/Claude/claude-code-sessions" }

    // 本 App 自己的数据
    public var appSupportDir: String { home + "/Library/Application Support/BuddyOffice" }
    public var identitiesFile: String { appSupportDir + "/identities.json" }
    public var ledgerFile: String { appSupportDir + "/ledger.json" }

    /// sessionId 只允许 UUID 字符集（字母数字、-、_），防止登记表里的怪值拼出 `../` 之类的路径。
    public static func isSafeID(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 80 else { return false }
        for b in s.utf8 {
            let ok = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 95
            if !ok { return false }
        }
        return true
    }

    /// `~/.claude/.monitor/<sessionId>.events.jsonl`。只按登记表里的 sessionId 拼文件名，绝不扫描目录。
    public func hookLogPath(sessionId: String) -> String? {
        guard Paths.isSafeID(sessionId) else { return nil }
        return monitorDir + "/" + sessionId + ".events.jsonl"
    }

    /// 登记表文件名是否形如 `^\d+\.json$`（只有这种才允许打开）。
    public static func isRegistryFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(5)
        guard !stem.isEmpty, stem.utf8.count <= 10 else { return false }
        for b in stem.utf8 where b < 48 || b > 57 { return false }
        return true
    }
}
