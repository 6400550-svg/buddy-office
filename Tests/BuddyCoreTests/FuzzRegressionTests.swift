import Foundation
import Testing
@testable import BuddyCore

// QA 回归测试：每个测试对应 QA/issues-core.md 里的一条（C-xxx）。
// 写法：先写测试、确认它在修复前失败（崩溃类 = 整个测试进程 trap，别的 = 记 Issue），再修，再确认通过。
// 假数据一律放在临时目录；绝不碰 ~/.claude，绝不打开 .key / .sock（下面的 .key 是造出来的假文件，内容也是假的）。

@Suite struct FuzzRegressionTests {

    // MARK: C-001 procStart 极端值

    @Test("C-001 procStart 的年份 / 时分秒是天文数字时不崩溃（登记表 procStart 字段）")
    func c001_procStartExtremeValuesDoNotTrap() {
        let bad = [
            "Tue Sep 29 03:23:08 9223372036854775807",       // 年份 = Int.max：era × 146097 溢出
            "Tue Sep 29 03:23:08 99999999999999999",
            "Tue Sep 29 03:23:08 10000",                     // 超过 4 位
            "Tue Sep 29 -9223372036854775808:00:00 2026",    // 小时 = Int.min：× 3600 溢出
            "Tue Sep 29 03:-9223372036854775808:00 2026",
            "Tue Sep 29 03:00:-9223372036854775808 2026",
            "Tue Sep 29 -1:00:00 2026",                      // 负数也不合法
            "Tue Sep 29 03:-5:00 2026",
            "Tue Sep 29 03:00:-1 2026",
        ]
        for s in bad { #expect(TimeUtil.parseProcStart(s) == nil, "应当当作解析不了：\(s)") }
        #expect(TimeUtil.parseProcStart("Tue Sep 29 03:23:08 2026") == Date(timeIntervalSince1970: 1_790_652_188))
        #expect(TimeUtil.parseProcStart("Tue Sep  9 03:23:08 2026") != nil)         // 日期补空格
        // 整条登记记录：procStart 坏了，记录仍然可用（procStart 为 nil，原文保留给别名用）
        let json = #"{"pid":5,"sessionId":"s","procStart":"Tue Sep 29 03:23:08 9223372036854775807"}"#
        guard case .some(.some(let r)) = RegistryScanner.parse(Data(json.utf8)) else {
            Issue.record("登记记录应该可用"); return
        }
        #expect(r.procStart == nil)
        #expect(r.procStartRaw != nil)
        #expect(r.procStartKey != "?")
    }

    // MARK: C-002 时间戳换算 / identities.json 里的天文数字

    @Test("C-002 Date → 毫秒的换算是饱和的（不 trap）")
    func c002_millisSaturates() {
        #expect(TimeUtil.millis(Date(timeIntervalSince1970: 1e300)) == Int64.max)
        #expect(TimeUtil.millis(Date(timeIntervalSince1970: -1e300)) == Int64.min)
        #expect(TimeUtil.millis(Date(timeIntervalSince1970: .infinity)) == Int64.max)
        #expect(TimeUtil.millis(Date(timeIntervalSince1970: .nan)) == 0)
        #expect(TimeUtil.millis(Date(timeIntervalSince1970: 1_790_654_400.123)) == 1_790_654_400_123)
        // 反方向：格式化函数（replay / 测试用）遇到极端日期也不崩
        _ = TimeUtil.formatISO(Date(timeIntervalSince1970: 1e300))
        _ = TimeUtil.formatProcStart(Date(timeIntervalSince1970: -1e300))
        _ = TimeUtil.formatISO(Date(timeIntervalSince1970: .nan))
    }

    @Test("C-002 identities.json 里的天文数字不会让 App 每次启动都崩溃（崩溃循环）")
    func c002_identityFileWithAbsurdTimesCannotCrashLoop() throws {
        let dir = FuzzDir("c002")
        let path = dir.file("identities.json")
        let json = """
        {"version":1,"identities":[
          {"key":"d:local_a","seat":0,"salt":"1","aliases":["host:local_a"],"createdAt":1e300,"lastSeenAt":1e300},
          {"key":"t:b","seat":1,"salt":"2","aliases":[],"createdAt":17591000001234567890,"lastSeenAt":1790654400000},
          {"key":"t:c","seat":2,"salt":"3","aliases":[],"createdAt":1790654400000,"lastSeenAt":18446744073709551615}
        ]}
        """
        dir.write("identities.json", json)
        let r = IdentityResolver(path: path, now: { Harness.epoch })
        r.saveIfNeeded(force: true)                                   // 修复前：Int64(1e300) 直接 trap
        let data = try #require(dir.read("identities.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((obj["version"] as? Int) == 1)
        let items = try #require(obj["identities"] as? [[String: Any]])
        for it in items {
            let c = (it["createdAt"] as? NSNumber)?.doubleValue ?? -1
            let s = (it["lastSeenAt"] as? NSNumber)?.doubleValue ?? -1
            #expect(c > 946_684_800_000 && c < 7_258_118_400_000, "createdAt 应该是合理的毫秒时间戳：\(c)")
            #expect(s > 946_684_800_000 && s < 7_258_118_400_000, "lastSeenAt 应该是合理的毫秒时间戳：\(s)")
        }
        // 再读一遍：能正常载入
        let r2 = IdentityResolver(path: path, now: { Harness.epoch })
        #expect(r2.all.count == items.count)
    }

    // MARK: C-003 hook 事件的时间戳

    @Test("C-003 hook 行里离谱的 ts（天文数字 / 无穷 / 0 / 负数 / 布尔）在解析时就被拒绝")
    func c003_absurdHookTimestampsAreRejectedAtParseTime() {
        let hugeDigits = String(repeating: "9", count: 400)         // Double("999…") == +inf
        let bad = ["1e30", "99999999999999999999", "18446744073709551615", "0", "-5", "1", "true", "false",
                   "1e999", "1759100000123e5", "null", "\"1759100000123\"", "[]", "{}", hugeDigits]
        for ts in bad {
            let full = #"{"ts":\#(ts),"ev":"PreToolUse","tool":"Bash","detail":"x","extra":""}"#
            #expect(LineSanitizer.parseHookLine(full) == nil, "ts=\(ts.prefix(30)) 应当被拒绝")
            // 降级路径（JSON 被截断，只能靠扫描抠字段）：同样不能放行
            let broken = #"{"ts":\#(ts),"ev":"PreToolUse","tool":"Ba"#
            #expect(LineSanitizer.parseHookLine(broken) == nil, "降级路径：ts=\(ts.prefix(30)) 应当被拒绝")
        }
        // 正常的 ts 仍然通过（毫秒 / 带小数）
        let ok1 = LineSanitizer.parseHookLine(#"{"ts":1790654602874,"ev":"Stop","tool":"","detail":"","extra":""}"#)
        #expect(ok1?.ts == Date(timeIntervalSince1970: 1790654602.874))
        let ok2 = LineSanitizer.parseHookLine(#"{"ts":1790654602874,"ev":"Stop","tool":"Ba"#)
        #expect(ok2?.degraded == true)
    }

    @Test("C-003 归属判断遇到离谱的事件时间也不崩溃（Int(…) 换算）")
    func c003_attributionSurvivesAbsurdEventTimes() {
        var a = HelperAttributor()
        let now = Harness.epoch
        let ctx = HelperAttributor.Context(mainIdle: false, foregroundAgentOpenSince: now, hasActiveBackgroundHelper: false)
        for ts in [1e30, -1e30, 1e300, Double.infinity, -Double.infinity, 4.0e12, -4.0e12] {
            let ev = HookEvent(ts: Date(timeIntervalSince1970: ts), ev: "PreToolUse", tool: "Bash", detail: "x")
            _ = a.decide(event: ev, context: ctx, now: now)          // 修复前：Int(1e33.rounded()) trap
        }
    }

    // MARK: C-004 usage 数字相加溢出

    @Test("C-004 会话记录里 usage 的数字是天文数字时，解析 / 累计 / 账本都不溢出")
    func c004_hugeUsageNumbersDoNotOverflow() {
        let big = "9223372036854775807"
        let line = #"""
        {"type":"assistant","timestamp":"2026-09-29T04:12:39.255Z","message":{"id":"m1","model":"claude-opus-5-5","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":\#(big),"output_tokens":\#(big),"cache_creation_input_tokens":\#(big),"cache_read_input_tokens":\#(big),"cache_creation":{"ephemeral_5m_input_tokens":\#(big),"ephemeral_1h_input_tokens":\#(big)}}}}
        """#
        let bytes = Array(line.utf8)
        let parsed = bytes.withUnsafeBufferPointer { TranscriptLineParser.parse($0) }       // 修复前：cacheWrite1h + cacheWrite5m 溢出
        #expect(parsed?.usage != nil)
        var facts = TranscriptFacts()
        if let p = parsed { facts.apply(p, includeSidechain: false) }                       // 修复前：input + cacheWriteTotal + cacheRead 溢出
        if let c = facts.contextTokens { #expect(c > 0 && c < (1 << 50)) }
        if let u = parsed?.usage {
            #expect(u.input >= 0 && u.input < (1 << 50))
            #expect(u.cacheWrite5m + u.cacheWrite1h == u.cacheWriteTotal)
        }

        // 再走一遍 TokenLedger（后台扫描线程里崩溃也算崩溃）
        let dir = FuzzDir("c004")
        dir.write("t.jsonl", line + "\n")
        let ledger = TokenLedger(ledgerPath: nil, queue: testLedgerQueue())
        ledger.setGroup(key: "k", transcripts: [dir.file("t.jsonl")], helpers: [])
        #expect(ledger.waitUntilIdle(timeout: 60))
        let t = ledger.totals(forKey: "k")
        #expect(t.messages == 1)
        #expect(t.breakdown.total >= 0)
    }

    // MARK: C-005 ledger.json 里的天文数字 / 负数

    @Test("C-005 ledger.json 里的计数是天文数字或负数时，恢复后不溢出、不为负")
    func c005_ledgerWithAbsurdCountersIsSanitized() throws {
        for (label, v) in [("Int.max", "9223372036854775807"), ("负数", "-1000"), ("浮点", "1e300"), ("uint64", "18446744073709551615")] {
            let dir = FuzzDir("c005")
            let t = dir.file("t.jsonl")
            dir.write("t.jsonl", "junk line\n")
            let st = try #require(FileIO.stat(t))
            let ledgerJSON = """
            {"version":1,"files":{"\(t)":{"dev":\(st.dev),"ino":\(st.ino),"offset":\(st.size),
              "input":\(v),"output":\(v),"cw":\(v),"cr":\(v),"n":\(v),"recent":[{"h":"deadbeef","i":\(v),"o":\(v),"w5":\(v),"w1":\(v),"r":\(v)}]}}}
            """
            dir.write("ledger.json", ledgerJSON)
            let ledger = TokenLedger(ledgerPath: dir.file("ledger.json"), queue: testLedgerQueue())
            ledger.setGroup(key: "k", transcripts: [t], helpers: [])
            #expect(ledger.waitUntilIdle(timeout: 60))
            var tot = ledger.totals(forKey: "k")
            #expect(tot.breakdown.input >= 0 && tot.breakdown.output >= 0 && tot.breakdown.cacheWrite >= 0 && tot.breakdown.cacheRead >= 0,
                    "\(label)：恢复出来的计数不能是负数")
            #expect(tot.breakdown.total >= 0, "\(label)：total 不能溢出")              // 修复前：Int.max + Int.max 溢出 trap
            // 之后文件继续增长：累加也不能溢出
            FakeClaudeTree.appendBytes(t, FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "new-\(label)")))
            ledger.poke()
            #expect(ledger.waitUntilIdle(timeout: 60))
            tot = ledger.totals(forKey: "k")
            #expect(tot.breakdown.total >= 0)
            ledger.flush()
            // 写回去的账本仍然是合法 JSON
            let back = try #require(dir.read("ledger.json"))
            #expect((try? JSONSerialization.jsonObject(with: back)) != nil)
        }
    }

    // MARK: C-006 未来的时间戳把 hook 队列卡死

    @Test("C-006 事件时间戳在未来时，归属扣留最多 0.4 秒，不会把整个 hook 队列永远卡住")
    func c006_attributionHoldIsBoundedEvenWithFutureTimestamps() {
        var a = HelperAttributor()
        let t0 = Harness.epoch
        let ctx = HelperAttributor.Context(mainIdle: false, foregroundAgentOpenSince: nil, hasActiveBackgroundHelper: true)
        for future in [3600.0, 86400.0 * 365, 86400.0 * 365 * 100] {
            var a = a
            let ev = HookEvent(ts: t0.addingTimeInterval(future), ev: "PreToolUse", tool: "Bash", detail: "x")
            // 和引擎一样：每个 poll 问一次，一旦不再扣留这个事件就出队了（不会再问第二次）
            var decidedAt: Double?
            for i in 0...10 {
                let at = Double(i) * 0.1
                if case .hold = a.decide(event: ev, context: ctx, now: t0.addingTimeInterval(at)) { continue }
                decidedAt = at; break
            }
            if decidedAt == nil { Issue.record("未来 \(Int(future)) 秒的事件：1 秒后还在扣留（hook 队列被卡死）") }
            else if let d = decidedAt { #expect(d <= 0.5 + 1e-9, "扣留应该最多 0.4 秒：\(d)") }
        }
        // 正常的（时间戳 = 现在）仍然先扣留、不超过 400 ms
        let ev = HookEvent(ts: t0, ev: "PreToolUse", tool: "Bash", detail: "x")
        #expect(a.decide(event: ev, context: ctx, now: t0) == .hold(until: t0.addingTimeInterval(0.4)))
        #expect(a.decide(event: ev, context: ctx, now: t0.addingTimeInterval(0.41)) == .main)
    }

    // MARK: C-008 FileIO 阻塞

    @Test("C-008 <pid>.json 是命名管道（FIFO）时不会把读取线程永远卡在 open() 上")
    func c008_fifoDoesNotBlockTheReader() {
        let dir = FuzzDir("c008")
        let fifo = dir.file("1234.json")
        #expect(mkfifo(fifo, 0o600) == 0)
        let done = FuzzBox(false)
        let finished = fuzzRun("readAll(FIFO)", timeout: 15) {
            _ = FileIO.readAll(fifo)
            _ = FileIO.readAll(fifo, maxBytes: 100)
            let t = JSONLTailer(path: fifo)
            t.poll { _ in }
            t.seekToTail(window: 10)
            done.value = true
        }
        if !finished {
            // 把卡住的 open() 放走（对 FIFO 写端 open 会让读端返回），免得留下一个永远阻塞的线程
            let w = open(fifo, O_WRONLY | O_NONBLOCK)
            if w >= 0 { close(w) }
        }
        #expect(finished)
        // 桌面元数据目录里同名的 FIFO 也一样
        let meta = FuzzDir("c008m")
        let acct = meta.file("acct/org")
        try? FileManager.default.createDirectory(atPath: acct, withIntermediateDirectories: true)
        #expect(mkfifo(acct + "/local_x.json", 0o600) == 0)
        let refreshed = fuzzRun("DesktopMetaReader.refresh(FIFO)", timeout: 15) {
            _ = DesktopMetaReader(rootDir: meta.path).refresh()
        }
        if !refreshed {
            let w = open(acct + "/local_x.json", O_WRONLY | O_NONBLOCK)
            if w >= 0 { close(w) }
        }
        #expect(refreshed)
    }

    // MARK: C-009 identities.json 载入无上限

    @Test("C-009 identities.json 里别名 / 工位 / 条目数量离谱时，载入后有上界、不卡死")
    func c009_identityFileIsBoundedOnLoad() throws {
        let dir = FuzzDir("c009")
        // ① 一个身份挂了 50000 个别名（sid / proc / host 都有）
        var aliases: [String] = []
        for i in 0..<20_000 { aliases.append("sid:s\(i)") }
        for i in 0..<20_000 { aliases.append("proc:\(i)@\(i)") }
        for i in 0..<10_000 { aliases.append("host:local_\(i)") }
        // ② 工位号是各种离谱的值
        var items: [[String: Any]] = [["key": "d:local_big", "seat": 0, "salt": "1", "aliases": aliases,
                                        "createdAt": 1790654400000, "lastSeenAt": 1790654400000]]
        let seats: [Any] = [Int.max, Int.min, -5, 1_000_000, 4294967296, 1e300, "3", NSNull()]
        for (i, s) in seats.enumerated() {
            items.append(["key": "t:seat\(i)", "seat": s, "salt": "1", "aliases": [], "createdAt": 1790654400000, "lastSeenAt": 1790654400000])
        }
        // ③ 上万个身份
        for i in 0..<5_000 {
            items.append(["key": "t:bulk\(i)", "seat": i, "salt": "1", "aliases": ["sid:bulk\(i)"],
                          "createdAt": 1790654400000, "lastSeenAt": 1790654400000 + i])
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "identities": items] as [String: Any])
        dir.write("identities.json", data)
        let box = FuzzBox<IdentityResolver?>(nil)
        let finished = fuzzRun("IdentityResolver.load", timeout: 20) {
            box.value = IdentityResolver(path: dir.file("identities.json"), now: { Harness.epoch })
        }
        #expect(finished)
        guard let r = box.value else { return }
        #expect(r.all.count <= 2000, "身份条目数应有上界：\(r.all.count)")
        for id in r.all {
            #expect(id.aliases.count <= IdentityResolver.maxAliases, "别名数应有上界：\(id.aliases.count)")
            #expect(id.seat >= -1 && id.seat <= 999, "工位号应合理：\(id.seat)")
        }
        // 载入之后正常使用、正常存盘
        let rec: RegistryRecord = {
            var x = RegistryRecord(pid: 4242, sessionId: "brand-new-session")
            x.procStartRaw = "Tue Sep 29 03:23:08 2026"
            x.procStart = TimeUtil.parseProcStart("Tue Sep 29 03:23:08 2026")
            return x
        }()
        let finished2 = fuzzRun("IdentityResolver.resolve after load", timeout: 20) {
            let m = r.resolve(rec, metaLookup: { _ in nil })
            _ = r.assignSeat(forKey: m.identity.key, occupied: [])
            r.saveIfNeeded(force: true)
        }
        #expect(finished2)
        let back = dir.read("identities.json")
        #expect(back != nil && (try? JSONSerialization.jsonObject(with: back!)) != nil)
    }

    // MARK: C-010 桌面元数据里的 priorCliSessionIds

    @Test("C-010 桌面元数据里 priorCliSessionIds 有上万项时有上界、不卡死")
    func c010_priorCliSessionIdsAreBounded() throws {
        let ids = (0..<12_000).map { "00000000-0000-4000-8000-\(String(format: "%012ld", $0))" }
        let obj: [String: Any] = ["sessionId": "local_x", "cliSessionId": "cur", "priorCliSessionIds": ids, "title": "t"]
        let data = try JSONSerialization.data(withJSONObject: obj)
        let count = FuzzBox(-1)
        let hasCur = FuzzBox(false)
        let lastPrior = FuzzBox<String?>(nil)
        // 全部放在 fuzzRun 里算：超时以后测试线程不能再去碰那个慢函数（否则测试自己卡死）
        let finished = fuzzRun("DesktopMetaReader.parse + allCliSessionIds", timeout: 20) {
            let m = DesktopMetaReader.parse(data, path: "/x/local_x.json")
            let all = m?.allCliSessionIds ?? []                                  // 修复前：O(n²) 去重
            count.value = all.count
            hasCur.value = all.contains("cur")
            lastPrior.value = m?.priorCliSessionIds.last
        }
        #expect(finished)
        guard finished else { return }
        #expect(count.value >= 1 && count.value <= 1000, "别名个数应有上界：\(count.value)")
        #expect(hasCur.value)
        // 有上界时保留的是最近的那些（数组末尾）
        #expect(lastPrior.value == ids.last)
    }

    // MARK: C-011 ToolTracker

    @Test("C-011 hook 事件狂刷（Pre 永远没有 Post）时，ToolTracker 的 open 有上界")
    func c011_toolTrackerOpenListIsBounded() {
        var t = ToolTracker()
        let base = Harness.epoch
        for i in 0..<30_000 {
            t.pre(name: "Read", detail: "f\(i)", at: base, owner: i % 3 == 0 ? .helper : .main)   // 同一时刻：永远不会开新的一批
        }
        #expect(t.open.count <= 1024, "open 应有上界：\(t.open.count)")
        #expect(t.closed.count <= 64)
        // 仍然能配对关闭最新的
        t.post(name: "Read", detail: "f29999", at: base)
        #expect(!t.open.contains { $0.call.detail == "f29999" })
    }

    // MARK: C-012 JSON 嵌套太深 → 栈溢出

    @Test("C-012 嵌套 470–512 层的 JSON 不会把 512 KB 栈的工作线程压爆（JSONSerialization 递归解析）")
    func c012_deeplyNestedJSONDoesNotOverflowTheStack() {
        // fuzzRun 的线程栈和 GCD 工作线程（ingest / tokenscan 队列）一样是 512 KB
        let finished = fuzzRun("deep JSON", timeout: 60) { r in
            for depth in [200, 470, 480, 500, 512, 513, 600, 5000, 100_000] {
                let obj = FuzzCorpus.deepObject(depth)
                let arr = FuzzCorpus.deepArray(depth)
                // ① hook 行：嵌套放在 detail 里（有效 JSON 的 ts / ev 在前面）
                let hook = "{\"ts\":1790654400123,\"ev\":\"PreToolUse\",\"tool\":\"Bash\",\"detail\":\(obj),\"extra\":\"\"}"
                _ = LineSanitizer.parseHookLine(hook)
                // ② 会话记录行：tool_use 的 input 嵌套很深
                let transcript = "{\"type\":\"assistant\",\"timestamp\":\"2026-09-29T04:12:39.255Z\",\"message\":{\"id\":\"m\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"Bash\",\"input\":\(obj)}],\"usage\":{\"output_tokens\":5}}}"
                let tb = Array(transcript.utf8)
                _ = tb.withUnsafeBufferPointer { TranscriptLineParser.parse($0) }
                // ③ 登记表 / 桌面元数据 / 账本 / 身份文件
                _ = RegistryScanner.parse(Data("{\"pid\":1,\"sessionId\":\"s\",\"x\":\(arr)}".utf8))
                _ = RegistryScanner.parse(Data("{\"pid\":1,\"sessionId\":\"s\",\"x\":\(obj)}".utf8))
                _ = DesktopMetaReader.parse(Data("{\"sessionId\":\"local_x\",\"remoteMcpServersConfig\":\(obj)}".utf8), path: "/x/local_x.json")
                r.check(SafeJSON.object(Data(obj.utf8)) == nil, "深度 \(depth) 的对象应当被当作坏数据")
            }
            // 正常的嵌套（十几层）照常解析
            let ok = "{\"a\":{\"b\":[1,2,{\"c\":[[[[1]]]]}]},\"ts\":1}"
            r.check(SafeJSON.object(Data(ok.utf8)) != nil, "浅的 JSON 应当照常解析")
            // 字符串里的括号不算嵌套
            let inStr = "{\"s\":\"" + String(repeating: "[{", count: 5000) + "\"}"
            r.check(SafeJSON.object(Data(inStr.utf8)) != nil, "字符串里的括号不算嵌套")
            let escaped = "{\"s\":\"" + String(repeating: "\\\"[{", count: 5000) + "\"}"
            r.check(SafeJSON.object(Data(escaped.utf8)) != nil, "转义的引号不结束字符串")
        }
        #expect(finished)
    }

    // MARK: C-013 bootstrap 窗口参数

    @Test("C-013 TranscriptReader.bootstrap 遇到非正的窗口大小不会死循环")
    func c013_bootstrapWithNonPositiveWindowTerminates() {
        let dir = FuzzDir("c013")
        dir.write("t.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m1")) + FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m2")))
        for w in [0, -1, Int.min, 1] {
            let finished = fuzzRun("bootstrap(tailWindow: \(w))", timeout: 15) {
                let r = TranscriptReader(path: dir.file("t.jsonl"))
                r.bootstrap(tailWindow: w)
                let h = HookLogReader(path: dir.file("t.jsonl"))
                _ = h.bootstrap(tailWindow: w)
            }
            #expect(finished, "tailWindow=\(w)")
        }
    }

    // MARK: C-023 字符串字段没有长度上限

    @Test("C-023 外部 JSON 里几 MB 长的字符串字段（标题 / 路径 / id / 工具名 / detail……）被截断到上限，不会原样留在内存 / 快照 / identities.json 里")
    func c023_hugeStringFieldsAreClipped() {
        let big = String(repeating: "长", count: 300_000)                    // 900 KB 的一个字符串
        // ① 登记表
        let reg = #"{"pid":7,"sessionId":"s","cwd":"\#(big)","name":"\#(big)","version":"\#(big)","hostSessionId":"h","waitingFor":"\#(big)","status":"busy"}"#
        if case .some(.some(let r)) = RegistryScanner.parse(Data(reg.utf8)) {
            #expect((r.cwd?.count ?? 0) <= 2048 && (r.name?.count ?? 0) <= 2048 && (r.version?.count ?? 0) <= 64 && (r.waitingFor?.count ?? 0) <= 200)
        } else { Issue.record("登记表应当可用") }
        // id 太长：没法用（不是合法的会话 id），而不是把几 MB 的 id 拿去拼别名
        let longId = String(repeating: "a", count: 5000)
        if case .some(.none) = RegistryScanner.parse(Data(#"{"pid":7,"sessionId":"\#(longId)"}"#.utf8)) {} else { Issue.record("超长 sessionId 应当不可用") }
        if case .some(.some(let r)) = RegistryScanner.parse(Data(#"{"pid":7,"sessionId":"s","hostSessionId":"\#(longId)"}"#.utf8)) { #expect(r.hostSessionId == nil) }
        // ② 桌面元数据
        let meta = #"{"sessionId":"local_x","cliSessionId":"c","title":"\#(big)","cwd":"\#(big)","postTurnSummary":{"status_category":"blocked","status_detail":"\#(big)","needs_action":"\#(big)"}}"#
        let m = DesktopMetaReader.parse(Data(meta.utf8), path: "/x/local_x.json")
        #expect((m?.title?.count ?? 0) <= 2048 && (m?.cwd?.count ?? 0) <= 2048)
        #expect((m?.postTurnSummary?.statusDetail?.count ?? 0) <= 4096 && (m?.postTurnSummary?.needsAction?.count ?? 0) <= 4096)
        #expect(DesktopMetaReader.parse(Data(#"{"sessionId":"\#(longId)"}"#.utf8), path: "/x/local_x.json") == nil)
        // ③ hook 行
        let hook = #"{"ts":1790654400123,"ev":"PreToolUse","tool":"\#(big)","detail":"\#(big)","extra":"\#(big)"}"#
        if let e = LineSanitizer.parseHookLine(hook) {
            #expect(e.tool.count <= 200 && e.detail.count <= 4096 && e.extra.count <= 4096)
        } else { Issue.record("hook 行应当解析成功（字段被截断）") }
        let broken = #"{"ts":1790654400123,"ev":"PreToolUse","tool":"\#(big)"#
        if let e = LineSanitizer.parseHookLine(broken) { #expect(e.tool.count <= 200) }
        #expect(LineSanitizer.parseHookLine(#"{"ts":1790654400123,"ev":"\#(String(repeating: "E", count: 500))"}"#) == nil)      // 事件名不可能这么长
        // ④ 会话记录
        let line = #"{"type":"assistant","timestamp":"2026-09-29T04:12:39.255Z","message":{"id":"\#(big)","model":"\#(big)","stop_reason":"\#(big)","content":[{"type":"tool_use","id":"\#(big)","name":"\#(big)","input":{"command":"\#(big)"}}]}}"#
        let bytes = Array(line.utf8)
        if let p = bytes.withUnsafeBufferPointer({ TranscriptLineParser.parse($0) }) {
            #expect((p.messageId?.count ?? 0) <= 200 && (p.model?.count ?? 0) <= 200 && (p.stopReason?.count ?? 0) <= 64)
            #expect(p.toolUses.allSatisfy { $0.id.count <= 200 && $0.name.count <= 200 && $0.key.count <= 160 })
        } else { Issue.record("会话记录行应当解析成功") }
        let title = Array(#"{"type":"custom-title","customTitle":"\#(big)"}"#.utf8)
        #expect((title.withUnsafeBufferPointer { TranscriptLineParser.parse($0) }?.text?.count ?? 0) <= 2048)
    }

    // MARK: C-025 会缓存到界面上的数字没有范围

    @Test("C-025 会话记录里 turn_duration / api_error 的数字（用时、重试次数）是天文数字或负数时被当作没有，不会流到快照里让界面的 Int(秒数) 换算 trap")
    func c025_durationsAndRetryCountsAreBounded() {
        func parse(_ text: String) -> TranscriptLine? { Array(text.utf8).withUnsafeBufferPointer { TranscriptLineParser.parse($0) } }
        let ts = "\"timestamp\":\"2026-09-29T04:12:39.255Z\""
        for bad in ["1e300", "-1e300", "-5", "1e13", "1e15", "9223372036854775807", "true", "\"x\"", "null", "[]"] {
            let l = parse("{\"type\":\"system\",\"subtype\":\"turn_duration\",\(ts),\"durationMs\":\(bad)}")
            #expect(l?.durationMs == nil, "durationMs=\(bad) 应当被当作没有：\(String(describing: l?.durationMs))")
            let e = parse("{\"type\":\"system\",\"subtype\":\"api_error\",\(ts),\"retryAttempt\":\(bad),\"maxRetries\":\(bad),\"retryInMs\":\(bad)}")
            #expect(e?.retryAttempt == nil && e?.maxRetries == nil && e?.retryInMs == nil, "api_error 的 \(bad) 应当被当作没有")
        }
        // 正常的值原样保留
        #expect(parse("{\"type\":\"system\",\"subtype\":\"turn_duration\",\(ts),\"durationMs\":192000}")?.durationMs == 192_000)
        let ok = parse("{\"type\":\"system\",\"subtype\":\"api_error\",\(ts),\"retryAttempt\":2,\"maxRetries\":10,\"retryInMs\":2500.5}")
        #expect(ok?.retryAttempt == 2 && ok?.maxRetries == 10 && ok?.retryInMs == 2500.5)
        // 事实里也一样：绝不出现天文数字的用时
        var facts = TranscriptFacts()
        if let l = parse("{\"type\":\"system\",\"subtype\":\"turn_duration\",\(ts),\"durationMs\":1e300}") { facts.apply(l, includeSidechain: false) }
        #expect(facts.turnDurationMs == nil)
    }

    // MARK: C-026 时间戳远在未来毒化状态

    @Test("C-026 hook 里一条时间戳在一年以后的 Stop、会话记录里一条一年以后的行，不会让登记表明明是 busy 的会话永远被当成 idle，也不会毒化“取最大时间”的事实")
    func c026_farFutureTimestampsDoNotPoisonState() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
        h.advance(0.5); h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)
        let year = 86400.0 * 365
        h.tree.appendHook(f.sid, Data((#"{"ts":\#(TimeUtil.millis(h.now.addingTimeInterval(year))),"ev":"Stop","tool":"","detail":"","extra":""}"# + "\n").utf8))
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now.addingTimeInterval(year), messageId: "future", block: TL.text(), stopReason: "end_turn")])
        h.advance(2); h.poll()
        // 下一轮开始：登记表 busy（新的 statusUpdatedAt）+ 新的用户输入 + 一个工具
        h.advance(20)
        h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
        h.tree.hook(f.sid, "UserPromptSubmit"); h.advance(0.3)
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/after/the/future")
        h.advance(0.5); h.poll(); h.advance(0.5); h.poll()
        guard case .tool(let c, _)? = h.snap(DesktopFixture.key)?.activity else {
            Issue.record("新一轮开始之后应该是「Read」，实际 \(String(describing: h.snap(DesktopFixture.key)?.activity))（被未来的 Stop 毒化成了 idle）"); return
        }
        #expect(c.name == "Read")
        // 事实里没有远在未来的时间
        let st = h.engine.debugState(key: DesktopFixture.key)
        #expect((st?.transcript?.facts.lastAssistantAt ?? .distantPast) <= h.now.addingTimeInterval(86400 + 1))
        #expect((st?.transcript?.facts.lastLineAt ?? .distantPast) <= h.now.addingTimeInterval(86400 + 1))
        #expect((st?.hookMaxTs ?? .distantPast) <= h.now.addingTimeInterval(86400 + 1))
        #expect((st?.lastStopAt ?? .distantPast) <= h.now.addingTimeInterval(86400 + 1))
    }

    // MARK: C-027 Paths.init 的复杂度

    @Test("C-027 Paths(home:) 遇到几十万个结尾斜杠不会 O(n²) 卡住；结果和原来的语义一致")
    func c027_pathsInitIsLinear() {
        let finished = fuzzRun("Paths.init", timeout: 10) { r in
            let slashes = String(repeating: "/", count: 300_000)
            r.check(Paths(home: "/Users/x" + slashes).home == "/Users/x", "结尾斜杠没去掉干净")
            r.check(Paths(home: slashes).home == "/", "全是斜杠应当只剩一个")
        }
        #expect(finished)
        #expect(Paths(home: "/Users/x/").home == "/Users/x" && Paths(home: "/Users/x").home == "/Users/x")
        #expect(Paths(home: "").home == "" && Paths(home: "/").home == "/" && Paths(home: "//").home == "/")
        #expect(Paths(home: "/带 空格/😀/").home == "/带 空格/😀" && Paths(home: "a//").home == "a")
    }

    // MARK: C-028 TokenLedger.flush 在扫描队列上调用会死锁

    @Test("C-028 在 onChange 回调里（也就是在扫描队列上）调用 TokenLedger.flush() 不会对自己所在的队列 sync 而死锁 / 崩溃")
    func c028_flushFromInsideOnChangeDoesNotDeadlock() {
        let dir = FuzzDir("c028")
        dir.write("t.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m1")))
        let ledger = TokenLedger(ledgerPath: dir.file("ledger.json"), queue: testLedgerQueue())
        let called = FuzzBox(0)
        ledger.onChange = { ledger.flush(); called.value += 1 }
        let finished = fuzzRun("flush inside onChange", timeout: 90) { r in
            ledger.setGroup(key: "k", transcripts: [dir.file("t.jsonl")], helpers: [])
            r.check(ledger.waitUntilIdle(timeout: 60), "扫描没有结束")
        }
        #expect(finished)
        // onChange 是在 waitUntilIdle 判定"空闲"之后才调用的（isScanning 先清、回调后调），等它一小会儿
        let deadline = Date().addingTimeInterval(60)
        while called.value < 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(called.value >= 1, "onChange 没有被调用")
        ledger.flush()
        let back = FileManager.default.contents(atPath: dir.file("ledger.json"))
        #expect(back.flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil)
    }

    // MARK: C-029 一次 poll 交出的 hook 事件没有上界

    @Test("C-029 hook 文件一下子有几十万行（App 被挂起很久 / 文件被换成大文件）：一次 poll 只交出最新的一批事件，不把所有事件堆在内存里")
    func c029_hookReaderBoundsEventsPerPoll() throws {
        let dir = FuzzDir("c029")
        let total = 60_000
        var text = ""
        text.reserveCapacity(total * 110)
        for i in 0..<total { text += FuzzCorpus.hookLine(ts: 1_790_654_400_000 + Int64(i), ev: "PostToolUse", tool: "Read", detail: "f\(i)") + "\n" }
        dir.write("h.events.jsonl", text)
        let r = HookLogReader(path: dir.file("h.events.jsonl"))
        let box = FuzzBox<HookLogReader.PollResult?>(nil)
        let finished = fuzzRun("HookLogReader big poll", timeout: 60) { _ in box.value = r.poll() }
        #expect(finished)
        let res = try #require(box.value)
        #expect(res.events.count <= 20_000, "一次 poll 交出了 \(res.events.count) 个事件")
        #expect(res.reset, "丢掉了旧事件，应当通知调用者作废由它们推出来的状态")
        // 留下的是最新的那批：最后一个事件就是最后一行
        #expect(res.events.last?.ts == Date(timeIntervalSince1970: Double(1_790_654_400_000 + total - 1) / 1000))
        #expect(res.events.first?.ts == Date(timeIntervalSince1970: Double(1_790_654_400_000 + total - res.events.count) / 1000))
        // 之后的增量读取照常
        FakeClaudeTree.appendBytes(dir.file("h.events.jsonl"), Data((FuzzCorpus.hookLine(ts: 1_790_654_500_000, ev: "Stop", tool: "") + "\n").utf8))
        let next = r.poll()
        #expect(next.events.count == 1 && next.events.first?.ev == "Stop" && !next.reset)
    }

    // MARK: C-030 几处小的整数换算 / 参数校验

    @Test("C-030 FileIO.readAll 的负数上限、文件时间的纳秒乘法、DumpFormatter.clock 的 Int(秒数) 换算：极端值不 trap")
    func c030_smallIntegerConversionsDoNotTrap() {
        // ① 文件修改时间（秒 → 纳秒）：APFS 会把时间夹在 ±9223372036 秒以内，别的文件系统 / 网络盘上可能更大，乘 1e9 会溢出
        #expect(FileIO.mtimeNs(sec: 1_790_654_400, nsec: 123) == 1_790_654_400_000_000_123)
        #expect(FileIO.mtimeNs(sec: Int64.max, nsec: 999_999_999) == Int64.max)
        #expect(FileIO.mtimeNs(sec: Int64.min, nsec: 0) == Int64.min)
        #expect(FileIO.mtimeNs(sec: 9_223_372_036, nsec: 854_775_807) == Int64.max)
        #expect(FileIO.mtimeNs(sec: 300_000_000_000, nsec: 0) == Int64.max)
        // ② readAll 的上限参数：负数以前会在 UInt64(maxBytes) 里 trap
        let dir = FuzzDir("c030")
        dir.write("f", "abc")
        #expect(FileIO.readAll(dir.file("f"), maxBytes: -1) == nil)
        #expect(FileIO.readAll(dir.file("f"), maxBytes: Int.min) == nil)
        #expect(FileIO.readAll(dir.file("f"), maxBytes: 3)?.count == 3)
        // ③ dump 的“用时”格式化：时间差是天文数字 / 负数 / NaN
        for v in [1e300, -1e300, Double.infinity, -Double.infinity, Double.nan, 0, 61, 3661, 1e10, 1e11] { _ = DumpFormatter.clock(v) }
        #expect(DumpFormatter.clock(3661) == "1:01:01" && DumpFormatter.clock(61) == "1:01" && DumpFormatter.clock(-5) == "0:00")
    }

    // MARK: C-014 缓存 / 账本无上界

    @Test("C-014 引擎里按会话累积的缓存在会话来来去去之后有上界（transcriptPathCache / transcriptMissAt）")
    func c014_engineCachesStayBoundedWhenSessionsComeAndGo() {
        let h = Harness()
        for i in 0..<300 {
            let sid = String(format: "cccc%04ld-0000-4000-8000-000000000001", i)
            let pid = Int32(3000 + i)
            let sess = FakeClaudeTree.Session(pid: pid, sessionId: sid, host: nil, name: nil, startedAt: h.now)
            if i % 2 == 0 { h.tree.appendTranscript(sid, [TL.userPrompt(sessionId: sid, at: h.now)]) }      // 一半有会话记录，一半"没找到"
            h.tree.writeRegistry(sess, status: "idle")
            h.advance(0.5); h.poll()
            h.advance(2.5); h.poll()
            h.tree.endProcess(pid: pid)
            h.advance(4); h.poll()                       // 防抖 3 秒之后离场
            h.advance(9); h.poll()                       // 非下班工位 8 秒后收回
        }
        h.advance(60); h.poll(); h.advance(60); h.poll()          // 最后一个也收回、缓存清理跑一遍
        #expect(h.snapshots.isEmpty)
        let c = h.engine.cacheSizes
        #expect(c.buddies == 0)
        #expect(c.transcriptPaths <= 32, "会话记录路径缓存应有上界：\(c.transcriptPaths)")
        #expect(c.transcriptMisses <= 32, "没找到的记录应有上界：\(c.transcriptMisses)")
        #expect(c.liveness <= 32 && c.resolvedKeys <= 32)
    }

    @Test("C-015 读过一条很长的行之后，半行缓冲不会一直占着几 MB 内存")
    func c015_pendingBufferIsReleasedAfterALargeLine() {
        let dir = FuzzDir("c015")
        var bytes = [UInt8](repeating: 0x41, count: 3 << 20)          // 3 MiB 的一行（跨很多个 1 MiB 的块）
        bytes.append(0x0A)
        bytes += Array("small\n".utf8)
        dir.write("big.jsonl", Data(bytes))
        let t = JSONLTailer(path: dir.file("big.jsonl"))
        var count = 0
        t.poll { _ in count += 1 }
        #expect(count == 2)
        #expect(t.pendingCapacity <= 256 * 1024, "半行缓冲还占着 \(t.pendingCapacity) 字节")
    }

    @Test("C-017 登记表 pid 不是整数（布尔 / 小数 / 超出 Int32 / 0 / 负数）时当作不可用，而不是被强转成别的 pid；文件名的 pid 为准")
    func c017_registryPidMustBeARealPid() {
        for v in ["true", "false", "1.5", "0", "-3", "4294967297", "9223372036854775807", "1e30", "\"12\"", "null", "[]", "{}"] {
            let r = RegistryScanner.parse(Data(#"{"pid":\#(v),"sessionId":"s"}"#.utf8))
            if case .some(.none) = r {} else { Issue.record("pid=\(v) 应当是 “合法 JSON 但不可用”，实际 \(String(describing: r))") }
        }
        if case .some(.some(let rec)) = RegistryScanner.parse(Data(#"{"pid":35991,"sessionId":"s"}"#.utf8)) { #expect(rec.pid == 35991) }
        else { Issue.record("正常的 pid 应当可用") }
        // 文件名 = pid：记录里的 pid 和文件名不一致时以文件名为准（引擎探测存活用的就是文件名的 pid）
        let dir = FuzzDir("c017")
        dir.write("1001.json", #"{"pid":2002,"sessionId":"s1"}"#)
        let r = RegistryScanner(dir: dir.path).scan(now: Harness.epoch)
        #expect(r.records[1001]?.pid == 1001)
        #expect(r.records[2002] == nil)
    }

    @Test("C-018 会话记录里 AskUserQuestion 的 input 不管带什么字段，detail 都是空串（不能当问题显示）")
    func c018_askUserQuestionTranscriptKeyIsAlwaysEmpty() {
        for name in ["AskUserQuestion", "AskUserQuestion…", " AskUserQuestion "] {
            #expect(ToolDetail.key(name: name, input: ["description": "第一个选项的说明", "command": "x", "question": "q?"]) == "")
        }
        #expect(ToolDetail.key(name: "Bash", input: ["command": "ls"]) == "ls")        // 别的工具不受影响
    }

    @Test("C-019 文件事件按目录边界分流：sessions-old 之类同前缀的兄弟目录不算；空的会话 id 不匹配一切")
    func c019_fileEventRoutingRespectsDirectoryBoundaries() {
        let pre = (sessions: "/h/.claude/sessions", desktop: "/h/Library/Application Support/Claude/claude-code-sessions",
                   monitor: "/h/.claude/.monitor", projects: "/h/.claude/projects")
        let tracked: Set<String> = ["5e1a0000-0000-4000-8000-000000000001", ""]
        func poke(_ p: String...) -> Bool { SessionStore.shouldPoke(paths: p, prefixes: pre, tracked: tracked) }
        #expect(poke("/h/.claude/sessions/123.json"))
        #expect(poke("/h/.claude/sessions"))
        #expect(poke("/h/Library/Application Support/Claude/claude-code-sessions/a/b/local_x.json"))
        #expect(poke("/h/.claude/.monitor/5e1a0000-0000-4000-8000-000000000001.events.jsonl"))
        #expect(poke("/h/.claude/projects/-p/5e1a0000-0000-4000-8000-000000000001.jsonl"))
        #expect(poke("/h/.claude/projects/-p/5e1a0000-0000-4000-8000-000000000001/subagents/agent-1.jsonl"))
        #expect(poke("/h/.claude/.monitor"))
        #expect(poke("/h/.claude/projects"))
        #expect(!poke("/h/.claude/.monitor/019a1111-2222-7333-8444-555566667777.events.jsonl"))       // Codex / 别的会话
        #expect(!poke("/h/.claude/projects/-p/other.jsonl"))
        #expect(!poke("/h/.claude/settings.json"))
        #expect(!poke("/h/.claude/sessions-old/123.json"), "兄弟目录 sessions-old 不是 sessions")
        #expect(!poke("/h/.claude/sessions2"))
        #expect(!poke("/h/Library/Application Support/Claude/claude-code-sessions-backup/x.json"))
        #expect(!poke("/h/.claude/.monitor-old/5e1a0000-0000-4000-8000-000000000001.events.jsonl"))
        #expect(!poke(""))
        #expect(poke("/x", "/h/.claude/sessions/1.json"))                                             // 一批里有一个就算
    }

    @Test("C-020 两个文件声称同一个 hostSessionId 时，桌面元数据读取器不会每次刷新都报告“变了”（抖动）")
    func c020_duplicateHostIdsDoNotThrash() {
        let dir = FuzzDir("c020")
        let org = dir.file("acct/org")
        try? FileManager.default.createDirectory(atPath: org, withIntermediateDirectories: true)
        let body = #"{"sessionId":"local_dup","cliSessionId":"cli-1","title":"t","lastActivityAt":1790654400000}"#
        FakeClaudeTree.writeInPlace(org + "/local_dup.json", Data(body.utf8))
        FakeClaudeTree.writeInPlace(org + "/local_dup copy.json", Data(body.utf8))          // 用户复制出来的副本
        let reader = DesktopMetaReader(rootDir: dir.path)
        _ = reader.refresh()
        var changes = 0
        for _ in 0..<5 { if !reader.refresh().isEmpty { changes += 1 } }
        #expect(changes == 0, "文件没变，refresh 却报告了 \(changes) 次变化")
        #expect(reader.meta(host: "local_dup") != nil)
    }
}

// MARK: C-007 FileIO 保险（放进已有的串行套件 FileAccessTests 的扩展里）
// 原因：FileIO.forbiddenHits / openObserver 是全局的，FileAccessTests 里有 “== hitsBefore” 这类断言，
// 会触发保险的测试必须和它们串行跑，否则互相踩计数器。

let fuzzFakeSha = String(repeating: "ab", count: 32)

extension FileAccessTests {
    @Test("C-007 符号链接指向 .key 文件：FileIO 拒绝打开（保险不能被绕过）")
    func c007_symlinkToKeyFileIsRefused() {
        let dir = FuzzDir("c007a")
        let keyName = "1001.\(fuzzFakeSha).key"
        dir.write(keyName, "FAKE-KEY-CONTENT-NOT-A-REAL-SECRET")          // 可读的假 .key：如果被打开就能读到内容，测试就抓得到
        symlink(dir.file(keyName), dir.file("1001.json"))                    // 名字合法的登记表文件名，实际指向 .key
        try? FileManager.default.createDirectory(atPath: dir.file("sub"), withIntermediateDirectories: true)
        symlink(dir.path, dir.file("sub/loop"))                              // 目录符号链接
        let before = FileIO.forbiddenHits
        #expect(FileIO.readAll(dir.file("1001.json")) == nil, "通过符号链接读到了 .key 的内容")
        #expect(FileIO.open(dir.file("1001.json")) == -1)
        #expect(FileIO.open(dir.file("sub/loop/\(keyName)")) == -1)
        // 经过目录符号链接、文件名合法（.json）的路径也要挡住：把 .key 的内容“放”到一个 .json 名字下面（硬链接除外）
        symlink(dir.file(keyName), dir.file("sub/2002.json"))
        #expect(FileIO.readAll(dir.file("sub/loop/sub/2002.json")) == nil)
        #expect(FileIO.forbiddenHits >= before + 3)
        // 扫描器层面：目录里有一个指向 .key 的 <pid>.json，不能读出记录，也不能崩
        let s = RegistryScanner(dir: dir.path)
        let r = s.scan(now: Harness.epoch)
        #expect(r.records.isEmpty)
    }

    @Test("C-007 .KEY / .Sock / CC-SOCKS 的大小写变体、路径里的 NUL、../ 都被保险认出来")
    func c007_caseVariantsNulAndDotDotAreForbidden() {
        let forbidden = [
            "/h/.claude/sessions/1001.abc.KEY", "/h/.claude/sessions/1001.abc.Key", "/x/A.SOCK", "/x/a.Sock",
            "/tmp/CC-SOCKS/1.txt", "/tmp/Cc-Socks/x", "/tmp/cc-socks/x", "/x/.key", "/x/.KEY",
            "/x/123.key\u{0}.json", "/x/123.json\u{0}.key", "/x/a\u{0}b",           // 路径里有 NUL：C 字符串会在这里截断
            "/x/y/../1001.abc.key", "/x/1001.abc.key/", "/x/1001.abc.key//",
        ]
        for p in forbidden { #expect(FileIO.isForbidden(path: p), "应该被禁止：\(p.debugDescription)") }
        let fine = ["/h/.claude/sessions/1001.json", "/h/.claude/.monitor/abc.events.jsonl", "/x/key.json", "/x/keys/1.json",
                    "/x/1001.abc.key.json", "/x/sock.jsonl", "/x/cc-socks-notes.txt"]
        for p in fine { #expect(!FileIO.isForbidden(path: p), "不该被误伤：\(p)") }

        // 真正的大小写不敏感文件系统（APFS 默认）：用大写名字打开小写名字的文件
        let dir = FuzzDir("c007b")
        let keyName = "1001.\(fuzzFakeSha).key"
        dir.write(keyName, "FAKE-KEY-CONTENT-NOT-A-REAL-SECRET")
        let upper = dir.file(keyName.uppercased())
        if FileManager.default.fileExists(atPath: upper) {
            #expect(FileIO.open(upper) == -1, "大小写不敏感的文件系统上，大写名字打开了 .key")
            #expect(FileIO.readAll(upper) == nil)
        }
        // NUL 注入：Swift 字符串里带 NUL，传给 open() 时会在 NUL 处截断成 “…/1001.<sha>.key”
        let nul = dir.file(keyName) + "\u{0}.json"
        #expect(FileIO.open(nul) == -1)
    }

    @Test("C-014 token 账本：没有 buddy 在用的文件不再被扫描（不再 stat / open），也不会无限累积")
    func c014_ledgerDoesNotKeepScanningOrHoardingDetachedFiles() throws {
        let dir = FuzzDir("c014")
        let lp = dir.file("ledger.json")
        let ledger = TokenLedger(ledgerPath: lp, queue: testLedgerQueue())
        // ① 不再被使用的文件：之后追加内容、poke，账本不该再去打开它
        let a = dir.file("a.jsonl")
        dir.write("a.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "a1", input: 1, output: 2, cacheWrite: 3, cacheRead: 4)))
        ledger.setGroup(key: "A", transcripts: [a], helpers: [])
        #expect(ledger.waitUntilIdle(timeout: 60))
        #expect(ledger.totals(forKey: "A").messages == 1)
        ledger.removeGroup(key: "A")
        let opened = FuzzBox<[String]>([])
        FileIO.openObserver = { p in if p.hasPrefix(dir.path) { opened.value.append(p) } }
        defer { FileIO.openObserver = nil }
        FakeClaudeTree.appendBytes(a, FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "a2")))
        // 有别的 buddy 在用的文件被 poke 了：只该碰它
        dir.write("b.jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "b1")))
        ledger.setGroup(key: "B", transcripts: [dir.file("b.jsonl")], helpers: [])
        ledger.poke()
        #expect(ledger.waitUntilIdle(timeout: 60))
        #expect(!opened.value.contains(a), "没有 buddy 在用的文件还在被扫描")
        #expect(opened.value.contains(dir.file("b.jsonl")))
        FileIO.openObserver = nil

        // ② 大量 buddy 来来去去：跟着的文件数和去重表都有上界
        for i in 0..<150 {
            let f = dir.file("s\(i).jsonl")
            dir.write("s\(i).jsonl", FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "sid-\(i)")))
            ledger.setGroup(key: "k\(i)", transcripts: [f], helpers: [])
            #expect(ledger.waitUntilIdle(timeout: 60))
            ledger.removeGroup(key: "k\(i)")
        }
        #expect(ledger.trackedFileCount <= 100, "账本跟着的文件数应有上界：\(ledger.trackedFileCount)")
        #expect(ledger.dedupeEntryCount <= 100, "去重表应有上界：\(ledger.dedupeEntryCount)")

        // ③ 被清出去的会话又回来了：统计值正确（从账本断点恢复或重新扫描）
        ledger.setGroup(key: "back", transcripts: [dir.file("s0.jsonl")], helpers: [])
        #expect(ledger.waitUntilIdle(timeout: 60))
        let t = ledger.totals(forKey: "back")
        #expect(t.messages == 1 && t.breakdown.input == 10 && t.breakdown.output == 20)
        ledger.flush()
        let back = try #require(FileManager.default.contents(atPath: lp))
        #expect((try? JSONSerialization.jsonObject(with: back)) != nil)
    }

    @Test("C-021 子代理的 .meta.json 一直不存在时，不会每次 poll 都去 open 它")
    func c021_missingSubagentMetaIsNotRetriedOnEveryPoll() {
        let dir = FuzzDir("c021")
        let sub = dir.file("sess/subagents")
        try? FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        let now = Date()
        // 还没做完（stop_reason = tool_use）、刚写过：属于活跃的小助手
        FakeClaudeTree.writeInPlace(sub + "/agent-abc.jsonl", FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "m", at: now, stop: "tool_use")))
        let reader = SubagentReader(sessionDir: dir.file("sess"))
        let opened = FuzzBox<[String]>([])
        FileIO.openObserver = { p in if p.hasPrefix(dir.path) { opened.value.append(p) } }
        defer { FileIO.openObserver = nil }
        reader.poll(now: now, list: true)
        for i in 1...60 { reader.poll(now: now.addingTimeInterval(Double(i) * 0.05), list: false) }
        let metaOpens = opened.value.filter { $0.hasSuffix("agent-abc.meta.json") }.count
        #expect(metaOpens <= 3, "没有 meta 文件时被反复 open 了 \(metaOpens) 次")
        // meta 出现以后（下一次列目录的时候）能读到
        FakeClaudeTree.writeInPlace(sub + "/agent-abc.meta.json", Data(#"{"agentType":"x","description":"d","requestShape":"background"}"#.utf8))
        reader.poll(now: now.addingTimeInterval(10), list: true)
        #expect(reader.snapshots(now: now.addingTimeInterval(10)).first?.description == "d")
    }
}
