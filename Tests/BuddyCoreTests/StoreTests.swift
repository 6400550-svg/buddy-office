import Foundation
import Testing
@testable import BuddyCore

/// 线程安全的回调记录器。
final class CallbackRecorder {
    private let lock = NSLock()
    private var _updates: [(at: Date, snaps: [BuddySnapshot])] = []
    private var _events: [BuddyEvent] = []
    func onUpdate(_ s: [BuddySnapshot]) { lock.lock(); _updates.append((Date(), s)); lock.unlock() }
    func onEvent(_ e: BuddyEvent) { lock.lock(); _events.append(e); lock.unlock() }
    var updates: [(at: Date, snaps: [BuddySnapshot])] { lock.lock(); defer { lock.unlock() }; return _updates }
    var events: [BuddyEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    var latest: [BuddySnapshot] { updates.last?.snaps ?? [] }
    func snap(_ key: String) -> BuddySnapshot? { latest.first { $0.key == key } }
    func wait(timeout: TimeInterval = 8, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; Thread.sleep(forTimeInterval: 0.002) }
        return cond()
    }
}

/// 真实的线程 / 定时器 / 文件监听链路（流动的虚拟时钟）。
final class StoreRig {
    let root = FileIO.temporaryDirectory + "buddy-store-" + UUID().uuidString
    let clock = VirtualClock()
    let probe = FakeProcessProbe()
    let tree: FakeClaudeTree
    let rec = CallbackRecorder()
    let store: SessionStore
    let f: DesktopFixture

    init(polling: Bool, tokens: Bool = false) {
        tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        tree.prepare()
        var eo = SessionEngine.Options(paths: tree.paths, now: { [clock] in clock.now() }, probe: probe)
        eo.ledgerQueue = testLedgerQueue()
        eo.persist = false; eo.scanTokens = tokens
        var so = SessionStore.Options(engine: eo)
        so.usePolling = polling
        so.callbackQueue = DispatchQueue(label: "test.callback")
        store = SessionStore(options: so)
        let session = FakeClaudeTree.Session(pid: 1001, sessionId: DesktopFixture.sid, host: DesktopFixture.host, name: "线程测试", startedAt: clock.now().addingTimeInterval(-30))
        f = DesktopFixture(session: session)
        store.onUpdate = { [rec] in rec.onUpdate($0) }
        store.onEvent = { [rec] in rec.onEvent($0) }
    }
    deinit { store.stop(); try? FileManager.default.removeItem(atPath: root) }
    var key: String { DesktopFixture.key }
}

@Suite struct StoreTests {
    @Test func pollingStoreDeliversSnapshotsAndEventsOnTheCallbackQueue() {
        let r = StoreRig(polling: true)
        r.store.start()
        #expect(r.rec.wait { !r.rec.updates.isEmpty })                                  // 启动后马上有第一次（空）回调
        #expect(r.rec.latest.isEmpty)
        r.tree.writeRegistry(r.f.session, status: "idle")
        #expect(r.rec.wait { r.rec.snap(r.key) != nil })
        #expect(r.rec.wait { r.rec.events.contains { $0.key == r.key && $0.kind == .arrived(freshAfterLaunch: true) } })
        r.clock.advance(by: 1)
        r.tree.writeRegistry(r.f.session, status: "busy")
        r.tree.hook(r.f.sid, "UserPromptSubmit")
        #expect(r.rec.wait { r.rec.snap(r.key)?.activity == .thinking })
        r.tree.hook(r.f.sid, "PreToolUse", tool: "Read", detail: "/x")
        #expect(r.rec.wait { if case .tool(let c, _)? = r.rec.snap(r.key)?.activity { return c.name == "Read" } else { return false } })
        #expect(r.store.currentSnapshots.first?.key == r.key)
        let d = r.store.diagnostics()
        #expect(d.sourceStatus.first?.contains("纯轮询") == true)
        #expect(d.liveSessionCount == 1)
    }

    @Test func snapshotCallbacksAreLimitedTo20HzEvenUnderAStreamOfChanges() {
        let r = StoreRig(polling: true)
        r.tree.writeRegistry(r.f.session, status: "busy")
        r.tree.hook(r.f.sid, "UserPromptSubmit")
        r.store.start()
        #expect(r.rec.wait { r.rec.snap(r.key) != nil })
        Thread.sleep(forTimeInterval: 0.3)
        let base = r.rec.updates.count
        let t0 = Date()
        // 1 秒内每 3 ms 一个新工具：每次都会让快照变化
        var i = 0
        while Date().timeIntervalSince(t0) < 1.0 {
            r.clock.advance(by: 0.5)
            r.tree.hook(r.f.sid, "PreToolUse", tool: "Read", detail: "/f\(i)")      // 只有 Pre：每次都是新的一批，快照每个 poll 都在变
            i += 1
            Thread.sleep(forTimeInterval: 0.003)
        }
        Thread.sleep(forTimeInterval: 0.2)
        let n = r.rec.updates.count - base
        #expect(i > 100)
        #expect(n <= 28, "1.2 秒里收到 \(n) 次快照回调，20 Hz 限速应该 ≤ 24 次上下")
        #expect(n >= 3)                                                              // 机器忙时可能少，但不该是 0
    }

    @Test func aHeartbeatArrivesAtLeastOncePerSecondWhenNothingChanges() {
        let r = StoreRig(polling: true)
        r.tree.writeRegistry(r.f.session, status: "idle", statusUpdatedAt: r.clock.now().addingTimeInterval(-3000))
        r.store.start()
        #expect(r.rec.wait { r.rec.snap(r.key) != nil })
        Thread.sleep(forTimeInterval: 0.2)
        let base = r.rec.updates.count
        Thread.sleep(forTimeInterval: 2.5)
        let n = r.rec.updates.count - base
        #expect(n >= 1 && n <= 6, "静止时 2.5 秒里应该收到约 2–3 次心跳，实际 \(n)")
    }

    @Test func timeDrivenChangesHappenOnTimeNotOnTheNextHeartbeat() {
        // 被打断 3 秒 → 空闲：靠 nextWake 精确唤醒，不等 1 秒的心跳
        let r = StoreRig(polling: true)
        r.tree.writeRegistry(r.f.session, status: "busy", statusUpdatedAt: r.clock.now().addingTimeInterval(-10))
        r.tree.hook(r.f.sid, "UserPromptSubmit", at: r.clock.now().addingTimeInterval(-9.9))
        r.store.start()
        #expect(r.rec.wait { r.rec.snap(r.key)?.activity == .thinking })
        Thread.sleep(forTimeInterval: 0.2)
        r.tree.appendTranscript(r.f.sid, [TL.userInterrupt(sessionId: r.f.sid, at: r.clock.now())])
        r.tree.writeRegistry(r.f.session, status: "idle", statusUpdatedAt: r.clock.now())
        #expect(r.rec.wait { r.rec.snap(r.key)?.activity == .interrupted })
        let t0 = Date()
        #expect(r.rec.wait(timeout: 8) { r.rec.snap(r.key)?.activity == .idle })
        let d = Date().timeIntervalSince(t0)
        #expect(d < 5, "被打断显示了 \(d) 秒才消退，应该约 3 秒")
    }

    @Test func stopIsIdempotentAndSilencesCallbacks() {
        let r = StoreRig(polling: true)
        r.store.start()
        r.store.start()                                                               // 重复 start 无害
        #expect(r.rec.wait { !r.rec.updates.isEmpty })
        r.store.stop()
        r.store.stop()
        Thread.sleep(forTimeInterval: 0.2)
        let n = r.rec.updates.count
        r.tree.writeRegistry(r.f.session, status: "busy")
        Thread.sleep(forTimeInterval: 0.4)
        #expect(r.rec.updates.count == n)
    }

    @Test func markSeenAndRerollAreSafeFromAnyThread() {
        let r = StoreRig(polling: true)
        r.tree.writeRegistry(r.f.session, status: "busy")
        r.tree.hook(r.f.sid, "UserPromptSubmit")
        r.store.start()
        #expect(r.rec.wait { r.rec.snap(r.key) != nil })
        r.clock.advance(by: 2)
        r.tree.hook(r.f.sid, "Stop")
        #expect(r.rec.wait { r.rec.snap(r.key)?.unread == true })
        // 用专门的线程而不是 DispatchQueue.global()：整套测试并行跑、很多测试在阻塞等待时，全局队列的线程池会被占满，这一句可能几秒都得不到执行（整套跑时偶发失败过一次）
        Thread.detachNewThread { r.store.markSeen(key: r.key) }
        #expect(r.rec.wait { r.rec.snap(r.key)?.unread == false })
        let salt = r.rec.snap(r.key)!.salt
        Thread.detachNewThread { r.store.rerollAppearance(key: r.key) }
        #expect(r.rec.wait { r.rec.snap(r.key)?.salt == salt &+ 1 })
    }

    @Test func fsEventsModeWorksWhenTheSystemAllowsIt() {
        let r = StoreRig(polling: false)
        r.store.start()
        #expect(r.rec.wait { !r.rec.updates.isEmpty })
        let note = r.store.diagnostics().sourceStatus.first ?? ""
        if note.contains("FSEvents 不可用") {
            // 沙箱里 FSEvents 也许不工作：必须自动退回纯轮询，而且照常工作
            r.tree.writeRegistry(r.f.session, status: "idle")
            #expect(r.rec.wait { r.rec.snap(r.key) != nil })
            return
        }
        #expect(note.contains("FSEvents"))
        Thread.sleep(forTimeInterval: 0.6)                                            // 让监听稳定
        var lats: [Double] = []
        for i in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            let status = i % 2 == 0 ? "busy" : "waiting"
            let t0 = Date()
            r.tree.writeRegistry(r.f.session, status: status, waitingFor: status == "waiting" ? "input needed" : nil)
            let want: Activity = status == "busy" ? .thinking : .asking
            if r.rec.wait(timeout: 2, { r.rec.snap(r.key)?.activity == want }) { lats.append(Date().timeIntervalSince(t0) * 1000) }
        }
        lats.sort()
        #expect(lats.count == 12, "FSEvents 模式下有 \(12 - lats.count) 次没等到")
        #expect((lats.last ?? 0) < 3000)
        print("FSEvents 模式延迟：p50 \(Int(lats[lats.count / 2])) ms, max \(Int(lats.last ?? 0)) ms")
    }
}

@Suite struct FileWatcherTests {
    @Test func reportsFileChangesUnderTheWatchedRoots() {
        let dir = FileIO.temporaryDirectory + "buddy-fsw-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let q = DispatchQueue(label: "test.fsw")
        let lock = NSLock()
        var seen: [String] = []
        let real = FileWatcher.resolved(dir)
        let w = FileWatcher(roots: [dir], queue: q) { paths in lock.lock(); seen.append(contentsOf: paths); lock.unlock() }
        guard w.start() else {
            // FSEvents 在沙箱里可能起不来：这是允许的降级（SessionStore 会退回纯轮询）
            print("FSEvents 不可用（沙箱？），跳过监听断言")
            return
        }
        defer { w.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        FakeClaudeTree.appendBytes(dir + "/1234.json", Data("{}".utf8))
        let end = Date().addingTimeInterval(3)
        var ok = false
        while Date() < end {
            lock.lock(); ok = seen.contains { $0.hasPrefix(real) && $0.hasSuffix("1234.json") }; lock.unlock()
            if ok { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(ok, "没收到文件事件：\(seen)")
        w.stop()
        #expect(!w.isRunning)
    }

    @Test func aWatcherWithNoExistingRootFailsToStart() {
        let w = FileWatcher(roots: ["/nonexistent/buddy/root"], queue: DispatchQueue(label: "x")) { _ in }
        #expect(!w.start())
    }
}

/// 整条回放（进场 → … → 同一个身份回来），走真实的 SessionStore。
@Suite(.serialized) struct ReplayTests {
    @Test func fullReplayPassesWithPolling() {
        let root = FileIO.temporaryDirectory + "buddy-replay-test-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(runReplayCommand(arguments: ["--root", root]) == 0)
    }

    @Test func fullReplayPassesThroughTheFSEventsChainWhenAvailable() {
        let root = FileIO.temporaryDirectory + "buddy-replay-fse-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(runReplayCommand(arguments: ["--root", root, "--fsevents", "--latency", "20"]) == 0)
    }

    @Test func replayRefusesANonEmptyRoot() {
        let root = FileIO.temporaryDirectory + "buddy-replay-nonempty-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: root + "/.claude/sessions", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(runReplayCommand(arguments: ["--root", root]) == 2)          // 绝不往已有数据的目录（比如真实的 home）里写假数据
    }
}
