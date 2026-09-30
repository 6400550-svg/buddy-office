import Foundation

extension Notification.Name { static let settingsChanged = Notification.Name("BuddyOffice.settingsChanged") }

/// 全部配置项（UserDefaults；键名见任务书 7.5）。改了就发 .settingsChanged。
final class Settings {
    static let shared = Settings()
    private let d: UserDefaults
    /// defaults 默认是标准偏好设置；测试传一个私有的 suite（不碰用户真实的偏好文件）。
    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            "office.visible": true, "office.zoom": 0,
            "tank.visible": false, "tank.zoom": 2, "tank.opacity": 1.0,
            "strip.visible": false, "strip.zoom": 2, "strip.screen": "main", "strip.align": "right", "strip.level": "floating", "strip.fullscreen": false,
            "ui.menuBarIcon": true, "ui.dockIcon": true, "ui.labels": "always",
            "notify.permission": true, "notify.question": true, "notify.finished": true, "notify.finishedMinSeconds": 30,
            "notify.includeDesktop": true, "notify.suppressWhenFocused": true, "notify.sound": "8bit", "notify.error": false,
            "idle.dozeMinutes": 10, "idle.sleepMinutes": 45,
            "dormant.max": 4, "dormant.recentHours": 3,
            "codex.enabled": true,
            "privacy.hideDetails": false, "autoQuitWithClaude": true, "login.enabled": false, "hotkey.enabled": false,
            "hidden.keys": [String](),
        ])
    }
    private func post() { NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    // 偏好设置文件可以被手改 / 写坏：带范围的数值项读取时统一夹进合法范围（设置页的控件本来就限制在这些范围里），
    // 所有消费者都不用自己再防（`prefix(-1)`、`0..<负数`、缩放 99……都是运行时陷阱）。
    static let intRanges: [String: ClosedRange<Int>] = [
        "office.zoom": 0...5, "tank.zoom": 1...2, "strip.zoom": 1...3,
        "notify.finishedMinSeconds": 5...600,
        "idle.dozeMinutes": 1...120, "idle.sleepMinutes": 2...240,
        "dormant.max": 0...8, "dormant.recentHours": 1...24,
    ]
    static let doubleRanges: [String: ClosedRange<Double>] = ["tank.opacity": 0.3...1.0]
    static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { max(r.lowerBound, min(r.upperBound, v)) }
    /// NaN 取上界（不透明度这类「满」是安全的默认）；±∞ 自然夹到两端。
    static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isNaN ? r.upperBound : max(r.lowerBound, min(r.upperBound, v)) }

    func bool(_ k: String) -> Bool { d.bool(forKey: k) }
    func int(_ k: String) -> Int { let v = d.integer(forKey: k); return Self.intRanges[k].map { Self.clamp(v, $0) } ?? v }
    func double(_ k: String) -> Double { let v = d.double(forKey: k); return Self.doubleRanges[k].map { Self.clamp(v, $0) } ?? v }
    func string(_ k: String) -> String { d.string(forKey: k) ?? "" }
    func set(_ v: Any, _ k: String) { d.set(v, forKey: k); post() }
    var hiddenKeys: Set<String> {
        get { Set(d.stringArray(forKey: "hidden.keys") ?? []) }
        set { d.set(Array(newValue), forKey: "hidden.keys"); post() }
    }

    // 今日完成的轮数（白板上的「正」字）：按天存，App 自己观察到的「正常做完」次数。白板最多画 15 个「正」字，存的值夹在 0…9999（被写成负数 / 天文数字时 drawTally 和 + 1 都会陷阱）。
    static let tallyRange = 0...9_999
    private var tallyCache: (stamp: TimeInterval, day: String, value: Int) = (0, "", 0)
    func tallyToday() -> Int {
        // 每帧都会问：一秒内直接用缓存（跨天也最多晚一秒）
        let now = Date().timeIntervalSinceReferenceDate
        if now - tallyCache.stamp < 1 { return tallyCache.value }
        let day = Self.dayString()
        let v = Self.clamp(d.integer(forKey: "tally.\(day)"), Self.tallyRange)
        tallyCache = (now, day, v)
        return v
    }
    func addTally() {
        let key = "tally.\(Self.dayString())"
        let v = Self.clamp(Self.clamp(d.integer(forKey: key), Self.tallyRange) + 1, Self.tallyRange)        // 先夹再加：存的是 Int.max 时 + 1 会溢出
        d.set(v, forKey: key)
        tallyCache = (Date().timeIntervalSinceReferenceDate, Self.dayString(), v)
    }
    /// 白板计数每天一个键（tally.YYYY-MM-DD）永远不清理：启动时把 keepDays 天之前的（和认不出日期的）删掉。
    static func staleTallyKeys(_ keys: [String], now: Date = Date(), keepDays: Int = 30) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        let f = makeDayFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: .autoupdatingCurrent)
        return keys.filter { k in
            guard k.hasPrefix("tally.") else { return false }
            guard let d = f.date(from: String(k.dropFirst(6))) else { return true }
            return d < cutoff
        }.sorted()
    }
    func pruneOldTallies(now: Date = Date()) {
        for k in Self.staleTallyKeys(Array(d.dictionaryRepresentation().keys), now: now) { d.removeObject(forKey: k) }
    }
    /// 日期键永远是公历 yyyy-MM-dd（不跟用户的历法 / 语言走：佛历、日本年号下 yyyy 是另一个年份，键一变当天计数就从 0 重新开始）；时区跟随系统（跨时区旅行后也对）。
    private static func makeDayFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = Calendar(identifier: .gregorian)          // 放在 locale 之后：显式指定的公历不被 locale 的历法盖掉
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
    private static let dayFormatter = makeDayFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: .autoupdatingCurrent)
    static func dayString(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }
    /// 测试用：指定 locale / 时区的日期串（不缓存）。
    static func dayString(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        makeDayFormatter(locale: locale, timeZone: timeZone).string(from: date)
    }
}
