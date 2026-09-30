import Foundation
import Testing
@testable import BuddyCore

@Suite struct TranscriptTests {
    let t0 = Harness.epoch
    let sid = "bbbbbbbb-0000-4000-8000-000000000001"
    func at(_ s: Double) -> Date { Harness.at(s) }

    /// 读取器 + 它读的临时文件绑在一起（文件在读取器活着时不会被删掉）。
    final class TR {
        let file = TempFile(name: "tr")
        let reader: TranscriptReader
        init(_ lines: [[String: Any]], includeSidechain: Bool) {
            var d = Data()
            for l in lines { d.append(FakeClaudeTree.jsonLine(l)) }
            file.write(d)
            reader = TranscriptReader(path: file.path, includeSidechain: includeSidechain)
            reader.bootstrap()
        }
        var facts: TranscriptFacts { reader.facts }
        var path: String { file.path }
        var jsonErrors: Int { reader.jsonErrors }
        @discardableResult func poll() -> Bool { reader.poll() }
    }

    func reader(_ lines: [[String: Any]], includeSidechain: Bool = false) -> (TR, TR) {
        let t = TR(lines, includeSidechain: includeSidechain)
        return (t, t)
    }

    // MARK: api_error

    @Test func apiErrorIsRecordedWithRetryInfo() {
        let (r, _) = reader([
            TL.userPrompt(sessionId: sid, at: at(0)),
            TL.apiError(sessionId: sid, at: at(10), attempt: 3, max: 10, retryInMs: 2500),
        ])
        #expect(r.facts.apiError?.attempt == 3)
        #expect(r.facts.apiError?.max == 10)
        #expect(r.facts.apiError?.retryInMs == 2500)
        #expect(r.facts.apiError?.at == at(10))
        // 之后有新的 assistant 行 → lastAssistantOrUserAt 比 api_error 新
        FakeClaudeTree.appendBytes(r.path, FakeClaudeTree.jsonLine(TL.assistant(sessionId: sid, at: at(15), messageId: "m", block: TL.text(), stopReason: "end_turn")))
        r.poll()
        #expect(r.facts.lastAssistantOrUserAt == at(15))
        #expect(r.facts.apiError!.at < r.facts.lastAssistantOrUserAt!)
    }

    @Test func syntheticApiErrorAssistantIsRecognized() {
        let (r, _) = reader([
            TL.assistant(sessionId: sid, at: at(5), messageId: "syn", block: TL.text("API Error: 403"), stopReason: "stop_sequence",
                         model: "<synthetic>", apiErrorMessage: true),
        ])
        #expect(r.facts.syntheticErrorAt == at(5))
        #expect(r.facts.lastAssistantAt == at(5))
        #expect(r.facts.model == nil)                                  // 合成的行不算模型
        // "No response requested."（打断之后的合成行）不是错误
        let (r2, _) = reader([
            TL.assistant(sessionId: sid, at: at(5), messageId: "syn2", block: TL.text("No response requested."), stopReason: "stop_sequence", model: "<synthetic>"),
        ])
        #expect(r2.facts.syntheticErrorAt == nil)
    }

    // MARK: 两种打断

    @Test func userInterruptTextIsDetectedInBothShapes() {
        let (r, _) = reader([
            TL.userPrompt(sessionId: sid, at: at(0)),
            TL.userInterrupt(sessionId: sid, at: at(5)),
        ])
        #expect(r.facts.interruptAt == at(5))
        let (r2, _) = reader([TL.userInterrupt(sessionId: sid, at: at(7), forToolUse: true)])   // "… for tool use]"
        #expect(r2.facts.interruptAt == at(7))
        // 内容是字符串（不是数组）的形式
        let plain: [String: Any] = ["type": "user", "timestamp": TL.iso(at(9)), "sessionId": sid,
                                    "message": ["role": "user", "content": "[Request interrupted by user]"]]
        let (r3, _) = reader([plain])
        #expect(r3.facts.interruptAt == at(9))
        #expect(r3.facts.lastPromptAt == nil)                          // 打断行不算"用户的一次输入"
    }

    @Test func abortedMidStreamAssistantIsAnInterrupt() {
        let (r, _) = reader([
            TL.assistant(sessionId: sid, at: at(3), messageId: "m", block: TL.text("half a sentence"), stopReason: nil, aborted: true),
        ])
        #expect(r.facts.interruptAt == at(3))
        // stop_reason 为 null 但没有 isAbortedMidStream（子代理实时写的中间行）：不算打断
        let (r2, _) = reader([TL.assistant(sessionId: sid, at: at(3), messageId: "m", block: TL.text("x"), stopReason: nil)])
        #expect(r2.facts.interruptAt == nil)
    }

    // MARK: 一轮结束 / 其他系统行

    @Test func stopHookSummaryEndTurnAndTurnDuration() {
        let (r, _) = reader([
            TL.userPrompt(sessionId: sid, at: at(0)),
            TL.assistant(sessionId: sid, at: at(4), messageId: "m", block: TL.text("done"), stopReason: "end_turn"),
            TL.stopHookSummary(sessionId: sid, at: at(4.05)),
            TL.system(sessionId: sid, at: at(4.06), subtype: "turn_duration", extra: ["durationMs": 4012, "messageCount": 3]),
            TL.system(sessionId: sid, at: at(4.07), subtype: "compact_boundary"),
        ])
        #expect(r.facts.stopHookSummaryAt == at(4.05))
        #expect(r.facts.endTurnAt == at(4))
        #expect(r.facts.turnDurationMs == 4012)
        #expect(r.facts.compactBoundaryAt == at(4.07))
        #expect(r.facts.lastPromptAt == at(0))
    }

    @Test func toolUseIsOpenUntilItsResultArrives() {
        let (r, f) = reader([
            TL.assistant(sessionId: sid, at: at(1), messageId: "m", block: TL.toolUse(id: "t1", name: "Bash", input: ["command": "npm test"])),
            TL.assistant(sessionId: sid, at: at(1.1), messageId: "m", block: TL.toolUse(id: "t2", name: "Read", input: ["file_path": "/x"])),
        ])
        #expect(r.facts.openToolUses.map { $0.id } == ["t1", "t2"])
        #expect(r.facts.openToolUses.first?.key == "npm test")
        FakeClaudeTree.appendBytes(f.path, FakeClaudeTree.jsonLine(TL.userToolResult(sessionId: sid, at: at(2), toolUseId: "t1")))
        r.poll()
        #expect(r.facts.openToolUses.map { $0.id } == ["t2"])
        #expect(r.facts.recentToolUses.count == 2)
    }

    @Test func promptsAreRecordedButNeverTheirText() {
        let (r, _) = reader([TL.userPrompt(sessionId: sid, at: at(3), text: "这是用户的输入，绝不能保留")])
        #expect(r.facts.lastPromptAt == at(3))
        let dump = String(describing: r.facts)
        #expect(!dump.contains("绝不能保留"))
    }

    @Test func metaUserLinesAreSkipped() {
        var meta = TL.userPrompt(sessionId: sid, at: at(3))
        meta["isMeta"] = true
        let (r, _) = reader([meta])
        #expect(r.facts.lastPromptAt == nil)
        #expect(r.facts.lastUserAt == nil)
    }

    @Test func sidechainLinesBelongToOthersInTheMainFile() {
        var side = TL.assistant(sessionId: sid, at: at(5), messageId: "sm", block: TL.toolUse(id: "st", name: "Bash", input: ["command": "x"]), agentId: "ag1")
        side["isSidechain"] = true
        let (r, _) = reader([side])
        #expect(r.facts.openToolUses.isEmpty)
        // 子代理自己的文件要包含这些行
        let (r2, _) = reader([side], includeSidechain: true)
        #expect(r2.facts.openToolUses.map { $0.id } == ["st"])
    }

    @Test func titlesAndModelAndContext() {
        let (r, _) = reader([
            TL.customTitle(sessionId: sid, "自定义标题"),
            ["type": "ai-title", "aiTitle": "AI 起的标题", "sessionId": sid],
            ["type": "permission-mode", "permissionMode": "acceptEdits", "sessionId": sid],
            TL.assistant(sessionId: sid, at: at(1), messageId: "m", block: TL.text(), stopReason: "end_turn", model: "glm-5.3",
                         usage: TL.usage(input: 100, output: 50, cacheWrite: 1000, cacheRead: 20000)),
        ])
        #expect(r.facts.customTitle == "自定义标题")
        #expect(r.facts.aiTitle == "AI 起的标题")
        #expect(r.facts.permissionMode == "acceptEdits")
        #expect(r.facts.model == "glm-5.3")
        #expect(r.facts.contextTokens == 100 + 1000 + 20000)             // 输入 + 缓存写 + 缓存读（不含输出）
    }

    @Test func bootstrapReadsOnlyTheTailWindowOfABigFile() {
        var lines: [[String: Any]] = []
        for i in 0..<2000 { lines.append(TL.userPrompt(sessionId: sid, at: at(Double(i)), text: String(repeating: "p", count: 200))) }
        lines.append(TL.customTitle(sessionId: sid, "尾部的标题"))
        let f = TempFile(name: "big")
        var d = Data()
        for l in lines { d.append(FakeClaudeTree.jsonLine(l)) }
        f.write(d)
        #expect(d.count > 400_000)
        let r = TranscriptReader(path: f.path)
        r.bootstrap(tailWindow: 8 << 10)
        #expect(r.facts.linesSeen < 100)                                  // 只读了尾部窗口，不是整个文件
        #expect(r.facts.customTitle == "尾部的标题")
        #expect(r.facts.lastPromptAt == at(1999))
    }

    @Test func rewrittenFileDropsStaleFacts() {
        let f = TempFile(name: "rw")
        f.write(FakeClaudeTree.jsonLine(TL.customTitle(sessionId: sid, "旧标题")) + FakeClaudeTree.jsonLine(TL.userPrompt(sessionId: sid, at: at(1))))
        let r = TranscriptReader(path: f.path)
        r.bootstrap()
        #expect(r.facts.customTitle == "旧标题")
        f.replaceWithNewInode(String(decoding: FakeClaudeTree.jsonLine(TL.userInterrupt(sessionId: sid, at: at(9))), as: UTF8.self))
        r.poll()
        #expect(r.facts.customTitle == nil)
        #expect(r.facts.interruptAt == at(9))
    }

    @Test func badJsonLinesAreCountedButDoNotBreakAnything() {
        let f = TempFile(name: "bad")
        var d = Data("not json\n".utf8)
        d += FakeClaudeTree.jsonLine(TL.userPrompt(sessionId: sid, at: at(1)))
        d += Data("{\"type\":\"assistant\",\"message\":{\"content\":\n".utf8)      // 写了一半的行（但有换行）
        d += FakeClaudeTree.jsonLine(TL.customTitle(sessionId: sid, "还是读到了"))
        f.write(d)
        let r = TranscriptReader(path: f.path)
        r.bootstrap()
        #expect(r.jsonErrors == 2)
        #expect(r.facts.customTitle == "还是读到了")
    }

    @Test func locatorFindsTheFileByGlobbingProjectDirectories() {
        let h = Harness()
        let sid = "cccccccc-0000-4000-8000-000000000009"
        let other = h.tree.paths.projectsDir + "/-Users-someone-else"
        try? FileManager.default.createDirectory(atPath: other, withIntermediateDirectories: true)
        FakeClaudeTree.appendBytes(other + "/\(sid).jsonl", Data("{}\n".utf8))
        #expect(TranscriptLocator.find(sessionId: sid, projectsDir: h.tree.paths.projectsDir) == other + "/\(sid).jsonl")
        #expect(TranscriptLocator.find(sessionId: "nope-0000", projectsDir: h.tree.paths.projectsDir) == nil)
        #expect(TranscriptLocator.find(sessionId: "../x", projectsDir: h.tree.paths.projectsDir) == nil)
        #expect(TranscriptLocator.sessionDir(forTranscript: other + "/\(sid).jsonl") == other + "/\(sid)")
    }
}
