import Foundation
import Testing
@testable import BuddyCore

/// 引擎的基本时间线：进场 → 思考 → 工具 → 等批准 → 做完 → 空闲 → 打盹 → 睡着。
@Suite struct EngineBasicTests {
    @Test func arrivalThenBusyThenTool() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        // 会话记录里先有一条自定义标题
        h.tree.writeRegistry(f.session, status: "idle")
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.poll()
        let s = h.only()
        #expect(s != nil)
        #expect(s?.key == DesktopFixture.key)
        #expect(s?.presence == .present)
        #expect(s?.appearedAfterLaunch == false)      // App 启动时就在
        expectActivity(s, .idle)                        // 刚进场的会话不能显示"做完了"
        #expect(s?.title == "测试会话")
        #expect(s?.origin == .desktop)

        // 一轮开始：登记表 busy，hook 有 UserPromptSubmit
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit", extra: "绝不能显示出来的用户输入")
        h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)
        #expect(h.kinds(DesktopFixture.key).contains(.turnStarted))

        // 读一个文件
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/tmp/a.swift")
        h.poll()
        guard case .tool(let call, let parallel)? = h.snap(DesktopFixture.key)?.activity else {
            Issue.record("应该是 .tool，实际 \(String(describing: h.snap(DesktopFixture.key)?.activity))"); return
        }
        #expect(call.name == "Read")
        #expect(call.category == .read)
        #expect(call.detail == "/tmp/a.swift")
        #expect(parallel == 1)

        h.advance(0.5)
        h.tree.hook(f.sid, "PostToolUse", tool: "Read", detail: "/tmp/a.swift", extra: "len=100")
        h.poll()
        expectActivity(h.snap(DesktopFixture.key), .thinking)
    }
}
