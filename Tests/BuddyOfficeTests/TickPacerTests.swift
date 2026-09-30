import Testing
import Foundation
@testable import BuddyOffice

/// A-017：wake() 没有速率上限——鼠标在办公室窗口里移动时（≥ 75 Hz 的事件），节拍可以超过 30 fps。
@Suite struct TickPacerTests {
    /// 离散事件模拟：稳态间隔 interval，鼠标事件以 hz 的频率持续 seconds 秒，每个事件都 wake()。返回 tick 次数。
    static func simulate(hz: Double, seconds: Double, interval: TimeInterval = 1.0 / 30, minInterval: TimeInterval) -> Int {
        var pacer = TickPacer(); pacer.minInterval = minInterval
        var ticks = 0
        var fireAt = 0.0
        pacer.scheduled(after: 0, now: 0)
        let dt = 0.0005
        var nextWake = 0.0
        var t = 0.0
        while t < seconds {
            if t >= nextWake {
                nextWake += 1 / hz
                if let d = pacer.wakeDelay(now: t) { fireAt = t + d; pacer.scheduled(after: d, now: t) }
            }
            if t >= fireAt {
                ticks += 1
                pacer.didTick(at: t)
                fireAt = t + interval
                pacer.scheduled(after: interval, now: t)
            }
            t += dt
        }
        return ticks
    }

    @Test func aHighRateMouseCannotDriveTheTicksAboveThirtyFps() {
        for hz in [75.0, 120.0, 240.0, 1000.0] {
            let n = Self.simulate(hz: hz, seconds: 1, minInterval: 1.0 / 30)
            #expect(n <= 35, "\(Int(hz)) Hz 的鼠标事件下 1 秒里 tick 了 \(n) 次")
            #expect(n >= 25, "不能被压得太慢：\(n)")
        }
    }

    /// 没有鼠标事件时按稳态间隔走；间隔更长（10 fps）时 wake 仍然能立刻拉一拍（悬停要立刻出一帧）。
    @Test func wakingStillPullsALateTickForwardImmediately() {
        var p = TickPacer(); p.minInterval = 1.0 / 30
        p.didTick(at: 10.0); p.scheduled(after: 0.1, now: 10.0)           // 10 fps 稳态：下一拍在 10.1
        #expect(p.wakeDelay(now: 10.06) == 0.001, "距上一拍已经 60 ms（> 33 ms）：立刻出一帧")
        // 上一拍刚过去 10 ms：不能立刻再来，要等到满 33 ms
        let d = p.wakeDelay(now: 10.01)
        #expect(d != nil && d! >= 1.0 / 30 - 0.01 - 1e-9 && d! <= 1.0 / 30, "\(String(describing: d))")
        // 下一拍本来就快到了（20 ms 以内）：不动
        #expect(p.wakeDelay(now: 10.085) == nil)
    }

    @Test func aHeavyTickNeverSchedulesTheNextOneBackToBack() {
        #expect(TickPacer.delayAfterTick(interval: 1.0 / 30, elapsed: 0.05) >= 0.004, "tick 耗时超过间隔：原来是 1 ms 后又来一拍")
        #expect(TickPacer.delayAfterTick(interval: 1.0 / 30, elapsed: 1.0) >= 0.004)
        #expect(TickPacer.delayAfterTick(interval: 0.1, elapsed: 0.02) == 0.08)
    }
}
