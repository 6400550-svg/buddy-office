import Foundation
import Testing
@testable import BuddyCore

// QA · `buddydump --audit-opens`：在真实环境里证明「没有打开过密钥文件 / socket」的这个工具本身要可靠——
// 分类对、抓得到不该出现的路径、汇总里不泄露文件名、在一棵放了诱饵的假 home 上跑一遍是干净的。
// 会碰全局观察口（FileIO.openObserver / forbiddenHits）的放进串行套件 FileAccessTests 的扩展里。

extension FileAccessTests {

    @Test("open 审计：每一类路径归到该归的类别；名字不合规的、类别之外的、密钥文件 / socket 都算「不该出现」")
    func openAudit_classifiesPaths() {
        let paths = Paths(home: "/h")
        func cat(_ p: String) -> (name: String, expected: Bool) { OpenAudit.category(of: p, paths: paths) }
        #expect(cat("/h/.claude/sessions/1001.json").expected)
        #expect(cat("/h/.claude/sessions/1001.json").name.hasPrefix("登记表"))
        #expect(cat("/h/.claude/.monitor/sid-1.events.jsonl").expected)
        #expect(cat("/h/.claude/projects/-x/sid-1.jsonl").expected)
        #expect(cat("/h/.claude/projects/-x/sid-1/subagents/agent-a.jsonl").expected)
        #expect(cat("/h/.claude/projects/-x/sid-1/subagents/agent-a.meta.json").expected)
        #expect(cat("/h/.claude/projects/-x/sid-1/custom-title.json").expected)          // 会话标题（引擎每 3 秒看一眼）
        #expect(cat("/h/Library/Application Support/Claude/claude-code-sessions/a/b/local_1234.json").expected)
        #expect(cat("/h/.claude/settings.json").expected)
        #expect(cat("/h/Library/Application Support/BuddyOffice/ledger.json").expected)
        // 不该出现的
        #expect(!cat("/h/.claude/sessions/1001.\(fuzzFakeSha).key").expected)
        #expect(!cat("/h/.claude/sessions/abc.json").expected)
        #expect(!cat("/h/.claude/sessions/sub/1001.json").expected)
        #expect(!cat("/h/.claude/.monitor/x.log").expected)
        #expect(!cat("/h/.claude/projects/-x/notes.txt").expected)
        #expect(!cat("/h/Library/Application Support/Claude/claude-code-sessions/a/b/other.json").expected)
        #expect(!cat("/etc/passwd").expected)
        #expect(!cat("/tmp/cc-socks/x").expected)
    }

    @Test("open 审计：报告抓得到密钥文件 / socket 的路径，汇总文字里不出现文件名，装上之前保险的拒绝次数不算")
    func openAudit_reportFlagsOffendersAndHidesFileNames() {
        let paths = Paths(home: "/h")
        let a = OpenAudit()
        a.install(scope: "/h/"); defer { a.uninstall() }                          // 范围缩到 /h/：并行的别的测试在自己临时目录里的 open 不会混进来（SAN-02）
        a.record("/h/.claude/sessions/1001.json"); a.record("/h/.claude/sessions/1001.json")
        a.record("/h/.claude/sessions/1002.json")
        a.record("/h/.claude/projects/-x/sid-secret-9.jsonl")
        var r = a.report(paths: paths)
        #expect(r.ok && r.totalOpens == 4 && r.offenders.isEmpty && r.forbiddenAttempts == 0, "\(r.text())")
        #expect(r.rows.first { $0.name.hasPrefix("登记表") } == OpenAudit.Row(name: "登记表 sessions/<pid>.json", distinct: 2, opens: 3))
        let text = r.text()
        #expect(!text.contains("1001") && !text.contains("1002") && !text.contains("sid-secret-9"), "汇总里不该出现文件名：\(text)")
        #expect(text.contains("✅"))
        // 一条密钥文件的路径 → 不 ok，路径被带出来
        a.record("/h/.claude/sessions/1001.\(fuzzFakeSha).key")
        r = a.report(paths: paths)
        #expect(!r.ok && r.offenders == ["/h/.claude/sessions/1001.\(fuzzFakeSha).key"] && r.text().contains("✗"))
    }

    @Test("open 审计：保险在观察期间拒绝过一次 = 有代码尝试打开不该打开的文件 → 不 ok；之前的拒绝不算")
    func openAudit_countsForbiddenAttemptsOnlyAfterInstall() {
        let dir = FuzzDir("audit-forbidden")
        dir.write("1001.\(fuzzFakeSha).key", "FAKE-KEY-CONTENT")
        _ = FileIO.open(dir.file("1001.\(fuzzFakeSha).key"))                    // 装上之前的一次拒绝
        let a = OpenAudit()
        a.install(); defer { a.uninstall() }
        #expect(a.report(paths: Paths(home: dir.path)).forbiddenAttempts == 0)
        #expect(FileIO.open(dir.file("1001.\(fuzzFakeSha).key")) == -1)         // 观察期间的一次
        let r = a.report(paths: Paths(home: dir.path))
        #expect(r.forbiddenAttempts == 1 && !r.ok)
    }

    @Test("open 审计：在一棵放了诱饵的假 home 上跑一遍数据层（和 App 同一条链路）：只打开了 <pid>.json，一个诱饵都没碰，保险一次都没拒绝")
    func openAudit_endToEndOnAFakeHomeWithDecoys() {
        let home = FuzzDir("audit-e2e")
        let sessions = home.file(".claude/sessions")
        try? FileManager.default.createDirectory(atPath: sessions, withIntermediateDirectories: true)
        func reg(_ pid: Int, _ sid: String) -> Data { Data(#"{"pid":\#(pid),"sessionId":"\#(sid)","kind":"interactive","status":"idle"}"#.utf8) }
        FakeClaudeTree.writeInPlace(sessions + "/\(getpid()).json", reg(Int(getpid()), "sid-live"))
        FakeClaudeTree.writeInPlace(sessions + "/1002.json", reg(1002, "sid-dead"))
        // 诱饵：密钥文件（普通文件，内容看起来像合法记录）、大写扩展名、socket 名字、名字差一点点的文件
        FakeClaudeTree.writeInPlace(sessions + "/\(getpid()).\(fuzzFakeSha).key", reg(Int(getpid()), "SECRET-FROM-KEY"))
        FakeClaudeTree.writeInPlace(sessions + "/1003.\(fuzzFakeSha).KEY", reg(1003, "SECRET-FROM-KEY-2"))
        FakeClaudeTree.writeInPlace(sessions + "/agent.sock", Data("x".utf8))
        FakeClaudeTree.writeInPlace(sessions + "/abc.json", reg(1099, "SECRET-DECOY"))
        var eo = SessionEngine.Options(paths: Paths(home: home.path))
        eo.persist = false
        eo.scanTokens = false
        var so = SessionStore.Options(engine: eo)
        so.usePolling = true
        let r = OpenAudit.run(options: so, seconds: 0, tokens: false, scope: home.path)      // 范围 = 自己的假 home（SAN-02）
        #expect(r.ok, "\(r.text())")
        let regRow = r.rows.first { $0.name.hasPrefix("登记表") }
        #expect(regRow != nil && regRow!.distinct == 2, "只有 <pid>.json 两个：\(r.text())")
        #expect(r.offenders.isEmpty && r.forbiddenAttempts == 0)
    }

    /// SAN-02：`FileIO.openObserver` 是进程全局的，并行跑的别的测试（读自己的临时目录）的 open 也会被观察到。
    /// 这条测试让另一个线程在审计期间不停地打开别处的文件：有范围时审计不受影响；不设范围时那些 open 会被记成「其他位置的文件」。
    @Test("open 审计：别的线程同时在打开别处的文件（并行跑的其它测试）时，限定了范围的审计不受影响，不设范围的会被记进来")
    func openAudit_scopeKeepsConcurrentOpensOfOtherTestsOut() {
        let other = FuzzDir("audit-noise")
        other.write("noise.jsonl", "{}\n")
        let home = FuzzDir("audit-scope")
        let sessions = home.file(".claude/sessions")
        try? FileManager.default.createDirectory(atPath: sessions, withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(sessions + "/\(getpid()).json", Data(#"{"pid":\#(getpid()),"sessionId":"sid-live","kind":"interactive","status":"idle"}"#.utf8))
        let stop = FuzzBox<Bool>(false), opens = FuzzBox<Int>(0)
        let done = DispatchSemaphore(value: 0)
        Thread {
            while !stop.value { let fd = FileIO.open(other.file("noise.jsonl")); if fd >= 0 { close(fd); opens.value += 1 }; Thread.sleep(forTimeInterval: 0.0005) }      // 不空转：机器忙时别再抢 CPU（R4b P3）
            done.signal()
        }.start()
        defer { stop.value = true; done.wait() }
        let t0 = Date(); while opens.value == 0, Date().timeIntervalSince(t0) < 10 { Thread.sleep(forTimeInterval: 0.01) }               // 等噪声线程真的 open 过一次再开始审计
        var eo = SessionEngine.Options(paths: Paths(home: home.path)); eo.persist = false; eo.scanTokens = false
        var so = SessionStore.Options(engine: eo); so.usePolling = true
        let scoped = OpenAudit.run(options: so, seconds: 0.3, tokens: false, scope: home.path)
        #expect(scoped.ok && !scoped.rows.contains { $0.name == "其他位置的文件" } && scoped.rows.contains { $0.name.hasPrefix("登记表") }, "限定范围：\(scoped.text())")
        let unscoped = OpenAudit.run(options: so, seconds: 0.3, tokens: false)
        #expect(!unscoped.ok && unscoped.offenders.contains { $0.hasSuffix("noise.jsonl") }, "不设范围：别处的 open 应该被记成「其他位置的文件」：\(unscoped.text())")
    }
}
