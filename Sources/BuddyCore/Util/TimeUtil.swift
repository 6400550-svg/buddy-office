import Foundation

/// 不依赖 DateFormatter 的时间解析（线程安全、快、结果确定）。
public enum TimeUtil {
    /// 可信时间戳的范围（毫秒）：2000-01-01 … 2200-01-01。范围之外（含 NaN / 无穷 / 0 / 负数）一律当作坏数据：
    /// 外部文件里的时间戳一旦是天文数字，后面任何 `Int(…)` / `Int64(…)` 换算都会 trap（整个 App 崩掉），
    /// 而且一个远在未来的时间戳还会把"取最大值"的各种状态永远毒化。所以在解析的入口就挡掉。
    public static let saneMinMs: Double = 946_684_800_000
    public static let saneMaxMs: Double = 7_258_118_400_000

    public static func date(ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    /// 毫秒数 → Date；范围外返回 nil（见 `saneMinMs`）。
    public static func date(saneMs ms: Double) -> Date? {
        guard ms.isFinite, ms >= saneMinMs, ms < saneMaxMs else { return nil }
        return date(ms: ms)
    }

    /// Date → 毫秒（饱和：超出 Int64 的夹在两端，NaN 当 0；绝不 trap）。
    public static func millis(_ d: Date) -> Int64 {
        let v = d.timeIntervalSince1970 * 1000
        if v.isNaN { return 0 }
        if v >= 0x1p63 { return Int64.max }
        if v <= -0x1p63 { return Int64.min }
        return Int64(v.rounded())
    }

    /// 这个 NSNumber 是不是 JSON 的 true / false（`as? NSNumber` 会把布尔也当成数字，1 / 0）。
    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// 从 JSON 里取出的毫秒数（可能是 Int / Double / NSNumber）→ Date。布尔、范围外的数（见 `saneMinMs`）一律 nil。
    public static func date(fromJSONMillis v: Any?) -> Date? {
        guard let n = v as? NSNumber, !isBool(n) else { return nil }
        return date(saneMs: n.doubleValue)
    }

    // MARK: - ISO 8601（会话记录里的 timestamp："2026-09-29T04:12:39.255Z"）

    public static func parseISO(_ s: String) -> Date? {
        var s = s
        return s.withUTF8 { parseISO(bytes: $0) }
    }

    public static func parseISO(bytes: UnsafeBufferPointer<UInt8>) -> Date? {
        // 至少 "YYYY-MM-DDTHH:MM:SS"
        guard bytes.count >= 19 else { return nil }
        @inline(__always) func d2(_ i: Int) -> Int? {
            let a = Int(bytes[i]) - 48, b = Int(bytes[i + 1]) - 48
            guard a >= 0, a <= 9, b >= 0, b <= 9 else { return nil }
            return a * 10 + b
        }
        guard let c = d2(0), let yy = d2(2), bytes[4] == 45,
              let mo = d2(5), bytes[7] == 45, let dd = d2(8),
              bytes[10] == 84 || bytes[10] == 32,
              let hh = d2(11), bytes[13] == 58, let mi = d2(14), bytes[16] == 58, let ss = d2(17)
        else { return nil }
        let year = c * 100 + yy
        guard (1...12).contains(mo), (1...31).contains(dd), hh < 24, mi < 60, ss < 61 else { return nil }
        var idx = 19
        var fracMs = 0
        if idx < bytes.count, bytes[idx] == 46 {
            idx += 1
            var digits = 0
            while idx < bytes.count, bytes[idx] >= 48, bytes[idx] <= 57 {
                if digits < 3 { fracMs = fracMs * 10 + Int(bytes[idx] - 48); digits += 1 }
                idx += 1
            }
            while digits < 3 { fracMs *= 10; digits += 1 }
        }
        var offsetSec = 0
        if idx < bytes.count {
            let ch = bytes[idx]
            if ch == 43 || ch == 45 { // ±HH:MM / ±HHMM / ±HH
                guard bytes.count >= idx + 3, let oh = d2(idx + 1) else { return nil }
                var om = 0
                if bytes.count >= idx + 6, bytes[idx + 3] == 58 { om = d2(idx + 4) ?? 0 }
                else if bytes.count >= idx + 5 { om = d2(idx + 3) ?? 0 }
                offsetSec = (oh * 3600 + om * 60) * (ch == 45 ? -1 : 1)
            }
        }
        let days = daysFromCivil(year: year, month: mo, day: dd)
        let totalMs = (days * 86400 + hh * 3600 + mi * 60 + ss - offsetSec) * 1000 + fracMs
        // 毫秒整数 → 秒：和 hook 的 ts 换算方式一致；范围外（0000 年、9999 年之类的坏时间戳）当作没有
        return date(saneMs: Double(totalMs))
    }

    /// 公历日期 → 距 1970-01-01 的天数（Howard Hinnant 的算法）。
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    // MARK: - procStart（登记表：`"Tue Sep 29 03:23:08 2026"`，UTC；日期个位数时用空格补位）

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// 先把连续空白压成一个，再按 `EEE MMM d HH:mm:ss yyyy`（UTC）解析。
    public static func parseProcStart(_ raw: String) -> Date? {
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        var p = parts
        if p.count == 5 { p.removeFirst() }          // 去掉星期
        guard p.count == 4 else { return nil }
        // 年份必须在合理范围里（天文数字会让 daysFromCivil 里的乘法溢出 trap）；时分秒不许是负数
        guard let mo = months[String(p[0].lowercased().prefix(3))],
              let day = Int(p[1]), (1...31).contains(day),
              let year = Int(p[3]), year > 1970, year < 10_000 else { return nil }
        let t = p[2].split(separator: ":").compactMap { Int($0) }
        guard t.count == 3, (0..<24).contains(t[0]), (0..<60).contains(t[1]), (0..<61).contains(t[2]) else { return nil }
        let days = daysFromCivil(year: year, month: mo, day: day)
        return Date(timeIntervalSince1970: Double(days) * 86400 + Double(t[0] * 3600 + t[1] * 60 + t[2]))
    }
}

extension TimeUtil {
    /// 把 Date 夹在 0001-01-01 … 9999-12-31 之间（NaN 当 0）：格式化函数遇到极端日期也不会在 Int(…) 换算里 trap。
    static func clampedSeconds(_ d: Date) -> Double {
        let v = d.timeIntervalSince1970
        if v.isNaN { return 0 }
        return min(max(v, -62_135_596_800), 253_402_300_799)
    }

    /// 距 1970-01-01 的天数 → 公历（年, 月, 日）。
    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        var y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        if month <= 2 { y += 1 }
        return (y, month, day)
    }

    /// Date → `"Tue Sep  9 03:23:08 2026"`（UTC，日期个位数时用空格补位，和 `ps -o lstart` 一致）。测试和 replay 用。
    public static func formatProcStart(_ d: Date) -> String {
        let secs = Int(clampedSeconds(d))
        let days = Int(floor(Double(secs) / 86400))
        let rem = secs - days * 86400
        let (y, month, day) = civil(fromDays: days)
        let dow = ((days % 7) + 7 + 4) % 7          // 1970-01-01 是星期四
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return String(format: "%@ %@ %2ld %02ld:%02ld:%02ld %ld", names[dow], mons[month - 1], day,
                      rem / 3600, (rem / 60) % 60, rem % 60, y)
    }

    /// Date → `"2026-09-29T04:12:39.255Z"`（会话记录里的 timestamp 格式）。测试和 replay 用。
    public static func formatISO(_ d: Date) -> String {
        let ms = Int((clampedSeconds(d) * 1000).rounded())
        let secs = Int(floor(Double(ms) / 1000))
        let frac = ms - secs * 1000
        let days = Int(floor(Double(secs) / 86400))
        let rem = secs - days * 86400
        let (y, month, day) = civil(fromDays: days)
        return String(format: "%04ld-%02ld-%02ldT%02ld:%02ld:%02ld.%03ldZ", y, month, day, rem / 3600, (rem / 60) % 60, rem % 60, frac)
    }
}

extension Date {
    /// 调试输出用：HH:mm:ss.SSS（本地时区）。
    var debugClock: String {
        let secs = TimeUtil.clampedSeconds(self)
        var t = time_t(secs)
        var tmv = tm()
        localtime_r(&t, &tmv)
        let ms = Int((secs - floor(secs)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, ms)
    }
}
