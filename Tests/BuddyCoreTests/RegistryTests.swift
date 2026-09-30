import Foundation
import Testing
@testable import BuddyCore

@Suite struct RegistryScannerTests {
    /// 用内存里的假文件系统测扫描器（可以精确控制"写了一半"）。
    final class FakeFS {
        var files: [String: Data] = [:]
        var sigs: [String: Int] = [:]
        var opened: [String] = []
        let dir = "/fake/sessions"
        func write(_ name: String, _ s: String) { files[dir + "/" + name] = Data(s.utf8); sigs[dir + "/" + name, default: 0] += 1 }
        func remove(_ name: String) { files[dir + "/" + name] = nil }
        func scanner() -> RegistryScanner {
            RegistryScanner(dir: dir,
                            listDir: { [unowned self] _ in Array(Set(self.files.keys.map { ($0 as NSString).lastPathComponent })) },
                            statFile: { [unowned self] p in
                                guard self.files[p] != nil else { return nil }
                                return FileStat(dev: 1, ino: 1, size: UInt64(self.files[p]!.count), mtimeNs: Int64(self.sigs[p] ?? 0) * 1_000_000_000, isDirectory: false)
                            },
                            readFile: { [unowned self] p in self.opened.append(p); return self.files[p] })
        }
    }

    static let good = #"{"pid":1001,"sessionId":"aaaa-1","cwd":"/x","startedAt":1790654597849,"procStart":"Tue Sep 29 04:03:17 2026","version":"2.1.284","kind":"interactive","entrypoint":"claude-desktop","hostSessionId":"local_1","name":"标题","status":"busy","statusUpdatedAt":1790654598476,"updatedAt":1790654600325}"#
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesEveryField() {
        let fs = FakeFS(); fs.write("1001.json", Self.good)
        let r = fs.scanner().scan(now: Self.t0)
        let rec = r.records[1001]
        #expect(rec?.sessionId == "aaaa-1")
        #expect(rec?.hostSessionId == "local_1")
        #expect(rec?.name == "标题")
        #expect(rec?.status == .busy)
        #expect(rec?.origin == .desktop)
        #expect(rec?.startedAt == Date(timeIntervalSince1970: 1790654597.849))
        #expect(rec?.procStart == Date(timeIntervalSince1970: 1790654597))     // 04:03:17 UTC
        #expect(rec?.statusUpdatedAt == Date(timeIntervalSince1970: 1790654598.476))
    }

    @Test func missingFieldsAreOptionalButPidAndSessionIdAreRequired() {
        let fs = FakeFS()
        fs.write("1.json", #"{"pid":1,"sessionId":"s"}"#)                       // 只有必需字段
        fs.write("2.json", #"{"pid":2}"#)                                        // 缺 sessionId
        fs.write("3.json", #"{"sessionId":"s3"}"#)                               // 缺 pid
        fs.write("4.json", #"{"pid":4,"sessionId":""}"#)                         // sessionId 为空
        let r = fs.scanner().scan(now: Self.t0)
        #expect(Set(r.records.keys) == [1])
        let rec = r.records[1]!
        #expect(rec.cwd == nil && rec.name == nil && rec.status == nil && rec.hostSessionId == nil && rec.procStart == nil)
        #expect(rec.origin == .terminal)                                         // 没有 entrypoint：按终端算
    }

    @Test func unknownFieldsAndUnknownStatusAreTolerated() {
        let fs = FakeFS()
        fs.write("7.json", #"{"pid":7,"sessionId":"s7","futureField":{"a":[1,2,3]},"status":"starting","peerFeatures":["x"],"messagingSocketPath":"/tmp/cc-socks/7.sock"}"#)
        let r = fs.scanner().scan(now: Self.t0)
        #expect(r.records[7] != nil)
        #expect(r.records[7]?.status == nil)                                     // 不认识的 status → nil，记录还在
        #expect(r.records[7]?.statusRaw == "starting")
    }

    @Test func onlyInteractiveSessionsAreShown() {
        let fs = FakeFS()
        for (i, kind) in ["background", "job", "sdk", "spare", "worker", "interactive"].enumerated() {
            fs.write("\(10 + i).json", #"{"pid":\#(10 + i),"sessionId":"s\#(i)","kind":"\#(kind)"}"#)
        }
        fs.write("20.json", #"{"pid":20,"sessionId":"s20"}"#)                    // 没有 kind：当作 interactive
        let r = fs.scanner().scan(now: Self.t0)
        #expect(Set(r.records.keys) == [15, 20])
    }

    @Test func entrypointMapsToOrigin() {
        func origin(_ e: String?) -> SessionOrigin {
            var r = RegistryRecord(pid: 1, sessionId: "s"); r.entrypoint = e; return r.origin
        }
        #expect(origin("claude-desktop") == .desktop)
        #expect(origin("claude-desktop-3p") == .desktop)
        #expect(origin("local-agent") == .desktop)
        #expect(origin("claude-vscode") == .vscode)
        #expect(origin("cli") == .terminal)
        #expect(origin("sdk-ts") == .terminal)
        #expect(origin(nil) == .terminal)
    }

    @Test func halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms() {
        let fs = FakeFS(); fs.write("1001.json", Self.good)
        let sc = fs.scanner()
        var now = Self.t0
        #expect(sc.scan(now: now).records[1001]?.status == .busy)
        // 原地重写到一半：JSON 不完整
        fs.write("1001.json", String(Self.good.prefix(80)))
        now = now.addingTimeInterval(1)
        var r = sc.scan(now: now)
        #expect(r.records[1001]?.status == .busy)                                 // 保留上一份好的
        #expect(r.nextRetry == now.addingTimeInterval(0.05))
        // 50 ms 后重试，最多 5 次
        var retries = 0
        while let t = r.nextRetry, retries < 10 {
            now = t
            r = sc.scan(now: now)
            #expect(r.records[1001]?.status == .busy)
            retries += 1
        }
        #expect(retries == 4)                                                    // 第 1 次读 + 4 次重试 = 共 5 次
        #expect(r.nextRetry == nil)                                              // 之后不再重试，等文件再变
        // 写完整了：立刻更新
        fs.write("1001.json", Self.good.replacingOccurrences(of: "\"busy\"", with: "\"idle\""))
        now = now.addingTimeInterval(1)
        r = sc.scan(now: now)
        #expect(r.records[1001]?.status == .idle)
        #expect(r.changed.contains(1001))
    }

    @Test func emptyFileDuringTruncateIsTreatedAsHalfWritten() {
        let fs = FakeFS(); fs.write("5.json", #"{"pid":5,"sessionId":"s5","status":"idle"}"#)
        let sc = fs.scanner()
        _ = sc.scan(now: Self.t0)
        fs.write("5.json", "")                                                    // O_TRUNC 之后、write 之前的瞬间
        let r = sc.scan(now: Self.t0.addingTimeInterval(1))
        #expect(r.records[5]?.status == .idle)
        #expect(r.nextRetry != nil)
    }

    @Test func removedFilesAreReported() {
        let fs = FakeFS(); fs.write("1001.json", Self.good)
        let sc = fs.scanner()
        _ = sc.scan(now: Self.t0)
        fs.remove("1001.json")
        let r = sc.scan(now: Self.t0.addingTimeInterval(1))
        #expect(r.records.isEmpty)
        #expect(r.removed == [1001])
    }

    @Test func unreadableDirectoryKeepsPreviousRecords() {
        let fs = FakeFS(); fs.write("1001.json", Self.good)
        var readable = true
        let dirPath = fs.dir
        let sc = RegistryScanner(dir: fs.dir, listDir: { _ in readable ? ["1001.json"] : nil },
                                 statFile: { p in (p == dirPath && !readable) ? nil : FileStat(dev: 1, ino: 1, size: 10, mtimeNs: 1, isDirectory: p == dirPath) },
                                 readFile: { _ in Data(Self.good.utf8) })
        #expect(sc.scan(now: Self.t0).records.count == 1)
        readable = false
        let r = sc.scan(now: Self.t0.addingTimeInterval(1))
        #expect(!r.directoryReadable)
        #expect(r.records.count == 1)                                             // 目录读不了 ≠ 所有人都下班了
    }

    @Test func fileNamePattern() {
        #expect(Paths.isRegistryFileName("123.json"))
        #expect(Paths.isRegistryFileName("35991.json"))
        #expect(!Paths.isRegistryFileName("123.abcdef0123.key"))
        #expect(!Paths.isRegistryFileName("123.sha.json"))
        #expect(!Paths.isRegistryFileName("abc.json"))
        #expect(!Paths.isRegistryFileName("12a.json"))
        #expect(!Paths.isRegistryFileName(".json"))
        #expect(!Paths.isRegistryFileName("123.json.bak"))
        #expect(!Paths.isRegistryFileName("123.key"))
    }

    @Test func procStartParsingHandlesPaddingSpaces() {
        let a = TimeUtil.parseProcStart("Tue Sep 29 03:23:08 2026")
        #expect(a == Date(timeIntervalSince1970: 1790652188))
        let b = TimeUtil.parseProcStart("Wed Sep  9 03:23:08 2026")               // 日期个位数时用空格补位
        #expect(b == Date(timeIntervalSince1970: 1788924188))
        #expect(TimeUtil.parseProcStart("garbage") == nil)
        #expect(TimeUtil.parseProcStart("Tue Foo 29 03:23:08 2026") == nil)
        // 往返
        let d = Date(timeIntervalSince1970: 1788924188)
        #expect(TimeUtil.formatProcStart(d) == "Wed Sep  9 03:23:08 2026")
        #expect(TimeUtil.parseProcStart(TimeUtil.formatProcStart(d)) == d)
    }

    @Test func isoTimestampParsing() {
        #expect(TimeUtil.parseISO("2026-09-29T04:12:39.255Z") == Date(timeIntervalSince1970: 1790655159.255))
        #expect(TimeUtil.parseISO("2026-09-29T04:12:39Z") == Date(timeIntervalSince1970: 1790655159))
        #expect(TimeUtil.parseISO("2026-09-29T06:12:39+02:00") == Date(timeIntervalSince1970: 1790655159))
        #expect(TimeUtil.parseISO("2026-09-29T04:12:39.255+0000") == Date(timeIntervalSince1970: 1790655159.255))
        #expect(TimeUtil.parseISO("nope") == nil)
        let d = Date(timeIntervalSince1970: 1790655159.255)
        #expect(TimeUtil.formatISO(d) == "2026-09-29T04:12:39.255Z")
    }
}

@Suite struct ProcessProbeTests {
    let start = Date(timeIntervalSince1970: 1_790_654_597)

    @Test func classification() {
        #expect(ProcessProbe.classify(.init(state: .dead), procStart: start) == .dead)
        #expect(ProcessProbe.classify(.init(state: .unknown), procStart: start) == .alive)            // sysctl 失败：当作还活着
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: start), procStart: start) == .alive)
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: start.addingTimeInterval(1.9)), procStart: start) == .alive)
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: start.addingTimeInterval(2.5)), procStart: start) == .reused)
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: start.addingTimeInterval(-3)), procStart: start) == .reused)
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: nil), procStart: start) == .alive)  // 探测不到启动时间
        #expect(ProcessProbe.classify(.init(state: .alive, startTime: start), procStart: nil) == .alive)  // 登记表没有 procStart
    }

    @Test func systemProbeSeesThisProcess() {
        let p = SystemProcessProbe()
        let me = p.probe(pid: getpid())
        #expect(me.state == .alive)
        if let t = me.startTime {                       // 沙箱里 sysctl 可能失败（nil）；成功时启动时间应该在过去
            #expect(t < Date() && Date().timeIntervalSince(t) < 86400 * 30)
        }
        #expect(p.probe(pid: 1).state == .alive)        // launchd：kill(1, 0) 给 EPERM，按存活算
        #expect(p.probe(pid: 2_000_000_000).state == .dead)
        #expect(p.probe(pid: -5).state == .dead)
    }
}

/// 会读文件的测试放进一个串行的套件里：它们要用全局的 FileIO.openObserver。
@Suite(.serialized) struct FileAccessTests {
    @Test func keyFilesAreNeverOpened() throws {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        // 同目录放一个没有读权限的假 .key（真实的是 <pid>.<sha256>.key）
        let keyPath = h.tree.paths.sessionsDir + "/1001.\(String(repeating: "ab", count: 32)).key"
        FakeClaudeTree.writeInPlace(keyPath, Data("SECRET".utf8))
        chmod(keyPath, 0o000)
        defer { chmod(keyPath, 0o600) }
        var opened: [String] = []
        let lock = NSLock()
        let hitsBefore = FileIO.forbiddenHits
        FileIO.openObserver = { p in lock.lock(); opened.append(p); lock.unlock() }
        defer { FileIO.openObserver = nil }
        for _ in 0..<5 { h.advance(1); h.poll() }
        lock.lock(); let paths = opened; lock.unlock()
        #expect(h.only()?.key == DesktopFixture.key)                          // 正常读到了登记表
        #expect(paths.contains(h.tree.paths.sessionsDir + "/1001.json"))
        #expect(!paths.contains { $0.hasSuffix(".key") })                     // 一次都没碰 .key
        #expect(FileIO.forbiddenHits == hitsBefore)                           // 保险也没被触发（上层根本没想打开）
    }

    @Test func safetyNetRefusesKeyAndSocketPaths() {
        let before = FileIO.forbiddenHits
        #expect(FileIO.open("/nonexistent/dir/1001.abcd.key") == -1)
        #expect(FileIO.open("/tmp/cc-socks/1001.sock") == -1)
        #expect(FileIO.readAll("/x/y/z.key") == nil)
        #expect(FileIO.forbiddenHits == before + 3)
        #expect(FileIO.isForbidden(path: "/Users/a/.claude/sessions/35991.deadbeef.key"))
        #expect(!FileIO.isForbidden(path: "/Users/a/.claude/sessions/35991.json"))
    }

    @Test func codexHookFilesInTheSameDirectoryAreNeverTouched() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        let codex = h.tree.paths.monitorDir + "/019a1111-2222-7333-8444-555566667777.events.jsonl"
        FakeClaudeTree.appendBytes(codex, Data(#"{"ts":1790654600000,"ev":"PreToolUse","tool":"shell","detail":"ls","extra":""}"#.utf8) + Data([10]))
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        var opened: [String] = []
        let lock = NSLock()
        FileIO.openObserver = { p in lock.lock(); opened.append(p); lock.unlock() }
        defer { FileIO.openObserver = nil }
        h.poll(); h.advance(1); h.poll()
        lock.lock(); let paths = opened; lock.unlock()
        #expect(!paths.contains(codex))
        #expect(!paths.contains { $0.contains("019a1111") })
        #expect(paths.contains(h.tree.paths.hookLogPath(sessionId: f.sid)!))
        #expect(h.snapshots.count == 1)                                       // Codex 文件没有变成 buddy
    }

    @Test func engineNeverWritesUnderClaudeDir() {
        // App 运行时绝不写 ~/.claude 下的任何东西：只读打开
        let h = Harness(persist: true, tokens: true)
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "ls")
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        func listing() -> [String: (Int, Int64)] {
            var out: [String: (Int, Int64)] = [:]
            let base = h.tree.paths.claudeDir
            if let e = FileManager.default.enumerator(atPath: base) {
                for case let rel as String in e {
                    if let st = FileIO.stat(base + "/" + rel), !st.isDirectory { out[rel] = (Int(st.size), st.mtimeNs) }
                }
            }
            return out
        }
        let before = listing()
        var wrote = false
        FileIO.openObserver = { _ in }
        defer { FileIO.openObserver = nil }
        for _ in 0..<10 { h.advance(0.5); h.poll() }
        h.engine.flush()
        let after = listing()
        for (k, v) in before { if after[k]?.0 != v.0 || after[k]?.1 != v.1 { wrote = true } }
        #expect(!wrote)
        #expect(after.count == before.count)
        // 自己的数据写在 Application Support/BuddyOffice
        #expect(FileIO.stat(h.tree.paths.identitiesFile) != nil)
    }
}
