import Foundation
import Testing
@testable import BuddyCore

/// 测试脚手架：一棵假的 home 树 + 冻结的虚拟时钟 + 假的进程探测 + 一个引擎。
/// 做法是"带时间的事件脚本 → 断言期望的动作时间线"：往假树里写带时间戳的数据，`advance` 推进时钟，`poll` 后断言快照。
final class Harness {
    let root: String
    let clock: VirtualClock
    let probe = FakeProcessProbe()
    let tree: FakeClaudeTree
    let engine: SessionEngine
    private(set) var events: [BuddyEvent] = []
    private(set) var snapshots: [BuddySnapshot] = []
    private(set) var lastOutput: SessionEngine.Output?

    /// 2026-09-29 04:00:00 UTC（和真实数据同一天，便于对照）
    static let epoch = Date(timeIntervalSince1970: 1_790_654_400)
    /// epoch + s 秒，取整到毫秒（和 hook / 会话记录时间戳的换算方式一致，Date 才能精确相等）。
    static func at(_ s: Double) -> Date {
        Date(timeIntervalSince1970: (1_790_654_400_000 + (s * 1000).rounded()) / 1000)
    }

    init(persist: Bool = false, tokens: Bool = false, registerHook: Bool = true,
         configure: ((inout SessionEngine.Options) -> Void)? = nil) {
        root = FileIO.temporaryDirectory + "buddy-test-" + UUID().uuidString
        clock = VirtualClock(frozenAt: Harness.epoch)
        tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        tree.prepare(registerHook: registerHook)
        var o = SessionEngine.Options(paths: tree.paths, now: { [clock] in clock.now() }, probe: probe)
        o.ledgerQueue = testLedgerQueue()
        o.persist = persist
        o.scanTokens = tokens
        configure?(&o)
        engine = SessionEngine(options: o)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    var now: Date { clock.now() }
    func advance(_ s: TimeInterval) { clock.advance(by: s) }

    @discardableResult
    func poll() -> [BuddySnapshot] {
        let out = engine.poll()
        lastOutput = out
        snapshots = out.snapshots
        events.append(contentsOf: out.events)
        return snapshots
    }

    /// 推进 `seconds` 秒，每 `step` 秒 poll 一次。
    func run(for seconds: TimeInterval, step: TimeInterval = 0.05) {
        var t = 0.0
        while t < seconds - 1e-9 { advance(step); poll(); t += step }
    }

    func snap(_ key: String) -> BuddySnapshot? { snapshots.first { $0.key == key } }
    func only() -> BuddySnapshot? { snapshots.count == 1 ? snapshots[0] : nil }

    func kinds(_ key: String) -> [BuddyEvent.Kind] { events.filter { $0.key == key }.map { $0.kind } }
    func clearEvents() { events = [] }
}

/// 一个常用的桌面会话（pid 1001）。
struct DesktopFixture {
    static let sid = "aaaaaaaa-0000-4000-8000-000000000001"
    static let host = "local_11111111-0000-4000-8000-000000000001"
    static let key = "d:" + host
    let session: FakeClaudeTree.Session
    init(h: Harness, pid: Int32 = 1001, sid: String = DesktopFixture.sid, host: String = DesktopFixture.host,
         name: String? = "测试会话", startedAgo: TimeInterval = 60) {
        session = FakeClaudeTree.Session(pid: pid, sessionId: sid, host: host, name: name,
                                         startedAt: h.now.addingTimeInterval(-startedAgo))
    }
    var sid: String { session.sessionId }
}

/// 让 Swift Testing 的断言带上描述的小工具。
func expectActivity(_ s: BuddySnapshot?, _ expected: Activity, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(s?.activity == expected, "动作应为 \(expected)，实际 \(String(describing: s?.activity))", sourceLocation: sourceLocation)
}

/// 时间相等（允许 2 ms 误差：hook / 登记表的时间戳是毫秒整数）。
func near(_ a: Date?, _ b: Date, tol: TimeInterval = 0.002) -> Bool {
    guard let a else { return false }
    return abs(a.timeIntervalSince(b)) <= tol
}

/// 测试用的账本扫描队列：默认队列是 `.background`，机器被别的进程占满时（同时跑几路检查）会被饿死几十秒，等它的测试就间歇性超时（R4b-01）。
/// 「默认队列就是 .background」由 `SpecTraceCoreTests` 的 4.3-42 / 4.3-43 单独钉住。
func testLedgerQueue(_ label: String = "test.tokenscan") -> DispatchQueue { DispatchQueue(label: label, qos: .userInitiated) }
