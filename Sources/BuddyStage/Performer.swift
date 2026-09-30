import Foundation
import BuddyCore
import PixelKit
import BuddyArt

public enum BubbleKind: Hashable { case think, approval(String), question, plan, search, book, toolbox, zzz, note, mug }

public struct HelperDraw {
    public var id: String
    public var appearance: Appearance
    public var slot: Int
    public var dx: Int             // 滑入 / 滑出的水平偏移（美术像素）
    public var moving: Bool
    public var time: Double
}

/// 一个工位这一帧要画的一切（Performer 算出来，SeatRenderer 画）。
public struct SeatView {
    public enum Mode { case empty, occupied, dormant }
    public var seat: Int
    public var origin: IntPoint
    public var mode: Mode
    public var appearance: Appearance
    public var rig: RigInput?
    public var mirror = false
    public var screen: ScreenKind = .off
    public var screenT = 0.0
    public var screenSeed = 0
    public var lampOn = false
    public var flag = false
    public var props: [DeskProp] = []
    public var holdClipboard = false
    public var bubble: (kind: BubbleKind, age: Double)? = nil
    public var led = 0                 // 0 关 / 1 绿 / 2 琥珀 / 3 呼吸待机
    public var hitID: UInt16 = 0
    public var glow: RGBA8? = nil
    public var title = ""
    public var status = ""
    public var statusCandidates: [String] = []
    public var dim = false             // 下班工位：桌牌变暗
    public var helperDraws: [HelperDraw] = []   // 旁边的小助手
    public var extraHelpers = 0
    public var chairOut = false        // 人不在座位上，但椅子拉出来（走过来 / 刚起身）
    public var transition = false      // 这一帧在转身 / 过渡（闪烁扫描里允许整块变化）
    public var blink = false           // 这一帧在眨眼（闪烁扫描白名单）
    public var sway = 0.0
    public var boot: Double = 1        // 显示器开机进度 0…1（Bayer 抖动渐变，16 级，300 ms）
    /// 显示器关机：人离开后屏幕上原来的内容用 Bayer 抖动倒放 300 ms 熄灭（progress 0…1 = 熄灭的程度），而不是一帧硬切成黑屏。
    public var fade: (kind: ScreenKind, t: Double, seed: Int, progress: Double)? = nil
}

/// 每个 buddy 一个 Performer：把数据层的 BuddySnapshot 变成「好看的动作」。
/// 规则（任务书 5.6）：姿势最短停留 1.5 s、屏幕 0.8 s、桌牌文字 1.0 s；停留期间只记下最新目标，跳过中间态；
/// 等待类状态持续 0.4 s 才转身，等待结束后再面向你 1.5 s 才转回去；一轮做完先等 0.4 s 再伸懒腰。
public final class Performer {
    public let key: String
    public private(set) var seat: Int
    public private(set) var appearance: Appearance
    public private(set) var snapshot: BuddySnapshot

    // 三个通道：各自的当前值 + 自从何时
    var pose: PoseKind = .idle, poseSince = 0.0
    var screen: ScreenKind = .off, screenSince = 0.0
    var plate = "", plateSince = 0.0
    var bubble: BubbleKind? = nil, bubbleSince = 0.0, bubbleHoldSince = -100.0
    var lastBusyPose: PoseKind = .typing

    // 转身
    var waitSince: Double? = nil
    var waitEndedAt: Double? = nil
    public private(set) var facingUser = false
    var faceStart: Double? = nil
    var unfaceStart: Double? = nil
    var ask: UserAsk = .approval

    // 弹簧
    var sTorso = PixelSpring(period: 0.34), sHeadX = PixelSpring(period: 0.30), sHeadY = PixelSpring(period: 0.30)
    var sLX = PixelSpring(period: 0.26), sLY = PixelSpring(period: 0.26), sRX = PixelSpring(period: 0.26), sRY = PixelSpring(period: 0.26)
    var lastTime = 0.0
    var started = false
    var lastPrivacy: Bool? = nil
    let born: Double
    let seedI: Int
    public var appearedAt: Double { born }

    public init(key: String, snapshot: BuddySnapshot, appearance: Appearance, time: Double) {
        self.key = key; self.snapshot = snapshot; self.appearance = appearance; self.seat = snapshot.seat
        self.born = time
        self.seedI = Int(truncatingIfNeeded: FNV1a64.hash(key) & 0x7FFFFFFF)
        poseSince = time; screenSince = time; plateSince = time; lastTime = time
    }

    public func setAppearance(_ a: Appearance) { appearance = a }

    // MARK: 目标状态
    static func askKind(_ a: Activity) -> UserAsk? {
        switch a {
        case .waitingApproval, .waitingOther: return .approval
        case .asking: return .question
        case .planReview: return .plan
        default: return nil
        }
    }

    func targetPose(now: Date, time: Double) -> PoseKind {
        let s = snapshot
        let el = now.timeIntervalSince(s.activitySince)
        switch s.activity {
        case .thinking: return el > 20 ? .thinkingDeep : .thinking
        case .compacting: return .compacting
        case .retrying: return .retry
        case .tool(let c, _):
            let elapsed = now.timeIntervalSince(c.startedAt)
            switch c.category {
            case .read, .skill: return .mouse
            case .search: return .searching
            case .edit: return .typing
            case .write: return .typingFast
            case .bash: return elapsed > 8 ? .leanBack : (elapsed > 3 ? .restAtDesk : .typing)
            case .monitor: return .leanBack
            case .web: return elapsed > 8 ? .leanBack : ((c.name == "WebSearch" && elapsed < 2.5) ? .typing : .mouse)     // WebSearch：先打字（输入搜索词）再用鼠标（任务书 6.5）
            case .browser, .computer: return .mouse
            case .mcp: return safeInt(elapsed / 3) % 2 == 0 ? .typing : .mouse
            case .delegate: return s.helpers.contains(where: { $0.foreground && !$0.done }) ? .delegate : .typing
            case .todo, .planEnter, .planExit: return .writingPad
            case .sendFile: return .sendFile
            case .schedule: return .alarm
            case .unknown: return safeInt(elapsed / 3) % 2 == 0 ? .typing : .mouse              // 未知工具：打字和鼠标交替（任务书 6.5，和其他 MCP 一样）
            }
        case .waitingApproval, .waitingOther: return .faceUser(.approval)
        case .asking: return .faceUser(.question)
        case .planReview: return .faceUser(.plan)
        case .interrupted: return el < 1.5 ? .shrug : .leanSide
        case .finished:
            if el < 0.4 { return lastBusyPose }
            return el < 1.6 ? .stretch : .leanSide
        case .errored: return .facepalm
        case .idle: return .idle
        case .dozing: return .doze
        case .sleeping: return .sleep
        }
    }

    func targetScreen(now: Date) -> ScreenKind {
        let s = snapshot
        switch s.activity {
        case .thinking: return .ide
        case .compacting: return .compact
        case .retrying(let a, let m): return .retry(a, m)
        case .tool(let c, _):
            let elapsed = now.timeIntervalSince(c.startedAt)
            switch c.category {
            case .read: return .doc(PlateCopy.fileExtension(c.detail))
            case .search: return c.name == "Grep" ? .results : .tree
            case .edit: return .diffEdit
            case .write: return .notebook
            case .bash: return elapsed > 8 ? .terminalLong : .terminal
            case .monitor: return .log
            case .web: return c.name == "WebSearch" ? .search : .browser
            case .browser: return .mcpBrowser
            case .computer: return .desktop
            case .delegate: return .helpers
            case .todo: return .checklist
            case .skill: return c.name == "ToolSearch" ? .iconGrid : .manual
            case .planEnter, .planExit: return .plan
            case .sendFile: return .outbox
            case .schedule: return .clock
            case .mcp: return .mcpApp(c.server ?? "M")
            case .unknown: return .gear
            }
        case .waitingApproval, .waitingOther: return .permission
        case .asking: return .question
        case .planReview: return .plan
        case .interrupted: return .stop
        case .finished: return .done
        case .errored: return .warning
        case .idle: return .idleDesktop
        case .dozing: return .screensaver
        case .sleeping: return .off
        }
    }

    /// 由工具 / 思考的节奏驱动的气泡（可以被最短停留拦住）；等待类和睡觉的气泡不是。
    static func isToolBubble(_ b: BubbleKind?) -> Bool {
        switch b {
        case nil, .think?, .search?, .book?, .toolbox?: return true
        default: return false
        }
    }

    func targetBubble(now: Date) -> BubbleKind? {
        let s = snapshot
        switch s.activity {
        case .thinking: return .think
        case .tool(let c, _):
            switch c.category {
            case .search: return .search
            case .skill: return c.name == "ToolSearch" ? .toolbox : .book
            case .todo, .planEnter: return nil
            default: return nil
            }
        case .waitingApproval(let c): return .approval(iconName(for: c))
        case .waitingOther: return .approval("icon.tool.other")
        case .asking: return .question
        case .planReview: return .plan
        case .dozing, .sleeping: return .zzz
        case .idle: return s.blocked ? .note : nil
        default: return nil
        }
    }

    func iconName(for c: ToolCall?) -> String {
        guard let c = c else { return "icon.tool.other" }
        switch c.category {
        case .bash: return "icon.tool.bash"
        case .edit, .write: return "icon.tool.edit"
        case .web, .browser: return "icon.tool.web"
        case .read, .search: return "icon.tool.file"
        default: return "icon.tool.other"
        }
    }

    // MARK: 每帧更新
    public func update(snapshot s: BuddySnapshot, now: Date, time: Double, privacy: Bool) {
        let prevActivity = snapshot.activity
        snapshot = s
        seat = s.seat
        // App 启动时就在的会话（没有走进来的过程）：姿势 / 屏幕 / 桌牌第一帧就采用真正的目标，不用等最短停留——否则所有人先都是空闲姿势、
        // 屏幕黑着，1.5 秒 / 0.8 秒后一起「啪」地变过来，任务书要的「直接坐好、显示器依次开机」就成了一起硬切。
        let adoptNow = !started && !s.appearedAfterLaunch
        if !started { started = true }
        let dt = max(0, min(0.25, time - lastTime)); lastTime = time
        _ = prevActivity

        // ---- 等待 / 转身状态机 ----
        let asking = Performer.askKind(s.activity)
        if let a = asking {
            ask = a
            waitEndedAt = nil
            if waitSince == nil { waitSince = time }
            if !facingUser, let w = waitSince, time - w >= 0.4 {           // 持续 0.4 s 才转身
                facingUser = true; faceStart = time; unfaceStart = nil
                snapshotResetHands()
            }
        } else {
            waitSince = nil
            if facingUser {
                if waitEndedAt == nil { waitEndedAt = time }
                if let e = waitEndedAt, time - e >= 1.5 {                    // 等待结束后再面向你 1.5 s
                    facingUser = false; unfaceStart = time; faceStart = nil; waitEndedAt = nil
                    poseSince = time
                }
            }
        }

        // ---- 三个通道的最短停留 ----
        var pt = Prof.begin()
        let tp = targetPose(now: now, time: time)
        if case .tool = s.activity { lastBusyPose = tp }
        if case .thinking = s.activity { lastBusyPose = tp }
        // 等待类的「面向你」姿势不走姿势通道（由转身状态机负责）：转身开始之前，身体继续保持原来的样子
        let waitingPose: Bool = { if case .faceUser = tp { return true }; return false }()
        if !waitingPose && tp != pose && (adoptNow || time - poseSince >= 1.5) { pose = tp; poseSince = time }

        let ts = targetScreen(now: now)
        let waitingScreen: Bool = asking != nil
        if ts != screen && (waitingScreen || adoptNow || time - screenSince >= 0.8) { screen = ts; screenSince = time }

        Prof.end("perf.channels", pt)
        pt = Prof.begin()
        // 桌牌文字：只有「动作」部分受 1.0 s 最短停留约束；本轮用时 / token 每帧实时拼（见 seatView）
        let action = actionText(s, now: now, privacy: privacy)
        let privacyToggled = lastPrivacy != nil && lastPrivacy != privacy        // 刚开 / 关隐私模式：文字要当场换，不等最短停留（不然开隐私之后旧文字还挂最多 1 秒，R1b-05）
        lastPrivacy = privacy
        if action != plate {
            // 「数字换了、动作没换」（计时器在走）不算换动作，直接更新；这里才需要把数字抹掉比较（多数帧不会走到这里）
            let actionKind = Performer.digitMask(action), plateKind = Performer.digitMask(plate)
            if plate.isEmpty || asking != nil || privacyToggled || actionKind == plateKind || time - plateSince >= 1.0 {
                if actionKind != plateKind || plate.isEmpty { plateSince = time }
                plate = action
            }
        }

        Prof.end("perf.plate", pt)
        pt = Prof.begin()
        let tb = targetBubble(now: now)
        if tb != bubble {
            // 工具节奏驱动的气泡（放大镜 / 书 / 工具箱 / 思考 / 没有气泡）也遵守 0.8 s 最短停留（和屏幕通道同一规则）：
            // Grep / Read 每 0.3 s 交替时气泡不能跟着一闪一闪（R1b-04）；等待类气泡（钥匙 / 问号 / 计划 / 便利贴 / zzz）立即，不受限
            let held = !adoptNow && Performer.isToolBubble(bubble) && Performer.isToolBubble(tb) && time - bubbleHoldSince < 0.8
            if !held {
                if bubble == nil || tb == nil { bubbleSince = time }
                bubble = tb; bubbleHoldSince = time
            }
        }

        syncHelpers(time: time)
        for k in Array(helperTracks.keys) { helperTracks[k]!.spring.step(dt) }
        Prof.end("perf.helpers", pt)
        pt = Prof.begin()
        stepSprings(now: now, time: time, dt: dt)
        Prof.end("perf.springs", pt)
    }

    /// 把「计数器位置」的数字抹成 `#`，用来判断「数字换了、动作没换」（计时器在走，不受 1.0 s 最短停留约束）。
    /// 只抹：最后一个「 · 」之后的整段（计时 / 用时：`1:23`、`12 秒`、`3分12秒`）、`重试中 a/m`、` ×N`、`派了 N 个帮手`、`打盹 N 分钟 / 小时`；
    /// 文件名 / 命令 / 搜索词里的数字保留——它们变了就是换了动作（`part1.txt` → `part2.txt`），要受最短停留约束（R1b-02）。
    static func digitMask(_ s: String) -> String {
        var head = s, tail = ""
        if let r = head.range(of: " · ", options: .backwards) { tail = String(head[r.upperBound...]); head = String(head[..<r.upperBound]) }
        return maskCounters(head) + maskRuns(tail)
    }

    /// 前缀后面紧跟的 `[0-9/]` 抹成 `#`（只处理最后一次出现）。
    private static func maskCounters(_ h: String) -> String {
        var out = h
        for p in ["重试中 ", " ×", "派了 ", "打盹 "] {
            guard let r = out.range(of: p, options: .backwards) else { continue }
            var end = r.upperBound
            while end < out.endIndex, let a = out[end].asciiValue, (a >= 48 && a <= 57) || a == 47 { end = out.index(after: end) }
            if end > r.upperBound { out.replaceSubrange(r.upperBound..<end, with: "#") }
        }
        return out
    }

    /// 把连续的数字 / 冒号抹成 `#`（等价于正则 `[0-9:]+` → `#`，但不用每次编译正则）。
    private static func maskRuns(_ s: String) -> String {
        var out = [UInt8](); out.reserveCapacity(s.utf8.count)
        var inRun = false
        for b in s.utf8 {
            if (b >= 48 && b <= 57) || b == 58 { if !inRun { out.append(35); inRun = true } }
            else { inRun = false; out.append(b) }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// 动作文案按「秒」缓存：文字里的时间只到秒，一秒内不会变；数据（活动、帮手、隐私）变了就重算。
    struct ActionKey: Equatable {
        var activity: Activity, since: Date, blocked: Bool, lastTurn: Double?, idleSince: Date?, helpers: Int, privacy: Bool
    }
    var actionCache: (sec: Int, key: ActionKey, text: String)?
    func actionText(_ s: BuddySnapshot, now: Date, privacy: Bool) -> String {
        let sec = Int(now.timeIntervalSinceReferenceDate.rounded(.down))
        var hs = 0
        for h in s.helpers { hs = hs &* 5 &+ 1 &+ (h.foreground ? 1 : 0) &+ (h.done ? 2 : 0) }
        let key = ActionKey(activity: s.activity, since: s.activitySince, blocked: s.blocked, lastTurn: s.lastTurnDuration, idleSince: s.idleSince, helpers: hs, privacy: privacy)
        if let c = actionCache, c.sec == sec, c.key == key { return c.text }
        let t = PlateCopy.activity(s, now: now, privacy: privacy)
        actionCache = (sec, key, t)
        return t
    }
    var candidateCache: (sec: Int, plate: String, turn: Date?, tokens: Int, phase: Phase, out: [String])?
    func statusCandidates(now: Date) -> [String] {
        let sec = Int(now.timeIntervalSinceReferenceDate.rounded(.down))
        let s = snapshot
        if let c = candidateCache, c.sec == sec, c.plate == plate, c.turn == s.turnStartedAt, c.tokens == s.tokens.total, c.phase == s.phase { return c.out }
        let out = PlateCopy.statusCandidates(action: plate, s, now: now)
        candidateCache = (sec, plate, s.turnStartedAt, s.tokens.total, s.phase, out)
        return out
    }

    /// 现在有没有需要 30 fps 才画得顺的运动：转身（每步只有 60–90 ms）、气泡弹出（三档各 60 ms）、
    /// 小助手滑进 / 滑出（几十个像素）、刚坐下开机。其余的（手 / 头 / 身体的弹簧 1–3 像素的位移、打字、呼吸、眨眼）
    /// 15 fps 就够：位移本来就取整到整像素，几格之内走完。
    public func needsFullRate(time: Double) -> Bool {
        if unfaceStart != nil { return true }
        if let fs = faceStart, facingUser, time - fs < 0.9 { return true }
        if let w = waitSince, !facingUser, time - w < 0.5 { return true }
        if bubble != nil, time - bubbleSince < 0.15 { return true }
        if time - born < 0.6 { return true }
        for t in helperTracks.values where !t.spring.isSettled || t.leftAt != nil { return true }
        return false
    }

    func snapshotResetHands() {
        sLX.snap(to: sLX.target); sLY.snap(to: sLY.target); sRX.snap(to: sRX.target); sRY.snap(to: sRY.target)
    }

    // 当前姿势帧（含转身期间的覆盖）
    struct Resolved { var frame: PoseFrame; var chairFacing: Facing?; var turning: Bool }
    func resolveFrame(time: Double) -> Resolved {
        let gt = time
        if facingUser, let fs = faceStart {
            let e = time - fs
            let steps: [(Facing, Double, Double)] = [(.back, 0.08, 1), (.threeQuarterBack, 0.07, 0), (.side, 0.06, 0), (.threeQuarterFront, 0.07, 0), (.front, 0.09, 0), (.front, 0.08, -1)]
            var acc = 0.0
            for (f, d, dy) in steps {
                if e < acc + d {
                    var fr = PoseFrame(); fr.facing = f; fr.torsoDy = dy
                    fr.handL = nil; fr.handR = nil
                    return Resolved(frame: fr, chairFacing: f, turning: true)
                }
                acc += d
            }
            let after = e - acc
            var fr = PoseLibrary.frame(.faceUser(ask), t: after, gt: gt, seed: seedI)
            // 面向你的时候脸上有表情：等批准先是平静地挥手，等久了着急，再久就困了；提问是疑问；计划做好了是开心
            let waited = time - (waitSince ?? fs)
            switch ask {
            case .approval: fr.expression = waited > 120 ? "sleepy" : (waited > 10 ? "worried" : nil)
            case .question: fr.expression = waited > 300 ? "sleepy" : "question"
            case .plan: fr.expression = waited > 300 ? "sleepy" : "happy"
            }
            // 举手 3 帧（70/70/90 ms），过冲 1 像素后回落：由手的弹簧完成
            return Resolved(frame: fr, chairFacing: .front, turning: false)
        }
        if let us = unfaceStart {
            let e = time - us
            let steps: [(Facing, Double, Double)] = [(.front, 0.07, 0), (.threeQuarterFront, 0.07, 0), (.side, 0.06, 0), (.threeQuarterBack, 0.07, 0), (.back, 0.08, 1)]
            var acc = 0.0
            for (f, d, dy) in steps {
                if e < acc + d { var fr = PoseFrame(); fr.facing = f; fr.torsoDy = dy; return Resolved(frame: fr, chairFacing: f, turning: true) }
                acc += d
            }
            unfaceStart = nil
        }
        let fr = PoseLibrary.frame(pose, t: time - poseSince, gt: gt, seed: seedI)
        return Resolved(frame: fr, chairFacing: nil, turning: false)
    }

    struct HelperTrack { var born: Double; var spring: PixelSpring; var leftAt: Double?; var appearance: Appearance; var slot: Int }
    var helperTracks: [String: HelperTrack] = [:]
    var extraHelpers = 0

    func syncHelpers(time: Double) {
        let active = snapshot.helpers.filter { !$0.done }
        let ids = Set(active.map { $0.id })
        for h in active where helperTracks[h.id] == nil {
            let seed = AppearanceSeed.seed(key: h.id + key, salt: 3)
            var sp = PixelSpring(value: 0, period: 0.5)
            let slot = (0..<3).first { s in !helperTracks.values.contains { $0.slot == s && $0.leftAt == nil } } ?? 2
            let fromRight = slot != 0
            sp.snap(to: fromRight ? 40 : -40); sp.target = 0
            helperTracks[h.id] = HelperTrack(born: time, spring: sp, leftAt: nil, appearance: Appearance.generate(seed: seed), slot: slot)
        }
        for (id, var t) in helperTracks {
            if !ids.contains(id) && t.leftAt == nil { t.leftAt = time; t.spring.target = t.slot == 0 ? -40 : 40; helperTracks[id] = t }
            if let l = t.leftAt, time - l > 0.6 { helperTracks.removeValue(forKey: id) }
        }
        extraHelpers = max(0, active.count - 3)
    }

    var lastFrame = PoseFrame()
    var lastFacingSeen: Facing = .back
    var facingChangedAt = -10.0
    func stepSprings(now: Date, time: Double, dt: Double) {
        let r = resolveFrame(time: time)
        var f = r.frame
        // 呼吸：4 秒一个周期，1 像素（带迟滞，不会在半像素附近来回跳）
        let breath = breathPhase(time + Double(seedI % 40) / 10, period: 4.0)
        if breath > 0.62 { breathDy = 1 } else if breath < 0.38 { breathDy = 0 }
        f.torsoDy += Double(breathDy) * (pose == .sleep ? 0 : 0.0)   // 躯干呼吸交给头：头随呼吸上下 1 像素
        lastFrame = f
        let restL = Spots.restL, restR = Spots.restR
        let hl = f.handL ?? restL, hr = f.handR ?? restR
        sTorso.target = f.torsoDy; sHeadX.target = f.headDx; sHeadY.target = f.headDy
        sLX.target = hl.x; sLY.target = hl.y; sRX.target = hr.x; sRY.target = hr.y
        if !springsInit {
            sTorso.snap(to: f.torsoDy); sHeadX.snap(to: f.headDx); sHeadY.snap(to: f.headDy)
            sLX.snap(to: hl.x); sLY.snap(to: hl.y); sRX.snap(to: hr.x); sRY.snap(to: hr.y)
            springsInit = true
        }
        // 转身期间朝向 / 身体高度是硬切的序列帧（不经过弹簧），手回到自然位置
        if r.turning { sLX.snap(to: restL.x); sLY.snap(to: restL.y); sRX.snap(to: restR.x); sRY.snap(to: restR.y); sTorso.snap(to: f.torsoDy) }
        sTorso.step(dt); sHeadX.step(dt); sHeadY.step(dt)
        sLX.step(dt); sLY.step(dt); sRX.step(dt); sRY.step(dt)
    }
    var breathDy = 0
    var springsInit = false
    var hairLagX = 0, hairLagY = 0
    var prevHeadX = 0, prevHeadY = 0

    /// 眨眼：每 5–8 秒一次（两次间隔 5.4 s 和 7.4 s 交替，各个 buddy 相位不同），3 帧共 260 ms（半闭 90 ms → 闭 80 ms → 半闭 90 ms），只动眼睛。
    func blinkExpression(time: Double, facing: Facing) -> String? {
        guard facing == .front || facing == .threeQuarterFront || facing == .side else { return nil }
        let cycle = 12.8
        var t = (time + Double(seedI % 1280) / 100).truncatingRemainder(dividingBy: cycle)
        if t >= 5.4 { t -= 5.4 }
        if t < 0.09 || (t >= 0.17 && t < 0.26) { return "blinkHalf" }
        if t >= 0.09 && t < 0.17 { return "blinkClosed" }
        return nil
    }

    // MARK: 画面输入
    /// mirror：这个显示面里，这个人朝哪边转（true = 向画面左侧转）。每个显示面自己决定（离画面中线近的一侧是过道）。
    public func seatView(origin: IntPoint, time: Double, now: Date, light: LightState, hitID: UInt16, privacy: Bool, mirror: Bool) -> SeatView {
        let r = resolveFrame(time: time)
        let f = r.frame
        var v = SeatView(seat: seat, origin: origin, mode: .occupied, appearance: appearance)
        var ri = RigInput(appearance: appearance)
        ri.facing = f.facing
        ri.chairFacing = r.chairFacing
        let headDx = sHeadX.shown, headDy = sHeadY.shown
        ri.torsoDy = sTorso.shown
        ri.headDx = headDx; ri.headDy = headDy + breathDy
        // 头发和头同步：任务书想要「头发比头晚 1 帧」的跟随感，但 1 像素的头部位移加上 1 帧的头发滞后，
        // 会在头 / 发交界处留下 1 帧的错位，闪烁扫描（A→B→A）会抓到，也确实像闪一下。头本身已经由弹簧带动、比躯干晚，跟随感够了。
        ri.hairDx = headDx; ri.hairDy = headDy + breathDy
        let usesHands = !r.turning
        if usesHands {
            ri.handL = IntPoint(sLX.shown + f.oscL.x, sLY.shown + f.oscL.y)
            ri.handR = IntPoint(sRX.shown + f.oscR.x, sRY.shown + f.oscR.y)
        }
        ri.bendL = f.bendL; ri.bendR = f.bendR
        ri.expression = f.expression ?? blinkExpression(time: time, facing: f.facing)
        v.rig = ri
        if f.facing != lastFacingSeen { lastFacingSeen = f.facing; facingChangedAt = time }
        v.transition = r.turning || abs(time - poseSince) < 0.05 || abs(time - (faceStart ?? -9)) < 1.0 || time - facingChangedAt < 0.15
        v.blink = (ri.expression ?? "").hasPrefix("blink")
        v.mirror = (f.facing == .back && r.chairFacing == nil) ? false : mirror
        v.props = f.props
        v.holdClipboard = f.holdClipboard
        v.screen = screen
        v.screenT = time - screenSince
        v.screenSeed = seedI % 977
        v.lampOn = { if case .idle = snapshot.activity { return light.darkness > 0.5 }; if case .sleeping = snapshot.activity { return false }; return snapshot.phase != .idle || light.darkness > 0.5 }()
        v.flag = snapshot.unread
        if let b = bubble { v.bubble = (b, time - bubbleSince) }
        v.hitID = hitID
        v.led = { switch snapshot.activity { case .sleeping: return 3; case .waitingApproval, .asking, .planReview, .waitingOther: return 2; case .idle, .dozing, .finished, .interrupted, .errored: return snapshot.phase == .idle ? 3 : 1; default: return 1 } }()
        v.glow = light.darkness > 0.2 ? ScreenContent.glowColor(screen) : nil
        v.title = snapshot.title
        v.status = plate
        v.statusCandidates = statusCandidates(now: now)
        v.helperDraws = helperTracks.map { (id, t) in
            HelperDraw(id: id, appearance: t.appearance, slot: t.slot, dx: t.spring.shown, moving: !t.spring.isSettled, time: time - t.born)
        }.sorted { ($0.slot, -$0.time, $0.id) < ($1.slot, -$1.time, $1.id) }      // 同一个槽位里的先后要固定（否则字典顺序一变，两个小助手的前后遮挡会互换）
        v.extraHelpers = extraHelpers
        return v
    }
}
