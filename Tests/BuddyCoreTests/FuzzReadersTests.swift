import Foundation
import Testing
@testable import BuddyCore

// QA 模糊测试 · 目录级读取器：RegistryScanner（原地重写的登记表）/ DesktopMetaReader / SubagentReader。

@Suite struct FuzzReadersTests {

    static func registryText(pid: Int, sid: String, status: String, kind: String = "interactive", extra: String = "") -> String {
        #"{"pid":\#(pid),"sessionId":"\#(sid)","kind":"\#(kind)","status":"\#(status)","name":"n","statusUpdatedAt":1790654400000\#(extra)}"#
    }

    @Test("登记表被原地反复重写（先写一半再写完整 / 写垃圾 / 清空 / 换成非 interactive / 删除再重建）：扫描器总是收敛到“最后一份好的内容”，从不丢会话、不产出垃圾")
    func registryScannerConvergesUnderRandomRewrites() {
        let dir = FuzzDir("reg-converge")
        let path = dir.file("1001.json")
        let finished = fuzzRun("registry converge", timeout: 120) { r in
            var rng = FuzzRNG(seed: 0xEAD_0001)
            let scanner = RegistryScanner(dir: dir.path)
            var expected: (status: String, sid: String)?          // 最后一份好的内容（nil = 没有可用记录）
            var fileExists = false
            /// 扫描直到结果收敛（最多 0.8 秒；写了一半的文件要 50 ms 一次重试）。
            func settle(_ label: String) {
                let deadline = Date().addingTimeInterval(0.8)
                var last: RegistryScanner.ScanResult
                repeat {
                    last = scanner.scan(now: Date())
                    let rec = last.records[1001]
                    if let e = expected {
                        if rec?.status?.rawValue == e.status && rec?.sessionId == e.sid { return }
                    } else if rec == nil { return }
                    Thread.sleep(forTimeInterval: 0.02)
                } while Date() < deadline
                let rec = last.records[1001]
                r.fail("\(label)：没有收敛：应为 \(String(describing: expected))，实际 \(String(describing: rec?.status)) \(String(describing: rec?.sessionId))（文件存在=\(fileExists)）")
            }
            for round in 0..<60 {
                let sid = "sid-\(round % 5)"
                let status = rng.pick(["busy", "idle", "waiting"])
                let good = FuzzReadersTests.registryText(pid: 1001, sid: sid, status: status)
                switch rng.int(0...6) {
                case 0, 1:      // 先写一半，扫一次，再写完整
                    FakeClaudeTree.writeInPlace(path, Data(good.utf8.prefix(rng.int(1...(good.utf8.count - 1)))))
                    fileExists = true
                    _ = scanner.scan(now: Date())
                    FakeClaudeTree.writeInPlace(path, Data(good.utf8)); expected = (status, sid)
                case 2:         // 写垃圾：保留上一份好的
                    FakeClaudeTree.writeInPlace(path, Data(rng.bytes(rng.int(0...200)))); fileExists = true
                case 3:         // 清空（O_TRUNC 之后、写之前的那一瞬间）
                    FakeClaudeTree.writeInPlace(path, Data()); fileExists = true
                case 4:         // 换成非 interactive：不显示
                    FakeClaudeTree.writeInPlace(path, Data(FuzzReadersTests.registryText(pid: 1001, sid: sid, status: status, kind: "background").utf8)); fileExists = true; expected = nil
                case 5:         // 删除再重建
                    try? FileManager.default.removeItem(atPath: path); fileExists = false; expected = nil
                    settle("删除 #\(round)")
                    let res = scanner.scan(now: Date())
                    r.check(res.records[1001] == nil, "删除之后不该还有记录")
                    FakeClaudeTree.writeInPlace(path, Data(good.utf8)); fileExists = true; expected = (status, sid)
                default:        // 正常更新
                    FakeClaudeTree.writeInPlace(path, Data(good.utf8)); fileExists = true; expected = (status, sid)
                }
                settle("第 \(round) 轮")
                if r.failed { return }
            }
        }
        #expect(finished)
    }

    @Test("桌面元数据目录里各种脏东西（目录 / FIFO / 符号链接 / 垃圾 JSON / 超过 4 MiB / 名字古怪 / 文件在读的时候被删）：refresh 不崩溃、不卡死、结果只含合法条目，重复刷新没有抖动")
    func desktopMetaRefreshOnJunkTree() {
        let dir = FuzzDir("meta-junk")
        let finished = fuzzRun("desktop meta refresh", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xEAD_0002)
            let org = dir.file("acct/org")
            try? FileManager.default.createDirectory(atPath: org, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: dir.file("acct2/org2"), withIntermediateDirectories: true)
            for i in 0..<6 {
                FakeClaudeTree.writeInPlace(org + "/local_ok\(i).json", Data("{\"sessionId\":\"local_ok\(i)\",\"cliSessionId\":\"cli-\(i)\",\"priorCliSessionIds\":[\"prior-\(i)\"],\"title\":\"t\(i)\",\"lastActivityAt\":1790654400000}".utf8))
            }
            FakeClaudeTree.writeInPlace(org + "/local_junk.json", Data(rng.bytes(500)))
            FakeClaudeTree.writeInPlace(org + "/local_empty.json", Data())
            FakeClaudeTree.writeInPlace(org + "/local_big.json", Data(repeating: 0x20, count: (4 << 20) + 10))                   // 超过 4 MiB：不读
            FakeClaudeTree.writeInPlace(org + "/local_deep.json", Data("{\"sessionId\":\"local_deep\",\"x\":\(FuzzCorpus.deepObject(600))}".utf8))
            FakeClaudeTree.writeInPlace(org + "/notlocal.json", Data("{\"sessionId\":\"local_notlocal\"}".utf8))                  // 不以 local_ 开头：不认
            FakeClaudeTree.writeInPlace(org + "/local_x.json.bak", Data("{\"sessionId\":\"local_bak\"}".utf8))                   // 不以 .json 结尾：不认
            FakeClaudeTree.writeInPlace(org + "/local_带 空格\n名字.json", Data("{\"cliSessionId\":\"cli-weird\"}".utf8))          // sessionId 缺失：用文件名当 host
            try? FileManager.default.createDirectory(atPath: org + "/local_dir.json", withIntermediateDirectories: true)
            r.check(mkfifo(org + "/local_fifo.json", 0o600) == 0, "mkfifo")
            symlink(org + "/local_ok0.json", org + "/local_link.json")
            symlink(dir.path + "/nonexistent", org + "/local_dangling.json")
            FakeClaudeTree.writeInPlace(dir.file("acct/stray-file.json"), Data("{}".utf8))                                        // org 层放了个文件
            let reader = DesktopMetaReader(rootDir: dir.path)
            let first = reader.refresh()
            r.check(reader.directoryReadable, "目录应当可读")
            let hosts = Set(reader.all.map { $0.hostSessionId })
            r.check((0..<6).allSatisfy { hosts.contains("local_ok\($0)") }, "合法条目应该都在：\(hosts)")
            r.check(!hosts.contains("local_junk") && !hosts.contains("local_deep") && !hosts.contains("local_big") && !hosts.contains("local_bak") && !hosts.contains("local_notlocal"), "读到了不该有的：\(hosts)")
            r.check(reader.find(cliSessionId: "cli-3")?.hostSessionId == "local_ok3" && reader.find(cliSessionId: "prior-2")?.hostSessionId == "local_ok2", "按 cliSessionId 反查")
            r.check(reader.find(cliSessionId: "nope") == nil, "不存在的 id")
            r.check(!first.isEmpty, "第一次应当报告变化")
            for i in 0..<5 { r.check(reader.refresh().isEmpty, "第 \(i) 次重复刷新不该有变化（抖动）") }
            // 文件被改 / 被删
            FakeClaudeTree.writeInPlace(org + "/local_ok1.json", Data("{\"sessionId\":\"local_ok1\",\"cliSessionId\":\"cli-1b\",\"title\":\"changed\"}".utf8))
            r.check(reader.refresh() == ["local_ok1"], "改了一个文件应当只报告它")
            r.check(reader.meta(host: "local_ok1")?.title == "changed" && reader.find(cliSessionId: "cli-1b") != nil && reader.find(cliSessionId: "cli-1") == nil, "改动没生效")
            try? FileManager.default.removeItem(atPath: org + "/local_ok2.json")
            r.check(reader.refresh() == ["local_ok2"] && reader.meta(host: "local_ok2") == nil && reader.find(cliSessionId: "prior-2") == nil, "删掉一个文件应当只报告它，并且从反查里去掉")
            // 根目录整个不存在：不可读，保留上次的（不把所有人都判成消失）
            let gone = DesktopMetaReader(rootDir: dir.file("nonexistent"))
            _ = gone.refresh()
            r.check(!gone.directoryReadable && gone.all.isEmpty, "不存在的根目录")
            // 随机来回折腾
            for _ in 0..<100 {
                let name = org + "/local_ok\(rng.int(0...5)).json"
                switch rng.int(0...3) {
                case 0: FakeClaudeTree.writeInPlace(name, Data(rng.bytes(rng.int(0...100))))
                case 1: try? FileManager.default.removeItem(atPath: name)
                case 2: FakeClaudeTree.writeInPlace(name, Data("{\"sessionId\":\"local_ok\(rng.int(0...5))\",\"title\":\"x\"}".utf8))
                default: _ = reader.refresh()
                }
                _ = reader.refresh()
                r.check(reader.all.allSatisfy { !$0.hostSessionId.isEmpty && $0.hostSessionId.utf8.count <= 200 }, "条目不合法")
            }
        }
        #expect(finished)
    }

    @Test("子代理目录里各种脏东西（垃圾 meta / 垃圾记录 / 目录 / FIFO / 符号链接 / 名字古怪 / 文件在读的时候增长和被删）：poll 不崩溃、不卡死，只报告目录里真有的文件")
    func subagentReaderOnJunkDirectory() {
        let dir = FuzzDir("sub-junk")
        let finished = fuzzRun("subagent reader", timeout: 60) { r in
            var rng = FuzzRNG(seed: 0xEAD_0003)
            let sub = dir.file("sess/subagents")
            let wf = sub + "/workflows/wf_1"
            try? FileManager.default.createDirectory(atPath: wf, withIntermediateDirectories: true)
            let now = Date()
            func line(_ id: String, stop: String) -> Data { FakeClaudeTree.jsonLine(FuzzCorpus.assistantLine(id: id, at: now, stop: stop)) }
            FakeClaudeTree.writeInPlace(sub + "/agent-aaa.jsonl", line("a1", stop: "tool_use"))
            FakeClaudeTree.writeInPlace(sub + "/agent-aaa.meta.json", Data(#"{"agentType":"general","description":"desc","requestShape":"background","spawnDepth":1}"#.utf8))
            FakeClaudeTree.writeInPlace(sub + "/agent-bbb.jsonl", Data(rng.bytes(300)))
            FakeClaudeTree.writeInPlace(sub + "/agent-bbb.meta.json", Data(rng.bytes(300)))
            FakeClaudeTree.writeInPlace(sub + "/agent-ccc.jsonl", line("c1", stop: "end_turn"))
            FakeClaudeTree.writeInPlace(sub + "/agent-ccc.meta.json", Data(FuzzJSON.object(&rng, known: ["agentType", "description", "toolUseId", "spawnDepth", "requestShape"], p: 1).utf8))
            FakeClaudeTree.writeInPlace(sub + "/agent-.jsonl", line("e1", stop: "end_turn"))
            FakeClaudeTree.writeInPlace(sub + "/agent-带 空格\n.jsonl", line("w1", stop: "end_turn"))
            FakeClaudeTree.writeInPlace(sub + "/agent-x.txt", line("t1", stop: "end_turn"))                               // 不是 .jsonl
            FakeClaudeTree.writeInPlace(sub + "/journal.jsonl", line("j1", stop: "end_turn"))                             // 不以 agent- 开头
            try? FileManager.default.createDirectory(atPath: sub + "/agent-dir.jsonl", withIntermediateDirectories: true)
            r.check(mkfifo(sub + "/agent-fifo.jsonl", 0o600) == 0, "mkfifo")
            symlink(sub + "/agent-aaa.jsonl", sub + "/agent-link.jsonl")
            symlink(dir.path + "/nonexistent", sub + "/agent-dangling.jsonl")
            FakeClaudeTree.writeInPlace(wf + "/agent-wfa.jsonl", line("w2", stop: "tool_use"))
            FakeClaudeTree.writeInPlace(wf + "/journal.jsonl", line("j2", stop: "end_turn"))
            let reader = SubagentReader(sessionDir: dir.file("sess"))
            var t = now
            for i in 0..<40 {
                if rng.chance(0.4) { FakeClaudeTree.appendBytes(sub + "/agent-aaa.jsonl", rng.chance(0.5) ? line("a\(i)", stop: rng.pick(["tool_use", "end_turn"])) : Data(FuzzTailerTests.messy(&rng, length: rng.int(1...80)))) }
                if rng.chance(0.1) { try? FileManager.default.removeItem(atPath: sub + "/agent-ccc.jsonl") }
                if rng.chance(0.1) { Darwin.truncate(sub + "/agent-aaa.jsonl", off_t(rng.int(0...50))) }
                if rng.chance(0.1) { FakeClaudeTree.writeInPlace(sub + "/agent-new\(i).jsonl", line("n\(i)", stop: "tool_use")) }
                t = t.addingTimeInterval(Double(rng.int(0...100)) / 10)
                reader.poll(now: t, list: rng.chance(0.6))
                for p in reader.jsonlPaths {
                    r.check(p.hasPrefix(sub) && (p as NSString).lastPathComponent.hasPrefix("agent-") && p.hasSuffix(".jsonl"), "报告了不该有的路径：\(p)")
                }
                for sn in reader.snapshots(now: t) { r.check(sn.id.hasPrefix("agent-") && sn.description.count <= 2048, "快照 id / 描述：\(sn.id)") }
                _ = reader.hasActive(now: t); _ = reader.hasActiveBackground(now: t); _ = reader.recentToolUses
            }
            let paths = reader.jsonlPaths.map { ($0 as NSString).lastPathComponent }
            r.check(paths.contains("agent-aaa.jsonl") && paths.contains("agent-wfa.jsonl"), "应该发现正常的子代理文件：\(paths)")
            r.check(!paths.contains("journal.jsonl") && !paths.contains("agent-x.txt"), "不该报告 journal / .txt")
            r.check(SubagentReader.listJSONL(sessionDir: dir.file("sess")).allSatisfy { ($0 as NSString).lastPathComponent.hasPrefix("agent-") }, "listJSONL")
        }
        #expect(finished)
    }
}
