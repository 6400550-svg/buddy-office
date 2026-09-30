import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 表现层对「数据层给出的怪值」的防护：时间差是 NaN / 无穷 / 天文数字时，`Int(x)` 会在运行时 trap（主线程崩溃）。
/// 数据层（C-002 / C-003 / C-025 / C-026）现在已经把这些值夹住了，表现层自己也夹一遍是双保险（C-033）。
@Suite struct ExtremeValuesTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    static let extremes: [Double] = [.nan, .infinity, -.infinity, -1, 0, 0.4, 59.9, 3600, 1e9, 1e12, 1e18, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, .leastNonzeroMagnitude]

    @Test func durationFormattersNeverTrapAndCapAtAboutThirtyYears() {
        for x in Self.extremes {
            let strings = [PlateCopy.duration(x), PlateCopy.spoken(x), PlateCopy.waitSpoken(x), HoverCard.ago(x)]
            #expect(strings.allSatisfy { !$0.isEmpty }, "\(x)")
        }
        #expect(PlateCopy.duration(.nan) == "0:00")
        #expect(PlateCopy.duration(-.infinity) == "0:00")
        #expect(PlateCopy.duration(75) == "1:15")
        #expect(PlateCopy.wholeSeconds(1e18) == 1_000_000_000, "夹到 10 亿秒")
        #expect(PlateCopy.wholeSeconds(.infinity) == 0)
    }

    /// 快照里所有时间都是怪值：桌牌文字、悬停卡片、表演者的姿势 / 屏幕、整个场景渲染都不能崩。
    @Test func aSnapshotWithCorruptTimesNeverCrashesTheStage() {
        let weird: [Date] = [Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: -.infinity),
                             Date(timeIntervalSinceReferenceDate: 1e300), Date(timeIntervalSinceReferenceDate: -1e300), .distantPast, .distantFuture]
        for w in weird {
            for tool in [true, false] {
                var s = PerformerTimingTests.snap(tool ? PerformerTimingTests.tool("mcp__notion__x", "", at: 0) : .thinking)
                s.activitySince = w; s.turnStartedAt = w; s.sessionStartedAt = w; s.idleSince = w; s.lastTurnEndedAt = w
                if tool { s.activity = .tool(ToolCall(name: "mcp__notion__x", category: .mcp, server: "notion", startedAt: w), parallel: 1) }
                _ = PlateCopy.activity(s, now: Self.base, privacy: false)
                _ = PlateCopy.statusLine(s, now: Self.base, privacy: false)
                _ = HoverCard.make(s, now: Self.base, zoom: 2, privacy: false)
                let director = VisualDirector()
                let scene = OfficeScene(); scene.director = director
                var o = SceneOptions(); o.directorIsExternal = true; o.retained = false
                for i in 0..<30 {
                    let t = Double(i) / 15
                    director.update(snapshots: [s], now: Self.base.addingTimeInterval(t), time: t, privacy: false)
                    _ = scene.render(viewportW: 224, viewportH: 226, present: [s], dormant: [], now: Self.base.addingTimeInterval(t), time: t, options: o)
                }
            }
        }
    }

    @Test func idleMinutesWithACorruptIdleSince() {
        var s = PerformerTimingTests.snap(.idle)
        for w in [Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: 1e300), .distantPast] {
            s.idleSince = w
            #expect(!PlateCopy.idleMinutes(s, now: Self.base).isEmpty)
        }
    }
}
