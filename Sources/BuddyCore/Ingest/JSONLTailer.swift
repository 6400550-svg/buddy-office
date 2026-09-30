import Foundation

/// 增量读取 `.jsonl` 的读取器（会话记录最大 44 MB、单行最长 1.5 MB，所以只能流式读）。
///
/// - 用 `pread` 每次最多读 1 MiB，用 `memchr` 找换行；
/// - 只处理**完整**的行，末尾的半行留到下次再拼；
/// - 单行超过 `maxLineBytes`（默认 4 MiB）就丢掉，一直跳到下一个 `\n`；
/// - 文件变短（被截断）或换了 inode（被轮转 / 重写）就从头读；
/// - 热路径上绝不整文件读取。
public final class JSONLTailer {
    public struct Config: Sendable {
        public var maxLineBytes: Int
        public var chunkBytes: Int
        public init(maxLineBytes: Int = 4 << 20, chunkBytes: Int = 1 << 20) {
            self.maxLineBytes = maxLineBytes
            self.chunkBytes = chunkBytes
        }
    }

    public struct PollResult: Equatable {
        public var bytesRead = 0
        public var lines = 0
        /// 这次读取前发现文件被截断 / 轮转，已经从头开始。
        public var reset = false
        /// 文件不存在（或打不开）。
        public var missing = false
        public var droppedOversize = 0
        public var changed: Bool { bytesRead > 0 || reset }
    }

    public let path: String
    public let config: Config

    /// 下一个要读的字节位置（已经读到这里）。
    public private(set) var offset: UInt64 = 0
    /// 最近一次 stat 看到的文件大小。
    public private(set) var lastSize: UInt64 = 0
    public private(set) var fileID: (dev: UInt64, ino: UInt64)?
    /// 累计丢掉的超长行数 / 累计被截断轮转的次数（诊断用）。
    public private(set) var droppedOversizeLines = 0
    public private(set) var resetCount = 0

    private var pending: [UInt8] = []
    private var skipping = false

    public init(path: String, config: Config = Config()) {
        self.path = path
        self.config = config
    }

    /// 半行缓冲当前占的内存容量（字节；测试 / 诊断用）。
    var pendingCapacity: Int { pending.capacity }

    /// 清空半行缓冲；超过 64 KiB 的容量直接释放（读过一条 1.5 MB 的长行之后，别一直占着几 MB 内存：
    /// 几十个文件同时在跟踪时，每个读取器都留着自己最大的那一块会很可观）。
    private func clearPending() {
        if pending.capacity > 64 << 10 { pending = [] } else { pending.removeAll(keepingCapacity: true) }
    }

    /// 下一条**完整行**的起点（写进账本 / 从这里恢复时用，半行会被重新读）。
    public var committedOffset: UInt64 {
        skipping ? offset : offset - UInt64(pending.count)
    }

    /// 从指定位置开始读（恢复账本时用）。调用者保证这是一条完整行的起点。
    public func seek(to newOffset: UInt64, fileID id: (dev: UInt64, ino: UInt64)?) {
        offset = newOffset
        fileID = id
        clearPending()
        skipping = false
    }

    /// 只关心"当前状态"的读者：从文件尾部 `window` 字节处开始读，并对齐到行首
    /// （起点落在一行中间时，跳过那半行）。
    public func seekToTail(window rawWindow: Int) {
        let window = max(0, rawWindow)                       // 负数当 0（从文件尾开始），UInt64(负数) 会 trap
        guard let st = FileIO.stat(path) else { return }
        fileID = (st.dev, st.ino)
        lastSize = st.size
        clearPending()
        skipping = false
        if st.size <= UInt64(window) { offset = 0; return }
        let start = st.size - UInt64(window)
        offset = start
        let fd = FileIO.open(path)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var prev: UInt8 = 0
        if pread(fd, &prev, 1, off_t(start - 1)) == 1, prev == 0x0A { skipping = false } else { skipping = true }
    }

    /// 回到文件开头（保留 fileID）。
    public func rewind() {
        offset = 0
        clearPending()
        skipping = false
    }

    private func resetState() {
        offset = 0
        clearPending()
        skipping = false
        resetCount += 1
    }

    /// 读取新增的完整行，逐行回调。回调里拿到的指针只在回调期间有效（不含换行符）。
    @discardableResult
    public func poll(_ handler: (UnsafeBufferPointer<UInt8>) -> Void) -> PollResult {
        var result = PollResult()
        guard let st = FileIO.stat(path), !st.isDirectory else {
            // 文件没了：状态清零，等它再出现时从头读。
            if fileID != nil { resetState(); fileID = nil; result.reset = true }
            result.missing = true
            lastSize = 0
            return result
        }
        if let id = fileID, id.dev != st.dev || id.ino != st.ino {
            resetState(); result.reset = true          // 换了文件（轮转 / 重写）
        }
        fileID = (st.dev, st.ino)
        if st.size < offset {
            resetState(); result.reset = true          // 变短（被截断）
        }
        lastSize = st.size
        if st.size == offset { return result }

        let fd = FileIO.open(path)
        guard fd >= 0 else { result.missing = true; return result }
        defer { close(fd) }
        // 用打开的这个 fd 再看一次（stat 和 open 之间文件可能又被换掉 / 截断了）
        guard let fst = FileIO.fstat(fd) else { result.missing = true; return result }
        if let id = fileID, id.dev != fst.dev || id.ino != fst.ino {
            resetState(); result.reset = true
        }
        fileID = (fst.dev, fst.ino)
        if fst.size < offset { resetState(); result.reset = true }
        let size = fst.size
        lastSize = size
        if size <= offset { return result }
        // 读缓冲按这次要读的量分配（最多一个 chunk），读完就释放：几十个文件同时在跟踪时不会各占 1 MiB 常驻内存
        let cap = max(1, Int(min(UInt64(config.chunkBytes), size - offset)))
        let buf = UnsafeMutableRawPointer.allocate(byteCount: cap, alignment: 16)
        defer { buf.deallocate() }
        while offset < size {
            let want = Int(min(UInt64(cap), size &- offset))
            let n = pread(fd, buf, want, off_t(offset))
            if n <= 0 { break }
            offset += UInt64(n)
            result.bytesRead += n
            consume(UnsafePointer(buf.assumingMemoryBound(to: UInt8.self)), n, handler, &result)
        }
        return result
    }

    private func consume(_ base: UnsafePointer<UInt8>, _ n: Int,
                         _ handler: (UnsafeBufferPointer<UInt8>) -> Void, _ result: inout PollResult) {
        var start = 0
        while start < n {
            guard let hit = memchr(base + start, 0x0A, n - start) else {
                // 这一块里没有换行：并入半行
                if !skipping {
                    pending.append(contentsOf: UnsafeBufferPointer(start: base + start, count: n - start))
                    if pending.count > config.maxLineBytes {
                        pending = []                       // 释放内存
                        skipping = true
                        droppedOversizeLines += 1
                        result.droppedOversize += 1
                    }
                }
                return
            }
            let nl = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
            let segLen = nl - start
            if skipping {
                skipping = false                            // 超长行到这里结束
            } else if pending.isEmpty {
                if segLen > config.maxLineBytes {
                    droppedOversizeLines += 1; result.droppedOversize += 1
                } else if segLen > 0 {
                    deliver(UnsafeBufferPointer(start: base + start, count: segLen), handler, &result)
                }
            } else {
                if pending.count + segLen > config.maxLineBytes {
                    droppedOversizeLines += 1; result.droppedOversize += 1
                    pending = []
                } else {
                    pending.append(contentsOf: UnsafeBufferPointer(start: base + start, count: segLen))
                    pending.withUnsafeBufferPointer { deliver($0, handler, &result) }
                    clearPending()
                }
            }
            start = nl + 1
        }
    }

    @inline(__always)
    private func deliver(_ line: UnsafeBufferPointer<UInt8>, _ handler: (UnsafeBufferPointer<UInt8>) -> Void,
                         _ result: inout PollResult) {
        var l = line
        if let last = l.last, last == 0x0D { l = UnsafeBufferPointer(rebasing: l[0..<(l.count - 1)]) }
        if l.isEmpty { return }
        result.lines += 1
        handler(l)
    }
}
