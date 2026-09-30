import Foundation
import Testing
@testable import BuddyCore

// 模糊测试的公共脚手架（QA：BuddyCore 解析器模糊测试）。
//
// 铁律：只造假数据、只在临时目录里读写；绝不碰 ~/.claude 下的任何东西，绝不打开 *.key / *.sock。
// 所有随机都来自自己实现的 SplitMix64（同一个种子永远得到同一串数，失败可以原样复现）。

/// SplitMix64（自己实现，不用系统随机，也不用被测代码里的同名类型）。
struct FuzzRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 闭区间内的均匀整数。
    mutating func int(_ r: ClosedRange<Int>) -> Int {
        let span = UInt64(r.upperBound - r.lowerBound) &+ 1
        if span == 0 { return Int(truncatingIfNeeded: next()) }
        return r.lowerBound + Int(next() % span)
    }

    mutating func chance(_ p: Double) -> Bool { Double(next() >> 11) / Double(1 << 53) < p }

    mutating func pick<T>(_ a: [T]) -> T { a[int(0...(a.count - 1))] }

    /// n 个随机字节（1 MiB 也很快：一次取 8 个）。
    mutating func bytes(_ n: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(n)
        while out.count < n {
            var v = next()
            for _ in 0..<8 where out.count < n { out.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        }
        return out
    }

    /// n 个随机的可打印 ASCII（不含换行、引号、反斜杠）。
    mutating func ascii(_ n: Int) -> String {
        let table = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-./:")
        return String((0..<n).map { _ in table[int(0...(table.count - 1))] })
    }
}

/// 一个能跨线程传结果的小盒子。
final class FuzzBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _v: T
    init(_ v: T) { _v = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _v }
        set { lock.lock(); _v = newValue; lock.unlock() }
    }
}

/// 在后台线程里收集失败信息（`Issue.record` / `#expect` 在自己开的线程里丢失和测试的关联，所以先收集，回到测试线程再一起报）。
final class FuzzReport: @unchecked Sendable {
    private let lock = NSLock()
    private var msgs: [String] = []
    /// 记一条失败（最多留 25 条，免得一个 bug 刷屏）。
    func fail(_ m: String) { lock.lock(); if msgs.count < 25 { msgs.append(m) }; lock.unlock() }
    func check(_ ok: Bool, _ m: @autoclosure () -> String) { if !ok { fail(m()) } }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return msgs }
    var failed: Bool { !messages.isEmpty }
}

/// 每个用例都带超时：放到一条单独的线程上跑（栈和 GCD 工作线程一样只有 512 KB，所以深递归之类的问题也能暴露），
/// 超时就记一条 Issue（疑似死循环），不让整个测试进程卡死。返回是否按时跑完。
/// 不用 GCD 全局队列：整个测试目标并行跑的时候，utility 队列的线程可能被别的测试占满，小任务也会饿死。
/// 线程里用 `report.fail(…)` 记失败，回到测试线程后统一 `Issue.record`（这样失败会算在当前这个测试头上）。
@discardableResult
func fuzzRun(_ label: String, timeout: TimeInterval = 30, sourceLocation: SourceLocation = #_sourceLocation,
             _ body: @escaping @Sendable (FuzzReport) -> Void) -> Bool {
    let report = FuzzReport()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread { body(report); done.signal() }
    thread.stackSize = 512 * 1024
    thread.qualityOfService = .userInitiated
    thread.start()
    if done.wait(timeout: .now() + timeout) == .timedOut {
        Issue.record("超时（疑似死循环 / 卡死）：\(label)（>\(Int(timeout)) 秒）", sourceLocation: sourceLocation)
        return false
    }
    for m in report.messages { Issue.record("\(label)：\(m)", sourceLocation: sourceLocation) }
    return true
}

/// 不需要收集失败信息的写法。
@discardableResult
func fuzzRun(_ label: String, timeout: TimeInterval = 30, sourceLocation: SourceLocation = #_sourceLocation,
             _ body: @escaping @Sendable () -> Void) -> Bool {
    fuzzRun(label, timeout: timeout, sourceLocation: sourceLocation) { (_: FuzzReport) in body() }
}

/// 临时目录（用完自动删）。只在 `FileIO.temporaryDirectory`（= $TMPDIR）下面建。
final class FuzzDir {
    let path: String
    init(_ tag: String = "fuzz") {
        path = FileIO.temporaryDirectory + "buddy-\(tag)-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    deinit {
        // 测试里可能改过权限（chmod 0）：先恢复再删
        if let e = FileManager.default.enumerator(atPath: path) {
            for case let rel as String in e { chmod(path + "/" + rel, 0o700) }
        }
        chmod(path, 0o700)
        try? FileManager.default.removeItem(atPath: path)
    }
    func file(_ name: String) -> String { path + "/" + name }
    func write(_ name: String, _ data: Data) { FakeClaudeTree.writeInPlace(file(name), data) }
    func write(_ name: String, _ s: String) { write(name, Data(s.utf8)) }
    func read(_ name: String) -> Data? { FileManager.default.contents(atPath: file(name)) }
}

/// 语料：各种"刁钻的字节"。
enum FuzzCorpus {
    /// 非法 UTF-8 的各种形态（每一条都是一小段字节）。
    static let invalidUTF8: [(String, [UInt8])] = [
        ("孤立的续字节 0x80", [0x80]),
        ("孤立的续字节 0xBF", [0xBF]),
        ("连续的续字节", [0x80, 0x80, 0x80, 0x80]),
        ("被截断的 2 字节序列", [0xC3]),
        ("被截断的 3 字节序列（缺 1）", [0xE2, 0x82]),
        ("被截断的 3 字节序列（缺 2）", [0xE2]),
        ("被截断的 4 字节序列（缺 1）", [0xF0, 0x9F, 0x98]),
        ("被截断的 4 字节序列（缺 3）", [0xF0]),
        ("0xFF", [0xFF]),
        ("0xFE", [0xFE]),
        ("0xFF 0xFE（UTF-16 BOM）", [0xFF, 0xFE]),
        ("过长编码 C0 80", [0xC0, 0x80]),
        ("过长编码 C1 BF", [0xC1, 0xBF]),
        ("过长编码 E0 80 80", [0xE0, 0x80, 0x80]),
        ("过长编码 F0 80 80 80", [0xF0, 0x80, 0x80, 0x80]),
        ("代理对的高半 ED A0 80", [0xED, 0xA0, 0x80]),
        ("代理对的低半 ED BF BF", [0xED, 0xBF, 0xBF]),
        ("代理对整对 ED A0 BD ED B8 80", [0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80]),
        ("超出 U+10FFFF：F4 90 80 80", [0xF4, 0x90, 0x80, 0x80]),
        ("F5 起头", [0xF5, 0x80, 0x80, 0x80]),
        ("UTF-8 BOM", [0xEF, 0xBB, 0xBF]),
        ("NUL", [0x00]),
        ("NUL 夹在中间", [0x41, 0x00, 0x42]),
        ("控制字符", [0x01, 0x02, 0x1B, 0x7F]),
    ]

    /// 各种长度的随机字节。
    static let randomLengths = [0, 1, 2, 7, 64, 4096, 1 << 20]

    /// `\uXXXX` 转义的各种坏形态（放在 JSON 字符串里）。
    static let badEscapes: [String] = [
        #"\u"#, #"\u0"#, #"\u00"#, #"\u00e"#, #"é"#, #"\uD83D"#, #"\uDE00"#, #"\uD83D\u"#, #"\uD83D\uDE"#,
        #"\uZZZZ"#, #"\x41"#, #"\"#, #"\q"#,
    ]

    /// 合法的 hook 行（hook.sh 的真实格式：ts / ev / tool / detail / extra）。
    static func hookLine(ts: Int64 = 1_790_654_400_123, ev: String = "PreToolUse", tool: String = "Bash",
                         detail: String = "npm test", extra: String = "") -> String {
        // 键顺序固定成和 hook.sh 一样（ts 在前）：JSONSerialization 的字典顺序不固定，自己拼
        func q(_ s: String) -> String {
            let d = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
            var t = String(decoding: d ?? Data(), as: UTF8.self)
            t.removeFirst(); t.removeLast()
            return t
        }
        return "{\"ts\":\(ts),\"ev\":\(q(ev)),\"tool\":\(q(tool)),\"detail\":\(q(detail)),\"extra\":\(q(extra))}"
    }

    /// 一条合法的 assistant 行（带 usage）。
    static func assistantLine(id: String, at: Date = Harness.epoch, model: String = "claude-opus-5-5",
                              input: Int = 10, output: Int = 20, cacheWrite: Int = 5, cacheRead: Int = 100,
                              stop: String? = "end_turn") -> [String: Any] {
        TL.assistant(sessionId: "s", at: at, messageId: id, block: TL.text("ok"), stopReason: stop, model: model,
                     usage: TL.usage(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead))
    }

    static func jsonLine(_ o: [String: Any]) -> String {
        String(decoding: FakeClaudeTree.jsonLine(o), as: UTF8.self)
    }

    /// 构造 n 层嵌套的数组 / 对象。
    static func deepArray(_ n: Int) -> String { String(repeating: "[", count: n) + String(repeating: "]", count: n) }
    static func deepObject(_ n: Int) -> String {
        String(repeating: "{\"a\":", count: n) + "1" + String(repeating: "}", count: n)
    }
}

/// 用来当"标准答案"的独立实现：按任务书的规则把一段字节切成行。
/// 规则：按 \n 切；最后没有 \n 结尾的半行不算；行内容（不含 \n，含 \r）超过 maxLineBytes 的丢掉；
/// 行尾的一个 \r 去掉；去掉 \r 之后是空的行不算。
func fuzzReferenceLines(_ data: [UInt8], maxLineBytes: Int) -> [[UInt8]] {
    var out: [[UInt8]] = []
    var start = 0
    for (i, b) in data.enumerated() where b == 0x0A {
        var line = Array(data[start..<i])
        start = i + 1
        if line.count > maxLineBytes { continue }
        if line.last == 0x0D { line.removeLast() }
        if line.isEmpty { continue }
        out.append(line)
    }
    return out
}

/// 一次读完一个文件的所有行。
func fuzzReadAll(_ path: String, config: JSONLTailer.Config = .init()) -> (lines: [[UInt8]], tailer: JSONLTailer) {
    let t = JSONLTailer(path: path, config: config)
    var out: [[UInt8]] = []
    t.poll { out.append(Array($0)) }
    return (out, t)
}

/// 随机 JSON 文本生成器（自己拼文本，这样能造出 JSONSerialization 造不出来的东西：超出 Int64 的数、重复键、超长键……）。
enum FuzzJSON {
    /// 各种"边界数字"的文本。
    static let numbers: [String] = [
        "0", "-0", "1", "-1", "2", "42", "-42", "255", "256", "65535", "65536", "2147483647", "2147483648", "-2147483648", "-2147483649",
        "4294967295", "4294967296", "4294967297", "9007199254740992", "9007199254740993", "9223372036854775807", "9223372036854775808",
        "-9223372036854775808", "-9223372036854775809", "18446744073709551615", "18446744073709551616",
        "1.5", "-1.5", "0.1", "1e3", "1E3", "1e30", "1e300", "-1e300", "1e-300", "1.7976931348623157e308", "5e-324",
        "1790654400123", "1790654400123.5", "1790654400123e0", String(repeating: "9", count: 50), "-" + String(repeating: "9", count: 50),
        String(repeating: "1", count: 400),
    ]

    static func string(_ rng: inout FuzzRNG) -> String {
        switch rng.int(0...9) {
        case 0: return "\"\""
        case 1: return "\"" + rng.ascii(rng.int(1...20)) + "\""
        case 2: return "\"中文标题 \\u4e2d\\u6587 😀\""
        case 3: return "\"" + String(repeating: "x", count: rng.int(1...3000)) + "\""
        case 4: return "\"line1\\nline2\\t\\\"q\\\" \\\\ /\""
        case 5: return "\"\\u0000\\u001f\""
        case 6: return "\"" + rng.pick(["interactive", "busy", "waiting", "idle", "claude-desktop", "assistant", "user", "system", "tool_use", "end_turn"]) + "\""
        case 7: return "\"[Request interrupted by user]\""
        case 8: return "\"local_" + rng.ascii(rng.int(1...40)).replacingOccurrences(of: " ", with: "_") + "\""
        default: return "\"" + String(repeating: "é", count: rng.int(1...500)) + "\""
        }
    }

    static func value(_ rng: inout FuzzRNG, depth: Int = 0) -> String {
        switch rng.int(0...(depth >= 3 ? 6 : 9)) {
        case 0: return "null"
        case 1: return "true"
        case 2: return "false"
        case 3, 4: return rng.pick(numbers)
        case 5, 6: return string(&rng)
        case 7: return "[" + (0..<rng.int(0...4)).map { _ in value(&rng, depth: depth + 1) }.joined(separator: ",") + "]"
        default:
            let n = rng.int(0...4)
            return "{" + (0..<n).map { _ in "\"" + rng.ascii(rng.int(1...8)) + "\":" + value(&rng, depth: depth + 1) }.joined(separator: ",") + "}"
        }
    }

    /// 一个对象：`known` 里的键各以 `p` 的概率出现，值是随机类型；再加几个随机键，偶尔重复某个键。
    static func object(_ rng: inout FuzzRNG, known: [String], p: Double = 0.7) -> String {
        var parts: [String] = []
        for k in known where rng.chance(p) { parts.append("\"\(k)\":" + value(&rng)) }
        for _ in 0..<rng.int(0...2) { parts.append("\"" + rng.ascii(rng.int(1...10)) + "\":" + value(&rng)) }
        if !parts.isEmpty && rng.chance(0.15) { parts.append(rng.pick(parts)) }                       // 重复键
        if rng.chance(0.2) { rng.shuffle(&parts) }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

extension FuzzRNG {
    mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(0...i)) }
    }
}
