import Foundation

/// 64 位混合器：把一串整数 / 可哈希值折成一个指纹。只用来判断「这一帧的输入和上一帧一样吗」，只在进程内比较
/// （Hashable 的 hashValue 每次启动的种子不同，所以指纹不能存盘、不能拿来做金图）。
struct KeyHasher {
    var h: UInt64 = 0xcbf29ce484222325
    @inline(__always) mutating func add(_ x: Int) {
        h = (h ^ UInt64(bitPattern: Int64(x))) &* 0x100000001b3
        h ^= h >> 29
    }
    @inline(__always) mutating func add(_ b: Bool) { add(b ? 1 : 0) }
    @inline(__always) mutating func add(_ d: Double) { add(Int(truncatingIfNeeded: d.bitPattern)) }
    mutating func add(_ s: String) { for b in s.utf8 { add(Int(b)) }; add(-1) }
    @inline(__always) mutating func add<T: Hashable>(_ v: T) { add(v.hashValue) }
}
