import Foundation

/// 一个还开着的工具调用。
public struct OpenTool: Sendable, Equatable {
    public enum Owner: Sendable, Equatable { case main, helper }
    public var seq: Int
    public var call: ToolCall
    /// hook 把名字截断过（`call.name` 已去掉 `…`，要按前缀匹配）。
    public var nameTruncated: Bool
    public var batch: Int
    public var owner: Owner
}

/// 已经关掉的调用（最近几十个，测试和诊断用）。
public struct ClosedTool: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case post          // 正常收到 PostToolUse
        case superseded    // 被新一批取代（工具失败 / 权限被拒时只有 Pre 没有 Post）
        case turnBoundary  // Stop / UserPromptSubmit / SessionStart / 登记表变 idle / stop_hook_summary
        case stale         // 兜底：登记表 idle 而调用开了超过 30 分钟
    }
    public var call: ToolCall
    public var owner: OpenTool.Owner
    public var closedAt: Date
    public var reason: Reason
}

/// 工具追踪：处理"悬空"和"并行"（DESIGN.md 5.2）。
///
/// ccmon 没有注册 PostToolUseFailure，工具失败或权限被拒时只有 Pre 没有 Post，会一直悬空。
/// 处理办法：模型必须等上一条消息的所有结果都回来才能发下一条消息，
/// 所以主线程的新一批 Pre 一到，更早批次里还开着的调用就可以全部关掉。
public struct ToolTracker: Sendable, Equatable {
    /// 距离上一个主线程 Pre 超过这么久（秒）就算新的一批。
    public static let batchGap: TimeInterval = 0.25
    /// 兜底：登记表是 idle 而调用已经开了这么久，强制关掉。
    public static let staleAfter: TimeInterval = 30 * 60
    /// 同时开着的调用数上限（hook 文件被刷屏 / 坏数据时不能无限涨；超出就把最老的当作被取代关掉）。
    public static let maxOpen = 512

    public private(set) var open: [OpenTool] = []
    public private(set) var closed: [ClosedTool] = []
    private var nextSeq = 0
    private var batch = 0
    private var lastMainPreAt: Date?

    public init() {}

    /// 主线程还开着的调用，按开始顺序。
    public var mainOpen: [OpenTool] { open.filter { $0.owner == .main } }
    public var helperOpen: [OpenTool] { open.filter { $0.owner == .helper } }
    /// 最新的主线程调用。
    public var latestMain: OpenTool? { open.last(where: { $0.owner == .main }) }

    // MARK: - 名字匹配（hook 会把工具名截成 40 字符加 `…`）

    static func namesMatch(_ a: String, aTruncated: Bool, _ b: String, bTruncated: Bool) -> Bool {
        if a == b { return true }
        if aTruncated && b.hasPrefix(a) { return true }
        if bTruncated && a.hasPrefix(b) { return true }
        return false
    }

    // MARK: - 事件

    /// PreToolUse 到来。`owner` 是归属判断（主线程 / 小助手）的结果。
    public mutating func pre(name rawName: String, truncated: Bool = false, detail: String, at: Date, owner: OpenTool.Owner) {
        if owner == .main {
            let newBatch = lastMainPreAt.map { at.timeIntervalSince($0) > ToolTracker.batchGap } ?? true
            if newBatch {
                // 新的一批：把更早批次里还开着的主线程调用全部关掉（被取代）
                closeAll(owner: .main, at: at, reason: .superseded)
                batch += 1
            }
            lastMainPreAt = at
        }
        let name = ToolCatalog.cleanName(rawName)
        // AskUserQuestion 的 detail 是第一个选项的 description，不是问题本身：永不保留
        let d = (name == "AskUserQuestion") ? "" : detail
        let call = ToolCatalog.makeCall(name: name, detail: d, at: at)
        open.append(OpenTool(seq: nextSeq, call: call, nameTruncated: truncated, batch: batch, owner: owner))
        nextSeq += 1
        if open.count > ToolTracker.maxOpen {
            let drop = open.count - ToolTracker.maxOpen
            for t in open.prefix(drop) { record(t, at: at, reason: .superseded) }
            open.removeFirst(drop)
        }
    }

    /// PostToolUse 到来：按"工具名 + detail 都相同"关掉最早的那个；没有就按工具名关；还没有就忽略。
    /// 并行调用按先进先出配对（实测同一毫秒出现过两个 Read）。
    public mutating func post(name rawName: String, truncated: Bool = false, detail: String, at: Date) {
        let name = ToolCatalog.cleanName(rawName)
        let d = (name == "AskUserQuestion") ? "" : detail
        var idx = open.firstIndex(where: {
            ToolTracker.namesMatch($0.call.name, aTruncated: $0.nameTruncated, name, bTruncated: truncated) && $0.call.detail == d
        })
        if idx == nil {
            idx = open.firstIndex(where: {
                ToolTracker.namesMatch($0.call.name, aTruncated: $0.nameTruncated, name, bTruncated: truncated)
            })
        }
        guard let i = idx else { return }
        record(open.remove(at: i), at: at, reason: .post)
    }

    /// 轮次边界（Stop、UserPromptSubmit、SessionStart、登记表变 idle、stop_hook_summary）：
    /// 关掉主线程在这个时刻**之前（含）**开始的全部调用。
    /// （会话记录里的 stop_hook_summary 可能比当前开着的调用旧，那些新开的调用不能被误关。）
    public mutating func turnBoundary(at: Date) {
        var keep: [OpenTool] = []
        for t in open {
            if t.owner == .main && t.call.startedAt <= at { record(t, at: at, reason: .turnBoundary) } else { keep.append(t) }
        }
        open = keep
        if let last = lastMainPreAt, last <= at { lastMainPreAt = nil }
    }

    /// 兜底清理。登记表是 idle 而调用已开超过 30 分钟就强制关掉；小助手名下的记录只是配对用，超过 30 分钟一律丢掉。
    public mutating func expireStale(now: Date, registryIdle: Bool) {
        var keep: [OpenTool] = []
        for t in open {
            let age = now.timeIntervalSince(t.call.startedAt)
            let stale = age > ToolTracker.staleAfter && (registryIdle || t.owner == .helper)
            if stale { record(t, at: now, reason: .stale) } else { keep.append(t) }
        }
        open = keep
    }

    /// 全部清空（会话换了 / hook 文件被轮转）。
    public mutating func reset() {
        open.removeAll()
        lastMainPreAt = nil
    }

    // MARK: - 内部

    private mutating func closeAll(owner: OpenTool.Owner, at: Date, reason: ClosedTool.Reason) {
        var keep: [OpenTool] = []
        for t in open {
            if t.owner == owner { record(t, at: at, reason: reason) } else { keep.append(t) }
        }
        open = keep
    }

    private mutating func record(_ t: OpenTool, at: Date, reason: ClosedTool.Reason) {
        closed.append(ClosedTool(call: t.call, owner: t.owner, closedAt: at, reason: reason))
        if closed.count > 64 { closed.removeFirst(closed.count - 64) }
    }
}
