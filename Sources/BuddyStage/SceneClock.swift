import Foundation
import BuddyArt

/// 场景用的时钟量（光照状态、钟点、几号），一秒只算一次：Calendar 很慢，冷启动时更慢，而这些量一秒内不会变。
/// 只在主线程用（三个显示面共用同一份缓存）。
public enum SceneClock {
    public struct Reading { public var light: LightState; public var hour: Double; public var day: Int }
    nonisolated(unsafe) static var sec = Int.min
    nonisolated(unsafe) static var cached = Reading(light: LightState(a: .day), hour: 12, day: 1)
    private static let lock = NSLock()

    /// hour 只精确到分钟：钟、太阳、天色一分钟内肉眼看不出变化，动态部分的指纹一分钟才变一次。
    public static func at(_ now: Date) -> Reading {
        let s = Int(now.timeIntervalSinceReferenceDate.rounded(.down))
        lock.lock(); defer { lock.unlock() }
        if s != sec {
            let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second, .day], from: now)          // 跟着系统时区变（跑好几天 + 跨时区旅行时，Calendar.current 的快照可能还是旧时区）
            let h = Double(c.hour ?? 12), m = Double(c.minute ?? 0), sc = Double(c.second ?? 0)
            cached = Reading(light: DaySchedule.state(atHour: h + m / 60 + sc / 3600), hour: h + m / 60, day: c.day ?? 1)
            sec = s
        }
        return cached
    }
}
