// swift-tools-version: 6.0
// 表现层的隔离开发包：BuddyCore 只包含「合同」文件（Model / ToolCatalog / Hashing / Info），
// 所以数据层子代理写到一半的代码不会挡住这边的编译。
import PackageDescription
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let package = Package(
    name: "BuddyStageDev",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "stagectl", targets: ["stagectl"]), .executable(name: "BuddyOffice", targets: ["BuddyOffice"])],
    targets: [
        .target(name: "BuddyCore", swiftSettings: v5),
        .target(name: "PixelKit", swiftSettings: v5),
        .target(name: "BuddyArt", dependencies: ["PixelKit"], swiftSettings: v5),
        .target(name: "BuddyStage", dependencies: ["BuddyCore", "PixelKit", "BuddyArt"], swiftSettings: v5),
        .executableTarget(name: "BuddyOffice", dependencies: ["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"], swiftSettings: v5),
        .executableTarget(name: "stagectl", dependencies: ["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"], swiftSettings: v5),
    ]
)
