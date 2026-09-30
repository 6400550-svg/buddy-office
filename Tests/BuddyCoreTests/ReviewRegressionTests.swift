import Foundation
import Testing
@testable import BuddyCore

// 收尾前的独立复查（QA/review-R1a.md 等）新发现的问题的回归测试。编号对应 QA/issues-review.md。

extension StateRuleTests {

    /// R1a-01：busy 而且 quiet（10 分钟没有任何新数据：长命令 / 卡住的会话 / 合盖睡眠醒来）的会话，引擎给出的 `nextWake`
    /// 不能停在过去——否则 `SessionStore.arm` 里 `max(0.005, w − now)` 变成 5 ms，ingest 队列每秒空转一百多次（实测 ~140 次 / 秒，CPU 2.7%，
    /// 定时器 200 Hz 唤醒也让整机进不了低功耗）。`nextWake` 的定义是「没有新信号时最早什么时候要再 poll」，过去的时间没有意义。
    @Test("R1a-01 busy 又 quiet 的会话：nextWake 要么没有、要么在现在之后（不能让 SessionStore 5 ms 一次空转）")
    func r1a01_quietBusySessionNeverAsksForAnImmediateRepoll() {
        let (h, f) = K.idleSession()
        K.startTurn(h, f)
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 9999"); h.poll()
        let growth = K.secs(h)
        // 还没 quiet 时：最迟要在「变 quiet 的那一刻」（最后一次增长 + 10 分钟）醒来，不然 quiet 会晚一个心跳才亮
        K.goto(h, growth + 300); h.poll()
        let before = h.lastOutput?.nextWake
        #expect(before != nil && before! > h.now && before!.timeIntervalSince(Harness.epoch) <= growth + 600 + 0.5, "变 quiet 之前要有一个不晚于那一刻的唤醒：\(String(describing: before))")
        for dt in [599.0, 601, 602, 700, 1200, 3600, 7200] {
            K.goto(h, growth + dt); h.poll()
            let wake = h.lastOutput?.nextWake
            #expect(h.snap(key)?.quiet == (dt > 600), "dt=\(dt) 的 quiet 判断不对")
            #expect(wake == nil || wake! > h.now, "dt=\(dt)：nextWake 在过去 \(wake.map { h.now.timeIntervalSince($0) } ?? 0) 秒（quiet=\(String(describing: h.snap(key)?.quiet))）")
        }
    }

    /// 随机时间线（合法数据）：无论会话在什么状态，`nextWake` 都必须在现在之后（或者没有）。
    @Test("R1a-01 不变量：会话在 busy / quiet / 等待 / 做完 / 打盹……任何时刻，nextWake 都不在过去")
    func r1a01_nextWakeIsNeverInThePastOnATimeline() {
        let (h, f) = K.idleSession()
        var bad: [String] = []
        func check(_ tag: String) {
            if let w = h.lastOutput?.nextWake, w <= h.now { bad.append("\(tag)：nextWake 在过去 \(h.now.timeIntervalSince(w)) 秒") }
        }
        K.startTurn(h, f); check("开始一轮")
        for s in [1.0, 5, 20, 100, 400, 601, 900, 4000] { h.advance(s); h.poll(); check("忙 +\(s)") }
        h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now); h.poll(); check("做完")
        for s in [0.3, 1, 5, 30, 300, 700, 3000] { h.advance(s); h.poll(); check("空闲 +\(s)") }
        #expect(bad.isEmpty, "\(bad)")
    }
}

// MARK: - R1a-03(c) 阈值没被钉住：hook 掉线判据的 15 秒

extension StateRuleTests {
    /// DESIGN §13：会话记录比 hook 的最后一个事件领先超过 15 秒，就当作 hook 掉线（用户中途卸掉了 ccmon：hook 安静、会话记录还在长）。
    /// 变异测试（把 15 改成 16）原来存活——没有任何测试卡在这个边界上。
    @Test("R1a-03 hook 掉线判据恰好是「会话记录比 hook 的最后一个事件领先超过 15 秒」：14.9 秒还算在工作，15.1 秒算掉线")
    func r1a03_hookDropoutBoundaryIsFifteenSeconds() {
        #expect(SessionEngine.hookDropoutGap == 15)
        for (lead, active) in [(1.0, true), (14.0, true), (14.9, true), (15.1, false), (30.0, false), (300.0, false)] {
            let (h, f) = K.idleSession()
            K.startTurn(h, f)
            h.advance(1)
            let x = h.now
            h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/a", at: x); h.poll()
            #expect(h.snap(key)?.hookActive == true, "领先 0 秒时 hook 当然在工作")
            h.advance(lead + 0.05)
            h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: x.addingTimeInterval(lead), messageId: "d\(lead)", block: TL.text("…"), stopReason: "tool_use")])
            h.poll()
            #expect(h.snap(key)?.hookActive == active, "会话记录比 hook 最后一个事件领先 \(lead) 秒：hookActive 应为 \(active)")
        }
    }
}

// MARK: - R3a P2-2 桌面元数据里的未来时间戳（和 hook / 会话记录 / identities 一样夹到「现在」）

extension StateRuleTests {
    /// 一个远在未来的 `lastFocusedAt`（桌面 App 的时钟被拨快过 / 坏数据）让 `f > e → unread = false` 恒成立：「未读」永远不亮。
    @Test("R3a P2-2 桌面元数据的 lastFocusedAt 在 30 天以后：未读照样亮（和「一小时前」一样），不能让「未读」永远不亮", arguments: [false, true])
    func r3aP22_aFutureLastFocusedAtDoesNotSuppressUnread(future: Bool) {
        let (h, f) = K.idleSession()
        var m = FakeClaudeTree.Meta(host: DesktopFixture.host, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastFocusedAt = future ? h.now.addingTimeInterval(86400 * 30) : h.now.addingTimeInterval(-3600)
        h.tree.writeMeta(m)
        h.poll()
        K.startTurn(h, f)
        h.advance(2)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "e1", block: TL.text("done"), stopReason: "end_turn")])
        h.tree.hook(f.sid, "Stop")
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now)
        h.poll(); h.advance(1); h.poll(); h.advance(6); h.poll()
        #expect(h.snap(K.key)?.unread == true, "lastFocusedAt \(future ? "在 30 天以后" : "在一小时前")：一轮做完之后应该是未读")
    }

    /// 一个未来的 `lastActivityAt` 让下班工位里的幽灵座位排第一、超过 12 小时也不走（别的候选都按 12 小时到期移走了）。
    @Test("R3a P2-2 桌面元数据的 lastActivityAt 在 30 天以后：只当作「刚刚」，下班工位照常在 12 小时后到期，不会永远占着座位")
    func r3aP22_aFutureLastActivityAtDoesNotPinADormantSeatForever() {
        let h = Harness()
        let names = (0..<5).map { String(format: "local_22222222-0000-4000-8000-%012d", $0) }
        for (i, n) in names.enumerated() {
            let last = i == 0 ? h.now.addingTimeInterval(86400 * 30) : h.now.addingTimeInterval(-Double(i) * 600)
            h.tree.writeMeta(FakeClaudeTree.Meta(host: n, cliSessionId: String(format: "bbbbbbbb-0000-4000-8000-%012d", i), lastActivityAt: last))
        }
        h.poll()
        #expect(h.snapshots.count == 4, "下班工位最多 4 个：\(h.snapshots.map { $0.key.suffix(3) })")
        h.advance(13 * 3600); h.poll()
        #expect(h.snapshots.isEmpty, "13 小时之后所有下班工位（包括那个时间在未来的）都该到期移走：\(h.snapshots.map { $0.key.suffix(3) })")
    }
}
