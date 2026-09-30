import Testing
import Foundation

/// 安全红线的源码审计（数据层 / 画布 / 美术 / 表现层 / 命令行工具）：不联网、不碰钥匙串 / 凭据、不开子进程；
/// 读文件只有 FileIO 一个入口（它拒绝 `*.key` / `*.sock` / 命名管道 / 符号链接绕过），少数写假数据 / 读自己产出的文件的地方要白名单。
/// 谁不小心加了新的读文件 / 联网 / 起进程的写法，这里立刻红，逼着人来看一眼。（应用层有自己的一份：BuddyOfficeTests/SourceAuditTests。）
@Suite struct SourceAuditCoreTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let targets = ["BuddyCore", "PixelKit", "BuddyArt", "BuddyStage", "buddyctl", "buddydump"]

    /// (相对路径, 去掉注释的代码行)。整行 // 注释和行尾 // 注释都去掉（这几个目标里没有字符串里带 // 的、需要保留的情形）。
    static func sources() throws -> [(name: String, lines: [(n: Int, text: String)])] {
        var out: [(String, [(Int, String)])] = []
        for t in targets {
            let dir = root.appendingPathComponent("Sources/\(t)")
            guard let e = FileManager.default.enumerator(atPath: dir.path) else { continue }
            for case let rel as String in e where rel.hasSuffix(".swift") {
                let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { i, l -> (Int, String)? in
                    var s = String(l)
                    if let r = s.range(of: "//") { s = String(s[..<r.lowerBound]) }
                    return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (i + 1, s)
                }
                out.append(("\(t)/\(rel)", lines))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    static func offenders(_ patterns: [String], allow: Set<String> = [], in srcs: [(name: String, lines: [(n: Int, text: String)])]) -> [String] {
        var bad: [String] = []
        for s in srcs where !allow.contains(s.name) {
            for l in s.lines { for p in patterns where l.text.range(of: p, options: .regularExpression) != nil { bad.append("\(s.name):\(l.n) 匹配 \(p)：\(l.text.trimmingCharacters(in: .whitespaces))") } }
        }
        return bad
    }

    @Test func noNetworkNoCredentialsNoSubprocesses() throws {
        let bad = Self.offenders([#"URLSession"#, #"NWConnection"#, #"NWPathMonitor"#, #"CFNetwork"#, #"WKWebView"#, #"import WebKit"#, #"URLRequest"#, #"getaddrinfo"#,
                                  #"[^.\w]socket\("#, #"SecItem"#, #"Keychain"#, #"import Security"#,
                                  #"\bProcess\(\)"#, #"\bNSTask\b"#, #"posix_spawn"#, #"(?<![.\w])system\(\s*""#, #"\bpopen\("#, #"\bfork\("#],
                                 in: try Self.sources())
        #expect(bad.isEmpty, "\(bad)")
    }

    /// 读文件的原语（open / fopen / FileHandle / Data(contentsOf:) / contents(atPath:) / 枚举目录……）：数据层里只有 FileIO 用；
    /// 白名单：FakeTree（往假 home 里写测试数据）、ReplayCommand（同）、Export（GIF 拼帧时读自己刚写出的 PNG）、StageCommands（读自己的金图哈希文件）。
    @Test func fileReadsGoThroughFileIOWithAShortReviewedAllowlist() throws {
        let primitives = [#"FileHandle\("#, #"fopen\("#, #"(?<![.\w])open\("#, #"contentsOfFile"#, #"contents\(atPath"#, #"Data\(contentsOf"#, #"String\(contentsOf"#, #"NSData\(contentsOf"#,
                          #"InputStream\("#, #"opendir\("#, #"readdir\("#, #"FileManager\.default\.(contents|enumerator|subpaths|contentsOfDirectory)"#]
        let allow: Set<String> = ["BuddyCore/Util/FileIO.swift", "BuddyCore/Tools/FakeTree.swift", "BuddyCore/Tools/ReplayCommand.swift",
                                  "PixelKit/Export.swift", "BuddyStage/StageCommands.swift"]
        let bad = Self.offenders(primitives, allow: allow, in: try Self.sources())
        #expect(bad.isEmpty, "在 FileIO 之外直接读文件（要么改走 FileIO，要么确认它碰不到 ~/.claude/sessions 的 *.key，再加进白名单）：\(bad)")
        // 白名单里的文件要真的存在（文件改名 / 删除之后白名单不能悄悄留着）
        let names = Set(try Self.sources().map(\.name))
        for a in allow { #expect(names.contains(a), "白名单里的 \(a) 不存在了") }
    }

    /// 除了 Paths.swift（路径常量）和 FileIO（保险的判断），读数据的代码（BuddyCore + 两个命令行工具）里不出现 `.key` / `.sock` 这样的文件名字面量——
    /// 没有哪段代码「想」去打开它们。（美术里的调色板名字 `ui.key`、`icon.key` 是另一回事，不在这个范围。）
    @Test func noCodeMentionsKeyOrSocketFileNamesExceptTheGuardAndPathConstants() throws {
        let dataSide = try Self.sources().filter { $0.name.hasPrefix("BuddyCore/") || $0.name.hasPrefix("buddyctl/") || $0.name.hasPrefix("buddydump/") }
        let bad = Self.offenders([#""[^"\n]*\.(key|sock)""#, #"cc-socks"#], allow: ["BuddyCore/Util/FileIO.swift", "BuddyCore/Paths.swift"], in: dataSide)
        #expect(bad.isEmpty, "\(bad)")
    }

    /// 审计本身管用：这些写法会被抓到，正常代码不会。
    @Test func theAuditCatchesItsTargetsAndIgnoresLookAlikes() {
        func hits(_ src: String, _ patterns: [String]) -> Bool { !Self.offenders(patterns, in: [("x.swift", [(1, src)])]).isEmpty }
        let net = [#"URLSession"#, #"[^.\w]socket\("#]
        #expect(hits("let s = URLSession.shared", net) && hits("let fd = socket(AF_INET, SOCK_STREAM, 0)", net))
        #expect(!hits("let m = subsocket(1)", net))
        let reads = [#"FileHandle\("#, #"(?<![.\w])open\("#, #"Data\(contentsOf"#]
        #expect(hits("let h = FileHandle(forReadingAtPath: p)", reads) && hits("let fd = open(path, O_RDONLY)", reads) && hits("let d = try Data(contentsOf: url)", reads))
        #expect(!hits("panel.open(x)", reads) && !hits("func isOpen(", reads))
        #expect(hits(#"let p = "1001.abc.key""#, [#""[^"\n]*\.(key|sock)""#]) && !hits("let k = snap.key", [#""[^"\n]*\.(key|sock)""#]))
        #expect(hits(#"exit(system("ls"))"#, [#"(?<![.\w])system\(\s*""#]) && !hits("system(sessionId: id, at: t)", [#"(?<![.\w])system\(\s*""#]))
    }
}
