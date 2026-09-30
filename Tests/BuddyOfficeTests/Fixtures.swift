import Foundation
import BuddyCore
@testable import BuddyOffice

/// 测试夹具：造快照、造隔离的 Settings（私有 suite，不碰用户真实的偏好文件）。
enum Fx {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func snap(_ key: String, seat: Int = 0, origin: SessionOrigin = .terminal, activity: Activity = .idle,
                     title: String? = nil, host: String? = nil, pid: Int32? = nil, now: Date = base) -> BuddySnapshot {
        var s = BuddySnapshot(key: key, seat: seat, salt: 1, title: title ?? "会话 \(key)", sessionId: key, origin: origin, activity: activity, now: now)
        s.hostSessionId = host; s.pid = pid
        return s
    }

    /// 下班工位（away + dormant）；since 越晚越「新鲜」。
    static func dormant(_ key: String, seat: Int, since: Date = base) -> BuddySnapshot {
        var s = snap(key, seat: seat, origin: .desktop, host: "local_" + key)
        s.presence = .away(since: since, dormant: true)
        return s
    }

    static func call(_ name: String, _ detail: String = "", at: Date = base) -> ToolCall { ToolCatalog.makeCall(name: name, detail: detail, at: at) }

    /// 私有 suite 的 Settings；用完调 cleanUp()。
    /// suite 名用临时目录里的绝对路径（UserDefaults 把它当成 plist 文件路径）：偏好文件落在临时目录、cleanUp 时删掉，
    /// 不会在用户的 ~/Library/Preferences 里留下一堆 local.buddy-office.tests.<UUID>.plist。
    final class Store {
        let suite = NSTemporaryDirectory() + "buddy-office-tests-" + UUID().uuidString
        let defaults: UserDefaults
        let settings: Settings
        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = Settings(defaults: defaults)
        }
        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(atPath: suite + ".plist")
        }
    }
    static func withSettings<T>(_ body: (Settings, UserDefaults) throws -> T) rethrows -> T {
        let st = Store()
        defer { st.cleanUp() }
        return try body(st.settings, st.defaults)
    }
}
