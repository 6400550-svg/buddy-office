import Foundation

/// SplitMix64 确定性随机数（外观抽取、抖动错峰用）。
/// 和 BuddyCore 里的 SplitMix64 算法相同；这里另起一个名字，避免两个模块同时 import 时重名。
public struct PixelRNG: RandomNumberGenerator, Sendable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// [0, n) 的均匀整数（n > 0）。
    public mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    /// [0, 1) 的浮点。
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
