import Foundation

/// Double → Int，NaN / ±∞ / 超出 Int 范围都不会陷阱（`Int(Double)` 对这些是运行时陷阱）：NaN → 0，其余夹到 ±2^53（Double 能精确表示的整数上限）。
/// 时间差这类「从外部时间戳算出来的 Double」转 Int 前用它（被写坏 / 被篡改的时间戳不能让 App 崩）。
@inline(__always) public func safeInt(_ d: Double) -> Int {
    if d.isNaN { return 0 }
    let limit = 9_007_199_254_740_992.0
    return Int(max(-limit, min(limit, d)))
}
