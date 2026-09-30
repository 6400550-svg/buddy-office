import Foundation

/// 身份（DESIGN.md 4.5）：一个 buddy = 一个会话，关掉再打开回来的还是同一个人，坐回同一个工位。
///
/// - buddy key：桌面会话是 `"d:" + hostSessionId`，其他会话是 `"t:" + 第一次见到的 sessionId`；
/// - 每个 buddy 挂多个别名：`host:<local_…>`、`sid:<uuid>`、`proc:<pid>@<启动时间>`；
/// - 一条登记记录按顺序归属：① host 别名 ② 进程别名（同一个进程 `/clear`）③ sid 别名（在新进程里 resume）
///   ④ 桌面元数据里的 cliSessionId / priorCliSessionIds ⑤ 都不匹配就是新 buddy；
/// - 别名、工位编号、外观种子盐持久化到 `identities.json`，保留 7 天。
public final class IdentityResolver {
    public struct Identity: Equatable, Sendable {
        public var key: String
        /// 工位编号；-1 = 还没分配过。
        public var seat: Int
        public var salt: UInt64
        public var aliases: [String]
        public var createdAt: Date
        public var lastSeenAt: Date
    }

    public enum MatchKind: Sendable, Equatable { case host, process, session, desktopMeta, new }

    public struct Match {
        public var identity: Identity
        public var kind: MatchKind
        public var isNew: Bool { kind == .new }
    }

    public static let retention: TimeInterval = 7 * 86400
    /// 别名数量上限：sid 别名留最近 30 个（在新进程里 resume 要用），proc 别名留最近 4 个（同一个进程 /clear 要用），host 别名全留。
    static let maxSessionAliases = 30
    static let maxProcessAliases = 4
    static let maxHostAliases = 6
    static var maxAliases: Int { maxSessionAliases + maxProcessAliases + maxHostAliases }
    /// 载入 identities.json 时的上限（文件是外部输入，被写坏 / 被人改过时不能让内存和 CPU 跟着无限涨）。
    static let maxIdentities = 2000
    /// 工位号的合理上限（超出当作没分配过）。
    static let maxSeat = 999
    static let maxKeyLength = 200
    /// lastSeenAt 至少推进这么久才落盘（避免频繁写）。
    static let touchPersistInterval: TimeInterval = 10 * 60

    private var identities: [String: Identity] = [:]
    private var aliasIndex: [String: String] = [:]
    private let path: String?
    private let now: () -> Date
    private var dirty = false
    private var lastPersistedSeen: [String: Date] = [:]
    /// 持久化是否可用；nil = 还没试过。沙箱里写不了 Application Support 时为 false（只在内存里）。
    public private(set) var persistenceOK: Bool?

    public init(path: String?, now: @escaping () -> Date = Date.init) {
        self.path = path
        self.now = now
        if let p = path { load(p) }
    }

    // MARK: - 查询

    public var all: [Identity] { Array(identities.values) }
    public func identity(forKey key: String) -> Identity? { identities[key] }
    public func identity(forHost host: String) -> Identity? {
        aliasIndex["host:" + host].flatMap { identities[$0] }
    }

    // MARK: - 归属

    /// 把一条登记记录归属到一个 buddy（没有就新建）。会把这条记录的别名都挂上去。
    public func resolve(_ r: RegistryRecord, metaLookup: (String) -> DesktopMeta?) -> Match {
        let hostAlias = r.hostSessionId.map { "host:" + $0 }
        let procAlias: String? = r.procStartKey == "?" ? nil : "proc:\(r.pid)@\(r.procStartKey)"
        let sidAlias = "sid:" + r.sessionId
        let meta = metaLookup(r.sessionId)

        var key: String?
        var kind = MatchKind.new
        if let a = hostAlias, let k = aliasIndex[a] { key = k; kind = .host }
        else if let a = procAlias, let k = aliasIndex[a] { key = k; kind = .process }
        else if let k = aliasIndex[sidAlias] { key = k; kind = .session }
        else if let m = meta, let k = aliasIndex["host:" + m.hostSessionId] { key = k; kind = .desktopMeta }

        let t = now()
        var identity: Identity
        if let k = key, let existing = identities[k] {
            identity = existing
        } else {
            let newKey: String
            if let h = r.hostSessionId { newKey = "d:" + h }
            else if let m = meta { newKey = "d:" + m.hostSessionId }
            else { newKey = "t:" + r.sessionId }
            if let existing = identities[newKey] {
                identity = existing; kind = .host           // key 相同：同一个人（别名表被裁剪过）
            } else {
                identity = Identity(key: newKey, seat: -1, salt: 0, aliases: [], createdAt: t, lastSeenAt: t)
                kind = .new
            }
        }
        var wanted = [sidAlias]
        if let a = hostAlias { wanted.append(a) }
        if let a = procAlias { wanted.append(a) }
        if let m = meta { wanted.append("host:" + m.hostSessionId) }
        attach(wanted, to: &identity)
        identity.lastSeenAt = t
        store(identity, persistNow: kind == .new)
        return Match(identity: identity, kind: kind)
    }

    /// 给桌面元数据里的会话（App 启动时还没有进程的"下班工位"候选）建立 / 找回身份。
    public func desktopIdentity(host: String, cliSessionIds: [String]) -> Match {
        if let existing = identity(forHost: host) { return Match(identity: existing, kind: .host) }
        let key = "d:" + host
        let t = now()
        var identity = identities[key] ?? Identity(key: key, seat: -1, salt: 0, aliases: [], createdAt: t, lastSeenAt: t)
        attach(["host:" + host] + cliSessionIds.map { "sid:" + $0 }, to: &identity)
        store(identity, persistNow: true)
        return Match(identity: identity, kind: .new)
    }

    private func attach(_ aliases: [String], to identity: inout Identity) {
        for a in aliases where !identity.aliases.contains(a) {
            identity.aliases.append(a)
            dirty = true
        }
        // 别名太多时丢最老的 sid / proc 别名（host 别名要一直留着；proc 别名不能被一堆新的 sid 别名挤掉，
        // 否则同一个进程的下一次 /clear 就认不出来了）
        for (prefix, keep) in [("sid:", IdentityResolver.maxSessionAliases), ("proc:", IdentityResolver.maxProcessAliases)] {
            var n = identity.aliases.filter { $0.hasPrefix(prefix) }.count
            while n > keep, let i = identity.aliases.firstIndex(where: { $0.hasPrefix(prefix) }) {
                let removed = identity.aliases.remove(at: i)
                if aliasIndex[removed] == identity.key { aliasIndex[removed] = nil }
                n -= 1
            }
        }
        for a in identity.aliases { aliasIndex[a] = identity.key }
    }

    private func store(_ identity: Identity, persistNow: Bool) {
        let old = identities[identity.key]
        identities[identity.key] = identity
        if persistNow || old == nil || old?.seat != identity.seat || old?.salt != identity.salt { dirty = true }
        if let last = lastPersistedSeen[identity.key], identity.lastSeenAt.timeIntervalSince(last) >= IdentityResolver.touchPersistInterval {
            dirty = true
        }
        if persistNow { saveIfNeeded(force: true) }
    }

    // MARK: - 工位与外观

    /// 分配工位：优先坐回上次的工位（没被别人占着的话），否则取编号最小的空位。
    @discardableResult
    public func assignSeat(forKey key: String, occupied: Set<Int>) -> Int {
        guard var id = identities[key] else { return -1 }
        var seat = id.seat
        if seat < 0 || occupied.contains(seat) {
            seat = 0
            while occupied.contains(seat) { seat += 1 }
        }
        if seat != id.seat { id.seat = seat; store(id, persistNow: false) }
        return seat
    }

    public func setSeat(_ seat: Int, forKey key: String) {
        guard var id = identities[key], id.seat != seat else { return }
        id.seat = seat
        store(id, persistNow: false)
    }

    /// 「换个造型」：换新的外观 salt 并持久化。
    @discardableResult
    public func reroll(key: String) -> UInt64? {
        guard var id = identities[key] else { return nil }
        id.salt &+= 1
        store(id, persistNow: true)
        return id.salt
    }

    public func touch(key: String) {
        guard var id = identities[key] else { return }
        id.lastSeenAt = now()
        store(id, persistNow: false)
    }

    // MARK: - 持久化

    public func saveIfNeeded(force: Bool = false) {
        guard let path, dirty || force else { return }
        pruneExpired()
        let t = now()
        let items: [[String: Any]] = identities.values.sorted { $0.key < $1.key }.map { id in
            ["key": id.key, "seat": id.seat, "salt": String(id.salt), "aliases": id.aliases,
             "createdAt": TimeUtil.millis(id.createdAt), "lastSeenAt": TimeUtil.millis(id.lastSeenAt)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "identities": items] as [String: Any],
                                                     options: [.sortedKeys]) else { return }
        let ok = FileIO.writeAtomically(data, to: path)
        persistenceOK = ok
        if ok {
            dirty = false
            for id in identities.values { lastPersistedSeen[id.key] = id.lastSeenAt }
        } else {
            dirty = false     // 写不了（沙箱 / 只读）：只留在内存里，别每次都重试
        }
        _ = t
    }

    private func load(_ path: String) {
        guard let data = FileIO.readAll(path, maxBytes: 16 << 20),
              let obj = SafeJSON.object(data),
              (obj["version"] as? Int) == 1, let items = obj["identities"] as? [[String: Any]] else { return }
        let t = now()
        var loaded: [Identity] = []
        for item in items {
            guard let key = item["key"] as? String, !key.isEmpty, key.utf8.count <= IdentityResolver.maxKeyLength else { continue }
            var seen = TimeUtil.date(fromJSONMillis: item["lastSeenAt"]) ?? t
            if seen > t { seen = t }                                                       // 未来的时间（坏数据 / 时钟被拨回）：当作刚见过
            if t.timeIntervalSince(seen) > IdentityResolver.retention { continue }       // 保留 7 天
            let salt = (item["salt"] as? String).flatMap { UInt64($0) } ?? UInt64((item["salt"] as? NSNumber)?.uint64Value ?? 0)
            // 工位号：只认 0…maxSeat 的整数，别的（负数、天文数字、布尔、字符串）当作没分配过
            var seat = -1
            if let n = item["seat"] as? NSNumber, !TimeUtil.isBool(n) {
                let d = n.doubleValue
                if d >= 0, d <= Double(IdentityResolver.maxSeat) { seat = Int(d) }
            }
            let created = min(TimeUtil.date(fromJSONMillis: item["createdAt"]) ?? seen, seen)
            loaded.append(Identity(key: key, seat: seat, salt: salt,
                                   aliases: IdentityResolver.boundedAliases((item["aliases"] as? [String]) ?? []),
                                   createdAt: created, lastSeenAt: seen))
        }
        // 太多就只留最近见到的
        if loaded.count > IdentityResolver.maxIdentities {
            loaded.sort { $0.lastSeenAt != $1.lastSeenAt ? $0.lastSeenAt > $1.lastSeenAt : $0.key < $1.key }
            loaded.removeLast(loaded.count - IdentityResolver.maxIdentities)
        }
        for id in loaded {
            identities[id.key] = id
            lastPersistedSeen[id.key] = id.lastSeenAt
            for a in id.aliases { aliasIndex[a] = id.key }
        }
    }

    /// 别名列表的上界：host 最近 6 个、sid 最近 30 个、proc 最近 4 个，去重，别的前缀 / 过长的丢掉（保持原来的先后顺序）。
    static func boundedAliases(_ raw: [String]) -> [String] {
        let limits: [(prefix: String, limit: Int)] = [("host:", maxHostAliases), ("sid:", maxSessionAliases), ("proc:", maxProcessAliases)]
        var counts = [Int](repeating: 0, count: limits.count)
        var seen = Set<String>()
        var out: [String] = []
        for a in raw.reversed() {
            guard a.utf8.count <= maxKeyLength, let i = limits.firstIndex(where: { a.hasPrefix($0.prefix) }),
                  counts[i] < limits[i].limit, seen.insert(a).inserted else { continue }
            counts[i] += 1
            out.append(a)
        }
        return out.reversed()
    }

    private func pruneExpired() {
        let t = now()
        for (k, id) in identities where t.timeIntervalSince(id.lastSeenAt) > IdentityResolver.retention {
            for a in id.aliases where aliasIndex[a] == k { aliasIndex[a] = nil }
            identities[k] = nil
            lastPersistedSeen[k] = nil
        }
    }
}
