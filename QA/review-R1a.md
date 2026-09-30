# 复查 R1a（数据层）

> 复查员：R1a　日期：2026-09-29　范围：`Sources/BuddyCore/**`、`Tests/BuddyCoreTests/**`、`scripts/hook-merge.py`、`安装.command`、`卸载.command`
> 方法：不采信之前的结论，自己逐行读代码，再用 scratch 副本里的实验证实（副本、编译产物、临时测试全在 `/private/tmp/claude-501/.../scratchpad/r1a/`）；**没有改项目目录里的任何文件**（只新建了这份报告）；没有碰真实的 `~/.claude/sessions`、没有连 socket、没有联网、没有按名字杀进程。
> 所有实验都用 `FakeClaudeTree` / 虚拟时钟 / 临时目录；数据层用我自己的隔离包（`Package.swift` 与 `.dev/core` 相同，BuddyCore 用 -Onone），`-j 2`。
> **时间线**：我的副本是 05:54 的快照，发现和实验都基于它。写这份报告的过程中（06:13–06:30）协调者已经按我的中间稿修了 R1a-01 / R1a-02 / R1a-03（见 `QA/issues-review.md`）；06:32 我重新同步了项目当前状态，逐条复核了这些修复，结果在 §1.1。文中的文件行号是 05:54 快照里的行号（`SessionEngine.swift` 现在因为多了一行注释，quiet 那行是 :438）。

## 1. 结论

**新发现 2 个 P2（产品）+ 1 个 P2（测试套件质量），没有新的 P0 / P1。三个都已经被协调者修掉，我在项目当前状态上重新复核过（§1.1）；此外有 5 条疑点（§3）和 12 条 P3（§5）。**

| 编号 | 严重度 | 一句话 |
|---|---|---|
| R1a-01 | P2 | 会话处于 busy 且 10 分钟没有任何新数据（长命令 / 卡住 / 合盖后醒来）时，引擎给出的 `nextWake` 永远在「过去」，`SessionStore` 从 1 次/秒变成约 140 次/秒空转（1 个会话：进程 CPU 0.1% → 1.7%–2.7%，定时器 ~140–200 Hz 唤醒），直到会话不再 busy |
| R1a-02 | P2 | `hook-merge.py`：`~/.claude/settings.json` 是符号链接（dotfiles 常见）时，install / uninstall 会把链接换成一个普通文件，真正的目标文件没被改 |
| R1a-03 | P2（测试质量，不是产品缺陷） | 整套 BuddyCoreTests 在机器负载高时会**假失败**（至少 6 个 TokenLedger 相关测试超时）；同时「`nextWake` 必须在未来」「静止的 busy 会话不空转」这类不变量没有任何测试，所以 R1a-01 一直没被抓到；`hookDropoutGap` 之类的阈值没有被测试钉住（变异测试存活） |

已给出经验证的修法：R1a-01 只需改一行（`if phase == .busy, !st.quiet { wakeAt(...) }`）——我在独立副本里改完，三个复现测试全部转绿、随机时间线 0 违规、现有 408 个测试不受影响（见 §2）。

### 1.1 修复后的复核（项目当前状态，06:32–06:35 我自己重跑的）

| 项 | 复核结果 |
|---|---|
| R1a-01 修复（`SessionEngine.swift:438`：`if phase == .busy && !st.quiet { wakeAt(…) }`） | 与我建议的一行完全一致。当前状态下我的实验全部通过：引擎层 `nextWake − now = +1.0 秒`（原来 −600）；真实 SessionStore 的 tick 频率 busy 30 秒 / busy 11 分钟（quiet）都是 2 次 `now()`/秒（原来 285）；随机时间线（60 种子 × 260 步）`nextWake` 违规 0 次（原来 2936）、事件配对违规 0 次；整套 416 个测试（含协调者新增的 `ReviewRegressionTests`、我的 5 个实验测试，跳过 ReplayTests）全部通过。协调者的两条回归测试（`r1a01_quietBusySessionNeverAsksForAnImmediateRepoll` 在 dt = 599…7200 秒逐点断言、`r1a01_nextWakeIsNeverInThePastOnATimeline`）我也看过，断言是对的（包括「变 quiet 之前仍要在那一刻醒来」，防修过头）。 |
| R1a-02 修复（`hook-merge.py` 新增 `resolve()`，备份仍放在链接旁边） | 我的复现脚本现在：install / status / uninstall 之后链接都还在、真实文件被改对、备份在链接旁边；链接链（link → link → 真实文件）改到最终的真实文件、两级链接都保持；指向存在的目录但文件不存在的悬空链接：在目标位置新建文件、链接保持；指向不存在的目录：拒绝（退出码 2）、什么都不建。`python3 Tests/hook_merge_test.py`：15 个测试全过。没有发现遗留问题。 |
| R1a-03 修复 | 放宽了 34 处等待后台扫描的超时（→ 60 秒；C-024 → 600 秒）、新增 `r1a03_hookDropoutBoundaryIsFifteenSeconds`（14.9 / 15.1 秒）、FSEvents 起不来的跳过现在会打印一句可被完整回归统计的话。**没补的**：§6 里另外 4 个存活变异（`doneLinger` 30 秒、`compactStaleAfter` 15 分钟、`TokenLedger.recentKeep` 24、`TranscriptFacts.maxOpen` 64）仍然没有边界测试；「静止 / quiet 时 SessionStore tick 频率」的 store 层测试也没加（引擎层的 `nextWake` 测试已经能挡住这个 bug，所以只是建议）。 |

## 2. 发现

### R1a-01（P2）busy 且 quiet 的会话让 `nextWake` 永远在过去 → SessionStore 空转

**现象**
任何一个会话只要满足：登记表 status 是 busy（或临时修正后是 busy），并且 10 分钟（`quietAfter`）内 hook 和会话记录都没有增长——一个 10 分钟以上的长命令（构建 / 测试 / `sleep`）、卡住的 MCP 调用、合盖睡眠后醒来的会话、桌面 App 里等后台任务——引擎每次 `poll()` 返回的 `nextWake` 都是一个已经过去的时间。`SessionStore.arm()`（`SessionStore.swift:165-169`）里 `delay = min(delay, max(0.005, w - now))`，负数被夹成 5 ms，于是 ingest 队列不停地跑完整的 `engine.poll()`（登记表 stat + 每个会话的 hook / 会话记录 / 子代理 stat + 快照拼装 + `ledger.totals`），FSEvents 模式下本来的兜底间隔是 1 秒。主线程不受影响（快照没变就不回调，只有 1 Hz 心跳），受影响的是 ingest 队列的 CPU 和整机的定时器唤醒（耗电、无法进入低功耗）。纯轮询模式（50 / 100 ms）下同样从 20 Hz 涨到 ~140–200 Hz。

**实测（scratch 副本，测试见附录 A）**

| 状态 | `now()` 调用 / 秒（每次 poll 2 次） | 进程 CPU |
|---|---|---|
| busy 30 秒（未 quiet） | 2（≈ 1 次 poll / 秒） | 0.1% |
| busy 11 分钟（quiet，虚拟时钟跳 11 分钟） | 265–285（≈ 135–142 次 poll / 秒） | 1.7%–2.7%（1 个会话：-O 编译 1.9% / 1.7%，-Onone 2.7%；会话越多越贵） |

（BuddyCore 用 -O 编译（App 里就是这样）也一样：CPU 主要花在每次 poll 的十几个 stat 和队列调度上，不是 -Onone 的问题。机器很忙时 ingest 队列（utility）拿不到 CPU，只能跑到 ~25 次/秒（一次负载 19–35 时测到 51 次 `now()`/秒、0.6%），但仍比静止时的 1 次/秒高一到两个数量级。）

引擎层：`nextWake − now = −600 秒`（恰好是超过 `quietAfter` 的那 600 秒）。

**证明它是唯一来源**：合法数据的随机时间线（60 个种子 × 260 步：两个会话、登记表状态、hook、会话记录、进程死活、桌面元数据、时钟跳 0.02 秒～50 分钟）每步检查 `nextWake == nil || nextWake > now`：违反 2936 次，**全部**发生在 `snapshot.quiet == true` 时，其余状态 0 次。

**根因**
`Sources/BuddyCore/Fusion/SessionEngine.swift:436-437`

```swift
st.quiet = phase == .busy && now.timeIntervalSince(st.lastGrowthAt) >= options.quietAfter
if phase == .busy { wakeAt(st.lastGrowthAt.addingTimeInterval(options.quietAfter)) }   // quiet 之后这个时间永远 ≤ now
```

`wakeAt`（:192）不过滤过去的时间（引擎里其它来源——`ActivityResolver.consider` 有 `t > now` 的过滤，别的 `wakeAt` 调用点本来就是未来的时间——只有这一处会落在过去）。README 里「6 个都在忙 CPU 1.0%」的性能测量、`replay` 里「忙了 61 分钟仍是 busy」都没有覆盖「quiet 之后 CPU」这一项。

**为什么现有测试没抓到**：`nextWake` 只在几个具体场景里被断言——`EngineScenarioTests:390-394`（做完了 5 秒：只测上界和非 nil）、`StateRuleTests:1044`（半截登记表：> 0 且 ≤ 50 ms）、`HelperAttributionTests:192` / `SpecTraceCoreTests:570`（只测非 nil）——没有一个覆盖「busy 且 quiet」，也没有「任何状态下 `nextWake` 都在未来」的通用不变量；`StoreTests` 里的会话一直在增长，从没进过 quiet，也没有测「静止 / quiet 时的 tick 频率」。

**状态：已修**（`SessionEngine.swift:438`，与下面的建议一致，复核见 §1.1）。**建议修法（已验证）**：`SessionEngine.swift:437` 改成 `if phase == .busy, !st.quiet { wakeAt(...) }`（进入 quiet 之后本来就靠增长触发的 poll 来退出 quiet）；更稳的是在 `wakeAt` 里直接忽略 `t <= now`。再补两条测试：随机时间线 + `nextWake == nil || nextWake > now`（附录 A.3，可原样收进 `FuzzEngineTests`）、SessionStore 层「busy 且 quiet 时 tick 频率与静止时同一量级」（附录 A.2）。
验证：在独立副本里只改这一行——`quietBusyNextWakeIsInThePast` 通过（`nextWake − now = 1.0 s`，是 1 秒一次的存活检查）、`quietBusySessionMakesTheStoreSpin` 通过（quiet 前后都是 2 次 `now()`/秒）、随机时间线 0 违规、事件配对不变量 0 违规；在这个修复副本里跑现有套件：408 个测试（跳过 ReplayTests 和我的 R1a 实验）全部通过。（ReplayTests 没跑：它走真实的 FSEvents 链路，要 40–60 秒，且我没改它涉及的行为。）

---

### R1a-02（P2）`hook-merge.py` 遇到符号链接的 settings.json 会把链接换成普通文件

**现象**
`~/.claude/settings.json` 是指向 dotfiles 仓库的符号链接（很常见）时：`install` 之后链接没了，变成一个普通文件；dotfiles 里真正的那份**没有**加上 hook；`uninstall` 又会再写一次普通文件。结果：用户的 dotfiles 管理被悄悄破坏（之后重新 `stow` / 重新链接会盖掉 hook，或者两份内容分叉）。备份文件内容是对的，脚本也报「已添加」，没有任何提示。这位用户当前的 settings.json 是普通文件（0600），所以对他自己没有影响，但安装包是要给别人用的。

**复现（我在 scratch 里跑过，输出如下）**
```bash
S=$(mktemp -d); cd $S; mkdir -p dotfiles home/.claude
printf '{\n  "theme": "dark"\n}\n' > dotfiles/settings.json
ln -s ../../dotfiles/settings.json home/.claude/settings.json
python3 scripts/hook-merge.py install --settings home/.claude/settings.json
ls -l home/.claude/            # settings.json 现在是 -rw-r--r--（普通文件），不再是 lrwxr-xr-x
grep -c local.buddy-office dotfiles/settings.json     # 0：真正的目标文件没被改
grep -c local.buddy-office home/.claude/settings.json # 1
```
实测输出：`已添加 SessionStart hook。备份：home/.claude/settings.json.bak-…`，`dotfiles/settings.json` 的 hook 计数 0、链接位置的文件计数 1、链接已被替换。

**根因**：`scripts/hook-merge.py` 的 `write_atomic()`：在 `dirname(abspath(path))`（链接所在目录）建临时文件，最后 `os.replace(tmp, path)`——`path` 是链接本身，`replace` 替换的是链接而不是它指向的文件。`backup()` 和 `os.stat(path)` 是跟随链接的，所以备份内容 / 权限都对，只有最后一步不对。

**状态：已修**（新增 `resolve()`，复核见 §1.1）。**建议修法**：`main()` 里在所有操作之前 `path = os.path.realpath(path)`（临时文件建在真实文件所在目录、`replace` 真实路径；悬空链接也会落到目标位置）；或者 `os.path.islink(path)` 时拒绝并提示手动添加。加一条测试（`hook-merge.py` 现在没有自动化测试）。

---

### R1a-03（P2，测试质量）BuddyCoreTests 在负载高时假失败；关键不变量没有测试；阈值没被钉住

**(a) 负载下的假失败（依赖真实调度的测试）**
完整跑一遍（411 个测试，我的隔离包，补齐目录布局之后）：机器较空闲时 67 秒，全绿；在修复副本里（负载 ~35）再跑一次 408 个（跳过 ReplayTests），30 秒，全绿。另一次是在机器负载很高（`uptime` 负载 40–58：别的编译 + 我的变异测试同时在跑，并且带着 `TZ=Pacific/Chatham LC_ALL=de_DE`）时跑，出现失败：`C-005`（`ledger.json` 天文数字）、`C-028`（`onChange` 里 `flush()`）、`C-024`（多线程原子写）、`4.3-42`（扫描队列 QoS）、`aTerminalSessionOnlyCountsItsCurrentSessionId`、`desktopTokensMergeThePriorCliSessionsAndSubagents`（输出被我截到前 12 行，至少这 6 个）。**同样的测试单独跑（同一时刻、同样的高负载）0.02–0.14 秒全过**，换 `TZ=Pacific/Chatham LC_ALL=de_DE` 单独跑也全过 → 与时区 / 区域无关，与整机负载 + 套件内并行有关。
根因（推断，没有单独复现「高负载 + 不带 TZ」这一组合）：这些测试用默认的 `TokenLedger`（`DispatchQueue(qos: .background)`）扫描，再 `waitUntilIdle(timeout: 20)` / `sem.wait(timeout:)`；测试进程同时并行跑 35 个套件（模糊测试很吃 CPU），`.background` 队列在整机繁忙时会被饿死，超时就判失败。表现是「有人在编译时 `swift test` 随机红」，会让人习惯性忽略红灯。
建议：需要等扫描的测试统一用 `TokenLedger(…, queue: DispatchQueue(label:…, qos: .userInitiated))`（初始化本来就有 `queue:` 参数），只留一条专门测默认队列是 `.background` 的（`4.3-42` 只读队列自己的 QoS，不必等它跑）；`waitUntilIdle` 的超时取「不超时」或很大的值。

**(b) 没有测试的不变量**：`nextWake > now`（见 R1a-01）、静止会话的 SessionStore tick 频率（同上）、`hook-merge.py` 完全没有自动化测试（符号链接 / 只读 / 并发 / 非法 JSON / 往返）。

**(c) 变异测试（把阈值 ±1 单位，跑现有套件，跳过 ReplayTests）**：见 §6；已出结果里 `hookDropoutGap 15→16` **存活**——没有任何测试卡在 15 秒这个边界上（设计文档 §13 把它写成了规格）。

**(d) 静默通过的分支**：`StoreTests.swift:195-198`（FSEvents 起不来就 `return`，只打印一句「跳过」）、`FuzzWatcherTests.swift:19、46`（`guard w.start() else { return }`）。这些在沙箱里会「绿」但什么也没验证，应该用 `Issue.record` / 条件跳过让它在报告里可见。

**(f) 混沌模糊测试只在 3 个固定种子上验证过「恢复」**：我把 `FuzzEngineTests.engineSurvivesExtremeValuesEverywhere` 的种子换成 24 个新的（scratch 副本，每个 500 步的极端数据 + 时间大跳跃）：0 次崩溃 / 卡死，`checkSnapshots` 的全部快照不变量 0 违规；1 个种子（0xA1A010A1）在最后的「恢复」断言上失败——`乱七八糟之后应该恢复出「Read」：retrying(attempt: 0, max: 0)`。查下来**不是引擎错误，是断言过严**：混沌阶段最后留下一条 13 秒前的 `api_error`（`retryInMs = 0`），规则是「api_error 之后 retryInMs + 15 秒内没有新的 assistant / user 行 → 重试中」，恢复阶段只写了 hook（UserPromptSubmit / PreToolUse），没有写会话记录里的 user 行，所以按规则确实还在「重试中」（真实流程里用户的新提示会先落一条 user 行结束重试）。建议恢复阶段先 `h.advance(20)`，或者同时写一条会话记录 user 行。顺带的设计注记（P3）：hook 里比 `api_error` 更新的 UserPromptSubmit / PreToolUse 不会取消「重试中」，只有会话记录里更新的 assistant / user 行才会。

**(e) 文档里的隔离包跑法现在不是全绿**：`Sources/BuddyCore/README.md` 和 `scripts/dev.sh` 的注释都建议用 `BUDDY_PKG=.dev/core` 跑数据层测试。`.dev/core` 里只链了 BuddyCore / buddydump，而 `SourceAuditCoreTests`（2 个）和 `StateRuleChainTests`（3 个）会从「项目根目录」读 `Sources/PixelKit|BuddyStage|BuddyOffice`、`QA/tools/*.py`——我用等价布局第一次完整跑就是这 5 个失败（补齐链接后 411 个全绿）。根包（不设 `BUDDY_PKG`）不受影响。建议：这几个测试在找不到根目录的兄弟目录时 `Issue.record` 说明「请用根包跑」，或者把 `.dev/core` 补上 `QA` / 其它 `Sources` 的链接。

## 3. 疑点（没能复现成产品问题，或取决于我无法验证的外部行为）

- **S-1 Stop 事件之后又有新工具，而登记表一直 busy**：`ActivityResolver.phase()` 的临时修正 2（`base == .busy` 且存在 `stop > statusUpdatedAt && stop >= lastPromptAt` → 当作 idle）只看时间，不看 Stop 之后有没有新的 Pre / Post。我用引擎复现了「登记表 busy（`statusUpdatedAt` 不变）→ Stop → 之后 PreToolUse」：活动是 `finished/idle`，11 分钟后变 `dozing`，尽管有一个工具一直开着（附录 A.4）。是否会在真实使用中出现，取决于 Claude Code 在「Stop hook 拦下（decision: block）、Claude 继续干活」时登记表怎么写：如果它不重写 `status/statusUpdatedAt`，就会出现；如果会翻 idle→busy 并更新 `statusUpdatedAt`，就不会。我没有这类真实数据，所以只报疑点。若要防：在临时修正 2 里再加一个条件「Stop 之后没有更新的 Pre / Post / 会话记录增长」。
- **S-2 同一个 sessionId 在两个项目目录里各有一份会话记录**：`TranscriptLocator.find`（`TranscriptReader.swift:217-225`）按 `readdir` 顺序取第一个，没有按修改时间择优，并且结果被 `transcriptPathCache` 永久缓存。如果 Claude Code 在「换目录 resume」时复制了会话记录，可能读到旧副本。我没有见过这种数据。
- **S-3 `DesktopMetaReader.rebuildCliIndex`**（`:149-154`）：同一个 prior sessionId 出现在两个桌面元数据文件里（复制 / 分叉出来的会话）时，`for (host, e) in index` 的遍历顺序每次进程启动都不一样（Swift 字典哈希种子随机），归到哪个 host 不确定；只影响「这个 id 不是任何元数据的当前会话」的情形。没有复现成可见错误。
- **S-4 token 去重跨重启**：某会话先以单文件组登记（从账本断点恢复，去重表里只有该文件最近 24 条消息），同一次运行里桌面元数据又出现 `prior=[A]`、`cli=B`（组变成 `[A, B]`）时，B 里复制自 A 的**更早的**消息不会被去重。README 实测 resume 只复制 1 条 message.id，所以实际影响 ≤ 1 条消息的量，没有构造复现（重启后一次性登记 `[A, B]` 的路径是正确的：两个文件都从 0 重扫）。

- **S-5 `pidDomain` 只解析、不参与存活判断**：`RegistryRecord.pidDomain`（`RegistryScanner.swift:216`）从没被引擎用到；`kill(pid, 0)` / `sysctl` 探测的永远是宿主的 pid 空间。如果 `~/.claude` 被挂进容器 / 虚拟机 / 远程环境（devcontainer 常见），登记表里会有 `pidDomain` 不是 `darwin` 的记录：pid 在宿主上不存在 → 判死（那个会话在办公室里看不到）；恰好撞上一个宿主进程时，有 `procStart` 会因启动时间对不上判 `reused`（安全），没有 `procStart` 就会被当成活的（幽灵同事）。我这里没有这类真实记录，只是读代码看出来的，不确定实际会不会出现。

## 4. 已检查、没问题（都是我自己读过代码 / 跑过实验的项，一行一条）

**读过的文件（逐行）**：`JSONLTailer`、`FileIO`、`TimeUtil`、`Paths`、`SafeJSON`、`LineSanitizer`、`HookLogReader`、`TranscriptLine`、`TranscriptReader`、`TokenLedger`、`RegistryScanner`、`ProcessProbe`、`DesktopMetaReader`、`SubagentReader`、`ToolTracker`、`HelperAttributor`、`ToolCatalog`、`ActivityResolver`、`BuddyState`、`SessionSignals`、`IdentityResolver`、`SessionEngine`（全部 1063 行）、`SessionStore`、`FileWatcher`、`BuddySnapshot`、`Activity`、`Hashing`、`OpenAudit`；`DumpCommand` / `ReplayCommand` 的参数与目录安全部分；`FakeTree` 的接口；`hook-merge.py`、`安装.command`、`卸载.command`、`build-app.sh`。

**增量读取（`JSONLTailer`）**
- 半行：`consume()` 里 pending / skipping / 块边界的三种组合（无换行块、恰好 `maxLineBytes`、`maxLineBytes+1` 后接换行）逐一推演，交付 / 丢弃结果与规格一致。
- CRLF：`deliver()` 去掉行尾 `\r`，只有 `\r` 的行当空行丢掉；BOM：不处理，只会让「文件开头带 BOM 的第一行」解析失败（数据源都是 Claude Code / ccmon 写的，没有 BOM 来源）→ P3。
- 截断 / 轮转 / inode：stat 与 fstat 各核对一次，`size < offset` 与 inode 变化都会 reset；同 inode 原地重写且更长——已知限制（QA 剩余风险 2），会话记录 / hook 文件是只追加的，不成立。
- `seekToTail`：`window` 负数夹 0、`start - 1` 不会下溢（`size > window` 时 `start ≥ 1`）、起点在行中间时跳过半行；`committedOffset` 在 skipping 时不是行首——从账本恢复到这里会把一条超长行的后半段当一行解析，`SafeJSON.object` 要求顶层是对象，实际读不出东西，无害。
- 资源上界：块缓冲随读随放、`pending` 超过 64 KiB 容量就释放、`HookLogReader` 一次最多 20000 个事件（摊还 O(1) 丢旧的）。

**时间 / 整数**
- `TimeUtil`：`parseISO` 的所有下标都有长度保护（时区偏移 `d2(idx+1/3/4)` 逐个核对）、范围夹在 2000–2200；`parseProcStart` 年份 1971–9999；`millis(_:)` 饱和；`formatProcStart` / `formatISO` 的下标范围（星期 0–6、月 1–12）。
- **`procStart` 是 UTC 的假设**：这台机器是 PDT（UTC-7），README 里实测「与 sysctl 的 p_starttime 一致」，所以不是「恰好在 UTC 时区才对」；容差 2 秒；DST 不影响（UTC）。数据层没有任何 `Calendar` / `DateFormatter` / `TimeZone`（grep 过）。
- 时区 / 区域：整套测试在 `TZ=Pacific/Chatham LC_ALL=de_DE.UTF-8`（+12:45 / 夏令时 +13:45，逗号小数）下跑了一遍：我看到的失败（输出只看了前 12 行）全是 TokenLedger / 后台队列相关的负载假失败（R1a-03(a)），其中两个代表性的测试用同样的 TZ / 区域单独跑全过；数据层本身也没有任何 `Calendar` / `DateFormatter` / `TimeZone` 用法可以受影响。
- 整数换算：`Int(Double)` / `UInt32(clamping:)` / `sat()` / `intValue`（≤ 2^40）/ `restoredCount`（≤ 2^50）/ `TokenBreakdown.total` 饱和加；`Int32(name.dropLast(5))` 超出返回 nil；`pid` 校验 1…Int32.max。

**登记表 / 进程 / 身份**
- 只 stat / open 匹配 `^\d+\.json$` 的文件（`Paths.isRegistryFileName` ≤ 10 位 ASCII 数字），`.key` 连 stat 都不碰；`FileIO.open` 的三层保险（名字 / `realpath` / `F_GETPATH`）+ 只开普通文件 + `O_NONBLOCK`；`FileIO` 是唯一读入口（`SourceAuditCoreTests` 守着，我在完整目录布局下跑过：通过）。
- `RegistryScanner`：写了一半 → 保留上一份好记录、50 ms 重试 ≤ 5 次；`recentlyModified` 防同刻度写入；目录消失 → 保持旧记录；文件名 pid 为准。
- `ProcessProbe`：`kill(pid,0)` 的 ESRCH / EPERM / 其它三分支；`classify` 的 `.unknown → alive`、`procStart == nil → alive`；不因时间旧判死。**注意**（P3）：僵尸进程（`p_stat == SZOMB`）`kill(pid,0)` 返回 0，会被当成活的——只在父进程不 wait 时出现。
- `IdentityResolver`：别名归属顺序 host → proc → sid → 元数据 → 新建；别名上限（host 6 / sid 30 / proc 4）与 `aliasIndex` 一致性；7 天保留只在存盘时清理、活会话每 10 分钟 touch；工位分配 `occupied` 含离场未收回的；`compressSeats` 只在首次 poll。
- 隐私 / 落盘：数据层只写两个文件（`identities.json`：key / 别名 / 工位 / 盐；`ledger.json`：会话记录路径 + 断点 + 计数），都在 `~/Library/Application Support/BuddyOffice/`；没有任何 `print` / `NSLog` / 日志（grep 过，工具目录除外）；用户输入（UserPromptSubmit 的 extra）在解析时置空、AskUserQuestion 的 detail 置空；唯一会读到用户可能带密钥的文件是 `settings.json`（`detectHookInSettings`，≤ 4 MiB，只看有没有 `hook.sh`，只在内存里解析）。
- `aliveRecords` / `reconcile`：同 key 多条记录取 `startedAt` 最新；`resolvedKeys` 用（pid、sessionId、host、procStart、metaVersion）做签名；离场防抖 3 秒、非下班工位 8 秒收回、下班工位 12 小时 / 最多 4 个。

**状态机（时序，虚拟时钟）**
- `nextWake`：全部 15 个 `wakeAt` / `consider` 调用点逐个推演 + 随机时间线实测：**除 R1a-01 外全部 > now**。
- 事件配对不变量（60 种子 × 260 步随机合法时间线：`arrived/departed` 交替、`needsUser/needsUserCleared` 配对、`turnStarted` 不连发、`turnFinished` 不会没有开始就出现；到场 / 离场后允许「未知」状态）：0 违规。
- 一轮结束的判定（`pendingEnd` / `classify` / `finalizePendingEnd`）：证据不够时不先报「做完了」，`stopGrace` 到点后 `wakeAt` 在未来；`estimateTurnStart` 用 `su >= idleSince` 挡住旧值；`hookActive` 三个条件。
- `ToolTracker`：批次（0.25 秒）/ 轮次边界只关「边界时刻及之前开始的」/ 30 分钟兜底 / 512 上界 / FIFO 配对；`HelperAttributor`：扣留最多 400 ms 且不会被未来时间戳卡死（`min(event.ts, firstSeen)`）、`claimed` 600 秒清理、`foregroundGap` 用毫秒取整比较。

**账本 / 并发**
- `TokenLedger`：去重（每字段取最大、差额记到最早的文件）、断点（`committedOffset` + 最近 24 条）、`resetStats` 清掉该文件的去重条目、`refreshDetached` 只在扫描队列上做、`flush()` 在扫描队列上不 `sync`、`totals` / `version` 都过锁；所有锁的持有区间内没有再取别的锁（无死锁环）；`checkpoint` 与扫描在同一个串行队列，不会读到半行状态。
- `SessionStore`：`start` / `stop` 的串行顺序（`stop` 用 `queue.sync`，`start` 是 `async`，先后顺序有保证）、`poke` 合并（40 ms 间隔）、20 Hz 限速 + 1 Hz 心跳（实测静止时 2 次 `now()`/秒 ≈ 1 次 poll/秒，与兜底间隔 1 秒一致）、`[weak self]` 全覆盖、`FileWatcher` 的 Create/Start/Stop/Invalidate/Release 成对、`shouldPoke` 按目录边界匹配。

**`hook-merge.py` / 安装脚本（实验）**
- 6 个 `install` 并发：最终只有 1 个 hook（`groups: 2` = 用户原有的 + 我们的），没有重复、没有损坏；`uninstall` 往返后内容还原（格式被规范化，见 P3）；非法 JSON（尾逗号）/ 顶层是数组 / `hooks` 是数组或 null / `SessionStart` 不是数组一律 exit 2 且文件哈希不变（逐个跑过）；空文件当 `{}`；目录不可写 exit 1 且没有留下临时文件 / 备份；权限保持（0600 → 0600）；备份不覆盖（同一秒重名加序号）；写完读回校验 + `os.replace` 原子替换；临时文件在同目录、按 pid 命名、`finally` 里清理。
- `卸载.command` 的 `[ "$yn" = "y" ] || [ "$yn" = "Y" ] && DEL=1` 是 `(A || B) && C`，符合预期；`--unregister-login` 在 `main.swift` 第 4 行处理并 `exit(0)`，不会把 GUI 拉起来卡住卸载；`replay --root` 只接受空目录 / 不存在的目录，且只删自己建的临时目录。

**测试套件本身**
- 完整跑：411 个测试、35 个套件，隔离包里全绿（要把 `Sources/*`、`QA/`、`DESIGN.md` 也链进隔离包；只链 BuddyCore 的 `.dev/core` 布局会有 5 个失败，见 R1a-03(e)）。
- 静态扫描：没有 `withKnownIssue`、没有 `.disabled` / `.enabled(if:)`；182 个可解析的 `@Test` 里只有 3 个没有断言关键字，都不是空测试（一个是嵌套函数名撞了、一个是「不崩溃」的专项、一个是审计器自测）。

## 5. P3（一行一条）

1. `hook-merge.py` 整体重写会规范化用户的 JSON 排版（缩进 2 空格、CRLF→LF；键顺序保留，只保留末尾换行）。
2. `hook-merge.py` 的临时文件 / 备份先按默认 umask（0644）创建、写完内容再 `chmod`，`~/.claude` 是 0755，存在一个极短的窗口里其它本机用户能读到 settings.json 的内容（可能带 env 密钥）。
3. `hook-merge.py --settings` 是最后一个参数时 `IndexError` 回溯（仅测试用开关）。
4. `hook-merge.py` 遇到带 UTF-8 BOM 的 settings.json 会以「不是合法 JSON」拒绝（安全，但提示不准）。
5. `scripts/build-app.sh`：`swift build … | tail -4` 在 `set -e` 下没有 `pipefail`，编译失败被吞掉，只靠「二进制存在」判断；有旧的 `.build/release/BuddyOffice` 时会把旧版本打包安装（`安装.command` 依赖它）。
6. `安装.command`：`rm -rf "$DEST"` 之后 `mv "$STAGE" "$DEST"` 失败就没有 App 了（没有回滚）。
7. `TokenLedger.writeLedger`：仍被跟踪但还没扫完的文件（启动后立刻退出）的旧断点会被丢掉（`files[k] == nil` 条件），下次启动重扫，只是慢一点；`writeLedger` 持锁时对每个旧断点 `stat` 一次（几千个断点时几十毫秒，`totals()` 会被挡一下）。
8. `FileWatcher.start()`：`~/.claude` 启动时不存在（Claude Code 还没装）则 FSEvents 起不来，整个运行期停在 50–100 ms 轮询。
9. `SessionEngine.bootstrapDormants`：首次 poll 时登记表恰好读不出来，会把实际在跑的桌面会话先当成下班工位，再「走回来」。
10. `ProcessProbe`：僵尸进程被当成活的（见上）。
11. 测试里几处「FSEvents 起不来就静默 return」的分支（见 R1a-03(d)）。
12. `hook-merge.py`：用户特意设成只读（0444）的 settings.json 也会被替换（模式保持 0444，只要目录可写就能 `os.replace`）——通常无害，但绕过了「只读保护」的意图。

## 6. 变异测试（阈值 ±1 单位，现有套件，跳过 ReplayTests；`SURVIVED` = 没有任何测试发现）

做法：在 scratch 副本里每次只改一处（常量 ±1 单位，或一个比较符 `<`→`<=`、`>`→`>=`、`max`→`min`），跑现有套件（408 个，跳过 ReplayTests），看有没有测试变红。「非抖动杀死」= 杀死它的测试里至少有一个不是 R1a-03(a) 那类负载假失败。全部 22 个变异 + 1 个我建议的修复（最后一行）：

| # | 变异 | 结果 | 杀死它的代表测试 |
|---|---|---|---|
| 1 | `awayLinger` 8→9 | 杀死 | `i1`（防抖 3 秒 / 8 秒收回）、`j2`、`aFreedSeatIsReusedByTheNextNewcomer` |
| 2 | `quietAfter` 10→11 分钟 | 杀死 | `h2`（quiet 恰好 10 分钟） |
| 3 | **`hookDropoutGap` 15→16 秒** | **存活** | — （`HookDropoutTests` 只测 20.5 秒和 30 分钟，没有测 15 秒边界） |
| 4 | `dormantRecent` 3 小时→4 小时 | 杀死 | `5.5-13`（2:59:59 进、3:00:01 不进） |
| 5 | `dormantExpire` 12→13 小时 | 杀死 | `dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted` |
| 6 | `HelperAttributor.foregroundGap` 0.15→0.2 | 杀死 | `k1`、`z1`（参考模型对拍） |
| 7 | `ToolTracker.batchGap` 0.25→0.3 | 杀死 | `a2`、`z1` |
| 8 | **`SubagentReader.doneLinger` 30→31 秒** | **存活** | — （README「完成后继续报告 30 秒」没有边界测试） |
| 9 | `SubagentReader.activeWindow` 90→91 | 杀死 | `helperStopsBeingActiveAfter90SecondsWithoutWrites` |
| 10 | `ProcessProbe.startTolerance` 2→3 | 杀死 | `i4`、`i6`、`r1` |
| 11 | `IdentityResolver.retention` 7→8 天 | 杀死 | `identitiesAreForgottenAfterSevenDays` |
| 12 | `RegistryScanner.maxRetries` 5→6 | 杀死 | `halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms` |
| 13 | `TokenLedger.persistInterval` 30→31 | 杀死 | `4.3-40`（10 / 29.9 / 30.1 秒） |
| 14 | **`TokenLedger.recentKeep` 24→25** | **存活** | — （账本里保存最近 24 条消息用来跨重启去重，没有测 24 / 25 条的边界） |
| 15 | `ActivityResolver.retrySlack` 15→16 | 杀死 | `c1`、`nextChangeTellsWhenTimeWillChangeTheResult` |
| 16 | **`ActivityResolver.compactStaleAfter` 15→16 分钟** | **存活** | — （设计文档：「PreCompact 之后 15 分钟没有 PostCompact 就不再显示」，只测过远大于 15 分钟的情形） |
| 17 | `transcriptCompactWindow` 120→121 | 杀死 | `o2` |
| 18 | `tempBusyWindow` 3→4 | 杀死 | `m1`、`aPromptThatNeverBecomesBusyExpiresAfter3Seconds` |
| 19 | **`TranscriptFacts.maxOpen` 64→65** | **存活** | — （内部上界，P3） |
| 20 | `JSONLTailer` 变短判断 `size < offset`→`<=` | 杀死 | 13 个测试（C-026、b4 … ） |
| 21 | 账本去重 `max`→`min`（input 字段） | 杀死 | 「多个会话记录 + prior + 子代理」、「随机真实行 / 重复行 / 合并」 |
| 22 | `classify` 的 `>` tolerance → `>=` | 杀死 | `i4`（恰好 2 秒） |
| 23 | （我建议的修复）`quiet` 时不再登记 `wakeAt` | 存活 = 现有套件全部通过 | 既说明这个修复不会破坏现有行为，也说明**没有任何现有测试能发现这个 bug** |

结论：22 个变异里 17 个被杀死、**5 个存活**（#3、#8、#14、#16、#19）；其中 #3 / #8 / #16 对应的是设计文档 / README 里写明的规格数值（15 秒、30 秒、15 分钟），应该补边界测试（例如各测 14.9 / 15.1 秒）。杀死的那 17 个基本都是「恰好在边界」的测试（2.95 / 3.05 秒、29.9 / 30.1 秒、2:59:59 / 3:00:01），钉得很扎实；存活的 5 个都是没有边界测试的常量。

## 附录 A：复现用测试 / 脚本

以下测试（A.1–A.4）放进 `Tests/BuddyCoreTests/` 一个新文件里就能跑（我在 scratch 副本里就是这么跑的；用了仓库里已有的 `Harness` / `DesktopFixture` / `FuzzRNG` / `FakeClaudeTree`）。运行：
`BUDDY_SCRATCH=<自己的目录> scripts/dev.sh test --filter R1a -j 2`（沙箱外）。

### A.1 引擎层（R1a-01，最小复现）

```swift
@Suite struct R1aExperiments {
    @Test func quietBusyNextWakeIsInThePast() {
        let h = Harness()
        let f = DesktopFixture(h: h)
        h.tree.writeRegistry(f.session, status: "idle")
        h.tree.hook(f.sid, "SessionStart", extra: "startup")
        h.poll()
        h.advance(1)
        h.tree.writeRegistry(f.session, status: "busy")
        h.tree.hook(f.sid, "UserPromptSubmit")
        h.poll()
        h.advance(1)
        h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "sleep 3600")
        h.poll()
        for _ in 0..<12 { h.advance(100); h.poll() }         // 20 分钟：hook / 会话记录都没有增长
        let d = h.lastOutput?.nextWake.map { $0.timeIntervalSince(h.now) }
        #expect((d ?? 1) > 0, "nextWake 在过去：\(String(describing: d))")   // 现在：-600.0
    }
}
```

### A.2 SessionStore 层（R1a-01，tick 频率 / CPU）

```swift
final class CountingClock {
    let base = VirtualClock()
    private let lock = NSLock()
    private var n = 0
    func now() -> Date { lock.lock(); n += 1; lock.unlock(); return base.now() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}
func cpuSeconds() -> Double {
    var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
    return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
}

@Suite(.serialized) struct R1aStoreExperiments {
    @Test func quietBusySessionMakesTheStoreSpin() {
        let root = FileIO.temporaryDirectory + "r1a-spin-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let cc = CountingClock()
        let probe = FakeProcessProbe()
        let tree = FakeClaudeTree(root: root, clock: cc.base, probe: probe)
        tree.prepare()
        var eo = SessionEngine.Options(paths: tree.paths, now: { cc.now() }, probe: probe)
        eo.persist = false; eo.scanTokens = false
        var so = SessionStore.Options(engine: eo)
        so.usePolling = false                                   // FSEvents 模式：兜底本来是 1 秒
        so.callbackQueue = DispatchQueue(label: "r1a.cb")
        let store = SessionStore(options: so)
        let session = FakeClaudeTree.Session(pid: 1001, sessionId: DesktopFixture.sid, host: DesktopFixture.host,
                                             name: "spin", startedAt: cc.base.now().addingTimeInterval(-30))
        tree.writeRegistry(session, status: "busy")
        tree.hook(session.sessionId, "UserPromptSubmit")
        tree.hook(session.sessionId, "PreToolUse", tool: "Bash", detail: "sleep 3600")
        store.start()
        Thread.sleep(forTimeInterval: 1.5)

        func measure(_ label: String, _ secs: Double) -> (rate: Double, cpu: Double) {
            let c0 = cc.count, t0 = cpuSeconds(), w0 = Date()
            Thread.sleep(forTimeInterval: secs)
            let dt = Date().timeIntervalSince(w0)
            let r = (rate: Double(cc.count - c0) / dt, cpu: (cpuSeconds() - t0) / dt)
            print("R1A \(label): now() calls/s = \(Int(r.rate)), process CPU = \(String(format: "%.1f", r.cpu * 100))%")
            return r
        }
        let before = measure("busy 30s (not quiet)", 3)         // 2 次/秒，CPU 0.1%
        cc.base.advance(by: 11 * 60)                            // 虚拟时间跳 11 分钟
        Thread.sleep(forTimeInterval: 1.5)
        let after = measure("busy 11min (quiet)", 3)            // 285 次/秒，CPU 2.7%
        store.stop()
        #expect(after.rate < before.rate * 3 + 20, "quiet 之后 tick 频率暴涨：\(before.rate) → \(after.rate) 次/秒")
    }
}
```

### A.3 随机时间线（R1a-01「唯一来源」+ 事件配对不变量）

```swift
/// 合法数据的随机时间线：两个会话（桌面 pid 1001 + 终端 pid 2002），每步随机写登记表 / hook / 会话记录 / 杀进程 / 写元数据，再随机推进虚拟时钟。
func r1aRunTimeline(seed: Int, steps: Int, kill: Bool = true, persistDir: Bool = false,
                    onStep: (Harness, Int, [String]) -> Void) {
    var rng = FuzzRNG(seed: UInt64(0xA1A0_0000 + seed))
    let h = Harness(persist: false, tokens: false)
    let d = DesktopFixture(h: h)
    let tsid = "bbbbbbbb-0000-4000-8000-000000000002"
    let term = FakeClaudeTree.Session(pid: 2002, sessionId: tsid, host: nil, name: nil, startedAt: h.now.addingTimeInterval(-100))
    var log: [String] = []
    func L(_ s: String) { log.append(s); if log.count > 14 { log.removeFirst() } }
    let sessions: [FakeClaudeTree.Session] = [d.session, term]
    var tcount = 0
    for step in 0..<steps {
        let i = rng.int(0...1)
        let s = sessions[i]
        switch rng.int(0...16) {
        case 0, 1:
            let st = rng.pick(["idle", "busy", "busy", "waiting"])
            h.tree.writeRegistry(s, status: st, waitingFor: st == "waiting" ? rng.pick(["permission prompt", "input needed", "dialog open", "worker request"]) : nil, statusUpdatedAt: h.now)
            L("reg[\(i)]=\(st)")
        case 2:
            let t = rng.pick(["Bash", "Read", "Edit", "Agent", "AskUserQuestion", "ExitPlanMode", "mcp__x__y"])
            h.tree.hook(s.sessionId, "PreToolUse", tool: t, detail: "d\(rng.int(0...3))"); L("pre[\(i)] \(t)")
        case 3:
            h.tree.hook(s.sessionId, "PostToolUse", tool: rng.pick(["Bash", "Read", "Edit", "Agent"]), detail: "d\(rng.int(0...3))"); L("post[\(i)]")
        case 4: h.tree.hook(s.sessionId, "Stop"); L("stop[\(i)]")
        case 5: h.tree.hook(s.sessionId, "UserPromptSubmit"); L("prompt[\(i)]")
        case 6:
            h.tree.hook(s.sessionId, "Notification", extra: rng.pick(["Claude needs your permission to use Bash", "Claude is waiting for your input"])); L("notif[\(i)]")
        case 7:
            h.tree.hook(s.sessionId, rng.pick(["PreCompact", "PostCompact", "SessionStart", "SubagentStop"]), extra: rng.pick(["", "compact", "startup"])); L("misc-hook[\(i)]")
        case 8:
            tcount += 1
            h.tree.appendTranscript(s.sessionId, [TL.assistant(sessionId: s.sessionId, at: h.now, messageId: "m\(seed)-\(tcount)", block: TL.toolUse(id: "tu\(seed)-\(tcount)", name: "Bash", input: ["command": "ls"]), stopReason: "tool_use")]); L("tr-tooluse[\(i)]")
        case 9:
            tcount += 1
            h.tree.appendTranscript(s.sessionId, [TL.assistant(sessionId: s.sessionId, at: h.now, messageId: "m\(seed)-\(tcount)", block: TL.text(), stopReason: "end_turn")]); L("tr-endturn[\(i)]")
        case 10: h.tree.appendTranscript(s.sessionId, [TL.userPrompt(sessionId: s.sessionId, at: h.now)]); L("tr-prompt[\(i)]")
        case 11: h.tree.appendTranscript(s.sessionId, [TL.userInterrupt(sessionId: s.sessionId, at: h.now)]); L("tr-interrupt[\(i)]")
        case 12:
            let m = rng.int(1...5)
            h.tree.appendTranscript(s.sessionId, [TL.apiError(sessionId: s.sessionId, at: h.now, attempt: rng.int(1...m), max: m, retryInMs: Double(rng.int(500...20000)))]); L("tr-apierr[\(i)]")
        case 13:
            h.tree.appendTranscript(s.sessionId, [TL.system(sessionId: s.sessionId, at: h.now, subtype: rng.pick(["compact_boundary", "stop_hook_summary"]))]); L("tr-sys[\(i)]")
        case 14:
            if kill && rng.chance(0.3) { h.tree.endProcess(pid: s.pid); L("end[\(i)]") }
        case 15:
            h.tree.writeMeta(FakeClaudeTree.Meta(host: DesktopFixture.host, cliSessionId: d.sid, lastActivityAt: h.now)); L("meta")
        default: break
        }
        h.advance(rng.pick([0.02, 0.1, 0.3, 0.5, 1, 2, 5, 12, 40, 200, 700, 2000, 3000]))
        h.poll()
        onStep(h, step, log)
    }
}

@Suite(.serialized) struct R1aScenarioFuzz {
    /// 每次 poll 之后 nextWake 必须在「现在」之后。现在：2936 次违反，全部在 snapshot.quiet == true 时。
    @Test func nextWakeIsAlwaysInTheFuture() {
        var violations: [String: Int] = [:]
        var samples: [String: String] = [:]
        for seed in 1...60 {
            r1aRunTimeline(seed: seed, steps: 260) { h, step, log in
                if let w = h.lastOutput?.nextWake, w <= h.now {
                    let bucket = h.snapshots.contains { $0.quiet } ? "quiet" : "OTHER"
                    violations[bucket, default: 0] += 1
                    if samples[bucket] == nil { samples[bucket] = "seed=\(seed) step=\(step) wake-now=\(w.timeIntervalSince(h.now)) log=\(log)" }
                }
            }
        }
        print("R1A violations: \(violations)")
        for (k, v) in samples { print("R1A sample[\(k)]: \(v)") }
        #expect(violations.isEmpty)
    }
}
```

事件配对不变量（0 违规，可以一起收进去）：对 `h.events` 的新增部分按 key 维护 `live` / `needs` / `open(-1 未知 / 0 已结束 / 1 进行中)`：`arrived` 时 `open = -1`、`departed` 时 `open = 0`；`turnStarted` 遇到 `open == 1` 报错、`turnFinished` 遇到 `open == 0` 报错；`needsUserCleared` 必须先有 `needsUser`。

### A.4 疑点 S-1（Stop 之后又有新工具，登记表一直 busy）

```swift
@Test func stopThenMoreToolsWhileRegistryStaysBusy() {
    let h = Harness(); let f = DesktopFixture(h: h)
    h.tree.writeRegistry(f.session, status: "idle"); h.tree.hook(f.sid, "SessionStart", extra: "startup"); h.poll()
    h.advance(1); h.tree.writeRegistry(f.session, status: "busy", statusUpdatedAt: h.now)
    h.tree.hook(f.sid, "UserPromptSubmit"); h.poll()
    h.advance(1); h.tree.hook(f.sid, "PreToolUse", tool: "Bash", detail: "make"); h.poll()
    h.advance(1); h.tree.hook(f.sid, "PostToolUse", tool: "Bash", detail: "make"); h.poll()
    h.advance(0.5); h.tree.hook(f.sid, "Stop"); h.poll()            // 登记表不变（Claude 被别的 Stop hook 拦下后继续）
    h.advance(6); h.poll()
    print(h.only()!.activity)                                        // idle
    h.tree.hook(f.sid, "PreToolUse", tool: "Read", detail: "/x"); h.advance(1); h.poll()
    print(h.only()!.activity, h.only()!.phase)                       // idle idle（有工具开着）
    h.advance(700); h.poll()
    print(h.only()!.activity)                                        // dozing
}
```

### A.5 `hook-merge.py` 并发 / 往返（无问题的对照）

```bash
S=$(mktemp -d); cd $S
printf '{"env": {"K": "v"}, "hooks": {"SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "echo hi"}]}]}}' > s.json; chmod 600 s.json
for i in 1 2 3 4 5 6; do python3 scripts/hook-merge.py install --settings s.json >/dev/null 2>&1 & done; wait
# 结果：our hooks = 1，groups = 2；权限仍是 -rw-------
python3 scripts/hook-merge.py uninstall --settings s.json      # 往返：内容还原（排版被规范化）
```
