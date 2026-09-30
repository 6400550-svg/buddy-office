import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// A-001：设置页里「打盹 / 睡着 / 最近 N 小时 / 最多保留」四项要真的传到数据层（SessionEngine.Options）。
@Suite struct EngineConfigTests {
    @Test func settingsMapToEngineOptions() {
        let v = EngineConfig.values(dozeMinutes: 3, sleepMinutes: 20, dormantMax: 6, recentHours: 5)
        #expect(v.dozeAfter == 180)
        #expect(v.sleepAfter == 1200)
        #expect(v.dormantMax == 6)
        #expect(v.dormantRecent == 5 * 3600)
        // 默认值 = 引擎自己原来的默认值（任务书：10 分钟打盹 / 45 分钟睡着 / 4 个下班工位 / 3 小时）
        let d = EngineConfig.values(dozeMinutes: 10, sleepMinutes: 45, dormantMax: 4, recentHours: 3)
        #expect(d == EngineConfig.Values(dozeAfter: 600, sleepAfter: 2700, dormantMax: 4, dormantRecent: 10800))
    }

    @Test func outOfRangeValuesAreClampedAndSleepAlwaysComesAfterDoze() {
        let lo = EngineConfig.values(dozeMinutes: 0, sleepMinutes: -5, dormantMax: -1, recentHours: 0)
        #expect(lo.dozeAfter == 60)                    // 至少 1 分钟
        #expect(lo.sleepAfter == 120)                  // 至少 2 分钟，且晚于打盹
        #expect(lo.dormantMax == 0)
        #expect(lo.dormantRecent == 3600)
        let hi = EngineConfig.values(dozeMinutes: Int.max, sleepMinutes: Int.max, dormantMax: Int.max, recentHours: Int.max)
        #expect(hi.dozeAfter == 120 * 60)
        #expect(hi.sleepAfter == 240 * 60)
        #expect(hi.dormantMax == 8)
        #expect(hi.dormantRecent == 24 * 3600)
        // 睡着比打盹早（或一样）：状态机里 idleFor >= sleepAfter 先判，永远走不到打盹——所以睡着必须至少比打盹晚 1 分钟
        let inverted = EngineConfig.values(dozeMinutes: 30, sleepMinutes: 10, dormantMax: 4, recentHours: 3)
        #expect(inverted.dozeAfter == 1800)
        #expect(inverted.sleepAfter == 1860)
        let same = EngineConfig.values(dozeMinutes: 120, sleepMinutes: 120, dormantMax: 4, recentHours: 3)
        #expect(same.sleepAfter == 121 * 60)
    }

    /// RealProvider 造出来的 SessionStore 带着设置里的值（只造对象，不 start，不起线程）。
    @Test func realProviderPassesTheSettingsToTheEngine() throws {
        try DesktopMetaGate.exclusive { try Fx.withSettings { s, d in
            d.set(3, forKey: "idle.dozeMinutes"); d.set(20, forKey: "idle.sleepMinutes")
            d.set(6, forKey: "dormant.max"); d.set(5, forKey: "dormant.recentHours")
            let store = try #require(RealProvider.make(args: ["--data-root", "/nonexistent/buddy-test-home", "--no-persist", "--poll"], settings: s) as? SessionStore)
            let e = store.options.engine
            #expect(e.dozeAfter == 180)
            #expect(e.sleepAfter == 1200)
            #expect(e.dormantMax == 6)
            #expect(e.dormantRecent == 5 * 3600)
            #expect(store.options.usePolling)
            #expect(!e.persist)
        } }
    }

    /// 设置项被外部写成非法值时，传给引擎的也是夹过的。
    @Test func realProviderClampsWhatItReadsFromDefaults() throws {
        try DesktopMetaGate.exclusive { try Fx.withSettings { s, d in
            d.set(-7, forKey: "idle.dozeMinutes"); d.set(0, forKey: "idle.sleepMinutes"); d.set(-1, forKey: "dormant.max"); d.set(Int.max, forKey: "dormant.recentHours")
            let store = try #require(RealProvider.make(args: ["--data-root", "/nonexistent/buddy-test-home"], settings: s) as? SessionStore)
            let e = store.options.engine
            #expect(e.dozeAfter == 60)
            #expect(e.sleepAfter == 120)
            #expect(e.dormantMax == 0)
            #expect(e.dormantRecent == 24 * 3600)
        } }
    }

    /// --data-root 要原样传进数据层（假 home 树；测试 / 自检都靠它隔离真实数据）；不给就是真实的 home。
    /// （BuddyCoreTests 的 chain1 从源码结构上看同一件事：RealProvider 只造 SessionStore，走 SessionEngine.Options → SessionStore.Options → SessionStore(options:)。）
    @Test func theDataRootArgumentReachesTheEngine() throws {
        try DesktopMetaGate.exclusive { try Fx.withSettings { s, _ in
            let fake = try #require(RealProvider.make(args: ["--data-root", "/x/fake-home/", "--poll"], settings: s) as? SessionStore)
            #expect(fake.options.engine.paths == Paths(home: "/x/fake-home"))
            let real = try #require(RealProvider.make(args: [], settings: s) as? SessionStore)
            #expect(real.options.engine.paths == Paths.real)
            #expect(real.options.engine.persist && !real.options.usePolling, "默认落盘、用 FSEvents")
        } }
        let src = try SourceAudit.read("RealProvider.swift")
        #expect(src.contains(#"DebugTools.opt(args, "--data-root")"#) && src.contains("Paths(home:"))
        #expect(src.contains("SessionStore(options:") && src.contains("SessionEngine.Options(paths:") && src.contains("SessionStore.Options(engine:"))
    }
}
