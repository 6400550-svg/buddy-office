// swift-tools-version: 6.0
// 数据层（BuddyCore）的隔离开发包：源码目录是指向上层真实目录的符号链接。
// 好处：只编译 BuddyCore / buddydump / BuddyCoreTests，不受别的模块半成品影响。
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "BuddyCoreDev",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "buddydump", targets: ["buddydump"])],
    targets: [
        .target(name: "BuddyCore", swiftSettings: v5),
        .executableTarget(name: "buddydump", dependencies: ["BuddyCore"], swiftSettings: v5),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"], swiftSettings: v5),
    ]
)
