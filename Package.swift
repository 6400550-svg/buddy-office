// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
// 库（画布、美术、表现层、数据层）在 debug 构建里也开优化：渲染循环在 -Onone 下慢 30 倍，闪烁扫描 / 局部重绘对比这类测试会跑上十几分钟。
// 溢出 / 越界检查仍然开着（不是 -Ounchecked）。测试目标本身仍是 debug。
let optimizedLibs: [SwiftSetting] = v5 + [.unsafeFlags(["-O"], .when(configuration: .debug))]

let package = Package(
    name: "BuddyOffice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BuddyOffice", targets: ["BuddyOffice"]),
        .executable(name: "buddyctl", targets: ["buddyctl"]),
        .executable(name: "buddydump", targets: ["buddydump"]),
    ],
    targets: [
        // 数据 + 状态融合：只依赖 Foundation / Darwin / CoreServices(FSEvents)
        .target(name: "BuddyCore", exclude: ["README.md"], swiftSettings: optimizedLibs),
        // 画布、调色板、精灵解析、弹簧、PNG/GIF 导出、文字叠层
        .target(name: "PixelKit", swiftSettings: optimizedLibs),
        // 全部美术（代码形式）
        .target(name: "BuddyArt", dependencies: ["PixelKit"], exclude: ["Character/STYLE.md"], swiftSettings: optimizedLibs),
        // 表现层、场景、布局、屏幕内容、闪烁扫描
        .target(name: "BuddyStage", dependencies: ["BuddyCore", "PixelKit", "BuddyArt"], swiftSettings: optimizedLibs),
        .executableTarget(name: "BuddyOffice",
                          dependencies: ["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"],
                          swiftSettings: v5 + [.define("HAS_SESSIONSTORE")]),
        .executableTarget(name: "buddyctl",
                          dependencies: ["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"], swiftSettings: v5),
        // 只依赖 BuddyCore 的小工具（buddyctl dump 用的是同一份实现），方便数据层单独构建
        .executableTarget(name: "buddydump", dependencies: ["BuddyCore"], swiftSettings: v5),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"], swiftSettings: v5),
        .testTarget(name: "BuddyStageTests", dependencies: ["BuddyStage", "BuddyArt", "PixelKit", "BuddyCore"], exclude: ["golden.txt"], swiftSettings: v5),
        // App 层（AppKit 胶水：设置接线 / 提醒 / 跳转 / 自动收起 / 面板定位）：SwiftPM 支持 @testable import 可执行目标，测的都是抽出来的纯逻辑，不起 NSApplication、不弹窗口
        .testTarget(name: "BuddyOfficeTests", dependencies: ["BuddyOffice", "BuddyStage", "BuddyCore", "PixelKit", "BuddyArt"], swiftSettings: v5),
    ]
)
