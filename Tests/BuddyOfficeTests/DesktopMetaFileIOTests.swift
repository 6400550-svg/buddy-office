import Testing
import Foundation
import BuddyCore
@testable import BuddyOffice

/// C-032：桌面元数据（点击跳转 / 提醒判定读 lastFocusedAt）的读取走 BuddyCore 的 FileIO 统一入口——
/// 它拒绝 `*.key` / `*.sock`（含符号链接、大小写绕过）和命名管道，读不到的文件当作没有。（`import BuddyCore` 保留，别的测试要用。）
@Suite(.serialized) struct DesktopMetaFileIOTests {
    /// 诱饵：名字合法（local_*.json）但其实是一个命名管道（FIFO）——`FileManager.contents(atPath:)` 会一直阻塞到有写者出现，
    /// FileIO 用 `O_NONBLOCK` 打开、发现不是普通文件就放弃。
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("desktopmeta-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("acct/org")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"sessionId":"local_a","lastFocusedAt":1000}"#.write(to: dir.appendingPathComponent("local_a.json"), atomically: true, encoding: .utf8)
        try #"{"sessionId":"local_b","lastFocusedAt":2000}"#.write(to: dir.appendingPathComponent("local_b.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("local_bad.json"), atomically: true, encoding: .utf8)
        #expect(mkfifo(dir.appendingPathComponent("local_fifo.json").path, 0o600) == 0)
        return root
    }

    /// 注意：这个套件**不碰**全局的 `FileIO.openObserver`，也不制造会让 `FileIO.forbiddenHits` 加一的诱饵（比如指向 .key 的符号链接）——
    /// BuddyCoreTests 里有测试断言它们的精确值，测试都编进同一个进程、跨套件并行，共用全局量会互相踩（复查 R2-005：单独放在一起跑 70% 失败）。
    /// 「不跟着符号链接读 .key」由 BuddyCore 的 FuzzSecurityTests / FuzzRegressionTests 证明；这里用下面的源码审计保证应用层没有绕过 FileIO 的读文件写法。
    @Test func readsLastFocusedThroughFileIOAndSkipsUnreadableEntries() throws {
        try DesktopMetaGate.exclusive {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            DesktopMeta.baseOverride = root.path
            let all = DesktopMeta.readAll()                                          // 有 FIFO 诱饵：读文件不能被它卡住
            #expect(all == ["local_a": 1000, "local_b": 2000], "\(all)")
            #expect(DesktopMeta.mostRecentHost(all) == "local_b")
            #expect(DesktopMeta.isMostRecentlyFocused(host: "local_b") && !DesktopMeta.isMostRecentlyFocused(host: "local_a"))
        }
    }

    /// 应用层读文件只有 BuddyCore 的 FileIO 一个入口（它拒绝 `*.key` / `*.sock` / 命名管道）：源码里不出现直接读文件的 API。
    @Test func theOfficeLayerReadsFilesOnlyThroughFileIO() throws {
        let bad = SourceAuditTests.offenders([#"FileManager\.default\.contents\("#, #"contentsOfDirectory"#, #"\.enumerator\("#, #"subpathsOfDirectory"#,
                                              #"Data\(contentsOf"#, #"String\(contentsOf"#, #"NSData\(contentsOf"#, #"contentsOfFile"#, #"FileHandle\(forReading"#, #"InputStream\("#],
                                             in: try SourceAudit.allOfficeSources())
        #expect(bad.isEmpty, "应用层直接读文件（改走 FileIO）：\(bad)")
    }

    @Test func aMissingOrUnreadableDirectoryIsJustEmpty() {
        DesktopMetaGate.exclusive {
            DesktopMeta.baseOverride = "/nonexistent-\(UUID().uuidString)"
            #expect(DesktopMeta.readAll().isEmpty)
            #expect(!DesktopMeta.isMostRecentlyFocused(host: "local_a"))
        }
    }
}
