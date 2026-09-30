import Foundation
import PixelKit

public enum TimeOfDay: Int, Sendable, CaseIterable { case dawn, day, dusk, night }

/// 时段光照状态：从时段 a 过渡到时段 b，progress 0…1；白天黑夜切换用 4×4 Bayer 抖动，每个像素只翻转一次。
public struct LightState: Equatable, Sendable {
    public var a: TimeOfDay
    public var b: TimeOfDay
    /// 已量化到 1/16（Bayer 的级数），所以缓存键稳定。
    public var level: Int
    public init(a: TimeOfDay, b: TimeOfDay? = nil, level: Int = 0) { self.a = a; self.b = b ?? a; self.level = max(0, min(16, level)) }
    public var progress: Double { Double(level) / 16 }
    public var isTransitioning: Bool { a != b && level > 0 && level < 16 }
    /// 台灯 / 屏幕是否要亮（夜里、黄昏、黎明更明显）。
    public var darkness: Double {
        func d(_ t: TimeOfDay) -> Double { switch t { case .day: return 0; case .dawn: return 0.35; case .dusk: return 0.45; case .night: return 1 } }
        return d(a) * (1 - progress) + d(b) * progress
    }
}

/// 一天里几点换哪一张 LUT（本地时间，小时为单位的小数）。过渡用 20 分钟。
public enum DaySchedule {
    public static let transitionMinutes = 20.0
    // (开始过渡的钟点, 从, 到)
    static let steps: [(Double, TimeOfDay, TimeOfDay)] = [
        (5.5, .night, .dawn), (6.667, .dawn, .day), (17.5, .day, .dusk), (18.833, .dusk, .night),
    ]
    public static func state(atHour h: Double) -> LightState {
        let hour = (h.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let span = transitionMinutes / 60
        for (start, from, to) in steps where hour >= start && hour < start + span {
            let p = (hour - start) / span
            return LightState(a: from, b: to, level: Int((p * 16).rounded(.down)))
        }
        // 不在过渡里：看最近一次过渡之后是什么时段
        var current: TimeOfDay = .night
        for (start, _, to) in steps where hour >= start + span { current = to }
        if hour < steps[0].0 { current = .night }
        return LightState(a: current)
    }
    public static func state(at date: Date, calendar: Calendar = .current) -> LightState {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return state(atHour: Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600)
    }
}

/// 五张 LUT。
public struct LightLUTs: Sendable {
    public let day: PaletteLUT
    public let dawn: PaletteLUT
    public let dusk: PaletteLUT
    public let night: PaletteLUT
    public let lamp: PaletteLUT
    /// 天花板灯在地上的光斑：只提亮，不改色相（暖色台灯光圈落在蓝地毯上会变成橙灰色噪点）。
    public let ceiling: PaletteLUT
    public func lut(_ t: TimeOfDay) -> PaletteLUT {
        switch t { case .day: return day; case .dawn: return dawn; case .dusk: return dusk; case .night: return night }
    }
}

public enum Lighting {
    public static let luts: LightLUTs = {
        let m = Pal.master
        func tint(_ c: RGBA8, mul: (Double, Double, Double), add: (Double, Double, Double) = (0, 0, 0), sat: Double = 1) -> RGBA8 {
            var r = Double(c.r), g = Double(c.g), b = Double(c.b)
            let y = 0.299 * r + 0.587 * g + 0.114 * b
            r = y + (r - y) * sat; g = y + (g - y) * sat; b = y + (b - y) * sat
            r = r * mul.0 + add.0; g = g * mul.1 + add.1; b = b * mul.2 + add.2
            func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
            return RGBA8(q(r), q(g), q(b), c.a)
        }
        let day = PaletteLUT.identity(m)
        let dawn = PaletteLUT.make(from: m) { _, c in tint(c, mul: (0.97, 0.90, 0.92), add: (10, 3, 4), sat: 0.94) }
        let dusk = PaletteLUT.make(from: m) { _, c in tint(c, mul: (0.98, 0.83, 0.70), add: (12, 2, -2), sat: 0.98) }
        // 夜里天花板灯亮着，所以不是漆黑：整体压暗、偏蓝，但暗部仍然读得清
        let night = PaletteLUT.make(from: m) { _, c in tint(c, mul: (0.60, 0.66, 0.86), add: (5, 8, 20), sat: 0.85) }
        // 台灯 / 天花板灯光圈：相对夜晚提亮、偏暖，但仍比白天暗一些（光圈是「夜里被照亮」，不是「比白天还亮」）
        let lamp = PaletteLUT.make(from: m) { _, c in tint(c, mul: (0.90, 0.82, 0.68), add: (14, 8, 0), sat: 0.95) }
        let ceiling = PaletteLUT.make(from: m) { _, c in tint(c, mul: (0.72, 0.78, 0.98), add: (8, 8, 14), sat: 0.9) }
        return LightLUTs(day: day, dawn: dawn, dusk: dusk, night: night, lamp: lamp, ceiling: ceiling)
    }()

    /// 给某个光照状态建一份 Resolved（同一个 buddy、同一个状态可以缓存复用）。
    public static func resolved(map: RoleMap?, state: LightState, glow: RGBA8? = nil, glowAmount: Double = 0.5,
                                reflectBase: UInt8 = Role.hairHi) -> Resolved {
        Resolved(map: map, lutA: luts.lut(state.a), lutB: luts.lut(state.b), progress: state.progress,
                 glow: glow, glowAmount: glowAmount, reflectBase: reflectBase)
    }

    // 每帧每个工位要用到好几份 Resolved（桌面、人、杯子、椅子、小助手），每份要现算 3 张 256 项的表；
    // 外观和光照状态不变时结果完全一样，所以按（外观, 光照, 光晕）缓存。Resolved 是不可变的，可以放心共享。
    struct ResolvedKey: Hashable {
        var app: Appearance?; var a: TimeOfDay; var b: TimeOfDay; var level: Int; var glow: RGBA8?; var glowMilli: Int
    }
    nonisolated(unsafe) static var resolvedCache: [ResolvedKey: Resolved] = [:]
    private static let cacheLock = NSLock()
    /// 带缓存的版本。appearance == nil 表示「值本身就是主调色板索引」（道具、房间）。
    public static func resolved(appearance: Appearance?, state: LightState, glow: RGBA8? = nil, glowAmount: Double = 0.5) -> Resolved {
        let key = ResolvedKey(app: appearance, a: state.a, b: state.b, level: state.level, glow: glow, glowMilli: Int((glowAmount * 1000).rounded()))
        cacheLock.lock()
        if let r = resolvedCache[key] { cacheLock.unlock(); return r }
        cacheLock.unlock()
        let r = resolved(map: appearance?.roleMap, state: state, glow: glow, glowAmount: glowAmount)      // 建表在锁外做（可能有别的线程同时在建同一份，结果相同，无所谓）
        cacheLock.lock()
        if resolvedCache.count > 400 { resolvedCache.removeAll(keepingCapacity: true) }
        resolvedCache[key] = r
        cacheLock.unlock()
        return r
    }
}
