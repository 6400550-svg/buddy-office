import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// A-014：桌面会话元数据（lastFocusedAt）不再每次都重列目录、重读全部 local_*.json；A-025：悬停卡片按内容缓存。
@Suite struct CachesTests {
    @Test func mostRecentHostIsTheLargestLastFocusedAndTiesAreDeterministic() {
        #expect(DesktopMeta.mostRecentHost([:]) == nil)
        #expect(DesktopMeta.mostRecentHost(["local_a": 100, "local_b": 300, "local_c": 200]) == "local_b")
        #expect(DesktopMeta.mostRecentHost(["local_z": 300, "local_a": 300, "local_m": 300]) == "local_a", "并列：id 最小的（不随字典顺序变）")
        for _ in 0..<20 { #expect(DesktopMeta.mostRecentHost(["local_y": 5, "local_x": 5]) == "local_x") }
    }

    @Test func theMetadataCacheReadsOncePerSecondNotOncePerCall() {
        var reads = 0, now = 1000.0
        let cache = DesktopMeta.Cache(maxAge: 1, read: { reads += 1; return ["local_a": Double(reads), "local_b": 0] }, clock: { now })
        #expect(cache.isMostRecentlyFocused(host: "local_a"))
        for _ in 0..<50 { _ = cache.isMostRecentlyFocused(host: "local_b") }
        #expect(reads == 1, "同一秒里问 50 次只读一次盘")
        now += 0.99
        _ = cache.all(); #expect(reads == 1)
        now += 0.02
        _ = cache.all(); #expect(reads == 2, "过了 1 秒重新读")
        now -= 100                                                     // 时钟往回走（不会发生，但不能因此永远不刷新）
        _ = cache.all(); #expect(reads == 3)
    }

    @Test func aMissingHostIsNeverMostRecentlyFocused() {
        let cache = DesktopMeta.Cache(maxAge: 1, read: { ["local_a": 5] }, clock: { 0 })
        #expect(!cache.isMostRecentlyFocused(host: "local_nope"))
        let empty = DesktopMeta.Cache(maxAge: 1, read: { [:] }, clock: { 0 })
        #expect(!empty.isMostRecentlyFocused(host: "local_a"))
    }

    @Test func theHoverCardIsRebuiltOnlyWhenItsContentCanHaveChanged() {
        typealias K = HoverPanelController.CardKey
        let s = Fx.snap("t:a", activity: .thinking)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000.2)
        let k = K(s, now: t0, zoom: 2, privacy: false)
        #expect(k == K(s, now: t0.addingTimeInterval(0.5), zoom: 2, privacy: false), "同一秒内：不重建")
        #expect(k != K(s, now: t0.addingTimeInterval(1), zoom: 2, privacy: false), "过了一秒：卡片里的用时变了")
        var changed = s; changed.activity = .idle
        #expect(k != K(changed, now: t0, zoom: 2, privacy: false))
        #expect(k != K(s, now: t0, zoom: 3, privacy: false) && k != K(s, now: t0, zoom: 2, privacy: true))
        _ = K(s, now: Date(timeIntervalSince1970: .infinity), zoom: 2, privacy: false)          // 时间戳再离谱也不崩（safeInt）
    }
}
