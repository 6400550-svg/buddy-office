import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// 设置：外部可写的数值统一夹取（A-004 / A-005）、日期键永远是公历（A-028）。
@Suite struct SettingsTests {
    /// A-004：dormant.max 被写成负数 / 极大值不能让 prefix(-1) 之类崩溃；所有带范围的数值项读出来都在合法范围内。
    @Test func numbersWrittenBehindOurBackAreClampedIntoTheirValidRange() {
        Fx.withSettings { s, d in
            for (v, want) in [(-1, 0), (0, 0), (5, 5), (8, 8), (99, 8), (Int.min, 0), (Int.max, 8)] {
                d.set(v, forKey: "dormant.max")
                #expect(s.int("dormant.max") == want, "dormant.max = \(v)")
            }
            for (v, want) in [(-5, 5), (30, 30), (10_000_000, 600), (Int.min, 5), (Int.max, 600)] {
                d.set(v, forKey: "notify.finishedMinSeconds")
                #expect(s.int("notify.finishedMinSeconds") == want, "notify.finishedMinSeconds = \(v)")
            }
            for (v, want) in [(-3, 0), (0, 0), (3, 3), (99, 5)] { d.set(v, forKey: "office.zoom"); #expect(s.int("office.zoom") == want, "office.zoom = \(v)") }
            for (v, want) in [(0, 1), (2, 2), (9, 2)] { d.set(v, forKey: "tank.zoom"); #expect(s.int("tank.zoom") == want, "tank.zoom = \(v)") }
            for (v, want) in [(0, 1), (3, 3), (7, 3)] { d.set(v, forKey: "strip.zoom"); #expect(s.int("strip.zoom") == want, "strip.zoom = \(v)") }
            for (v, want) in [(-1.0, 0.3), (0.5, 0.5), (5.0, 1.0), (Double.nan, 1.0), (Double.infinity, 1.0), (-Double.infinity, 0.3)] {
                d.set(v, forKey: "tank.opacity")
                #expect(s.double("tank.opacity") == want, "tank.opacity = \(v)")
            }
            for (v, want) in [(0, 1), (500, 120)] { d.set(v, forKey: "idle.dozeMinutes"); #expect(s.int("idle.dozeMinutes") == want) }
            for (v, want) in [(0, 2), (5000, 240)] { d.set(v, forKey: "idle.sleepMinutes"); #expect(s.int("idle.sleepMinutes") == want) }
            for (v, want) in [(0, 1), (500, 24)] { d.set(v, forKey: "dormant.recentHours"); #expect(s.int("dormant.recentHours") == want) }
        }
    }

    /// A-004：AppModel.derive 不管 dormantMax 是什么都不能崩（Array.prefix(负数) 是运行时陷阱）。
    @Test func deriveNeverTrapsWhateverTheDormantMaxIs() {
        let snaps = [Fx.snap("t:a", seat: 0), Fx.dormant("d:b", seat: 1), Fx.dormant("d:c", seat: 2)]
        for n in [-1, Int.min, 0, 1, 8, Int.max] {
            let r = AppModel.derive(snapshots: snaps, hidden: [], dormantMax: n)
            #expect(r.present.count == 1)
            #expect(r.dormant.count == max(0, min(n, 8, 2)), "dormantMax = \(n)")
        }
    }

    /// A-005：今日白板计数被写成负数 / 巨大值：读出来必须是 0…9999（drawTally 的区间 0..<负数 会陷阱）。
    @Test func tallyReadFromTheFileIsClamped() {
        Fx.withSettings { s, d in
            let key = "tally." + Settings.dayString()
            for (v, want) in [(-5, 0), (Int.min, 0), (7, 7), (123_456, 9999), (Int.max, 9999)] {
                d.set(v, forKey: key)
                let fresh = Settings(defaults: d)          // tallyToday 有 1 秒缓存，换个实例读
                #expect(fresh.tallyToday() == want, "tally = \(v)")
            }
        }
    }

    /// A-005：存的值是 Int.max 时，addTally 的 + 1 不能溢出。
    @Test func addTallyDoesNotOverflow() {
        Fx.withSettings { s, d in
            let key = "tally." + Settings.dayString()
            d.set(Int.max, forKey: key)
            s.addTally()
            #expect(s.tallyToday() == 9999)
            d.set(-100, forKey: key)
            let fresh = Settings(defaults: d)
            fresh.addTally()
            #expect(fresh.tallyToday() == 1, "被写坏的负数当 0 处理，加一轮就是 1")
        }
    }

    /// A-028：白板计数的日期键永远是公历 yyyy-MM-dd（佛历 / 日本年号 / 伊斯兰历下 yyyy 会是另一个年份，键一变当天计数就从 0 开始）。
    @Test func dayKeysStayGregorianInAnyLocale() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)          // 2027-01-15 08:00:00 UTC
        let utc = TimeZone(identifier: "UTC")!
        for id in ["en_US_POSIX", "th_TH@calendar=buddhist", "ja_JP@calendar=japanese", "ar_SA@calendar=islamic-civil;numbers=latn", "fa_IR@calendar=persian;numbers=latn"] {
            #expect(Settings.dayString(date, locale: Locale(identifier: id), timeZone: utc) == "2027-01-15", "locale \(id)")
        }
        // 时区：同一个时刻，太平洋时间还在前一天
        #expect(Settings.dayString(date, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2027-01-15")
        #expect(Settings.dayString(date.addingTimeInterval(-9 * 3600), locale: Locale(identifier: "th_TH@calendar=buddhist"), timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2027-01-14")
    }
}
