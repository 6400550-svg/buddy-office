import Foundation

/// FNV-1a 64 位。外观种子用：seed = FNV1a64(key) ⊕ (salt × 黄金比例常数)。
public enum FNV1a64 {
    public static func hash(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in bytes { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
    public static func hash(_ string: String) -> UInt64 { hash(Array(string.utf8)) }
}

/// SplitMix64：确定性伪随机，逐个抽取外观属性。
public struct SplitMix64: RandomNumberGenerator, Sendable {
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

public enum AppearanceSeed {
    /// 一个 buddy 的外观种子：key 决定基础，salt 决定「换个造型」的变体。
    public static func seed(key: String, salt: UInt64) -> UInt64 {
        FNV1a64.hash(key) ^ (salt &* 0x9E3779B97F4A7C15)
    }
}
