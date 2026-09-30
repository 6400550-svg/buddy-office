# 任务书第 4、5 节 · 逐条 spec-trace（数据源 + 状态判定 + 表现层节奏）

> QA 只读追踪：只读源码和测试，**没有编译、没有运行任何测试**（按要求不跑 `swift build` / `swift test`）；每个 ✓ 都是打开对应源码和测试逐行确认过断言之后才写的。
> 追踪基于 2026-09-29 03:10–03:30 的源码 / 测试快照。**同一时间有别的 QA 在并行改代码和加测试，所以这份表是「一个时间点」的结论**：
> - 我第一次读完之后，`Core/Fusion/SessionEngine.swift`（03:20）、`Core/Util/TimeUtil.swift`、`Core/Ingest/LineSanitizer.swift`、`Core/Fusion/HelperAttributor.swift`、`Core/Ingest/TranscriptLine.swift`、`Core/Ingest/TokenLedger.swift`、`Core/Model/BuddySnapshot.swift`、`Core/Util/FileIO.swift`（03:24–03:25）、`Stage/OfficeScene.swift`（03:21–03:25）被改过，`IdentityResolver` / `ToolTracker` / `DesktopMetaReader` / `JSONLTailer` / `TranscriptReader` 在 03:25:51 又被改。我把这些文件里和本表有关的函数**重读**过，规则和数字的结论对得上改动后的版本；**但行号已经漂移**（`SessionEngine.swift` 第 653 行之后整体后移了 3 行，别的文件漂移不等），以函数名为准。
> - `Tests/BuddyCoreTests/` 里有几份是我读到一半才出现的：`StateRuleTests.swift`、`StateRuleProcessTests.swift`、`StateRuleChainTests.swift`、`StateRuleInvariantTests.swift`（别的 QA 的「逻辑线」，03:19–03:29）和 `FuzzRegressionTests.swift` / `FuzzSupport.swift` / `FuzzTailerTests.swift`（模糊测试线，03:08–03:30）。我读过它们的断言并把对得上的写进了各行，在「测试」列里用「新：」标出；**这些新测试我没有运行**，其中 Fuzz 那份是「先写失败测试、再修」的回归测试，修复可能还在进行。
> - 两个我一开始怀疑的问题已经被别人修掉了（疑点 Q-01、Q-10），表里保留记录。

## 怎么读这份表

- 路径缩写：`Core/` = `Sources/BuddyCore/`；`Stage/` = `Sources/BuddyStage/`；`App/` = `Sources/BuddyOffice/`；`T-Core/` = `Tests/BuddyCoreTests/`；`T-Stage/` = `Tests/BuddyStageTests/`；`T-Py/` = `Tests/hook_merge_test.py`。测试写成「文件 › 测试函数名」。`Lnnn` = 行号。
- 任务书位置：4.x / 5.x 是任务书章节，后面是小标题。
- 状态（只用下面六个）：
  - **✓**：实现了，而且有测试的断言真的检查到了这条要求的数字 / 行为。
  - **✓(无专门测试)**：实现了，但没有测试，或者测试只覆盖了枚举里的一部分 / 只验了阈值的一侧 / 断言够不到这个数字（「测试」列会写「无」或「弱：…」「部分：…」说明）。
  - **偏离**：实现和任务书不同，且在 DESIGN.md 里找到了理由（写在「实现」列末尾的「记录：…」里）。DESIGN.md 第 4 节明说「约 40 条小决定都在 Sources/BuddyCore/README.md」，所以只记在 README 里的也标「偏离」，同时在缺口里提醒补进 DESIGN 汇总表。
  - **偏离-未记录**：实现和任务书不同，DESIGN.md / README 里都没找到记录。
  - **缺失**：任务书要求但没实现。
  - **N/A**：任务书自己说了不适用 / 可选 / 只是环境事实，理由写在行里。
- 表里不含任何对话内容（prompt）。

---

## 4（章首说明）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.0-01 | 4 章首 | 全部只读，不需要任何配置就能拿到全部状态 | Core/Util/FileIO.swift（只读 `open(O_RDONLY)`）；Core/Paths.swift `Paths.real`（默认真实 home，只有 `--data-root` 才换根） | T-Core/RegistryTests › engineNeverWritesUnderClaudeDir | ✓ |
| 4.0-02 | 4 章首 | 旧笔记 `~/.claude/monitor/DATA-SOURCES.md`（8 月版本）可以参考，冲突时以本节为准 | — 参考资料；与实测不一致的地方见 DESIGN.md 第 4 节末段、Core/README.md「数据源实测结论」 | — | N/A |

---

## 4.1 活会话登记表 `~/.claude/sessions/<pid>.json`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.1-01 | 4.1 文件规则 | 每个活 claude 进程一个 `<pid>.json`，进程退出文件被删 | Core/Ingest/RegistryScanner.swift `scan` L183-186（文件消失 → removed）；Core/Fusion/SessionEngine.swift `reconcile` L261-275（消失 → pendingAway） | T-Core/RegistryTests › removedFilesAreReported；EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat（endProcess 同时删文件 + 杀进程，是混合触发） | ✓ |
| 4.1-02 | 4.1 文件规则 | 只打开文件名匹配 `^\d+\.json$` 的文件 | Core/Paths.swift `isRegistryFileName` L54-60（另限 ≤10 位数字）；RegistryScanner.`scan` L122 | RegistryTests › fileNamePattern（123.json 过；`.key`、`.sha.json`、abc.json、12a.json、`.json`、`.json.bak` 全拒）；新：StateRuleTests › n2_onlyPidJsonFilesAreOpened（只打开 1001.json / 1003.json；`.key`、`.bak`、非数字名连 stat 都没做） | ✓ |
| 4.1-03 | 4.1 文件规则 | `<pid>.<sha256>.key` 绝对不能打开（连 stat 都不碰） | Core/Util/FileIO.swift `isForbidden` / `open` L43-58（保险）；RegistryScanner 只处理匹配名的文件 | RegistryTests › keyFilesAreNeverOpened（不可读假 .key + `openObserver`：0 次打开、`forbiddenHits` 不变）；safetyNetRefusesKeyAndSocketPaths；新：StateRuleTests › n2_onlyPidJsonFilesAreOpened（.key 连 stat 都没做）、FuzzRegressionTests › c007_symlinkToKeyFileIsRefused / c007_caseVariantsNulAndDotDotAreForbidden。（我第一次读到的保险只按路径名判断，03:25 被别的 QA 加固成按真实路径 + 大小写不敏感 + NUL，见疑点 Q-10） | ✓ |
| 4.1-04 | 4.1 原地重写 | 读到写了一半的 JSON：解析失败时保留上一份好记录 | RegistryScanner.`scan` L164-173；`parse` L194-195 | RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms；emptyFileDuringTruncateIsTreatedAsHalfWritten；新：StateRuleTests › n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine（引擎层：写到一半 → 仍在场、动作不变） | ✓ |
| 4.1-05 | 4.1 原地重写 | 每隔 50 ms 重试一次 | `RegistryScanner.retryInterval = 0.05` L67；L168 | halfWritten… 断言 `r.nextRetry == now + 0.05`；新：n1（`nextWake` ≤ 50 ms） | ✓ |
| 4.1-06 | 4.1 原地重写 | 最多 5 次 | `maxRetries = 5` L68；L167（`failures < 5` 才排下一次） | halfWritten… 断言「首读 + 4 次重试 = 共 5 次读」后 `nextRetry == nil`（「最多 5 次」按 5 次读计，不是 5 次重试，见疑点 Q-08）；新：n1（12 次 50 ms 心跳后仍是上一份好记录；写完整后立刻更新） | ✓ |
| 4.1-07 | 4.1 字段 | 所有字段按可选，只有 `pid`、`sessionId` 必需 | RegistryScanner.`parse` L196（pid 是数字 + sessionId 非空） | RegistryTests › missingFieldsAreOptionalButPidAndSessionIdAreRequired（缺 sessionId / 缺 pid / 空 sessionId 都被忽略，只剩必需字段的记录可用）；RobustnessTests › aRegistryFileThatIsADirectoryOrHasWeirdTypesIsIgnored | ✓ |
| 4.1-08 | 4.1 字段·基本信息 | `pid`、`sessionId`（= 会话记录 UUID）、`cwd`、`startedAt`（毫秒） | `parse` L206-208（`TimeUtil.date(fromJSONMillis:)`） | RegistryTests › parsesEveryField（startedAt = 1790654597.849 s、sessionId）；EnginePresenceTests › snapshotCarriesTheDescriptiveFields（cwd、pid） | ✓ |
| 4.1-09 | 4.1 字段·procStart | UTC 的 lstart 格式，例 `Tue Sep 29 03:23:08 2026` | Core/Util/TimeUtil.swift `parseProcStart` L84-96 | RegistryTests › parsesEveryField（procStart = 04:03:17 UTC）；procStartParsingHandlesPaddingSpaces（1790652188）；新：FuzzRegressionTests › c001_procStartExtremeValuesDoNotTrap（天文数字 / 负数的年份时分秒 → nil） | ✓ |
| 4.1-10 | 4.1 字段·procStart | 日期个位数时用空格补位；解析前先把连续空格压成一个 | `parseProcStart` L85（按空白切分） | procStartParsingHandlesPaddingSpaces（`Wed Sep  9 03:23:08 2026` = 1788924188）；乱码 / 未知月份返回 nil | ✓ |
| 4.1-11 | 4.1 字段·procStart | 用 en_US_POSIX、UTC、格式 `EEE MMM d HH:mm:ss yyyy` 解析 | 自写解析器（不用 DateFormatter，UTC 由 `daysFromCivil` 算出），结果等价；文件头注释说明原因 | 同上（含 `formatProcStart` ↔ `parseProcStart` 往返相等） | ✓ |
| 4.1-12 | 4.1 字段·其他 | `version` / `kind` / `entrypoint` / `hostSessionId` / `name` / `status` / `waitingFor` / `statusUpdatedAt` 被读取并使用 | `parse` L211-223 | RegistryTests › parsesEveryField；EnginePresenceTests › snapshotCarriesTheDescriptiveFields（cliVersion = 2.1.284）、entrypointsMapToOrigins；EngineScenarioTests › waitingVariantsThroughTheEngine（waitingFor） | ✓ |
| 4.1-13 | 4.1 字段·其他 | `pidDomain` / `nameSource` / `nameSince` / `updatedAt` / `peerProtocol` / `peerFeatures` 存在时不出错 | `parse` L211、L217-218、L222 解析（引擎不使用）；peerProtocol / peerFeatures 不解析 | RegistryTests › unknownFieldsAndUnknownStatusAreTolerated（JSON 里带 peerFeatures，记录照常可用）。弱：pidDomain / nameSource / nameSince / updatedAt 的值没有任何断言（没人用它们） | ✓(无专门测试) |
| 4.1-14 | 4.1 字段 | `messagingSocketPath`：不要使用 | `parse` 不读该字段；FileIO 拒 `.sock` / `/cc-socks/`（L43-48）；源码里没有 socket / connect 调用（grep 过） | RegistryTests › unknownFieldsAndUnknownStatusAreTolerated（JSON 含该字段，记录照常）；safetyNetRefusesKeyAndSocketPaths | ✓ |
| 4.1-15 | 4.1 status | 取值 `busy` / `waiting` / `idle`；不认识的值 → nil 但记录保留 | Core/Model/Activity.swift `Phase(rawValue:)`；`parse` L219-220 | parsesEveryField（busy）；unknownFieldsAndUnknownStatusAreTolerated（"starting" → nil，`statusRaw` 保留）；RobustnessTests chaos 里带 "weird" | ✓ |
| 4.1-16 | 4.1 waitingFor | `"permission prompt"` → 等批准 | Core/Fusion/ActivityResolver.swift `waitingActivity` L82 | ActivityResolverTests › permissionPromptIsApprovalWithTheNewestOpenTool；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-17 | 4.1 waitingFor | `"input needed"`（AskUserQuestion / 对话框）→ 提问 | `waitingActivity` L84 | ActivityResolverTests › inputNeededAndDialogOpenAreQuestions；waitingVariantsThroughTheEngine | ✓ |
| 4.1-18 | 4.1 waitingFor | 终端会话 `"dialog open"` → 提问 | `waitingActivity` L84 | inputNeededAndDialogOpenAreQuestions；waitingVariantsThroughTheEngine | ✓ |
| 4.1-19 | 4.1 waitingFor | 终端会话 `"goal proposal"` → 其他等待 | `waitingActivity` L98 | ActivityResolverTests › nonPermissionWaitsFromTerminalSessions；waitingVariantsThroughTheEngine | ✓ |
| 4.1-20 | 4.1 waitingFor | 终端会话 `"worker request"` → 其他等待 | 同上 | 同上 | ✓ |
| 4.1-21 | 4.1 waitingFor | 终端会话 `"sandbox request"` → 等批准 | `waitingActivity` L82 | ActivityResolverTests › sandboxRequestIsApproval；waitingVariantsThroughTheEngine | ✓ |
| 4.1-22 | 4.1 entrypoint | `claude-desktop` / `claude-desktop-3p` / `local-agent` → 桌面 App | RegistryRecord.`origin` L30-36 | RegistryTests › entrypointMapsToOrigin（三项）；EnginePresenceTests › entrypointsMapToOrigins | ✓ |
| 4.1-23 | 4.1 entrypoint | `claude-vscode` → VS Code | 同上 | 同上 | ✓ |
| 4.1-24 | 4.1 entrypoint | 其他（含缺省）→ 终端 | 同上 | entrypointMapsToOrigin（cli、sdk-ts、nil） | ✓ |
| 4.1-25 | 4.1 kind | 只显示 `"interactive"` | `parse` L199-200 | RegistryTests › onlyInteractiveSessionsAreShown；EnginePresenceTests › nonInteractiveSessionsNeverBecomeGhostColleagues | ✓ |
| 4.1-26 | 4.1 kind | background / job / sdk / spare / worker 不画成幽灵同事 | 同上 | 同上（五种 kind 逐个写进假登记表，只剩 interactive 的一个 buddy） | ✓ |
| 4.1-27 | 4.1 kind | （任务书未规定）缺 `kind` 的记录按 interactive 显示 | `parse` L199（nil 不过滤） | onlyInteractiveSessionsAreShown（20.json 无 kind → 显示） | 偏离（记录：Core/README.md「我做的小决定 · 登记表」；DESIGN.md 第 4 节指向该 README，DESIGN 汇总表没列） |
| 4.1-28 | 4.1 延迟 | 状态变成 waiting 约 49 ms；一轮结束变成 idle 约 8 ms | —（观测值，不是实现要求；端到端延迟的实测见 DESIGN.md 第 9 节） | — | N/A |
| 4.1-29 | 4.1 没有心跳 | 会话可连续 busy 67 分钟以上、`statusUpdatedAt` 不变 → 判断存活只看进程 | SessionEngine.`aliveRecords` L189-205（只调 `ProcessProbe.classify`）；ActivityResolver 没有「时间旧就判死」的分支 | ActivityResolverTests › aSessionBusyForAnHourIsStillBusy（1…600 分钟）；EngineScenarioTests › aSessionBusyForAnHourNeverDies（62 分钟）、aWaitingSessionStaysWaitingNoMatterHowLong（两小时）；新：StateRuleTests › h1_twoHoursOfBusyIsQuietNotDead（busy 连续 2 小时：在场、busy、同一个工具、无离场事件） | ✓ |
| 4.1-30 | 4.1 存活判断 | `kill(pid, 0)` 返回 0 → 存在 | Core/Ingest/ProcessProbe.swift `SystemProcessProbe.probe` L54-65 | ProcessProbeTests › systemProbeSeesThisProcess（本进程 alive）；新：StateRuleProcessTests › r1_realStartTimeAndLiveness（真子进程：alive；退出后 ESRCH = dead） | ✓ |
| 4.1-31 | 4.1 存活判断 | 返回 EPERM 也算存在 | `probe` L60 | systemProbeSeesThisProcess（pid 1：launchd，kill 给 EPERM → alive）；新：StateRuleProcessTests › r2_epermCountsAsAlive（引擎里也一直在场） | ✓ |
| 4.1-32 | 4.1 存活判断 | 返回 ESRCH 算已死 | `probe` L59 | systemProbeSeesThisProcess（pid 2000000000 → dead）；EnginePresenceTests › aDeadPidWithALeftoverRegistryFileIsGone；新：StateRuleProcessTests › r1、r3（真子进程退出 → 防抖 3 s 后离场） | ✓ |
| 4.1-33 | 4.1 存活判断 | 用 `sysctl(KERN_PROC_PID)` 读 `p_starttime` | `SystemProcessProbe.startTime` L68-77 | systemProbeSeesThisProcess（sysctl 可用时断言启动时间在过去 30 天内；沙箱里为 nil 时不断言）；新：StateRuleProcessTests › r1（真子进程：sysctl 读到的启动时间落在启动前后 2 s 内） | ✓ |
| 4.1-34 | 4.1 存活判断 | 与 `procStart` 相差超过 2 秒 → PID 已被别的进程复用 | `ProcessProbe.startTolerance = 2` L31；`classify` L41-44 | ProcessProbeTests › classification（+1.9 s alive；+2.5 s、−3 s reused）；EnginePresenceTests › pidReuseIsTreatedAsTheOldProcessBeingGone（差 10 s → away；差 1.5 s → present）；新：StateRuleTests › i4_pidReuseToleranceIsExactlyTwoSeconds（恰好 2.0 s 仍算同一个进程、2.001 s 才算复用；−2.001 s 也算）、i6；StateRuleProcessTests › r1、r4（真进程） | ✓ |
| 4.1-35 | 4.1 存活判断 | sysctl 失败（如沙箱）→ 「未知」→ 当作还活着 | `ProcessStatus.State.unknown`；`classify` L38-41（startTime nil → alive） | classification（unknown → alive；startTime nil → alive；procStart nil → alive）；EnginePresenceTests › unknownProbeStateMeansAlive；新：StateRuleTests › i4、i5_aliveWithoutAStartTimeStaysPresent（kill 成功但读不到启动时间 → 一直在场） | ✓ |
| 4.1-36 | 4.1 存活判断 | 绝不能因为时间戳旧就判定会话死了 | 同 4.1-29 | 同 4.1-29；新：StateRuleTests › h1 | ✓ |
| 4.1-37 | 4.1 回收 | 桌面 App 回收空闲进程；用户再打开时带着同一个 hostSessionId 重新出现 → 还是同一个人 | Core/Fusion/IdentityResolver.swift `resolve` L71（host 别名）；SessionEngine.`reconcile` `.away` 分支 L237-243 | IdentityTests › hostAliasWinsEvenWhenPidAndSessionIdChange；EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat | ✓ |
| 4.1-38 | 4.1 终端会话 | 字段应大致相同、没有 hostSessionId；碰到活终端会话要核对，碰不到就靠 fixture | 终端记录走同一个 `parse`；无 host → 别名 `sid:` / `proc:`，key 用 `t:` | fixture：EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles、terminalResumeInANewProcessGivesTheSameBuddyBack；真实终端会话没核对过（DESIGN.md 第 10 节已知限制第 2 条、Core/README.md「已知限制」第 1 条） | N/A（任务书自己给了退路：碰不到就靠 fixture；已记录） |

---

## 4.2 ccmon 的 hook 事件流 `~/.claude/.monitor/<session_id>.events.jsonl`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.2-01 | 4.2 路径 | 只按登记表里的 sessionId 拼文件名，绝不扫描目录 | Core/Paths.swift `hookLogPath` L48-51（`isSafeID` 白名单）；SessionEngine.`openReaders` L433；Core/Fusion/SessionStore.swift `fsEvents` L228-240（别的会话 / Codex 的文件事件直接忽略） | T-Core/HookLogTests › unsafeSessionIdsNeverBecomePaths；RegistryTests › codexHookFilesInTheSameDirectoryAreNeverTouched；新：FuzzTailerTests › hookKnownPitfallsUnderMutation（④ 各种坏 sessionId 都拼不出路径） | ✓ |
| 4.2-02 | 4.2 | 不要改 ccmon 的任何文件（只读） | FileIO 只读 `open(O_RDONLY)`；引擎里没有写 ~/.claude 的调用 | RegistryTests › engineNeverWritesUnderClaudeDir（假 home 的 .claude 树里所有文件的大小 + mtime 不变） | ✓ |
| 4.2-03 | 4.2 格式 | 每行 `{"ts","ev","tool","detail","extra"}` | Core/Ingest/LineSanitizer.swift `parseStrict` L66-75 | HookLogTests › normalLine；新：FuzzRegressionTests › c003_absurdHookTimestampsAreRejectedAtParseTime（ts 是天文数字 / 0 / 负数 / 布尔 → 拒绝；正常毫秒照常） | ✓ |
| 4.2-04 | 4.2 | 10 个事件：SessionStart / SessionEnd / UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SubagentStop / PreCompact / PostCompact | `HookEvent` 常量 LineSanitizer.swift L27-36；SessionEngine.`processInbox` L529-568 每个都有分支 | 除 SessionEnd 外都有引擎测试（EngineScenarioTests 里的 Pre / Post / Stop / Prompt / SessionStart / PreCompact / PostCompact；Notification 见 StateRuleTests › l1；SubagentStop 见 StateRuleTests › k2）；SessionEnd 没有任何测试 | ✓(无专门测试) |
| 4.2-05 | 4.2 detail | 最多 160 字，超长截断并加 `…` | `ToolDetail.maxLength = 160`（Core/Ingest/TranscriptLine.swift L175）；`matches` L199-209（去掉结尾 `…` / U+FFFD 后按前缀比） | HookLogTests › toolDetailKeyFollowsTheHookRules（300 字 → 160；"npm te…" 前缀匹配）；HelperAttributionTests › truncatedHookDetailMatchesByPrefix（160 字 + `…`） | ✓ |
| 4.2-06 | 4.2 detail 取值 | Bash → command | `ToolDetail.key` L185 | toolDetailKeyFollowsTheHookRules | ✓ |
| 4.2-07 | 4.2 detail 取值 | Read / Edit / Write → file_path | `ToolDetail.key` L186 | 部分：只断言了 Read；Edit / Write 走同一个 case 但没断言 | ✓(无专门测试) |
| 4.2-08 | 4.2 detail 取值 | Grep / Glob → pattern | L187 | 部分：只断言了 Grep | ✓(无专门测试) |
| 4.2-09 | 4.2 detail 取值 | WebFetch / WebSearch → url 或 query | L188 | toolDetailKeyFollowsTheHookRules（url、query 两种都断言） | ✓ |
| 4.2-10 | 4.2 detail 取值 | Task / Agent → description | L189 | 部分：只断言了 Agent | ✓(无专门测试) |
| 4.2-11 | 4.2 detail 取值 | Skill → skill | L190 | toolDetailKeyFollowsTheHookRules | ✓ |
| 4.2-12 | 4.2 detail 取值 | 其他工具 → 第一个 `description` | L193 | toolDetailKeyFollowsTheHookRules（`mcp__x__y`）；MultiEdit 无 description → "" | ✓ |
| 4.2-13 | 4.2 extra | UserPromptSubmit → prompt 前 200 字，**绝不能显示** | LineSanitizer.`finalize` L125（解析时就置空） | HookLogTests › userPromptIsDroppedAtParseTime；新：FuzzTailerTests › hookKnownPitfallsUnderMutation（② 200 个随机 extra，UserPromptSubmit 的 extra 一律为空） | ✓ |
| 4.2-14 | 4.2 extra | Notification → message，只见过 `"Claude needs your permission to use <T>"` | 保留 `extra`；ActivityResolver.`toolName(fromNotification:)` L117-123 | HookLogTests › notificationTextIsKept；ActivityResolverTests › toolNameParsingFromNotification | ✓ |
| 4.2-15 | 4.2 extra | SessionStart → source（startup / resume / clear / compact / fork） | SessionEngine.`processInbox` L548（只用 `compact` → 相当于 PostCompact） | EngineScenarioTests › compactionThroughHooks（compact）；其余 source 不参与任何逻辑 | ✓ |
| 4.2-16 | 4.2 extra | PreCompact → trigger、SessionEnd → reason、PostToolUse → `len=N` | 解析保留 `extra`，引擎不使用这三项 | — | N/A（hook.sh 输出的字段说明，没有行为要求） |
| 4.2-17 | 4.2 | 桌面 App 里的会话也会触发这些 hook | — | — | N/A（环境事实） |
| 4.2-18 | 4.2 坑 1 | 目录里约 60% 是 Codex 的文件：只按 sessionId 拼文件名 | 同 4.2-01 | RegistryTests › codexHookFilesInTheSameDirectoryAreNeverTouched（Codex 文件不被打开、不变成 buddy） | ✓ |
| 4.2-19 | 4.2 坑 2 | `tool` 被截成 40 字符加 `…`：去掉 `…`，剩下的当前缀匹配 | LineSanitizer.`splitTool` L113-120；ToolTracker.`namesMatch` L55-60；ToolCatalog.`cleanName` L6-10 | HookLogTests › truncatedMcpToolNameKeepsPrefixAndMatchesByPrefix；ToolTrackerTests › truncatedToolNamesMatchByPrefix；新：FuzzTailerTests › hookKnownPitfallsUnderMutation（③ 每一种截断长度：去掉 `…`、前缀匹配都成立） | ✓ |
| 4.2-20 | 4.2 坑 3 | AskUserQuestion 的 detail 不是问题本身，绝不能显示 | LineSanitizer.`finalize` L127；ToolTracker.`pre` L77 / `post` L87 | HookLogTests › askUserQuestionDetailIsNeverKept（含降级解析路径 + Tracker 第二道保险）；新：FuzzTailerTests › hookKnownPitfallsUnderMutation（① 300 个变异：AskUserQuestion 的 detail 一律为空） | ✓ |
| 4.2-21 | 4.2 坑 4 | MultiEdit / NotebookEdit / TodoWrite 的 detail 永远是空 → 不能因 detail 空而配不上 | 通用机制：Tracker 按「名字 + detail」配对（空 = 空）；`ToolDetail.matches` 空对空为真 L206 | HookLogTests › toolDetailKeyFollowsTheHookRules（MultiEdit key == ""；`matches("","")`）；ToolTrackerTests › truncatedToolNamesMatchByPrefix（mcp 工具空 detail 的 pre / post 配对） | ✓ |
| 4.2-22 | 4.2 坑 5 | 子代理的工具调用也记在父会话文件里，且没有 agent_id | Core/Fusion/HelperAttributor.swift（见 5.3） | T-Core/HelperAttributionTests（整套） | ✓ |
| 4.2-23 | 4.2 坑 6 | 没注册 PostToolUseFailure：失败 / 被拒时只有 Pre 没有 Post，会一直悬空 | ToolTracker 新一批关掉旧的（见 5.2-03） | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded、permissionDeniedDanglingIsClosedByTheNextBatch | ✓ |
| 4.2-24 | 4.2 坑 7 | 每行先用 `String(decoding:as: UTF8.self)` 清洗，再做 JSON 解析 | LineSanitizer.`string` L49-51 → `parseHookLine` L53-62 | HookLogTests › invalidUTF8IsCleanedNotFatal（被截断的中文字节 → U+FFFD，JSON 仍合法）；新：FuzzTailerTests › hookLineWithInvalidUTF8Everywhere（非法 UTF-8 放在行首 / 行中 / 每个字段 / 行尾：不崩溃、不放行坏 ts） | ✓ |
| 4.2-25 | 4.2 坑 7 | JSON 解析失败时，只抠出 ts、ev、tool 三个字段 | LineSanitizer.`parseDegraded` L79-85（扫描式，不是正则，效果等价） | HookLogTests › truncatedUnicodeEscapeFallsBackToRegexFields（degraded == true；ts / ev / tool 对；detail == ""）；新：FuzzTailerTests › hookLineTruncatedAtEveryByte（在每一个字节位置截断：结果要么 nil，要么和原事件前缀一致） | ✓ |
| 4.2-26 | 4.2 坑 7 | 实在解析不了的行直接跳过，不能让整个文件失败 | Core/Ingest/HookLogReader.swift `poll`（`skippedLines += 1`） | HookLogTests › garbageLinesAreSkippedWithoutFailingTheWholeFile（3 行被跳过、其余读到）；RobustnessTests › randomGarbageInEveryDataSourceNeverCrashesTheEngine；新：FuzzTailerTests › hookReaderIncrementalEqualsOneShot（坏行被跳过、计数自洽） | ✓ |
| 4.2-27 | 4.2 坑 8 | SubagentStop 大多不代表小助手做完了（170 次里 122 次紧跟 Stop），只能当「总结已生成」的提示 | SessionEngine.`processInbox` L558-562（只记 `summaryHintAt` + `metaRefreshHint`，不动小助手状态） | 新：StateRuleTests › k2_subagentStopIsOnlyASummaryHint（SubagentStop 只让下一次 poll 立刻重读桌面元数据；不改变主线程的工具 / 阶段） | ✓ |
| 4.2-28 | 4.2 坑 9 | PreCompact / PostCompact 在 Claude 日志里从没出现 → 只能用合成 fixture 测 | ActivityResolver `busyActivity` L129-138；SessionEngine.`processInbox` L554-557 | ActivityResolverTests › compactingWhenPreCompactHasNoPostCompact；EngineScenarioTests › compactionThroughHooks（合成 fixture） | ✓ |
| 4.2-29 | 4.2 hook 在不在工作 | 当前会话有 `ts ≥ startedAt − 5s` 的事件 → 正常 | SessionEngine.`hookActive` L522-527 | EnginePresenceTests › hookActiveMeansAnEventNoOlderThanStartedAtMinus5Seconds（−700 s → false；startedAt − 4 s → true） | ✓ |
| 4.2-30 | 4.2 hook 掉线 | 用户卸掉 ccmon 后，自动退回用会话记录判断工具，不能崩 | SessionEngine.`buildSignals` L609-616；`hookActive` 的 15 s 掉线判据 L520-526 | EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript；HookDropoutTests › ifCcmonIsUninstalledMidSessionToolsFallBackToTheTranscript、aBusyHookSessionWithAQuietTranscriptStaysOnHooks | ✓ |
| 4.2-31 | 4.2 诊断页 | 只读地看一眼 settings.json 里有没有注册 hook.sh | SessionEngine.`detectHookInSettings` L959-972（`FileIO.readAll`，只读）；`diagnostics` L925-957 | EnginePresenceTests › diagnosticsReportSourcesAndPerSessionHookState（已注册 = true）；EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript（未注册 = false，「hook: 没检测到」） | ✓ |

---

## 4.3 会话记录 `~/.claude/projects/<编码后的cwd>/<sessionId>.jsonl`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.3-01 | 4.3 找文件 | 用 sessionId 遍历项目子目录去找，不自己拼目录名 | Core/Ingest/TranscriptReader.swift `TranscriptLocator.find` L207-215 | T-Core/TranscriptTests › locatorFindsTheFileByGlobbingProjectDirectories（别的项目目录里找到；未知 sid → nil；`../x` → nil） | ✓ |
| 4.3-02 | 4.3 找文件 | 目录名以 `-` 开头，shell 通配要写 `./*/` 或加 `--` | 不经过 shell（opendir / readdir），不存在这个问题；测试夹具的目录名本来就是 `-fake-project` | — | N/A |
| 4.3-03 | 4.3 文件很大 | 最大 44.2 MB、单行最长 1.53 MB，只能流式读取 | Core/Ingest/JSONLTailer.swift（`poll` / `consume`） | TokenLedgerTests › aBigFileIsScannedFast（44 MB < 2 s）；TranscriptTests › bootstrapReadsOnlyTheTailWindowOfABigFile | ✓ |
| 4.3-04 | 4.3 文件很大 | 用 `pread` 每次最多读 1 MiB，用 `memchr` 找换行 | `JSONLTailer.Config.chunkBytes = 1 << 20` L14；`poll` L136；`consume` L149 | 弱：块边界用 64 B / 7 B 的小块测（JSONLTailerTests › linesStraddlingChunkBoundaries、multiByteCharactersAcrossChunks），默认 1 MiB 本身没有断言 | ✓(无专门测试) |
| 4.3-05 | 4.3 文件很大 | 只处理完整的行，剩下的半行留到下次再拼 | `pending` / `committedOffset`（`consume` L145-184） | JSONLTailerTests › halfLineIsHeldUntilCompleted；TokenLedgerTests › partialLineIsCountedOnlyOnceItIsComplete；新：FuzzTailerTests › tailerHalfLinesAndBlankLines、tailerIncrementalAppendsEqualOneShot（随机分段追加：每次只交付完整的行） | ✓ |
| 4.3-06 | 4.3 文件很大 | 单行超过 4 MiB 就丢掉，一直跳到下一个 `\n` | `maxLineBytes = 4 << 20` L14；`consume` L153-158、L173-176 | JSONLTailerTests › oversizeLineIsDroppedAndTheNextLineSurvives（5 MiB）、oversizeLineSplitAcrossPollsIsSkippedUntilNewline、exactlyAtTheLimitIsKept（恰好 4 MiB 保留）；新：FuzzTailerTests › tailerOversizeLineBoundaries（1.5 MB 保留、恰好 4 MiB 保留、4 MiB + 1 丢掉、16 MiB 丢掉；后面的行都读得到；没有换行的半截超长行不交付） | ✓ |
| 4.3-07 | 4.3 文件很大 | 热路径上绝不整文件读取 | TranscriptReader.`bootstrap` 尾部窗口 512 KiB（L164-174）；hook 尾窗 256 KiB；`FileIO.readAll` 只用于小文件 | TranscriptTests › bootstrapReadsOnlyTheTailWindowOfABigFile（400 KB 文件、8 KiB 窗口，`linesSeen < 100`） | ✓ |
| 4.3-08 | 4.3 条目·assistant | 每行一个 content block（thinking / text / tool_use{id,name,input}）+ `message.id/model/usage/stop_reason` + `isAbortedMidStream/isApiErrorMessage/isSidechain/timestamp` | Core/Ingest/TranscriptLine.swift `parse` L75-108 | TranscriptTests › titlesAndModelAndContext、toolUseIsOpenUntilItsResultArrives、syntheticApiErrorAssistantIsRecognized、abortedMidStreamAssistantIsAnInterrupt、sidechainLinesBelongToOthersInTheMainFile | ✓ |
| 4.3-09 | 4.3 条目·assistant | `stop_reason`：tool_use / end_turn / null（null 表示被打断） | TranscriptFacts.`apply` L96-103（end_turn → `endTurnAt`）；null 只有带 `isAbortedMidStream` 才算打断 L103 | abortedMidStreamAssistantIsAnInterrupt（null + aborted = 打断；null 但没有 aborted = 不算） | 偏离（记录：DESIGN.md 第 4 节末段「子代理会话记录是按 block 实时写的，中间行 stop_reason 全是 null」；Core/README.md「会话记录」前两条） |
| 4.3-10 | 4.3 条目·user | content 是字符串 = 用户输入，**绝不能显示** | `TranscriptLine.isPrompt` 只是布尔（L115、L133）；TranscriptFacts 里没有任何文本字段 | TranscriptTests › promptsAreRecordedButNeverTheirText（`String(describing: facts)` 里找不到 prompt 文字） | ✓ |
| 4.3-11 | 4.3 条目·user | content 是数组：`tool_result{tool_use_id,is_error}`、text 等 | `parse` L116-134 | toolUseIsOpenUntilItsResultArrives（tool_result 关闭对应 tool_use）；is_error 被解析但没人使用 | ✓ |
| 4.3-12 | 4.3 条目·user | `isMeta` 为真的行直接跳过 | TranscriptFacts.`apply` L113 | TranscriptTests › metaUserLinesAreSkipped | ✓ |
| 4.3-13 | 4.3 条目·user | 文本以 `[Request interrupted by user` 开头 = 被用户打断 | `interruptPrefix` L59；`parse` L115、L127 | TranscriptTests › userInterruptTextIsDetectedInBothShapes（数组 text、字符串、`… for tool use]` 三种形状；打断行不算 prompt） | ✓ |
| 4.3-14 | 4.3 条目·system | `stop_hook_summary` = 一轮结束 | `apply` L123-124 | TranscriptTests › stopHookSummaryEndTurnAndTurnDuration（解析）；在引擎里当轮次边界用，见 5.2-14 | ✓ |
| 4.3-15 | 4.3 条目·system | `api_error` 带 `retryAttempt` / `maxRetries` / `retryInMs` | `parse` L140-143；`apply` L125-129 | TranscriptTests › apiErrorIsRecordedWithRetryInfo（3 / 10 / 2500） | ✓ |
| 4.3-16 | 4.3 条目·system | `compact_boundary` = 上下文压缩 | `apply` L130-131；ActivityResolver `busyActivity` L134-138 | stopHookSummaryEndTurnAndTurnDuration（解析）；ActivityResolverTests › compactingFromTranscriptBoundary | ✓ |
| 4.3-17 | 4.3 条目·system | `turn_duration` 只在终端会话里有 | `parse` L144-145；`apply` L132-133；SessionEngine.`complete` L757-760 用它修正「用时」 | 解析有测试（stopHookSummaryEndTurnAndTurnDuration：4012 ms）；引擎用它修正用时没有测试 | ✓(无专门测试) |
| 4.3-18 | 4.3 条目 | `cost-state` 进程退出时写入 | 忽略（未知 type → `.other`）；用量表的「后台调用补差」没移植（见 4.3-33） | — | N/A（环境说明） |
| 4.3-19 | 4.3 元数据行 | 没有 timestamp 的元数据行（last-prompt / custom-title / ai-title / agent-name / atis-latch / mode / permission-mode…）判断状态时跳过；标题取 custom-title / ai-title（custom 优先） | TranscriptFacts.`apply`（assistant / user / system 无 ts 直接 return；custom / ai / permissionMode 分支 L81-86） | TranscriptTests › titlesAndModelAndContext；EnginePresenceTests › titlePrecedenceChain（custom 胜 ai） | ✓ |
| 4.3-20 | 4.3 元数据行 | 另有 `<sid>/custom-title.json`，内容 `{customTitle}` | SessionEngine.`refreshCustomTitleFile` L500-513 | EnginePresenceTests › customTitleJsonInTheSessionDirectoryIsUsed | ✓ |
| 4.3-21 | 4.3 写入延迟 | 主线程整条消息写完才落盘，最多延迟约 33 s → 会话记录只作「当前工具」的兜底 | 设计：hook 优先，`buildSignals` L609-616 hook 不工作才用会话记录 | EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript（33 s 是观测值，没有断言） | ✓ |
| 4.3-22 | 4.3 用途 | 会话记录用来：算 token、取标题、发现 api_error 和被打断、没有 hook 时判断工具 | TokenLedger；SessionEngine.`title` / `classify` / `buildSignals` | 分别见 4.3-28…39、4.4-09、5.4-15、5.4-22、4.2-30 | ✓ |
| 4.3-23 | 4.3 子代理 | 文件在 `<sid>/subagents/agent-<hex>.jsonl`，按 block 实时写；旁边 `.meta.json` | Core/Ingest/SubagentReader.swift `discover` L110-135；`helperDirectories` L90-97（另含 `workflows/wf_*/`） | HelperAttributionTests › workflowSubagentsInNestedDirectoriesAreDiscovered；HelperAttributionEngineTests 各用例（写 agent-*.jsonl + .meta.json） | ✓ |
| 4.3-24 | 4.3 子代理 | meta 里有 `agentType`、`description`、`toolUseId`、`spawnDepth`、`requestShape`（background / foreground） | `loadMeta` L137-148；`isForeground` L19（缺省当前台） | 断言了 description、agentType、foreground；toolUseId / spawnDepth 只解析、无断言 | ✓(无专门测试) |
| 4.3-25 | 4.3 子代理 | 子代理当前的工具 = 它最后一个还没有结果的 tool_use | `snapshots` L186-188（`openToolUses.last`） | HelperAttributionEngineTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity（currentTool = Bash）；helperIsDoneWhenLastAssistantIsEndTurnWithNoOpenTool（结束后 nil） | ✓ |
| 4.3-26 | 4.3 子代理 | 最后一条 assistant 是 end_turn 且没有未完成的工具 = 已完成 | `isDone` L156-159 | helperIsDoneWhenLastAssistantIsEndTurnWithNoOpenTool | ✓ |
| 4.3-27 | 4.3 子代理 | 最近 90 秒内有写入且还没完成 = 活跃 | `activeWindow = 90` L23；`isActive` L161-163；`snapshots` L180-183 | helperStopsBeingActiveAfter90SecondsWithoutWrites（89 s 仍活跃、91 s 消失） | ✓ |
| 4.3-28 | 4.3 token·parse_line() | 取 usage：assistant + `message.id` + 合法 timestamp + 非 `<synthetic>` + usage 非空；`cache_creation` 没有细分或对不上总数时全当 5m | Core/Ingest/TokenLedger.swift `handle` L214-217；TranscriptLine.swift L92-108 | T-Core/TokenLedgerTests › sumsInputOutputCacheWriteAndCacheRead、syntheticAndIncompleteLinesAreIgnored、cacheCreationSplitFollowsTheMeterRule。（判据用的是顶层 `type == "assistant"`，Python 用 `message.role`，见疑点 Q-09）；新：StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree（QA/tools/token_crosscheck.py 在假 home 树上：独立实现 == 用量表 parse_line == dump == 手算期望值）；FuzzRegressionTests › c004_hugeUsageNumbersDoNotOverflow | ✓ |
| 4.3-29 | 4.3 token·update() | 按字节偏移增量读取 | JSONLTailer `offset`；TokenLedger.`scan` L177-197 | TokenLedgerTests › dedupeAlsoWorksAcrossPollsAndFiles（增量追加同一条消息的后续行） | ✓ |
| 4.3-30 | 4.3 token·update() | 文件变短就从头读 | JSONLTailer.`poll` L111-113；TokenLedger.`resetStats` L199-203 | TokenLedgerTests › truncatedFileIsRescannedFromTheStart（300 → 7） | ✓ |
| 4.3-31 | 4.3 token·update() | 只处理到最后一个 `\n` | tailer 的 `pending` | TokenLedgerTests › partialLineIsCountedOnlyOnceItIsComplete | ✓ |
| 4.3-32 | 4.3 token·update() | 按 `message.id` 去重，每个字段取最大值 | TokenLedger.`handle` L222-235 | TokenLedgerTests › sameMessageIdIsCountedOnceWithTheMaximumOfEachField（cache_read 变小仍取最大）、dedupeAlsoWorksAcrossPollsAndFiles（跨文件） | ✓ |
| 4.3-33 | 4.3 token | 「把用量表里的 Python 算法移植成 Swift」——用量表还有 cost-state 的「后台调用补差」（`read_cost_state` / `background_recs`），没移植 | TokenLedger 头注释 L13-14 明说「有意的」 | 与用量表对照：Core/README.md「真实数据核对」（不含 cost-state，四项相等）；无自动测试 | 偏离（记录：Core/README.md「我做的小决定 · token」+「真实数据核对」；DESIGN.md 第 4 节指向该 README，DESIGN 汇总表没列） |
| 4.3-34 | 4.3 token·read_title() | 标题：custom-title 优先于 ai-title | TranscriptFacts.`customTitle` / `aiTitle`；SessionEngine.`title` L870-871 | TranscriptTests › titlesAndModelAndContext；EnginePresenceTests › titlePrecedenceChain | ✓ |
| 4.3-35 | 4.3 token·read_app_windows() / window_of() | 窗口 ↔ CLI 会话（当前 + prior）的映射 | DesktopMetaReader.`find` / `allCliSessionIds`（Core/Ingest/DesktopMetaReader.swift L129-133、L50-54）；SessionEngine.`updateTokenGroup` L833-862 | EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents | ✓ |
| 4.3-36 | 4.3 token | 读取时先用字节预过滤（先看有没有 `"usage"` 和 `"assistant"`），命中了再解码 | TokenLedger.`handle` L211-213（`memmem`） | 只有间接：aBigFileIsScannedFast；没有直接断言预过滤 | ✓(无专门测试) |
| 4.3-37 | 4.3 token | 本会话总量 = 输入 + 输出 + 缓存写 + 缓存读 | Core/Model/BuddySnapshot.swift `TokenBreakdown.total` L30 | TokenLedgerTests › sumsInputOutputCacheWriteAndCacheRead（`t.total == 11 + 22 + 303 + 4004`） | ✓ |
| 4.3-38 | 4.3 token | 子代理的 token 也要算进来 | SessionEngine.`updateTokenGroup` L849-853（helperPaths） | TokenLedgerTests › subagentTranscriptsAreAddedToTheBuddysTotal；EnginePresenceTests › desktopTokensMerge…（+40） | ✓ |
| 4.3-39 | 4.3 token | 按文件把 `{dev, ino, offset, totals}` 缓存到 `ledger.json` | TokenLedger.`writeLedger` L279-304、`restore` L256-277 | TokenLedgerTests › ledgerFileRestoresProgressAndDedupesAcrossTheBoundary、groupsWithPriorSessionsAreRescannedInsteadOfUsingTheLedger、persistenceFailureDegradesToMemoryOnly；新：FuzzRegressionTests › c005_ledgerWithAbsurdCountersIsSanitized（账本里的天文数字 / 负数恢复后不溢出） | ✓ |
| 4.3-40 | 4.3 token | 最多 30 秒写一次 | `persistInterval = 30` L45；`writeLedger` L282 | 无（没有任何测试推进时间去验证节流） | ✓(无专门测试) |
| 4.3-41 | 4.3 token | 退出时也写一次 | TokenLedger.`flush` L145；SessionEngine.`shutdown` L132-135；App/AppDelegate.swift `applicationWillTerminate` L127-128 → SessionStore.`stop` L81-89 | 弱：单测只覆盖 `flush()` 本身（ledgerFileRestores…）；退出链路只有 DESIGN.md 第 9.1 节「退出时落盘」的手工实测（假 home） | ✓(无专门测试) |
| 4.3-42 | 4.3 token | 第一次扫大文件放到后台低优先级 | TokenLedger.`init` L71-72：队列 `qos: .background` | 无（测试用自己传的队列） | ✓(无专门测试) |
| 4.3-43 | 4.3 token | 一次只扫一个文件 | `pass()` L155-167：串行队列上逐个 `scan` | 无 | ✓(无专门测试) |

---

## 4.4 桌面 App 会话元数据 `…/claude-code-sessions/<acct>/<org>/local_<uuid>.json`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.4-01 | 4.4 路径 | `~/Library/Application Support/Claude/claude-code-sessions/<acct>/<org>/local_<uuid>.json` | Core/Paths.swift `desktopSessionsDir` L30；DesktopMetaReader.`refresh` L77-117 | FakeTree.writeMeta（`acct/org` 两级目录）被下班工位 / 标题 / blocked 等一大批测试使用 | ✓ |
| 4.4-02 | 4.4 字段 | `sessionId`（local_…）、`cliSessionId`、`priorCliSessionIds[]` | DesktopMetaReader.`parse` L137-145 | IdentityTests › desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing；EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents | ✓ |
| 4.4-03 | 4.4 字段 | `cwd`、`originCwd`、`title`、`titleSource`、`model`、`effort`、`permissionMode`、`isArchived` | `parse` L146-153 | 断言了 title（titlePrecedenceChain）、model / effort / permissionMode（snapshotCarriesTheDescriptiveFields）、isArchived（下班工位）；cwd / originCwd / titleSource 无断言 | ✓(无专门测试) |
| 4.4-04 | 4.4 字段 | `createdAt`、`lastActivityAt`、`lastFocusedAt`、`completedTurns`、`lastAssistantUuid` | `parse` L154-158 | 断言了 lastActivityAt（3 h / 12 h）、lastFocusedAt（清未读）、lastAssistantUuid（blocked）；createdAt / completedTurns 无断言 | ✓(无专门测试) |
| 4.4-05 | 4.4 字段 | `postTurnSummary{status_category: completed/blocked, needs_action, status_detail}`、`postTurnSummaryFor` | `parse` L159-166 | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（category、status_detail、For）；needs_action 无断言 | ✓ |
| 4.4-06 | 4.4 字段 | 没有表示「运行中」的字段 | 代码不依赖这种字段 | — | N/A（环境事实） |
| 4.4-07 | 4.4 blocked | `status_category == "blocked"` 并且 `postTurnSummaryFor == lastAssistantUuid` | DesktopMeta.`isBlocked` / `summaryIsCurrent` L41-47 | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn、aSummaryForAnOlderAssistantMessageIsNotBlocked、aBlockedSummaryAlreadyThereAtLaunchShowsBlocked；新：StateRuleTests › f3_blockedOverlayFollowsTheDesktopSummary（completed 不亮；blocked 晚落盘也亮、只发一次事件、保持一小时、下一轮清掉） | ✓ |
| 4.4-08 | 4.4 blocked | `status_detail` 是英文，只在悬停卡片里显示 | 快照 `statusDetail`（SessionEngine L828）；唯一的展示处 Stage/HoverCard.swift L60（隐私模式不显示） | 数据层：blockedComesFromTheDesktopSummary… 断言 statusDetail 内容；「只在悬停卡片显示」没有测试 | ✓(无专门测试) |
| 4.4-09 | 4.4 标题优先级 | 登记表 `name` → 桌面 `title` → custom-title → ai-title → cwd 文件夹名 →「会话 <sid 前 8 位>」 | SessionEngine.`title` L866-878 | EnginePresenceTests › titlePrecedenceChain（cwd → ai → custom → 桌面 title → 登记表 name 逐级）；titleFallsBackToSessionIdPrefixWhenNothingElseExists（「会话 abcdef12」）；新：StateRuleChainTests › py2_dumpVsRegistryScriptOnAFakeTree（QA/tools/dump_vs_registry.py 核对标题链，输出里没有标题文字） | ✓ |

---

## 4.5 身份

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.5-01 | 4.5 buddy key | 桌面会话 = `"d:" + hostSessionId` | Core/Fusion/IdentityResolver.swift `resolve` L82 | T-Core/IdentityTests › desktopKeyIsDPrefixPlusHostSessionId | ✓ |
| 4.5-02 | 4.5 buddy key | 其他会话 = `"t:" + 第一次见到的 sessionId` | `resolve` L84 | IdentityTests › terminalKeyIsTPrefixPlusFirstSeenSessionId、terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess（/clear 后 key 仍是 `t:before-clear`）；新：StateRuleTests › j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume | ✓ |
| 4.5-03 | 4.5 别名 | `host:<local_…>`、`sid:<uuid>`、`proc:<pid>@<启动时间>` | `resolve` L64-66、`attach` L113-129 | IdentityTests › desktopKeyIsDPrefixPlusHostSessionId（三种别名都在，`proc:1@` 前缀） | ✓ |
| 4.5-04 | 4.5 归属顺序 | ① host 别名 | `resolve` L71 | IdentityTests › hostAliasWinsEvenWhenPidAndSessionIdChange（kind == .host） | ✓ |
| 4.5-05 | 4.5 归属顺序 | ② 进程别名（同一进程 `/clear`） | `resolve` L72 | IdentityTests › terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess（kind == .process）；EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles；新：StateRuleTests › j1_desktopClearInTheSameProcessKeepsTheBuddy（桌面 /clear：key / 工位 / 盐不变） | ✓ |
| 4.5-06 | 4.5 归属顺序 | （hook 里的 SessionStart `source=clear` 可以佐证进程别名） | 未实现（引擎只用 `source=compact`） | — | N/A（任务书写的是「可以」，可选） |
| 4.5-07 | 4.5 归属顺序 | ③ sid 别名（在新进程里 resume） | `resolve` L73 | IdentityTests › terminalResumeInANewProcessKeepsTheSameBuddyViaSessionAlias；EnginePresenceTests › terminalResumeInANewProcessGivesTheSameBuddyBack；新：StateRuleTests › j2 | ✓ |
| 4.5-08 | 4.5 归属顺序 | ④ 桌面元数据里的 `cliSessionId` / `priorCliSessionIds` | `resolve` L74 | IdentityTests › desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing（current 与 prior 两种都反查得到）、aSessionKnownOnlyToDesktopMetadataBecomesADesktopIdentity；新：StateRuleTests › j3_desktopResumeIsRecognizedThroughTheMetadataCliSessionIds | ✓ |
| 4.5-09 | 4.5 归属顺序 | ⑤ 以上都不匹配就是新 buddy | `resolve` L81-89 | IdentityTests › pidReuseWithADifferentStartTimeIsANewBuddy、withoutProcStartNoProcessAliasIsUsed | ✓ |
| 4.5-10 | 4.5 持久化 | 别名、工位编号、外观种子盐存到 `~/Library/Application Support/BuddyOffice/identities.json` | `saveIfNeeded` L179-198；`load` L200-217；Paths.`identitiesFile` L34 | IdentityTests › persistenceRoundTripKeepsAliasesSeatAndSalt；EnginePresenceTests › identitiesAndAppearanceSurviveARestart | ✓ |
| 4.5-11 | 4.5 持久化 | 保留 7 天 | `retention = 7 * 86400` L29；`load` L208 | IdentityTests › identitiesAreForgottenAfterSevenDays（6 天还在、7.1 天忘掉） | ✓ |
| 4.5-12 | 4.5 持久化 | 同一个会话关掉再打开，回来的还是同一个人、坐回同一个工位 | `assignSeat` L145-154；SessionEngine.`reconcile`（away → live 保留 seat / salt） | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat、terminalResumeInANewProcessGivesTheSameBuddyBack（seat / salt 相同）；IdentityTests › seatsAreTheSmallestFreeNumberAndReturningBuddiesGetTheirOwnSeatBack | ✓ |
| 4.5-13 | 4.5 token 合并 | 桌面会话把 `cliSessionId` 和 `priorCliSessionIds` 对应的会话记录加在一起 | SessionEngine.`updateTokenGroup` L838-853 | EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents（100 + 200 + 300 + 40，重叠的 m2 只算一次）；新：StateRuleTests › j1（token = 1000 + 7） | ✓ |
| 4.5-14 | 4.5 token 合并 | 终端会话只算当前的 sessionId | `updateTokenGroup` L839-843 | EnginePresenceTests › aTerminalSessionOnlyCountsItsCurrentSessionId；terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles（/clear 后只算新的 7） | ✓ |

---

## 4.6 安全红线

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.6-01 | 4.6 | 绝不打开 `~/.claude/sessions/*.key` | 同 4.1-03（FileIO 保险 + 只碰匹配名的文件） | RegistryTests › keyFilesAreNeverOpened（`FileAccessTests` 串行套件）、safetyNetRefusesKeyAndSocketPaths；新：FuzzRegressionTests › c007_symlinkToKeyFileIsRefused（符号链接指向 .key 也拒绝） | ✓ |
| 4.6-02 | 4.6 | 绝不连接 `/tmp/cc-socks/*.sock` | FileIO 拒 `.sock`、路径含 `/cc-socks/`（L43-48）；全部源码里没有 socket / connect / Network 相关调用（grep 过） | safetyNetRefusesKeyAndSocketPaths（`open` 返回 −1；`forbiddenHits` +3）；「没有连接代码」这一点只有静态检查，没有测试；新：FuzzRegressionTests › c007_caseVariantsNulAndDotDotAreForbidden（`.Sock`、`CC-SOCKS`、NUL、`../`） | ✓ |
| 4.6-03 | 4.6 | 不读任何凭据或钥匙串 | 源码里没有 Keychain / SecItem / 凭据文件读取（grep 过）；`detectHookInSettings` 会把整份 settings.json 解析进内存但只取 `hooks`、不保留不记日志（4.2 允许这一处） | 无 | ✓(无专门测试) |
| 4.6-04 | 4.6 | 不改 ccmon 的文件 | 只读打开；写入点只有 4.6-05 列的几处 | RegistryTests › engineNeverWritesUnderClaudeDir | ✓ |
| 4.6-05 | 4.6 | 不改用量表、Claude.app 的任何文件 | 全部写入点（grep `writeAtomically` / `FileManager` / `write(to:)`）只有：identities.json、ledger.json、开机启动 LaunchAgent plist、`/tmp/buddy-office-debug.log`、buddyctl 的输出目录 | 无 | ✓(无专门测试) |
| 4.6-06 | 4.6 | App 运行时绝不写 `~/.claude` 下的任何东西 | 同上；数据层只写 `~/Library/Application Support/BuddyOffice/`（IdentityResolver.`saveIfNeeded`、TokenLedger.`writeLedger`） | RegistryTests › engineNeverWritesUnderClaudeDir（只覆盖引擎层；App 层没有对应测试） | ✓ |
| 4.6-07 | 4.6 | settings.json 只改一处：只有安装脚本可以改，且只加一条 SessionStart hook（7.4 节） | scripts/hook-merge.py `install` / `GROUP`（matcher `startup` 与 `resume` 用竖线连接，命令 `pgrep -xq BuddyOffice …; exit 0`，timeout 5）；Sources 里没有任何写 settings.json 的代码（FakeTree 只往测试用的假 home 写） | T-Py › test_install_appends_one_group_and_keeps_everything_else、test_install_creates_file_when_missing、test_install_then_uninstall_is_byte_identical_and_keeps_trailing_newline_state（Python 脚本的测试，要单独用 `python3 Tests/hook_merge_test.py` 跑） | ✓ |
| 4.6-08 | 4.6 | 改之前先备份 | hook-merge.py `backup`（`settings.json.bak-YYYYmmdd-HHMMSS`） | T-Py › test_install_appends_one_group_and_keeps_everything_else（备份数 == 1）、test_install_twice_is_idempotent（第二次什么都不做，也没有第二份备份）、test_refuses_invalid_json_and_leaves_no_trace | ✓ |
| 4.6-09 | 4.6 | 用户已经同意这一处改动 | — | — | N/A（授权事实，不是实现要求） |
| 4.6-10 | 4.6 | 不显示对话内容：绝不显示用户输入的 prompt | UserPromptSubmit 的 `extra` 解析即丢（LineSanitizer L125）；TranscriptFacts 不存任何文本；AskUserQuestion 的 detail 丢弃 | HookLogTests › userPromptIsDroppedAtParseTime、askUserQuestionDetailIsNeverKept；TranscriptTests › promptsAreRecordedButNeverTheirText；T-Stage/PlateCopyTests › privacyModeNeverLeaksDetails（隐私模式，另一条线） | ✓ |
| 4.6-11 | 4.6 | 调试日志只写元数据（状态、工具名、时间），不写对话内容 | App/DebugTools.swift `log`：调用点写的是窗口 frame / 命中测试 / 开关状态 / 计时；**`--test-jump` 的日志会写会话标题**（App/AppDelegate.swift L104、L107，只在测试参数下） | 无 | ✓(无专门测试) |
| 4.6-12 | 4.6 | 不联网 | 源码里没有 URLSession / Network / socket；Package.swift 没有第三方依赖；唯一的 `https://` 字面量是演示剧本里的假域名（Stage/DemoScript.swift L50） | 无 | ✓(无专门测试) |

---

## 5.1 阶段（phase）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.1-01 | 5.1 基础 | 阶段以登记表的 `status` 为准 | Core/Fusion/ActivityResolver.swift `phase` L30-33 | T-Core/ActivityResolverTests 里所有 `sig(status)` 用例；waitingIsNeverOverriddenByHooks；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（16 个固定种子的随机事件流，与按任务书写的独立参考模型逐步对拍：阶段、主线程打开的调用个数与顺序、忙碌 / 等待时的动作） | ✓ |
| 5.1-02 | 5.1 修正 1 | 登记表还是 idle，但有一条比 `statusUpdatedAt` 更新的 UserPromptSubmit → 暂时当作 busy | `phase` L39-43 | ActivityResolverTests › registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds（提示比 statusUpdatedAt 旧 → 不修正）；EngineScenarioTests › promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce。（实测登记表 busy 比 UserPromptSubmit 早 0.09–0.5 s，这条路径几乎不触发——写在 Core/README.md「数据源实测结论 · 时序」，DESIGN.md 第 4 节末段只写了 Stop 早 40–60 ms 那一半）；新：StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds（引擎层：2.9 s 仍 busy、3.1 s 回 idle，只发一次 turnStarted） | ✓ |
| 5.1-03 | 5.1 修正 1 | …最多 3 秒 | `tempBusyWindow = 3` L6；`phase` L41 | registryIdleButNewerPrompt…（103.4 s 仍 busy、103.6 s 已 idle）；EngineScenarioTests › aPromptThatNeverBecomesBusyExpiresAfter3Seconds（3.2 s 后 idle）；新：StateRuleTests › m1 | ✓ |
| 5.1-04 | 5.1 修正 2 | 登记表还是 busy，但有一条比 `statusUpdatedAt` 更新的 Stop → 暂时当作 idle | `phase` L44-47 | ActivityResolverTests › registryBusyButNewerStopIsTemporarilyIdle（Stop 比登记表 busy 旧 → 不修正；Stop 之后又来提示 → 仍 busy）；EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（Stop 先到、登记表 56 ms 后才翻 idle，Stop 一到就是「做完了」）；新：StateRuleTests › m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle | ✓ |
| 5.1-05 | 5.1（任务书未写） | 登记表没有 / 不认识 status 时改用 hook 推断；修正 1 另要求提示晚于最近的 Stop，修正 2 要求 Stop 不早于最近的提示 | `phase` L34-37、L40-41、L45 | ActivityResolverTests › missingRegistryStatusFallsBackToHooks；registryBusyButNewerStopIsTemporarilyIdle（排队的下一轮） | 偏离（记录：Core/README.md「我做的小决定 · 登记表」：不认识的 status → nil，靠 hook 推断阶段；DESIGN.md 第 4 节指向该 README） |

---

## 5.2 工具追踪（ToolTracker：处理悬空和并行）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.2-01 | 5.2 Pre 到来 | ① 先判断属于主线程还是子代理（见 5.3） | SessionEngine.`processInbox` L532-537（`attributionContext` → `attributor.decide` → owner） | T-Core/HelperAttributionTests（整套，见 5.3） | ✓ |
| 5.2-02 | 5.2 Pre 到来 | ② 主线程，且距上一个主线程 Pre **超过 0.25 秒** → 新的一批 | Core/Fusion/ToolTracker.swift `batchGap = 0.25` L35；`pre` L66-73（只看主线程 Pre；用事件时间戳） | ToolTrackerTests › callsWithin250msOfThePreviousPreStayInTheSameBatch（0.2 s 同批、0.3 s 新批）；parallelCallsInTheSameMillisecondShareABatch；新：StateRuleTests › a2_batchGapIsExactly250ms（恰好 0.25 s 不算新批、0.251 s 才算并关掉旧批）；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.2-03 | 5.2 Pre 到来 | ②（续）新批次同时把更早批次里还开着的工具全部关掉，原因记为「被取代」 | `closeAll(owner: .main, reason: .superseded)` L70 | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded（`reason == .superseded`）；新：StateRuleTests › a2、b6_danglingCallIsSupersededByTheNextBatch（引擎层） | ✓ |
| 5.2-04 | 5.2 Pre 到来 | ②（续）这一步同时解决「没有 PostToolUseFailure」和「权限被拒」两种悬空 | 同上 | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded（失败）、permissionDeniedDanglingIsClosedByTheNextBatch（被拒，间隔 12 s） | ✓ |
| 5.2-05 | 5.2 Pre 到来 | ③ 把这次调用登记为打开状态 | `pre` L75-80 | ToolTrackerTests › parallelCallsInTheSameMillisecondShareABatch（`mainOpen.count == 2`） | ✓ |
| 5.2-06 | 5.2 Post 到来 | 按「工具名 + detail 都相同」关掉最早的那个打开调用 | `post` L88-90 | ToolTrackerTests › parallelCallsInTheSameMillisecondShareABatch（先 Post `/b` 再 `/a`，按内容而不是到达顺序配对）；新：StateRuleTests › a1_sameMillisecondParallelReadsPairFirstInFirstOut（引擎层） | ✓ |
| 5.2-07 | 5.2 Post 到来 | 没有这样的，就按工具名关 | `post` L91-95 | ToolTrackerTests › postFallsBackToToolNameThenIgnores（detail 对不上 → 按名字关）；新：StateRuleTests › a1、a3_postFallsBackToTheEarliestOpenCallOfTheSameName | ✓ |
| 5.2-08 | 5.2 Post 到来 | 还没有就忽略 | `post` L96 | postFallsBackToToolNameThenIgnores；postWithoutPreIsIgnored；新：StateRuleTests › a3（没有可关的 Read → 忽略） | ✓ |
| 5.2-09 | 5.2 Post 到来 | 并行调用按先进先出配对（实测同一毫秒出现过两个 Read） | `firstIndex`（最早的先关） | ToolTrackerTests › identicalParallelCallsCloseFirstInFirstOut（剩下的是 `startedAt == 0.001` 那个） | ✓ |
| 5.2-10 | 5.2 轮次边界 | Stop → 关掉主线程的全部打开调用 | SessionEngine.`processInbox` L540-542（`tracker.turnBoundary`） | 新：StateRuleTests › b1_stopEventClosesDanglingMainCalls（引擎层：悬空的 Bash 被 Stop 以 turnBoundary 关掉）；旧：ToolTrackerTests › turnBoundariesCloseAllMainCalls（tracker 单元） | ✓ |
| 5.2-11 | 5.2 轮次边界 | UserPromptSubmit → 同上 | `processInbox` L543-545 | 新：StateRuleTests › b2_userPromptSubmitClosesDanglingMainCalls；旧：ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-12 | 5.2 轮次边界 | SessionStart → 同上 | `processInbox` L546-548 | 新：StateRuleTests › b3_sessionStartClosesDanglingMainCalls；旧：ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-13 | 5.2 轮次边界 | 登记表变成 idle → 同上 | SessionEngine.`transition` L644-646（`tracker.turnBoundary(at: now)`，按修正后的阶段触发） | 新：StateRuleTests › b4_registryTurningIdleClosesDanglingMainCalls（没有 Stop，光靠登记表翻 idle）；旧：ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-14 | 5.2 轮次边界 | 会话记录出现 `stop_hook_summary` → 同上 | `update` L402-405 | 新：StateRuleTests › b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt（会话记录里的 stop_hook_summary 关掉之前开始的调用；比它新的不受影响；登记表仍 busy） | ✓ |
| 5.2-15 | 5.2 轮次边界 | （任务书写「关掉全部」）实现只关「在边界时刻之前或同时开始」的调用，小助手名下的不受影响 | `turnBoundary` L103-110 | ToolTrackerTests › aBoundaryOlderThanAnOpenCallDoesNotCloseIt；turnBoundariesCloseAllMainCalls（`helperOpen.count == 1`）；新：StateRuleTests › b5（第二段：stop_hook_summary 比开着的调用旧 → 不误关） | 偏离（记录：Core/README.md「我做的小决定 · ToolTracker」；DESIGN.md 第 4 节指向该 README，DESIGN 汇总表没列） |
| 5.2-16 | 5.2 兜底 | 登记表是 idle 而某个调用已开超过 30 分钟 → 强制关掉 | `staleAfter = 30 * 60` L37；`expireStale` L113-121；SessionEngine `update` L407（`registryIdle: record.status == .idle`） | ToolTrackerTests › staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle（29 分钟不关、31 分钟关、busy 时不关）；helperOwnedRecordsExpireRegardless；新：StateRuleTests › b7（恰好 30 分钟不关、+1 ms 才关、登记表不是 idle 绝不关）、b8_helperOwnedRecordsExpireAfter30Minutes（引擎层：小助手名下的记录 29 分钟还在、31 分钟被丢）；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |

---

## 5.3 子代理事件的归属（hook 里没有 agent_id）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.3-01 | 5.3 规则 1 | 主会话是 idle → 事件归后台小助手 | Core/Fusion/HelperAttributor.swift `decide` L67；SessionEngine.`attributionContext` L573（`effectivePhase(…, now: 事件时间) == .idle`） | T-Core/HelperAttributionTests › rule1MainIdleMeansBackgroundHelper；HelperAttributionEngineTests › idleMainSessionsBackgroundHelperEventsGoToTheHelper；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.3-02 | 5.3 规则 1 | …「没有临时 busy」：5.1 的临时 busy 不算 idle | `attributionContext` L573 用的是修正后的阶段（含临时 busy） | 无（没有测试构造「登记表 idle + 刚提交提示」时的后台事件） | ✓(无专门测试) |
| 5.3-03 | 5.3 规则 2 | 主线程有前台 Agent / Task 正开着，事件比它晚 **0.15 秒以上** → 归小助手 | `foregroundGap = 0.15` L53；`decide` L70-73（按毫秒取整比较，恰好 0.15 算「以上」）；`attributionContext` L574-576 | HelperAttributorTests › rule2ForegroundAgentOpenAndEventLaterThan150ms（0.05 s → 主线程；恰好 0.15 s、2 s → 小助手）；HelperAttributionEngineTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity（0.4 s）；新：StateRuleTests › k1_foregroundTaskAttributionBoundaryAt150ms（引擎层：前台 Task（不只是 Agent）：0.149 s 的同批调用归主线程、0.15 s 归小助手；Task 结束后新调用不再算小助手的）；FuzzRegressionTests › c003_attributionSurvivesAbsurdEventTimes | ✓ |
| 5.3-04 | 5.3 规则 3 | 有后台小助手正在活跃 → 先把事件扣住，**最多 400 ms** | `holdLimit = 0.4` L55；`decide` L75-86 | rule3NoMatchHoldsFor400msThenGoesToMain（5.39 s 仍扣住、5.41 s 归主线程）；HelperAttributionEngineTests › unmatchedEventIsHeldFor400msThenAttributedToTheMainThread；新：StateRuleTests › k3_unmatchedEventIsHeldForExactly400ms（0.39 s 仍扣住、0.41 s 归主线程）；FuzzRegressionTests › c006_attributionHoldIsBoundedEvenWithFutureTimestamps（时间戳在未来的事件 1 s 后不再被扣留，不会卡死 hook 队列；正常事件仍扣 ≤ 0.4 s） | ✓ |
| 5.3-05 | 5.3 规则 3 | 扣住期间拿「工具名 + 第一个输入字段（command / file_path / pattern / url / query / description），按前缀比较，最多 160 字」去比对 | `firstMatch` L91-99 + `ToolDetail.matches`（TranscriptLine.swift L199-209，前缀比较、160 字） | rule3MatchesHelperTranscriptAndIsAttributedToTheHelper；truncatedHookDetailMatchesByPrefix（160 字 + `…`）；rule3HoldEndsEarlyWhenTheTranscriptCatchesUp | ✓ |
| 5.3-06 | 5.3 规则 3 | …和小助手会话记录、**主会话记录**里最近的 tool_use 比对；比对上的归那一方 | `decide` L76-81（`helperUses` / `mainUses`）；「最近」= 事件前 90 s 到后 10 s 的窗口（`windowBefore` / `windowAfter` L57-58，任务书没给数字） | rule3MatchesHelperTranscript…（两边各配一个）；HelperAttributionEngineTests › busyMainWithBackgroundHelperUsesTranscriptsToTellThemApart；toolUsesFarInThePastDoNotMatch（−200 s 不算） | ✓ |
| 5.3-07 | 5.3 规则 3 | 比对不上就归主线程（两边都对得上时无法区分，也归主线程——任务书没写，代码注释说明） | `decide` L81-84 | rule3NoMatchHoldsFor400msThenGoesToMain；rule3AmbiguousMatchGoesToMain；eachToolUseIsClaimedOnlyOnce | ✓ |
| 5.3-08 | 5.3 规则 4 | 其他情况 → 归主线程 | `decide` L88 | HelperAttributorTests › noBackgroundHelperMeansMain | ✓ |
| 5.3-09 | 5.3 说明 | 小助手显示的动作直接取自它自己的会话记录 | SubagentReader.`snapshots` L186-188（`currentTool` = 它自己的最后一个未完成 tool_use） | HelperAttributionEngineTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity、idleMainSessions…（`helpers.first?.currentTool?.name`） | ✓ |
| 5.3-10 | 5.3 说明 | 即使归属判错，也只影响主 buddy，到下一个轮次边界就纠正 | 主线程 Tracker 的错归属记录由 `turnBoundary` 关掉（同 5.2-10…14） | 无（没有测试构造「归错」再看边界纠正） | ✓(无专门测试) |

---

## 5.4 动作判定（ActivityResolver）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.4-01 | 5.4 总则 | 输入是信号和当前时间，输出只由它们决定，不依赖其他状态 | `public enum ActivityResolver`，全是 static 纯函数（Core/Fusion/ActivityResolver.swift L4）；无存储属性 | ActivityResolverTests 全部用例都是「构造 SessionSignals + now → 断言」 | ✓ |
| 5.4-02 | 5.4 waiting | `waitingFor` 是 "permission prompt" 或 "sandbox request" → 等批准 | `waitingActivity` L82 | 同 4.1-16、4.1-21；新：StateRuleTests › l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen（引擎层 sandbox request） | ✓ |
| 5.4-03 | 5.4 waiting | 或者文本里含 `permission` / `allow` → 等批准（文本 = waitingFor；缺失时用比这次等待更新的 Notification 文本） | `waitingActivity` L76-83 | ActivityResolverTests › unknownWaitingTextIsClassifiedByKeywords（"…permission…"、"Allow this action?"）；missingWaitingForFallsBackToNotificationText | ✓ |
| 5.4-04 | 5.4 waiting | 等批准的工具取最新一个打开的主线程调用 | `approvalTool` L103-114（`openTools.last`） | ActivityResolverTests › permissionPromptIsApprovalWithTheNewestOpenTool（Bash `git push`，不是更早的 Read）；新：StateRuleTests › l1（取最新打开的 Bash `git push`）；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-05 | 5.4 waiting | 没有的话，从 Notification 文本里解析 `use <T>` | `approvalTool` L112；`toolName(fromNotification:)` L117-123 | ActivityResolverTests › approvalToolComesFromTheNotificationWhenNothingIsOpen（解析出 Bash；通知比这次等待旧就不用）；toolNameParsingFromNotification；新：StateRuleTests › l1（没有打开的调用 → 从 Notification 解析出 Bash） | ✓ |
| 5.4-06 | 5.4 waiting（任务书未写） | Notification 点了名、且比这次等待更新时，优先取名字对得上的那个打开调用（并行时不张冠李戴） | `approvalTool` L105-110 | ActivityResolverTests › notificationNamesTheToolAmongParallelOnes | 偏离（记录：DESIGN.md 第 4 节「动作判定」waiting 条：「Notification 点名了就取那个」） |
| 5.4-07 | 5.4 waiting | `waitingFor` 是 "input needed" 或 "dialog open" → 提问 | `waitingActivity` L84 | 同 4.1-17、4.1-18；新：StateRuleTests › l2_questionsAndPlanReview（引擎层：input needed / dialog open → 提问；AskUserQuestion 的 detail 不保留） | ✓ |
| 5.4-08 | 5.4 waiting | 或者文本里含 `input` / `question` / `elicitation` → 提问 | `waitingActivity` L84-85 | ActivityResolverTests › unknownWaitingTextIsClassifiedByKeywords（"awaiting user input"、"an elicitation is open"、"a question for you" 三个都断言） | ✓ |
| 5.4-09 | 5.4 waiting | 此时 ExitPlanMode 正开着 → 计划待审 | `waitingActivity` L90、L95（判据是「最新打开的工具是 ExitPlanMode」） | ActivityResolverTests › exitPlanModeWhileWaitingIsPlanReview（"input needed" / "dialog open" / "permission prompt" 三种 waitingFor）；新：StateRuleTests › l2 | ✓ |
| 5.4-10 | 5.4 waiting | 其他 → 其他等待，并把原始文本记下来 | `waitingActivity` L98（`.waitingOther(text ?? "")`） | ActivityResolverTests › nonPermissionWaitsFromTerminalSessions；unknownWaitingTextIsClassifiedByKeywords（"something else entirely"）；missingWaitingForFallsBackToNotificationText（无文本 → 空串）；新：StateRuleTests › l3_otherWaitsCarryTheRawText（附原始文本；批准后发「不再等你」） | ✓ |
| 5.4-11 | 5.4 waiting（实测） | AskUserQuestion / ExitPlanMode 的 Notification 文本也叫 "needs your permission to use X"，要看打开的工具名：AskUserQuestion 开着 → 提问，ExitPlanMode 开着 → 计划待审 | `waitingActivity` L88-92 | ActivityResolverTests › askUserQuestionNotificationSaysPermissionButItIsAQuestion；exitPlanModeWhileWaitingIsPlanReview（含 waitingFor = permission prompt）；新：StateRuleTests › l2（ExitPlanMode / AskUserQuestion 的通知文本都叫 permission） | 偏离（记录：DESIGN.md 第 4 节末段「实测里和任务书不一致的地方」：AskUserQuestion / ExitPlanMode 的 Notification 文本也是 …permission…） |
| 5.4-12 | 5.4 busy 1 | 有 PreCompact 但还没有 PostCompact → 整理上下文 | `busyActivity` L129-133 | ActivityResolverTests › compactingWhenPreCompactHasNoPostCompact；EngineScenarioTests › compactionThroughHooks | ✓ |
| 5.4-13 | 5.4 busy 1 | 或会话记录显示正处在 `compact_boundary` 压缩中 → 整理上下文 | `busyActivity` L134-138 | ActivityResolverTests › compactingFromTranscriptBoundary（边界之后有新行 → 不再算） | ✓ |
| 5.4-14 | 5.4 busy 1（任务书未写） | PreCompact 之后 15 分钟没有 PostCompact 就不再显示；`compact_boundary` 之后 120 秒内没有新行才算 | `compactStaleAfter = 15 * 60` L12；`transcriptCompactWindow = 120` L14 | ActivityResolverTests › compactingExpiresIfPostCompactNeverArrives（14 分钟仍显示、16 分钟不再）；120 秒窗口无断言 | 偏离（记录：Core/README.md「我做的小决定 · 压缩」；DESIGN.md 第 4 节指向该 README，DESIGN 汇总表没列） |
| 5.4-15 | 5.4 busy 2 | 距最近一次 `api_error` 不超过 `retryInMs + 15 秒`，且之后没有新的 assistant / user 行 → 重试中 | `retrySlack = 15` L10；`busyActivity` L140-146 | ActivityResolverTests › retryingWithinRetryInMsPlus15Seconds（118.9 s 是、119.1 s 否、之后有新行则否）；EngineScenarioTests › retryingThenBackToThinkingWhenTheRetryWindowPasses（16.2 s 边界）；新：StateRuleTests › c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds（3/10；2.5 s + 15 s：17.4 s 仍在、17.6 s 消退）、c2（之后出现新的 user 行 → 不再显示） | ✓ |
| 5.4-16 | 5.4 busy 2 | 显示第几次 / 共几次 | `.retrying(attempt:max:)` L144 | retryingWithinRetryInMsPlus15Seconds（`.retrying(attempt: 2, max: 10)`）；EngineScenarioTests（2/10、3/10）；新：StateRuleTests › c1（3/10）、c2（2/5） | ✓ |
| 5.4-17 | 5.4 busy 3 | 有打开的主线程工具 → 显示最新的那个 | `busyActivity` L148-150（`openTools.last`） | ActivityResolverTests › busyShowsTheNewestOpenToolWithParallelCount（Read 是最新的）；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-18 | 5.4 busy 3 | …并带上并行的个数 | `.tool(latest, parallel: openTools.count)` L149 | busyShowsTheNewestOpenToolWithParallelCount（`n == 3`）；新：StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-19 | 5.4 busy 4 | 以上都不是 → 思考中 | `busyActivity` L152 | ActivityResolverTests › busyWithoutToolsIsThinking | ✓ |
| 5.4-20 | 5.4 busy | 按 1 → 2 → 3 → 4 的顺序判断（压缩 > 重试 > 工具 > 思考） | `busyActivity` 的分支顺序 | 部分：压缩压过工具（compactingWhenPreCompact…）、重试压过工具（retryingBeatsOpenTools）都有；压缩 vs 重试的先后没有断言 | ✓(无专门测试) |
| 5.4-21 | 5.4 idle 1 | 被打断（持续 **3 秒**） | `interruptedDuration = 3` L7；`idleActivity` L164-166 | ActivityResolverTests › interruptedLasts3SecondsThenIdle（2.9 s 是、3.1 s 否）；新：StateRuleTests › e1_transcriptInterruptLastsThreeSeconds（引擎层：从登记表 idle 起 2.9 s 还在、3.1 s 消退） | ✓ |
| 5.4-22 | 5.4 idle 1 | 打断判据：会话记录里出现打断，且比上一次轮次结束更晚 | SessionEngine.`classify` L722（`interruptAt ≥ 本轮开始 − 0.5 s` 且 `> stopMarker`） | EngineScenarioTests › interruptDetectedFromTheTranscriptWithoutAnyHook、abortedMidStreamAlsoCountsAsAnInterrupt、aNormalStopAfterAnEarlierInterruptIsNotInterrupted（更旧的打断不算）；新：StateRuleTests › e1、d5_noResponseRequestedAfterAnInterruptIsNotAnError（打断之后的合成「No response requested.」不算出错） | ✓ |
| 5.4-23 | 5.4 idle 1 | 或者 hook 正常工作，但状态从 busy 变成 idle 时没有 Stop 事件 | `classify` L732-733（`stopGrace = 0.4` 后 `hookActive ? .interrupted : .finished`） | EngineScenarioTests › aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted；新：StateRuleTests › e2_hookInferredInterruptNeverShowsFinished（宽限期内不能显示 .finished）、e3（无 hook → 0.4 s 后当作做完了）、e4（宽限期内 Stop 到 → 做完了）。（e2 对应我第一次读到的问题，03:20 已被别的 QA 修掉：`transition` 里 turnEnd 先置 .none，见疑点 Q-01）；新：StateRuleTests › e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst（Stop / 打断标记以任何顺序、在 0.4 s 宽限期内任何时刻到达，结论都对，中途不先显示 .finished / .interrupted / .errored 里的错误结论；但没有禁止宽限期内显示 .idle，见疑点 Q-13） | ✓ |
| 5.4-24 | 5.4 idle 2 | 做完了（持续 **5 秒**） | `finishedDuration = 5` L8；`idleActivity` L170-172 | ActivityResolverTests › finishedLasts5SecondsThenIdle（4.9 s 是、5.1 s 否）；EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents；新：StateRuleTests › f1_finishedLastsFiveSeconds（4.9 s 还在、5.1 s 消退、idleSince == Stop 时刻） | ✓ |
| 5.4-25 | 5.4 idle 2 | 桌面会话最多等 **4 秒**看有没有新的 postTurnSummary | 数据层没有等待（元数据一变 `blocked` 就亮）；App 层 AlertCoordinator 等 8 秒（App/AlertCoordinator.swift L82） | 无（AlertCoordinator 没有单元测试） | 偏离（记录：DESIGN.md 第 10 节「与任务书不一致 / 没做的地方」表「桌面会话「做完了」最多等 4 s 看 blocked → 等 8 s」；第 11 节「提醒判定只看快照的变化…」） |
| 5.4-26 | 5.4 idle 2 | 如果是 blocked，就叠加「需要你处理」 | SessionEngine.`updateOverlays` L822-828 | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（7 s 后总结落盘 → blocked）；新：StateRuleTests › f3；新：StateRuleInvariantTests › z2（随机回放里「未读 / blocked 只在 idle」等不变量） | ✓ |
| 5.4-27 | 5.4 idle 3 | 出错：最后一次 `api_error` 已经重试到上限 | `classify` L725-726（`attempt ≥ max`、`max > 0`、之后没有新行） | 新：StateRuleTests › d1_erroredByExhaustedRetriesAlone（只有 10/10 的 api_error、没有合成消息 → 出错、unread、事件 errored）、d3、d4（重试没到上限 / 之后又有 assistant 输出 → 不算出错） | ✓ |
| 5.4-28 | 5.4 idle 3 | 或者最后一条 assistant 是合成出来的 API 错误 | `classify` L727（`syntheticErrorAt == lastAssistantAt`） | TranscriptTests › syntheticApiErrorAssistantIsRecognized（解析）；EngineScenarioTests › erroredTurnStaysErroredUntilItStartsDozing；新：StateRuleTests › d2_erroredBySyntheticApiErrorMessageAlone、d5 | ✓ |
| 5.4-29 | 5.4 idle 3（任务书未写时长） | 出错状态一直保持到开始打盹（10 分钟） | `idleActivity` L168-169（`idleFor < dozeAfter`） | ActivityResolverTests › erroredStaysUntilDozing（599 s 仍出错、601 s 打盹）；EngineScenarioTests › erroredTurnStaysErroredUntilItStartsDozing。（任务书没给时长；DESIGN.md 第 4 节「idle：…出错（一直保持到打盹）」写明了这个取舍） | ✓ |
| 5.4-30 | 5.4 idle | 判断顺序 被打断 → 做完了 → 出错；实现里出错优先于做完了 | `classify` L724-728 先于 L730 | 无（没有同时带 Stop 证据和出错证据的用例） | 偏离（记录：Core/README.md「我做的小决定 · 出错（errored）」：任务书的顺序会让出错的一轮先闪 5 秒「做完了」；DESIGN.md 第 4 节只写了「出错一直保持到打盹」，没写优先级） |
| 5.4-31 | 5.4 idle 4 | 空闲超过 **10 分钟** → 打盹 | `dozeAfter = 10 * 60`（SessionSignals L52）；`idleActivity` L176-179 | ActivityResolverTests › idleThenDozingThenSleepingAtTheThresholds（9:59 idle、10:00 dozing）；EngineScenarioTests › attachingToALongIdleSessionShowsTheRightSleepState；新：StateRuleTests › g1_dozeAt10MinutesSleepAt45Minutes（0.1 s 边界：599.9 s idle、600.1 s dozing） | ✓ |
| 5.4-32 | 5.4 idle 4 | 空闲超过 **45 分钟** → 睡着 | `sleepAfter = 45 * 60`；`idleActivity` L175 | idleThenDozingThenSleepingAtTheThresholds（44:59 dozing、45:00 sleeping）；新：StateRuleTests › g1（2699.9 s dozing、2700.1 s sleeping、24 小时仍 sleeping） | ✓ |
| 5.4-33 | 5.4 idle 4 | 两个时间都可以改：引擎层可配 | `SessionEngine.Options.dozeAfter / sleepAfter` L15-16 → `baseSignals` L602-603 | ActivityResolverTests（60 / 120 s）；EngineScenarioTests › dozeAndSleepThresholdsAreConfigurable（30 / 90 s） | ✓ |
| 5.4-34 | 5.4 idle 4 | 两个时间都可以在**设置里**改（`idle.dozeMinutes` / `idle.sleepMinutes`） | App/SettingsView.swift L96-97 有两个 Stepper，Settings.swift L17 有默认值；但 `RealProvider.make` → `SessionStore(dataRoot:usePolling:persist:)` 只用默认 Options，全 Sources 里没有任何地方读这两个键（grep 过）——改了没有任何效果 | 无 | 缺失 |
| 5.4-35 | 5.4 叠加·未读 | 一轮做完后亮起（被自己打断的不亮：README 小决定；出错也亮） | SessionEngine.`complete` L761（`kind != .interrupted` → `unread = true`） | EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（unread == true）；aTurnWithoutAStopEvent…（打断 → false）；erroredTurnStays…（出错 → true） | ✓ |
| 5.4-36 | 5.4 叠加·未读 | 你跳转到这个会话 → 清掉 | SessionEngine.`markSeen` L119；App/AppModel.swift `jump` L253-256（`provider.markSeen`） | EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（`markSeen` → false）；StoreTests › markSeenAndRerollAreSafeFromAnyThread；新：StateRuleTests › f2_unreadClearsInExactlyThreeWays（条件 1：markSeen 后不会自己再亮） | ✓ |
| 5.4-37 | 5.4 叠加·未读 | 桌面 `lastFocusedAt` 晚于这一轮结束 → 清掉 | `updateOverlays` L818 | EnginePresenceTests › focusingTheSessionInTheDesktopAppClearsUnread；新：StateRuleTests › f2（早于 / 等于本轮结束都不清，晚 1 ms 才清） | ✓ |
| 5.4-38 | 5.4 叠加·未读 | 下一轮开始 → 清掉 | `transition` L639 | EngineScenarioTests › startingTheNextTurnClearsUnread；新：StateRuleTests › f2（条件 3：下一轮开始） | ✓ |
| 5.4-39 | 5.4 叠加·blocked | 一直保持到下一轮开始 | `updateOverlays` L820-828；`transition` L640 | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（30 分钟后仍 blocked；下一轮开始清掉，即使元数据里还是旧总结）；新：StateRuleTests › f3（保持一小时；只发一次事件；completed 不亮） | ✓ |
| 5.4-40 | 5.4 叠加·安静 | busy 但 **10 分钟**内 hook 和会话记录都没有增长 | `quietAfter = 10 * 60` L33；`update` L422-423 | EngineScenarioTests › aSessionBusyForAnHourNeverDies（第 1–8 分钟 false、第 11 分钟起 true、有新 hook 事件立刻清掉）；新：StateRuleTests › h2_quietThresholdAndItsResets（599 s 不是、601 s 是；会话记录长一行 / hook 有新事件都立刻清掉） | ✓ |
| 5.4-41 | 5.4 叠加·安静 | 只是换一种画法，绝不能据此判定会话已死 | 同 4.1-29；`quiet` 只是快照标记 | aSessionBusyForAnHourNeverDies（每分钟断言 presence == .present、phase == .busy）；新：StateRuleTests › h1 | ✓ |

---

## 5.5 在场、离场、下班工位

（`Stage/OfficeScene.swift`、`SeatRenderer.swift` 的行号取自 03:25 的版本。）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.5-01 | 5.5 离场触发 | 登记文件消失 → 离场 | Core/Ingest/RegistryScanner.swift `scan` L183-186；SessionEngine.`reconcile` L261-275（这个 key 不在存活记录里 → pendingAway） | T-Core/RegistryTests › removedFilesAreReported；EnginePresenceTests › departureIsDebouncedBy3SecondsAndComingBackCancelsIt（`endProcess` 同时删文件 + 杀进程，是混合触发）；新：StateRuleTests › i1_departureDebounceThenReclaimAfter8Seconds | ✓ |
| 5.5-02 | 5.5 离场触发 | PID 已死 → 离场（文件还在也一样） | `aliveRecords` L189-205（`ProcessProbe.classify` → dead 不进存活列表） | EnginePresenceTests › aDeadPidWithALeftoverRegistryFileIsGone；新：StateRuleProcessTests › r3 | ✓ |
| 5.5-03 | 5.5 离场触发 | PID 被复用 → 离场 | 同上（`.reused` 不进存活列表） | EnginePresenceTests › pidReuseIsTreatedAsTheOldProcessBeingGone；新：StateRuleTests › i6_pidReuseGoesThroughTheSameDebounce、StateRuleProcessTests › r4 | ✓ |
| 5.5-04 | 5.5 离场 | 先防抖 **3 秒**（桌面 App 重启会带着同一个 host id 回来） | `awayDebounce = 3` L22；`reconcile` L261-271（pendingAway 期间快照仍是 `.present`，回来则什么都没发生） | EnginePresenceTests › departureIsDebouncedBy3SecondsAndComingBackCancelsIt（2.5 s 时仍在场；回来后没有离场 / 再进场事件）；aDesktopSessionWithMetadataGoesToADormantSeat…（run 3.2 s 后才是 away）；新：StateRuleTests › i1（2.95 s 仍在场、3.05 s 离场、事件只发一次）、StateRuleProcessTests › r3（真子进程退出：2.9 s 仍在场、3.1 s 离场） | ✓ |
| 5.5-05 | 5.5 离场 | 确认后播放离场动画：起身、推好椅子、挥手、走出门 | Stage/OfficeScene.swift `render` L171-173（人从 present 消失 → `startLeaving`）；Stage/Walkers.swift：起身 0.3 s、挥手 0.7 s、走出、门在身后关上（`standTime` / `waveTime` / `tail = 0.16`，L41、L31）；`chairOut` L95-102 | 部分：T-Stage/RenderingTests › walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt（离场时门开过、门洞外没有人、走完后走路系统清空）；起身 / 推椅子 / 挥手的顺序与时长没有断言 | ✓(无专门测试) |
| 5.5-06 | 5.5 离场 | 桌面会话、元数据还在、没归档 → 下班工位 | SessionEngine.`confirmAway` L279-282（`hostSessionId` + `metaReader.meta` + `!isArchived`） | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat（dormant == true、座位保留）；aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves（归档 / 终端 → dormant == false）；新：StateRuleTests › i2_dormantSeatOnlyForDesktopSessionsWithLiveUnarchivedMetadata | ✓ |
| 5.5-07 | 5.5 下班工位 | 显示器关掉 | Stage/SeatRenderer.swift `drawMonitor` L276（非 occupied → `.off`）；`ledName` L177（待机灯关） | 弱：只有金图哈希（T-Stage/RenderingTests › goldenFrameHashesAreStable，`office@12:00/t=66` 含一个下班工位），没有语义断言 | ✓(无专门测试) |
| 5.5-08 | 5.5 下班工位 | 椅子推进去 | SeatRenderer.`draw` L44-48（非 occupied 且没有 `chairOut` → 画推进去的椅子） | 同上（金图） | ✓(无专门测试) |
| 5.5-09 | 5.5 下班工位 | 外套挂到门口的衣帽架上 | OfficeScene.`render` L184-192（`dormant.prefix(coatSlots.count)`）、L305 画外套；Stage/RoomRenderer.swift L85（4 个挂钩） | 同上（金图）；`buddyctl snapshot --mode crowd10d4` 手工看过（DESIGN.md 第 7 节） | ✓(无专门测试) |
| 5.5-10 | 5.5 下班工位 | 桌牌变暗 | OfficeScene.`plateTexts` L430（`dim = v.dim \|\| mode == .dormant`）；`SeatView.dim`（L219-220 置位） | 同上（金图） | ✓(无专门测试) |
| 5.5-11 | 5.5 离场 | 其他会话 → **8 秒**后收回工位 | `awayLinger = 8` L23；`confirmAway` L282；`maintainAway` L303-306 | 新：StateRuleTests › i1_departureDebounceThenReclaimAfter8Seconds（确认离场后 7.9 s 工位还在、8.1 s 收回）；旧：EnginePresenceTests › aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves（只验上界） | ✓ |
| 5.5-12 | 5.5 下班工位来源 | 本次运行中见过的 buddy（离场后成为下班工位） | `confirmAway`：同一个 BuddyState 转入 `.away(dormant: true)` | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat；departedSessionsCompeteForTheFourDormantSeats | ✓ |
| 5.5-13 | 5.5 下班工位来源 | App 启动时 `lastActivityAt` 在 **3 小时**以内（没归档、没有活进程）的桌面会话 | `dormantRecent = 3 * 3600` L19；`bootstrapDormants` L327-347 | 弱：EnginePresenceTests › dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions 用的是 10–60 分钟前（入选）和 3 小时零 1 分钟前（落选），数据夹在 1 h 与 3 h 之外，阈值改成 2 h 也能过；归档的被排除、活会话不重复这两点有断言（aLiveSessionIsNotAlsoADormantSeat） | ✓(无专门测试) |
| 5.5-14 | 5.5 下班工位 | 最多保留 **4 个** | `dormantMax = 4` L18；`bootstrapDormants` `.prefix` L333；`maintainAway` L316-318 | EnginePresenceTests › dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions（6 个候选 → 4 个）；departedSessionsCompeteForTheFourDormantSeats（6 个离场 → 4 个） | ✓ |
| 5.5-15 | 5.5 下班工位 | 超出时先移走最久没活动的 | `maintainAway` L314-318（按 `max(since, lastActivityAt)` 排序，留最近的 4 个） | dormantSeatsAtLaunch…（留下的正好是最近活动的 1–4 号）；departedSessionsCompete…（运行中离场只断言了个数，没断言移走的是哪两个） | ✓ |
| 5.5-16 | 5.5 下班工位 | 满 **12 小时**移除 | `dormantExpire = 12 * 3600` L20；`maintainAway` L310 | EnginePresenceTests › dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted（11 小时还在、12 小时后没了） | ✓ |
| 5.5-17 | 5.5 下班工位 | 会话被归档时移除 | `maintainAway` L310（`isArchived`） | 同上（b 被归档 → 消失） | ✓ |
| 5.5-18 | 5.5 下班工位 | 会话被删除（元数据没了）时移除 | `maintainAway` L310（`meta == nil`） | 同上（c 元数据被删 → 消失） | ✓ |
| 5.5-19 | 5.5 下班工位 | 同一个身份回来时，会走回原来的工位 | 数据层：`reconcile` `.away` 分支 L237-243（座位、salt 保留，发 `arrived(freshAfterLaunch: true)`）；舞台：OfficeScene.`render` L168-170（不在上一帧 present 里且 `appearedAfterLaunch` → `startEntering`） | 数据层：EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat；新：StateRuleTests › i3_theSameIdentityComingBackDuringTheLingerSitsInTheSameSeat（8 s 收回之前带着新进程回来：坐回原座位、发一次 arrived）。舞台侧「走回去」没有任何测试，而且同一个 key 第二次回来时疑似画出两个人（`seatedAt` 从不清除，见疑点 Q-02） | ✓(无专门测试) |
| 5.5-20 | 5.5 进场 | App 启动之后新出现的会话 → 从门口走到工位坐下 | 数据层 `appearedAfterLaunch = !firstPoll` L251-256；舞台 OfficeScene.`render` L168-170、Stage/Walkers.swift `startEntering` | EnginePresenceTests › sessionsPresentAtLaunchSitDownDirectlyAndLaterOnesWalkIn（标志与 arrived 事件）；T-Stage/RenderingTests › enteringWalkerAppearsOnlyAfterTheDoorStartedOpening（门先开、0.3 s 时人已出来、走完才算坐下） | ✓ |
| 5.5-21 | 5.5 进场 | …约 **2.5 秒** | Walkers.`startEntering`：`speed = max(28, min(70, 路线长度 / 2.5))`，走路时间 = 长度 / speed；另有门开 0.1 s、坐下 0.3 s（`lead` / `sitTime`） | 弱：enteringWalkerAppearsOnly… 只断言了「1.0 s 时没走完、6.0 s 时走完」，2.5 s 没有钉住；路线短于 70 px 或长于 175 px 时速度被夹住，走路时间不是 2.5 s | ✓(无专门测试) |
| 5.5-22 | 5.5 进场 | App 启动时就在跑的会话 → 直接坐好（数据层标志） | SessionEngine.`reconcile` L251-256（`appearedAfterLaunch: false`） | EnginePresenceTests › sessionsPresentAtLaunchSitDownDirectlyAndLaterOnesWalkIn | ✓ |
| 5.5-23 | 5.5 进场 | …舞台上不走路、直接坐好 | OfficeScene.`render` L167（`prevKeys == nil` 的第一帧不启动走路；`appearedAfterLaunch == false` 的也不走） | 无（RenderingTests 里大量用例把 `animateWalkers` 关掉，没有断言「启动时不走路」） | ✓(无专门测试) |
| 5.5-24 | 5.5 进场 | …显示器从左到右依次开机，每台间隔 **100 ms** | 没有按座位错开：`v.boot = (time − (seatedAt ?? p.appearedAt)) / 0.3`（OfficeScene L215），启动时所有 Performer 的 `appearedAt` 相同 → 所有显示器同时开机 | 无 | 偏离-未记录 |

---

## 5.6 表现层节奏（VisualDirector：每个 buddy 一个 Performer）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.6-01 | 5.6 总则 | 每个 buddy 一个 Performer，由 VisualDirector 持有 | Stage/VisualDirector.swift `performers` L8、`update` L43-79 | T-Stage/PerformerTimingTests 各用例都通过 `director.performers[key]` 取 Performer | ✓ |
| 5.6-02 | 5.6 等待类 | 等待状态要持续 **0.4 秒**才开始转身 | Stage/Performer.swift `update` L227（`time − waitSince ≥ 0.4`） | PerformerTimingTests › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5（0.36 s 不转、0.44 s 已转）；aWaitingBlipShorterThan0_4SecondsDoesNotTurnTheBuddy | ✓ |
| 5.6-03 | 5.6 等待类 | 持续 **1.5 秒**才发提醒 | App/AlertCoordinator.swift `observe` L57（`now − ep.since ≥ 1.5`，`ep.since` 是协调器第一次看到这段等待的时刻） | 无（AlertCoordinator 没有任何单元测试） | ✓(无专门测试) |
| 5.6-04 | 5.6 等待类 | 等待结束后，再保持面向你 **1.5 秒**才转回去 | `update` L233-238（`waitEndedAt`，`time − e ≥ 1.5`） | waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5（结束后 1.4 s 仍面向、1.6 s 已转回） | ✓ |
| 5.6-05 | 5.6 等待类 | 这样连着批准好几次时不会来回转 | `update` L225（新一段等待到来时 `waitEndedAt = nil`，不转回也不重新转） | 无（只有单次等待的用例） | ✓(无专门测试) |
| 5.6-06 | 5.6 最短停留 | 姿势最短停留 **1.5 秒** | `update` L249（`time − poseSince ≥ 1.5`） | PerformerTimingTests › poseNeverChangesFasterThanEvery1_5Seconds（读 ↔ 改每 0.4 s 交替，相邻两次姿势变化 ≥ 1.5 s） | ✓ |
| 5.6-07 | 5.6 最短停留 | 屏幕内容最短停留 **0.8 秒** | `update` L253（`time − screenSince ≥ 0.8`） | PerformerTimingTests › screenNeverChangesFasterThanEvery0_8Seconds（每 0.2 s 交替） | ✓ |
| 5.6-08 | 5.6 最短停留 | 桌牌文字最短停留 **1.0 秒** | `update` L259-266（只有「动作」部分受限；数字换了动作没换、等待类、空牌直接更新） | PerformerTimingTests › plateActionTextNeverChangesFasterThanEverySecond（每 0.3 s 交替） | ✓ |
| 5.6-09 | 5.6 最短停留 | 停留期间只记下最新的目标状态，跳过中间态（Read → Grep → Read = 一直在读，屏幕最多每 0.8 秒换一次） | 目标每帧重算（`targetPose` / `targetScreen`），到期才切换：`update` L244-253 | 弱：上面三个用例只断言了相邻两次变化的最小间隔，没有断言「切过去的是最新目标、中间态被跳过」 | ✓(无专门测试) |
| 5.6-10 | 5.6 切换方式 | 同一类工具之间切换，只换屏幕内容 | 姿势通道按 `PoseKind`、屏幕通道按 `ScreenKind` 各自独立（`targetPose` L102-139、`targetScreen` L141-178）；同类工具姿势相同，只有屏幕变 | 无 | ✓(无专门测试) |
| 5.6-11 | 5.6 切换方式 | …用 **4 帧从上往下的擦除**过渡 | 没有：屏幕直接硬切（`screen = ts`，`screenT` 只是让新内容的动画从 0 开始）；全源码里没有擦除 / wipe 的实现（grep 过） | 无 | 缺失 |
| 5.6-12 | 5.6 切换方式 | 不同类之间切换，走过渡帧：先放下道具，再开始新动作 | 没有过渡帧：`pose = tp` 直接切，道具随姿势一起立刻出现 / 消失（`PoseFrame.props` → SeatRenderer L68-77）；手 / 头靠弹簧平滑，但不是「先放下道具」 | 无 | 缺失 |
| 5.6-13 | 5.6 切换方式 | 等待类状态到来时，最多等当前过渡帧播完（≤ **250 ms**）就立即插入 | 因为没有过渡帧，等待类是立即插入：屏幕 / 桌牌绕过最短停留（L253 `waitingScreen \|\|`、L262 `asking != nil \|\|`），转身按 0.4 s 确认（L227），姿势通道不管它（L248） | 无 | 偏离-未记录 |
| 5.6-14 | 5.6 长时间状态 | Bash 超过 **8 秒** → 「往后靠着盯屏幕」姿势 | `targetPose` L116（`elapsed > 8 → .leanBack`，3–8 s 是 `.restAtDesk`）；屏幕 `.terminalLong` L154 | 无 | ✓(无专门测试) |
| 5.6-15 | 5.6 长时间状态 | WebFetch / WebSearch 超过 **8 秒** → 同上 | `targetPose` L118 | 无 | ✓(无专门测试) |
| 5.6-16 | 5.6 长时间状态 | Monitor 超过 **8 秒** → 同上 | `targetPose` L117：Monitor 一开始就是 `.leanBack`（和 6.5 表「Monitor：往后靠」一致），不等 8 秒 | 无 | ✓(无专门测试) |
| 5.6-17 | 5.6 长时间状态 | 思考超过 **20 秒** → 「深度思考」姿势 | `targetPose` L106（`el = now − activitySince`，`el > 20 → .thinkingDeep`） | 无 | ✓(无专门测试) |
| 5.6-18 | 5.6 做完一轮 | busy → idle 后先等 **0.4 秒**（防止这一轮其实还没完） | `targetPose` L132（`.finished` 且 `el < 0.4` → 沿用 `lastBusyPose`）。只有姿势通道在等这 0.4 s，屏幕 / 桌牌 / 小旗立刻切到「做完了」（数据层在证据不足时已不再先报 `.finished`，见疑点 Q-01 的修复） | 无 | ✓(无专门测试) |
| 5.6-19 | 5.6 做完一轮 | 伸个 **1.2 秒**的懒腰 | `targetPose` L133（`el < 1.6 → .stretch`）；Stage/PoseLibrary.swift `.stretch` L154-160（`p = t / 1.2`） | 无（也没有断言 1.5 s 姿势最短停留会不会把懒腰截短，见疑点 Q-07） | ✓(无专门测试) |
| 5.6-20 | 5.6 做完一轮 | 再侧身靠到椅背上 | `targetPose` L133（`.leanSide`）；PoseLibrary `.leanSide` L161-170 | 无（金图 `office@12:00/t=66` 覆盖了这一姿势，仅哈希） | ✓(无专门测试) |
| 5.6-21 | 5.6 做完一轮 | 未读标记一直保留 | 数据层：未读只在 3 个条件下清（见 5.4-36…38）；舞台：`SeatView.flag = snapshot.unread`（Performer.`seatView` L472）→ SeatRenderer.`drawMonitor` L304 插小旗 | EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（「做完了」结束 5 s 后 `unread` 仍为 true）；小旗的画法只有金图哈希 | ✓ |
| 5.6-22 | 5.6 错开 | 多个 buddy 同时变化时，按顺序每个晚 **90 ms** | VisualDirector `update` L61（`time + min(0.6, 0.09 × order)`，按座位顺序；等待类不错开） | PerformerTimingTests › simultaneousChangesAreStaggeredBy90msEach（5 人，相邻间隔 ≈ 0.09 ± 0.04 s） | ✓ |
| 5.6-23 | 5.6 错开 | …最多错开 **0.6 秒** | 同上 `min(0.6, …)` | 弱：同一用例断言了 `最后一个 − 第一个 ≤ 0.6 + 1/30`，但只有 5 个人，最大错开只有 0.36 s，够不到上限；去掉 `min` 这个用例照样通过（要 ≥ 8 个人才碰得到） | ✓(无专门测试) |

---

## 5.7 工具归类（ToolCatalog）

（实现都在 `Core/Fusion/ToolCatalog.swift` 的 `category(of:)` L22-46；输入先经 `cleanName` 去掉 hook 截断留下的 `…`。测试主要是 `T-Core/ModelTests › toolCatalogClassifies` 和几个间接用例——**只断言了表里的一小部分名字**。）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.7-01 | 5.7 表 | read：Read、NotebookRead | L25 | 部分：Read（ModelTests、EngineBasicTests › arrivalThenBusyThenTool 的 `category == .read`）；NotebookRead 无 | ✓(无专门测试) |
| 5.7-02 | 5.7 表 | search：Grep、Glob、LS | L26 | 无 | ✓(无专门测试) |
| 5.7-03 | 5.7 表 | edit：Edit、MultiEdit | L27 | 部分：MultiEdit（ModelTests）；Edit 无 | ✓(无专门测试) |
| 5.7-04 | 5.7 表 | write：Write、NotebookEdit | L28 | 无 | ✓(无专门测试) |
| 5.7-05 | 5.7 表 | bash：Bash、BashOutput、KillShell（实现另加 TaskOutput、TaskStop：新版本里的新名字，真实日志里见过） | L30 | 部分：Bash（EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents、ActivityResolverTests › approvalToolComesFromTheNotificationWhenNothingIsOpen）、TaskStop、TaskOutput（ModelTests）；BashOutput、KillShell 无。（多出的两个名字已记在 DESIGN.md 第 5 节表格「bash」行和 Core/README.md「tool 名字 / 别的」） | ✓(无专门测试) |
| 5.7-06 | 5.7 表 | monitor：Monitor | L31 | 无 | ✓(无专门测试) |
| 5.7-07 | 5.7 表 | web：WebFetch、WebSearch | L32 | 无 | ✓(无专门测试) |
| 5.7-08 | 5.7 表 | browser：`mcp__Claude_Browser__*`、`mcp__claude-in-chrome__*` | L42（前缀匹配） | 部分：`mcp__Claude_Browser__navigate`（ModelTests）；claude-in-chrome 无 | ✓(无专门测试) |
| 5.7-09 | 5.7 表 | computer：`mcp__computer-use__*` | L43 | ModelTests › toolCatalogClassifies（`mcp__computer-use__app_click`） | ✓ |
| 5.7-10 | 5.7 表 | delegate：Agent、Task、Workflow、SendMessage | L33 | 无（HelperAttribution 测试里出现 Agent，但只断言名字，没断言类别） | ✓(无专门测试) |
| 5.7-11 | 5.7 表 | todo：TodoWrite、TaskCreate、TaskUpdate、TaskList、TaskGet | L34 | 部分：TaskCreate（ModelTests）；其余四个无 | ✓(无专门测试) |
| 5.7-12 | 5.7 表 | skill：Skill、ToolSearch、ListSkills | L35 | 无 | ✓(无专门测试) |
| 5.7-13 | 5.7 表 | planEnter：EnterPlanMode | L36 | 无 | ✓(无专门测试) |
| 5.7-14 | 5.7 表 | planExit：ExitPlanMode | L37 | 间接：ActivityResolverTests › exitPlanModeWhileWaitingIsPlanReview（依赖 `category == .planExit`） | ✓ |
| 5.7-15 | 5.7 表 | planExit 等待时就是「计划待审」 | ActivityResolver `waitingActivity` L90、L95 | 同 5.4-09 | ✓ |
| 5.7-16 | 5.7 表 | sendFile：SendUserFile | L38 | 无 | ✓(无专门测试) |
| 5.7-17 | 5.7 表 | schedule：ScheduleWakeup、CronCreate（实现另加 CronDelete、CronList） | L39 | 无。（多出的名字记在 DESIGN.md 第 5 节表格「schedule」行的 `Cron*`） | ✓(无专门测试) |
| 5.7-18 | 5.7 表 | mcp：其他 `mcp__<server>__*`，**显示 server 名** | L44；`makeCall` L49-54（`server` 只对 mcp / browser / computer 类填）；`mcpServer(of:)` L14-20 | ModelTests › toolCatalogClassifies（`mcp__ccd_session_mgmt__…` → mcp）、mcpServerFromTruncatedName（含 UUID 形状的 server 名）；ToolTrackerTests › truncatedToolNamesMatchByPrefix（`server == "ccd_session_mgmt"`） | ✓ |
| 5.7-19 | 5.7 表 | unknown：其余全部 | L45 | ModelTests › toolCatalogClassifies（"SomethingNew" → unknown） | ✓ |
| 5.7-20 | 5.7（hook 坑 2） | 被 hook 截断、结尾带 `…` 的名字也能归类 | `cleanName` L6-10 | ModelTests › toolCatalogClassifies（`mcp__ccd_session_mgmt__search_session_tr…` → mcp） | ✓ |

---

## 缺口（缺失 / ✓(无专门测试) / 偏离-未记录 的汇总，按严重度排序）

范围说明：本文只追踪任务书第 4、5 节；5.6 里「提醒」那一句在 App/AlertCoordinator.swift，顺带看了它和 7.2 重合的数字，但 6.x / 7.x 没有逐条追。下面列的「无测试」都是**合入别的 QA 新增测试之后**还剩下的（5.2-10…14、4.2-27、5.4-27、5.5-11 已被新测试补上，不再算缺口）。

### A. 缺失 / 偏离-未记录（实现和任务书不符，DESIGN.md 里没有记录，或记录与实现相反）

1. **【高】5.4-34　设置里的「空闲多久后打盹 / 睡着」是摆设。** `idle.dozeMinutes` / `idle.sleepMinutes`（App/SettingsView.swift 两个 Stepper、Settings.swift 默认值）没有接到 `SessionEngine.Options.dozeAfter / sleepAfter`：`RealProvider.make` 只构造默认 Options，全部 Sources 里没有别处读这两个键；同理 `dormant.recentHours`（对应 5.5-13）没接线，`dormant.max`（对应 5.5-14）只在 AppModel.refreshDerived 里按座位号 `.prefix`（见疑点 Q-03）。DESIGN.md 第 4 节写着「设置里可改」，使用说明.txt 第 107 行也这么说——文档和实现不一致。
   - 应修：给 `SnapshotProvider` / `SessionStore` 加一个 `applyConfig(dozeAfter:sleepAfter:dormantRecent:dormantMax:)`（在 ingest 队列上改 `engine.options`，别重建引擎），AppModel 在 `.settingsChanged` 时推送。
   - 应补测：StoreTests 里「改配置后 idle → dozing 的时刻跟着变」（虚拟时钟）；再加一个「SettingsView 里每个 `@AppStorage` 键都在 Sources 里被读取」的静态测试，防止以后又出摆设。
2. **【中】5.6-11、5.6-12、5.6-13　「切换方式」三条都没做，DESIGN.md 里没有记录**：屏幕 4 帧从上往下的擦除、异类切换的过渡帧（先放下道具再开始新动作）、等待类插入最多等 250 ms。现状是屏幕硬切、道具随姿势瞬间出现 / 消失、等待类绕过最短停留立即插入。
   - 二选一：实现（PerformerTimingTests 增加「同类切换只换屏幕且经过 4 帧」「异类切换先有道具消失的过渡帧」的断言，FlickerScan 的 `transition` 白名单要同步放宽）；或者在 DESIGN.md「与任务书不一致」汇总表补三行，写明「用手 / 头弹簧平滑代替过渡帧、屏幕硬切」。
3. **【中】5.5-24　启动时就在的会话，显示器不是「从左到右依次开机、每台间隔 100 ms」，而是所有显示器同时开机**（Stage/OfficeScene.swift `render` 里 `v.boot` 的起点是各 Performer 的 `appearedAt`，启动时完全相同）。
   - 应修：`boot` 起点 = `appearedAt + rank × 0.1`（rank = 启动那一刻按座位从左到右的序号）；应补测：同一时刻 6 个座位的 `SeatView.boot` 依次相差 0.1 s；或者在 DESIGN.md 记为「同时开机」。

### B. ✓(无专门测试)（实现了，但没有测试，或测试是弱断言 / 只覆盖枚举的一部分）

4. **【高】5.6-03　AlertCoordinator 完全没有单元测试**（1.5 s 才提醒；另外和 7.2 重合的 20 s 节流、2 s 合并、桌面「做完了」等 8 s 看 blocked、终端 8 s 延迟、用时 < 30 s 不提醒都没有测）。它是纯函数式的（`observe(snaps, now:, settings:, isLooking:, privacy:)`），最容易补：AlertCoordinatorTests——等批准 1.49 s 不发 / 1.5 s 发；同 buddy 同类 20 s 内第二条被节流；2 s 内两个 buddy 合并成「2 位同事在等你」；被打断的一轮不提醒（数据层刚修过「先报做完了再改口」，这里正好加一道回归）。
5. **【中】5.5-05、5.5-07、5.5-08、5.5-09、5.5-10、5.5-13、5.5-19、5.5-21、5.5-23　下班工位 / 离场 / 进场的画面语义只有金图哈希 + 「门洞外不穿帮」**：应补（SeatView 层，不用截图）：dormant 座位 `screen == .off`、椅子推进去（`chairOut == false`）、`dim == true`；`coats.count == min(下班人数, 4)`；离场 Walker 的起身 0.3 s / 挥手 0.7 s；进场走路时间落在 [2, 3.2] s；启动首帧不启动 Walker；同一个 key 第二次回来时该座位是 `.empty` + `chairOut`（这条会抓住疑点 Q-02）；5.5-13 再加「2.9 h 入选、3.1 h 落选」。
6. **【中】5.6-05、5.6-09、5.6-10、5.6-14、5.6-15、5.6-16、5.6-17、5.6-18、5.6-19、5.6-20、5.6-23　Performer 的其余节奏没有测试**：连续批准不来回转（5.6-05）、「跳过中间态」（5.6-09）、同类切换只换屏幕（5.6-10）、Bash / Web / Monitor 8 秒靠椅背（5.6-14…16）、思考 20 秒深度思考（5.6-17）、做完一轮的 0.4 s → 懒腰 1.2 s → 侧靠（5.6-18…20）、错开上限 0.6 s（5.6-23，要 ≥ 8 个 buddy 才碰得到上限）。都能用 PerformerTimingTests 现成的 `run(...)` 假时钟写。
7. **【中】5.7-01、5.7-02、5.7-03、5.7-04、5.7-05、5.7-06、5.7-07、5.7-08、5.7-10、5.7-11、5.7-12、5.7-13、5.7-16、5.7-17　工具归类表几乎没测**（`toolCatalogClassifies` 只有约 10 个名字）：写一个表驱动测试，把任务书 5.7 的每个名字（含 `mcp__claude-in-chrome__*`、BashOutput、KillShell、Cron* 等）逐个断言类别，约 40 行。
8. **【低】数据层小项：4.1-13、4.2-04、4.2-07、4.2-08、4.2-10、4.3-04、4.3-17、4.3-24、4.3-36、4.3-40、4.3-41、4.3-42、4.3-43、4.4-03、4.4-04、4.4-08、5.3-02、5.3-10、5.4-20**——4.1-13（pidDomain 等字段）、4.2-04（SessionEnd 没有任何测试）、4.2-07 / 4.2-08 / 4.2-10（Edit / Write / Glob / Task 走的 case 没逐个断言）、4.3-04（1 MiB 块）、4.3-17（`turn_duration` 修正用时）、4.3-24（meta 的 toolUseId / spawnDepth）、4.3-36（字节预过滤）、4.3-40（30 秒写盘节流，需要注入时钟）、4.3-41（退出写盘链路：`SessionStore.stop` → `shutdown` → `flush`）、4.3-42 / 4.3-43（后台低优先级 / 一次只扫一个文件：可断言队列 qos 与「同时只有一个 `scan` 在跑」）、4.4-03 / 4.4-04（桌面元数据里没断言过的字段）、4.4-08（`status_detail` 只出现在悬停卡片）、5.3-02（「没有临时 busy」）、5.3-10（归属判错到边界纠正）、5.4-20（压缩 vs 重试的先后）。
9. **【低】安全红线里只能靠静态审计的四条：4.6-03、4.6-05、4.6-11、4.6-12。** 建议加一个「源码审计」测试：扫描 Sources/**/*.swift，禁止 `URLSession` / `NWConnection` / `socket(` / `connect(` / `SecItem` 等；写文件的 API（`writeAtomically`、`write(to:`、`FileManager…createFile`）只允许出现在白名单文件里。

### C. 偏离，但记录不全（可以留，只需补文档）

10. 只记在 Core/README.md、DESIGN.md 汇总表里没有：4.1-27（缺 kind 当 interactive）、4.3-33（不做 cost-state 补差）、5.1-05（无 status 时用 hook 推断）、5.2-15（轮次边界只关「之前开始」的调用）、5.4-14（压缩的 15 分钟 / 120 秒窗口）、5.4-30（出错优先于做完了；这条还没有测试——应补「同时有 Stop 证据和出错证据 → 出错」）。建议把这几条抄进 DESIGN.md 第 10 节「与任务书不一致」表。
11. 已在 DESIGN.md 里有位置：4.3-09、5.4-06、5.4-11（第 4 节正文）、5.4-25（第 10 节表）。

---

## 疑点（读代码时怀疑有问题、但没法在只读条件下确认；供主线程后续验证）

| 编号 | 位置 | 怀疑 | 怎么验证 |
|---|---|---|---|
| Q-01（已被别的 QA 修掉） | Core/Fusion/SessionEngine.swift `transition` L653-656（我第一次读到的版本里 busy → idle 时先写 `st.turnEnd = .finished`，`finalizePendingEnd` 在 `classify` 返回 nil 时不改） | 「登记表翻 idle、没有 Stop、会话记录里也还没有打断行」时，被打断的一轮会先以 `.finished` 出现约 0.4 s（`stopGrace`）：屏幕通道立刻切绿色 ✓ 又被 0.8 s 最短停留拖住；`alerts.finishedTurns` 让白板「正」字多记一笔；用时 ≥ 30 s 的一轮会挂起一条「做完了」提醒且之后不会被清掉。**03:20 起 `transition` 里改成先置 `.none`**（源码里有一段注释说明），新增的 StateRuleTests › e2_hookInferredInterruptNeverShowsFinished 覆盖它。 | 已在源码里确认修复；建议跑 e2。修复的副作用见 Q-13 |
| Q-02（中） | Stage/OfficeScene.swift `render` L183、L206、L215：`seatedAt` 只在 nil 时写（`for s in present` 那一行）、`walkers.isBusy(s.key), seatedAt[s.key] == nil` 才把座位画成空座 + 拉出的椅子、`v.boot` 用旧的 `seatedAt`；全文件没有任何地方删 `seatedAt`（03:25 的版本里仍然如此） | 同一个 key 在一次运行里第二次（及以后）回到办公室时：`startEntering` 会启动走路，但上面那个条件已经为假，座位直接画成「已经坐着的人」，门口又走进来一个——两个人叠在一起，且没有开机动画。启动时就在的会话第一次回来是对的，第二次才错；App 启动后进来过的会话第一次回来就错（桌面 App 回收空闲进程后再打开，正是 4.1 描述的常见路径） | RenderingTests 里加：同一个 key 进场 → 走完 → 离场 → 再进场，第二次进场期间断言 `lastSeatViews[seat].mode == .empty && chairOut` |
| Q-03（低） | App/AppModel.swift `refreshDerived` L59-60（`dormant.max` 那一行） | `dormant.max` 只在这里对「按座位号排好的快照」取 `.prefix(N)`：N < 4 时留下的是座位号小的，不是最近活动的（5.5「先移走最久没活动的」）；引擎里那几个名额仍占着座位 | 设置里把 `dormant.max` 改成 2，造 4 个下班工位、活动时间和座位号顺序相反，看留下哪两个 |
| Q-04（低） | App/AlertCoordinator.swift `observe` 里等待分支的三处 `continue`（L58、L60、L61） | 会跳过同一轮里后面的 `prevActivity[key] = cur`（L72-73）。目前等待 → 做完之间一定有 busy 快照，没出错，但很脆 | 单测里连续喂「等待、等待、直接 finished」的快照，看 `finishedTurns` |
| Q-05（低） | Stage/VisualDirector.swift `update` L59-66（`if let pd = pending[s.key]` 那一段） | 某个 buddy 正处于「错开」待应用状态时变成等待类：`changed && !needsUser` 为假，到点后套用的是**过期的** `pd.snap`（不是等待态），要多一帧才切到等待态，等待类没做到「立即插入」（最长晚 0.6 s） | PerformerTimingTests 里：两个 buddy 同帧变化，第二个在 pending 期间又变成 `.waitingApproval`，看 `applied` 里出现的顺序 |
| Q-06（低） | Core/Fusion/SessionEngine.swift `hookActive` L520-527（`hookDropoutGap = 15`） | 没有工具的长时间生成结束时，会话记录先于 Stop hook 落盘（差几十毫秒），这一瞬间 `hookActive` 会为 false；若正好赶上「登记表翻 idle 又没有 Stop」，`classify` 里 `sig.hookActive ? .interrupted : .finished` 会判成「做完了」 | 用虚拟时钟造：hook 最后事件在 t0，会话记录 t0+40 s 一行，登记表 idle，无 Stop |
| Q-07（低） | Stage/Performer.swift `update` L249（姿势最短停留 1.5 s）与 `targetPose` L132-133（懒腰只在 0.4–1.6 s 内是目标） | 上一个姿势若是 1.5 s 内刚换的（短工具后立刻结束的一轮），懒腰会被截短或整个跳过（目标已经变成 `.leanSide`） | PerformerTimingTests：`.tool(Read)` 开始后 0.5 s 就 `.finished`，看 `pose` 序列里有没有 `.stretch` |
| Q-08（低） | Core/Ingest/RegistryScanner.swift `scan`（`failures < maxRetries`）；T-Core/RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms | 「每隔 50 ms 重试一次，最多 5 次」被实现成「首读 + 4 次重试 = 共 5 次读」，测试把「共 5 次」写成了断言；任务书更自然的读法是 5 次重试 | 只需确认意图 |
| Q-09（低） | Core/Ingest/TokenLedger.swift `handle` L231（`parsed.kind == .assistant`；文件头注释写的是 `message.role`）；TranscriptLine.swift `parse` | 计入用量的判据是顶层 `type == "assistant"`，用量表的 `parse_line` 用的是 `message.role == "assistant"`。真实数据里两者一致，但移植不完全逐字 | 拿真实数据对照用量表的全量结果（新增的 StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree 会在假 home 树上做独立实现对照，但假数据里 type 和 role 必然一致） |
| Q-10（已被别的 QA 修掉） | Core/Util/FileIO.swift `isForbidden` / `open` | 我第一次读到的保险只按路径名判断（大小写敏感、不解析符号链接、不管 NUL）。**03:25 起**已改成：不区分大小写、NUL 拒绝、任何一段叫 `cc-socks` 的目录都拒绝、符号链接按真实路径判断、打开后再用 `F_GETPATH` 核对、只打开普通文件且 `O_NONBLOCK` | 已在源码里确认；对应测试 FuzzRegressionTests › c007_*、c008_*（我没运行） |
| Q-11（低） | App/JumpService.swift `DesktopMeta`（`files()` / `lastFocused` / `isMostRecentlyFocused`）、App/AppModel.swift `isUserLooking` | App 层用 FileManager 直接读桌面元数据找 `lastFocusedAt`，绕开了 FileIO 的保险，也不是「所有读文件的唯一入口」；每次调用都重列目录、重读并解析全部 `local_*.json`（约 20 KB 一个）。调用次数很少（每段等待 / 每次「做完了」最多几次），只是「唯一入口」的说法不严谨 | 只需确认是否要收进 FileIO |
| Q-12（低） | App/AppDelegate.swift 里 `--test-jump` 的两条 `DebugTools.log`（L104、L107） | 调试日志会写会话标题（标题可能是 AI 根据对话生成的；4.6：调试日志只写元数据）。只在测试参数下触发 | 只需确认可接受，或改成只写 hostSessionId |
| Q-13（低） | Core/Fusion/SessionEngine.swift `transition` L653-656（Q-01 的修复）→ `idleActivity` | 修复后宽限期（≤ 0.4 s）内 `turnEnd == .none`，动作是 `.idle`（不再是 `.finished`）。Stop 先到的正常流程不受影响（同一次 `update` 里就定下来）；只有「登记表先翻 idle、Stop 后到 / 没有 Stop」的少见路径，舞台会先切到「空闲桌面」再切「停止标志 / 做完了」，被 0.8 s 的屏幕最短停留拖住，最长约 0.8 s 的错位。比先闪绿色 ✓ 好，但还不是「保持 busy 直到判定」 | 在 e2 的第一次 `poll()` 之后看 `activity`：现在应是 `.idle`；若想更彻底，宽限期内保持上一个 busy 动作 |

---

## 统计

总条数：**288**（表格行数，每行一条要求；由脚本按每行最后一格的状态数出来的；快照约 03:30，已并入别的 QA 新增的 StateRule*Tests / FuzzRegressionTests 的断言）

| 状态 | 条数 |
|---|---|
| ✓ | 205 |
| ✓(无专门测试) | 58 |
| 偏离 | 10 |
| 偏离-未记录 | 2 |
| 缺失 | 3 |
| N/A | 10 |
| 合计 | 288 |

按章节：

| 章节 | 合计 | ✓ | ✓(无专门测试) | 偏离 | 偏离-未记录 | 缺失 | N/A |
|---|---|---|---|---|---|---|---|
| 4.0 | 2 | 1 | 0 | 0 | 0 | 0 | 1 |
| 4.1 | 38 | 34 | 1 | 1 | 0 | 0 | 2 |
| 4.2 | 31 | 25 | 4 | 0 | 0 | 0 | 2 |
| 4.3 | 43 | 31 | 8 | 2 | 0 | 0 | 2 |
| 4.4 | 9 | 5 | 3 | 0 | 0 | 0 | 1 |
| 4.5 | 14 | 13 | 0 | 0 | 0 | 0 | 1 |
| 4.6 | 12 | 7 | 4 | 0 | 0 | 0 | 1 |
| 5.1 | 5 | 4 | 0 | 1 | 0 | 0 | 0 |
| 5.2 | 16 | 15 | 0 | 1 | 0 | 0 | 0 |
| 5.3 | 10 | 8 | 2 | 0 | 0 | 0 | 0 |
| 5.4 | 41 | 34 | 1 | 5 | 0 | 1 | 0 |
| 5.5 | 24 | 14 | 9 | 0 | 1 | 0 | 0 |
| 5.6 | 23 | 8 | 12 | 0 | 1 | 2 | 0 |
| 5.7 | 20 | 6 | 14 | 0 | 0 | 0 | 0 |

说明：「✓」只表示「实现了、且有测试的断言真的检查到了这条」；测试我**没有运行**，所以「测试通过」这件事本身没有验证（DESIGN.md 第 9 节记录的是 269 个 Swift 测试 + 13 个 Python 测试通过，是别的 QA 加测试之前的数字）。新增测试里 Fuzz 那份是「先写失败测试、再修」的回归测试，我读到的时候部分修复还没落地。
