import Testing
import Foundation
@testable import BuddyOffice

/// 安全红线的源码审计（BuddyOffice 层）：不联网、不碰钥匙串 / 凭据、不写 ~/.claude、不开子进程、没有第三方依赖、没有 try! / as! / 强制的 fatalError。
/// 一旦谁不小心加了这些东西，这里会立刻红。
@Suite struct SourceAuditTests {
    /// 去掉注释（整行 // 注释和行尾 // 注释；不处理字符串里的 //——BuddyOffice 里没有需要它的地方）。
    static func code(_ text: String) -> [(n: Int, line: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { i, l in
            var s = String(l)
            if let r = s.range(of: "//") { s = String(s[..<r.lowerBound]) }
            return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (i + 1, s)
        }
    }
    static func offenders(_ patterns: [String], in sources: [(name: String, text: String)]) -> [String] {
        var out: [String] = []
        for (name, text) in sources { for (n, line) in code(text) { for p in patterns where line.range(of: p, options: .regularExpression) != nil { out.append("\(name):\(n) 匹配 \(p)：\(line.trimmingCharacters(in: .whitespaces))") } } }
        return out
    }

    @Test func noNetworkAndNoCredentialAPIs() throws {
        let bad = Self.offenders([#"URLSession"#, #"NWConnection"#, #"NWPathMonitor"#, #"CFNetwork"#, #"WKWebView"#, #"import WebKit"#, #"URLRequest"#, #"Sparkle"#,
                                  #"\bsocket\("#, #"SecItem"#, #"Keychain"#, #"import Security"#], in: try SourceAudit.allOfficeSources())
        #expect(bad.isEmpty, "\(bad)")
    }

    /// 运行时不写 ~/.claude、不碰 ccmon / 用量表 / 密钥 / socket：代码（非注释）的字符串里不出现这些路径。
    @Test func noPathsUnderTheClaudeDirectoryOrSecretFiles() throws {
        let bad = Self.offenders([#"[/~]\.claude\b"#, #""\.claude\b"#, #"[/~]\.monitor\b"#, #""\.monitor\b"#, #"cc-socks"#, #""[^"\n]*\.(key|sock)""#, #"token-meter|token_meter|用量表"#],
                                 in: try SourceAudit.allOfficeSources())
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test func noSubprocessesAndNoThirdPartyImports() throws {
        let sources = try SourceAudit.allOfficeSources()
        #expect(Self.offenders([#"\bProcess\(\)"#, #"\bNSTask\b"#, #"posix_spawn"#, #"(?<![.\w])system\("#, #"\bpopen\("#, #"\bfork\("#], in: sources).isEmpty)
        let allowed: Set<String> = ["AppKit", "Foundation", "SwiftUI", "UserNotifications", "ServiceManagement", "Carbon", "AVFoundation", "QuartzCore", "IOSurface", "BuddyCore", "PixelKit", "BuddyArt", "BuddyStage"]
        for (name, text) in sources {
            for line in text.split(separator: "\n") where line.hasPrefix("import ") {
                let m = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                #expect(allowed.contains(m), "\(name) 引入了不在白名单里的模块 \(m)")
            }
        }
    }

    /// 强制解包类的陷阱：没有 try! / as!；fatalError 只出现在 `required init?(coder:)`（永远不会被调用）。
    @Test func noForceTryNoForceCastAndFatalErrorOnlyInRequiredInits() throws {
        for (name, text) in try SourceAudit.allOfficeSources() {
            for (n, line) in Self.code(text) {
                #expect(!line.contains("try!") && !line.contains("as!"), "\(name):\(n) \(line)")
                if line.contains("fatalError(") { #expect(line.contains("required init"), "\(name):\(n) 只有 required init 里允许 fatalError：\(line)") }
            }
        }
    }

    /// 通知授权 / 系统通知只经过 NotificationService（其余文件不直接碰 UNUserNotificationCenter，裸跑的可执行文件会崩）。
    @Test func onlyNotificationServiceTouchesTheUserNotificationCenter() throws {
        for (name, text) in try SourceAudit.allOfficeSources() where name != "NotificationService.swift" {
            #expect(!text.contains("UNUserNotificationCenter"), "\(name)")
        }
    }

    /// 审计本身管用：这些写法会被抓到，正常代码（`$0.key`、`.system(size:)`、bundle id 里的 claude）不会。
    @Test func theAuditsCatchTheirTargetsAndIgnoreLookAlikes() {
        func hits(_ src: String, _ patterns: [String]) -> Bool { !Self.offenders(patterns, in: [("x.swift", src)]).isEmpty }
        let claudeDir = [#"[/~]\.claude\b"#, #""\.claude\b"#]
        #expect(hits(#"let p = NSHomeDirectory() + "/.claude/settings.json""#, claudeDir))
        #expect(hits(#"let p = "~/.claude/sessions""#, claudeDir))
        #expect(!hits(#"static let claudeBundleID = "com.anthropic.claudefordesktop""#, claudeDir))
        #expect(!hits(#"// 不写 ~/.claude"#, claudeDir), "注释不算")
        #expect(hits(#"let u = URLSession.shared"#, [#"URLSession"#]))
        #expect(hits(#"let f = "abc.sock""#, [#""[^"\n]*\.(key|sock)""#]) && !hits(#"let k = snap.key"#, [#""[^"\n]*\.(key|sock)""#]))
        #expect(hits(#"let p = Process()"#, [#"\bProcess\(\)"#]))
        #expect(hits(#"exit(system("ls"))"#, [#"(?<![.\w])system\("#]) && !hits(#"Text("x").font(.system(size: 12))"#, [#"(?<![.\w])system\("#]))
    }
}
