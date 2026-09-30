#if HAS_SESSIONSTORE
import Foundation
import BuddyCore

/// 真实数据：SessionStore（数据层）。--data-root DIR 把所有路径整体换到一棵假的 home 树；--poll 用纯轮询（沙箱里 FSEvents 起不来）。
/// 设置里的「空闲 / 下班工位」四项在这里读进引擎的 Options（EngineConfig）。
enum RealProvider {
    static func make(args: [String], settings: Settings = .shared) -> SnapshotProvider {
        let root = DebugTools.opt(args, "--data-root")
        // 假 home 整体替换：应用层读桌面元数据（lastFocusedAt）的根目录也要跟着换，不然开发副本仍会读真实的桌面会话元数据（R2-008）
        if let root { DesktopMeta.baseOverride = Paths(home: root).desktopSessionsDir }
        var eo = SessionEngine.Options(paths: root.map { Paths(home: $0) } ?? .real)
        eo.persist = !args.contains("--no-persist")
        EngineConfig.apply(to: &eo, settings: settings)
        var o = SessionStore.Options(engine: eo)
        o.usePolling = args.contains("--poll")
        return SessionStore(options: o)
    }
}
#endif
