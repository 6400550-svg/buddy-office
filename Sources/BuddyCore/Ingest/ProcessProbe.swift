import Foundation

/// 对一个 pid 的一次探测结果。
public struct ProcessStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case alive     // kill(pid,0) 返回 0 或 EPERM
        case dead      // ESRCH
        case unknown   // 探测手段失败（沙箱里可能发生）：按"当作还活着"处理
    }
    public var state: State
    /// sysctl(KERN_PROC_PID) 读到的进程启动时间（失败为 nil）。
    public var startTime: Date?
    public init(state: State, startTime: Date? = nil) { self.state = state; self.startTime = startTime }
}

/// 进程探测。做成协议，测试和 replay 里用假 pid（`FakeProcessProbe`）。
public protocol ProcessProbing: AnyObject {
    func probe(pid: Int32) -> ProcessStatus
}

/// 综合判断结果。
public enum ProcessLiveness: Sendable, Equatable {
    case alive
    case dead
    /// 进程还在，但启动时间和登记表里的 procStart 相差超过 2 秒 → PID 已经被别的进程复用。
    case reused
}

public enum ProcessProbe {
    /// 登记表 procStart 与 sysctl 启动时间的容差（秒）。
    public static let startTolerance: TimeInterval = 2

    /// 判定一个登记记录对应的进程是不是还是"那个"进程。
    /// - `procStart` 为 nil（登记表没有这个字段）或探测不到启动时间时，无法比较，按还活着处理。
    /// - **绝不因为时间戳旧就判死**：只看进程。
    public static func classify(_ status: ProcessStatus, procStart: Date?) -> ProcessLiveness {
        switch status.state {
        case .dead: return .dead
        case .unknown: return .alive
        case .alive:
            if let expected = procStart, let actual = status.startTime,
               abs(actual.timeIntervalSince(expected)) > startTolerance {
                return .reused
            }
            return .alive
        }
    }
}

/// 真实的探测：`kill(pid, 0)` + `sysctl(KERN_PROC_PID)`。
public final class SystemProcessProbe: ProcessProbing {
    public init() {}

    public func probe(pid: Int32) -> ProcessStatus {
        guard pid > 0 else { return ProcessStatus(state: .dead) }
        let r = kill(pid, 0)
        if r != 0 {
            switch errno {
            case ESRCH: return ProcessStatus(state: .dead)
            case EPERM: break                       // 没权限发信号 = 进程存在
            default: return ProcessStatus(state: .unknown)
            }
        }
        return ProcessStatus(state: .alive, startTime: SystemProcessProbe.startTime(of: pid))
    }

    /// `kp_proc.p_starttime`；sysctl 失败（例如沙箱里）返回 nil。
    public static func startTime(of pid: Int32) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = mib.withUnsafeMutableBufferPointer { sysctl($0.baseAddress, 4, &info, &size, nil, 0) }
        guard rc == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }
}

/// 假的探测：测试和 replay 用。线程安全。
public final class FakeProcessProbe: ProcessProbing {
    private let lock = NSLock()
    private var table: [Int32: ProcessStatus] = [:]
    /// 没登记过的 pid 的默认状态。
    public var defaultState: ProcessStatus.State = .dead

    public init(defaultState: ProcessStatus.State = .dead) { self.defaultState = defaultState }

    /// 让某个 pid "活着"，并指定它的启动时间（nil = 探测不到启动时间）。
    public func setAlive(_ pid: Int32, start: Date?) {
        lock.lock(); table[pid] = ProcessStatus(state: .alive, startTime: start); lock.unlock()
    }
    public func setUnknown(_ pid: Int32) {
        lock.lock(); table[pid] = ProcessStatus(state: .unknown); lock.unlock()
    }
    /// 让某个 pid 死掉。
    public func kill(_ pid: Int32) {
        lock.lock(); table[pid] = ProcessStatus(state: .dead); lock.unlock()
    }
    public func probe(pid: Int32) -> ProcessStatus {
        lock.lock(); defer { lock.unlock() }
        return table[pid] ?? ProcessStatus(state: defaultState)
    }
}
