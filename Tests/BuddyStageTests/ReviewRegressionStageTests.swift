import Testing
import Foundation
import BuddyCore
import PixelKit
@testable import BuddyStage

/// 收尾前的独立复查（QA/review-R1b.md）新发现的问题的回归测试。编号对应 QA/issues-review.md。全部用假时钟。
/// 后台线程的停止标志（线程安全）。
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

@Suite struct ReviewRegressionStageTests {
    typealias T = PerformerTimingTests
    static let base = PerformerTimingTests.base

    // MARK: R1b-01 错开推迟期间活动变回去

    /// SP-06 只修了「推迟期间变成等待类」；同一个根因（推迟记录里存着一份过期的中间快照、到点原样套用）在
    /// 「推迟期间变回已套用的同一种类」这条路径上还在：Read → Edit → Read，到点那一帧把 Edit 套给了表演者。
    @Test("R1b-01 错开推迟期间活动变回已套用的同一种类：推迟记录作废，不能套用推迟开始时存下的过期快照")
    func r1b01_aStaggeredChangeThatRevertsBeforeItsTurnIsDropped() {
        let d = VisualDirector()
        var sawEdit: [Double] = [], typing: [Double] = []
        T.run(d, from: 0, to: 5, snapshots: { t in
            // 3 个人在 2.0 秒同时 Read → Edit（错开 0 / 90 / 180 ms）；第 3 个人在 2.05 秒（他自己的推迟到点之前）变回 Read
            (0..<3).map { i in
                let editing = t >= 2.0 && !(i == 2 && t >= 2.05)
                return T.snap(editing ? T.tool("Edit", "/b", at: 2.0) : T.tool("Read", "/a", at: 0), key: "d:\(i)", seat: i, since: editing ? 2.0 : 0)
            }
        }) { t, dir in
            guard let p = dir.performers["d:2"] else { return }
            if case .tool(let c, _) = p.snapshot.activity, c.name == "Edit" { sawEdit.append(t) }
            if t >= 2.0, p.pose == .typing { typing.append(t) }
        }
        #expect(sawEdit.isEmpty, "第 3 个人一直在 Read（2.05 秒就变回来了），表演者却在 \(sawEdit) 看到了过期的 Edit")
        #expect(typing.isEmpty, "第 3 个人一直在 Read，姿势却在 \(typing.first ?? 0)…\(typing.last ?? 0) 秒是打字")
        // 前两个人照常（Edit 不会被误伤）：第 1 个人 2.0 秒起是打字
        #expect(d.performers["d:0"]?.pose == .typing)
    }

    // MARK: R1b-02 桌牌 1.0 s 最短停留被文件名 / 命令里的数字绕过

    @Test("R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）")
    func r1b02_digitsInFileNamesAndCommandsDoNotBypassThePlateHold() {
        let variants: [(String, (Int) -> Activity)] = [
            ("Read part<n>.txt", { n in T.tool("Read", "/a/part\(n).txt", at: Double(n) * 0.15) }),
            ("Bash sleep <n>", { n in T.tool("Bash", "sleep \(n)", at: Double(n) * 0.15) }),
            ("WebSearch swift <n>", { n in T.tool("WebSearch", "swift \(n)", at: Double(n) * 0.15) }),
            ("Read v<n>", { n in T.tool("Read", "/a/v\(n)", at: Double(n) * 0.15) }),
        ]
        for (name, make) in variants {
            let d = VisualDirector()
            var series: [(Double, String)] = []
            T.run(d, from: 0, to: 4, snapshots: { t in
                let n = Int(t / 0.15)
                return [T.snap(make(n), since: Double(n) * 0.15)]
            }) { t, dir in if let p = dir.performers["d:a"] { series.append((t, p.plate)) } }
            let times = T.changeTimes(series)
            #expect(times.count >= 2, "\(name)：桌牌文字应该换过几次")
            for i in 1..<max(1, times.count) { #expect(times[i] - times[i - 1] >= 1.0 - 1.0 / 30 - 1e-9, "\(name)：桌牌 \(times[i - 1]) → \(times[i]) 只隔了 \(times[i] - times[i - 1]) 秒（任务书 5.6 要求 ≥ 1.0）") }
        }
    }

    @Test("R1b-02 计时器数字仍然不受最短停留约束：「运行中 npm test · 0:09」→「0:10」…每秒都立刻换")
    func r1b02_timerDigitsStillTickEverySecond() {
        let d = VisualDirector()
        var series: [(Double, String)] = []
        T.run(d, from: 0, to: 22, snapshots: { _ in [T.snap(T.tool("Bash", "npm test", at: 0), since: 0)] }) { t, dir in
            if let p = dir.performers["d:a"] { series.append((t, p.plate)) }
        }
        let inWindow = series.filter { $0.0 >= 10 && $0.0 <= 20 }
        var changes = 0
        for i in 1..<inWindow.count where inWindow[i].1 != inWindow[i - 1].1 { changes += 1 }
        #expect(changes >= 9, "10–20 秒里计时器每秒该换一次数字，只换了 \(changes) 次：\(Set(inWindow.map { $0.1 }).sorted())")
        #expect(inWindow.allSatisfy { $0.1.hasPrefix("运行中 npm test · ") }, "\(Set(inWindow.map { $0.1 }))")
    }

    @Test("R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留")
    func r1b02_digitMaskOnlyMasksCounterPositions() {
        let m = Performer.digitMask
        #expect(m("运行中 npm test · 1:23") == m("运行中 npm test · 12:05"))
        #expect(m("等你批准 Bash · 12 秒") == m("等你批准 Bash · 45 秒"))
        #expect(m("做完了 · 3分12秒") == m("做完了 · 5分40秒"))
        #expect(m("网络不稳，重试中 2/10") == m("网络不稳，重试中 9/10"))
        #expect(m("在找 \"TODO\" ×3") == m("在找 \"TODO\" ×12"))
        #expect(m("派了 2 个帮手") == m("派了 10 个帮手"))
        #expect(m("打盹 12 分钟") == m("打盹 45 分钟"))
        // 文件名 / 命令 / 搜索词里的数字不是计数器
        #expect(m("在读 part1.txt") != m("在读 part2.txt"))
        #expect(m("运行 sleep 1") != m("运行 sleep 5"))
        #expect(m("在搜 \"swift 5\"") != m("在搜 \"swift 6\""))
        #expect(m("在读 v1") != m("在读 v2"))
        // 命令里有数字、后面又有计时器：只抹计时器
        #expect(m("运行中 sleep 5 · 0:09") == m("运行中 sleep 5 · 0:10"))
        #expect(m("运行中 sleep 5 · 0:09") != m("运行中 sleep 6 · 0:09"))
    }

    // MARK: R1b-03 隐私模式没有隐藏 MCP server 名和未知工具名

    @Test("R1b-03 隐私模式：MCP server 名和未知工具名也不能出现在桌牌动作 / 状态行里（任务书 6.3：隐私模式下隐藏全部细节）")
    func r1b03_privacyModeHidesMcpServerAndUnknownToolNames() {
        func call(_ n: String, _ d: String = "x") -> ToolCall { ToolCatalog.makeCall(name: n, detail: d, at: Self.base) }
        func snap(_ a: Activity) -> BuddySnapshot {
            var s = BuddySnapshot(key: "d:x", seat: 0, salt: 0, title: "标题", sessionId: "x", origin: .desktop, now: Self.base)
            s.activity = a; s.phase = a.phase; s.activitySince = Self.base; s.turnStartedAt = Self.base
            return s
        }
        let now = Self.base.addingTimeInterval(1)
        let secrets = ["acme", "secret", "crm", "linear", "SomeInternal", "Internal", "query", "create_issue"]
        let acts: [Activity] = [.tool(call("mcp__acme-secret-crm__query"), parallel: 1), .tool(call("mcp__linear__create_issue"), parallel: 1),
                                .tool(call("SomeInternalTool"), parallel: 1), .waitingApproval(tool: call("mcp__acme-secret-crm__query")),
                                .waitingApproval(tool: call("SomeInternalTool"))]
        for a in acts {
            let t = PlateCopy.activity(snap(a), now: now, privacy: true)
            let line = PlateCopy.statusLine(snap(a), now: now, privacy: true)
            for s in secrets {
                #expect(!t.contains(s), "隐私模式下桌牌动作「\(t)」泄露了 \(s)")
                #expect(!line.contains(s), "隐私模式下状态行「\(line)」泄露了 \(s)")
            }
        }
        // 不开隐私模式时照旧
        #expect(PlateCopy.activity(snap(.tool(call("mcp__acme-secret-crm__query"), parallel: 1)), now: now, privacy: false) == "在用 acme-secre…")
        #expect(PlateCopy.activity(snap(.tool(call("SomeInternalTool"), parallel: 1)), now: now, privacy: false) == "在用 SomeInternalTo…")
    }

    // MARK: R1b-04 气泡没有最短停留

    @Test("R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪")
    func r1b04_toolBubblesAreHeldForAtLeast0_8Seconds() {
        let d = VisualDirector()
        var bubble: [(Double, BubbleKind?)] = [], pose: [(Double, PoseKind)] = []
        T.run(d, from: 0, to: 6, snapshots: { t in
            let n = Int(t / 0.3)
            let a = n % 2 == 0 ? T.tool("Grep", "TODO", at: Double(n) * 0.3) : T.tool("Read", "/a.swift", at: Double(n) * 0.3)
            return [T.snap(a, since: Double(n) * 0.3)]
        }) { t, dir in if let p = dir.performers["d:a"] { bubble.append((t, p.bubble)); pose.append((t, p.pose)) } }
        let times = T.changeTimes(bubble)
        #expect(times.count >= 2, "气泡应该变过几次")
        for i in 1..<max(1, times.count) { #expect(times[i] - times[i - 1] >= 0.8 - 1.0 / 30 - 1e-9, "气泡 \(times[i - 1]) → \(times[i]) 只隔了 \(times[i] - times[i - 1]) 秒") }
    }

    @Test("R1b-04 等待类气泡（钥匙 / 问号 / 计划）不受最短停留限制：立刻出现，批准之后立刻消失；新来的人第一帧就有气泡")
    func r1b04_waitingBubblesAreNeverHeld() {
        // 放大镜气泡刚出现 0.1 秒，等批准来了 → 钥匙气泡立刻取代；批准完成又变回读文件 → 气泡马上没了
        let d = VisualDirector()
        var frames: [(t: Double, bubble: BubbleKind?)] = []
        T.run(d, from: 0, to: 4, snapshots: { t in
            if t < 1.1 { return [T.snap(T.tool("Grep", "TODO", at: 0), since: 0)] }
            if t < 2.0 { return [T.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: T.base.addingTimeInterval(1.1))), since: 1.1)] }
            return [T.snap(T.tool("Read", "/a.swift", at: 2.0), since: 2.0)]
        }) { t, dir in if let p = dir.performers["d:a"] { frames.append((t, p.bubble)) } }
        let frame = 1.0 / 30
        let firstApproval = frames.first { if case .approval? = $0.bubble { return true } else { return false } }?.t
        #expect(firstApproval != nil && firstApproval! - 1.1 <= frame + 1e-6, "等批准的钥匙气泡该在 1.1 秒的同一帧出现：\(String(describing: firstApproval))")
        let goneAt = frames.first { $0.t >= 2.0 && $0.bubble == nil }?.t
        #expect(goneAt != nil && goneAt! - 2.0 <= 0.8, "批准完成变回读文件之后气泡该马上没有（最多等一个最短停留）：\(String(describing: goneAt))")
        // 一个新来的人：第一帧就要有放大镜气泡（不用等最短停留）
        let d2 = VisualDirector()
        d2.update(snapshots: [T.snap(T.tool("Grep", "TODO", at: 0), since: 0)], now: T.base, time: 0, privacy: false)
        #expect(d2.performers["d:a"]?.bubble == .search)
    }

    // MARK: R1b-05 打开隐私模式时桌牌动作文字还要等最短停留

    @Test("R1b-05 打开隐私模式：桌牌动作文字当场就隐藏，不等 1.0 秒最短停留（刚换过字也一样）")
    func r1b05_turningPrivacyOnHidesThePlateActionImmediately() {
        let d = VisualDirector()
        var afterToggle: [(Double, String)] = []
        var t = 0.0
        while t <= 4 {
            let editing = t >= 2.0
            let a = editing ? T.tool("Edit", "/secret/Payroll.swift", at: 2.0) : T.tool("Read", "/secret/Salaries.swift", at: 0)
            d.update(snapshots: [T.snap(a, since: editing ? 2.0 : 0)], now: T.base.addingTimeInterval(t), time: t, privacy: t >= 2.3)
            if t >= 2.3, let p = d.performers["d:a"] { afterToggle.append((t, p.plate)) }
            t += 1.0 / 30
        }
        // 2.0 秒换成 Edit（桌牌更新），2.3 秒打开隐私：第一帧就该是不带文件名的文案
        #expect(afterToggle.first?.1 == "在改代码", "打开隐私的那一帧桌牌是「\(afterToggle.first?.1 ?? "")」")
        #expect(afterToggle.allSatisfy { !$0.1.contains("Payroll") && !$0.1.contains("Salaries") }, "\(afterToggle.map { $0.1 })")
    }

    // MARK: R1b-06 只有零宽 / 控制字符的标题会画出一块空桌牌

    @Test("R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌")
    func r1b06_invisibleOnlyTitlesGetThePlaceholder() {
        let placeholder = PlateCopy.displayTitle("")
        #expect(placeholder == "（没有标题）")
        for t in ["\u{200B}", "\u{200B}\u{200C}\u{200D}", "\u{FEFF}", "\u{2060}", "\u{202E}\u{202C}", " \u{200B}\t\n", "\u{0007}", "\u{00A0}", "\u{2028}"] {
            #expect(PlateCopy.displayTitle(t) == placeholder, "「\(t.unicodeScalars.map { String($0.value, radix: 16) })」应该算空标题")
        }
        // 有可见字符就原样（哪怕夹着零宽字符）
        #expect(PlateCopy.displayTitle("a\u{200B}") == "a\u{200B}")
        #expect(PlateCopy.displayTitle("重构登录模块") == "重构登录模块")
        #expect(PlateCopy.displayTitle("🚀") == "🚀")
    }

    // MARK: R2-015（A-019 的遗留）工具详情为空时的文案

    @Test("R2-015 工具详情为空（hook 行被截断走降级解析时会出现）：桌牌文案不能是「在读 」「在找 \"\"」「运行 」这种带尾随空格 / 空引号的半截话")
    func r2015_emptyToolDetailsFallBackToGenericCopy() {
        func call(_ n: String, _ d: String) -> ToolCall { ToolCatalog.makeCall(name: n, detail: d, at: Self.base) }
        func text(_ n: String, _ d: String) -> String {
            var s = BuddySnapshot(key: "d:x", seat: 0, salt: 0, title: "标题", sessionId: "x", origin: .desktop, now: Self.base)
            let a: Activity = .tool(call(n, d), parallel: 1)
            s.activity = a; s.phase = a.phase; s.activitySince = Self.base
            return PlateCopy.activity(s, now: Self.base.addingTimeInterval(1), privacy: false)
        }
        let cases: [(String, String, String)] = [("Read", "", "在读文件"), ("Read", "   ", "在读文件"), ("Edit", "", "在改代码"), ("Write", "", "在写文件"),
                                                 ("Grep", "", "在找东西"), ("Bash", "", "在运行命令"), ("WebSearch", "", "在搜索"), ("WebFetch", "", "在看网页"), ("NotebookEdit", "", "在改代码")]
        for (name, detail, want) in cases {
            let t = text(name, detail)
            #expect(t == want || (name == "NotebookEdit" && !t.hasSuffix(" ")), "\(name)(空详情)：「\(t)」，应为「\(want)」")
            #expect(!t.hasSuffix(" ") && !t.contains("\"\""), "\(name)：「\(t)」有尾随空格或空引号")
        }
        // 有详情时照旧
        #expect(text("Read", "/a/b/LoginView.swift") == "在读 LoginView.swift")
        #expect(text("Grep", "TODO") == "在找 \"TODO\"")
        #expect(text("Bash", "cd x && git status") == "运行 git status")
    }

    // MARK: R3b-02 隐私模式下的文字：标题 / 项目路径 / 工具详情 / server 名不能出现在任何文字层里

    /// 隐私模式（任务书 6.3：隐藏全部细节）的隐藏发生在好几处：桌牌标题（`OfficeScene`）、悬停卡片的标题和项目路径（`HoverCard`）、
    /// 桌牌动作 / 状态行（`PlateCopy`）。复查员做了变异（各处的隐私分支失效），整套 BuddyStage + BuddyOffice 379 个测试全绿——没有任何测试钉住它们。
    /// 这条是端到端的泄漏扫描：18 种工具 × 忙 / 等批准 × 刚开始 / 做了很久，会话标题、项目路径、statusDetail、工具详情、MCP server 名都带同一个标记串，
    /// 走完 Director、办公室（在场 / 下班 / 悬停）、悬停卡片，所有文字层里一处都不能出现这个标记串。
    @Test("R3b-02 隐私模式端到端泄漏扫描：18 种工具 × 忙 / 等批准，桌牌 / 状态行 / 悬停卡片 / 下班工位的所有文字里都不出现会话标题、项目路径、工具详情、server 名")
    func r3b02_privacyModeLeaksNothingIntoAnyTextTheUIProduces() {
        let secret = "SECRETXYZ"
        let calls: [(String, String)] = [("Read", "/Users/x/\(secret)/file\(secret).swift"), ("Edit", "/a/\(secret).swift"), ("Write", "/a/\(secret).txt"), ("Bash", "\(secret)cmd arg"), ("Grep", "\(secret)query"),
            ("Glob", "**/\(secret)"), ("WebFetch", "https://\(secret).com/x"), ("WebSearch", "\(secret) query"), ("Agent", "\(secret) research"), ("Skill", "\(secret)"), ("ToolSearch", "\(secret)"), ("mcp__\(secret)srv__act", "\(secret)"),
            ("mcp__Claude_Browser__\(secret)", "\(secret)"), ("mcp__computer-use__\(secret)", "\(secret)"), ("\(secret)Tool", "\(secret)"), ("SendUserFile", "/tmp/\(secret).md"), ("Monitor", "tail \(secret)"), ("TodoWrite", "\(secret)")]
        var leaks: [String] = []
        for (idx, (n, dt)) in calls.enumerated() {
            for long in [false, true] {
                var s = BuddySnapshot(key: "k\(idx)", seat: 0, salt: 0, title: "标题\(secret)", sessionId: "s", origin: .desktop, now: Self.base)
                let start = Self.base.addingTimeInterval(long ? -20 : -1)
                let call = ToolCatalog.makeCall(name: n, detail: dt, at: start)
                s.activity = .tool(call, parallel: 2); s.phase = .busy; s.turnStartedAt = start; s.cwd = "/Users/\(secret)/proj"; s.statusDetail = "detail \(secret)"; s.hookActive = true
                var w = s; w.activity = .waitingApproval(tool: call)
                for (label, snap) in [("tool", s), ("waiting", w)] {
                    let d = VisualDirector(); let sc = OfficeScene(); sc.director = d
                    var o = SceneOptions(); o.zoom = 3; o.privacy = true; o.directorIsExternal = true; o.animateWalkers = false
                    var strs: [String] = []
                    for tt in stride(from: 0.0, to: 4.0, by: 0.5) {
                        let now = Self.base.addingTimeInterval(tt)
                        var sn = snap; sn.appearedAfterLaunch = false
                        d.update(snapshots: [sn], now: now, time: tt, privacy: true)
                        var oo = o; oo.hoverSeat = 0; oo.hoverSnapshot = sn
                        strs += sc.render(viewportW: 224, viewportH: 226, present: [sn], dormant: [], now: now, time: tt, options: oo).texts.map { $0.text }
                        strs += sc.render(viewportW: 224, viewportH: 226, present: [], dormant: [sn], now: now, time: tt, options: o).texts.map { $0.text }
                        for st in d.performers.values { strs.append(st.plate); strs += st.statusCandidates(now: now) }
                        strs += HoverCard.make(sn, now: now, zoom: 3, privacy: true).texts.map { $0.text }
                    }
                    for x in Set(strs) where x.contains(secret) { leaks.append("\(n) long=\(long) \(label): \(x)") }
                }
            }
        }
        #expect(leaks.isEmpty, "隐私模式下泄漏了 \(leaks.count) 处：\(Set(leaks).sorted().prefix(8))")
    }

    // MARK: SAN-01 像素字审计钩子：withDraws 返回时和别的线程里晚到的 append 竞争（最后一次 ASan 测试抓到 heap-use-after-free）

    /// `withDraws` 在 `setAuditSink(nil)` 之后直接读 `box.value`，而别的线程里「已经取到 sink、还没 append 完」的那次 draw 会在锁里改同一个数组：
    /// 数据竞争，读到的数组缓冲区可能已经被 append 换掉 / 释放。审计打开的那一小段时间里，并行跑的其它线程的像素字也会被收进来（文档写明过），所以这个窗口是真的。
    /// 这条测试在普通运行下多半不红（窗口很窄），要在 ASan / TSan 下才能确定地抓到（QA/tools/asan_tests.sh、tsan_run.sh 跑它；证据在 QA/evidence/fail-before-review.md）。
    @Test("SAN-01 withDraws 返回的是一份稳定的拷贝：别的线程一直在画像素字时，反复收集并逐条读像素，不崩、不读到释放过的内存；自己画的那一条一条不少")
    func san01_withDrawsIsSafeWhileOtherThreadsKeepDrawingPixelText() {
        var pal = MasterPalette()
        let ink = UInt8(pal.add("ink", RGBA8(255, 255, 255)))
        let style = Resolved(map: nil, lutA: PaletteLUT.identity(pal))
        let stop = StopFlag()
        let finished = DispatchSemaphore(value: 0)
        let workers = 4
        for _ in 0..<workers {
            Thread {
                let c = Canvas(width: 64, height: 12)
                while !stop.isSet {
                    PixelFont.tiny.draw("0123456789", x: 1, y: 1, value: ink, style: style, on: c)
                    sched_yield()                                                                  // 让出 CPU：机器忙时不要 4 个核空转（R4b P3）
                }
                finished.signal()
            }.start()
        }
        let mine = Canvas(width: 64, height: 12)
        var pixels = 0, missing = 0
        for _ in 0..<4000 {
            let (_, draws) = TextAuditRunner.withDraws { PixelFont.tiny.draw("12:34", x: 1, y: 1, value: ink, style: style, on: mine) }
            var own = 0
            for d in draws { pixels += d.pixels.count + d.text.count; if d.canvasID == ObjectIdentifier(mine) { own += 1 } }
            if own != 1 { missing += 1 }
        }
        stop.set()
        for _ in 0..<workers { finished.wait() }
        #expect(missing == 0, "\(missing) 次收集里自己画的那一条不是恰好一条")
        #expect(pixels > 0)
    }
}
