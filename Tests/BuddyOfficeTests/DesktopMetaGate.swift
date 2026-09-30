import Foundation
@testable import BuddyOffice

/// `DesktopMeta.baseOverride` 是进程全局的（`RealProvider.make` 收到 `--data-root` 时会写它）。测试都编进同一个进程、跨套件并行（`.serialized` 只管套件内部），
/// 所以写它、或者依赖它的值的测试必须互斥：`DesktopMetaFileIOTests`、`ReviewRegressionAppTests` 的 R2-008、`EngineConfigTests` 里带 `--data-root` 的几条都要走这一把锁
/// （和 R2-005 / SAN-02 同一类问题：间歇性红灯，40 次里 4 次；R3b-01 / R3c-03）。进出都把它复位成 nil，谁也不会把假路径留给别人。
enum DesktopMetaGate {
    private static let lock = NSLock()
    static func exclusive<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); DesktopMeta.baseOverride = nil
        defer { DesktopMeta.baseOverride = nil; lock.unlock() }
        return try body()
    }
}
