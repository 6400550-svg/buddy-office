import Foundation

/// 桌面 App 每轮结束后生成的"本轮总结"。
public struct PostTurnSummary: Sendable, Equatable {
    /// completed / blocked
    public var statusCategory: String
    public var needsAction: String?
    /// 英文，只在悬停卡片里显示。
    public var statusDetail: String?
    public var summarizesUuid: String?
}

/// 桌面 App 的会话元数据：`~/Library/Application Support/Claude/claude-code-sessions/<acct>/<org>/local_<uuid>.json`。
/// 没有表示"运行中"的字段。
public struct DesktopMeta: Sendable, Equatable {
    /// `local_<uuid>`（登记表里的 hostSessionId）
    public var hostSessionId: String
    /// = 登记表里的 sessionId（当前的 CLI 会话）
    public var cliSessionId: String?
    public var priorCliSessionIds: [String] = []
    public var cwd: String?
    public var originCwd: String?
    public var title: String?
    public var titleSource: String?
    public var model: String?
    public var effort: String?
    public var permissionMode: String?
    public var isArchived = false
    public var createdAt: Date?
    public var lastActivityAt: Date?
    public var lastFocusedAt: Date?
    public var completedTurns: Int?
    public var lastAssistantUuid: String?
    public var postTurnSummary: PostTurnSummary?
    public var postTurnSummaryFor: String?
    public var path: String = ""

    public init(hostSessionId: String) { self.hostSessionId = hostSessionId }

    /// "做完了但需要你处理"：`status_category == "blocked"` 并且 `postTurnSummaryFor == lastAssistantUuid`。
    public var isBlocked: Bool { summaryIsCurrent && postTurnSummary?.statusCategory == "blocked" }

    /// 总结是不是针对最新一条 assistant 消息的（不是就说明是上一轮的旧总结）。
    public var summaryIsCurrent: Bool {
        guard postTurnSummary != nil, let f = postTurnSummaryFor, let l = lastAssistantUuid else { return false }
        return f == l
    }

    /// 这个会话的全部 CLI 会话 id（当前 + 之前的），token 合并用。去重（O(n)），保持先后顺序。
    public var allCliSessionIds: [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for id in priorCliSessionIds + [cliSessionId].compactMap({ $0 }) where seen.insert(id).inserted { ids.append(id) }
        return ids
    }

    /// priorCliSessionIds 最多留多少个（取最近的，即数组末尾）。元数据文件是外部输入：
    /// 上万个 id 会让去重、按 id 找会话记录（每个都要列一遍 projects/ 目录）把 ingest 队列拖死。
    public static let maxPriorIds = 256
}

/// 桌面会话元数据读取器：按文件签名（mtime + size + ino）只在变化时重读，删除的文件从索引里去掉。
public final class DesktopMetaReader {
    private struct Entry {
        var signature: FileStat
        var meta: DesktopMeta
    }

    public let rootDir: String
    private var index: [String: Entry] = [:]        // hostSessionId → 条目
    private var pathToHost: [String: String] = [:]
    /// 被同一个 hostSessionId 的另一个文件"压住"的副本（用户手动复制出来的 `local_x copy.json` 之类）：路径 → (上次看到的签名, 压住它的 host)。
    /// 没变就不再重读，也不再和赢家来回抢（否则每次 refresh 都会互相覆盖、报告"变了"）；赢家不在了副本才转正。
    private var shadowed: [String: (sig: FileStat, host: String)] = [:]
    /// cliSessionId（当前的和 prior 的）→ hostSessionId；当前的优先。
    private var cliIndex: [String: String] = [:]
    public private(set) var directoryReadable = false
    public private(set) var fileCount = 0
    public private(set) var parseFailures = 0

    /// 时钟（引擎传它的 `options.now`）：比「现在」晚一天以上的时间戳按「现在」算（见 `clampingFuture`）。
    private let now: () -> Date

    public init(rootDir: String, now: @escaping () -> Date = Date.init) { self.rootDir = rootDir; self.now = now }

    /// 桌面 App 写出的时间戳比「现在」晚一天以上（它的时钟被拨快过 / 虚拟机恢复后时钟不对 / 坏数据）：按「现在」算，和 hook、会话记录、identities.json 一致（C-006 / C-026）。
    /// 不处理的话：一个远在未来的 `lastFocusedAt` 让「未读」永远不亮（`f > e → unread = false`），一个未来的 `lastActivityAt` 让下班工位里的幽灵座位排第一、永远不到期（R3a P2-2）。
    /// `lastFocusedAt` 在未来的直接丢掉（当作没聚焦过），`createdAt` / `lastActivityAt` 夹成「现在」。
    static func clampingFuture(_ m: DesktopMeta, now: Date) -> DesktopMeta {
        var m = m
        let cap = now.addingTimeInterval(86400)
        if let t = m.createdAt, t > cap { m.createdAt = now }
        if let t = m.lastActivityAt, t > cap { m.lastActivityAt = now }
        if let t = m.lastFocusedAt, t > cap { m.lastFocusedAt = nil }         // 聚焦时间在未来：没有意义，当作「没有」（夹成现在的话它会永远比真实的聚焦更新，R4a-01）
        return m
    }

    /// 重新列目录，读新增 / 有变化的文件。返回内容有变化（含新增、删除）的 hostSessionId。
    @discardableResult
    public func refresh() -> Set<String> {
        var changed = Set<String>()
        var seenPaths = Set<String>()
        var readable = false
        if let accts = FileIO.listDirectory(rootDir) {
            readable = true
            for acct in accts {
                let acctPath = rootDir + "/" + acct
                guard let orgs = FileIO.listDirectory(acctPath) else { continue }
                for org in orgs {
                    let orgPath = acctPath + "/" + org
                    guard let files = FileIO.listDirectory(orgPath) else { continue }
                    for f in files where f.hasPrefix("local_") && f.hasSuffix(".json") {
                        let path = orgPath + "/" + f
                        seenPaths.insert(path)
                        guard let st = FileIO.stat(path), !st.isDirectory else { continue }
                        let host = String(f.dropLast(5))
                        if let sh = shadowed[path], sh.sig == st { continue }
                        // 这个文件上次读出来是哪个 host（文件里的 sessionId 不一定等于文件名）：没变就不用重读
                        if let known = pathToHost[path], let e = index[known], e.signature == st, e.meta.path == path { continue }
                        guard let data = FileIO.readAll(path, maxBytes: 4 << 20),
                              let parsed = DesktopMetaReader.parse(data, path: path, fallbackHost: host) else {
                            parseFailures += 1      // 写了一半 / 不合法：保留旧的，下次再读
                            continue
                        }
                        let meta = DesktopMetaReader.clampingFuture(parsed, now: now())
                        // 已经有另一个文件占着这个 host：文件名和 host 一致的优先，否则路径小的优先（不依赖目录遍历顺序）
                        if let other = index[meta.hostSessionId], other.meta.path != path {
                            if !DesktopMetaReader.prefers(path, over: other.meta.path, host: meta.hostSessionId) {
                                shadowed[path] = (st, meta.hostSessionId)
                                continue
                            }
                            shadowed[other.meta.path] = (other.signature, meta.hostSessionId)            // 被顶掉的变成副本
                            pathToHost[other.meta.path] = nil
                        }
                        shadowed[path] = nil
                        if index[meta.hostSessionId]?.meta != meta { changed.insert(meta.hostSessionId) }
                        index[meta.hostSessionId] = Entry(signature: st, meta: meta)
                        pathToHost[path] = meta.hostSessionId
                    }
                }
            }
        }
        directoryReadable = readable
        if readable {
            for (path, host) in pathToHost where !seenPaths.contains(path) {
                if index[host]?.meta.path == path { index[host] = nil; changed.insert(host) }
                pathToHost[path] = nil
            }
            // 副本文件没了、或者压住它的赢家不在了（下一次 refresh 重新读它，转正）：从副本表里去掉
            for (path, sh) in Array(shadowed) where !seenPaths.contains(path) || index[sh.host] == nil { shadowed[path] = nil }
        }
        if !changed.isEmpty { rebuildCliIndex() }
        fileCount = index.count
        return changed
    }

    /// 两个文件声称同一个 host 时谁赢：文件名恰好是 `<host>.json` 的赢，否则路径字典序小的赢。
    static func prefers(_ a: String, over b: String, host: String) -> Bool {
        let an = (a as NSString).lastPathComponent == host + ".json"
        let bn = (b as NSString).lastPathComponent == host + ".json"
        if an != bn { return an }
        return a < b
    }

    private func rebuildCliIndex() {
        var out: [String: String] = [:]
        for (host, e) in index { for p in e.meta.priorCliSessionIds where out[p] == nil { out[p] = host } }
        for (host, e) in index { if let c = e.meta.cliSessionId { out[c] = host } }       // 当前的覆盖 prior 的
        cliIndex = out
    }

    public func meta(host: String) -> DesktopMeta? { index[host]?.meta }
    public var all: [DesktopMeta] { index.values.map { $0.meta } }

    /// 用 CLI 会话 id 反查：`cliSessionId` 或 `priorCliSessionIds` 里有它。当前的优先。
    public func find(cliSessionId sid: String) -> DesktopMeta? {
        guard let host = cliIndex[sid] else { return nil }
        return index[host]?.meta
    }

    public static func parse(_ data: Data, path: String, fallbackHost: String? = nil) -> DesktopMeta? {
        guard let obj = SafeJSON.object(data) else { return nil }
        guard let host = (obj["sessionId"] as? String) ?? fallbackHost, !host.isEmpty, host.utf8.count <= SafeJSON.maxIdLength else { return nil }
        func str(_ k: String, max n: Int = SafeJSON.maxLabelLength) -> String? {
            guard let s = SafeJSON.string(obj[k], max: n), !s.isEmpty else { return nil }
            return s
        }
        var m = DesktopMeta(hostSessionId: host)
        m.path = path
        m.cliSessionId = SafeJSON.id(obj["cliSessionId"])
        let priors = ((obj["priorCliSessionIds"] as? [Any])?.compactMap { $0 as? String } ?? []).filter(Paths.isSafeID)
        m.priorCliSessionIds = Array(priors.suffix(DesktopMeta.maxPriorIds))
        m.cwd = str("cwd")
        m.originCwd = str("originCwd")
        m.title = str("title")
        m.titleSource = str("titleSource", max: 64)
        m.model = str("model", max: SafeJSON.maxIdLength)
        m.effort = str("effort", max: 64)
        m.permissionMode = str("permissionMode", max: 64)
        m.isArchived = (obj["isArchived"] as? Bool) ?? false
        m.createdAt = TimeUtil.date(fromJSONMillis: obj["createdAt"])
        m.lastActivityAt = TimeUtil.date(fromJSONMillis: obj["lastActivityAt"])
        m.lastFocusedAt = TimeUtil.date(fromJSONMillis: obj["lastFocusedAt"])
        m.completedTurns = (obj["completedTurns"] as? NSNumber)?.intValue
        m.lastAssistantUuid = SafeJSON.id(obj["lastAssistantUuid"])
        m.postTurnSummaryFor = SafeJSON.id(obj["postTurnSummaryFor"])
        if let s = obj["postTurnSummary"] as? [String: Any], let cat = SafeJSON.string(s["status_category"], max: 64) {
            m.postTurnSummary = PostTurnSummary(
                statusCategory: cat,
                needsAction: SafeJSON.string(s["needs_action"], max: SafeJSON.maxDetailLength).flatMap { $0.isEmpty ? nil : $0 },
                statusDetail: SafeJSON.string(s["status_detail"], max: SafeJSON.maxDetailLength).flatMap { $0.isEmpty ? nil : $0 },
                summarizesUuid: SafeJSON.id(s["summarizes_uuid"]))
        }
        return m
    }
}
