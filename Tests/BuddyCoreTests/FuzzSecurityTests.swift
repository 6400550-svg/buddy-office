import Foundation
import Testing
@testable import BuddyCore

// QA · 「绝不打开 *.key / 绝不连接 *.sock」的保护能不能被绕过；FileIO 是不是所有读文件的唯一入口；FileIO 的边界。
// 假的 .key / .sock 都是造出来的假文件（内容也是假的），放在临时目录里。会碰全局计数器 / 观察口的测试放进串行套件 FileAccessTests 的扩展里。

extension FileAccessTests {

    @Test("isForbidden 和独立判断在随机路径上逐个对照（大小写、NUL、cc-socks 目录、.、..、空段、Unicode）")
    func fuzz_forbiddenOracleOnRandomPaths() {
        var rng = FuzzRNG(seed: 0x5EC_0001)
        let comps = ["h", ".claude", "sessions", "1001.json", "1001.abc.key", "1001.abc.KEY", "x.Key", "a.sock", "B.SOCK", "cc-socks", "CC-SOCKS", "Cc-Socks",
                     "cc-socks-x", "xcc-socks", "key", "keys.json", "..", ".", "", "é", "😀", "a\u{0}b", "with space", "new\nline", "x.key.json", "x.sock.bak",
                     "1001.abc.\u{212A}EY", ".KEY", ".sock", "K.ey"]
        func oracle(_ path: String) -> Bool {
            if path.utf8.contains(0) { return true }
            func lower(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.map { $0.value >= 65 && $0.value <= 90 ? Unicode.Scalar($0.value + 32)! : $0 })) }
            let parts = path.split(separator: "/", omittingEmptySubsequences: true).map { lower(String($0)) }
            if parts.contains("cc-socks") { return true }
            guard var last = parts.last else { return false }
            last = last.replacingOccurrences(of: "\u{212A}", with: "k")          // 开尔文符号 K 在大小写不敏感的 APFS 上等于 k
            return last.hasSuffix(".key") || last.hasSuffix(".sock")
        }
        for _ in 0..<30_000 {
            let n = rng.int(0...6)
            var p = rng.chance(0.7) ? "/" : ""
            p += (0..<n).map { _ in rng.pick(comps) }.joined(separator: rng.chance(0.9) ? "/" : "//")
            if rng.chance(0.1) { p += "/" }
            if FileIO.isForbidden(path: p) != oracle(p) { Issue.record("isForbidden(\(p.debugDescription)) = \(FileIO.isForbidden(path: p))，独立判断 \(oracle(p))"); return }
        }
    }

    @Test("各种变体路径（大小写 / ./ / // / .. / 结尾斜杠 / 符号链接链 / 目录符号链接 / 绕过 cc-socks）都打不开假的 .key / .sock；观察口里一个都没有")
    func fuzz_variantsNeverOpenForbiddenFiles() {
        let dir = FuzzDir("sec-variants")
        let keyName = "1001.\(fuzzFakeSha).key"
        dir.write(keyName, "FAKE-KEY-CONTENT-NOT-A-REAL-SECRET")
        dir.write("agent.sock", "FAKE-SOCK-CONTENT")
        try? FileManager.default.createDirectory(atPath: dir.file("cc-socks"), withIntermediateDirectories: true)
        dir.write("cc-socks/x.txt", "FAKE-IN-CC-SOCKS")
        try? FileManager.default.createDirectory(atPath: dir.file("sub"), withIntermediateDirectories: true)
        symlink(dir.file(keyName), dir.file("link1"))
        symlink(dir.file("link1"), dir.file("link2"))                       // 链
        symlink(dir.file("link2"), dir.file("1003.json"))                   // 名字合法的登记表文件名 → 链 → .key
        symlink(dir.file("agent.sock"), dir.file("1002.json"))
        symlink(dir.path, dir.file("dirlink"))                              // 目录符号链接（指向自己所在目录）
        symlink(dir.file("cc-socks"), dir.file("cc-alias"))                 // 目录符号链接绕过 cc-socks
        symlink("cc-socks", dir.file("sub/rel-alias"))                      // 相对目标的符号链接（相对 sub/ 解析成 sub/cc-socks：不存在）
        symlink("../" + keyName, dir.file("sub/rel-key"))                   // 相对符号链接指向上一层的 .key
        let base = dir.path
        let variants: [String] = [
            base + "/" + keyName, base + "/" + keyName.uppercased(), base + "/./" + keyName, base + "//" + keyName, base + "/sub/../" + keyName,
            base + "/" + keyName + "/", base + "/" + keyName + "/.", base + "/" + keyName + "/..",
            base + "/agent.sock", base + "/AGENT.SOCK", base + "/Agent.Sock",
            base + "/link1", base + "/link2", base + "/1003.json", base + "/1002.json", base + "/sub/rel-key",
            base + "/dirlink/" + keyName, base + "/dirlink/dirlink/dirlink/" + keyName, base + "/dirlink/1003.json", base + "/sub/../dirlink/link1",
            base + "/cc-socks/x.txt", base + "/CC-SOCKS/x.txt", base + "/cc-alias/x.txt", base + "/dirlink/cc-alias/x.txt", base + "/dirlink/cc-socks/x.txt",
            base + "/" + keyName + "\u{0}.json", base + "/x\u{0}",
        ]
        let observed = FuzzBox<[String]>([])
        FileIO.openObserver = { p in if p.hasPrefix(dir.path) { observed.value.append(p) } }      // 观察口是进程全局的：并行跑的别的套件在它们自己临时目录里的 open 不算（R3a P2-1）
        defer { FileIO.openObserver = nil }
        let hits0 = FileIO.forbiddenHits
        var refused = 0
        for v in variants {
            let fd = FileIO.open(v)
            if fd >= 0 { close(fd); Issue.record("打开了不该打开的路径：\(v.replacingOccurrences(of: base, with: "<dir>").debugDescription)") }
            if FileIO.readAll(v) != nil { Issue.record("读到了不该读的路径：\(v.replacingOccurrences(of: base, with: "<dir>").debugDescription)") }
            refused += 1
        }
        #expect(refused == variants.count)
        #expect(FileIO.forbiddenHits > hits0)
        // 观察口：只有“真的要去打开”的路径才会被报告，被保险挡掉的（含符号链接、目录符号链接）一个都不该出现
        let bad = observed.value.filter { p in
            let l = p.lowercased()
            return l.hasSuffix(".key") || l.hasSuffix(".sock") || l.contains("/cc-socks/") || l.contains("cc-alias") || l.contains("link") || l.contains("1003.json") || l.contains("1002.json") || l.contains("rel-key")
        }
        #expect(bad.isEmpty, "这些路径被交给了 open：\(bad.map { $0.replacingOccurrences(of: base, with: "<dir>") })")
        // 对照：正常的文件照样能读
        dir.write("ok.json", #"{"a":1}"#)
        #expect(FileIO.readAll(dir.file("ok.json")) != nil)
        #expect(FileIO.readAll(dir.file("dirlink/ok.json")) != nil)
    }

    @Test("登记表目录里一堆诱饵（假 .key / 名字差一点点的 / 目录 / FIFO / 指向 .key 的符号链接）：只读合法的 <pid>.json，绝不打开 .key，记录不含任何诱饵的内容")
    func fuzz_registryScannerWithDecoyFiles() {
        let dir = FuzzDir("sec-registry")
        func reg(_ pid: Int, _ sid: String) -> String { #"{"pid":\#(pid),"sessionId":"\#(sid)","kind":"interactive","status":"idle"}"# }
        dir.write("1001.json", reg(1001, "sid-1001"))
        dir.write("1002.json", "not json {{{")
        dir.write("1003.json", reg(1003, "sid-1003"))
        dir.write("00007.json", reg(7, "sid-7"))
        let keyPath = dir.file("1001.\(fuzzFakeSha).key")
        dir.write("1001.\(fuzzFakeSha).key", reg(1001, "SECRET-FROM-KEY-FILE"))                  // 万一被读到，内容看起来像合法记录：sessionId 会泄露出来
        chmod(keyPath, 0o000)
        dir.write("1004.\(fuzzFakeSha).key", reg(1004, "SECRET-FROM-KEY-FILE-2"))                // 可读的假 .key
        for name in ["abc.json", "12a.json", ".json", " 12.json", "12.JSON", "12.json.bak", "٣٤.json", "99999999999.json", "12345678901234567890.json",
                     "new\nline.json", "1010.json.key", "1011.KEY", "1012.sock"] { dir.write(name, reg(1099, "SECRET-FROM-DECOY")) }
        try? FileManager.default.createDirectory(atPath: dir.file("1005.json"), withIntermediateDirectories: true)
        symlink(dir.file("1004.\(fuzzFakeSha).key"), dir.file("1006.json"))
        #expect(mkfifo(dir.file("1007.json"), 0o600) == 0)
        symlink(dir.file("1001.json"), dir.file("1008.json"))
        let allowedSids: Set<String> = ["sid-1001", "sid-1003", "sid-7"]
        let observed = FuzzBox<[String]>([])
        FileIO.openObserver = { p in if p.hasPrefix(dir.path) { observed.value.append(p) } }      // 同上：只记自己临时目录里的 open（R3a P2-1）
        defer { FileIO.openObserver = nil; chmod(keyPath, 0o600) }
        let hits0 = FileIO.forbiddenHits
        let scanner = RegistryScanner(dir: dir.path)
        let lastBox = FuzzBox(RegistryScanner.ScanResult())
        let finished = fuzzRun("registry scan with decoys", timeout: 30) { r in
            var now = Harness.epoch
            for _ in 0..<8 {
                let res = scanner.scan(now: now)
                lastBox.value = res
                now = now.addingTimeInterval(0.06)
                r.check(res.records.values.allSatisfy { allowedSids.contains($0.sessionId) }, "出现了不该有的记录：\(res.records.values.map { $0.sessionId })")
                r.check(res.records.keys.allSatisfy { [1001, 1003, 7, 1008].contains($0) }, "出现了不该有的 pid：\(res.records.keys.sorted())")
            }
        }
        #expect(finished)
        let last = lastBox.value
        #expect(last.records[1001]?.sessionId == "sid-1001" && last.records[1003]?.sessionId == "sid-1003" && last.records[7]?.sessionId == "sid-7")
        #expect(last.records[1002] == nil && last.records[1006] == nil && last.records[1007] == nil && last.records[1005] == nil)
        #expect(last.fileCount == 8, "匹配 ^\\d+\\.json$ 的文件数应为 8：\(last.fileCount)")
        // 观察口：只有匹配 ^\d+\.json$ 的路径被 open 过；一个 .key / .sock / 诱饵都没有
        let names = Set(observed.value.map { ($0 as NSString).lastPathComponent })
        #expect(names.allSatisfy { Paths.isRegistryFileName($0) }, "被 open 的文件名里有不匹配 ^\\d+\\.json$ 的：\(names.filter { !Paths.isRegistryFileName($0) })")
        #expect(!observed.value.contains { $0.lowercased().hasSuffix(".key") || $0.lowercased().hasSuffix(".sock") })
        #expect(FileIO.forbiddenHits > hits0, "指向 .key 的符号链接 1006.json 应该被保险拒绝过")
    }

    /// R3a P2-1：`FileIO.openObserver` 是进程全局的，并行跑的别的套件在它们自己临时目录里的 open 也会被观察到。
    /// 上面两条测试原来把观察到的每个路径都当成自己的：默认并行的 `swift test` 里 8 次红 2 次（被观察到 `agent-….jsonl` / `….events.jsonl`）。
    /// 这条让另一个线程在测试期间不停地打开别处的文件，再原样调用那条测试：观察口按自己的临时目录过滤之后，它不受影响。
    @Test("R3a P2-1 登记表诱饵测试不受并行套件的 open 影响：另一个线程一直在打开别处的 jsonl 文件时，它仍然通过")
    func r3aP21_theRegistryDecoyTestIsNotFooledByOtherThreadsOpens() {
        let other = FuzzDir("noisy-neighbour")
        other.write("neighbour.events.jsonl", "{}\n")
        let stop = FuzzBox<Bool>(false)
        let done = DispatchSemaphore(value: 0)
        Thread {
            while !stop.value { let fd = FileIO.open(other.file("neighbour.events.jsonl")); if fd >= 0 { close(fd) }; Thread.sleep(forTimeInterval: 0.0005) }
            done.signal()
        }.start()
        defer { stop.value = true; done.wait() }
        fuzz_registryScannerWithDecoyFiles()
    }

    // 触发保险（forbiddenHits 是全局计数器）的测试必须和 FileAccessTests 里的断言串行，所以放在这个扩展里
    @Test("句柄泄漏：把所有读取器（FileIO / JSONLTailer / 登记表 / 桌面元数据 / 子代理 / 账本 / FileWatcher）在各种文件（正常 / 目录 / FIFO / .key / 符号链接 / 不存在 / 被删）上反复跑几千次，文件描述符个数不涨")
    func noFileDescriptorLeaksAcrossReaders() {
        let dir = FuzzDir("fd-leak")
        let keyName = "1001.\(fuzzFakeSha).key"
        dir.write("ok.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m1")) + FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m2")))
        dir.write("1001.json", #"{"pid":1001,"sessionId":"s"}"#)
        dir.write(keyName, "FAKE")
        try? FileManager.default.createDirectory(atPath: dir.file("adir.json"), withIntermediateDirectories: true)
        mkfifo(dir.file("fifo.json"), 0o600)
        symlink(dir.file(keyName), dir.file("1002.json"))
        symlink(dir.file("ok.jsonl"), dir.file("link.jsonl"))
        let meta = dir.file("meta/acct/org")
        try? FileManager.default.createDirectory(atPath: meta, withIntermediateDirectories: true)
        dir.write("meta/acct/org/local_a.json", #"{"sessionId":"local_a","cliSessionId":"c"}"#)
        let sub = dir.file("sess/subagents")
        try? FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        dir.write("sess/subagents/agent-a.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "s1", at: Date(), stop: "tool_use")))
        dir.write("sess/subagents/agent-a.meta.json", #"{"description":"d"}"#)
        let paths = ["ok.jsonl", "adir.json", "fifo.json", keyName, "1002.json", "link.jsonl", "nonexistent", "1001.json"].map { dir.file($0) }
        let before = FuzzFileIOTests.openDescriptorCount()
        let finished = fuzzRun("fd leak", timeout: 120) { r in
            let scanner = RegistryScanner(dir: dir.path)
            let metaReader = DesktopMetaReader(rootDir: dir.file("meta"))
            let helpers = SubagentReader(sessionDir: dir.file("sess"))
            let ledger = TokenLedger(ledgerPath: dir.file("ledger.json"), queue: testLedgerQueue())
            ledger.setGroup(key: "k", transcripts: [dir.file("ok.jsonl")], helpers: [])
            let tailers = paths.map { JSONLTailer(path: $0) }
            for i in 0..<400 {
                for p in paths {
                    _ = FileIO.readAll(p)
                    let fd = FileIO.open(p); if fd >= 0 { close(fd) }
                }
                for t in tailers { t.poll { _ in }; if i % 50 == 0 { t.seekToTail(window: 10); t.rewind() } }
                _ = scanner.scan(now: Date().addingTimeInterval(Double(i)))
                _ = metaReader.refresh()
                helpers.poll(now: Date().addingTimeInterval(Double(i)), list: true)
                if i % 20 == 0 { ledger.poke(); _ = ledger.waitUntilIdle(timeout: 60); ledger.flush() }
                if i % 100 == 0 { FakeClaudeTree.appendBytes(dir.file("ok.jsonl"), FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "x\(i)"))) }
            }
            // FSEvents 流：反复启动 / 停止
            for _ in 0..<40 {
                let w = FileWatcher(roots: [FileWatcher.resolved(dir.path)], queue: DispatchQueue(label: "fd-leak-fw"), latency: 0.01) { _ in }
                _ = w.start(); w.stop()
            }
            ledger.cancel()
            r.check(true, "")
        }
        #expect(finished)
        // FSEvents 流停掉之后，它占的 fd（每个流约 10 个）由系统在后台异步关掉：机器忙时 0.3 秒不够（40 个流约 440 个，R5b-01）。
        // 等 fd 数回落（最多 15 秒）再断言；真泄漏的话几千次读取之后是几千个，回落不了
        var after = FuzzFileIOTests.openDescriptorCount()
        let settle = Date().addingTimeInterval(15)
        while after - before > 150, Date() < settle { Thread.sleep(forTimeInterval: 0.1); after = FuzzFileIOTests.openDescriptorCount() }
        // 其它测试也在并行地开关文件，允许一点波动；泄漏的话是几千个
        #expect(after - before <= 150, "文件描述符从 \(before) 涨到了 \(after)")
    }
}

// MARK: - FileIO 的边界和“唯一入口”

@Suite struct FuzzFileIOTests {

    /// 项目根目录：从这个测试文件往上找，直到有 Sources/BuddyCore/Util/FileIO.swift。
    static func repoRoot(from file: String = #filePath) -> String? {
        var dir = (file as NSString).deletingLastPathComponent
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir + "/Sources/BuddyCore/Util/FileIO.swift") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    @Test("FileIO 是 BuddyCore 里读文件的唯一入口：源码里除了 FileIO.swift（读）和 Tools/FakeTree.swift（造假数据的写）之外，没有任何别的 open / fopen / FileHandle / Data(contentsOf:) 之类")
    func fileIOIsTheOnlyReaderInSources() throws {
        let root = try #require(Self.repoRoot(), "找不到项目根目录")
        let core = root + "/Sources/BuddyCore"
        let bannedSubstrings = ["Darwin.open(", "fopen(", "freopen(", "FileHandle(forReading", "FileHandle(forUpdating", "FileHandle(forWritingTo", "FileHandle(fileDescriptor",
                                "Data(contentsOf", "NSData(contentsOf", "String(contentsOf", "String(contentsOfFile", "NSString(contentsOf", "contentsOfFile",
                                "FileManager.default.contents(", "InputStream(", "mmap(", "readLine(", "dlopen(", "posix_spawn", "Process()", "NSTask", "system("]
        let bareOpen = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])open\("#)
        let bareRead = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])p?read\("#)
        let allowOpen: Set<String> = ["Util/FileIO.swift", "Tools/FakeTree.swift"]
        let allowPread: Set<String> = ["Util/FileIO.swift", "Ingest/JSONLTailer.swift"]                 // pread 读的是 FileIO.open 给的 fd
        var scanned = 0
        var problems: [String] = []
        let e = try #require(FileManager.default.enumerator(atPath: core))
        for case let rel as String in e where rel.hasSuffix(".swift") {
            scanned += 1
            let text = try String(contentsOfFile: core + "/" + rel, encoding: .utf8)
            for (i, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var line = String(rawLine)
                if let c = line.range(of: "//") { line = String(line[..<c.lowerBound]) }             // 去掉注释（字符串里的 // 也会被去掉，只会放过更多，不会误报）
                let ns = line as NSString
                let full = NSRange(location: 0, length: ns.length)
                if !allowOpen.contains(rel) {
                    for b in bannedSubstrings where line.contains(b) { problems.append("\(rel):\(i + 1) 含 \(b)") }
                    if bareOpen.firstMatch(in: line, range: full) != nil { problems.append("\(rel):\(i + 1) 直接调用了 open(") }
                }
                if !allowPread.contains(rel), bareRead.firstMatch(in: line, range: full) != nil, !allowOpen.contains(rel) { problems.append("\(rel):\(i + 1) 直接调用了 read(/pread(") }
            }
        }
        #expect(scanned >= 25, "只扫描了 \(scanned) 个源文件")
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("readAll / open 遇到特殊文件：目录 / 设备 / 空文件 / 恰好等于上限 / 超过上限 / 负数上限 / 读的时候被截断：不崩溃、不卡死，结果合理")
    func specialFiles() {
        let dir = FuzzDir("fileio-special")
        try? FileManager.default.createDirectory(atPath: dir.file("d.json"), withIntermediateDirectories: true)
        dir.write("empty", Data())
        dir.write("ten", "0123456789")
        #expect(FileIO.readAll(dir.file("d.json")) == nil)
        #expect(FileIO.open(dir.path) == -1)
        #expect(FileIO.readAll("/dev/null") == nil && FileIO.open("/dev/zero") == -1 && FileIO.open("/dev/random") == -1)
        #expect(FileIO.readAll(dir.file("empty"))?.count == 0)
        #expect(FileIO.readAll(dir.file("ten"), maxBytes: 10)?.count == 10)
        #expect(FileIO.readAll(dir.file("ten"), maxBytes: 9) == nil)
        #expect(FileIO.readAll(dir.file("ten"), maxBytes: 0) == nil && FileIO.readAll(dir.file("ten"), maxBytes: -1) == nil && FileIO.readAll(dir.file("ten"), maxBytes: Int.min) == nil)
        #expect(FileIO.readAll(dir.file("ten"), maxBytes: Int.max)?.count == 10)
        #expect(FileIO.readAll(dir.file("nonexistent")) == nil && FileIO.readAll("") == nil && FileIO.readAll("/") == nil)
        #expect(FileIO.stat("") == nil && FileIO.stat(dir.file("nonexistent")) == nil && FileIO.stat(dir.path)?.isDirectory == true)
        #expect(FileIO.listDirectory(dir.file("ten")) == nil && FileIO.listDirectory("") == nil && FileIO.listDirectory(dir.file("nonexistent")) == nil)
        #expect(Set(FileIO.listDirectory(dir.path) ?? []) == ["d.json", "empty", "ten"])
        // Unix socket 文件（路径要够短：sun_path 只有 104 字节）
        let sockDir = "/tmp/bs\(getpid())"
        try? FileManager.default.createDirectory(atPath: sockDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: sockDir) }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sockPath = sockDir + "/x.json"
        _ = sockPath.withCString { src in withUnsafeMutablePointer(to: &addr.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, src, 103) } } }
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        if bound == 0 {
            #expect(FileIO.readAll(sockPath) == nil)
            #expect(FileIO.open(sockPath) == -1)
        }
        close(s)
        // 读的时候文件被另一个线程反复截断 / 追加：不崩溃，结果要么是某个时刻的内容（长度不超过写入的最大值）要么 nil
        let stop = FuzzBox(false)
        let writer = Thread {
            var i = 0
            while !stop.value {
                if i % 2 == 0 { Darwin.truncate(dir.file("race"), off_t((i * 7919) % 5000)) } else { FakeClaudeTree.appendBytes(dir.file("race"), Data(repeating: 0x41, count: (i * 31) % 800)) }
                i += 1
            }
        }
        FakeClaudeTree.appendBytes(dir.file("race"), Data(repeating: 0x41, count: 100))
        writer.start()
        let finished = fuzzRun("readAll race", timeout: 30) { r in
            for _ in 0..<3000 { if let d = FileIO.readAll(dir.file("race"), maxBytes: 1 << 20) { r.check(d.allSatisfy { $0 == 0x41 || $0 == 0 }, "读到了别的内容") } }
        }
        stop.value = true
        #expect(finished)
    }

    @Test("writeAtomically 的边界：嵌套目录 / 父路径是文件 / 目标是目录 / 名字太长 / Unicode 和换行 / 只读目录 / 空数据：返回值正确、不留临时文件")
    func writeAtomicallyEdgeCases() {
        let dir = FuzzDir("fileio-write")
        func leftovers() -> [String] { (FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []).filter { $0.contains(".tmp") } }
        #expect(FileIO.writeAtomically(Data("x".utf8), to: dir.file("a/b/c/d.json")))
        #expect(dir.read("a/b/c/d.json") == Data("x".utf8))
        dir.write("afile", "x")
        #expect(!FileIO.writeAtomically(Data("x".utf8), to: dir.file("afile/child.json")))                      // 父路径是文件
        try? FileManager.default.createDirectory(atPath: dir.file("adir/keep"), withIntermediateDirectories: true)
        #expect(!FileIO.writeAtomically(Data("x".utf8), to: dir.file("adir")))                                     // 目标是（非空）目录
        #expect(!FileIO.writeAtomically(Data("x".utf8), to: dir.file(String(repeating: "n", count: 300) + ".json")))   // 名字太长
        for name in ["带 空格.json", "中文.json", "emoji😀.json", "new\nline.json", "quote\".json", String(repeating: "长", count: 80) + ".json"] {
            #expect(FileIO.writeAtomically(Data(name.utf8), to: dir.file(name)), "\(name.debugDescription)")
            #expect(dir.read(name) == Data(name.utf8))
        }
        #expect(FileIO.writeAtomically(Data(), to: dir.file("empty.json")))
        #expect(dir.read("empty.json") == Data())
        try? FileManager.default.createDirectory(atPath: dir.file("ro"), withIntermediateDirectories: true)
        chmod(dir.file("ro"), 0o500)
        let ok = FileIO.writeAtomically(Data("x".utf8), to: dir.file("ro/x.json"))
        chmod(dir.file("ro"), 0o700)
        if getuid() != 0 { #expect(!ok, "只读目录里居然写成功了") }
        #expect(leftovers().isEmpty, "留下了临时文件：\(leftovers())")
        #expect(FileIO.writeAtomically(Data("again".utf8), to: dir.file("ro/x.json")))                          // 恢复权限后能写
    }

    @Test("C-024 多个线程同时原子写同一个文件：读到的永远是某一次完整的内容，不会是两次写的混合（临时文件名不能共用）")
    func c024_concurrentAtomicWritersNeverProduceMixedContent() {
        let dir = FuzzDir("fileio-concurrent")
        let path = dir.file("shared.json")
        // 四个写者的内容长度都不同（字节值也不同）：共用临时文件时，后写的短内容盖在先写的长内容前面，就会得到“混合”的文件
        let sizes = [40_000, 120_000, 200_000, 280_000]
        let payloads: [Data] = (0..<4).map { Data(repeating: UInt8(0x61 + $0), count: sizes[$0]) }
        func isWhole(_ d: Data) -> Bool {
            guard let f = d.first, f >= 0x61, f < 0x65 else { return false }
            return d.count == sizes[Int(f - 0x61)] && d.last == f && d[d.count / 2] == f && d[d.count / 4] == f
        }
        let stop = FuzzBox(false)
        let mixed = FuzzBox(0)
        let reads = FuzzBox(0)
        let reader = Thread {
            while !stop.value {
                if let d = FileManager.default.contents(atPath: path), !d.isEmpty {
                    reads.value += 1
                    if !isWhole(d) { mixed.value += 1 }
                }
                Thread.sleep(forTimeInterval: 0.0002)              // 别把 CPU 占满（不然写者在慢的机器 / 消毒器下会被饿死）
            }
        }
        reader.start()
        let done = DispatchGroup()
        for w in 0..<4 {
            DispatchQueue.global().async(group: done) { for _ in 0..<60 { _ = FileIO.writeAtomically(payloads[w], to: path) } }
        }
        #expect(done.wait(timeout: .now() + 600) == .success)         // 正常几秒；机器被别的编译压得很满时会慢很多，只是别让它误报
        stop.value = true
        Thread.sleep(forTimeInterval: 0.05)
        let final = FileManager.default.contents(atPath: path) ?? Data()
        #expect(isWhole(final), "最终文件不是任何一次完整写入的内容（长度 \(final.count)）")
        #expect(mixed.value == 0, "读到了 \(mixed.value) 次混合 / 不完整的内容（共读 \(reads.value) 次）")
        let leftovers = (FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []).filter { $0.contains(".tmp") }
        #expect(leftovers.isEmpty, "留下了临时文件：\(leftovers)")
    }

    /// 当前进程打开着的文件描述符个数（逐个 fcntl 探测）。
    static func openDescriptorCount() -> Int {
        var n = 0
        for fd in 0..<4096 where fcntl(Int32(fd), F_GETFD) != -1 { n += 1 }
        return n
    }
}
