import Foundation
import Testing
@testable import BuddyCore

// QA · FileWatcher（FSEvents）的生命周期和路径处理。只在临时目录里造文件。

@Suite(.serialized) struct FuzzWatcherTests {

    @Test("审查确认：FileWatcher 停掉并释放的时候队列里还排着 FSEvents 的回调块，回调不会去碰已经释放的对象（配合 MallocScribble 跑过）")
    func stopWhileCallbacksAreQueuedDoesNotTouchFreedMemory() {
        let dir = FuzzDir("fw-lifecycle")
        let root = FileWatcher.resolved(dir.path)
        let delivered = FuzzBox(0)
        for iter in 0..<20 {
            let q = DispatchQueue(label: "fw-\(iter)")
            let gate = DispatchSemaphore(value: 0)
            q.async { gate.wait() }                                   // 先把队列堵住：事件只能排队
            var w: FileWatcher? = FileWatcher(roots: [root], queue: q, latency: 0) { _ in delivered.value += 1 }
            guard w?.start() == true else { gate.signal(); print("FSEvents 不可用（沙箱？），跳过监听断言"); return }   // FSEvents 起不来（沙箱里会这样）：没法测；打印一句，完整回归会数这句话（应为 0）
            for j in 0..<8 { dir.write("f\(j).txt", "round \(iter)") }
            Thread.sleep(forTimeInterval: 0.08)                       // 让 fseventsd 把事件投递进（被堵住的）队列
            w?.stop()
            w = nil                                                   // 对象在这里释放；排队的回调块还没跑
            gate.signal()                                             // 放行：排队的回调块现在才执行
            q.sync {}
        }
        // 能走到这里没有崩溃就算通过；顺带确认正常使用时事件确实能送到
        let q = DispatchQueue(label: "fw-normal")
        let got = FuzzBox<[String]>([])
        let w = FileWatcher(roots: [root], queue: q, latency: 0.01) { paths in got.value += paths }
        guard w.start() else { return }
        dir.write("hello.txt", "x")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !got.value.contains(where: { $0.hasSuffix("hello.txt") }) { Thread.sleep(forTimeInterval: 0.02) }
        w.stop()
        #expect(got.value.contains { $0.hasSuffix("hello.txt") })
    }

    @Test("文件名里有空格 / 中文 / emoji / 换行 / 很长：FSEvents 回调照常送出原样的路径，不崩溃")
    func weirdFileNamesArriveIntact() {
        let dir = FuzzDir("fw-names")
        let root = FileWatcher.resolved(dir.path)
        let q = DispatchQueue(label: "fw-names")
        let got = FuzzBox<[String]>([])
        let w = FileWatcher(roots: [root], queue: q, latency: 0.01) { paths in got.value += paths }
        guard w.start() else { print("FSEvents 不可用（沙箱？），跳过监听断言"); return }        // FSEvents 起不来（沙箱里会这样）：没法测；打印一句，完整回归会数这句话（应为 0）
        defer { w.stop() }
        let names = ["带 空格.json", "中文名字.jsonl", "emoji😀.txt", "new\nline.txt", "quote\".txt", String(repeating: "长", count: 80) + ".txt", "a b  c.key"]
        for n in names { dir.write(n, "x") }
        let deadline = Date().addingTimeInterval(8)
        func missing() -> [String] { names.filter { n in !got.value.contains { $0.hasSuffix("/" + n) } } }
        while Date() < deadline, !missing().isEmpty { Thread.sleep(forTimeInterval: 0.05) }
        #expect(missing().isEmpty, "没有收到这些文件的事件：\(missing())")
    }

    @Test("C-022 FileWatcher.resolved：空串 / 根 / 一堆斜杠 / `..` / 超长 / 含 NUL / 几千层不存在的深路径：不崩溃（递归会压爆 512 KB 的栈）、结果稳定")
    func c022_resolvedHandlesEveryKindOfPath() {
        let dir = FuzzDir("fw-resolved")
        try? FileManager.default.createDirectory(atPath: dir.file("a/b"), withIntermediateDirectories: true)
        symlink(dir.file("a"), dir.file("link"))
        let deep = (0..<3000).map { _ in "d" }.joined(separator: "/")
        let paths = ["", "/", "//", "///a//b//", ".", "..", "../..", "a/b/c", dir.path + "/link/b", dir.path + "/nonexistent/x/y/z",
                     dir.path + "/a/../a/b", "/" + deep, deep, String(repeating: "x", count: 5000), "/tmp/\u{0}/x", "/tmp/é/😀"]
        let finished = fuzzRun("FileWatcher.resolved", timeout: 30) { r in
            for p in paths {
                let a = FileWatcher.resolved(p)
                let b = FileWatcher.resolved(a)
                r.check(a == b, "resolved 不是幂等的：\(p.prefix(40).debugDescription) → \(a.prefix(40).debugDescription) → \(b.prefix(40).debugDescription)")
            }
        }
        #expect(finished)
        // 符号链接被解析成真实路径
        #expect(FileWatcher.resolved(dir.path + "/link/b") == FileWatcher.resolved(dir.path + "/a/b"))
    }
}
