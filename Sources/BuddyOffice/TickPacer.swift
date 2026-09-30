import Foundation

/// 节拍的调度规则（值类型，单测直接喂时钟）：
///  · 稳态间隔由 AppModel 按需要定（10 / 15 / 30 fps）；
///  · wake()（新数据、鼠标悬停、窗口重新可见……）可以把已经排好的下一拍提前，但两拍之间的间隔不能小于 minInterval（30 fps）——
///    否则鼠标事件的间隔小于约 13 ms（≥ 75 Hz，比如 120 Hz 的触控板）时，每个 mouseMoved 都把下一拍提前，节拍跟着鼠标事件的频率跑
///    （每拍都渲染办公室 + 小鱼缸 + 宠物条）。
struct TickPacer {
    var minInterval: TimeInterval = 1.0 / 30
    /// 下一拍已经排在这么久之后才值得提前。
    static let earlyThreshold: TimeInterval = 0.02
    private(set) var lastTick: TimeInterval = -1000
    private(set) var nextFire: TimeInterval = 0

    mutating func didTick(at now: TimeInterval) { lastTick = now }
    mutating func scheduled(after delay: TimeInterval, now: TimeInterval) { nextFire = now + delay }

    /// wake：需要把下一拍提前就返回新的延迟（秒），不需要返回 nil。
    /// 提前到「上一拍之后满 minInterval」（悬停要立刻出一帧，但不需要超过 30 fps）；比现在排的还晚就不动。
    func wakeDelay(now: TimeInterval) -> TimeInterval? {
        let remaining = nextFire - now
        guard remaining > Self.earlyThreshold else { return nil }
        let d = max(0.001, lastTick + minInterval - now)
        return d < remaining ? d : nil
    }

    /// 一拍做完之后排下一拍的延迟：tick 耗时超过间隔时也至少隔 minDelay，不背靠背（原来是 1 ms 后又来一拍，CPU 顶满）。
    static func delayAfterTick(interval: TimeInterval, elapsed: TimeInterval, minDelay: TimeInterval = 0.004) -> TimeInterval { max(minDelay, interval - elapsed) }
}
