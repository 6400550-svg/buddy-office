# QA · 逻辑线：状态机规则回放 + token 交叉核对 + dump 一致性

> 日期：2026-09-29　范围：任务书 4.1 / 5 节的状态机规则（`Sources/BuddyCore/Fusion` 一层）、token 统计的独立交叉核对、`buddyctl dump` 与登记表的一致性
> 方法：把它当成别人写的代码——先读任务书和源码，再用**假时钟回放**、**独立的参考模型**、**独立的 Python 脚本**、**变异测试**和**真实数据**逐条核对；只在新测试证明确实有 bug 时才动 `Fusion/**`。
> 铁律遵守情况：真实数据只读了 `~/.claude/sessions/<pid>.json`（文件名按 `^\d+\.json$` 过滤，`.key` 一次没打开过，连 stat 都没做）、按登记表 sessionId 拼出的 `~/.claude/.monitor/<id>.events.jsonl`、`~/.claude/projects` 下的会话记录、桌面元数据、`~/.token-meter/plugins/tokens.1m.py` 和 App 自己的 `ledger.json`，全部只读；没有连过任何 `*.sock`，没有读过任何凭据 / 钥匙串；没有改 `~/.claude`、ccmon、用量表（我 import 用量表时设了 `sys.dont_write_bytecode`，它的 `__pycache__` 还是 9 月 28 日 22:09 的那一份）、Claude.app；没有联网、没有 `pkill` App、没有碰正在运行的 `~/Applications/Buddy 办公室.app`、没有运行安装 / 卸载脚本；脚本 / 报告 / 日志里**没有任何对话内容**（只有计数、id 前缀、数字；标题只输出「来自哪一级」和「一致 / 不一致」；两个 Python 脚本的输出里有没有泄漏由 Swift 测试 `py1` / `py2` 逐字检查，冻结快照里有没有泄漏由 `token_crosscheck.py --selftest` 检查）。
> 没有削弱 / 跳过 / 删除任何已有测试；没有屏蔽编译警告（我新增的文件 0 警告）；没有改 Package.swift、BuddyStage、BuddyOffice、PixelKit、BuddyArt、buddyctl、别人的测试文件。
> 我改动的文件：新增 `Tests/BuddyCoreTests/StateRule{,Process,Chain,Invariant}Tests.swift`、`QA/tools/{token_crosscheck,dump_vs_registry,hooklog_replay,mutation_check}.py`、本文件；改了两处 `Sources/BuddyCore/Fusion`（`SessionEngine.swift`：L-001；`ActivityResolver.swift`：L-003）。

## 0. 结论与统计

**发现 5 个**：P0 0 / P1 1 / P2 2 / P3 2；**由我修复 2 个**（L-001、L-003）；1 个（L-002）在我发现之后已被别的代理接线修好（= `issues-app.md` A-001，我没有改 BuddyOffice）；2 个未修复（L-004 / L-005，都在范围外，且和别的 QA 的条目重复：`spec-trace-core.md` Q-08 / `issues-core.md` C-031）。
另有 7 条「已确认不是问题」（第 1 节末尾，不计入上面的数）。

**新增测试 63 个**（4 个套件；`z1` / `z2` 各带 16 个种子，共 93 个用例）：
`StateRuleTests` 52 个（任务书规则 a…n 逐条 + 清单外的 o）、`StateRuleProcessTests` 4 个（真进程）、`StateRuleChainTests` 5 个（dump 与 App 同一条数据链路 + 两个 Python 脚本在 FakeTree 上跑）、`StateRuleInvariantTests` 2 个（随机回放：参考模型对拍 / 快照不变量）。
另有 4 个 Python 工具（`token_crosscheck.py`、`dump_vs_registry.py`、`hooklog_replay.py`、`mutation_check.py`），前两个带 `--selftest`（Python 3.14 和系统的 3.9 都跑过）。

### 测试命令与结果（都在沙箱外跑；scratch 目录 `.build-qa-logic`，`-j 2`，收工时已删除）

| 命令 | 结果 |
|---|---|
| `cd ~/Desktop/编程项目/Buddy办公室 && BUDDY_SCRATCH=.build-qa-logic scripts/dev.sh test --filter StateRule -j 2`（根包，任务书指定的命令；**收工前删掉 scratch 目录后冷编译重跑的最终一次**） | **63 个测试（4 个套件）：63 通过、0 失败**（测试本身约 2.4 秒）。中途有几次因为别的代理正在改源码（`input file … was modified during the build`）编译失败，隔 20–30 秒重试通过。冷编译的 60 行警告全部来自别人的 `HelperAttributionTests.swift:250`（见 L-005），我的文件 0 警告。 |
| 同上，私有沙箱里跑**全部** BuddyCoreTests（不含别的 QA 正在写的 `Fuzz*`；沙箱 = 把源码 / 测试 rsync 到 `$TMPDIR` 下的隔离包，免得别人改到一半的文件挡住编译） | **290 个测试（25 个套件）：290 通过、0 失败**（约 24 秒）——即原有的 227 个全部还通过 + 我的 63 个。 |
| 稳定性：`--filter StateRule` 连跑 4 次；再在 6 个 CPU 满载进程下跑 1 次；收工前又用编好的测试包连续跑 12 次（`--skip-build`） | 17 次全部 63 / 63 通过（真进程、子进程、虚拟时钟三类测试都没有时序敏感的偶发失败）。**唯一一次例外**：收工前有一次官方命令跑到 1.5 秒左右进程无声地结束——日志截断、没有汇总行、`exit=1`、也没有崩溃报告。我对自己的测试进程发 `SIGTERM` / `SIGKILL` 复现出了**一模一样**的现象，而我的测试里没有 `exit` / `kill` / `try!`，所以这是测试进程被外部杀掉（多个代理共用这台机器），不是测试崩溃；立刻重跑 63 / 63。同一时段 `~/Library/Logs/DiagnosticReports` 里的三份 `swiftpm-testing-helper` 崩溃报告（04:46 / 04:49）都出自别的代理的 `AppLayerFixTests.demoModesWithNonsenseParametersDoNotCrashOrExplode`（`DemoScript.snapshots` 里 NaN → Int / 区间下界大于上界，BuddyStage，范围外，看样子正在被修）。 |
| 修复前失败（在私有副本里把修复撤回，不动真实源码）：L-001 撤回 → `e2`、`e5` | **失败**：`Expectation failed: (h.snap(key)?.activity → .finished) != (Activity.finished → .finished)`（e2）；e5 的 `seen` 序列是 `[finished, finished, finished, interrupted, …]`（e2 一个 issue、e5 三个）。恢复修复后 2 / 2 通过。 |
| L-003 撤回 → `o1`、`o2` | **失败**（6 个 issue）：`Expectation failed: (s?.activity → .compacting) == (expected → .thinking)`、`(K.tool(h.snap(key))?.call.name → nil) == "Bash"`、`(ActivityResolver.resolve(sig(postCompact: 199.98), now: at(201)) → .compacting) == .thinking`。恢复修复后 2 / 2 通过。 |
| 变异测试（第 3 节）：60 个变异 + 手工补的 2 个 | 我的测试杀死 57 个、只被已有测试杀死 4 个、存活 1 个（`M47`，等价变异：引擎层不可达）。 |
| `python3 QA/tools/{token_crosscheck,dump_vs_registry}.py --selftest`（3.14 与 `/usr/bin/python3` 3.9） | 4 / 4 通过。 |

**本轮最重要的几条**
1. **L-003（真实数据发现的）**：真实日志里现在有 3 组 `PreCompact / PostCompact / compact_boundary`（这台机器本会话的 3 次自动压缩），时序和任务书 / README 的假设相反——`compact_boundary` 是压缩**结束**时才写的（比 `PreCompact` 晚 88–104 秒），引擎却把它当「正处在压缩中」，结果每次压缩结束后要等下一条 assistant 行落盘（实测 2.4–3.8 秒，最坏 120 秒）才不再显示「整理上下文」，把压缩完的第一个工具盖住。已修。
2. **L-001**：一轮没有 Stop、也还没有打断标记就结束时，引擎先报 0.4 秒「做完了」再改口成「被打断 / 出错」，而 App 的提醒（`AlertCoordinator`）看到 `.finished` 就会发「做完了」提醒。已修。
3. **token 统计四个口径逐位一致**（独立重写的实现 == 用量表原版 `parse_line` == App 的 `ledger.json` == `buddyctl dump`），真实的 4 个活会话 + 1 个带 prior 的桌面会话都是个位数相同；`dump` 与登记表核对 4 / 4 一致。
4. 变异测试证明：已有测试把大多数数字钉住了（重试余量 15 秒、做完了 5 秒、被打断 3 秒、临时 busy 3 秒、PID 复用 2 秒、0.15 / 0.4 秒……），但**没有钉住**的有 18 个（第 3 节列出）：30 分钟兜底的精确边界、引擎的 45 分钟睡着、quiet 的 10 分钟、离场防抖 3 秒的下界、8 秒收回工位的下界、0.4 秒宽限期的下界、各个「轮次边界」在引擎层的效果、`Task` 也算前台委派……新测试把它们都钉上了。

---

## 1. 问题清单

### L-001 [P2] 一轮结束时证据还不够的 0.4 秒里，引擎先报「做完了」再改口成「被打断 / 出错」
- 现象：登记表翻 idle、hook 正常、但还没有 Stop 事件也没有打断 / 错误的会话记录行时（例如打断标记落盘比登记表晚、或者出错证据晚到），`transition` 把 `turnEnd` 先置成 `.finished`，`finalizePendingEnd` 在 `classify` 返回 nil（宽限期 0.4 秒内）时不改，于是快照在这 0.4 秒里是 `.finished`，之后才变成 `.interrupted`。`AlertCoordinator.observe`（`Sources/BuddyOffice/AlertCoordinator.swift`：`case .finished = s.activity, was != cur, let d = s.lastTurnDuration` 那一段，`wait` 对终端会话是 0）看到 `.finished` 且用时 ≥ 30 秒就登记「做完了」提醒，终端会话当场发出去、桌面会话 8 秒后发——而且之后变成 `.interrupted` 也不会撤销。「被打断」的那一轮还会让白板「正」字多记一笔。
- 根因：`Sources/BuddyCore/Fusion/SessionEngine.swift`（`transition` 里 `newPhase == .idle` 分支，`st.turnEnd = .finished`）。
- 修法：证据不够时先置 `.none`（动作是 `.idle`），证据够了由同一次 `update` 里的 `finalizePendingEnd → complete()` 定下来；宽限期满还没有证据也会定下来（`nextWake` 已经安排在 `endedAt + 0.4 秒`）。正常流程（Stop 先到、比登记表早 40–60 ms）不受影响——分类在同一次 `update` 里完成，不会出现中间态。
- 回归测试：`StateRuleTests › e2_hookInferredInterruptNeverShowsFinished`、`e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst`（Stop / 打断标记在登记表翻 idle 之前 60 ms 到 … 之后 350 ms 到、都没有，共 9 种到达顺序，每 50 ms 记一次动作，断言中途绝不出现错误的结论、最终结论对、只发一次结束事件）。
- 修复前失败的证据：`Expectation failed: (h.snap(key)?.activity → .finished) != (Activity.finished → .finished)`（StateRuleTests.swift:368，e2）；e5：`seen → [finished, finished, finished, interrupted, …]`。
- 修复后：e2、e5 通过；变异 M48（把修复撤回）被 e2、e5 杀死。整套 BuddyCoreTests 290 / 290 通过。
- 残留（`spec-trace-core.md` Q-13 也提到）：宽限期内动作是 `.idle`——舞台会先切到空闲桌面再切到「做完了 / 被打断」，比先闪绿色 ✓ 好，但还不是「保持 busy 直到判定」。想更彻底，可以在宽限期内保持上一个 busy 动作（要让 `phase` 和登记表暂时不一致，我没有这么改）。
- 状态：**已修复**

### L-002 [P1] 设置里的「空闲多久后打盹 / 睡着」「启动时只显示最近 N 小时」是摆设
- 现象：`idle.dozeMinutes` / `idle.sleepMinutes` / `dormant.recentHours` 只存进 UserDefaults，没有任何代码把它们传给 `SessionEngine.Options.dozeAfter / sleepAfter / dormantRecent`（`RealProvider.make` 只造默认 Options；`SessionStore.options` 是 `let`）；`dormant.max` 只在 `AppModel.refreshDerived` 里按座位号 `.prefix`，引擎里那几个名额仍占着座位。任务书 5.4「两个时间都可以在设置里改」/ 7.5 没有实现。我用「设置键 → 消费者」的静态统计核实过：三个键在 `Sources/BuddyOffice` 里除了设置页和默认值没有任何读取者。数据层这一半是好的（`EngineScenarioTests.dozeAndSleepThresholdsAreConfigurable`、我的 `g1`）。
- 根因：BuddyOffice 没接线（不在我的修改范围）。
- 修法：由别的代理处理——我写完发现后不久（03:54 起）`Sources/BuddyOffice/EngineConfig.swift` / `RealProvider.swift` / `Tests/BuddyOfficeTests` 出现，现在 `RealProvider.make` 已经用 `SessionEngine.Options(paths:)` 加 `EngineConfig.apply(to:settings:)` 覆盖四项设置再 `SessionStore(options:)`（「下次启动生效」）。这和 `issues-app.md` A-001 是同一条。
- 回归测试：别的代理的 `Tests/BuddyOfficeTests/EngineConfigTests.swift`；我这边没有重复写（我曾写过一个 `withKnownIssue` 的静态检查，接线出现后就删掉了）。
- 修复前失败：同 A-001（应用层的 `EngineConfigTests`；放上「旧行为骨架」——设置不传给引擎——后失败：`EngineConfigTests.swift:10:9: Expectation failed: (v.dozeAfter → 600.0) == (180 → 180.0)`；修复后通过）。
- 状态：已修（由应用层修复，同 `issues-app.md` A-001；「下次启动生效」）。我的 `chain1` 里对 App 造 `SessionStore` 方式的断言已跟着新的 `RealProvider` 更新。

### L-003 [P2] 压缩结束后仍显示「整理上下文」（`compact_boundary` 是压缩**结束**时才写的）
- 现象：真实日志（这台机器，20c4bcc8 那个会话的 3 次自动压缩）里：`PreCompact(auto)` → 88–104 秒后 → 会话记录先写一行 `isCompactSummary` 的 user 行（比边界早 0.4 秒）→ hook 的 `SessionStart(source=compact)` → `PostCompact`（晚 0.02–0.03 秒）→ `compact_boundary`（比 `SessionStart(compact)` 晚 0.04–0.07 秒）→ 2.4–3.8 秒后才是第一条 assistant 行（第一个 `PreToolUse` 在 3–5 秒后）。压缩**开始**时会话记录里什么都没有。引擎的会话记录规则（`ActivityResolver.busyActivity` 1b）却是「`compact_boundary` 之后没有新的 assistant / user 行 → 整理上下文（最多 120 秒）」，而且排在「有打开的工具」之前——所以每次压缩**结束**后，即使 hook 已经报了 `PostCompact`，buddy 还会继续显示「整理上下文」，把压缩完的第一个工具盖住，直到下一条 assistant 行落盘（实测 2.4–3.8 秒；主会话记录要等整条消息生成完才写盘，慢的时候更久，兜底 120 秒）。
- 根因：`Sources/BuddyCore/Fusion/ActivityResolver.swift`（`busyActivity` 里 `compactBoundaryAt` 那一段）。任务书 5.4「或者会话记录显示正处在 compact_boundary 压缩中」以及 README / DESIGN 的「没有任何真实样本，只用合成 fixture 测」都是在没有真实数据时的假设；现在有真实样本，假设不成立。
- 修法：hook 已经说压缩结束了（`postCompactAt`——`PostCompact` 或 `SessionStart(compact)` 都会写它——不早于 `compact_boundary` 前 5 秒，`boundaryHookSlack`）就不再用 `compact_boundary` 显示整理上下文；没有 hook 的会话（只有这一个信号）照旧。已有的 `ActivityResolverTests.compactingFromTranscriptBoundary` 不受影响（它没有 postCompactAt）。
- 回归测试：`StateRuleTests › o1_compactionEndsWhenTheHooksSayItEnded`（用真实时序：PreCompact → 100 秒 → isCompactSummary 行 / SessionStart(compact) / PostCompact / compact_boundary → 4.6 秒后 `PreToolUse`；断言压缩中显示整理上下文、结束后不再显示、第一个工具马上显示）、`o2_boundaryHookSlackIsFiveSeconds`（5 秒口径：4.9 秒算、5.1 秒不算；没有 hook 仍是整理上下文；120 秒兜底）。
- 修复前失败的证据：`Expectation failed: (s?.activity → .compacting) == (expected → .thinking)`；`(K.tool(h.snap(key))?.call.name → nil) == "Bash"`；`(ActivityResolver.resolve(sig(postCompact: 199.98), now: at(201)) → .compacting) == .thinking`。
- 修复后：o1、o2 通过；BuddyCoreTests 290 / 290 通过。
- 顺带：Core README / DESIGN 里「PreCompact / PostCompact / compact_boundary 没有任何真实样本」的说法已经过时（文档不在我的修改范围，未改）。
- 状态：**已修复**

### L-004 [P3] 登记表半截文件「最多 5 次」的口径
- 现象：任务书 4.1「每隔 50 ms 重试一次，最多 5 次」，实现是「首读 + 4 次重试 = 共 5 次读」（`RegistryScanner.maxRetries = 5`，`failures < 5` 才排下一次）；更自然的读法是 5 次**重试**（共 6 次读，窗口 250 ms 而不是 200 ms）。现有测试 `RegistryScannerTests.halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms` 把「共 5 次」写成了断言（变异 M59 被它杀死）。实际影响几乎为零（半截文件微秒级就写完）。
- 根因：任务书措辞有歧义；实现选了一种读法。
- 修法：若要改成 5 次重试，改 `RegistryScanner`（Ingest，不在我的范围）并同时改那条已有测试的断言（我不能改）。
- 回归测试：我的 `n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine`（引擎层：12 次 50 ms 心跳之后仍是上一份好记录、`nextWake` ≤ 50 ms、写完整后立刻更新）只钉「保留 + 50 ms」，不钉次数。
- 状态：不修（P3，任务书措辞有歧义；影响几乎为零——半截文件微秒级就写完；已在 DESIGN.md §13 记录「5 次」按总读次数理解及理由）。

### L-005 [P3] 既有测试文件里有编译警告
- 根因：Swift Testing 宏展开对 `(a?.b ?? []).isEmpty` 这种写法会报两条编译警告。
- 回归测试：本身就是测试文件里的警告；修复后测试目标 0 警告（见 QA/evidence/regression-final/summary.txt）。
- 现象：根包 `swift test` 首次全量编译输出里有 120 行含 `warning:` 的行，全部来自 `Tests/BuddyCoreTests/HelperAttributionTests.swift` 里两处 `#expect((h.snap(DesktopFixture.key)?.helpers ?? []).isEmpty)`：这种写法在 Swift Testing 宏展开里报 `left side of nil coalescing operator '??' has non-optional type '[HelperSnapshot]?'` 和 `expression of type 'Bool?' is unused`。DESIGN.md「debug 和 release 构建都是 0 警告」只对库目标成立。我的新测试避开了这种写法（先取值再 `#expect`），0 警告。
- 后续（收工前，删掉 scratch 目录后冷编译重跑）：04:49 有人把其中一处（现在的 `:262`）改成了先取值再 `#expect(shown.isEmpty)`，`issues-core.md` C-031 因此标成「已修」；但**另一处 `HelperAttributionTests.swift:250` 还是原样**，冷编译仍有 60 行警告（就是那一处，重复出现在 15 次编译批次里）。
- 修法：把 `:250` 也改成 `let shown = h.snap(DesktopFixture.key)?.helpers ?? []` 再 `#expect(shown.isEmpty)`（和 `:262` 一样），或者 `#expect(h.snap(DesktopFixture.key)?.helpers.isEmpty == true)`。没改：任务书规定不改别人的测试文件。
- 状态：已修（主线程收尾时把 `:250` 和 `:262` 两处都改成了先取值再 `#expect`，断言的意思不变；同 `issues-core.md` C-031）。

### 已确认不是问题（不计入统计）
- **N-1 `type == "assistant"` 与 `message.role == "assistant"` 的判据差异**（`spec-trace-core.md` Q-09）：真实数据里 5372 行带 `usage` 的行（4 个活会话）两个判据 0 行不一致；两边都只统计 assistant。
- **N-2 30 分钟兜底在引擎层不可达**：变异 M47（把 `expireStale` 的 `registryIdle` 恒置 false）存活——因为登记表 idle 时主线程的调用早被「轮次边界（登记表变 idle）」关掉了，兜底只对小助手名下的记录起作用（`b8` 钉着）；规则本身由 `ToolTracker` 单元测试 `b7` 钉在精确边界（30:00 不关、30:00.001 关）。是防御性代码，不是 bug。
- **N-3 一条从不变成 busy 的提示**（比如本地处理的斜杠命令）留下的「幻影一轮」：`turnStarted` → 3 秒后 `turnFinished(duration: 0, interrupted: true)`，`lastTurnDuration` 被改成 0、`lastTurnEndedAt` 不变、未读被清。实验确认过；App 不消费事件（`AppModel` 里 `onEvent = { _ in }`），`lastTurnDuration` 只在 `.finished` 时显示，所以没有可见影响；「下一轮开始时清未读」是任务书的规则。
- **N-4 `isCompactSummary` 的 user 行被当作「人的一次输入」**（`isPrompt`）：只影响「没有 hook 的会话」里 `f.lastPromptAt`；本轮开始时间取最早的候选（登记表 busy 时间 / hook 提示），不受影响。
- **N-5 会话标题只在会话记录的尾部窗口（512 KB）里找**：真实数据 47 个会话文件里所有 `custom-title` / `ai-title` 行都在尾部窗口内（离文件末尾最远 28,312 字节，Claude Code 会反复把标题行写在末尾）。
- **N-6 `hookActive` 的「掉线」启发式**（会话记录比 hook 领先 > 15 秒就当 hook 掉线，`spec-trace-core.md` Q-06）：没有 Stop 又没有任何打断证据时会把「被打断」判成「做完了」，但所有打断形态（用户行、`isAbortedMidStream`）都有会话记录证据，只剩极窄的路径；README 已记录这个启发式。
- **N-7 同一批次里相隔 > 0.25 秒的并行调用会被提前「取代」**：真实 hook 日志独立回放里 8aab9e77（没有子代理）65 个 Pre 里 6 个被取代、另有 5 个 Post 找不到对应的 Pre（多半就是被提前取代的那些）；对应 README 的已知限制，只影响「×N」的个数和「当前工具」。

---

## 2. 规则 × 测试 × 状态 对照表

「已有测试」列括号里写的是**变异测试证明它有没有把具体数字钉住**（见第 3 节）。新测试的完整函数名见第 6 节。

| 规则 | 任务书出处 | 验证它的已有测试（数字有没有钉住） | 新增测试 | 结论 |
|---|---|---|---|---|
| (a) 并行工具：同一毫秒两个 Read 先进先出配对；距离上一个主线程 Pre 超过 0.25 秒算新一批 | 5.2 Pre / Post | `ToolTrackerTests.parallelCallsInTheSameMillisecondShareABatch`、`identicalParallelCallsCloseFirstInFirstOut`（FIFO 已钉，M05）、`postFallsBackToToolNameThenIgnores`、`callsWithin250msOfThePreviousPreStayInTheSameBatch`（用 0.2 / 0.3 两点夹住 0.25，M01 / M02 都杀；但没有恰好 0.25 / 0.251）。引擎层没有 | a1（引擎层：同一毫秒三个 Read、FIFO、名字优先）、a2（恰好 0.25 秒同批 / 0.251 秒新批）、a3（detail 对不上退回「最早的同名」）、z1 | ✓ |
| (b) 悬空工具：被新一批取代；轮次边界（Stop / UserPromptSubmit / SessionStart / 登记表 idle / stop_hook_summary）关掉主线程全部打开调用；idle 且开着超过 30 分钟强制关 | 5.2 | `ToolTrackerTests.newBatchClosesOlderOpenCallsAsSuperseded`、`permissionDeniedDanglingIsClosedByTheNextBatch`、`turnBoundariesCloseAllMainCalls`、`aBoundaryOlderThanAnOpenCallDoesNotCloseIt`、`staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle`（只钉「29 分钟不关、31 分钟关」，M03 / M08：已有测试杀不死）、`helperOwnedRecordsExpireRegardless`。**引擎层五种边界一个都没有** | b1 Stop、b2 UserPromptSubmit、b3 SessionStart、b9 SessionEnd、b4 登记表 idle、b5 stop_hook_summary（含「比调用旧的不能误关」）、b6 被下一批取代 + 晚到的 Post、b7 30 分钟精确边界、b8 小助手名下 29 / 31 分钟、z1 | ✓（30 分钟兜底对主线程在引擎层不可达，见 N-2） |
| (c) 重试：显示第 n / 共 m 次；`retryInMs` + 15 秒后没有新行则不再显示 | 5.4 busy 2 | `ActivityResolverTests.retryingWithinRetryInMsPlus15Seconds`（118.9 / 119.1 秒，M17 / M18 都杀）、`retryingBeatsOpenTools`；`EngineScenarioTests.retryingThenBackToThinkingWhenTheRetryWindowPasses`（16 / 16.5 秒）；`TranscriptTests.apiErrorIsRecordedWithRetryInfo` | c1（引擎层：3/10、retryInMs 2.5 秒 → 17.4 秒还在、17.6 秒消退）、c2（新的 user 行也清掉重试） | ✓ |
| (d) 出错：重试到上限 / 最后一条 assistant 是合成的 API 错误 | 5.4 idle 3 | `EngineScenarioTests.erroredTurnStaysErroredUntilItStartsDozing`（两个信号同时给）、`ActivityResolverTests.erroredStaysUntilDozing`、`TranscriptTests.syntheticApiErrorAssistantIsRecognized`（M40 只有我的 d1 杀） | d1（只有重试到上限）、d2（只有合成错误消息）、d3（5/10 且之后恢复 → 不算）、d4（到上限但之后又有 assistant 行 → 不算）、d5（打断后的 "No response requested." 不算错误）、d6（出错优先于做完了） | ✓ |
| (e) 被打断：会话记录里的 `[Request interrupted by user`（比上次轮次结束更晚）和「hook 正常但 busy→idle 没有 Stop」两种形式，持续 3 秒 | 5.4 idle 1 | `ActivityResolverTests.interruptedLasts3SecondsThenIdle`（2.9 / 3.1 秒，M13 / M14 杀）；`EngineScenarioTests.aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted`、`interruptDetectedFromTheTranscriptWithoutAnyHook`、`abortedMidStreamAlsoCountsAsAnInterrupt`、`aNormalStopAfterAnEarlierInterruptIsNotInterrupted`；`TranscriptTests.userInterruptTextIsDetectedInBothShapes`、`abortedMidStreamAssistantIsAnInterrupt`；`StoreTests.timeDrivenChangesHappenOnTimeNotOnTheNextHeartbeat`（0.4 秒宽限的下界没钉，M32：已有测试杀不死） | e1（转录标记：登记表 idle 起 2.9 秒在、3.1 秒消）、e2（hook 推断：**不能先报做完了** → L-001）、e3（无 hook → 做完了）、e4（宽限期内 Stop 到 → 做完了）、e5（9 种证据到达顺序） | ✓（L-001 已修） |
| (f) 做完一轮：5 秒；桌面会话最多等 4 秒看 postTurnSummary，blocked 叠加「需要你处理」保持到下一轮；未读的三个清除条件 | 5.4 idle 2 / 叠加标记 | `ActivityResolverTests.finishedLasts5SecondsThenIdle`（4.9 / 5.1 秒，M15 / M16 杀）；`EngineScenarioTests.aNormalTurnProducesTheExpectedActivitiesAndEvents`、`startingTheNextTurnClearsUnread`；`EnginePresenceTests.focusingTheSessionInTheDesktopAppClearsUnread`、`blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn`、`aSummaryForAnOlderAssistantMessageIsNotBlocked`、`aBlockedSummaryAlreadyThereAtLaunchShowsBlocked`；`StoreTests.markSeenAndRerollAreSafeFromAnyThread`（「严格晚于」M36：已有测试杀不死） | f1（引擎层 4.9 / 5.1 秒 + 未读保留）、f2（三个清除条件，lastFocusedAt 早于 / 等于 / 晚 1 毫秒于本轮结束）、f3（completed 不亮 blocked、blocked 7 秒后才落盘也亮、只发一次、保持到下一轮） | ✓；「最多等 4 秒」：数据层没有等待逻辑，App 层 `AlertCoordinator.summaryWait` = 8 秒（DESIGN.md「与任务书不一致」表已记录：本轮总结实测约 7 秒后才落盘）——**已记录的偏离**；`AlertCoordinator` 在 App 目标里，BuddyCoreTests 测不到，别的代理新增了 `Tests/BuddyOfficeTests/AlertCoordinatorTests.swift`（含「被打断的一轮不提醒」），我没有复核它的断言 |
| (g) 空闲 10 分钟打盹、45 分钟睡着（设置里可改） | 5.4 idle 4 | `ActivityResolverTests.idleThenDozingThenSleepingAtTheThresholds`（9:59 / 10:00 / 44:59 / 45:00，但测的是 `SessionSignals` 的默认值，不是引擎的默认值；M24：已有测试杀不死）、`EngineScenarioTests.dozeAndSleepThresholdsAreConfigurable`、`attachingToALongIdleSessionShowsTheRightSleepState` | g1（引擎默认值：599.9 秒 idle、600.1 秒 dozing、2699.9 秒 dozing、2700.1 秒 sleeping）、z2（随机回放里每一步检查空闲时间窗口） | ✓；「设置里可改」的接线：L-002（已被别的代理修） |
| (h) busy 连续 2 小时不判死，只是 quiet 换画法 | 4.1 / 5.4 叠加标记 | `EngineScenarioTests.aSessionBusyForAnHourNeverDies`（62 分钟，每分钟一步；只抽查 < 9 分钟不是 quiet、≥ 11 分钟是 quiet，10 分钟边界没钉，M25 / M26：已有测试杀不死）、`aWaitingSessionStaysWaitingNoMatterHowLong`、`ActivityResolverTests.aSessionBusyForAnHourIsStillBusy` | h1（虚拟时钟**一次推进 2 小时** + 60 次反复心跳：在场、busy、还是那个工具、quiet、没有任何事件）、h2（quiet 恰好 10 分钟；hook 有新事件 / 会话记录长了一行都立刻清掉） | ✓ |
| (i) 进程被回收：登记文件消失 → 防抖 3 秒 → 离场；桌面 + 元数据在 + 没归档 → 下班工位；其他 8 秒后收回；同一身份带新进程回来坐回原工位；PID 复用（相差 > 2 秒）判死；EPERM 当活着；sysctl 失败当「未知」= 活着 | 4.1 / 5.5 | `EnginePresenceTests.departureIsDebouncedBy3SecondsAndComingBackCancelsIt`、`aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat`、`aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves`、`aFreedSeatIsReusedByTheNextNewcomer`、`aSeatHeldByADormantBuddyIsNotGivenToNewcomers`、`pidReuseIsTreatedAsTheOldProcessBeingGone`、`unknownProbeStateMeansAlive`、`aDeadPidWithALeftoverRegistryFileIsGone`、`dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted`、`departedSessionsCompeteForTheFourDormantSeats`、`dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions`；`ProcessProbeTests.classification`（1.9 / 2.5 / −3 秒；M54 / M55 杀）、`systemProbeSeesThisProcess`（pid 1 = EPERM）。防抖 3 秒只钉了上界（M27：已有测试杀不死）、8 秒只钉了上界（M29：已有测试杀不死） | i1（防抖 2.95 / 3.05 秒 + 事件只发一次 + 8 秒收回 7.9 / 8.1 秒）、i2（下班工位 vs 归档）、i3（8 秒内带新进程回来）、i4（容差恰好 2.0 / 2.001 秒）、i5（kill 成功但 sysctl 读不到）、i6（PID 复用同样先防抖）；**真进程**：r1（sysctl 启动时间就是启动的时候）、r2（pid 1：EPERM 当活着）、r3（真的子进程被回收：2.9 / 3.1 秒）、r4（PID 复用：procStart 差 10 秒） | ✓ |
| (j) /clear（同进程）和 --resume（新进程同 sessionId）之后还认得是同一个人；key = `d:`+host / `t:`+第一次见到的 sessionId；工位号和外观盐不变 | 4.5 | `IdentityTests`（`desktopKeyIsDPrefixPlusHostSessionId`、`terminalKeyIsTPrefixPlusFirstSeenSessionId`、`hostAliasWinsEvenWhenPidAndSessionIdChange`、`desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing`、`terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess`、`terminalResumeInANewProcessKeepsTheSameBuddyViaSessionAlias`、`persistenceRoundTripKeepsAliasesSeatAndSalt` 等）；`EnginePresenceTests.terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles`、`terminalResumeInANewProcessGivesTheSameBuddyBack`、`identitiesAndAppearanceSurviveARestart` | j1（桌面 /clear：key / 工位 / 盐不变、旧工具不带过来、token = 新旧两份之和）、j2（终端 key 穿过 /clear + 进程退出 + resume 新 sessionId 仍是 `t:` + 第一次见到的）、j3（桌面 resume 登记表没有 host：靠元数据 cliSessionId / prior 认出） | ✓ |
| (k) 子代理归属：前台 Agent / Task 开着且事件晚 ≥ 0.15 秒 → 小助手；主会话 idle → 后台小助手；有后台小助手活跃先扣 400 ms；SubagentStop 只当提示 | 5.3 | `HelperAttributorTests`（`rule1MainIdleMeansBackgroundHelper`、`rule2ForegroundAgentOpenAndEventLaterThan150ms`、`rule3…` 四个、`eachToolUseIsClaimedOnlyOnce` 等，0.15 的上界和 0.4 的两侧钉住：M49 / M51 / M52 杀）、`HelperAttributionEngineTests` 八个；`0.1` 的下界没钉（M50：已有测试杀不死） | k1（`Task` 也算前台委派；0.149 秒的同批并行调用归主线程、恰好 0.15 秒归小助手）、k2（SubagentStop 让下一次 poll 马上重读桌面元数据；不改变工具 / 阶段）、k3（扣住 0.39 / 0.41 秒）、z1（规则 1、2 在随机事件流里对拍） | ✓ |
| (l) 等待类判定：permission prompt / sandbox request → 等批准（工具取最新打开的主线程调用，没有则从 Notification 解析 `use <T>`）；input needed / dialog open → 提问；ExitPlanMode 开着 → 计划待审；其他 → 其他等待 | 5.4 waiting | `ActivityResolverTests` 十个（`permissionPromptIsApprovalWithTheNewestOpenTool`、`sandboxRequestIsApproval`、`inputNeededAndDialogOpenAreQuestions`、`exitPlanModeWhileWaitingIsPlanReview`、`askUserQuestionNotificationSaysPermissionButItIsAQuestion`、`nonPermissionWaitsFromTerminalSessions`、`unknownWaitingTextIsClassifiedByKeywords`、`approvalToolComesFromTheNotificationWhenNothingIsOpen`、`notificationNamesTheToolAmongParallelOnes`、`missingWaitingForFallsBackToNotificationText`）；`EngineScenarioTests.waitingVariantsThroughTheEngine`、`attentionKindChangesWhileStillWaitingEmitAFreshEvent`、`waitingAtStartupIsReportedImmediately` | l1（引擎层：Notification 解析 `use Bash`、最新打开的调用、sandbox request）、l2（提问 / 计划待审 / AskUserQuestion 的 detail 永远为空）、l3（其他等待附原始文本 + 批准后 `needsUserCleared`）、z1 | ✓ |
| (m) phase 的两个临时修正：登记表 idle 但有更新的 UserPromptSubmit → 暂时 busy（最多 3 秒）；登记表 busy 但有更新的 Stop → 暂时 idle | 5.1 | `ActivityResolverTests.registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds`（103.4 / 103.6 秒，M11 / M12 杀）、`registryBusyButNewerStopIsTemporarilyIdle`、`waitingIsNeverOverriddenByHooks`、`missingRegistryStatusFallsBackToHooks`；`EngineScenarioTests.promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce`、`aPromptThatNeverBecomesBusyExpiresAfter3Seconds` | m1（引擎层 2.9 / 3.1 秒、只开始一轮）、m2（Stop 后又来提示 → 又是 busy）、z1（每一步阶段和独立参考模型一致） | ✓ |
| (n) 登记表读取规则：半截 JSON 保留上一份好记录并每 50 ms 重试至多 5 次；kind 不是 interactive 的不画；只打开 `^\d+\.json$` | 4.1 | `RegistryScannerTests.halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms`（M58 / M59 杀）、`emptyFileDuringTruncateIsTreatedAsHalfWritten`、`onlyInteractiveSessionsAreShown`（M60）、`fileNamePattern`、`missingFieldsAreOptionalButPidAndSessionIdAreRequired`；`FileAccessTests.keyFilesAreNeverOpened`、`safetyNetRefusesKeyAndSocketPaths`；`EnginePresenceTests.nonInteractiveSessionsNeverBecomeGhostColleagues`；`RobustnessTests.aRegistryFileThatIsADirectoryOrHasWeirdTypesIsIgnored` | n1（引擎层：半截文件后 12 次心跳仍在场、`nextWake` ≤ 50 ms、写完整后立刻更新）、n2（`RegistryScanner` 只 `read` 匹配名的文件、`.key` / `.bak` / 非数字名 / 多段名连 stat 都不做） | ✓；「最多 5 次」的口径：L-004 |
| (o) 清单外：整理上下文（PreCompact / PostCompact / compact_boundary） | 5.4 busy 1 | `EngineScenarioTests.compactionThroughHooks`、`ActivityResolverTests.compactingWhenPreCompactHasNoPostCompact`、`compactingExpiresIfPostCompactNeverArrives`、`compactingFromTranscriptBoundary` | o1、o2（真实时序） | ✓（L-003 已修） |
| 任务 3：dump 与 App 同一条数据链路 | — | — | chain1（结构）、chain2（真的 dump 可执行文件 == App 构造方式的 SessionStore）、chain3（SessionStore == 直接用 SessionEngine）、py1 / py2（两个 Python 脚本在 FakeTree 上） | ✓ |

---

## 3. 变异测试（证明测试真的把数字钉住了）

`QA/tools/mutation_check.py` 对 `Sources/BuddyCore` 的**副本**做 60 个小变异（只改副本，不改仓库；每个变异前都和仓库重新同步），每个变异编译一次，跑「我的测试」和「已有测试」两组。结果：**55 个被我的测试杀死；4 个（M33 M34 M59 M60）只被已有测试杀死；1 个存活（M47，等价变异，见 N-2）**。另外手工补了两个：`M61`（`SessionEnd` 不再是轮次边界）被 `b9` 杀死；`M62`（出错的重试上限判据 `>=` → `>`）被 `d1`、`d6` 杀死。

「已有测试」一列为空（—）的，就是**已有测试没有钉住这个数字 / 分支**，只有我的测试杀得到：M03 M06 M08（30 分钟兜底的精确边界、Post 只按名字时关最早的）、M24（引擎的 45 分钟睡着）、M25 M26（quiet 的 10 分钟）、M27（离场防抖的下界）、M29（8 秒收回的下界）、M32（0.4 秒宽限的下界）、M36（未读「严格晚于」）、M40（出错的重试上限判据）、M41–M45（五种轮次边界在引擎层的效果）、M46（`Task` 也算前台委派）、M50（0.15 秒的下界）。

| # | 变异 | 我的测试杀死 | 已有测试杀死 | 结果 |
|---|---|---|---|---|
| M01 | 批次间隔 0.25→0.3 | a2、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch | 杀死 |
| M02 | 批次间隔 0.25→0.2 | a2、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch | 杀死 |
| M03 | 悬空兜底 30→29 分钟 | b7 | — | 杀死 |
| M04 | 悬空兜底 30→31 分钟 | b7、b8 | helperOwnedRecordsExpireRegardless、staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle | 杀死 |
| M05 | Post 配对不是先进先出（名字+detail） | a1、z1 | identicalParallelCallsCloseFirstInFirstOut | 杀死 |
| M06 | Post 只按名字时不是最早的 | a3、z1 | — | 杀死 |
| M07 | 新一批不关旧批次悬空的调用 | a2、b6、k1、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch、newBatchClosesOlderOpenCallsAsSuperseded、permissionDeniedDanglingIsClosedByTheNextBatch | 杀死 |
| M08 | 兜底：>= 而不是 >（恰好 30 分钟就关） | b7 | — | 杀死 |
| M09 | 兜底：登记表 idle 或小助手 → 登记表 idle 且小助手 | b7、z1 | helperOwnedRecordsExpireRegardless、staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle | 杀死 |
| M10 | 轮次边界不关任何调用 | b1、b2、b3、b4 等6个 | turnBoundariesCloseAllMainCalls | 杀死 |
| M11 | 临时 busy 窗口 3→4 | m1 | aPromptThatNeverBecomesBusyExpiresAfter3Seconds、registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds | 杀死 |
| M12 | 临时 busy 窗口 3→2 | m1 | registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds | 杀死 |
| M13 | 被打断持续 3→4 | e1、e2、z2 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted、interruptedLasts3SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M14 | 被打断持续 3→2 | e1、e2、e5 | interruptedLasts3SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M15 | 做完了持续 5→6 | f1、z2 | aNormalTurnProducesTheExpectedActivitiesAndEvents、attachingToAnIdleSessionThatJustFinishedShowsFinishedForTheRemainingTime、finishedLasts5SecondsThenIdle 等4个 | 杀死 |
| M16 | 做完了持续 5→4 | f1 | finishedLasts5SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M17 | 重试余量 15→16 秒 | c1 | nextChangeTellsWhenTimeWillChangeTheResult、retryingThenBackToThinkingWhenTheRetryWindowPasses、retryingWithinRetryInMsPlus15Seconds | 杀死 |
| M18 | 重试余量 15→14 秒 | c1 | nextChangeTellsWhenTimeWillChangeTheResult、retryingThenBackToThinkingWhenTheRetryWindowPasses、retryingWithinRetryInMsPlus15Seconds | 杀死 |
| M19 | sandbox request 不算等批准 | l1、z1 | sandboxRequestIsApproval、waitingVariantsThroughTheEngine | 杀死 |
| M20 | dialog open 不算提问 | l2、z1 | exitPlanModeWhileWaitingIsPlanReview、inputNeededAndDialogOpenAreQuestions、waitingVariantsThroughTheEngine | 杀死 |
| M21 | 等批准时 ExitPlanMode 不是计划待审 | l2、z1 | exitPlanModeWhileWaitingIsPlanReview | 杀死 |
| M22 | 等批准时 AskUserQuestion 不是提问 | l2、z1 | askUserQuestionNotificationSaysPermissionButItIsAQuestion | 杀死 |
| M23 | 打盹 10→9 分钟 | g1 | erroredTurnStaysErroredUntilItStartsDozing | 杀死 |
| M24 | 睡着 45→44 分钟 | g1 | — | 杀死 |
| M25 | quiet 10→9 分钟 | h2 | — | 杀死 |
| M26 | quiet 10→11 分钟 | h2 | — | 杀死 |
| M27 | 离场防抖 3→2 秒 | i1、i6、r3、r4 | — | 杀死 |
| M28 | 离场防抖 3→4 秒 | i1、i2、i3、i6 等7个 | aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat、aFreedSeatIsReusedByTheNextNewcomer、aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves 等5个 | 杀死 |
| M29 | 收回工位 8→7 秒 | i1 | — | 杀死 |
| M30 | 收回工位 8→9 秒 | i1、j2 | aFreedSeatIsReusedByTheNextNewcomer、aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves、terminalResumeInANewProcessGivesTheSameBuddyBack | 杀死 |
| M31 | Stop 宽限 0.4→0.6 | e2、e3 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted | 杀死 |
| M32 | Stop 宽限 0.4→0.2 | e5 | — | 杀死 |
| M33 | 下班工位上限 4→5 | — | departedSessionsCompeteForTheFourDormantSeats、dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions | 只被已有测试杀死 |
| M34 | 下班工位 12→11 小时 | — | dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted | 只被已有测试杀死 |
| M35 | 下班工位不看归档 | i2 | aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves | 杀死 |
| M36 | 未读：lastFocusedAt >= 也清 | f2 | — | 杀死 |
| M37 | 未读：lastFocusedAt 不清未读 | f2 | focusingTheSessionInTheDesktopAppClearsUnread | 杀死 |
| M38 | 被打断也亮未读 | e1、e2 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted | 杀死 |
| M39 | 没有 Stop：hook 正常 → 做完了，没有 hook → 被打断（反了） | e2、e3、e5 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted、timeDrivenChangesHappenOnTimeNotOnTheNextHeartbeat | 杀死 |
| M40 | 出错：重试到上限 → 超过上限 | d1 | — | 杀死 |
| M41 | 轮次边界：Stop 不关调用 | z1 | — | 杀死 |
| M42 | 轮次边界：UserPromptSubmit 不关调用 | b2、z1 | — | 杀死 |
| M43 | 轮次边界：SessionStart 不关调用 | b3、z1 | — | 杀死 |
| M44 | 轮次边界：登记表变 idle 不关调用 | b4、z1 | — | 杀死 |
| M45 | 轮次边界：stop_hook_summary 不关调用 | b5 | — | 杀死 |
| M46 | 前台只认 Agent 不认 Task | k1、z1 | — | 杀死 |
| M47 | 兜底用的登记表 idle 恒为 false | — | — | 存活（等价变异） |
| M48 | (回退我的修复) 宽限期内先报做完了 | e2、e5 | — | 杀死 |
| M49 | 前台 Agent 间隔 0.15→0.2 | k1、z1 | rule2ForegroundAgentOpenAndEventLaterThan150ms | 杀死 |
| M50 | 前台 Agent 间隔 0.15→0.1 | k1、z1 | — | 杀死 |
| M51 | 扣住 0.4→0.5 秒 | k3 | eachToolUseIsClaimedOnlyOnce、rule3HoldEndsEarlyWhenTheTranscriptCatchesUp、rule3NoMatchHoldsFor400msThenGoesToMain 等4个 | 杀死 |
| M52 | 扣住 0.4→0.3 秒 | k3 | eachToolUseIsClaimedOnlyOnce、rule3HoldEndsEarlyWhenTheTranscriptCatchesUp、rule3NoMatchHoldsFor400msThenGoesToMain | 杀死 |
| M53 | 主会话 idle 不归小助手 | b8、z1 | idleMainSessionsBackgroundHelperEventsGoToTheHelper、rule1MainIdleMeansBackgroundHelper | 杀死 |
| M54 | PID 复用容差 2→3 秒 | i4、i6、r1 | classification | 杀死 |
| M55 | PID 复用容差 2→1 秒 | i4、r1 | classification、pidReuseIsTreatedAsTheOldProcessBeingGone | 杀死 |
| M56 | EPERM 当作死了 | r2 | systemProbeSeesThisProcess | 杀死 |
| M57 | sysctl 失败(unknown)当作死了 | i4 | classification、unknownProbeStateMeansAlive | 杀死 |
| M58 | 登记表重试间隔 50→100 ms | n1 | halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms | 杀死 |
| M59 | 登记表重试上限 5→6 | — | halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms | 只被已有测试杀死 |
| M60 | 登记表：非 interactive 也显示 | — | nonInteractiveSessionsNeverBecomeGhostColleagues、onlyInteractiveSessionsAreShown | 只被已有测试杀死 |
| M61 | 轮次边界：SessionEnd 不关调用（手工） | b9 | — | 杀死 |
| M62 | 出错：重试到上限 → 超过上限（手工，验证 d6） | d1、d6 | — | 杀死 |

---

## 4. 任务 2：token 交叉核对（`QA/tools/token_crosscheck.py`）

**规则**（只按用量表 `tokens.1m.py` 的语义自己重写，没有移植 Swift 代码）：只统计带 `"usage"` 的 assistant 行（用量表判据 `message.role`，任务书判据 `type`，两个都实现并报出不一致的行数）；要有 `message.id`、合法 timestamp、model 不是 `<synthetic>`、usage 非空；缓存写 = 5m + 1h，细分对不上总数就全当 5m；按 `message.id` 去重、每个字段取最大值；总量 = input + output + 缓存写 + 缓存读；桌面会话把 `cliSessionId` 与 `priorCliSessionIds` 对应的会话记录相加，子代理文件（含 `workflows/wf_*/`）也算。
**四个口径**：① 独立实现；② 直接 import 用量表原版的 `parse_line` + 它的合并规则（只读，不写缓存、不写 `.pyc`）；③ App 的 `ledger.json`——按 ledger 里记录的每个文件的 `offset` 只读到那个位置（文件在增长）；④ `buddyctl dump --once --json` 的 `tokens`，外加默认表格里的 `token(ctx)` 列（缩写，检查 `fmtTok` 排版）。文件在增长时用 `--snapshot DIR`：先把每个文件当前大小以内的 token 事实**去掉全部对话内容**（只留 `type / timestamp / sessionId / message.{id,role,model,usage}`；登记表和桌面元数据也只留认人和算 token 需要的字段，不带标题 / cwd / 本轮总结）冻结成一棵假 home，两边都读这份冻结的数据（我这一侧读的是**原文件**冻结时的大小，不是快照文件，所以也验证了快照的裁剪）。
**能对真实数据跑，也能对 FakeTree 假数据跑**（`--root`）；`--extra-host local_<uuid>` 可以把一个桌面会话（带 prior）当作活会话一起核对（登记表是合成的、只写在快照里，绝不写真实的 `~/.claude`）。

### 4.1 真实数据（2026-09-29 04:28，冻结快照；输入 / 输出 / 缓存写 / 缓存读 = 合计，消息数）

| 会话（pid / sid 前 8 位） | 文件 | 独立实现 | 用量表 `parse_line` | ledger.json（读到 offset） | dump `tokens` | dump 表格列 | 一致？ |
|---|---|---|---|---|---|---|---|
| 25245 / 8aab9e77 | 1 | 94/218197/293045/9487490 = **9,998,826**（47 条） | 同 | 同（47 条） | 同（47 条） | 10.0M | 是 |
| 35991 / 20c4bcc8（本会话，忙着，1 个主文件 + 10 个子代理文件） | 11 | 6140/6289195/14493696/1550678757 = **1,571,467,788**（3069 条） | 同（3069） | ledger 读到 offset：6132/6286643/14485753/1547568224 = 1,568,346,752（3065 条）——**独立实现在同一 offset 处也是这个数**（逐位一致） | 同独立实现（3069） | 1.57B | 是 |
| 65995 / d95629cf | 5（4 个子代理） | 446/369189/1396978/31362169 = **33,128,782**（204 条） | 同 | 同 | 同 | 33.1M | 是 |
| 80510 / cdc48c29 | 1 | 206/138872/875085/22591481 = **23,605,644**（102 条） | 同 | 同 | 同 | 23.6M | 是 |
| 桌面会话 local_3b2f8a28…（**带 prior**，`--extra-host`；不是活会话，登记表合成；取自另一次运行，文件不再增长） | 2 | 26/26291/60673/1105167 = **1,192,157**（13 条） | 同 | 无（有 prior 的组每次重扫，不写断点） | 同 | — | 是（README 里那个「两个文件合计，重叠那条只算一次」的数） |

结论：**每个会话四项分别、消息条数、合计都逐位一致**；忙着的那个会话在冻结的同一时刻两边读到同一个数；ledger 用「读到 offset 为止」的办法对上了。收工前（05:04）又用 `--run-dump --snapshot` 复核了一次，结论同样是「全部一致」（本会话那一行随着对话在涨：3327 条 / 1,737,257,991，ledger 读到 offset 处 3325 条 / 1,736,342,427，独立实现在同一 offset 处也是这个数；另外三个会话的数字和上表相同）。真实数据里跨会话共享的 `message.id` 为 0（全局去重把重复消息记给先扫到的那个会话，这里没有触发）；`role` 与 `type` 判据不一致的行数为 0。
**没有发现任何不一致，所以没有需要修的 token 相关代码，也没有相关回归测试要补**；这个交叉核对本身的回归测试是 `StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree`。

### 4.2 FakeTree 假数据（`py1`）
3 个会话（A 桌面：prior + 当前 + 子代理 + 重复消息 + 合成消息 + 多次写入取最大值；B 终端；C 下班工位），手算期望值 A = 5503、B = 26。独立实现 == 用量表 `parse_line` == 真的 dump 可执行文件 == 手算期望值；假 home 里还放了 `kind=job`、进程已死、`.key`（权限 000）、名字不对（`abc.json`、`.json.bak`）的登记文件，都不该被统计（`--liveness check`）。脚本输出里没有 `桌面标题A` / `终端自定义B` / `sleep 30` 之类的内容。

### 4.3 脚本自己的自检
`python3 QA/tools/token_crosscheck.py --selftest`：合成一棵树，手算期望值验证规则（多次写入取最大值、5m / 1h 细分、合成消息、没有 timestamp、usage 为空、非 assistant、没有换行的半行、`journal.jsonl` 不算、prior 相加、`kind=job` 不统计、跨会话共享的消息 id 报出来、冻结快照里没有任何 `SECRET-*`）。

---

## 5. 任务 3：dump 与登记表的一致性（`QA/tools/dump_vs_registry.py`）

逐个会话核对：pid、sessionId、hostSessionId、来源、key 前缀、liveness、`registryStatus`（== 登记表 status）、`waitingFor`、`phase`（== 登记表 status + 两个临时修正，独立用 hook 里的 Stop / UserPromptSubmit 的 ts 推算，只读 ts 和 ev）、标题（登记表 name → 桌面 title → custom-title → ai-title → cwd 文件夹名 → 「会话 <sid 前 8 位>」，只输出来自哪一级和一致 / 不一致）；集合：dump 的 present 会话 == 登记表里 `kind` 缺省或 interactive 且进程活着的会话（不多出、不漏掉、非 interactive 绝不出现）。跑 dump 前后各读一次登记表，中途变过的会话标记「不稳定」而不是「不一致」。

**真实数据（2026-09-29 04:28）**：dump 共 4 行（present 4，下班 / 离场 0）；多出 []，漏掉 []；4 个会话（pid 25245 / 35991 / 65995 / 80510，都是桌面会话，标题都来自登记表 `name`）的 10 项检查全部通过（`pid sessionId hostSessionId origin key liveness registryStatus waitingFor phase title`）；阶段推算 / dump：idle/idle、busy/busy、idle/idle、idle/idle。**全部一致**（收工前 05:04 又跑了一次，结果相同）。
**假数据（`py2`）**：桌面标题来自「桌面 title」、终端标题来自「custom-title」（会话记录里 key 顺序是乱的，第一版脚本的「只看行首 40 字节」预过滤漏掉了它，已改成整行判断——这是我自己脚本的 bug，测试抓到的）。`--selftest` 还覆盖：标题链每一级、阶段推算的两个临时修正、多出的 pid、漏掉的 pid、`kind=job` 出现在 dump 里。

### 5.1 「buddyctl dump 与 App 用的是同一条数据链路」的证明（`StateRuleChainTests`）
- **chain1 结构**：`DumpCommand.swift` 里只造 `SessionStore(options:)`（`SessionEngine.Options(paths:)` → `SessionStore.Options(engine:)` → `store.debugRows()`），源码里没有 `RegistryScanner` / `TokenLedger(` / `HookLogReader` / `TranscriptReader` / `DesktopMetaReader` / `IdentityResolver` / `ToolTracker` / `ActivityResolver`——它自己不读任何数据源、不判定任何状态；App 的 `RealProvider.make` 也是 `SessionEngine.Options(paths:)` → `EngineConfig.apply`（只覆盖设置里的四项）→ `SessionStore.Options(engine:)` → `SessionStore(options:)`；`buddyctl` / `buddydump` 的 `main.swift` 只转发 `runDumpCommand`。
- **chain2 行为**：同一棵假 home 树（会话用真 pid：测试进程和它的父进程，这样 dump 可执行文件里真的 `SystemProcessProbe` 也认为它们活着），真的 `buddyctl`（根包）/ `buddydump`（隔离包）`dump --once --poll --json --data-root <树>` 的输出，和 App 构造方式的 `SessionStore` 用 `DumpFormatter.renderJSON` 序列化的结果**逐字段相同**（`NSDictionary` 相等，A / B / C 三个会话），并且语义上也对：token 手算期望值、标题链、阶段、下班工位。
- **chain3**：App 构造方式的 `SessionStore.pollNow()` 快照和直接 `SessionEngine.poll()` 的快照在 seat / title / phase / activity / presence / tokens / pid / 叠加标记 / 各时间戳上逐字段相等。

---

## 6. 新增测试清单（完整函数名）

- `StateRuleTests`（52）：`a1_sameMillisecondParallelReadsPairFirstInFirstOut`、`a2_batchGapIsExactly250ms`、`a3_postFallsBackToTheEarliestOpenCallOfTheSameName`、`b1_stopEventClosesDanglingMainCalls`、`b2_userPromptSubmitClosesDanglingMainCalls`、`b3_sessionStartClosesDanglingMainCalls`、`b9_sessionEndClosesDanglingMainCalls`、`b4_registryTurningIdleClosesDanglingMainCalls`、`b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt`、`b6_danglingCallIsSupersededByTheNextBatch`、`b7_staleCallIsForceClosedOnlyAfterMoreThan30MinutesWhileRegistryIdle`、`b8_helperOwnedRecordsExpireAfter30Minutes`、`c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds`、`c2_aNewUserLineEndsTheRetryDisplay`、`d1_erroredByExhaustedRetriesAlone`、`d2_erroredBySyntheticApiErrorMessageAlone`、`d3_notErroredWhenRetriesRecovered`、`d4_notErroredWhenAnAssistantLineFollowsTheLastRetry`、`d5_noResponseRequestedAfterAnInterruptIsNotAnError`、`d6_erroredWinsOverFinishedWhenBothEvidencesExist`、`e1_transcriptInterruptLastsThreeSeconds`、`e2_hookInferredInterruptNeverShowsFinished`、`e3_withoutHooksTheEndOfATurnIsFinishedNotInterrupted`、`e4_aStopWithinTheGraceKeepsFinished`、`e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst`、`f1_finishedLastsFiveSeconds`、`f2_unreadClearsInExactlyThreeWays`、`f3_blockedOverlayFollowsTheDesktopSummary`、`g1_dozeAt10MinutesSleepAt45Minutes`、`h1_twoHoursOfBusyIsQuietNotDead`、`h2_quietThresholdAndItsResets`、`i1_departureDebounceThenReclaimAfter8Seconds`、`i2_dormantSeatOnlyForDesktopSessionsWithLiveUnarchivedMetadata`、`i3_theSameIdentityComingBackDuringTheLingerSitsInTheSameSeat`、`i4_pidReuseToleranceIsExactlyTwoSeconds`、`i5_aliveWithoutAStartTimeStaysPresent`、`i6_pidReuseGoesThroughTheSameDebounce`、`j1_desktopClearInTheSameProcessKeepsTheBuddy`、`j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume`、`j3_desktopResumeIsRecognizedThroughTheMetadataCliSessionIds`、`k1_foregroundTaskAttributionBoundaryAt150ms`、`k2_subagentStopIsOnlyASummaryHint`、`k3_unmatchedEventIsHeldForExactly400ms`、`l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen`、`l2_questionsAndPlanReview`、`l3_otherWaitsCarryTheRawText`、`m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds`、`m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle`、`n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine`、`n2_onlyPidJsonFilesAreOpened`、`o1_compactionEndsWhenTheHooksSayItEnded`、`o2_boundaryHookSlackIsFiveSeconds`。
- `StateRuleProcessTests`（4，真进程 / 真的 `SystemProcessProbe`，虚拟时钟）：`r1_realStartTimeAndLiveness`、`r2_epermCountsAsAlive`、`r3_recycledProcessIsDebouncedBy3Seconds`、`r4_pidReuseWithARealProcess`。
- `StateRuleChainTests`（5）：`chain1_sourcesShowTheSameSessionStoreChain`、`chain2_dumpExecutableMatchesTheAppChain`、`chain3_storeAndRawEngineAgree`、`py1_tokenCrosscheckScriptOnAFakeTree`、`py2_dumpVsRegistryScriptOnAFakeTree`。
- `StateRuleInvariantTests`（2 × 16 个种子）：`z1_referenceModelAgreesWithTheEngine`（独立参考模型：只按 5.1 阶段 / 5.2 工具追踪 / 5.3 前台归属 / 5.4 等待类写，和引擎在 500 步随机事件流——登记表翻转、Stop / 提示 / SessionStart、同一毫秒的 Pre 小批、Post、0.25 秒边界附近的间隔、几十秒、10–70 分钟的大跳——上逐步对拍阶段、主线程打开的调用个数和顺序、忙碌 / 等待时的动作；杀死了 M01 M02 M05 M06 M07 M09 M10 M19–M22 M41–M44 M46 M49 M50 M53 共 19 个变异）、`z2_snapshotInvariantsHoldUnderRandomReplay`（更脏的 400 步：会话记录里的打断 / 错误 / 重试 / 压缩、小助手写文件、桌面元数据、Notification、markSeen……；杀死 M13、M15；每一步检查：phase == activity.phase、idle 时没有 turnStartedAt、非 idle 时没有 idleSince / 未读 / blocked、quiet 只在 busy、并行个数 == 打开的主线程调用、提醒事件和动作对得上、一轮开始 / 结束事件配对、**空闲时间窗口**：打断 ≤ 3 秒、做完了 ≤ 5 秒、空闲 < 10 分钟、打盹 10–45 分钟、睡着 ≥ 45 分钟）。
- 支撑：`StateRuleKit`（`StateRuleTests.swift` 里；idleSession / startTurn / goto 等）；`BUDDY_REPO_ROOT` 环境变量可以指定项目根目录（私有沙箱里跑 chain 测试用）。

---

## 7. 已记录的偏离（实现和任务书不同，但 DESIGN.md / Core README 里有理由，不算 bug）

| 偏离 | 记录在哪 | 我的验证 |
|---|---|---|
| 「做完了」桌面会话等本轮总结：任务书最多 4 秒，实现 8 秒（App 层 `AlertCoordinator.summaryWait`；数据层没有等待逻辑，blocked 在元数据一更新就给出） | DESIGN.md「与任务书不一致」表；Core README | f3（blocked 7 秒后才落盘也亮、保持到下一轮） |
| 「出错」优先于「做完了」，并且一直保持到打盹（10 分钟）；任务书的顺序会让出错的一轮先闪 5 秒「做完了」 | Core README「我做的小决定」 | d1、d6、既有 `erroredTurnStaysErroredUntilItStartsDozing` |
| 被打断的 hook 推断先等 0.4 秒（`stopGrace`）没有 Stop 才判定 | Core README「我做的小决定」 | e2–e5（L-001 补上了宽限期内不能报错误结论） |
| 「登记表还是 busy 但 Stop 已到」才是常态（Stop 比登记表翻 idle 早 40–60 ms） | Core README「数据源实测结论」 | m2、e5（Stop 在登记表之前 60 ms 到） |
| `ExitPlanMode` / `AskUserQuestion` 的 Notification 文本也叫 "needs your permission to use X"，所以看打开的工具名：`ExitPlanMode` 开着 → 计划待审（不只在「提问」类等待下），`AskUserQuestion` 开着 → 提问 | Core README「数据源实测结论」 | l2 |
| 等批准的工具：Notification 点了名就取名字对得上的那个打开的调用（并行时不会张冠李戴），否则最新打开的，再否则解析 `use <T>` | Core README「我做的小决定」 | l1、既有 `notificationNamesTheToolAmongParallelOnes` |
| 缺 `kind` 的登记记录当 interactive；`pid` / `sessionId` 缺失的忽略；不认识的 `status` → nil | Core README「我做的小决定」 | 既有 `RegistryScannerTests` |
| 30 分钟兜底：小助手名下的记录一律丢；主线程的只在登记表 idle 时强制关 | Core README「我做的小决定」 | b7、b8（主线程那一半在引擎层不可达，见 N-2） |
| 会话记录 `stop_hook_summary` 只关「在它之前开始」的调用 | Core README「我做的小决定」 | b5 |
| 下班工位：启动时取 `lastActivityAt` 3 小时内、没归档、没有活进程的桌面会话，最多 4 个；满 12 小时 / 归档 / 元数据被删移除 | Core README | 既有 `dormantSeats…` 系列（M33 / M34 被它们杀死） |

---

## 8. 这一轮用真实日志核实的时序事实（不是 bug，但改变了对若干规则的信心）

| 事实（这台机器，2.1.284，4 个活会话的 hook 日志 / 会话记录） | 对哪条规则 |
|---|---|
| **压缩**：3 组 `PreCompact(auto)` → `SessionStart(compact)` 分别晚 103.4 / 87.9 / 91.5 秒；`PostCompact` 比 `SessionStart(compact)` 晚 20–30 毫秒；`compact_boundary`（会话记录）比 `SessionStart(compact)` 晚 40–70 毫秒；边界前 0.4 秒有一行 `isCompactSummary` 的 user 行；压缩开始时会话记录里什么都没有；边界后 2.4 / 3.4 / 3.8 秒才是第一条 assistant 行 | L-003 |
| **打断没有 Stop**：10 个 `[Request interrupted by user` 标记，最近的 Stop 事件都在 60 秒以外 | (e)：「hook 正常但没有 Stop」的推断成立 |
| **`stop_hook_summary` 与 Stop**：和 Stop 事件 1 : 1，比 Stop 晚 4–59 毫秒（各会话的中位数 4–8 毫秒） | (b) 的 `stop_hook_summary` 边界、(e) 的 `stopMarker` |
| **`api_error`**：25 行，`retryAttempt` 1–9 / `maxRetries` 10，`retryInMs` 512–39,720；相邻两次重试的间隔 ≈ 上一条的 `retryInMs`；没有一条到上限的样本 | (c)、(d)：字段与 `retryInMs + 15 秒` 的窗口一致；「出错」只能用合成 fixture 测 |
| **合成 assistant 行的形状**：2 条 `isApiErrorMessage: true`（`<synthetic>`、`stop_sequence`）、2 条 `isAbortedMidStream`（`stop_reason: null`）、1 条 `No response requested.`（`<synthetic>`、不是错误） | (d)、(e) 的解析假设都对 |
| **hook 日志独立回放**（`QA/tools/hooklog_replay.py`，把 4 个会话的日志按 5.2 独立回放一遍，所有 Pre 都当主线程；日志一直在增长，这是 04:4x 的一次）：Pre 4135 = Post 关 3746（名字 + detail 相同 3637、只能按名字配 109）+ 被取代 388 + 轮次边界 0 + 末尾残留 1（正在运行的那个 Bash）；找不到对应的 Post 331；同一毫秒的 Pre 对 5 个（「同一毫秒两个 Read」实测存在）；相邻 Pre 间隔在 240–260 毫秒的 21 个 | (a)(b)：规则自洽。0.25 秒附近确有 21 处间隔，但阈值不会因为浮点误差在边界上「抖」：毫秒时间戳相减时，0.25 秒和 3 秒恰好是 2^-22 秒（1.79e9 附近 double 的间距）的整数倍，25 万次随机基数下差恒等于 0.25 / 3.0；150 毫秒和 400 毫秒不是整数倍，会抖（`HelperAttributor` 已经按毫秒取整处理了 0.15 秒） |
| **Notification**：真实样本只有 AskUserQuestion（5 条）和 ExitPlanMode（5 条）的 "needs your permission to use X"（其余会话没有）；没有「真的权限提示」样本 | (l)：README 已记录，本轮没有新增 |
| **登记表**：4 个都是 `kind` = `interactive`、`entrypoint` = `claude-desktop`，`waitingFor` 都缺省；没有终端会话 | (n)：终端 / VS Code 路径仍只靠 fixture（README 已记录） |

---

## 9. 剩余风险

1. **晚到的证据不会回头改判**：`complete()` 之后 `pendingEnd` 就清了。登记表翻 idle 后 0.4 秒内没有 Stop / 打断行 / 错误行，会按「hook 正常 → 被打断」（或无 hook → 做完了）定下来；如果出错的证据（`api_error` 到上限、合成错误消息）比登记表晚 > 0.4 秒才落盘（主会话记录写盘可能延迟），就会被判成「被打断」而不是「出错」，且不会更正。真实日志里没有到上限的样本，无法量化。
2. **App 层的数字不在我的测试范围**：`AlertCoordinator` 的 1.5 秒、20 秒节流、8 秒等 blocked、30 秒最短用时在 App 目标里，BuddyCoreTests 测不到；别的代理新增了 `Tests/BuddyOfficeTests/AlertCoordinatorTests.swift`，我没有复核它的断言。数据层给它的输入我已经保证：宽限期内不再有假的 `.finished`（L-001）。
3. **终端 / VS Code 会话、真实的权限提示、`sandbox request` / `dialog open` / `goal proposal` / `worker request`、`turn_duration` 没有真实样本**：只靠 fixture。
4. **归属规则（5.3）本质是猜**：hook 里没有 agent_id；我的 z1 对拍验证了规则 1、2 在随机事件流里被正确实现，但规则 3（扣住 + 会话记录比对）只有确定性的场景测试。
5. **我的所有回放都走纯轮询引擎 + 虚拟时钟**：FSEvents 链路由已有的 `StoreTests` / `ReplayTests(--fsevents)` 覆盖，我没有重复。
6. **同一 `message.id` 出现在两个不同会话的文件里**（resume 复制历史）时，全局去重会把它记给先扫到的那个会话，各会话的合计取决于扫描顺序；真实数据里当前为 0 处，没有验证过这条路径的真实数据（`token_crosscheck.py` 会把它报出来）。
7. **测试基础设施**：多个 QA 同时在改同一个仓库，`swift build` 会因为「input file was modified during the build」偶发失败（不是产品问题）。我用私有沙箱（把源码 / 测试 rsync 到 `$TMPDIR`）绕开；官方命令本身在收工前反复因此失败（隔 20–30 秒重试），最后一次冷编译通过（63 / 63）。另外测试进程偶尔会被别人杀掉（现象见第 0 节「稳定性」一行，我用 `SIGTERM` / `SIGKILL` 自己复现过同样的日志截断 + `exit=1`），看到这种「没有汇总行的 `exit=1`」先重跑，不要当成测试失败。
8. 变异测试只覆盖数字和明显的分支（60 + 2 个），不是全部逻辑。

---

## 10. 怎么复现

```bash
# 测试（沙箱外）
cd ~/Desktop/编程项目/Buddy办公室
BUDDY_SCRATCH=.build-qa-logic scripts/dev.sh test --filter StateRule -j 2

# token 交叉核对（真实数据 / 冻结快照 / 假数据 / 自检）
python3 QA/tools/token_crosscheck.py
python3 QA/tools/token_crosscheck.py --run-dump --snapshot "$TMPDIR/tc-snap"      # 目录必须为空
python3 QA/tools/token_crosscheck.py --root <假 home> --liveness check --run-dump --json
python3 QA/tools/token_crosscheck.py --selftest

# dump 与登记表
python3 QA/tools/dump_vs_registry.py            # 需要 .build/release/buddyctl（已编译好的；不重新编）
python3 QA/tools/dump_vs_registry.py --selftest

# 真实 hook 日志的独立回放（只输出计数）
python3 QA/tools/hooklog_replay.py

# 变异测试（沙箱外，别和别的编译同时跑；只改副本）
python3 QA/tools/mutation_check.py --list
python3 QA/tools/mutation_check.py --only M02 M27 --json "$TMPDIR/mut.jsonl"
```
