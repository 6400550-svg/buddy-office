import Foundation

/// 外部 JSON（会话记录行、hook 行、登记表、桌面元数据、账本……）的统一解析入口。
///
/// 为什么要单独包一层：`JSONSerialization` 是递归下降解析，每一层对象嵌套要吃约 1 KB 栈。
/// 数据层跑在 GCD 工作线程上（栈只有 512 KB），实测嵌套 ≥ 约 470 层的对象会直接爆栈（SIGBUS，整个 App 崩掉）；
/// 到 512 层它自己的深度上限才会报错。真实数据嵌套不会超过十几层，所以解析前先用一遍 O(n) 的扫描数嵌套深度，
/// 超过 `maxDepth` 的一律当作坏数据（返回 nil），根本不交给 JSONSerialization。
enum SafeJSON {
    /// 允许的最大嵌套深度（`{` / `[` 的层数）。
    static let maxDepth = 100

    /// 字节流里 `{` / `[` 的嵌套有没有超过 `maxDepth`（字符串里的括号不算；对 UTF-16 / UTF-32 编码同样有效，NUL 字节被忽略）。
    static func isShallowEnough(_ bytes: UnsafeRawBufferPointer, maxDepth: Int = SafeJSON.maxDepth) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for b in bytes {
            if inString {
                if escaped { escaped = false } else if b == 0x5C { escaped = true } else if b == 0x22 { inString = false }
                continue
            }
            switch b {
            case 0x22: inString = true
            case 0x7B, 0x5B:
                depth += 1
                if depth > maxDepth { return false }
            case 0x7D, 0x5D:
                if depth > 0 { depth -= 1 }
            default: break
            }
        }
        return true
    }

    /// 字符串字段的长度上限（外部文件里的字符串可以有几 MB 长：不设上限，标题 / 路径 / 名字这类会被复制进每一份快照、
    /// 写进 identities.json，内存和磁盘都会被撑大）。`clip` 按 Unicode 标量截断。
    static let maxIdLength = 200
    static let maxLabelLength = 2048
    static let maxDetailLength = 4096

    static func clip(_ s: String, max n: Int) -> String {
        if s.utf8.count <= n { return s }
        return String(String.UnicodeScalarView(s.unicodeScalars.prefix(n)))
    }

    /// `v` 是字符串就截到 n 个标量以内，不是字符串返回 nil。
    static func string(_ v: Any?, max n: Int = SafeJSON.maxLabelLength) -> String? {
        (v as? String).map { clip($0, max: n) }
    }

    /// id 类字段（会话 id / 消息 id / uuid）：太长就当没有——不能截断，截断之后不同的 id 可能变成相等，去重、配对全会错。
    static func id(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty, s.utf8.count <= maxIdLength else { return nil }
        return s
    }

    /// 解析成字典；不是合法 JSON / 不是对象 / 嵌套太深都返回 nil。
    static func object(_ data: Data) -> [String: Any]? {
        guard data.withUnsafeBytes({ isShallowEnough($0) }) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func object(_ bytes: UnsafeBufferPointer<UInt8>) -> [String: Any]? {
        guard isShallowEnough(UnsafeRawBufferPointer(bytes)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(buffer: bytes))) as? [String: Any]
    }
}
