// swift-tools-version: 6.0
// 美术层的隔离开发包：源码目录是指向上层真实目录的符号链接，只编译 PixelKit + BuddyArt。
import PackageDescription
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let package = Package(
    name: "BuddyArtDev-a",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "artctl", targets: ["artctl"])],
    targets: [
        .target(name: "PixelKit", swiftSettings: v5),
        .target(name: "BuddyArt", dependencies: ["PixelKit"], swiftSettings: v5),
        .executableTarget(name: "artctl", dependencies: ["BuddyArt", "PixelKit"], swiftSettings: v5),
    ]
)
