import Foundation
import Testing
@testable import BuddyCore

// QA 模糊测试 · 持久化文件（ledger.json / identities.json）和 token 账本的扫描。
// 被截断、乱码、version 不对、字段缺失 / 类型错误 / 天文数字时，都要安全回退（不崩溃，之后仍然能正常写盘）。

@Suite struct FuzzPersistenceTests {

    // MARK: 造一份真实的 ledger.json

    struct LedgerFixture {
        let dir = FuzzDir("ledger-fix")
        var transcript: String { dir.file("t.jsonl") }
        var ledgerPath: String { dir.file("ledger.json") }
        var good = Data()
        var expected = TokenLedger.Totals()

        init() {
            var lines = ""
            for i in 0..<12 {
                lines += FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "msg-\(i)", at: Harness.epoch.addingTimeInterval(Double(i)),
                                                                      input: 10 + i, output: 20 + i, cacheWrite: 5, cacheRead: 100 * i))
            }
            lines += FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "msg-3", at: Harness.epoch, input: 13, output: 99, cacheWrite: 5, cacheRead: 300))   // 同一条消息再写一遍（字段取最大）
            dir.write("t.jsonl", lines)
            let l = TokenLedger(ledgerPath: ledgerPath, queue: testLedgerQueue())
            l.setGroup(key: "k", transcripts: [transcript], helpers: [])
            _ = l.waitUntilIdle(timeout: 60)
            expected = l.totals(forKey: "k")
            l.flush()
            good = dir.read("ledger.json") ?? Data()
        }
    }

    /// 用一份（可能被写坏的）ledger.json 启动账本，扫同一个会话记录，返回统计值。
    static func totals(withLedger data: Data?, fixture f: LedgerFixture, appendMore: Bool = false) -> (TokenLedger.Totals, TokenLedger)? {
        if let data { FakeClaudeTree.writeInPlace(f.ledgerPath, data) } else { unlink(f.ledgerPath) }
        let l = TokenLedger(ledgerPath: f.ledgerPath, queue: testLedgerQueue())
        l.setGroup(key: "k", transcripts: [f.transcript], helpers: [])
        guard l.waitUntilIdle(timeout: 60) else { return nil }
        return (l.totals(forKey: "k"), l)
    }

    @Test("ledger.json 在每一个字节位置被截断：安全回退到从头扫描，统计值 == 真实值；之后写盘的账本合法")
    func ledgerTruncatedAtEveryByte() {
        let f = LedgerFixture()
        #expect(f.expected.messages == 12 && !f.good.isEmpty)
        var cutSet = Set(0..<min(f.good.count, 90))
        cutSet.formUnion(max(0, f.good.count - 90)..<f.good.count)
        var rng = FuzzRNG(seed: 0xB0B0_001)
        for _ in 0..<50 { cutSet.insert(rng.int(0...f.good.count)) }
        let cuts = cutSet.sorted()
        let box = FuzzBox<[String]>([])
        let finished = fuzzRun("ledger truncation", timeout: 120) { r in
            for cut in cuts {
                guard let (t, l) = FuzzPersistenceTests.totals(withLedger: Data(f.good.prefix(cut)), fixture: f) else { r.fail("截断 \(cut)：扫描超时"); return }
                if t.breakdown != f.expected.breakdown || t.messages != f.expected.messages {
                    r.fail("截断在 \(cut)/\(f.good.count)：统计值 \(t.breakdown) ≠ 真实值 \(f.expected.breakdown)")
                    return
                }
                l.flush()
                guard let back = f.dir.read("ledger.json"), let obj = try? JSONSerialization.jsonObject(with: back) as? [String: Any], (obj["version"] as? Int) == 1 else {
                    r.fail("截断 \(cut)：之后写出来的账本不合法"); return
                }
            }
            box.value = ["done"]
        }
        #expect(finished && box.value == ["done"])
    }

    @Test("ledger.json 被随机破坏（翻转 / 替换 / 删除 / 重复 / 插入字节）：不崩溃；统计值非负、不溢出；之后追加新行只增不减；写盘的账本合法")
    func ledgerRandomCorruption() {
        let f = LedgerFixture()
        let finished = fuzzRun("ledger corruption", timeout: 180) { r in
            var rng = FuzzRNG(seed: 0xB0B0_002)
            for round in 0..<100 {
                var m = Array(f.good)
                for _ in 0..<rng.int(1...4) {
                    let i = rng.int(0...(m.count - 1))
                    switch rng.int(0...4) {
                    case 0: m[i] ^= UInt8(1 << rng.int(0...7))
                    case 1: m[i] = UInt8(truncatingIfNeeded: rng.next())
                    case 2: m.remove(at: i)
                    case 3: m.insert(contentsOf: m[i..<min(m.count, i + rng.int(1...30))], at: i)
                    default: m.insert(contentsOf: rng.pick(FuzzCorpus.invalidUTF8).1, at: i)
                    }
                }
                guard let (t0, l) = FuzzPersistenceTests.totals(withLedger: Data(m), fixture: f) else { r.fail("第 \(round) 轮：扫描超时"); return }
                let b = t0.breakdown
                if b.input < 0 || b.output < 0 || b.cacheWrite < 0 || b.cacheRead < 0 || t0.messages < 0 { r.fail("第 \(round) 轮：统计值为负 \(b)"); return }
                _ = b.total                                                            // 不能溢出
                // 追加新的消息：只增不减
                FakeClaudeTree.appendBytes(f.transcript, FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "extra-\(round)-a", input: 7, output: 8, cacheWrite: 9, cacheRead: 10)))
                FakeClaudeTree.appendBytes(f.transcript, FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: "extra-\(round)-b", input: 1, output: 2, cacheWrite: 3, cacheRead: 4)))
                l.poke()
                guard l.waitUntilIdle(timeout: 60) else { r.fail("第 \(round) 轮：追加后扫描超时"); return }
                let t1 = l.totals(forKey: "k")
                if t1.breakdown.input < b.input || t1.breakdown.output < b.output || t1.breakdown.cacheWrite < b.cacheWrite
                    || t1.breakdown.cacheRead < b.cacheRead || t1.messages < t0.messages {
                    r.fail("第 \(round) 轮：追加之后统计值变小了：\(b) → \(t1.breakdown)"); return
                }
                l.flush()
                if let back = f.dir.read("ledger.json"), (try? JSONSerialization.jsonObject(with: back)) == nil { r.fail("第 \(round) 轮：写出来的账本不是合法 JSON"); return }
                // 还原文件（追加进去的行删掉），下一轮重新来
                Darwin.truncate(f.transcript, off_t(FuzzPersistenceTests.originalSize(f)))
            }
        }
        #expect(finished)
    }

    static func originalSize(_ f: LedgerFixture) -> UInt64 {
        // 固定内容：12 行 + 1 行重复；用第一次扫描时的偏移
        let obj = (try? JSONSerialization.jsonObject(with: f.good)) as? [String: Any]
        let files = obj?["files"] as? [String: Any]
        let entry = files?[f.transcript] as? [String: Any]
        return (entry?["offset"] as? NSNumber)?.uint64Value ?? 0
    }

    @Test("ledger.json 结构化破坏：version / files / 每个字段缺失或换成错误类型 / 天文数字 / 负数：不崩溃；断点无效时统计值 == 真实值")
    func ledgerFieldwiseMutations() {
        let f = LedgerFixture()
        guard let goodObj = try? JSONSerialization.jsonObject(with: f.good) as? [String: Any], let files = goodObj["files"] as? [String: Any],
              let entry = files[f.transcript] as? [String: Any] else { Issue.record("样本账本不对"); return }
        let junk: [Any] = [NSNull(), "x", "1", 1.5, -1, true, [1, 2], ["a": 1], 1e30, Int.max, Int.min, UInt64.max, ""]
        let finished = fuzzRun("ledger fieldwise", timeout: 180) { r in
            func run(_ label: String, _ obj: Any, mustEqualExpected: Bool) {
                guard JSONSerialization.isValidJSONObject(obj), let data = try? JSONSerialization.data(withJSONObject: obj) else { return }     // 生成器造出不能序列化的（NaN 等）就跳过
                guard let (t, l) = FuzzPersistenceTests.totals(withLedger: data, fixture: f) else { r.fail("\(label)：扫描超时"); return }
                if t.breakdown.input < 0 || t.breakdown.output < 0 || t.breakdown.cacheWrite < 0 || t.breakdown.cacheRead < 0 { r.fail("\(label)：统计值为负"); return }
                _ = t.breakdown.total
                if mustEqualExpected && (t.breakdown != f.expected.breakdown || t.messages != f.expected.messages) {
                    r.fail("\(label)：断点无效时应该从头扫、统计值 == 真实值，实际 \(t.breakdown) vs \(f.expected.breakdown)")
                }
                l.flush()
                if let back = f.dir.read("ledger.json"), (try? JSONSerialization.jsonObject(with: back)) == nil { r.fail("\(label)：写出来的账本不合法") }
            }
            // version 不对 / 缺失
            for v: Any in [0, 2, "1", NSNull(), 1.5, true, [1], ["a": 1], -1, Int.max] {
                var o = goodObj; o["version"] = v
                run("version=\(v)", o, mustEqualExpected: !(v is Int && (v as! Int) == 1))
            }
            var noVersion = goodObj; noVersion["version"] = nil
            run("没有 version", noVersion, mustEqualExpected: true)
            // files 类型不对
            for v: Any in [NSNull(), [1, 2], "x", 5, true] { var o = goodObj; o["files"] = v; run("files=\(v)", o, mustEqualExpected: true) }
            var noFiles = goodObj; noFiles["files"] = nil
            run("没有 files", noFiles, mustEqualExpected: true)
            // 文件条目本身类型不对
            for v: Any in [NSNull(), [1], "x", 5] { var o = goodObj; o["files"] = [f.transcript: v]; run("entry=\(v)", o, mustEqualExpected: true) }
            // 条目里每个字段：删掉 / 换成各种错误类型
            for key in ["dev", "ino", "offset", "input", "output", "cw", "cr", "n", "recent"] {
                var e = entry; e[key] = nil
                var o = goodObj; o["files"] = [f.transcript: e]
                run("删掉 \(key)", o, mustEqualExpected: ["dev", "ino", "offset"].contains(key))
                for v in junk {
                    var e2 = entry; e2[key] = v
                    var o2 = goodObj; o2["files"] = [f.transcript: e2]
                    // dev / ino 换成不一样的值 → 断点无效 → 重扫；offset 是错误类型（不是数字）→ 无效；数字类型的 offset（true / 1.5 / -1 / 天文数字）可能被接受，不断言相等
                    let invalid: Bool
                    switch key {
                    case "dev", "ino": invalid = true                           // 换成的值都不是真的 dev / ino：断点无效
                    case "offset": invalid = !(v is NSNumber)
                    default: invalid = false
                    }
                    run("\(key)=\(v)", o2, mustEqualExpected: invalid)
                }
            }
            // recent 里的条目
            for v in junk {
                var e = entry; e["recent"] = [v, ["h": v, "i": v, "o": v, "w5": v, "w1": v, "r": v], ["h": "zzzz"], ["h": "ffffffffffffffffff"]]
                var o = goodObj; o["files"] = [f.transcript: e]
                run("recent=\(v)", o, mustEqualExpected: false)
            }
            // 顶层不是对象
            for raw in ["[]", "null", "42", "\"x\"", "", "{", "{\"version\":1,\"files\":{", String(repeating: "[", count: 1000), "{\"version\":1,\"files\":" + FuzzCorpus.deepObject(2000) + "}"] {
                guard let (t, l) = FuzzPersistenceTests.totals(withLedger: Data(raw.utf8), fixture: f) else { r.fail("顶层 \(raw.prefix(20))：超时"); continue }
                r.check(t.breakdown == f.expected.breakdown, "顶层 \(raw.prefix(20).debugDescription)：断点无效时应该从头扫")
                l.flush()
            }
        }
        #expect(finished)
    }

    @Test("ledger.json 是 1 MiB 的随机垃圾 / 是一个目录 / 不可读：不崩溃，账本降级为只在内存里；文件是目录时写不了也不崩溃")
    func ledgerGarbageDirectoryAndUnreadable() {
        let f = LedgerFixture()
        var rng = FuzzRNG(seed: 0xB0B0_003)
        for n in FuzzCorpus.randomLengths {
            guard let (t, l) = FuzzPersistenceTests.totals(withLedger: Data(rng.bytes(n)), fixture: f) else { Issue.record("垃圾 \(n)：超时"); continue }
            #expect(t.breakdown == f.expected.breakdown, "垃圾账本 \(n) 字节：应该从头扫")
            l.flush()
        }
        // 账本路径是一个目录：读不了、写不了（rename 失败）
        unlink(f.ledgerPath)
        try? FileManager.default.createDirectory(atPath: f.ledgerPath + "/sub", withIntermediateDirectories: true)
        let l = TokenLedger(ledgerPath: f.ledgerPath, queue: testLedgerQueue())
        l.setGroup(key: "k", transcripts: [f.transcript], helpers: [])
        #expect(l.waitUntilIdle(timeout: 60))
        #expect(l.totals(forKey: "k").breakdown == f.expected.breakdown)
        l.flush()
        #expect(l.persistenceOK == false)
        try? FileManager.default.removeItem(atPath: f.ledgerPath)
        // 账本文件没有读权限
        FakeClaudeTree.writeInPlace(f.ledgerPath, f.good)
        chmod(f.ledgerPath, 0o000)
        defer { chmod(f.ledgerPath, 0o600) }
        let l2 = TokenLedger(ledgerPath: f.ledgerPath, queue: testLedgerQueue())
        l2.setGroup(key: "k", transcripts: [f.transcript], helpers: [])
        #expect(l2.waitUntilIdle(timeout: 60))
        #expect(l2.totals(forKey: "k").breakdown == f.expected.breakdown)
    }

    // MARK: 账本扫描 vs 独立实现

    /// 独立实现：按任务书 4.3 的规则算一个会话记录文件的 token 总量。
    static func referenceTotals(_ lines: [[UInt8]]) -> (input: Int, output: Int, cacheWrite: Int, cacheRead: Int, messages: Int) {
        var byId: [String: (i: Int, o: Int, w5: Int, w1: Int, r: Int)] = [:]
        func num(_ v: Any?) -> Int {
            guard let n = v as? NSNumber else { return 0 }
            let d = n.doubleValue
            return d > 0 ? Int(min(d, Double(1 << 40))) : 0
        }
        for l in lines {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(l))) as? [String: Any], obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any], let id = msg["id"] as? String, !id.isEmpty,
                  let ts = obj["timestamp"] as? String, TimeUtil.parseISO(ts) != nil,
                  (msg["model"] as? String) != "<synthetic>", let u = msg["usage"] as? [String: Any], !u.isEmpty else { continue }
            let total = num(u["cache_creation_input_tokens"])
            var w5 = 0, w1 = 0
            if let cc = u["cache_creation"] as? [String: Any] { w1 = num(cc["ephemeral_1h_input_tokens"]); w5 = num(cc["ephemeral_5m_input_tokens"]) }
            if w1 + w5 != total { w5 = total; w1 = 0 }
            // 账本每条消息的每个字段按 UInt32 存（4294967295 封顶）——单条消息不可能有这么多 token，这是防坏数据的设计
            func cap(_ v: Int) -> Int { min(v, Int(UInt32.max)) }
            let new = (i: cap(num(u["input_tokens"])), o: cap(num(u["output_tokens"])), w5: cap(w5), w1: cap(w1), r: cap(num(u["cache_read_input_tokens"])))
            if let old = byId[id] { byId[id] = (max(old.i, new.i), max(old.o, new.o), max(old.w5, new.w5), max(old.w1, new.w1), max(old.r, new.r)) } else { byId[id] = new }
        }
        var t = (input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: byId.count)
        for v in byId.values { t.input += v.i; t.output += v.o; t.cacheWrite += v.w5 + v.w1; t.cacheRead += v.r }
        return t
    }

    @Test("token 账本：随机的真实行 / 重复行 / 合成行 / 缺字段行 / 垃圾行 / 半行，分多次追加，统计值和独立实现逐项相等；重启后从账本断点继续也一样")
    func ledgerMatchesIndependentReference() {
        let finished = fuzzRun("ledger vs reference", timeout: 180) { r in
            var rng = FuzzRNG(seed: 0xB0B0_004)
            for round in 0..<25 {
                let dir = FuzzDir("ledger-ref")
                let path = dir.file("t.jsonl"), lp = dir.file("ledger.json")
                var all: [UInt8] = []
                var ledger = TokenLedger(ledgerPath: lp, queue: testLedgerQueue())
                ledger.setGroup(key: "k", transcripts: [path], helpers: [])
                for step in 0..<rng.int(3...10) {
                    var chunk: [UInt8] = []
                    for _ in 0..<rng.int(1...8) {
                        let id = "m\(rng.int(0...6))"
                        switch rng.int(0...9) {
                        case 0: chunk += FuzzTailerTests.messy(&rng, length: rng.int(1...40)); chunk.append(0x0A)
                        case 1:
                            let usage = FuzzJSON.object(&rng, known: ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "cache_creation"], p: 0.8)
                            chunk += Array("{\"type\":\"assistant\",\"timestamp\":\"2026-09-29T04:12:39.255Z\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-opus-5-5\",\"usage\":\(usage)}}\n".utf8)
                        case 2: chunk += Array(FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: id, model: "<synthetic>")))
                        case 3: chunk += Array("{\"type\":\"assistant\",\"timestamp\":\"not a time\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"output_tokens\":5}}}\n".utf8)
                        case 4: chunk += Array("{\"type\":\"user\",\"timestamp\":\"2026-09-29T04:12:39.255Z\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"output_tokens\":5}}}\n".utf8)
                        case 5:
                            let full = Array(FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: id, input: rng.int(0...50), output: rng.int(0...50), cacheWrite: rng.int(0...50), cacheRead: rng.int(0...50))))
                            chunk += full.prefix(rng.int(1...(full.count - 1)))                                    // 半行（没有换行）
                        default:
                            let u = TL.usage(input: rng.int(0...500), output: rng.int(0...500), cacheWrite: rng.int(0...500), cacheRead: rng.int(0...500),
                                             write5m: rng.chance(0.5) ? rng.int(0...200) : nil, write1h: rng.chance(0.5) ? rng.int(0...200) : nil)
                            chunk += Array(FakeClaudeTree.jsonLine(TL.assistant(sessionId: "s", at: Harness.epoch, messageId: id, block: TL.text(), stopReason: "end_turn", usage: u)))
                        }
                    }
                    FakeClaudeTree.appendBytes(path, Data(chunk)); all += chunk
                    ledger.poke()
                    if !ledger.waitUntilIdle(timeout: 60) { r.fail("第 \(round).\(step)：扫描超时"); return }
                    if rng.chance(0.2) && step > 0 {
                        // 重启：写盘，新账本从断点继续（半行会被重新读）
                        ledger.flush(); ledger.cancel()
                        ledger = TokenLedger(ledgerPath: lp, queue: testLedgerQueue())
                        ledger.setGroup(key: "k", transcripts: [path], helpers: [])
                        if !ledger.waitUntilIdle(timeout: 60) { r.fail("第 \(round).\(step)：重启后扫描超时"); return }
                    }
                }
                // 完整行 = 按 \n 切出来的、以 \n 结尾的
                let lines = fuzzReferenceLines(all, maxLineBytes: 4 << 20)
                let ref = FuzzPersistenceTests.referenceTotals(lines)
                let t = ledger.totals(forKey: "k")
                if (t.breakdown.input, t.breakdown.output, t.breakdown.cacheWrite, t.breakdown.cacheRead, t.messages) != (ref.input, ref.output, ref.cacheWrite, ref.cacheRead, ref.messages) {
                    r.fail("第 \(round) 轮：账本 \(t.breakdown) n=\(t.messages) ≠ 独立实现 \(ref)"); return
                }
            }
        }
        #expect(finished)
    }

    @Test("token 账本：一个 buddy 的多个会话记录（当前 + prior）加子代理文件，同一条消息出现在不同文件里时按 message.id 全局去重（每个字段取最大值），和独立实现相等；再启动一次（不使用断点）结果不变")
    func ledgerGroupAcrossFilesMatchesReference() {
        let finished = fuzzRun("ledger multi-file group", timeout: 180) { r in
            var rng = FuzzRNG(seed: 0xB0B0_007)
            for round in 0..<8 {
                let dir = FuzzDir("ledger-multi")
                let files = ["prior.jsonl", "cur.jsonl", "sub.jsonl"].map { dir.file($0) }
                var all: [UInt8] = []
                var ledger = TokenLedger(ledgerPath: dir.file("ledger.json"), queue: testLedgerQueue())
                ledger.setGroup(key: "k", transcripts: [files[0], files[1]], helpers: [files[2]])
                for step in 0..<rng.int(3...8) {
                    for f in files where rng.chance(0.7) {
                        var chunk: [UInt8] = []
                        for _ in 0..<rng.int(1...5) {
                            let id = "m\(rng.int(0...7))"
                            if rng.chance(0.15) { chunk += FuzzTailerTests.messy(&rng, length: rng.int(1...30)); chunk.append(0x0A); continue }
                            let u = TL.usage(input: rng.int(0...300), output: rng.int(0...300), cacheWrite: rng.int(0...300), cacheRead: rng.int(0...300))
                            chunk += Array(FakeClaudeTree.jsonLine(TL.assistant(sessionId: "s", at: Harness.epoch, messageId: id, block: TL.text(), stopReason: "end_turn", usage: u)))
                        }
                        FakeClaudeTree.appendBytes(f, Data(chunk)); all += chunk
                    }
                    ledger.poke()
                    if !ledger.waitUntilIdle(timeout: 60) { r.fail("第 \(round).\(step)：扫描超时"); return }
                }
                let ref = FuzzPersistenceTests.referenceTotals(fuzzReferenceLines(all, maxLineBytes: 4 << 20))
                func same(_ t: TokenLedger.Totals) -> Bool {
                    (t.breakdown.input, t.breakdown.output, t.breakdown.cacheWrite, t.breakdown.cacheRead, t.messages) == (ref.input, ref.output, ref.cacheWrite, ref.cacheRead, ref.messages)
                }
                let t = ledger.totals(forKey: "k")
                if !same(t) { r.fail("第 \(round) 轮：账本 \(t.breakdown) n=\(t.messages) ≠ 独立实现 \(ref)"); return }
                // 写盘、重启：有 prior 的组不用断点、每次重扫，结果必须一样
                ledger.flush(); ledger.cancel()
                ledger = TokenLedger(ledgerPath: dir.file("ledger.json"), queue: testLedgerQueue())
                ledger.setGroup(key: "k", transcripts: [files[0], files[1]], helpers: [files[2]])
                if !ledger.waitUntilIdle(timeout: 60) { r.fail("第 \(round) 轮：重启后扫描超时"); return }
                let t2 = ledger.totals(forKey: "k")
                if !same(t2) { r.fail("第 \(round) 轮：重启之后 \(t2.breakdown) ≠ 独立实现 \(ref)"); return }
            }
        }
        #expect(finished)
    }

    // MARK: identities.json

    struct IdentityFixture {
        let dir = FuzzDir("ident-fix")
        var path: String { dir.file("identities.json") }
        var good = Data()
        init() {
            let now = Harness.epoch
            let r = IdentityResolver(path: path, now: { now })
            func rec(_ pid: Int32, _ sid: String, host: String?, ps: String? = "Tue Sep 29 03:23:08 2026") -> RegistryRecord {
                var x = RegistryRecord(pid: pid, sessionId: sid)
                x.hostSessionId = host; x.procStartRaw = ps; x.procStart = ps.flatMap { TimeUtil.parseProcStart($0) }
                return x
            }
            for (i, x) in [rec(101, "sid-a", host: "local_a"), rec(102, "sid-b", host: nil), rec(103, "sid-c", host: "local_c"), rec(104, "sid-d", host: nil, ps: nil)].enumerated() {
                let m = r.resolve(x, metaLookup: { _ in nil })
                _ = r.assignSeat(forKey: m.identity.key, occupied: Set(0..<i))
            }
            _ = r.reroll(key: "d:local_a")
            r.saveIfNeeded(force: true)
            good = dir.read("identities.json") ?? Data()
        }
    }

    /// 载入之后的不变量。
    static func checkIdentities(_ r: IdentityResolver, now: Date, _ label: String, _ report: FuzzReport) {
        for id in r.all {
            report.check(!id.key.isEmpty && id.key.utf8.count <= IdentityResolver.maxKeyLength, "\(label)：key 不合法")
            report.check(id.seat >= -1 && id.seat <= IdentityResolver.maxSeat, "\(label)：seat=\(id.seat)")
            report.check(id.aliases.count <= IdentityResolver.maxAliases, "\(label)：别名 \(id.aliases.count) 个")
            report.check(id.lastSeenAt <= now && id.createdAt <= id.lastSeenAt, "\(label)：时间不合理")
            report.check(id.aliases.allSatisfy { $0.hasPrefix("host:") || $0.hasPrefix("sid:") || $0.hasPrefix("proc:") }, "\(label)：别名前缀")
        }
        report.check(r.all.count <= IdentityResolver.maxIdentities, "\(label)：身份太多")
    }

    /// 载入 → 正常使用 → 存盘 → 再载入：不崩溃、不变量成立、存出来的文件合法。
    static func exerciseIdentities(_ f: IdentityFixture, data: Data?, label: String, report: FuzzReport) {
        if let data { FakeClaudeTree.writeInPlace(f.path, data) } else { unlink(f.path) }
        let now = Harness.epoch
        let r = IdentityResolver(path: f.path, now: { now })
        checkIdentities(r, now: now, label, report)
        var x = RegistryRecord(pid: 900, sessionId: "fresh-session")
        x.procStartRaw = "Tue Sep 29 03:23:08 2026"; x.procStart = TimeUtil.parseProcStart("Tue Sep 29 03:23:08 2026")
        x.hostSessionId = "local_fresh"
        let m = r.resolve(x, metaLookup: { _ in nil })
        report.check(m.identity.key == "d:local_fresh" || !m.isNew, "\(label)：新会话的 key 不对：\(m.identity.key)")
        let seat = r.assignSeat(forKey: m.identity.key, occupied: [])
        report.check(seat >= 0, "\(label)：分不到工位")
        r.saveIfNeeded(force: true)
        guard let back = f.dir.read("identities.json"), let obj = (try? JSONSerialization.jsonObject(with: back)) as? [String: Any], (obj["version"] as? Int) == 1 else {
            report.fail("\(label)：存出来的文件不合法"); return
        }
        let r2 = IdentityResolver(path: f.path, now: { now })
        checkIdentities(r2, now: now, "\(label) 重载", report)
        report.check(r2.identity(forKey: m.identity.key) != nil, "\(label)：新身份没有存下来")
        report.check(r2.all.sorted { $0.key < $1.key } == r.all.sorted { $0.key < $1.key }, "\(label)：存了再读不是恒等的")
    }

    @Test("identities.json 在每一个字节位置被截断：不崩溃、不变量成立、之后照常写盘")
    func identitiesTruncatedAtEveryByte() {
        let f = IdentityFixture()
        #expect(!f.good.isEmpty)
        let finished = fuzzRun("identities truncation", timeout: 120) { r in
            var cuts = Set(0..<min(f.good.count, 400))
            cuts.formUnion(max(0, f.good.count - 200)..<f.good.count)
            for cut in cuts.sorted() { FuzzPersistenceTests.exerciseIdentities(f, data: Data(f.good.prefix(cut)), label: "截断 \(cut)", report: r) }
        }
        #expect(finished)
    }

    @Test("identities.json 被随机破坏 / 结构化破坏（version、identities、每个字段缺失或类型错误 / 天文数字）：不崩溃、不变量成立、之后照常写盘")
    func identitiesCorruption() {
        let f = IdentityFixture()
        guard let goodObj = try? JSONSerialization.jsonObject(with: f.good) as? [String: Any], let items = goodObj["identities"] as? [[String: Any]], let first = items.first else {
            Issue.record("样本身份文件不对"); return
        }
        let junk: [Any] = [NSNull(), "x", "1", 1.5, -1, true, [1, 2], ["a": 1], 1e30, Int.max, Int.min, UInt64.max, "", 1e300, -1e300, String(repeating: "长", count: 100_000)]
        let finished = fuzzRun("identities corruption", timeout: 180) { r in
            var rng = FuzzRNG(seed: 0xB0B0_005)
            for round in 0..<250 {
                var m = Array(f.good)
                for _ in 0..<rng.int(1...4) {
                    let i = rng.int(0...(m.count - 1))
                    switch rng.int(0...3) {
                    case 0: m[i] ^= UInt8(1 << rng.int(0...7))
                    case 1: m.remove(at: i)
                    case 2: m.insert(contentsOf: rng.pick(FuzzCorpus.invalidUTF8).1, at: i)
                    default: m[i] = UInt8(truncatingIfNeeded: rng.next())
                    }
                }
                FuzzPersistenceTests.exerciseIdentities(f, data: Data(m), label: "随机破坏 #\(round)", report: r)
            }
            for v: Any in [0, 2, "1", NSNull(), 1.5, true, [1], -1] { var o = goodObj; o["version"] = v; FuzzPersistenceTests.exerciseIdentities(f, data: try? JSONSerialization.data(withJSONObject: o), label: "version=\(v)", report: r) }
            for v: Any in [NSNull(), [1, 2], "x", 5, ["a": 1], [NSNull()], [[1]]] { var o = goodObj; o["identities"] = v; FuzzPersistenceTests.exerciseIdentities(f, data: try? JSONSerialization.data(withJSONObject: o), label: "identities=\(v)", report: r) }
            for key in ["key", "seat", "salt", "aliases", "createdAt", "lastSeenAt"] {
                var missing = first; missing[key] = nil
                var o = goodObj; o["identities"] = [missing] + items.dropFirst()
                FuzzPersistenceTests.exerciseIdentities(f, data: try? JSONSerialization.data(withJSONObject: o), label: "删掉 \(key)", report: r)
                for v in junk {
                    var e = first; e[key] = v
                    var o2 = goodObj; o2["identities"] = [e] + items.dropFirst()
                    if JSONSerialization.isValidJSONObject(o2) { FuzzPersistenceTests.exerciseIdentities(f, data: try? JSONSerialization.data(withJSONObject: o2), label: "\(key)=\(String(describing: v).prefix(20))", report: r) }
                }
            }
            // 别名列表里全是垃圾
            var e = first; e["aliases"] = [1, NSNull(), "sid:ok", "x:y", ["a"], String(repeating: "s", count: 5000)] as [Any]
            var o = goodObj; o["identities"] = [e]
            FuzzPersistenceTests.exerciseIdentities(f, data: try? JSONSerialization.data(withJSONObject: o), label: "别名垃圾", report: r)
            // 顶层不是对象 / 随机字节
            for raw in ["[]", "null", "42", "", "{", "{\"version\":1,\"identities\":[", String(repeating: "{\"a\":", count: 3000)] {
                FuzzPersistenceTests.exerciseIdentities(f, data: Data(raw.utf8), label: "顶层 \(raw.prefix(15).debugDescription)", report: r)
            }
            for n in FuzzCorpus.randomLengths { FuzzPersistenceTests.exerciseIdentities(f, data: Data(rng.bytes(n)), label: "垃圾 \(n)", report: r) }
        }
        #expect(finished)
    }

    @Test("引擎：identities.json / ledger.json 都是垃圾时照常启动、照常工作，并且退出时把两份文件写成合法的（覆盖掉垃圾）")
    func engineOverwritesGarbagePersistenceFiles() {
        var rng = FuzzRNG(seed: 0xB0B0_006)
        let root = FileIO.temporaryDirectory + "buddy-persist-" + UUID().uuidString
        let clock = VirtualClock(frozenAt: Harness.epoch)
        let probe = FakeProcessProbe()
        let tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        defer { try? FileManager.default.removeItem(atPath: root) }
        tree.prepare()
        try? FileManager.default.createDirectory(atPath: tree.paths.appSupportDir, withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(tree.paths.identitiesFile, Data(rng.bytes(4096)))
        FakeClaudeTree.writeInPlace(tree.paths.ledgerFile, Data(rng.bytes(4096)))
        var o = SessionEngine.Options(paths: tree.paths, now: { [clock] in clock.now() }, probe: probe)
        o.ledgerQueue = testLedgerQueue()
        o.persist = true; o.scanTokens = true
        let engine = SessionEngine(options: o)
        let sess = FakeClaudeTree.Session(pid: 4001, sessionId: "eeee0000-0000-4000-8000-000000000001", host: "local_eeee0000-0000-4000-8000-000000000001", name: "持久化", startedAt: clock.now())
        tree.appendTranscript(sess.sessionId, [TL.userPrompt(sessionId: sess.sessionId, at: clock.now()),
                                               FuzzCorpus.assistantLine(id: "p1", at: clock.now())])
        tree.writeRegistry(sess, status: "busy")
        for _ in 0..<5 { clock.advance(by: 0.5); _ = engine.poll() }
        _ = engine.ledger?.waitUntilIdle(timeout: 60)
        engine.shutdown()
        for (name, path) in [("identities.json", tree.paths.identitiesFile), ("ledger.json", tree.paths.ledgerFile)] {
            let data = FileManager.default.contents(atPath: path)
            let obj = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            #expect((obj?["version"] as? Int) == 1, "\(name) 没有被写成合法的账本")
        }
        // 重启：能读回来
        let r2 = IdentityResolver(path: tree.paths.identitiesFile, now: { clock.now() })
        #expect(r2.identity(forKey: "d:local_eeee0000-0000-4000-8000-000000000001") != nil)
    }
}
