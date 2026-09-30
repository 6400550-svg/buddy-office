import Foundation

/// `buddydump [--watch|--once] [--poll] [--data-root DIR] [--no-tokens] [--persist]`
/// （`buddyctl dump` 转发到同一个函数。）
///
/// 实时打印一张表：key、来源、pid 与是否存活、登记表 status / waitingFor、判定出的动作、工具与细节、
/// 本轮用时、token、小助手、hook 状态。M1 阶段拿它对照真实会话。
/// 只打印元数据（状态、工具名、时间），**绝不打印对话内容**。
public func runDumpCommand(arguments: [String]) -> Int32 {
    var watch = false
    var poll = false
    var dataRoot: String?
    var tokens = true
    var persist = false
    var json = false
    var quiet = false
    var interval = 1.0
    var auditSeconds: Double?
    var i = 0
    func usage() -> Int32 {
        print("""
        用法：buddydump [--once|--watch] [--poll] [--data-root DIR] [--interval 秒] [--no-tokens] [--persist] [--json]
          --once       扫描一次并打印（默认）
          --watch      持续刷新（Ctrl-C 退出）
          --poll       纯轮询（不用 FSEvents；沙箱里用这个）
          --data-root  把所有数据路径换到这个假的 home 目录（下面要有 .claude/sessions 等）
          --no-tokens  不统计 token
          --persist    读写 identities.json / ledger.json（默认不写，免得干扰真正的 App）
          --json       输出 JSON（含精确的 token 分项），只有元数据，没有对话内容
          --quiet      --watch 时只运行数据层、不画表（测 CPU / 内存用）
          --audit-opens 秒数
                       只读地把数据层跑这么多秒（0 = 扫描一次），然后按类别汇总一共打开过哪些文件（只列类别和个数，不列文件名），
                       并确认没有打开过密钥文件 / socket、保险也没有拒绝过；有问题时退出码为 1
        """)
        return 2
    }
    while i < arguments.count {
        let a = arguments[i]
        switch a {
        case "--watch": watch = true
        case "--once": watch = false
        case "--poll": poll = true
        case "--no-tokens": tokens = false
        case "--persist": persist = true
        case "--json": json = true
        case "--quiet": quiet = true
        case "--audit-opens":
            i += 1
            guard i < arguments.count, let v = Double(arguments[i]), v >= 0, v <= 86_400 else { return usage() }
            auditSeconds = v
        case "--data-root":
            i += 1
            guard i < arguments.count else { return usage() }
            dataRoot = arguments[i]
        case "--interval":
            i += 1
            guard i < arguments.count, let v = Double(arguments[i]), v > 0 else { return usage() }
            interval = v
        case "-h", "--help": _ = usage(); return 0
        default:
            FileHandle.standardError.write(Data("未知参数：\(a)\n".utf8))
            return usage()
        }
        i += 1
    }

    let paths = dataRoot.map { Paths(home: $0) } ?? .real
    var eo = SessionEngine.Options(paths: paths)
    eo.persist = persist
    eo.scanTokens = tokens
    var so = SessionStore.Options(engine: eo)
    so.usePolling = poll
    let outQueue = DispatchQueue(label: "buddydump.out")
    so.callbackQueue = outQueue
    if let seconds = auditSeconds {
        // 不画表：只读地把数据层跑 seconds 秒（0 = 扫描一次），再按类别汇总打开过的文件
        let report = OpenAudit.run(options: so, seconds: seconds, tokens: tokens)
        print(report.text())
        return report.ok ? 0 : 1
    }
    let store = SessionStore(options: so)
    store.start()

    if !watch {
        _ = store.pollNow()
        if tokens { store.waitForTokenScan(timeout: 30) }
        _ = store.pollNow()
        if json {
            print(DumpFormatter.renderJSON(rows: store.debugRows()))
        } else {
            print(DumpFormatter.render(rows: store.debugRows(), diagnostics: store.diagnostics(), now: Date()))
        }
        store.stop()
        return 0
    }

    // --watch：每次快照更新（最多 4 Hz）或每 interval 秒重画一次
    let isTTY = isatty(1) != 0
    var lastDraw = Date.distantPast
    func draw() {
        let text = DumpFormatter.render(rows: store.debugRows(), diagnostics: store.diagnostics(), now: Date())
        if isTTY { print("\u{1B}[H\u{1B}[2J", terminator: "") } else { print("\n----------------------------------------") }
        print(text)
        fflush(stdout)
        lastDraw = Date()
    }
    if quiet {
        store.onUpdate = { _ in }
        dispatchMain()
    }
    store.onUpdate = { _ in
        if Date().timeIntervalSince(lastDraw) >= 0.25 { draw() }
    }
    let timer = DispatchSource.makeTimerSource(queue: outQueue)
    timer.schedule(deadline: .now() + 0.1, repeating: interval)
    timer.setEventHandler { draw() }
    timer.resume()
    dispatchMain()
}

/// dump 表格的排版（中文按 2 格宽对齐）。
public enum DumpFormatter {
    public static func render(rows: [BuddyDebugRow], diagnostics d: DiagnosticsInfo, now: Date) -> String {
        var out: [String] = []
        let hookStr = d.hookDetectedInSettings ? "已注册" : "未检测到"
        out.append("[\(now.debugClock)] 活会话 \(d.liveSessionCount) · settings.json 里 hook \(hookStr)"
                   + (d.lastHookEventAt.map { " · 最近 hook 事件 \(age($0, now)) 前" } ?? ""))
        out.append(d.sourceStatus.joined(separator: " | "))
        out.append("")
        let cols: [(String, Int)] = [("座", 3), ("key", 22), ("标题", 18), ("来源", 12), ("pid", 9), ("登记表", 20),
                                     ("动作", 22), ("细节", 30), ("本轮", 9), ("token(ctx)", 16), ("小助手", 22), ("hook", 18), ("标记", 14)]
        out.append(cols.map { pad($0.0, $0.1) }.joined(separator: " "))
        out.append(cols.map { String(repeating: "-", count: $0.1) }.joined(separator: " "))
        if rows.isEmpty { out.append("（没有 buddy）") }
        for r in rows {
            let s = r.snapshot
            let originName: String
            switch s.origin { case .desktop: originName = "桌面"; case .vscode: originName = "VSCode"; case .terminal: originName = "终端" }
            var src = originName
            if s.modelFamily != .claude { src += "/\(s.modelFamily.rawValue)" }
            let pidStr: String
            if let pid = s.pid { pidStr = "\(pid)" + livenessMark(r.liveness) } else { pidStr = "-" + livenessMark(r.liveness) }
            var reg = r.registryStatus ?? "-"
            if let w = r.waitingFor { reg += "/" + w }
            var flags: [String] = []
            if s.unread { flags.append("未读") }
            if s.blocked { flags.append("需处理") }
            if s.quiet { flags.append("安静") }
            if case .away(_, let dormant) = s.presence { flags.append(dormant ? "下班" : "离场") }
            if s.appearedAfterLaunch { flags.append("新") }
            let (actText, detail) = describe(s.activity)
            let since = age(s.activitySince, now)
            var turn = "-"
            if let t0 = s.turnStartedAt { turn = clock(now.timeIntervalSince(t0)) }
            else if let d = s.lastTurnDuration { turn = "(" + clock(d) + ")" }
            var tok = "-"
            if s.tokens.total > 0 || r.tokenMessages > 0 {
                tok = fmtTok(s.tokens.total) + (s.contextTokens.map { "(\(fmtTok($0)))" } ?? "")
                if !r.tokenScanComplete { tok += "…" }
            }
            var helpers = "-"
            if !s.helpers.isEmpty {
                let active = s.helpers.filter { $0.active }.count
                helpers = "\(active)活/\(s.helpers.count)"
                if let t = s.helpers.first(where: { $0.currentTool != nil })?.currentTool { helpers += " " + t.name }
            } else if r.helperFiles > 0 { helpers = "0/\(r.helperFiles)文件" }
            var hook = s.hookActive ? "✓" : "✗"
            if let t = r.lastHookEventAt { hook += " \(age(t, now))" }
            hook += " n=\(r.hookEventsSeen)"
            if r.hookDegradedLines > 0 { hook += " 降级\(r.hookDegradedLines)" }
            let cells = [pad("\(s.seat)", 3), pad(s.key, 22), pad(s.title, 18), pad(src, 12), pad(pidStr, 9), pad(reg, 20),
                         pad(actText + " " + since, 22), pad(detail, 30), pad(turn, 9), pad(tok, 16), pad(helpers, 22),
                         pad(hook, 18), pad(flags.joined(separator: ","), 14)]
            out.append(cells.joined(separator: " "))
            if !r.openMainTools.isEmpty || !r.openHelperTools.isEmpty {
                let m = r.openMainTools.map { $0.name }.joined(separator: ",")
                let h = r.openHelperTools.map { $0.name }.joined(separator: ",")
                out.append("      └ 开着的工具：主线程 [\(m)]" + (h.isEmpty ? "" : "  小助手名下 [\(h)]"))
            }
            if let sd = s.statusDetail { out.append("      └ 桌面总结：\(truncate(sd, 100))") }
        }
        return out.joined(separator: "\n")
    }

    /// JSON 输出：每个 buddy 一个对象（元数据，没有对话内容）。
    public static func renderJSON(rows: [BuddyDebugRow]) -> String {
        var arr: [[String: Any]] = []
        for r in rows {
            let s = r.snapshot
            var o: [String: Any] = [
                "seat": s.seat, "key": s.key, "sessionId": s.sessionId, "title": s.title, "origin": s.origin.rawValue,
                "phase": s.phase.rawValue, "activity": describe(s.activity).0, "activityDetail": describe(s.activity).1,
                "registryStatus": r.registryStatus as Any? ?? NSNull(), "waitingFor": r.waitingFor as Any? ?? NSNull(),
                "liveness": r.liveness, "hookActive": s.hookActive, "hookEvents": r.hookEventsSeen,
                "unread": s.unread, "blocked": s.blocked, "quiet": s.quiet,
                "tokens": ["input": s.tokens.input, "output": s.tokens.output, "cacheWrite": s.tokens.cacheWrite,
                           "cacheRead": s.tokens.cacheRead, "total": s.tokens.total, "messages": r.tokenMessages,
                           "scanComplete": r.tokenScanComplete] as [String: Any],
                "helpers": s.helpers.map { ["id": $0.id, "foreground": $0.foreground, "active": $0.active, "done": $0.done,
                                             "tool": $0.currentTool?.name as Any? ?? NSNull()] as [String: Any] },
            ]
            if let pid = s.pid { o["pid"] = Int(pid) }
            if let h = s.hostSessionId { o["hostSessionId"] = h }
            if let c = s.contextTokens { o["contextTokens"] = c }
            if let t = s.turnStartedAt { o["turnStartedAt"] = TimeUtil.millis(t) }
            if let t = s.idleSince { o["idleSince"] = TimeUtil.millis(t) }
            if let d = s.lastTurnDuration { o["lastTurnDuration"] = d }
            if let p = r.transcriptPath { o["transcriptFile"] = (p as NSString).lastPathComponent }
            switch s.presence {
            case .present: o["presence"] = "present"
            case .away(let since, let dormant): o["presence"] = dormant ? "dormant" : "away"; o["awaySince"] = TimeUtil.millis(since)
            }
            arr.append(o)
        }
        let data = (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 文案

    static func describe(_ a: Activity) -> (String, String) {
        switch a {
        case .thinking: return ("思考中", "")
        case .tool(let c, let n): return ("工具 \(c.name)" + (n > 1 ? " ×\(n)" : ""), c.detail.replacingOccurrences(of: "\n", with: " "))
        case .compacting: return ("整理上下文", "")
        case .retrying(let x, let m): return ("重试中 \(x)/\(m)", "")
        case .waitingApproval(let t): return ("等批准" + (t.map { " " + $0.name } ?? ""), t?.detail.replacingOccurrences(of: "\n", with: " ") ?? "")
        case .asking: return ("提问", "")
        case .planReview: return ("计划待审", "")
        case .waitingOther(let s): return ("其他等待", s)
        case .interrupted: return ("被打断", "")
        case .finished: return ("做完了", "")
        case .errored: return ("出错", "")
        case .idle: return ("空闲", "")
        case .dozing: return ("打盹", "")
        case .sleeping: return ("睡着", "")
        }
    }

    static func livenessMark(_ l: String) -> String {
        switch l {
        case "alive": return "✓"
        case "dead": return "✗"
        case "reused": return "≠"
        case "away?": return "?"
        case "away": return "·"
        default: return "?"
        }
    }

    public static func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1e9) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1000 { return String(format: "%.0fK", Double(n) / 1e3) }
        return "\(n)"
    }

    static func clock(_ sec: TimeInterval) -> String {
        let s = sec.isNaN ? 0 : Int(min(max(sec, 0), 1e10))         // 别让极端的时间差（含 NaN）在 Int(…) 换算里 trap
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func age(_ d: Date, _ now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 0 { return "0s" }
        if s < 10 { return String(format: "%.1fs", s) }
        if s < 90 { return "\(Int(s))s" }
        if s < 5400 { return "\(Int(s / 60))m" }
        return String(format: "%.1fh", s / 3600)
    }

    // MARK: 对齐（东亚宽字符占 2 格）

    static func width(_ s: String) -> Int {
        var w = 0
        for u in s.unicodeScalars { w += isWide(u) ? 2 : 1 }
        return w
    }

    static func isWide(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        return (v >= 0x1100 && v <= 0x115F) || (v >= 0x2E80 && v <= 0xA4CF) || (v >= 0xAC00 && v <= 0xD7A3)
            || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0xFE30 && v <= 0xFE6F) || (v >= 0xFF00 && v <= 0xFF60)
            || (v >= 0xFFE0 && v <= 0xFFE6) || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x20000 && v <= 0x3FFFD)
    }

    static func truncate(_ s: String, _ maxWidth: Int) -> String {
        if width(s) <= maxWidth { return s }
        var out = ""
        var w = 0
        for ch in s {
            let cw = ch.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
            if w + cw > maxWidth - 1 { break }
            out.append(ch); w += cw
        }
        return out + "…"
    }

    static func pad(_ s: String, _ w: Int) -> String {
        let t = truncate(s.replacingOccurrences(of: "\n", with: " "), w)
        return t + String(repeating: " ", count: max(0, w - width(t)))
    }
}
