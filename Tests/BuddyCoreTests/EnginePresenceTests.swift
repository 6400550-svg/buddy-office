import Foundation
import Testing
@testable import BuddyCore

/// 在场 / 离场 / 下班工位 / 身份 / 工位 / 标题 / token。
@Suite struct EnginePresenceTests {
    let key = DesktopFixture.key

    func fixture(_ h: Harness, n: Int, desktop: Bool = true, startedAgo: TimeInterval = 600) -> (DesktopFixture, String) {
        let sid = String(format: "aaaaaaaa-0000-4000-8000-%012d", n)
        let host = String(format: "local_11111111-0000-4000-8000-%012d", n)
        let f = DesktopFixture(h: h, pid: Int32(1000 + n), sid: sid, host: desktop ? host : "", name: "会话\(n)", startedAgo: startedAgo)
        if desktop { return (f, "d:" + host) }
        let session = FakeClaudeTree.Session(pid: Int32(1000 + n), sessionId: sid, host: nil, name: "会话\(n)", startedAt: h.now.addingTimeInterval(-startedAgo))
        return (DesktopFixture(session: session), "t:" + sid)
    }

    func meta(_ h: Harness, _ f: DesktopFixture, ago: TimeInterval = 60, archived: Bool = false) {
        var m = FakeClaudeTree.Meta(host: f.session.host ?? "local_x", cliSessionId: f.sid, lastActivityAt: h.now.addingTimeInterval(-ago))
        m.archived = archived
        h.tree.writeMeta(m)
    }

    // MARK: 进场 / 离场

    @Test func sessionsPresentAtLaunchSitDownDirectlyAndLaterOnesWalkIn() {
        let h = Harness()
        let (a, ka) = fixture(h, n: 1)
        h.tree.writeRegistry(a.session, status: "idle"); h.poll()
        #expect(h.snap(ka)?.appearedAfterLaunch == false)
        #expect(h.kinds(ka) == [.arrived(freshAfterLaunch: false)])
        let (b, kb) = fixture(h, n: 2)
        h.advance(5); h.tree.writeRegistry(b.session, status: "idle"); h.poll()
        #expect(h.snap(kb)?.appearedAfterLaunch == true)
        #expect(h.kinds(kb) == [.arrived(freshAfterLaunch: true)])
        #expect(h.snapshots.map { $0.seat } == [0, 1])
    }

    @Test func departureIsDebouncedBy3SecondsAndComingBackCancelsIt() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll(); h.clearEvents()
        // 桌面 App 重启：登记文件消失一会儿，带着同一个 host id 回来
        h.tree.endProcess(pid: f.session.pid)
        h.advance(1); h.poll()
        #expect(h.snap(k)?.presence == .present)
        h.advance(1.5); h.poll()
        #expect(h.snap(k)?.presence == .present)
        let back = FakeClaudeTree.Session(pid: 2001, sessionId: f.sid, host: f.session.host, name: "会话1", startedAt: h.now)
        h.tree.writeRegistry(back, status: "idle"); h.poll()
        h.run(for: 5)
        #expect(h.snap(k)?.presence == .present)
        #expect(h.kinds(k).isEmpty)                                                 // 没有离场，也没有再次进场
        #expect(h.snapshots.count == 1)
    }

    @Test func aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        meta(h, f)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        let before = h.snap(k)!
        h.clearEvents()
        h.tree.endProcess(pid: f.session.pid)
        h.run(for: 3.2)
        guard case .away(_, let dormant)? = h.snap(k)?.presence else { Issue.record("应该离场了"); return }
        #expect(dormant)
        #expect(h.kinds(k) == [.departed(dormant: true)])
        #expect(h.snap(k)?.seat == before.seat)                                       // 下班工位：座位还占着
        expectActivity(h.snap(k), .idle)
        #expect(h.snap(k)?.title == "会话1")
        // 桌面 App 回收了进程；用户再打开这个会话：新进程、新 sessionId、同一个 host
        h.advance(60)
        let again = FakeClaudeTree.Session(pid: 3001, sessionId: "bbbbbbbb-0000-4000-8000-000000000001", host: f.session.host, name: "会话1", startedAt: h.now)
        h.tree.writeRegistry(again, status: "idle"); h.poll()
        let after = h.snap(k)!
        #expect(after.presence == .present)
        #expect(after.seat == before.seat && after.salt == before.salt)               // 走回原来的工位，还是同一个人
        #expect(after.appearedAfterLaunch == true)
        #expect(h.kinds(k).last == .arrived(freshAfterLaunch: true))
        #expect(h.snapshots.count == 1)
    }

    @Test func aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves() {
        let h = Harness()
        let (t, kt) = fixture(h, n: 1, desktop: false)            // 终端会话
        let (d, kd) = fixture(h, n: 2)                             // 桌面会话，但元数据已归档
        meta(h, d, archived: true)
        h.tree.writeRegistry(t.session, status: "idle")
        h.tree.writeRegistry(d.session, status: "idle")
        h.poll(); h.clearEvents()
        h.tree.endProcess(pid: t.session.pid); h.tree.endProcess(pid: d.session.pid)
        h.run(for: 3.2)
        for k in [kt, kd] {
            guard case .away(_, let dormant)? = h.snap(k)?.presence else { Issue.record("\(k) 应该离场"); continue }
            #expect(!dormant)
            #expect(h.kinds(k) == [.departed(dormant: false)])
        }
        h.run(for: 8.2)                                             // 8 秒后收回工位
        #expect(h.snapshots.isEmpty)
    }

    @Test func aFreedSeatIsReusedByTheNextNewcomer() {
        let h = Harness()
        let (a, _) = fixture(h, n: 1, desktop: false)
        let (b, kb) = fixture(h, n: 2, desktop: false)
        h.tree.writeRegistry(a.session, status: "idle"); h.tree.writeRegistry(b.session, status: "idle"); h.poll()
        #expect(h.snapshots.map { $0.seat } == [0, 1])
        h.tree.endProcess(pid: a.session.pid)
        h.run(for: 12)                                              // 离场 + 收回工位
        #expect(h.snapshots.map { $0.key } == [kb])
        let (c, kc) = fixture(h, n: 3, desktop: false)
        h.tree.writeRegistry(c.session, status: "idle"); h.poll()
        #expect(h.snap(kc)?.seat == 0)                              // 编号最小的空位
        #expect(h.snap(kb)?.seat == 1)                              // 有人坐的工位永远不移动
    }

    @Test func aSeatHeldByADormantBuddyIsNotGivenToNewcomers() {
        let h = Harness()
        let (a, ka) = fixture(h, n: 1)
        meta(h, a)
        h.tree.writeRegistry(a.session, status: "idle"); h.poll()
        h.tree.endProcess(pid: a.session.pid); h.run(for: 3.2)
        let (b, kb) = fixture(h, n: 2, desktop: false)
        h.tree.writeRegistry(b.session, status: "idle"); h.poll()
        #expect(h.snap(ka)?.seat == 0)
        #expect(h.snap(kb)?.seat == 1)
    }

    @Test func pidReuseIsTreatedAsTheOldProcessBeingGone() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1, desktop: false)
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        #expect(h.snap(k)?.presence == .present)
        // 登记文件还在、pid 也还活着，但启动时间和 procStart 差了 10 秒：这个 pid 已经是别的进程了
        h.probe.setAlive(f.session.pid, start: f.session.startedAt.addingTimeInterval(10))
        h.run(for: 5)                                                    // 存活检查每 1 秒一次 + 离场防抖 3 秒
        guard case .away? = h.snap(k)?.presence else { Issue.record("PID 被复用应该算离场"); return }
        // 差 1.5 秒（在 2 秒容差内）不算复用
        let (g, kg) = fixture(h, n: 5, desktop: false)
        h.tree.writeRegistry(g.session, status: "busy")
        h.probe.setAlive(g.session.pid, start: g.session.startedAt.addingTimeInterval(1.5))
        h.run(for: 5)
        #expect(h.snap(kg)?.presence == .present)
    }

    @Test func unknownProbeStateMeansAlive() {
        // 沙箱里 sysctl 可能失败：结果算"未知"，当作还活着
        let h = Harness()
        let (f, k) = fixture(h, n: 1, desktop: false)
        h.tree.writeRegistry(f.session, status: "busy", markAlive: false)
        h.probe.setUnknown(f.session.pid)
        h.poll(); h.run(for: 10)
        #expect(h.snap(k)?.presence == .present)
    }

    @Test func aDeadPidWithALeftoverRegistryFileIsGone() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1, desktop: false)
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        h.probe.kill(f.session.pid)                                      // 文件还在，进程没了（App 被 kill -9）
        h.run(for: 5)
        guard case .away? = h.snap(k)?.presence else { Issue.record("进程死了应该离场"); return }
    }

    @Test func nonInteractiveSessionsNeverBecomeGhostColleagues() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        h.tree.writeRegistry(f.session, status: "busy")
        let job = FakeClaudeTree.Session(pid: 5000, sessionId: "jjjjjjjj-0000-4000-8000-000000000000", host: nil, startedAt: h.now)
        for (i, kind) in ["background", "job", "sdk", "spare", "worker"].enumerated() {
            var s = job; s.pid = Int32(5000 + i)
            h.tree.writeRegistry(s, status: "busy", extra: ["kind": kind])
        }
        h.poll()
        #expect(h.snapshots.map { $0.key } == [k])
    }

    @Test func twoRegistryFilesForTheSameSessionMakeOneBuddy() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        h.tree.writeRegistry(f.session, status: "idle")
        var newer = f.session; newer.pid = 7777; newer.startedAt = h.now.addingTimeInterval(-10)
        h.tree.writeRegistry(newer, status: "busy")
        h.poll()
        #expect(h.snapshots.count == 1)
        #expect(h.snap(k)?.pid == 7777)                                   // 取后启动的那个
    }

    // MARK: 启动时的下班工位

    @Test func dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions() {
        let h = Harness()
        // 6 个最近 3 小时内活跃的、1 个 3 小时前的、1 个归档的
        for n in 1...6 { let (f, _) = fixture(h, n: n); meta(h, f, ago: Double(n) * 600) }        // 10, 20, …, 60 分钟前
        let (old, _) = fixture(h, n: 7); meta(h, old, ago: 3 * 3600 + 60)
        let (arch, _) = fixture(h, n: 8); meta(h, arch, ago: 60, archived: true)
        h.poll()
        #expect(h.snapshots.count == 4)                                                           // 最多保留 4 个
        #expect(Set(h.snapshots.map { $0.key }) == Set((1...4).map { String(format: "d:local_11111111-0000-4000-8000-%012d", $0) }))   // 最近活动的 4 个
        for s in h.snapshots {
            guard case .away(_, true) = s.presence else { Issue.record("\(s.key) 应该是下班工位"); continue }
            #expect(s.appearedAfterLaunch == false)
        }
        #expect(h.snapshots.map { $0.seat } == [0, 1, 2, 3])
        #expect(h.events.isEmpty)                                                                 // 启动时的下班工位不发事件
    }

    @Test func aLiveSessionIsNotAlsoADormantSeat() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1); meta(h, f)
        let (g, kg) = fixture(h, n: 2); meta(h, g)
        h.tree.writeRegistry(f.session, status: "busy")
        h.poll()
        #expect(h.snapshots.count == 2)
        #expect(h.snap(k)?.presence == .present)
        guard case .away(_, true)? = h.snap(kg)?.presence else { Issue.record("g 应该是下班工位"); return }
    }

    @Test func dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted() {
        let h = Harness()
        let (a, ka) = fixture(h, n: 1); meta(h, a, ago: 60)
        let (b, kb) = fixture(h, n: 2); meta(h, b, ago: 60)
        let (c, kc) = fixture(h, n: 3); meta(h, c, ago: 60)
        h.poll()
        #expect(h.snapshots.count == 3)
        // b 被归档，c 被删除
        meta(h, b, ago: 60, archived: true)
        h.tree.removeMeta(host: c.session.host!)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snapshots.map { $0.key } == [ka])
        _ = (kb, kc)
        // a 满 12 小时
        h.advance(11 * 3600); h.poll()
        #expect(h.snapshots.map { $0.key } == [ka])
        h.advance(3600); h.poll()
        #expect(h.snapshots.isEmpty)
    }

    @Test func departedSessionsCompeteForTheFourDormantSeats() {
        let h = Harness()
        var fs: [(DesktopFixture, String)] = []
        for n in 1...6 {
            let (f, k) = fixture(h, n: n)
            meta(h, f, ago: 100 - Double(n))
            h.tree.writeRegistry(f.session, status: "idle")
            fs.append((f, k))
        }
        h.poll()
        #expect(h.snapshots.count == 6)
        for (i, (f, _)) in fs.enumerated() {                           // 依次离场（先走的活动更早）
            h.advance(2)
            meta(h, f, ago: 0)
            h.tree.endProcess(pid: f.session.pid)
            _ = i
        }
        h.run(for: 4)
        let dormant = h.snapshots.filter { if case .away(_, true) = $0.presence { return true } else { return false } }
        #expect(dormant.count == 4)
        #expect(h.snapshots.count == 4)                                // 超出的（最久没活动的）被移走
    }

    // MARK: 身份（引擎里的完整流程）

    @Test func terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles() {
        let h = Harness(tokens: true)
        let (f, k) = fixture(h, n: 1, desktop: false)
        let s1 = f.sid
        let s2 = "cccccccc-0000-4000-8000-00000000000a"
        h.tree.appendTranscript(s1, [TL.assistant(sessionId: s1, at: h.now, messageId: "a1", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 1000))])
        h.tree.hook(s1, "UserPromptSubmit")
        h.tree.hook(s1, "PreToolUse", tool: "Bash", detail: "old session tool")
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        guard case .tool(let c, 1)? = h.snap(k)?.activity, c.detail == "old session tool" else { Issue.record("先要有旧会话的工具"); return }
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60); h.advance(0.2); h.poll()
        #expect(h.snap(k)?.tokens.output == 1000)
        let seat = h.snap(k)!.seat, salt = h.snap(k)!.salt
        // /clear：同一个进程（pid 和启动时间不变），登记表里的 sessionId 换了
        h.advance(5)
        h.tree.appendTranscript(s2, [TL.assistant(sessionId: s2, at: h.now, messageId: "b1", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 7))])
        h.tree.hook(s2, "SessionStart", extra: "clear")
        var cleared = f.session; cleared.sessionId = s2
        h.tree.writeRegistry(cleared, status: "idle"); h.poll()
        let s = h.snap(k)
        #expect(h.snapshots.count == 1)                                  // 还是同一个 buddy
        #expect(s?.sessionId == s2)
        #expect(s?.seat == seat && s?.salt == salt)
        #expect(s?.phase == .idle)                                       // 旧会话的工具没有带过来
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60); h.advance(0.2); h.poll()
        #expect(h.snap(k)?.tokens.output == 7)                           // 终端会话只算当前的 sessionId
        #expect(!h.kinds(k).contains { if case .departed = $0 { return true } else { return false } })
    }

    @Test func terminalResumeInANewProcessGivesTheSameBuddyBack() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1, desktop: false)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        let before = h.snap(k)!
        h.tree.endProcess(pid: f.session.pid)
        h.run(for: 12)                                                    // 离场并收回工位
        #expect(h.snapshots.isEmpty)
        let resumed = FakeClaudeTree.Session(pid: 4321, sessionId: f.sid, host: nil, name: "会话1", startedAt: h.now)
        h.tree.writeRegistry(resumed, status: "idle"); h.poll()
        #expect(h.only()?.key == k)                                        // key 还是第一次见到的 sessionId
        #expect(h.only()?.seat == before.seat)
        #expect(h.only()?.salt == before.salt)
    }

    @Test func identitiesAndAppearanceSurviveARestart() {
        let h1 = Harness(persist: true)
        let (a, ka) = fixture(h1, n: 1, desktop: false)
        let (b, kb) = fixture(h1, n: 2)
        h1.tree.writeRegistry(a.session, status: "idle"); h1.tree.writeRegistry(b.session, status: "idle"); h1.poll()
        h1.engine.rerollAppearance(key: kb)
        h1.poll()
        let seatB = h1.snap(kb)!.seat
        #expect(h1.snap(kb)?.salt == 1)
        h1.engine.flush()
        // 重启（新引擎，同一个数据目录）
        var o = SessionEngine.Options(paths: h1.tree.paths, now: { [clock = h1.clock] in clock.now() }, probe: h1.probe)
        o.ledgerQueue = testLedgerQueue()
        o.persist = true; o.scanTokens = false
        let e2 = SessionEngine(options: o)
        let out = e2.poll()
        let sb = out.snapshots.first { $0.key == kb }
        #expect(sb?.salt == 1)                                              // 「换个造型」的新盐保存下来了
        #expect(sb?.seat == seatB || out.snapshots.count == 2)             // 启动时压缩空位，相对顺序不变
        #expect(out.snapshots.map { $0.seat } == [0, 1])
        #expect(out.snapshots.first?.key == ka || seatB == 0)
    }

    @Test func seatsAreCompactedAtStartup() {
        let h1 = Harness(persist: true)
        var sessions: [(DesktopFixture, String)] = []
        for n in 1...4 { let (f, k) = fixture(h1, n: n, desktop: false); h1.tree.writeRegistry(f.session, status: "idle"); sessions.append((f, k)) }
        h1.poll()
        #expect(h1.snapshots.map { $0.seat } == [0, 1, 2, 3])
        h1.engine.flush()
        // 2 号和 3 号在两次运行之间退出了
        h1.tree.endProcess(pid: sessions[1].0.session.pid); h1.tree.endProcess(pid: sessions[2].0.session.pid)
        var o = SessionEngine.Options(paths: h1.tree.paths, now: { [clock = h1.clock] in clock.now() }, probe: h1.probe)
        o.ledgerQueue = testLedgerQueue()
        o.persist = true; o.scanTokens = false
        let out = SessionEngine(options: o).poll()
        #expect(out.snapshots.map { $0.key } == [sessions[0].1, sessions[3].1])     // 相对顺序不变
        #expect(out.snapshots.map { $0.seat } == [0, 1])                             // 空位被压缩了
    }

    @Test func unwritableDataDirectoryDoesNotCrashAndIsReportedInDiagnostics() {
        let h = Harness(persist: true, tokens: true)
        // 沙箱里写不了 ~/Library/Application Support/BuddyOffice：用一个同名的普通文件模拟"建不了目录"
        try? FileManager.default.createDirectory(atPath: (h.tree.paths.appSupportDir as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(h.tree.paths.appSupportDir, Data("blocker".utf8))
        let (f, k) = fixture(h, n: 1)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 5))])
        h.tree.writeRegistry(f.session, status: "busy"); h.poll()
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60)
        h.advance(1); h.poll()
        h.engine.flush()
        #expect(h.snap(k)?.tokens.output == 5)                                        // 只在内存里，照常工作
        let d = h.engine.diagnostics()
        #expect(d.sourceStatus.contains { $0.contains("写不了磁盘") })
    }

    // MARK: 标题 / 字段

    @Test func titlePrecedenceChain() {
        let h = Harness()
        let sid = "abcdef12-0000-4000-8000-000000000001"
        var s = FakeClaudeTree.Session(pid: 1, sessionId: sid, host: "local_t", name: nil, startedAt: h.now.addingTimeInterval(-100))
        s.cwd = "/Users/x/项目文件夹"
        let k = "d:local_t"
        // 6. 什么都没有 → cwd 文件夹名
        h.tree.writeRegistry(s, status: "idle"); h.poll()
        #expect(h.snap(k)?.title == "项目文件夹")
        // 5. ai-title
        h.tree.appendTranscript(sid, [["type": "ai-title", "aiTitle": "AI 标题", "sessionId": sid]])
        h.advance(1); h.poll(); h.advance(1.1); h.poll()
        #expect(h.snap(k)?.title == "AI 标题")
        // 4. custom-title 比 ai-title 优先
        h.tree.appendTranscript(sid, [TL.customTitle(sessionId: sid, "自定义标题")])
        h.advance(1); h.poll()
        #expect(h.snap(k)?.title == "自定义标题")
        // 3. 桌面元数据的 title 比 custom-title 优先
        var m = FakeClaudeTree.Meta(host: "local_t", cliSessionId: sid, lastActivityAt: h.now)
        m.title = "桌面标题"
        h.tree.writeMeta(m)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(k)?.title == "桌面标题")
        // 2. 登记表的 name 最优先
        s.name = "登记表的名字"
        h.tree.writeRegistry(s, status: "idle"); h.advance(1); h.poll()
        #expect(h.snap(k)?.title == "登记表的名字")
    }

    @Test func titleFallsBackToSessionIdPrefixWhenNothingElseExists() {
        let h = Harness()
        let s = FakeClaudeTree.Session(pid: 1, sessionId: "abcdef12-0000-4000-8000-000000000001", host: nil, startedAt: h.now)
        var noCwd = s; noCwd.cwd = ""
        h.tree.writeRegistry(noCwd, status: "idle", extra: ["cwd": ""])
        h.poll()
        #expect(h.only()?.title == "会话 abcdef12")
    }

    @Test func customTitleJsonInTheSessionDirectoryIsUsed() {
        let h = Harness()
        let sid = "abcdef12-0000-4000-8000-000000000002"
        let s = FakeClaudeTree.Session(pid: 1, sessionId: sid, host: nil, startedAt: h.now)
        h.tree.appendTranscript(sid, [TL.userPrompt(sessionId: sid, at: h.now)])
        let dir = h.tree.paths.projectsDir + "/" + h.tree.projectDir + "/" + sid
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FakeClaudeTree.writeInPlace(dir + "/custom-title.json", Data(#"{"customTitle":"来自 custom-title.json"}"#.utf8))
        h.tree.writeRegistry(s, status: "idle"); h.poll()
        #expect(h.only()?.title == "来自 custom-title.json")
    }

    @Test func snapshotCarriesTheDescriptiveFields() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.model = "claude-sonnet-5-5"; m.effort = "max"; m.permissionMode = "bypassPermissions"
        h.tree.writeMeta(m)
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "m", block: TL.text(), stopReason: "end_turn", model: "glm-5.3",
                                                     usage: TL.usage(input: 10, output: 5, cacheWrite: 100, cacheRead: 1000))])
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        let s = h.snap(k)!
        #expect(s.origin == .desktop)
        #expect(s.modelFamily == .glm)
        #expect(s.modelName == "glm-5.3")
        #expect(s.effort == "max")
        #expect(s.permissionMode == "bypassPermissions")
        #expect(s.cliVersion == "2.1.284")
        #expect(s.pid == 1001)
        #expect(s.hostSessionId == f.session.host)
        #expect(s.cwd == "/fake/project")
        #expect(s.projectName == "project")
        #expect(s.contextTokens == 1110)
        #expect(s.sessionStartedAt != nil)
        #expect(SessionEngine.modelFamily("deepseek-v4-pro") == .deepseek)
        #expect(SessionEngine.modelFamily("claude-opus-5-5") == .claude)
        #expect(SessionEngine.modelFamily("gpt-x") == .other)
        #expect(SessionEngine.modelFamily(nil) == .claude)
    }

    @Test func entrypointsMapToOrigins() {
        let h = Harness()
        for (i, e) in ["claude-desktop", "claude-desktop-3p", "local-agent", "claude-vscode", "cli"].enumerated() {
            let sid = String(format: "aaaaaaaa-0000-4000-8000-%012d", 100 + i)
            let s = FakeClaudeTree.Session(pid: Int32(2000 + i), sessionId: sid, host: nil, startedAt: h.now, entrypoint: e)
            h.tree.writeRegistry(s, status: "idle")
        }
        h.poll()
        let byPid = Dictionary(uniqueKeysWithValues: h.snapshots.map { ($0.pid!, $0.origin) })
        #expect(byPid[2000] == .desktop && byPid[2001] == .desktop && byPid[2002] == .desktop)
        #expect(byPid[2003] == .vscode)
        #expect(byPid[2004] == .terminal)
    }

    // MARK: 未读 / blocked

    @Test func focusingTheSessionInTheDesktopAppClearsUnread() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastFocusedAt = h.now.addingTimeInterval(-100)
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        h.advance(1); h.tree.writeRegistry(f.session, status: "busy"); h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
        h.advance(3); h.tree.hook(f.sid, "Stop"); h.poll()
        #expect(h.snap(k)?.unread == true)
        h.advance(2)
        m.lastFocusedAt = h.now                                             // 用户切到了这个会话
        h.tree.writeMeta(m)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(k)?.unread == false)
    }

    @Test func blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastAssistantUuid = "uuid-1"
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        h.advance(1); h.tree.writeRegistry(f.session, status: "busy"); h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
        h.advance(3)
        m.lastAssistantUuid = "uuid-2"
        h.tree.writeMeta(m)
        h.tree.hook(f.sid, "Stop"); h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        #expect(h.snap(k)?.blocked == false)                                 // 总结还没生成
        // 大约 7 秒后桌面 App 写入本轮总结：blocked
        h.advance(7)
        m.summaryFor = "uuid-2"; m.summaryCategory = "blocked"; m.summaryDetail = "needs your confirmation"
        h.tree.writeMeta(m)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(k)?.blocked == true)
        #expect(h.snap(k)?.statusDetail == "needs your confirmation")
        #expect(h.kinds(k).filter { $0 == .blocked }.count == 1)
        h.advance(60 * 30); h.poll()
        #expect(h.snap(k)?.blocked == true)                                  // 保持到下一轮开始
        // 下一轮开始：清掉；即使元数据里还是旧总结
        h.advance(1); h.tree.writeRegistry(f.session, status: "busy"); h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
        #expect(h.snap(k)?.blocked == false)
        #expect(h.snap(k)?.statusDetail == nil)
        h.advance(2); h.poll()
        #expect(h.snap(k)?.blocked == false)
    }

    @Test func aSummaryForAnOlderAssistantMessageIsNotBlocked() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastAssistantUuid = "uuid-new"; m.summaryFor = "uuid-old"; m.summaryCategory = "blocked"
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        #expect(h.snap(k)?.blocked == false)
        #expect(h.snap(k)?.statusDetail == nil)
    }

    @Test func aBlockedSummaryAlreadyThereAtLaunchShowsBlocked() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1)
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.lastAssistantUuid = "u"; m.summaryFor = "u"; m.summaryCategory = "blocked"; m.summaryDetail = "waiting on you"
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle", statusUpdatedAt: h.now.addingTimeInterval(-1000)); h.poll()
        #expect(h.snap(k)?.blocked == true)
        #expect(h.snap(k)?.unread == false)
    }

    // MARK: token

    @Test func desktopTokensMergeThePriorCliSessionsAndSubagents() {
        let h = Harness(tokens: true)
        let (f, k) = fixture(h, n: 1)
        let prior = "bbbbbbbb-0000-4000-8000-0000000000aa"
        // 当前会话与 prior 会话各有记录，且有 1 条重叠的消息（resume 复制历史）；子代理再加一份
        func line(_ sid: String, _ id: String, _ out: Int, _ agent: String? = nil) -> [String: Any] {
            TL.assistant(sessionId: sid, at: h.now, messageId: id, block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: out), agentId: agent)
        }
        h.tree.appendTranscript(prior, [line(prior, "m1", 100), line(prior, "m2", 200)])
        h.tree.appendTranscript(f.sid, [line(f.sid, "m2", 200), line(f.sid, "m3", 300)])
        h.tree.appendSubagent(f.sid, agentId: "ag1", [line(f.sid, "s1", 40, "ag1")])
        var m = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        m.priors = [prior]
        h.tree.writeMeta(m)
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60)
        h.advance(1); h.poll(); h.advance(1); h.poll(); _ = h.engine.ledger?.waitUntilIdle(timeout: 60); h.poll()
        #expect(h.snap(k)?.tokens.output == 100 + 200 + 300 + 40)              // m2 只算一次
    }

    @Test func aTerminalSessionOnlyCountsItsCurrentSessionId() {
        let h = Harness(tokens: true)
        let (f, k) = fixture(h, n: 1, desktop: false)
        let other = "bbbbbbbb-0000-4000-8000-0000000000bb"
        h.tree.appendTranscript(other, [TL.assistant(sessionId: other, at: h.now, messageId: "x", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 9999))])
        h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "y", block: TL.text(), stopReason: "end_turn", usage: TL.usage(output: 11))])
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        _ = h.engine.ledger?.waitUntilIdle(timeout: 60)
        h.advance(1); h.poll(); h.advance(1); h.poll()
        #expect(h.snap(k)?.tokens.output == 11)
    }

    // MARK: hook 是否在工作 / 诊断

    @Test func hookActiveMeansAnEventNoOlderThanStartedAtMinus5Seconds() {
        let h = Harness()
        let (f, k) = fixture(h, n: 1, startedAgo: 600)
        h.tree.hook(f.sid, "SessionStart", extra: "startup", at: h.now.addingTimeInterval(-700))        // 上一次进程留下的旧事件
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        #expect(h.snap(k)?.hookActive == false)
        h.tree.hook(f.sid, "SessionStart", extra: "resume", at: h.now.addingTimeInterval(-604))         // startedAt − 4 s：算
        h.advance(0.2); h.poll()
        #expect(h.snap(k)?.hookActive == true)
    }

    @Test func diagnosticsReportSourcesAndPerSessionHookState() {
        let h = Harness()
        let (f, _) = fixture(h, n: 1)
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.tree.writeRegistry(f.session, status: "idle"); h.poll()
        let d = h.engine.diagnostics()
        #expect(d.liveSessionCount == 1)
        #expect(d.hookDetectedInSettings)
        #expect(d.lastHookEventAt != nil)
        #expect(d.sessions.count == 1 && d.sessions[0].hookActive && d.sessions[0].cliVersion == "2.1.284")
        #expect(d.sourceStatus.contains { $0.hasPrefix("登记表: 正常") })
        #expect(d.sourceStatus.contains { $0.hasPrefix("hook: 正常") })
    }

    @Test func aMissingSessionsDirectoryIsNotACrash() {
        let h = Harness()
        try? FileManager.default.removeItem(atPath: h.tree.paths.sessionsDir)
        h.poll()
        #expect(h.snapshots.isEmpty)
        #expect(h.engine.diagnostics().sourceStatus.contains { $0.contains("登记表: 目录读不了") })
    }

    @Test func snapshotsAreSortedBySeat() {
        let h = Harness()
        for n in [3, 1, 2] { let (f, _) = fixture(h, n: n, desktop: false); h.tree.writeRegistry(f.session, status: "idle") }
        h.poll()
        #expect(h.snapshots.map { $0.seat } == [0, 1, 2])
    }
}

extension DesktopFixture {
    init(session: FakeClaudeTree.Session) { self.session = session }
}
