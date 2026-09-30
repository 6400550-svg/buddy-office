import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// QA 定稿（规格追踪）：应用层里、追踪表疑点的补充断言。
@Suite struct SpecTraceAppTests {
    /// 5.5「下班工位最多保留 4 个，超出时先移走最久没活动的」在应用层的一半（设置里「最多保留」调小时）：
    /// 留下的是最近离场 / 活动的，而不是座位号小的（追踪表疑点 Q-03；数据层那一半见 EnginePresenceTests / SpecTraceCoreTests）。
    @Test func shrinkingTheDormantLimitKeepsTheMostRecentlyActiveSeats() {
        let t0 = Fx.base
        let snaps = [Fx.dormant("d:a", seat: 0, since: t0),                                    // 最久没活动，座位号最小
                     Fx.dormant("d:b", seat: 1, since: t0.addingTimeInterval(300)),            // 最近
                     Fx.dormant("d:c", seat: 2, since: t0.addingTimeInterval(100)),
                     Fx.dormant("d:d", seat: 3, since: t0.addingTimeInterval(200)),
                     Fx.snap("t:live", seat: 4)]
        let two = AppModel.derive(snapshots: snaps, hidden: [], dormantMax: 2)
        #expect(two.dormant.map { $0.key } == ["d:b", "d:d"], "留下 since 最晚的两个，仍按座位号排")
        let three = AppModel.derive(snapshots: snaps, hidden: [], dormantMax: 3)
        #expect(three.dormant.map { $0.key } == ["d:b", "d:c", "d:d"])
        #expect(two.present.map { $0.key } == ["t:live"])
        // 不缩小时全留（在场的不受影响）
        #expect(AppModel.derive(snapshots: snaps, hidden: [], dormantMax: 4).dormant.count == 4)
    }
}
