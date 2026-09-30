import Foundation

/// 像素弹簧：从静止起步（v0 = 0）、阻尼比 ζ≈0.75（轻微过冲），输出取整到整像素。
/// 取整带 ±0.6 px 迟滞：只有连续值离当前显示的整数超过 0.6 才换格，弹簧停在半像素附近不会来回跳（看起来就是闪）；
/// 速度 |v| < 0.5 px/s 且已经贴近终点时直接吸附。
public struct PixelSpring: Sendable {
    public var value: Double
    public var velocity: Double = 0
    public var target: Double
    /// 弹簧的响应周期（秒）：越小越快。
    public var period: Double
    public var zeta: Double
    public private(set) var shown: Int

    public init(value: Double = 0, period: Double = 0.42, zeta: Double = 0.75) {
        self.value = value; self.target = value; self.period = period; self.zeta = zeta
        self.shown = Int(value.rounded())
    }

    /// 显式位置（不带动画）。
    public mutating func snap(to v: Double) {
        value = v; target = v; velocity = 0; shown = Int(v.rounded())
    }

    /// 推进 dt 秒，返回要显示的整数像素。
    @discardableResult
    public mutating func step(_ dt: Double) -> Int {
        let omega = 2 * Double.pi / max(0.05, period)
        var remaining = min(dt, 0.25)
        let h = 1.0 / 240
        while remaining > 1e-9 {
            let d = min(h, remaining)
            let acc = -omega * omega * (value - target) - 2 * zeta * omega * velocity
            velocity += acc * d
            value += velocity * d
            remaining -= d
        }
        if abs(velocity) < 0.5, abs(value - target) < 0.6 {
            value = target; velocity = 0
        }
        if abs(value - Double(shown)) > 0.6 { shown = Int(value.rounded()) }
        if velocity == 0 && value == target { shown = Int(target.rounded()) }
        return shown
    }
    public var isSettled: Bool { velocity == 0 && value == target }
}

/// 一段动画：每一帧有自己的时长。
public struct Clip: Sendable {
    public var frames: [Int]          // 帧号（自己解释：精灵下标、姿势下标……）
    public var durations: [Double]    // 每帧秒数
    public var loops: Bool
    public init(frames: [Int], durations: [Double], loops: Bool = true) {
        precondition(frames.count == durations.count && !frames.isEmpty, "帧和时长个数要一致")
        self.frames = frames; self.durations = durations; self.loops = loops
    }
    public init(frames: [Int], each: Double, loops: Bool = true) {
        self.init(frames: frames, durations: [Double](repeating: each, count: frames.count), loops: loops)
    }
    public var total: Double { durations.reduce(0, +) }
    /// t 秒时的帧号；不循环时停在最后一帧。
    public func frame(at t: Double) -> Int {
        guard t > 0 else { return frames[0] }
        var tt = t
        if loops { tt = t.truncatingRemainder(dividingBy: total) } else if t >= total { return frames[frames.count - 1] }
        var acc = 0.0
        for (i, d) in durations.enumerated() {
            acc += d
            if tt < acc { return frames[i] }
        }
        return frames[frames.count - 1]
    }
    public func isFinished(at t: Double) -> Bool { !loops && t >= total }
}

/// 平滑呼吸：4 秒一个周期，输出 0…1（正弦，起点在 0，不突变）。
@inline(__always) public func breathPhase(_ t: Double, period: Double = 4.0) -> Double {
    0.5 - 0.5 * cos(2 * Double.pi * t / period)
}

/// 缓动：ease-in-out，输出 0…1。
@inline(__always) public func smoothstep(_ x: Double) -> Double {
    let t = max(0, min(1, x)); return t * t * (3 - 2 * t)
}
