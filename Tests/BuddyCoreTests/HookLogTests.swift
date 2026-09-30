import Foundation
import Testing
@testable import BuddyCore

@Suite struct HookLogTests {
    private func parse(_ bytes: [UInt8]) -> HookEvent? {
        bytes.withUnsafeBufferPointer { LineSanitizer.parseHookLine($0) }
    }
    private func parse(_ s: String) -> HookEvent? { parse(Array(s.utf8)) }

    @Test func normalLine() {
        let e = parse(#"{"ts":1790654602874,"ev":"PreToolUse","tool":"Read","detail":"/tmp/a.swift","extra":""}"#)
        #expect(e?.ev == "PreToolUse")
        #expect(e?.tool == "Read")
        #expect(e?.detail == "/tmp/a.swift")
        #expect(e?.degraded == false)
        #expect(e?.ts == Date(timeIntervalSince1970: 1790654602.874))
    }

    @Test func invalidUTF8IsCleanedNotFatal() {
        // "…/中" 的第三个字节被截掉（E4 B8 后面缺 AD），这是真实日志里超过一半文件都有的情况
        var bytes = Array(#"{"ts":1790654602874,"ev":"PreToolUse","tool":"Bash","detail":"echo /tmp/"#.utf8)
        bytes += [0xE4, 0xB8]
        bytes += Array(#"…","extra":""}"#.utf8)
        let e = parse(bytes)
        #expect(e != nil)
        #expect(e?.degraded == false)                       // 清洗之后 JSON 还是合法的
        #expect(e?.detail.contains("\u{FFFD}") == true)
        #expect(e?.tool == "Bash")
    }

    @Test func truncatedUnicodeEscapeFallsBackToRegexFields() {
        // hook 把 \uXXXX 从中间截断了：JSON 不合法，只能抠 ts / ev / tool
        let line = #"{"ts":1790654602874,"ev":"PostToolUse","tool":"Bash","detail":"echo \u4e…","extra":"len=5"}"#
        let e = parse(line)
        #expect(e != nil)
        #expect(e?.degraded == true)
        #expect(e?.ev == "PostToolUse")
        #expect(e?.tool == "Bash")
        #expect(e?.ts == Date(timeIntervalSince1970: 1790654602.874))
        #expect(e?.detail == "")

        // 只剩 "\u4" 的更短截断
        let e2 = parse(#"{"ts":1790654602999,"ev":"PreToolUse","tool":"Read","detail":"a\u4…","extra":""}"#)
        #expect(e2?.degraded == true)
        #expect(e2?.tool == "Read")
    }

    @Test func truncatedMcpToolNameKeepsPrefixAndMatchesByPrefix() {
        let raw = "mcp__ccd_session_mgmt__search_session_tr…"          // 40 字符 + …
        let e = parse(#"{"ts":1790654602874,"ev":"PreToolUse","tool":"\#(raw)","detail":"","extra":""}"#)
        #expect(e?.tool == "mcp__ccd_session_mgmt__search_session_tr")
        #expect(e?.toolTruncated == true)
        #expect(ToolCatalog.category(of: e!.tool) == .mcp)
        #expect(ToolCatalog.mcpServer(of: e!.tool) == "ccd_session_mgmt")
        // 完整名字（会话记录里的）按前缀能对上
        #expect(ToolTracker.namesMatch(e!.tool, aTruncated: true, "mcp__ccd_session_mgmt__search_session_transcripts", bTruncated: false))
        #expect(!ToolTracker.namesMatch(e!.tool, aTruncated: true, "mcp__ccd_session_mgmt__get_session", bTruncated: false))
    }

    @Test func garbageLinesAreSkippedWithoutFailingTheWholeFile() throws {
        let f = TempFile(name: "hook")
        var data = Data()
        data += Data(#"{"ts":1790654600000,"ev":"SessionStart","tool":"","detail":"","extra":"startup"}"#.utf8) + Data([10])
        data += Data("this is not json at all".utf8) + Data([10])
        data += Data(#"{"ev":"Stop"}"#.utf8) + Data([10])                       // 缺 ts
        data += Data([0xFF, 0xFE, 0xFD, 10])
        data += Data(#"{"ts":1790654601000,"ev":"Stop","tool":"","detail":"","extra":""}"#.utf8) + Data([10])
        f.write(data)
        let r = HookLogReader(path: f.path)
        let res = r.poll()
        #expect(res.events.map { $0.ev } == ["SessionStart", "Stop"])
        #expect(r.skippedLines == 3)
    }

    @Test func askUserQuestionDetailIsNeverKept() {
        let e = parse(#"{"ts":1790654602874,"ev":"PreToolUse","tool":"AskUserQuestion","detail":"第一个选项的 description，不是问题","extra":""}"#)
        #expect(e?.detail == "")
        // 降级解析也不会带出 detail
        let d = parse(#"{"ts":1790654602874,"ev":"PreToolUse","tool":"AskUserQuestion","detail":"x\u4…","extra":""}"#)
        #expect(d?.detail == "")
        // Tracker 层再保一道保险
        var t = ToolTracker()
        t.pre(name: "AskUserQuestion", detail: "某个 description", at: Harness.epoch, owner: .main)
        #expect(t.mainOpen.first?.call.detail == "")
    }

    @Test func userPromptIsDroppedAtParseTime() {
        let e = parse(#"{"ts":1790654602874,"ev":"UserPromptSubmit","tool":"","detail":"","extra":"这是用户的输入，绝不能显示出来"}"#)
        #expect(e?.ev == "UserPromptSubmit")
        #expect(e?.extra == "")
    }

    @Test func notificationTextIsKept() {
        let e = parse(#"{"ts":1790654602874,"ev":"Notification","tool":"","detail":"","extra":"Claude needs your permission to use Bash"}"#)
        #expect(e?.extra == "Claude needs your permission to use Bash")
        #expect(ActivityResolver.toolName(fromNotification: e!.extra) == "Bash")
    }

    @Test func unsafeSessionIdsNeverBecomePaths() {
        let p = Paths(home: "/tmp/x")
        #expect(p.hookLogPath(sessionId: "../../etc/passwd") == nil)
        #expect(p.hookLogPath(sessionId: "a/b") == nil)
        #expect(p.hookLogPath(sessionId: "") == nil)
        #expect(p.hookLogPath(sessionId: "20c4bcc8-f611-4701-b1d3-f910aaa5248d") == "/tmp/x/.claude/.monitor/20c4bcc8-f611-4701-b1d3-f910aaa5248d.events.jsonl")
    }

    @Test func toolDetailKeyFollowsTheHookRules() {
        #expect(ToolDetail.key(name: "Bash", input: ["command": "npm test", "description": "run"]) == "npm test")
        #expect(ToolDetail.key(name: "Read", input: ["file_path": "/a/b"]) == "/a/b")
        #expect(ToolDetail.key(name: "Grep", input: ["pattern": "TODO", "path": "."]) == "TODO")
        #expect(ToolDetail.key(name: "WebFetch", input: ["url": "https://x.y"]) == "https://x.y")
        #expect(ToolDetail.key(name: "WebSearch", input: ["query": "swift"]) == "swift")
        #expect(ToolDetail.key(name: "Agent", input: ["description": "研究", "prompt": "…"]) == "研究")
        #expect(ToolDetail.key(name: "Skill", input: ["skill": "pdf"]) == "pdf")
        #expect(ToolDetail.key(name: "mcp__x__y", input: ["description": "d"]) == "d")
        #expect(ToolDetail.key(name: "MultiEdit", input: ["file_path": "/a"]) == "")        // 永远是空的
        #expect(ToolDetail.key(name: "Bash", input: ["command": String(repeating: "a", count: 300)]).count == 160)
        #expect(ToolDetail.matches(hookDetail: "npm te…", transcriptKey: "npm test"))
        #expect(!ToolDetail.matches(hookDetail: "ls", transcriptKey: "npm test"))
        #expect(ToolDetail.matches(hookDetail: "", transcriptKey: ""))
        #expect(!ToolDetail.matches(hookDetail: "", transcriptKey: "x"))
    }
}
