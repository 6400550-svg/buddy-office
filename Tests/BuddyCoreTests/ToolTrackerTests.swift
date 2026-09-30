import Foundation
import Testing
@testable import BuddyCore

@Suite struct ToolTrackerTests {
    let t0 = Harness.epoch
    func at(_ s: Double) -> Date { Harness.at(s) }

    @Test func parallelCallsInTheSameMillisecondShareABatch() {
        var t = ToolTracker()
        t.pre(name: "Read", detail: "/a", at: at(0), owner: .main)
        t.pre(name: "Read", detail: "/b", at: at(0), owner: .main)         // 实测同一毫秒出现过两个 Read
        #expect(t.mainOpen.count == 2)
        #expect(Set(t.mainOpen.map { $0.batch }).count == 1)
        // Post 按"工具名 + detail 都相同"配对，不是按到达顺序
        t.post(name: "Read", detail: "/b", at: at(0.1))
        #expect(t.mainOpen.map { $0.call.detail } == ["/a"])
        t.post(name: "Read", detail: "/a", at: at(0.1))
        #expect(t.mainOpen.isEmpty)
    }

    @Test func identicalParallelCallsCloseFirstInFirstOut() {
        var t = ToolTracker()
        t.pre(name: "Read", detail: "/same", at: at(0), owner: .main)
        t.pre(name: "Read", detail: "/same", at: at(0.001), owner: .main)
        t.post(name: "Read", detail: "/same", at: at(0.2))
        #expect(t.mainOpen.count == 1)
        #expect(t.mainOpen[0].call.startedAt == at(0.001))                   // 最早的那个先关
    }

    @Test func postFallsBackToToolNameThenIgnores() {
        var t = ToolTracker()
        t.pre(name: "Bash", detail: "npm test", at: at(0), owner: .main)
        t.post(name: "Bash", detail: "different detail", at: at(1))          // detail 对不上：按工具名关
        #expect(t.mainOpen.isEmpty)
        t.post(name: "Bash", detail: "x", at: at(2))                         // 什么都没开着：忽略，不崩
        #expect(t.mainOpen.isEmpty)
        #expect(t.closed.count == 1)
    }

    @Test func newBatchClosesOlderOpenCallsAsSuperseded() {
        // ccmon 没注册 PostToolUseFailure：失败的工具只有 Pre 没有 Post，会一直悬空
        var t = ToolTracker()
        t.pre(name: "Bash", detail: "failing command", at: at(0), owner: .main)
        // 没有 Post（工具失败了）；模型看到失败结果后发下一条消息
        t.pre(name: "Read", detail: "/x", at: at(3), owner: .main)
        #expect(t.mainOpen.map { $0.call.name } == ["Read"])
        #expect(t.closed.last?.reason == .superseded)
        #expect(t.closed.last?.call.name == "Bash")
    }

    @Test func permissionDeniedDanglingIsClosedByTheNextBatch() {
        var t = ToolTracker()
        t.pre(name: "Write", detail: "/etc/x", at: at(0), owner: .main)      // 权限被拒：没有 Post
        t.pre(name: "Bash", detail: "ls", at: at(12), owner: .main)           // 用户拒绝后模型换了个办法
        t.post(name: "Bash", detail: "ls", at: at(12.5))
        #expect(t.mainOpen.isEmpty)
        #expect(t.closed.contains { $0.call.name == "Write" && $0.reason == .superseded })
    }

    @Test func callsWithin250msOfThePreviousPreStayInTheSameBatch() {
        var t = ToolTracker()
        t.pre(name: "Grep", detail: "a", at: at(0), owner: .main)
        t.pre(name: "Grep", detail: "b", at: at(0.2), owner: .main)           // ≤ 0.25 s：同一批
        t.pre(name: "Grep", detail: "c", at: at(0.4), owner: .main)           // 距上一个 Pre 仍是 0.2 s：同一批
        #expect(t.mainOpen.count == 3)
        t.pre(name: "Glob", detail: "d", at: at(0.7), owner: .main)           // 距上一个 0.3 s > 0.25：新的一批
        #expect(t.mainOpen.map { $0.call.name } == ["Glob"])
    }

    @Test func turnBoundariesCloseAllMainCalls() {
        var t = ToolTracker()
        t.pre(name: "Bash", detail: "x", at: at(0), owner: .main)
        t.pre(name: "Read", detail: "y", at: at(0), owner: .main)
        t.pre(name: "Bash", detail: "helper's", at: at(1), owner: .helper)
        t.turnBoundary(at: at(5))
        #expect(t.mainOpen.isEmpty)
        #expect(t.helperOpen.count == 1)                                      // 小助手名下的不受主线程轮次边界影响
        #expect(t.closed.filter { $0.reason == .turnBoundary }.count == 2)
    }

    @Test func aBoundaryOlderThanAnOpenCallDoesNotCloseIt() {
        // 会话记录里的 stop_hook_summary 可能比当前开着的调用旧
        var t = ToolTracker()
        t.pre(name: "Bash", detail: "new turn", at: at(10), owner: .main)
        t.turnBoundary(at: at(5))
        #expect(t.mainOpen.count == 1)
    }

    @Test func staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle() {
        var t = ToolTracker()
        t.pre(name: "Monitor", detail: "", at: at(0), owner: .main)
        t.expireStale(now: at(31 * 60), registryIdle: false)
        #expect(t.mainOpen.count == 1)                                        // busy 时长时间开着的工具是正常的
        t.expireStale(now: at(29 * 60), registryIdle: true)
        #expect(t.mainOpen.count == 1)                                        // 还没到 30 分钟
        t.expireStale(now: at(31 * 60), registryIdle: true)
        #expect(t.mainOpen.isEmpty)
        #expect(t.closed.last?.reason == .stale)
    }

    @Test func helperOwnedRecordsExpireRegardless() {
        var t = ToolTracker()
        t.pre(name: "Bash", detail: "x", at: at(0), owner: .helper)
        t.expireStale(now: at(31 * 60), registryIdle: false)
        #expect(t.open.isEmpty)
    }

    @Test func truncatedToolNamesMatchByPrefix() {
        var t = ToolTracker()
        t.pre(name: "mcp__ccd_session_mgmt__search_session_tr", truncated: true, detail: "", at: at(0), owner: .main)
        #expect(t.mainOpen[0].call.category == .mcp)
        #expect(t.mainOpen[0].call.server == "ccd_session_mgmt")
        t.post(name: "mcp__ccd_session_mgmt__search_session_tr", truncated: true, detail: "", at: at(1))
        #expect(t.mainOpen.isEmpty)
    }

    @Test func postWithoutPreIsIgnored() {
        var t = ToolTracker()
        t.post(name: "Read", detail: "/x", at: at(0))
        #expect(t.open.isEmpty && t.closed.isEmpty)
    }

    @Test func resetClearsEverything() {
        var t = ToolTracker()
        t.pre(name: "Read", detail: "x", at: at(0), owner: .main)
        t.reset()
        #expect(t.open.isEmpty)
    }
}
