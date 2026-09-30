import Foundation
import Testing
@testable import BuddyCore

/// QA（逻辑线）：进程存活规则用**真的进程**验证——`kill(pid, 0)`（ESRCH = 死、EPERM = 活）、
/// `sysctl(KERN_PROC_PID)` 读到的启动时间、PID 被复用（procStart 与实际启动时间相差 > 2 秒）、进程回收后的防抖。
/// 引擎用真的 `SystemProcessProbe`，时间仍然是虚拟时钟（防抖 3 秒不用真的等）。
@Suite(.serialized) struct StateRuleProcessTests {
    /// 一个真的子进程（/bin/sleep）。用完一定要 stop()。
    final class Child {
        let process = Process()
        var before = Date()
        var after = Date()
        var pid: Int32 { process.processIdentifier }
        init() throws {
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["300"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            before = Date()
            try process.run()
            after = Date()
        }
        func stop() {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        deinit { stop() }
    }

    func engine(_ h: Harness) -> SessionEngine {
        var o = SessionEngine.Options(paths: h.tree.paths, now: { [clock = h.clock] in clock.now() }, probe: SystemProcessProbe())
        o.ledgerQueue = testLedgerQueue()
        o.persist = false
        o.scanTokens = false
        return SessionEngine(options: o)
    }

    func session(pid: Int32, start: Date, sid: String = "dddddddd-0000-4000-8000-000000000001") -> FakeClaudeTree.Session {
        FakeClaudeTree.Session(pid: pid, sessionId: sid, host: nil, name: "真进程", startedAt: start)
    }

    @Test("r1 sysctl 读到的启动时间就是进程真的启动的时候；procStart（整秒）与它相差 < 2 秒算同一个进程，别的时间算被复用；进程退出后 kill(pid,0) 是 ESRCH = 死")
    func r1_realStartTimeAndLiveness() throws {
        let c = try Child()
        defer { c.stop() }
        guard let st = SystemProcessProbe.startTime(of: c.pid) else { Issue.record("sysctl 读不到子进程的启动时间"); return }
        #expect(st >= c.before.addingTimeInterval(-2) && st <= c.after.addingTimeInterval(2), "读到的启动时间 \(st) 不在 [\(c.before), \(c.after)] 附近")
        let probe = SystemProcessProbe()
        let s = probe.probe(pid: c.pid)
        #expect(s.state == .alive)
        #expect(s.startTime != nil)
        let procStart = Date(timeIntervalSince1970: floor(st.timeIntervalSince1970))            // 登记表的 procStart 只有整秒
        #expect(ProcessProbe.classify(s, procStart: procStart) == .alive)
        #expect(ProcessProbe.classify(s, procStart: st.addingTimeInterval(-1.9)) == .alive)
        #expect(ProcessProbe.classify(s, procStart: st.addingTimeInterval(-2.5)) == .reused)
        #expect(ProcessProbe.classify(s, procStart: st.addingTimeInterval(+10)) == .reused)
        c.stop()
        #expect(probe.probe(pid: c.pid).state == .dead)
    }

    @Test("r2 kill(pid,0) 返回 EPERM（别人的进程，比如 launchd）当活着；引擎里也一直在场")
    func r2_epermCountsAsAlive() {
        let s = SystemProcessProbe().probe(pid: 1)
        #expect(s.state == .alive)
        let h = Harness()
        let rec = FakeClaudeTree.Session(pid: 1, sessionId: "dddddddd-0000-4000-8000-000000000002", host: nil, name: "别人的进程", startedAt: h.now)
        h.tree.writeRegistry(rec, status: "busy", extra: ["procStart": NSNull()], markAlive: false)     // 没有 procStart：不比启动时间，只看 kill
        let e = engine(h)
        var last = e.poll().snapshots
        for _ in 0..<8 { h.advance(1.1); last = e.poll().snapshots }
        #expect(last.count == 1)
        #expect(last.first?.presence == .present)
    }

    @Test("r3 进程被回收（真的子进程退出）：存活检查发现之后先防抖 3 秒（2.9 秒仍在场），3.1 秒离场")
    func r3_recycledProcessIsDebouncedBy3Seconds() throws {
        let h = Harness()
        let c = try Child()
        defer { c.stop() }
        guard let st = SystemProcessProbe.startTime(of: c.pid) else { Issue.record("sysctl 读不到子进程的启动时间"); return }
        h.tree.writeRegistry(session(pid: c.pid, start: st), status: "idle", markAlive: false)
        let e = engine(h)
        #expect(e.poll().snapshots.first?.presence == .present)
        c.stop()
        h.advance(1.1)                                                            // 存活检查每 1 秒一次
        #expect(e.poll().snapshots.first?.presence == .present)                    // 这次发现进程没了：防抖开始
        h.advance(2.9)
        #expect(e.poll().snapshots.first?.presence == .present, "发现后 2.9 秒仍在场")
        h.advance(0.2)
        guard case .away? = e.poll().snapshots.first?.presence else { Issue.record("发现后 3.1 秒应该离场"); return }
    }

    @Test("r4 PID 被复用（真进程还活着，但登记表 procStart 和它的启动时间差 10 秒）：判死，同样先防抖 3 秒")
    func r4_pidReuseWithARealProcess() throws {
        let h = Harness()
        let c = try Child()
        defer { c.stop() }
        guard let st = SystemProcessProbe.startTime(of: c.pid) else { Issue.record("sysctl 读不到子进程的启动时间"); return }
        h.tree.writeRegistry(session(pid: c.pid, start: st), status: "busy", markAlive: false)
        let e = engine(h)
        #expect(e.poll().snapshots.first?.presence == .present)
        // 换成一份 procStart 差 10 秒的登记表：等于「这个 pid 现在是另一个进程」
        h.advance(0.1)
        h.tree.writeRegistry(session(pid: c.pid, start: st.addingTimeInterval(-10)), status: "busy", markAlive: false)
        #expect(e.poll().snapshots.first?.presence == .present)                   // 防抖开始（登记表一变就重新探测）
        h.advance(2.9)
        #expect(e.poll().snapshots.first?.presence == .present)
        h.advance(0.2)
        guard case .away? = e.poll().snapshots.first?.presence else { Issue.record("3.1 秒后应该离场"); return }
    }
}
