import Foundation

/// ccmon hook 事件文件（`~/.claude/.monitor/<sessionId>.events.jsonl`）的增量读取器。
///
/// 只读**登记表里这个会话**的那一个文件：文件名由 `Paths.hookLogPath(sessionId:)` 拼出，
/// 绝不扫描 `.monitor` 目录（里面约 60% 是 Codex 的）。
public final class HookLogReader {
    public struct PollResult {
        public var events: [HookEvent] = []
        /// 文件被截断 / 轮转了（调用者要作废由它推出来的状态）。一次读到的事件太多、只留下最新的一批时也会置位。
        public var reset = false
        public var exists = true
    }

    /// 一次 poll 最多交出多少个事件（只留最新的）。正常情况下一次只有几个到几十个；
    /// 文件一下子长了几十 MB（App 被挂起很久 / 文件被换成一个大文件）时，不能把上百万个事件全堆在内存里。
    public static let maxEventsPerPoll = 20_000

    public let path: String
    public private(set) var degradedLines = 0     // JSON 解析失败、靠扫描抠字段的行数
    public private(set) var skippedLines = 0      // 完全没法解析的行数
    public private(set) var totalEvents = 0
    private let tailer: JSONLTailer

    public init(path: String) {
        self.path = path
        self.tailer = JSONLTailer(path: path, config: .init(maxLineBytes: 1 << 20, chunkBytes: 256 << 10))
    }

    /// 第一次读：从尾部窗口开始（文件可能有几 MB，只关心最近的状态）。
    public func bootstrap(tailWindow: Int = 256 << 10) -> PollResult {
        tailer.seekToTail(window: tailWindow)
        return poll()
    }

    public func poll() -> PollResult {
        var out = PollResult()
        var overflowed = false
        let cap = HookLogReader.maxEventsPerPoll
        let r = tailer.poll { [self] bytes in
            if let ev = LineSanitizer.parseHookLine(bytes) {
                if ev.degraded { degradedLines += 1 }
                totalEvents += 1
                out.events.append(ev)
                if out.events.count >= 2 * cap {                       // 摊还 O(1)：攒到两倍再一次性丢掉旧的
                    out.events.removeFirst(out.events.count - cap)
                    overflowed = true
                }
            } else {
                skippedLines += 1
            }
        }
        if out.events.count > cap { out.events.removeFirst(out.events.count - cap); overflowed = true }
        out.reset = r.reset || overflowed
        out.exists = !r.missing
        return out
    }
}
