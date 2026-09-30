import Foundation

/// 轻量分段计时（只在 `buddyctl bench` 里打开）。关着的时候每次调用就是一个布尔判断，不影响帧耗时。
public enum Prof {
    nonisolated(unsafe) public static var enabled = false
    nonisolated(unsafe) static var acc: [String: (ns: UInt64, n: Int)] = [:]

    @inline(__always) public static func begin() -> UInt64 { enabled ? DispatchTime.now().uptimeNanoseconds : 0 }
    @inline(__always) public static func end(_ name: String, _ t0: UInt64) {
        guard enabled else { return }
        let d = DispatchTime.now().uptimeNanoseconds &- t0
        let e = acc[name] ?? (0, 0)
        acc[name] = (e.ns &+ d, e.n + 1)
    }
    public static func reset() { acc.removeAll() }
    /// 每帧平均耗时（毫秒），按总耗时从大到小。
    public static func report(frames: Int) -> String {
        var s = ""
        for (k, v) in acc.sorted(by: { $0.value.ns > $1.value.ns }) {
            s += String(format: "  %-28@ %7.3f ms/帧  (%d 次/帧)\n", k as NSString, Double(v.ns) / 1e6 / Double(max(1, frames)), v.n / max(1, frames))
        }
        return s
    }
}
