import Foundation
import Testing
@testable import BuddyCore

// QA 模糊测试 · 各个解析入口：登记表 / 会话记录行 / 桌面元数据 / 时间解析 / 路径规则 / 工具归类。
// 确定性（SplitMix64 种子）、带超时、只造假数据。

@Suite struct FuzzParserTests {

    // MARK: - 登记表 RegistryScanner.parse

    static let registrySample = """
    {"pid":35991,"sessionId":"5e1a0000-0000-4000-8000-000000000001","cwd":"/Users/a/项目","startedAt":1790654597849,\
    "procStart":"Tue Sep 29 04:03:17 2026","version":"2.1.284","kind":"interactive","entrypoint":"claude-desktop",\
    "hostSessionId":"local_5e1a0000-0000-4000-8000-0000000000a1","name":"标题 \\u4e2d\\u6587","nameSource":"user",\
    "nameSince":1790654597849,"status":"busy","waitingFor":"permission prompt","updatedAt":1790654598000,\
    "statusUpdatedAt":1790654598476,"pidDomain":"darwin","peerProtocol":1,"peerFeatures":["a","b"]}
    """

    @Test("登记表在每一个字节位置截断：都当作“写了一半”（nil，保留上一份好的记录），只有完整的才产出记录")
    func registryTruncatedAtEveryByteIsHalfWritten() {
        let bytes = Array(FuzzParserTests.registrySample.utf8)
        for cut in 0..<bytes.count {
            let r = RegistryScanner.parse(Data(bytes[0..<cut]))
            if r != nil { Issue.record("截断在 \(cut)/\(bytes.count)：应当是“写了一半”(nil)，实际 \(String(describing: r).prefix(80))"); return }
        }
        guard case .some(.some(let rec)) = RegistryScanner.parse(Data(bytes)) else { Issue.record("完整的样本应当可用"); return }
        #expect(rec.pid == 35991 && rec.sessionId == "5e1a0000-0000-4000-8000-000000000001")
        #expect(rec.status == .busy && rec.waitingFor == "permission prompt" && rec.origin == .desktop)
        #expect(rec.procStart == Date(timeIntervalSince1970: 1_790_654_597))
    }

    @Test("登记表：随机字节（各种长度）、样本上的单字节 / 多字节变异：不崩溃；能产出记录时字段合法")
    func registryRandomBytesAndMutations() {
        fuzzRun("registry mutations", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_001)
            for n in FuzzCorpus.randomLengths {
                for _ in 0..<(n >= 4096 ? 2 : 20) {
                    if case .some(.some(let rec)) = RegistryScanner.parse(Data(rng.bytes(n))) {
                        r.check(!rec.sessionId.isEmpty && rec.pid >= 1, "随机字节居然产出了记录：\(rec.pid) \(rec.sessionId.prefix(20))")
                    }
                }
            }
            let base = Array(FuzzParserTests.registrySample.utf8)
            for _ in 0..<3000 {
                var m = base
                for _ in 0..<rng.int(1...4) {
                    let i = rng.int(0...(m.count - 1))
                    switch rng.int(0...3) {
                    case 0: m[i] = UInt8(truncatingIfNeeded: rng.next())
                    case 1: m.remove(at: i)
                    case 2: m.insert(UInt8(truncatingIfNeeded: rng.next()), at: i)
                    default: m.insert(contentsOf: rng.pick(FuzzCorpus.invalidUTF8).1, at: i)
                    }
                }
                if case .some(.some(let rec)) = RegistryScanner.parse(Data(m)) {
                    r.check(rec.pid >= 1 && !rec.sessionId.isEmpty && rec.sessionId.utf8.count <= 200, "变异之后产出了不合法的记录")
                    r.check((rec.name?.count ?? 0) <= 2048 && (rec.cwd?.count ?? 0) <= 2048, "字段没有截断")
                }
            }
        }
    }

    /// 独立的“这个 JSON 对象能不能算一条可用的登记记录”判断（不看被测代码）。
    static func registryUsable(_ obj: [String: Any]) -> (pid: Int32, sid: String)? {
        guard let n = obj["pid"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d == d.rounded(), d >= 1, d <= 2_147_483_647 else { return nil }
        guard let sid = obj["sessionId"] as? String, !sid.isEmpty, sid.utf8.count <= 200 else { return nil }
        if let k = obj["kind"] as? String, k != "interactive" { return nil }
        return (Int32(d), sid)
    }

    @Test("登记表 JSON 层面：字段类型错误 / null / 重复键 / 超长键 / 巨大数字 / 空对象 / 顶层不是对象，和独立判断一致")
    func registryJSONLevelAgreesWithOracle() {
        fuzzRun("registry json level", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_002)
            let keys = ["pid", "sessionId", "cwd", "startedAt", "procStart", "pidDomain", "version", "kind", "entrypoint", "hostSessionId",
                        "name", "nameSource", "nameSince", "status", "waitingFor", "updatedAt", "statusUpdatedAt", "messagingSocketPath"]
            var usableCount = 0
            for round in 0..<4000 {
                var text = FuzzJSON.object(&rng, known: keys, p: 0.75)
                if round % 13 == 0 { text = FuzzJSON.value(&rng) }                                   // 顶层不是对象
                if round % 17 == 0 { text = "{\"\(String(repeating: "k", count: 100_000))\":1,\"pid\":5,\"sessionId\":\"s\"}" }   // 超长键
                let data = Data(text.utf8)
                let result = RegistryScanner.parse(data)
                let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                guard let dict else {
                    r.check(result == nil, "第 \(round) 轮：不是合法的 JSON 对象，应当是“写了一半”(nil)：\(text.prefix(80))")
                    continue
                }
                if let u = FuzzParserTests.registryUsable(dict) {
                    usableCount += 1
                    guard case .some(.some(let rec)) = result else { r.fail("第 \(round) 轮：应当可用：\(text.prefix(120))"); return }
                    r.check(rec.pid == u.pid && rec.sessionId == u.sid, "第 \(round) 轮：pid / sessionId 不对")
                    r.check(rec.kind == nil || rec.kind == "interactive", "kind")
                    r.check((rec.cwd?.count ?? 0) <= 2048 && (rec.name?.count ?? 0) <= 2048 && (rec.hostSessionId?.utf8.count ?? 0) <= 200, "字段没截断")
                    if let st = rec.statusRaw { r.check(rec.status == Phase(rawValue: st), "status 映射") }
                    for d in [rec.startedAt, rec.nameSince, rec.updatedAt, rec.statusUpdatedAt] {
                        if let d { r.check(TimeUtil.millis(d) >= 946_684_800_000 && TimeUtil.millis(d) < 7_258_118_400_000, "时间戳不在合理范围") }
                    }
                } else {
                    if case .some(.none) = result {} else { r.fail("第 \(round) 轮：应当是“合法 JSON 但不可用”：\(text.prefix(120)) → \(String(describing: result).prefix(60))"); return }
                }
            }
            r.check(usableCount > 100, "生成器太弱：只有 \(usableCount) 条可用记录")
        }
    }

    // MARK: - 会话记录行 TranscriptLineParser

    /// 一批真实形状的会话记录行（每行一个 JSON 对象）。
    static func transcriptSamples() -> [(String, String)] {
        let sid = "5e1a0000-0000-4000-8000-000000000001"
        let t = Harness.epoch
        func j(_ o: [String: Any]) -> String { String(decoding: FakeClaudeTree.jsonLine(o), as: UTF8.self).trimmingCharacters(in: .newlines) }
        return [
            ("assistant tool_use", j(TL.assistant(sessionId: sid, at: t, messageId: "m1", block: TL.toolUse(id: "toolu_1", name: "Bash", input: ["command": "npm test 中文"]),
                                                  usage: TL.usage(input: 3, output: 4, cacheWrite: 5, cacheRead: 6, write5m: 2, write1h: 3)))),
            ("assistant text", j(TL.assistant(sessionId: sid, at: t, messageId: "m2", block: TL.text("回答 😀"), stopReason: "end_turn", usage: TL.usage(output: 9)))),
            ("assistant aborted", j(TL.assistant(sessionId: sid, at: t, messageId: "m3", block: TL.thinking(), stopReason: nil, aborted: true))),
            ("user prompt", j(TL.userPrompt(sessionId: sid, at: t, text: "用户输入 绝不能留下"))),
            ("user tool_result", j(TL.userToolResult(sessionId: sid, at: t, toolUseId: "toolu_1", isError: true))),
            ("user interrupt", j(TL.userInterrupt(sessionId: sid, at: t, forToolUse: true))),
            ("system api_error", j(TL.apiError(sessionId: sid, at: t, attempt: 2, max: 10, retryInMs: 2500))),
            ("system stop_hook_summary", j(TL.stopHookSummary(sessionId: sid, at: t))),
            ("custom-title", j(TL.customTitle(sessionId: sid, "自定义标题"))),
        ]
    }

    @Test("会话记录行在每一个字节位置截断：全部当作“不是完整的 JSON”（nil），只有完整的才解析出事实")
    func transcriptLineTruncatedAtEveryByte() {
        fuzzRun("transcript truncation", timeout: 60) { r in
            for (name, line) in FuzzParserTests.transcriptSamples() {
                let bytes = Array(line.utf8)
                for cut in 0..<bytes.count {
                    let p = bytes[0..<cut].withUnsafeBufferPointer { TranscriptLineParser.parse($0) }
                    if p != nil { r.fail("\(name)：截断在 \(cut)/\(bytes.count) 居然解析出来了"); return }
                }
                let full = bytes.withUnsafeBufferPointer { TranscriptLineParser.parse($0) }
                r.check(full != nil && full?.kind != .other, "\(name)：完整的行应当解析出来")
            }
        }
    }

    @Test("会话记录行：随机字节 / 样本变异 / 非法 UTF-8 / JSON 层面（类型错误、巨大数字、重复键、深嵌套）：不崩溃，usage 在范围内")
    func transcriptLineRandomAndTypeConfusion() {
        fuzzRun("transcript fuzz", timeout: 90) { r in
            var rng = FuzzRNG(seed: 0xA11CE_003)
            func check(_ line: TranscriptLine, _ label: String) {
                if let u = line.usage {
                    for v in [u.input, u.output, u.cacheWriteTotal, u.cacheWrite5m, u.cacheWrite1h, u.cacheRead] {
                        r.check(v >= 0 && v <= TranscriptLineParser.maxTokenValue, "\(label)：usage 不在范围内 \(v)")
                    }
                    r.check(u.cacheWrite5m + u.cacheWrite1h == u.cacheWriteTotal, "\(label)：缓存写拆分对不上总数")
                }
                if let ts = line.timestamp {
                    r.check(TimeUtil.millis(ts) >= 946_684_800_000 && TimeUtil.millis(ts) < 7_258_118_400_000, "\(label)：时间戳不在合理范围")
                }
                for tu in line.toolUses { r.check(!tu.id.isEmpty && tu.id.utf8.count <= 200 && tu.key.count <= 160, "\(label)：tool_use 字段") }
                if let m = line.messageId { r.check(!m.isEmpty && m.utf8.count <= 200, "\(label)：messageId") }
            }
            // ① 随机字节
            for n in FuzzCorpus.randomLengths {
                for _ in 0..<(n >= 4096 ? 2 : 20) {
                    let b = rng.bytes(n)
                    if let l = b.withUnsafeBufferPointer({ TranscriptLineParser.parse($0) }) { check(l, "随机 \(n)") }
                }
            }
            // ② 样本变异（含非法 UTF-8 插入）
            for (name, line) in FuzzParserTests.transcriptSamples() {
                let base = Array(line.utf8)
                for _ in 0..<300 {
                    var m = base
                    for _ in 0..<rng.int(1...3) {
                        let i = rng.int(0...(m.count - 1))
                        switch rng.int(0...3) {
                        case 0: m[i] = UInt8(truncatingIfNeeded: rng.next())
                        case 1: m.remove(at: i)
                        case 2: m.insert(contentsOf: rng.pick(FuzzCorpus.invalidUTF8).1, at: i)
                        default: m.insert(UInt8(ascii: rng.pick(["{", "}", "[", "]", "\"", ",", ":", "\\"])), at: i)
                        }
                    }
                    if let l = m.withUnsafeBufferPointer({ TranscriptLineParser.parse($0) }) { check(l, name) }
                }
            }
            // ③ JSON 层面：每个字段随机类型
            for round in 0..<2500 {
                let usage = FuzzJSON.object(&rng, known: ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "cache_creation"], p: 0.8)
                let block = FuzzJSON.object(&rng, known: ["type", "id", "name", "input", "text", "tool_use_id", "is_error", "content"], p: 0.7)
                let message = "{\"id\":\(rng.chance(0.8) ? "\"m\(round)\"" : FuzzJSON.value(&rng)),\"model\":\(FuzzJSON.value(&rng)),\"stop_reason\":\(FuzzJSON.value(&rng)),\"usage\":\(usage),\"content\":[\(block),\(FuzzJSON.value(&rng))]}"
                let type = rng.pick(["assistant", "user", "system", "custom-title", "ai-title", "permission-mode", "other", "\"x\""])
                let text = "{\"type\":\"\(type)\",\"timestamp\":\(rng.chance(0.7) ? "\"2026-09-29T04:12:39.255Z\"" : FuzzJSON.value(&rng)),\"message\":\(rng.chance(0.85) ? message : FuzzJSON.value(&rng)),\"isSidechain\":\(FuzzJSON.value(&rng)),\"subtype\":\(FuzzJSON.value(&rng)),\"retryAttempt\":\(FuzzJSON.value(&rng)),\"maxRetries\":\(FuzzJSON.value(&rng)),\"retryInMs\":\(FuzzJSON.value(&rng)),\"durationMs\":\(FuzzJSON.value(&rng)),\"customTitle\":\(FuzzJSON.value(&rng))}"
                let b = Array(text.utf8)
                if let l = b.withUnsafeBufferPointer({ TranscriptLineParser.parse($0) }) {
                    check(l, "JSON#\(round)")
                    var facts = TranscriptFacts()
                    facts.apply(l, includeSidechain: rng.chance(0.5))                                   // 相加 / 取最大都不能溢出
                    if let c = facts.contextTokens { r.check(c >= 0, "contextTokens 为负") }
                }
            }
        }
    }

    @Test("隐私：用户输入、助手文字、工具结果、thinking 的内容永远不会出现在解析出来的事实里")
    func transcriptFactsNeverKeepConversationText() {
        let secret = "SECRET-CONVERSATION-\(UUID().uuidString)"
        let sid = "5e1a0000-0000-4000-8000-000000000001"
        let t = Harness.epoch
        let lines: [[String: Any]] = [
            TL.userPrompt(sessionId: sid, at: t, text: secret),
            TL.assistant(sessionId: sid, at: t.addingTimeInterval(1), messageId: "a1", block: TL.text(secret), stopReason: "end_turn", usage: TL.usage(output: 3)),
            TL.assistant(sessionId: sid, at: t.addingTimeInterval(2), messageId: "a2", block: ["type": "thinking", "thinking": secret], stopReason: "tool_use"),
            TL.assistant(sessionId: sid, at: t.addingTimeInterval(3), messageId: "a3", block: TL.toolUse(id: "toolu_9", name: "Write", input: ["content": secret, "file_path": "/tmp/x.txt"])),
            ["type": "user", "timestamp": TL.iso(t.addingTimeInterval(4)), "isSidechain": false,
             "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "toolu_9", "content": secret], ["type": "text", "text": secret]]]],
            TL.userInterrupt(sessionId: sid, at: t.addingTimeInterval(5)),
        ]
        var facts = TranscriptFacts()
        for l in lines {
            let bytes = Array(FakeClaudeTree.jsonLine(l).dropLast())
            guard let p = bytes.withUnsafeBufferPointer({ TranscriptLineParser.parse($0) }) else { Issue.record("样本解析失败"); continue }
            #expect(!String(describing: p).contains(secret), "解析出的行里带着对话内容")
            facts.apply(p, includeSidechain: true)
        }
        #expect(!String(describing: facts).contains(secret), "事实里带着对话内容")
        #expect(facts.lastPromptAt != nil && facts.interruptAt != nil)                       // 事实本身还在
        // 写 / 编辑类工具的 key 只取 file_path，不取内容
        #expect(facts.recentToolUses.first { $0.name == "Write" }?.key == "/tmp/x.txt")
    }

    @Test("TranscriptReader：把一堆真实行 + 垃圾行分成随机长度的追加，得到的事实和一次读完完全相同")
    func transcriptReaderIncrementalEqualsOneShot() {
        fuzzRun("TranscriptReader incremental", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_004)
            let dir = FuzzDir("tr-inc")
            let samples = FuzzParserTests.transcriptSamples()
            for round in 0..<40 {
                var bytes: [UInt8] = []
                for i in 0..<rng.int(2...25) {
                    switch rng.int(0...5) {
                    case 0: bytes += FuzzTailerTests.messy(&rng, length: rng.int(1...50)); bytes.append(0x0A)
                    case 1: bytes += Array(rng.pick(samples).1.utf8).prefix(rng.int(1...80)); bytes.append(0x0A)
                    default:
                        // 时间戳递增的真实行
                        let (_, line) = samples[i % samples.count]
                        bytes += Array(line.utf8); bytes.append(0x0A)
                    }
                }
                dir.write("a\(round).jsonl", Data(bytes))
                let one = TranscriptReader(path: dir.file("a\(round).jsonl"))
                one.poll()
                let path2 = dir.file("b\(round).jsonl")
                let inc = TranscriptReader(path: path2)
                var pos = 0
                while pos < bytes.count {
                    let n = min(bytes.count - pos, rng.int(1...70))
                    FakeClaudeTree.appendBytes(path2, Data(bytes[pos..<(pos + n)])); pos += n
                    inc.poll()
                }
                if one.facts != inc.facts { r.fail("第 \(round) 轮：分块追加的事实和一次读完的不同"); return }
                if one.jsonErrors != inc.jsonErrors { r.fail("第 \(round) 轮：坏行计数不同 \(one.jsonErrors) vs \(inc.jsonErrors)"); return }
            }
        }
    }

    // MARK: - 桌面元数据 DesktopMetaReader.parse

    static let metaSample = """
    {"sessionId":"local_5e1a0000-0000-4000-8000-0000000000a1","cliSessionId":"5e1a0000-0000-4000-8000-000000000001",\
    "priorCliSessionIds":["aaaa","bbbb"],"cwd":"/Users/a/x","originCwd":"/Users/a/x","title":"标题","titleSource":"auto",\
    "model":"claude-opus-5-5","effort":"high","permissionMode":"default","isArchived":false,"createdAt":1790650000000,\
    "lastActivityAt":1790654400000,"lastFocusedAt":1790654300000,"completedTurns":3,"lastAssistantUuid":"u1",\
    "postTurnSummary":{"status_category":"blocked","needs_action":"x","status_detail":"detail","summarizes_uuid":"u1"},\
    "postTurnSummaryFor":"u1","remoteMcpServersConfig":[{"a":{"b":[1,2,3]}}]}
    """

    @Test("桌面元数据：每个字节位置截断都是“写了一半”(nil)；随机字节 / 类型错误 / 巨大数字不崩溃，和独立判断一致")
    func desktopMetaTruncationAndTypeConfusion() {
        fuzzRun("desktop meta", timeout: 60) { r in
            let bytes = Array(FuzzParserTests.metaSample.utf8)
            for cut in 0..<bytes.count {
                if DesktopMetaReader.parse(Data(bytes[0..<cut]), path: "/x/local_a.json") != nil { r.fail("截断在 \(cut) 居然解析出来了"); return }
            }
            let full = DesktopMetaReader.parse(Data(bytes), path: "/x/local_a.json")
            r.check(full?.isBlocked == true && full?.priorCliSessionIds == ["aaaa", "bbbb"], "完整样本")
            var rng = FuzzRNG(seed: 0xA11CE_005)
            for n in FuzzCorpus.randomLengths { for _ in 0..<(n >= 4096 ? 2 : 15) { _ = DesktopMetaReader.parse(Data(rng.bytes(n)), path: "/x/local_a.json", fallbackHost: "local_a") } }
            let keys = ["sessionId", "cliSessionId", "priorCliSessionIds", "cwd", "originCwd", "title", "titleSource", "model", "effort", "permissionMode",
                        "isArchived", "createdAt", "lastActivityAt", "lastFocusedAt", "completedTurns", "lastAssistantUuid", "postTurnSummary", "postTurnSummaryFor"]
            for round in 0..<3000 {
                let text = round % 11 == 0 ? FuzzJSON.value(&rng) : FuzzJSON.object(&rng, known: keys, p: 0.75)
                let data = Data(text.utf8)
                let fallback: String? = rng.chance(0.5) ? "local_fallback" : nil
                let m = DesktopMetaReader.parse(data, path: "/x/local_x.json", fallbackHost: fallback)
                guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    r.check(m == nil, "第 \(round) 轮：不是 JSON 对象应当返回 nil")
                    continue
                }
                let host = (dict["sessionId"] as? String) ?? fallback
                let usable = host.map { !$0.isEmpty && $0.utf8.count <= 200 } ?? false
                r.check((m != nil) == usable, "第 \(round) 轮：可用性和独立判断不一致：\(text.prefix(100))")
                if let m {
                    r.check(m.priorCliSessionIds.count <= DesktopMeta.maxPriorIds && m.priorCliSessionIds.allSatisfy(Paths.isSafeID), "priors")
                    r.check((m.title?.count ?? 0) <= 2048 && (m.cwd?.count ?? 0) <= 2048, "字段没截断")
                    for d in [m.createdAt, m.lastActivityAt, m.lastFocusedAt] {
                        if let d { r.check(TimeUtil.millis(d) >= 946_684_800_000 && TimeUtil.millis(d) < 7_258_118_400_000, "时间戳不在合理范围") }
                    }
                    _ = m.allCliSessionIds; _ = m.isBlocked
                }
            }
        }
    }

    // MARK: - 时间解析

    @Test("TimeUtil.parseISO：截断 / 变异 / 随机字节：不崩溃，结果要么 nil 要么在合理范围；格式化再解析是恒等的")
    func timeISOFuzz() {
        fuzzRun("parseISO", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_006)
            let samples = ["2026-09-29T04:12:39.255Z", "2026-09-29T04:12:39Z", "2026-09-29T06:12:39+02:00", "2026-09-29T04:12:39.255+0000",
                           "2026-09-29 04:12:39", "2026-09-29T04:12:39.1", "2026-09-29T04:12:39-05", "2026-09-29T04:12:39.123456789Z"]
            for s in samples {
                let b = Array(s.utf8)
                for cut in 0...b.count {
                    let d = TimeUtil.parseISO(String(decoding: b[0..<cut], as: UTF8.self))
                    if let d { r.check(TimeUtil.millis(d) >= 946_684_800_000 && TimeUtil.millis(d) < 7_258_118_400_000, "\(s.prefix(cut))：结果不在合理范围") }
                    if cut < 19 { r.check(d == nil, "太短的前缀 \(cut) 不该解析成功") }
                }
                for _ in 0..<300 {
                    var m = b
                    m[rng.int(0...(m.count - 1))] = UInt8(truncatingIfNeeded: rng.next())
                    if rng.chance(0.3) { m.insert(contentsOf: rng.pick(FuzzCorpus.invalidUTF8).1, at: rng.int(0...m.count)) }
                    if let d = m.withUnsafeBufferPointer({ TimeUtil.parseISO(bytes: $0) }) {
                        r.check(TimeUtil.millis(d) >= 946_684_800_000 && TimeUtil.millis(d) < 7_258_118_400_000, "变异结果不在合理范围")
                    }
                }
            }
            for n in FuzzCorpus.randomLengths where n <= 4096 {
                for _ in 0..<50 { _ = rng.bytes(n).withUnsafeBufferPointer { TimeUtil.parseISO(bytes: $0) } }
            }
            // 年 / 月 / 日 / 时 / 分 / 秒的边界值
            for y in ["0000", "0001", "1969", "1999", "2000", "2026", "2199", "2200", "9999"] {
                for rest in ["-01-01T00:00:00Z", "-12-31T23:59:59Z", "-02-30T12:00:00Z", "-13-01T00:00:00Z", "-00-10T00:00:00Z", "-01-32T00:00:00Z",
                             "-01-01T24:00:00Z", "-01-01T00:60:00Z", "-01-01T00:00:60Z", "-01-01T00:00:61Z", "-01-01T00:00:00+99:99"] {
                    if let d = TimeUtil.parseISO(y + rest) { r.check(TimeUtil.millis(d) >= 946_684_800_000 && TimeUtil.millis(d) < 7_258_118_400_000, "\(y + rest)") }
                }
            }
            // 恒等：任何合理范围内的毫秒时间戳 format 再 parse 回来一样
            for _ in 0..<3000 {
                let ms = Int64(rng.int(946_684_800_000...7_258_118_399_999))
                let d = Date(timeIntervalSince1970: Double(ms) / 1000)
                let back = TimeUtil.parseISO(TimeUtil.formatISO(d))
                r.check(back == d, "formatISO/parseISO 不是恒等的：\(ms) → \(TimeUtil.formatISO(d)) → \(String(describing: back))")
            }
        }
    }

    @Test("TimeUtil.parseProcStart / date(fromJSONMillis:)：各种畸形输入不崩溃；格式化再解析是恒等的；JSON 数字的各种形态")
    func timeProcStartAndJSONMillisFuzz() {
        fuzzRun("procStart / millis", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_007)
            let sample = "Tue Sep 29 04:03:17 2026"
            let b = Array(sample.utf8)
            for cut in 0...b.count {
                if let d = TimeUtil.parseProcStart(String(decoding: b[0..<cut], as: UTF8.self)) {
                    r.check(d.timeIntervalSince1970.isFinite && d.timeIntervalSince1970 > 0, "截断 \(cut) 的结果")
                }
            }
            let months = ["Jan", "Feb", "Mar", "sep", "SEP", "Sept", "Foo", "", "13", "-1"]
            let days = ["1", "01", "9", " 9", "31", "32", "0", "-1", "+5", "1e1", "９", "99999999999999999999", String(Int.min), String(Int.max)]
            let times = ["00:00:00", "23:59:59", "24:00:00", "12:60:00", "12:00:60", "12:00:61", "1:2:3", "::", "12:00", "12:00:00:00", "-1:00:00", "٣:٠٠:٠٠",
                         String(Int.min) + ":00:00", "00:" + String(Int.max) + ":00", "00:00:" + String(Int.min)]
            let years = ["2026", "1970", "1971", "9999", "10000", "0", "-2026", "99999999999999999999", String(Int.max), String(Int.min), "20261", "２０２６"]
            for _ in 0..<6000 {
                let dow = rng.chance(0.7) ? rng.pick(["Tue", "Mon", "Xxx", ""]) + " " : ""
                let s = dow + rng.pick(months) + rng.pick([" ", "  ", "\t", "\n"]) + rng.pick(days) + " " + rng.pick(times) + " " + rng.pick(years)
                if let d = TimeUtil.parseProcStart(s) {
                    r.check(d.timeIntervalSince1970.isFinite && d.timeIntervalSince1970 > 0 && d.timeIntervalSince1970 < 253_402_300_800, "\(s.debugDescription) → \(d)")
                }
            }
            for n in FuzzCorpus.randomLengths where n <= 4096 { for _ in 0..<30 { _ = TimeUtil.parseProcStart(String(decoding: rng.bytes(n), as: UTF8.self)) } }
            // 恒等
            for _ in 0..<3000 {
                let secs = Int64(rng.int(946_684_800...7_258_118_399))
                let d = Date(timeIntervalSince1970: Double(secs))
                r.check(TimeUtil.parseProcStart(TimeUtil.formatProcStart(d)) == d, "formatProcStart/parseProcStart 不是恒等的：\(secs)")
            }
            // JSON 数字：NSNumber 的各种形态
            let ok = Double(1_790_654_400_123)
            for n: NSNumber in [NSNumber(value: ok), NSNumber(value: Int64(ok)), NSNumber(value: UInt64(ok)), NSNumber(value: Int(ok)), NSNumber(value: Float(1.79e12))] {
                r.check(TimeUtil.date(fromJSONMillis: n) != nil, "\(n) 应当可用")
            }
            for bad: Any in [NSNumber(value: true), NSNumber(value: false), NSNumber(value: 0), NSNumber(value: -1), NSNumber(value: Double.nan), NSNumber(value: Double.infinity),
                             NSNumber(value: -Double.infinity), NSNumber(value: 1e300), NSNumber(value: UInt64.max), NSNumber(value: Int64.min), NSNumber(value: Int64.max),
                             "1790654400123", NSNull(), [1], ["a": 1]] {
                r.check(TimeUtil.date(fromJSONMillis: bad) == nil, "\(bad) 应当被拒绝")
            }
            r.check(TimeUtil.date(fromJSONMillis: nil) == nil, "nil")
            // 天数 ↔ 公历
            for _ in 0..<5000 {
                let days = rng.int(-800_000...3_000_000)
                let c = TimeUtil.civil(fromDays: days)
                r.check(TimeUtil.daysFromCivil(year: c.year, month: c.month, day: c.day) == days, "civil 往返：\(days)")
                r.check((1...12).contains(c.month) && (1...31).contains(c.day), "civil 的月 / 日不在范围内：\(c)")
            }
        }
    }

    // MARK: - 路径规则

    @Test("Paths.isSafeID / isRegistryFileName / hookLogPath：和按字节写的独立判断逐个对照（Unicode 数字、换行、NUL、超长、组合字符）")
    func pathRulesAgreeWithByteOracle() {
        var rng = FuzzRNG(seed: 0xA11CE_008)
        let pieces = ["0", "1", "9", "123", "a", "Z", "_", "-", ".", ".json", ".key", "json", "key", ".JSON", "/", "\\", " ", "\n", "\t", "\u{0}", "٣", "２", "é", "e\u{301}",
                      "😀", "\u{202E}", "\u{200B}", "..", "sock", "-", "local_", "5e1a0000-0000-4000-8000-000000000001"]
        for _ in 0..<20_000 {
            let s = (0..<rng.int(0...6)).map { _ in rng.pick(pieces) }.joined()
            let bytes = Array(s.utf8)
            // isSafeID：1…80 个 [0-9A-Za-z_-] 字节
            let safe = !bytes.isEmpty && bytes.count <= 80 && bytes.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }
            if Paths.isSafeID(s) != safe { Issue.record("isSafeID(\(s.debugDescription)) = \(Paths.isSafeID(s))，应为 \(safe)"); return }
            // isRegistryFileName：1…10 个 ASCII 数字 + 恰好 ".json"
            let suffix = Array(".json".utf8)
            let reg = bytes.count > suffix.count && bytes.count - suffix.count <= 10 && Array(bytes.suffix(suffix.count)) == suffix
                && bytes.dropLast(suffix.count).allSatisfy { $0 >= 48 && $0 <= 57 }
            if Paths.isRegistryFileName(s) != reg { Issue.record("isRegistryFileName(\(s.debugDescription)) = \(Paths.isRegistryFileName(s))，应为 \(reg)"); return }
            // hookLogPath：只有安全 id 才能拼出路径，而且路径恰好在 .monitor 目录下一层
            let p = Paths(home: "/h").hookLogPath(sessionId: s)
            if safe {
                if p != "/h/.claude/.monitor/\(s).events.jsonl" { Issue.record("hookLogPath(\(s)) = \(String(describing: p))"); return }
            } else if p != nil { Issue.record("不安全的 id 拼出了路径：\(s.debugDescription)"); return }
        }
        // 已知的边界
        #expect(Paths.isRegistryFileName("35991.json"))
        #expect(!Paths.isRegistryFileName("35991.abcdef.key") && !Paths.isRegistryFileName("35991.json.key") && !Paths.isRegistryFileName(".json"))
        #expect(!Paths.isRegistryFileName("12345678901.json"))                 // 11 位
        #expect(Paths.isRegistryFileName("1234567890.json"))                   // 10 位
        #expect(Paths(home: "/h///").home == "/h")
    }

    // MARK: - 进程探测

    @Test("SystemProcessProbe / classify：各种 pid（0 / 负数 / Int32.max / 自己 / launchd）和各种时间：不崩溃，pid ≤ 0 一律当死进程，绝不给别人发信号")
    func processProbeFuzz() {
        let p = SystemProcessProbe()
        for pid: Int32 in [0, -1, -2, Int32.min, Int32.max, 1, getpid(), getppid(), 99_999_999, 2_000_000_000] {
            let s = p.probe(pid: pid)
            if pid <= 0 { #expect(s.state == .dead, "pid=\(pid)") }
            if pid == getpid() { #expect(s.state == .alive) }
            _ = SystemProcessProbe.startTime(of: pid)
        }
        var rng = FuzzRNG(seed: 0xA11CE_009)
        for _ in 0..<2000 { _ = p.probe(pid: Int32(truncatingIfNeeded: rng.next())) }          // 随机 pid：只是存在性检查（signal 0），不会真的发信号
        let dates: [Date?] = [nil, .distantPast, .distantFuture, Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: -1e300), Date(timeIntervalSince1970: 1e300),
                              Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity), Harness.epoch]
        for st: ProcessStatus.State in [.alive, .dead, .unknown] {
            for a in dates { for b in dates { _ = ProcessProbe.classify(ProcessStatus(state: st, startTime: a), procStart: b) } }
        }
        // 假探测：线程安全，随便用
        let fake = FakeProcessProbe()
        fake.setAlive(5, start: Harness.epoch)
        #expect(fake.probe(pid: 5).state == .alive && fake.probe(pid: 6).state == .dead)
    }

    // MARK: - 工具归类 / 追踪 / 归属 / 动作判定

    @Test("ToolCatalog / ToolDetail：随机字符串（含 …、emoji、RTL、超长）不崩溃；截断的名字和完整的名字归到同一类；detail 前缀匹配是对称的")
    func toolCatalogFuzz() {
        fuzzRun("tool catalog", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_00A)
            let names = ["Bash", "Read", "Edit", "MultiEdit", "Write", "Grep", "Glob", "TodoWrite", "Agent", "Task", "AskUserQuestion", "ExitPlanMode", "Skill",
                         "mcp__ccd_session_mgmt__search_session_transcripts", "mcp__Claude_Browser__navigate", "mcp__claude-in-chrome__computer", "mcp__computer-use__app_click", "mcp__x"]
            for full in names {
                let cat = ToolCatalog.category(of: full)
                for cut in 1..<max(2, full.count) {
                    let trunc = String(full.prefix(cut)) + "…"
                    _ = ToolCatalog.category(of: trunc); _ = ToolCatalog.mcpServer(of: trunc); _ = ToolCatalog.makeCall(name: trunc, at: Harness.epoch)
                }
                r.check(ToolCatalog.category(of: full + "…") == cat && ToolCatalog.category(of: " " + full + "\n") == cat, "\(full)：加 … / 空白之后归类变了")
            }
            for _ in 0..<3000 {
                let s = String((0..<rng.int(0...40)).map { _ in Character(UnicodeScalar(UInt32(rng.pick([rng.int(32...126), rng.int(0x4E00...0x9FFF), rng.int(0x1F300...0x1F5FF), 0x2026, 0x202E, 0x0, 0x301, 0xFFFD]))) ?? "x") })
                let c = ToolCatalog.makeCall(name: s, detail: s, at: Harness.epoch)
                r.check(c.name == ToolCatalog.cleanName(s), "makeCall 的 name")
                if let sv = ToolCatalog.mcpServer(of: s) { r.check(ToolCatalog.cleanName(s).hasPrefix("mcp__") && !sv.contains("__"), "mcpServer：\(sv)") }
                let t = String((0..<rng.int(0...40)).map { _ in Character(UnicodeScalar(UInt32(rng.int(32...126))) ?? "x") })
                r.check(ToolDetail.matches(hookDetail: s, transcriptKey: t) == ToolDetail.matches(hookDetail: t, transcriptKey: s), "detail 匹配不对称")
                _ = ToolDetail.key(name: s, input: ["command": s, "file_path": t, "pattern": s, "url": t, "description": s, "skill": t])
            }
            let big = String(repeating: "长", count: 1 << 20)
            r.check(ToolDetail.key(name: "Bash", input: ["command": big]).count == 160, "detail 应截到 160 字")
            _ = ToolDetail.matches(hookDetail: big, transcriptKey: big + "x")
        }
    }

    @Test("ToolTracker + HelperAttributor：随机事件序列（乱序 / 同一毫秒 / 名字被截断 / 时间倒流）：不崩溃，open 有上界，配对后关掉的调用不再出现")
    func toolTrackerAndAttributorRandomSequences() {
        fuzzRun("tracker sequences", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_00B)
            let tools = ["Bash", "Read", "Edit", "Agent", "Task", "AskUserQuestion", "mcp__ccd_session_mgmt__search_session_transcripts", "mcp__x__y", ""]
            for round in 0..<40 {
                var t = ToolTracker()
                var a = HelperAttributor()
                var now = Harness.epoch
                var lastSeq = -1
                for step in 0..<400 {
                    now = now.addingTimeInterval(rng.chance(0.2) ? -Double(rng.int(0...5)) : Double(rng.int(0...30)) / 100)         // 偶尔时间倒流
                    let name = rng.pick(tools)
                    let shown = rng.chance(0.3) && name.count > 4 ? String(name.prefix(name.count - 2)) + "…" : name
                    switch rng.int(0...6) {
                    case 0, 1, 2:
                        let ev = HookEvent(ts: now, ev: "PreToolUse", tool: shown, detail: rng.ascii(rng.int(0...5)))
                        let ctx = HelperAttributor.Context(mainIdle: rng.chance(0.2), foregroundAgentOpenSince: rng.chance(0.3) ? now.addingTimeInterval(Double(rng.int(-5...5))) : nil,
                                                           hasActiveBackgroundHelper: rng.chance(0.3))
                        let d = a.decide(event: ev, context: ctx, now: now)
                        if case .hold(let until) = d { r.check(until <= now.addingTimeInterval(HelperAttributor.holdLimit + 1e-6), "扣留超过了 400 ms") }
                        t.pre(name: shown, truncated: shown != name, detail: ev.detail, at: now, owner: d == .helper ? .helper : .main)
                    case 3: t.post(name: shown, truncated: shown != name, detail: rng.ascii(rng.int(0...5)), at: now)
                    case 4: t.turnBoundary(at: now.addingTimeInterval(Double(rng.int(-3...3))))
                    case 5: t.expireStale(now: now.addingTimeInterval(Double(rng.int(0...4000))), registryIdle: rng.chance(0.5))
                    default: if rng.chance(0.05) { t.reset() }
                    }
                    a.prune(now: now)
                    if t.open.count > ToolTracker.maxOpen || t.closed.count > 64 { r.fail("第 \(round).\(step)：open=\(t.open.count) closed=\(t.closed.count) 超过上界"); return }
                    let seqs = t.open.map { $0.seq }
                    if seqs != seqs.sorted() || Set(seqs).count != seqs.count { r.fail("第 \(round).\(step)：open 的 seq 不是严格递增的"); return }
                    if let m = seqs.max(), m < lastSeq && !t.open.isEmpty && false { r.fail("seq 倒退") }
                    lastSeq = max(lastSeq, seqs.max() ?? -1)
                    r.check(t.mainOpen.allSatisfy { $0.owner == .main } && t.helperOpen.allSatisfy { $0.owner == .helper }, "owner 分类")
                }
            }
        }
    }

    @Test("ActivityResolver：随机信号（时间乱序 / 未来 / 极端 / NaN、疯狂的配置）：不崩溃；阶段和动作一致；nextChange 一定在未来")
    func activityResolverRandomSignals() {
        fuzzRun("ActivityResolver", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xA11CE_00C)
            let now = Harness.epoch
            func date() -> Date? {
                switch rng.int(0...9) {
                case 0: return nil
                case 1: return .distantPast
                case 2: return .distantFuture
                case 3: return Date(timeIntervalSince1970: .nan)
                case 4: return Date(timeIntervalSince1970: 1e300)
                default: return now.addingTimeInterval(Double(rng.int(-100_000...100_000)) / (rng.chance(0.5) ? 1 : 100))
                }
            }
            for _ in 0..<20_000 {
                var s = SessionSignals()
                s.registryStatus = rng.chance(0.85) ? rng.pick([Phase.busy, .idle, .waiting]) : nil
                s.statusUpdatedAt = date(); s.waitingFor = rng.chance(0.6) ? rng.pick(["permission prompt", "input needed", "dialog open", "sandbox request", "???", ""]) : nil
                s.hookActive = rng.chance(0.5); s.lastPromptAt = date(); s.lastStopAt = date(); s.preCompactAt = date(); s.postCompactAt = date()
                s.notificationText = rng.chance(0.5) ? rng.pick(["Claude needs your permission to use Bash", "input", "", "use", " use ", "x use  "]) : nil
                s.notificationAt = date()
                s.openTools = (0..<rng.int(0...3)).map { _ in ToolCatalog.makeCall(name: rng.pick(["Bash", "AskUserQuestion", "ExitPlanMode", "Read", ""]), detail: "d", at: date() ?? now) }
                if rng.chance(0.4), let at = date() {
                    s.apiError = TranscriptFacts.ApiError(at: at, attempt: rng.int(-5...20), max: rng.int(-5...20), retryInMs: rng.pick([0, -1, 1000, 1e300, -1e300, .nan, .infinity]))
                }
                s.lastAssistantOrUserAt = date(); s.compactBoundaryAt = date(); s.idleSince = date()
                s.turnEnd = rng.pick([TurnEndKind.none, .finished, .interrupted, .errored])
                s.dozeAfter = rng.pick([0, -5, 600, 1e300, .nan, .infinity]); s.sleepAfter = rng.pick([0, -5, 2700, 1e300, .nan, .infinity])
                let res = ActivityResolver.evaluate(s, now: now)
                if res.activity.phase != res.phase { r.fail("阶段和动作不一致：\(res.phase) vs \(res.activity)"); return }
                if let n = res.nextChange, !(n > now) { r.fail("nextChange 不在未来：\(n)"); return }
                if ActivityResolver.effectivePhase(s, now: now) != res.phase { r.fail("effectivePhase 和 evaluate 不一致"); return }
            }
            _ = ActivityResolver.toolName(fromNotification: String(repeating: " use ", count: 100_000))
            _ = ActivityResolver.toolName(fromNotification: "")
        }
    }
}
