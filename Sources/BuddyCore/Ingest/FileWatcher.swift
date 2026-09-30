import Foundation
import CoreServices

/// FSEvents 文件监听：一个 stream 同时监听 `~/.claude`（递归）和 `claude-code-sessions` 目录。
///
/// - 延迟 0.05 秒，标志：FileEvents | NoDefer | WatchRoot，事件投递到给定的（ingest）队列；
/// - 这里只负责"有文件变了"这个提示，真正读什么由引擎按路径过滤；
/// - 收到 MustScanSubDirs（事件丢了）时，把根目录本身当作变化的路径回调，调用者做一次全量重扫；
/// - 沙箱里 FSEvents 也许不工作，所以永远要有纯轮询兜底（SessionStore 的 `--poll` 模式）。
public final class FileWatcher {
    public typealias Handler = (_ paths: [String]) -> Void

    public let roots: [String]
    private let queue: DispatchQueue
    private let latency: TimeInterval
    private let handler: Handler
    private var stream: FSEventStreamRef?
    public private(set) var isRunning = false

    public init(roots: [String], queue: DispatchQueue, latency: TimeInterval = 0.05, handler: @escaping Handler) {
        self.roots = roots
        self.queue = queue
        self.latency = latency
        self.handler = handler
    }

    deinit { stop() }

    /// 开始监听。失败（没有可监听的根目录 / 系统不允许）返回 false。
    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        let existing = roots.filter { FileIO.stat($0) != nil }
        guard !existing.isEmpty else { return false }

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var out: [String] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let mustScan = eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                if mustScan { out.append(contentsOf: watcher.roots) } else if i < paths.count { out.append(paths[i]) }
            }
            if !out.isEmpty { watcher.handler(out) }
        }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                                             | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx, existing as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            return false
        }
        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            return false
        }
        stream = s
        isRunning = true
        return true
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        isRunning = false
    }

    /// 解析符号链接后的真实路径（FSEvents 报的是真实路径，比如 /private/var/… 而不是 /var/…）。
    /// 注意不能用 `URL.resolvingSymlinksInPath()`：它会把 /private 前缀又去掉。
    /// 路径（或它的末尾几级）还不存在时，解析最深的、已存在的祖先目录，再把剩下的接回去。
    /// 用循环而不是递归：递归的深度和路径的层数成正比，几百层的路径就会把 GCD 工作线程 512 KB 的栈压爆。
    public static func resolved(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        var rest: [String] = []                          // 还没解析的末尾几级，最里面的一级在最前
        var current = path
        var base: String
        while true {
            if realpath(current, &buf) != nil { base = String(cString: buf); break }
            let ns = current as NSString
            let parent = ns.deletingLastPathComponent
            if parent.isEmpty || parent == current || parent == "/" { base = current; break }
            rest.append(ns.lastPathComponent)
            current = parent
        }
        for last in rest.reversed() { base = base.hasSuffix("/") ? base + last : base + "/" + last }
        return base
    }
}
