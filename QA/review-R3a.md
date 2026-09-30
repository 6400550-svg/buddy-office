# R3a 终审复查（数据层 + 状态机 + 脚本）

2026-09-29 11:53–12:30（墙钟约 37 分钟）。范围：`Sources/BuddyCore/**`、`scripts/hook-merge.py`、`scripts/build-app.sh`、`安装.command`、`卸载.command`、`scripts/measure.sh` / `soak.sh`。
所有编译 / 测试 / 探针都在拷贝 `…/scratchpad/r3a/`（`BUDDY_SCRATCH=.build-r3a`）里做，探针文件 `Tests/BuddyCoreTests/R3aProbeTests.swift` **只在拷贝里**，主目录除本报告外没有改动。没有碰 `~/.claude`（真实数据只用 `buddyctl dump --once --json`（只取阶段 / 动作 / 计数等字段，不取标题）和 `dump --audit-opens 3 --poll` 只读地看了一遍）、没有连 socket、没有打开过 `.key`、没有动运行中的 App。

## 结论

**新发现：P0 0 条 / P1 0 条 / P2 2 条 / P3 8 条。** 两条 P2 都有可复现的失败输出（见下）。上一轮修复引入的回归（R1a-01 的 quiet 唤醒、hook-merge 的符号链接 / 私有创建 / 备份、build-app.sh 的 pipefail、安装.command 的移开 + 回滚、OpenAudit scope、`--audit-opens`、JumpService 的 DesktopMeta 走 FileIO）逐项复查过，**没有发现回归**。

## P2

### P2-1 [测试基础设施] 红线测试 `fuzz_registryScannerWithDecoyFiles` 在默认并行的 `swift test` 里间歇性变红（8 次里 2 次），SAN-02 只修了 OpenAudit，同一类问题在它的兄弟测试里还在

- **位置**：`Tests/BuddyCoreTests/FuzzSecurityTests.swift:62`、`:106`（安装进程全局的 `FileIO.openObserver`，没有按路径过滤）、`:128`（`names.allSatisfy { Paths.isRegistryFileName($0) }`）；根因是 `Sources/BuddyCore/Util/FileIO.swift:28/77` 的观察口是进程全局的。SAN-02（`OpenAudit(scope:)`）只把 OpenAudit 自己的几条测试限定了范围，这几条没动。
- **证据 1（真实失败输出）**：在拷贝里 `scripts/dev.sh test --filter "BuddyCoreTests|BuddyOfficeTests" --skip R3aProbe` 连跑 8 次（每次 608 个测试、67 个套件），**第 1 次和第 7 次失败**，都是同一条：
  ```
  ✘ Test "登记表目录里一堆诱饵（…）：只读合法的 <pid>.json，绝不打开 .key，记录不含任何诱饵的内容" recorded an issue at FuzzSecurityTests.swift:128:9: Expectation failed: names.allSatisfy { Paths.isRegistryFileName($0) }
  ↳ 被 open 的文件名里有不匹配 ^\d+\.json$ 的：["agent-aafga30000000000.jsonl"]          （第 1 次）
  ↳ 被 open 的文件名里有不匹配 ^\d+\.json$ 的：["5e1a0000-0000-4000-8000-000000000001.events.jsonl"]   （第 7 次）
  ```
  被观察到的是**别的并行套件**（子代理 / hook 相关的引擎测试）在它们自己临时目录里的 open。原始日志：`…/scratchpad/r3a-full-1.log`、`r3a-full-7.log`。
- **证据 2（确定性复现）**：探针 `probe R`（拷贝里的 `R3aProbeTests.swift`）在同一进程里开一个线程反复 `FileIO.open` 一个无关的 `neighbour.events.jsonl`，再调用同一个测试函数 → 立即失败：`被 open 的文件名里有不匹配…：["neighbour.events.jsonl", "local_22222222-….json"…]`（连我同时并行跑的别的探针的元数据文件也被记了进来）。`swift test --filter "R3aProbeDormantTests|probeR_noisyNeighbour"`。
- **为什么算 P2**：这条测试是「绝不打开 `.key` / 非 `<pid>.json`」红线的直接证据之一；报告里「789 个测试全部通过」「连跑 20 次失败 0」不能在默认并行方式下复现。它只会误报红（不会误报绿），但会让人对红线测试失去信任、或者习惯性地重跑。QA 之前的 20 次连跑只跑了「会抢全局计数器的那一组」，没有和其余套件并行，所以没暴露。
- **同类隐患（没看到失败，但断言对陌生路径敏感）**：`FuzzSecurityTests.swift:75-78` 的 `bad` 过滤器把路径里含 `link` / `1002.json` / `1003.json` / `rel-key` 的都算违规，而 `EngineScenarioTests` / `StateRuleTests` 会用 pid 1002 建登记表；`FuzzRegressionTests.swift:784` 的 `hasSuffix("agent-abc.meta.json")` 计数同理。
- **建议修法**：这些测试装观察口时按自己临时目录前缀过滤（和 `OpenAudit.install(scope:)` 一样：`FileIO.openObserver = { p in if p.hasPrefix(dir.path) { observed.value.append(p) } }`）；或者给 `FileIO` 加 `observeOpens(prefix:)`，让全局观察口本身就带范围。

### P2-2 桌面会话元数据里的**未来时间戳**没有像其他数据源那样夹紧：一个 `lastFocusedAt` 就让「未读」永远不亮，一个 `lastActivityAt` 就让「下班工位」的幽灵座位占位、超过 12 小时也不走

- **位置**：`Sources/BuddyCore/Fusion/SessionEngine.swift:844`（`f > e → unread = false`）、`:328` / `:341-358`（下班工位的选取 / 到期都用 `meta.lastActivityAt`）；`DesktopMetaReader.parse`（`Ingest/DesktopMetaReader.swift:185-187`）只做了「2000–2200 年」的范围检查，没有和「现在」比。hook（`SessionEngine.swift:509-513`）、会话记录（`TranscriptReader.futureSlack`）、identities.json（`IdentityResolver.load`）都把「比现在晚一天以上」的时间戳夹回现在（C-006 / C-026，当时定为 P1）；桌面元数据这一条漏了。
- **证据（拷贝里的探针，假时钟）**：
  - `probe U`（`swift test --filter R3aProbeUnreadTests`）：同一条时间线（一轮做完、Stop + 登记表 idle），元数据 `lastFocusedAt` = 一小时前 → `unread=true`；`lastFocusedAt` = 30 天后 → **`unread=false`**（`PROBE-U future=true unread=Optional(false)`）。
  - `probe I`（`--filter R3aProbeDormantTests`）：5 个下班工位候选，一个 `lastActivityAt` = 30 天后、其余是 0–40 分钟前 → 最多 4 个，那个未来的排第一占位、最老的真候选被挤掉；**推进 13 小时后别的都按 12 小时到期移走了，它还在**（`after 13h dormants=["000"]`）。
- **可达性**：需要 Claude 桌面 App 写出一个未来的时间（它自己的时钟被拨快过 / 虚拟机恢复后时钟不对），不是正常使用会遇到的；所以只定 P2，不定 P1。
- **建议修法**：在引擎读到 `meta` 的地方（`update` / `bootstrapDormants` / `maintainAway`）把 `lastActivityAt` / `lastFocusedAt` / `createdAt` 夹到 `now + 86400` 以内（和 hook 一致），或在 `DesktopMetaReader.refresh` 里传入时钟统一夹。

## P3（一句话）

1. **hook-merge.py 会把 `1e400` 这类溢出成无穷大的数字写成 `Infinity`（不是合法 JSON），而且「读回校验」发现不了**（`inf == inf`）：`printf '{"a": 1e400}' > s.json; hook-merge.py install --settings s.json` → 输出 `"a": Infinity`（`scripts/hook-merge.py:123-130`，`node` 的 `JSON.parse` 会拒绝）。真实 settings.json 里不会有这种数；修法是 `json.dump(..., allow_nan=False)` 并把 `ValueError` 转成 `Refuse`。
2. hook-merge.py 遇到孤立代理项字符（`"\ud800"`）时 `UnicodeEncodeError` 直接抛栈追踪、退出码 1（原文件没动、临时文件清掉了，但备份留下）；目标目录只读时同样留一份备份。都不损坏数据。
3. `SessionEngine.processInbox`（`SessionEngine.swift:553/589`）用 `inbox.removeFirst()` 逐个出队：一次 poll 里积压 2 万条 hook 事件时是 O(n²)，实测 **2 000 条 19 ms、20 000 条 1.09 s、20 万条（被截成最新 2 万）2.59 s**（`probe D`）；真实使用里积压最多一两千条，只在 App 被挂起很久后的第一次 poll 可能卡 1 秒。
4. `SubagentReader.helpers` / `order` 在会话存续期间只增不减（每个子代理文件一个 `TranscriptReader`）；工作流派几百个小助手的会话里，每次列目录都要对所有没结束的小助手 stat 一遍。没测到实际数字。
5. `Sources/BuddyCore/Util/Info.swift` 的 `BuddyCoreInfo.version = "0.1.0"` 没有任何人引用，注释还说「build-app.sh 也从这里读」（实际读 `VERSION` = 1.0.1）：过期的死代码 + 误导性注释。
6. `buddyctl dump` 的文档头说「只打印元数据…绝不打印对话内容」，但表里「细节」列会打印工具的 detail（Bash 命令 / 路径 / URL / 搜索词），还有一行「桌面总结：…」（`DumpCommand.swift:176-180`，模型生成的英文总结）；`--json` 里有 `title` 和 `activityDetail`。QA 证据目录里没有这类内容（我 grep 过），只是文档说得比行为宽。
7. `dump --audit-opens` 文档说「只读地」，但和 `--persist` 一起给时（`DumpCommand.swift:44/69`）会读写真实的 identities.json / ledger.json（和运行中的 App 抢同一份文件）。
8. Core 的 `SessionEngine.Options.dormantMax` 为负数时 `prefix(-1)` / `dropFirst(-1)` 会 trap（`SessionEngine.swift:331/347`）：A-004 只在 App 层夹了（`EngineConfig.values`），Core 公开接口本身没夹。App 里不可达。
（另：第 7 次完整并行回归里 `SpecTraceCoreTests.swift:389-390`「4.3-42 QoS」测试在机器被别人编译占满时（那一遍 185 秒）等满 90 秒超时后误报红，属于 R1a-03 那一类「机器满载误报」，没有单独当问题。安装.command 失败时会留下隐藏的 `.Buddy 办公室.new.app` 暂存目录，下次运行会清掉。）

## 检查过什么（覆盖清单）

**读过的文件**：`QA/ISSUES.md` 汇总表、`QA/REPORT.md` 全文（重点第 2、7、8 节）、任务书第 5 节；`Sources/BuddyCore/` 下：`Fusion/SessionEngine.swift`（全文）、`SessionStore.swift`、`ActivityResolver.swift`、`ToolTracker.swift`、`HelperAttributor.swift`、`BuddyState.swift`、`IdentityResolver.swift`、`ToolCatalog.swift`；`Ingest/RegistryScanner`、`JSONLTailer`、`HookLogReader`、`TokenLedger`、`FileWatcher`、`DesktopMetaReader`、`TranscriptReader`、`TranscriptLine`（解析部分）、`LineSanitizer`、`SubagentReader`、`ProcessProbe`；`Util/FileIO`、`SafeJSON`、`TimeUtil`、`Paths.swift`、`Info.swift`；`Model/Activity`、`BuddySnapshot`；`Tools/DumpCommand`、`OpenAudit`、`ReplayCommand`（参数与安全部分）、`FakeTree`（接口）；App 层的 `JumpService`（DesktopMeta 一段）、`EngineConfig`；`scripts/` 全部（hook-merge.py、build-app.sh、dev-app.sh、measure.sh、soak.sh、make-showcase.sh、winlist.swift）、`安装.command`、`卸载.command`、`Package.swift`；测试侧：`ReviewRegressionTests`（R1a-01）、`OpenAuditTests`、`FuzzSecurityTests`、`RegistryTests`（FileAccessTests）、`FuzzRegressionTests`（C-014 / C-021）、`SourceAuditCoreTests`、`Tests/hook_merge_test.py`；`QA/tools/soak_watch.py` 的 lsof 检测部分。

**跑过的探针 / 测试（都在拷贝里）**：
- `BuddyCoreTests` 基线：415 个全过（108 秒）。`Tests/hook_merge_test.py`：16 个 OK。
- **probe A**（假时钟随机合法时间线：40 个种子 × 400 步，登记表 / hook / 会话记录 / 打断 / api_error / 压缩边界 / 子代理 / 元数据 / 进程死活 / 时间跳 0 s–25 h）：`nextWake` 在过去的次数 **0**（R1a-01 的不变量在随机数据上成立；`nextWake` 最大 1.0 s，因为只要有登记记录，进程存活检查就每秒登记一次唤醒）。
- **probe C**（真实 `SessionStore` + FSEvents，快进 15 分钟让 busy 会话变 quiet）：3 秒内 engine 被 poll 约 4 次（`now()` 调用 12 次）；纯轮询模式 174 次（50 ms 间隔，预期内）。没有空转。
- **probe B**（`SessionStore` 启停 40 次 × 2 种模式，同时有线程疯狂写 hook / 会话记录 / 登记表，账本开启）：`stop()` 最长 5 ms，没崩没卡。
- **probe D**（hook 积压 2k / 20k / 200k 行一次 poll）：见 P3-3。
- **probe E**（登记表 / hook / 会话记录 / 桌面元数据 / 子代理目录里放 FIFO、目录、自指符号链接、指向 /dev/zero、权限 000 的文件）：引擎 20 次 poll 不卡、合法会话仍正常。
- **probe F**（5 个会话随机来去 / 归档 / 元数据删改 / 时间跳到 13 小时，25 个种子 × 300 步 × persist 开关）：座位不重复、没有负座位、`turnStartedAt` 与阶段一致、quiet 只在 busy、离场者必为 idle、busy 时不 unread——**0 违反**。
- **probe R / I / U**：见两条 P2。
- **完整并行回归 × 8**（`BuddyCoreTests|BuddyOfficeTests`，608 个测试）：6 次全过，2 次失败（P2-1；其中一次另有机器满载引起的 QoS 测试超时）。另把「会抢全局计数器的组合」（FileAccessTests / DesktopMetaFileIOTests / ReplayTests / OpenAudit…，23 个测试）单独连跑 8 次：8/8 过——说明只有和其余套件并行时才会碰上。
- **脚本**：hook-merge.py 在临时目录里试了符号链接（指向 dotfiles 目录、链式链接、只读目录里的链接、悬空链接）、umask 000 / 077 下的临时文件与备份权限（都是原文件权限，见 `ls -la`）、同一秒内多次备份（`-1` `-2` 后缀）、`1e400`、孤立代理项；`build-app.sh` 用假 `swift`（退出码 1：脚本失败、没有产物、也没有拿旧二进制打包；退出码 0 且**没有 dist 目录**：图标 → 组装 → 签名全流程通过）；`安装.command`（改一份 LSREG 指向不存在路径的拷贝，假 HOME + 假 pgrep / pkill / osascript / open）首次安装、覆盖旧版本（`.old.app` / `.new.app` 都清掉）、强制 `mv 暂存→目标` 失败（旧版本被放回，提示「已恢复旧版本」）；`卸载.command` 在假 HOME 里只删我们那一条 hook、别的原样保留。**没有跑过真实的安装.command**（它会 `pkill -x BuddyOffice`）。
- **真实数据只读**：`buddyctl dump --once --poll --json`（4 个会话，阶段 / 动作 / 登记表状态 / hook 事件数正常）、`dump --audit-opens 3 --poll`：**120 次 open、保险拒绝 0 次、不该出现的路径 0 个**，只有 `<pid>.json` 被打开。

**试过的坏数据**：极端 / 未来 / 乱序时间戳（随机 + 元数据）、FIFO / 目录 / 符号链接环 / 设备文件 / 000 权限、超大 hook 积压、`1e400` 与孤立代理项（hook-merge）、`dormantMax` 负数（读代码）、`nextWake` 过去时间（随机）。截断 UTF-8、嵌套、超大数字、NUL 路径这几类我没有重复造数据，只读了 `SafeJSON` / `LineSanitizer` / `TimeUtil` / `FileIO` / `TokenLedger.restoredCount` 的守卫代码并确认现有 Fuzz 套件覆盖（`FuzzParserTests` / `FuzzSecurityTests` / `FuzzPersistenceTests` 在基线里全过）。

**读了没找到问题的地方**（如实写，供判断查得够不够）：`TokenLedger` 的锁 / 队列关系（没有 ingest ↔ scan 的环形等待；`flush` 在自己队列上不会死锁；驱逐 → 断点恢复的时序在扫描队列上串行）、`SessionStore` 的定时器 / 泄漏（回调都是 `[weak self]`）、`FileWatcher` 的起停、`RegistryScanner` 的重试有界、`JSONLTailer.committedOffset` 不会下溢、`OpenAudit` 的 `forbiddenAttempts` 是全局计数（只在串行套件里被用，本轮 8 次并行没有因它失败）。S-1 按要求没有重报。

## 统计

| 严重度 | 新增 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 2（P2-1 测试基础设施、P2-2 桌面元数据未来时间戳） |
| P3 | 8 |
