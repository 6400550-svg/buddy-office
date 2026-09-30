import Foundation
import BuddyCore

/// 压力测试用的假会话（text-audit、测试、`buddyctl snapshot --mode audit…` 共用）：各种标题、各种状态、各种数字。
public enum AuditFixtures {
    public enum TitleMode: String, CaseIterable, Sendable {
        case normal            // 短的中文标题
        case longZh            // 40 字长中文
        case longEn            // 没有空格的长英文
        case emoji             // emoji 混排（含带零宽连接符的组合 emoji）
        case empty             // 空标题
        case mixed             // 上面几种轮流
    }
    public enum StateMode: String, CaseIterable, Sendable {
        case demo              // 演示剧本第 41 秒那几个人（复制到需要的个数）
        case all               // 每个座位一种状态：把所有状态同时摆出来
    }

    public static let longZh = "重构登录模块并且补全所有单元测试再顺便把文档也一起更新到最新版本以免后面忘记检查"
    public static let longEn = "AuthenticationMiddlewareRefactoringForOAuth2PKCEFlowWithoutAnySpacesAtAll_v2_final"
    public static let emoji = "🚀发布🎉v2.0✨上线🔥Ship it 👨‍💻部署🇨🇳完成"
    static let shortTitles = ["重构登录模块", "论文引用检查", "健身计划 app", "DeepSeek 试验", "打盹的会话", "新来的同事"]

    public static func title(_ mode: TitleMode, index i: Int) -> String {
        switch mode {
        case .normal: return shortTitles[i % shortTitles.count]
        case .longZh: return longZh
        case .longEn: return longEn
        case .emoji: return emoji
        case .empty: return ""
        case .mixed: return [longZh, longEn, emoji, "", shortTitles[i % shortTitles.count]][i % 5]
        }
    }

    typealias StateFn = (inout BuddySnapshot, Date) -> Void
    static func tool(_ name: String, _ detail: String, par: Int = 1, since: Double = 0) -> StateFn {
        { s, d in
            let start = d.addingTimeInterval(-since)
            s.activity = .tool(ToolCatalog.makeCall(name: name, detail: detail, at: start), parallel: par)
            s.activitySince = start
        }
    }
    static func helpers(_ n: Int, fg: Bool = true) -> [HelperSnapshot] {
        (0..<n).map { HelperSnapshot(id: "h\($0)", description: "并行任务 \($0 + 1)", foreground: fg, active: true) }
    }

    /// 所有状态（每一种至少一次）。名字用来报告。
    static let states: [(String, StateFn)] = [
        ("思考", { s, _ in s.activity = .thinking }),
        ("思考很久", { s, d in s.activity = .thinking; s.activitySince = d.addingTimeInterval(-40) }),
        ("Read 长路径", tool("Read", "/Users/demo/app/Sources/Authentication/Middleware/OAuth2PKCEFlowController+Extensions.swift")),
        ("Edit", tool("Edit", "/Users/demo/app/src/auth/LoginView.swift")),
        ("Write", tool("Write", "/Users/demo/app/src/auth/Session.swift")),
        ("Bash 短", tool("Bash", "git status")),
        ("Bash 很久", tool("Bash", "cd ~/app && npm test -- --watch --coverage --reporters=default --maxWorkers=4", since: 45)),
        ("Grep ×3", tool("Grep", "TODO", par: 3)),
        ("Glob", tool("Glob", "**/*.swift")),
        ("WebFetch", tool("WebFetch", "https://www.example-with-a-very-long-domain-name.co.uk/articles/some/path")),
        ("WebSearch 长", tool("WebSearch", "hydrogen embrittlement of high strength steels under cyclic loading review")),
        ("Agent + 3 帮手", { s, d in tool("Agent", "调研三篇文献")(&s, d); s.helpers = helpers(3) }),
        ("Agent + 5 帮手", { s, d in tool("Agent", "并行任务")(&s, d); s.helpers = helpers(5) }),
        ("Agent 后台", { s, d in tool("Agent", "后台整理")(&s, d); s.helpers = helpers(1, fg: false) }),
        ("TodoWrite", tool("TodoWrite", "")),
        ("Skill", tool("Skill", "brainstorming")),
        ("ToolSearch", tool("ToolSearch", "select:Read")),
        ("EnterPlanMode", tool("EnterPlanMode", "")),
        ("SendUserFile", tool("SendUserFile", "/tmp/plan.md")),
        ("ScheduleWakeup", tool("ScheduleWakeup", "")),
        ("Monitor", tool("Monitor", "tail -f /var/log/system.log")),
        ("MCP 浏览器", tool("mcp__Claude_Browser__navigate", "")),
        ("MCP 电脑", tool("mcp__computer-use__app_click", "")),
        ("MCP 其他", tool("mcp__notion__search_pages", "")),
        ("未知工具（长名字）", tool("SomeVeryLongUnknownToolNameThatKeepsGoing", "")),
        ("等批准 Bash", { s, d in s.activity = .waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push origin main --force-with-lease", at: d.addingTimeInterval(-9))); s.activitySince = d.addingTimeInterval(-9) }),
        ("等批准 Edit", { s, d in s.activity = .waitingApproval(tool: ToolCatalog.makeCall(name: "Edit", detail: "/a/b.swift", at: d.addingTimeInterval(-130))); s.activitySince = d.addingTimeInterval(-130) }),
        ("等批准 MCP", { s, d in s.activity = .waitingApproval(tool: ToolCatalog.makeCall(name: "mcp__slack__post_message", detail: "", at: d.addingTimeInterval(-400))); s.activitySince = d.addingTimeInterval(-400) }),
        ("提问", { s, d in s.activity = .asking; s.activitySince = d.addingTimeInterval(-20) }),
        ("计划待审", { s, d in s.activity = .planReview; s.activitySince = d.addingTimeInterval(-70) }),
        ("其他等待", { s, d in s.activity = .waitingOther("goal proposal"); s.activitySince = d.addingTimeInterval(-3) }),
        ("整理上下文", { s, _ in s.activity = .compacting }),
        ("重试 2/10", { s, _ in s.activity = .retrying(attempt: 2, max: 10) }),
        ("重试 10/10", { s, _ in s.activity = .retrying(attempt: 10, max: 10) }),
        ("被打断", { s, _ in s.activity = .interrupted }),
        ("出错", { s, _ in s.activity = .errored }),
        ("做完了（未读）", { s, d in s.activity = .finished; s.unread = true; s.lastTurnDuration = 192; s.lastTurnEndedAt = d }),
        ("做完了（需要你处理）", { s, d in s.activity = .finished; s.unread = true; s.blocked = true; s.lastTurnDuration = 3725; s.lastTurnEndedAt = d
            s.statusDetail = "The migration finished but two of the integration tests are still failing and need a decision from you about which database to keep." }),
        ("空闲", { s, d in s.activity = .idle; s.idleSince = d.addingTimeInterval(-30) }),
        ("打盹", { s, d in s.activity = .dozing; s.idleSince = d.addingTimeInterval(-700) }),
        ("睡着", { s, d in s.activity = .sleeping; s.idleSince = d.addingTimeInterval(-3000) }),
    ]
    public static var stateNames: [String] { states.map { $0.0 } }
    /// 所有状态同时出现需要的座位数。
    public static var allStatesCount: Int { states.count }

    /// count 个会话（座位 0…count-1）。.all 模式下座位 i 用第 (i + stateOffset) % 状态总数 种状态——
    /// 小鱼缸 / 宠物条最多画 8 个人，靠 stateOffset 依次错开，才能把所有状态都摆上去。
    public static func snapshots(count: Int, titles: TitleMode, states mode: StateMode, base: Date, stateOffset: Int = 0) -> [BuddySnapshot] {
        if count <= 0 { return [] }
        var out: [BuddySnapshot] = []
        let demo = DemoScript.snapshots(at: 41, base: base).present
        for i in 0..<count {
            var s: BuddySnapshot
            if mode == .demo, !demo.isEmpty {
                s = demo[i % demo.count]
                if i >= demo.count { s.key += "#\(i)"; s.sessionId = s.key }
                s.seat = i; s.salt = UInt64(i)
            } else {
                let origin: SessionOrigin = [.desktop, .terminal, .vscode][i % 3]
                s = BuddySnapshot(key: "audit:\(i)", seat: i, salt: UInt64(i), title: "", sessionId: "audit\(i)", origin: origin, now: base)
                s.modelFamily = [ModelFamily.claude, .deepseek, .glm, .other][i % 4]
                s.cwd = "/Users/demo/projects/some-rather-long-project-folder-name/and/a/nested/directory/\(i)"
                s.modelName = "claude-opus-5"; s.effort = "high"; s.permissionMode = "acceptEdits"; s.cliVersion = "2.1.284"
                s.hookActive = true
                s.appearedAfterLaunch = false
                s.sessionStartedAt = base.addingTimeInterval(-Double(3600 * 5 + 61))
                let (_, fn) = self.states[(i + stateOffset) % self.states.count]
                s.activitySince = base
                fn(&s, base)
                s.phase = s.activity.phase
                if s.phase != .idle { s.turnStartedAt = base.addingTimeInterval(-(i % 2 == 0 ? 3725 : 12)) }
                s.tokens = TokenBreakdown(input: 12_345_678, output: 234_567_890, cacheWrite: 345_678_901, cacheRead: 1_234_567_890)
                s.contextTokens = 246_000 + i
            }
            s.title = title(titles, index: i)
            out.append(s)
        }
        return out
    }
}
