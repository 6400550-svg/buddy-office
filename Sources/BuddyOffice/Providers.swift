import Foundation
import BuddyCore
import BuddyStage

/// 选择数据源：真实的 SessionStore（数据层）或空数据源。
enum Providers {
    static func make(args: [String]) -> SnapshotProvider {
        #if HAS_SESSIONSTORE
        return RealProvider.make(args: args)
        #else
        return EmptyProvider()
        #endif
    }
}

/// 没有数据层时的占位：永远没有人上班。
final class EmptyProvider: SnapshotProvider {
    var onUpdate: (([BuddySnapshot]) -> Void)?
    var onEvent: ((BuddyEvent) -> Void)?
    func start() { onUpdate?([]) }
    func stop() {}
    func markSeen(key: String) {}
    func rerollAppearance(key: String) {}
    func diagnostics() -> DiagnosticsInfo { DiagnosticsInfo() }
}
