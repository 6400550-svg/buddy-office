import Testing
import Foundation
import BuddyCore
import BuddyArt
import BuddyStage
import PixelKit
@testable import BuddyOffice

/// B-2「点击 buddy 不会跳到别人的会话」：目标解析（命中 ID → 座位 → 会话 key → 深链 / tty / 宿主）是纯函数，逐项测。
@Suite struct JumpTests {
    /// 6 个会话，三种来源，座位号和数组顺序都故意错开。
    static func crowd() -> [BuddySnapshot] {
        [Fx.snap("d:a", seat: 3, origin: .desktop, activity: .thinking, host: "local_aaa-111"),
         Fx.snap("t:b", seat: 0, origin: .terminal, pid: 4001),
         Fx.snap("d:c", seat: 5, origin: .desktop, activity: .waitingApproval(tool: Fx.call("Bash", "ls")), host: "local_ccc-333"),
         { var s = Fx.snap("v:d", seat: 1, origin: .vscode); s.cwd = "/Users/x/proj-d"; return s }(),
         Fx.snap("t:e", seat: 2, origin: .terminal, pid: 4002),
         Fx.snap("d:f", seat: 4, origin: .desktop, host: "local_fff-666")]
    }

    @Test func everySeatMapsToItsOwnSessionAndItsOwnTarget() throws {
        let all = Self.crowd()
        let expected: [Int: JumpTarget] = [
            0: .terminal(pid: 4001), 1: .vscode(cwd: "/Users/x/proj-d"), 2: .terminal(pid: 4002),
            3: .desktopDeepLink(host: "local_aaa-111", url: URL(string: "claude://code/continue?session=local_aaa-111")!),
            4: .desktopDeepLink(host: "local_fff-666", url: URL(string: "claude://code/continue?session=local_fff-666")!),
            5: .desktopDeepLink(host: "local_ccc-333", url: URL(string: "claude://code/needs-input?session=local_ccc-333")!),
        ]
        for seat in 0..<6 {
            let s = try #require(JumpResolver.snapshot(forSeat: seat, in: all), "seat \(seat)")
            #expect(s.seat == seat)
            #expect(JumpResolver.target(for: s, deepLinkDisabled: false) == expected[seat], "seat \(seat)")
        }
    }

    /// 座位 / 会话变动之后不串：走了的人的座位换了新人，点到的是现在坐着的那个；换了座位的按新座位。
    @Test func afterSeatsAndSessionsChangeAClickStillResolvesToWhoSitsThereNow() throws {
        var all = Self.crowd()
        #expect(JumpResolver.snapshot(forSeat: 0, in: all)?.key == "t:b")
        // t:b 走了，新来的 t:new 坐了 0 号；d:a 从 3 号搬到 6 号
        all.removeAll { $0.key == "t:b" }
        all.append(Fx.snap("t:new", seat: 0, origin: .terminal, pid: 4100))
        if let i = all.firstIndex(where: { $0.key == "d:a" }) { all[i].seat = 6 }
        let s0 = try #require(JumpResolver.snapshot(forSeat: 0, in: all))
        #expect(s0.key == "t:new" && JumpResolver.target(for: s0, deepLinkDisabled: false) == .terminal(pid: 4100), "0 号现在是新来的，不是走了的 t:b")
        #expect(JumpResolver.snapshot(forSeat: 3, in: all) == nil, "3 号空了：d:a 搬走了")
        #expect(JumpResolver.snapshot(forSeat: 6, in: all)?.key == "d:a")
        // 按 key 找（提示卡 / 通知 / 小鱼缸 / 宠物条）：跟着人走，不看座位
        #expect(JumpResolver.snapshot(forKey: "d:a", in: all)?.seat == 6)
        #expect(JumpResolver.snapshot(forKey: "t:b", in: all) == nil, "走了的会话：点他的通知什么都不发生")
    }

    /// 悬空的座位号（没有人 / 只有下班工位 / 越界 / 负数）：点了不跳。
    @Test func danglingSeatsNeverJump() {
        var all = Self.crowd()
        all.append(Fx.dormant("d:off", seat: 7))
        #expect(JumpResolver.snapshot(forSeat: 7, in: all) == nil, "下班工位（away）点了不跳")
        for seat in [6, 8, 63, 64, 1_000_000, -1, Int.max, Int.min] { #expect(JumpResolver.snapshot(forSeat: seat, in: all) == nil, "seat \(seat)") }
        #expect(JumpResolver.snapshot(forSeat: 0, in: []) == nil)
        // 同一个座位号上既有下班工位又有在场的会话（换人的那一帧）：只认在场的
        var both = [Fx.dormant("d:old", seat: 2), Fx.snap("t:now", seat: 2, pid: 9)]
        #expect(JumpResolver.snapshot(forSeat: 2, in: both)?.key == "t:now")
        both.removeAll { $0.key == "t:now" }
        #expect(JumpResolver.snapshot(forSeat: 2, in: both) == nil)
    }

    @Test func aKeyThatIsNoLongerPresentResolvesToNothing() {
        let all = [Fx.dormant("d:gone", seat: 1), Fx.snap("t:ok", seat: 0, pid: 1)]
        #expect(JumpResolver.snapshot(forKey: "d:gone", in: all) == nil)
        #expect(JumpResolver.snapshot(forKey: "t:ok", in: all)?.seat == 0)
        #expect(JumpResolver.snapshot(forKey: "nope", in: all) == nil)
    }

    @Test func codexThreadsJumpThroughTheirOwnDeepLink() {
        let id = "01a0f083-d304-7420-b1e2-8305fec5add2"
        var s = Fx.snap("x:" + id, origin: .codex, activity: .thinking)
        s.sessionId = id
        #expect(JumpResolver.target(for: s, deepLinkDisabled: false) == .codexThread(url: URL(string: "codex://threads/\(id)")!))
        #expect(JumpResolver.target(for: s, deepLinkDisabled: true) == .codexThread(url: URL(string: "codex://threads/\(id)")!), "Codex 的深链不受 Claude 深链停用的影响")
        s.sessionId = "../../evil"
        #expect(JumpResolver.target(for: s, deepLinkDisabled: false) == .none, "线程 id 不是 UUID：不拼进链接")
        #expect(SessionOrigin.codex.isAppHosted && SessionOrigin.desktop.isAppHosted && !SessionOrigin.terminal.isAppHosted)
    }

    @Test func deepLinkRules() {
        func desktop(_ host: String?, _ act: Activity = .idle) -> BuddySnapshot { Fx.snap("d:x", origin: .desktop, activity: act, host: host) }
        #expect(JumpResolver.target(for: desktop("local_abc-123"), deepLinkDisabled: false) == .desktopDeepLink(host: "local_abc-123", url: URL(string: "claude://code/continue?session=local_abc-123")!))
        #expect(JumpResolver.target(for: desktop("local_abc-123", .asking), deepLinkDisabled: false) == .desktopDeepLink(host: "local_abc-123", url: URL(string: "claude://code/needs-input?session=local_abc-123")!), "等你的时候是 needs-input")
        #expect(JumpResolver.target(for: desktop("local_abc-123", .planReview), deepLinkDisabled: false) != JumpResolver.target(for: desktop("local_abc-123", .thinking), deepLinkDisabled: false))
        // 连续失败被停用：直接激活 Claude
        #expect(JumpResolver.target(for: desktop("local_abc-123"), deepLinkDisabled: true) == .activateClaude)
        // host id 不合法（正则 ^local_[A-Za-z0-9-]{1,64}$）：不拼深链
        for bad in [nil, "", "abc", "local_", "local_../etc/passwd", "local_a b", "local_a&b=1", "local_" + String(repeating: "a", count: 65), "LOCAL_abc", "local_abc\n", "local_中文"] as [String?] {
            #expect(JumpResolver.target(for: desktop(bad), deepLinkDisabled: false) == .activateClaude, "host \(bad ?? "nil")")
        }
        #expect(JumpResolver.target(for: desktop("local_" + String(repeating: "a", count: 64)), deepLinkDisabled: false) != .activateClaude, "64 位是上限，刚好合法")
    }

    @Test func terminalAndVSCodeTargets() {
        #expect(JumpResolver.target(for: Fx.snap("t:x", origin: .terminal, pid: nil), deepLinkDisabled: false) == .none, "终端会话没有 pid：跳不了")
        #expect(JumpResolver.target(for: Fx.snap("t:x", origin: .terminal, pid: 77), deepLinkDisabled: true) == .terminal(pid: 77), "深链停用不影响终端")
        var v = Fx.snap("v:x", origin: .vscode)
        #expect(JumpResolver.target(for: v, deepLinkDisabled: false) == .vscode(cwd: nil))
        v.cwd = ""
        #expect(JumpResolver.target(for: v, deepLinkDisabled: false) == .vscode(cwd: nil), "空 cwd 当没有")
        v.cwd = "/a/b"
        #expect(JumpResolver.target(for: v, deepLinkDisabled: false) == .vscode(cwd: "/a/b"))
    }

    /// 合并提醒（「N 位同事在等你」）点了打开办公室；认得的 key 跳；走了的什么都不做。
    @Test func notificationClicksRouteCorrectly() {
        let all = Self.crowd()
        #expect(JumpResolver.notificationClick(key: AlertCoordinator.multiKey, in: all) == .openOffice)
        #expect(JumpResolver.notificationClick(key: "d:c", in: all) == .jump("d:c"))
        #expect(JumpResolver.notificationClick(key: "t:gone", in: all) == .nothing)
        #expect(JumpResolver.notificationClick(key: "notice", in: all) == .nothing, "「深链没生效」那条说明卡：点了不跳")
        #expect(JumpResolver.notificationClick(key: "test", in: all) == .nothing)
    }

    // MARK: 深链发出 2.5 秒后的判定（A-026）
    @Test func deepLinkVerdictAfterTwoAndAHalfSeconds() {
        typealias V = JumpResolver.DeepLinkVerdict
        // lastFocusedAt 变新了：成功
        #expect(JumpResolver.deepLinkVerdict(wasLatest: false, before: 100, after: 200, claudeFrontmost: true) == V(succeeded: true, activateClaude: false))
        #expect(JumpResolver.deepLinkVerdict(wasLatest: false, before: nil, after: 200, claudeFrontmost: false) == V(succeeded: true, activateClaude: false), "之前没有记录、现在有了")
        // 没变、目标也不是最近聚焦的：失败，改为直接激活 Claude
        #expect(JumpResolver.deepLinkVerdict(wasLatest: false, before: 100, after: 100, claudeFrontmost: false) == V(succeeded: false, activateClaude: true))
        #expect(JumpResolver.deepLinkVerdict(wasLatest: false, before: 100, after: nil, claudeFrontmost: true) == V(succeeded: false, activateClaude: true))
        #expect(JumpResolver.deepLinkVerdict(wasLatest: false, before: nil, after: nil, claudeFrontmost: true) == V(succeeded: false, activateClaude: true))
        // 目标本来就是最近聚焦的（M0 实测：lastFocusedAt 不会变）：不算失败；但 Claude 不在最前面就补一次激活（原来无条件当成功，什么都没发生）
        #expect(JumpResolver.deepLinkVerdict(wasLatest: true, before: 100, after: 100, claudeFrontmost: true) == V(succeeded: true, activateClaude: false))
        #expect(JumpResolver.deepLinkVerdict(wasLatest: true, before: 100, after: 100, claudeFrontmost: false) == V(succeeded: true, activateClaude: true))
    }

    // MARK: 终端跳转脚本（A-013）
    @Test func theTerminalScriptHasATimeoutAndOnlyAcceptsRealTTYNames() throws {
        let script = try #require(JumpResolver.terminalTabScript(tty: "/dev/ttys012"))
        #expect(script.hasPrefix("with timeout of 5 seconds") && script.hasSuffix("end timeout"), "自动化授权弹窗没人答复时最长卡 5 秒，不是 2 分钟")
        #expect(script.contains(#"(tty of tb) is "/dev/ttys012""#))
        for bad in ["", "ttys012", "/dev/ttys012\" then\nquit", "/dev/../etc/passwd", "/dev/ttys 1", "/dev/ttys012;", "/dev/", "/dev/tty" + String(repeating: "a", count: 40)] {
            #expect(JumpResolver.terminalTabScript(tty: bad) == nil, "\(bad.debugDescription) 不该拼进脚本")
        }
        #expect(JumpResolver.isValidTTY("/dev/ttys000") && JumpResolver.isValidTTY("/dev/ttyp3"))
    }

    // MARK: 桌牌不可点（使用说明 vs 实现）
    /// 桌牌底板上的像素不带对象 ID：点桌牌不会跳转。使用说明.txt 不能再写「点小人（或桌牌）」。
    @Test func plateStripPixelsCarryNoObjectIDSoClickingThePlateDoesNothing() {
        let scene = OfficeScene()
        var opts = SceneOptions(); opts.zoom = 3; opts.animateWalkers = false
        let s = [Fx.snap("t:a", seat: 1, activity: .thinking)]
        let f = scene.render(viewportW: 336, viewportH: 339, present: s, dormant: [], now: Fx.base, time: 5, options: opts)
        guard let v = scene.lastSeatViews.first(where: { $0.seat == 1 }) else { Issue.record("没有 1 号座位"); return }
        var bodyHits = 0, plateHits = 0
        for y in v.origin.y..<(v.origin.y + Metrics.cellH) { for x in v.origin.x..<(v.origin.x + Metrics.cellW) where f.canvas.objectID(x, y) == OfficeScene.hitID(seat: 1) { bodyHits += 1 } }
        for y in (v.origin.y + Metrics.cellH)..<(v.origin.y + Metrics.cellH + Metrics.plateH) { for x in v.origin.x..<(v.origin.x + Metrics.cellW) where f.canvas.hitID(x: x, y: y, dilate: false) != 0 { plateHits += 1 } }
        #expect(bodyHits > 20, "小人本身是可点的")
        #expect(plateHits == 0, "桌牌带里没有任何可点的像素")
    }

    @Test func theUserManualDoesNotClaimThatThePlateIsClickable() throws {
        let manual = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("使用说明.txt"), encoding: .utf8)
        let offending = manual.split(separator: "\n").filter { $0.contains("点") && $0.contains("桌牌") && ($0.contains("跳") || $0.contains("小人")) }
        #expect(offending.isEmpty, "使用说明说点桌牌也能跳，但桌牌没有命中 ID：\(offending)")
        #expect(manual.contains("· 点小人：桌面 App 会话用深链"), "点击那一条还在（只是不再提桌牌）")
    }
}
