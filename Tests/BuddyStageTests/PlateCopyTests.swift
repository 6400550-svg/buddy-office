import Testing
import Foundation
import BuddyCore
import PixelKit
@testable import BuddyStage

/// 桌牌 / 卡片 / 通知里的中文文案：缩写规则、格式、隐私模式下不泄露细节、永远不显示 prompt。
@Suite struct PlateCopyTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func shortCommandKeepsTheFirstWordsAndDropsCdPrefixesAndOptions() {
        #expect(PlateCopy.shortCommand("git status") == "git status")
        #expect(PlateCopy.shortCommand("cd ~/app && npm test -- --watch") == "npm test")
        #expect(PlateCopy.shortCommand("/usr/bin/python3 run.py --epochs 3") == "python3 run.py")
        #expect(PlateCopy.shortCommand("ls -la /tmp") == "ls")
        #expect(PlateCopy.shortCommand("swift build; echo done") == "swift build")
        #expect(PlateCopy.shortCommand("cat a | grep b") == "cat a")
        #expect(PlateCopy.shortCommand("   ") == "")
        #expect(PlateCopy.shortCommand("cd /a && cd /b && make all") == "make all")
    }

    @Test func fileNamesClipsAndDurations() {
        #expect(PlateCopy.fileName("/Users/x/app/src/LoginView.swift") == "LoginView.swift")
        #expect(PlateCopy.fileName("noslash") == "noslash")
        #expect(PlateCopy.fileExtension("/a/b.SWIFT") == "swift")
        #expect(PlateCopy.clip("短的") == "短的")
        #expect(PlateCopy.clip("一二三四五六七八九十一二三四五") == "一二三四五六七八九十一二…")
        #expect(PlateCopy.duration(0) == "0:00")
        #expect(PlateCopy.duration(75) == "1:15")
        #expect(PlateCopy.duration(3725) == "62:05")
        #expect(PlateCopy.spoken(45) == "45秒")
        #expect(PlateCopy.spoken(192) == "3分12秒")
        #expect(PlateCopy.spoken(7260) == "2小时1分")
        #expect(PlateCopy.waitSpoken(59) == "59 秒")
        #expect(PlateCopy.waitSpoken(120) == "2 分钟")
        #expect(PlateCopy.tokens(999) == "999 tok")
        #expect(PlateCopy.tokens(13_800) == "14K tok")
        #expect(PlateCopy.tokens(1_234_567) == "1.2M tok")
        #expect(PlateCopy.tokens(999_949_999) == "999.9M tok")
        #expect(PlateCopy.tokens(1_827_160_359) == "1.8B tok")
        #expect(PlateCopy.domain("https://www.nature.com/articles/x") == "nature.com")
    }

    static func snap(_ a: Activity) -> BuddySnapshot {
        var s = BuddySnapshot(key: "d:x", seat: 0, salt: 0, title: "重构登录模块", sessionId: "x", origin: .desktop, now: base)
        s.activity = a; s.phase = a.phase; s.activitySince = base
        return s
    }

    @Test func activityTextForEveryState() {
        let now = Self.base.addingTimeInterval(5)
        func call(_ n: String, _ d: String) -> ToolCall { ToolCatalog.makeCall(name: n, detail: d, at: Self.base) }
        let cases: [(Activity, String)] = [
            (.thinking, "思考中"), (.compacting, "在整理记忆"), (.retrying(attempt: 2, max: 10), "网络不稳，重试中 2/10"),
            (.tool(call("Read", "/a/b/LoginView.swift"), parallel: 1), "在读 LoginView.swift"),
            (.tool(call("Edit", "/a/Session.swift"), parallel: 1), "在改 Session.swift"),
            (.tool(call("Bash", "cd x && git status"), parallel: 1), "运行 git status"),
            (.tool(call("Grep", "TODO"), parallel: 3), "在找 \"TODO\" ×3"),
            (.waitingApproval(tool: call("Bash", "git push")), "等你批准 Bash · 5 秒"),
            (.asking, "有问题问你"), (.planReview, "计划好了，等你看"), (.interrupted, "被你打断了"), (.errored, "出错了"), (.idle, "空闲"), (.sleeping, "睡着了"),
        ]
        for (a, want) in cases { #expect(PlateCopy.activity(Self.snap(a), now: now, privacy: false) == want, "\(a)") }
    }

    @Test func privacyModeNeverLeaksDetails() {
        let now = Self.base.addingTimeInterval(5)
        func call(_ n: String, _ d: String) -> ToolCall { ToolCatalog.makeCall(name: n, detail: d, at: Self.base) }
        let secrets = ["LoginView", "git push", "hydrogen", "nature.com", "TODO", "npm"]
        let acts: [Activity] = [.tool(call("Read", "/a/LoginView.swift"), parallel: 1), .tool(call("Bash", "npm test"), parallel: 1),
                                .tool(call("WebSearch", "hydrogen embrittlement"), parallel: 1), .tool(call("WebFetch", "https://nature.com/x"), parallel: 1),
                                .tool(call("Grep", "TODO"), parallel: 1), .waitingApproval(tool: call("Bash", "git push"))]
        for a in acts {
            let t = PlateCopy.activity(Self.snap(a), now: now, privacy: true)
            for s in secrets { #expect(!t.contains(s), "隐私模式下「\(t)」泄露了 \(s)") }
        }
    }

    @Test func statusCandidatesGoFromDetailedToShort() {
        var s = Self.snap(.tool(ToolCatalog.makeCall(name: "Read", detail: "/a.swift", at: Self.base), parallel: 1))
        s.turnStartedAt = Self.base
        s.tokens = TokenBreakdown(input: 1000, output: 2000, cacheWrite: 0, cacheRead: 10_000)
        let c = PlateCopy.statusCandidates(action: "在读 a.swift", s, now: Self.base.addingTimeInterval(75))
        #expect(c == ["在读 a.swift · 本轮 1:15 · 13K tok", "在读 a.swift · 本轮 1:15", "在读 a.swift"])
        var idle = s; idle.phase = .idle
        #expect(PlateCopy.statusCandidates(action: "空闲", idle, now: Self.base) == ["空闲"])
    }

    /// 标题里有 emoji 时，系统会回退到别的字体，它们的 ascent / descent 更大：行高必须只按苹方算，
    /// 否则整行基线被挪下去、盖到桌牌下面那一行文字上（压力测试里抓到的）。
    @Test func emojiInTheTextDoesNotChangeTheLineHeight() {
        for weight in [FontWeightKind.regular, .medium, .semibold] {
            let style = TextStyle(size: 11, color: RGBA8(0, 0, 0, 255), weight: weight)
            let plain = TextRenderer.shared.measure("发布上线 v2.0", style: style)
            let emoji = TextRenderer.shared.measure("🚀 发布上线 v2.0 ✨", style: style)
            #expect(plain.height == emoji.height, "\(weight)：有 emoji 时行高变了（\(plain.height) → \(emoji.height)）")
        }
    }

    @Test func textMeasurementIsCachedAndConsistent() {
        let style = TextStyle(size: 11, color: RGBA8(0, 0, 0, 255), weight: .semibold)
        let a = TextRenderer.shared.measure("重构登录模块", style: style)
        let b = TextRenderer.shared.measure("重构登录模块", style: style)
        #expect(a == b && a.width > 20 && a.height > 8)
        let narrow = TextRenderer.shared.measure("一个很长很长很长很长很长的标题", style: style, maxWidth: 60)
        #expect(narrow.width <= 61, "有 maxWidth 时按省略号截断后的宽度")
    }
}
