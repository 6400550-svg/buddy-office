import Foundation
import Testing
@testable import BuddyCore

/// 各种脏数据 / 半截文件 / 被删被换的文件：引擎不能崩，也不能被脏数据卡死。
@Suite struct RobustnessTests {
    struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 29)
        }
    }

    @Test func randomGarbageInEveryDataSourceNeverCrashesTheEngine() {
        for seed in [0xB0DD1E5, 0x5EEDBEEF, 0x1234567] as [UInt64] { runChaos(seed: seed) }
    }

    func runChaos(seed: UInt64) {
        let h = Harness(tokens: true)
        let f = DesktopFixture(h: h)
        let hook = h.tree.paths.hookLogPath(sessionId: f.sid)!
        let transcript = h.tree.transcriptPath(f.sid)
        let reg = h.tree.paths.sessionsDir + "/1001.json"
        var rng = SeededRandom(state: seed)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.poll()

        func junk(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }) }
        let goodHook = FakeClaudeTree.jsonLine(["ts": TimeUtil.millis(h.now), "ev": "PreToolUse", "tool": "Bash", "detail": "x", "extra": ""])
        let goodLine = FakeClaudeTree.jsonLine(TL.assistant(sessionId: f.sid, at: h.now, messageId: "m", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 5)))
        for i in 0..<400 {
            switch Int.random(in: 0..<14, using: &rng) {
            case 0: FakeClaudeTree.appendBytes(hook, junk(Int.random(in: 1...300, using: &rng)))
            case 1: FakeClaudeTree.appendBytes(transcript, junk(Int.random(in: 1...300, using: &rng)))
            case 2: FakeClaudeTree.appendBytes(hook, goodHook.prefix(Int.random(in: 1..<goodHook.count, using: &rng)))       // 半截行
            case 3: FakeClaudeTree.appendBytes(transcript, goodLine.prefix(Int.random(in: 1..<goodLine.count, using: &rng)))
            case 4: Darwin.truncate(hook, off_t(Int.random(in: 0...50, using: &rng)))
            case 5: Darwin.truncate(transcript, off_t(Int.random(in: 0...50, using: &rng)))
            case 6: try? FileManager.default.removeItem(atPath: hook)
            case 7: try? FileManager.default.removeItem(atPath: transcript)
            case 8: FakeClaudeTree.writeInPlace(reg, junk(Int.random(in: 0...200, using: &rng)))                        // 登记表被写坏
            case 9: FakeClaudeTree.writeInPlace(reg, Data(String(decoding: goodHook, as: UTF8.self).utf8))              // 合法 JSON 但不是登记表
            case 10: h.tree.writeRegistry(f.session, status: ["busy", "idle", "waiting", "weird"].randomElement(using: &rng)!, waitingFor: ["permission prompt", "input needed", nil, "???"].randomElement(using: &rng)!)
            case 11: FakeClaudeTree.appendBytes(hook, goodHook); FakeClaudeTree.appendBytes(transcript, goodLine)
            case 12: h.advance(Double.random(in: 0...400, using: &rng))
            default: h.tree.appendSubagent(f.sid, agentId: "zz\(i % 3)", [["type": "assistant", "junk": true]]); FakeClaudeTree.appendBytes(h.tree.subagentDir(f.sid) + "/agent-zz\(i % 3).jsonl", junk(40))
            }
            h.advance(0.05)
            h.poll()
        }
        // 之后写入好数据，引擎照常工作
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.hook(f.sid, "UserPromptSubmit"); h.advance(0.2)
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/after/the/storm")
        h.advance(0.3); h.poll(); h.advance(0.3); h.poll()
        #expect(h.snapshots.count == 1)
        guard case .tool(let c, _)? = h.snap(DesktopFixture.key)?.activity else {
            Issue.record("乱七八糟之后应该恢复：\(String(describing: h.snap(DesktopFixture.key)?.activity))"); return
        }
        #expect(c.name == "Read" && c.detail == "/after/the/storm")
    }

    @Test func aTailerSurvivesTheFileBeingRewrittenUnderneathIt() {
        // 读的同时另一个线程在追加 / 截断 / 删除重建（打开文件之后 size 可能比 offset 小：曾经会无符号下溢崩溃）
        let f = TempFile(name: "race")
        f.write("start\n")
        let t = JSONLTailer(path: f.path)
        let stop = ManagedFlag()
        let writer = Thread {
            var i = 0
            while !stop.value {
                switch i % 5 {
                case 0: f.append(String(repeating: "x", count: 5000) + "\n")
                case 1: f.truncate(to: (i * 37) % 3000)
                case 2: f.write("short \(i)\n")
                case 3: f.replaceWithNewInode(String(repeating: "y\n", count: 800))
                default: f.append("tail \(i)")
                }
                i += 1
            }
        }
        writer.start()
        let end = Date().addingTimeInterval(1.5)
        var total = 0
        while Date() < end { t.poll { _ in total += 1 } }
        stop.value = true
        Thread.sleep(forTimeInterval: 0.05)
        #expect(total > 0)
    }

    final class ManagedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _v = false
        var value: Bool { get { lock.lock(); defer { lock.unlock() }; return _v } set { lock.lock(); _v = newValue; lock.unlock() } }
    }

    @Test func aHugeGarbageLineDoesNotStallTheHookReader() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.poll()
        // 6 MiB 没有换行的垃圾，之后才是正常事件
        h.tree.appendHook(f.sid, Data(repeating: 0x41, count: 6 << 20))
        h.advance(0.1); h.poll()
        h.tree.appendHook(f.sid, Data("\n".utf8))
        h.tree.hook(f.sid, "PreToolUse", tool: "Grep", detail: "still works")
        h.advance(0.1); h.poll()
        guard case .tool(let c, _)? = h.snap(DesktopFixture.key)?.activity else { Issue.record("超长垃圾行之后应该继续工作"); return }
        #expect(c.name == "Grep")
    }

    @Test func aRegistryFileThatIsADirectoryOrHasWeirdTypesIsIgnored() {
        let h = Harness()
        try? FileManager.default.createDirectory(atPath: h.tree.paths.sessionsDir + "/777.json", withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(h.tree.paths.sessionsDir + "/778.json", Data(#"{"pid":"not a number","sessionId":42}"#.utf8))
        FakeClaudeTree.writeInPlace(h.tree.paths.sessionsDir + "/779.json", Data(#"[1,2,3]"#.utf8))
        FakeClaudeTree.writeInPlace(h.tree.paths.sessionsDir + "/780.json", Data(#"{"pid":780,"sessionId":"s780","status":123,"startedAt":"yesterday","cwd":42}"#.utf8))
        h.poll()
        // 只有 780 是勉强可用的记录（必需字段齐全，其他字段类型不对就当作没有）
        #expect(h.snapshots.count <= 1)
        if let s = h.snapshots.first { #expect(s.pid == 780); #expect(s.cwd == nil) }
    }

    @Test func pathsWithSpecialCharactersWork() {
        let h = Harness()
        let s = FakeClaudeTree.Session(pid: 1234, sessionId: "abcdef00-0000-4000-8000-000000000123", host: "local_special",
                                       name: "标题 with \"quotes\" 和 emoji 🙂", startedAt: h.now)
        h.tree.writeRegistry(s, status: "idle")
        h.poll()
        #expect(h.only()?.title == "标题 with \"quotes\" 和 emoji 🙂")
    }
}
