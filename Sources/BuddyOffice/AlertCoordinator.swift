import AppKit
import BuddyCore
import BuddyStage
import PixelKit

/// 提醒用到的那几项设置（拷成一个值：判定逻辑不直接碰 UserDefaults，测试直接喂）。
struct AlertConfig: Equatable {
    var permission = true, question = true, finished = true, error = false
    var finishedMinSeconds = 30
    var includeDesktop = true, suppressWhenFocused = true
    init() {}
    init(settings s: Settings) {
        permission = s.bool("notify.permission"); question = s.bool("notify.question"); finished = s.bool("notify.finished"); error = s.bool("notify.error")
        finishedMinSeconds = s.int("notify.finishedMinSeconds")
        includeDesktop = s.bool("notify.includeDesktop"); suppressWhenFocused = s.bool("notify.suppressWhenFocused")
    }
}

/// 提醒里显示的文字：会话标题统一走这里（提示卡 / 系统通知 / 菜单 / 右键菜单）。
enum AlertText {
    static let maxTitleChars = 40
    /// 隐私模式只写「会话」；空白标题用占位（不出一行空白）；换行 / 制表符换成空格；最多 40 个字。
    static func title(_ raw: String, privacy: Bool) -> String {
        if privacy { return "会话" }
        let flat = PlateCopy.displayTitle(raw).split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
        let t = flat.trimmingCharacters(in: .whitespaces)
        return t.count <= maxTitleChars ? t : String(t.prefix(maxTitleChars)) + "…"
    }

    /// 「想用 <工具>[：<命令>]（等你批准）」——工具名和命令是数据里来的，可以很长；提示卡单行放不下（fits 为 false）时
    /// 依次：截短命令（保留开头）→ 去掉命令 → 截短工具名 → 退到通用文案。放得下的原样返回。
    static func approvalBody(tool: String, command: String, fits: (String) -> Bool = ToastFit.bodyFits) -> String {
        func body(_ t: String, _ c: String) -> String { "想用 \(t)\(c.isEmpty ? "" : "：" + c)（等你批准）" }
        let full = body(tool, command)
        if fits(full) { return full }
        var c = command
        while c.count > 4 {
            c = String(c.dropLast(c.count > 16 ? 3 : 1))
            let cand = body(tool, c.trimmingCharacters(in: .whitespaces) + "…")
            if fits(cand) { return cand }
        }
        let bare = body(tool, "")
        if !command.isEmpty, fits(bare) { return bare }
        var t = tool
        while t.count > 3 {
            t = String(t.dropLast())
            let cand = "想用 \(t)…（等你批准）"
            if fits(cand) { return cand }
        }
        return "有个权限请求（等你批准）"
    }
}

/// 提示卡（ToastCard）单行放不放得下：用 ToastCard 自己产出的文字项（样式、最大宽度都取它的）+ TextRenderer 出图，看有没有被省略号截断。
enum ToastFit {
    static func bodyFits(_ body: String) -> Bool {
        let card = ToastCard.make(kind: .approval, title: "会话", body: body, zoom: 2)
        guard let item = card.texts.last, let img = TextRenderer.shared.image(item.text, style: item.style, scale: 2, maxWidth: item.maxWidth) else { return false }
        return !img.truncated
    }
}

/// 提醒的判定逻辑（任务书 7.2）：只看快照的变化，不依赖数据层发事件，所以真实数据和演示数据都能用。时钟由调用方传进来（observe 的 now），测试用假时钟。
///  · 等批准 / 提问 / 计划待审：连续等待满 1.5 s 才提醒（Dock 弹跳也一样）；
///  · 做完了：这一轮 ≥ 30 s 且没被打断；桌面会话最多等 8 s（本轮总结约 7 s 后才落盘）看有没有变成 blocked（→「需要你处理」），
///    这 8 s 里下一轮已经开始了就不发；
///  · 出错：默认关闭；
///  · 不打扰：桌面会话 Claude 在最前且这个会话是最近聚焦的 → 不提醒；终端会话宿主 App 在最前 → 先等 8 s 再判断一次（等待类和做完了都一样）；
///    用户「隐藏」的 buddy（muted）→ 什么提醒都没有（不弹窗 / 不响铃 / 不计入角标和菜单栏 / 不让 Dock 弹跳），但白板的「正」字照常数；
///  · 节流：同一个 buddy 同一类提醒 20 s 内最多一条；2 s 内连着来几条，合并成一条「N 位同事……」。
final class AlertCoordinator {
    enum Attention: Equatable { case approval, question, plan, other }
    struct Episode { var kind: Attention; var since: Date; var alerted = false; var bounced = false; var deferredUntil: Date? }
    struct FinishedPending { var since: Date; var duration: TimeInterval; var deferredUntil: Date? }
    enum Output {
        case post(key: String, kind: ToastCard.Kind, title: String, body: String)
        case clear(key: String)
    }

    /// 任务书 7.2 的几个时间常数（秒）。
    static let debounce: TimeInterval = 1.5, throttleWindow: TimeInterval = 20, mergeWindow: TimeInterval = 2
    /// 上一张合并卡在屏幕上的时间（提示卡 6 秒后收回）：在这段时间里又来的、和它连在一起的提醒，人数要把它已经合并进去的人也算上。
    static let mergeCarry: TimeInterval = 6
    /// 宿主 App 在最前面时先等这么久再判断一次；桌面会话等本轮总结（约 7 s 后才落盘）也是这么久。
    static let deferWindow: TimeInterval = 8, summaryWait: TimeInterval = 8
    /// 合并提醒（「N 位同事在等你」）用的通知 key。
    static let multiKey = "multi"

    private var episodes: [String: Episode] = [:]
    private var prevActivity: [String: Activity] = [:]
    private var finished: [String: FinishedPending] = [:]
    private var lastAlert: [String: Date] = [:]
    private var recent: [(key: String, at: Date, kind: ToastCard.Kind)] = []
    /// 现在显示着的合并提醒：合并了哪些人、是不是「都在等你」（是的话，他们都不再等了要撤掉它）。
    private var multiShown: (keys: Set<String>, waitingBased: Bool, kind: MergedKind, at: Date)?
    private enum MergedKind { case attention, done, mixed }
    /// 有没有人正在等（去重后的 key 集合），Dock 角标 / 菜单栏图标用。
    private(set) var waitingKeys: Set<String> = []
    /// 这一次 observe 里有没有一段等待刚满 1.5 s（Dock 弹一下用；一闪而过的等待不算）。
    private(set) var newlyWaiting = false
    /// 这一次 observe 里观察到几轮「正常做完」（白板上的「正」字计数用）。
    private(set) var finishedTurns = 0

    /// 内部记账字典的大小（测试用：会话来来去去时不许无限增长）。
    var bookkeepingCounts: (prevActivity: Int, finished: Int, lastAlert: Int, episodes: Int) { (prevActivity.count, finished.count, lastAlert.count, episodes.count) }

    static func attention(of a: Activity) -> Attention? {
        switch a {
        case .waitingApproval: return .approval
        case .asking: return .question
        case .planReview: return .plan
        case .waitingOther: return .other
        default: return nil
        }
    }

    func observe(_ snaps: [BuddySnapshot], now: Date, settings: Settings, muted: Set<String> = [], isLooking: (BuddySnapshot) -> Bool, privacy: Bool) -> [Output] {
        observe(snaps, now: now, config: AlertConfig(settings: settings), muted: muted, isLooking: isLooking, privacy: privacy)
    }

    func observe(_ snaps: [BuddySnapshot], now: Date, config: AlertConfig, muted: Set<String> = [], isLooking: (BuddySnapshot) -> Bool, privacy: Bool) -> [Output] {
        var out: [Output] = []
        var waiting: Set<String> = []
        newlyWaiting = false
        finishedTurns = 0
        let present = snaps.filter { $0.presence == .present }
        let keys = Set(snaps.map { $0.key })
        let alertable = Set(present.map { $0.key }).subtracting(muted)          // 还在场、也没被隐藏的
        // 走了 / 被隐藏了：撤掉他那条提醒
        for k in episodes.keys where !alertable.contains(k) { episodes.removeValue(forKey: k); out.append(.clear(key: k)) }
        // 记账只留还有意义的：会话走了就删；节流记录过了 20 秒就没用了（不然每个见过的会话都在这几个字典里留一条，没有上界）
        prevActivity = prevActivity.filter { keys.contains($0.key) }
        finished = finished.filter { alertable.contains($0.key) }
        lastAlert = lastAlert.filter { let dt = now.timeIntervalSince($0.value); return dt >= 0 && dt < Self.throttleWindow }     // 「来自未来」的记录（时钟被拨回）也扔掉（R2-014）

        for s in present {
            let cur = s.activity
            let was = prevActivity[s.key]
            prevActivity[s.key] = cur                       // 逐个快照的记账放在最前面：下面任何分支都不会跳过它
            if case .finished = cur, was != cur, was != nil { finishedTurns += 1 }          // 白板计数：隐藏的 buddy 也数
            guard !muted.contains(s.key) else { continue }
            let title = AlertText.title(s.title, privacy: privacy)

            // 等你（批准 / 提问 / 计划待审 / 其他）
            if let att = Self.attention(of: cur) {
                waiting.insert(s.key)
                out += handleWaiting(s, att: att, now: now, config: config, isLooking: isLooking, title: title, privacy: privacy)
            } else if episodes[s.key] != nil {
                episodes.removeValue(forKey: s.key); out.append(.clear(key: s.key))
            }

            // 做完了
            if case .finished = cur, was != cur, let d = s.lastTurnDuration,
               config.finished, d >= Double(config.finishedMinSeconds), (s.origin != .desktop || config.includeDesktop) {
                finished[s.key] = FinishedPending(since: now, duration: d)
            }
            if let f = finished[s.key] { out += handleFinished(s, f, now: now, config: config, isLooking: isLooking, title: title) }

            // 出错（默认关）。和等待类 / 做完了一样要过两道闸：桌面 App 的会话要开着「桌面 App 里的会话也提醒」，你正在看那个会话时不提醒
            // （原来只看开关和节流：关掉「桌面会话也提醒」来避免和 Claude.app 自己的通知重复的人，桌面会话出错时还是被提醒；R5a-01）
            if case .errored = cur, was != cur, config.error, s.origin != .desktop || config.includeDesktop,
               !(config.suppressWhenFocused && isLooking(s)), throttle("\(s.key)|error", now: now) {
                out += post(key: s.key, kind: .error, title: title, body: "出错了", now: now)
            }
        }
        waitingKeys = waiting
        // 合并出来的「N 位同事在等你」：所有被合并的人都不再等了，就撤掉
        if let m = multiShown, m.waitingBased, m.keys.isDisjoint(with: waiting) { multiShown = nil; out.append(.clear(key: Self.multiKey)) }
        return out
    }

    private func handleWaiting(_ s: BuddySnapshot, att: Attention, now: Date, config: AlertConfig, isLooking: (BuddySnapshot) -> Bool,
                               title: String, privacy: Bool) -> [Output] {
        var ep: Episode
        if let old = episodes[s.key], old.kind == att, old.since <= now { ep = old } else { ep = Episode(kind: att, since: now) }       // 等待的种类变了（或时钟被拨回过，R2-014）：重新计时
        defer { episodes[s.key] = ep }
        guard now.timeIntervalSince(ep.since) >= Self.debounce else { return [] }
        if !ep.bounced { ep.bounced = true; newlyWaiting = true }             // Dock 弹跳和弹窗 / 系统通知共用同一个 1.5 s 去抖
        let enabled = (att == .question || att == .plan) ? config.question : config.permission
        let desktopOK = s.origin != .desktop || config.includeDesktop
        guard !ep.alerted, enabled, desktopOK else { return [] }
        if let d = ep.deferredUntil, now < d { return [] }                    // 宿主 App 在最前面：先等 8 s 再判断
        if config.suppressWhenFocused, isLooking(s) {
            if s.origin == .terminal, ep.deferredUntil == nil { ep.deferredUntil = now.addingTimeInterval(Self.deferWindow); return [] }
            ep.alerted = true; return []                                      // 你一直在看：这一整段等待都不提醒
        }
        // 先节流、后置位（R2-004）：被 20 秒节流挡住时这段等待还没提醒过，`alerted` 不置位，下一拍接着试——
        // 窗口一过、还在等就补发一条（原来先置位再节流，被挡掉的这段等待再也不会提醒，哪怕一直等 2 分钟）；文案（含提示卡宽度测量）也放在节流之后
        guard throttle("\(s.key)|\(att)", now: now) else { return [] }
        ep.alerted = true
        let (kind, body) = Self.text(for: s, att: att, privacy: privacy)
        return post(key: s.key, kind: kind, title: title, body: body, now: now)
    }

    private func handleFinished(_ s: BuddySnapshot, _ f: FinishedPending, now: Date, config: AlertConfig, isLooking: (BuddySnapshot) -> Bool, title: String) -> [Output] {
        // 等的这段时间里下一轮已经开始了（或又在等你）：不能在一个正忙着的会话上冒出「做完了」
        guard s.phase == .idle else { finished.removeValue(forKey: s.key); return [] }
        // 桌面会话的「本轮总结」大约在一轮结束后 7 秒才落盘：最多等 8 秒看有没有变成 blocked
        let wait: TimeInterval = s.origin == .desktop ? Self.summaryWait : 0
        guard s.blocked || now.timeIntervalSince(f.since) >= wait else { return [] }
        if let d = f.deferredUntil, now < d { return [] }
        if config.suppressWhenFocused, isLooking(s) {
            // 终端会话：宿主 App 在最前面，先等 8 s 再判断一次（和等待类提醒一样）；还在看就不提醒
            if s.origin == .terminal, f.deferredUntil == nil { finished[s.key]?.deferredUntil = now.addingTimeInterval(Self.deferWindow); return [] }
            finished.removeValue(forKey: s.key); return []
        }
        finished.removeValue(forKey: s.key)
        let kind: ToastCard.Kind = s.blocked ? .blocked : .finished
        let body = s.blocked ? "需要你处理" : "做完了（用时 \(PlateCopy.spoken(f.duration))）"
        guard throttle("\(s.key)|finished", now: now) else { return [] }
        return post(key: s.key, kind: kind, title: title, body: body, now: now)
    }

    private func throttle(_ k: String, now: Date) -> Bool {
        if let t = lastAlert[k], case let dt = now.timeIntervalSince(t), dt >= 0, dt < Self.throttleWindow { return false }        // dt < 0：时钟被拨回过，这条记录已经过期（R2-014）
        lastAlert[k] = now; return true
    }

    /// 2 s 内连着来几条：合并成一条「N 位同事……」。文案按被合并的种类选：都是在等你 →「在等你」，都是做完了 →「做完了」，混着 →「有事找你」。
    private func post(key: String, kind: ToastCard.Kind, title: String, body: String, now: Date) -> [Output] {
        recent = recent.filter { now.timeIntervalSince($0.at) < Self.mergeWindow }
        recent.append((key, now, kind))
        var who = Set(recent.map { $0.key })
        guard who.count >= 2 else { return [.post(key: key, kind: kind, title: title, body: body)] }
        let kinds = recent.map { $0.kind }
        let attention0 = kinds.allSatisfy { $0 == .approval || $0 == .question || $0 == .plan }        // blocked（做完了要你处理）是事件、不是「正在等」：不进 waitingKeys，按「有事找你」合并（R2-003）
        let done0 = kinds.allSatisfy { $0 == .finished }
        var merged: MergedKind = attention0 ? .attention : (done0 ? .done : .mixed)
        // 上一张合并卡还在屏幕上：它合并进去的人的单独提示卡已经撤掉了，新的合并卡必须把他们也算进去、并接着盖住他们
        // （原来只数最近 2 秒里发出的条数：A、B 合并成「2 位」之后，C 在 B 之后 1.6 秒到，合并卡还是「2 位」，A 没有任何卡盖着了；R3c-01）。
        // 「在等你」的合并卡只带还在等的人。
        if let m = multiShown, case let dt = now.timeIntervalSince(m.at), dt >= 0, dt < Self.mergeCarry {
            who.formUnion(m.waitingBased ? m.keys.intersection(waitingKeys) : m.keys)
            merged = merged == m.kind ? merged : .mixed
        }
        let text: String
        switch merged {
        case .attention: text = "\(who.count) 位同事在等你"
        case .done: text = "\(who.count) 位同事做完了"
        case .mixed: text = "\(who.count) 位同事有事找你"
        }
        let attention = merged == .attention, done = merged == .done
        multiShown = (who, attention, merged, now)
        var o: [Output] = who.sorted().map { .clear(key: $0) }
        o.append(.post(key: Self.multiKey, kind: done ? .finished : .approval, title: "Buddy 办公室", body: text))
        return o
    }

    static func text(for s: BuddySnapshot, att: Attention, privacy: Bool) -> (ToastCard.Kind, String) {
        switch att {
        case .approval:
            if case .waitingApproval(let c) = s.activity, let c = c, !privacy {
                let d = PlateCopy.shortCommand(c.detail)
                return (.approval, AlertText.approvalBody(tool: PlateCopy.toolLabel(c), command: c.category == .bash ? d : ""))
            }
            return (.approval, "有个权限请求（等你批准）")
        case .question: return (.question, "有个问题要问你")
        case .plan: return (.plan, "计划好了，等你看")
        case .other: return (.approval, "在等你")
        }
    }
}
