import Foundation

/// 「绝不打开密钥文件 / socket」在**真实环境**里的证据（`buddydump --audit-opens 秒数`，QA 长跑之外的直接检查）。
///
/// 给 `FileIO.openObserver` 装一个记录器，让数据层真的跑一段时间（读真实的 ~/.claude，只读，和 App 用的是同一条链路），
/// 结束后按类别汇总：一共打开过哪几类文件、各多少个、有没有出现不该出现的路径、保险（`FileIO.forbiddenHits`）有没有拒绝过。
/// 汇总里**只有类别和个数，不打印文件名**（会话 id 等）；只有出现不该有的路径时才把那条路径带出来。
public final class OpenAudit: @unchecked Sendable {
    public struct Row: Sendable, Equatable {
        public var name: String
        public var distinct: Int
        public var opens: Int
    }

    public struct Report: Sendable, Equatable {
        public var rows: [Row]
        public var totalOpens: Int
        /// 观察这段时间里，保险拒绝打开的次数（= 有代码尝试过打开一个不该打开的文件；正常必须是 0）
        public var forbiddenAttempts: Int
        /// 不该出现的路径（名字不合规的、类别之外的、本该被保险拦下的）
        public var offenders: [String]
        public var ok: Bool { offenders.isEmpty && forbiddenAttempts == 0 }

        public func text() -> String {
            var out: [String] = ["open 审计（数据层只读地跑了一段真实数据；只列类别和个数，不列文件名）："]
            for r in rows { out.append("  \(r.name)：\(r.distinct) 个文件，共 \(r.opens) 次") }
            if rows.isEmpty { out.append("  （这段时间里一个文件也没打开）") }
            out.append("  合计 \(totalOpens) 次 open；保险拒绝过的尝试 \(forbiddenAttempts) 次；不该出现的路径 \(offenders.count) 个")
            for p in offenders.prefix(10) { out.append("  ✗ \(p)") }
            out.append(ok ? "  结论：✅ 没有打开过任何密钥文件 / socket，也没有任何代码尝试过；sessions 目录里打开的文件名全部是 <pid>.json"
                          : "  结论：✗ 有问题，见上面")
            return out.joined(separator: "\n")
        }
    }

    private let lock = NSLock()
    private var opened: [String: Int] = [:]
    private var forbiddenBase = 0
    /// 只记这个前缀下的路径（nil = 全部）。`FileIO.openObserver` 是全局的：同一个进程里并行跑的别的测试（读它们自己的临时目录）也会被观察到，
    /// 测试里要把范围缩到自己的假 home（SAN-02）；真实环境里（`buddydump --audit-opens`）不设范围：进程里的每一次 open 都要看。
    private var scope: String?

    public init() {}

    /// 装上观察口，并记下保险此前拒绝过的次数（报告里只算装上之后的）。
    public func install(scope: String? = nil) {
        forbiddenBase = FileIO.forbiddenHits
        self.scope = scope
        FileIO.openObserver = { [self] path in record(path) }
    }

    public func uninstall() { FileIO.openObserver = nil }

    public func record(_ path: String) {
        if let s = scope, !path.hasPrefix(s) { return }
        lock.lock(); opened[path, default: 0] += 1; lock.unlock()
    }

    /// 一个被打开的路径属于哪一类；`expected == false` 表示这个路径本来就不该被打开。
    static func category(of path: String, paths: Paths) -> (name: String, expected: Bool) {
        func under(_ dir: String) -> String? { path.hasPrefix(dir + "/") ? String(path.dropFirst(dir.count + 1)) : nil }
        let last = (path as NSString).lastPathComponent
        if let rest = under(paths.sessionsDir) {
            return !rest.contains("/") && Paths.isRegistryFileName(rest) ? ("登记表 sessions/<pid>.json", true) : ("sessions 目录里名字不合规的文件", false)
        }
        if under(paths.monitorDir) != nil { return last.hasSuffix(".events.jsonl") ? ("hook 事件流 .monitor/<会话>.events.jsonl", true) : (".monitor 目录里名字不合规的文件", false) }
        if under(paths.projectsDir) != nil {
            if last == "custom-title.json" { return ("会话标题 projects/**/custom-title.json", true) }
            return last.hasSuffix(".jsonl") || last.hasSuffix(".meta.json") ? ("会话记录 projects/**（.jsonl / .meta.json）", true) : ("projects 目录里名字不合规的文件", false)
        }
        if under(paths.desktopSessionsDir) != nil {
            return last.hasPrefix("local_") && last.hasSuffix(".json") ? ("桌面会话元数据 local_<uuid>.json", true) : ("桌面会话目录里名字不合规的文件", false)
        }
        if path == paths.codexIndexFile { return ("Codex 线程索引 ~/.codex/session_index.jsonl", true) }
        if under(paths.codexSessionsDir) != nil {
            return CodexNames.threadId(fromRolloutName: last) != nil ? ("Codex 会话记录 ~/.codex/sessions/**/rollout-*.jsonl", true) : ("Codex sessions 目录里名字不合规的文件", false)
        }
        if path == paths.settingsFile { return ("settings.json（只读：检查 hook 有没有注册）", true) }
        if under(paths.appSupportDir) != nil { return ("本 App 自己的数据（identities / ledger）", true) }
        return ("其他位置的文件", false)
    }

    /// 数据层只读地跑 `seconds` 秒（0 = 扫描一次），返回打开过哪些文件的汇总。和 App 用的是同一条链路（`SessionStore`）。
    public static func run(options: SessionStore.Options, seconds: Double, tokens: Bool, scope: String? = nil) -> Report {
        let audit = OpenAudit()
        audit.install(scope: scope)
        defer { audit.uninstall() }
        let store = SessionStore(options: options)
        store.start()
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
        _ = store.pollNow()
        if tokens { store.waitForTokenScan(timeout: 30) }
        _ = store.pollNow()
        store.stop()
        return audit.report(paths: options.engine.paths)
    }

    public func report(paths: Paths) -> Report {
        lock.lock(); let snapshot = opened; lock.unlock()
        var byName: [String: (paths: Set<String>, opens: Int)] = [:]
        var offenders: [String] = []
        for (p, n) in snapshot {
            let c = Self.category(of: p, paths: paths)
            var e = byName[c.name] ?? ([], 0)
            e.paths.insert(p); e.opens += n
            byName[c.name] = e
            if !c.expected || FileIO.isForbidden(path: p) { offenders.append(p) }
        }
        let rows = byName.map { Row(name: $0.key, distinct: $0.value.paths.count, opens: $0.value.opens) }.sorted { $0.name < $1.name }
        return Report(rows: rows, totalOpens: snapshot.values.reduce(0, +), forbiddenAttempts: max(0, FileIO.forbiddenHits - forbiddenBase),
                      offenders: offenders.sorted())
    }
}
