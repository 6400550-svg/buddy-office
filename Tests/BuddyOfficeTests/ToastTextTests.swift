import Testing
import Foundation
import BuddyCore
import BuddyStage
import PixelKit
@testable import BuddyOffice

/// 提示卡（系统通知被拒时的兜底）单行最宽 220 pt，放不下会被省略号截断（看图 [O]：深链停用那条显示成「…直接打开 Clau…」）。
/// JumpService / AlertCoordinator 发出的提示文案必须在这个宽度下放得下。量法：用 ToastCard 自己产出的文字项（样式和最大宽度都取它的，不重复常数）+ TextRenderer 出图，看 truncated。
@Suite struct ToastTextTests {
    /// 这张卡里被省略号截断的文字（没有 = 全部放得下）。
    static func truncated(title: String, body: String, zoom: Int = 2) -> [String] {
        let card = ToastCard.make(kind: .info, title: title, body: body, zoom: zoom)
        return card.texts.compactMap { item in
            guard let img = TextRenderer.shared.image(item.text, style: item.style, scale: 2, maxWidth: item.maxWidth) else { return item.text }
            return img.truncated ? item.text : nil
        }
    }

    /// 证明测得出来：旧的深链停用文案确实被截断了；新的放得下。
    @Test func theOldDeepLinkNoticeWasTruncatedAndTheNewOneFits() {
        let old = "深链跳转没有生效，已改为直接打开 Claude。（可在设置 → 数据源诊断里重新测试）"
        #expect(Self.truncated(title: "Buddy 办公室", body: old) == [old], "旧文案在 220 pt 里放不下")
        let n = JumpService.deepLinkDisabledNotice
        #expect(Self.truncated(title: n.title, body: n.body).isEmpty, "\(n.title) / \(n.body)")
    }

    @Test func everyFixedAlertTextFits() {
        var bodies = ["有个问题要问你", "计划好了，等你看", "在等你", "有个权限请求（等你批准）", "需要你处理", "出错了", "做完了（用时 59秒）", "做完了（用时 59分59秒）",
                      "做完了（用时 100小时59分）", "做完了（用时 3分12秒）"]
        for n in [2, 3, 9, 10, 99] { bodies += ["\(n) 位同事在等你", "\(n) 位同事做完了", "\(n) 位同事有事找你"] }
        for b in bodies { #expect(Self.truncated(title: "Buddy 办公室", body: b).isEmpty, "\(b)") }
        for t in ["会话", "Buddy 办公室"] { #expect(Self.truncated(title: t, body: "在等你").isEmpty, "\(t)") }
    }

    /// 「想用 X：命令（等你批准）」里工具名和命令是数据里来的，可以很长：放不下就依次去掉命令 / 截短，永远不被省略号截断。
    @Test func approvalBodiesFitNoMatterHowLongTheToolOrTheCommandIs() {
        let cases: [(String, String)] = [
            ("Bash", "git push"), ("Bash", "npm test"), ("Bash", "/usr/local/bin/some-very-long-command-name-here --flag value"),
            ("Bash", "averyveryveryveryverylongsinglewordcommandwithnospaces"), ("Bash", "python3 -m pytest tests/integration"),
            ("Edit", "/a/b/c.swift"), ("WebSearch", "swift"), ("NotebookEdit", "x"), ("SomeVeryLongUnknownToolNameThatKeepsGoingForever", "x"),
            ("mcp__scheduled-tasks__create_scheduled_task", "x"), ("mcp__claude-in-chrome__navigate", "x"), ("mcp__" + String(repeating: "s", count: 50) + "__tool", "x"),
            ("Bash", "中文命令名很长很长很长很长很长很长很长很长很长很长"),
        ]
        for (tool, cmd) in cases {
            let s = Fx.snap("t:a", activity: .waitingApproval(tool: Fx.call(tool, cmd)))
            let (_, body) = AlertCoordinator.text(for: s, att: .approval, privacy: false)
            #expect(Self.truncated(title: "会话", body: body).isEmpty, "\(tool) / \(cmd) → \(body)")
            #expect(body.hasPrefix("想用 ") || body == "有个权限请求（等你批准）", "\(body)")
            #expect(body.hasSuffix("（等你批准）"), "\(body)")
        }
    }

    /// 放得下的照旧（不能因为加了「放不下就缩」把正常文案也改了）。
    @Test func approvalWordingThatAlreadyFitsIsUnchanged() {
        func body(_ tool: String, _ cmd: String) -> String {
            AlertCoordinator.text(for: Fx.snap("t:a", activity: .waitingApproval(tool: Fx.call(tool, cmd))), att: .approval, privacy: false).1
        }
        #expect(body("Bash", "git push") == "想用 Bash：git push（等你批准）")
        #expect(body("Bash", "cd ~/app && npm test -- --watch") == "想用 Bash：npm test（等你批准）")
        #expect(body("Edit", "/a/b.swift") == "想用 Edit（等你批准）")
        #expect(body("WebSearch", "x") == "想用 WebSearch（等你批准）")
    }

    /// 纯函数：fits 注入，验证缩短的顺序。
    @Test func shorteningOrderIsCommandThenToolThenGeneric() {
        let full = AlertText.approvalBody(tool: "Bash", command: "git push --force-with-lease origin main", fits: { _ in true })
        #expect(full == "想用 Bash：git push --force-with-lease origin main（等你批准）")
        let short = AlertText.approvalBody(tool: "Bash", command: "git push --force-with-lease origin main", fits: { $0.count <= 20 })
        #expect(short.hasPrefix("想用 Bash：") && short.contains("…") && short.count <= 20, "\(short)")
        let noCmd = AlertText.approvalBody(tool: "Bash", command: "git push --force-with-lease origin main", fits: { $0 == "想用 Bash（等你批准）" })
        #expect(noCmd == "想用 Bash（等你批准）")
        let cutTool = AlertText.approvalBody(tool: "VeryLongToolName", command: "", fits: { $0.count <= 15 })
        #expect(cutTool.hasPrefix("想用 Very") && cutTool.contains("…（等你批准）"), "\(cutTool)")
        #expect(AlertText.approvalBody(tool: "VeryLongToolName", command: "x", fits: { _ in false }) == "有个权限请求（等你批准）", "什么都放不下：退到最短的通用文案")
    }
}
