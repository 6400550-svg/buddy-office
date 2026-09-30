import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// A-011（App 层）：数据层给出的座位号（持久化文件被写坏时可能是天文数字 / 负数）要落在 0..<64，否则办公室会去分配天文数字的数组和画布。
@Suite struct SeatSanitizerTests {
    @Test func wildSeatNumbersBecomeTheSmallestFreeSeats() {
        let snaps = [Fx.snap("t:a", seat: 0), Fx.snap("t:b", seat: 2), Fx.snap("t:huge", seat: 1_000_000_000),
                     Fx.snap("t:neg", seat: -7), Fx.snap("t:max", seat: Int.max), Fx.dormant("d:z", seat: 64)]
        let r = SeatSanitizer.sanitize(snaps)
        #expect(r.count == snaps.count)
        let by = Dictionary(uniqueKeysWithValues: r.map { ($0.key, $0.seat) })
        #expect(by["t:a"] == 0 && by["t:b"] == 2, "正常的座位号不动")
        #expect(r.allSatisfy { (0..<SeatSanitizer.maxSeats).contains($0.seat) })
        #expect(Set(r.map { $0.seat }).count == r.count, "改出来的座位号不能和别人撞")
        // 确定性：按 key 排序依次拿最小的空位（1、3、4、5）
        #expect(by["d:z"] == 1 && by["t:huge"] == 3 && by["t:max"] == 4 && by["t:neg"] == 5)
    }

    @Test func aNormalListIsReturnedUntouchedAndOrderIsKept() {
        let snaps = (0..<6).map { Fx.snap("t:\($0)", seat: $0) }
        #expect(SeatSanitizer.sanitize(snaps) == snaps)
        #expect(SeatSanitizer.sanitize([]).isEmpty)
    }

    /// 座位真的不够用（超过 64 个同时在场，几乎不可能）：不崩，剩下的保持原样（办公室不画它们，小鱼缸 / 宠物条 / 菜单仍然有）。
    @Test func whenThereAreNoFreeSeatsLeftNothingCrashes() {
        var snaps = (0..<SeatSanitizer.maxSeats).map { Fx.snap("t:\($0)", seat: $0) }
        snaps.append(Fx.snap("t:extra", seat: 999_999))
        let r = SeatSanitizer.sanitize(snaps)
        #expect(r.count == snaps.count)
        #expect(r.last?.seat == 999_999)
    }
}
