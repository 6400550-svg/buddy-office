import Foundation

/// token 账本：把 `~/.token-meter/plugins/tokens.1m.py` 的算法移植成 Swift。
///
/// 算法（与用量表一致）：
/// - 每行先用字节做预过滤（有没有 `"usage"` 和 `"assistant"`），命中了才解码；
/// - 只算 `message.role == assistant`、有 `message.id`、有合法 `timestamp`、`model != <synthetic>` 且 usage 非空的行；
/// - 缓存写 = 5m + 1h（`cache_creation` 没有细分或对不上总数时，全部当 5m）；
/// - **按 message.id 去重**（同一条回复会分多行写入），每个字段取最大值；
/// - 会话总量 = 输入 + 输出 + 缓存写 + 缓存读，子代理的 token 也算进来；
/// - 按文件缓存 {dev, ino, offset, totals} 到 `ledger.json`，最多 30 秒写一次，退出时再写一次；
/// - 全量扫描放在后台低优先级串行队列里，一次只扫一个文件。
///
/// 和用量表不同的地方（有意的）：没有把 cost-state 里"会话记录没写的后台调用"补进来。
public final class TokenLedger {
    struct Rec {
        var input: UInt32 = 0, output: UInt32 = 0, cw5m: UInt32 = 0, cw1h: UInt32 = 0, cacheRead: UInt32 = 0
        var owner: Int32 = 0
        var cacheWrite: Int { Int(cw5m) + Int(cw1h) }
    }

    final class FileState {
        let path: String
        let id: Int32
        let tailer: JSONLTailer
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        var messages = 0
        var restored = false
        var scannedOnce = false
        /// 属于"每次都重扫"的组（有 prior 会话的桌面会话）：不写断点。
        var noLedger = false
        /// 没有任何 buddy 在用它之后的先后次序（nil = 有人在用）。
        var detachedSeq: Int?
        /// 最近写进来的几条消息（写进账本，重启后用来给半条消息去重）
        var recent: [(hash: UInt64, rec: Rec)] = []
        init(path: String, id: Int32) {
            self.path = path; self.id = id
            self.tailer = JSONLTailer(path: path)
        }
    }

    public struct Totals: Sendable, Equatable {
        public var breakdown = TokenBreakdown()
        public var messages = 0
        public var scannedAllFiles = true
    }

    static let recentKeep = 24
    static let persistInterval: TimeInterval = 30
    /// 账本里恢复出来的单个计数的上限（2^50）：ledger.json 是外部文件，被改坏 / 写坏时数字可能是天文数字或负数，
    /// 不夹住的话后面的累加（`+=`）和 `TokenBreakdown.total` 会溢出 trap。
    static let maxRestoredCount = 1 << 50

    /// 饱和加法（永远不溢出）。
    @inline(__always) static func sat(_ a: Int, _ b: Int) -> Int {
        let (r, o) = a.addingReportingOverflow(b)
        return o ? (b < 0 ? Int.min : Int.max) : r
    }

    /// ledger.json 里的计数 → [0, maxRestoredCount]（不是数字 / 负数 / NaN 当 0）。
    static func restoredCount(_ v: Any?) -> Int {
        guard let n = v as? NSNumber else { return 0 }
        let d = n.doubleValue
        guard d > 0 else { return 0 }
        return d >= Double(maxRestoredCount) ? maxRestoredCount : Int(d)
    }

    private let queue: DispatchQueue
    /// 用来判断"当前是不是在扫描队列上"（`flush()` 用）。
    private static let queueKey = DispatchSpecificKey<UUID>()
    private let queueTag = UUID()
    private let lock = NSLock()
    private let ledgerPath: String?
    private let now: () -> Date

    private var files: [String: FileState] = [:]
    private var fileList: [FileState] = []
    private var filesById: [Int32: FileState] = [:]
    private var nextFileId: Int32 = 0
    private var nextDetachSeq = 0
    /// 没有 buddy 在用的文件最多留多少个（结果留着，万一那个 buddy 又回来）；超出就把最早"没人用"的清出去
    /// （断点转存进 `persisted`，回来时从断点恢复）。否则 App 长时间运行、会话来来去去，文件 / 去重表会一直涨，
    /// 而且每次扫描都要把所有出现过的文件 stat 一遍。
    static let maxDetachedFiles = 64
    private var groups: [String: [String]] = [:]
    private var groupNoLedger: Set<String> = []
    private var messages: [UInt64: Rec] = [:]
    private var persisted: [String: [String: Any]] = [:]
    private var scheduled = false
    private var cancelled = false
    private var dirtySinceFlush = false
    private var lastFlushAt: Date?
    private var _version = 0
    private var _persistenceOK: Bool?
    private var _isScanning = false

    /// 有新的统计结果时回调（在扫描队列上，调用者自己切线程）。
    public var onChange: (() -> Void)?
    /// 每次统计有变化就 +1。（这三个状态在扫描队列上改、在别的线程上读，所以都过锁。）
    public var version: Int { lock.lock(); defer { lock.unlock() }; return _version }
    /// 持久化是不是可用（沙箱里写 Application Support 会失败，只在内存里）。nil = 还没写过。
    public var persistenceOK: Bool? { lock.lock(); defer { lock.unlock() }; return _persistenceOK }
    public var isScanning: Bool { lock.lock(); defer { lock.unlock() }; return _isScanning }

    /// 默认的扫描队列：一条串行的 `.background` 队列（第一次扫大文件不抢前台的 CPU）。
    public static func makeDefaultQueue() -> DispatchQueue { DispatchQueue(label: "buddy.tokenscan", qos: .background) }

    /// `queue`：扫描跑在哪条队列上；nil = 默认的 `.background` 队列。测试可以传更高优先级的队列——机器被别的进程占满时（同时跑几路检查）
    /// `.background` 队列会被饿死几十秒，等它的测试就间歇性超时（R4b-01）。
    public init(ledgerPath: String?, now: @escaping () -> Date = Date.init, queue: DispatchQueue? = nil) {
        self.ledgerPath = ledgerPath
        self.now = now
        let q = queue ?? Self.makeDefaultQueue()
        self.queue = q
        q.setSpecific(key: TokenLedger.queueKey, value: queueTag)
        if let p = ledgerPath { loadPersisted(p) }
    }

    // MARK: - 诊断 / 测试用的只读计数

    /// 账本里现在跟着的文件个数（含已经没有 buddy 在用的）。
    var trackedFileCount: Int { lock.lock(); defer { lock.unlock() }; return fileList.count }
    /// 跨文件去重表（message.id 哈希 → 各字段最大值）里的条数。
    var dedupeEntryCount: Int { lock.lock(); defer { lock.unlock() }; return messages.count }

    // MARK: - 对外接口

    /// 登记一个 buddy 要统计的文件：`transcripts` 是会话记录（桌面会话含 prior 的），`helpers` 是子代理记录。
    /// 只有一个会话记录的组才使用账本里的断点（有 prior 的组每次重扫，保证跨文件去重是准的）。
    public func setGroup(key: String, transcripts: [String], helpers: [String]) {
        lock.lock()
        let paths = transcripts + helpers
        let old = groups[key]
        groups[key] = paths
        if transcripts.count > 1 { groupNoLedger.insert(key) } else { groupNoLedger.remove(key) }
        var added = false
        for p in paths {
            if let fs = files[p] {
                fs.detachedSeq = nil                                 // 又有人用了
                if transcripts.count > 1 { fs.noLedger = true }
                continue
            }
            let fs = FileState(path: p, id: nextFileId)
            nextFileId &+= 1
            fs.noLedger = transcripts.count > 1
            files[p] = fs
            filesById[fs.id] = fs
            fileList.append(fs)
            if !(transcripts.count > 1) { restore(fs) }
            added = true
        }
        lock.unlock()
        if added || old != paths { poke() }
    }

    /// 移除一个 buddy 的登记（文件的统计结果先留着，万一它又回来；没人用的文件超过 `maxDetachedFiles` 个才清理，
    /// 见 `refreshDetached`）。没人用的文件不再被扫描。
    public func removeGroup(key: String) {
        lock.lock(); groups[key] = nil; groupNoLedger.remove(key); lock.unlock()
    }

    /// 一个 buddy 当前的 token 总量。
    public func totals(forKey key: String) -> Totals {
        lock.lock(); defer { lock.unlock() }
        var t = Totals()
        for p in groups[key] ?? [] {
            guard let f = files[p] else { continue }
            t.breakdown.input = TokenLedger.sat(t.breakdown.input, f.input)
            t.breakdown.output = TokenLedger.sat(t.breakdown.output, f.output)
            t.breakdown.cacheWrite = TokenLedger.sat(t.breakdown.cacheWrite, f.cacheWrite)
            t.breakdown.cacheRead = TokenLedger.sat(t.breakdown.cacheRead, f.cacheRead)
            t.messages = TokenLedger.sat(t.messages, f.messages)
            if !f.scannedOnce { t.scannedAllFiles = false }
        }
        return t
    }

    /// 有文件可能增长了：后台重新检查（多次调用会合并）。
    public func poke() {
        lock.lock()
        if scheduled || cancelled { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.async { [weak self] in self?.pass() }
    }

    /// 同步等到当前排队的扫描结束（测试 / dump --once 用）。
    public func waitUntilIdle(timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let busy = scheduled || _isScanning
            lock.unlock()
            if !busy { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    /// 立即写盘（退出时调用）。在扫描队列上（比如 `onChange` 回调里）调用也是安全的：
    /// 已经在队列上就直接写，不再 `queue.sync`（对自己所在的队列 sync 会死锁 / 被 libdispatch 直接崩掉）。
    public func flush() {
        if DispatchQueue.getSpecific(key: TokenLedger.queueKey) == queueTag { writeLedger(force: true) }
        else { queue.sync { self.writeLedger(force: true) } }
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    // MARK: - 扫描

    private func pass() {
        lock.lock()
        scheduled = false
        _isScanning = true
        refreshDetached()
        let list = fileList.filter { $0.detachedSeq == nil }         // 没人用的文件不扫
        lock.unlock()

        var anyChanged = false
        for f in list {
            lock.lock(); let stop = cancelled; lock.unlock()
            if stop { break }
            if scan(f) { anyChanged = true }
        }
        lock.lock(); _isScanning = false; lock.unlock()
        if anyChanged {
            lock.lock(); _version += 1; dirtySinceFlush = true; lock.unlock()
            onChange?()
        }
        writeLedger(force: false)
    }

    /// （持锁调用）标出没有任何 buddy 在用的文件；这样的文件超过 `maxDetachedFiles` 个，就把最早没人用的清出去：
    /// 断点转存进 `persisted`（回来时从断点恢复），去重表里属于它的条目一起删掉。
    /// 只在扫描队列上（`pass()` 开头）做：这时没有任何扫描在进行，清理不会和正在读的文件撞上。
    private func refreshDetached() {
        let active = Set(groups.values.lazy.flatMap { $0 })
        for f in fileList {
            if active.contains(f.path) { f.detachedSeq = nil }
            else if f.detachedSeq == nil { f.detachedSeq = nextDetachSeq; nextDetachSeq += 1 }
        }
        let detached = fileList.filter { $0.detachedSeq != nil }
        guard detached.count > TokenLedger.maxDetachedFiles else { return }
        let victims = detached.sorted { ($0.detachedSeq ?? 0) < ($1.detachedSeq ?? 0) }.prefix(detached.count - TokenLedger.maxDetachedFiles)
        for f in victims {
            if f.scannedOnce, !f.noLedger, let fid = f.tailer.fileID { persisted[f.path] = checkpoint(f, fid) }
            for (k, v) in messages where v.owner == f.id { messages[k] = nil }
            files[f.path] = nil
            filesById[f.id] = nil
        }
        let gone = Set(victims.map { $0.id })
        fileList.removeAll { gone.contains($0.id) }
    }

    /// 一个文件的断点（写进 ledger.json 的那一份）。
    private func checkpoint(_ f: FileState, _ fid: (dev: UInt64, ino: UInt64)) -> [String: Any] {
        [
            "dev": fid.dev, "ino": fid.ino, "offset": f.tailer.committedOffset,
            "input": f.input, "output": f.output, "cw": f.cacheWrite, "cr": f.cacheRead, "n": f.messages,
            "recent": f.recent.map { ["h": String($0.hash, radix: 16), "i": Int($0.rec.input), "o": Int($0.rec.output),
                                      "w5": Int($0.rec.cw5m), "w1": Int($0.rec.cw1h), "r": Int($0.rec.cacheRead)] },
        ] as [String: Any]
    }

    /// 扫一个文件的新增部分。返回统计有没有变化。
    private func scan(_ f: FileState) -> Bool {
        var changed = false
        var seenResets = f.tailer.resetCount
        let r = f.tailer.poll { line in
            if f.tailer.resetCount != seenResets {
                // 文件被截断 / 重写：这个文件贡献的统计作废，从新内容重新累积（必须在处理新行之前做）
                seenResets = f.tailer.resetCount
                self.resetStats(f)
                changed = true
            }
            // 每行解码放进自己的 autoreleasepool：扫大文件时不让 Foundation 的临时对象堆起来
            if autoreleasepool(invoking: { self.handle(line: line, file: f) }) { changed = true }
        }
        if r.reset && r.lines == 0 { resetStats(f); changed = true }
        if !f.scannedOnce {
            // 第一次扫完（文件不存在也算扫完：0 token，别一直显示"扫描中"）
            lock.lock(); f.scannedOnce = true; lock.unlock()
            changed = true
        }
        return changed
    }

    private func resetStats(_ f: FileState) {
        lock.lock(); defer { lock.unlock() }
        f.input = 0; f.output = 0; f.cacheWrite = 0; f.cacheRead = 0; f.messages = 0; f.recent = []
        for (k, v) in messages where v.owner == f.id { messages[k] = nil }
    }

    private static let usageNeedle: [UInt8] = Array("\"usage\"".utf8)
    private static let assistantNeedle: [UInt8] = Array("\"assistant\"".utf8)

    private func handle(line: UnsafeBufferPointer<UInt8>, file f: FileState) -> Bool {
        guard let base = line.baseAddress else { return false }
        // 字节预过滤：先看有没有 "usage" 和 "assistant"
        guard memmem(base, line.count, TokenLedger.usageNeedle, TokenLedger.usageNeedle.count) != nil,
              memmem(base, line.count, TokenLedger.assistantNeedle, TokenLedger.assistantNeedle.count) != nil
        else { return false }
        guard let parsed = TranscriptLineParser.parse(line), parsed.kind == .assistant,
              let mid = parsed.messageId, !mid.isEmpty, parsed.timestamp != nil,
              parsed.model != "<synthetic>", let u = parsed.usage else { return false }
        func c(_ v: Int) -> UInt32 { UInt32(clamping: v) }
        var rec = Rec(input: c(u.input), output: c(u.output), cw5m: c(u.cacheWrite5m), cw1h: c(u.cacheWrite1h),
                      cacheRead: c(u.cacheRead), owner: f.id)
        let h = FNV1a64.hash(mid)
        lock.lock(); defer { lock.unlock() }
        if let old = messages[h] {
            // 同一条回复多次写入：每个字段取最大值；差额记到最早看到它的那个文件上
            let owner = filesById[old.owner] ?? f
            let merged = Rec(input: max(old.input, rec.input), output: max(old.output, rec.output),
                             cw5m: max(old.cw5m, rec.cw5m), cw1h: max(old.cw1h, rec.cw1h),
                             cacheRead: max(old.cacheRead, rec.cacheRead), owner: old.owner)
            let dIn = Int(merged.input) - Int(old.input), dOut = Int(merged.output) - Int(old.output)
            let dCw = merged.cacheWrite - old.cacheWrite, dCr = Int(merged.cacheRead) - Int(old.cacheRead)
            if dIn == 0 && dOut == 0 && dCw == 0 && dCr == 0 { return false }
            owner.input = TokenLedger.sat(owner.input, dIn); owner.output = TokenLedger.sat(owner.output, dOut)
            owner.cacheWrite = TokenLedger.sat(owner.cacheWrite, dCw); owner.cacheRead = TokenLedger.sat(owner.cacheRead, dCr)
            messages[h] = merged
            if let i = owner.recent.lastIndex(where: { $0.hash == h }) { owner.recent[i].rec = merged }
            return true
        }
        rec.owner = f.id
        messages[h] = rec
        f.input = TokenLedger.sat(f.input, Int(rec.input)); f.output = TokenLedger.sat(f.output, Int(rec.output))
        f.cacheWrite = TokenLedger.sat(f.cacheWrite, rec.cacheWrite); f.cacheRead = TokenLedger.sat(f.cacheRead, Int(rec.cacheRead))
        f.messages = TokenLedger.sat(f.messages, 1)
        f.recent.append((h, rec))
        if f.recent.count > TokenLedger.recentKeep { f.recent.removeFirst() }
        return true
    }

    // MARK: - 持久化

    private func loadPersisted(_ path: String) {
        guard let data = FileIO.readAll(path, maxBytes: 64 << 20),
              let obj = SafeJSON.object(data),
              (obj["version"] as? Int) == 1, let files = obj["files"] as? [String: Any] else { return }
        for (k, v) in files { if let d = v as? [String: Any] { persisted[k] = d } }
    }

    /// 用账本里的断点恢复一个文件（文件必须还是同一个 inode，而且没变短）。
    private func restore(_ f: FileState) {
        guard let d = persisted[f.path],
              let dev = (d["dev"] as? NSNumber)?.uint64Value, let ino = (d["ino"] as? NSNumber)?.uint64Value,
              let offset = (d["offset"] as? NSNumber)?.uint64Value,
              let st = FileIO.stat(f.path), st.dev == dev, st.ino == ino, st.size >= offset else { return }
        f.tailer.seek(to: offset, fileID: (dev, ino))
        f.input = TokenLedger.restoredCount(d["input"])
        f.output = TokenLedger.restoredCount(d["output"])
        f.cacheWrite = TokenLedger.restoredCount(d["cw"])
        f.cacheRead = TokenLedger.restoredCount(d["cr"])
        f.messages = TokenLedger.restoredCount(d["n"])
        f.restored = true
        if let recent = d["recent"] as? [[String: Any]] {
            for r in recent {
                guard let hs = r["h"] as? String, let h = UInt64(hs, radix: 16) else { continue }
                func n(_ k: String) -> UInt32 { UInt32(clamping: TokenLedger.restoredCount(r[k])) }
                let rec = Rec(input: n("i"), output: n("o"), cw5m: n("w5"), cw1h: n("w1"), cacheRead: n("r"), owner: f.id)
                messages[h] = rec
                f.recent.append((h, rec))
            }
        }
    }

    private func writeLedger(force: Bool) {
        guard let path = ledgerPath else { return }
        lock.lock()
        let due = force || (dirtySinceFlush && (lastFlushAt.map { now().timeIntervalSince($0) >= TokenLedger.persistInterval } ?? true))
        guard due, dirtySinceFlush || force else { lock.unlock(); return }
        var out: [String: Any] = [:]
        for f in fileList {
            // 这个文件属于"要每次重扫"的组就不写断点
            if let fid = f.tailer.fileID, f.scannedOnce, !isNoLedger(path: f.path) {
                out[f.path] = checkpoint(f, fid)
            }
        }
        // 以前写过、这次没碰的文件也保留（别的 buddy 还没回来），但文件已经不存在的就丢掉，账本不会无限长大
        for (k, v) in persisted where out[k] == nil && files[k] == nil && FileIO.stat(k) != nil { out[k] = v }
        dirtySinceFlush = false
        lastFlushAt = now()
        lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "files": out] as [String: Any]) else { return }
        let ok = FileIO.writeAtomically(data, to: path)
        lock.lock(); _persistenceOK = ok; lock.unlock()
    }

    private func isNoLedger(path: String) -> Bool {
        for (k, paths) in groups where groupNoLedger.contains(k) && paths.contains(path) { return true }
        return false
    }
}
