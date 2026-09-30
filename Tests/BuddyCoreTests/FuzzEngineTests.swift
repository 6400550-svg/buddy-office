import Foundation
import Testing
@testable import BuddyCore

// QA · 整个引擎（登记表 + hook + 会话记录 + 子代理 + 桌面元数据 + 账本 + 身份文件）一起灌极端值、类型错误、天文数字、
// 乱序 / 未来 / 巨大跳跃的时间、被删被换的文件，看有没有崩溃、卡死、不合理的快照。放在和 ingest 队列一样小的栈上跑。

@Suite struct FuzzEngineTests {

    static func checkSnapshots(_ snaps: [BuddySnapshot], now: Date, _ label: String, _ r: FuzzReport) {
        r.check(Set(snaps.map { $0.key }).count == snaps.count, "\(label)：key 有重复")
        r.check(snaps.map { $0.seat }.enumerated().allSatisfy { i, s in i == 0 || s >= snaps[i - 1].seat }, "\(label)：没有按工位排序")
        for s in snaps {
            r.check(!s.key.isEmpty && !s.title.isEmpty, "\(label)：key / title 为空")
            r.check(s.title.count <= 2048 + 20, "\(label)：title 太长 \(s.title.count)")
            r.check(s.seat >= -1 && s.seat <= 9999, "\(label)：seat=\(s.seat)")
            let b = s.tokens
            r.check(b.input >= 0 && b.output >= 0 && b.cacheWrite >= 0 && b.cacheRead >= 0 && b.total >= 0, "\(label)：token 为负 \(b)")
            if let c = s.contextTokens { r.check(c >= 0, "\(label)：contextTokens 为负") }
            for d in [s.activitySince, s.turnStartedAt, s.lastTurnEndedAt, s.idleSince, s.sessionStartedAt].compactMap({ $0 }) {
                r.check(d.timeIntervalSince1970.isFinite, "\(label)：时间不是有限数")
            }
            if let t = s.turnStartedAt { r.check(t <= now.addingTimeInterval(0.001), "\(label)：本轮开始时间在未来") }
            r.check(s.helpers.allSatisfy { !$0.id.isEmpty && $0.description.count <= 2048 }, "\(label)：小助手字段不合理")
            if let d = s.lastTurnDuration { r.check(d.isFinite && d >= 0, "\(label)：lastTurnDuration=\(d)") }
        }
    }

    @Test("整个引擎：每个数据源都灌极端值 / 类型错误 / 深嵌套 / 超长行 / 乱序 + 未来的时间 / 被删被换的文件 / 进程反复死活，随时间大幅跳跃：不崩溃、不卡死、快照满足不变量，之后恢复正常")
    func engineSurvivesExtremeValuesEverywhere() {
        for seed in [0xE61E_0001, 0xE61E_0002, 0xE61E_0003] as [UInt64] {
            let finished = fuzzRun("engine chaos seed \(seed)", timeout: 240) { r in
                var rng = FuzzRNG(seed: seed)
                let h = Harness(persist: true, tokens: true)
                let f = DesktopFixture(h: h)
                let regPath = h.tree.paths.sessionsDir + "/1001.json"
                let metaPath = h.tree.metaDir + "/" + DesktopFixture.host + ".json"
                let regKeys = ["pid", "sessionId", "cwd", "startedAt", "procStart", "pidDomain", "version", "kind", "entrypoint", "hostSessionId", "name", "nameSource",
                               "nameSince", "status", "waitingFor", "updatedAt", "statusUpdatedAt"]
                let metaKeys = ["sessionId", "cliSessionId", "priorCliSessionIds", "cwd", "title", "model", "effort", "permissionMode", "isArchived", "createdAt",
                                "lastActivityAt", "lastFocusedAt", "completedTurns", "lastAssistantUuid", "postTurnSummary", "postTurnSummaryFor"]
                func timestampMs() -> String {
                    switch rng.int(0...5) {
                    case 0: return String(TimeUtil.millis(h.now))
                    case 1: return String(TimeUtil.millis(h.now.addingTimeInterval(Double(rng.int(-100_000...100_000)))))
                    case 2: return rng.pick(FuzzJSON.numbers)
                    case 3: return String(TimeUtil.millis(h.now.addingTimeInterval(86400 * 365)))                   // 未来一年
                    default: return String(TimeUtil.millis(h.now.addingTimeInterval(-Double(rng.int(0...5)))))
                    }
                }
                func isoTime() -> String {
                    rng.chance(0.75) ? TL.iso(h.now.addingTimeInterval(Double(rng.int(-50...5)))) : rng.pick(["0000-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "1970-01-01T00:00:00Z", "x", ""])
                }
                func validRegistry(status: String) {
                    h.tree.writeRegistry(f.session, status: status, waitingFor: status == "waiting" ? rng.pick(["permission prompt", "input needed"]) : nil, statusUpdatedAt: h.now)
                }
                validRegistry(status: "busy")
                h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)])
                h.tree.hook(f.sid, "UserPromptSubmit")
                h.poll()
                var polls = 0
                var stepsWithBuddy = 0
                var activityKinds = Set<String>()
                var bigJumpDone = false
                for round in 0..<500 {
                    switch rng.int(0...19) {
                    case 0, 1: validRegistry(status: rng.pick(["busy", "idle", "waiting"]))
                    case 2:      // 登记表：随机 JSON（pid / sessionId 大概率保持合法）
                        var text = FuzzJSON.object(&rng, known: regKeys, p: 0.7)
                        if rng.chance(0.6) { text = "{\"pid\":1001,\"sessionId\":\"\(f.sid)\",\"hostSessionId\":\"\(DesktopFixture.host)\",\"status\":\"\(rng.pick(["busy", "idle", "waiting", "x"]))\",\"statusUpdatedAt\":\(timestampMs()),\"startedAt\":\(timestampMs()),\"procStart\":\(rng.chance(0.5) ? "\"Tue Sep 29 03:23:08 2026\"" : FuzzJSON.value(&rng)),\"name\":\(FuzzJSON.value(&rng)),\"waitingFor\":\(FuzzJSON.value(&rng)),\"kind\":\(rng.chance(0.8) ? "\"interactive\"" : FuzzJSON.value(&rng))}" }
                        FakeClaudeTree.writeInPlace(regPath, Data(text.utf8))
                    case 3, 4:   // hook：合法 / 极端时间 / 随机对象 / 垃圾
                        let ev = rng.pick(["PreToolUse", "PostToolUse", "Stop", "UserPromptSubmit", "Notification", "SessionStart", "PreCompact", "PostCompact", "SubagentStop", "SessionEnd", "Weird"])
                        var line: String
                        switch rng.int(0...3) {
                        case 0: line = FuzzCorpus.hookLine(ts: TimeUtil.millis(h.now), ev: ev, tool: rng.pick(["Bash", "Read", "Agent", "AskUserQuestion", "ExitPlanMode", "mcp__x__y…", ""]), detail: rng.ascii(rng.int(0...30)), extra: rng.chance(0.3) ? "compact" : "")
                        case 1: line = "{\"ts\":\(timestampMs()),\"ev\":\"\(ev)\",\"tool\":\"Bash\",\"detail\":\(FuzzJSON.value(&rng)),\"extra\":\(FuzzJSON.value(&rng))}"
                        case 2: line = FuzzJSON.object(&rng, known: ["ts", "ev", "tool", "detail", "extra"], p: 0.8)
                        default: line = String(decoding: rng.bytes(rng.int(1...80)), as: UTF8.self)
                        }
                        h.tree.appendHook(f.sid, Data((line + "\n").utf8))
                    case 5, 6:   // 会话记录：合法行 / 极端字段 / 深嵌套 / 超长行
                        var line: String
                        let usage = FuzzJSON.object(&rng, known: ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "cache_creation"], p: 0.8)
                        switch rng.int(0...5) {
                        case 0: line = FuzzCorpus.jsonLine(FuzzCorpus.assistantLine(id: "m\(rng.int(0...30))", at: h.now, input: rng.int(0...1000), output: rng.int(0...1000), stop: rng.pick(["end_turn", "tool_use", nil])))
                        case 1: line = "{\"type\":\"assistant\",\"timestamp\":\"\(isoTime())\",\"message\":{\"id\":\"m\(rng.int(0...30))\",\"model\":\"claude-opus-5-5\",\"stop_reason\":\(FuzzJSON.value(&rng)),\"content\":[{\"type\":\"tool_use\",\"id\":\"t\(rng.int(0...9))\",\"name\":\"Bash\",\"input\":\(FuzzJSON.value(&rng))}],\"usage\":\(usage)}}\n"
                        case 2: line = "{\"type\":\"user\",\"timestamp\":\"\(isoTime())\",\"message\":{\"content\":\(FuzzJSON.value(&rng))}}\n"
                        case 3: line = "{\"type\":\"system\",\"subtype\":\"\(rng.pick(["api_error", "stop_hook_summary", "compact_boundary", "turn_duration", "x"]))\",\"timestamp\":\"\(isoTime())\",\"retryAttempt\":\(FuzzJSON.value(&rng)),\"maxRetries\":\(FuzzJSON.value(&rng)),\"retryInMs\":\(FuzzJSON.value(&rng)),\"durationMs\":\(FuzzJSON.value(&rng))}\n"
                        case 4: line = "{\"type\":\"assistant\",\"timestamp\":\"\(isoTime())\",\"message\":{\"id\":\"deep\",\"usage\":{\"output_tokens\":1},\"x\":\(FuzzCorpus.deepObject(rng.pick([50, 99, 101, 480, 600])))}}\n"
                        default: line = (rng.chance(0.05) ? String(repeating: "x", count: rng.pick([1 << 20, 4 << 20, (4 << 20) + 1])) : String(repeating: "y", count: rng.int(1...3000))) + "\n"
                        }
                        h.tree.appendTranscriptRaw(f.sid, Data(line.utf8))
                    case 7:      // 桌面元数据
                        var text = FuzzJSON.object(&rng, known: metaKeys, p: 0.7)
                        if rng.chance(0.6) { text = "{\"sessionId\":\"\(DesktopFixture.host)\",\"cliSessionId\":\"\(f.sid)\",\"priorCliSessionIds\":\(rng.chance(0.5) ? "[\"\(rng.ascii(8).replacingOccurrences(of: " ", with: "x"))\",\"\(f.sid)\"]" : FuzzJSON.value(&rng)),\"title\":\(FuzzJSON.value(&rng)),\"lastActivityAt\":\(timestampMs()),\"lastFocusedAt\":\(timestampMs()),\"isArchived\":\(FuzzJSON.value(&rng)),\"lastAssistantUuid\":\"u\(rng.int(0...3))\",\"postTurnSummaryFor\":\"u\(rng.int(0...3))\",\"postTurnSummary\":{\"status_category\":\(rng.chance(0.7) ? "\"blocked\"" : FuzzJSON.value(&rng)),\"status_detail\":\(FuzzJSON.value(&rng))}}" }
                        try? FileManager.default.createDirectory(atPath: h.tree.metaDir, withIntermediateDirectories: true)
                        FakeClaudeTree.writeInPlace(metaPath, Data(text.utf8))
                    case 8:      // 子代理：垃圾的 meta / 记录
                        let id = "zz\(rng.int(0...3))"
                        h.tree.writeSubagentMeta(f.sid, agentId: id, foreground: rng.chance(0.5))
                        if rng.chance(0.5) { FakeClaudeTree.writeInPlace(h.tree.subagentDir(f.sid) + "/agent-\(id).meta.json", Data(FuzzJSON.object(&rng, known: ["agentType", "description", "toolUseId", "spawnDepth", "requestShape"], p: 0.8).utf8)) }
                        FakeClaudeTree.appendBytes(h.tree.subagentDir(f.sid) + "/agent-\(id).jsonl", Data(FuzzTailerTests.messy(&rng, length: rng.int(1...100)) + [0x0A]))
                        if rng.chance(0.4) { h.tree.appendSubagent(f.sid, agentId: id, [FuzzCorpus.assistantLine(id: "sub\(rng.int(0...9))", at: h.now, stop: rng.pick(["end_turn", "tool_use"]))]) }
                    case 9:      // 文件被截短 / 删除 / 换掉
                        let target = rng.pick([h.tree.paths.hookLogPath(sessionId: f.sid)!, h.tree.transcriptPath(f.sid), metaPath, regPath])
                        switch rng.int(0...2) {
                        case 0: Darwin.truncate(target, off_t(rng.int(0...100)))
                        case 1: try? FileManager.default.removeItem(atPath: target)
                        default: FakeClaudeTree.writeInPlace(target, Data(rng.bytes(rng.int(0...200))))
                        }
                    case 10:     // 进程死 / 活
                        if rng.chance(0.5) { h.probe.kill(1001) } else { h.probe.setAlive(1001, start: rng.chance(0.5) ? f.session.startedAt : h.now.addingTimeInterval(-50)) }
                    case 11:     // 存盘
                        h.engine.flush()
                    case 12:     // 时间大跳跃（4e9 秒 ≈ 127 年，最多跳一次：再多的话“现在”会超过 2200 年，所有按“现在”打的时间戳都会被当作坏数据）
                        let jump = rng.pick([700, 3000, 100_000, 5e6, 4e9])
                        if jump < 4e9 || !bigJumpDone { h.advance(jump); if jump >= 4e9 { bigJumpDone = true } }
                    default: break
                    }
                    h.advance(rng.pick([0.05, 0.05, 0.3, 1, 5, 31]))
                    let snaps = h.poll()
                    polls += 1
                    if snaps.contains(where: { $0.sessionId == f.sid }) { stepsWithBuddy += 1 }
                    for sn in snaps { activityKinds.insert(String(describing: sn.activity).prefix(12).description) }
                    FuzzEngineTests.checkSnapshots(snaps, now: h.now, "第 \(round) 步", r)
                    if r.failed { return }
                }
                // 覆盖检查：这个测试不能是空转（大部分步骤里 buddy 在场、见过好几种动作）
                r.check(stepsWithBuddy > 150, "seed \(seed)：只有 \(stepsWithBuddy)/500 步里 buddy 在场，测试太空了")
                r.check(activityKinds.count >= 3, "seed \(seed)：只见过这些动作：\(activityKinds)")
                // 之后写入好数据，引擎恢复正常
                try? FileManager.default.removeItem(atPath: h.tree.paths.hookLogPath(sessionId: f.sid)!)
                h.probe.setAlive(1001, start: f.session.startedAt)
                validRegistry(status: "busy")
                h.tree.hook(f.sid, "UserPromptSubmit"); h.advance(0.2)
                h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/after/the/storm")
                for _ in 0..<12 { h.advance(0.3); h.poll() }
                let key = h.snapshots.first { $0.sessionId == f.sid }?.key
                if case .tool(let c, _)? = h.snapshots.first(where: { $0.sessionId == f.sid })?.activity {
                    r.check(c.name == "Read" && c.detail == "/after/the/storm", "恢复之后的工具不对：\(c.name)")
                } else { r.fail("乱七八糟之后应该恢复出「Read」：\(String(describing: h.snapshots.first { $0.sessionId == f.sid }?.activity)) key=\(String(describing: key))") }
                let c = h.engine.cacheSizes
                r.check(c.transcriptPaths <= 32 && c.transcriptMisses <= 32 && c.buddies <= 8, "缓存大小不合理：\(c)")
                _ = polls
            }
            #expect(finished, "seed \(seed) 超时")
        }
    }

    @Test("引擎：登记表目录里一次冒出几百个会话（含重复 sessionId / 同一个 host / 一半进程已死）再全部消失：不崩溃、不卡死，快照数和缓存有上界")
    func engineWithHundredsOfSessionsComingAndGoing() {
        let finished = fuzzRun("many sessions", timeout: 240) { r in
            var rng = FuzzRNG(seed: 0xE61E_0010)
            let h = Harness(tokens: true)
            for round in 0..<6 {
                var pids: [Int32] = []
                for i in 0..<150 {
                    let pid = Int32(10_000 + round * 1000 + i)
                    let sid = rng.chance(0.2) ? "dddd0000-0000-4000-8000-000000000001" : String(format: "dddd%04ld-0000-4000-8000-%012ld", round, i)      // 一部分共用 sessionId
                    let host: String? = rng.chance(0.5) ? "local_\(rng.int(0...20))" : nil                                                              // host 也大量重复
                    let s = FakeClaudeTree.Session(pid: pid, sessionId: sid, host: host, name: rng.chance(0.5) ? "会话\(i)" : nil, startedAt: h.now.addingTimeInterval(-Double(rng.int(0...100))))
                    if rng.chance(0.5) { h.tree.appendTranscript(sid, [TL.userPrompt(sessionId: sid, at: h.now)]) }
                    h.tree.writeRegistry(s, status: rng.pick(["busy", "idle", "waiting"]), markAlive: rng.chance(0.6))
                    pids.append(pid)
                }
                for _ in 0..<4 { h.advance(0.5); h.poll() }
                FuzzEngineTests.checkSnapshots(h.snapshots, now: h.now, "第 \(round) 批", r)
                r.check(h.snapshots.count <= 200, "快照数不合理：\(h.snapshots.count)")
                for pid in pids { h.tree.endProcess(pid: pid) }
                for _ in 0..<4 { h.advance(4); h.poll() }
                h.advance(30); h.poll()
                if r.failed { return }
            }
            h.advance(120); h.poll(); h.advance(120); h.poll()
            let c = h.engine.cacheSizes
            r.check(c.transcriptPaths <= 40 && c.transcriptMisses <= 40 && c.liveness <= 5 && c.resolvedKeys <= 5, "全部离场之后缓存还很大：\(c)")
        }
        #expect(finished)
    }

    @Test("SessionStore 的公开 API 被多个线程同时乱用（markSeen / rerollAppearance / diagnostics / currentSnapshots / debugRows / pollNow / poke），同时数据在变：不死锁、不崩溃；停掉之后再调用也安全，还能重新启动")
    func storePublicAPIUnderConcurrentUse() {
        let root = FileIO.temporaryDirectory + "buddy-store-stress-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let clock = VirtualClock()
        let probe = FakeProcessProbe()
        let tree = FakeClaudeTree(root: root, clock: clock, probe: probe)
        tree.prepare()
        var eo = SessionEngine.Options(paths: tree.paths, now: { [clock] in clock.now() }, probe: probe)
        eo.ledgerQueue = testLedgerQueue()
        eo.persist = false
        eo.scanTokens = true
        var so = SessionStore.Options(engine: eo)
        so.usePolling = true
        so.callbackQueue = DispatchQueue(label: "store-stress.callback")
        let store = SessionStore(options: so)
        let updates = FuzzBox(0), events = FuzzBox(0)
        store.onUpdate = { _ in updates.value += 1 }
        store.onEvent = { _ in events.value += 1 }
        let sessions = (0..<4).map { i in
            FakeClaudeTree.Session(pid: Int32(6000 + i), sessionId: String(format: "ffff%04ld-0000-4000-8000-000000000001", i), host: i % 2 == 0 ? "local_ffff\(i)" : nil,
                                   name: "压力\(i)", startedAt: clock.now())
        }
        for s in sessions { tree.appendTranscript(s.sessionId, [TL.userPrompt(sessionId: s.sessionId, at: clock.now())]); tree.writeRegistry(s, status: "busy") }
        store.start()
        let stop = FuzzBox(false)
        let finishedWorkers = DispatchGroup()
        for w in 0..<4 {
            let t = Thread {
                finishedWorkers.enter(); defer { finishedWorkers.leave() }
                var rng = FuzzRNG(seed: UInt64(0xC0C0 + w))
                while !stop.value {
                    let key = "d:local_ffff\(rng.int(0...3))"
                    switch rng.int(0...7) {
                    case 0: store.markSeen(key: key)
                    case 1: store.rerollAppearance(key: key)
                    case 2: _ = store.diagnostics()
                    case 3: _ = store.currentSnapshots
                    case 4: _ = store.debugRows()
                    case 5: _ = store.pollNow()
                    case 6: store.poke()
                    default: _ = store.currentSnapshots.count
                    }
                }
            }
            t.stackSize = 512 * 1024
            t.start()
        }
        // 数据在变
        var rng = FuzzRNG(seed: 0xC0C0_FFFF)
        let end = Date().addingTimeInterval(1.5)
        while Date() < end {
            let s = rng.pick(sessions)
            switch rng.int(0...5) {
            case 0: tree.writeRegistry(s, status: rng.pick(["busy", "idle", "waiting"]), waitingFor: rng.chance(0.5) ? "permission prompt" : nil)
            case 1: tree.hook(s.sessionId, rng.pick(["PreToolUse", "PostToolUse", "Stop", "UserPromptSubmit"]), tool: "Bash", detail: "x")
            case 2: tree.appendTranscript(s.sessionId, [FuzzCorpus.assistantLine(id: "m\(rng.int(0...50))", at: clock.now())])
            case 3: tree.endProcess(pid: s.pid)
            case 4: clock.advance(by: Double(rng.int(0...5)))
            default: FakeClaudeTree.appendBytes(tree.transcriptPath(s.sessionId), Data(rng.bytes(rng.int(1...50))))
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        let stopped = FuzzBox(false)
        let stopper = Thread { store.stop(); stopped.value = true }
        stopper.start()
        let deadline = Date().addingTimeInterval(20)
        while !stopped.value, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(stopped.value, "stop() 没有在 20 秒内返回（死锁？）")
        stop.value = true
        #expect(finishedWorkers.wait(timeout: .now() + 20) == .success, "有线程没有结束（死锁？）")
        // 停掉之后调用一切都安全
        store.markSeen(key: "d:local_ffff0"); store.rerollAppearance(key: "d:local_ffff0"); store.poke()
        _ = store.diagnostics(); _ = store.debugRows(); _ = store.currentSnapshots; _ = store.pollNow()
        store.stop()
        // 重新启动
        store.start()
        Thread.sleep(forTimeInterval: 0.3)
        _ = store.pollNow()
        store.stop()
        #expect(updates.value > 0)
    }
}
