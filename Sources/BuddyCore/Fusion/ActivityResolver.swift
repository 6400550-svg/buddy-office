import Foundation

/// 动作判定（DESIGN.md 5.1 / 5.4）。**纯函数**：输出只由（信号, 当前时间）决定。
public enum ActivityResolver {
    /// 临时修正：登记表还是 idle 但有更新的 UserPromptSubmit → 暂时当作 busy，最多 3 秒。
    public static let tempBusyWindow: TimeInterval = 3
    public static let interruptedDuration: TimeInterval = 3
    public static let finishedDuration: TimeInterval = 5
    /// api_error 之后，`retryInMs + 15 秒` 内没有新的 assistant / user 行 → 重试中。
    public static let retrySlack: TimeInterval = 15
    /// PreCompact 之后一直没有 PostCompact：超过这么久（秒）就不再当作压缩中（防止 hook 丢了导致永远显示）。
    public static let compactStaleAfter: TimeInterval = 15 * 60
    /// 会话记录里 compact_boundary 之后没有新行的最长显示时间。
    public static let transcriptCompactWindow: TimeInterval = 120
    /// compact_boundary 之前多久（秒）以内的 PostCompact / SessionStart(compact) 算「hook 已经说压缩结束了」。
    public static let boundaryHookSlack: TimeInterval = 5

    public static func resolve(_ s: SessionSignals, now: Date) -> Activity {
        evaluate(s, now: now).activity
    }

    // MARK: - 阶段（5.1）

    /// 基础：登记表的 status；两个临时修正（hook 往往比登记表快一点）：
    /// - 登记表还是 idle，但有一条比 statusUpdatedAt 更新的 UserPromptSubmit → 暂时当作 busy，最多 3 秒；
    /// - 登记表还是 busy，但有一条比 statusUpdatedAt 更新的 Stop → 暂时当作 idle。
    public static func effectivePhase(_ s: SessionSignals, now: Date) -> Phase {
        phase(s, now: now).0
    }

    /// 返回（阶段, 因临时修正 1 而变成 busy 时的到期时间）。
    private static func phase(_ s: SessionSignals, now: Date) -> (Phase, Date?) {
        var base: Phase
        if let r = s.registryStatus {
            base = r
        } else if s.hookActive, let p = s.lastPromptAt, p > (s.lastStopAt ?? .distantPast) {
            base = .busy                      // 登记表没有状态：只能靠 hook 推断
        } else {
            base = .idle
        }
        if base == .idle, let p = s.lastPromptAt,
           p > (s.statusUpdatedAt ?? .distantPast), p > (s.lastStopAt ?? .distantPast),
           p <= now, now.timeIntervalSince(p) < tempBusyWindow {
            return (.busy, p.addingTimeInterval(tempBusyWindow))
        }
        if base == .busy, let stop = s.lastStopAt,
           stop > (s.statusUpdatedAt ?? .distantPast), stop >= (s.lastPromptAt ?? .distantPast) {
            base = .idle
        }
        return (base, nil)
    }

    // MARK: - 动作（5.4）

    public static func evaluate(_ s: SessionSignals, now: Date) -> Resolution {
        var next: Date?
        func consider(_ t: Date) { if t > now { next = min(next ?? t, t) } }

        let (ph, tempBusyUntil) = phase(s, now: now)
        if let t = tempBusyUntil { consider(t) }

        switch ph {
        case .waiting:
            return Resolution(activity: waitingActivity(s), phase: ph, nextChange: next)
        case .busy:
            return Resolution(activity: busyActivity(s, now: now, consider: consider), phase: ph, nextChange: next)
        case .idle:
            return Resolution(activity: idleActivity(s, now: now, consider: consider), phase: ph, nextChange: next)
        }
    }

    // MARK: waiting

    /// 等批准 / 提问 / 计划待审 / 其他等待。
    private static func waitingActivity(_ s: SessionSignals) -> Activity {
        let wf = s.waitingFor
        // waitingFor 缺失时，用比这次等待更新的 Notification 文本兜底
        var text = wf
        if text == nil, let nt = s.notificationText, let na = s.notificationAt,
           na >= (s.statusUpdatedAt ?? .distantPast) {
            text = nt
        }
        let lower = (text ?? "").lowercased()
        let approval = wf == "permission prompt" || wf == "sandbox request"
            || lower.contains("permission") || lower.contains("allow")
        let question = wf == "input needed" || wf == "dialog open"
            || lower.contains("input") || lower.contains("question") || lower.contains("elicitation")
        let latest = s.openTools.last

        if approval {
            // 计划待审也是"请求批准"，但要画成举写字板；AskUserQuestion 的通知文本也叫 permission，实际是提问
            if latest?.category == .planExit { return .planReview }
            if latest?.name == "AskUserQuestion" { return .asking }
            return .waitingApproval(tool: approvalTool(s))
        }
        if question {
            if latest?.category == .planExit { return .planReview }
            return .asking
        }
        return .waitingOther(text ?? "")
    }

    /// 等批准的工具：最新一个打开的主线程调用；没有的话，从 Notification 文本里解析 `use <T>`。
    /// Notification 点名了工具、并且比这次等待更新时，优先取名字对得上的那个打开调用（并行时不会张冠李戴）。
    private static func approvalTool(_ s: SessionSignals) -> ToolCall? {
        var named: String?
        if let nt = s.notificationText, let na = s.notificationAt, na >= (s.statusUpdatedAt ?? .distantPast) {
            named = toolName(fromNotification: nt)
        }
        if let n = named {
            if let hit = s.openTools.last(where: { $0.name == n || $0.name.hasPrefix(n) || n.hasPrefix($0.name) }) { return hit }
        }
        if let latest = s.openTools.last { return latest }
        if let n = named { return ToolCatalog.makeCall(name: n, at: s.notificationAt ?? Date.distantPast) }
        return nil
    }

    /// "Claude needs your permission to use Bash" → "Bash"
    public static func toolName(fromNotification text: String) -> String? {
        guard let r = text.range(of: " use ", options: .backwards) else { return nil }
        var rest = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        while rest.hasSuffix(".") || rest.hasSuffix("。") { rest.removeLast() }
        guard let first = rest.split(separator: " ").first, !first.isEmpty else { return nil }
        return String(first)
    }

    // MARK: busy

    private static func busyActivity(_ s: SessionSignals, now: Date, consider: (Date) -> Void) -> Activity {
        // 1. 整理上下文：有 PreCompact 但还没有 PostCompact；或会话记录显示压缩边界之后还没有新行
        if let pre = s.preCompactAt, pre <= now, (s.postCompactAt ?? .distantPast) < pre,
           now.timeIntervalSince(pre) < compactStaleAfter {
            consider(pre.addingTimeInterval(compactStaleAfter))
            return .compacting
        }
        // 会话记录里的 compact_boundary 是压缩**结束**时才写的（真实日志：比 SessionStart(compact) 晚约 0.04 秒、比 PostCompact 晚约 0.02 秒，
        // 离 PreCompact 已经过了 88–104 秒）；hook 已经说压缩结束了（PostCompact / SessionStart(compact) 不早于它前 5 秒），
        // 就不能再靠它显示「整理上下文」——否则压缩完之后第一个工具会被盖住，直到下一条 assistant 行落盘。
        // 没有 hook 的会话只有这一个信号，照旧。
        let hookSaysCompactionEnded: (Date) -> Bool = { b in
            (s.postCompactAt ?? .distantPast) >= b.addingTimeInterval(-boundaryHookSlack)
        }
        if let b = s.compactBoundaryAt, b <= now, b >= (s.lastAssistantOrUserAt ?? .distantPast),
           now.timeIntervalSince(b) < transcriptCompactWindow, !hookSaysCompactionEnded(b) {
            consider(b.addingTimeInterval(transcriptCompactWindow))
            return .compacting
        }
        // 2. 重试中：距离最近一次 api_error 不超过 retryInMs + 15 秒，且之后没有新的 assistant / user 行
        if let e = s.apiError, e.at <= now, (s.lastAssistantOrUserAt ?? .distantPast) <= e.at {
            let until = e.at.addingTimeInterval(e.retryInMs / 1000 + retrySlack)
            if now < until {
                consider(until)
                return .retrying(attempt: e.attempt, max: e.max)
            }
        }
        // 3. 有打开的主线程工具 → 最新的那个，带上并行个数
        if let latest = s.openTools.last {
            return .tool(latest, parallel: s.openTools.count)
        }
        // 4. 思考中
        return .thinking
    }

    // MARK: idle

    private static func idleActivity(_ s: SessionSignals, now: Date, consider: (Date) -> Void) -> Activity {
        guard let since = s.idleSince, since <= now else { return .idle }
        let idleFor = now.timeIntervalSince(since)

        switch s.turnEnd {
        case .none:
            break
        case .interrupted:
            // 被打断（持续 3 秒）
            if idleFor < interruptedDuration { consider(since.addingTimeInterval(interruptedDuration)); return .interrupted }
        case .errored:
            // 出错：一直保持到开始打盹（错误不能一闪而过）
            if idleFor < s.dozeAfter { consider(since.addingTimeInterval(s.dozeAfter)); return .errored }
        case .finished:
            // 做完了（持续 5 秒）
            if idleFor < finishedDuration { consider(since.addingTimeInterval(finishedDuration)); return .finished }
        }
        // 空闲 → 打盹 → 睡着
        if idleFor >= s.sleepAfter { return .sleeping }
        if idleFor >= s.dozeAfter {
            consider(since.addingTimeInterval(s.sleepAfter))
            return .dozing
        }
        consider(since.addingTimeInterval(s.dozeAfter))
        return .idle
    }
}
