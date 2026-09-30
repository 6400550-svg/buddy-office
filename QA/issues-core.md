# QA · BuddyCore：解析器模糊测试 + 代码审查

> 日期：2026-09-29　范围：`Sources/BuddyCore/**`（31 个 Swift 文件）　方法：把它当成别人写的代码，独立审查 + 确定性模糊测试。
> 铁律遵守情况：全程只用临时目录里的假数据；没有打开过任何 `*.key`、没有连过任何 `*.sock`、没有读过任何凭据；没有改 `~/.claude`、ccmon、用量表、Claude.app；没有联网、没有 pkill、没有动正在运行的 App；
> 没有削弱 / 跳过 / 删除任何已有测试，也没有屏蔽编译警告（BuddyCore 在两套配置——隔离包 -Onone、根包 -O——下都是 0 警告；release 配置我没有单独编）。
> 只改了 `Sources/BuddyCore/**` 和 `Tests/BuddyCoreTests/**`（新增测试全在 `Fuzz*.swift` 里，另外在 `FileAccessTests` 的**扩展**里加了几个必须和它串行跑的测试——没改别人的测试文件）。

## 0. 结论与统计

**发现 33 个**：P0 6 个 / P1 5 个 / P2 5 个 / P3 17 个；**已修复 30 个**，3 个未修复（都是范围外，见 C-031 / C-032 / C-033）。另有 2 条「已确认不是问题」（C-034 / C-035，不计入上面的数）。
**新增测试 86 个**（`Tests/BuddyCoreTests/Fuzz*.swift`；其中 31 个是回归测试，对应每一条已修复且能构造出失败输入的发现，其余是模糊 / 属性 / 压力测试）。

测试命令与结果（都在沙箱外跑；scratch 目录 `.build-qa-core`，`-j 2`，收工时已删除）：

| 命令 | 结果 |
|---|---|
| `BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core scripts/dev.sh test --filter BuddyCoreTests -j 2`（隔离数据层包；BuddyCore 用 -Onone）| **374 个测试（33 个套件）：373 通过、1 失败**。失败的是别的 QA 的 `StateRuleChainTests/chain1`：它检查 `Sources/BuddyOffice/RealProvider.swift` 的源码文本里有 `SessionStore(dataRoot:`，应用层把它改成 `SessionStore(options:)` 之后这条断言过时了，与 BuddyCore 无关。其余包括我新增的 86 个全部通过 |
| `BUDDY_SCRATCH=.build-qa-core scripts/dev.sh test --filter BuddyCoreTests -j 2`（根包；BuddyCore 用 -O）| **374 个测试（33 个套件）：373 通过、1 失败**（同一个 `chain1`）。全量约 49 秒（隔离包因为 -Onone 更慢，约 70 秒）；编译期只有两条 `HelperAttributionTests.swift` 里既有的警告（C-031） |
| `BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core-tsan scripts/dev.sh test --sanitize=thread --filter BuddyCoreTests -j 2`（ThreadSanitizer）| 374 个测试，**0 条 `WARNING: ThreadSanitizer`**（只有 `chain1` 失败）。检测器验证过：把 C-016 的加锁读取撤销，`FuzzEngineTests|TokenLedgerTests` 立刻报 9 条 data race |
| `… BUDDY_SCRATCH=.build-qa-core-asan … --sanitize=address --filter BuddyCoreTests`（AddressSanitizer）| 374 个测试，**0 条 AddressSanitizer 报告**（第一次全量里 C-024 在消毒器下写得太慢超时，已把那个测试改轻、单独重跑通过；另一个失败是 `chain1`）；另用 `MallocScribble=1 MallocPreScribble=1 MallocGuardEdges=1` 跑了 170 个解析 / 模糊 / 账本测试，通过 |
| `BUDDY_SCRATCH=.build-qa-core scripts/dev.sh build -j 2`（根包全部目标：BuddyCore / PixelKit / BuddyArt / BuddyStage / BuddyOffice / buddyctl / buddydump）| Build complete，**0 警告 0 错误** |

修复前失败的证据：崩溃类是「整个测试进程 SIGTRAP / SIGBUS」（`swift test` 报 `exited with unexpected signal code 5 / 10`，崩溃报告里能看到出事的函数和行号），其它是 `Expectation failed` / 超时。
每条都在文件里写了关键一行。凡是回归测试后来又改过、或者修复和测试是一起写的，我都**临时撤销修复重新跑了一遍**证明测试确实会失败，然后恢复（C-006 / C-012 / C-019 / C-023 / C-025 / C-026 / C-027 / C-028 / C-029 / C-030 / 句柄泄漏检测器）。

**本轮最重要的几条**：
1. 一批「外部数据里的一个坏数字就让整个 App 崩溃」：`procStart` 年份（C-001）、`identities.json` 里的时间（C-002，**每次启动都崩，崩溃循环**）、hook 的 `ts`（C-003）、usage 数字（C-004）、账本数字（C-005）；根因都是 Swift 整数溢出 / `Int(Double)` 换算直接 trap。
2. 深嵌套 JSON 会把 512 KB 栈的 GCD 工作线程压爆（C-012，SIGBUS）。
3. `FileIO` 的「绝不打开 .key」保险可以被符号链接、大小写、NUL 绕过（C-007）；命名管道能把读取线程永远卡在 open 上（C-008）。
4. 一条时间戳在未来的 hook 事件，会让登记表明明是 busy 的会话永远显示 idle（C-026），或者让整个 hook 队列卡死（C-006）。

---

## 1. 问题清单

### C-001 [P0] 登记表 `procStart` 里年份 / 时分秒是天文数字 → 整个 App 崩溃
- 现象：登记表（`~/.claude/sessions/<pid>.json`）的 `procStart` 字段是 `"Tue Sep 29 03:23:08 9223372036854775807"`，或者小时写成 `-9223372036854775808:00:00` 时，`TimeUtil.parseProcStart` 在 ingest 线程上直接 trap，App 崩溃。
- 根因：`Util/TimeUtil.swift:90-93`：年份只检查 `> 1970`，没有上界；`daysFromCivil`（:73）里 `era * 146097` 对 Int.max 级别的年份溢出；时分秒只检查 `< 24 / < 60`，没检查非负，`t[0] * 3600` 对 Int.min 溢出（:95）。
- 修法：年份限制在 1971…9999；时、分、秒必须 ≥ 0（不合格返回 nil，记录仍可用，只是没有 `procStart`）。
- 回归测试：`FuzzRegressionTests/c001_procStartExtremeValuesDoNotTrap`；另有 `FuzzParserTests/timeProcStartAndJSONMillisFuzz`（畸形组合 6000 个 + 格式化再解析恒等）。
- 修复前失败的证据：`SIGTRAP`，崩溃栈 `Swift runtime failure: arithmetic overflow` ← `static TimeUtil.daysFromCivil(year:month:day:) TimeUtil.swift 73` ← `static TimeUtil.parseProcStart(_:) TimeUtil.swift 94`。
- 修复后：`✔ Test "C-001 procStart 的年份 / 时分秒是天文数字时不崩溃（登记表 procStart 字段）" passed`。
- 状态：已修复。

### C-002 [P0] `identities.json` 里有一个天文数字的时间 → 每次启动都崩溃（崩溃循环）
- 现象：`identities.json` 是合法 JSON，但某条身份的 `createdAt` / `lastSeenAt` 是 `1e300`、`17591000001234567890`、`18446744073709551615` 之类（一个数字被写坏 / 手动改过）。载入没事，第一次存盘（新会话出现就会触发）在 `Int64(Double)` 里 trap；文件没被覆盖，**下次启动照旧崩**。
- 根因：`Util/TimeUtil.swift:6` `millis(_:)` 是 `Int64((d.timeIntervalSince1970 * 1000).rounded())`，超出 Int64 范围直接 trap；`IdentityResolver.swift:185` 存盘时对每个身份都调它；`TimeUtil.date(fromJSONMillis:)`（:9-14）对任何有限正数都放行，所以坏时间戳能载入并留在内存里。
- 修法：`millis` 改成饱和（超出夹在 Int64 两端，NaN 当 0）；`date(fromJSONMillis:)` 统一改成「合理范围 2000-01-01…2200-01-01 之外都当坏数据」（同时拒绝布尔）；identities 载入时时间戳不合理的用「现在」代替；`formatISO` / `formatProcStart` / `debugClock` 也夹住极端日期。
- 回归测试：`c002_millisSaturates`、`c002_identityFileWithAbsurdTimesCannotCrashLoop`（载入 → 存盘 → 再载入，文件合法、时间都在合理范围）。
- 修复前失败的证据：`Fatal error: Double value cannot be converted to Int64 because the result would be greater than Int64.max`；崩溃栈 `TimeUtil.millis(_:) TimeUtil.swift 6` ← `closure #2 in IdentityResolver.saveIfNeeded(force:) IdentityResolver.swift 185`。
- 修复后：两个测试 passed。
- 状态：已修复。

### C-003 [P0] hook 行的 `ts` 不做范围检查：接受 1970 年 / 550 万年 / 无穷，并且让归属判断崩溃
- 现象：① `{"ts":0,…}`、`{"ts":1,…}`、`{"ts":-5,…}`、`{"ts":true,…}`、`{"ts":1e30,…}`、400 位的数字都被当成合法事件（`ts` 变成 1970 年、5576335 年、+inf）；② 只要主线程有一个前台 Agent/Task 开着，这种事件就会让 `HelperAttributor.decide` 在 `Int(…)` 换算里 trap。
- 根因：`Ingest/LineSanitizer.swift:73-74`（严格解析）和 :80-84（降级解析）直接 `TimeUtil.date(ms:)`，没有范围检查；降级路径里 `scanNumber` 把 `1759100000123e5` 当成 `1759100000123`；`Fusion/HelperAttributor.swift:71` 是 `Int((event.ts.timeIntervalSince(since) * 1000).rounded()) >= …`。
- 修法：hook `ts` 必须在合理范围（2000…2200 年，布尔 / 无穷 / 0 / 负数都拒绝，整行当坏行跳过）；降级扫描里数字后面必须紧跟 `, } ]` 或空白、最多 20 位；`decide` 改成 Double 比较，不做 Int 换算。
- 回归测试：`c003_absurdHookTimestampsAreRejectedAtParseTime`（15 种坏 ts × 严格 / 降级两条路径）、`c003_attributionSurvivesAbsurdEventTimes`（`±1e30 / ±1e300 / ±inf`）。
- 修复前失败的证据：`Expectation failed: (LineSanitizer.parseHookLine(full) → HookEvent(ts: 5576335-12-29 12:18:20 +0000, ev: "PreToolUse" …)) == nil`（19 个 issue）；崩溃：`Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max` ← `HelperAttributor.decide(event:context:now:) HelperAttributor.swift 71`。
- 修复后：两个测试 passed。
- 状态：已修复。

### C-004 [P0] 会话记录里 `usage` 的数字太大 → 相加溢出，崩溃（解析线程 / 账本扫描线程）
- 现象：一行 assistant 记录里 `input_tokens` / `cache_read_input_tokens` 之类是 `9223372036854775807`（或者 `cache_creation` 的 5m / 1h 两项都很大），解析这一行就 trap；账本的后台扫描线程也会崩。
- 根因：`Ingest/TranscriptLine.swift:164-167` `intValue` 只做 `max(0, n.intValue)`（`NSNumber.intValue` 对超范围的数会饱和成 Int.max），然后 :103 `usage.cacheWrite1h + usage.cacheWrite5m` 和 `TranscriptReader.swift:96-97` `u.input + u.cacheWriteTotal + u.cacheRead` 都是普通 `+`。
- 修法：每个 token 计数夹到 `[0, 2^40]`（≈ 1.1 万亿，比任何真实的单条消息大几个数量级），三项相加不可能溢出。
- 回归测试：`c004_hugeUsageNumbersDoNotOverflow`（解析 + `TranscriptFacts.apply` + `TokenLedger` 扫描）；`FuzzParserTests/transcriptLineRandomAndTypeConfusion`（2500 个字段类型随机的行，usage 一律在范围内、缓存写拆分对得上总数）。
- 修复前失败的证据：`SIGTRAP`，`Swift runtime failure: arithmetic overflow` ← `static TranscriptLineParser.parse(object:) TranscriptLine.swift 103`。
- 修复后：passed。
- 状态：已修复。

### C-005 [P0] `ledger.json` 里的计数是天文数字 / 负数 → 恢复后累加、求和都会溢出崩溃
- 现象：账本条目里 `input` / `output` / `cw` / `cr` / `n` 是 `9223372036854775807`、`-1000`、`1e300`、`18446744073709551615`：恢复之后 `TokenBreakdown.total`（界面每次都会读）溢出 trap；之后追加的新消息 `+=` 也溢出；负数则让「token 只增不减」不成立。
- 根因：`Ingest/TokenLedger.swift` 的 `restore` 用 `NSNumber.intValue` 直接赋值，没有范围；`totals(forKey:)` / `handle` 都是普通 `+=`；`Model/BuddySnapshot.swift:30` `total` 是四个 Int 直接相加。
- 修法：恢复出来的计数夹到 `[0, 2^50]`；账本里所有累加改成饱和加法（`TokenLedger.sat`）；`TokenBreakdown.total` 也是饱和加法。
- 回归测试：`c005_ledgerWithAbsurdCountersIsSanitized`（四种坏值 × 恢复 + 追加新行 + 写盘）；`FuzzPersistenceTests/ledgerFieldwiseMutations`、`ledgerRandomCorruption`（字段缺失 / 错误类型 / 天文数字 / 随机字节破坏，统计值非负、追加后只增不减）。
- 修复前失败的证据：`SIGTRAP`，`Swift runtime failure: arithmetic overflow` ← `TokenBreakdown.total.getter BuddySnapshot.swift 30`。
- 修复后：passed。
- 状态：已修复。

### C-006 [P1] 时间戳在未来的 hook 事件会把「归属扣留」永远扣下去，整个 hook 队列卡死
- 现象：有后台小助手活跃时，主线程的 PreToolUse 要先扣住最多 400 ms（等会话记录里的 tool_use 落盘来比对）。如果这个事件的 `ts` 在未来（时钟被拨回 / 坏数据，哪怕只是几分钟），扣留要等到「现在」追上 `ts + 0.4 s` 才结束；期间它后面的所有事件（Post、Stop……）都排在收件箱里出不来，收件箱一直涨。
- 根因：`Fusion/HelperAttributor.swift:83-84` `deadline = event.ts + 0.4`，`now < deadline ? .hold : .main`；`SessionEngine.processInbox`（:530-536）遇到 `.hold` 就整个 return。
- 修法：记住「第一次扣它的时刻」，扣留时限取 `min(事件时间戳, 第一次扣留时刻) + 0.4 s`（正常事件行为不变）。
- 回归测试：`c006_attributionHoldIsBoundedEvenWithFutureTimestamps`（未来 1 小时 / 1 年 / 100 年，都要在 0.5 秒内决定）。
- 修复前失败的证据（撤销修复后重跑）：`未来 3600 秒的事件：1 秒后还在扣留（hook 队列被卡死）`、`未来 31536000 秒…`、`未来 3153600000 秒…`。
- 修复后：passed。另外 C-026 的入口处把比现在晚一天以上的事件按「现在」算，双重保险。
- 状态：已修复。

### C-007 [P1] `FileIO` 的「绝不打开 .key / .sock」保险可以被绕过
- 现象：① 名字合法但是符号链接指向 `.key` 的文件（`1001.json -> 1001.<sha>.key`）：`FileIO.readAll` 读出了 key 的内容（测试里读到 34 字节的假内容）；② `1001.abc.KEY`、`A.SOCK`、`/tmp/CC-SOCKS/x` 大小写变体（macOS 默认的 APFS 大小写不敏感，`ABC.KEY` 打开的就是 `abc.key`）不被认出来；③ 路径里带 NUL（`x.key\0.json`）：名字判断看到的是 `.json`，C 字符串在 NUL 处截断，实际打开的是 `x.key`（测试里 `FileIO.open` 真的返回了 fd）；④ 经过目录符号链接（`cc-alias -> cc-socks`）也能绕过 `cc-socks` 检查。
- 根因：`Util/FileIO.swift:43-58`：只对路径字符串做**大小写敏感**的后缀 / 子串判断，不看 NUL，不看符号链接的真实路径，不核对打开之后的 fd。
- 修法：`isForbidden` 不区分大小写 + 拒绝含 NUL 的路径 + 路径里任何一段叫 `cc-socks` 都算；`open` 在文件存在时先 `realpath` 解析再判断（被拒绝的路径连 `open` 都不调用，观察口里也不会出现）；打开之后再用 `fcntl(F_GETPATH)` 核对 fd 自己的真实路径；只允许打开普通文件。
- 回归测试（都在串行套件 `FileAccessTests` 的扩展里，因为要用全局的 `forbiddenHits` / `openObserver`）：`c007_symlinkToKeyFileIsRefused`、`c007_caseVariantsNulAndDotDotAreForbidden`；模糊测试 `fuzz_forbiddenOracleOnRandomPaths`（3 万个随机路径和独立判断逐个对照）、`fuzz_variantsNeverOpenForbiddenFiles`（27 种变体：大小写 / `./` / `//` / `..` / 结尾斜杠 / 符号链接链 / 目录符号链接 / 相对符号链接 / NUL，全部打不开，观察口里一个都没有）、`fuzz_registryScannerWithDecoyFiles`（诱饵目录：假 `.key`（含不可读的）、名字差一点点的、目录、FIFO、指向 `.key` 的符号链接：只读合法的 `<pid>.json`，被 open 的文件名全部匹配 `^\d+\.json$`）。
- 修复前失败的证据：`Expectation failed: (FileIO.readAll(dir.file("1001.json")) → 34 bytes) == nil`；`FileIO.open(dir.file("1001.json")) → 3`；`FileIO.isForbidden(path: "/h/.claude/sessions/1001.abc.KEY")` 为 false（12 个 issue）；`FileIO.open(nul) → 4`。
- 修复后：全部 passed；已有的 `FileAccessTests` 4 个测试照常通过。
- 状态：已修复。**没修（也修不了）的一种：硬链接**——同一个 inode 的另一个名字（`ln 1001.<sha>.key 1002.json`）从路径上看不出来，见「剩余风险」。

### C-008 [P1] 数据文件位置上是命名管道（FIFO）→ 读取线程永远卡在 `open()`
- 现象：`~/.claude/sessions/<pid>.json`、桌面元数据 `local_x.json`、hook 文件等的位置上如果是一个 FIFO，`open(O_RDONLY)` 会一直阻塞到有写者出现，ingest 队列（整个数据层）从此卡死。
- 根因：`Util/FileIO.swift:57` `Darwin.open(path, O_RDONLY | O_CLOEXEC)` 没有 `O_NONBLOCK`，也不检查文件类型。
- 修法：`O_NONBLOCK` 打开，打开后 `fstat` 不是普通文件（管道 / 设备 / socket / 目录）就关掉返回 -1。
- 回归测试：`c008_fifoDoesNotBlockTheReader`（`readAll` / `JSONLTailer` / `DesktopMetaReader.refresh` 遇到 FIFO 都要在 15 秒内返回）；诱饵目录测试里也有 FIFO。
- 修复前失败的证据：`超时（疑似死循环 / 卡死）：DesktopMetaReader.refresh(FIFO)（>5 秒）` + `readAll(FIFO)` 超时（4 个 issue，测试跑了 10 秒）。
- 修复后：passed（0.04 秒）。
- 状态：已修复。

### C-009 [P2] `identities.json` 载入没有上界：别名 / 工位号 / 身份个数都可以是任意大
- 现象：一个身份挂 5 万个别名、工位号是 `Int.max` / `-5` / `4294967296`、上万条身份，都原样载入（内存里长期占着，别名索引也跟着涨；工位号一路传到界面层，见应用层 A-011）。
- 根因：`Fusion/IdentityResolver.swift:200-217` `load` 对 `aliases` / `seat` / 条目数都不设限；`maxAliases` 这个常量定义了但没人用；`lastPersistedSeen` 在身份过期后不清理（:219-225）。
- 修法：载入时别名按 host 6 / sid 30 / proc 4 保留最近的、去重、丢掉别的前缀和过长的；工位号只认 0…999，别的当作没分配；身份最多 2000 个（留最近见到的）；key 长度 ≤ 200；未来的时间当作刚见过；`pruneExpired` 同步清理 `lastPersistedSeen`。（应用层 QA 建议的「load 丢弃 seat < 0 / > 999」已做；「输出夹到 0..<64」没做——Core 输出的座位号是最小空位，超过 64 个人同时在场时夹到 64 会撞座位，应用层的 `SeatSanitizer` 已经处理。）
- 回归测试：`c009_identityFileIsBoundedOnLoad`；`FuzzPersistenceTests/identitiesTruncatedAtEveryByte`（每个字节位置截断）、`identitiesCorruption`（随机破坏 250 个 + 每个字段缺失 / 换成 16 种错误类型）：载入后不变量成立（seat / 别名数 / 时间），再 resolve、存盘、重载是恒等的。
- 修复前失败的证据：`(id.aliases.count → 50000) <= (IdentityResolver.maxAliases → 40)`、`(r.all.count → 5009) <= 2000`、`(id.seat >= -1 → false)`（8 个 issue）。
- 修复后：passed。
- 状态：已修复。

### C-010 [P2] 桌面元数据的 `priorCliSessionIds` 没有上界：O(n²) + 每个 id 都要列一遍 projects 目录
- 现象：元数据里 `priorCliSessionIds` 有 1.2 万项时，`allCliSessionIds`（去重用 `contains`）要算 16 秒（-Onone；-O 也是秒级）；引擎还会对每个 id 去 `TranscriptLocator.find`（列 projects/ 目录），几十万项会把 ingest 队列拖死。
- 根因：`Ingest/DesktopMetaReader.swift:52` `allCliSessionIds` 是 O(n²)；:145 解析时不设上限、不校验 id 格式。
- 修法：只留最近 256 个、只认 `Paths.isSafeID` 的 id；`allCliSessionIds` 用 Set 去重（O(n)）。
- 回归测试：`c010_priorCliSessionIdsAreBounded`；`FuzzParserTests/desktopMetaTruncationAndTypeConfusion`。
- 修复前失败的证据：`别名个数应有上界：12001`（测试花了 16 秒）。
- 修复后：passed（0.1 秒）。
- 状态：已修复。

### C-011 [P2] `ToolTracker.open` 没有上界
- 现象：hook 文件被刷屏（或坏数据：一堆 PreToolUse 没有 PostToolUse，时间戳相同所以永远不开新的一批）时，`open` 数组无限增长，每次 `post` 还要线性扫描。
- 根因：`Fusion/ToolTracker.swift:65-81` `pre` 只追加；只有 Post / 轮次边界 / 新一批 / 30 分钟兜底才会关。
- 修法：`maxOpen = 512`，超出把最老的当作被取代关掉。
- 回归测试：`c011_toolTrackerOpenListIsBounded`；`FuzzParserTests/toolTrackerAndAttributorRandomSequences`（随机序列：乱序 / 同一毫秒 / 名字被截断 / 时间倒流，open 有上界且 seq 严格递增）。
- 修复前失败的证据：`(t.open.count → 30000) <= 1024`。
- 修复后：passed。
- 状态：已修复。

### C-012 [P0] 嵌套 ≥ 约 470 层的 JSON 把 512 KB 栈的 GCD 工作线程压爆（SIGBUS）
- 现象：任何一个被解析的 JSON（hook 行 / 会话记录行 / 登记表 / 桌面元数据 / 子代理 meta / 账本 / 身份文件 / custom-title.json / settings.json）里只要有一个嵌套 470～512 层的对象，`JSONSerialization` 递归解析就会栈溢出，整个 App 崩溃（SIGBUS）。超过 512 层它自己的深度上限才会报错，所以更深的反而没事。
- 根因：8 处 `JSONSerialization.jsonObject` 都直接解析外部输入；数据层跑在 GCD 工作线程上（栈 512 KB），每层对象嵌套约吃 1 KB 栈（实测：512 KB 栈上 450 层没事、480 层崩）。
- 修法：新增 `Util/SafeJSON.swift`，解析前先用一遍 O(n) 的扫描数嵌套深度（字符串 / 转义里的括号不算，对 UTF-16 编码同样有效），> 100 层一律当坏数据；8 个解析点全部改走 `SafeJSON.object`。
- 回归测试：`c012_deeplyNestedJSONDoesNotOverflowTheStack`（在 512 KB 栈的线程上，深度 200～10 万的对象 / 数组分别塞进 hook 行 / 会话记录行 / 登记表 / 桌面元数据，正常的浅 JSON 照常解析，字符串里的括号不算）。
- 修复前失败的证据（`maxDepth` 改成 `Int.max` 重跑）：`CRASH: SIGBUS`，栈 `newJSONValue` ← `newJSONObject` ← `newJSONValue` …（Foundation 的递归解析）。第一次是在 `FuzzTailerTests/hookLineJSONLevel` 里意外撞到的。
- 修复后：passed（0.009 秒）。
- 状态：已修复。

### C-013 [P3] `TranscriptReader.bootstrap(tailWindow:)` 传 0 死循环、传负数 trap
- 现象：`tailWindow: 0` → 循环里 `window *= 4` 永远是 0，永远出不来；`tailWindow < 0` → `UInt64(window)` trap。（`SessionEngine.Options.transcriptTailWindow` / `hookTailWindow` 是公开的可配置项，App 没设，但接口不该这么脆。）
- 根因：`Ingest/TranscriptReader.swift:164-174`；`Ingest/JSONLTailer.swift:72-73` `UInt64(window)`。
- 修法：`bootstrap` 里 `max(1, tailWindow)`；`seekToTail` 里负数当 0。
- 回归测试：`c013_bootstrapWithNonPositiveWindowTerminates`（0 / -1 / Int.min / 1，TranscriptReader 和 HookLogReader 都测）。
- 修复前失败的证据：`Expectation failed: finished`（`tailWindow: 0` 超时 = 死循环）；`tailWindow: -1` 崩溃：`JSONLTailer.seekToTail(window:) JSONLTailer.swift 72`。
- 修复后：passed。
- 状态：已修复。

### C-014 [P2] 按会话累积的缓存 / 账本里没有 buddy 在用的文件永远不清理，还每次都被扫描
- 现象：App 长时间运行、会话来来去去之后：`SessionEngine.transcriptPathCache` / `transcriptMissAt`（按 sessionId）只增不减（300 个会话之后各 150 条）；`TokenLedger` 的 `files` / `fileList` / 去重表 `messages` 只增不减（`removeGroup` 只删分组，文件状态「万一它又回来」全留着），而且**每次扫描都把出现过的所有文件 stat 一遍、有增长的还会 open 读**（测试里已经没人用的文件被反复 open）。
- 根因：`Fusion/SessionEngine.swift:84-86` 两个字典从不清理；`Ingest/TokenLedger.swift:52-56, 102-104, 155-174`。
- 修法：引擎每 30 秒清一次（miss 记录过 10 秒就没用了；路径缓存只留还有 buddy 在用的会话）；账本里没有任何分组在用的文件标记为「没人用」，不再扫描，超过 64 个就把最早没人用的清出去（断点转存进 `ledger.json`，回来时从断点恢复，去重表里属于它的条目一起删掉）；`removeGroup` 同时清 `groupNoLedger`。
- 回归测试：`c014_engineCachesStayBoundedWhenSessionsComeAndGo`（300 个会话来去，缓存 ≤ 32）；`FileAccessTests/c014_ledgerDoesNotKeepScanningOrHoardingDetachedFiles`（用观察口证明没人用的文件不再被 open；文件数 ≤ 100、去重表 ≤ 100；被清出去的会话回来，统计值正确、写盘的账本合法）；`FuzzEngineTests/engineWithHundredsOfSessionsComingAndGoing`（每批 150 个会话，含重复 sessionId / 重复 host，全部离场后缓存回落）。
- 修复前失败的证据：`(c.transcriptPaths → 150) <= 32`、`(c.transcriptMisses → 150) <= 32`；`(ledger.trackedFileCount → 302) <= 100`、`(ledger.dedupeEntryCount → 303) <= 200`、`!(opened.value → [".../a.jsonl", …])`（没人用的文件还在被 open）。
- 修复后：passed。
- 状态：已修复。

### C-015 [P3] 读过一条很长的行之后，`JSONLTailer` 的半行缓冲一直占着几 MB 内存
- 现象：读过一条 3 MiB 的行之后，半行缓冲的容量仍是 3162080 字节（`removeAll(keepingCapacity: true)`）；几十个读取器同时跟踪时每个都留着自己见过的最大一块。
- 根因：`Ingest/JSONLTailer.swift:179` 等处。
- 修法：容量超过 64 KiB 就直接释放（`clearPending()`）。
- 回归测试：`c015_pendingBufferIsReleasedAfterALargeLine`。
- 修复前失败的证据：`(t.pendingCapacity → 3162080) <= (256 * 1024 → 262144)`。
- 修复后：passed。
- 状态：已修复。

### C-016 [P3] `TokenLedger` 的 `version` / `persistenceOK` / `isScanning` 在别的线程无锁读取（数据竞争）
- 现象：这三个公开状态在扫描队列上（持锁）写，`SessionEngine.poll()` / 诊断页在 ingest 队列 / 主线程无锁读——形式上是数据竞争（实际是机器字，多半无害，但 TSAN 会报）。
- 根因：`Ingest/TokenLedger.swift` 里它们是 `public private(set) var`。
- 修法：改成持锁读取的计算属性（`_version` 等私有存储）。
- 回归测试：普通 `swift test` 里数据竞争不会让断言失败，所以没有常规测试；用 ThreadSanitizer 验证：`BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core-tsan scripts/dev.sh test --sanitize=thread --filter 'FuzzEngineTests|TokenLedgerTests' -j 2`（`FuzzEngineTests/storePublicAPIUnderConcurrentUse` 让 4 个线程同时乱用 `SessionStore` 的公开 API，同时数据在变）。
- 修复前失败的证据（撤销加锁后重跑，9 条）：`WARNING: ThreadSanitizer: Swift access race … Modifying access of Swift variable … by thread T11 (mutexes: write M0): #0 TokenLedger.pass() … Previous read of size 8 … by thread T12: #0 TokenLedger.version.getter TokenLedger.swift:100 #1 SessionEngine.poll() SessionEngine.swift:177 #2 Harness.poll()`。
- 修复后：全量 374 个测试在 TSAN 下 0 条警告。
- 状态：已修复。

### C-017 [P3] 登记表 `pid` 不校验：布尔 / 小数 / 超出 Int32 的数被强转成别的 pid；记录里的 pid 和文件名不一致时用哪个没有规定
- 现象：`{"pid":true}` → pid 1（launchd，永远「活着」）；`4294967297` → 1；`9223372036854775807` / `1e30` → -1；`1.5` → 1；`0` / 负数原样放行。引擎探测存活用的是文件名的 pid，界面 / 终端跳转显示的却是记录里的 pid，两者不一致时会拿错进程。
- 根因：`Ingest/RegistryScanner.swift:196,206` `pidNum.int32Value`。
- 修法：`pid` 必须是 1…Int32.max 的整数（布尔 / 小数 / 范围外 = 不可用）；扫描时以**文件名里的 pid** 为准（记录里的只是冗余信息，不会因此隐藏会话）。
- 回归测试：`c017_registryPidMustBeARealPid`；`FuzzParserTests/registryJSONLevelAgreesWithOracle`（4000 个随机 JSON 和独立判断一致）。
- 修复前失败的证据：`pid=true → RegistryRecord(pid: 1 …)`、`pid=4294967297 → pid: 1`、`pid=9223372036854775807 → pid: -1`、`(r.records[1001]?.pid → 2002) == 1001`。
- 修复后：passed。
- 状态：已修复。

### C-018 [P3] 会话记录里 AskUserQuestion 的 `key` 没有像 hook 那样置空
- 现象：`ToolDetail.key(name: "AskUserQuestion", input: ["description": …])` 返回那个 description；README 说「AskUserQuestion 的 detail 在解析和追踪两层都置空」，会话记录这一层漏了（只在没有 hook 时的回退路径会用到，但任务书第 4 节明确写了这个坑）。
- 根因：`Ingest/TranscriptLine.swift:177-196`。
- 修法：AskUserQuestion（含被截断 / 带空白的名字）一律返回空串。
- 回归测试：`c018_askUserQuestionTranscriptKeyIsAlwaysEmpty`；`FuzzTailerTests/hookKnownPitfallsUnderMutation`（hook 那一层的变异：截断的转义 / 非法字节 / 超长，300 次）。
- 修复前失败的证据：`ToolDetail.key(name: "AskUserQuestion", …) → "第一个选项的说明"`。
- 修复后：passed。
- 状态：已修复。

### C-019 [P3] 文件事件分流按前缀匹配、不看目录边界；空会话 id 会匹配一切
- 现象：`~/.claude/sessions-old/…`、`sessions2`、`.monitor-old/…`、`claude-code-sessions-backup/…` 的变化都会触发一次 poll；已跟踪的会话 id 集合里如果有空串，`path.contains("")` 让 monitor / projects 下所有文件的变化都触发。（只会多 poll，不会出错。）
- 根因：`Fusion/SessionStore.swift:228-240` `hasPrefix(pre.sessions)`、`tracked.contains(where: { path.contains($0) })`。
- 修法：抽成纯函数 `SessionStore.shouldPoke(paths:prefixes:tracked:)`，按目录边界匹配（`path == dir || hasPrefix(dir + "/")`），空 id 不匹配。
- 回归测试：`c019_fileEventRoutingRespectsDirectoryBoundaries`。
- 修复前失败的证据（撤销边界判断后重跑）：`!(poke("/h/.claude/sessions-old/123.json") → true)`、`!(poke("/h/.claude/sessions2") → true)`、`…claude-code-sessions-backup/x.json`、`…/.monitor-old/…events.jsonl`（4 个 issue）。
- 修复后：passed。
- 状态：已修复。

### C-020 [P3] 两个桌面元数据文件声称同一个 `sessionId`（用户复制出的副本）→ 每次刷新都互相覆盖、报告「变了」
- 现象：`local_x.json` 和 `local_x copy.json` 内容里 `sessionId` 相同：`refresh()` 每次都重读两个文件、来回覆盖索引、都返回 `[local_x]`（测试里 5 次刷新报了 5 次变化），引擎每次都当作元数据变了。
- 根因：`Ingest/DesktopMetaReader.swift:89-103`：索引键是文件**内容里**的 sessionId，跳过检查用的却是**文件名**推出的 host。
- 修法：同一个 host 有多个文件时确定性地选一个（文件名恰好是 `<host>.json` 的优先，否则路径小的优先），其余记进「副本表」（路径 → 签名 + 压住它的 host），没变就不再重读，赢家没了副本才转正；「没变就不重读」的判断改用 `pathToHost`。
- 回归测试：`c020_duplicateHostIdsDoNotThrash`；`FuzzReadersTests/desktopMetaRefreshOnJunkTree`（目录 / FIFO / 符号链接（含指向别的元数据文件的）/ 垃圾 / 超过 4 MiB / 深嵌套 / 古怪文件名，重复刷新 5 次没有抖动，改一个 / 删一个只报告它）。
- 修复前失败的证据：`文件没变，refresh 却报告了 5 次变化`（`changes → 5`）。
- 修复后：passed。
- 状态：已修复。

### C-021 [P3] 子代理的 `.meta.json` 一直不存在时，每次 poll 都 `open` 它一遍
- 现象：老版本的子代理没有 meta 文件；引擎每个 poll（忙时 20 Hz）对每个没有 meta 的小助手都 `open()` 一次（失败）。60 个 poll 里 open 了 62 次。
- 根因：`Ingest/SubagentReader.swift:68` `if h.meta == nil { loadMeta(h) }` 在每次 poll 里都执行。
- 修法：只在「列目录」的节拍上重试（忙时 0.15 秒、闲时 1 秒）。
- 回归测试：`FileAccessTests/c021_missingSubagentMetaIsNotRetriedOnEveryPoll`（meta 后来出现能读到）；`FuzzReadersTests/subagentReaderOnJunkDirectory`。
- 修复前失败的证据：`没有 meta 文件时被反复 open 了 62 次`（`metaOpens → 62`）。
- 修复后：passed。
- 状态：已修复。

### C-022 [P3] `FileWatcher.resolved` 是递归的：几百层的不存在路径把 512 KB 栈压爆
- 现象：`FileWatcher.resolved(<3000 层的不存在路径>)` 在 GCD 工作线程上 SIGBUS（每层递归都有一个 `realpath` 的大栈帧）。（路径来自 `Paths`，正常只有几层；`--data-root` 传一个畸形值才会碰到。）
- 根因：`Ingest/FileWatcher.swift:79-88`。
- 修法：改成循环（收集未解析的末尾几级，找到最深的存在的祖先再接回去，语义不变）。
- 回归测试：`FuzzWatcherTests/c022_resolvedHandlesEveryKindOfPath`（空串 / 根 / 一堆斜杠 / `..` / 超长 / 含 NUL / 3000 层深路径；结果幂等）。
- 修复前失败的证据：`CRASH: SIGBUS`，栈 `___chkstk_darwin` ← `realpath$DARWIN_EXTSN` ← `static FileWatcher.resolved(_:) FileWatcher.swift 81 / 86 / 86 / 86 …`。
- 修复后：passed。
- 状态：已修复。

### C-023 [P3] 外部 JSON 里的字符串字段没有长度上限
- 现象：登记表的 `name` / `cwd`、元数据的 `title`、hook 的 `tool` / `detail` / `extra`、会话记录里的 id / 模型 / 工具名 / 标题……都可以是几 MB 的字符串，会被复制进每一份快照、写进 identities.json（别名 / key）。
- 根因：所有 `as? String` 的解析点。
- 修法：`SafeJSON.string / id`：标签类字段截到 2048、detail 4096、名字 / 模型 200、状态类 64（按 Unicode 标量截）；**id 类字段太长当没有、不截断**（截断会让不同的 id 变相等，去重 / 配对会错）；hook 的 `ev` > 64 字符整行当坏行；降级扫描的字符串 / 数字扫描到上限就停。
- 回归测试：`c023_hugeStringFieldsAreClipped`（登记表 / 桌面元数据 / hook 行（严格 + 降级）/ 会话记录 / 标题，都塞 90 万字的字段）。
- 修复前失败的证据（上限改成 1 亿重跑）：`Expectation failed: ((r.cwd?.count ?? 0) <= 2048 && … → false)`、`(r.hostSessionId → "aaaa…(5000 个)")`、`((m?.title?.count ?? 0) <= 2048 → false)`。
- 修复后：passed。
- 状态：已修复。

### C-024 [P3] `FileIO.writeAtomically` 的临时文件名是固定的：多线程同时写同一个文件会得到两次内容的混合
- 现象：`path.tmp<pid>` 每次调用都一样；两个线程同时写同一个目标时互相 `O_TRUNC`、交错写入，然后 rename 出去的是混合内容。（App 里没有这种并发——身份和账本各写各的、都在各自的串行队列上——但这是公开的通用接口。）
- 根因：`Util/FileIO.swift:131`。
- 修法：临时文件名 = `path.tmp<pid>-<递增计数>`（计数在锁里）。
- 回归测试：`FuzzFileIOTests/c024_concurrentAtomicWritersNeverProduceMixedContent`（4 个线程写长度不同、字节不同的内容，另一个线程不停读：读到的永远是某一次完整的内容，最终文件完整，没有残留临时文件）。
- 修复前失败的证据：`读到了 32 次混合 / 不完整的内容（共读 1844 次）`（第一版参数较重；为了在 ASAN 等慢环境下也能跑完，后来把内容缩小、加了读者的休眠，撤销修复重跑：`读到了 2 次混合 / 不完整的内容（共读 78 次）`）。
- 修复后：passed。
- 状态：已修复。

### C-025 [P1] 会话记录里 `turn_duration` / `api_error` 的数字没有范围：天文数字会流进快照，让表现层的 `Int(秒数)` 换算 trap
- 现象：`turn_duration` 的 `durationMs` 是 `1e300`（或 `-1e300`）→ `lastTurnDuration = 1e297` 进入快照；BuddyStage 的 `PlateCopy.spoken`（`max(0, Int(seconds))`）对它做 `Int(…)` 换算会直接 trap（**主线程崩溃**）。`retryInMs` / `retryAttempt` / `maxRetries` 同理（重试次数会显示在桌牌上）。
- 根因：`Ingest/TranscriptLine.swift:141-146` 直接取 `NSNumber.doubleValue / intValue`；`Fusion/SessionEngine.swift:757-760` 把 `ms / 1000` 当作 `lastTurnDuration`。
- 修法：解析时夹到合理范围（`durationMs` 0…1e12 ms、`retryInMs` 0…1 小时、次数 0…1000），范围外 / 布尔 / 非数字当作没有。（表现层自己没有防护，见 C-033。）
- 回归测试：`c025_durationsAndRetryCountsAreBounded`（10 种坏值 × `turn_duration` / `api_error`，事实里也没有）；`FuzzEngineTests/engineSurvivesExtremeValuesEverywhere` 的快照不变量里检查 `lastTurnDuration` 有限且非负。
- 修复前失败的证据（撤销范围后重跑）：`Expectation failed: (l?.durationMs → -1e+300)`、`durationMs=-1e300 应当被当作没有：Optional(-1e+300)`、`api_error 的 1e300 应当被当作没有`。
- 修复后：passed。
- 状态：已修复（数据层保证范围）。

### C-026 [P1] 时间戳远在未来的 hook 事件 / 会话记录行，把「取最大时间」的状态永远毒化（会话被卡在 idle）
- 现象：hook 里一条 `Stop` 的 `ts` 是一年以后（时钟被拨快过 / 坏数据）：`lastStopAt` 变成一年后，`ActivityResolver.effectivePhase` 里「登记表 busy 但有比 statusUpdatedAt 更新的 Stop → 暂时当作 idle」的条件永远成立——之后**每一轮**登记表都是 busy，界面却一直显示空闲，直到 App 重启（甚至更久，只要那一行还在读取窗口里）。会话记录里一条未来的 assistant 行同样毒化 `lastAssistantAt / lastLineAt / lastAssistantOrUserAt`（hookActive 误判、重试 / 出错判断失效）。
- 根因：`Fusion/SessionEngine.swift:489-498` `ingestHook` 直接 `max(…, e.ts)`；`Ingest/TranscriptReader.swift` 的 `apply` 也是；`Fusion/ActivityResolver.swift:44-47` 的 Stop 判断没有 `<= now` 保护（Prompt 那一条有）。
- 修法：引擎入口处把比「现在」晚一天以上的 hook 事件时间戳按「现在」算；`TranscriptReader` 接受一个时钟（引擎传 `options.now`，子代理读取器同理），比现在晚一天以上的行时间戳按「现在」算（不注入时钟就不改，所以直接构造读取器的旧测试 / 工具不受影响）。
- 回归测试：`c026_farFutureTimestampsDoNotPoisonState`（一年后的 Stop + 一年后的 assistant 行，之后新一轮开始：要显示 `Read`，事实里 `lastAssistantAt / lastLineAt / hookMaxTs / lastStopAt` 都不超过现在 + 1 天）。
- 修复前失败的证据（撤销后重跑）：`新一轮开始之后应该是「Read」，实际 Optional(BuddyCore.Activity.idle)（被未来的 Stop 毒化成了 idle）`。
- 修复后：passed。
- 状态：已修复。

### C-027 [P3] `Paths(home:)` 去掉结尾斜杠是 O(n²)
- 现象：`home` 是几十万个斜杠时卡 10 秒以上（每次循环都对整个字符串 `count`）。
- 根因：`Paths.swift:12` `while h.count > 1 && h.hasSuffix("/") { h.removeLast() }`。
- 修法：转成字节数组，从后往前数一遍。
- 回归测试：`c027_pathsInitIsLinear`（也验证 `""` / `"/"` / `"//"` / 带空格 / emoji 的语义不变）。
- 修复前失败的证据（撤销后重跑）：`超时（疑似死循环 / 卡死）：Paths.init（>10 秒）`。
- 修复后：passed（0.009 秒）。
- 状态：已修复。

### C-028 [P3] `TokenLedger.flush()` 在扫描队列上调用会对自己所在的队列 `sync` → 崩溃 / 死锁
- 现象：`onChange` 回调（在扫描队列上执行）里调 `flush()`，libdispatch 直接报「dispatch_sync called on queue already owned by current thread」并崩溃。（`SessionStore` 的 `onChange` 只是异步 poke，不会碰到；但这是公开接口。）
- 根因：`Ingest/TokenLedger.swift:145-147` `queue.sync { … }`。
- 修法：用 `DispatchSpecificKey` 判断当前是否就在扫描队列上，是就直接写。
- 回归测试：`c028_flushFromInsideOnChangeDoesNotDeadlock`。
- 修复前失败的证据（撤销后重跑）：`CRASH: SIGTRAP`，栈 `__DISPATCH_WAIT_FOR_QUEUE__` ← `_dispatch_sync_f_slow` ← `TokenLedger.flush() TokenLedger.swift 198` ← `closure in c028…` ← `TokenLedger.pass()`。
- 修复后：passed。
- 状态：已修复。

### C-029 [P2] `HookLogReader.poll()` 一次交出的事件没有上界
- 现象：hook 文件一下子有几十万行时（App 被挂起很久 / 文件被换成一个大文件）一次 poll 把所有事件（60000 个测试事件）全堆进数组，随后又被复制进收件箱；100 MB 的文件会是上百万个事件、几百 MB 内存。
- 根因：`Ingest/HookLogReader.swift:32-46`。
- 修法：一次最多交出最新的 20000 个（摊还 O(1) 地丢旧的），并置 `reset`，引擎据此作废旧事件推出来的状态（`resetHookState`），再吃最新这批。
- 回归测试：`c029_hookReaderBoundsEventsPerPoll`（6 万行：交出 ≤ 20000 个、最后一个事件就是最后一行、之后的增量读取照常）。
- 修复前失败的证据（撤销上限后重跑）：`一次 poll 交出了 60000 个事件`；`丢掉了旧事件，应当通知调用者作废…`。
- 修复后：passed。
- 状态：已修复。

### C-030 [P3] 几处小的整数换算 / 参数校验（FileIO 与 dump）
- 现象：① `FileIO.readAll(path, maxBytes: 负数)` 在 `UInt64(maxBytes)` 里 trap；② `FileStat` 的修改时间 `tv_sec * 1_000_000_000` 在秒数很大时溢出（APFS 会把时间夹在 ±9223372036 秒内，所以本机构造不出这个输入；网络盘 / 别的文件系统可能有）；③ `DumpFormatter.clock(sec)` 对天文数字 / NaN 做 `Int(sec)` trap（dump 工具）；④ `writeAtomically` 写到一半失败时（磁盘满）不删临时文件。
- 根因：`Util/FileIO.swift:73-74, 83, 131-133`；`Tools/DumpCommand.swift:245`。
- 修法：`readAll` 负数上限返回 nil；`FileIO.mtimeNs` 饱和乘 / 加；`clock` 夹范围 + 处理 NaN；写失败时 unlink 临时文件。
- 回归测试：`c030_smallIntegerConversionsDoNotTrap`（①②③；④ 需要磁盘满，构造不出来，只修不测）；`FuzzFileIOTests/specialFiles` 也覆盖 ①。
- 修复前失败的证据（三处分别撤销后重跑）：① `Fatal error: Negative value is not representable`；② `static FileIO.mtimeNs(sec:nsec:) FileIO.swift 109` `arithmetic overflow`；③ `Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max`。
- 修复后：passed。
- 状态：已修复。

### C-031 [P3] 既有测试文件里有编译警告（不是本轮新增的）
- 现象：`Tests/BuddyCoreTests/HelperAttributionTests.swift:262`：`#expect((h.snap(DesktopFixture.key)?.helpers ?? []).isEmpty)` → `warning: left side of nil coalescing operator '??' has non-optional type '[HelperSnapshot]?', so the right side is never used`（宏展开里还有一条 `expression of type 'Bool?' is unused`）。DESIGN.md 里说的「debug 和 release 构建都是 0 警告」指的是库目标，测试目标里有这一条。
- 根因：`snap(_:)?.helpers` 已经是可选链，`?? []` 是多余的（而且 `isEmpty` 作用在 `Optional` 上，可选为 nil 时的行为和作者想的不一样：`nil?.isEmpty` 是 nil，`#expect(nil)` 会失败）。
- 修法：把取值拿到宏外面（`let shown = h.snap(DesktopFixture.key)?.helpers ?? []`，再 `#expect(shown.isEmpty)`），断言的意思不变。数据层负责人当时按分工没有改既有测试文件，由主线程接手。
- 回归测试：这条本身就是测试文件里的警告；修复后 debug 测试目标 0 警告（`QA/evidence/regression-final/summary.txt`）。
- 状态：已修（主线程接手；改的是取值的写法，没有削弱断言）。

### C-032 [P3] BuddyOffice 的 `JumpService.DesktopMeta` 在调用线程同步读取全部桌面元数据文件，并且绕过 `FileIO`
- 根因：应用层另写了一套无缓存的读取，没有复用数据层带缓存的 DesktopMetaReader，也绕过 FileIO；点击处理在主线程调用。
- 回归测试：见 issues-app.md A-014（`CachesTests`：读盘次数）。
- 现象：`Sources/BuddyOffice/JumpService.swift:152-176`：`isMostRecentlyFocused` / `lastFocusedAt(host:)` 每次都 `contentsOfDirectory` 三层目录、把每个 `local_*.json`（每个约 20 KB）整个读进来解析，而且直接用 `FileManager.default.contents(atPath:)`——不走 `FileIO`（违背「FileIO 是唯一入口」的约定；它只读 `local_*.json`，不会碰 `.key`，所以没有违反安全红线）。从点击处理（主线程）调用时，桌面元数据文件多的话会卡界面。
- 修法（已做的部分：改走 FileIO）：改用 BuddyCore 已经建好的索引（快照里带 `lastFocusedAt` 就不用再读文件），或者至少放到后台队列并走 `FileIO.readAll`。**没改**：BuddyOffice 不在我的范围内。
- 状态：已修（主线程接手：读目录 / 读文件改走 `FileIO`，见 `DesktopMetaFileIOTests`（源码审计 + FIFO 诱饵；不碰全局的 FileIO 计数器，见 R2-005）；缓存和读盘次数见 issues-app.md A-014。点击时仍在主线程读一遍（3–8 ms 量级），作为 P3 接受）。

### C-033 [P3] BuddyStage 对数据层给出的时间差做 `Int(…)` 换算，自己没有防护
- 根因：表现层对数据层给出的时间差直接 `Int(x)`，没有自己的范围保护（数据层现在已经夹住了这些值，所以此前不可达）。
- 现象：`Sources/BuddyStage/PlateCopy.swift:46, 52, 104`、`Performer.swift:120` 等处对 `TimeInterval` 直接 `Int(x)`，超出 Int 范围会 trap。现在数据层保证了这些值在合理范围（C-002 / C-003 / C-025 / C-026），所以不可达；但表现层如果自己也夹一下（`min(max(x, 0), 1e9)`）就是双保险，以后数据层再出新的坏值也不会主线程崩溃。
- 修法：`PlateCopy.wholeSeconds`（基于 `safeInt`，夹到 0…10 亿秒）用在 `duration / spoken / waitSpoken / idleMinutes`，`HoverCard.ago`；`Performer` 里 MCP / 未知工具的 `safeInt(elapsed / 3)`。见 `issues-stage.md` 末尾。
- 回归测试：`ExtremeValuesTests`（3 个测试；修复前把 `wholeSeconds` 换回 `Int(x)`，测试进程 SIGTRAP）。
- 状态：已修（表现层负责人接手）。

### C-034 [—] 已确认不是问题：`FileWatcher` 的 FSEvents 回调里用 `passUnretained(self)`，对象释放后排队的回调块会不会解引用野指针
- 怀疑：`stop()` / `deinit` 之后，队列里已经排着的回调块还会执行，`takeUnretainedValue()` 访问已释放的对象。
- 验证：`FuzzWatcherTests/stopWhileCallbacksAreQueuedDoesNotTouchFreedMemory`：先把回调队列堵住，造一批文件事件让 FSEvents 把回调块投递进去，然后 `stop()` + 释放对象，再放行队列；重复 20 轮，**配合 `MallocScribble=1 MallocPreScribble=1`（释放的内存填 0x55）**也没有崩溃，说明 `FSEventStreamStop / Invalidate` 之后排队的回调块不再执行。
- 状态：已确认不是问题（保留测试作为回归保护）。

### C-035 [—] 已确认不是问题：句柄泄漏
- 怀疑：`FileIO.open` 的调用点、`opendir`、`FSEventStream`、`DispatchSourceTimer` 有没有成对释放。
- 验证：逐个读了每个 `open / opendir / FSEventStreamCreate / makeTimerSource` 的释放路径（`defer { close(fd) }`、`defer { closedir }`、`FSEventStreamStop → Invalidate → Release`、`stop()` 里 `timer.cancel()`）；`FuzzFileIOTests/noFileDescriptorLeaksAcrossReaders`：把所有读取器在 8 种文件（正常 / 目录 / FIFO / .key / 指向 .key 的符号链接 / 普通符号链接 / 不存在 / 被删）上跑 400 轮 + FSEvents 启停 40 次，文件描述符个数不涨。**检测器本身也验证过**：故意让 `readAll` 少一个 `close`，同一个测试报 `文件描述符从 3 涨到了 1207`。
- 状态：已确认不是问题。

---

## 2. 已审查文件 / 检查项清单

检查项：**A** 强制解包 / `try!` / `as!` / `fatalError`；**B** 下标 / 指针越界；**C** 整数溢出 / `Int(Double)` / 无符号下溢；**D** 除零；**E** 无界增长；**F** 句柄 / 资源成对释放；**G** 闭包循环引用；**H** 共享可变状态的锁；**I** 主线程同步文件 IO；**J** 外部输入 / 路径安全。

| 文件 | 行数 | 查了什么 | 结论 |
|---|---|---|---|
| `Paths.swift` | 62 | A–D、J：`isSafeID` / `isRegistryFileName` / `hookLogPath` 和按字节写的独立判断对照 2 万个随机串（Unicode 数字、换行、NUL、组合字符、超长） | 规则正确；`init` 去斜杠 O(n²) → C-027 |
| `Model/Activity.swift` | 82 | 枚举 / 值类型；`ToolCall` 无算术 | 无问题 |
| `Model/BuddySnapshot.swift` | 200 | C：`TokenBreakdown.total` | 溢出 → C-005（改饱和加法）；其余是数据结构 |
| `Util/FileIO.swift` | 186 | A–C、F、H、J：保险绕过 / FIFO / 溢出 / 临时文件；全部 `open` 调用点；锁 | C-007 / C-008 / C-024 / C-030；`_observer`、`_forbiddenHits`、`_tmpCounter` 都在锁里；源码扫描测试保证它是唯一读入口 |
| `Util/TimeUtil.swift` | 180 | B、C：所有下标（`parseISO` 的 `bytes[i + 1]` 等都有长度保护）；乘法；`Int(Double)`；格式化 | C-001 / C-002 / C-003（范围）；`parseISO` 加了合理范围；格式化夹范围 |
| `Util/Hashing.swift` | 35 | C、D：`&*` / `&+` 都是回绕运算；`below(_:)` 有 `max(n,1)` | 无问题 |
| `Util/Info.swift` | 4 | 常量 | 无问题 |
| `Util/SafeJSON.swift`（新增） | 68 | 深度扫描 / 字符串上限 | C-012 / C-023 的修复本身；被 8 个解析点使用 |
| `Ingest/DesktopMetaReader.swift` | 200 | B、C、E、J：`refresh` 三层目录遍历、`parse` 全部字段类型、索引一致性 | C-010 / C-020 / C-023；`refresh` 每 0.5 秒 stat 全部元数据文件（O(文件数)）→ 剩余风险 |
| `Ingest/FileWatcher.swift` | 96 | A、B、F、G：`unsafeBitCast(eventPaths)`（`UseCFTypes` 标志下成立）、`eventFlags[i]`（`i < count`）、Stream 的 Create/Start/Stop/Invalidate/Release 成对、`passUnretained` 的生命周期 | C-022（递归）；C-034（生命周期，已确认不是问题） |
| `Ingest/HookLogReader.swift` | 58 | E | C-029 |
| `Ingest/JSONLTailer.swift` | 205 | B、C、E、F：`memchr` 指针算术、`pending` 上界、`committedOffset` 下溢、超长行 / 半行 / 轮转 / 截短；**和独立实现逐行对照** | 逻辑无 bug（0 个发现，见覆盖矩阵）；C-013（窗口参数）/ C-015（容量）；`defer { close }` 齐全 |
| `Ingest/LineSanitizer.swift` | 151 | B、C、E、J：严格 / 降级两条解析路径、截断到每个字节、非法 UTF-8、坏转义 | C-003 / C-023；降级扫描的数字终止符 |
| `Ingest/ProcessProbe.swift` | 104 | C、J：`pid <= 0` 不发信号、`startTime(of:)` 的 sysctl 结果处理、`classify` 极端时间 | 无问题（`kill(pid, 0)` 只做存在性检查；sysctl 返回 0 字节时按 nil） |
| `Ingest/RegistryScanner.swift` | 231 | A、C、E、J：`entry!.nextRetryAt!`（前面一行刚设过）、重试节拍、`Int32(文件名)`、`pidNum.int32Value` | C-001（procStart）/ C-017 / C-023；只 stat / open 匹配 `^\d+\.json$` 的文件 |
| `Ingest/SubagentReader.swift` | 209 | E、J：helpers / order 增长、meta 重试、目录遍历只认 `agent-*.jsonl` | C-021 / C-023；helpers 只增不减（与磁盘上的文件数成正比，每个约几 KB）→ 剩余风险 |
| `Ingest/TokenLedger.swift` | 392 | C、E、H：累加、恢复、锁、`queue.sync`、文件 / 去重表增长 | C-004 / C-005 / C-014 / C-016 / C-028；**和独立实现逐项对照**（含跨文件去重、断点恢复） |
| `Ingest/TranscriptLine.swift` | 238 | C、E：usage 数字、tool 名 / id、`ToolDetail` | C-004 / C-018 / C-023 / C-025 |
| `Ingest/TranscriptReader.swift` | 231 | A、C、E：`apiError!.at`（前面有 nil 判断）、`bootstrap` 循环、`TranscriptLocator.find` | C-013 / C-026；`Paths.isSafeID` 保证不会拼出 `../` |
| `Fusion/ActivityResolver.swift` | 192 | C：纯函数，只有 `Date` 运算，随机信号 2 万组 | 无问题（阶段和动作一致、`nextChange` 一定在未来）；输入里的未来时间戳问题在入口处解决（C-026） |
| `Fusion/BuddyState.swift` | 132 | E：`inbox` / 读取器 | 无问题（`resetSessionScope` 全部作废） |
| `Fusion/HelperAttributor.swift` | 121 | C、E：`Int(…)`、`claimed` 清理、扣留 | C-003 / C-006；`claimed` 每次 update 清理（600 秒）✓ |
| `Fusion/IdentityResolver.swift` | 264 | A–C、E：载入 / 存盘 / 别名 / 工位 / 时间 | C-002 / C-009；别名 / 索引的清理逻辑正确 |
| `Fusion/SessionEngine.swift` | 1063 | A–C、E、J：`entry!` / `meta!` / `lastMetaRefreshAt!`（都紧跟在 nil 判断之后）、缓存、拼路径（`hookLogPath` / `locateTranscript` 都过 `isSafeID`）、轮次判定 | C-014 / C-026；整机随机灌数据（3 个种子 × 500 步）无崩溃、快照不变量成立 |
| `Fusion/SessionSignals.swift` | 65 | 数据结构 | 无问题 |
| `Fusion/SessionStore.swift` | 250 | F、G、H、I：定时器 / 监听器的释放、`[weak self]`、队列使用、20 Hz 限速、并发 API | C-019；线程安全用 4 个线程同时乱用公开 API + 数据变化压力测试验证（无死锁 / 崩溃）；`diagnostics()` 是 `queue.sync`，主线程会等一次 tick（见下面 I 项） |
| `Fusion/ToolCatalog.swift` | 55 | 字符串处理 | 无问题（随机字符串 3000 个，含 `…` / emoji / RTL / NUL） |
| `Fusion/ToolTracker.swift` | 150 | E | C-011 |
| `Tools/DumpCommand.swift` | 290 | C：`Int(sec)`、`String(format:)` | C-030 |
| `Tools/FakeTree.swift` | 323 | A：`raw.baseAddress!`（只在循环体里、`count > 0` 才进） | 无问题；只写文件（测试夹具），不读 |
| `Tools/ReplayCommand.swift` | 631 | 根目录安全（必须是空目录或不存在）、除零（`pct` 有非空保护）、`Int(…)` | 无问题 |

**A 全仓库扫描**：`try!` / `as!` / `fatalError` / `precondition` / `assert` 在 BuddyCore 里 **0 处**；`!` 强制解包共 10 处（SessionEngine 6 处、RegistryScanner 1 处、TranscriptReader 1 处、FakeTree 2 处），逐个确认前面都有 nil / 长度保护。
**I 主线程同步文件 IO**：`grep` 了 `Sources/BuddyOffice`：BuddyCore 的公开同步读文件函数（`FileIO.*`、`TranscriptLocator.find`、各个 Reader）**没有一个被 BuddyOffice 直接调用**；App 只通过 `SessionStore`：`start()` 是 `queue.async`、`markSeen` / `rerollAppearance` 是 `async`；`stop()`（`applicationWillTerminate` / 切换演示模式时）和 `diagnostics()`（设置页打开 / 刷新时）是 `queue.sync`——主线程会等 ingest 队列跑完当前那一次 tick（毫秒级，首次 tick 读尾部窗口也只有几十毫秒），退出时 `TokenLedger.flush()` 会再等一次当前文件的后台扫描（最长约一个大文件的扫描时间，README 里 44 MB 是 0.3–0.5 秒）。
唯一直接读数据文件的是 BuddyOffice 自己的 `JumpService.DesktopMeta`（C-032）。

## 3. 成员集合（缓存 / 字典 / 数组）上界表

| 位置 | 集合 | 键 / 内容 | 上界或清理 | 结论 |
|---|---|---|---|---|
| `RegistryScanner.entries` | `[Int32: Entry]` | pid | 每次扫描删掉目录里已经没有的 pid | ✓ |
| `RegistryScanner.cachedListing` | 单个 | 目录列表 | 单个值，2 秒过期 | ✓ |
| `DesktopMetaReader.index / pathToHost / cliIndex` | 字典 | host / 路径 / cliSessionId | 文件消失时删；`cliIndex` 每次变化重建；prior ids ≤ 256/个 | ✓（C-010） |
| `DesktopMetaReader.shadowed` | 字典 | 副本路径 | 文件消失 / 赢家消失时删 | ✓（C-020 新增） |
| `SubagentReader.helpers / order` | 字典 + 数组 | 子代理文件 | 与磁盘文件数成正比；读取器随 buddy 离场 / 换会话释放；已完成的只留几 KB | 有界（按文件数）；剩余风险 |
| `TranscriptFacts.openToolUses / recentToolUses` | 数组 | 工具调用 | 64 / 32，超出丢最老 | ✓ |
| `TokenLedger.files / fileList / filesById` | 字典 + 数组 | 跟踪的文件 | 没人用的 ≤ 64（转存断点后清出） | ✓（C-014） |
| `TokenLedger.messages` | `[UInt64: Rec]` | message.id 哈希 | 随文件清出一起删；单文件受文件大小限制 | ✓（C-014） |
| `TokenLedger.persisted` | 字典 | 账本里的断点 | 只增加被清出去的文件；写盘时丢掉磁盘上已不存在的文件 | ✓ |
| `TokenLedger.groups / groupNoLedger` | 字典 / 集合 | buddy key | `removeGroup` 都删（原来漏了 `groupNoLedger`） | ✓ |
| `IdentityResolver.identities / aliasIndex` | 字典 | key / 别名 | 载入 ≤ 2000 个、别名 ≤ 40/个；7 天过期（存盘时清理） | ✓（C-009） |
| `IdentityResolver.lastPersistedSeen` | 字典 | key | 过期时同步删（原来漏了） | ✓（C-009） |
| `ToolTracker.open / closed` | 数组 | 调用 | 512 / 64 | ✓（C-011） |
| `HelperAttributor.claimed` | 字典 | tool_use id | 每次 update 清理 600 秒前的 | ✓ |
| `BuddyState.inbox` | 数组 | hook 事件 | 每次 poll 排空；扣留最多 400 ms（C-006）；一次交入 ≤ 20000（C-029） | ✓ |
| `HookLogReader.PollResult.events` | 数组 | 事件 | ≤ 20000/次 | ✓（C-029） |
| `JSONLTailer.pending` | `[UInt8]` | 半行 | ≤ maxLine + 一个块；读完释放 | ✓（C-015） |
| `SessionEngine.buddies` | 字典 | buddy key | 离场 8 秒后删；下班工位 ≤ 4、12 小时过期 | ✓ |
| `SessionEngine.resolvedKeys / livenessCache` | 字典 | pid | 每次 poll 清理已经不在的 pid | ✓ |
| `SessionEngine.transcriptPathCache / transcriptMissAt` | 字典 | sessionId | 每 30 秒清理 | ✓（C-014） |
| `SessionStore.lastSnapshots / latestSnapshots` | 数组 | 快照 | 与 buddy 数成正比 | ✓ |

## 4. 其它审查项（句柄 / 闭包 / 线程 / 锁）

- **句柄**：`FileIO.open` 的三个调用点（`readAll`、`JSONLTailer.poll`、`JSONLTailer.seekToTail`）都是 `defer { close(fd) }`；`listDirectory` 是 `defer { closedir }`；`FSEventStream`：Create 失败不需要释放、Start 失败走 `Invalidate + Release`、`stop()` 是 `Stop → Invalidate → Release`，`deinit` 也调 `stop()`；`SessionStore` 的 `DispatchSourceTimer` 在 `stop()` 里 `cancel()`。实测见 C-035。
- **循环引用**：`SessionStore` 里所有回调都是 `[weak self]`（`TokenLedger.onChange`、`FileWatcher` handler、定时器 handler、`callbackQueue.async`）；`TokenLedger.poke` 的 `queue.async` 是 `[weak self]`；没有发现循环引用。
- **锁**：`FileIO`（观察口 / 计数 / 临时文件计数）、`TokenLedger`（除 C-016 之外的状态都在锁里，`flush` / `waitUntilIdle` 逻辑见上）、`FakeProcessProbe` / `VirtualClock` / `SessionStore.latestSnapshots` 都有锁；`SessionEngine` 及其读取器只在 ingest 队列上使用（由 `SessionStore` 保证，`applicationWillTerminate` 也是 `queue.sync`）。
- **主线程**：见上面 I 项。

## 5. 「解析器 × 模糊类别」覆盖矩阵

列：**A** 每个字节位置截断（含多字节 / `\uXXXX` 中间）；**B** 随机字节（0/1/2/7/64/4096/1 MiB）；**C** 半行 / 只有换行 / 很多空行；**D** 超长行（1.5 MB / 恰好 4 MiB / 4 MiB+1 / 16 MiB）；**E** 非法 UTF-8；**F** 写到一半（逐步追加）/ 截短 / 轮转 / 换 inode；**G** JSON 层面（深嵌套 / 超出 Int64 / 负数 / 浮点当整数 / 类型错误 / null / 重复键 / 超长键 / 空对象数组）；**H** 持久化文件被截断 / 乱码 / version 不对 / 字段缺失。「—」= 该类别对这个解析器不适用（原因在括号里）。

| 解析器 | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| `JSONLTailer`（poll / seekToTail / committedOffset / seek） | `tailerResumeFromCommittedOffset`（100 个恢复点）、`tailerSeekToTailAlignsToLineStart`（150 个窗口） | `tailerRandomBytesOfEveryLength` | `tailerHalfLinesAndBlankLines`、`tailerMatchesTheReferenceOnRandomFiles`（120 轮 × 极小块 / 极小行上限，逐行对独立实现） | `tailerOversizeLineBoundaries`（4 档 + 半行补完） | `tailerMatchesTheReference…`（片段里含非法字节） | `tailerIncrementalAppendsEqualOneShot`、`tailerSurvivesTruncationRotationAndReplacement` | —（字节级） | — |
| `LineSanitizer` / `HookLogReader` | `hookLineTruncatedAtEveryByte`（8 个样本 × 每个字节） | `hookLineRandomBytes` | `hookReaderIncrementalEqualsOneShot` | `hookLineJSONLevel`（1 MiB 键 / 值）、`RobustnessTests.aHugeGarbageLine…`、`c029`（6 万行） | `hookLineWithInvalidUTF8Everywhere`（24 种 × 行首 / 行尾 / 每个字段）、坏转义 13 种 | `hookReaderIncrementalEqualsOneShot`、`c029` | `hookLineJSONLevel`（30 种）、`c003` | — |
| `TranscriptLineParser` / `TranscriptReader` / `TranscriptFacts`（含 token usage） | `transcriptLineTruncatedAtEveryByte`（9 种行 × 每个字节） | `transcriptLineRandomAndTypeConfusion` | `transcriptReaderIncrementalEqualsOneShot` | `FuzzEngineTests.engineSurvivesExtremeValuesEverywhere`（1 / 4 / 4 MiB+1 的行）、tailer 那一组 | `transcriptLineRandomAndTypeConfusion`（变异里插入非法 UTF-8） | `transcriptReaderIncrementalEqualsOneShot`、引擎整机（截短 / 删除 / 换掉） | `transcriptLineRandomAndTypeConfusion`（2500 个随机类型）、`c004`、`c012`、`c025` | — |
| `RegistryScanner`（parse + scan） | `registryTruncatedAtEveryByteIsHalfWritten` | `registryRandomBytesAndMutations` | `registryScannerConvergesUnderRandomRewrites`（清空） | 由 `FileIO.readAll(maxBytes)` 覆盖（`specialFiles`） | `registryRandomBytesAndMutations` | `registryScannerConvergesUnderRandomRewrites`（半写 / 垃圾 / 删除 / 换类型 60 轮）、`fuzz_registryScannerWithDecoyFiles` | `registryJSONLevelAgreesWithOracle`（4000 个 + 独立判断）、`c001`、`c017` | — |
| `DesktopMetaReader`（parse + refresh） | `desktopMetaTruncationAndTypeConfusion` | 同左 | — | `desktopMetaRefreshOnJunkTree`（4 MiB+10） | 同 B | `desktopMetaRefreshOnJunkTree`（改 / 删 / 来回折腾） | `desktopMetaTruncationAndTypeConfusion`（3000 个 + 独立判断）、`c010`、`c020`、`c023` | — |
| `SubagentReader`（poll + meta） | —（jsonl 走 TranscriptReader） | `subagentReaderOnJunkDirectory`（垃圾 meta / 记录） | 同左 | — | 同左 | `subagentReaderOnJunkDirectory`（追加 / 截短 / 删除 / 新文件） | `subagentReaderOnJunkDirectory`（`FuzzJSON` 的 meta） | — |
| `TokenLedger`（扫描 + `ledger.json`） | `ledgerTruncatedAtEveryByte`（前 90 / 后 90 / 随机 50 个位置） | `ledgerGarbageDirectoryAndUnreadable`（0…1 MiB 垃圾） | `ledgerMatchesIndependentReference`（垃圾行 / 半行） | 已有 `aBigFileIsScannedFast` + 引擎整机 | 同 A（`ledgerRandomCorruption` 插入非法 UTF-8） | `ledgerMatchesIndependentReference`（追加 + 重启断点续读）、`ledgerGroupAcrossFilesMatchesReference`（跨文件去重） | `ledgerFieldwiseMutations`（version / files / 每个字段 13 种错误类型）、`c004`、`c005` | 同 G + `ledgerRandomCorruption`（100 个）、`ledgerGarbageDirectoryAndUnreadable` |
| `IdentityResolver`（`identities.json`） | `identitiesTruncatedAtEveryByte` | `identitiesCorruption`（0…1 MiB 垃圾） | — | — | `identitiesCorruption` | — | `identitiesCorruption`（每个字段 16 种错误类型）、`c002`、`c009` | 全部；`engineOverwritesGarbagePersistenceFiles`（引擎启动时两个文件都是垃圾） |
| `TimeUtil`（parseISO / parseProcStart / JSON 毫秒 / 格式化） | `timeISOFuzz`、`timeProcStartAndJSONMillisFuzz`（每个前缀） | 同左 | — | — | 同左（变异插入非法 UTF-8；Unicode 数字） | — | `timeProcStartAndJSONMillisFuzz`（NSNumber 各种形态：布尔 / UInt64.max / Int64.min / NaN / 无穷） | — |
| `ProcessProbe`（`SystemProcessProbe` / `classify`） | — | `processProbeFuzz`（随机 pid 2000 个 + 极端 pid） | — | — | — | — | `processProbeFuzz`（极端时间的 `classify` 组合） | — |
| `FileWatcher`（路径 / 分流） | — | — | — | — | `weirdFileNamesArriveIntact`（Unicode / 换行 / 空格 / 超长） | `stopWhileCallbacksAreQueued…` | `c022`（畸形路径）、`c019`（分流） | — |
| `FileIO` / `Paths` | — | `specialFiles`、`pathRulesAgreeWithByteOracle`（2 万个） | `specialFiles`（空文件） | `specialFiles`（maxBytes 边界） | `pathRulesAgreeWithByteOracle`（组合字符 / NUL / RTL） | `specialFiles`（读的时候被截断）、`c024` | — | — |
| 引擎整机（所有数据源一起） | — | — | — | 4 MiB 级长行 | 是 | `engineSurvivesExtremeValuesEverywhere`（3 个种子 × 500 步，含 4e9 秒的时间大跳跃）、`engineWithHundredsOfSessionsComingAndGoing` | 极端值随机灌入每个数据源 | 是 |

任务书第 4 节的已知坑对应用例：tool 名被截断（`hookKnownPitfallsUnderMutation`：48 个截断长度 × 前缀匹配）；`\u` 转义被截断（`hookLineTruncatedAtEveryByte` 的「转义」样本、`hookLineWithInvalidUTF8Everywhere` 的坏转义）；AskUserQuestion 的 detail 不能当问题（hook 层 300 次变异 + 会话记录层 C-018）；Codex 文件不能碰（`hookKnownPitfallsUnderMutation`：非 sessionId 一律拼不出路径；`FileAccessTests.codexHookFilesInTheSameDirectoryAreNeverTouched` 已有）；用户输入永不留下（hook 层 200 次变异 + `transcriptFactsNeverKeepConversationText`：用户输入 / 助手文字 / 工具结果 / thinking 的内容不出现在任何解析结果里）。

## 6. 「绝不打开 `*.key` / `*.sock`」保护是否无法绕过

结论：**现在绕不过去**（修复前有四条绕过，C-007）。

| 绕过方式 | 修复前 | 现在 |
|---|---|---|
| 大小写（`.KEY` / `.Sock` / `CC-SOCKS`） | 认不出来 | 认得出（不区分大小写；开尔文符号 K 也算） |
| 符号链接（`<pid>.json → *.key`，链式，目录符号链接，相对符号链接） | 读到内容 | `realpath` 解析后拒绝，`open` 都不调用；打开后 `F_GETPATH` 再核对一次 |
| `../`、`./`、`//`、结尾 `/` | `..` 靠 `lastPathComponent` 已经能挡 | 仍能挡（27 种变体测试） |
| 路径里的 NUL | 真的打开了 | 直接拒绝 |
| 带空格 / Unicode / 换行的路径 | 名字判断只看后缀，不受影响 | 同左（诱饵目录里有 `new\nline.json`、`٣٤.json` 等） |
| `<pid>.json` 与 `<pid>.<sha256>.key` 的边界 | `isRegistryFileName` 只认 `^\d+\.json$`（≤ 10 位 ASCII 数字），`.key` 文件连 stat 都不碰 | 同左；和按字节写的独立判断对照 2 万个随机串一致 |
| 命名管道 / 设备 / socket / 目录 | `open` 会阻塞（C-008） | 只打开普通文件 |
| **硬链接**（同一个 inode 的另一个名字） | 挡不住 | **仍然挡不住**：从路径和 `F_GETPATH` 都看不出这个 inode 也叫 `.key`；要求攻击者能在 `~/.claude/sessions` 里建硬链接，那时他自己已经能读 key 了 → 剩余风险 |

**`FileIO` 是不是所有读取的唯一入口**：`grep` 了 `Sources/BuddyCore` 里所有 `open( / Darwin.open / FileHandle / Data(contentsOf / String(contentsOf / contentsOfFile / fopen / read( / pread( / URL(fileURLWithPath / FileManager`：读取只有 `FileIO`（`open` / `readAll` / `stat` / `fstat` / `listDirectory`）；`pread` 只出现在 `FileIO.swift` 和 `JSONLTailer.swift`（读的是 `FileIO.open` 给的 fd）；`Tools/FakeTree.swift` 有 `open(O_WRONLY…)`，是造假数据的**写**；`URL(fileURLWithPath:)` 只在 `FileIO.writeAtomically`；`FileManager` 只在工具（建 / 删临时目录）里。这条约定现在有测试守着：`FuzzFileIOTests/fileIOIsTheOnlyReaderInSources`（源码扫描，任何人以后在别处加 `open(` 都会失败）。
`FileWatcher.resolved` 用 `realpath`（只解析路径，不读文件内容）。BuddyOffice 里唯一绕过 FileIO 的是 `JumpService.DesktopMeta`（C-032，只读 `local_*.json`）。

## 7. 剩余风险（没修 / 修不了 / 需要别人决定）

1. **硬链接**指向 `.key` 的文件读取保险挡不住（见上）。威胁模型里攻击者已经在同一用户下，只作记录。
2. **同一个 inode 原地重写、而且新内容比旧偏移长**的情况，`JSONLTailer` 无法察觉（只看 inode 和大小）；会话记录 / hook 文件是只追加的，所以正常使用不会碰到。
3. **过去的时间戳没有夹**：只夹了「比现在晚一天以上」的（C-026）；一条时间戳很旧（比如 2001 年）的行不会毒化「取最大值」类的事实，但会让「最早」类的取值（`estimateTurnStart` 取 `min`）变成很久以前 → 本轮用时显示为几十年。数值仍在合理范围（不会溢出）。
4. **`JSONLTailer.poll` 一次读完所有新增字节**（没有单次预算）：App 被挂起几小时后醒来，一个 50 MB 的增量会在 ingest 队列上解析 0.5～1 秒。`HookLogReader` 有事件数上界（C-029），会话记录没有（要加预算需要改「事实是否已追平」的语义，属于设计变更，没动）。
5. **`SubagentReader.helpers` 只增不减**（每个几 KB，与磁盘上的子代理文件数成正比）；一次 Workflow 派几百个子代理时会有几 MB。
6. **`DesktopMetaReader.refresh` 每 0.5 秒 stat 全部 `local_*.json`**：元数据文件很多（上千个）时是每秒几千次 stat。要优化需要目录级签名（元数据是原地重写，目录签名不变，做不了）。
7. **退出时 `TokenLedger.flush()` 会等当前文件的后台扫描**（在主线程，最长约一个大文件的扫描时间）。
8. ThreadSanitizer / AddressSanitizer 各把全量测试跑了一遍（0 条报告），但只覆盖测试触发的路径；真实 App 里 FSEvents、主线程回调和 ingest 队列的交织没有在消毒器下跑过（用户拒绝了对 App 的 GUI 自动化，见 PROGRESS.md）。
9. **表现层没有自己的防护**（C-033）和 BuddyOffice 的直接读文件（C-032）在我的范围外。
10. 测试用的是 `.dev/core` 隔离包（BuddyCore 用 `-Onone`）+ 根包（BuddyCore 用 `-O`）两套配置各跑一遍；没有在 release 配置下跑测试（`Package.swift` 的 `optimizedLibs` 只对 debug 生效）。
