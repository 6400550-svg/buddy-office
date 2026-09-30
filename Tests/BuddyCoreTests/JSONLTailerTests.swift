import Foundation
import Testing
@testable import BuddyCore

/// 临时文件小工具。
final class TempFile {
    let path: String
    init(name: String = "tail") {
        path = FileIO.temporaryDirectory + "buddy-\(name)-" + UUID().uuidString + ".jsonl"
    }
    deinit { try? FileManager.default.removeItem(atPath: path) }
    func write(_ s: String) { FakeClaudeTree.writeInPlace(path, Data(s.utf8)) }
    func write(_ d: Data) { FakeClaudeTree.writeInPlace(path, d) }
    func append(_ s: String) { FakeClaudeTree.appendBytes(path, Data(s.utf8)) }
    func append(_ d: Data) { FakeClaudeTree.appendBytes(path, d) }
    func truncate(to n: Int) { Darwin.truncate(path, off_t(n)) }
    func replaceWithNewInode(_ s: String) {
        try? FileManager.default.removeItem(atPath: path)
        FakeClaudeTree.writeInPlace(path, Data(s.utf8))
    }
}

func collect(_ t: JSONLTailer) -> (lines: [String], result: JSONLTailer.PollResult) {
    var out: [String] = []
    let r = t.poll { out.append(String(decoding: $0, as: UTF8.self)) }
    return (out, r)
}

@Suite struct JSONLTailerTests {
    @Test func halfLineIsHeldUntilCompleted() {
        let f = TempFile()
        f.write("abc\ndef")
        let t = JSONLTailer(path: f.path)
        #expect(collect(t).lines == ["abc"])
        #expect(t.committedOffset == 4)            // 半行 "def" 还没算读完
        f.append("gh\nlast")
        #expect(collect(t).lines == ["defgh"])
        f.append("\n")
        #expect(collect(t).lines == ["last"])
        #expect(collect(t).lines == [])
    }

    @Test func truncationRestartsFromZero() {
        let f = TempFile()
        f.write("one\ntwo\nthree\n")
        let t = JSONLTailer(path: f.path)
        #expect(collect(t).lines == ["one", "two", "three"])
        f.write("new\n")                            // 原地截断重写，变短了
        let r = collect(t)
        #expect(r.lines == ["new"])
        #expect(r.result.reset)
        #expect(t.resetCount == 1)
    }

    @Test func rotationToNewInodeRestartsFromZero() {
        let f = TempFile()
        f.write("aaaaaaaaaa\nbbbbbbbbbb\n")
        let t = JSONLTailer(path: f.path)
        _ = collect(t)
        f.replaceWithNewInode("x\ny\nz\nw\nvvvvvvvvvvvvvvvvvvvv\n")     // 比原来长，但 inode 变了
        let r = collect(t)
        #expect(r.lines == ["x", "y", "z", "w", "vvvvvvvvvvvvvvvvvvvv"])
        #expect(r.result.reset)
    }

    @Test func missingFileThenAppears() {
        let f = TempFile()
        let t = JSONLTailer(path: f.path)
        let r0 = collect(t)
        #expect(r0.result.missing)
        #expect(r0.lines.isEmpty)
        f.write("hello\n")
        #expect(collect(t).lines == ["hello"])
    }

    @Test func oversizeLineIsDroppedAndTheNextLineSurvives() {
        let f = TempFile()
        let big = String(repeating: "x", count: 5 << 20)       // 5 MiB > 4 MiB 上限
        f.write("A\n" + big + "\nB\n")
        let t = JSONLTailer(path: f.path)
        let r = collect(t)
        #expect(r.lines == ["A", "B"])
        #expect(t.droppedOversizeLines == 1)
    }

    @Test func oversizeLineSplitAcrossPollsIsSkippedUntilNewline() {
        let f = TempFile()
        f.write("A\n")
        let t = JSONLTailer(path: f.path)
        #expect(collect(t).lines == ["A"])
        // 超长行分两次写进来：第一次没有换行
        f.append(String(repeating: "y", count: 5 << 20))
        #expect(collect(t).lines == [])
        f.append(String(repeating: "y", count: 1000) + "\nC\nD")
        #expect(collect(t).lines == ["C"])                          // 超长行被整个丢掉，C 完好
        f.append("\n")
        #expect(collect(t).lines == ["D"])
    }

    @Test func exactlyAtTheLimitIsKept() {
        let f = TempFile()
        let ok = String(repeating: "z", count: 4 << 20)              // 恰好 4 MiB：不算超长
        f.write(ok + "\nE\n")
        let t = JSONLTailer(path: f.path)
        let r = collect(t)
        #expect(r.lines.count == 2)
        #expect(r.lines.first?.count == 4 << 20)
        #expect(t.droppedOversizeLines == 0)
    }

    @Test func linesStraddlingChunkBoundaries() {
        // 用很小的块（64 字节），让几乎每一行都跨块
        var expected: [String] = []
        var s = ""
        for i in 0..<400 {
            let line = "line-\(i)-" + String(repeating: Character(UnicodeScalar(UInt8(97 + i % 26))), count: (i * 7) % 150)
            expected.append(line); s += line + "\n"
        }
        let f = TempFile()
        f.write(s)
        let t = JSONLTailer(path: f.path, config: .init(maxLineBytes: 4 << 20, chunkBytes: 64))
        #expect(collect(t).lines == expected)
    }

    @Test func crlfAndEmptyLines() {
        let f = TempFile()
        f.write("a\r\n\r\n\nb\r\n")
        let t = JSONLTailer(path: f.path)
        #expect(collect(t).lines == ["a", "b"])
    }

    @Test func multiByteCharactersAcrossChunks() {
        let text = String(repeating: "中文测试🙂", count: 200)
        let f = TempFile()
        f.write(text + "\n" + text + "\n")
        let t = JSONLTailer(path: f.path, config: .init(maxLineBytes: 4 << 20, chunkBytes: 7))
        #expect(collect(t).lines == [text, text])
    }

    @Test func seekToTailAlignsToLineStart() {
        var lines: [String] = []
        for i in 0..<100 { lines.append("this is line number \(i) of the file") }
        let f = TempFile()
        f.write(lines.joined(separator: "\n") + "\n")
        let t = JSONLTailer(path: f.path)
        t.seekToTail(window: 300)
        let got = collect(t).lines
        #expect(!got.isEmpty)
        #expect(got.last == lines.last)
        // 每一行都必须是完整的原始行（起点落在半行里时，那半行被跳过）
        for l in got { #expect(lines.contains(l)) }
        #expect(got.count < 100)
    }

    @Test func seekToTailWhenStartIsExactlyALineStartKeepsThatLine() {
        let f = TempFile()
        f.write("aaaa\nbbbb\ncccc\n")         // 15 字节；窗口 10 → 起点 5 = "bbbb" 的行首
        let t = JSONLTailer(path: f.path)
        t.seekToTail(window: 10)
        #expect(collect(t).lines == ["bbbb", "cccc"])
    }

    @Test func resumeFromCommittedOffset() {
        let f = TempFile()
        f.write("1\n2\n3")
        let t1 = JSONLTailer(path: f.path)
        _ = collect(t1)
        let saved = (t1.committedOffset, t1.fileID)
        f.append("\n4\n")
        let t2 = JSONLTailer(path: f.path)
        t2.seek(to: saved.0, fileID: saved.1)
        #expect(collect(t2).lines == ["3", "4"])
    }
}
