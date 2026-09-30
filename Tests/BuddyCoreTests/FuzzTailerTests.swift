import Foundation
import Testing
@testable import BuddyCore

// QA 模糊测试 · 增量读取器（JSONLTailer）和 hook 行解析（LineSanitizer / HookLogReader）。
// 全部确定性（SplitMix64 种子），每个用例带超时；只在临时目录里造假文件。

@Suite struct FuzzTailerTests {

    // MARK: 造数据

    /// 一段"像 JSONL 的乱七八糟"：小字母表里随机取，换行 / \r / NUL / 非法 UTF-8 片段的比例故意很高。
    static func messy(_ rng: inout FuzzRNG, length: Int) -> [UInt8] {
        let pieces: [[UInt8]] = [
            Array("a".utf8), Array("b".utf8), Array("{\"x\":1}".utf8), [0x0A], [0x0A], [0x0D, 0x0A], [0x0D], [0x00],
            [0xC3], [0xA9], [0xE4, 0xB8, 0xAD], [0xE4, 0xB8], [0xF0, 0x9F, 0x98, 0x80], [0xF0, 0x9F], [0xFF], [0x80],
            Array(" ".utf8), Array("\\u4e2d".utf8), Array("\\u4e".utf8),
        ]
        var out: [UInt8] = []
        while out.count < length { out.append(contentsOf: rng.pick(pieces)) }
        return Array(out.prefix(length))
    }

    // MARK: 和标准答案逐行对照

    @Test("随机内容 × 极小的块 / 极小的行上限：逐行和独立实现的标准答案一致")
    func tailerMatchesTheReferenceOnRandomFiles() {
        fuzzRun("tailer vs reference", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0001)
            let dir = FuzzDir("tailer-ref")
            for round in 0..<120 {
                let content = FuzzTailerTests.messy(&rng, length: rng.int(0...400))
                let chunk = rng.pick([1, 2, 3, 5, 7, 16, 64, 4096])
                let maxLine = rng.pick([1, 2, 5, 16, 40, 1000])
                dir.write("f.jsonl", Data(content))
                let (lines, t) = fuzzReadAll(dir.file("f.jsonl"), config: .init(maxLineBytes: maxLine, chunkBytes: chunk))
                let expected = fuzzReferenceLines(content, maxLineBytes: maxLine)
                if lines != expected {
                    r.fail("第 \(round) 轮（chunk=\(chunk) maxLine=\(maxLine) len=\(content.count)）：读出 \(lines.count) 行，标准答案 \(expected.count) 行")
                    return
                }
                if t.offset != UInt64(content.count) || t.committedOffset > t.offset {
                    r.fail("offset 不对：offset=\(t.offset) committed=\(t.committedOffset) size=\(content.count)")
                    return
                }
                // committedOffset 之后只可能是没有换行的半行
                if fuzzReferenceLines(Array(content[Int(t.committedOffset)...]), maxLineBytes: Int.max).count != 0 {
                    r.fail("committedOffset 之后还有完整的行")
                    return
                }
            }
        }
    }

    @Test("文件分成随机长度的很多次追加：每一步都只交付完整的行，最终结果和一次读完完全相同")
    func tailerIncrementalAppendsEqualOneShot() {
        fuzzRun("tailer incremental", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0002)
            let dir = FuzzDir("tailer-inc")
            for round in 0..<60 {
                let content = FuzzTailerTests.messy(&rng, length: rng.int(0...600))
                let chunk = rng.pick([1, 3, 8, 64, 4096])
                let maxLine = rng.pick([4, 30, 1000])
                let path = dir.file("f\(round).jsonl")
                let t = JSONLTailer(path: path, config: .init(maxLineBytes: maxLine, chunkBytes: chunk))
                var got: [[UInt8]] = []
                var written = 0
                var previousOffset: UInt64 = 0
                while written < content.count {
                    let n = min(content.count - written, rng.int(1...40))
                    FakeClaudeTree.appendBytes(path, Data(content[written..<(written + n)]))
                    written += n
                    t.poll { got.append(Array($0)) }
                    // 每一步：offset 单调、不超过文件大小；交付的行 = 已经写完的那些完整行
                    if t.offset < previousOffset || t.offset > UInt64(written) || t.committedOffset > t.offset {
                        r.fail("第 \(round) 轮：offset=\(t.offset) previous=\(previousOffset) written=\(written) committed=\(t.committedOffset)")
                        return
                    }
                    previousOffset = t.offset
                    if got != fuzzReferenceLines(Array(content[0..<written]), maxLineBytes: maxLine) {
                        r.fail("第 \(round) 轮：写到 \(written) 字节时已交付 \(got.count) 行，和标准答案不同")
                        return
                    }
                }
            }
        }
    }

    // MARK: 超长行（任务书：单行超过 4 MiB 丢掉并一直跳到下一个 \n）

    @Test("超长行的边界：1.5 MB 保留、恰好 4 MiB 保留、4 MiB + 1 丢掉、16 MiB 丢掉；后面的行都能读到")
    func tailerOversizeLineBoundaries() {
        fuzzRun("oversize lines", timeout: 120) { r in
            let dir = FuzzDir("tailer-big")
            let limit = 4 << 20
            for (label, size, kept) in [("1.5 MB", 1_500_000, true), ("恰好 4 MiB", limit, true), ("4 MiB + 1", limit + 1, false),
                                        ("16 MiB", 16 << 20, false)] {
                var bytes = Array("before\n".utf8)
                bytes.append(contentsOf: [UInt8](repeating: 0x41, count: size))
                bytes.append(0x0A)
                bytes.append(contentsOf: Array("after\n".utf8))
                dir.write("big.jsonl", Data(bytes))
                let (lines, t) = fuzzReadAll(dir.file("big.jsonl"))
                let texts = lines.map { $0.count > 20 ? "<\($0.count) bytes>" : String(decoding: $0, as: UTF8.self) }
                let expected = kept ? ["before", "<\(size) bytes>", "after"] : ["before", "after"]
                r.check(texts == expected, "\(label)：读到 \(texts)，应为 \(expected)")
                r.check(t.droppedOversizeLines == (kept ? 0 : 1), "\(label)：丢弃计数 \(t.droppedOversizeLines)")
                r.check(t.offset == UInt64(bytes.count), "\(label)：offset \(t.offset) != \(bytes.count)")
                // 超长行没有换行结尾（写到一半）：不交付、内存里的半行有上界，等到换行才继续
                var half = Array("x\n".utf8)
                half.append(contentsOf: [UInt8](repeating: 0x42, count: size))
                dir.write("half.jsonl", Data(half))
                let t2 = JSONLTailer(path: dir.file("half.jsonl"))
                var got: [String] = []
                t2.poll { got.append(String(decoding: $0.prefix(4), as: UTF8.self)) }
                r.check(got == ["x"], "\(label) 半行：读到 \(got)")
                FakeClaudeTree.appendBytes(dir.file("half.jsonl"), Data("\nnext\n".utf8))
                t2.poll { got.append(String(decoding: $0.prefix(4), as: UTF8.self)) }
                let expectedHalf = kept ? ["x", "BBBB", "next"] : ["x", "next"]
                r.check(got == expectedHalf, "\(label) 半行补完之后：读到 \(got)，应为 \(expectedHalf)")
            }
        }
    }

    @Test("随机字节：长度 0 / 1 / 2 / 7 / 64 / 4096 / 1 MiB，和标准答案一致，不崩溃")
    func tailerRandomBytesOfEveryLength() {
        fuzzRun("tailer random bytes", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0003)
            let dir = FuzzDir("tailer-rand")
            for n in FuzzCorpus.randomLengths {
                for _ in 0..<(n >= 4096 ? 2 : 6) {
                    let bytes = rng.bytes(n)
                    dir.write("r.jsonl", Data(bytes))
                    let (lines, t) = fuzzReadAll(dir.file("r.jsonl"))
                    r.check(lines == fuzzReferenceLines(bytes, maxLineBytes: 4 << 20), "长度 \(n)：和标准答案不同")
                    r.check(t.offset == UInt64(n), "长度 \(n)：offset \(t.offset)")
                    // 同一份内容再用 hook 读取器的配置（1 MiB 上限、256 KiB 块）读一遍
                    let (lines2, _) = fuzzReadAll(dir.file("r.jsonl"), config: .init(maxLineBytes: 1 << 20, chunkBytes: 256 << 10))
                    r.check(lines2 == fuzzReferenceLines(bytes, maxLineBytes: 1 << 20), "长度 \(n)（hook 配置）：和标准答案不同")
                }
            }
        }
    }

    @Test("半行 / 只有换行 / 很多空行 / CRLF / 结尾没有换行")
    func tailerHalfLinesAndBlankLines() {
        let dir = FuzzDir("tailer-blank")
        func lines(_ s: String) -> [String] {
            dir.write("f.jsonl", s)
            return fuzzReadAll(dir.file("f.jsonl")).lines.map { String(decoding: $0, as: UTF8.self) }
        }
        #expect(lines("") == [])
        #expect(lines("\n") == [])
        #expect(lines("\n\n\n\n") == [])
        #expect(lines("\r\n\r\n") == [])
        #expect(lines("\r") == [])
        #expect(lines("abc") == [])                                   // 没有换行：半行，不交付
        #expect(lines("abc\n") == ["abc"])
        #expect(lines("abc\ndef") == ["abc"])
        #expect(lines("\n\nabc\n\n\ndef\n\n") == ["abc", "def"])
        #expect(lines("a\r\nb\r\n") == ["a", "b"])
        #expect(lines("a\r\r\nb") == ["a\r"])                          // 只去掉最后一个 \r
        #expect(lines(String(repeating: "\n", count: 100_000) + "x\n") == ["x"])
        #expect(lines(String(repeating: "\r\n", count: 50_000) + "y") == [])
    }

    // MARK: 文件被截短 / 轮转 / 替换

    @Test("文件被截短、删除、换成新 inode、再追加：每次都从头读、只交付完整的行，不会读到旧内容的残片")
    func tailerSurvivesTruncationRotationAndReplacement() {
        fuzzRun("tailer rotation", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0004)
            let dir = FuzzDir("tailer-rot")
            let path = dir.file("f.jsonl")
            for round in 0..<25 {
                let t = JSONLTailer(path: path, config: .init(maxLineBytes: 50, chunkBytes: rng.pick([1, 7, 64])))
                var content: [UInt8] = FuzzTailerTests.messy(&rng, length: rng.int(20...200))
                dir.write("f.jsonl", Data(content))
                var sinceReset: [[UInt8]] = []
                t.poll { sinceReset.append(Array($0)) }
                for step in 0..<12 {
                    let op = rng.int(0...4)
                    var expectReset = false
                    switch op {
                    case 0:      // 追加
                        let more = FuzzTailerTests.messy(&rng, length: rng.int(1...80))
                        FakeClaudeTree.appendBytes(path, Data(more)); content += more
                    case 1:      // 截短到比当前 offset 小（原地）
                        if t.offset > 0 {
                            let n = rng.int(0...Int(t.offset) - 1)
                            content = Array(content.prefix(n)); Darwin.truncate(path, off_t(n)); expectReset = true
                        }
                    case 2:      // 换成新 inode（比原来长或短都可以）
                        content = FuzzTailerTests.messy(&rng, length: rng.int(1...300))
                        try? FileManager.default.removeItem(atPath: path)
                        FakeClaudeTree.writeInPlace(path, Data(content)); expectReset = true
                    case 3:      // 删除（读取器应当报告 missing），之后重新出现、从头读
                        try? FileManager.default.removeItem(atPath: path)
                        let res = t.poll { _ in }
                        r.check(res.missing, "第 \(round).\(step)：文件删除后没有报告 missing")
                        content = FuzzTailerTests.messy(&rng, length: rng.int(1...100))
                        FakeClaudeTree.writeInPlace(path, Data(content)); expectReset = true
                        sinceReset = []
                    default:
                        break
                    }
                    let resetsBefore = t.resetCount
                    var delivered: [[UInt8]] = []
                    t.poll { delivered.append(Array($0)) }
                    if expectReset || t.resetCount != resetsBefore { sinceReset = delivered } else { sinceReset += delivered }
                    // 不变量：自上次重置以来交付的全部行 == 当前内容里的全部完整行（没有旧内容的残片，也没有漏行）
                    if sinceReset != fuzzReferenceLines(content, maxLineBytes: 50) {
                        r.fail("第 \(round).\(step)（op=\(op)）：交付 \(sinceReset.count) 行，标准答案 \(fuzzReferenceLines(content, maxLineBytes: 50).count) 行")
                        return
                    }
                    if t.offset > UInt64(content.count) || t.committedOffset > t.offset {
                        r.fail("第 \(round).\(step)：offset=\(t.offset) size=\(content.count)")
                        return
                    }
                }
            }
        }
    }

    @Test("seekToTail：从任意窗口开始，只交付完整的行，起点落在行中间就跳过那半行")
    func tailerSeekToTailAlignsToLineStart() {
        fuzzRun("seekToTail", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0005)
            let dir = FuzzDir("tailer-tail")
            for round in 0..<150 {
                let content = FuzzTailerTests.messy(&rng, length: rng.int(0...300))
                dir.write("f.jsonl", Data(content))
                let window = rng.pick([0, 1, 2, 5, 17, 64, 100, 299, 300, 301, 4096])
                let t = JSONLTailer(path: dir.file("f.jsonl"), config: .init(maxLineBytes: 1000, chunkBytes: rng.pick([1, 5, 4096])))
                t.seekToTail(window: window)
                var got: [[UInt8]] = []
                t.poll { got.append(Array($0)) }
                // 标准答案：窗口起点，落在行中间就对齐到下一行的开头
                var start = max(0, content.count - window)
                if start > 0, content[start - 1] != 0x0A {
                    if let nl = content[start...].firstIndex(of: 0x0A) { start = nl + 1 } else { start = content.count }
                }
                let expected = fuzzReferenceLines(Array(content[start...]), maxLineBytes: 1000)
                if got != expected { r.fail("第 \(round) 轮（window=\(window) len=\(content.count)）：读到 \(got.count) 行，应为 \(expected.count) 行"); return }
                if t.offset != UInt64(content.count) { r.fail("offset \(t.offset) != \(content.count)"); return }
            }
        }
    }

    @Test("从 committedOffset 恢复：新读取器接着读，得到剩下的完整行（半行会被重新读）")
    func tailerResumeFromCommittedOffset() {
        fuzzRun("resume", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0006)
            let dir = FuzzDir("tailer-resume")
            for round in 0..<100 {
                let content = FuzzTailerTests.messy(&rng, length: rng.int(1...300))
                let cut = rng.int(0...content.count)
                dir.write("f.jsonl", Data(content[0..<cut]))
                // 行上限比内容还大：没有超长行（恢复点落在超长行中间不在契约里，见 README）
                let a = JSONLTailer(path: dir.file("f.jsonl"), config: .init(maxLineBytes: 1000, chunkBytes: rng.pick([1, 9, 4096])))
                var first: [[UInt8]] = []
                a.poll { first.append(Array($0)) }
                let resume = a.committedOffset
                let fid = a.fileID
                FakeClaudeTree.appendBytes(dir.file("f.jsonl"), Data(content[cut...]))
                let b = JSONLTailer(path: dir.file("f.jsonl"), config: .init(maxLineBytes: 1000, chunkBytes: rng.pick([1, 9, 4096])))
                b.seek(to: resume, fileID: fid)
                var rest: [[UInt8]] = []
                b.poll { rest.append(Array($0)) }
                if first + rest != fuzzReferenceLines(content, maxLineBytes: 1000) {
                    r.fail("第 \(round) 轮：恢复之后和一次读完不同（cut=\(cut) resume=\(resume)）")
                    return
                }
            }
        }
    }

    // MARK: hook 读取器

    @Test("HookLogReader：一次读完 / 分很多次追加，事件序列相同；计数自洽；坏行被跳过而不是让整个文件失败")
    func hookReaderIncrementalEqualsOneShot() {
        fuzzRun("HookLogReader", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xF00D_0007)
            let dir = FuzzDir("hook-inc")
            for round in 0..<40 {
                var bytes: [UInt8] = []
                var goodCount = 0
                for i in 0..<rng.int(1...30) {
                    switch rng.int(0...5) {
                    case 0: bytes += FuzzTailerTests.messy(&rng, length: rng.int(1...60)); bytes.append(0x0A)
                    case 1:
                        let line = Array(FuzzCorpus.hookLine(ts: 1_790_654_400_000 + Int64(i), ev: "PreToolUse", tool: "Bash", detail: "命令 \(i) 中文").utf8)
                        bytes += line.prefix(rng.int(1...line.count)); bytes.append(0x0A)          // 被截断的整行
                    default:
                        bytes += Array(FuzzCorpus.hookLine(ts: 1_790_654_400_000 + Int64(i), ev: "PostToolUse", tool: "Read", detail: "f\(i)").utf8)
                        bytes.append(0x0A); goodCount += 1
                    }
                }
                let path = dir.file("h\(round).events.jsonl")
                dir.write("h\(round).events.jsonl", Data(bytes))
                let one = HookLogReader(path: path)
                let r1 = one.poll()
                // 分块追加
                let path2 = dir.file("g\(round).events.jsonl")
                let inc = HookLogReader(path: path2)
                var events: [HookEvent] = []
                var pos = 0
                while pos < bytes.count {
                    let n = min(bytes.count - pos, rng.int(1...25))
                    FakeClaudeTree.appendBytes(path2, Data(bytes[pos..<(pos + n)])); pos += n
                    events += inc.poll().events
                }
                if events != r1.events { r.fail("第 \(round) 轮：分块追加和一次读完的事件不同（\(events.count) vs \(r1.events.count)）"); return }
                if r1.events.count < goodCount { r.fail("第 \(round) 轮：漏掉了好行（\(r1.events.count) < \(goodCount)）"); return }
                if one.totalEvents != r1.events.count || one.degradedLines > one.totalEvents { r.fail("计数不自洽"); return }
                if r1.events.contains(where: { $0.ev.isEmpty }) { r.fail("出现了空 ev"); return }
            }
        }
    }

    // MARK: 单行解析：截断 / 非法 UTF-8 / JSON 层面

    static let hookSamples: [(String, String)] = [
        ("ASCII", FuzzCorpus.hookLine(tool: "Bash", detail: "npm test")),
        ("中文", FuzzCorpus.hookLine(tool: "Bash", detail: "echo 中文命令和更长的一段话")),
        ("emoji", FuzzCorpus.hookLine(tool: "Read", detail: "/tmp/😀😀/a.swift")),
        ("转义", #"{"ts":1790654400123,"ev":"PreToolUse","tool":"Bash","detail":"echo 中文 \"q\" \\ \n end","extra":""}"#),
        ("长 MCP 名", FuzzCorpus.hookLine(tool: "mcp__ccd_session_mgmt__search_session_tr…", detail: "")),
        ("AskUserQuestion", FuzzCorpus.hookLine(tool: "AskUserQuestion", detail: "第一个选项的 description")),
        ("UserPromptSubmit", FuzzCorpus.hookLine(ev: "UserPromptSubmit", tool: "", detail: "", extra: "这是用户输入，绝不能留下")),
        ("Notification", FuzzCorpus.hookLine(ev: "Notification", tool: "", detail: "", extra: "Claude needs your permission to use Bash")),
    ]

    /// 检查一个解析结果的不变量；`original` 是没被截断的完整事件。返回 nil = 通过。
    static func checkHook(_ e: HookEvent, original: HookEvent?, label: String) -> String? {
        if e.ev.isEmpty { return "\(label)：ev 为空" }
        if !e.ts.timeIntervalSince1970.isFinite || TimeUtil.millis(e.ts) < 946_684_800_000 { return "\(label)：ts 不合理 \(e.ts)" }
        if e.tool.hasSuffix("…") || e.tool.hasSuffix("\u{FFFD}") { return "\(label)：tool 结尾带 …/U+FFFD：\(e.tool)" }
        if e.tool == "AskUserQuestion" && !e.detail.isEmpty { return "\(label)：AskUserQuestion 的 detail 没被清掉" }
        if e.ev == HookEvent.prompt && !e.extra.isEmpty { return "\(label)：用户输入没被清掉" }
        if let o = original {
            if e.ts != o.ts { return "\(label)：ts 变了 \(e.ts) != \(o.ts)" }
            if !o.ev.hasPrefix(e.ev) { return "\(label)：ev 不是原来的前缀 \(e.ev) / \(o.ev)" }
            if !o.tool.hasPrefix(e.tool) { return "\(label)：tool 不是原来的前缀 \(e.tool) / \(o.tool)" }
        }
        return nil
    }

    @Test("hook 行在每一个字节位置截断（含多字节字符中间、\\uXXXX 转义中间）：不崩溃，结果要么是 nil 要么和原事件前缀一致")
    func hookLineTruncatedAtEveryByte() {
        fuzzRun("hook truncation", timeout: 60) { r in
            for (name, line) in FuzzTailerTests.hookSamples {
                let bytes = Array(line.utf8)
                let original = LineSanitizer.parseHookLine(line)
                if original == nil { r.fail("样本 \(name) 自己解析不了"); continue }
                for cut in 0...bytes.count {
                    let prefix = Array(bytes[0..<cut])
                    let e = prefix.withUnsafeBufferPointer { LineSanitizer.parseHookLine($0) }
                    if let e {
                        if let msg = FuzzTailerTests.checkHook(e, original: original, label: "\(name)@\(cut)") { r.fail(msg); return }
                        if cut < bytes.count && !e.degraded { r.fail("\(name)@\(cut)：被截断的行不该走严格解析"); return }
                    } else if cut == bytes.count {
                        r.fail("\(name)：完整的行解析不出来")
                    }
                }
            }
        }
    }

    @Test("非法 UTF-8（孤立续字节 / 截断的多字节 / 0xFF / 过长编码 / 代理对）放在行首、行中、每个字段里、行尾：不崩溃、不放行坏 ts")
    func hookLineWithInvalidUTF8Everywhere() {
        fuzzRun("hook invalid utf8", timeout: 60) { r in
            let base = FuzzCorpus.hookLine(tool: "Bash", detail: "npm test", extra: "len=5")
            let bytes = Array(base.utf8)
            // 每个字段值里的一个位置（引号内部）
            let anchors: [String] = ["\"ev\":\"", "\"tool\":\"", "\"detail\":\"", "\"extra\":\""]
            for (name, bad) in FuzzCorpus.invalidUTF8 {
                var variants: [[UInt8]] = [bad + bytes, bytes + bad, bad, bad + [0x0A] + bytes]
                for a in anchors {
                    if let range = base.range(of: a) {
                        let at = base.utf8.distance(from: base.utf8.startIndex, to: range.upperBound)
                        variants.append(Array(bytes[0..<at]) + bad + Array(bytes[at...]))
                        variants.append(Array(bytes[0..<at]) + bad)                      // 字段里被截断
                    }
                }
                for (i, v) in variants.enumerated() {
                    let e = v.withUnsafeBufferPointer { LineSanitizer.parseHookLine($0) }
                    if let e, let msg = FuzzTailerTests.checkHook(e, original: nil, label: "\(name)#\(i)") { r.fail(msg); return }
                }
            }
            // 坏转义
            for esc in FuzzCorpus.badEscapes {
                for tail in ["", "\",\"extra\":\"\"}", "\"}"] {
                    let line = "{\"ts\":1790654400123,\"ev\":\"PreToolUse\",\"tool\":\"Bash\",\"detail\":\"x\(esc)\(tail)"
                    if let e = LineSanitizer.parseHookLine(line), let msg = FuzzTailerTests.checkHook(e, original: nil, label: "esc \(esc)") {
                        r.fail(msg); return
                    }
                }
            }
        }
    }

    @Test("hook 行的 JSON 层面：类型错误 / null / 重复键 / 超长键 / 深层嵌套 / 空对象空数组 / 巨大数字：不崩溃，结果满足不变量")
    func hookLineJSONLevel() {
        fuzzRun("hook json level", timeout: 60) { r in
            let longKey = String(repeating: "k", count: 1 << 20)
            let cases: [(String, String)] = [
                ("空对象", "{}"), ("空数组", "[]"), ("空串", ""), ("null", "null"), ("数字", "42"), ("字符串", "\"x\""), ("true", "true"),
                ("ts 字符串", #"{"ts":"1790654400123","ev":"Stop"}"#), ("ts null", #"{"ts":null,"ev":"Stop"}"#),
                ("ts 数组", #"{"ts":[1790654400123],"ev":"Stop"}"#), ("ts 浮点", #"{"ts":1790654400123.75,"ev":"Stop"}"#),
                ("ts 负数", #"{"ts":-1790654400123,"ev":"Stop"}"#), ("ts 超过 Int64", #"{"ts":9223372036854775808,"ev":"Stop"}"#),
                ("ts 指数", #"{"ts":1.790654400123e12,"ev":"Stop"}"#), ("ts 很多位", "{\"ts\":\(String(repeating: "9", count: 500)),\"ev\":\"Stop\"}"),
                ("ev 数字", #"{"ts":1790654400123,"ev":5}"#), ("ev null", #"{"ts":1790654400123,"ev":null}"#), ("ev 空", #"{"ts":1790654400123,"ev":""}"#),
                ("tool 数字", #"{"ts":1790654400123,"ev":"Stop","tool":7}"#), ("tool null", #"{"ts":1790654400123,"ev":"Stop","tool":null}"#),
                ("detail 对象", #"{"ts":1790654400123,"ev":"Stop","detail":{"a":[1,2,{"b":null}]}}"#),
                ("重复键", #"{"ts":1,"ts":1790654400123,"ev":"Stop","ev":"PreToolUse","tool":"A","tool":"B"}"#),
                ("超长键", "{\"\(longKey)\":1,\"ts\":1790654400123,\"ev\":\"Stop\"}"),
                ("超长值", "{\"ts\":1790654400123,\"ev\":\"Stop\",\"tool\":\"\(String(repeating: "t", count: 1 << 20))\"}"),
                ("深数组", FuzzCorpus.deepArray(100_000)), ("深对象", FuzzCorpus.deepObject(10_000)),
                ("detail 里深嵌套", "{\"ts\":1790654400123,\"ev\":\"Stop\",\"detail\":\(FuzzCorpus.deepArray(5000))}"),
                ("前导空白", "   \t {\"ts\":1790654400123,\"ev\":\"Stop\"}   "),
                ("BOM", "\u{FEFF}{\"ts\":1790654400123,\"ev\":\"Stop\"}"),
                ("NUL", "{\"ts\":1790654400123,\"ev\":\"St\u{0}op\"}"),
                ("尾部垃圾", #"{"ts":1790654400123,"ev":"Stop"} garbage"#),
                ("两个对象", #"{"ts":1790654400123,"ev":"Stop"}{"ts":1790654400124,"ev":"Stop"}"#),
            ]
            for (name, text) in cases {
                if let e = LineSanitizer.parseHookLine(text), let msg = FuzzTailerTests.checkHook(e, original: nil, label: name) { r.fail(msg) }
            }
            // 缺字段的合法行：ts / ev 都是必需的
            r.check(LineSanitizer.parseHookLine(#"{"ev":"Stop"}"#) == nil, "缺 ts 应当解析失败")
            r.check(LineSanitizer.parseHookLine(#"{"ts":1790654400123}"#) == nil, "缺 ev 应当解析失败")
            let ok = LineSanitizer.parseHookLine(#"{"ts":1790654400123,"ev":"Stop"}"#)
            r.check(ok?.tool == "" && ok?.detail == "" && ok?.extra == "", "缺 tool / detail / extra 时应为空串")
        }
    }

    @Test("随机字节（0 / 1 / 2 / 7 / 64 / 4096 / 1 MiB）当 hook 行：不崩溃、不死循环，放行的一定满足不变量")
    func hookLineRandomBytes() {
        fuzzRun("hook random bytes", timeout: 90) { r in
            var rng = FuzzRNG(seed: 0xF00D_0008)
            for n in FuzzCorpus.randomLengths {
                for _ in 0..<(n >= 4096 ? 3 : 30) {
                    let bytes = rng.bytes(n)
                    let e = bytes.withUnsafeBufferPointer { LineSanitizer.parseHookLine($0) }
                    if let e, let msg = FuzzTailerTests.checkHook(e, original: nil, label: "随机 \(n)") { r.fail(msg); return }
                }
            }
            // 半随机：好行的前半 + 随机字节 + 好行的后半
            let good = Array(FuzzCorpus.hookLine(tool: "Bash", detail: "npm test").utf8)
            for _ in 0..<400 {
                let cut = rng.int(0...good.count)
                let mutated = Array(good[0..<cut]) + rng.bytes(rng.int(0...8)) + Array(good[cut...])
                let e = mutated.withUnsafeBufferPointer { LineSanitizer.parseHookLine($0) }
                if let e, let msg = FuzzTailerTests.checkHook(e, original: nil, label: "半随机") { r.fail(msg); return }
            }
        }
    }

    @Test("任务书第 4 节的已知坑（Codex 文件 / AskUserQuestion 的 detail / tool 名被截断 / 用户输入）：变异用例")
    func hookKnownPitfallsUnderMutation() {
        // ① AskUserQuestion 无论 detail 怎么变（含被截断的转义、超长、非法字节）都不留
        var rng = FuzzRNG(seed: 0xF00D_0009)
        for _ in 0..<300 {
            let detail = rng.ascii(rng.int(0...50)) + (rng.chance(0.5) ? "\\u4e" : "") + (rng.chance(0.3) ? "中" : "")
            let line = "{\"ts\":1790654400123,\"ev\":\"PreToolUse\",\"tool\":\"AskUserQuestion\",\"detail\":\"\(detail)\",\"extra\":\"\"}"
            var bytes = Array(line.utf8)
            if rng.chance(0.4) { bytes.removeLast(rng.int(0...min(20, bytes.count - 1))) }
            if rng.chance(0.3) { bytes.insert(contentsOf: [0xE4, 0xB8], at: rng.int(0...bytes.count)) }
            if let e = bytes.withUnsafeBufferPointer({ LineSanitizer.parseHookLine($0) }), e.tool == "AskUserQuestion" {
                #expect(e.detail.isEmpty)
            }
        }
        // ② 用户输入永远不留（extra 可以是任何东西）
        for _ in 0..<200 {
            let extra = rng.ascii(rng.int(0...80))
            let e = LineSanitizer.parseHookLine("{\"ts\":1790654400123,\"ev\":\"UserPromptSubmit\",\"tool\":\"\",\"detail\":\"\",\"extra\":\"\(extra)\"}")
            #expect(e?.extra == "")
        }
        // ③ tool 名被截成 40 字符加 …：去掉 …，按前缀匹配
        let full = "mcp__ccd_session_mgmt__search_session_transcripts"
        for cut in 1...(full.count - 1) {
            let name = String(full.prefix(cut)) + "…"
            let e = LineSanitizer.parseHookLine("{\"ts\":1790654400123,\"ev\":\"PreToolUse\",\"tool\":\"\(name)\",\"detail\":\"\",\"extra\":\"\"}")
            #expect(e?.tool == String(full.prefix(cut)) && e?.toolTruncated == true)
            #expect(ToolTracker.namesMatch(e?.tool ?? "", aTruncated: true, full, bTruncated: false))
        }
        // ④ Codex 的文件名（不是登记表里的 sessionId）永远拼不出路径
        let p = Paths(home: "/h")
        for bad in ["019a1111-2222-7333-8444-555566667777/../x", "../../etc/passwd", "a b", "a/b", "a.b", "", String(repeating: "a", count: 81), "é", "a\nb"] {
            #expect(p.hookLogPath(sessionId: bad) == nil, "\(bad.debugDescription)")
        }
    }
}
