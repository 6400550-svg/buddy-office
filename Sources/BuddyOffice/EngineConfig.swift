import Foundation
import BuddyCore

/// 设置页里「空闲 / 下班工位」四项 → 数据层 SessionEngine.Options 的映射（纯函数：测试直接喂数字，不碰 UserDefaults）。
/// 引擎的 Options 是构造时定下来的（`SessionEngine.options` 是 let），所以这四项是「下次启动生效」——设置页里写明了；
/// 「最多保留」调小会立刻生效（AppModel.derive 还会再截一次）。
enum EngineConfig {
    struct Values: Equatable {
        var dozeAfter: TimeInterval
        var sleepAfter: TimeInterval
        var dormantMax: Int
        var dormantRecent: TimeInterval
    }

    /// 范围和设置页的控件一致（打盹 1–120 分钟、睡着 2–240 分钟、下班工位 0–8 个、最近 1–24 小时）；
    /// 睡着必须至少比打盹晚 1 分钟——状态机先判 idleFor >= sleepAfter，睡着 ≤ 打盹时永远走不到「打盹」。
    static func values(dozeMinutes: Int, sleepMinutes: Int, dormantMax: Int, recentHours: Int) -> Values {
        let doze = Settings.clamp(dozeMinutes, 1...120)
        let sleep = max(Settings.clamp(sleepMinutes, 2...240), doze + 1)
        return Values(dozeAfter: TimeInterval(doze * 60), sleepAfter: TimeInterval(sleep * 60),
                      dormantMax: Settings.clamp(dormantMax, 0...8), dormantRecent: TimeInterval(Settings.clamp(recentHours, 1...24) * 3600))
    }

    /// 把设置里的四项填进引擎的 Options（其余字段不动）。
    static func apply(to options: inout SessionEngine.Options, settings: Settings) {
        let v = values(dozeMinutes: settings.int("idle.dozeMinutes"), sleepMinutes: settings.int("idle.sleepMinutes"),
                       dormantMax: settings.int("dormant.max"), recentHours: settings.int("dormant.recentHours"))
        options.dozeAfter = v.dozeAfter
        options.sleepAfter = v.sleepAfter
        options.dormantMax = v.dormantMax
        options.dormantRecent = v.dormantRecent
    }
}
