import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 任务书 6.5「状态 → 动画」表：每一行的（身体动作, 屏幕, 道具 / 气泡）逐行断言，加上几个时间阈值（思考 > 20 s、Bash 3 / 8 s、WebSearch 先打字、
/// 其他 MCP / 未知工具打字和鼠标交替、被打断 1.5 s、做完 0.4 / 1.6 s）。桌牌文字见 PlateCopyTests。
/// 之前这一层只有金图哈希（锁像素，不锁语义），谁把 Read 的姿势改成打字，哈希会变、但没有测试说得出「该是什么」。
@Suite struct PerformerMappingTests {
    static let base = PerformerTimingTests.base

    /// 一个表演者，活动开始于 base，当前时间 = base + elapsed。
    private func performer(_ activity: Activity, elapsed: Double, helpers: [HelperSnapshot] = [], blocked: Bool = false) -> (Performer, Date) {
        var s = PerformerTimingTests.snap(activity, since: 0)
        s.helpers = helpers; s.blocked = blocked
        let p = Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
        return (p, Self.base.addingTimeInterval(elapsed))
    }
    private func tool(_ name: String, _ detail: String = "", server: String? = nil) -> Activity {
        // 工具开始于 base：elapsed 秒之后它已经跑了 elapsed 秒
        .tool(ToolCatalog.makeCall(name: name, detail: detail, at: Self.base), parallel: 1)
    }

    struct Row { var name: String; var activity: Activity; var elapsed: Double; var pose: PoseKind; var screen: ScreenKind; var bubble: BubbleKind? }

    private var rows: [Row] {
        [
            Row(name: "思考", activity: .thinking, elapsed: 5, pose: .thinking, screen: .ide, bubble: .think),
            Row(name: "思考 > 20 秒：用笔轻敲桌面", activity: .thinking, elapsed: 25, pose: .thinkingDeep, screen: .ide, bubble: .think),
            Row(name: "Read", activity: tool("Read", "/a/b/app.swift"), elapsed: 2, pose: .mouse, screen: .doc("swift"), bubble: nil),
            Row(name: "Read（颜色随扩展名变）", activity: tool("Read", "/a/b/notes.md"), elapsed: 2, pose: .mouse, screen: .doc("md"), bubble: nil),
            Row(name: "Grep", activity: tool("Grep", "TODO"), elapsed: 2, pose: .searching, screen: .results, bubble: .search),
            Row(name: "Glob", activity: tool("Glob", "**/*.swift"), elapsed: 2, pose: .searching, screen: .tree, bubble: .search),
            Row(name: "Edit", activity: tool("Edit", "/a/x.swift"), elapsed: 2, pose: .typing, screen: .diffEdit, bubble: nil),
            Row(name: "MultiEdit", activity: tool("MultiEdit", "/a/x.swift"), elapsed: 2, pose: .typing, screen: .diffEdit, bubble: nil),
            Row(name: "Write（打字更快）", activity: tool("Write", "/a/x.swift"), elapsed: 2, pose: .typingFast, screen: .notebook, bubble: nil),
            Row(name: "NotebookEdit", activity: tool("NotebookEdit", "/a/x.ipynb"), elapsed: 2, pose: .typingFast, screen: .notebook, bubble: nil),
            Row(name: "Bash ≤ 3 秒：快速敲一阵", activity: tool("Bash", "git status"), elapsed: 2, pose: .typing, screen: .terminal, bubble: nil),
            Row(name: "Bash 3–8 秒：手歇下来", activity: tool("Bash", "npm test"), elapsed: 5, pose: .restAtDesk, screen: .terminal, bubble: nil),
            Row(name: "Bash > 8 秒：往后靠 + 进度条", activity: tool("Bash", "npm test"), elapsed: 12, pose: .leanBack, screen: .terminalLong, bubble: nil),
            Row(name: "WebFetch", activity: tool("WebFetch", "https://github.com/x"), elapsed: 2, pose: .mouse, screen: .browser, bubble: nil),
            Row(name: "WebSearch 开头：先打字", activity: tool("WebSearch", "hydrogen"), elapsed: 1, pose: .typing, screen: .search, bubble: nil),
            Row(name: "WebSearch 之后：用鼠标", activity: tool("WebSearch", "hydrogen"), elapsed: 4, pose: .mouse, screen: .search, bubble: nil),
            Row(name: "TodoWrite", activity: tool("TodoWrite"), elapsed: 2, pose: .writingPad, screen: .checklist, bubble: nil),
            Row(name: "Skill：翻手册", activity: tool("Skill", "brainstorming"), elapsed: 2, pose: .mouse, screen: .manual, bubble: .book),
            Row(name: "ToolSearch：翻工具箱", activity: tool("ToolSearch", "select:Read"), elapsed: 2, pose: .mouse, screen: .iconGrid, bubble: .toolbox),
            Row(name: "MCP 浏览器", activity: tool("mcp__Claude_Browser__navigate"), elapsed: 2, pose: .mouse, screen: .mcpBrowser, bubble: nil),
            Row(name: "computer-use", activity: tool("mcp__computer-use__app_click"), elapsed: 2, pose: .mouse, screen: .desktop, bubble: nil),
            Row(name: "其他 MCP 前 3 秒：打字", activity: tool("mcp__notion__search_pages"), elapsed: 1, pose: .typing, screen: .mcpApp("notion"), bubble: nil),
            Row(name: "其他 MCP 3–6 秒：鼠标", activity: tool("mcp__notion__search_pages"), elapsed: 4, pose: .mouse, screen: .mcpApp("notion"), bubble: nil),
            Row(name: "未知工具前 3 秒：打字", activity: tool("SomeUnknownTool"), elapsed: 1, pose: .typing, screen: .gear, bubble: nil),
            Row(name: "未知工具 3–6 秒：鼠标（打字和鼠标交替）", activity: tool("SomeUnknownTool"), elapsed: 4, pose: .mouse, screen: .gear, bubble: nil),
            Row(name: "SendUserFile", activity: tool("SendUserFile", "/tmp/plan.md"), elapsed: 2, pose: .sendFile, screen: .outbox, bubble: nil),
            Row(name: "定时", activity: tool("ScheduleWakeup"), elapsed: 2, pose: .alarm, screen: .clock, bubble: nil),
            Row(name: "Monitor", activity: tool("Monitor", "tail -f x"), elapsed: 2, pose: .leanBack, screen: .log, bubble: nil),
            Row(name: "EnterPlanMode", activity: tool("EnterPlanMode"), elapsed: 2, pose: .writingPad, screen: .plan, bubble: nil),
            Row(name: "等批准（Bash）", activity: .waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: Self.base)), elapsed: 2,
                pose: .faceUser(.approval), screen: .permission, bubble: .approval("icon.tool.bash")),
            Row(name: "等批准（Edit）", activity: .waitingApproval(tool: ToolCatalog.makeCall(name: "Edit", detail: "/a/b.swift", at: Self.base)), elapsed: 2,
                pose: .faceUser(.approval), screen: .permission, bubble: .approval("icon.tool.edit")),
            Row(name: "提问", activity: .asking, elapsed: 2, pose: .faceUser(.question), screen: .question, bubble: .question),
            Row(name: "计划待审", activity: .planReview, elapsed: 2, pose: .faceUser(.plan), screen: .plan, bubble: .plan),
            Row(name: "整理上下文", activity: .compacting, elapsed: 2, pose: .compacting, screen: .compact, bubble: nil),
            Row(name: "重试中", activity: .retrying(attempt: 2, max: 10), elapsed: 2, pose: .retry, screen: .retry(2, 10), bubble: nil),
            Row(name: "出错", activity: .errored, elapsed: 2, pose: .facepalm, screen: .warning, bubble: nil),
            Row(name: "被打断：两手一摊 1.5 秒", activity: .interrupted, elapsed: 1, pose: .shrug, screen: .stop, bubble: nil),
            Row(name: "被打断 1.5 秒之后：靠着", activity: .interrupted, elapsed: 2, pose: .leanSide, screen: .stop, bubble: nil),
            Row(name: "做完了：伸懒腰", activity: .finished, elapsed: 1, pose: .stretch, screen: .done, bubble: nil),
            Row(name: "做完了：3/4 侧身靠着", activity: .finished, elapsed: 3, pose: .leanSide, screen: .done, bubble: nil),
            Row(name: "空闲", activity: .idle, elapsed: 30, pose: .idle, screen: .idleDesktop, bubble: nil),
            Row(name: "打盹", activity: .dozing, elapsed: 30, pose: .doze, screen: .screensaver, bubble: .zzz),
            Row(name: "睡着", activity: .sleeping, elapsed: 30, pose: .sleep, screen: .off, bubble: .zzz),
        ]
    }

    @Test func everyRowOfTheStateToAnimationTable() {
        for row in rows {
            let (p, now) = performer(row.activity, elapsed: row.elapsed)
            #expect(p.targetPose(now: now, time: row.elapsed) == row.pose, "「\(row.name)」姿势 \(p.targetPose(now: now, time: row.elapsed))，应为 \(row.pose)")
            #expect(p.targetScreen(now: now) == row.screen, "「\(row.name)」屏幕 \(p.targetScreen(now: now))，应为 \(row.screen)")
            #expect(p.targetBubble(now: now) == row.bubble, "「\(row.name)」气泡 \(String(describing: p.targetBubble(now: now)))，应为 \(String(describing: row.bubble))")
        }
        #expect(rows.count >= 40, "6.5 表的每一行都要有")
    }

    @Test func delegatingToForegroundHelpersPointsAtThemAndBackgroundOnesLeavesYouTyping() {
        let fg = [HelperSnapshot(id: "h1", description: "调研", foreground: true, active: true)]
        let bg = [HelperSnapshot(id: "h1", description: "整理", foreground: false, active: true)]
        let (pf, now) = performer(tool("Agent", "调研"), elapsed: 2, helpers: fg)
        #expect(pf.targetPose(now: now, time: 2) == .delegate, "前台小助手：转过去指一指、抱臂督工")
        #expect(pf.targetScreen(now: now) == .helpers)
        let (pb, now2) = performer(tool("Agent", "整理"), elapsed: 2, helpers: bg)
        #expect(pb.targetPose(now: now2, time: 2) == .typing, "后台小助手：回去干自己的活")
    }

    @Test func aBlockedIdleSessionShowsTheStickyNote() {
        let (p, now) = performer(.idle, elapsed: 30, blocked: true)
        #expect(p.targetBubble(now: now) == .note)
        let (q, now2) = performer(.idle, elapsed: 30, blocked: false)
        #expect(q.targetBubble(now: now2) == nil)
    }

    /// 任务书 5.6：一轮做完，先等 0.4 s 再伸懒腰（这 0.4 s 里继续保持刚才的忙姿势）。
    @Test func finishingATurnWaits0_4SecondsBeforeStretching() {
        let (p, _) = performer(.finished, elapsed: 0)
        p.lastBusyPose = .typing
        #expect(p.targetPose(now: Self.base.addingTimeInterval(0.2), time: 0.2) == .typing, "0.4 秒内还保持刚才的忙姿势")
        #expect(p.targetPose(now: Self.base.addingTimeInterval(0.5), time: 0.5) == .stretch)
        #expect(p.targetPose(now: Self.base.addingTimeInterval(1.7), time: 1.7) == .leanSide, "伸完懒腰 3/4 侧身靠着")
    }

    /// 屏幕内容和姿势的映射是穷尽的：所有活动种类 × 所有工具类别都给得出一个姿势 / 屏幕（不会有未处理的分支被默认值悄悄吞掉）。
    @Test func everyToolCategoryHasAPoseAndAScreen() {
        for name in ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "Monitor", "WebFetch", "WebSearch", "mcp__Claude_Browser__navigate", "mcp__computer-use__app_click",
                     "Agent", "TodoWrite", "Skill", "ToolSearch", "EnterPlanMode", "ExitPlanMode", "SendUserFile", "ScheduleWakeup", "mcp__x__y", "Whatever"] {
            for el in [0.5, 4, 10, 40] {
                let (p, now) = performer(tool(name), elapsed: el)
                _ = p.targetPose(now: now, time: el)
                #expect(p.targetScreen(now: now) != .off, "\(name) 在 \(el) 秒时屏幕不该是关着的")
            }
        }
    }
}
