import Foundation
import MachO
import Testing
@testable import BuddyCore

/// QA（逻辑线）：
///  1. 证明 `buddyctl dump` / `buddydump` 和 App 走的是**同一条数据链路**（SessionStore → SessionEngine）：
///     结构上（源码里 DumpCommand 只造 SessionStore、不自己读数据源；App 的 RealProvider 也只造 SessionStore；
///     两个可执行文件都只转发 runDumpCommand），行为上（同一棵假 home 树，真的 dump 可执行文件的输出
///     和 App 用的构造方式 / 直接用引擎算出来的结果逐字段相同）。
///  2. 在同一棵 FakeTree 上跑 QA/tools 里的两个 Python 脚本（token_crosscheck.py / dump_vs_registry.py），
///     并用手算的 token 期望值当第三个口径。
/// 假 home 树里的会话用**真的 pid**（测试进程自己和它的父进程），这样 dump 可执行文件里真的 SystemProcessProbe 也认为它们活着。
@Suite(.serialized) struct StateRuleChainTests {
    // MARK: 定位

    static func repoRoot(from file: String = #filePath) -> String? {
        if let e = ProcessInfo.processInfo.environment["BUDDY_REPO_ROOT"], FileManager.default.fileExists(atPath: e + "/QA/tools/token_crosscheck.py") { return e }
        var dir = (file as NSString).deletingLastPathComponent
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir + "/QA/tools/token_crosscheck.py"),
               FileManager.default.fileExists(atPath: dir + "/Sources/BuddyCore/Tools/DumpCommand.swift") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// 测试包（.xctest）所在的产物目录：buddyctl / buddydump 就在它旁边。
    static func productsDirectory() -> String? {
        for b in Bundle.allBundles where b.bundlePath.hasSuffix(".xctest") {
            return (b.bundlePath as NSString).deletingLastPathComponent
        }
        for i in 0..<_dyld_image_count() {
            guard let c = _dyld_get_image_name(i) else { continue }
            let p = String(cString: c)
            if let r = p.range(of: ".xctest/") { return (String(p[..<r.lowerBound]) as NSString).deletingLastPathComponent }
        }
        return nil
    }

    static func dumpExecutable() -> String? {
        guard let dir = productsDirectory() else { return nil }
        for n in ["buddyctl", "buddydump"] {
            let p = dir + "/" + n
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// buddyctl 有 dump 子命令；buddydump 本身就是 dump。
    static func dumpArguments(_ exe: String, root: String) -> [String] {
        (exe.hasSuffix("buddydump") ? [] : ["dump"]) + ["--once", "--poll", "--json", "--data-root", root]
    }

    static func python() -> String? {
        ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ exe: String, _ args: [String]) -> (status: Int32, out: Data)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    static func json(_ d: Data) -> Any? { try? JSONSerialization.jsonObject(with: d) }

    // MARK: 假 home 树

    /// 3 个会话：A 桌面（真 pid = 测试进程；忙着开着一个 Bash；有 prior 会话、子代理、重复消息）、
    /// B 终端（真 pid = 父进程；空闲；标题来自会话记录里的 custom-title）、C 桌面下班工位（没有进程，元数据 10 分钟前还活跃）。
    final class Rig {
        let root = FileIO.temporaryDirectory + "buddy-chain-" + UUID().uuidString
        let tree: FakeClaudeTree
        let now = Date()
        let sPrior = "eeeeeeee-0000-4000-8000-0000000000a0"
        let sA = "eeeeeeee-0000-4000-8000-0000000000a1"
        let sB = "eeeeeeee-0000-4000-8000-0000000000b1"
        let hostA = "local_eeeeeeee-0000-4000-8000-0000000000a1"
        let hostC = "local_eeeeeeee-0000-4000-8000-0000000000c1"
        /// 手算的 token 期望值（和任何实现都无关）。
        /// A：prior(1+100+10+1000) + shared(50，prior 和当前会话各有一份，只算一次) + m1(2+max(20,30)+300+4000) + 子代理 s1(7+3)；合成消息不算。
        let expectA = TokenBreakdown(input: 1 + 2, output: 100 + 50 + 30 + 7, cacheWrite: 10 + 300, cacheRead: 1000 + 4000 + 3)
        let expectB = TokenBreakdown(input: 5, output: 6, cacheWrite: 7, cacheRead: 8)

        init() {
            tree = FakeClaudeTree(root: root, clock: VirtualClock(), probe: FakeProcessProbe())
            tree.prepare()
            build()
        }
        deinit {
            chmod(tree.paths.sessionsDir + "/91002.\(String(repeating: "ab", count: 32)).key", 0o600)
            try? FileManager.default.removeItem(atPath: root)
        }

        func line(_ sid: String, _ id: String, at: Double, _ usage: [String: Any], model: String = "claude-opus-5-5", agent: String? = nil) -> [String: Any] {
            TL.assistant(sessionId: sid, at: now.addingTimeInterval(at), messageId: id, block: TL.text(), stopReason: "end_turn",
                         model: model, usage: usage, agentId: agent)
        }

        func build() {
            func started(_ pid: Int32) -> Date { SystemProcessProbe.startTime(of: pid) ?? now.addingTimeInterval(-3600) }
            // A
            var metaA = FakeClaudeTree.Meta(host: hostA, cliSessionId: sA, lastActivityAt: now.addingTimeInterval(-10))
            metaA.title = "桌面标题A"; metaA.priors = [sPrior]
            tree.writeMeta(metaA)
            let full = TL.usage(input: 2, output: 20, cacheWrite: 300, cacheRead: 4000, write5m: 100, write1h: 200)
            var fuller = full; fuller["output_tokens"] = 30
            tree.appendTranscript(sPrior, [line(sPrior, "p1", at: -3000, TL.usage(input: 1, output: 100, cacheWrite: 10, cacheRead: 1000)),
                                           line(sPrior, "shared", at: -2999, TL.usage(output: 50))])
            tree.appendTranscript(sA, [TL.userPrompt(sessionId: sA, at: now.addingTimeInterval(-20)),
                                       line(sA, "shared", at: -2999, TL.usage(output: 50)),            // resume 复制的历史：同一条消息
                                       line(sA, "m1", at: -15, full), line(sA, "m1", at: -14, fuller),   // 同一条回复多次写入：每个字段取最大值
                                       line(sA, "syn", at: -13, TL.usage(output: 999), model: "<synthetic>")])
            tree.appendSubagent(sA, agentId: "ag01", [line(sA, "s1", at: -100, TL.usage(output: 7, cacheRead: 3), agent: "ag01")])   // 100 秒前写的：早过了「完成后继续报告 30 秒」，小助手列表是稳定的（但 token 照算）
            tree.writeSubagentMeta(sA, agentId: "ag01", foreground: false)
            tree.hook(sA, "UserPromptSubmit", at: now.addingTimeInterval(-19.9))
            tree.hook(sA, "PreToolUse", tool: "Bash", detail: "sleep 30", at: now.addingTimeInterval(-10))
            let sessA = FakeClaudeTree.Session(pid: getpid(), sessionId: sA, host: hostA, name: nil, startedAt: started(getpid()))
            // 登记表里的 startedAt（会话开始）取一小时前：hook 事件要 ≥ startedAt − 5 秒才算「hook 在工作」；procStart 仍是真进程的启动时间
            let hourAgo = TimeUtil.millis(now.addingTimeInterval(-3600))
            tree.writeRegistry(sessA, status: "busy", statusUpdatedAt: now.addingTimeInterval(-20), extra: ["startedAt": hourAgo], markAlive: false)
            // B
            tree.appendTranscript(sB, [TL.customTitle(sessionId: sB, "终端自定义B"),
                                       line(sB, "b1", at: -400, TL.usage(input: 5, output: 6, cacheWrite: 7, cacheRead: 8))])
            let sessB = FakeClaudeTree.Session(pid: getppid(), sessionId: sB, host: nil, name: nil, startedAt: started(getppid()))
            tree.writeRegistry(sessB, status: "idle", statusUpdatedAt: now.addingTimeInterval(-300), extra: ["startedAt": hourAgo], markAlive: false)
            // 不该出现在 dump 里的登记文件：非 interactive 的、进程已死的、.key、名字不对的
            let job = FakeClaudeTree.Session(pid: 91001, sessionId: "eeeeeeee-0000-4000-8000-0000000000d1", host: nil, name: nil, startedAt: now.addingTimeInterval(-500))
            tree.writeRegistry(job, status: "busy", extra: ["kind": "job", "startedAt": hourAgo], markAlive: false)
            let dead = FakeClaudeTree.Session(pid: 2_000_000, sessionId: "eeeeeeee-0000-4000-8000-0000000000d2", host: nil, name: nil, startedAt: now.addingTimeInterval(-500))
            tree.writeRegistry(dead, status: "busy", extra: ["startedAt": hourAgo], markAlive: false)
            let sdir = tree.paths.sessionsDir
            FakeClaudeTree.writeInPlace(sdir + "/91002.\(String(repeating: "ab", count: 32)).key", Data("SECRET".utf8))
            chmod(sdir + "/91002.\(String(repeating: "ab", count: 32)).key", 0)
            FakeClaudeTree.writeInPlace(sdir + "/abc.json", Data(#"{"pid":91003,"sessionId":"x"}"#.utf8))
            FakeClaudeTree.writeInPlace(sdir + "/91004.json.bak", Data(#"{"pid":91004,"sessionId":"y"}"#.utf8))
            // C：下班工位
            var metaC = FakeClaudeTree.Meta(host: hostC, cliSessionId: "eeeeeeee-0000-4000-8000-0000000000c2", lastActivityAt: now.addingTimeInterval(-600))
            metaC.title = "下班工位C"
            tree.writeMeta(metaC)
        }
    }

    /// App 构造 SessionStore 的方式（RealProvider.make）：SessionEngine.Options(paths:) + 设置里的四项覆盖（默认值和引擎默认值相同）+ SessionStore(options:)；
    /// 这里用等价的便捷构造 SessionStore(dataRoot:usePolling:persist:)（内部就是同样的 Options）+ 纯轮询（沙箱里 FSEvents 起不来）+ 不落盘。
    static func appStyleRows(root: String) -> [BuddyDebugRow] {
        let store = SessionStore(dataRoot: root, usePolling: true, persist: false)
        store.start()
        _ = store.pollNow()
        store.waitForTokenScan(timeout: 30)
        _ = store.pollNow()
        let rows = store.debugRows()
        store.stop()
        return rows
    }

    // MARK: 结构

    @Test("chain1 结构：DumpCommand 只造 SessionStore、自己不读任何数据源；App 的 RealProvider 也只造 SessionStore；buddyctl / buddydump 只转发 runDumpCommand")
    func chain1_sourcesShowTheSameSessionStoreChain() {
        guard let repo = Self.repoRoot() else { Issue.record("找不到项目根目录"); return }
        func src(_ p: String) -> String { (try? String(contentsOfFile: repo + "/" + p, encoding: .utf8)) ?? "" }
        let dump = src("Sources/BuddyCore/Tools/DumpCommand.swift")
        let app = src("Sources/BuddyOffice/RealProvider.swift")
        #expect(dump.contains("SessionStore(options:"))
        #expect(dump.contains("SessionEngine.Options(paths:"))
        #expect(dump.contains("store.debugRows()"))
        for banned in ["RegistryScanner", "TokenLedger(", "HookLogReader", "TranscriptReader", "DesktopMetaReader", "IdentityResolver", "ToolTracker", "ActivityResolver"] {
            #expect(!dump.contains(banned), "DumpCommand 不该自己读数据源 / 自己判定状态：\(banned)")
        }
        // App 造 SessionStore 的方式和 dump 一样：SessionEngine.Options(paths:) → SessionStore.Options(engine:) → SessionStore(options:)
        // （App 只多一步：把设置里的四项覆盖到 Options 上；数据路径、引擎、存储都是同一份代码）
        #expect(app.contains("SessionStore(options:"))
        #expect(app.contains("SessionEngine.Options(paths:"))
        #expect(app.contains("SessionStore.Options(engine:"))
        #expect(src("Sources/buddyctl/main.swift").contains("case \"dump\": exit(runDumpCommand(arguments: rest))"))
        #expect(src("Sources/buddydump/main.swift").contains("runDumpCommand(arguments: args)"))
        // 便捷构造 = 用 SessionEngine.Options(paths:) 造引擎（和 dump 一样，只是 persist 的默认值不同）
        let store = src("Sources/BuddyCore/Fusion/SessionStore.swift")
        #expect(store.contains("var eo = SessionEngine.Options(paths: paths)"))
    }

    // MARK: 行为

    @Test("chain2 行为：同一棵假 home 树，真的 buddyctl/buddydump dump --json 的输出 == App 构造方式的 SessionStore 算出来的（逐字段）")
    func chain2_dumpExecutableMatchesTheAppChain() {
        guard let exe = Self.dumpExecutable() else { Issue.record("找不到 buddyctl / buddydump 可执行文件（应该和测试包在同一个产物目录）：\(String(describing: Self.productsDirectory()))"); return }
        let rig = Rig()
        guard let r = Self.run(exe, Self.dumpArguments(exe, root: rig.root)), r.status == 0 else { Issue.record("dump 可执行文件运行失败"); return }
        compare(rig, dumpOutput: r.out)
    }

    func compare(_ rig: Rig, dumpOutput: Data) {
        guard let dumped = Self.json(dumpOutput) as? [[String: Any]] else { Issue.record("dump 的输出不是 JSON 数组"); return }
        let rows = Self.appStyleRows(root: rig.root)
        guard let appJSON = Self.json(Data(DumpFormatter.renderJSON(rows: rows).utf8)) as? [[String: Any]] else { Issue.record("App 侧序列化失败"); return }
        #expect(dumped.count == 3 && appJSON.count == 3, "A / B / C 三个：dump \(dumped.count)，App \(appJSON.count)")
        func byKey(_ a: [[String: Any]]) -> [String: [String: Any]] { Dictionary(uniqueKeysWithValues: a.compactMap { r in (r["key"] as? String).map { ($0, r) } }) }
        let d = byKey(dumped), a = byKey(appJSON)
        #expect(Set(d.keys) == Set(a.keys))
        for (k, row) in d {
            #expect((row as NSDictionary).isEqual(to: a[k] ?? [:]), "会话 \(k) 的 dump 和 App 链路结果不同：\(row) vs \(String(describing: a[k]))")
        }
        // 语义上也对（不只是「两边一样」）：手算的 token 期望值、标题链、阶段
        let ka = "d:" + rig.hostA, kb = "t:" + rig.sB, kc = "d:" + rig.hostC
        let tokens: (String) -> Int? = { k in (d[k]?["tokens"] as? [String: Any])?["total"] as? Int }
        #expect(tokens(ka) == rig.expectA.total, "A 的 token：\(String(describing: tokens(ka))) 期望 \(rig.expectA.total)")
        #expect(tokens(kb) == rig.expectB.total)
        #expect(d[ka]?["title"] as? String == "桌面标题A")                      // 登记表没有 name → 桌面元数据的 title
        #expect(d[kb]?["title"] as? String == "终端自定义B")                     // 没有桌面元数据 → 会话记录里的 custom-title
        #expect(d[kc]?["title"] as? String == "下班工位C")
        #expect(d[ka]?["phase"] as? String == "busy" && d[ka]?["activity"] as? String == "工具 Bash", "A 的阶段 / 动作：\(String(describing: d[ka]?["phase"])) / \(String(describing: d[ka]?["activity"])) 开着的工具 hookActive=\(String(describing: d[ka]?["hookActive"])) hookEvents=\(String(describing: d[ka]?["hookEvents"]))")
        #expect(d[kb]?["phase"] as? String == "idle" && d[kb]?["presence"] as? String == "present")
        #expect(d[kc]?["presence"] as? String == "dormant")
        #expect(d[ka]?["liveness"] as? String == "alive" && d[kb]?["liveness"] as? String == "alive")
    }

    @Test("chain3 行为：App 构造方式的 SessionStore 与直接用 SessionEngine 算出来的快照一致（同一个引擎）")
    func chain3_storeAndRawEngineAgree() {
        let rig = Rig()
        var eo = SessionEngine.Options(paths: rig.tree.paths)
        eo.ledgerQueue = testLedgerQueue()
        eo.persist = false
        let engine = SessionEngine(options: eo)
        _ = engine.poll()
        _ = engine.ledger?.waitUntilIdle(timeout: 60)
        let snaps = engine.poll().snapshots
        let store = SessionStore(dataRoot: rig.root, usePolling: true, persist: false)
        store.start()
        _ = store.pollNow(); store.waitForTokenScan(timeout: 30)
        let fromStore = store.pollNow()?.snapshots ?? []
        store.stop()
        #expect(snaps.count == 3 && fromStore.count == 3)
        for s in snaps {
            guard let t = fromStore.first(where: { $0.key == s.key }) else { Issue.record("\(s.key) 在 store 里没有"); continue }
            #expect(t.seat == s.seat && t.title == s.title && t.sessionId == s.sessionId && t.origin == s.origin)
            #expect(t.phase == s.phase && t.activity == s.activity && t.presence == s.presence)
            #expect(t.tokens == s.tokens && t.pid == s.pid && t.hostSessionId == s.hostSessionId)
            #expect(t.unread == s.unread && t.blocked == s.blocked && t.quiet == s.quiet && t.hookActive == s.hookActive)
            #expect(t.turnStartedAt == s.turnStartedAt && t.idleSince == s.idleSince && t.contextTokens == s.contextTokens)
        }
    }

    // MARK: 两个 Python 脚本在 FakeTree 上跑

    @Test("py1 QA/tools/token_crosscheck.py 在假 home 树上：独立实现 == 用量表 parse_line == dump == 手算期望值")
    func py1_tokenCrosscheckScriptOnAFakeTree() {
        guard let repo = Self.repoRoot(), let py = Self.python() else { Issue.record("找不到项目根目录或 python3"); return }
        guard let exe = Self.dumpExecutable() else { Issue.record("找不到 buddyctl / buddydump 可执行文件"); return }
        let rig = Rig()
        let args = [repo + "/QA/tools/token_crosscheck.py", "--root", rig.root, "--liveness", "check", "--no-ledger", "--run-dump", "--buddyctl", exe, "--json"]
        guard let r = Self.run(py, args), let obj = Self.json(r.out) as? [String: Any] else { Issue.record("脚本没有输出 JSON"); return }
        #expect(obj["problems"] as? [String] == [], "\(String(describing: obj["problems"]))")
        guard let sessions = obj["sessions"] as? [[String: Any]] else { Issue.record("没有 sessions"); return }
        #expect(sessions.count == 2)                                                 // 下班工位没有进程：不在「活会话」里
        func total(_ s: [String: Any]) -> Int? { (s["mine"] as? [String: Any])?["total"] as? Int }
        #expect(sessions.first { $0["pid"] as? Int == Int(getpid()) }.flatMap(total) == rig.expectA.total)
        #expect(sessions.first { $0["pid"] as? Int == Int(getppid()) }.flatMap(total) == rig.expectB.total)
        #expect(sessions.allSatisfy { ($0["mine_vs_meter"] as? Bool) != false })     // 用量表在这台机器上才有；没有就是 nil
        #expect(sessions.allSatisfy { ($0["mine_vs_dump"] as? Bool) == true }, "独立实现和 dump 不一致：\(sessions)")
        #expect(obj["ok"] as? Bool == true)
        #expect(r.status == 0)
        // 输出里绝不能有对话内容 / 标题文字
        let text = String(decoding: r.out, as: UTF8.self)
        for secret in ["桌面标题A", "终端自定义B", "下班工位C", "sleep 30"] { #expect(!text.contains(secret), "脚本输出里不该出现：\(secret)") }
    }

    @Test("py2 QA/tools/dump_vs_registry.py 在假 home 树上：pid / 标题链 / status / waitingFor / 集合 全部一致，输出里没有标题文字")
    func py2_dumpVsRegistryScriptOnAFakeTree() {
        guard let repo = Self.repoRoot(), let py = Self.python() else { Issue.record("找不到项目根目录或 python3"); return }
        guard let exe = Self.dumpExecutable() else { Issue.record("找不到 buddyctl / buddydump 可执行文件"); return }
        let rig = Rig()
        let args = [repo + "/QA/tools/dump_vs_registry.py", "--root", rig.root, "--liveness", "check", "--json", "--buddyctl", exe]
        guard let r = Self.run(py, args), let obj = Self.json(r.out) as? [String: Any] else { Issue.record("脚本没有输出 JSON"); return }
        #expect(obj["problems"] as? [String] == [], "\(String(describing: obj["problems"]))")
        #expect(obj["ok"] as? Bool == true, "\(obj)")
        #expect(obj["extra_in_dump"] as? [Int] == [] && obj["missing_in_dump"] as? [Int] == [])
        guard let sessions = obj["sessions"] as? [[String: Any]] else { Issue.record("没有 sessions"); return }
        #expect(sessions.count == 2)
        for s in sessions {
            #expect((s["checks"] as? [String: Bool])?.values.allSatisfy { $0 } == true, "\(s)")
        }
        let src = Dictionary(uniqueKeysWithValues: sessions.compactMap { s in (s["pid"] as? Int).map { ($0, s["title_source"] as? String ?? "") } })
        #expect(src[Int(getpid())] == "桌面 title")
        #expect(src[Int(getppid())] == "custom-title")
        let text = String(decoding: r.out, as: UTF8.self)
        for secret in ["桌面标题A", "终端自定义B", "下班工位C", "sleep 30"] { #expect(!text.contains(secret), "脚本输出里不该出现：\(secret)") }
    }
}
