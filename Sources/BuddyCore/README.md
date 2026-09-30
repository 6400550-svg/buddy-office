# BuddyCore（M1：数据层 + 状态机）

只依赖 Foundation / Darwin / CoreServices(FSEvents)，**纯本机、只读、不联网**。把这台 Mac 上活着的 Claude Code 会话
（桌面 App / 终端 / VS Code）读成 `[BuddySnapshot]` + 一次性的 `BuddyEvent`，交给表现层。

```
Sources/BuddyCore
├─ Paths.swift                 所有路径集中在这里，可整体换根（--data-root）
├─ Model/                      合同：Activity / BuddySnapshot / SnapshotProvider（未改名、未删任何已有成员）
├─ Ingest/                     数据源读取（都是"只读 + 增量"）
│  ├─ FileWatcher              FSEvents（~/.claude 递归 + claude-code-sessions），事件按路径过滤
│  ├─ JSONLTailer              pread 1 MiB + memchr；半行 / 截断 / 轮转 / >4 MiB 行
│  ├─ LineSanitizer            一行字节 → 干净字符串；hook 行的 JSON→正则降级解析
│  ├─ RegistryScanner          ~/.claude/sessions/<pid>.json（只碰 ^\d+\.json$，绝不碰 .key）
│  ├─ ProcessProbe             kill(pid,0) + sysctl(KERN_PROC_PID)；协议 + 假实现，可注入
│  ├─ HookLogReader            ccmon 事件文件，按 sessionId 拼文件名，绝不扫描目录
│  ├─ TranscriptLine/Reader    会话记录：尾部窗口 + 增量；只留事实，不留对话内容
│  ├─ TokenLedger              用量表算法的 Swift 移植 + ledger.json 断点
│  ├─ SubagentReader           subagents/agent-*.jsonl(+workflows/wf_*/) 与 .meta.json
│  └─ DesktopMetaReader        claude-code-sessions/<acct>/<org>/local_*.json
├─ Fusion/
│  ├─ ToolTracker              悬空 / 并行 / 批次 / 轮次边界 / 30 分钟兜底
│  ├─ HelperAttributor         hook 里没有 agent_id：子代理事件归属（4 条规则 + 400 ms 扣留）
│  ├─ SessionSignals + ActivityResolver   纯函数：resolve(signals, now) → Activity
│  ├─ IdentityResolver         key / 别名 / 工位 / 外观盐，identities.json 保留 7 天
│  ├─ SessionEngine            把上面全部串起来。无线程、无定时器：poll() → 快照 + 事件 + nextWake
│  ├─ SessionStore             真实的 SnapshotProvider：ingest 串行队列 + FSEvents/轮询 + 20 Hz 限速 + 1 Hz 心跳
│  └─ ToolCatalog / BuddyState
├─ Tools/
│  ├─ DumpCommand              runDumpCommand（buddydump / buddyctl dump）
│  ├─ ReplayCommand            runReplayCommand（buddyctl replay）
│  └─ FakeTree                 假 home 树 + 虚拟时钟 + 会话记录行构造器（replay 和测试共用）
└─ Util/  FileIO（所有读文件的唯一入口）/ TimeUtil / Hashing
```

## 怎么用

```swift
// App 里：真实数据，回调在主线程
let store = SessionStore(dataRoot: nil /* 或 --data-root 的目录 */, usePolling: false)
store.onUpdate = { snapshots in … }        // 最多 20 Hz，另有每秒 1 次心跳
store.onEvent  = { event in … }            // 进场/离场/一轮开始/一轮结束/开始等你/不再等你/blocked
store.start()                              // stop() 时会把身份和 token 账本写盘
```

需要更细的控制（注入时钟、假进程探测、关掉 token 统计、回调队列）用
`SessionStore(options: SessionStore.Options(engine: SessionEngine.Options(paths:now:probe:)))`。

命令行：

```
buddydump [--once|--watch] [--poll] [--data-root DIR] [--no-tokens] [--json] [--persist] [--quiet] [--audit-opens 秒数]
buddydump replay --root <空目录> [--fsevents] [--latency N] [--keep] [--verbose] [--continue]
```

* `buddyctl dump` / `buddyctl replay` 直接转发 `runDumpCommand(arguments:)` / `runReplayCommand(arguments:)`。
* `--poll`：纯轮询，沙箱里用（FSEvents 在沙箱里起不来，会自动退回轮询并在诊断里写明）。
* `buddydump` 默认**不写** identities.json / ledger.json（`--persist` 才写），免得干扰真正的 App。
* `buddydump --audit-opens 60`（QA 加的）：只读地把数据层（和 App 同一条链路）跑 60 秒，按类别汇总一共打开过哪些文件（只列类别和个数，不列文件名），确认没有打开过密钥文件 / socket、保险一次都没拒绝过；有问题时退出码 1。可以直接对着真实的 `~/.claude` 跑。
* 构建 / 测试：`BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-core scripts/dev.sh build|test`
  （`swift build/test` 要在沙箱外跑；产出的 buddydump 可以在沙箱里跑。）

## 数据源实测结论（和任务书不一致的地方加粗）

**时序（这台机器上的实测，2.1.284）**

* **Stop 事件比登记表翻成 idle 早 40–60 ms**（实测 −56 / −37 ms），不是任务书暗示的"hook 往往更快，但登记表可能先 idle"。
  原因：Stop hook 是同步的，CLI 等它跑完才算结束。所以"登记表还是 busy 但 Stop 更新"这个 5.1 的临时修正才是常态路径；
  反过来"登记表 idle 但 UserPromptSubmit 更新"几乎不会触发（**登记表 busy 比 UserPromptSubmit 早 0.09–0.5 秒**，实测 88 ms / 496 ms）。
* **SubagentStop 在 Stop 之后约 7.1–7.6 秒**才出现（那是桌面 App 生成"本轮总结"的内部代理），所以桌面 `postTurnSummary`
  大约在一轮结束后 7 秒才落盘 —— **比任务书 7.2 里"最多等 4 秒"长**。数据层没有等待逻辑：`blocked` 标记/事件在元数据一更新就给出，
  App 层如果要"做完通知等总结"，等 8 秒左右才够。SubagentStop 只当"总结已生成"的提示：让下一次 poll 立刻重读桌面元数据。
* permission / AskUserQuestion 的 Notification 比 Pre 晚约 **6 秒**（所以等批准靠登记表，不靠 Notification；Notification 只用来点名工具）。
  **AskUserQuestion / ExitPlanMode 的 Notification 文本也是 "needs your permission to use X"**，所以 `waitingFor` 之外还要看打开的工具名
  （ExitPlanMode 开着 → 计划待审；AskUserQuestion 开着 → 提问），而不是只看文本里有没有 "permission"。
* hook 写盘延迟 4–10 ms；子代理会话记录里 tool_use 行比 hook 的 Pre 晚约 60 ms（所以归属规则 3 的 400 ms 扣留窗口够用）。

**会话记录**

* 主会话记录是**整条消息写完才落盘**（同一条消息的所有行 stop_reason 都是最终值；只有被打断的消息才是 `null`，最后一行带
  `isAbortedMidStream`）。**子代理记录是按 block 实时写的，中间行的 `stop_reason` 全是 null** —— 所以"stop_reason 为 null = 被打断"
  只对主会话成立；子代理的 done 只看"最后一条 assistant 是 end_turn 且没有未完成的工具"。
* 打断有两种形状：用户行 `[Request interrupted by user…]`（含 `… for tool use]`，内容可能是字符串或 text 数组），
  和 assistant 行 `isAbortedMidStream`。另外还有第三种（hook 推断）：hook 正常工作、busy→idle 时没有 Stop。
* 合成行：`<synthetic>`。`isApiErrorMessage: true` 才是错误；打断之后的 "No response requested."（stop_sequence）不是。
* 整个历史里 `system` 子类型只有 stop_hook_summary / api_error / turn_duration / local_command / informational；
  **compact_boundary 从没出现过**（和 PreCompact/PostCompact 一样，只能用合成 fixture 测）。
* `assistant.message.usage` 有大量重复行；resume 会复制历史（实测 1 条跨文件重复的 message.id，用量表全局去重，我们也是）。

**子代理**

* 目录里除了 `agent-<hex>.jsonl/.meta.json`，工作流的子代理在 `subagents/workflows/wf_*/agent-*.jsonl`（同目录有 journal.jsonl，不算）。
  meta 的 `requestShape` 可能缺（老版本）→ 按前台算；工作流子代理的 `requestShape` 是 foreground，但 `Workflow` 工具本身立刻返回。
* 后台 `Agent` 的 Pre→Post 只有 ~100 ms；前台 Agent 一直开到子代理结束。

**tool 名字 / 别的**

* `TaskStop` / `TaskOutput` 是 KillShell / BashOutput 的新名字，已加进 `ToolCatalog`（归 bash）。`AskUserQuestion`、`StructuredOutput` 归 unknown。
* hook.sh 的 detail 是**转义后的原文**按字符截断（不是按解析后的字符）：所以带引号 / 换行的命令，hook 的 detail 比会话记录里的短，
  归属比对用"前缀 + 去掉 `…`/U+FFFD"，不能用相等。
* `URL.resolvingSymlinksInPath()` 会把 `/private` 前缀去掉，而 FSEvents 报的是 `/private/var/…`：路径用 `realpath`（`FileWatcher.resolved`）。
* 沙箱里 `NSTemporaryDirectory()` 不可写，要用环境变量 `TMPDIR`（`FileIO.temporaryDirectory`）。
* 桌面元数据文件约 20 KB（`remoteMcpServersConfig` 很大），只在签名变化时重读。

**0.25 秒批次规则的真实表现**（对照会话记录里"同一条 assistant 消息里的 tool_use"，1138 对相邻 Pre）：
从不把不同消息的调用并成一批（0 次），但 231 对同一消息里的调用被拆开（串行执行的非只读工具，最长相隔 67 秒）。
拆开的害处很小：前一个若还开着会被"取代"关掉，只影响"×N"的个数。
在没有子代理的会话上跑了整套 ToolTracker 规则：1980 个 Pre → 1871 个被 Post 关、102 个被下一批取代（悬空）、7 个被轮次边界关、
文件末尾 0 个残留；30 个 Post 找不到对应（多是被提前取代的 WebFetch）；Notification 点名的工具 = 当时最新打开的工具，18/18。

## 我做的小决定（任务书没覆盖 / 需要取舍的）

* **登记表**：`kind` 缺省当 interactive；`pid` 或 `sessionId` 缺失的记录忽略；不认识的 `status` 值 → nil（记录保留，靠 hook 推断阶段）。
  目录列表按目录签名缓存（登记文件是原地重写，所以每个文件仍然每次 stat），每 2 秒强制重列一次。
* **离场检测**：进程存活每 1 秒检查一次（缓存），记录消失是立刻的；PID 被复用 / 进程死了但文件还在，最坏 1 秒 + 3 秒防抖。
* **`hookActive`**：`ts ≥ startedAt − 5s` 的事件存在，**并且** hook 没有比会话记录落后 15 秒以上（用户中途卸掉 ccmon 时，
  hook 安静而会话记录还在长 → 当作 hook 掉线，退回用会话记录里没有 tool_result 的 tool_use 判断工具）。
* **出错（errored）**：一直保持到开始打盹（10 分钟），且优先于"做完了"（任务书 5.4 的顺序会让出错的一轮先闪 5 秒绿色的"做完了"）。
* **`TurnEndKind.none`**：刚进场的新会话、或启动时找不到"一轮刚结束"的证据的 idle 会话，动作直接是"空闲"，不显示"做完了"。
* **被打断的 hook 推断**：busy→idle 后等 0.4 秒（`stopGrace`）没有 Stop 才判为被打断（实测 Stop 总是先到）；
  被自己打断的不亮未读；正常做完和出错亮未读。
* **压缩**：PreCompact 无 PostCompact → 整理上下文（15 分钟没有 PostCompact 就不再显示）；`SessionStart source=compact` 也当 PostCompact；
  会话记录里 compact_boundary 之后 120 秒内没有新的 assistant/user 行 → 整理上下文（**没有真实数据，只用合成 fixture 测**）。
* **等批准的工具**：Notification 点了名就取名字对得上的那个打开的调用（并行时不会张冠李戴），否则最新打开的，再否则从 Notification 文本里解析 `use <T>`。
* **ToolTracker**：会话记录的 `stop_hook_summary` 边界只关"在它之前开始"的调用（会话记录写盘有延迟，别把新开的误关）；
  helper 名下的记录只做配对，超过 30 分钟一律丢；AskUserQuestion 的 detail 在解析和追踪两层都置空。
* **子代理**：目录列表间隔——会话在忙 / 有小助手时 0.15 秒，闲着 1 秒；发现时修改时间早于 10 分钟（真实时钟）的文件直接当"早就结束"，不读内容；
  完成后继续报告 30 秒（给表现层留"小助手离开"的时间）；没完成但 90 秒没动静的不再报告。
* **turnStartedAt**：取"登记表变 busy / hook 的 UserPromptSubmit / 会话记录里的用户输入"里最早的一个（都必须比上一轮结束的证据晚），
  App 中途启动接手一个正在跑的会话也能给出正确的"本轮已工作多久"。
* **桌面 blocked / statusDetail**：一轮开始时记下当时的 `postTurnSummaryFor` 并压住它，之后只有新的总结才算数（元数据里旧总结的 uuid 还等于 lastAssistantUuid 的那几百毫秒里不会误亮）。
* **下班工位**：启动时取 `lastActivityAt` 3 小时内、没归档、没有活进程的桌面会话，最多 4 个（含运行中离场的）；满 12 小时 / 归档 / 元数据被删移除；
  下班工位也会算 token；启动时的下班工位不发事件。
* **身份**：别名里 host 全留、sid 留最近 30 个、proc 留最近 4 个（proc 别名不能被一堆新 sid 别名挤掉，否则同一进程的下一次 /clear 认不出来）；
  没有 procStart 的记录不建 proc 别名；启动时压缩工位（按上次的顺序重新从 0 编号），运行中工位永远不动。
* **token**：不做 cost-state 的"后台调用补差"（用量表会补；实时会话没有 cost-state，历史会话差额很小）。
  有 prior 会话的分组（桌面会话 resume 过）每次启动都重扫，保证跨文件去重准确；单文件分组用账本断点，账本里存了最近 24 条消息，跨断点的同一条消息的后续行也能去重。
  账本里已不存在的文件在写盘时丢掉。
* **SessionStore**：文件事件触发的 poll 之间至少隔 40 ms；纯轮询模式有会话在忙时 50 ms、全部空闲时 100 ms；
  FSEvents 模式兜底每秒一次；引擎给出 `nextWake`，"被打断 3 秒 / 做完 5 秒 / 防抖 3 秒 / 打盹 10 分钟"这些时间点是准点醒来的，不等心跳。
* **JSONLTailer 读缓冲**按每次要读的量分配、读完就释放（几十个文件同时跟踪也不会各占 1 MiB）。
* **`FileIO`** 是所有读文件的唯一入口：拒绝 `*.key` / `*.sock` / `cc-socks`（保险），并给测试留了 `openObserver`。

## 已知限制

* **没有碰到活着的终端会话**：终端 / VS Code 路径（没有 hostSessionId、`/clear`、`--resume`、`dialog open` / `goal proposal` / `worker request` /
  `sandbox request` 等待、`turn_duration`）只靠 fixture 测；真实终端会话的登记表字段没核对过。
* **没有碰到真实的"等批准"**（本会话是 bypassPermissions，别的会话此刻都不在等）：用合成数据测，并用历史 hook 日志验证了
  "Notification 点名的工具 = 最新打开的工具"（18/18）。登记表里 `waiting` 期间 waitingFor 的真实取值只按任务书。
* PreCompact / PostCompact / compact_boundary 没有任何真实样本（见上）。
* 归属规则（hook 里没有 agent_id）本质上是猜：判错只影响主 buddy，到下一个轮次边界纠正。
  0.25 秒批次规则会把同一条消息里相隔更久的调用当成新批次（见上），前一个还开着会被提前关掉。
* 主会话记录写盘可能延迟（老版本最多 33 秒）：没有 hook 时，工具显示会滞后。
* FSEvents 在沙箱里起不来（自动退回轮询）；沙箱外的 FSEvents 行为用 `swift test` 里的 StoreTests / ReplayTests(--fsevents) 验证。
* 时间相关字段用注入的时钟；文件修改时间只用来做启动时的粗判断（"太旧的子代理文件不读"、账本断点），其余全用内容里的时间戳，
  所以虚拟时钟下的测试是确定的。

## 真实数据核对（这台 Mac，4 个活着的桌面会话）

* 登记表：4 个 `[0-9]*.json`（`.key` 文件一次没碰，测试里用 `FileIO.openObserver` 断言过）；字段与任务书一致；`procStart`
  与 `sysctl` 的 `p_starttime` 一致（04:03:17 UTC）；`kill(pid,0)` 在沙箱里对别人的进程给 EPERM（按存活算），`sysctl` 在这个沙箱里能用。
* buddydump 与真实状态一致：忙碌的桌面会话（本会话 busy、主线程"思考中"、我这个后台小助手的 Bash 归在小助手名下，
  主线程自己的 Bash 归在主线程；4 个活跃小助手）、空闲 10 分钟→打盹、45 分钟→睡着、进程被回收后的会话是"下班"。
  标题（登记表 name）、status、hook 事件数 / 最后事件时间、桌面总结 status_detail 都对得上。
* **token 与用量表一致到个位数**：4 个活会话 + 1 个 44 MB 的历史会话 + 一个带 prior 的桌面会话（1,192,157 = 两个文件合计，重叠那条消息只算一次）。
  对照的是用量表 `parse_line` + 全局 message.id 去重（不含 cost-state），输入 / 输出 / 缓存写 / 缓存读四项分别相等，消息条数也相等。
  本会话（主会话 + 子代理，122,537,688）在它还在增长的时候两边读到同一个数。
* 标题优先级链、下班工位的 token（含 prior 合并）、`desktopMeta` 的 `lastFocusedAt` 清未读，都有测试。

## 性能（release 构建，6 个 buddy，FSEvents 模式在沙箱外量的）

| 项目 | 目标 | 实测 |
|---|---|---|
| RSS | ≤ 80 MB | 6–9 MB（真实数据启动时扫 40+ MB 记录的峰值 21 MB；6 个忙会话持续 4 分钟后仍是 8 MB，没有增长） |
| CPU，全部空闲 | ≤ 1% | **0.10%**（6 个空闲 buddy；真实数据静止时 ≈0%；纯轮询 100 ms 兜底：0.8%） |
| CPU，6 个都在忙 | ≤ 3% | **1.0%**（4 分钟平均；每个会话每 0.3 秒一对 hook 事件 + 每 1.2 秒一行会话记录，比真实忙得多；前 30 秒 2.4%） |
| 登记表变化 → 快照回调 | p95 ≤ 150 ms | FSEvents：p50 14–30 ms，max 42 ms；纯轮询有会话在忙(50 ms)孤立变化：p50 9 ms，p95 53 ms，max 60 ms；纯轮询全部空闲(100 ms)时的第一次变化最多约 105 ms |
| 首次扫 44 MB 会话记录 | ≤ 2 秒，后台 | 0.34–0.47 秒（整个进程含启动）；4 个活会话共约 65 MB：1.2–1.7 秒 |
| 冷启动（不含 token） | — | 40–70 ms |

（20 Hz 限速下连续变化的步骤延迟约 50 ms 是限速造成的；上表是孤立变化的延迟。`buddydump replay --latency N` 可以复现。）

## 测试

`scripts/dev.sh test`：Swift Testing，227 个测试，约 25 秒（其中 44 MB 扫描、FSEvents、整条回放各占几秒）。覆盖：登记表（字段缺失 / 未知字段 /
非 interactive / 写到一半 / PID 被复用 / `.key` 永不被打开）、hook 日志（非法 UTF-8 / 被截断的 `\u` / 被截断的 MCP 名 / Codex 文件不被误用 /
AskUserQuestion 的 detail / 用户输入不留）、增量读取器（半行 / 缩短 / 轮转 / 超过 4 MiB / 块边界 / 多字节 / 读写竞争）、会话记录、token 去重与账本断点、
身份（prior ids / `/clear` / `--resume` / 持久化 / 7 天 / 工位）、ToolTracker、子代理归属（前台 / 后台空闲 / 后台忙碌 / 扣留 400 ms / 工作流目录）、
ActivityResolver（含 PreCompact/PostCompact、非权限类等待、不因时间判死）、引擎时间线（带时间的事件脚本）、在场 / 离场 / 下班工位、
SessionStore（线程 / 20 Hz / 心跳 / 准点唤醒 / FSEvents）、整条回放（轮询和 FSEvents 两种链路）、随机脏数据 chaos 测试。

## QA 加固（2026-09-29 的独立审查，逐条记录见 `QA/issues-core.md`）

**外部数据一律当不可信的**（登记表、hook 行、会话记录、桌面元数据、账本、身份文件都是别人写的文件，随时可能写到一半 / 写坏）。入口处统一收紧，往下的代码就不用各自防：

* **时间戳合理范围 2000-01-01 … 2200-01-01**（`TimeUtil.saneMinMs / saneMaxMs`）：hook 的 `ts`、登记表 / 元数据 / identities.json 里的毫秒数、会话记录的 ISO 时间都按这个范围检查，范围外（含 0、负数、NaN、无穷、布尔）当坏数据（hook 行被跳过，字段当作没有）。
  比"现在"晚一天以上的 hook 事件 / 会话记录行按"现在"算（一条远在未来的 Stop 会让登记表明明是 busy 的会话永远显示 idle）。`TimeUtil.millis(Date)` 是饱和的，不再 trap。
* **JSON 只走 `SafeJSON`**：先数一遍嵌套深度（> 100 层当坏数据）——`JSONSerialization` 是递归解析，GCD 工作线程只有 512 KB 栈，约 470 层嵌套的对象会直接爆栈；字符串字段有长度上限（id 200 / 标签 2048 / detail 4096，id 太长当没有，不截断）。
* **数字上限**：会话记录里的 token 计数 ≤ 2^40，账本里恢复出来的计数 ≤ 2^50（每条消息每个字段按 UInt32 存），累加和 `TokenBreakdown.total` 都是饱和加法；`turn_duration` / `api_error` 的数字超出合理范围当作没有（表现层会对它们做 `Int(秒数)` 换算）；登记表 `pid` 必须是 1…Int32.max 的整数，并且**以文件名里的 pid 为准**；`procStart` 年份 1971…9999、时分秒非负。
* **持久化文件载入有上界**：identities.json 最多 2000 个身份、每个身份别名 ≤ 40（host 6 / sid 30 / proc 4）、工位号只认 0…999（别的当作没分配）；桌面元数据的 `priorCliSessionIds` 只留最近 256 个。
* **`FileIO` 的保险绕不过去**：不区分大小写；路径里有 NUL 直接拒绝；文件存在时先 `realpath` 解析（符号链接 / 目录符号链接 / `..` 全部还原）再判断，打开之后再用 `F_GETPATH` 核对一遍；只打开普通文件（`O_NONBLOCK` + `S_ISREG`：命名管道不会把读取线程卡死在 open 上）。`Tests/BuddyCoreTests/FuzzSecurityTests.swift` 里有一个源码扫描测试，保证 FileIO.swift 之外没有任何别的 `open` / `fopen` / `FileHandle` / `Data(contentsOf:)`。
* **缓存 / 集合都有上界或清理**：`ToolTracker.open` ≤ 512；`HookLogReader` 一次 poll 最多交出最新 20000 个事件（多了就置 `reset`）；引擎每 30 秒清一次会话记录路径缓存；账本里没有 buddy 在用的文件不再被扫描，最多留 64 个，再多就把断点转存进 `ledger.json`、清出内存；`JSONLTailer` 的半行缓冲读完长行就释放。
* **其它**：`FileWatcher.resolved` 用循环而不是递归；`FileIO.writeAtomically` 的临时文件名每次不同（多线程同时写同一个文件不会互相踩）；`TokenLedger.flush()` 在扫描队列上调用也安全；文件事件按目录边界分流（`sessions-old` 不是 `sessions`）。

测试：`Tests/BuddyCoreTests/Fuzz*.swift`（确定性种子、每个用例带超时；覆盖矩阵见 `QA/issues-core.md`）。
