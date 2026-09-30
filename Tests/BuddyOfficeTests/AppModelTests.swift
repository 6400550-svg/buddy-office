import Testing
import Foundation
import AppKit
import BuddyCore
@testable import BuddyOffice

/// AppModel 的接线（不 start()：不建办公室窗口、不弹任何东西；数据源是假的，绝不去读真实数据）。
@MainActor @Suite struct AppModelTests {
    final class Rig {
        let store = Fx.Store()
        let real = FakeProvider()
        let model: AppModel
        var demoProviders: [FakeProvider] = [], realProviders: [FakeProvider] = []
        init() {
            model = AppModel(provider: real, args: ["--data-root", "/nonexistent/buddy-test-home"], settings: store.settings)
            model.makeDemoProvider = { [unowned self] in let p = FakeProvider(); demoProviders.append(p); return p }
            model.makeRealProvider = { [unowned self] _ in let p = FakeProvider(); realProviders.append(p); return p }
            model.stopProvider = { p, _ in p.stop() }                       // 测试里同步停
        }
        deinit { store.cleanUp() }
    }

    /// A-021：换数据源（演示 ⇄ 真实）之后，新数据到来之前不能显示「今天还没人上班」——gotData 要重置（原来一直是 true，牌子会闪一下）。
    @Test func switchingTheDataSourceResetsTheFirstDataFlagAndStopsTheOldOne() {
        let r = Rig()
        #expect(!r.model.gotData)
        r.real.onUpdate?([Fx.snap("t:a", seat: 0)])
        #expect(r.model.gotData && r.model.snapshots.count == 1)
        r.model.setDemo(true)
        #expect(r.model.demo && !r.model.gotData, "换成演示：新数据没到之前不出牌子")
        #expect(r.model.snapshots.isEmpty)
        #expect(r.real.stopped == 1, "旧的真实数据源要停掉")
        #expect(r.demoProviders.count == 1 && r.demoProviders[0].started == 1)
        r.demoProviders[0].onUpdate?([Fx.snap("demo:1", seat: 0)])
        #expect(r.model.gotData)
        r.model.setDemo(true)
        #expect(r.demoProviders.count == 1, "已经是演示：什么都不做")
        r.model.setDemo(false)
        #expect(!r.model.demo && !r.model.gotData && r.model.snapshots.isEmpty)
        #expect(r.demoProviders[0].stopped == 1 && r.realProviders.count == 1 && r.realProviders[0].started == 1)
    }

    /// A-011：数据进来先清洗座位号、再按座位排序；A-004：下班工位数量夹在 0…8（设置被写成负数时原来在这里崩）。
    @Test func incomingDataIsSanitizedSortedAndDerived() {
        let r = Rig()
        r.store.defaults.set(-1, forKey: "dormant.max")
        r.real.onUpdate?([Fx.snap("t:b", seat: 5), Fx.snap("t:wild", seat: Int.max), Fx.snap("t:a", seat: 0), Fx.dormant("d:z", seat: 2)])
        let seats = r.model.snapshots.map { $0.seat }
        #expect(seats == seats.sorted() && seats.allSatisfy { (0..<64).contains($0) })
        #expect(r.model.present.count == 3)
        #expect(r.model.dormant.isEmpty, "dormant.max = -1 夹成 0")
        r.store.defaults.set(8, forKey: "dormant.max")
        r.model.refreshDerived()
        #expect(r.model.dormant.count == 1)
    }

    /// A-010（端到端）：autoQuit 用的「还有没有活会话」闭包：被用户隐藏的 buddy 也算。
    @Test func theAutoQuitLiveSessionCheckCountsHiddenBuddies() {
        let r = Rig()
        r.model.wireAutoQuit()
        #expect(!r.model.autoQuit.hasLiveSessions())
        r.real.onUpdate?([Fx.snap("t:h", seat: 0, activity: .thinking)])
        r.store.settings.hiddenKeys = ["t:h"]
        r.model.refreshDerived()
        #expect(r.model.present.isEmpty, "被隐藏了：办公室里看不到他")
        #expect(r.model.autoQuit.hasLiveSessions(), "但他的会话还活着：不能因为 Claude 退出就把 Buddy 也收了")
        #expect(r.model.autoQuit.isEnabled())
        r.store.defaults.set(false, forKey: "autoQuitWithClaude")
        #expect(!r.model.autoQuit.isEnabled())
    }

    /// 点击：悬空座位号什么都不发生；演示模式只写日志、不真的跳、不清未读。
    @Test func clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal() {
        let r = Rig()
        r.real.onUpdate?([Fx.snap("t:a", seat: 0, pid: 123)])
        r.model.jump(seat: 9)                                   // 没有人
        r.model.jump(snapshot: Fx.snap("t:gone", seat: 3, pid: 5))   // 已经走了的会话
        #expect(r.real.seen.isEmpty)
        r.model.setDemo(true)
        r.demoProviders[0].onUpdate?([Fx.snap("demo:1", seat: 0, origin: .desktop, host: "local_abc-123")])
        r.model.jump(seat: 0)
        r.model.jump(snapshot: r.model.snapshots[0])
        #expect(r.demoProviders[0].seen.isEmpty, "演示里点了不清未读、不跳")
    }
}
