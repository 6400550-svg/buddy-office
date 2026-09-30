# 任务书第 4、5 节 · 逐条 spec-trace（定稿）：数据源 + 状态判定 + 表现层节奏

> 这是 `QA/spec-trace-core.md`（03:10–03:45 两位只读追踪员写的第一版，288 条）的**定稿**。结构和编号不变；每一行都回到任务书原文（`~/Desktop/Buddy办公室-开发提示词.md` 第 4、5 节）核对过要求，再按 05:1x–05:5x 的源码和测试逐行更新了状态和证据（最后一次核对：2026-09-29 05:5x）。

## 定稿说明

- **状态只剩三种**（第一版里没落实的那几种：没有专门测试的 ✓、没记录理由的偏离、没实现、没法判断，都已消灭）：
  - **✓**：实现了，并且「测试」列里至少有一个测试的断言真的检查到了这条要求的数字 / 行为（不只是金图哈希）。
  - **偏离（DESIGN.md §x）**：实现和任务书不同，理由在 DESIGN.md 里（每一条我都 grep 确认了那段文字真的存在；原来只写在 `Sources/BuddyCore/README.md` 里的，已经在 DESIGN.md 第 13 节末尾补了一节「数据层 / 状态机的偏离」，共 11 条，每条写了偏离了什么、为什么、影响）。
  - **✓（间接验证：…）**：只用在确实没法自动化测的地方（真实 GUI 点击会真的打开 Claude / 终端、真实的终端会话这台机器上没有）。这类一共 2 条，单独列在文末的「间接验证清单」，可以原样搬进 REPORT.md。
- **第一版之后发生了什么**（所以很多行的状态变了）：
  - 数据层：`QA/issues-core.md`（C-001…C-035，30 个已修）、`QA/issues-logic.md`（L-001、L-003 已修：一轮结束时先报「做完了」再改口、压缩结束后还显示「整理上下文」）、新增 `Tests/BuddyCoreTests/StateRule*Tests.swift` / `Fuzz*Tests.swift` / `SourceAuditCoreTests.swift`。
  - 表现层：`QA/issues-stage.md`（TA-001…013、SP-01…05：其中 SP-05 修掉了「启动时显示器不是依次开机」，即第一版里 5.5-24 那条没记录理由的偏离）、新增 `PerformerMappingTests`（6.5 表逐行）/ `WalkersAndOffDutyTests` / `MonitorTests` 等。
  - 应用层：`QA/issues-app.md`（A-001…A-029、B-001…B-010）：设置终于接到了数据层（5.4-34，原来是没接上）、`AlertCoordinator` 有了单元测试（5.6-03：1.5 秒去抖、20 秒节流、2 秒合并、桌面 8 秒等总结）、离场的人从舞台记录里清掉（第一版疑点 Q-02）。
- **这次新增的测试**（都在没改任何产品代码的前提下写的，debug 构建 0 警告，在整套 `swift test` 里稳定通过）：
  - `Tests/BuddyCoreTests/SpecTraceCoreTests.swift`（27 个）：登记表其余字段、十个 hook 事件、hook 各事件的 extra、按工具取 detail 的全部规则、桌面 / 终端同一串 hook、`-` 开头的目录、1 MiB 读块、`turn_duration` 修正用时、cost-state、token 字节预过滤、账本 30 秒节流、退出时落盘、后台低优先级 / 一次只扫一个文件、桌面元数据全字段、元数据不能把 idle 变 busy、只读 / 只写自己目录、没有第三方依赖、子代理归属的两个边界、busy 判断顺序、下班工位的 3 小时窗口和「先移走最久没活动的」、工具归类整张表。
  - `Tests/BuddyStageTests/SpecTraceStageTests.swift`（14 个）：三个通道的最短停留（正好 1.5 / 0.8 / 1.0 秒）、连着批准不来回转、跳过中间态、同类工具只换屏幕、等待类立即插入、错开上限 0.6 秒、长时间状态的 8 秒 / 20 秒边界、做完一轮（0.4 秒 → 1.2 秒懒腰 → 侧身靠着 → 未读旗）、离场时间线、进场 2.5 秒、下班工位的显示器 / 待机灯 / 衣帽架、`status_detail` 只在悬停卡片里。其中 1 个（等待类状态在「错开」推迟期间到来）写的时候先用 `withKnownIssue` 钉住了一个已确认的小缺口（G-1）；写完之后产品代码被修掉了（`QA/issues-stage.md` SP-06），包装已去掉，现在是一条普通断言，见「遗留缺口」。
  - `Tests/BuddyOfficeTests/SpecTraceAppTests.swift`（1 个）：设置里「最多保留」调小时留下的是最近活动的下班工位（第一版疑点 Q-03）。
  - 每个新测试都在私有副本里做过**变异验证**（把数字改一点，测试必须变红），结果见文末。
- **表里做了哪些整理**：实现列里的行号全部去掉了（多人并行改代码时行号一直在漂，只留函数名）；「新：」「旧：」「我没有运行」这类第一版的过程性说明去掉了；3 行的「要求」列改写得更准确（4.2-28 加了真实压缩样本、5.2-15 加了 SessionEnd、5.4-35 加了「被你自己打断的不亮」）；原来 10 行「不适用」全部落成 ✓ 或偏离（其中 4.5-06 是偏离，其余是补了测试 / 证据的 ✓，只有 4.1-38 是间接验证）。
- 路径缩写：`Core/` = `Sources/BuddyCore/`；`Stage/` = `Sources/BuddyStage/`；`App/` = `Sources/BuddyOffice/`；`T-Core/` = `Tests/BuddyCoreTests/`；`T-Stage/` = `Tests/BuddyStageTests/`；`T-Py/` = `Tests/hook_merge_test.py`。测试写成「测试文件名（不带 `.swift`）› 测试函数名」，同一个文件里的函数用「、」连着写；`AlertCoordinatorTests`、`EngineConfigTests`、`DebugLogTests`、`SourceAuditTests` 等在 `Tests/BuddyOfficeTests/`；`StateRuleTests` 里的 `f2_…` 这类用例名是「字母 + 数字 + 下划线」开头，全名都写出来了，可以直接 grep。
- 怎么跑：`BUDDY_SCRATCH=<自己的目录> scripts/dev.sh test --filter SpecTrace`（只跑这次新增的）；全套 `scripts/dev.sh test`；Python 那部分 `python3 Tests/hook_merge_test.py`。表里不含任何对话内容（prompt）。

## 统计

总条数：**288**（表格行数，每行一条要求）

| 状态 | 条数 |
|---|---|
| ✓ | 268 |
| 偏离（DESIGN.md §x 里写明理由） | 18 |
| ✓（间接验证：…） | 2 |
| 合计 | 288 |

按章节：

| 章节 | 合计 | ✓ | 偏离 | ✓（间接验证） |
|---|---|---|---|---|
| 4.0 | 2 | 2 | 0 | 0 |
| 4.1 | 38 | 35 | 2 | 1 |
| 4.2 | 31 | 31 | 0 | 0 |
| 4.3 | 43 | 41 | 2 | 0 |
| 4.4 | 9 | 9 | 0 | 0 |
| 4.5 | 14 | 13 | 1 | 0 |
| 4.6 | 12 | 12 | 0 | 0 |
| 5.1 | 5 | 4 | 1 | 0 |
| 5.2 | 16 | 15 | 1 | 0 |
| 5.3 | 10 | 10 | 0 | 0 |
| 5.4 | 41 | 33 | 7 | 1 |
| 5.5 | 24 | 23 | 1 | 0 |
| 5.6 | 23 | 20 | 3 | 0 |
| 5.7 | 20 | 20 | 0 | 0 |

## 最近一次验证

- `BUDDY_SCRATCH=<自己的目录> scripts/dev.sh test --filter SpecTrace`：**42 个测试、3 个套件全部通过**（Core 27 + Stage 14 + App 1；debug 构建 0 警告）。
- 全新的构建目录、从零编译整个包（debug，245 个编译步骤）：**0 警告、0 错误**，同样 42 个测试全部通过。
- 整套 `scripts/dev.sh test`（含别人的全部测试）：**684 个测试、75 个套件全部通过**，0 失败、0 警告、0 个 known issue。
- 稳定性：连续 15 次 `--filter SpecTrace`（同一份构建，机器上同时有别的 agent 在跑 ASAN / 长跑，负载 15–60）：通过 15 次，失败 0 次。
- 环境敏感性（已处理）：机器负载 60–80 时 `.background` 队列会被饿住，token 扫描要等很久；早先一次整套在那种负载下，别人写的几条依赖后台扫描的测试超时过。我的两条会等后台扫描的测试（4.3-41、4.3-42）已把等待上限放宽到 30–90 秒（都是「等到条件成立就返回」，不是固定睡眠，所以平时不会变慢）。测试里没有真实时间 / 网络：状态机用假时钟，文件用临时目录。


---

## 4（章首说明）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.0-01 | 4 章首 | 全部只读，不需要任何配置就能拿到全部状态 | Core/Util/FileIO.swift（只读 `open(O_RDONLY)`）；Core/Paths.swift `Paths.real`（默认真实 home，只有 `--data-root` 才换根） | T-Core/RegistryTests › engineNeverWritesUnderClaudeDir；SpecTraceCoreTests › theEngineOnlyWritesInsideItsOwnSupportFolder（完整跑一遍引擎，假 home 里除了自己的 Application Support/BuddyOffice 之外没有任何文件变化）；SourceAuditCoreTests › fileReadsGoThroughFileIOWithAShortReviewedAllowlist（读文件只有 FileIO 一个入口） | ✓ |
| 4.0-02 | 4 章首 | 旧笔记 `~/.claude/monitor/DATA-SOURCES.md`（8 月版本）可以参考，冲突时以本节为准 | 代码里没有任何地方读旧笔记，也不依赖 ~/.claude/monitor 下的脚本；和旧笔记 / 任务书不一致的实测结论以任务书 4、5 节为准，不一致的地方记在 DESIGN.md 第 4 节末段、第 13 节和 Core/README.md「数据源实测结论」 | SpecTraceCoreTests › theOldDataSourcesNoteIsNeverRead（所有非注释的源码里没有 `DATA-SOURCES` / `.claude/monitor/` / `hook.sh` 路径 / `close-by-tty` 引用；FakeTree 是往假 home 里写测试数据的夹具，除外） | ✓ |

---

## 4.1 活会话登记表 `~/.claude/sessions/<pid>.json`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.1-01 | 4.1 文件规则 | 每个活 claude 进程一个 `<pid>.json`，进程退出文件被删 | Core/Ingest/RegistryScanner.swift `scan`（文件消失 → removed）；Core/Fusion/SessionEngine.swift `reconcile`（消失 → pendingAway） | T-Core/RegistryTests › removedFilesAreReported；EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat（endProcess 同时删文件 + 杀进程，是混合触发） | ✓ |
| 4.1-02 | 4.1 文件规则 | 只打开文件名匹配 `^\d+\.json$` 的文件 | Core/Paths.swift `isRegistryFileName`（另限 ≤10 位数字）；RegistryScanner.`scan` | RegistryTests › fileNamePattern（123.json 过；`.key`、`.sha.json`、abc.json、12a.json、`.json`、`.json.bak` 全拒）；StateRuleTests › n2_onlyPidJsonFilesAreOpened（只打开 1001.json / 1003.json；`.key`、`.bak`、非数字名连 stat 都没做） | ✓ |
| 4.1-03 | 4.1 文件规则 | `<pid>.<sha256>.key` 绝对不能打开（连 stat 都不碰） | Core/Util/FileIO.swift `isForbidden` / `open`（保险：不区分大小写、拒 NUL、按真实路径判断、只开普通文件）；RegistryScanner 只处理匹配名的文件 | RegistryTests › keyFilesAreNeverOpened（不可读假 .key + `openObserver`：0 次打开、`forbiddenHits` 不变）；RegistryTests › safetyNetRefusesKeyAndSocketPaths；StateRuleTests › n2_onlyPidJsonFilesAreOpened（`.key` 连 stat 都没做）；FuzzRegressionTests › c007_symlinkToKeyFileIsRefused（符号链接指向 .key 也拒绝）、c007_caseVariantsNulAndDotDotAreForbidden（`.KEY`、NUL、`../`）；FuzzSecurityTests › fuzz_variantsNeverOpenForbiddenFiles、fuzz_registryScannerWithDecoyFiles（27 种绕过写法与诱饵目录：`.key` 一个都没被 open） | ✓ |
| 4.1-04 | 4.1 原地重写 | 读到写了一半的 JSON：解析失败时保留上一份好记录 | RegistryScanner.`scan`；`parse` | RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms；RegistryTests › emptyFileDuringTruncateIsTreatedAsHalfWritten；StateRuleTests › n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine（引擎层：写到一半 → 仍在场、动作不变） | ✓ |
| 4.1-05 | 4.1 原地重写 | 每隔 50 ms 重试一次 | `RegistryScanner.retryInterval = 0.05` | RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms 断言 `r.nextRetry == now + 0.05`；StateRuleTests › n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine（`nextWake` ≤ 50 ms） | ✓ |
| 4.1-06 | 4.1 原地重写 | 最多 5 次 | `maxRetries = 5`（`failures < 5` 才排下一次） | RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms 断言「首读 + 4 次重试 = 共 5 次读」后 `nextRetry == nil`；StateRuleTests › n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine（引擎层：12 次 50 ms 心跳后仍是上一份好记录；写完整后立刻更新）。「最多 5 次」按共 5 次读计，「5 次重试（共 6 次读）」也说得通，两种读法在实践中没有区别（半截文件微秒级就写完） | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：登记表「半截文件每隔 50 ms 重试一次，最多 5 次」按共 5 次读理解） |
| 4.1-07 | 4.1 字段 | 所有字段按可选，只有 `pid`、`sessionId` 必需 | RegistryScanner.`parse`（pid 是数字 + sessionId 非空） | RegistryTests › missingFieldsAreOptionalButPidAndSessionIdAreRequired（缺 sessionId / 缺 pid / 空 sessionId 都被忽略，只剩必需字段的记录可用）；RobustnessTests › aRegistryFileThatIsADirectoryOrHasWeirdTypesIsIgnored | ✓ |
| 4.1-08 | 4.1 字段·基本信息 | `pid`、`sessionId`（= 会话记录 UUID）、`cwd`、`startedAt`（毫秒） | `parse`（`TimeUtil.date(fromJSONMillis:)`） | RegistryTests › parsesEveryField（startedAt = 1790654597.849 s、sessionId）；EnginePresenceTests › snapshotCarriesTheDescriptiveFields（cwd、pid） | ✓ |
| 4.1-09 | 4.1 字段·procStart | UTC 的 lstart 格式，例 `Tue Sep 29 03:23:08 2026` | Core/Util/TimeUtil.swift `parseProcStart` | RegistryTests › parsesEveryField（procStart = 04:03:17 UTC）；RegistryTests › procStartParsingHandlesPaddingSpaces（1790652188）；FuzzRegressionTests › c001_procStartExtremeValuesDoNotTrap（天文数字 / 负数的年份时分秒 → nil） | ✓ |
| 4.1-10 | 4.1 字段·procStart | 日期个位数时用空格补位；解析前先把连续空格压成一个 | `parseProcStart`（按空白切分） | RegistryTests › procStartParsingHandlesPaddingSpaces（`Wed Sep  9 03:23:08 2026` = 1788924188）；乱码 / 未知月份返回 nil | ✓ |
| 4.1-11 | 4.1 字段·procStart | 用 en_US_POSIX、UTC、格式 `EEE MMM d HH:mm:ss yyyy` 解析 | 自写解析器（不用 DateFormatter，UTC 由 `daysFromCivil` 算出），结果等价；文件头注释说明原因 | 同上（含 `formatProcStart` ↔ `parseProcStart` 往返相等） | ✓ |
| 4.1-12 | 4.1 字段·其他 | `version` / `kind` / `entrypoint` / `hostSessionId` / `name` / `status` / `waitingFor` / `statusUpdatedAt` 被读取并使用 | `parse` | RegistryTests › parsesEveryField；EnginePresenceTests › snapshotCarriesTheDescriptiveFields（cliVersion = 2.1.284）、entrypointsMapToOrigins；EngineScenarioTests › waitingVariantsThroughTheEngine（waitingFor） | ✓ |
| 4.1-13 | 4.1 字段·其他 | `pidDomain` / `nameSource` / `nameSince` / `updatedAt` / `peerProtocol` / `peerFeatures` 存在时不出错 | `parse` 解析 pidDomain / nameSource / nameSince / updatedAt（引擎不使用）；peerProtocol / peerFeatures 不解析，多出的键一律忽略 | SpecTraceCoreTests › registryOtherFieldsAreToleratedAndTheSocketPathIsNeverKept（六个字段和 messagingSocketPath 都写进 JSON：前四个值读对，记录里没有 socket / messaging / peer 字段）；RegistryTests › unknownFieldsAndUnknownStatusAreTolerated | ✓ |
| 4.1-14 | 4.1 字段 | `messagingSocketPath`：不要使用 | `parse` 不读该字段；FileIO 拒 `.sock` / `/cc-socks/`；源码里没有 socket / connect 调用（grep 过） | SpecTraceCoreTests › registryOtherFieldsAreToleratedAndTheSocketPathIsNeverKept（记录里没有存 messagingSocketPath 的字段）；RegistryTests › unknownFieldsAndUnknownStatusAreTolerated（JSON 含该字段，记录照常）、safetyNetRefusesKeyAndSocketPaths；SourceAuditCoreTests › noNetworkNoCredentialsNoSubprocesses（数据层源码里没有 `socket(` / `NWConnection` / `URLSession`）、noCodeMentionsKeyOrSocketFileNamesExceptTheGuardAndPathConstants | ✓ |
| 4.1-15 | 4.1 status | 取值 `busy` / `waiting` / `idle`；不认识的值 → nil 但记录保留 | Core/Model/Activity.swift `Phase(rawValue:)`；`parse` | RegistryTests › parsesEveryField（busy）；RegistryTests › unknownFieldsAndUnknownStatusAreTolerated（"starting" → nil，`statusRaw` 保留）；RobustnessTests chaos 里带 "weird" | ✓ |
| 4.1-16 | 4.1 waitingFor | `"permission prompt"` → 等批准 | Core/Fusion/ActivityResolver.swift `waitingActivity` | ActivityResolverTests › permissionPromptIsApprovalWithTheNewestOpenTool；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-17 | 4.1 waitingFor | `"input needed"`（AskUserQuestion / 对话框）→ 提问 | `waitingActivity` | ActivityResolverTests › inputNeededAndDialogOpenAreQuestions；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-18 | 4.1 waitingFor | 终端会话 `"dialog open"` → 提问 | `waitingActivity` | ActivityResolverTests › inputNeededAndDialogOpenAreQuestions；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-19 | 4.1 waitingFor | 终端会话 `"goal proposal"` → 其他等待 | `waitingActivity` | ActivityResolverTests › nonPermissionWaitsFromTerminalSessions；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-20 | 4.1 waitingFor | 终端会话 `"worker request"` → 其他等待 | 同上 | 同上 | ✓ |
| 4.1-21 | 4.1 waitingFor | 终端会话 `"sandbox request"` → 等批准 | `waitingActivity` | ActivityResolverTests › sandboxRequestIsApproval；EngineScenarioTests › waitingVariantsThroughTheEngine | ✓ |
| 4.1-22 | 4.1 entrypoint | `claude-desktop` / `claude-desktop-3p` / `local-agent` → 桌面 App | RegistryRecord.`origin` | RegistryTests › entrypointMapsToOrigin（三项）；EnginePresenceTests › entrypointsMapToOrigins | ✓ |
| 4.1-23 | 4.1 entrypoint | `claude-vscode` → VS Code | 同上 | 同上 | ✓ |
| 4.1-24 | 4.1 entrypoint | 其他（含缺省）→ 终端 | 同上 | RegistryTests › entrypointMapsToOrigin（cli、sdk-ts、nil） | ✓ |
| 4.1-25 | 4.1 kind | 只显示 `"interactive"` | `parse` | RegistryTests › onlyInteractiveSessionsAreShown；EnginePresenceTests › nonInteractiveSessionsNeverBecomeGhostColleagues | ✓ |
| 4.1-26 | 4.1 kind | background / job / sdk / spare / worker 不画成幽灵同事 | 同上 | 同上（五种 kind 逐个写进假登记表，只剩 interactive 的一个 buddy） | ✓ |
| 4.1-27 | 4.1 kind | （任务书未规定）缺 `kind` 的记录按 interactive 显示 | `parse`（nil 不过滤） | RegistryTests › onlyInteractiveSessionsAreShown（20.json 无 kind → 显示） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：缺 kind 的记录按 interactive 显示） |
| 4.1-28 | 4.1 延迟 | 状态变成 waiting 约 49 ms；一轮结束变成 idle 约 8 ms | （观测值，不是实现要求；对实现的要求是延迟这么大时时间线仍然对、不闪错误的状态）`phase` 的两个临时修正；Stop 一到就在同一次 update 里定下「做完了」（`transition` → `classify`） | SpecTraceCoreTests › theObservedRegistryLatenciesProduceTheRightTimeline（Pre 先到、49 ms 后登记表才变 waiting：先是 Bash、再是等批准（Bash），activitySince = 登记表变化的时刻，只发一次 needsUser；Stop 先到、8 ms 后登记表才翻 idle：一直是「做完了」，只发一次 turnFinished）；StateRuleTests › m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle；端到端延迟的实测见 DESIGN.md 第 9 节（数据层回调 p95 34 ms） | ✓ |
| 4.1-29 | 4.1 没有心跳 | 会话可连续 busy 67 分钟以上、`statusUpdatedAt` 不变 → 判断存活只看进程 | SessionEngine.`aliveRecords`（只调 `ProcessProbe.classify`）；ActivityResolver 没有「时间旧就判死」的分支 | ActivityResolverTests › aSessionBusyForAnHourIsStillBusy（1…600 分钟）；EngineScenarioTests › aSessionBusyForAnHourNeverDies（62 分钟）、aWaitingSessionStaysWaitingNoMatterHowLong（两小时）；StateRuleTests › h1_twoHoursOfBusyIsQuietNotDead（busy 连续 2 小时：在场、busy、同一个工具、无离场事件） | ✓ |
| 4.1-30 | 4.1 存活判断 | `kill(pid, 0)` 返回 0 → 存在 | Core/Ingest/ProcessProbe.swift `SystemProcessProbe.probe` | RegistryTests › systemProbeSeesThisProcess（本进程 alive）；StateRuleProcessTests › r1_realStartTimeAndLiveness（真子进程：alive；退出后 ESRCH = dead） | ✓ |
| 4.1-31 | 4.1 存活判断 | 返回 EPERM 也算存在 | `probe` | RegistryTests › systemProbeSeesThisProcess（pid 1：launchd，kill 给 EPERM → alive）；StateRuleProcessTests › r2_epermCountsAsAlive（引擎里也一直在场） | ✓ |
| 4.1-32 | 4.1 存活判断 | 返回 ESRCH 算已死 | `probe` | RegistryTests › systemProbeSeesThisProcess（pid 2000000000 → dead）；EnginePresenceTests › aDeadPidWithALeftoverRegistryFileIsGone；StateRuleProcessTests › r1_realStartTimeAndLiveness、r3_recycledProcessIsDebouncedBy3Seconds（真子进程退出 → 防抖 3 s 后离场） | ✓ |
| 4.1-33 | 4.1 存活判断 | 用 `sysctl(KERN_PROC_PID)` 读 `p_starttime` | `SystemProcessProbe.startTime` | RegistryTests › systemProbeSeesThisProcess（sysctl 可用时断言启动时间在过去 30 天内；沙箱里为 nil 时不断言）；StateRuleProcessTests › r1_realStartTimeAndLiveness（真子进程：sysctl 读到的启动时间落在启动前后 2 s 内） | ✓ |
| 4.1-34 | 4.1 存活判断 | 与 `procStart` 相差超过 2 秒 → PID 已被别的进程复用 | `ProcessProbe.startTolerance = 2`；`classify` | RegistryTests › classification（+1.9 s alive；+2.5 s、−3 s reused）；EnginePresenceTests › pidReuseIsTreatedAsTheOldProcessBeingGone（差 10 s → away；差 1.5 s → present）；StateRuleTests › i4_pidReuseToleranceIsExactlyTwoSeconds（恰好 2.0 s 仍算同一个进程、2.001 s 才算复用；−2.001 s 也算）、i6_pidReuseGoesThroughTheSameDebounce；StateRuleProcessTests › r1_realStartTimeAndLiveness、r4_pidReuseWithARealProcess（真进程） | ✓ |
| 4.1-35 | 4.1 存活判断 | sysctl 失败（如沙箱）→ 「未知」→ 当作还活着 | `ProcessStatus.State.unknown`；`classify`（startTime nil → alive） | RegistryTests › classification（unknown → alive；startTime nil → alive；procStart nil → alive）；EnginePresenceTests › unknownProbeStateMeansAlive；StateRuleTests › i4_pidReuseToleranceIsExactlyTwoSeconds、i5_aliveWithoutAStartTimeStaysPresent（kill 成功但读不到启动时间 → 一直在场） | ✓ |
| 4.1-36 | 4.1 存活判断 | 绝不能因为时间戳旧就判定会话死了 | 同 4.1-29 | 同 4.1-29；StateRuleTests › h1_twoHoursOfBusyIsQuietNotDead | ✓ |
| 4.1-37 | 4.1 回收 | 桌面 App 回收空闲进程；用户再打开时带着同一个 hostSessionId 重新出现 → 还是同一个人 | Core/Fusion/IdentityResolver.swift `resolve`（host 别名）；SessionEngine.`reconcile` `.away` 分支 | IdentityTests › hostAliasWinsEvenWhenPidAndSessionIdChange；EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat | ✓ |
| 4.1-38 | 4.1 终端会话 | 字段应大致相同、没有 hostSessionId；碰到活终端会话要核对，碰不到就靠 fixture | 终端记录走同一个 `parse`；无 host → 别名 `sid:` / `proc:`，key 用 `t:` | fixture：EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles、terminalResumeInANewProcessGivesTheSameBuddyBack；RegistryTests › entrypointMapsToOrigin（cli 等 → 终端）、missingFieldsAreOptionalButPidAndSessionIdAreRequired；SpecTraceCoreTests › desktopAndTerminalSessionsAreDrivenByTheSameHookStream（没有 hostSessionId 的终端会话喂同一串 hook，动作时间线和桌面会话逐步相同）。真实终端会话的登记表字段没有核对过：这台机器上终端版 claude（2.1.267）的登录已过期（DESIGN.md 第 9.1 节），重新登录要碰凭据，没有做；任务书自己给了退路（碰不到就靠 fixture）。见「间接验证清单」 | ✓（间接验证：本机没有活着的终端会话） |

---

## 4.2 ccmon 的 hook 事件流 `~/.claude/.monitor/<session_id>.events.jsonl`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.2-01 | 4.2 路径 | 只按登记表里的 sessionId 拼文件名，绝不扫描目录 | Core/Paths.swift `hookLogPath`（`isSafeID` 白名单）；SessionEngine.`openReaders`；Core/Fusion/SessionStore.swift `fsEvents`（别的会话 / Codex 的文件事件直接忽略） | T-Core/HookLogTests › unsafeSessionIdsNeverBecomePaths；RegistryTests › codexHookFilesInTheSameDirectoryAreNeverTouched；FuzzTailerTests › hookKnownPitfallsUnderMutation（④ 各种坏 sessionId 都拼不出路径） | ✓ |
| 4.2-02 | 4.2 | 不要改 ccmon 的任何文件（只读） | FileIO 只读 `open(O_RDONLY)`；引擎里没有写 ~/.claude 的调用 | RegistryTests › engineNeverWritesUnderClaudeDir（假 home 的 .claude 树里所有文件的大小 + mtime 不变） | ✓ |
| 4.2-03 | 4.2 格式 | 每行 `{"ts","ev","tool","detail","extra"}` | Core/Ingest/LineSanitizer.swift `parseStrict` | HookLogTests › normalLine；FuzzRegressionTests › c003_absurdHookTimestampsAreRejectedAtParseTime（ts 是天文数字 / 0 / 负数 / 布尔 → 拒绝；正常毫秒照常） | ✓ |
| 4.2-04 | 4.2 | 10 个事件：SessionStart / SessionEnd / UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SubagentStop / PreCompact / PostCompact | `HookEvent` 常量（LineSanitizer.swift）；SessionEngine.`processInbox` 每个事件都有分支（`SessionEnd` 和 Stop 等一样是轮次边界） | SpecTraceCoreTests › allTenRegisteredHookEventsAreRecognised（十个事件名与任务书一致、逐个解析；十个事件按真实次序依次进引擎，SessionEnd 之后不留悬空的调用；没见过的事件名被忽略）；StateRuleTests › b9_sessionEndClosesDanglingMainCalls、l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen（Notification）、k2_subagentStopIsOnlyASummaryHint（SubagentStop）；EngineScenarioTests 里的 Pre / Post / Stop / Prompt / SessionStart / PreCompact / PostCompact | ✓ |
| 4.2-05 | 4.2 detail | 最多 160 字，超长截断并加 `…` | `ToolDetail.maxLength = 160`（Core/Ingest/TranscriptLine.swift）；`matches`（去掉结尾 `…` / U+FFFD 后按前缀比） | HookLogTests › toolDetailKeyFollowsTheHookRules（300 字 → 160；"npm te…" 前缀匹配）；HelperAttributionTests › truncatedHookDetailMatchesByPrefix（160 字 + `…`） | ✓ |
| 4.2-06 | 4.2 detail 取值 | Bash → command | `ToolDetail.key` | HookLogTests › toolDetailKeyFollowsTheHookRules；SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（Bash → command，同时有 description 时取 command） | ✓ |
| 4.2-07 | 4.2 detail 取值 | Read / Edit / Write → file_path | `ToolDetail.key`（同 4.2-06） | SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（逐个工具名断言取的字段：Read / Edit / Write → file_path；MultiEdit / NotebookEdit / TodoWrite 取不到 → 空）；HookLogTests › toolDetailKeyFollowsTheHookRules | ✓ |
| 4.2-08 | 4.2 detail 取值 | Grep / Glob → pattern | `ToolDetail.key`（同 4.2-06） | SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（逐个工具名断言取的字段：Grep / Glob → pattern；MultiEdit / NotebookEdit / TodoWrite 取不到 → 空）；HookLogTests › toolDetailKeyFollowsTheHookRules | ✓ |
| 4.2-09 | 4.2 detail 取值 | WebFetch / WebSearch → url 或 query | `ToolDetail.key`（同 4.2-06） | HookLogTests › toolDetailKeyFollowsTheHookRules（url、query 两种都断言）；SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（WebFetch → url、WebSearch → query；同时有 url 和 query 取 url） | ✓ |
| 4.2-10 | 4.2 detail 取值 | Task / Agent → description | `ToolDetail.key`（同 4.2-06） | SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（逐个工具名断言取的字段：Task / Agent → description；MultiEdit / NotebookEdit / TodoWrite 取不到 → 空）；HookLogTests › toolDetailKeyFollowsTheHookRules | ✓ |
| 4.2-11 | 4.2 detail 取值 | Skill → skill | `ToolDetail.key`（同 4.2-06） | HookLogTests › toolDetailKeyFollowsTheHookRules；SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（Skill → skill） | ✓ |
| 4.2-12 | 4.2 detail 取值 | 其他工具 → 第一个 `description` | `ToolDetail.key`（同 4.2-06） | HookLogTests › toolDetailKeyFollowsTheHookRules（`mcp__x__y`）；SpecTraceCoreTests › toolDetailKeyFollowsEveryRuleOfTheTaskBook（MultiEdit / NotebookEdit / TodoWrite 没有 description → 空） | ✓ |
| 4.2-13 | 4.2 extra | UserPromptSubmit → prompt 前 200 字，**绝不能显示** | LineSanitizer.`finalize`（解析时就置空） | HookLogTests › userPromptIsDroppedAtParseTime；FuzzTailerTests › hookKnownPitfallsUnderMutation（② 200 个随机 extra，UserPromptSubmit 的 extra 一律为空） | ✓ |
| 4.2-14 | 4.2 extra | Notification → message，只见过 `"Claude needs your permission to use <T>"` | 保留 `extra`；ActivityResolver.`toolName(fromNotification:)` | HookLogTests › notificationTextIsKept；ActivityResolverTests › toolNameParsingFromNotification | ✓ |
| 4.2-15 | 4.2 extra | SessionStart → source（startup / resume / clear / compact / fork） | SessionEngine.`processInbox`（只用 `compact` → 相当于 PostCompact） | EngineScenarioTests › compactionThroughHooks（compact）；其余 source 不参与任何逻辑 | ✓ |
| 4.2-16 | 4.2 extra | PreCompact → trigger、SessionEnd → reason、PostToolUse → `len=N` | 解析保留 `extra`：PreCompact 的 trigger、SessionEnd 的 reason、PostToolUse 的 `len=N`、Notification 的 message、SessionStart 的 source 原样留下；UserPromptSubmit 的丢掉；引擎只用 `source=compact` 和 Notification 的文本 | SpecTraceCoreTests › hookExtraPayloadsFollowTheTaskBook（各事件的 extra 原样保留，UserPromptSubmit 的 extra 一律丢掉）；HookLogTests › notificationTextIsKept、userPromptIsDroppedAtParseTime | ✓ |
| 4.2-17 | 4.2 | 桌面 App 里的会话也会触发这些 hook | 引擎对桌面 / 终端 / VS Code 会话读同一条 hook 文件（`Paths.hookLogPath(sessionId:)`），处理逻辑不按来源分叉 | SpecTraceCoreTests › desktopAndTerminalSessionsAreDrivenByTheSameHookStream（同一串 hook 分别喂给桌面会话和终端会话，8 步动作时间线逐步相同）；真实数据：DESIGN.md 第 8 节（真实的桌面会话的动作随 hook 变化） | ✓ |
| 4.2-18 | 4.2 坑 1 | 目录里约 60% 是 Codex 的文件：只按 sessionId 拼文件名 | 同 4.2-01 | RegistryTests › codexHookFilesInTheSameDirectoryAreNeverTouched（Codex 文件不被打开、不变成 buddy） | ✓ |
| 4.2-19 | 4.2 坑 2 | `tool` 被截成 40 字符加 `…`：去掉 `…`，剩下的当前缀匹配 | LineSanitizer.`splitTool`；ToolTracker.`namesMatch`；ToolCatalog.`cleanName` | HookLogTests › truncatedMcpToolNameKeepsPrefixAndMatchesByPrefix；ToolTrackerTests › truncatedToolNamesMatchByPrefix；FuzzTailerTests › hookKnownPitfallsUnderMutation（③ 每一种截断长度：去掉 `…`、前缀匹配都成立） | ✓ |
| 4.2-20 | 4.2 坑 3 | AskUserQuestion 的 detail 不是问题本身，绝不能显示 | LineSanitizer.`finalize`；ToolTracker.`pre` / `post` | HookLogTests › askUserQuestionDetailIsNeverKept（含降级解析路径 + Tracker 第二道保险）；FuzzTailerTests › hookKnownPitfallsUnderMutation（① 300 个变异：AskUserQuestion 的 detail 一律为空） | ✓ |
| 4.2-21 | 4.2 坑 4 | MultiEdit / NotebookEdit / TodoWrite 的 detail 永远是空 → 不能因 detail 空而配不上 | 通用机制：Tracker 按「名字 + detail」配对（空 = 空）；`ToolDetail.matches` 空对空为真 | HookLogTests › toolDetailKeyFollowsTheHookRules（MultiEdit key == ""；`matches("","")`）；ToolTrackerTests › truncatedToolNamesMatchByPrefix（mcp 工具空 detail 的 pre / post 配对） | ✓ |
| 4.2-22 | 4.2 坑 5 | 子代理的工具调用也记在父会话文件里，且没有 agent_id | Core/Fusion/HelperAttributor.swift（见 5.3） | T-Core/HelperAttributionTests（整套） | ✓ |
| 4.2-23 | 4.2 坑 6 | 没注册 PostToolUseFailure：失败 / 被拒时只有 Pre 没有 Post，会一直悬空 | ToolTracker 新一批关掉旧的（见 5.2-03） | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded、permissionDeniedDanglingIsClosedByTheNextBatch | ✓ |
| 4.2-24 | 4.2 坑 7 | 每行先用 `String(decoding:as: UTF8.self)` 清洗，再做 JSON 解析 | LineSanitizer.`string` → `parseHookLine` | HookLogTests › invalidUTF8IsCleanedNotFatal（被截断的中文字节 → U+FFFD，JSON 仍合法）；FuzzTailerTests › hookLineWithInvalidUTF8Everywhere（非法 UTF-8 放在行首 / 行中 / 每个字段 / 行尾：不崩溃、不放行坏 ts） | ✓ |
| 4.2-25 | 4.2 坑 7 | JSON 解析失败时，只抠出 ts、ev、tool 三个字段 | LineSanitizer.`parseDegraded`（扫描式，不是正则，效果等价） | HookLogTests › truncatedUnicodeEscapeFallsBackToRegexFields（degraded == true；ts / ev / tool 对；detail == ""）；FuzzTailerTests › hookLineTruncatedAtEveryByte（在每一个字节位置截断：结果要么 nil，要么和原事件前缀一致） | ✓ |
| 4.2-26 | 4.2 坑 7 | 实在解析不了的行直接跳过，不能让整个文件失败 | Core/Ingest/HookLogReader.swift `poll`（`skippedLines += 1`） | HookLogTests › garbageLinesAreSkippedWithoutFailingTheWholeFile（3 行被跳过、其余读到）；RobustnessTests › randomGarbageInEveryDataSourceNeverCrashesTheEngine；FuzzTailerTests › hookReaderIncrementalEqualsOneShot（坏行被跳过、计数自洽） | ✓ |
| 4.2-27 | 4.2 坑 8 | SubagentStop 大多不代表小助手做完了（170 次里 122 次紧跟 Stop），只能当「总结已生成」的提示 | SessionEngine.`processInbox`（只记 `summaryHintAt` + `metaRefreshHint`，不动小助手状态） | StateRuleTests › k2_subagentStopIsOnlyASummaryHint（SubagentStop 只让下一次 poll 立刻重读桌面元数据；不改变主线程的工具 / 阶段） | ✓ |
| 4.2-28 | 4.2 坑 9 | PreCompact / PostCompact 在 Claude 的日志里从没出现过（只在 Codex 日志里见过）→ 压缩状态和「非权限类等待」只能用合成 fixture 测（QA 时这台机器上出现了 3 次真实的自动压缩，据此修了一处，见 L-003） | ActivityResolver `busyActivity`；SessionEngine.`processInbox` | ActivityResolverTests › compactingWhenPreCompactHasNoPostCompact；EngineScenarioTests › compactionThroughHooks（合成 fixture）；StateRuleTests › o1_compactionEndsWhenTheHooksSayItEnded、o2_boundaryHookSlackIsFiveSeconds（用这台机器上 3 次真实自动压缩的时序：PreCompact → 88–104 秒 → SessionStart(compact) → PostCompact → compact_boundary） | ✓ |
| 4.2-29 | 4.2 hook 在不在工作 | 当前会话有 `ts ≥ startedAt − 5s` 的事件 → 正常 | SessionEngine.`hookActive`（另有 15 秒掉线判据，DESIGN.md §13 已补记） | EnginePresenceTests › hookActiveMeansAnEventNoOlderThanStartedAtMinus5Seconds（−700 s → false；startedAt − 4 s → true） | ✓ |
| 4.2-30 | 4.2 hook 掉线 | 用户卸掉 ccmon 后，自动退回用会话记录判断工具，不能崩 | SessionEngine.`buildSignals`；`hookActive` 的 15 s 掉线判据 | EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript；EngineScenarioTests › ifCcmonIsUninstalledMidSessionToolsFallBackToTheTranscript、aBusyHookSessionWithAQuietTranscriptStaysOnHooks | ✓ |
| 4.2-31 | 4.2 诊断页 | 只读地看一眼 settings.json 里有没有注册 hook.sh | SessionEngine.`detectHookInSettings`（`FileIO.readAll`，只读）；`diagnostics` | EnginePresenceTests › diagnosticsReportSourcesAndPerSessionHookState（已注册 = true）；EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript（未注册 = false，「hook: 没检测到」） | ✓ |

---

## 4.3 会话记录 `~/.claude/projects/<编码后的cwd>/<sessionId>.jsonl`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.3-01 | 4.3 找文件 | 用 sessionId 遍历项目子目录去找，不自己拼目录名 | Core/Ingest/TranscriptReader.swift `TranscriptLocator.find` | T-Core/TranscriptTests › locatorFindsTheFileByGlobbingProjectDirectories（别的项目目录里找到；未知 sid → nil；`../x` → nil） | ✓ |
| 4.3-02 | 4.3 找文件 | 目录名以 `-` 开头，shell 通配要写 `./*/` 或加 `--` | 不经过 shell（opendir / readdir），不存在通配问题；`TranscriptLocator.find` 逐个子目录看有没有 `<sessionId>.jsonl` | SpecTraceCoreTests › transcriptLocatorHandlesDirectoryNamesStartingWithADash（`projects/-Users-USER-Desktop-proj` 和 `--weird-dir` 两个以 - 开头的目录里找到会话记录）；所有引擎测试的假树都用 `-fake-project` 目录 | ✓ |
| 4.3-03 | 4.3 文件很大 | 最大 44.2 MB、单行最长 1.53 MB，只能流式读取 | Core/Ingest/JSONLTailer.swift（`poll` / `consume`） | TokenLedgerTests › aBigFileIsScannedFast（44 MB < 2 s）；TranscriptTests › bootstrapReadsOnlyTheTailWindowOfABigFile | ✓ |
| 4.3-04 | 4.3 文件很大 | 用 `pread` 每次最多读 1 MiB，用 `memchr` 找换行 | `JSONLTailer.Config.chunkBytes = 1 << 20`；`poll`；`consume` | SpecTraceCoreTests › tailerDefaultsAndLinesAcrossTheMiBBoundary（默认配置 `chunkBytes == 1 MiB`、`maxLineBytes == 4 MiB`；一条 2,000,000 字节的行跨过 1 MiB / 2 MiB 两个块边界、另一条恰好在块边界结束，全部完整交付，`bytesRead` 等于文件大小）；JSONLTailerTests › linesStraddlingChunkBoundaries、multiByteCharactersAcrossChunks（小块） | ✓ |
| 4.3-05 | 4.3 文件很大 | 只处理完整的行，剩下的半行留到下次再拼 | `pending` / `committedOffset`（`consume`） | JSONLTailerTests › halfLineIsHeldUntilCompleted；TokenLedgerTests › partialLineIsCountedOnlyOnceItIsComplete；FuzzTailerTests › tailerHalfLinesAndBlankLines、tailerIncrementalAppendsEqualOneShot（随机分段追加：每次只交付完整的行） | ✓ |
| 4.3-06 | 4.3 文件很大 | 单行超过 4 MiB 就丢掉，一直跳到下一个 `\n` | `maxLineBytes = 4 << 20`；`consume` | JSONLTailerTests › oversizeLineIsDroppedAndTheNextLineSurvives（5 MiB）、oversizeLineSplitAcrossPollsIsSkippedUntilNewline、exactlyAtTheLimitIsKept（恰好 4 MiB 保留）；FuzzTailerTests › tailerOversizeLineBoundaries（1.5 MB 保留、恰好 4 MiB 保留、4 MiB + 1 丢掉、16 MiB 丢掉；后面的行都读得到；没有换行的半截超长行不交付） | ✓ |
| 4.3-07 | 4.3 文件很大 | 热路径上绝不整文件读取 | TranscriptReader.`bootstrap` 尾部窗口 512 KiB；hook 尾窗 256 KiB；`FileIO.readAll` 只用于小文件 | TranscriptTests › bootstrapReadsOnlyTheTailWindowOfABigFile（400 KB 文件、8 KiB 窗口，`linesSeen < 100`） | ✓ |
| 4.3-08 | 4.3 条目·assistant | 每行一个 content block（thinking / text / tool_use{id,name,input}）+ `message.id/model/usage/stop_reason` + `isAbortedMidStream/isApiErrorMessage/isSidechain/timestamp` | Core/Ingest/TranscriptLine.swift `parse` | TranscriptTests › titlesAndModelAndContext、toolUseIsOpenUntilItsResultArrives、syntheticApiErrorAssistantIsRecognized、abortedMidStreamAssistantIsAnInterrupt、sidechainLinesBelongToOthersInTheMainFile | ✓ |
| 4.3-09 | 4.3 条目·assistant | `stop_reason`：tool_use / end_turn / null（null 表示被打断） | TranscriptFacts.`apply`（end_turn → `endTurnAt`）；null 只有带 `isAbortedMidStream` 才算打断 | TranscriptTests › abortedMidStreamAssistantIsAnInterrupt（null + aborted = 打断；null 但没有 aborted = 不算） | 偏离（DESIGN.md §4 末段「子代理会话记录是按 block 实时写的，中间行 stop_reason 全是 null」；§13「数据层 / 状态机的偏离」：stop_reason 为 null 不一律当作被打断） |
| 4.3-10 | 4.3 条目·user | content 是字符串 = 用户输入，**绝不能显示** | `TranscriptLine.isPrompt` 只是布尔；TranscriptFacts 里没有任何文本字段 | TranscriptTests › promptsAreRecordedButNeverTheirText（`String(describing: facts)` 里找不到 prompt 文字） | ✓ |
| 4.3-11 | 4.3 条目·user | content 是数组：`tool_result{tool_use_id,is_error}`、text 等 | `parse` | TranscriptTests › toolUseIsOpenUntilItsResultArrives（tool_result 关闭对应 tool_use）；is_error 被解析但没人使用 | ✓ |
| 4.3-12 | 4.3 条目·user | `isMeta` 为真的行直接跳过 | TranscriptFacts.`apply` | TranscriptTests › metaUserLinesAreSkipped | ✓ |
| 4.3-13 | 4.3 条目·user | 文本以 `[Request interrupted by user` 开头 = 被用户打断 | `interruptPrefix`；`parse` | TranscriptTests › userInterruptTextIsDetectedInBothShapes（数组 text、字符串、`… for tool use]` 三种形状；打断行不算 prompt） | ✓ |
| 4.3-14 | 4.3 条目·system | `stop_hook_summary` = 一轮结束 | `apply` | TranscriptTests › stopHookSummaryEndTurnAndTurnDuration（解析）；在引擎里当轮次边界用，见 5.2-14 | ✓ |
| 4.3-15 | 4.3 条目·system | `api_error` 带 `retryAttempt` / `maxRetries` / `retryInMs` | `parse`；`apply` | TranscriptTests › apiErrorIsRecordedWithRetryInfo（3 / 10 / 2500） | ✓ |
| 4.3-16 | 4.3 条目·system | `compact_boundary` = 上下文压缩 | `apply`；ActivityResolver `busyActivity`（hook 已经说压缩结束了就不再靠它显示，见 5.4-13） | TranscriptTests › stopHookSummaryEndTurnAndTurnDuration（解析）；ActivityResolverTests › compactingFromTranscriptBoundary | ✓ |
| 4.3-17 | 4.3 条目·system | `turn_duration` 只在终端会话里有 | `parse`；`apply`；SessionEngine.`complete` 用它修正「用时」 | SpecTraceCoreTests › turnDurationFromTheTranscriptCorrectsTheShownTurnLength（turn_duration 4012 ms → 「本轮用时」4.012 秒；对照：没有 turn_duration 时是观察到的 ≈ 8 秒）；TranscriptTests › stopHookSummaryEndTurnAndTurnDuration（解析） | ✓ |
| 4.3-18 | 4.3 条目 | `cost-state` 进程退出时写入 | 忽略（未知 type → `.other`，不参与任何事实，也不计入 token）；用量表的「后台调用补差」没移植（见 4.3-33） | SpecTraceCoreTests › costStateLinesAreIgnored（带着 usage / assistant 字样的 cost-state 行能通过字节预过滤，但既不计入 token、也不改变任何事实） | ✓ |
| 4.3-19 | 4.3 元数据行 | 没有 timestamp 的元数据行（last-prompt / custom-title / ai-title / agent-name / atis-latch / mode / permission-mode…）判断状态时跳过；标题取 custom-title / ai-title（custom 优先） | TranscriptFacts.`apply`（assistant / user / system 无 ts 直接 return；custom / ai / permissionMode 分支） | TranscriptTests › titlesAndModelAndContext；EnginePresenceTests › titlePrecedenceChain（custom 胜 ai） | ✓ |
| 4.3-20 | 4.3 元数据行 | 另有 `<sid>/custom-title.json`，内容 `{customTitle}` | SessionEngine.`refreshCustomTitleFile` | EnginePresenceTests › customTitleJsonInTheSessionDirectoryIsUsed | ✓ |
| 4.3-21 | 4.3 写入延迟 | 主线程整条消息写完才落盘，最多延迟约 33 s → 会话记录只作「当前工具」的兜底 | 设计：hook 优先，`buildSignals` hook 不工作才用会话记录 | EngineScenarioTests › withoutHooksToolsComeFromDanglingToolUsesInTheTranscript（33 s 是观测值，没有断言） | ✓ |
| 4.3-22 | 4.3 用途 | 会话记录用来：算 token、取标题、发现 api_error 和被打断、没有 hook 时判断工具 | TokenLedger；SessionEngine.`title` / `classify` / `buildSignals` | 分别见 4.3-28…39、4.4-09、5.4-15、5.4-22、4.2-30 | ✓ |
| 4.3-23 | 4.3 子代理 | 文件在 `<sid>/subagents/agent-<hex>.jsonl`，按 block 实时写；旁边 `.meta.json` | Core/Ingest/SubagentReader.swift `discover`；`helperDirectories`（另含 `workflows/wf_*/`） | HelperAttributionTests › workflowSubagentsInNestedDirectoriesAreDiscovered；HelperAttributionEngineTests 各用例（写 agent-*.jsonl + .meta.json） | ✓ |
| 4.3-24 | 4.3 子代理 | meta 里有 `agentType`、`description`、`toolUseId`、`spawnDepth`、`requestShape`（background / foreground） | `loadMeta`；`isForeground`（缺省当前台） | HelperAttributionEngineTests 里 `writeSubagentMeta` 按真实格式写全部五个字段：断言 description、agentType（HelperAttributionTests › workflowSubagentsInNestedDirectoriesAreDiscovered）、foreground / background（HelperAttributionTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity、idleMainSessionsBackgroundHelperEventsGoToTheHelper）；toolUseId / spawnDepth 只解析进 `SubagentReader.Meta`，没有任何消费者、没有可观察的行为 | ✓ |
| 4.3-25 | 4.3 子代理 | 子代理当前的工具 = 它最后一个还没有结果的 tool_use | `snapshots`（`openToolUses.last`） | HelperAttributionTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity（currentTool = Bash）；HelperAttributionTests › helperIsDoneWhenLastAssistantIsEndTurnWithNoOpenTool（结束后 nil） | ✓ |
| 4.3-26 | 4.3 子代理 | 最后一条 assistant 是 end_turn 且没有未完成的工具 = 已完成 | `isDone` | HelperAttributionTests › helperIsDoneWhenLastAssistantIsEndTurnWithNoOpenTool | ✓ |
| 4.3-27 | 4.3 子代理 | 最近 90 秒内有写入且还没完成 = 活跃 | `activeWindow = 90`；`isActive`；`snapshots` | HelperAttributionTests › helperStopsBeingActiveAfter90SecondsWithoutWrites（89 s 仍活跃、91 s 消失） | ✓ |
| 4.3-28 | 4.3 token·parse_line() | 取 usage：assistant + `message.id` + 合法 timestamp + 非 `<synthetic>` + usage 非空；`cache_creation` 没有细分或对不上总数时全当 5m | Core/Ingest/TokenLedger.swift `handle`；TranscriptLine.swift | T-Core/TokenLedgerTests › sumsInputOutputCacheWriteAndCacheRead、syntheticAndIncompleteLinesAreIgnored、cacheCreationSplitFollowsTheMeterRule；StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree（QA/tools/token_crosscheck.py 在假 home 树上：独立实现 == 用量表 parse_line == dump == 手算期望值）；FuzzRegressionTests › c004_hugeUsageNumbersDoNotOverflow。判据用顶层 `type == "assistant"`，用量表用 `message.role`：真实数据里 5372 行带 usage 的行两个判据 0 行不一致（QA/issues-logic.md N-1） | ✓ |
| 4.3-29 | 4.3 token·update() | 按字节偏移增量读取 | JSONLTailer `offset`；TokenLedger.`scan` | TokenLedgerTests › dedupeAlsoWorksAcrossPollsAndFiles（增量追加同一条消息的后续行） | ✓ |
| 4.3-30 | 4.3 token·update() | 文件变短就从头读 | JSONLTailer.`poll`；TokenLedger.`resetStats` | TokenLedgerTests › truncatedFileIsRescannedFromTheStart（300 → 7） | ✓ |
| 4.3-31 | 4.3 token·update() | 只处理到最后一个 `\n` | tailer 的 `pending` | TokenLedgerTests › partialLineIsCountedOnlyOnceItIsComplete | ✓ |
| 4.3-32 | 4.3 token·update() | 按 `message.id` 去重，每个字段取最大值 | TokenLedger.`handle` | TokenLedgerTests › sameMessageIdIsCountedOnceWithTheMaximumOfEachField（cache_read 变小仍取最大）、dedupeAlsoWorksAcrossPollsAndFiles（跨文件） | ✓ |
| 4.3-33 | 4.3 token | 「把用量表里的 Python 算法移植成 Swift」——用量表还有 cost-state 的「后台调用补差」（`read_cost_state` / `background_recs`），没移植 | TokenLedger 头注释明说「有意的」；Core/README.md「我做的小决定 · token」 | SpecTraceCoreTests › costStateLinesAreIgnored；StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree（独立实现 == 用量表 parse_line == dump == 手算期望值）；真实数据核对：QA/issues-logic.md 第 4 节（4 个活会话 + 1 个带 prior 的桌面会话，四项和消息条数逐位一致） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：不移植用量表的 cost-state「后台调用补差」） |
| 4.3-34 | 4.3 token·read_title() | 标题：custom-title 优先于 ai-title | TranscriptFacts.`customTitle` / `aiTitle`；SessionEngine.`title` | TranscriptTests › titlesAndModelAndContext；EnginePresenceTests › titlePrecedenceChain | ✓ |
| 4.3-35 | 4.3 token·read_app_windows() / window_of() | 窗口 ↔ CLI 会话（当前 + prior）的映射 | DesktopMetaReader.`find` / `allCliSessionIds`（Core/Ingest/DesktopMetaReader.swift）；SessionEngine.`updateTokenGroup` | EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents | ✓ |
| 4.3-36 | 4.3 token | 读取时先用字节预过滤（先看有没有 `"usage"` 和 `"assistant"`），命中了再解码 | TokenLedger.`handle`（`memmem`） | SpecTraceCoreTests › theByteFilterRunsBeforeAnyDecoding（把 `"usage"` / `"assistant"` 写成 JSON 转义拼写的行：解码器认得、原始字节里却找不到这两个词，结果不计入——只有预过滤挡在解码前才会这样；两行原样的照常计入）；TokenLedgerTests › aBigFileIsScannedFast（44 MB < 2 秒） | ✓ |
| 4.3-37 | 4.3 token | 本会话总量 = 输入 + 输出 + 缓存写 + 缓存读 | Core/Model/BuddySnapshot.swift `TokenBreakdown.total` | TokenLedgerTests › sumsInputOutputCacheWriteAndCacheRead（`t.total == 11 + 22 + 303 + 4004`） | ✓ |
| 4.3-38 | 4.3 token | 子代理的 token 也要算进来 | SessionEngine.`updateTokenGroup`（helperPaths） | TokenLedgerTests › subagentTranscriptsAreAddedToTheBuddysTotal；EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents（+40） | ✓ |
| 4.3-39 | 4.3 token | 按文件把 `{dev, ino, offset, totals}` 缓存到 `ledger.json` | TokenLedger.`writeLedger`、`restore` | TokenLedgerTests › ledgerFileRestoresProgressAndDedupesAcrossTheBoundary、groupsWithPriorSessionsAreRescannedInsteadOfUsingTheLedger、persistenceFailureDegradesToMemoryOnly；FuzzRegressionTests › c005_ledgerWithAbsurdCountersIsSanitized（账本里的天文数字 / 负数恢复后不溢出） | ✓ |
| 4.3-40 | 4.3 token | 最多 30 秒写一次 | `persistInterval = 30`；`writeLedger` | SpecTraceCoreTests › theLedgerFileIsWrittenAtMostOnceEvery30Seconds（虚拟时钟：统计完立即写一次；+10 秒、+29.9 秒不写，+30.1 秒才写） | ✓ |
| 4.3-41 | 4.3 token | 退出时也写一次 | TokenLedger.`flush`；SessionEngine.`shutdown`；App/AppDelegate.swift `applicationWillTerminate` → SessionStore.`stop` | SpecTraceCoreTests › stoppingTheStoreWritesTheLedgerOneLastTime（SessionStore + 冻结的虚拟时钟：第二条消息落在 30 秒节流窗口里，`ledger.json` 仍是旧的 1000；`store.stop()` 之后变成 1500）；TokenLedgerTests › ledgerFileRestoresProgressAndDedupesAcrossTheBoundary（flush 本身）；DESIGN.md 第 9.1 节（真实 App 退出后落盘的手工实测） | ✓ |
| 4.3-42 | 4.3 token | 第一次扫大文件放到后台低优先级 | TokenLedger.`init` ：队列 `qos: .background` | SpecTraceCoreTests › theDefaultScanQueueRunsAtBackgroundQoS（默认队列：从最低优先级的线程提交，扫描回调里 `qos_class_self() == QOS_CLASS_BACKGROUND`）、theLedgerScansOneFileAtATimeOnOneSerialQueue（源码断言默认队列是 `.background`） | ✓ |
| 4.3-43 | 4.3 token | 一次只扫一个文件 | `pass` ：串行队列上逐个 `scan` | SpecTraceCoreTests › theLedgerScansOneFileAtATimeOnOneSerialQueue（结构性要求，用源码断言：一条串行队列；`pass()` 里 `for f in list { scan(f) }` 只有一处 scan；没有 `.concurrent` / `concurrentPerform` / `DispatchQueue.global` / `OperationQueue` / `Task` / `Thread` / `DispatchGroup`） | ✓ |

---

## 4.4 桌面 App 会话元数据 `…/claude-code-sessions/<acct>/<org>/local_<uuid>.json`

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.4-01 | 4.4 路径 | `~/Library/Application Support/Claude/claude-code-sessions/<acct>/<org>/local_<uuid>.json` | Core/Paths.swift `desktopSessionsDir`；DesktopMetaReader.`refresh` | FakeTree.writeMeta（`acct/org` 两级目录）被下班工位 / 标题 / blocked 等一大批测试使用 | ✓ |
| 4.4-02 | 4.4 字段 | `sessionId`（local_…）、`cliSessionId`、`priorCliSessionIds[]` | DesktopMetaReader.`parse` | IdentityTests › desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing；EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents | ✓ |
| 4.4-03 | 4.4 字段 | `cwd`、`originCwd`、`title`、`titleSource`、`model`、`effort`、`permissionMode`、`isArchived` | `parse` | SpecTraceCoreTests › desktopMetadataParsesEveryListedField（cwd / originCwd / title / titleSource / model / effort / permissionMode / isArchived 逐个断言）；EnginePresenceTests › titlePrecedenceChain、snapshotCarriesTheDescriptiveFields | ✓ |
| 4.4-04 | 4.4 字段 | `createdAt`、`lastActivityAt`、`lastFocusedAt`、`completedTurns`、`lastAssistantUuid` | `parse` | SpecTraceCoreTests › desktopMetadataParsesEveryListedField（createdAt / lastActivityAt / lastFocusedAt / completedTurns / lastAssistantUuid 逐个断言）；EnginePresenceTests › dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted（lastActivityAt）、focusingTheSessionInTheDesktopAppClearsUnread（lastFocusedAt） | ✓ |
| 4.4-05 | 4.4 字段 | `postTurnSummary{status_category: completed/blocked, needs_action, status_detail}`、`postTurnSummaryFor` | `parse` | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（category、status_detail、postTurnSummaryFor）；SpecTraceCoreTests › desktopMetadataParsesEveryListedField（status_category / needs_action / status_detail / postTurnSummaryFor 逐个断言） | ✓ |
| 4.4-06 | 4.4 字段 | 没有表示「运行中」的字段 | 代码不依赖这种字段：桌面会话的阶段只来自登记表（元数据只用于标题 / 下班工位 / blocked / lastFocusedAt / prior 会话） | SpecTraceCoreTests › desktopMetadataCannotMakeAnIdleSessionBusy（元数据里多出 `status: running` / `isRunning: true` 这类键：登记表 idle 的会话仍是 idle，2 秒内不变）；所有桌面会话测试的元数据夹具都没有这样的字段，引擎照常判定 | ✓ |
| 4.4-07 | 4.4 blocked | `status_category == "blocked"` 并且 `postTurnSummaryFor == lastAssistantUuid` | DesktopMeta.`isBlocked` / `summaryIsCurrent` | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn、aSummaryForAnOlderAssistantMessageIsNotBlocked、aBlockedSummaryAlreadyThereAtLaunchShowsBlocked；StateRuleTests › f3_blockedOverlayFollowsTheDesktopSummary（completed 不亮；blocked 晚落盘也亮、只发一次事件、保持一小时、下一轮清掉） | ✓ |
| 4.4-08 | 4.4 blocked | `status_detail` 是英文，只在悬停卡片里显示 | 快照 `statusDetail`（SessionEngine）；表现层 / 应用层里唯一读它的是 Stage/HoverCard.swift（隐私模式不显示） | SpecTraceStageTests › theEnglishStatusDetailIsOnlyShownInTheHoverCard（悬停卡片里有；隐私模式没有；`PlateCopy` 的动作 / 状态候选 / 状态行和办公室一帧里的全部文字都没有；源码里读 `statusDetail` 的文件只有 HoverCard.swift）；EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（数据层给出 statusDetail） | ✓ |
| 4.4-09 | 4.4 标题优先级 | 登记表 `name` → 桌面 `title` → custom-title → ai-title → cwd 文件夹名 →「会话 <sid 前 8 位>」 | SessionEngine.`title` | EnginePresenceTests › titlePrecedenceChain（cwd → ai → custom → 桌面 title → 登记表 name 逐级）；EnginePresenceTests › titleFallsBackToSessionIdPrefixWhenNothingElseExists（「会话 abcdef12」）；StateRuleChainTests › py2_dumpVsRegistryScriptOnAFakeTree（QA/tools/dump_vs_registry.py 核对标题链，输出里没有标题文字） | ✓ |

---

## 4.5 身份

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.5-01 | 4.5 buddy key | 桌面会话 = `"d:" + hostSessionId` | Core/Fusion/IdentityResolver.swift `resolve` | T-Core/IdentityTests › desktopKeyIsDPrefixPlusHostSessionId | ✓ |
| 4.5-02 | 4.5 buddy key | 其他会话 = `"t:" + 第一次见到的 sessionId` | `resolve` | IdentityTests › terminalKeyIsTPrefixPlusFirstSeenSessionId、terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess（/clear 后 key 仍是 `t:before-clear`）；StateRuleTests › j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume | ✓ |
| 4.5-03 | 4.5 别名 | `host:<local_…>`、`sid:<uuid>`、`proc:<pid>@<启动时间>` | `resolve`、`attach` | IdentityTests › desktopKeyIsDPrefixPlusHostSessionId（三种别名都在，`proc:1@` 前缀） | ✓ |
| 4.5-04 | 4.5 归属顺序 | ① host 别名 | `resolve` | IdentityTests › hostAliasWinsEvenWhenPidAndSessionIdChange（kind == .host） | ✓ |
| 4.5-05 | 4.5 归属顺序 | ② 进程别名（同一进程 `/clear`） | `resolve` | IdentityTests › terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess（kind == .process）；EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles；StateRuleTests › j1_desktopClearInTheSameProcessKeepsTheBuddy（桌面 /clear：key / 工位 / 盐不变） | ✓ |
| 4.5-06 | 4.5 归属顺序 | （hook 里的 SessionStart `source=clear` 可以佐证进程别名） | 未实现这条佐证（引擎只用 `source=compact`）：进程别名 `proc:<pid>@<启动时间>` 靠登记表里 pid + 启动时间不变就足够认出同一个进程 | IdentityTests › terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess（没有 hook 也认得同一个进程）；StateRuleTests › j1_desktopClearInTheSameProcessKeepsTheBuddy | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：不用 hook 的 SessionStart source=clear 佐证进程别名） |
| 4.5-07 | 4.5 归属顺序 | ③ sid 别名（在新进程里 resume） | `resolve` | IdentityTests › terminalResumeInANewProcessKeepsTheSameBuddyViaSessionAlias；EnginePresenceTests › terminalResumeInANewProcessGivesTheSameBuddyBack；StateRuleTests › j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume | ✓ |
| 4.5-08 | 4.5 归属顺序 | ④ 桌面元数据里的 `cliSessionId` / `priorCliSessionIds` | `resolve` | IdentityTests › desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing（current 与 prior 两种都反查得到）、aSessionKnownOnlyToDesktopMetadataBecomesADesktopIdentity；StateRuleTests › j3_desktopResumeIsRecognizedThroughTheMetadataCliSessionIds | ✓ |
| 4.5-09 | 4.5 归属顺序 | ⑤ 以上都不匹配就是新 buddy | `resolve` | IdentityTests › pidReuseWithADifferentStartTimeIsANewBuddy、withoutProcStartNoProcessAliasIsUsed | ✓ |
| 4.5-10 | 4.5 持久化 | 别名、工位编号、外观种子盐存到 `~/Library/Application Support/BuddyOffice/identities.json` | `saveIfNeeded`；`load`；Paths.`identitiesFile` | IdentityTests › persistenceRoundTripKeepsAliasesSeatAndSalt；EnginePresenceTests › identitiesAndAppearanceSurviveARestart | ✓ |
| 4.5-11 | 4.5 持久化 | 保留 7 天 | `retention = 7 * 86400`；`load` | IdentityTests › identitiesAreForgottenAfterSevenDays（6 天还在、7.1 天忘掉） | ✓ |
| 4.5-12 | 4.5 持久化 | 同一个会话关掉再打开，回来的还是同一个人、坐回同一个工位 | `assignSeat`；SessionEngine.`reconcile`（away → live 保留 seat / salt） | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat、terminalResumeInANewProcessGivesTheSameBuddyBack（seat / salt 相同）；IdentityTests › seatsAreTheSmallestFreeNumberAndReturningBuddiesGetTheirOwnSeatBack | ✓ |
| 4.5-13 | 4.5 token 合并 | 桌面会话把 `cliSessionId` 和 `priorCliSessionIds` 对应的会话记录加在一起 | SessionEngine.`updateTokenGroup` | EnginePresenceTests › desktopTokensMergeThePriorCliSessionsAndSubagents（100 + 200 + 300 + 40，重叠的 m2 只算一次）；StateRuleTests › j1_desktopClearInTheSameProcessKeepsTheBuddy（token = 1000 + 7） | ✓ |
| 4.5-14 | 4.5 token 合并 | 终端会话只算当前的 sessionId | `updateTokenGroup` | EnginePresenceTests › aTerminalSessionOnlyCountsItsCurrentSessionId；EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles（/clear 后只算新的 7） | ✓ |

---

## 4.6 安全红线

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.6-01 | 4.6 | 绝不打开 `~/.claude/sessions/*.key` | 同 4.1-03（FileIO 保险 + 只碰匹配名的文件） | RegistryTests › keyFilesAreNeverOpened（`FileAccessTests` 串行套件）、safetyNetRefusesKeyAndSocketPaths；FuzzRegressionTests › c007_symlinkToKeyFileIsRefused（符号链接指向 .key 也拒绝） | ✓ |
| 4.6-02 | 4.6 | 绝不连接 `/tmp/cc-socks/*.sock` | FileIO 拒 `.sock`、路径含 `/cc-socks/`；全部源码里没有 socket / connect / Network 相关调用（grep 过） | RegistryTests › safetyNetRefusesKeyAndSocketPaths（`open` 返回 −1；`forbiddenHits` +3）；FuzzRegressionTests › c007_caseVariantsNulAndDotDotAreForbidden（`.Sock`、`CC-SOCKS`、NUL、`../`）；「没有连接代码」：SourceAuditCoreTests › noNetworkNoCredentialsNoSubprocesses（数据层 / 表现层 / 命令行工具源码里没有 `socket(` / `NWConnection` / `URLSession`）、SourceAuditTests › noNetworkAndNoCredentialAPIs（应用层） | ✓ |
| 4.6-03 | 4.6 | 不读任何凭据或钥匙串 | 源码里没有 Keychain / SecItem / 凭据文件读取（grep 过）；`detectHookInSettings` 会把整份 settings.json 解析进内存但只取 `hooks`、不保留不记日志（4.2 允许这一处） | SourceAuditCoreTests › noNetworkNoCredentialsNoSubprocesses（数据层 / 画布 / 美术 / 表现层 / 命令行工具的源码里没有 `SecItem` / `Keychain` / `import Security`）、fileReadsGoThroughFileIOWithAShortReviewedAllowlist（读文件只有 FileIO 一个入口）；SourceAuditTests › noNetworkAndNoCredentialAPIs、noPathsUnderTheClaudeDirectoryOrSecretFiles（应用层同） | ✓ |
| 4.6-04 | 4.6 | 不改 ccmon 的文件 | 只读打开；写入点只有 4.6-05 列的几处 | RegistryTests › engineNeverWritesUnderClaudeDir；SpecTraceCoreTests › theEngineOnlyWritesInsideItsOwnSupportFolder（含 ccmon 的 .claude/monitor/hook.sh：一个字节没变） | ✓ |
| 4.6-05 | 4.6 | 不改用量表、Claude.app 的任何文件 | 全部写入点只有：identities.json、ledger.json（Application Support/BuddyOffice）、开机启动 LaunchAgent plist、`~/Library/Logs/BuddyOffice/debug.log`（开发开关下）、buddyctl 的输出目录 | SpecTraceCoreTests › theEngineOnlyWritesInsideItsOwnSupportFolder（假 home 里放上桌面 App 的元数据、用量表、Claude.app 的假文件，完整跑一遍引擎：这些文件和 ~/.claude 下没被测试自己动过的文件一个字节没变、没有多出任何文件，只有 Application Support/BuddyOffice 里有 identities.json / ledger.json）、writeAPIsAreConfinedToTheReviewedFiles（`FileIO.writeAtomically` 只有 IdentityResolver / TokenLedger 两处用，路径在 Application Support/BuddyOffice 下）；SourceAuditTests › noPathsUnderTheClaudeDirectoryOrSecretFiles（应用层源码里没有 `.claude` / `.monitor` / `token-meter` / `用量表` 路径） | ✓ |
| 4.6-06 | 4.6 | App 运行时绝不写 `~/.claude` 下的任何东西 | 同上；数据层只写 `~/Library/Application Support/BuddyOffice/`（IdentityResolver.`saveIfNeeded`、TokenLedger.`writeLedger`） | RegistryTests › engineNeverWritesUnderClaudeDir（引擎层）；SpecTraceCoreTests › theEngineOnlyWritesInsideItsOwnSupportFolder、writeAPIsAreConfinedToTheReviewedFiles；应用层：SourceAuditTests › noPathsUnderTheClaudeDirectoryOrSecretFiles（源码里没有 `.claude` 路径）、DebugLogTests › aSymlinkAtTheLogPathIsNeverFollowed（日志只写自己的 ~/Library/Logs/BuddyOffice） | ✓ |
| 4.6-07 | 4.6 | settings.json 只改一处：只有安装脚本可以改，且只加一条 SessionStart hook（7.4 节） | scripts/hook-merge.py `install` / `GROUP`（matcher `startup` 与 `resume` 用竖线连接，命令 `pgrep -xq BuddyOffice …; exit 0`，timeout 5）；Sources 里没有任何写 settings.json 的代码（FakeTree 只往测试用的假 home 写） | T-Py › test_install_appends_one_group_and_keeps_everything_else、test_install_creates_file_when_missing、test_install_then_uninstall_is_byte_identical_and_keeps_trailing_newline_state（Python 脚本的测试，要单独用 `python3 Tests/hook_merge_test.py` 跑） | ✓ |
| 4.6-08 | 4.6 | 改之前先备份 | hook-merge.py `backup`（`settings.json.bak-YYYYmmdd-HHMMSS`） | T-Py › test_install_appends_one_group_and_keeps_everything_else（备份数 == 1）、test_install_twice_is_idempotent（第二次什么都不做，也没有第二份备份）、test_refuses_invalid_json_and_leaves_no_trace | ✓ |
| 4.6-09 | 4.6 | 用户已经同意这一处改动 | 授权只覆盖 4.6-07 那一处（追加一个 SessionStart hook 组）：源码里没有任何写 settings.json 的代码，只有安装脚本 scripts/hook-merge.py 会改 | 对应的约束由 4.6-07 / 4.6-08 的测试钉住（Tests/hook_merge_test.py：只追加一个组、其余一字不动、先备份）；SourceAuditTests › noPathsUnderTheClaudeDirectoryOrSecretFiles（应用层源码里没有 `.claude` 路径） | ✓ |
| 4.6-10 | 4.6 | 不显示对话内容：绝不显示用户输入的 prompt | UserPromptSubmit 的 `extra` 解析即丢（LineSanitizer）；TranscriptFacts 不存任何文本；AskUserQuestion 的 detail 丢弃 | HookLogTests › userPromptIsDroppedAtParseTime、askUserQuestionDetailIsNeverKept；TranscriptTests › promptsAreRecordedButNeverTheirText；T-Stage/PlateCopyTests › privacyModeNeverLeaksDetails（隐私模式下文件名、命令、搜索词、域名一个都不出现） | ✓ |
| 4.6-11 | 4.6 | 调试日志只写元数据（状态、工具名、时间），不写对话内容 | App/DebugTools.swift：调用点写的是窗口 frame / 命中测试 / 开关状态 / 计时；`--test-jump` 的日志只写标题的字数（`DebugTools.titleForLog`）；默认路径 `~/Library/Logs/BuddyOffice/debug.log`（0600，超过 1 MB 轮转），只在开发开关下才写（A-015） | DebugLogTests › sessionTitlesNeverGoIntoTheLog、noDebugLogCallInterpolatesASessionTitle（源码审计：`DebugTools.log(` 的实参里没有 `.title`）、onlyDevelopmentFlagsTurnLoggingOn、noNSLogUsesAnInterpolatedFormatString | ✓ |
| 4.6-12 | 4.6 | 不联网 | 源码里没有 URLSession / Network / socket；Package.swift 没有任何 `.package` 依赖，所有源码只 import 系统框架和自己的四个库；唯一的 `https://` 字面量是演示剧本里的假域名（Stage/DemoScript.swift） | SourceAuditCoreTests › noNetworkNoCredentialsNoSubprocesses；SourceAuditTests › noNetworkAndNoCredentialAPIs、noSubprocessesAndNoThirdPartyImports（应用层只允许系统框架 + 自己的四个库）；SpecTraceCoreTests › thereAreNoThirdPartyDependencies（Package.swift 没有 `.package(`，全部源码的 import 都在白名单里） | ✓ |

---

## 5.1 阶段（phase）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.1-01 | 5.1 基础 | 阶段以登记表的 `status` 为准 | Core/Fusion/ActivityResolver.swift `phase` | T-Core/ActivityResolverTests 里所有 `sig(status)` 用例；ActivityResolverTests › waitingIsNeverOverriddenByHooks；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（16 个固定种子的随机事件流，与按任务书写的独立参考模型逐步对拍：阶段、主线程打开的调用个数与顺序、忙碌 / 等待时的动作） | ✓ |
| 5.1-02 | 5.1 修正 1 | 登记表还是 idle，但有一条比 `statusUpdatedAt` 更新的 UserPromptSubmit → 暂时当作 busy | `phase` | ActivityResolverTests › registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds（提示比 statusUpdatedAt 旧 → 不修正）；EngineScenarioTests › promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds（引擎层：2.9 秒仍 busy、3.1 秒回 idle，只发一次 turnStarted）。实测登记表 busy 比 UserPromptSubmit 早 0.09–0.5 秒，这条路径几乎不触发（Core/README.md「数据源实测结论 · 时序」） | ✓ |
| 5.1-03 | 5.1 修正 1 | …最多 3 秒 | `tempBusyWindow = 3`；`phase` | ActivityResolverTests › registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds（103.4 s 仍 busy、103.6 s 已 idle）；EngineScenarioTests › aPromptThatNeverBecomesBusyExpiresAfter3Seconds（3.2 s 后 idle）；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds | ✓ |
| 5.1-04 | 5.1 修正 2 | 登记表还是 busy，但有一条比 `statusUpdatedAt` 更新的 Stop → 暂时当作 idle | `phase` | ActivityResolverTests › registryBusyButNewerStopIsTemporarilyIdle（Stop 比登记表 busy 旧 → 不修正；Stop 之后又来提示 → 仍 busy）；EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（Stop 先到、登记表 56 ms 后才翻 idle，Stop 一到就是「做完了」）；StateRuleTests › m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle | ✓ |
| 5.1-05 | 5.1（任务书未写） | 登记表没有 / 不认识 status 时改用 hook 推断；修正 1 另要求提示晚于最近的 Stop，修正 2 要求 Stop 不早于最近的提示 | `phase` | ActivityResolverTests › missingRegistryStatusFallsBackToHooks；ActivityResolverTests › registryBusyButNewerStopIsTemporarilyIdle（排队的下一轮）；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds、m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：登记表没有 / 不认识 status 时靠 hook 推断阶段，两个临时修正各多一个条件） |

---

## 5.2 工具追踪（ToolTracker：处理悬空和并行）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.2-01 | 5.2 Pre 到来 | ① 先判断属于主线程还是子代理（见 5.3） | SessionEngine.`processInbox`（`attributionContext` → `attributor.decide` → owner） | T-Core/HelperAttributionTests（整套，见 5.3） | ✓ |
| 5.2-02 | 5.2 Pre 到来 | ② 主线程，且距上一个主线程 Pre **超过 0.25 秒** → 新的一批 | Core/Fusion/ToolTracker.swift `batchGap = 0.25`；`pre`（只看主线程 Pre；用事件时间戳） | ToolTrackerTests › callsWithin250msOfThePreviousPreStayInTheSameBatch（0.2 s 同批、0.3 s 新批）；ToolTrackerTests › parallelCallsInTheSameMillisecondShareABatch；StateRuleTests › a2_batchGapIsExactly250ms（恰好 0.25 s 不算新批、0.251 s 才算并关掉旧批）；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.2-03 | 5.2 Pre 到来 | ②（续）新批次同时把更早批次里还开着的工具全部关掉，原因记为「被取代」 | `closeAll(owner: .main, reason: .superseded)` | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded（`reason == .superseded`）；StateRuleTests › a2_batchGapIsExactly250ms、b6_danglingCallIsSupersededByTheNextBatch（引擎层） | ✓ |
| 5.2-04 | 5.2 Pre 到来 | ②（续）这一步同时解决「没有 PostToolUseFailure」和「权限被拒」两种悬空 | 同上 | ToolTrackerTests › newBatchClosesOlderOpenCallsAsSuperseded（失败）、permissionDeniedDanglingIsClosedByTheNextBatch（被拒，间隔 12 s） | ✓ |
| 5.2-05 | 5.2 Pre 到来 | ③ 把这次调用登记为打开状态 | `pre` | ToolTrackerTests › parallelCallsInTheSameMillisecondShareABatch（`mainOpen.count == 2`） | ✓ |
| 5.2-06 | 5.2 Post 到来 | 按「工具名 + detail 都相同」关掉最早的那个打开调用 | `post` | ToolTrackerTests › parallelCallsInTheSameMillisecondShareABatch（先 Post `/b` 再 `/a`，按内容而不是到达顺序配对）；StateRuleTests › a1_sameMillisecondParallelReadsPairFirstInFirstOut（引擎层） | ✓ |
| 5.2-07 | 5.2 Post 到来 | 没有这样的，就按工具名关 | `post` | ToolTrackerTests › postFallsBackToToolNameThenIgnores（detail 对不上 → 按名字关）；StateRuleTests › a1_sameMillisecondParallelReadsPairFirstInFirstOut、a3_postFallsBackToTheEarliestOpenCallOfTheSameName | ✓ |
| 5.2-08 | 5.2 Post 到来 | 还没有就忽略 | `post` | ToolTrackerTests › postFallsBackToToolNameThenIgnores；ToolTrackerTests › postWithoutPreIsIgnored；StateRuleTests › a3_postFallsBackToTheEarliestOpenCallOfTheSameName（没有可关的 Read → 忽略） | ✓ |
| 5.2-09 | 5.2 Post 到来 | 并行调用按先进先出配对（实测同一毫秒出现过两个 Read） | `firstIndex`（最早的先关） | ToolTrackerTests › identicalParallelCallsCloseFirstInFirstOut（剩下的是 `startedAt == 0.001` 那个） | ✓ |
| 5.2-10 | 5.2 轮次边界 | Stop → 关掉主线程的全部打开调用 | SessionEngine.`processInbox`（`tracker.turnBoundary`） | StateRuleTests › b1_stopEventClosesDanglingMainCalls（引擎层：悬空的 Bash 被 Stop 以 turnBoundary 关掉）；ToolTrackerTests › turnBoundariesCloseAllMainCalls（tracker 单元） | ✓ |
| 5.2-11 | 5.2 轮次边界 | UserPromptSubmit → 同上 | `processInbox` | StateRuleTests › b2_userPromptSubmitClosesDanglingMainCalls；ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-12 | 5.2 轮次边界 | SessionStart → 同上 | `processInbox` | StateRuleTests › b3_sessionStartClosesDanglingMainCalls；ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-13 | 5.2 轮次边界 | 登记表变成 idle → 同上 | SessionEngine.`transition`（`tracker.turnBoundary(at: now)`，按修正后的阶段触发） | StateRuleTests › b4_registryTurningIdleClosesDanglingMainCalls（没有 Stop，光靠登记表翻 idle）；ToolTrackerTests › turnBoundariesCloseAllMainCalls | ✓ |
| 5.2-14 | 5.2 轮次边界 | 会话记录出现 `stop_hook_summary` → 同上 | `update` | StateRuleTests › b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt（会话记录里的 stop_hook_summary 关掉之前开始的调用；比它新的不受影响；登记表仍 busy） | ✓ |
| 5.2-15 | 5.2 轮次边界 | （任务书写「关掉全部」）实现只关「在边界时刻之前或同时开始」的主线程调用，小助手名下的不受影响；另外 SessionEnd 也当边界 | `turnBoundary` | ToolTrackerTests › aBoundaryOlderThanAnOpenCallDoesNotCloseIt、turnBoundariesCloseAllMainCalls（`helperOpen.count == 1`）；StateRuleTests › b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt（第二段：stop_hook_summary 比开着的调用旧 → 不误关）、b9_sessionEndClosesDanglingMainCalls | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：轮次边界只关「边界时刻之前或同时开始」的主线程调用，SessionEnd 也算边界） |
| 5.2-16 | 5.2 兜底 | 登记表是 idle 而某个调用已开超过 30 分钟 → 强制关掉 | `staleAfter = 30 * 60`；`expireStale`；SessionEngine `update`（`registryIdle: record.status == .idle`） | ToolTrackerTests › staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle（29 分钟不关、31 分钟关、busy 时不关）；ToolTrackerTests › helperOwnedRecordsExpireRegardless；StateRuleTests › b7_staleCallIsForceClosedOnlyAfterMoreThan30MinutesWhileRegistryIdle（恰好 30 分钟不关、+1 ms 才关、登记表不是 idle 绝不关）、b8_helperOwnedRecordsExpireAfter30Minutes（引擎层：小助手名下的记录 29 分钟还在、31 分钟被丢）；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |

---

## 5.3 子代理事件的归属（hook 里没有 agent_id）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.3-01 | 5.3 规则 1 | 主会话是 idle → 事件归后台小助手 | Core/Fusion/HelperAttributor.swift `decide`；SessionEngine.`attributionContext`（`effectivePhase(…, now: 事件时间) == .idle`） | T-Core/HelperAttributionTests › rule1MainIdleMeansBackgroundHelper；HelperAttributionTests › idleMainSessionsBackgroundHelperEventsGoToTheHelper；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.3-02 | 5.3 规则 1 | …「没有临时 busy」：5.1 的临时 busy 不算 idle | `attributionContext` 用的是修正后的阶段（含临时 busy） | SpecTraceCoreTests › aTemporaryBusyIsNotIdleForRuleOne（同一个后台小助手、同一条 Pre：主会话真的 idle → 立刻归小助手；登记表 idle 但刚提交了提示（临时 busy）→ 不算 idle，先扣住，400 ms 后比对不上归主线程） | ✓ |
| 5.3-03 | 5.3 规则 2 | 主线程有前台 Agent / Task 正开着，事件比它晚 **0.15 秒以上** → 归小助手 | `foregroundGap = 0.15`；`decide`（按毫秒取整比较，恰好 0.15 算「以上」）；`attributionContext` | HelperAttributionTests › rule2ForegroundAgentOpenAndEventLaterThan150ms（0.05 s → 主线程；恰好 0.15 s、2 s → 小助手）；HelperAttributionTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity（0.4 s）；StateRuleTests › k1_foregroundTaskAttributionBoundaryAt150ms（引擎层：前台 Task（不只是 Agent）：0.149 s 的同批调用归主线程、0.15 s 归小助手；Task 结束后新调用不再算小助手的）；FuzzRegressionTests › c003_attributionSurvivesAbsurdEventTimes | ✓ |
| 5.3-04 | 5.3 规则 3 | 有后台小助手正在活跃 → 先把事件扣住，**最多 400 ms** | `holdLimit = 0.4`；`decide` | HelperAttributionTests › rule3NoMatchHoldsFor400msThenGoesToMain（5.39 s 仍扣住、5.41 s 归主线程）；HelperAttributionTests › unmatchedEventIsHeldFor400msThenAttributedToTheMainThread；StateRuleTests › k3_unmatchedEventIsHeldForExactly400ms（0.39 s 仍扣住、0.41 s 归主线程）；FuzzRegressionTests › c006_attributionHoldIsBoundedEvenWithFutureTimestamps（时间戳在未来的事件 1 s 后不再被扣留，不会卡死 hook 队列；正常事件仍扣 ≤ 0.4 s） | ✓ |
| 5.3-05 | 5.3 规则 3 | 扣住期间拿「工具名 + 第一个输入字段（command / file_path / pattern / url / query / description），按前缀比较，最多 160 字」去比对 | `firstMatch` + `ToolDetail.matches`（TranscriptLine.swift，前缀比较、160 字） | HelperAttributionTests › rule3MatchesHelperTranscriptAndIsAttributedToTheHelper；HelperAttributionTests › truncatedHookDetailMatchesByPrefix（160 字 + `…`）；HelperAttributionTests › rule3HoldEndsEarlyWhenTheTranscriptCatchesUp | ✓ |
| 5.3-06 | 5.3 规则 3 | …和小助手会话记录、**主会话记录**里最近的 tool_use 比对；比对上的归那一方 | `decide`（`helperUses` / `mainUses`）；「最近」= 事件前 90 s 到后 10 s 的窗口（`windowBefore` / `windowAfter`，任务书没给数字） | HelperAttributionTests › rule3MatchesHelperTranscriptAndIsAttributedToTheHelper（两边各配一个）；HelperAttributionTests › busyMainWithBackgroundHelperUsesTranscriptsToTellThemApart；HelperAttributionTests › toolUsesFarInThePastDoNotMatch（−200 s 不算） | ✓ |
| 5.3-07 | 5.3 规则 3 | 比对不上就归主线程（两边都对得上时无法区分，也归主线程——任务书没写，代码注释说明） | `decide` | HelperAttributionTests › rule3NoMatchHoldsFor400msThenGoesToMain；HelperAttributionTests › rule3AmbiguousMatchGoesToMain；HelperAttributionTests › eachToolUseIsClaimedOnlyOnce | ✓ |
| 5.3-08 | 5.3 规则 4 | 其他情况 → 归主线程 | `decide` | HelperAttributionTests › noBackgroundHelperMeansMain | ✓ |
| 5.3-09 | 5.3 说明 | 小助手显示的动作直接取自它自己的会话记录 | SubagentReader.`snapshots`（`currentTool` = 它自己的最后一个未完成 tool_use） | HelperAttributionTests › foregroundAgentHelpersDoNotStealTheMainThreadActivity、idleMainSessionsBackgroundHelperEventsGoToTheHelper（`helpers.first?.currentTool?.name`） | ✓ |
| 5.3-10 | 5.3 说明 | 即使归属判错，也只影响主 buddy，到下一个轮次边界就纠正 | 主线程 Tracker 里被错归属的记录由 `turnBoundary` 关掉（同 5.2-10…14）；小助手显示的动作取自它自己的会话记录（`SubagentReader.snapshots`） | SpecTraceCoreTests › aWronglyAttributedToolIsCorrectedAtTheNextTurnBoundary（小助手的 Bash 被误判给主线程：主线程显示 Bash、小助手自己显示的仍是对的；下一个轮次边界（Stop + 登记表 idle）之后主线程回到「做完了」、没有残留） | ✓ |

---

## 5.4 动作判定（ActivityResolver）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.4-01 | 5.4 总则 | 输入是信号和当前时间，输出只由它们决定，不依赖其他状态 | `public enum ActivityResolver`，全是 static 纯函数（Core/Fusion/ActivityResolver.swift）；无存储属性 | ActivityResolverTests 全部用例都是「构造 SessionSignals + now → 断言」 | ✓ |
| 5.4-02 | 5.4 waiting | `waitingFor` 是 "permission prompt" 或 "sandbox request" → 等批准 | `waitingActivity` | 同 4.1-16、4.1-21；StateRuleTests › l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen（引擎层 sandbox request） | ✓ |
| 5.4-03 | 5.4 waiting | 或者文本里含 `permission` / `allow` → 等批准（文本 = waitingFor；没有它时用比这次等待更新的 Notification 文本） | `waitingActivity` | ActivityResolverTests › unknownWaitingTextIsClassifiedByKeywords（"…permission…"、"Allow this action?"）；ActivityResolverTests › missingWaitingForFallsBackToNotificationText | ✓ |
| 5.4-04 | 5.4 waiting | 等批准的工具取最新一个打开的主线程调用 | `approvalTool`（`openTools.last`） | ActivityResolverTests › permissionPromptIsApprovalWithTheNewestOpenTool（Bash `git push`，不是更早的 Read）；StateRuleTests › l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen（取最新打开的 Bash `git push`）；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-05 | 5.4 waiting | 没有的话，从 Notification 文本里解析 `use <T>` | `approvalTool`；`toolName(fromNotification:)` | ActivityResolverTests › approvalToolComesFromTheNotificationWhenNothingIsOpen（解析出 Bash；通知比这次等待旧就不用）；ActivityResolverTests › toolNameParsingFromNotification；StateRuleTests › l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen（没有打开的调用 → 从 Notification 解析出 Bash） | ✓ |
| 5.4-06 | 5.4 waiting（任务书未写） | Notification 点了名、且比这次等待更新时，优先取名字对得上的那个打开调用（并行时不张冠李戴） | `approvalTool` | ActivityResolverTests › notificationNamesTheToolAmongParallelOnes | 偏离（DESIGN.md §4「动作判定」waiting 条：Notification 点了名就取那个） |
| 5.4-07 | 5.4 waiting | `waitingFor` 是 "input needed" 或 "dialog open" → 提问 | `waitingActivity` | 同 4.1-17、4.1-18；StateRuleTests › l2_questionsAndPlanReview（引擎层：input needed / dialog open → 提问；AskUserQuestion 的 detail 不保留） | ✓ |
| 5.4-08 | 5.4 waiting | 或者文本里含 `input` / `question` / `elicitation` → 提问 | `waitingActivity` | ActivityResolverTests › unknownWaitingTextIsClassifiedByKeywords（"awaiting user input"、"an elicitation is open"、"a question for you" 三个都断言） | ✓ |
| 5.4-09 | 5.4 waiting | 此时 ExitPlanMode 正开着 → 计划待审 | `waitingActivity`（判据是「最新打开的工具是 ExitPlanMode」） | ActivityResolverTests › exitPlanModeWhileWaitingIsPlanReview（"input needed" / "dialog open" / "permission prompt" 三种 waitingFor）；StateRuleTests › l2_questionsAndPlanReview | ✓ |
| 5.4-10 | 5.4 waiting | 其他 → 其他等待，并把原始文本记下来 | `waitingActivity`（`.waitingOther(text ?? "")`） | ActivityResolverTests › nonPermissionWaitsFromTerminalSessions；ActivityResolverTests › unknownWaitingTextIsClassifiedByKeywords（"something else entirely"）；ActivityResolverTests › missingWaitingForFallsBackToNotificationText（无文本 → 空串）；StateRuleTests › l3_otherWaitsCarryTheRawText（附原始文本；批准后发「不再等你」） | ✓ |
| 5.4-11 | 5.4 waiting（实测） | AskUserQuestion / ExitPlanMode 的 Notification 文本也叫 "needs your permission to use X"，要看打开的工具名：AskUserQuestion 开着 → 提问，ExitPlanMode 开着 → 计划待审 | `waitingActivity` | ActivityResolverTests › askUserQuestionNotificationSaysPermissionButItIsAQuestion；ActivityResolverTests › exitPlanModeWhileWaitingIsPlanReview（含 waitingFor = permission prompt）；StateRuleTests › l2_questionsAndPlanReview（ExitPlanMode / AskUserQuestion 的通知文本都叫 permission） | 偏离（DESIGN.md §4 末段「实测里和任务书不一致的地方」：AskUserQuestion / ExitPlanMode 的 Notification 文本也是 permission） |
| 5.4-12 | 5.4 busy 1 | 有 PreCompact 但还没有 PostCompact → 整理上下文 | `busyActivity` | ActivityResolverTests › compactingWhenPreCompactHasNoPostCompact；EngineScenarioTests › compactionThroughHooks | ✓ |
| 5.4-13 | 5.4 busy 1 | 或会话记录显示正处在 `compact_boundary` 压缩中 → 整理上下文 | `busyActivity`：`compact_boundary` 之后 120 秒内没有新的 assistant / user 行才算；但 hook 已经说压缩结束了（PostCompact / SessionStart(compact) 不早于边界前 5 秒）就不再用它（L-003：真实日志里 compact_boundary 是压缩结束时才写的） | ActivityResolverTests › compactingFromTranscriptBoundary（边界之后有新行 → 不再算）；StateRuleTests › o1_compactionEndsWhenTheHooksSayItEnded、o2_boundaryHookSlackIsFiveSeconds（真实时序；4.9 秒算、5.1 秒不算；没有 hook 仍是整理上下文）；SpecTraceCoreTests › busyRulesAreCheckedInTheOrderCompactRetryToolThinking（没有 hook 说结束时，会话记录的边界同样排在重试和工具前面） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：整理上下文：hook 已说压缩结束就不再用 compact_boundary） |
| 5.4-14 | 5.4 busy 1（任务书未写） | PreCompact 之后 15 分钟没有 PostCompact 就不再显示；`compact_boundary` 之后 120 秒内没有新行才算 | `compactStaleAfter = 15 * 60`；`transcriptCompactWindow = 120` | ActivityResolverTests › compactingExpiresIfPostCompactNeverArrives（14 分钟仍显示、16 分钟不再）；StateRuleTests › o2_boundaryHookSlackIsFiveSeconds（120 秒兜底、5 秒口径） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：整理上下文：15 分钟 / 120 秒 / 5 秒窗口） |
| 5.4-15 | 5.4 busy 2 | 距最近一次 `api_error` 不超过 `retryInMs + 15 秒`，且之后没有新的 assistant / user 行 → 重试中 | `retrySlack = 15`；`busyActivity` | ActivityResolverTests › retryingWithinRetryInMsPlus15Seconds（118.9 s 是、119.1 s 否、之后有新行则否）；EngineScenarioTests › retryingThenBackToThinkingWhenTheRetryWindowPasses（16.2 s 边界）；StateRuleTests › c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds（3/10；2.5 s + 15 s：17.4 s 仍在、17.6 s 消退）、c2_aNewUserLineEndsTheRetryDisplay（之后出现新的 user 行 → 不再显示） | ✓ |
| 5.4-16 | 5.4 busy 2 | 显示第几次 / 共几次 | `.retrying(attempt:max:)` | ActivityResolverTests › retryingWithinRetryInMsPlus15Seconds（`.retrying(attempt: 2, max: 10)`）；EngineScenarioTests（2/10、3/10）；StateRuleTests › c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds（3/10）、c2_aNewUserLineEndsTheRetryDisplay（2/5） | ✓ |
| 5.4-17 | 5.4 busy 3 | 有打开的主线程工具 → 显示最新的那个 | `busyActivity`（`openTools.last`） | ActivityResolverTests › busyShowsTheNewestOpenToolWithParallelCount（Read 是最新的）；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-18 | 5.4 busy 3 | …并带上并行的个数 | `.tool(latest, parallel: openTools.count)` | ActivityResolverTests › busyShowsTheNewestOpenToolWithParallelCount（`n == 3`）；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（同 5.1-01） | ✓ |
| 5.4-19 | 5.4 busy 4 | 以上都不是 → 思考中 | `busyActivity` | ActivityResolverTests › busyWithoutToolsIsThinking | ✓ |
| 5.4-20 | 5.4 busy | 按 1 → 2 → 3 → 4 的顺序判断（压缩 > 重试 > 工具 > 思考） | `busyActivity` 的分支顺序 | SpecTraceCoreTests › busyRulesAreCheckedInTheOrderCompactRetryToolThinking（四样同时满足时压缩赢；去掉压缩重试赢；再去掉重试工具赢；都没有才是思考中；会话记录的压缩边界同样排在重试前面）；ActivityResolverTests › compactingWhenPreCompactHasNoPostCompact、retryingBeatsOpenTools | ✓ |
| 5.4-21 | 5.4 idle 1 | 被打断（持续 **3 秒**） | `interruptedDuration = 3`；`idleActivity` | ActivityResolverTests › interruptedLasts3SecondsThenIdle（2.9 s 是、3.1 s 否）；StateRuleTests › e1_transcriptInterruptLastsThreeSeconds（引擎层：从登记表 idle 起 2.9 s 还在、3.1 s 消退） | ✓ |
| 5.4-22 | 5.4 idle 1 | 打断判据：会话记录里出现打断，且比上一次轮次结束更晚 | SessionEngine.`classify`（`interruptAt ≥ 本轮开始 − 0.5 s` 且 `> stopMarker`） | EngineScenarioTests › interruptDetectedFromTheTranscriptWithoutAnyHook、abortedMidStreamAlsoCountsAsAnInterrupt、aNormalStopAfterAnEarlierInterruptIsNotInterrupted（更旧的打断不算）；StateRuleTests › e1_transcriptInterruptLastsThreeSeconds、d5_noResponseRequestedAfterAnInterruptIsNotAnError（打断之后的合成「No response requested.」不算出错） | ✓ |
| 5.4-23 | 5.4 idle 1 | 或者 hook 正常工作，但状态从 busy 变成 idle 时没有 Stop 事件 | `classify`（`stopGrace = 0.4` 后 `hookActive ? .interrupted : .finished`） | EngineScenarioTests › aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted；StateRuleTests › e2_hookInferredInterruptNeverShowsFinished（宽限期内不能显示 .finished；L-001 修复）、e3_withoutHooksTheEndOfATurnIsFinishedNotInterrupted（无 hook → 0.4 秒后当作做完了）、e4_aStopWithinTheGraceKeepsFinished（宽限期内 Stop 到 → 做完了）、e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst（Stop / 打断标记以 9 种顺序在 0.4 秒宽限期内到达，结论都对，中途不先显示 .finished / .interrupted / .errored 里的错误结论） | ✓ |
| 5.4-24 | 5.4 idle 2 | 做完了（持续 **5 秒**） | `finishedDuration = 5`；`idleActivity` | ActivityResolverTests › finishedLasts5SecondsThenIdle（4.9 s 是、5.1 s 否）；EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents；StateRuleTests › f1_finishedLastsFiveSeconds（4.9 s 还在、5.1 s 消退、idleSince == Stop 时刻） | ✓ |
| 5.4-25 | 5.4 idle 2 | 桌面会话最多等 **4 秒**看有没有新的 postTurnSummary | 数据层没有等待（元数据一变 `blocked` 就亮）；App 层 AlertCoordinator 等 8 秒（本轮总结实测约 7 秒后才落盘） | AlertCoordinatorTests › aDesktopSessionWaitsEightSecondsForTheTurnSummary（8.9 秒不发、9 秒发；blocked 立刻改成「需要你处理」）、aPendingFinishedAlertIsDroppedIfTheNextTurnAlreadyStarted；数据层：StateRuleTests › f3_blockedOverlayFollowsTheDesktopSummary（blocked 7 秒后才落盘也亮、保持到下一轮） | 偏离（DESIGN.md §10「与任务书不一致」汇总表：桌面会话「做完了」最多等 4 s → 等 8 s；§11 提醒判定） |
| 5.4-26 | 5.4 idle 2 | 如果是 blocked，就叠加「需要你处理」 | SessionEngine.`updateOverlays` | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（7 s 后总结落盘 → blocked）；StateRuleTests › f3_blockedOverlayFollowsTheDesktopSummary；StateRuleInvariantTests › z2_snapshotInvariantsHoldUnderRandomReplay（随机回放里「未读 / blocked 只在 idle」等不变量） | ✓ |
| 5.4-27 | 5.4 idle 3 | 出错：最后一次 `api_error` 已经重试到上限 | `classify`（`attempt ≥ max`、`max > 0`、之后没有新行） | StateRuleTests › d1_erroredByExhaustedRetriesAlone（只有 10/10 的 api_error、没有合成消息 → 出错、unread、事件 errored）、d3_notErroredWhenRetriesRecovered、d4_notErroredWhenAnAssistantLineFollowsTheLastRetry（重试没到上限 / 之后又有 assistant 输出 → 不算出错） | ✓ |
| 5.4-28 | 5.4 idle 3 | 或者最后一条 assistant 是合成出来的 API 错误 | `classify`（`syntheticErrorAt == lastAssistantAt`） | TranscriptTests › syntheticApiErrorAssistantIsRecognized（解析）；EngineScenarioTests › erroredTurnStaysErroredUntilItStartsDozing；StateRuleTests › d2_erroredBySyntheticApiErrorMessageAlone、d5_noResponseRequestedAfterAnInterruptIsNotAnError | ✓ |
| 5.4-29 | 5.4 idle 3（任务书未写时长） | 出错状态一直保持到开始打盹（10 分钟） | `idleActivity`（`idleFor < dozeAfter`） | ActivityResolverTests › erroredStaysUntilDozing（599 s 仍出错、601 s 打盹）；EngineScenarioTests › erroredTurnStaysErroredUntilItStartsDozing。（任务书没给时长；DESIGN.md 第 4 节「idle：…出错（一直保持到打盹）」写明了这个取舍） | ✓ |
| 5.4-30 | 5.4 idle | 判断顺序 被打断 → 做完了 → 出错；实现里出错优先于做完了 | `classify`：被打断 → 出错 → 做完了 → 空闲（出错先于做完了） | StateRuleTests › d1_erroredByExhaustedRetriesAlone…StateRuleTests › d5_noResponseRequestedAfterAnInterruptIsNotAnError、d6_erroredWinsOverFinishedWhenBothEvidencesExist（同时有 Stop 证据和出错证据 → 出错） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：出错优先于做完了，并一直保持到打盹） |
| 5.4-31 | 5.4 idle 4 | 空闲超过 **10 分钟** → 打盹 | `dozeAfter = 10 * 60`（SessionSignals）；`idleActivity` | ActivityResolverTests › idleThenDozingThenSleepingAtTheThresholds（9:59 idle、10:00 dozing）；EngineScenarioTests › attachingToALongIdleSessionShowsTheRightSleepState；StateRuleTests › g1_dozeAt10MinutesSleepAt45Minutes（0.1 s 边界：599.9 s idle、600.1 s dozing） | ✓ |
| 5.4-32 | 5.4 idle 4 | 空闲超过 **45 分钟** → 睡着 | `sleepAfter = 45 * 60`；`idleActivity` | ActivityResolverTests › idleThenDozingThenSleepingAtTheThresholds（44:59 dozing、45:00 sleeping）；StateRuleTests › g1_dozeAt10MinutesSleepAt45Minutes（2699.9 s dozing、2700.1 s sleeping、24 小时仍 sleeping） | ✓ |
| 5.4-33 | 5.4 idle 4 | 两个时间都可以改：引擎层可配 | `SessionEngine.Options.dozeAfter / sleepAfter` → `baseSignals` | ActivityResolverTests（60 / 120 s）；EngineScenarioTests › dozeAndSleepThresholdsAreConfigurable（30 / 90 s） | ✓ |
| 5.4-34 | 5.4 idle 4 | 两个时间都可以在**设置里**改（`idle.dozeMinutes` / `idle.sleepMinutes`） | App/SettingsView.swift 的两个 Stepper（`idle.dozeMinutes` / `idle.sleepMinutes`）→ Settings（夹进合法范围）→ `EngineConfig.apply(to:settings:)` → `RealProvider.make` 造 `SessionStore` 时填进 `SessionEngine.Options`（A-001 / L-002 修复；下次启动生效，设置页里写明） | EngineConfigTests › settingsMapToEngineOptions（3 分钟 → dozeAfter == 180）、outOfRangeValuesAreClampedAndSleepAlwaysComesAfterDoze、realProviderPassesTheSettingsToTheEngine；SettingsTests › numbersWrittenBehindOurBackAreClampedIntoTheirValidRange；引擎层可配：EngineScenarioTests › dozeAndSleepThresholdsAreConfigurable、StateRuleTests › g1_dozeAt10MinutesSleepAt45Minutes | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」下次启动生效） |
| 5.4-35 | 5.4 叠加·未读 | 一轮做完后亮起（正常做完和出错亮；被你自己打断的不亮，DESIGN.md §13 已补记） | SessionEngine.`complete`（`kind != .interrupted` → `unread = true`） | EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（unread == true）；EngineScenarioTests › aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted（打断 → false）；EngineScenarioTests › erroredTurnStaysErroredUntilItStartsDozing（出错 → true） | ✓ |
| 5.4-36 | 5.4 叠加·未读 | 你跳转到这个会话 → 清掉 | SessionEngine.`markSeen`；App/AppModel.swift `jump(snapshot:)`（`JumpService.shared.jump` 之后调用 `provider.markSeen`） | 引擎层：EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（`markSeen` → unread == false，之后不会自己再亮）；StoreTests › markSeenAndRerollAreSafeFromAnyThread；StateRuleTests › f2_unreadClearsInExactlyThreeWays（条件 1）。应用层接线：AppModelTests › clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal（反例：悬空座位 / 演示模式的点击不跳、不清未读）；真实点击会真的打开 Claude / 终端，没有自动化测试。见「间接验证清单」 | ✓（间接验证：跳转会真的打开 Claude / 终端，AppModel.jump → provider.markSeen 这一步只能读代码 + 反例测试） |
| 5.4-37 | 5.4 叠加·未读 | 桌面 `lastFocusedAt` 晚于这一轮结束 → 清掉 | `updateOverlays` | EnginePresenceTests › focusingTheSessionInTheDesktopAppClearsUnread；StateRuleTests › f2_unreadClearsInExactlyThreeWays（早于 / 等于本轮结束都不清，晚 1 ms 才清） | ✓ |
| 5.4-38 | 5.4 叠加·未读 | 下一轮开始 → 清掉 | `transition` | EngineScenarioTests › startingTheNextTurnClearsUnread；StateRuleTests › f2_unreadClearsInExactlyThreeWays（条件 3：下一轮开始） | ✓ |
| 5.4-39 | 5.4 叠加·blocked | 一直保持到下一轮开始 | `updateOverlays`；`transition` | EnginePresenceTests › blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn（30 分钟后仍 blocked；下一轮开始清掉，即使元数据里还是旧总结）；StateRuleTests › f3_blockedOverlayFollowsTheDesktopSummary（保持一小时；只发一次事件；completed 不亮） | ✓ |
| 5.4-40 | 5.4 叠加·安静 | busy 但 **10 分钟**内 hook 和会话记录都没有增长 | `quietAfter = 10 * 60`；`update` | EngineScenarioTests › aSessionBusyForAnHourNeverDies（第 1–8 分钟 false、第 11 分钟起 true、有新 hook 事件立刻清掉）；StateRuleTests › h2_quietThresholdAndItsResets（599 s 不是、601 s 是；会话记录长一行 / hook 有新事件都立刻清掉） | ✓ |
| 5.4-41 | 5.4 叠加·安静 | 只是换一种画法，绝不能据此判定会话已死 | 同 4.1-29；`quiet` 只是快照标记 | EngineScenarioTests › aSessionBusyForAnHourNeverDies（每分钟断言 presence == .present、phase == .busy）；StateRuleTests › h1_twoHoursOfBusyIsQuietNotDead | ✓ |

---

## 5.5 在场、离场、下班工位

（`Stage/OfficeScene.swift`、`Walkers.swift` 的行为；下班工位的画面语义、走路的时间线现在都有语义测试。）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.5-01 | 5.5 离场触发 | 登记文件消失 → 离场 | Core/Ingest/RegistryScanner.swift `scan`；SessionEngine.`reconcile`（这个 key 不在存活记录里 → pendingAway） | T-Core/RegistryTests › removedFilesAreReported；EnginePresenceTests › departureIsDebouncedBy3SecondsAndComingBackCancelsIt（`endProcess` 同时删文件 + 杀进程，是混合触发）；StateRuleTests › i1_departureDebounceThenReclaimAfter8Seconds | ✓ |
| 5.5-02 | 5.5 离场触发 | PID 已死 → 离场（文件还在也一样） | `aliveRecords`（`ProcessProbe.classify` → dead 不进存活列表） | EnginePresenceTests › aDeadPidWithALeftoverRegistryFileIsGone；StateRuleProcessTests › r3_recycledProcessIsDebouncedBy3Seconds | ✓ |
| 5.5-03 | 5.5 离场触发 | PID 被复用 → 离场 | 同上（`.reused` 不进存活列表） | EnginePresenceTests › pidReuseIsTreatedAsTheOldProcessBeingGone；StateRuleTests › i6_pidReuseGoesThroughTheSameDebounce、StateRuleProcessTests › r4_pidReuseWithARealProcess | ✓ |
| 5.5-04 | 5.5 离场 | 先防抖 **3 秒**（桌面 App 重启会带着同一个 host id 回来） | `awayDebounce = 3`；`reconcile`（pendingAway 期间快照仍是 `.present`，回来则什么都没发生） | EnginePresenceTests › departureIsDebouncedBy3SecondsAndComingBackCancelsIt（2.5 s 时仍在场；回来后没有离场 / 再进场事件）；EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat（run 3.2 s 后才是 away）；StateRuleTests › i1_departureDebounceThenReclaimAfter8Seconds（2.95 s 仍在场、3.05 s 离场、事件只发一次）、StateRuleProcessTests › r3_recycledProcessIsDebouncedBy3Seconds（真子进程退出：2.9 s 仍在场、3.1 s 离场） | ✓ |
| 5.5-05 | 5.5 离场 | 确认后播放离场动画：起身、推好椅子、挥手、走出门 | Stage/OfficeScene.swift `render`（人从 present 消失 → `startLeaving`）；Stage/Walkers.swift：起身 0.3 秒（椅子拉出来）→ 椅子推好 → 挥手 0.7 秒 → 走进门洞 → 门在身后关上 0.16 秒（`standTime` / `waveTime` / `tail`；`chairOut`） | SpecTraceStageTests › leavingStandsUpPushesTheChairInWavesAndWalksOut（起身的 0.3 秒里椅子拉出来、之后推好；总时长 = 0.3 + 0.7 + 走路 + 0.16；走完后走路系统清空）；WalkersAndOffDutyTests › leavingStandsWavesWalksOutAndTheDoorClosesBehindThem（整个过程座位不再是「有人」、总时长范围）；RenderingTests › walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt（门洞外没有人） | ✓ |
| 5.5-06 | 5.5 离场 | 桌面会话、元数据还在、没归档 → 下班工位 | SessionEngine.`confirmAway`（`hostSessionId` + `metaReader.meta` + `!isArchived`） | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat（dormant == true、座位保留）；EnginePresenceTests › aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves（归档 / 终端 → dormant == false）；StateRuleTests › i2_dormantSeatOnlyForDesktopSessionsWithLiveUnarchivedMetadata | ✓ |
| 5.5-07 | 5.5 下班工位 | 显示器关掉 | Stage/SeatRenderer.swift `drawMonitor`（非 occupied → `.off`）；`ledName`（待机灯关） | SpecTraceStageTests › anOffDutyDeskHasItsMonitorAndLampOff（下班工位的 SeatView：`screen == .off`、待机灯 0、台灯灭、没有人 / 气泡 / 道具 / 小助手）；MonitorTests › theMonitorFadesOutOver300msInsteadOfCuttingToBlack（人离开时 300 ms 抖动渐变熄灭，不是硬切黑屏） | ✓ |
| 5.5-08 | 5.5 下班工位 | 椅子推进去 | SeatRenderer.`draw`（非 occupied 且没有 `chairOut` → 画推进去的椅子） | WalkersAndOffDutyTests › anOffDutyDeskIsDimSilentAndUnclickableAndTheCoatHangsByTheDoor（`!chairOut`：椅子推进去）；SpecTraceStageTests › anOffDutyDeskHasItsMonitorAndLampOff | ✓ |
| 5.5-09 | 5.5 下班工位 | 外套挂到门口的衣帽架上 | OfficeScene.`render`（`dormant.prefix(coatSlots.count)`）画外套；Stage/RoomRenderer.swift（衣帽架有 4 个挂钩） | WalkersAndOffDutyTests › anOffDutyDeskIsDimSilentAndUnclickableAndTheCoatHangsByTheDoor（衣帽架上那块像素和「没有下班同事」的同一帧不同）；SpecTraceStageTests › anOffDutyDeskHasItsMonitorAndLampOff（4 个挂钩） | ✓ |
| 5.5-10 | 5.5 下班工位 | 桌牌变暗 | OfficeScene.`plateTexts`（`dim = v.dim 或 mode == .dormant`）；`SeatView.dim`（置位） | WalkersAndOffDutyTests › anOffDutyDeskIsDimSilentAndUnclickableAndTheCoatHangsByTheDoor（`v.dim`、桌牌文字用浅色 `dormantTitleInk`）；SpecTraceStageTests › anOffDutyDeskHasItsMonitorAndLampOff | ✓ |
| 5.5-11 | 5.5 离场 | 其他会话 → **8 秒**后收回工位 | `awayLinger = 8`；`confirmAway`；`maintainAway` | StateRuleTests › i1_departureDebounceThenReclaimAfter8Seconds（确认离场后 7.9 s 工位还在、8.1 s 收回）；EnginePresenceTests › aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves（只验上界） | ✓ |
| 5.5-12 | 5.5 下班工位来源 | 本次运行中见过的 buddy（离场后成为下班工位） | `confirmAway`：同一个 BuddyState 转入 `.away(dormant: true)` | EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat；EnginePresenceTests › departedSessionsCompeteForTheFourDormantSeats | ✓ |
| 5.5-13 | 5.5 下班工位来源 | App 启动时 `lastActivityAt` 在 **3 小时**以内（没归档、没有活进程）的桌面会话 | `dormantRecent = 3 * 3600`；`bootstrapDormants` | SpecTraceCoreTests › dormantSeatsAtLaunchUseAThreeHourWindow（lastActivityAt 在 2:59:59 前的入选、3:00:01 前的不入选）；EnginePresenceTests › dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions（最多 4 个、归档的排除）、aLiveSessionIsNotAlsoADormantSeat | ✓ |
| 5.5-14 | 5.5 下班工位 | 最多保留 **4 个** | `dormantMax = 4`；`bootstrapDormants` `.prefix`；`maintainAway` | EnginePresenceTests › dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions（6 个候选 → 4 个）；EnginePresenceTests › departedSessionsCompeteForTheFourDormantSeats（6 个离场 → 4 个） | ✓ |
| 5.5-15 | 5.5 下班工位 | 超出时先移走最久没活动的 | `maintainAway`（按 `max(since, lastActivityAt)` 排序，留最近的 4 个） | SpecTraceCoreTests › whenMoreThanFourAreOffDutyTheLeastRecentlyActiveGoFirst（运行中依次离场 6 个：留下的正好是最后走的 3…6 号，1、2 号被移走）；EnginePresenceTests › dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions（启动时：留下的是最近活动的 1–4 号）、departedSessionsCompeteForTheFourDormantSeats（个数）；设置里「最多保留」调小时（应用层）：SpecTraceAppTests › shrinkingTheDormantLimitKeepsTheMostRecentlyActiveSeats | ✓ |
| 5.5-16 | 5.5 下班工位 | 满 **12 小时**移除 | `dormantExpire = 12 * 3600`；`maintainAway` | EnginePresenceTests › dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted（11 小时还在、12 小时后没了） | ✓ |
| 5.5-17 | 5.5 下班工位 | 会话被归档时移除 | `maintainAway`（`isArchived`） | 同上（b 被归档 → 消失） | ✓ |
| 5.5-18 | 5.5 下班工位 | 会话被删除（元数据没了）时移除 | `maintainAway`（`meta == nil`） | 同上（c 元数据被删 → 消失） | ✓ |
| 5.5-19 | 5.5 下班工位 | 同一个身份回来时，会走回原来的工位 | 数据层：`reconcile` `.away` 分支（座位、salt 保留，发 `arrived(freshAfterLaunch: true)`）；舞台：OfficeScene.`render`（不在上一帧 present 里且 `appearedAfterLaunch` → `startEntering`；离场的人从 `seatedAt` / `lastApp` 里清掉，第二次回来不会座位上已经坐着人，A-008 / 疑点 Q-02 的修复） | 数据层：EnginePresenceTests › aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat；StateRuleTests › i3_theSameIdentityComingBackDuringTheLingerSitsInTheSameSeat；舞台：AppLayerFixTests › aSessionThatComesBackWalksInAgainInsteadOfSittingDownAtOnce（出现 → 坐好 → 离场走完 → 再出现：第一帧座位是空的、椅子拉出来、有人在路上，走完才「有人」）、departedSessionsAreForgottenByTheScene | ✓ |
| 5.5-20 | 5.5 进场 | App 启动之后新出现的会话 → 从门口走到工位坐下 | 数据层 `appearedAfterLaunch = !firstPoll`；舞台 OfficeScene.`render`、Stage/Walkers.swift `startEntering` | EnginePresenceTests › sessionsPresentAtLaunchSitDownDirectlyAndLaterOnesWalkIn（标志与 arrived 事件）；T-Stage/RenderingTests › enteringWalkerAppearsOnlyAfterTheDoorStartedOpening（门先开、0.3 s 时人已出来、走完才算坐下） | ✓ |
| 5.5-21 | 5.5 进场 | …约 **2.5 秒** | Walkers.`startEntering`：`speed = max(28, min(70, 路线长度 / 2.5))`，走路时间 = 长度 / speed；另有门开 0.1 s、坐下 0.3 s（`lead` / `sitTime`） | SpecTraceStageTests › walkingInTakesTwoAndAHalfSecondsWhenTheRouteLengthAllowsIt（路线 70–175 像素的座位走路正好 2.5 秒；更近的按 28 像素 / 秒、更远的按 70 像素 / 秒封顶）；WalkersAndOffDutyTests › walkingInTakesAboutTwoAndAHalfSecondsAndFarSeatsAreSpeedCapped、aSessionThatArrivesAfterLaunchWalksInAndSitsDownWhileOnesPresentAtLaunchAreAlreadySeated（从出现到坐下 2–5.5 秒）；RenderingTests › enteringWalkerAppearsOnlyAfterTheDoorStartedOpening | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：走到工位「约 2.5 秒」：路程 / 2.5 s，夹在 28–70 像素 / 秒，远座位要 3–5 秒） |
| 5.5-22 | 5.5 进场 | App 启动时就在跑的会话 → 直接坐好（数据层标志） | SessionEngine.`reconcile`（`appearedAfterLaunch: false`） | EnginePresenceTests › sessionsPresentAtLaunchSitDownDirectlyAndLaterOnesWalkIn | ✓ |
| 5.5-23 | 5.5 进场 | …舞台上不走路、直接坐好 | OfficeScene.`render`（`prevKeys == nil` 的第一帧不启动走路；`appearedAfterLaunch == false` 的也不走） | WalkersAndOffDutyTests › aSessionThatArrivesAfterLaunchWalksInAndSitsDownWhileOnesPresentAtLaunchAreAlreadySeated（启动时就在的：第一帧就是「有人」、没有走路的人；之后才来的：椅子拉出来、走完才坐下） | ✓ |
| 5.5-24 | 5.5 进场 | …显示器从左到右依次开机，每台间隔 **100 ms** | OfficeScene.`render`：`appearedAfterLaunch == false` 的人第一帧就采用真正的姿势 / 屏幕，开机进度按座位号从左到右每台晚 `launchStaggerStep = 0.1` 秒（总延迟封顶 1.5 秒，DESIGN.md §13 已补记）；启动之后才来的人是走进来坐下再开机（SP-05 修复） | MonitorTests › monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals（四台显示器首次亮起的间隔 = 0.1 秒 ± 0.045，第一台在 0.15 秒内） | ✓ |

---

## 5.6 表现层节奏（VisualDirector：每个 buddy 一个 Performer）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.6-01 | 5.6 总则 | 每个 buddy 一个 Performer，由 VisualDirector 持有 | Stage/VisualDirector.swift `performers`、`update` | T-Stage/PerformerTimingTests 各用例都通过 `director.performers[key]` 取 Performer | ✓ |
| 5.6-02 | 5.6 等待类 | 等待状态要持续 **0.4 秒**才开始转身 | Stage/Performer.swift `update`（`time − waitSince ≥ 0.4`） | PerformerTimingTests › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5（0.36 s 不转、0.44 s 已转）；PerformerTimingTests › aWaitingBlipShorterThan0_4SecondsDoesNotTurnTheBuddy | ✓ |
| 5.6-03 | 5.6 等待类 | 持续 **1.5 秒**才发提醒 | App/AlertCoordinator.swift `observe`（设置拷成值 `AlertConfig`，时钟就是 `now` 参数；`ep.since` 是协调器第一次看到这段等待的时刻，满 1.5 秒才发） | AlertCoordinatorTests › approvalAlertWaitsExactlyOneAndAHalfSecondThenFiresOnce（1.49 秒不发、1.5 秒发、同一段等待只发一次）、aWaitBlipShorterThanTheDebounceNeverAlertsAndClearsItsNotification、changingTheKindOfWaitRestartsTheDebounce；AlertFallbackTests › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（等待满 1.5 秒后兜底提示卡出现） | ✓ |
| 5.6-04 | 5.6 等待类 | 等待结束后，再保持面向你 **1.5 秒**才转回去 | `update`（`waitEndedAt`，`time − e ≥ 1.5`） | PerformerTimingTests › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5（结束后 1.4 s 仍面向、1.6 s 已转回） | ✓ |
| 5.6-05 | 5.6 等待类 | 这样连着批准好几次时不会来回转 | `update`（新一段等待到来时 `waitEndedAt = nil`，不转回也不重新转） | SpecTraceStageTests › approvingSeveralTimesInARowNeverTurnsTheBuddyBackAndForth（三次等待之间只隔 0.6 秒：一直面向你、转身只开始过一次，最后一次结束 1.5 秒之后才转回去） | ✓ |
| 5.6-06 | 5.6 最短停留 | 姿势最短停留 **1.5 秒** | `update`（`time − poseSince ≥ 1.5`） | PerformerTimingTests › poseNeverChangesFasterThanEvery1_5Seconds（读 ↔ 改每 0.4 秒交替，相邻两次姿势变化 ≥ 1.5 秒）；SpecTraceStageTests › dwellTimesAreExactlyOneAndAHalfPointEightAndOneSecond（目标一变，姿势正好在 1.5 秒（±1 帧）换，不晚） | ✓ |
| 5.6-07 | 5.6 最短停留 | 屏幕内容最短停留 **0.8 秒** | `update`（`time − screenSince ≥ 0.8`） | PerformerTimingTests › screenNeverChangesFasterThanEvery0_8Seconds（每 0.2 秒交替）；SpecTraceStageTests › dwellTimesAreExactlyOneAndAHalfPointEightAndOneSecond（屏幕正好在 0.8 秒（±1 帧）换） | ✓ |
| 5.6-08 | 5.6 最短停留 | 桌牌文字最短停留 **1.0 秒** | `update`（只有「动作」部分受限；数字换了动作没换、等待类、空牌直接更新） | PerformerTimingTests › plateActionTextNeverChangesFasterThanEverySecond（每 0.3 秒交替）；SpecTraceStageTests › dwellTimesAreExactlyOneAndAHalfPointEightAndOneSecond（桌牌动作文字正好在 1.0 秒（±1 帧）换） | ✓ |
| 5.6-09 | 5.6 最短停留 | 停留期间只记下最新的目标状态，跳过中间态（Read → Grep → Read = 一直在读，屏幕最多每 0.8 秒换一次） | 目标每帧重算（`targetPose` / `targetScreen`），到期才切换：`update` | SpecTraceStageTests › intermediateStatesInsideTheDwellAreSkipped（Read → Grep → Read：姿势 / 屏幕 / 桌牌都没动过，一直是「在读」；Read → Grep → Edit：直接到 Edit，没显示过 Grep 的姿势 / 结果列表 / 「在找」）；PerformerTimingTests 的三个最短停留用例 | ✓ |
| 5.6-10 | 5.6 切换方式 | 同一类工具之间切换，只换屏幕内容 | 姿势通道按 `PoseKind`、屏幕通道按 `ScreenKind` 各自独立（`targetPose`、`targetScreen`）；同类工具姿势相同，只有屏幕变 | SpecTraceStageTests › sameCategoryToolsOnlySwapTheScreen（Grep → Glob：姿势不变，结果列表 → 文件树；Read swift → Read md：姿势不变，文档颜色换；Edit → MultiEdit：什么都不变；对照 Read → Edit：姿势和屏幕都换） | ✓ |
| 5.6-11 | 5.6 切换方式 | …用 **4 帧从上往下的擦除**过渡 | 没有：屏幕直接硬切（`screen = ts`，`screenT` 只是让新内容的动画从 0 开始）；全源码里没有擦除 / wipe 的实现（grep 过） | —（没做；屏幕切换是硬切，各屏幕自己有逐行出现动画）；无黑帧 / 白帧 / 闪烁由 RenderingTests › officeHasNoFlickerAtEveryZoom、tankAndStripHaveNoFlicker 钉住 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：屏幕内容 4 帧从上往下擦除没做，屏幕直接切换） |
| 5.6-12 | 5.6 切换方式 | 不同类之间切换，走过渡帧：先放下道具，再开始新动作 | 没有过渡帧：`pose = tp` 直接切，道具随姿势一起立刻出现 / 消失（`PoseFrame.props` → SeatRenderer）；手 / 头靠弹簧平滑，但不是「先放下道具」 | —（没做）；无黑帧 / 白帧 / 闪烁由 RenderingTests › officeHasNoFlickerAtEveryZoom、officeHasNoFlickerAtNightAndDuringLightTransition 钉住 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：不同类工具之间先放下道具再开始新动作没做，道具随姿势一起出现 / 消失） |
| 5.6-13 | 5.6 切换方式 | 等待类状态到来时，最多等当前过渡帧播完（≤ **250 ms**）就立即插入 | 因为没有过渡帧，等待类是立即插入：屏幕 / 桌牌绕过最短停留（`waitingScreen ||`、`asking != nil ||`），转身按 0.4 秒确认，姿势通道不管它。`VisualDirector.update`：等待类快照到来时先清掉这个人的 pending，不被此前的「错开」推迟拦住（定稿时发现的缺口 G-1，已修：`QA/issues-stage.md` SP-06） | SpecTraceStageTests › waitingContentIsInsertedImmediatelyEvenInsideTheDwell（屏幕、桌牌、气泡在等待开始的同一帧就换成等待内容；身体 0.4 秒后转身）；SpecTraceStageTests › aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately（SP-06 / 原 G-1：10 个人同一帧变化、第 10 个人被错开到 2.6 秒；他 2.1 秒变成等批准，等待态 ≤ 250 ms 内显示，中间没有一帧过期的旧动作） | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：没有过渡帧，等待类最多等过渡帧播完 ≤ 250 ms 这一段没做；等待类是立即插入） |
| 5.6-14 | 5.6 长时间状态 | Bash 超过 **8 秒** → 「往后靠着盯屏幕」姿势 | `targetPose`（`elapsed > 8 → .leanBack`，3–8 s 是 `.restAtDesk`）；屏幕 `.terminalLong` | SpecTraceStageTests › longRunningStatesSwitchPoseAtTheirThresholds（Bash 7.9 秒 ≠ 往后靠、8.1 秒 = 往后靠（屏幕也从「终端」换成「终端 + 进度条」））；PerformerMappingTests › everyRowOfTheStateToAnimationTable（6.5 表逐行） | ✓ |
| 5.6-15 | 5.6 长时间状态 | WebFetch / WebSearch 超过 **8 秒** → 同上 | `targetPose` | SpecTraceStageTests › longRunningStatesSwitchPoseAtTheirThresholds（WebFetch / WebSearch 7.9 秒 ≠ 往后靠、8.1 秒 = 往后靠）；PerformerMappingTests › everyRowOfTheStateToAnimationTable（6.5 表逐行） | ✓ |
| 5.6-16 | 5.6 长时间状态 | Monitor 超过 **8 秒** → 同上 | `targetPose` ：Monitor 一开始就是 `.leanBack`（和 6.5 表「Monitor：往后靠」一致），不等 8 秒 | SpecTraceStageTests › longRunningStatesSwitchPoseAtTheirThresholds（Monitor 0.5 秒和 30 秒都是往后靠）；PerformerMappingTests › everyRowOfTheStateToAnimationTable（6.5 表逐行） | ✓ |
| 5.6-17 | 5.6 长时间状态 | 思考超过 **20 秒** → 「深度思考」姿势 | `targetPose`（`el = now − activitySince`，`el > 20 → .thinkingDeep`） | SpecTraceStageTests › longRunningStatesSwitchPoseAtTheirThresholds（思考 19.9 秒 = 思考、20.1 秒 = 深度思考）；PerformerMappingTests › everyRowOfTheStateToAnimationTable（思考 > 20 秒一行） | ✓ |
| 5.6-18 | 5.6 做完一轮 | busy → idle 后先等 **0.4 秒**（防止这一轮其实还没完） | `targetPose`（`.finished` 且 `el < 0.4` → 沿用 `lastBusyPose`）。只有姿势通道在等这 0.4 秒；屏幕 / 桌牌 / 小旗立刻切到「做完了」（6.5 表对应行没有要求它们等）；数据层在证据不足时不再先报 `.finished`（L-001） | SpecTraceStageTests › finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack（目标边界 0.39 秒仍是忙姿势、0.41 秒才伸懒腰；30 fps 端到端：结束后 0.4 秒之内姿势不变）；PerformerMappingTests › finishingATurnWaits0_4SecondsBeforeStretching | ✓ |
| 5.6-19 | 5.6 做完一轮 | 伸个 **1.2 秒**的懒腰 | `targetPose`（`el < 1.6 → .stretch`）；Stage/PoseLibrary.swift `.stretch`（`p = t / 1.2`：手举过头再放下，正好 1.2 秒一个来回）。姿势 1.5 秒最短停留不会把懒腰跳过或截短（疑点 Q-07：最晚在结束后 1.5 秒起开始播） | SpecTraceStageTests › finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack（0.6 秒时手举得最高、1.2 秒回到起点；目标 1.59 秒仍是懒腰）、theStretchIsNotSkippedWhenThePoseJustChanged（上一个姿势 0.1 秒前才换：懒腰照样整整播完，随后靠回椅背） | ✓ |
| 5.6-20 | 5.6 做完一轮 | 再侧身靠到椅背上 | `targetPose`（`.leanSide`）；PoseLibrary `.leanSide` | SpecTraceStageTests › finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack（目标 1.61 秒起是 3/4 侧身靠着；端到端：最终姿势是 leanSide）；PerformerMappingTests › everyRowOfTheStateToAnimationTable（做完了：3/4 侧身靠着） | ✓ |
| 5.6-21 | 5.6 做完一轮 | 未读标记一直保留 | 数据层：未读只在 3 个条件下清（见 5.4-36…38）；舞台：`SeatView.flag = snapshot.unread`（Performer.`seatView`）→ SeatRenderer.`drawMonitor` 插小旗 | EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（「做完了」结束 5 秒后 `unread` 仍为 true）；SpecTraceStageTests › finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack（30 fps 端到端：结束之后每一帧 `SeatView.flag` 都是 true） | ✓ |
| 5.6-22 | 5.6 错开 | 多个 buddy 同时变化时，按顺序每个晚 **90 ms** | VisualDirector `update`（`time + min(0.6, 0.09 × order)`，按座位顺序；等待类不错开） | PerformerTimingTests › simultaneousChangesAreStaggeredBy90msEach（5 人，相邻间隔 ≈ 0.09 ± 0.04 s） | ✓ |
| 5.6-23 | 5.6 错开 | …最多错开 **0.6 秒** | 同上 `min(0.6, …)` | SpecTraceStageTests › staggerIsCappedAtSixTenthsOfASecond（10 个人同一帧变化：第 1…7 个依次晚 90 ms，第 8、9、10 个都是 0.6 秒，最大错开 ≤ 0.6 秒）；PerformerTimingTests › simultaneousChangesAreStaggeredBy90msEach | ✓ |

---

## 5.7 工具归类（ToolCatalog）

（实现都在 `Core/Fusion/ToolCatalog.swift` 的 `category(of:)`；输入先经 `cleanName` 去掉 hook 截断留下的 `…`。）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.7-01 | 5.7 表 | read：Read、NotebookRead | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）；ModelTests › toolCatalogClassifies | ✓ |
| 5.7-02 | 5.7 表 | search：Grep、Glob、LS | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-03 | 5.7 表 | edit：Edit、MultiEdit | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）；ModelTests › toolCatalogClassifies | ✓ |
| 5.7-04 | 5.7 表 | write：Write、NotebookEdit | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-05 | 5.7 表 | bash：Bash、BashOutput、KillShell（实现另加 TaskOutput、TaskStop：新版本里的新名字，真实日志里见过） | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）（TaskOutput / TaskStop 是新版本的新名字，DESIGN.md 第 5 节表格「bash」行已记录） | ✓ |
| 5.7-06 | 5.7 表 | monitor：Monitor | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-07 | 5.7 表 | web：WebFetch、WebSearch | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-08 | 5.7 表 | browser：`mcp__Claude_Browser__*`、`mcp__claude-in-chrome__*` | （前缀匹配） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）；ModelTests › toolCatalogClassifies | ✓ |
| 5.7-09 | 5.7 表 | computer：`mcp__computer-use__*` | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）；ModelTests › toolCatalogClassifies（`mcp__computer-use__app_click`） | ✓ |
| 5.7-10 | 5.7 表 | delegate：Agent、Task、Workflow、SendMessage | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-11 | 5.7 表 | todo：TodoWrite、TaskCreate、TaskUpdate、TaskList、TaskGet | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）；ModelTests › toolCatalogClassifies | ✓ |
| 5.7-12 | 5.7 表 | skill：Skill、ToolSearch、ListSkills | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-13 | 5.7 表 | planEnter：EnterPlanMode | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-14 | 5.7 表 | planExit：ExitPlanMode | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | 间接：ActivityResolverTests › exitPlanModeWhileWaitingIsPlanReview（依赖 `category == .planExit`） | ✓ |
| 5.7-15 | 5.7 表 | planExit 等待时就是「计划待审」 | ActivityResolver `waitingActivity` | 同 5.4-09 | ✓ |
| 5.7-16 | 5.7 表 | sendFile：SendUserFile | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`） | ✓ |
| 5.7-17 | 5.7 表 | schedule：ScheduleWakeup、CronCreate（实现另加 CronDelete、CronList） | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（任务书 5.7 表里的每个工具名逐个断言类别，含被 hook 截断的 `名字…`）（CronDelete / CronList 是同类的新名字，DESIGN.md 第 5 节表格「schedule」行的 `Cron*` 已记录） | ✓ |
| 5.7-18 | 5.7 表 | mcp：其他 `mcp__<server>__*`，**显示 server 名** | `makeCall`（`server` 只对 mcp / browser / computer 类填）；`mcpServer(of:)` | SpecTraceCoreTests › toolCatalogFollowsTheTaskBookTable（`mcp__notion__…` → server `notion`、`mcp__ccd_session_mgmt__search_session_tr…` → `ccd_session_mgmt`，浏览器 / computer-use 也带 server 名，内置工具没有 server）；ModelTests › toolCatalogClassifies、mcpServerFromTruncatedName；ToolTrackerTests › truncatedToolNamesMatchByPrefix | ✓ |
| 5.7-19 | 5.7 表 | unknown：其余全部 | `ToolCatalog.category(of:)`（Core/Fusion/ToolCatalog.swift） | ModelTests › toolCatalogClassifies（"SomethingNew" → unknown） | ✓ |
| 5.7-20 | 5.7（hook 坑 2） | 被 hook 截断、结尾带 `…` 的名字也能归类 | `cleanName` | ModelTests › toolCatalogClassifies（`mcp__ccd_session_mgmt__search_session_tr…` → mcp） | ✓ |


---

## 间接验证清单

（确实没法自动化测的 2 条。每条一行：编号 / 要求 / 为什么测不了 / 间接证据。主线程可以原样搬进 REPORT.md。）

| 编号 | 要求 | 为什么没法自动化测 | 间接证据 |
|---|---|---|---|
| 4.1-38 | 终端会话（2.1.267）的登记表字段应和桌面会话大致相同、没有 `hostSessionId`；碰到活终端会话要核对字段，碰不到就靠 fixture（任务书 4.1 自己给了退路） | 这台机器上没有活着的终端会话：终端版 `~/.local/bin/claude` 的 OAuth 登录已过期（DESIGN.md 第 9.1 节），重新登录要碰凭据，不做；也没法凭空造一个真实的终端登记表 | 终端记录走和桌面记录同一个 `RegistryScanner.parse`（所有字段可选，只有 pid / sessionId 必需）；无 hostSessionId → 别名 `sid:` / `proc:`、key 用 `t:`。fixture 测试：EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles、terminalResumeInANewProcessGivesTheSameBuddyBack；IdentityTests 的终端用例；RegistryTests › entrypointMapsToOrigin（cli → 终端）、missingFieldsAreOptionalButPidAndSessionIdAreRequired；SpecTraceCoreTests › desktopAndTerminalSessionsAreDrivenByTheSameHookStream（没有 hostSessionId 的会话喂同一串 hook，动作时间线和桌面会话逐步相同）。已记录在 DESIGN.md 第 10 节「已知限制」和 Core/README.md「已知限制」 |
| 5.4-36 | 「你跳转到这个会话」→ 清掉未读 | 「跳转」是用户点了小人 / 菜单 / 通知之后 `JumpService.jump` 真的去打开 Claude（深链）或激活终端；在测试里触发它会真的弹出用户的 Claude / 终端窗口，测试进程也没有 GUI 授权（DESIGN.md 第 10 节） | 引擎层的 `markSeen(key:)` 清未读有断言（EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents、StoreTests › markSeenAndRerollAreSafeFromAnyThread、StateRuleTests › f2_unreadClearsInExactlyThreeWays）；应用层接线读代码：App/AppModel.swift `jump(snapshot:)` 在 `JumpService.shared.jump(to:)` 之后调用 `provider.markSeen(key:)`；反例有测试（AppModelTests › clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal：悬空座位 / 演示模式的点击不跳、不清未读）。深链本身的真实行为见 DESIGN.md 第 8 节「深链跳转」（发出且没被判失败，前台切换没法看） |

## 遗留缺口

（写测试时发现的、实现和任务书不一致、而且**没有**在 DESIGN.md 里记为偏离的问题。按要求没有改产品代码，留给主线程处理。两条：G-1（SP-06）、G-2（C-032）定稿之后都已经被主线程修掉，这一节只作记录，没有遗留。）

### G-1 [低，定稿期间发现、之后已修：`QA/issues-stage.md` SP-06] 某个 buddy 正在「错开」等待应用变化时，到来的等待类状态晚到，还会先闪一帧过期的旧动作
- **对应任务书**：5.6「等待类状态到来时，最多等当前过渡帧播完（≤ 250 ms）就立即插入」（表格 5.6-13）；第一版疑点 Q-05。
- **现象（修复前）**：同一帧里多个人变化时，第 k 个人的变化被错开成「晚 min(0.6, 0.09 × k) 秒才应用」。如果这个人在这段推迟期间又变成等待类（等批准 / 提问 / 计划待审），`VisualDirector.update` 里 `if let pd = pending[s.key]` 那一支仍按「没到点就沿用旧快照」处理：表演者一直显示推迟之前的旧动作，到点那一帧套用的是推迟开始时存下的**过期**快照（不是等待态），下一帧才切到等待。所以等待类晚到最多 0.6 秒，并且中间闪一帧过期的旧动作。
- **复现**：`SpecTraceStageTests › aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately`（10 个人 2.0 秒同一帧 Read → Edit，第 10 个人被推迟到 2.6 秒；2.1 秒他变成 waitingApproval）。修复前实测：等待态 0.567 秒之后才显示（期望 ≤ 0.25 秒），中间有 1 帧显示的是过期的 Edit。
- **期望**：等待类到来时立刻清掉这个人的 pending、直接套用最新快照（`needsUser` 的状态不该被错开也不该被旧 pending 拦住）。
- **处理结果**：**已修**（SP-06）：`Sources/BuddyStage/VisualDirector.swift` `update` 里等待类快照到来时先 `pending.removeValue(forKey:)`。按要求我没有改产品代码；那条测试写的时候用 `withKnownIssue` 包住两条断言（套件是绿的，修好之后 `withKnownIssue` 会变红提醒去掉包装），修好之后包装已去掉，现在两条断言都是普通断言，整套通过。所以这条**不再是遗留**，只作记录。

### G-2 [低，不影响任何一行的状态；定稿之后已修：`QA/issues-core.md` C-032] 应用层 `JumpService.DesktopMeta` 直接用 `FileManager` 读桌面元数据，绕开 `FileIO`
- **对应**：第一版疑点 Q-11、`QA/issues-core.md` C-032、`QA/issues-app.md` A-014（只修了一半：加了 1 秒缓存、一次遍历读全部 lastFocusedAt，没改成走 `FileIO`，点击时那一次读仍在主线程）。
- **现象**：`App/JumpService.swift` 的 `DesktopMeta` 用 `FileManager.default.contents(atPath:)` 读 `local_*.json`（每个约 20 KB）。它只读这一类文件、不会碰 `.key` / `.sock`，所以不违反 4.6 的任何一条；但「`FileIO` 是唯一入口」的约定（`SourceAuditCoreTests › fileReadsGoThroughFileIOWithAShortReviewedAllowlist`）只审计了数据层 / 表现层 / 工具，应用层这一处不在审计范围里。
- **期望**：改用 BuddyCore 里已有的 `DesktopMetaReader`（带签名缓存和 FileIO 保险），或者在应用层的源码审计里把这一处列进白名单并写明理由。
- **处理结果**：**已修**（C-032，主线程接手）：`DesktopMeta` 读目录 / 读文件改走 `FileIO.listDirectory / readAll`（回归测试 `Tests/BuddyOfficeTests/DesktopMetaFileIOTests`：指向 `.key` 的符号链接诱饵不会被打开，修复前失败）；1 秒缓存和读盘次数的测试见 A-014（`CachesTests`）。点击时那一次读仍在主线程（3–8 ms 量级），作为 P3 接受（QA/REPORT.md 第 8 节）。所以这条也**不再是遗留**。

## 原疑点 Q-xx 的最终结论

| 编号 | 位置（第一版） | 最终结论 | 依据 |
|---|---|---|---|
| Q-01 | `SessionEngine.transition`：busy → idle 时先写 `turnEnd = .finished`，被打断的一轮会先闪 0.4 秒「做完了」并触发「做完了」提醒 | **已修**（L-001）：证据不够时先置 `.none`，证据够了同一次 update 里定下来 | StateRuleTests › e2_hookInferredInterruptNeverShowsFinished、e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst（修复前失败的记录见 QA/issues-logic.md L-001） |
| Q-02 | `OfficeScene.render`：`seatedAt` 从不清除，同一个 key 第二次回来时座位上已经坐着人、门口又走进来一个 | **已修**（A-008）：离场的人从 `seatedAt` / `lastApp` 里清掉 | AppLayerFixTests › aSessionThatComesBackWalksInAgainInsteadOfSittingDownAtOnce、departedSessionsAreForgottenByTheScene（表 5.5-19） |
| Q-03 | `AppModel.refreshDerived`：`dormant.max` 调小时留下的是座位号小的，不是最近活动的 | **已修**（A-004）：`AppModel.derive` 留下 `away.since` 最晚的几个，仍按座位号排 | SpecTraceAppTests › shrinkingTheDormantLimitKeepsTheMostRecentlyActiveSeats（这次新增）；SettingsTests › deriveNeverTrapsWhateverTheDormantMaxIs（不崩） |
| Q-04 | `AlertCoordinator.observe` 等待分支的三处 `continue` 跳过后面的记账 | **已修**（B-001 / A-022）：逐个快照的记账挪到循环最前面 | AlertCoordinatorTests › waitingBranchNeverSkipsThePerSnapshotBookkeeping（特征测试）、bookkeepingDoesNotGrowWithEverySessionEverSeen |
| Q-05 | `VisualDirector.update`：正在「错开」时变成等待类，套用的是过期快照，等待类晚到 | **已修**（SP-06）：定稿时我用测试确认了它（晚到 0.567 秒、闪一帧旧动作）并先记成遗留缺口 G-1；之后产品代码修好（等待类到来时先清掉这个人的 pending），测试去掉 `withKnownIssue`，现在是普通断言 | SpecTraceStageTests › aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately；QA/issues-stage.md SP-06 |
| Q-06 | `hookActive` 的 15 秒掉线判据：没有工具的长时间生成结束时，会话记录先于 Stop 落盘，`hookActive` 短暂为 false，「登记表翻 idle 又没有 Stop」时 `classify` 会把本该是「被打断」的一轮判成「做完了」 | **不是问题（已知的窄路径）**：所有打断形态（用户行 `[Request interrupted by user`、`isAbortedMidStream`）都有会话记录证据，`classify` 先检查它们、再走「hook 推断」；只剩「没有 Stop、没有任何打断证据、hook 又显得掉线」这条极窄的路径。晚于 0.4 秒宽限期才落盘的证据不会回头改判，是已记录的剩余风险（QA/issues-logic.md 第 9 节 1）。这条启发式本身已补记进 DESIGN.md §13 | QA/issues-logic.md N-6；StateRuleTests › e2_hookInferredInterruptNeverShowsFinished / e3_withoutHooksTheEndOfATurnIsFinishedNotInterrupted；HookDropoutTests |
| Q-07 | 姿势 1.5 秒最短停留可能把懒腰截短 / 跳过 | **不是问题**：上一个姿势最迟也是结束那一刻换的，所以最晚在结束后 1.5 秒起播，懒腰整整 1.2 秒都在，随后靠回椅背 | SpecTraceStageTests › theStretchIsNotSkippedWhenThePoseJustChanged、finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack |
| Q-08 | 登记表「最多 5 次」按共 5 次读实现，还是 5 次重试（共 6 次读） | **转成偏离**（已在 DESIGN.md §13「仍然存在的简化 / 偏离」记录：按共 5 次读理解，两种读法在实践中没有区别）→ 表 4.1-06 | RegistryTests › halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms |
| Q-09 | token 计入判据用顶层 `type == "assistant"`，用量表用 `message.role` | **不是问题**：真实数据里 5372 行带 usage 的行（4 个活会话）两个判据 0 行不一致 | QA/issues-logic.md N-1；StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree（两个判据都实现并报出不一致的行数） |
| Q-10 | `FileIO` 的「绝不打开 .key / .sock」保险只按路径名判断，可以被符号链接 / 大小写 / NUL 绕过 | **已修**（C-007）：不区分大小写、拒 NUL、按真实路径判断、打开后再核对 fd、只开普通文件 | FuzzRegressionTests › c007_symlinkToKeyFileIsRefused、c007_caseVariantsNulAndDotDotAreForbidden；FuzzSecurityTests › fuzz_variantsNeverOpenForbiddenFiles；唯一挡不住的是硬链接（QA/issues-core.md 第 6 节：攻击者已经能读 key，只作记录） |
| Q-11 | 应用层 `JumpService.DesktopMeta` 直接用 `FileManager` 读全部桌面元数据，绕开 `FileIO`，点击时在主线程读 | **已修**（C-032）：转成遗留缺口 G-2 之后，主线程把读目录 / 读文件改成走 `FileIO`（`DesktopMetaFileIOTests`）；A-014 的缓存已修；点击时那一次读仍在主线程，P3 接受 | QA/issues-app.md A-014；QA/issues-core.md C-032 |
| Q-12 | `--test-jump` 的调试日志会写会话标题 | **已修**（A-015）：改成只写标题的字数（`DebugTools.titleForLog`），默认路径 `~/Library/Logs/BuddyOffice/debug.log`（0600、轮转），发布版默认什么都不写 | DebugLogTests › sessionTitlesNeverGoIntoTheLog、noDebugLogCallInterpolatesASessionTitle |
| Q-13 | Q-01 修复之后，宽限期（≤ 0.4 秒）内动作是 `.idle`，舞台会先切到空闲桌面再切到「做完了 / 被打断」 | **不是问题（已知取舍）**：正常流程 Stop 比登记表翻 idle 早 40–60 ms，分类在同一次 update 里完成、不经过宽限期；只有「没有 Stop」的少见路径才会有最长 0.4 秒的空闲，比原来先闪绿色 ✓ 好 | QA/issues-logic.md L-001 残留；StateRuleTests › e2_hookInferredInterruptNeverShowsFinished / e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst |

## 新增测试与变异验证

每个新测试都要过一关：把产品代码里它钉住的那个数字 / 行为改错一点，测试必须变红。做法：

- 在**私有副本**里做（`scripts/dev.sh` 的 `BUDDY_PKG` 指向一份拷贝，构建目录也是自己的），真实源码树一个字节都没动；
- 每次只改一处（替换的旧片段必须在文件里恰好出现一次，否则跳过），构建并只跑对应包里的 `SpecTrace*` 套件，跑完立刻还原；
- 先确认两个包的基线都是全绿，再逐个变异：**共 47 个变异（数据层 26 个、表现层 21 个），47 个都被新测试抓到（变红），0 个存活，0 个编译失败**。

| # | 改的文件 | 改了什么 | 结果 | 变红的新测试（对应表里的编号） |
|---|---|---|---|---|
| C1 | `Sources/BuddyCore/Ingest/TokenLedger.swift` | 账本写盘间隔 30→60 s | 变红（KILLED） | 4.3-40 |
| C2 | `Sources/BuddyCore/Ingest/TokenLedger.swift` | 去掉字节预过滤 | 变红（KILLED） | 4.3-36 |
| C3 | `Sources/BuddyCore/Ingest/TokenLedger.swift` | 扫描队列 background→utility | 变红（KILLED） | 4.3-43、4.3-42 |
| C4 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | turn_duration 不再修正用时 | 变红（KILLED） | 4.3-17、4.3-41 |
| C5 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 退出时不写盘 | 变红（KILLED） | 4.3-41 |
| C6 | `Sources/BuddyCore/Fusion/ToolCatalog.swift` | LS 不再是 search | 变红（KILLED） | 5.7 |
| C7 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 下班工位启动窗口 3h→2h | 变红（KILLED） | 5.5-13 |
| C8 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 超出 4 个时移走最新的（反了） | 变红（KILLED） | 5.5-15 |
| C9 | `Sources/BuddyCore/Fusion/ActivityResolver.swift` | 有重试时压缩不显示（顺序变成重试 > 压缩） | 变红（KILLED） | 5.4-20 |
| C10 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 规则 1 忽略临时 busy | 变红（KILLED） | 5.3-02 |
| C11 | `Sources/BuddyCore/Ingest/TranscriptLine.swift` | Glob 不取 pattern | 变红（KILLED） | 4.2 |
| C12 | `Sources/BuddyCore/Ingest/JSONLTailer.swift` | 读块 1 MiB→512 KiB | 变红（KILLED） | 4.3-04 |
| C13 | `Sources/BuddyCore/Ingest/DesktopMetaReader.swift` | 桌面元数据不读 originCwd | 变红（KILLED） | 4.4-03/04/05 |
| C14 | `Sources/BuddyCore/Ingest/LineSanitizer.swift` | SessionEnd 事件名写错 | 变红（KILLED） | 4.2-04 |
| C15 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 退出时往 ~/.claude 里写一个文件 | 变红（KILLED） | 4.6-05/06、4.6-04/05/06 |
| C16 | `Sources/BuddyCore/Ingest/RegistryScanner.swift` | 登记表不读 pidDomain | 变红（KILLED） | 4.1-13 |
| C17 | `Sources/BuddyCore/Ingest/LineSanitizer.swift` | UserPromptSubmit 的 extra 不再丢 | 变红（KILLED） | 4.2 |
| C18 | `Sources/BuddyCore/Fusion/ActivityResolver.swift` | 去掉临时修正 2（Stop 先到） | 变红（KILLED） | 4.1-28 |
| C19 | `Sources/BuddyCore/Ingest/TranscriptReader.swift` | 找会话记录时跳过以 - 开头的目录 | 变红（KILLED） | 5.3-02、5.3-10、4.3-02、4.3-17、4.3-41 |
| C20 | `Sources/BuddyCore/Fusion/SessionEngine.swift` | 桌面会话不用 hook | 变红（KILLED） | 5.3-10、4.2-17、4.1-28 |
| C21 | `Sources/BuddyCore/Ingest/TokenLedger.swift` | 扫描里加一个并发原语（静态断言应该抓到） | 变红（KILLED） | 4.3-43 |
| C24 | `Sources/BuddyCore/Fusion/ToolTracker.swift` | 轮次边界不关任何主线程调用 | 变红（KILLED） | 5.3-10、4.2-04 |
| C25 | `Package.swift` | Package.swift 里加一个第三方依赖 | 变红（KILLED） | 4.6-12 |
| C26 | `Sources/BuddyCore/Util/Hashing.swift` | 引入不在白名单里的系统框架 | 变红（KILLED） | 4.6-12 |
| C27 | `Sources/BuddyCore/Util/Hashing.swift` | 在别处偷偷加一个写文件的调用 | 变红（KILLED） | 4.6-05/06 |
| C28 | `Sources/BuddyCore/Util/Hashing.swift` | 代码里出现旧笔记路径 | 变红（KILLED） | 4.0-02 |
| S1 | `Sources/BuddyStage/Performer.swift` | 姿势停留 1.5→2.0 | 变红（KILLED） | 5.6-06/07/08、5.6-19、5.6-18/19/20 |
| S2 | `Sources/BuddyStage/Performer.swift` | 等待结束后面向你 1.5→1.0 | 变红（KILLED） | 5.6-05 |
| S3 | `Sources/BuddyStage/VisualDirector.swift` | 错开上限 0.6→0.9 | 变红（KILLED） | 5.6-23 |
| S4 | `Sources/BuddyStage/Performer.swift` | Bash 往后靠 8→6 秒 | 变红（KILLED） | 5.6-14/15/16/17 |
| S5 | `Sources/BuddyStage/Performer.swift` | 做完先等 0.4→0.3 | 变红（KILLED） | 5.6-18/19/20 |
| S6 | `Sources/BuddyStage/PoseLibrary.swift` | 懒腰 1.2→1.5 秒 | 变红（KILLED） | 5.6-18/19/20 |
| S7 | `Sources/BuddyStage/Walkers.swift` | 起身 0.3→0.4 | 变红（KILLED） | 5.5-05 |
| S8 | `Sources/BuddyStage/Walkers.swift` | 进场 2.5→3.0 秒 | 变红（KILLED） | 5.5-21 |
| S9 | `Sources/BuddyStage/PlateCopy.swift` | 桌牌里也显示 status_detail | 变红（KILLED） | 4.4-08 |
| S10 | `Sources/BuddyStage/OfficeScene.swift` | 下班工位显示器没关 | 变红（KILLED） | 5.5-07 |
| S11 | `Sources/BuddyStage/Performer.swift` | 等待 0.4→0.6 秒才转身 | 变红（KILLED） | 5.6-13、5.6-05 |
| S12 | `Sources/BuddyStage/Performer.swift` | 屏幕停留 0.8→1.0 | 变红（KILLED） | 5.6-06/07/08 |
| S13 | `Sources/BuddyStage/Performer.swift` | 桌牌停留 1.0→1.2 | 变红（KILLED） | 5.6-06/07/08 |
| S14 | `Sources/BuddyStage/Performer.swift` | 深度思考 20→25 秒 | 变红（KILLED） | 5.6-14/15/16/17 |
| S15 | `Sources/BuddyStage/Performer.swift` | Web 往后靠 8→10 秒 | 变红（KILLED） | 5.6-14/15/16/17 |
| S16 | `Sources/BuddyStage/Performer.swift` | 等待类永远不转身（time>100 才转） | 变红（KILLED） | 5.6-13、5.6-05 |
| S17 | `Sources/BuddyStage/Performer.swift` | 屏幕没有最短停留（中间态不再被跳过） | 变红（KILLED） | 5.6-09、5.6-06/07/08 |
| S18 | `Sources/BuddyStage/Performer.swift` | Glob 的姿势和 Grep 不同（同类切换也换姿势） | 变红（KILLED） | 5.6-10 |
| S19 | `Sources/BuddyStage/Performer.swift` | 等待类的屏幕也要等最短停留 | 变红（KILLED） | 5.6-13 |
| S20 | `Sources/BuddyStage/Performer.swift` | 懒腰目标窗口缩短（姿势刚换过时被跳过） | 变红（KILLED） | 5.6-18/19/20、5.6-19 |
| S21 | `Sources/BuddyStage/PlateCopy.swift` | 表现层别处也读 statusDetail | 变红（KILLED） | 4.4-08 |

（编号 C22、C23 空缺：早期草稿里的两个变异后来合并进了别的编号。变异脚本和逐个的构建日志在临时目录里，没有放进仓库。）

