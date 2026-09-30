import Testing
import Foundation
@testable import BuddyOffice

/// A-015：DebugTools.log——新式 FileHandle API、私有目录 / 0600 / 轮转、不跟符号链接、失败不崩、不写会话标题、NSLog 不把插值字符串当格式串。
@Suite struct DebugLogTests {
    static func tempDir() -> String {
        let d = NSTemporaryDirectory() + "buddy-log-test-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    static func mode(_ path: String) -> Int? { ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber)?.intValue }

    @Test func linesAreAppendedToAPrivateFileInAPrivateDirectory() throws {
        let root = Self.tempDir(); defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/logs/BuddyOffice/debug.log"
        DebugTools.write("第一行", toPath: path)
        DebugTools.write("第二行", toPath: path)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2 && text.contains("第一行") && text.contains("第二行"))
        #expect(Self.mode(path) == 0o600, "文件 0600（原来是默认的 0644，同机其他用户可读）")
        #expect(Self.mode(root + "/logs/BuddyOffice") == 0o700)
    }

    @Test func theLogIsRotatedInsteadOfGrowingForever() throws {
        let root = Self.tempDir(); defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/debug.log"
        for i in 0..<200 { DebugTools.write("第 \(i) 行 " + String(repeating: "x", count: 40), toPath: path, maxBytes: 2_000) }
        let cur = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        #expect(cur <= 2_000, "当前日志 \(cur) 字节")
        #expect(FileManager.default.fileExists(atPath: path + ".1"), "旧的转成 .1")
        #expect(!FileManager.default.fileExists(atPath: path + ".2"), "只留一份旧的")
        #expect(try String(contentsOfFile: path, encoding: .utf8).contains("第 199 行"), "最新的在当前文件里")
    }

    /// 同机其他用户可以预先放一个符号链接，让 App 往别的自己有权限的文件里追加：不跟链接写。
    @Test func aSymlinkAtTheLogPathIsNeverFollowed() throws {
        let root = Self.tempDir(); defer { try? FileManager.default.removeItem(atPath: root) }
        let target = root + "/victim.txt"
        try "原内容\n".write(toFile: target, atomically: true, encoding: .utf8)
        let path = root + "/debug.log"
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
        DebugTools.write("不许写进去", toPath: path)
        #expect(try String(contentsOfFile: target, encoding: .utf8) == "原内容\n")
    }

    /// 写日志失败（磁盘满 / 路径下面是个普通文件 / 只读目录）不能崩：旧的 seekToEndOfFile / write 出错时抛 Objective-C 异常，Swift 捕不住。
    @Test func failuresNeverCrash() throws {
        DebugTools.write("写不了的路径", toPath: "/dev/full")               // macOS 没有 /dev/full：打不开也创建不了，只能静默放弃
        let root = Self.tempDir(); defer { try? FileManager.default.removeItem(atPath: root) }
        try "x".write(toFile: root + "/afile", atomically: true, encoding: .utf8)
        DebugTools.write("目录其实是个文件", toPath: root + "/afile/sub/debug.log")
        let ro = root + "/ro"
        try FileManager.default.createDirectory(atPath: ro, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o500])
        DebugTools.write("只读目录", toPath: ro + "/debug.log")
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ro)
        DebugTools.write("空路径", toPath: "")
        // 不崩之外还要什么都没写出来：没有凭空建出目录 / 文件，只读目录里也没有日志
        #expect(!FileManager.default.fileExists(atPath: root + "/afile/sub"))
        #expect(!FileManager.default.fileExists(atPath: ro + "/debug.log"))
    }

    @Test func onlyDevelopmentFlagsTurnLoggingOn() {
        #expect(!DebugTools.devFlagsPresent([]))
        #expect(!DebugTools.devFlagsPresent(["--demo", "--show", "--data-root", "/x"]))
        for f in ["--log-ui", "--prof", "--self-test", "--probe-pid", "--test-jump", "--test-autoquit", "--test-titlebar", "--test-hotkey", "--dump-window", "--dump-settings"] {
            #expect(DebugTools.devFlagsPresent([f]), "\(f)")
        }
    }

    @Test func sessionTitlesNeverGoIntoTheLog() {
        let secret = "帮我把银行账号 6222 写进报告"
        #expect(!DebugTools.titleForLog(secret).contains("银行") && DebugTools.titleForLog(secret).contains("\(secret.count)"))
    }

    // MARK: 源码审计（红线：日志里没有标题；NSLog 不把插值字符串当格式串）
    @Test func noDebugLogCallInterpolatesASessionTitle() throws {
        for (name, text) in try SourceAudit.allOfficeSources() {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains("DebugTools.log(") {
                let redacted = line.replacingOccurrences(of: "DebugTools.titleForLog(s.title)", with: "").replacingOccurrences(of: "DebugTools.titleForLog($0.title)", with: "")
                #expect(redacted.range(of: #"\.title\b"#, options: .regularExpression) == nil, "\(name):\(i + 1) 把会话标题写进了日志：\(line)")
            }
        }
    }

    static func nsLogInterpolatesItsFormat(_ line: Substring) -> Bool { line.range(of: #"NSLog\(\s*"[^"]*\\\("#, options: .regularExpression) != nil }

    /// 审计本身管用：修复前的两处写法（AppModel 的演示标题、JumpService 的 AppleScript 错误字典）会被它抓到，修复后的写法不会。
    @Test func theNSLogAuditCatchesTheOldSpellings() {
        #expect(Self.nsLogInterpolatesItsFormat(#"        if demo { NSLog("demo: 跳转到 \(s.title)"); return }"#))
        #expect(Self.nsLogInterpolatesItsFormat(#"            if let e = err { NSLog("BuddyOffice: 终端跳转 AppleScript 出错 \(e)") }"#))
        #expect(!Self.nsLogInterpolatesItsFormat(#"        if demo { NSLog("%@", "demo: 跳转到 \(fresh.title)"); return }"#))
    }

    @Test func noNSLogUsesAnInterpolatedFormatString() throws {
        for (name, text) in try SourceAudit.allOfficeSources() {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where Self.nsLogInterpolatesItsFormat(line) {
                Issue.record("\(name):\(i + 1) NSLog 的格式串里有插值（字符串里有 % 时是未定义行为，应该写 NSLog(\"%@\", msg)）：\(line)")
            }
        }
    }
}
