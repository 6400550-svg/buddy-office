import Testing
@testable import BuddyCore

@Suite struct ModelContractTests {
    @Test func toolCatalogClassifies() {
        #expect(ToolCatalog.category(of: "Read") == .read)
        #expect(ToolCatalog.category(of: "MultiEdit") == .edit)
        #expect(ToolCatalog.category(of: "mcp__Claude_Browser__navigate") == .browser)
        #expect(ToolCatalog.category(of: "mcp__computer-use__app_click") == .computer)
        #expect(ToolCatalog.category(of: "mcp__ccd_session_mgmt__search_session_tr…") == .mcp)
        #expect(ToolCatalog.category(of: "SomethingNew") == .unknown)
        #expect(ToolCatalog.category(of: "TaskStop") == .bash)          // KillShell 的新名字
        #expect(ToolCatalog.category(of: "TaskOutput") == .bash)        // BashOutput 的新名字
        #expect(ToolCatalog.category(of: "TaskCreate") == .todo)
    }

    @Test func mcpServerFromTruncatedName() {
        #expect(ToolCatalog.mcpServer(of: "mcp__ccd_session_mgmt__search_session_tr…") == "ccd_session_mgmt")
        #expect(ToolCatalog.mcpServer(of: "mcp__1a59c906-04da-521d-bda7-7f71b9f9e01c__batch") == "1a59c906-04da-521d-bda7-7f71b9f9e01c")
        #expect(ToolCatalog.mcpServer(of: "Bash") == nil)
    }

    @Test func activityPhase() {
        #expect(Activity.thinking.phase == .busy)
        #expect(Activity.asking.phase == .waiting)
        #expect(Activity.dozing.phase == .idle)
        #expect(Activity.planReview.needsUser)
        #expect(!Activity.finished.needsUser)
    }

    @Test func seedIsDeterministic() {
        let a = AppearanceSeed.seed(key: "d:local_x", salt: 0)
        let b = AppearanceSeed.seed(key: "d:local_x", salt: 0)
        let c = AppearanceSeed.seed(key: "d:local_x", salt: 1)
        #expect(a == b)
        #expect(a != c)
        var r1 = SplitMix64(seed: a), r2 = SplitMix64(seed: a)
        #expect(r1.next() == r2.next())
        // FNV-1a 官方测试向量
        #expect(FNV1a64.hash("") == 0xcbf29ce484222325)
        #expect(FNV1a64.hash("a") == 0xaf63dc4c8601ec8c)
    }
}
