import Testing
import Foundation
@testable import BuddyOffice

/// BuddyOffice 是 executableTarget：确认测试目标能 `@testable import` 它（SwiftPM 会把 main 符号改名，不会真的起 NSApplication）。
@Suite struct BuddyOfficeSmokeTests {
    @Test func testTargetCanImportTheExecutableModule() {
        #expect(JumpService.validHostID("local_abc-123"))
        #expect(!JumpService.validHostID("local_../etc"))
    }
}
