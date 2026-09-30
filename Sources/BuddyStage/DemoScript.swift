import Foundation
import BuddyCore

/// 演示剧本：6 个假 buddy 把所有状态演一遍。纯函数：（时间, 基准时刻）→ 快照。
/// 用来做无头快照、金图测试、闪烁扫描，也是 App 里「演示模式」的数据源。
public enum DemoScript {
    public static let duration = 80.0

    struct Beat {
        var t: Double
        var activity: (Date) -> Activity          // 参数是这一拍开始的时刻
        var turnStart: Double? = nil               // 这一轮从什么时候开始（busy / waiting 时）
        var unread = false
        var blocked = false
        var helpers: [HelperSnapshot] = []
        var finishedAfter: Double? = nil
        var interrupted = false
    }

    struct Actor {
        var key: String, seat: Int, title: String, origin: SessionOrigin, family: ModelFamily
        var beats: [Beat]
        var arrive: Double? = nil                  // App 启动之后才到（走进来）
        var leave: Double? = nil                   // 之后离场（下班工位）
    }

    static func tool(_ name: String, _ detail: String = "", par: Int = 1) -> (Date) -> Activity {
        { d in .tool(ToolCatalog.makeCall(name: name, detail: detail, at: d), parallel: par) }
    }
    static func fixed(_ a: Activity) -> (Date) -> Activity { { _ in a } }

    static let actors: [Actor] = [
        Actor(key: "d:local_demo0", seat: 0, title: "重构登录模块", origin: .desktop, family: .claude, beats: [
            Beat(t: 0, activity: fixed(.thinking), turnStart: 0),
            Beat(t: 4, activity: tool("Read", "/Users/demo/app/src/auth/LoginView.swift"), turnStart: 0),
            Beat(t: 8, activity: tool("Grep", "TODO", par: 2), turnStart: 0),
            Beat(t: 11, activity: tool("Glob", "**/*.swift"), turnStart: 0),
            Beat(t: 14, activity: tool("Edit", "/Users/demo/app/src/auth/LoginView.swift"), turnStart: 0),
            Beat(t: 19, activity: tool("Write", "/Users/demo/app/src/auth/Session.swift"), turnStart: 0),
            Beat(t: 23, activity: tool("Bash", "cd ~/app && npm test -- --watch"), turnStart: 0),
            Beat(t: 40, activity: { d in .waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push origin main", at: d)) }, turnStart: 0),
            Beat(t: 49, activity: fixed(.asking), turnStart: 0),
            Beat(t: 56, activity: fixed(.planReview), turnStart: 0),
            Beat(t: 63, activity: fixed(.finished), unread: true, blocked: true, finishedAfter: 63),
            Beat(t: 68.5, activity: fixed(.idle), unread: true, blocked: true, finishedAfter: 63),
            Beat(t: 74, activity: fixed(.thinking), turnStart: 74),
        ]),
        Actor(key: "d:local_demo1", seat: 1, title: "论文引用检查", origin: .desktop, family: .claude, beats: [
            Beat(t: 0, activity: fixed(.idle)),
            Beat(t: 2, activity: tool("WebFetch", "https://www.nature.com/articles/s41586-024-07487-w"), turnStart: 2),
            Beat(t: 8, activity: tool("WebSearch", "hydrogen embrittlement steel review"), turnStart: 2),
            Beat(t: 14, activity: tool("Agent", "调研三篇文献"), turnStart: 2, helpers: [
                HelperSnapshot(id: "a1", description: "读文献 A", foreground: true, active: true),
                HelperSnapshot(id: "a2", description: "读文献 B", foreground: true, active: true),
                HelperSnapshot(id: "a3", description: "读文献 C", foreground: true, active: true)]),
            Beat(t: 26, activity: tool("Agent", "整理引用格式"), turnStart: 2, helpers: [
                HelperSnapshot(id: "b1", description: "格式整理", foreground: false, active: true)]),
            Beat(t: 34, activity: fixed(.compacting), turnStart: 2),
            Beat(t: 40, activity: fixed(.retrying(attempt: 2, max: 10)), turnStart: 2),
            Beat(t: 46, activity: fixed(.errored), finishedAfter: 46),
            Beat(t: 50, activity: fixed(.thinking), turnStart: 50),
            Beat(t: 55, activity: fixed(.interrupted), interrupted: true),
            Beat(t: 59, activity: fixed(.idle)),
        ]),
        Actor(key: "t:demo2", seat: 2, title: "健身计划 app", origin: .terminal, family: .claude, beats: [
            Beat(t: 0, activity: tool("TodoWrite"), turnStart: 0),
            Beat(t: 5, activity: tool("Skill", "brainstorming"), turnStart: 0),
            Beat(t: 9, activity: tool("ToolSearch", "select:Read"), turnStart: 0),
            Beat(t: 13, activity: tool("mcp__Claude_Browser__navigate", ""), turnStart: 0),
            Beat(t: 18, activity: tool("mcp__computer-use__app_click", ""), turnStart: 0),
            Beat(t: 23, activity: tool("mcp__notion__search_pages", ""), turnStart: 0),
            Beat(t: 28, activity: tool("SendUserFile", "/tmp/plan.md"), turnStart: 0),
            Beat(t: 32, activity: tool("ScheduleWakeup", ""), turnStart: 0),
            Beat(t: 36, activity: tool("Monitor", "tail -f log"), turnStart: 0),
            Beat(t: 42, activity: tool("EnterPlanMode", ""), turnStart: 0),
            Beat(t: 48, activity: tool("FooTool", ""), turnStart: 0),
            Beat(t: 54, activity: fixed(.thinking), turnStart: 0),
        ]),
        Actor(key: "t:demo3", seat: 3, title: "DeepSeek 试验", origin: .terminal, family: .deepseek, beats: [
            Beat(t: 0, activity: tool("Read", "/Users/demo/lab/notes.md"), turnStart: 0),
            Beat(t: 6, activity: tool("Edit", "/Users/demo/lab/run.py"), turnStart: 0),
            Beat(t: 14, activity: tool("Bash", "python3 run.py --epochs 3"), turnStart: 0),
            Beat(t: 22, activity: { d in .waitingApproval(tool: ToolCatalog.makeCall(name: "Edit", detail: "/etc/hosts", at: d)) }, turnStart: 0),
            Beat(t: 34, activity: tool("Grep", "loss"), turnStart: 0),
            Beat(t: 40, activity: fixed(.finished), unread: true, finishedAfter: 40),
            Beat(t: 45, activity: fixed(.idle), unread: true, finishedAfter: 40),
        ]),
        Actor(key: "t:demo4", seat: 4, title: "打盹的会话", origin: .terminal, family: .glm, beats: [
            Beat(t: 0, activity: fixed(.idle)),
            Beat(t: 20, activity: fixed(.dozing)),
            Beat(t: 42, activity: fixed(.sleeping)),
        ]),
        Actor(key: "d:local_demo5", seat: 5, title: "新来的同事", origin: .desktop, family: .claude, beats: [
            Beat(t: 15, activity: fixed(.thinking), turnStart: 15),
            Beat(t: 20, activity: tool("Bash", "swift build"), turnStart: 15),
            Beat(t: 30, activity: tool("Edit", "/Users/demo/x/main.swift"), turnStart: 15),
            Beat(t: 45, activity: fixed(.idle)),
        ], arrive: 15, leave: 60),
    ]

    /// 在剧本时间 t（秒）时的快照。present = 在场的；dormant = 下班工位。
    public static func snapshots(at t: Double, base: Date) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) {
        var present: [BuddySnapshot] = [], dormant: [BuddySnapshot] = []
        for a in actors {
            if let arr = a.arrive, t < arr { continue }
            var s = BuddySnapshot(key: a.key, seat: a.seat, salt: 0, title: a.title, sessionId: a.key, origin: a.origin, now: base)
            s.modelFamily = a.family
            s.cwd = "/Users/demo/\(a.title)"
            s.modelName = a.family == .claude ? "claude-opus-5" : (a.family == .deepseek ? "deepseek-v4" : "glm-5")
            s.effort = "high"; s.permissionMode = "default"; s.cliVersion = "2.1.284"
            s.appearedAfterLaunch = a.arrive != nil
            if let lv = a.leave, t >= lv {
                s.presence = .away(since: base.addingTimeInterval(lv), dormant: a.origin == .desktop)
                if a.origin == .desktop { dormant.append(s) }
                continue
            }
            guard let beat = a.beats.last(where: { $0.t <= t }) ?? a.beats.first else { continue }
            let start = base.addingTimeInterval(beat.t)
            let act = beat.activity(start)
            s.activity = act; s.phase = act.phase
            s.activitySince = start
            s.unread = beat.unread; s.blocked = beat.blocked; s.helpers = beat.helpers
            if let ts = beat.turnStart, act.phase != .idle { s.turnStartedAt = base.addingTimeInterval(ts) }
            if let fa = beat.finishedAfter { s.lastTurnEndedAt = base.addingTimeInterval(fa); s.lastTurnDuration = max(1, fa - (a.beats.first?.t ?? 0)) }
            if act.phase == .idle { s.idleSince = start }
            let k = max(0, t)
            s.tokens = TokenBreakdown(input: Int(k * 2000), output: Int(k * 1500), cacheWrite: Int(k * 90_000), cacheRead: Int(k * 140_000))
            s.contextTokens = Int(k * 6000)
            s.hookActive = true
            present.append(s)
        }
        return (present, dormant)
    }

    /// 检查 / 压力测试用的快照来源（snapshot / gif / flicker / verify / bench / `--demo-mode`）：demo = 演示剧本本身（t 是剧本秒数，到头了从头再来）；
    /// busy6 = 6 个人一直忙（工具轮换）；idle6 = 6 个人都空闲；crowdN = 把演示角色复制成 N 个人（默认 12，检查「+N」用）。
    public static func snapshots(mode: String, t rawT: Double, base: Date) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) {
        let t = rawT.isFinite ? max(0, min(rawT, 1e9)) : 0               // 负数 / NaN / 天文数字的时间会让下面的 Int(t / 5) % n 出负下标或直接陷阱
        let tools: [(String, String)] = [("Read", "/Users/demo/a.swift"), ("Edit", "/Users/demo/b.swift"), ("Bash", "swift build"), ("Grep", "TODO"),
                                          ("Write", "/Users/demo/c.swift"), ("WebSearch", "swift concurrency"), ("Glob", "**/*.swift")]
        switch mode {
        case "busy6", "idle6":
            var (p, d) = snapshots(at: 20, base: base)
            for i in p.indices {
                if mode == "idle6" {
                    p[i].activity = .idle; p[i].phase = .idle; p[i].turnStartedAt = nil; p[i].helpers = []; p[i].unread = false
                    p[i].idleSince = base
                } else {
                    let (n, dt) = tools[(Int(t / 5) + i) % tools.count]
                    let start = base.addingTimeInterval(floor(t / 5) * 5)
                    p[i].activity = .tool(ToolCatalog.makeCall(name: n, detail: dt, at: start), parallel: 1)
                    p[i].phase = .busy; p[i].activitySince = start; p[i].turnStartedAt = base; p[i].helpers = []
                }
            }
            return (p, d)
        case "empty":
            return ([], [])           // 一个会话都没有：办公室里的「今天还没人上班」牌子
        case _ where mode.hasPrefix("crowd"):
            // 检查用：把演示角色复制成 N 个（crowd12 = 12 个，默认 12），一号位带 5 个前台小助手——
            // 看小鱼缸的「+N」、办公室多列排布、小助手的「+N」。
            // crowd12 = 12 个人；crowd10d4 = 10 个座位，其中最后 4 个是下班工位（衣帽架上挂 4 件外套）
            let parts = mode.dropFirst(5).split(separator: "d", omittingEmptySubsequences: false)
            let n = min(200, max(1, Int(parts.first ?? "") ?? 12)), away = max(0, min(n, Int(parts.count > 1 ? parts[1] : "") ?? 0))        // 开发参数也夹一下：crowd5d-3 原来是 8..<5 崩溃，crowd99999999 会分配几十 GB
            var (p, d) = snapshots(at: t.truncatingRemainder(dividingBy: duration), base: base)
            let src = p
            // 后面几个人用「刁钻」的标题和数字：很长的中文、很长的英文、emoji、全角字符、单个字、超大 token 数、超长的一轮——检查桌牌 / 卡片的文字会不会溢出、重叠
            let edgeTitles = ["这是一个非常非常长的会话标题用来测试文字会不会溢出牌子", "Refactor authentication middleware for OAuth2 PKCE flow", "🚀 发布 v2.0 ✨ 上线",
                              "a", "全角ＡＢＣ１２３ mixed 中英文 Mixed", "会话 1a2b3c4d"]
            while p.count < n {
                var s = src[p.count % src.count]
                s.key += "#\(p.count)"; s.sessionId = s.key; s.seat = p.count; s.salt = UInt64(p.count)
                let k = p.count - src.count
                s.title = k >= 0 ? edgeTitles[k % edgeTitles.count] : "同事 \(p.count + 1)"; s.helpers = []
                if k >= 0 {
                    if case .retrying = s.activity { s.activity = .retrying(attempt: 10, max: 10) }        // 「10/10」：像素数字最宽的一种
                    s.tokens = TokenBreakdown(input: 12_345_678, output: 234_567_890, cacheWrite: 345_678_901, cacheRead: 1_234_567_890)
                    if s.phase != .idle { s.turnStartedAt = base.addingTimeInterval(-3725) }
                }
                p.append(s)
            }
            if p.count > 1, p[1].phase == .busy {
                p[1].helpers = (1...5).map { HelperSnapshot(id: "c\($0)", description: "并行任务 \($0)", foreground: true, active: true) }
            }
            p = Array(p.prefix(n))
            for i in (n - away)..<n where away > 0 {
                var s = p[i]
                s.presence = .away(since: base.addingTimeInterval(-600), dormant: true)
                s.activity = .idle; s.phase = .idle; s.turnStartedAt = nil; s.helpers = []; s.unread = false
                d.append(s)
            }
            return (Array(p.prefix(n - away)), d)
        default:
            return snapshots(at: t.truncatingRemainder(dividingBy: duration), base: base)
        }
    }
}

/// 演示用的数据提供者：按剧本时钟（可 1–4 倍速）推送快照。
public final class MockSource: SnapshotProvider {
    public var onUpdate: (([BuddySnapshot]) -> Void)?
    public var onEvent: ((BuddyEvent) -> Void)?
    public var speed: Double = 1
    /// demo（默认，演示剧本）/ busy6 / idle6（压力测试）
    public var mode = "demo"
    var timer: Timer?
    var t0 = Date()
    let base: Date
    public init(speed: Double = 1, mode: String = "demo") {
        self.speed = speed.isFinite ? max(0.05, min(16, speed)) : 1           // --speed -1 / nan / inf 原来会让 Int(t / 5) 变负数、% 出负下标崩溃
        self.mode = mode; base = Date()
    }
    public func start() {
        t0 = Date()
        let tm = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common); timer = tm
    }
    public func stop() { timer?.invalidate(); timer = nil }
    public func markSeen(key: String) {}
    /// 「换个造型」：和真实数据一样把这个人的盐 +1（演示数据里盐是剧本给的，这里叠一个偏移量）。
    var saltBump: [String: UInt64] = [:]
    public func rerollAppearance(key: String) { saltBump[key, default: 0] &+= 1 }
    public func diagnostics() -> DiagnosticsInfo { var d = DiagnosticsInfo(); d.sourceStatus = ["演示模式：数据来自内置剧本"]; return d }
    public var scriptTime: Double { max(0, (Date().timeIntervalSince(t0) * speed).truncatingRemainder(dividingBy: DemoScript.duration)) }
    func tick() {
        let st = scriptTime
        let base = Date().addingTimeInterval(-st)
        let s = mode == "demo" ? DemoScript.snapshots(at: st, base: base) : DemoScript.snapshots(mode: mode, t: st, base: base)
        onUpdate?((s.present + s.dormant).map { var x = $0; x.salt &+= saltBump[x.key] ?? 0; return x })
    }
}
