import Foundation
import Testing
@testable import BuddyCore

@Suite struct TokenLedgerTests {
    let t0 = Harness.epoch
    let sid = "dddddddd-0000-4000-8000-000000000001"
    func at(_ s: Double) -> Date { Harness.at(s) }

    func ledger(persist: String? = nil) -> TokenLedger {
        TokenLedger(ledgerPath: persist, queue: DispatchQueue(label: "test.tokenscan"))
    }

    func line(_ id: String, at s: Double, input: Int = 0, output: Int = 0, cw: Int = 0, cr: Int = 0, w5: Int? = nil, w1: Int? = nil,
              model: String = "claude-opus-5-5", agent: String? = nil) -> [String: Any] {
        TL.assistant(sessionId: sid, at: at(s), messageId: id, block: TL.text(), stopReason: "end_turn", model: model,
                     usage: TL.usage(input: input, output: output, cacheWrite: cw, cacheRead: cr, write5m: w5, write1h: w1), agentId: agent)
    }

    func write(_ f: TempFile, _ lines: [[String: Any]]) {
        var d = Data()
        for l in lines { d += FakeClaudeTree.jsonLine(l) }
        f.write(d)
    }

    func total(_ l: TokenLedger, _ key: String = "k") -> TokenBreakdown {
        _ = l.waitUntilIdle(timeout: 60)
        return l.totals(forKey: key).breakdown
    }

    @Test func sumsInputOutputCacheWriteAndCacheRead() {
        let f = TempFile(name: "tok")
        write(f, [line("m1", at: 1, input: 10, output: 20, cw: 300, cr: 4000), line("m2", at: 2, input: 1, output: 2, cw: 3, cr: 4)])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        let t = total(l)
        #expect(t == TokenBreakdown(input: 11, output: 22, cacheWrite: 303, cacheRead: 4004))
        #expect(t.total == 11 + 22 + 303 + 4004)
    }

    @Test func sameMessageIdIsCountedOnceWithTheMaximumOfEachField() {
        // 同一条回复会分多行写入：每个字段取最大值（输出 token 在流式过程中递增）
        let f = TempFile(name: "dedupe")
        write(f, [line("m1", at: 1, input: 5, output: 3, cw: 100, cr: 1000),
                  line("m1", at: 1.1, input: 5, output: 40, cw: 100, cr: 1000),
                  line("m1", at: 1.2, input: 5, output: 90, cw: 100, cr: 900),     // cache_read 变小：仍取最大
                  line("m2", at: 2, input: 1, output: 1)])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l) == TokenBreakdown(input: 6, output: 91, cacheWrite: 100, cacheRead: 1000))
    }

    @Test func dedupeAlsoWorksAcrossPollsAndFiles() {
        let a = TempFile(name: "a"), b = TempFile(name: "b")
        write(a, [line("m1", at: 1, output: 10, cr: 500)])
        write(b, [line("m1", at: 1, output: 10, cr: 500), line("m9", at: 3, output: 7)])     // resume 复制了历史
        let l = ledger()
        l.setGroup(key: "k", transcripts: [a.path, b.path], helpers: [])
        #expect(total(l) == TokenBreakdown(input: 0, output: 17, cacheWrite: 0, cacheRead: 500))
        // 增量：同一条消息的后续行
        a.append(FakeClaudeTree.jsonLine(line("m1", at: 1.5, output: 25, cr: 500)))
        l.poke()
        #expect(total(l) == TokenBreakdown(input: 0, output: 32, cacheWrite: 0, cacheRead: 500))
    }

    @Test func syntheticAndIncompleteLinesAreIgnored() {
        let f = TempFile(name: "ign")
        var noTs = line("m3", at: 3, output: 999)
        noTs["timestamp"] = nil
        var noId = line("", at: 4, output: 999)
        (noId["message"] as? [String: Any]).map { var m = $0; m["id"] = nil; noId["message"] = m }
        write(f, [line("m1", at: 1, output: 5, model: "<synthetic>"),           // 合成的
                  noTs,                                                          // 没有 timestamp
                  noId,                                                          // 没有 message.id
                  TL.userPrompt(sessionId: sid, at: at(5), text: "usage assistant"),   // 用户行里出现这两个词也不算
                  ["type": "assistant", "timestamp": TL.iso(at(6)), "message": ["id": "e", "role": "assistant", "usage": [String: Any]()] as [String: Any]],   // usage 为空
                  line("m2", at: 7, output: 11)])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l).output == 11)
    }

    @Test func cacheCreationSplitFollowsTheMeterRule() {
        // 细分对得上总数：5m + 1h；对不上：全部当 5m。两种情况总量都是 cache_creation_input_tokens
        let f = TempFile(name: "cc")
        write(f, [line("m1", at: 1, cw: 300, w5: 100, w1: 200), line("m2", at: 2, cw: 500, w5: 1, w1: 2)])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l).cacheWrite == 800)
    }

    @Test func subagentTranscriptsAreAddedToTheBuddysTotal() {
        let main = TempFile(name: "m"), sub = TempFile(name: "s")
        write(main, [line("m1", at: 1, output: 10)])
        write(sub, [line("s1", at: 2, output: 5, agent: "ag1"), line("s2", at: 3, output: 6, agent: "ag1")])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [main.path], helpers: [sub.path])
        #expect(total(l).output == 21)
    }

    @Test func truncatedFileIsRescannedFromTheStart() {
        let f = TempFile(name: "trunc")
        write(f, [line("m1", at: 1, output: 100), line("m2", at: 2, output: 200)])
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l).output == 300)
        write(f, [line("m5", at: 9, output: 7)])                  // 文件被重写了（变短）
        l.poke()
        #expect(total(l).output == 7)
    }

    @Test func partialLineIsCountedOnlyOnceItIsComplete() {
        let f = TempFile(name: "half")
        let full = String(decoding: FakeClaudeTree.jsonLine(line("m1", at: 1, output: 42)), as: UTF8.self)
        f.write(String(full.prefix(50)))
        let l = ledger()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l).output == 0)
        f.append(String(full.dropFirst(50)))
        l.poke()
        #expect(total(l).output == 42)
    }

    @Test func ledgerFileRestoresProgressAndDedupesAcrossTheBoundary() throws {
        let f = TempFile(name: "res")
        let ledgerFile = TempFile(name: "ledger")
        write(f, [line("m1", at: 1, input: 1, output: 10, cw: 100, cr: 1000), line("m2", at: 2, output: 20)])
        let l1 = ledger(persist: ledgerFile.path)
        l1.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l1).output == 30)
        l1.flush()
        #expect(FileIO.stat(ledgerFile.path) != nil)

        // 重启后：从断点继续，不重复统计；跨断点的同一条消息的新行也能去重（账本里存了最近几条消息）
        f.append(FakeClaudeTree.jsonLine(line("m2", at: 2.1, output: 50)))      // m2 的后续行（输出变大）
        f.append(FakeClaudeTree.jsonLine(line("m3", at: 3, output: 5)))
        let l2 = ledger(persist: ledgerFile.path)
        l2.setGroup(key: "k", transcripts: [f.path], helpers: [])
        let t = total(l2)
        #expect(t.output == 10 + 50 + 5)
        #expect(t.input == 1 && t.cacheWrite == 100 && t.cacheRead == 1000)
    }

    @Test func groupsWithPriorSessionsAreRescannedInsteadOfUsingTheLedger() {
        let a = TempFile(name: "pa"), b = TempFile(name: "pb")
        let ledgerFile = TempFile(name: "ledger2")
        write(a, [line("m1", at: 1, output: 10)])
        write(b, [line("m1", at: 1, output: 10), line("m2", at: 2, output: 5)])
        let l1 = ledger(persist: ledgerFile.path)
        l1.setGroup(key: "k", transcripts: [a.path, b.path], helpers: [])
        #expect(total(l1).output == 15)
        l1.flush()
        let l2 = ledger(persist: ledgerFile.path)
        l2.setGroup(key: "k", transcripts: [a.path, b.path], helpers: [])
        #expect(total(l2).output == 15)                              // 重扫，跨文件去重仍然准确
    }

    @Test func persistenceFailureDegradesToMemoryOnly() {
        let blocker = TempFile(name: "blocker")
        blocker.write("x")                                           // 一个普通文件，当作"目录"用时建不出来
        let f = TempFile(name: "pf")
        write(f, [line("m1", at: 1, output: 3)])
        let l = ledger(persist: blocker.path + "/sub/ledger.json")
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        #expect(total(l).output == 3)
        l.flush()
        #expect(l.persistenceOK == false)                            // 写不了盘：只在内存里，不崩
        #expect(total(l).output == 3)
    }

    @Test func missingFilesCountAsScannedZeroNotForeverScanning() {
        let l = ledger()
        l.setGroup(key: "k", transcripts: ["/nonexistent/x.jsonl"], helpers: [])
        _ = l.waitUntilIdle(timeout: 60)
        let t = l.totals(forKey: "k")
        #expect(t.breakdown.total == 0)
        #expect(t.scannedAllFiles)
    }

    @Test func aBigFileIsScannedFast() {
        // 44 MB 的会话记录（大部分是几行超长的 tool_result）要在 2 秒内扫完：字节预过滤，不逐行解码
        let f = TempFile(name: "bigscan")
        var d = Data()
        let filler = String(repeating: "x", count: 1_300_000)
        for i in 0..<34 {
            d += FakeClaudeTree.jsonLine(["type": "user", "timestamp": TL.iso(at(Double(i))), "message": ["role": "user", "content": filler]])
            for j in 0..<30 { d += FakeClaudeTree.jsonLine(line("m\(i)-\(j)", at: Double(i), output: 10, cr: 1000)) }
        }
        f.write(d)
        #expect(d.count > 44_000_000)
        let l = ledger()
        let start = Date()
        l.setGroup(key: "k", transcripts: [f.path], helpers: [])
        let t = total(l)
        let secs = Date().timeIntervalSince(start)
        #expect(t.output == 34 * 30 * 10)
        #expect(secs < 2.0, "扫 44 MB 用了 \(secs) 秒")
    }
}
