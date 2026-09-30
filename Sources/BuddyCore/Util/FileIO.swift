import Foundation

/// 文件状态（stat 的精简版）。
public struct FileStat: Equatable, Sendable {
    public var dev: UInt64
    public var ino: UInt64
    public var size: UInt64
    /// 修改时间，纳秒。
    public var mtimeNs: Int64
    public var isDirectory: Bool

    public var mtime: Date { Date(timeIntervalSince1970: Double(mtimeNs) / 1e9) }
}

// 枚举里有同名的 stat / fstat 方法，会遮住 Darwin 的同名函数，所以把系统调用放在文件级的小函数里。
typealias SysStat = stat
private func sysStatBuffer() -> SysStat { SysStat() }
private func sysStat(_ path: String, _ st: inout SysStat) -> Int32 { stat(path, &st) }
private func sysFstat(_ fd: Int32, _ st: inout SysStat) -> Int32 { fstat(fd, &st) }

/// BuddyCore 里**所有**读文件的动作都从这里走。
///
/// 两个目的：
/// 1. 保险：绝不打开密钥文件（`*.key`）、socket（`*.sock`）；就算上层有 bug 想打开也会被拒绝。
/// 2. 给测试留一个观察口：`openObserver` 能看到每一次 open 的路径，用来断言"`.key` 永远没被碰过"。
public enum FileIO {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _observer: ((String) -> Void)?
    private nonisolated(unsafe) static var _forbiddenHits = 0
    private nonisolated(unsafe) static var _tmpCounter = 0

    /// 测试用：每次真正要打开文件前调用（参数是路径）。传 nil 取消。
    public static var openObserver: ((String) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _observer }
        set { lock.lock(); _observer = newValue; lock.unlock() }
    }

    /// 被保险拒绝过的次数（正常运行时必须是 0）。
    public static var forbiddenHits: Int {
        lock.lock(); defer { lock.unlock() }; return _forbiddenHits
    }

    /// 这个路径是不是绝不能打开的（密钥 / socket）。
    ///
    /// 判断时**不区分大小写**（macOS 默认的 APFS 大小写不敏感：`1001.abc.KEY` 打开的就是 `1001.abc.key`），
    /// 路径里有 NUL 也拒绝（C 字符串会在 NUL 处截断：`x.key\0.json` 看名字是 .json，实际打开的却是 x.key）；
    /// 路径里任何一段叫 `cc-socks` 的目录都算。
    public static func isForbidden(path: String) -> Bool {
        if path.utf8.contains(0) { return true }
        let name = (path as NSString).lastPathComponent.lowercased()
        if name.hasSuffix(".key") || name.hasSuffix(".sock") { return true }
        if path.lowercased().split(separator: "/", omittingEmptySubsequences: true).contains("cc-socks") { return true }
        return false
    }

    private static func noteForbidden() {
        lock.lock(); _forbiddenHits += 1; lock.unlock()
    }

    /// 符号链接 / `..` / 大小写解析之后的真实路径（解析不了返回 nil）。
    private static func realPath(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        return realpath(path, &buf) != nil ? String(cString: buf) : nil
    }

    /// 只读打开，失败（含被保险拒绝）返回 -1。
    ///
    /// - 保险按**真实路径**判断，绕不过去：名字合法但符号链接指向 `.key` 的（`1001.json -> 1001.<sha>.key`）、
    ///   经过目录符号链接的（`x/cc-alias/a.txt`，cc-alias 指向 cc-socks）、大小写不同的，都会被拒绝。
    ///   文件存在时先解析出真实路径（`realpath`）再判断，被拒绝的路径连 open 都不会调用；
    ///   打开之后再用 fd 自己的真实路径（`F_GETPATH`）核对一遍，挡住解析和打开之间被换掉的情况；
    /// - 只打开普通文件：命名管道 / 设备 / socket / 目录一律拒绝，而且用 `O_NONBLOCK` 打开，
    ///   FIFO 不会把调用线程永远卡在 open() 上。
    public static func open(_ path: String) -> Int32 {
        if isForbidden(path: path) { noteForbidden(); return -1 }
        if let real = realPath(path), isForbidden(path: real) { noteForbidden(); return -1 }
        if let obs = openObserver { obs(path) }
        let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return -1 }
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        if fcntl(fd, F_GETPATH, &buf) == 0, isForbidden(path: String(cString: buf)) {
            Darwin.close(fd); noteForbidden(); return -1
        }
        var st = sysStatBuffer()
        guard sysFstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { Darwin.close(fd); return -1 }
        return fd
    }

    public static func stat(_ path: String) -> FileStat? {
        var st = sysStatBuffer()
        guard sysStat(path, &st) == 0 else { return nil }
        return make(st)
    }

    public static func fstat(_ fd: Int32) -> FileStat? {
        var st = sysStatBuffer()
        guard sysFstat(fd, &st) == 0 else { return nil }
        return make(st)
    }

    private static func make(_ st: SysStat) -> FileStat {
        FileStat(dev: UInt64(bitPattern: Int64(st.st_dev)), ino: UInt64(st.st_ino), size: UInt64(max(0, st.st_size)),
                 mtimeNs: mtimeNs(sec: Int64(st.st_mtimespec.tv_sec), nsec: Int64(st.st_mtimespec.tv_nsec)),
                 isDirectory: (st.st_mode & S_IFMT) == S_IFDIR)
    }

    /// 秒 + 纳秒 → 纳秒（饱和，不 trap：APFS 会把时间夹在 ±9223372036 秒以内，别的文件系统 / 网络盘上可能更大）。
    static func mtimeNs(sec: Int64, nsec: Int64) -> Int64 {
        let (m, o1) = sec.multipliedReportingOverflow(by: 1_000_000_000)
        if o1 { return sec < 0 ? Int64.min : Int64.max }
        let (r, o2) = m.addingReportingOverflow(nsec)
        return o2 ? (nsec < 0 ? Int64.min : Int64.max) : r
    }

    /// 整个读进来（只用在小文件：登记表、桌面元数据、settings.json）。超过 maxBytes 返回 nil。
    public static func readAll(_ path: String, maxBytes: Int = 8 << 20) -> Data? {
        guard maxBytes >= 0 else { return nil }
        let fd = open(path)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let st = fstat(fd), st.size <= UInt64(maxBytes) else { return nil }
        var data = Data(count: Int(st.size))
        var got = 0
        let total = data.count
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return total == 0 }
            while got < total {
                let n = pread(fd, base + got, total - got, off_t(got))
                if n <= 0 { break }
                got += n
            }
            return true
        }
        guard ok else { return nil }
        if got < total { data.removeSubrange(got..<total) }
        return data
    }

    /// 列目录（只返回名字，不含 . 和 ..）；目录不存在返回 nil。
    public static func listDirectory(_ path: String) -> [String]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        var names: [String] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) { p -> String in
                p.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        return names
    }

    /// 临时目录。优先用环境变量 TMPDIR（Claude Code 沙箱里只有它可写，`NSTemporaryDirectory()` 会指到别处）。
    public static var temporaryDirectory: String {
        if let t = ProcessInfo.processInfo.environment["TMPDIR"], !t.isEmpty {
            return t.hasSuffix("/") ? t : t + "/"
        }
        let t = NSTemporaryDirectory()
        return t.hasSuffix("/") ? t : t + "/"
    }

    /// 原子写（先写临时文件再 rename）。失败返回 false（沙箱里写不了 Application Support 是正常的）。
    @discardableResult
    public static func writeAtomically(_ data: Data, to path: String) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // 临时文件名每次调用都不同（进程号 + 递增计数）：几个线程同时写同一个目标文件时不能共用一个临时文件，
            // 否则会互相截断、交错写入，rename 出去的是两次内容的混合
            lock.lock(); _tmpCounter &+= 1; let seq = _tmpCounter; lock.unlock()
            let tmp = path + ".tmp\(getpid())-\(seq)"
            do { try data.write(to: URL(fileURLWithPath: tmp)) } catch {
                unlink(tmp)                      // 写了一半（磁盘满 / 出错）：别留下半截的临时文件
                return false
            }
            if rename(tmp, path) != 0 {
                unlink(tmp)
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
