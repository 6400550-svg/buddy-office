import Foundation
import Testing
@testable import BuddyCore

/// QA（逻辑线）：随机事件回放。
///  · z1：**独立的参考模型**（只按任务书 5.1 阶段 / 5.2 工具追踪 / 5.3 前台 Agent 归属 / 5.4 等待类判定写的，不看引擎实现）
///    和引擎在同一串随机事件（登记表翻转、hook 事件、时间流逝 / 大跳）上逐步对拍：阶段、主线程打开的调用（个数、顺序）、
///    忙碌 / 等待时的动作必须每一步都一致。
///  · z2：更脏更全的随机回放（会话记录里的打断 / 错误 / 重试 / 压缩、小助手文件、桌面元数据、markSeen……），
///    每一步检查快照的不变量（阶段 = 动作的阶段、idle 时没有本轮开始时间、未读 / blocked 只在 idle……）。
/// 固定种子，完全确定；失败时报出种子和最近几步的动作。
@Suite struct StateRuleInvariantTests {
    struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {           // splitmix64
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

    // MARK: 参考模型

    struct Model {
        enum Owner { case main, helper }
        struct Call { var name: String; var detail: String; var at: Date; var owner: Owner }
        var status = "idle"
        var waitingFor: String?
        var su: Date
        var lastPrompt: Date?
        var lastStop: Date?
        var open: [Call] = []
        var lastMainPre: Date?
        var prevPhase = "idle"

        static func ms(_ d: Date) -> Date { Date(timeIntervalSince1970: Double(TimeUtil.millis(d)) / 1000) }

        /// 5.1：登记表 status + 两个临时修正。
        func phase(at now: Date) -> String {
            var base = status
            if base == "idle", let p = lastPrompt, p > su, p > (lastStop ?? .distantPast), p <= now, now.timeIntervalSince(p) < 3 { return "busy" }
            if base == "busy", let s = lastStop, s > su, s >= (lastPrompt ?? .distantPast) { base = "idle" }
            return base
        }

        mutating func boundary(at t: Date) {
            open.removeAll { $0.owner == .main && $0.at <= t }
            if let l = lastMainPre, l <= t { lastMainPre = nil }
        }

        /// 5.3：主会话 idle → 小助手；前台 Agent / Task 开着且事件比它晚 ≥ 0.15 秒 → 小助手；其余 → 主线程。
        mutating func pre(_ name: String, _ detail: String, at ts: Date) {
            var owner = Owner.main
            if phase(at: ts) == "idle" { owner = .helper }
            else if let fg = open.filter({ $0.owner == .main && ($0.name == "Agent" || $0.name == "Task") }).map({ $0.at }).max(),
                    Int((ts.timeIntervalSince(fg) * 1000).rounded()) >= 150 { owner = .helper }
            if owner == .main {
                if lastMainPre == nil || ts.timeIntervalSince(lastMainPre!) > 0.25 { open.removeAll { $0.owner == .main } }
                lastMainPre = ts
            }
            open.append(Call(name: name, detail: name == "AskUserQuestion" ? "" : detail, at: ts, owner: owner))
        }

        /// 5.2：按「名字 + detail 都相同」关最早的；没有就按名字关最早的；再没有就忽略。
        mutating func post(_ name: String, _ detail: String) {
            let d = name == "AskUserQuestion" ? "" : detail
            if let i = open.firstIndex(where: { $0.name == name && $0.detail == d }) ?? open.firstIndex(where: { $0.name == name }) { open.remove(at: i) }
        }

        /// 5.2 兜底：登记表 idle 且开了超过 30 分钟；小助手名下的记录超过 30 分钟一律丢。
        mutating func expire(now: Date, registryIdle: Bool) {
            open.removeAll { now.timeIntervalSince($0.at) > 1800 && (registryIdle || $0.owner == .helper) }
        }

        var mainOpen: [Call] { open.filter { $0.owner == .main } }

        /// 忙碌 / 等待时的期望动作（没有压缩 / 重试 / Notification 的世界里）。
        func expected(phase p: String) -> Activity? {
            let latest = mainOpen.last
            let call = latest.map { ToolCatalog.makeCall(name: $0.name, detail: $0.detail, at: $0.at) }
            switch p {
            case "busy":
                if let c = call { return .tool(c, parallel: mainOpen.count) }
                return .thinking
            case "waiting":
                let wf = waitingFor ?? ""
                if wf == "permission prompt" || wf == "sandbox request" {
                    if latest?.name == "ExitPlanMode" { return .planReview }
                    if latest?.name == "AskUserQuestion" { return .asking }
                    return .waitingApproval(tool: call)
                }
                if wf == "input needed" || wf == "dialog open" { return latest?.name == "ExitPlanMode" ? .planReview : .asking }
                return .waitingOther(wf)
            default: return nil
            }
        }
    }

    static let toolNames = ["Read", "Bash", "Grep", "Edit", "Write", "Agent", "Task", "ExitPlanMode", "AskUserQuestion", "mcp__x__y", "WebFetch"]
    static let details = ["/a", "/b", "ls", "npm test", "", "研究"]
    static let waits: [(String, String?)] = [("busy", nil), ("idle", nil), ("waiting", "permission prompt"), ("waiting", "input needed"),
                                             ("waiting", "sandbox request"), ("waiting", "dialog open"), ("waiting", "goal proposal")]

    @Test("z1 参考模型对拍：随机事件流里，阶段、主线程打开的调用（个数和顺序）、忙碌 / 等待时的动作每一步都和任务书规则一致", arguments: seeds)
    func z1_referenceModelAgreesWithTheEngine(seed: UInt64) {
        var rng = RNG(state: seed)
        let (h, f) = StateRuleKit.idleSession()
        let key = StateRuleKit.key
        var m = Model(su: Model.ms(h.now.addingTimeInterval(-40)))
        var log: [String] = []
        var failed = false

        func write(_ status: String, _ wf: String?) {
            let t = Model.ms(h.now)
            h.tree.writeRegistry(f.session, status: status, waitingFor: wf, statusUpdatedAt: t)
            m.status = status; m.waitingFor = wf; m.su = t
        }

        for step in 0..<500 where !failed {
            let t = Model.ms(h.now)
            var what = ""
            switch Int.random(in: 0..<20, using: &rng) {
            case 0, 1, 2:
                let (s, wf) = StateRuleInvariantTests.waits.randomElement(using: &rng)!
                write(s, wf); what = "登记表 \(s)/\(wf ?? "-")"
            case 3:
                h.tree.hook(f.sid, "UserPromptSubmit", at: t); m.lastPrompt = t; m.boundary(at: t); what = "UserPromptSubmit"
            case 4:
                h.tree.hook(f.sid, "Stop", at: t); m.lastStop = t; m.boundary(at: t); what = "Stop"
            case 5:
                h.tree.hook(f.sid, "SessionStart", extra: ["clear", "resume", "compact"].randomElement(using: &rng)!, at: t); m.boundary(at: t); what = "SessionStart"
            case 6, 7, 8, 9, 10, 11:
                let n = Int.random(in: 1...3, using: &rng)                       // 一小批（同一毫秒）Pre
                for _ in 0..<n {
                    let name = StateRuleInvariantTests.toolNames.randomElement(using: &rng)!, d = StateRuleInvariantTests.details.randomElement(using: &rng)!
                    h.tree.hook(f.sid, "PreToolUse", tool: name, detail: d, at: t); m.pre(name, d, at: t)
                    what += "Pre(\(name),\(d)) "
                }
            case 12, 13, 14:
                var name = StateRuleInvariantTests.toolNames.randomElement(using: &rng)!, d = StateRuleInvariantTests.details.randomElement(using: &rng)!
                if let c = m.open.randomElement(using: &rng), Bool.random(using: &rng) { name = c.name; d = c.detail }
                h.tree.hook(f.sid, "PostToolUse", tool: name, detail: d, extra: "len=1", at: t); m.post(name, d); what = "Post(\(name),\(d))"
            default:
                what = "(只推进时间)"
            }
            // 时间：大多数是小步（含 0.25 秒批次边界附近），偶尔几十秒，极少数 10–70 分钟的大跳
            let gap: Double
            switch Int.random(in: 0..<20, using: &rng) {
            case 0: gap = [0.24, 0.25, 0.251, 0.3].randomElement(using: &rng)!
            case 1: gap = Double.random(in: 1...40, using: &rng)
            case 2 where Int.random(in: 0..<4, using: &rng) == 0: gap = Double.random(in: 600...4200, using: &rng)
            case 3, 4: gap = 0
            default: gap = Double.random(in: 0.001...0.2, using: &rng)
            }
            h.advance(gap)
            let now = Model.ms(h.now)
            h.poll()
            // 模型：先处理事件（上面已经处理），再兜底过期，再看阶段变化（变成 idle 就是轮次边界）
            m.expire(now: now, registryIdle: m.status == "idle")
            let p = m.phase(at: h.now)
            if p == "idle" && m.prevPhase != "idle" { m.boundary(at: h.now) }
            m.prevPhase = p
            log.append("#\(step) \(what) +\(String(format: "%.3f", gap))s → 模型阶段 \(p)")
            if log.count > 14 { log.removeFirst() }

            guard let s = h.snap(key) else { Issue.record("seed \(seed) 第 \(step) 步：buddy 不见了\n\(log.joined(separator: "\n"))"); failed = true; break }
            let mainOpen = h.engine.openMainTools(key: key).map { "\($0.call.name)|\($0.call.detail)" }
            let modelOpen = m.mainOpen.map { "\($0.name)|\($0.detail)" }
            var problems: [String] = []
            if s.phase.rawValue != p { problems.append("阶段：引擎 \(s.phase.rawValue)，模型 \(p)") }
            if mainOpen != modelOpen { problems.append("主线程打开的调用：引擎 \(mainOpen)，模型 \(modelOpen)") }
            if let want = m.expected(phase: p), p == s.phase.rawValue {
                if !sameActivity(s.activity, want) { problems.append("动作：引擎 \(s.activity)，模型 \(want)") }
            }
            if !problems.isEmpty {
                Issue.record("seed \(seed) 第 \(step) 步不一致：\(problems.joined(separator: "；"))\n最近的动作：\n\(log.joined(separator: "\n"))")
                failed = true
            }
        }
    }

    /// 动作相等，但 .tool 的 startedAt 不比较（模型里的时间是取整过的）。
    func sameActivity(_ a: Activity, _ b: Activity) -> Bool {
        switch (a, b) {
        case let (.tool(c1, n1), .tool(c2, n2)): return c1.name == c2.name && c1.detail == c2.detail && c1.category == c2.category && n1 == n2
        case let (.waitingApproval(t1), .waitingApproval(t2)): return t1?.name == t2?.name && t1?.detail == t2?.detail
        default: return a == b
        }
    }

    // MARK: z2 不变量

    @Test("z2 更脏的随机回放：会话记录 / 小助手 / 桌面元数据 / 压缩 / 通知 / markSeen 混在一起，每一步快照都满足不变量", arguments: seeds)
    func z2_snapshotInvariantsHoldUnderRandomReplay(seed: UInt64) {
        var rng = RNG(state: seed &+ 1000)
        let (h, f) = StateRuleKit.idleSession()
        let key = StateRuleKit.key
        var meta = FakeClaudeTree.Meta(host: f.session.host!, cliSessionId: f.sid, lastActivityAt: h.now)
        meta.lastAssistantUuid = "u0"
        h.tree.writeMeta(meta)
        h.tree.writeSubagentMeta(f.sid, agentId: "zz01", foreground: false)
        var uuid = 0, msgId = 0
        var started = 0, finished = 0, attention = false
        var log: [String] = []
        var failed = false

        func assistant(_ block: [String: Any], stop: String? = "end_turn") {
            msgId += 1
            h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "z\(msgId)", block: block, stopReason: stop)])
        }

        for step in 0..<400 where !failed {
            var what = ""
            switch Int.random(in: 0..<26, using: &rng) {
            case 0, 1: let (s, wf) = StateRuleInvariantTests.waits.randomElement(using: &rng)!
                h.tree.writeRegistry(f.session, status: s, waitingFor: wf, statusUpdatedAt: h.now); what = "登记表 \(s)/\(wf ?? "-")"
            case 2: h.tree.hook(f.sid, "UserPromptSubmit"); h.tree.appendTranscript(f.sid, [TL.userPrompt(sessionId: f.sid, at: h.now)]); what = "prompt"
            case 3: h.tree.hook(f.sid, "Stop"); what = "Stop"
            case 4: h.tree.appendTranscript(f.sid, [TL.stopHookSummary(sessionId: f.sid, at: h.now)]); what = "stop_hook_summary"
            case 5: h.tree.appendTranscript(f.sid, [TL.userInterrupt(sessionId: f.sid, at: h.now, forToolUse: Bool.random(using: &rng))]); what = "打断标记"
            case 6: h.tree.appendTranscript(f.sid, [TL.apiError(sessionId: f.sid, at: h.now, attempt: Int.random(in: 1...10, using: &rng), max: 10, retryInMs: Double(Int.random(in: 500...30000, using: &rng)))]); what = "api_error"
            case 7: msgId += 1
                h.tree.appendTranscript(f.sid, [TL.assistant(sessionId: f.sid, at: h.now, messageId: "e\(msgId)", block: TL.text("API Error"), stopReason: "stop_sequence", model: "<synthetic>", apiErrorMessage: true)]); what = "合成错误消息"
            case 8: assistant(TL.text("说话")); what = "assistant 文字"
            case 9: h.tree.appendTranscript(f.sid, [TL.userToolResult(sessionId: f.sid, at: h.now, toolUseId: "toolu_z")]); what = "tool_result"
            case 10: h.tree.hook(f.sid, "PreCompact", extra: "auto"); what = "PreCompact"
            case 11: h.tree.hook(f.sid, "PostCompact"); what = "PostCompact"
            case 12: h.tree.hook(f.sid, "Notification", extra: "Claude needs your permission to use \(StateRuleInvariantTests.toolNames.randomElement(using: &rng)!)"); what = "Notification"
            case 13, 14, 15:
                let name = StateRuleInvariantTests.toolNames.randomElement(using: &rng)!, d = StateRuleInvariantTests.details.randomElement(using: &rng)!
                h.tree.hook(f.sid, "PreToolUse", tool: name, detail: d); what = "Pre(\(name))"
            case 16, 17:
                let name = StateRuleInvariantTests.toolNames.randomElement(using: &rng)!, d = StateRuleInvariantTests.details.randomElement(using: &rng)!
                h.tree.hook(f.sid, "PostToolUse", tool: name, detail: d, extra: "len=1"); what = "Post(\(name))"
            case 18: h.tree.hook(f.sid, "SessionStart", extra: ["clear", "resume", "compact", "startup"].randomElement(using: &rng)!); what = "SessionStart"
            case 19: h.tree.hook(f.sid, "SubagentStop"); what = "SubagentStop"
            case 20:                                                             // 后台小助手写一行
                msgId += 1
                h.tree.appendSubagent(f.sid, agentId: "zz01", [TL.assistant(sessionId: f.sid, at: h.now, messageId: "h\(msgId)", block: Bool.random(using: &rng) ? TL.toolUse(id: "th\(msgId)", name: "Read", input: ["file_path": "/h"]) : TL.text("hi"),
                                                                            stopReason: nil, agentId: "zz01")]); what = "小助手写了一行"
            case 21:                                                             // 桌面元数据：新的 assistant 消息 + 总结
                uuid += 1; meta.lastAssistantUuid = "u\(uuid)"
                if Bool.random(using: &rng) { meta.summaryFor = "u\(uuid)"; meta.summaryCategory = ["blocked", "completed"].randomElement(using: &rng)!; meta.summaryDetail = "d" } else { meta.summaryFor = nil; meta.summaryCategory = nil }
                if Bool.random(using: &rng) { meta.lastFocusedAt = h.now }
                h.tree.writeMeta(meta); what = "桌面元数据"
            case 22: h.engine.markSeen(key: key); what = "markSeen"
            default: what = "(只推进时间)"
            }
            let gap: Double
            switch Int.random(in: 0..<16, using: &rng) {
            case 0: gap = Double.random(in: 1...40, using: &rng)
            case 1 where Int.random(in: 0..<4, using: &rng) == 0: gap = Double.random(in: 600...4200, using: &rng)
            case 2, 3: gap = 0
            default: gap = Double.random(in: 0.001...0.6, using: &rng)
            }
            h.advance(gap)
            h.poll()
            log.append("#\(step) \(what) +\(String(format: "%.3f", gap))s")
            if log.count > 14 { log.removeFirst() }
            guard let s = h.snap(key) else { Issue.record("seed \(seed) 第 \(step) 步：buddy 不见了\n\(log.joined(separator: "\n"))"); failed = true; break }

            // 事件计数
            for k in h.events.filter({ $0.key == key }).map({ $0.kind }) {
                switch k {
                case .turnStarted: started += 1
                case .turnFinished: finished += 1
                case .needsUser: attention = true
                case .needsUserCleared: attention = false
                default: break
                }
            }
            h.clearEvents()

            var problems: [String] = []
            func check(_ ok: Bool, _ msg: String) { if !ok { problems.append(msg) } }
            check(s.phase == s.activity.phase, "phase 和 activity.phase 不一致")
            check(s.presence == .present, "会话怎么离场了")
            if s.phase == .idle {
                check(s.turnStartedAt == nil, "idle 时不该有 turnStartedAt")
                check(s.idleSince != nil, "idle 时应该有 idleSince")
            } else {
                check(s.turnStartedAt != nil, "\(s.phase) 时应该有 turnStartedAt")
                check(s.idleSince == nil, "\(s.phase) 时不该有 idleSince")
                check(!s.unread, "\(s.phase) 时不该亮未读（下一轮开始就该清掉）")
                check(!s.blocked, "\(s.phase) 时不该有 blocked")
            }
            check(!s.quiet || s.phase == .busy, "quiet 只在 busy")
            if case .tool(_, let n) = s.activity {
                check(n >= 1, "并行个数应 ≥ 1")
                if s.hookActive { check(n == h.engine.openMainTools(key: key).count, "并行个数 \(n) ≠ 打开的主线程调用 \(h.engine.openMainTools(key: key).count)") }
            }
            check(s.activitySince <= h.now.addingTimeInterval(0.002), "activitySince 在未来")
            if let i = s.idleSince { check(i <= h.now.addingTimeInterval(0.002), "idleSince 在未来") }
            if let d = s.lastTurnDuration { check(d >= 0, "lastTurnDuration 为负") }
            if s.phase == .idle, let i = s.idleSince {                         // 空闲时的时间窗口（3 / 5 秒，10 / 45 分钟）
                let idleFor = h.now.timeIntervalSince(i)
                switch s.activity {
                case .interrupted: check(idleFor < 3.002, "被打断只持续 3 秒，实际已经 \(idleFor)")
                case .finished: check(idleFor < 5.002, "做完了只持续 5 秒，实际已经 \(idleFor)")
                case .errored: check(idleFor < 600.002, "出错保持到打盹（10 分钟），实际已经 \(idleFor)")
                case .idle: check(idleFor < 600.002, "空闲超过 10 分钟应该打盹，实际已经 \(idleFor)")
                case .dozing: check(idleFor >= 599.998 && idleFor < 2700.002, "打盹应该是空闲 10–45 分钟，实际 \(idleFor)")
                case .sleeping: check(idleFor >= 2699.998, "睡着应该是空闲满 45 分钟，实际 \(idleFor)")
                default: check(false, "idle 阶段不该出现这个动作：\(s.activity)")
                }
                if idleFor >= 2700.002 { check(s.activity == .sleeping, "空闲满 45 分钟必须是睡着，实际 \(s.activity)") }
                else if idleFor >= 600.002 { check(s.activity == .dozing || s.activity == .sleeping, "空闲满 10 分钟必须至少是打盹，实际 \(s.activity)") }
            }
            check(attention == s.activity.needsUser, "提醒事件（开始 / 不再等你）和动作对不上：事件说 \(attention)，动作 \(s.activity)")
            check(started - finished == 0 || started - finished == 1, "一轮开始 \(started) / 结束 \(finished) 的事件对不上")
            if s.phase != .idle { check(started - finished == 1, "\(s.phase) 时应该有一轮在进行（开始 \(started) / 结束 \(finished)）") }
            if !problems.isEmpty {
                Issue.record("seed \(seed) 第 \(step) 步不变量被破坏：\(problems.joined(separator: "；"))\n最近的动作：\n\(log.joined(separator: "\n"))")
                failed = true
            }
        }
    }
}
