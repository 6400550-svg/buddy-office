import Foundation

/// 登记表 `~/.claude/sessions/<pid>.json` 里的一条记录。所有字段都按可选处理，只有 `pid` 和 `sessionId` 必需。
public struct RegistryRecord: Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String?
    public var startedAt: Date?
    /// 原始的 procStart（UTC 的 lstart 格式）与解析结果。
    public var procStartRaw: String?
    public var procStart: Date?
    public var pidDomain: String?
    public var version: String?
    public var kind: String?
    public var entrypoint: String?
    public var hostSessionId: String?
    public var name: String?
    public var nameSource: String?
    public var nameSince: Date?
    /// 登记表的 status：busy / waiting / idle；不认识的值为 nil。
    public var status: Phase?
    public var statusRaw: String?
    public var waitingFor: String?
    public var updatedAt: Date?
    public var statusUpdatedAt: Date?

    public init(pid: Int32, sessionId: String) { self.pid = pid; self.sessionId = sessionId }

    /// 来源：`claude-desktop` / `claude-desktop-3p` / `local-agent` = 桌面 App；`claude-vscode` = VS Code；其他 = 终端。
    public var origin: SessionOrigin {
        switch entrypoint {
        case "claude-desktop", "claude-desktop-3p", "local-agent": return .desktop
        case "claude-vscode": return .vscode
        default: return .terminal
        }
    }

    /// 进程别名里用的启动时间标识：能解析就用 epoch 秒，否则用压缩空白后的原文。
    public var procStartKey: String {
        if let d = procStart { return String(Int64(d.timeIntervalSince1970)) }
        if let raw = procStartRaw { return raw.split(separator: " ").joined(separator: " ") }
        return "?"
    }
}

/// 登记表扫描器。
///
/// - **只**打开文件名匹配 `^\d+\.json$` 的文件；同目录下 `<pid>.<sha256>.key` 是密钥，连 stat 都不碰；
/// - 文件是原地重写的，可能读到写了一半的 JSON：解析失败时保留上一份好的记录，
///   每隔 50 ms 重试一次，最多 5 次；
/// - 只显示 `kind == "interactive"`（缺省当作 interactive）。
public final class RegistryScanner {
    public struct ScanResult {
        public var records: [Int32: RegistryRecord] = [:]
        /// 这次扫描里内容有变化（新增或改动）的 pid。
        public var changed: Set<Int32> = []
        /// 文件已经消失的 pid。
        public var removed: Set<Int32> = []
        /// 需要再读一次（半个文件）的最早时间。
        public var nextRetry: Date?
        /// 目录能不能读（读不了说明这个数据源不可用）。
        public var directoryReadable = true
        /// 目录里匹配 `^\d+\.json$` 的文件个数。
        public var fileCount = 0
    }

    public static let retryInterval: TimeInterval = 0.05
    public static let maxRetries = 5

    private struct Entry {
        var signature: FileStat?
        var record: RegistryRecord?         // 最近一份好的记录（非 interactive 的为 nil）
        var skipped = false                 // 非 interactive：不显示，也不再解析
        var failures = 0
        var nextRetryAt: Date?
        var readAt: Date?
        var recentlyModified = false        // 上次读的时候文件刚被改过：下次再读一遍，防同刻度的写入被漏掉
    }

    private let dir: String
    private let listDir: (String) -> [String]?
    private let statFile: (String) -> FileStat?
    private let readFile: (String) -> Data?
    private var entries: [Int32: Entry] = [:]
    /// 目录列表缓存：目录的签名（mtime + inode）没变就不用重新 opendir / readdir。
    /// 登记文件是原地重写的（不改变目录签名），所以文件本身仍然每次 stat。
    private var cachedListing: (sig: FileStat, names: [String], at: Date)?
    /// 就算目录签名没变，也每隔这么久重新列一次（防止漏掉变化）。
    static let relistInterval: TimeInterval = 2

    public init(dir: String,
                listDir: @escaping (String) -> [String]? = { FileIO.listDirectory($0) },
                statFile: @escaping (String) -> FileStat? = { FileIO.stat($0) },
                readFile: @escaping (String) -> Data? = { FileIO.readAll($0, maxBytes: 1 << 20) }) {
        self.dir = dir
        self.listDir = listDir
        self.statFile = statFile
        self.readFile = readFile
    }

    public func scan(now: Date) -> ScanResult {
        var result = ScanResult()
        var listed: [String]?
        if let sig = statFile(dir) {
            if let c = cachedListing, c.sig == sig, now.timeIntervalSince(c.at) < RegistryScanner.relistInterval {
                listed = c.names
            } else {
                listed = listDir(dir)
                if let l = listed { cachedListing = (sig, l, now) } else { cachedListing = nil }
            }
        } else {
            cachedListing = nil
            listed = listDir(dir)
        }
        guard let names = listed else {
            result.directoryReadable = false
            // 目录读不了：保持上次的记录不动（别把所有人都判成离场）
            for (pid, e) in entries { if let r = e.record { result.records[pid] = r } }
            return result
        }
        var seen = Set<Int32>()
        for name in names where Paths.isRegistryFileName(name) {   // 只碰 ^\d+\.json$
            guard let pid = Int32(name.dropLast(5)) else { continue }
            seen.insert(pid)
            result.fileCount += 1
            let path = dir + "/" + name
            var entry = entries[pid] ?? Entry()
            guard let st = statFile(path) else { entries[pid] = entry; continue }

            let sameSignature = entry.signature == st
            var needRead = false
            if !sameSignature {
                needRead = true
                entry.failures = 0                     // 文件变了：重新计数
            } else if entry.recentlyModified {
                needRead = true                        // 上次读的时候文件刚被写过，再读一遍确认
            } else if entry.failures > 0, entry.failures < RegistryScanner.maxRetries,
                      let t = entry.nextRetryAt, t <= now {
                needRead = true                        // 写了一半的文件：到点重试
            }
            if !needRead {
                if let r = entry.record { result.records[pid] = r }
                if entry.failures > 0, entry.failures < RegistryScanner.maxRetries, let t = entry.nextRetryAt {
                    result.nextRetry = min(result.nextRetry ?? t, t)
                }
                entries[pid] = entry
                continue
            }
            entry.signature = st

            if let data = readFile(path), let parsed = RegistryScanner.parse(data) {
                entry.failures = 0
                entry.nextRetryAt = nil
                if var rec = parsed {
                    rec.pid = pid                        // 文件名的 pid 为准：引擎探测存活用的就是它，记录里的 pid 只是冗余信息
                    if entry.record != rec { result.changed.insert(pid) }
                    entry.record = rec
                    entry.skipped = false
                } else {
                    // JSON 合法但不是 interactive 会话，或缺少必需字段 → 不显示
                    if entry.record != nil { result.changed.insert(pid) }
                    entry.record = nil
                    entry.skipped = true
                }
            } else {
                // 读失败或写了一半的 JSON：保留上一份好记录，50 ms 后再试，最多 5 次
                entry.failures += 1
                if entry.failures < RegistryScanner.maxRetries {
                    entry.nextRetryAt = now.addingTimeInterval(RegistryScanner.retryInterval)
                    result.nextRetry = min(result.nextRetry ?? entry.nextRetryAt!, entry.nextRetryAt!)
                } else {
                    entry.nextRetryAt = nil
                }
            }
            entry.readAt = now
            entry.recentlyModified = now.timeIntervalSince(st.mtime) < 0.1 && now >= st.mtime
            if entry.recentlyModified {
                let t = now.addingTimeInterval(RegistryScanner.retryInterval)
                result.nextRetry = min(result.nextRetry ?? t, t)
            }
            entries[pid] = entry
            if let r = entry.record { result.records[pid] = r }
        }
        for pid in Array(entries.keys) where !seen.contains(pid) {
            if entries[pid]?.record != nil { result.removed.insert(pid) }
            entries[pid] = nil
        }
        return result
    }

    /// 解析一个登记表文件。
    /// - 返回 nil：JSON 不完整 / 不合法（写了一半）；
    /// - 返回 .some(nil)：JSON 合法，但不该显示（非 interactive，或缺 pid / sessionId）；
    /// - 返回 .some(record)：一条可用记录。
    public static func parse(_ data: Data) -> RegistryRecord?? {
        guard let obj = SafeJSON.object(data) else { return nil }
        // pid 必须是真正的整数 pid（1…Int32.max）：布尔 / 小数 / 0 / 负数 / 超出范围的数都当作不可用，
        // 不能被 `int32Value` 悄悄截断成别的 pid（比如 4294967297 → 1）
        guard let pidNum = obj["pid"] as? NSNumber, !TimeUtil.isBool(pidNum),
              case let pd = pidNum.doubleValue, pd.rounded() == pd, pd >= 1, pd <= Double(Int32.max),
              let sid = obj["sessionId"] as? String, !sid.isEmpty, sid.utf8.count <= SafeJSON.maxIdLength else {
            return .some(nil)
        }
        let kind = obj["kind"] as? String
        if let k = kind, k != "interactive" { return .some(nil) }

        func str(_ key: String, max n: Int = SafeJSON.maxLabelLength) -> String? {
            guard let s = SafeJSON.string(obj[key], max: n), !s.isEmpty else { return nil }
            return s
        }
        var r = RegistryRecord(pid: Int32(pd), sessionId: sid)
        r.cwd = str("cwd")
        r.startedAt = TimeUtil.date(fromJSONMillis: obj["startedAt"])
        r.procStartRaw = str("procStart", max: 64)
        r.procStart = r.procStartRaw.flatMap { TimeUtil.parseProcStart($0) }
        r.pidDomain = str("pidDomain", max: 64)
        r.version = str("version", max: 64)
        r.kind = kind
        r.entrypoint = str("entrypoint", max: 64)
        r.hostSessionId = SafeJSON.id(obj["hostSessionId"])
        r.name = str("name")
        r.nameSource = str("nameSource", max: 64)
        r.nameSince = TimeUtil.date(fromJSONMillis: obj["nameSince"])
        r.statusRaw = str("status", max: 64)
        r.status = r.statusRaw.flatMap { Phase(rawValue: $0) }
        r.waitingFor = str("waitingFor", max: 200)
        r.updatedAt = TimeUtil.date(fromJSONMillis: obj["updatedAt"])
        r.statusUpdatedAt = TimeUtil.date(fromJSONMillis: obj["statusUpdatedAt"])
        return .some(r)
    }
}
