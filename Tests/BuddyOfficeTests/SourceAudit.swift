import Foundation

/// 源码审计：读 Sources/BuddyOffice 下的文件（测试文件旁边的相对路径），红线类的东西用它守着。
enum SourceAudit {
    static func file(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BuddyOffice/\(name)")
    }
    static func read(_ name: String) throws -> String { try String(contentsOf: file(name), encoding: .utf8) }
    static func allOfficeSources() throws -> [(name: String, text: String)] {
        let dir = file("x").deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted().map { ($0, try read($0)) }
    }
}
