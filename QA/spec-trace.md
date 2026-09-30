# 规格追踪（任务书第 4、5、6.5、6.6、7 节 → 代码 + 测试）

> 任务书里每一条要求 → 现在的实现（函数名，不引行号）→ 钉住它的测试 → 状态。**状态只有三种**：`✓`（实现了，并且有测试的断言真的检查到了这条的数字 / 行为）；`偏离`（和任务书不一致而且是有意的，理由写在 DESIGN.md 里，行里引了那段话的开头）；`✓（间接验证）`（确实没法自动化测，写明原因和间接证据，汇总在文末「间接验证清单」和 REPORT.md 第 7 节）。
> 由两份定稿合成：[spec-trace-core-final.md](spec-trace-core-final.md)（第 4、5 节）+ [spec-trace-ui-final.md](spec-trace-ui-final.md)（第 6.5、6.6、7 节）；两份初稿（第一版只读追踪，里面有「✓(无专门测试)」「偏离-未记录」「缺失」这些后来都消灭了的状态）保留在 `spec-trace-core.md` / `spec-trace-ui.md`。表里不含任何对话内容。

## 总览（直接数两份追踪表的状态列）

| 部分 | 条数 | ✓ | 偏离（DESIGN.md 里有理由） | ✓（间接验证） |
|---|---|---|---|---|
| 任务书第 4、5 节（数据源、状态判定、表现层节奏） | 288 | 268 | 18 | 2 |
| 任务书 6.5 / 6.6 / 7.1–7.5（表现层动画与手感、三种形态、提醒、跳转、设置） | 267 | 210 | 35 | 22 |
| **合计** | **555** | **478** | **53** | **24** |

第一版（初稿）里的「缺失」「偏离-未记录」「✓(无专门测试)」「N/A」现在都是 0：缺的动作 / 屏幕要么补上了（`QA/issues-stage.md` 的 TA / SP 系列、`QA/issues-app.md`），要么在 DESIGN.md 里写明理由变成了「偏离」；没有测试的行要么补了测试（本轮新增 117 个追踪测试：`SpecTraceCoreTests` 27、`SpecTraceStageTests` 14、`SpecTraceAppTests` 1、`SpecTraceUITests` 两个文件共 75），要么写明间接验证的原因和证据。

## 偏离清单（53 条；理由都在 DESIGN.md，每条引用的原文开头都用脚本 grep 确认过存在）

| 编号 | 内容 | 状态（含 DESIGN.md 里的位置） |
|---|---|---|
| 4.1-06 | 4.1 原地重写 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：登记表「半截文件每隔 50 ms 重试一次，最多 5 次」按共 5 次读理解） |
| 4.1-27 | 4.1 kind | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：缺 kind 的记录按 interactive 显示） |
| 4.3-09 | 4.3 条目·assistant | 偏离（DESIGN.md §4 末段「子代理会话记录是按 block 实时写的，中间行 stop_reason 全是 null」；§13「数据层 / 状态机的偏离」：stop_reason 为 null 不一律当作被打断） |
| 4.3-33 | 4.3 token | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：不移植用量表的 cost-state「后台调用补差」） |
| 4.5-06 | 4.5 归属顺序 | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：不用 hook 的 SessionStart source=clear 佐证进程别名） |
| 5.1-05 | 5.1（任务书未写） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：登记表没有 / 不认识 status 时靠 hook 推断阶段，两个临时修正各多一个条件） |
| 5.2-15 | 5.2 轮次边界 | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：轮次边界只关「边界时刻之前或同时开始」的主线程调用，SessionEnd 也算边界） |
| 5.4-06 | 5.4 waiting（任务书未写） | 偏离（DESIGN.md §4「动作判定」waiting 条：Notification 点了名就取那个） |
| 5.4-11 | 5.4 waiting（实测） | 偏离（DESIGN.md §4 末段「实测里和任务书不一致的地方」：AskUserQuestion / ExitPlanMode 的 Notification 文本也是 permission） |
| 5.4-13 | 5.4 busy 1 | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：整理上下文：hook 已说压缩结束就不再用 compact_boundary） |
| 5.4-14 | 5.4 busy 1（任务书未写） | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：整理上下文：15 分钟 / 120 秒 / 5 秒窗口） |
| 5.4-25 | 5.4 idle 2 | 偏离（DESIGN.md §10「与任务书不一致」汇总表：桌面会话「做完了」最多等 4 s → 等 8 s；§11 提醒判定） |
| 5.4-30 | 5.4 idle | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：出错优先于做完了，并一直保持到打盹） |
| 5.4-34 | 5.4 idle 4 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」下次启动生效） |
| 5.5-21 | 5.5 进场 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：走到工位「约 2.5 秒」：路程 / 2.5 s，夹在 28–70 像素 / 秒，远座位要 3–5 秒） |
| 5.6-11 | 5.6 切换方式 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：屏幕内容 4 帧从上往下擦除没做，屏幕直接切换） |
| 5.6-12 | 5.6 切换方式 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：不同类工具之间先放下道具再开始新动作没做，道具随姿势一起出现 / 消失） |
| 5.6-13 | 5.6 切换方式 | 偏离（DESIGN.md §13「仍然存在的简化 / 偏离」：没有过渡帧，等待类最多等过渡帧播完 ≤ 250 ms 这一段没做；等待类是立即插入） |
| S01a2 | 6.5 思考·身体 | 偏离（DESIGN §13「重试时「轻敲显示器」…思考超过 20 秒的「用笔轻敲桌面」（没有笔道具，用手在键盘右端小幅上下敲代替）」） |
| S02a | 6.5 Read·身体 | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S02b | 6.5 Read·屏幕 | 偏离（DESIGN §13「连续滚动的步长」：文档 133 ms，任务书 150 ms） |
| S04a | 6.5 Edit·身体 | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| S05b2 | 6.5 NotebookEdit·屏幕 | 偏离（DESIGN §13「…NotebookEdit 的单元格屏幕…」：用 Write 的一行行出现的屏幕） |
| S07a1 | 6.5 Bash > 8 s·身体 | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S09a2 | 6.5 Agent 前台·身体 | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S11a | 6.5 TodoWrite·身体 | 偏离（DESIGN §13「TodoWrite 写字的竖直分量 3.75 Hz」） |
| S12a | 6.5 Skill/ToolSearch·身体 | 偏离（DESIGN §13「…Skill 时「翻手册」…」：Skill 是握鼠标 + 手册屏幕 + 书气泡） |
| S13a | 6.5 MCP 浏览器·身体 | 偏离（DESIGN §13「MCP 浏览器的「小幅度点击」和「扩散圈」」） |
| S13b | 6.5 MCP 浏览器·屏幕 | 偏离（DESIGN §13「MCP 浏览器的「小幅度点击」和「扩散圈」」） |
| S22a2 | 6.5 重试中·身体 | 偏离（DESIGN §13「重试时「轻敲显示器」…」：重试是挠头 + 转圈屏幕 + 「2/10」像素数字） |
| S23a | 6.5 出错·身体 | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S26a2 | 6.5 需要你处理·身体 | 偏离（DESIGN §13「…需要你处理时「点点便利贴」…」：靠着 + 静止的黄色「!」便利贴气泡） |
| S29b1 | 6.5 进场·屏幕 | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」；另见 §7「进场 / 离场」） |
| S29b2 | 6.5 离场·屏幕 | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」；小鱼缸 / 宠物条没有关机渐变见 §13「小鱼缸 / 宠物条没有离场时的显示器关机渐变」） |
| S30 | 6.5 附注·并行工具 | 偏离（DESIGN §13「并行工具的「×3」写在桌牌文字里」） |
| M08 | 6.6 不许开关式闪烁 | 偏离（DESIGN §13「「等待光晕」的「1 Hz、2 像素轻弹」」：由举手挥动承担） |
| M10 | 6.6 亮度变化 | 偏离（DESIGN §13「亮度变化 ≥ 250 ms 渐变只覆盖显示器开关机和昼夜」；另见 §13「屏幕内容切换是硬切」） |
| M11 | 6.6 亮度变化 | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」） |
| M15 | 6.6 帧时长·打字 | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| M16 | 6.6 帧时长·鼠标 | 偏离（DESIGN §13「鼠标「2 帧 × 300 ms」、走路「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」」） |
| M17 | 6.6 帧时长·走路 | 偏离（DESIGN §13「鼠标「2 帧 × 300 ms」、走路「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」」） |
| M19 | 6.6 转身 | 偏离（DESIGN §13「转身第 7 步「举手」」：总时长约 0.55 s，任务书约 0.75 s） |
| M21 | 6.6 转身 | 偏离（DESIGN §13「转身第 7 步「举手」」） |
| M22 | 6.6 气泡 | 偏离（DESIGN §13「气泡弹出 7 → 11 → 15 px」：第一帧 7 px 比任务书的下限 11 小一档） |
| U28 | 7.1 宠物条·多屏 | 偏离（DESIGN §13「应用层的决定」·桌面宠物：「每 0.5 秒（任务书写 2 秒）检查 `visibleFrame` / 鼠标所在屏幕」） |
| U40 | 7.1 Dock（可选） | 偏离（DESIGN §10「已知限制」最后一条＋§10 汇总表「Dock 图标里显示实时的迷你画面（可选）」） |
| N04 | 7.2 触发 | 偏离（DESIGN §10 汇总表「桌面会话「做完了」最多等 4 s 看 blocked…等 8 s」；§11「桌面会话的「做完了」最多等 8 s 看有没有变成 blocked（本轮总结约 7 s 后才落盘）」） |
| N15 | 7.2 文案 | 偏离（DESIGN §13「通知文案里的时长写法」：「3分12秒」，任务书示例写作「3 分 12 秒」） |
| N24b | 7.2 提示音 | 偏离（DESIGN §10 汇总表「提示音 `NSSound(data:)`…后台队列 + `AVAudioPlayer`」；§8「提示音」行） |
| J03 | 7.3 桌面 App 会话 | 偏离（DESIGN §2 M0 第 4 项；§10 汇总表「深链失败判据「2.5 s 内 lastFocusedAt 没变」」；§11「深链失败判据修正」） |
| C09 | 7.5 配置项·空闲 | 偏离（DESIGN §13「设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」…下次启动生效」） |
| C10 | 7.5 配置项·下班工位 | 偏离（DESIGN §13「最多保留 N 个下班工位」…「下次启动生效」…「「最多保留」调小立刻生效」） |
| C11 | 7.5 配置项·下班工位 | 偏离（DESIGN §13「设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」…下次启动生效」） |

---

## 第一部分 · 任务书第 4、5 节（数据源、状态判定、表现层节奏）

> 这是 `QA/spec-trace-core.md`（03:10–03:45 两位只读追踪员写的第一版，288 条）的**定稿**。结构和编号不变；每一行都回到任务书原文（`~/Desktop/Buddy办公室-开发提示词.md` 第 4、5 节）核对过要求，再按 05:1x–05:5x 的源码和测试逐行更新了状态和证据（最后一次核对：2026-09-29 05:5x）。

### 定稿说明

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

### 统计

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

### 最近一次验证

- `BUDDY_SCRATCH=<自己的目录> scripts/dev.sh test --filter SpecTrace`：**42 个测试、3 个套件全部通过**（Core 27 + Stage 14 + App 1；debug 构建 0 警告）。
- 全新的构建目录、从零编译整个包（debug，245 个编译步骤）：**0 警告、0 错误**，同样 42 个测试全部通过。
- 整套 `scripts/dev.sh test`（含别人的全部测试）：**684 个测试、75 个套件全部通过**，0 失败、0 警告、0 个 known issue。
- 稳定性：连续 15 次 `--filter SpecTrace`（同一份构建，机器上同时有别的 agent 在跑 ASAN / 长跑，负载 15–60）：通过 15 次，失败 0 次。
- 环境敏感性（已处理）：机器负载 60–80 时 `.background` 队列会被饿住，token 扫描要等很久；早先一次整套在那种负载下，别人写的几条依赖后台扫描的测试超时过。我的两条会等后台扫描的测试（4.3-41、4.3-42）已把等待上限放宽到 30–90 秒（都是「等到条件成立就返回」，不是固定睡眠，所以平时不会变慢）。测试里没有真实时间 / 网络：状态机用假时钟，文件用临时目录。


---

### 4（章首说明）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 4.0-01 | 4 章首 | 全部只读，不需要任何配置就能拿到全部状态 | Core/Util/FileIO.swift（只读 `open(O_RDONLY)`）；Core/Paths.swift `Paths.real`（默认真实 home，只有 `--data-root` 才换根） | T-Core/RegistryTests › engineNeverWritesUnderClaudeDir；SpecTraceCoreTests › theEngineOnlyWritesInsideItsOwnSupportFolder（完整跑一遍引擎，假 home 里除了自己的 Application Support/BuddyOffice 之外没有任何文件变化）；SourceAuditCoreTests › fileReadsGoThroughFileIOWithAShortReviewedAllowlist（读文件只有 FileIO 一个入口） | ✓ |
| 4.0-02 | 4 章首 | 旧笔记 `~/.claude/monitor/DATA-SOURCES.md`（8 月版本）可以参考，冲突时以本节为准 | 代码里没有任何地方读旧笔记，也不依赖 ~/.claude/monitor 下的脚本；和旧笔记 / 任务书不一致的实测结论以任务书 4、5 节为准，不一致的地方记在 DESIGN.md 第 4 节末段、第 13 节和 Core/README.md「数据源实测结论」 | SpecTraceCoreTests › theOldDataSourcesNoteIsNeverRead（所有非注释的源码里没有 `DATA-SOURCES` / `.claude/monitor/` / `hook.sh` 路径 / `close-by-tty` 引用；FakeTree 是往假 home 里写测试数据的夹具，除外） | ✓ |

---

### 4.1 活会话登记表 `~/.claude/sessions/<pid>.json`

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

### 4.2 ccmon 的 hook 事件流 `~/.claude/.monitor/<session_id>.events.jsonl`

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

### 4.3 会话记录 `~/.claude/projects/<编码后的cwd>/<sessionId>.jsonl`

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

### 4.4 桌面 App 会话元数据 `…/claude-code-sessions/<acct>/<org>/local_<uuid>.json`

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

### 4.5 身份

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

### 4.6 安全红线

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

### 5.1 阶段（phase）

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现 | 验证它的测试 | 状态 |
|---|---|---|---|---|---|
| 5.1-01 | 5.1 基础 | 阶段以登记表的 `status` 为准 | Core/Fusion/ActivityResolver.swift `phase` | T-Core/ActivityResolverTests 里所有 `sig(status)` 用例；ActivityResolverTests › waitingIsNeverOverriddenByHooks；StateRuleInvariantTests › z1_referenceModelAgreesWithTheEngine（16 个固定种子的随机事件流，与按任务书写的独立参考模型逐步对拍：阶段、主线程打开的调用个数与顺序、忙碌 / 等待时的动作） | ✓ |
| 5.1-02 | 5.1 修正 1 | 登记表还是 idle，但有一条比 `statusUpdatedAt` 更新的 UserPromptSubmit → 暂时当作 busy | `phase` | ActivityResolverTests › registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds（提示比 statusUpdatedAt 旧 → 不修正）；EngineScenarioTests › promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds（引擎层：2.9 秒仍 busy、3.1 秒回 idle，只发一次 turnStarted）。实测登记表 busy 比 UserPromptSubmit 早 0.09–0.5 秒，这条路径几乎不触发（Core/README.md「数据源实测结论 · 时序」） | ✓ |
| 5.1-03 | 5.1 修正 1 | …最多 3 秒 | `tempBusyWindow = 3`；`phase` | ActivityResolverTests › registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds（103.4 s 仍 busy、103.6 s 已 idle）；EngineScenarioTests › aPromptThatNeverBecomesBusyExpiresAfter3Seconds（3.2 s 后 idle）；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds | ✓ |
| 5.1-04 | 5.1 修正 2 | 登记表还是 busy，但有一条比 `statusUpdatedAt` 更新的 Stop → 暂时当作 idle | `phase` | ActivityResolverTests › registryBusyButNewerStopIsTemporarilyIdle（Stop 比登记表 busy 旧 → 不修正；Stop 之后又来提示 → 仍 busy）；EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents（Stop 先到、登记表 56 ms 后才翻 idle，Stop 一到就是「做完了」）；StateRuleTests › m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle | ✓ |
| 5.1-05 | 5.1（任务书未写） | 登记表没有 / 不认识 status 时改用 hook 推断；修正 1 另要求提示晚于最近的 Stop，修正 2 要求 Stop 不早于最近的提示 | `phase` | ActivityResolverTests › missingRegistryStatusFallsBackToHooks；ActivityResolverTests › registryBusyButNewerStopIsTemporarilyIdle（排队的下一轮）；StateRuleTests › m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds、m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle | 偏离（DESIGN.md §13「数据层 / 状态机的偏离」：登记表没有 / 不认识 status 时靠 hook 推断阶段，两个临时修正各多一个条件） |

---

### 5.2 工具追踪（ToolTracker：处理悬空和并行）

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

### 5.3 子代理事件的归属（hook 里没有 agent_id）

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

### 5.4 动作判定（ActivityResolver）

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

### 5.5 在场、离场、下班工位

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

### 5.6 表现层节奏（VisualDirector：每个 buddy 一个 Performer）

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

### 5.7 工具归类（ToolCatalog）

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

### 间接验证清单

（确实没法自动化测的 2 条。每条一行：编号 / 要求 / 为什么测不了 / 间接证据。主线程可以原样搬进 REPORT.md。）

| 编号 | 要求 | 为什么没法自动化测 | 间接证据 |
|---|---|---|---|
| 4.1-38 | 终端会话（2.1.267）的登记表字段应和桌面会话大致相同、没有 `hostSessionId`；碰到活终端会话要核对字段，碰不到就靠 fixture（任务书 4.1 自己给了退路） | 这台机器上没有活着的终端会话：终端版 `~/.local/bin/claude` 的 OAuth 登录已过期（DESIGN.md 第 9.1 节），重新登录要碰凭据，不做；也没法凭空造一个真实的终端登记表 | 终端记录走和桌面记录同一个 `RegistryScanner.parse`（所有字段可选，只有 pid / sessionId 必需）；无 hostSessionId → 别名 `sid:` / `proc:`、key 用 `t:`。fixture 测试：EnginePresenceTests › terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles、terminalResumeInANewProcessGivesTheSameBuddyBack；IdentityTests 的终端用例；RegistryTests › entrypointMapsToOrigin（cli → 终端）、missingFieldsAreOptionalButPidAndSessionIdAreRequired；SpecTraceCoreTests › desktopAndTerminalSessionsAreDrivenByTheSameHookStream（没有 hostSessionId 的会话喂同一串 hook，动作时间线和桌面会话逐步相同）。已记录在 DESIGN.md 第 10 节「已知限制」和 Core/README.md「已知限制」 |
| 5.4-36 | 「你跳转到这个会话」→ 清掉未读 | 「跳转」是用户点了小人 / 菜单 / 通知之后 `JumpService.jump` 真的去打开 Claude（深链）或激活终端；在测试里触发它会真的弹出用户的 Claude / 终端窗口，测试进程也没有 GUI 授权（DESIGN.md 第 10 节） | 引擎层的 `markSeen(key:)` 清未读有断言（EngineScenarioTests › aNormalTurnProducesTheExpectedActivitiesAndEvents、StoreTests › markSeenAndRerollAreSafeFromAnyThread、StateRuleTests › f2_unreadClearsInExactlyThreeWays）；应用层接线读代码：App/AppModel.swift `jump(snapshot:)` 在 `JumpService.shared.jump(to:)` 之后调用 `provider.markSeen(key:)`；反例有测试（AppModelTests › clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal：悬空座位 / 演示模式的点击不跳、不清未读）。深链本身的真实行为见 DESIGN.md 第 8 节「深链跳转」（发出且没被判失败，前台切换没法看） |

### 遗留缺口

（写测试时发现的、实现和任务书不一致、而且**没有**在 DESIGN.md 里记为偏离的问题。按要求没有改产品代码，留给主线程处理。两条：G-1（SP-06）、G-2（C-032）定稿之后都已经被主线程修掉，这一节只作记录，没有遗留。）

#### G-1 [低，定稿期间发现、之后已修：`QA/issues-stage.md` SP-06] 某个 buddy 正在「错开」等待应用变化时，到来的等待类状态晚到，还会先闪一帧过期的旧动作
- **对应任务书**：5.6「等待类状态到来时，最多等当前过渡帧播完（≤ 250 ms）就立即插入」（表格 5.6-13）；第一版疑点 Q-05。
- **现象（修复前）**：同一帧里多个人变化时，第 k 个人的变化被错开成「晚 min(0.6, 0.09 × k) 秒才应用」。如果这个人在这段推迟期间又变成等待类（等批准 / 提问 / 计划待审），`VisualDirector.update` 里 `if let pd = pending[s.key]` 那一支仍按「没到点就沿用旧快照」处理：表演者一直显示推迟之前的旧动作，到点那一帧套用的是推迟开始时存下的**过期**快照（不是等待态），下一帧才切到等待。所以等待类晚到最多 0.6 秒，并且中间闪一帧过期的旧动作。
- **复现**：`SpecTraceStageTests › aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately`（10 个人 2.0 秒同一帧 Read → Edit，第 10 个人被推迟到 2.6 秒；2.1 秒他变成 waitingApproval）。修复前实测：等待态 0.567 秒之后才显示（期望 ≤ 0.25 秒），中间有 1 帧显示的是过期的 Edit。
- **期望**：等待类到来时立刻清掉这个人的 pending、直接套用最新快照（`needsUser` 的状态不该被错开也不该被旧 pending 拦住）。
- **处理结果**：**已修**（SP-06）：`Sources/BuddyStage/VisualDirector.swift` `update` 里等待类快照到来时先 `pending.removeValue(forKey:)`。按要求我没有改产品代码；那条测试写的时候用 `withKnownIssue` 包住两条断言（套件是绿的，修好之后 `withKnownIssue` 会变红提醒去掉包装），修好之后包装已去掉，现在两条断言都是普通断言，整套通过。所以这条**不再是遗留**，只作记录。

#### G-2 [低，不影响任何一行的状态；定稿之后已修：`QA/issues-core.md` C-032] 应用层 `JumpService.DesktopMeta` 直接用 `FileManager` 读桌面元数据，绕开 `FileIO`
- **对应**：第一版疑点 Q-11、`QA/issues-core.md` C-032、`QA/issues-app.md` A-014（只修了一半：加了 1 秒缓存、一次遍历读全部 lastFocusedAt，没改成走 `FileIO`，点击时那一次读仍在主线程）。
- **现象**：`App/JumpService.swift` 的 `DesktopMeta` 用 `FileManager.default.contents(atPath:)` 读 `local_*.json`（每个约 20 KB）。它只读这一类文件、不会碰 `.key` / `.sock`，所以不违反 4.6 的任何一条；但「`FileIO` 是唯一入口」的约定（`SourceAuditCoreTests › fileReadsGoThroughFileIOWithAShortReviewedAllowlist`）只审计了数据层 / 表现层 / 工具，应用层这一处不在审计范围里。
- **期望**：改用 BuddyCore 里已有的 `DesktopMetaReader`（带签名缓存和 FileIO 保险），或者在应用层的源码审计里把这一处列进白名单并写明理由。
- **处理结果**：**已修**（C-032，主线程接手）：`DesktopMeta` 读目录 / 读文件改走 `FileIO.listDirectory / readAll`（回归测试 `Tests/BuddyOfficeTests/DesktopMetaFileIOTests`：指向 `.key` 的符号链接诱饵不会被打开，修复前失败）；1 秒缓存和读盘次数的测试见 A-014（`CachesTests`）。点击时那一次读仍在主线程（3–8 ms 量级），作为 P3 接受（QA/REPORT.md 第 8 节）。所以这条也**不再是遗留**。

### 原疑点 Q-xx 的最终结论

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

### 新增测试与变异验证

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

---

## 第二部分 · 任务书 6.5 / 6.6 / 7.1–7.5（表现层动画与手感、三种形态、提醒、跳转、设置）

> **定稿说明**
> 本文件是 `QA/spec-trace-ui.md`（03:10–03:45 只读追踪，267 条）的定稿版：编号和结构不变（`S` = 6.5 表、`M` = 6.6、`U` = 7.1、`N` = 7.2、`J` = 7.3、`F` = 7.4、`C` = 7.5），逐行更新了「实现」「测试 / 证据」「状态」三列，「要求」列回到任务书原文（`~/Desktop/Buddy办公室-开发提示词.md`）重新核对过。原文件保持不动。
> 追踪之后代码改了很多：表现层的缺口补上了（关机渐变、指示灯呼吸、启动依次开机、「其他 MCP」首字母、进度条位置、滚动节奏、WebSearch 先打字等，见 `QA/issues-stage.md`），应用层全部 P1 / P2 / P3 修了并新增了 `Tests/BuddyOfficeTests/`（见 `QA/issues-app.md`），DESIGN.md 第 13 节记录了保留下来的偏离。
> **状态现在只有三种**：`✓`（实现了，并且有测试的断言真的检查到了这条的数字 / 行为，「测试」列写 缩写 › 测试函数名）；`偏离（DESIGN §x）`（和任务书不一致而且是有意的，理由已写在 DESIGN.md 里，引号里是那段话的开头，已逐条 grep 确认存在）；`✓（间接验证：I-xx）`（确实没法自动化测：真实 GUI 点击 → 窗口服务器、系统授权弹窗、终端自动化授权、真实 Terminal 标签页选择等，汇总在 §9「间接验证清单」，每条写清为什么测不了 + 间接证据）。原文件里没有归宿的几类（没做的、偏离但没记录的、有实现但没有专门测试的、不适用的）全部消灭：修好的写了问题编号 + 测试名；能测的补了测试（新增 40 + 35 个测试函数，见 §0）；有意的偏离补记进 DESIGN.md 第 13 节（本次新增 10 条）；确实测不了的进 §9。「偏离」行对应的测试（有的话）断言的是**实际的数字**，谁改了实现，测试会红，提醒同时更新 DESIGN.md。
> **本次改动**：只新增了两个测试文件（`Tests/BuddyStageTests/SpecTraceUITests.swift`、`Tests/BuddyOfficeTests/SpecTraceUITests.swift`）和 DESIGN.md 第 13 节里新增的一小节；没有改任何源码 / 现有测试（也没有削弱或屏蔽任何现有断言）。新增的测试在 debug 下 0 警告（在全新的 scratch 目录里从零编译验证过），全量 `swift test`（759 个测试 / 88 个套件）连跑 3 次，本次新增的 13 个套件每次都通过（第 3 次机器负载高，数据层的 3 个现有测试超时 / 计数为 0 而失败，与本次改动无关，见 §10 G-04）；面板 / 窗口对象只建不显示，不弹窗口、不碰真实数据、不联网、不读 `~/.claude`。
> **时间与版本**：定稿 2026-09-29 05:10–06:20（PDT）；源码树是共享的，别人可能在同时改（另有一位定稿员做数据层那半）——「实现」列引函数名，不引行号。

### 定稿统计

| 状态 | 条数 | 占比 |
|---|---|---|
| ✓（有测试断言到了数字 / 行为） | 210 | 78.7% |
| 偏离（DESIGN.md 里有理由） | 35 | 13.1% |
| ✓（间接验证：见 §9 清单） | 22 | 8.2% |
| 合计 | 267 | 100% |

按章节：

| 章节 | 合计 | ✓ | 偏离 | ✓（间接验证） |
|---|---|---|---|---|
| 6.5 状态 → 动画（S） | 116 | 99 | 17 | 0 |
| 6.6 动作手感（M） | 24 | 14 | 9 | 1 |
| 7.1 三种形态 + 菜单栏 + Dock（U） | 52 | 43 | 2 | 7 |
| 7.2 提醒（N） | 30 | 23 | 3 | 4 |
| 7.3 跳转（J） | 13 | 5 | 1 | 7 |
| 7.4 跟着 Claude 开 / 收（F） | 9 | 8 | 0 | 1 |
| 7.5 设置与诊断（C） | 23 | 18 | 3 | 2 |

**原文件统计对照**（`spec-trace-ui.md`）：✓ 134、有实现但没有专门测试 101、偏离（已记录）7、偏离但没记录 15、没做 8、不适用 2 = 267。
定稿后：✓ 210、偏离 35、✓（间接验证）22 = 267，后面四类（没做 / 偏离但没记录 / 有实现但没有专门测试 / 不适用）都是 0。

### 0. 图例与证据索引

**状态**（只有三种）：`✓`、`偏离（DESIGN §x）`、`✓（间接验证：I-xx）`，含义见开头。「偏离」行的引号里是 DESIGN.md 里那段话的开头（有「…」的表示中间省略，各段都能在 DESIGN.md 里 grep 到）。

**编号**：`S<行号><a身体 b屏幕 c道具·气泡 d桌牌>` = 6.5 表的第几行的哪一列；`S30 / S31` = 表后两条附注；`M` = 6.6；`U` = 7.1（含 `U41` 空办公室牌子的补充核对）；`N` = 7.2；`J` = 7.3；`F` = 7.4；`C` = 7.5。

**测试索引**（「测试」列的缩写；函数名都是 Swift Testing 的 `@Test` 函数名，`HM` 是 Python 的 `test_*`）：

| 缩写 | 文件 |
|---|---|
| **SPT-S** | `Tests/BuddyStageTests/SpecTraceUITests.swift`（**本次新增**，40 个：`SpecTracePoseTests` / `SpecTraceScreenTests` / `SpecTracePlateTests` / `SpecTraceThresholdTests` / `SpecTraceMotionTests` / `SpecTraceSceneTests` / `SpecTraceExtraStageTests`） |
| **SPT-A** | `Tests/BuddyOfficeTests/SpecTraceUITests.swift`（**本次新增**，35 个：`SpecTraceSettingsTests` / `SpecTracePanelTests` / `SpecTraceChromeTests` / `SpecTraceAlertTests` / `SpecTraceJumpAndLifecycleTests` / `SpecTraceSourcePinTests`） |
| RRA / RRS | `BuddyOfficeTests/ReviewRegressionAppTests` / `BuddyStageTests/ReviewRegressionStageTests`（收尾前独立复查新发现的问题的回归测试：提示卡顺序、合并提醒、节流补发、缩放、隐私文案、气泡最短停留……，编号见 `QA/issues-review.md`） |
| PM / PT / PC | `BuddyStageTests/PerformerMappingTests.swift`（6.5 表逐行的姿势 / 屏幕 / 气泡）/ `PerformerTimingTests.swift`（5.6 节奏）/ `PlateCopyTests.swift` |
| MT / SCT / WO | `BuddyStageTests/MonitorTests.swift`（关机渐变、启动依次开机、指示灯）/ `ScreenContentTests.swift` / `WalkersAndOffDutyTests.swift` |
| HT / RT / TA / AL / SPR / EX | `BuddyStageTests/HitTestingTests` / `RenderingTests`（局部重绘、闪烁扫描、金图、走路 + 开门）/ `TextAuditTests` / `AppLayerFixTests` / `SpriteAndPaletteTests` / `ExtremeValuesTests` |
| AC / AF / AM / AP / AQ | `BuddyOfficeTests/AlertCoordinatorTests`（提醒判定，假时钟）/ `AlertFallbackTests`（系统通知被拒时的兜底）/ `AppModelTests` / `ApplyPlanTests` / `AutoQuitTests` |
| JT / NA / CA / SE / SL / SK / TT / EC / HK / PS / PA / PV / PD / SA | `BuddyOfficeTests/JumpTests` / `NotificationAuthTests` / `CachesTests` / `SettingsTests` / `StripPlacementTests` / `ScreenPickerTests` / `ToastTextTests` / `EngineConfigTests` / `HousekeepingTests` / `PanelShowTests` / `PanelAnimationTests` / `PixelViewTests` / `PixelViewDragTests` / `SourceAuditTests` |
| IT / AR / EnginePresenceTests | `BuddyCoreTests/IdentityTests` / `ActivityResolverTests` / `EnginePresenceTests`（数据层） |
| HM | `Tests/hook_merge_test.py`（13 个；本次没有重跑——约定不跑 `hook-merge.py`；逐条对应读的是测试源码里的断言） |

**怎么复现**（在自己的 scratch 目录里跑，别用别人的 `.build*`）：

```
BUDDY_SCRATCH=<自己的目录> scripts/dev.sh test --filter SpecTracePoseTests --filter SpecTraceScreenTests --filter SpecTracePlateTests \
  --filter SpecTraceThresholdTests --filter SpecTraceMotionTests --filter SpecTraceSceneTests --filter SpecTraceExtraStageTests \
  --filter SpecTraceSettingsTests --filter SpecTracePanelTests --filter SpecTraceChromeTests --filter SpecTraceAlertTests \
  --filter SpecTraceJumpAndLifecycleTests --filter SpecTraceSourcePinTests
```

**DESIGN.md 里的「偏离」记录位置**（「偏离」状态引用它们）：§7「打字节拍 133 ms 一格」；§7「进场 / 离场（走路 + 开门）」；§8「提示音」行；§10「与任务书不一致 / 没做的地方（汇总）」表的各行；§10「已知限制」最后一条（Dock 迷你画面）；§11 小决定；§2 M0 第 4 项（深链判据）；§13「仍然存在的简化 / 偏离」各条；§13「应用层的决定」（桌面宠物：每 0.5 秒）；§13「表现层 / 应用层的偏离（规格追踪定稿时补记）」（**本次新增**：气泡 7 → 11 → 15、开关机 16 级抖动、滚动步长、背对镜头的近似、写字 3.75 Hz、转身第 7 步、MCP 点击圈、亮度渐变范围、×N 写在桌牌里、通知里的时长写法）。

### 1. 任务书 6.5 状态 → 动画（每行 × 四列）

列缩写：a = 身体动作；b = 屏幕（24×15）；c = 道具 / 气泡；d = 桌牌文字。「—」列合并在 S00。文件名都在 `Sources/BuddyStage/` 下：`PoseLibrary.swift`（姿势帧）、`Performer.swift`（状态 → 姿势 / 屏幕 / 气泡的映射：`targetPose` / `targetScreen` / `targetBubble`）、`ScreenContent.swift`（屏幕）、`SeatRenderer.swift`（气泡 / 道具 / 小旗 / 待机灯）、`PlateCopy.swift`（桌牌文案）。行号会漂，以函数名为准。「测试」列的缩写见 §0 测试索引；`SPT-S ›` 是本次新增的 `Tests/BuddyStageTests/SpecTraceUITests.swift`。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| S01a1 | 6.5 思考·身体 | 略微后靠，手托下巴 | `PoseLibrary.frame(.thinking)`：躯干 / 头各下沉 1 px，右手落在头的一侧（`Spots.headSideR`），左手在键盘上；`Performer.targetPose` | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（torsoDy = headDy = 1、右手 = headSideR、左手 = kbL）；PM › everyRowOfTheStateToAnimationTable（姿势 = .thinking） | ✓ |
| S01a2 | 6.5 思考·身体 | > 20 秒后用笔轻敲桌面（≤ 2 Hz） | `.thinkingDeep`（`targetPose`：`elapsed > 20`）：右手落在键盘右端的桌面（`Spots.pad`），y 每 267 ms 换一格 = 1.85 Hz；没有笔的精灵 | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（20 s 仍是思考、20.01 s 起深度思考）、tappingScratchingWritingAndWavingFrequencies（轻敲 1.5–2.0 Hz，手落在 `Spots.pad`） | 偏离（DESIGN §13「重试时「轻敲显示器」…思考超过 20 秒的「用笔轻敲桌面」（没有笔道具，用手在键盘右端小幅上下敲代替）」） |
| S01b | 6.5 思考·屏幕 | IDE 界面，光标静止 | `ScreenContent.draw(.ide)`：光标位置固定在 (7, 9)，颜色在 3 个色阶间 0.5 Hz 呼吸（`cursorColor`） | SPT-S › theCursorBreathesThroughThreeLevelsAtHalfAHertzAndNeverBlinksOnAndOff（整张屏幕任何时刻只有光标那一个像素在变；3 个色阶、2 秒一周期）；RT › staticScreenClassificationMatchesWhatIsActuallyDrawn | ✓ |
| S01c | 6.5 思考·气泡 | 思考气泡，三个点缓缓升起 | `Performer.targetBubble` → `.think`；`SeatRenderer.drawBubble(.think)` + `thinkDy`（三点错相位，−1 / 0 / +1 px，0.7 Hz） | PM › everyRowOfTheStateToAnimationTable（气泡 = .think）；SPT-S › theThinkingBubbleDotsBobSlowlyAndOutOfPhase（三个点各自 −1/0/+1、一次只动 1 px、0.6–0.8 Hz、相位互相错开） | ✓ |
| S01d | 6.5 思考·桌牌 | 「思考中」 | `PlateCopy.activity` | SPT-S › everyRowOfTheTableShowsItsPlateText；PC › activityTextForEveryState | ✓ |
| S02a | 6.5 Read·身体 | 前倾，手放在鼠标上，头微低 | `.mouse`：躯干 / 头一起上移 1 px（朝显示器前倾），右手落在鼠标上（±1 px 缓慢漂移）；「头微低」并进整体前倾，头相对躯干没有再低一档 | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（torsoDy = headDy = −1、右手离鼠标 ≤ 1 px 且有漂移）；PM › everyRowOfTheStateToAnimationTable | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S02b | 6.5 Read·屏幕 | 文档每 150 ms 滚 1 像素；颜色随文件扩展名变 | `.doc(ext)`：每 133 ms（15 fps 的整 2 帧）整屏上移恰好 1 px（`rhythm(t, every: 2/15)`）；swift 橙 / py·sh 绿 / js·ts 琥珀 / md·txt 白 / json·yaml·toml 青 / html·css 粉 / 其余蓝 | SPT-S › documentScrollsOnePixelPerStepAndItsColourFollowsTheExtension（画面变化的间隔恒为 133 ms、每步第 3–12 行恰好上移 1 px、13 种扩展名的颜色，7 个类别互不相同）；SCT › documentAndLogScrollingStepsAreWholeFramesAt15fps | 偏离（DESIGN §13「连续滚动的步长」：文档 133 ms，任务书 150 ms） |
| S02d | 6.5 Read·桌牌 | 「在读 app.swift」 | `PlateCopy.toolText(.read)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S03a | 6.5 Grep/Glob·身体 | 同上（前倾握鼠标），头轻轻左右扫 | `.searching`：同 `.mouse` + `headDx = round(sin 2.2t)` ∈ −1…1 | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（headDx 走过 −1 / 0 / +1，来回 < 0.6 Hz，前倾同 Read） | ✓ |
| S03b | 6.5 Grep/Glob·屏幕 | 结果列表，高亮条缓动 / 文件树展开 | `.results`（高亮条按 smoothstep 换行）／`.tree`（每 0.35 s 多展开一行，最多 5 行）；`Performer.targetScreen` | SPT-S › resultsHighlightEasesAndTheTreeUnfolds（高亮依次走过第 0、1、2 行、两头停得久中间过得快、走到底停住；树 1→5 行）；PM › everyRowOfTheStateToAnimationTable（Grep→.results、Glob→.tree） | ✓ |
| S03c | 6.5 Grep/Glob·气泡 | 放大镜图标 | `Performer.targetBubble`：search 类 → `.search`（`icon.magnifier`） | PM › everyRowOfTheStateToAnimationTable（气泡 = .search）；SPT-S › bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven（图标 7×7） | ✓ |
| S03d | 6.5 Grep/Glob·桌牌 | 「在找 "TODO"」／「在翻文件」 | `PlateCopy.toolText`（搜索词最多 12 字） | SPT-S › everyRowOfTheTableShowsItsPlateText；PC › fileNamesClipsAndDurations（clip 12） | ✓ |
| S04a | 6.5 Edit·身体 | 打字（4 帧 × 8 fps，每只手 2 Hz） | `.typing`：133 ms 一格（7.5 格/秒），4 格一轮，每只手 1.85 Hz | SPT-S › typingBeatsAreFourFramesOf133msAndWriteIsTwiceAsFast（每格 133 ms、4 个状态一轮、每只手 1.7–2.0 Hz） | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| S04b | 6.5 Edit·屏幕 | 编辑器：一行高亮，字符逐个出现，左侧绿色 diff 标记 | `.diffEdit`：高亮行、`chars = min(14, Int(t*6))` 逐字出现、左侧绿点（0,9）（1,9）、光标呼吸 | SPT-S › editTypesCharactersAndWriteAddsRowsFromTheTop（白字最多 14 个、一个个增加；绿色标记和高亮行在每个时刻都在） | ✓ |
| S04d | 6.5 Edit·桌牌 | 「在改 x.swift」 | `PlateCopy.toolText(.edit)` | SPT-S › everyRowOfTheTableShowsItsPlateText（Edit / MultiEdit） | ✓ |
| S05a | 6.5 Write·身体 | 打字更快 | `.typingFast`：左右手每格交替，每只手 3.75 Hz（< 4 Hz） | SPT-S › typingBeatsAreFourFramesOf133msAndWriteIsTwiceAsFast（3.5–4.0 Hz、是 Edit 的 1.8 倍以上、状态 [[1,0],[0,1]] 交替）；noPoseSwingsFasterThanFourHertz | ✓ |
| S05b1 | 6.5 Write·屏幕 | 一行行从上往下出现 | `.notebook`：每 0.28 s 多一行，最多 6 行 | SPT-S › editTypesCharactersAndWriteAddsRowsFromTheTop（第 0…5 行依次出现，0.1 s / 0.35 s / 0.9 s / 1.7 s） | ✓ |
| S05b2 | 6.5 NotebookEdit·屏幕 | notebook 单元格 | NotebookEdit 与 Write 同属 write 类，走同一个 `.notebook`（逐行出现），没有单元格样式 | PM › everyRowOfTheStateToAnimationTable（NotebookEdit → .notebook） | 偏离（DESIGN §13「…NotebookEdit 的单元格屏幕…」：用 Write 的一行行出现的屏幕） |
| S05d | 6.5 Write·桌牌 | 「在写 x.swift」 | `PlateCopy.toolText(.write)` | SPT-S › everyRowOfTheTableShowsItsPlateText（Write / NotebookEdit） | ✓ |
| S06a | 6.5 Bash ≤ 8 s·身体 | 快速敲一阵，然后手歇下来 | `targetPose`：前 3 s `.typing`（普通打字节拍），3–8 s `.restAtDesk`（手停在键盘上）；「一阵」读作前 3 秒 | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（3 s 边界、8 s 边界）；PM › everyRowOfTheStateToAnimationTable（2 s 打字 / 5 s 手歇 / 12 s 靠着） | ✓ |
| S06b | 6.5 Bash ≤ 8 s·屏幕 | 黑底终端，绿色提示符，一行行输出 | `.terminal`：`scr.term` 黑底、`>` 提示符 (1,1)(2,2)(1,3) 绿色、4 行输出每 0.4 s 上滚 | SPT-S › terminalHasAGreenPromptAndTheLongBarFollowsOneMinusExpMinusTOverTau（黑底占多数、绿色提示符、4 行输出、4 秒里滚动 ≥ 9 次）；SCT › rhythmStepsAreEvenAndNeverSkip | ✓ |
| S06d | 6.5 Bash ≤ 8 s·桌牌 | 「运行 git status」 | `PlateCopy.toolText(.bash)` + `shortCommand` | SPT-S › everyRowOfTheTableShowsItsPlateText（2 s、8 s 都是「运行 git status」）；PC › shortCommandKeepsTheFirstWordsAndDropsCdPrefixesAndOptions | ✓ |
| S07a1 | 6.5 Bash > 8 s·身体 | 往后靠、抱着手臂 | `.leanBack`：躯干 / 头下沉 1 px，双手落在身侧（`restL / restR`）；「抱着手臂」画成手落在身侧 | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（torsoDy = headDy = 1、双手 = rest）；statesSwitchExactlyOnTheSpecifiedSeconds（> 8 s 起靠着） | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S07a2 | 6.5 Bash > 8 s·身体 | 每 20 秒最多喝一口 | `.leanBack`：22 秒一圈，圈尾 2.6 s 手去够杯子再举到嘴边 | SPT-S › sippingAndLookingAroundHappenAtTheSpecifiedIntervals（多个 seed：两口间隔 ≥ 20 s、一口 2.6 s、每个 buddy 相位不同）；everyDeskHasAMugAndTheSipReachesForIt（左手离杯子 ≤ 1 px） | ✓ |
| S07b | 6.5 Bash > 8 s·屏幕 | 终端 + 进度条，按 1−e^(−t/τ) 增长，永远不会假装跑满 | `.terminalLong`：τ = 30 s，宽度 `Int(22 × min(0.94, 1−e^(−t/30)))`，条在第 5–6 行（头挡不住） | SPT-S › terminalHasAGreenPromptAndTheLongBarFollowsOneMinusExpMinusTOverTau（t = 0…10⁶ 秒共 10 个时刻的格数逐个等于公式，上限 20/22 格）；SCT › theLongBashProgressBarIsAboveTheRowsTheHeadHides、aLongBashBarGrowsButNeverFillsUp（TA-013） | ✓ |
| S07c | 6.5 Bash > 8 s·道具 | 马克杯 | 每张桌子上都有马克杯（`SeatRenderer.draw` 的 `mug`），喝水动作去够它 | SPT-S › everyDeskHasAMugAndTheSipReachesForIt（杯子像素盖在桌面上 ≥ 8 个、喝的时候左手到杯子） | ✓ |
| S07d | 6.5 Bash > 8 s·桌牌 | 「运行中 npm test · 1:23」 | `PlateCopy.toolText(.bash)`：`elapsed > 8` → `运行中 <cmd> · m:ss` | SPT-S › everyRowOfTheTableShowsItsPlateText（83 秒 → 「运行中 npm test · 1:23」） | ✓ |
| S08a1 | 6.5 WebFetch·身体 | 握鼠标 | `targetPose(.web)`：`.mouse`（> 8 s 换 `.leanBack`） | PM › everyRowOfTheStateToAnimationTable；SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（8 s 边界） | ✓ |
| S08a2 | 6.5 WebSearch·身体 | 先打字再用鼠标 | `targetPose(.web)`：WebSearch 前 2.5 s `.typing`，之后 `.mouse`（TA/SP-04 修复） | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（2.49 s 打字、2.5 s 鼠标）；PM › everyRowOfTheStateToAnimationTable（WebSearch 开头 / 之后两行） | ✓ |
| S08b | 6.5 Web·屏幕 | 浏览器：地址栏，页面块逐个加载 / 搜索结果 | `.browser`（白色地址栏，每 0.5 s 多一块，最多 4 块）／`.search`（搜索框字逐个出现 + 3 条结果） | SPT-S › browserLoadsPageBlocksOneByOneAndSearchTypesTheQuery（块数 1→4；搜索框 2→9 格；3 条蓝色结果）；PM › everyRowOfTheStateToAnimationTable（WebFetch→.browser、WebSearch→.search） | ✓ |
| S08d | 6.5 Web·桌牌 | 「在看 github.com」／「在搜 …」 | `PlateCopy.toolText(.web)`（URL 只留域名，搜索词最多 12 字） | SPT-S › everyRowOfTheTableShowsItsPlateText（「在看 github.com」「在搜 "hydrogen emb…"」） | ✓ |
| S09a1 | 6.5 Agent 前台·身体 | 转成 3/4 朝向对着小助手 | `.delegate`：`facing = .threeQuarterBack`（座位在右半边时镜像） | PM › delegatingToForegroundHelpersPointsAtThemAndBackgroundOnesLeavesYouTyping（前台 → .delegate）；SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（facing = 3/4 后）、helpersSlideInAtMostThreeShownAndTheRestAreCountedAndBackgroundOnesStayBeside（有前台帮手时姿势 = .delegate） | ✓ |
| S09a2 | 6.5 Agent 前台·身体 | 指一指，然后抱臂督工 | `.delegate`：6 秒一轮，前 2.2 s 右手伸向一侧，之后收回身侧 | SPT-S › posesOfTheDashRowsCarryNoPropsAndTheSupervisorPointsThenFolds（0–2.2 s 指、之后收回、6 秒一轮） | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S09b | 6.5 Agent 前台·屏幕 | 小助手列表 + 进度 | `.helpers`：三个彩色方块 + 三条进度条 | SPT-S › helperListChecklistManualAndIconGrid（三色方块、进度条随时间变长）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S09c | 6.5 Agent 前台·道具 | 小助手坐着带轮凳子、抱着笔记本滑进来（最多 3 个，多了显示 +N） | `Performer.syncHelpers`（弹簧滑入，3 个槽位）；`SeatRenderer.draw` 小助手精灵 + 「+N」牌 | SPT-S › helpersSlideInAtMostThreeShownAndTheRestAreCountedAndBackgroundOnesStayBeside（1 / 3 / 5 / 6 个：从 40 px 外滑进来、停住、最多 3 个位置、多出的 +0 / +0 / +2 / +3） | ✓ |
| S09d | 6.5 Agent 前台·桌牌 | 「派了 2 个帮手」 | `PlateCopy.toolText(.delegate)` | SPT-S › everyRowOfTheTableShowsItsPlateText（2 个前台帮手 → 「派了 2 个帮手」） | ✓ |
| S10a | 6.5 Agent 后台·身体 | 回去干自己的活 | `targetPose(.delegate)`：没有前台未完成的帮手 → `.typing` | PM › delegatingToForegroundHelpersPointsAtThemAndBackgroundOnesLeavesYouTyping；SPT-S › helpersSlideInAtMostThreeShownAndTheRestAreCountedAndBackgroundOnesStayBeside（后台：姿势 = .typing） | ✓ |
| S10b | 6.5 Agent 后台·屏幕 | —（规格没写） | 仍显示小助手列表（`.helpers`） | PM › delegatingToForegroundHelpersPointsAtThemAndBackgroundOnesLeavesYouTyping（屏幕 = .helpers）；规格是「—」，多画不冲突 | ✓ |
| S10c | 6.5 Agent 后台·道具 | 小助手留在旁边 | 后台帮手照样留在 `helperTracks`（`active = !done`） | SPT-S › helpersSlideInAtMostThreeShownAndTheRestAreCountedAndBackgroundOnesStayBeside（后台：两个小助手还在旁边） | ✓ |
| S10d | 6.5 Agent 后台·桌牌 | 「帮手在后台干活」 | `PlateCopy.toolText(.delegate)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S11a | 6.5 TodoWrite·身体 | 在便签本上写（≤ 3 Hz） | `.writingPad`：4 格一轮（每格 133 ms）：横向 1.86 Hz、竖直分量 3.7 Hz（仍在 4 Hz 上限内），右手落在便签本上 | SPT-S › tappingScratchingWritingAndWavingFrequencies（横向 ≤ 2 Hz、竖直 3.5–4.0 Hz、图案每 0.533 s 重复、手落在 `Spots.pad`）；noPoseSwingsFasterThanFourHertz | 偏离（DESIGN §13「TodoWrite 写字的竖直分量 3.75 Hz」） |
| S11b | 6.5 TodoWrite·屏幕 | 清单逐项打勾 | `.checklist`：每 0.7 s 多勾一项，5 项勾完从头再来 | SPT-S › helperListChecklistManualAndIconGrid（0.1 / 0.8 / 1.5 / 2.2 / 2.9 / 3.6 / 4.3 s → 0,1,2,3,4,5,0 个勾） | ✓ |
| S11c | 6.5 TodoWrite·道具 | 便签本 | `.notepad` 桌面道具 | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（`.writingPad` 的道具 = [.notepad]） | ✓ |
| S11d | 6.5 TodoWrite·桌牌 | 「在列计划」 | `PlateCopy.toolText(.todo)` | SPT-S › everyRowOfTheTableShowsItsPlateText（TodoWrite / TaskCreate / TaskUpdate） | ✓ |
| S12a | 6.5 Skill/ToolSearch·身体 | 翻手册 / 点鼠标 | Skill 和 ToolSearch 都是 `.mouse`（ToolSearch 的「点鼠标」对得上；Skill 没有「翻手册」的动作） | PM › everyRowOfTheStateToAnimationTable（Skill、ToolSearch 两行） | 偏离（DESIGN §13「…Skill 时「翻手册」…」：Skill 是握鼠标 + 手册屏幕 + 书气泡） |
| S12b | 6.5 Skill/ToolSearch·屏幕 | 手册页 / 图标网格，高亮在移动 | `.manual`（两页白纸，每 1.6 s 翻页）／`.iconGrid`（高亮每 0.5 s 移一格，6 格循环） | SPT-S › helperListChecklistManualAndIconGrid（手册 t=0.1 ≠ 1.7、= 3.3；高亮 0…5,0） | ✓ |
| S12c | 6.5 Skill/ToolSearch·气泡 | 书 / 工具箱 | `targetBubble`：Skill → `.book`，ToolSearch → `.toolbox` | PM › everyRowOfTheStateToAnimationTable（两行的气泡） | ✓ |
| S12d | 6.5 Skill/ToolSearch·桌牌 | 「在看技能手册」／「在翻工具箱」 | `PlateCopy.toolText(.skill)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S13a | 6.5 MCP 浏览器·身体 | 握鼠标，小幅度点击 | `.mouse`：鼠标手 ±1 px 缓慢漂移，没有单独的「点击」动作 | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（握鼠标、±1 px 漂移）；PM › everyRowOfTheStateToAnimationTable | 偏离（DESIGN §13「MCP 浏览器的「小幅度点击」和「扩散圈」」） |
| S13b | 6.5 MCP 浏览器·屏幕 | 浏览器，指针在动；点击处有扩散圈，只用调色板变暗表现，不闪 | `.mcpBrowser`：指针沿环形路径；点击 = 指针四周 4 个 `scr.dark` 像素，每 3 s 一次约 0.36 s，不做逐帧扩散 | SPT-S › mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette（6 秒 10 ms 一帧：白色像素数恒定不闪白、变暗像素恰好 +4、每次 0.34–0.38 s、指针在动） | 偏离（DESIGN §13「MCP 浏览器的「小幅度点击」和「扩散圈」」） |
| S13d | 6.5 MCP 浏览器·桌牌 | 「在操作浏览器」 | `PlateCopy.toolText(.browser)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S14a | 6.5 computer-use·身体 | 握鼠标 | `targetPose(.computer)`：`.mouse` | PM › everyRowOfTheStateToAnimationTable | ✓ |
| S14b | 6.5 computer-use·屏幕 | 桌面上有窗口和指针 | `.desktop`：两个窗口 + 任务栏 + 移动的指针 | SPT-S › mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette（桌面上有窗口、指针 3 像素在动）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S14d | 6.5 computer-use·桌牌 | 「在操作电脑」 | `PlateCopy.toolText(.computer)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S15a | 6.5 其他 MCP·身体 | 打字和鼠标交替 | `targetPose(.mcp)`：`Int(elapsed/3) % 2`，每 3 s 换（受姿势最短停留 1.5 s 约束） | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（2.99 s 打字、3.0 s 鼠标、6.0 s 打字）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S15b | 6.5 其他 MCP·屏幕 | 带 server 首字母的应用面板 | `.mcpApp(name)`：`ScreenContent.mcpInitial`（名字里第一个 4×6 字体画得出的字母，否则 M）画在面板中间（TA-012 修复） | SPT-S › mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette（notion→N、slack→S、ccd_session→C、「计划」→M 的字形逐像素对得上）；SCT › theSmallPixelFontDrawsEveryLatinCapital、aMcpServersInitialIsALetterTheFontCanDraw、theMcpAppScreenNeverFallsBackToThePlaceholderGlyph | ✓ |
| S15d | 6.5 其他 MCP·桌牌 | 「在用 <server>」 | `PlateCopy.toolText(.mcp)`（server 截 10 字） | SPT-S › everyRowOfTheTableShowsItsPlateText（「在用 notion」） | ✓ |
| S16a | 6.5 SendUserFile/定时/Monitor·身体 | 把纸放进发件盘／拨桌上的闹钟／往后靠 | `.sendFile`、`.alarm`、`.leanBack`（Monitor） | PM › everyRowOfTheStateToAnimationTable（SendUserFile / 定时 / Monitor 三行）；SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（Monitor 一直靠着） | ✓ |
| S16b | 6.5 SendUserFile/定时/Monitor·屏幕 | 文件滑进盘里／钟面／日志滚动 | `.outbox`（白色文件从上往下滑进盘里）、`.clock`（分针 / 时针在转）、`.log`（黑底、每 333 ms 上滚一行） | SPT-S › stateScreens（文件左沿 6→7→8→9→11 一路滑；钟面两只针；日志 3 秒里滚动 ≥ 8 次）；SCT › documentAndLogScrollingStepsAreWholeFramesAt15fps | ✓ |
| S16c | 6.5 SendUserFile/定时/Monitor·道具 | 发件盘／闹钟（Monitor 无） | `.tray` / `.alarm` 桌面道具（`.leanBack` 没有） | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（sendFile = [.tray]、alarm = [.alarm]、leanBack 为空） | ✓ |
| S16d | 6.5 SendUserFile/定时/Monitor·桌牌 | 「发给你一个文件」／「定了闹钟」／「在盯日志」 | `PlateCopy.toolText` | SPT-S › everyRowOfTheTableShowsItsPlateText（含 ScheduleWakeup / CronCreate） | ✓ |
| S17a | 6.5 EnterPlanMode·身体 | 在笔记本上写 | `.writingPad` | PM › everyRowOfTheStateToAnimationTable（EnterPlanMode → .writingPad） | ✓ |
| S17b | 6.5 EnterPlanMode·屏幕 | 大纲文档 | `.plan`：白纸 + 4 条要点 | SPT-S › dialogScreensHaveTheirButtonsOptionsAndOutline（4 个要点 (5,6/8/10/12)、静止）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S17c | 6.5 EnterPlanMode·道具 | 笔记本 | `.notepad` | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（`.writingPad` 道具 = [.notepad]） | ✓ |
| S17d | 6.5 EnterPlanMode·桌牌 | 「在做计划」 | `PlateCopy.toolText(.planEnter)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S18a | 6.5 等批准·身体 | 转身面向你，举手轻轻挥（1.2 Hz） | 持续 0.4 s 才转身；`.faceUser(.approval)`：手 x = ±2 px × sin(2π·1.2·t)；转身序列见 M20 | PT › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5、aWaitingBlipShorterThan0_4SecondsDoesNotTurnTheBuddy；SPT-S › tappingScratchingWritingAndWavingFrequencies（挥动 1.15–1.25 Hz、幅度 ±2 px、面向你只举一只手）、theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises | ✓ |
| S18b | 6.5 等批准·屏幕 | 权限对话框，带两个按钮 | `.permission`：灰「拒绝」+ 绿「允许」；等待类立即切屏（不受 0.8 s 最短停留限制） | SPT-S › dialogScreensHaveTheirButtonsOptionsAndOutline（灰色 7×3 与绿色 7×3 两个按钮、白色窗口、静止）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S18c | 6.5 等批准·气泡 | 钥匙气泡 + 工具图标 | `targetBubble`：`.approval(icon)`（bash / edit·write / web·browser / read·search / 其他） | PM › everyRowOfTheStateToAnimationTable（Bash、Edit 两行的图标名）；SPT-S › bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven（钥匙和 5 种工具图标都是 7×7） | ✓ |
| S18d | 6.5 等批准·桌牌 | 「等你批准 Bash · 2 分钟」 | `PlateCopy.activity(.waitingApproval)`、`waitSpoken` | SPT-S › everyRowOfTheTableShowsItsPlateText（120 秒 → 「等你批准 Bash · 2 分钟」）；PC › fileNamesClipsAndDurations | ✓ |
| S19a | 6.5 提问·身体 | 转身举手 | `.faceUser(.question)`：面向你、右手举过肩、表情 question | PT › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5；SPT-S › askPosesRaiseAHandOrHoldAClipboard（facing = front、表情 question、手高于肩） | ✓ |
| S19b | 6.5 提问·屏幕 | 带选项的对话框 | `.question`：「?」+ 3 个选项 | SPT-S › dialogScreensHaveTheirButtonsOptionsAndOutline（(5,8)(5,10)(5,12) 三个选项点、大「?」、静止） | ✓ |
| S19c | 6.5 提问·气泡 | 「?」气泡 | `targetBubble` → `.question` | PM › everyRowOfTheStateToAnimationTable | ✓ |
| S19d | 6.5 提问·桌牌 | 「有问题问你」 | `PlateCopy.activity(.asking)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S20a | 6.5 计划待审·身体 | 转身举起一块写字板 | `.faceUser(.plan)`：`holdClipboard`，两手托在胸前 | SPT-S › askPosesRaiseAHandOrHoldAClipboard（facing = front、举着写字板、双手等高）；PT › waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5 | ✓ |
| S20b | 6.5 计划待审·屏幕 | 计划文档 | `.plan` | PM › everyRowOfTheStateToAnimationTable；SPT-S › dialogScreensHaveTheirButtonsOptionsAndOutline | ✓ |
| S20c | 6.5 计划待审·气泡 | 写字板气泡 | `targetBubble` → `.plan`（`icon.board`） | PM › everyRowOfTheStateToAnimationTable | ✓ |
| S20d | 6.5 计划待审·桌牌 | 「计划好了，等你看」 | `PlateCopy.activity(.planReview)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S21a | 6.5 整理上下文·身体 | 把一摞纸塞进箱子 | `.compacting`：双手在纸堆 / 箱子间来回（x ±3 px，0.48 Hz），桌面上摆纸堆 + 箱子 | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（道具 = [.papers, .box]）；noPoseSwingsFasterThanFourHertz；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S21b | 6.5 整理上下文·屏幕 | 一行行被压成一块 | `.compact`：3 s 一轮，行越来越短越挤，最后压成 8×3 的深色块 | SPT-S › compactSqueezesRowsIntoOneBlockAndRetryShowsARotatingArrowAndDigits（占用的行数 ≥ 6 → ≤ 4、行越压越短、8×3 深色块 24 个像素） | ✓ |
| S21c | 6.5 整理上下文·道具 | 纸堆 / 箱子 | `.papers` + `.box` 桌面道具 | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses | ✓ |
| S21d | 6.5 整理上下文·桌牌 | 「在整理记忆」 | `PlateCopy.activity(.compacting)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S22a1 | 6.5 重试中·身体 | 挠头 | `.retry`：右手到后脑上方，x 每 267 ms 换一格 = 1.85 Hz | SPT-S › tappingScratchingWritingAndWavingFrequencies（手在后脑上方、挠动 1.5–2.0 Hz ≤ 2 Hz） | ✓ |
| S22a2 | 6.5 重试中·身体 | 轻敲显示器（≤ 2 Hz） | 没有这个动作（只有挠头） | — | 偏离（DESIGN §13「重试时「轻敲显示器」…」：重试是挠头 + 转圈屏幕 + 「2/10」像素数字） |
| S22b | 6.5 重试中·屏幕 | 缓慢转动的循环箭头 + 像素数字「2/10」 | `.retry(a, b)`：箭头 4 个位置每 0.42 s 转一格（1.68 s 一圈 ≈ 0.6 Hz），数字用 3×5 像素字体；「10/10」太宽时换 3×3 小转圈 | SPT-S › compactSqueezesRowsIntoOneBlockAndRetryShowsARotatingArrowAndDigits（箭头 4 个位置各 4 个像素、一圈 1.68 s、「2/10」的白色像素数恒等于字形像素数、「10/10」+ 小转圈）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S22d | 6.5 重试中·桌牌 | 「网络不稳，重试中 2/10」 | `PlateCopy.activity(.retrying)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S23a | 6.5 出错·身体 | 手扶额头 | `.facepalm`：头低 2 px，右手举到后脑（背对镜头看不到额头） | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（headDy = 2、右手 = headBackR） | 偏离（DESIGN §13「背对镜头的动作用位移近似」） |
| S23b | 6.5 出错·屏幕 | 静止的橙色三角警告 | `.warning` | SPT-S › stateScreens（60 个时刻逐像素相同、橙色三角 ≥ 20 像素、无红色）；RT › staticScreenClassificationMatchesWhatIsActuallyDrawn | ✓ |
| S23d | 6.5 出错·桌牌 | 「出错了」 | `PlateCopy.activity(.errored)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S24a | 6.5 被打断·身体 | 两手一摊「哇哦」，1.5 秒 | `.shrug`；`targetPose`：`el < 1.5` → shrug，之后 `.leanSide` | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（1.49 s 摊手、1.5 s 起靠着）、idleDozeSleepErrorInterruptedAndStretchPoses（两手向两侧摊开 ≥ 30 px）；AR › interruptedLasts3SecondsThenIdle | ✓ |
| S24b | 6.5 被打断·屏幕 | 停止标志 | `.stop`：红色八边形 + 白条 | SPT-S › stateScreens（静止、红色 ≥ 40 像素、白条） | ✓ |
| S24d | 6.5 被打断·桌牌 | 「被你打断了」 | `PlateCopy.activity(.interrupted)` | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S25a | 6.5 做完了·身体 | 伸懒腰，然后 3/4 侧身靠着（5.6：先等 0.4 s，伸 1.2 s） | `targetPose`：0.4 s 保持原姿势 → 1.2 s `.stretch` → `.leanSide` | SPT-S › aFinishedTurnWaitsThenStretchesThenLeansThroughTheWholePipeline（整条流水线：0.4 s 起伸懒腰、1.6–2.0 s 起靠着）、statesSwitchExactlyOnTheSpecifiedSeconds（0.5 / 1.59 / 1.6 s 边界）、idleDozeSleepErrorInterruptedAndStretchPoses（0.6 s 双手举到头顶、1.2 s 放下） | ✓ |
| S25b | 6.5 做完了·屏幕 | 绿色 ✓ | `.done`：9 个点 × 2 行的绿色对勾 | SPT-S › stateScreens（绿色恰好 18 个像素、静止） | ✓ |
| S25c | 6.5 做完了·道具 | 未读时显示器上插一面小旗 | `v.flag = snapshot.unread`；`SeatRenderer.drawMonitor` 画 `prop.flag`（显示器右上角） | SPT-S › theUnreadFlagIsPlantedOnTheMonitorOnlyWhileUnread（未读有旗、已读收旗、有无旗的差异只在旗子那一块）、aFinishedTurnWaitsThenStretchesThenLeansThroughTheWholePipeline（做完之后小旗一直插着） | ✓ |
| S25d | 6.5 做完了·桌牌 | 「做完了 · 3分12秒」 | `PlateCopy.activity(.finished)`、`spoken` | SPT-S › everyRowOfTheTableShowsItsPlateText（192 秒 → 「做完了 · 3分12秒」） | ✓ |
| S26a1 | 6.5 需要你处理·身体 | 3/4 侧身 | `.idle` 姿势 = 3/4 侧身靠着 | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（facing = 3/4 后）；PM › aBlockedIdleSessionShowsTheStickyNote | ✓ |
| S26a2 | 6.5 需要你处理·身体 | 点点便利贴 | 没有这个动作：blocked 时身体和普通空闲完全一样（只影响气泡和桌牌） | — | 偏离（DESIGN §13「…需要你处理时「点点便利贴」…」：靠着 + 静止的黄色「!」便利贴气泡） |
| S26c | 6.5 需要你处理·气泡 | 静止的黄色「!」便利贴 | `targetBubble`：idle 且 blocked → `.note`（`icon.note`，无动画） | PM › aBlockedIdleSessionShowsTheStickyNote；SPT-S › onlyTheThinkingAndSleepingBubblesAnimateAndTheStickyNoteStandsStill（`.note` 在任意时刻逐像素相同） | ✓ |
| S26d | 6.5 需要你处理·桌牌 | 「需要你处理」 | `PlateCopy.activity(.idle)`：`blocked` → 「需要你处理」 | SPT-S › everyRowOfTheTableShowsItsPlateText | ✓ |
| S27a1 | 6.5 空闲·身体 | 3/4 侧身靠着，每 30–60 秒喝一口、四处看 | `.idle`：45 s 一圈，t≈30 s 起 1.6 s 侧身四处看、t≈40 s 起 2.6 s 喝一口（按 seed 错开相位） | SPT-S › sippingAndLookingAroundHappenAtTheSpecifiedIntervals（3 个 seed：看 / 喝的间隔都在 30–60 s、1.6 s / 2.6 s） | ✓ |
| S27a2 | 6.5 打盹·身体 | 头一点一点往下垂 | `.doze`：头 y = 1 + round(0.5 + 0.5·sin 0.7t)，1–2 px，约 0.11 Hz | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（headDy 只有 1、2 两档、来回 < 0.2 Hz） | ✓ |
| S27a3 | 6.5 睡着·身体 | 趴在手臂上 | `.sleep`：躯干 +3、头 +6、双手搭键盘 | SPT-S › idleDozeSleepErrorInterruptedAndStretchPoses（torsoDy = 3、headDy = 6 是所有姿势里最低的、手在键盘上） | ✓ |
| S27b1 | 6.5 空闲/打盹/睡着·屏幕 | 暗色桌面／慢速屏保／关屏 | `.idleDesktop`、`.screensaver`（小方块每 0.8 s 挪一格）、`.off` | SPT-S › stateScreens（暗桌面三图标 + 任务栏；屏保 x = 1,1,2,3,4；关屏只剩 4 个反光像素）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S27b2 | 6.5 空闲/打盹/睡着·屏幕 | 待机灯缓慢呼吸 | `SeatRenderer.ledName`：3 阶呼吸（灭 → 半亮 → 亮 → 半亮），周期 4 s（SP-02 修复） | MT › theStandbyLightBreathesThroughThreeLevelsSlowly | ✓ |
| S27c | 6.5 打盹/睡着·气泡 | z 气泡；空闲有马克杯 | `targetBubble`：打盹 / 睡着 → `.zzz`（两个 z 不粘，TA-004）；每张桌子上常驻马克杯 | PM › everyRowOfTheStateToAnimationTable（打盹 / 睡着的气泡）；SPT-S › onlyTheThinkingAndSleepingBubblesAnimateAndTheStickyNoteStandsStill（zzz 会动）、everyDeskHasAMugAndTheSipReachesForIt；TA › sleepingBuddysTwoZsDoNotTouch | ✓ |
| S27d | 6.5 空闲/打盹/睡着·桌牌 | 「空闲」／「打盹 12 分钟」／「睡着了」 | `PlateCopy.activity`、`idleMinutes`；触发阈值 10 / 45 分钟在数据层 | SPT-S › everyRowOfTheTableShowsItsPlateText（「打盹 12 分钟」「睡着了」「空闲」）；AR › idleThenDozingThenSleepingAtTheThresholds | ✓ |
| S28a | 6.5 未知工具·身体 | 打字和鼠标交替 | `targetPose(.unknown)`：每 3 s 在 `.typing` / `.mouse` 之间换（SP-04 修复） | SPT-S › statesSwitchExactlyOnTheSpecifiedSeconds（2.99 / 3.0 / 5.99 / 6.0 s）；PM › everyRowOfTheStateToAnimationTable（未知工具两行） | ✓ |
| S28b | 6.5 未知工具·屏幕 | 带齿轮的通用窗口 | `.gear`：中心 3×3 + 4 个齿，两帧每 0.6 s 换 | SPT-S › stateScreens（两帧交替、齿轮琥珀像素 13 个）；PM › everyRowOfTheStateToAnimationTable | ✓ |
| S28d | 6.5 未知工具·桌牌 | 「在用 <Tool>」 | `PlateCopy.toolText(.unknown)`（工具名截 14 字） | SPT-S › everyRowOfTheTableShowsItsPlateText（「在用 FooTool」） | ✓ |
| S29a1 | 6.5 进场·身体 | 从门口走进来坐下 | `WalkerSystem`：门开缝 0.10 s → 人从门洞走出 → 走到椅子前 → 坐下 0.3 s（下沉 0 / 2 / 4 px） | RT › enteringWalkerAppearsOnlyAfterTheDoorStartedOpening；WO › walkingInTakesAboutTwoAndAHalfSecondsAndFarSeatsAreSpeedCapped、aSessionThatArrivesAfterLaunchWalksInAndSitsDownWhileOnesPresentAtLaunchAreAlreadySeated；SPT-S › sittingDownAndStandingUpAreThreeFramesOfAHundredMilliseconds | ✓ |
| S29a2 | 6.5 离场·身体 | 起身挥手走出门 | `WalkerSystem`：起身 0.3 s → 挥手 0.7 s → 走进门洞 → 门关 0.16 s | WO › leavingStandsWavesWalksOutAndTheDoorClosesBehindThem；RT › walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt；SPT-S › sittingDownAndStandingUpAreThreeFramesOfAHundredMilliseconds（WalkerSystem 的 0.3 / 0.3 / 0.7 s） | ✓ |
| S29b1 | 6.5 进场·屏幕 | 开机：5 级调色板渐变，300 ms | `SeatRenderer.drawMonitor` + `OfficeScene`：4×4 Bayer 抖动，`Int(boot×16)` 共 16 级、0.3 s | SPT-S › theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds（0…15 共 16 级、一路变亮、300 ms 后全亮）；MT › monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」；另见 §7「进场 / 离场」） |
| S29b2 | 6.5 离场·屏幕 | 关机：5 级调色板渐变，300 ms | `OfficeScene`：人一离开，最后的屏幕内容用同一条 Bayer 抖动倒放 300 ms（SP-01 修复，`SeatView.fade`） | MT › theMonitorFadesOutOver300msInsteadOfCuttingToBlack、retainedRenderingStaysIdenticalWhileTheMonitorFadesOut、anEmptySeatNeverFades；SPT-S › theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds（`screenFadeSeconds = 0.3`） | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」；小鱼缸 / 宠物条没有关机渐变见 §13「小鱼缸 / 宠物条没有离场时的显示器关机渐变」） |
| S30 | 6.5 附注·并行工具 | 显示一个小标签「×3」 | `PlateCopy.activity`：动作文案后加 ` ×N`（在桌牌文字里，不是单独的小标签） | SPT-S › everyRowOfTheTableShowsItsPlateText（并行 3 个 Grep → 「在找 "TODO" ×3」） | 偏离（DESIGN §13「并行工具的「×3」写在桌牌文字里」） |
| S31 | 6.5 附注·转身 | 朝过道那一侧转；镜像的朝向直接水平翻转图像 | `OfficeScene`：工位在世界中线右半边 → 向左转（`mirror`）；`SeatRenderer.draw` 用 `blitCanvas(… flipH: v.mirror)`；小鱼缸 / 宠物条各有自己的中线 / 槽位奇偶规则 | SPT-S › seatsTurnTowardsTheAisleAndAMirroredPersonIsTheFlippedImage（8 个座位：中心 ≥ 世界中线的向左转、左右两半都有人；同一个人 mirror 开 / 关的对象 ID 平面逐点互为左右翻转） | ✓ |
| S00 | 6.5 各行「—」列 | Read / Edit / Write / Bash / Web / MCP 浏览器 / computer-use / 重试 / 出错 / 被打断 / 未知工具的道具·气泡列，需要你处理的屏幕列：没有额外要求 | `Performer.targetBubble` 对这些状态返回 nil；这些姿势不带桌面道具；需要你处理时屏幕是暗桌面 | PM › everyRowOfTheStateToAnimationTable（这些行的气泡 = nil）；SPT-S › posesOfTheDashRowsCarryNoPropsAndTheSupervisorPointsThenFolds（19 种姿势都没有桌面道具） | ✓ |


### 2. 任务书 6.6 动作手感与防闪烁（和 6.5 相关的数字）

`Motion.swift` = `Sources/PixelKit/Motion.swift`。原来这一节没有任何针对弹簧 / 呼吸 / 眨眼 / 转身 / 气泡的语义测试（只有金图哈希和闪烁扫描）；现在 `SPT-S` 里逐条钉住了。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| M01 | 6.6 弹簧 | 从静止起步（v0 = 0），阻尼比 ζ ≈ 0.75，带轻微过冲和跟随 | `PixelSpring.init(zeta: 0.75)`、`snap(to:)` 速度清零；`Performer` 的 7 根弹簧（响应周期 0.26–0.34 s）都是默认阻尼 | SPT-S › springsStartFromRestWithZetaThreeQuartersAndOvershootSlightly（ζ = 0.75、v0 = 0、第一步只挪 0.06 px；10 px 的阶跃过冲 0.215 px = 2.2%，由过冲反推的有效 ζ ≈ 0.77；7 根弹簧的 ζ 都是 0.75） | ✓ |
| M02 | 6.6 弹簧 | 输出取整到整像素，带 ±0.6 px 迟滞 | `PixelSpring.step`：`abs(value − shown) > 0.6` 才换格 | SPT-S › springOutputHasAPlusMinusPointSixHysteresisAndSlowSpringsSnap（连续值 0.3 / 0.5 / 0.59 / −0.59 显示仍是 0；0.61 才换成 1；回退到 0.9 / 0.5 / 0.41 仍是 1；0.39 才回 0） | ✓ |
| M03 | 6.6 弹簧 | \|v\| < 0.5 px/s（且贴近终点）直接吸附到终点 | `PixelSpring.step`：`abs(velocity) < 0.5, abs(value − target) < 0.6` → 吸附 | SPT-S › springOutputHasAPlusMinusPointSixHysteresisAndSlowSpringsSnap（v = 0.1、距终点 0.1：一步后 isSettled、value = target；v = 20 不吸附） | ✓ |
| M04 | 6.6 弹簧 | 永远不要「动一下、停一下」的生硬感 | 身体 / 头 / 手的位移全部走 `PixelSpring`（`Performer.stepSprings`）；打字 / 写字这类逐格离散的小动作按 133 ms 的格子直接给整数偏移 | SPT-S › springsStartFromRestWithZetaThreeQuartersAndOvershootSlightly（10 px 的整数输出方向最多改 2 次，没有来回抖）；RT › officeHasNoFlickerAtEveryZoom、tankAndStripHaveNoFlicker、officeHasNoFlickerAtNightAndDuringLightTransition（2398 帧 × 3 个场景 × 3 个缩放，A→B→A 全部干净） | ✓ |
| M05 | 6.6 呼吸 | 每个 buddy 一直有呼吸起伏：4 秒一周期，1 像素 | `Performer.stepSprings`：`breathPhase(period 4)`，`> 0.62` 上、`< 0.38` 下（带迟滞）；头（和头发）随呼吸上下 1 px | SPT-S › everyBuddyBreathesOnePixelEveryFourSeconds（思考 / 睡着 / 空闲 / 打字四种状态：只有 0 / 1 两档、每 4.00 s 一次上升沿；头 y = 弹簧 + 呼吸；4 个 buddy 相位各不相同；`breathPhase` 0 / 2 / 4 s = 0 / 1 / 0） | ✓ |
| M06 | 6.6 频率上限 | 任何摆动都不超过 4 Hz | 最快的是 `.typingFast`（每只手 3.75 Hz）和 `.writingPad` 的竖直分量（3.7 Hz），其余 ≤ 2.5 Hz；`FlickerScan` 检查 4（质心过零 > 8 次 / 秒即报错） | SPT-S › noPoseSwingsFasterThanFourHertz（24 种姿势 × 7 个会动的量逐个数来回次数，最快 3.73 Hz，其余 ≤ 2.5 Hz）；RT › officeHasNoFlickerAtEveryZoom（含检查 4） | ✓ |
| M07 | 6.6 不许开关式闪烁 | 光标要么静止，要么在 3 个色阶间以 0.5 Hz 呼吸 | `ScreenContent.cursorColor()`：`breathPhase(period 2.0)`，`scr.dark / dim / white` 三阶（IDE / 编辑器 / notebook 共用） | SPT-S › theCursorBreathesThroughThreeLevelsAtHalfAHertzAndNeverBlinksOnAndOff（3 个色阶、只在相邻色阶间走、白色峰值间隔 2.00 s） | ✓ |
| M08 | 6.6 不许开关式闪烁 | 等待时的光晕在 3 个相邻色阶间以 0.8 Hz 循环，外加 1 Hz、2 像素的轻弹 | 光晕 = 等待灯（`led.wait.lo / wait / wait.hi`）1.25 s 一圈（SP-02 修复）；「轻弹」由举手挥动（1.2 Hz，±2 px）承担 | MT › theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz、activeAndAbsentLightsStayPut；SPT-S › tappingScratchingWritingAndWavingFrequencies（挥动 1.2 Hz、±2 px） | 偏离（DESIGN §13「「等待光晕」的「1 Hz、2 像素轻弹」」：由举手挥动承担） |
| M09 | 6.6 眨眼 | 每 5–8 秒一次，3 帧，总时长 ≥ 240 ms，只动眼睛；闪烁扫描里加白名单 | `Performer.blinkExpression`（间隔 5.4 s / 7.4 s 交替，半闭 90 ms → 闭 80 ms → 半闭 90 ms = 260 ms，只在正面 / 3/4 正面 / 侧面）；`CharacterArt.buildBlink`（覆盖层只有眼睛行）；`StageRun` 的 `allowRects = blinkRects` | SPT-S › blinksEveryFiveToEightSecondsInThreeFramesOfAtLeast240msAndOnlyTouchTheEyes（5 个 buddy × 60 秒：每次半闭 → 闭 → 半闭、0.24–0.30 s、间隔都在 5–8 s、背对镜头不眨；覆盖层精灵的像素只在第 7–9 行） | ✓ |
| M10 | 6.6 亮度变化 | 亮度变化至少用 250 ms 渐变 | 显示器开 / 关机（300 ms 抖动）和昼夜（20 分钟 Bayer）是渐变；屏幕内容切换、台灯开关、待机灯 / 等待灯的色阶变化是一步到位 | MT › theMonitorFadesOutOver300msInsteadOfCuttingToBlack；SPT-S › theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds、dayNightSwitchTakesTwentyMinutesAndEveryPixelFlipsExactlyOnce | 偏离（DESIGN §13「亮度变化 ≥ 250 ms 渐变只覆盖显示器开关机和昼夜」；另见 §13「屏幕内容切换是硬切」） |
| M11 | 6.6 亮度变化 | 显示器开机是 5 级调色板渐变，用时 300 ms | 同 S29b1：16 级 Bayer 抖动，300 ms | SPT-S › theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds | 偏离（DESIGN §13「显示器开机 / 关机是 16 级 Bayer 抖动渐变」） |
| M12 | 6.6 亮度变化 | 绝不闪白，绝不黑帧，也绝不淡出到全黑 | `FlickerScan` 检查 1（整体亮度突变）、检查 5；关机渐变的终点是暗灰蓝的 `plastic` 色，不是纯黑 | RT › officeHasNoFlickerAtEveryZoom / …AtNightAndDuringLightTransition / tankAndStripHaveNoFlicker（0 个发现）；SPT-S › noFrameIsBlackAndTheMonitorNeverFadesToPureBlack（关屏每个像素的最大通道 ≥ 0x20；演示剧本 160 帧 × 2 个时段：没有纯黑像素、最暗的一帧近黑像素 < 10%）；mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette（点击圈期间白色像素数不变） | ✓ |
| M13a | 6.6 窗口出现时 | 先渲染好第一帧，再把窗口显示出来（办公室） | `AppModel.showOffice`：`office.render(model:force: true)` 之后才 `showWindow` | SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindowThatRendersItsFirstFrameBeforeItIsShown（窗口没显示时 `render(force:)` 已经产出第一帧）；SPT-A › dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified（源码里 render 在 showWindow 之前） | ✓（间接验证：`showOffice` 里两行的先后顺序只能钉源码；见清单 I-05） |
| M13b | 6.6 窗口出现时 | 同上（小鱼缸 / 宠物条） | `PanelShow.show(isVisible:renderFirstFrame:orderFront:)`（B-005）；`TankPanelController.show` / `StripPanelController.show` 用它 | PS › aPanelThatIsNotOnScreenGetsItsFirstFrameBeforeItAppears、aPanelThatIsAlreadyOnScreenIsNotOrderedFrontAgain、aHiddenPanelIsRenderedOnlyWhenItsFirstFrameIsRequested | ✓ |
| M14 | 6.6 白天 / 黑夜切换 | 4×4 Bayer 抖动，约 20 分钟完成，每个像素只翻转一次 | `DaySchedule.state(atHour:)`（20 分钟的过渡）、`Resolved.useB`（`bayer4 < threshold`） | SPT-S › dayNightSwitchTakesTwentyMinutesAndEveryPixelFlipsExactlyOnce（4×4 共 16 个位置在 level 0…16 里各恰好翻转 1 次；4 个过渡各 20 分钟、级数单调 0→15）；RT › officeHasNoFlickerAtNightAndDuringLightTransition | ✓ |
| M15 | 6.6 帧时长·打字 | 4 帧，每帧 125 ms | `PoseLibrary.frame(.typing)`：每格 133 ms | SPT-S › typingBeatsAreFourFramesOf133msAndWriteIsTwiceAsFast（每格 133 ms、4 格一轮） | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| M16 | 6.6 帧时长·鼠标 | 2 帧，每帧 300 ms | 鼠标手用 `sin(1.3t)` / `cos(0.9t)` 取整成 ±1 px 的缓慢漂移，不是 2 个 300 ms 的帧 | SPT-S › bodiesLeanAndHandsGoWhereTheTableSays（鼠标手离鼠标 ≤ 1 px、有多个位置、不是死的） | 偏离（DESIGN §13「鼠标「2 帧 × 300 ms」、走路「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」」） |
| M17 | 6.6 帧时长·走路 | 侧面走路 6 帧 × 110 ms；正面 / 背面 4 帧 × 130 ms | `WalkerSystem.draw`：所有朝向共用 1.6 步/秒的连续相位，`BuddyRig.renderStanding` 按 sin 取整摆腿 / 手臂 | WO › walkingInTakesAboutTwoAndAHalfSecondsAndFarSeatsAreSpeedCapped；RT › walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt | 偏离（DESIGN §13「鼠标「2 帧 × 300 ms」、走路「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」」） |
| M18 | 6.6 帧时长·坐下 / 起立 | 3 帧 | `WalkerSystem.draw`：下沉 0 / 2 / 4 px 三档各约 0.1 s（`sitTime` / `standTime` 0.3 s） | SPT-S › sittingDownAndStandingUpAreThreeFramesOfAHundredMilliseconds（坐下 0.3 s 里恰好 3 种画面、起立 3 种） | ✓ |
| M19 | 6.6 转身 | 约 0.75 秒，椅子同步转动 | 6 步共 450 ms，椅子的朝向逐步跟着（`chairFacing == facing`）；举手由弹簧完成；转身 + 举手到位共约 0.55 s | SPT-S › theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises（每步的椅子朝向 = 人的朝向；转身 + 举手到位 ≤ 0.75 s） | 偏离（DESIGN §13「转身第 7 步「举手」」：总时长约 0.55 s，任务书约 0.75 s） |
| M20 | 6.6 转身 | 6 步：背面下沉 1 px 80 ms → 3/4 背 70 → 侧面 60 → 3/4 正 70 → 正面 90 → 回弹 1 px 80 | `Performer.resolveFrame`（`[(.back,.08,+1) (.34back,.07) (.side,.06) (.34front,.07) (.front,.09) (.front,.08,−1)]`） | SPT-S › theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises（每一步的头尾和中点：朝向、躯干 +1 / 0 / −1、椅子朝向；6 步合计 450 ms；第 7 步起 `turning = false`） | ✓ |
| M21 | 6.6 转身 | 第 7 步：举手 3 帧，70 / 70 / 90 ms，过冲 1 像素后回落 | 不是 3 个离散帧：由手的弹簧完成（响应周期 0.26 s、ζ = 0.75）：约 0.1 s 升到位，理论过冲 0.45 px < ±0.6 px 的取整迟滞，画面上没有整像素过冲 | SPT-S › theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises（举手到位 ≤ 0.75 s，最低点不超过目标 1 px） | 偏离（DESIGN §13「转身第 7 步「举手」」） |
| M22 | 6.6 气泡 | 11–15 px，用 3 帧由小变大弹出，不用非整数缩放 | `SeatRenderer.bubbleSize`：age < 60 ms → 7 px、< 120 ms → 11 px、之后 15 px（手绘的三档整数尺寸精灵，共用左下角，不换位置） | SPT-S › bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven（尺寸序列 7,7,11,11,15,15、三档精灵宽度 = 7 / 11 / 15、稳定态 15 在 11–15 里） | 偏离（DESIGN §13「气泡弹出 7 → 11 → 15 px」：第一帧 7 px 比任务书的下限 11 小一档） |
| M23 | 6.6 气泡 | 图标是 7×7 | `BubbleArt`：每个图标 7 行 × 7 列的字符网格 | SPT-S › bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven（钥匙 / 问号 / 写字板 / 放大镜 / 书 / 工具箱 / 便签 / 杯子 + 5 种工具图标，全部 7×7）；SPR › spriteBooksHaveNoErrors | ✓ |


### 3. 任务书 7.1 三种形态 + 菜单栏 + Dock

文件都在 `Sources/BuddyOffice/`（AppKit 层）。原来这一层没有测试目标；现在有 `Tests/BuddyOfficeTests/`（约 30 个文件，见 §0），本次新增 `SPT-A`（`Tests/BuddyOfficeTests/SpecTraceUITests.swift`）。测试里的面板 / 窗口对象只建不显示（不 `orderFront`、不弹任何窗口、不碰真实数据）；真的要真实鼠标 / 窗口服务器 / 系统弹窗才能验的，状态写 ✓（间接验证），并在末尾「间接验证清单」里逐条列出（`I-xx`）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| U01 | 7.1 办公室窗口 | 普通 NSWindow：带标题栏、可缩放，内容铺满，标题栏透明 | `OfficeWindowController.init`：`.titled .closable .miniaturizable .resizable .fullSizeContentView`、`titlebarAppearsTransparent`、`titleVisibility = .hidden`、`contentView = pixelView`；`contentResizeIncrements` = 缩放倍数 | SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindowThatRendersItsFirstFrameBeforeItIsShown（样式、标题栏透明、内容视图 = pixelView、标题栏右侧挂着像素按钮） | ✓ |
| U02 | 7.1 办公室窗口 | 窗口位置自动保存 | `setFrameAutosaveName("BuddyOfficeMainWindow")`；`AppModel.showOffice`：只有第一次运行（没存过位置）才 `center()` | SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindowThatRendersItsFirstFrameBeforeItIsShown（`frameAutosaveName == "BuddyOfficeMainWindow"`：AppKit 的标准自动保存就靠这个名字）；AppKit 真的写 / 读位置那一半没法在单测里验：DESIGN §9.1「窗口位置记住」实测记录（发现并修了每次都居中的 bug），I-03 | ✓ |
| U03 | 7.1 办公室窗口 | 点关闭只是隐藏，App 继续运行 | `OfficeWindowController.windowShouldClose`（`orderOut` + 记 `office.visible = false` + `return false`）；`applicationShouldTerminateAfterLastWindowClosed` = false | SPT-A › closingTheOfficeWindowOnlyHidesItAndRemembersThatItIsClosed（关闭按钮调用的 `windowShouldClose` 真的返回 false、把 `office.visible = false` 写进设置、窗口没被释放；`AppDelegate().applicationShouldTerminateAfterLastWindowClosed` 真的返回 false）、dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified；点真实的关闭按钮见 I-03 | ✓ |
| U04a | 7.1 办公室窗口 | 标题栏像素按钮：缩成小鱼缸 | `TitleBarButtonBar.tank`（`PixelButton`）；`AppModel.shrinkToTank`（`tank.visible = true`、`office.visible = false`）；`start()` 里接线 | SPT-A › theThreeTitleBarButtonsClickOnlyWhenReleasedInsideAndShrinkingSwapsTheOfficeForTheTank（三个 24 pt 按钮；按下 + 在里面抬起才算点击；`shrinkToTank` 后设置 = 小鱼缸开 / 办公室关，应用计划 = 办公室收起 + 小鱼缸出现）；theTitleBarButtonsAreWiredToTheThreeActions（接线） | ✓ |
| U04b | 7.1 办公室窗口 | 标题栏像素按钮：打开桌面宠物 | `TitleBarButtonBar.strip`；`start()`：`tb.strip.onClick` 开关 `strip.visible`（不动办公室）；按钮的「亮着」由 `update(tankOn:stripOn:)` 决定 | SPT-A › theThreeTitleBarButtonsClickOnlyWhenReleasedInsideAndShrinkingSwapsTheOfficeForTheTank（按钮点击语义、`on` 状态）；theTitleBarButtonsAreWiredToTheThreeActions（钉住接线）；真实点击见 I-01；`--test-titlebar` 日志（DESIGN §8） | ✓（间接验证：I-01） |
| U04c | 7.1 办公室窗口 | 标题栏像素按钮：设置 | `TitleBarButtonBar.settings`；`start()`：`tb.settings.onClick` → `showSettings` | SPT-A › theSettingsWindowHostsTheSwiftUIForm（设置窗口能建）、theTitleBarButtonsAreWiredToTheThreeActions（钉住接线）；`showSettings` 会显示真窗口，不在单测里跑，见 I-01 | ✓（间接验证：I-01） |
| U04d | 7.1 办公室窗口 | （美术）12×12 木牌底板 4 种状态 + 10×10 图标，最近邻放大 | `ChromeArt`（`plate.normal/hover/pressed/on` + `chrome.tank/strip/gear`）；`PixelButton` 最近邻绘制 | SPT-A › titleBarButtonArtIsTwelveByTwelveWithFourStatesAndTenByTenIcons（4 块 12×12 底板、3 个 10×10 图标、每个图标 4 种状态互不相同） | ✓ |
| U05a | 7.1 办公室窗口（另见 6.3） | 悬停卡片直接画在场景里 | `OfficeScene.render`：`options.hoverSnapshot` → `HoverCard.make` → `blitCanvas` 进场景（位置搜索：不盖住那个人自己的头 / 屏幕 / 气泡，窗口再小也有兜底位置） | SPT-S › theHoverCardIsPaintedIntoTheOfficeScene（悬停时画布多出卡片、帧里多出 card.title / card.line 文字；不悬停没有）；TA › hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner、plateTextUnderTheHoverCardIsHidden | ✓ |
| U05b | 7.1 办公室窗口（另见 6.3） | 悬停 250 ms 后出卡片 | `OfficeWindowController.render`：`model.time − hoverSince >= 0.25` | SPT-A › theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms（真实时钟：鼠标刚停到小人身上没有卡片、停满 250 ms（隔了 0.35 s）之后卡片画进场景、移开就收起；「还没有」那一半只在两次渲染隔得很近时才断言，免得被调度抖动误伤）；hoverCardsAppearAfter250msOnAllThreeSurfaces（三个面的判定常数都是 0.25） | ✓ |
| U06 | 7.1 小鱼缸 | NSPanel，无边框、不抢焦点（nonactivating） | `FloatingPanel`（`.borderless, .nonactivatingPanel`、`canBecomeKey/Main = false`、`hidesOnDeactivate = false`） | SPT-A › thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent（没有标题栏、nonactivatingPanel、不能成为 key / main、不随 App 失活隐藏） | ✓ |
| U07 | 7.1 小鱼缸 | `level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` | `FloatingPanel.init` 的默认参数；`TankPanelController` 沿用 | SPT-A › thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent（小鱼缸面板 level = .floating、collectionBehavior 与规格逐项相等） | ✓ |
| U08 | 7.1 小鱼缸 | 按住背景可以拖动；`canBecomeKey = false` | `TankPanelController`：`pixelView.dragsWindowOnBackground = true`，背景单击交给 `performDrag`（不用会吞点击的 `isMovableByWindowBackground`，A-002）；`canBecomeKey = false` | SPT-A › theTankIsDraggedByItsBackgroundThroughThePixelViewNotAppKitsBackgroundDrag；PD › onlyASingleClickOnTheBackgroundStartsAWindowDrag、mouseDownRoutesBackgroundDragsAndBuddyClicksTheRightWay；PV › pixelViewAndTitleBarButtonsNeverLetAppKitStartAWindowDrag；真实拖动手感见 I-01 | ✓ |
| U09a | 7.1 小鱼缸 | 工位格 48×56 的紧凑版，排 1–2 行 | `TankScene`：`cellW 48 cellH 56`、`layout(count:)`（≤ 4 个一行，5–8 个两行 × 4 列） | SPT-S › tankAndStripGeometryMatchTheSpec（0…12 人：1–2 行、≤ 4 列、显示数 = min(8, max(n, 2))；1 / 4 人一行、5 / 8 人两行） | ✓ |
| U09b | 7.1 小鱼缸 | 最多显示 8 个人，更多的显示 "+N" | `TankScene.layout`：`extra = count − 8`；右下角木牌 + 像素数字 | RT › tankAndStripShowAnOverflowBadgeBeyondEightPeople（6 / 8 / 9 / 12 人）；SPT-S › tankAndStripGeometryMatchTheSpec（extra 逐个对） | ✓ |
| U09c | 7.1 小鱼缸 | 顶部有一条窄墙，上面有窗户和挂钟 | `TankScene.wallH = 26`；`bake` 画墙 / 窗框 / 挂钟，`skyRects` = 天空玻璃 + 钟面 | SPT-S › tankAndStripGeometryMatchTheSpec（墙高 26、总高 = 26 + 行数 × 56 + 8、窗户玻璃和钟面的矩形都在墙上） | ✓ |
| U10 | 7.1 小鱼缸 | 双击回到办公室 | `TankPanelController.click`：点空白处 `count >= 2` → `onDoubleClickBackground` → `AppModel.expandToOffice` | SPT-A › doubleClickingTheTanksBackgroundGoesBackAndClickingABuddyJumps（在进程内真的渲染一张小鱼缸，找到背景像素：单击不触发、双击触发 1 次；小人身上双击不算回办公室）；真实的窗口服务器点击见 I-01（`--test-tank-click` 日志） | ✓ |
| U11 | 7.1 小鱼缸 | 悬停卡片用单独的 HoverPanel 显示 | `HoverPanelController`（`.statusBar` 层、`ignoresMouseEvents`）；`TankPanelController.render`：250 ms 后 `hover.show` | SPT-A › thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent（悬停面板是独立的面板、不拦截鼠标、level = .statusBar；小鱼缸 / 宠物条各有自己的一个） | ✓ |
| U12 | 7.1 桌面宠物条 | NSPanel，无边框、不抢焦点，背景透明（`isOpaque = false`、`.clear`），没有阴影 | `FloatingPanel`；`StripPanelController.init`：`hasShadow = false`、`PixelView.makeTransparent`；画布没有墙和地板 | SPT-A › thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent（isOpaque = false、backgroundColor = .clear、hasShadow = false、nonactivating）；SPT-S › tankAndStripGeometryMatchTheSpec（画布四角完全透明） | ✓ |
| U13 | 7.1 桌面宠物条 | 窗口只和那一群 buddy 一样宽 | `StripScene.render`：画布宽 = `min(8, n) × 56 (+ 24 的「+N」列)`；`StripPanelController.render`：窗口 = 画布 × 缩放 | SPT-S › tankAndStripGeometryMatchTheSpec（3 人 → 168 × 140）；SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（窗口 = 3 × 56 × 倍数）；RT › tankAndStripShowAnOverflowBadgeBeyondEightPeople、stripKeepsSeatedBuddiesStillWhenSomeoneNewArrives | ✓ |
| U14 | 7.1 桌面宠物条 | 高度 = (64 + 20 气泡 + 56 卡片) × 缩放；底边贴 `visibleFrame.minY` | `StripScene`：`cardH 56 + bubbleH 20 + cellH 64` = 140；`StripPanelController.origin`：`y = vf.minY` | SPT-S › tankAndStripGeometryMatchTheSpec（56 / 20 / 64 与总高 140）；SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（1 / 2 / 3 倍：窗口高 = 140 × 倍数，`frame.minY == visibleFrame.minY`）；SL › rightLeftCenterAndUnknownAlignments | ✓ |
| U15 | 7.1 桌面宠物条 | 默认靠右，可以改成靠左或居中 | `Settings`：`strip.align` 默认 `right`；`StripPanelController.origin`（left / center / right）；设置改了立刻重新定位（A-006） | SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（默认 right）、settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（right / left / center 三档：窗口位置 = `origin(align:…)`、`scene.alignRight`）；SL › rightLeftCenterAndUnknownAlignments | ✓ |
| U16 | 7.1 桌面宠物条 | 地上画一层抖动的影子 | `SeatRenderer.draw`：桌下 / 椅下 `floor.gap` 抖动填充（不带对象 ID） | SPT-S › tankAndStripGeometryMatchTheSpec（宠物条画布里有 > 60 个 `floor.gap` 抖动像素，且都不参与命中） | ✓ |
| U17 | 7.1 桌面宠物条 | 窗口层级默认 `.floating`，可以改成桌面层级 | `StripPanelController.applyLevel`（`strip.level == "desktop"` → `desktopIconWindow + 1`）；设置页「层级」 | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（默认 .floating；改成 desktop 后 level = `CGWindowLevelForKey(.desktopIconWindow) + 1`） | ✓ |
| U18 | 7.1 桌面宠物条 | `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`；全屏的桌面空间里默认不显示 | `applyLevel`：默认三项；`strip.fullscreen`（默认 false）打开才加 `.fullScreenAuxiliary` | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（默认 = 三项逐项相等；打开「全屏里也显示」多一个 `.fullScreenAuxiliary`）、everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（`strip.fullscreen` 默认 false） | ✓ |
| U19 | 7.1 桌面宠物条·点穿 | 每秒 30 次读 `NSEvent.mouseLocation`；鼠标离得超过 100 pt 降到 10 次 | `StripPanelController.startPolling / poll`：`Timer(1/30)`；`insetBy(−100, −100)` 之外每 3 次只做 1 次 = 10 Hz | SPT-A › theStripPollingRatesAndDistancesStayAsSpecified（钉住 30 Hz 定时器、100 pt 外扩、每 3 次做 1 次）、noAccessibilityPermissionAPIsAreUsed（只读 `NSEvent.mouseLocation`）；`poll()` 要面板真的可见、跑在真实 RunLoop 上，频率没法在单测里量：I-02 | ✓（间接验证：I-02） |
| U20 | 7.1 桌面宠物条·点穿 | 对象 ID 缓冲做命中测试，外扩 1 像素，据此切换 `ignoresMouseEvents` | `PixelView.hitID(at:dilate:)` → `Canvas.hitID`（8 邻域）；`StripPanelController.evaluate` | SPT-A › theStripInterceptsBuddyPixelsWithAOnePixelHaloAndLetsEverythingElseThrough（真实渲染一条宠物条：小人身上 → 拦截；小人边上 1 像素 → 仍拦截；2 像素外 / 空白处 / 很远 → 点穿；`ignoresMouseEvents` 只在状态变化时切换，共 2 次）；RT › personPixelsCarryTheirSeatIDAndTheWallCarriesNone；HT › emptyAndOffDutySeatsAreNotClickable；真实鼠标下的效果见 I-02（`--self-test` 的 `panelsSelfTest`） | ✓ |
| U21 | 7.1 桌面宠物条·点穿 | `acceptsFirstMouse = true`，点一下不会把 App 激活 | `PixelView.acceptsFirstMouse`；`FloatingPanel` 是 nonactivating | SPT-A › thePanelsAreBorderlessNonActivatingFloatingAndTheStripIsTransparent（`acceptsFirstMouse(for:)` 真的返回 true、面板样式含 nonactivatingPanel、不能成为 key / main）；「点一下不激活 App」是窗口服务器的行为：DESIGN §2 M0 第 1 项（真实点击日志 `appActive=false`），I-01 | ✓ |
| U22 | 7.1 桌面宠物条·点穿 | 不需要辅助功能权限 | 只用 `NSEvent.mouseLocation`；没有 `AXIsProcessTrusted` / `CGEventTap` / `addGlobalMonitor` | SPT-A › noAccessibilityPermissionAPIsAreUsed（源码审计：这类 API 一个都没有）；SA › noNetworkAndNoCredentialAPIs 等 | ✓ |
| U23 | 7.1 桌面宠物条·交互 | 悬停 250 ms 出卡片（三个面都一样） | `StripPanelController.evaluate`、`TankPanelController.render`、`OfficeWindowController.render` 里都是 `>= 0.25` | SPT-A › hoverCardsAppearAfter250msOnAllThreeSurfaces（三个文件的判定常数）；CA › theHoverCardIsRebuiltOnlyWhenItsContentCanHaveChanged；真实悬停见 I-01 | ✓（间接验证：I-01） |
| U24 | 7.1 桌面宠物条·交互 | 左键点击跳到会话 | 三个面的 `onClick` 都接到 `AppModel.jump`（办公室按座位号、小鱼缸 / 宠物条按渲染那一刻的快照 key，B-002） | SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindowThatRendersItsFirstFrameBeforeItIsShown（办公室：点小人拿到座位号）、doubleClickingTheTanksBackgroundGoesBackAndClickingABuddyJumps（小鱼缸）、theStripInterceptsBuddyPixelsWithAOnePixelHaloAndLetsEverythingElseThrough（宠物条）；JT › everySeatMapsToItsOwnSessionAndItsOwnTarget、afterSeatsAndSessionsChangeAClickStillResolvesToWhoSitsThereNow、danglingSeatsNeverJump；AM › clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal | ✓ |
| U25 | 7.1 桌面宠物条·交互 | 右键菜单：跳转、换个造型、隐藏这个 buddy、打开办公室 | `AppModel.showContextMenu`（四项按这个顺序；另有「显示被隐藏的 buddy」「设置…」） | SPT-A › theContextMenuOffersJumpRerollHideAndOpenOfficeInThatOrder（钉住四项及顺序；`NSMenu.popUpContextMenu` 是模态的，单测不去弹）；每一项背后的行为各有测试：JT › everySeatMapsToItsOwnSessionAndItsOwnTarget（跳转）；AL › rerollWaitsForTheNewSaltAndThenEveryPlaceAgrees、rerollOnlyTouchesTheChosenBuddy（换造型）；AM › theAutoQuitLiveSessionCheckCountsHiddenBuddies；AF › aHiddenBuddyDisturbsNobodyButStillCountsAsALiveSession（隐藏） | ✓（间接验证：I-06） |
| U26a | 7.1 宠物条·多屏 | 可以选主屏幕 | `StripScreenPicker.pick`：`main`（默认）→ 主屏幕；设置页「显示在」 | SK › mainAndUnknownValuesUseThePrimaryScreen | ✓ |
| U26b | 7.1 宠物条·多屏 | 可以选鼠标所在的屏幕 | `StripScreenPicker.pick`：`mouse`；`poll()` 每 0.5 s 重新定位（A-006） | SK › mouseFollowsTheScreenTheMouseIsOn；SL › anyChangeOfThePlacementInputsTriggersARepositionAndNothingElseDoes | ✓ |
| U26c | 7.1 宠物条·多屏 | 指定某块屏幕（按 ID 和名字记住） | `StripScreenPicker`：`id:<NSScreenNumber>\|<名字>`，先按 ID、再按名字找；设置页列出已连接的显示器（B-007） | SK › aChosenScreenIsFoundByIDThenByNameAndFallsBackToThePrimaryWhenUnplugged、settingsPageOptionsAlwaysContainTheCurrentValue | ✓ |
| U27 | 7.1 宠物条·多屏 | 监听 `didChangeScreenParametersNotification` | `StripPanelController.init`：订阅 → `screensChanged` → `reposition` | SPT-A › aScreenParametersChangeRepositionsTheStrip（把宠物条挪开，发一条同名通知（进程内），它回到 Dock 上方的位置）、theStripPollingRatesAndDistancesStayAsSpecified（钉住订阅）；系统的真实显示器变化造不出来：I-04 | ✓ |
| U28 | 7.1 宠物条·多屏 | 每 2 秒检查一次 `visibleFrame`（Dock 移动 / 改变大小） | `StripPanelController.poll`：每 0.5 秒 `repositionIfNeeded()`（比任务书的 2 秒更勤；同时看鼠标所在屏幕），`Placement` 变了才 `reposition()`（A-006 / B-007） | SPT-A › theStripPollingRatesAndDistancesStayAsSpecified（30 Hz × 每 15 次 = 0.5 s）；SL › anyChangeOfThePlacementInputsTriggersARepositionAndNothingElseDoes（Dock 改大小 = 可见区域变了就重新定位，什么都没变不动）；SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（改「位置」立刻生效） | 偏离（DESIGN §13「应用层的决定」·桌面宠物：「每 0.5 秒（任务书写 2 秒）检查 `visibleFrame` / 鼠标所在屏幕」） |
| U29 | 7.1 宠物条·多屏 | 所在屏幕被拔掉时回到主屏幕 | `StripScreenPicker.pick`：找不到 ID 也找不到名字 → 主屏幕 | SK › aChosenScreenIsFoundByIDThenByNameAndFallsBackToThePrimaryWhenUnplugged | ✓ |
| U30 | 7.1 菜单栏 | 图标是 18 pt 像素模板图，有「正常 / 有人在忙」两种 | `MenuBarIcon`（18×18 美术像素，2 倍最近邻成 36 px 当 18 pt）；`StatusItemController.update`：`isTemplate = kind != .waiting` | SPT-A › menuBarIconsAreEighteenPointTemplatesExceptTheColouredWaitingOne（normal / busy 的每个像素只有透明或纯黑、36×36、三种图标互不相同；源码里 18 pt 和 `isTemplate` 判断）；AF › menuBarIconKindAndDockBadgeLabels；菜单栏里的真实观感见 I-06 | ✓ |
| U31 | 7.1 菜单栏 | 有人等你时换成彩色的举手图标，不做成模板图 | `StatusItemController.iconKind`：`waiting > 0` → `.waiting`，`isTemplate = false` | SPT-A › menuBarIconsAreEighteenPointTemplatesExceptTheColouredWaitingOne（举手图标 ≥ 4 种颜色、含橙 / 黄）；AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（等待 → `.waiting`，批准后恢复） | ✓ |
| U32 | 7.1 菜单栏·菜单 | 每个 buddy 一行：状态图标、标题、当前动作，点击跳转 | `StatusItemController.menuNeedsUpdate`（等你 🙋 / 忙 ⌨️ / 未读 🚩 / 空闲 ☕️ + 标题 + `PlateCopy.activity`；点击 → `onJump`；没人时「今天还没人上班」） | SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（4 种状态的行、点第一行拿到 t:0、隐私模式不出现标题 / 命令、没人时一行灰色文字） | ✓ |
| U33 | 7.1 菜单栏·菜单 | 开关：办公室窗口 / 小鱼缸 / 桌面宠物 / 菜单栏图标 / Dock 图标 | `StatusItemController.menuNeedsUpdate`（五项，勾选状态取自设置，点一下翻转） | SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（五项的标题顺序、勾选 = 设置值、逐个点击后设置翻转） | ✓ |
| U34 | 7.1 菜单栏·菜单 | 演示模式（看看所有动作） | 「演示模式（看看所有动作）」→ `AppModel.setDemo`（换成演示数据源） | SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（点一下 → `model.demo`、建出演示数据源）；AM › switchingTheDataSourceResetsTheFirstDataFlagAndStopsTheOldOne | ✓ |
| U35 | 7.1 菜单栏·菜单 | 设置… / 退出，顺序：buddy 行 → 开关 → 演示模式 → 设置 → 退出 | 同上（分隔线位置一致） | SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（整份菜单的标题 / 分隔线序列） | ✓ |
| U36 | 7.1 Dock | 默认显示 Dock 图标；隐藏时切换成 `.accessory` | `ApplyPlanner.plan`：`activationRegular`；`AppModel.applySettings` → `NSApp.setActivationPolicy(regular ? .regular : .accessory)` | AP › theFirstApplyDoesEverything（第一次应用 = `.regular`）、onlyTheChangedEntriesAreTouched（关掉 Dock 图标 → `activationRegular == false`）；SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（`ui.dockIcon` 默认 true）、dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified（钉住 `.regular / .accessory` 调用） | ✓ |
| U37 | 7.1 Dock | 所有入口里至少要保留一个可见 | `ApplyPlanner.entryFallback`：五个入口全关（含只剩空宠物条）→ 强制补 Dock 图标，并写回 `ui.dockIcon`（A-024 / B-008） | AP › atLeastOneEntryIsAlwaysKept、aLoneEmptyPetStripIsNotAnEntryPoint、aForcedDockIconIsWrittenBackSoTheSettingsPageDoesNotSayOff | ✓ |
| U38 | 7.1 Dock | 从 Dock 重新打开 App 时显示办公室窗口 | `AppDelegate.applicationShouldHandleReopen`：`showOffice()` + `office.visible = true` | SPT-A › dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified（钉住：先 `showOffice()` 再 `return true`）；`showOffice` 会显示真窗口，不在单测里跑：I-03 | ✓（间接验证：I-03） |
| U39 | 7.1 Dock（可选） | 全局快捷键 ⌃⌥⌘B 开关办公室窗口，不需要辅助功能权限 | `HotKey`（Carbon `RegisterEventHotKey(kVK_ANSI_B, controlKey\|optionKey\|cmdKey)`）；`hotkey.enabled` 默认 false | SPT-A › dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified（钉住键码和修饰键）、noAccessibilityPermissionAPIsAreUsed；AP › nothingChangedMeansNothingToDo（热键只在开关变化时注册 / 注销）；真的注册热键会占用系统级快捷键，不在单测里跑：I-13 | ✓（间接验证：I-13） |
| U40 | 7.1 Dock（可选） | Dock 图标里显示实时的迷你画面（最多每秒 2 帧） | 没做（Dock 角标 + 图标弹跳 + 菜单栏举手图标 + 场景气泡已经够用；每秒重绘 Dock 图标会多一路渲染，占 CPU 预算） | — | 偏离（DESIGN §10「已知限制」最后一条＋§10 汇总表「Dock 图标里显示实时的迷你画面（可选）」） |

**补充核对：6.2「空办公室」牌子（和 7.1 的窗口 / 小鱼缸相关）**

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| U41a | 6.2 空办公室（补充） | 一个会话都没有时，办公室里显示一块牌子「今天还没人上班」 | `OfficeScene.signText / signGeometry / drawSign`（摆在最后一张桌子后面那个空格子的地毯上，画在桌椅上面）；`render` 里 `signZoom` | RT › emptyOfficeAndTankShowTheNobodyIsInSign（空 → 有牌子；来 2 个人 → 没有；只剩下班工位 → 没有；人走光 → 又回来）；TA › emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks（缩放 1–5 × 白天 / 夜里）；RT › retainedRenderingMatchesFullRedrawWithNobodyAtAll | ✓ |
| U41b | 6.2 空办公室（补充） | 小鱼缸里同样显示 | `TankScene.signRect`、`render(… emptySign:)` | RT › emptyOfficeAndTankShowTheNobodyIsInSign（小鱼缸部分） | ✓ |
| U41c | 6.2 空办公室（补充） | App 刚启动、第一批数据到来之前不显示（否则每次启动先闪一下） | `AppModel.gotData` → `OfficeWindowController.render`、`TankPanelController.render` 的 `emptySign = model.gotData` | RT › emptyOfficeAndTankShowTheNobodyIsInSign（`emptySign = false` 时办公室和小鱼缸都不出牌子）；AM › switchingTheDataSourceResetsTheFirstDataFlagAndStopsTheOldOne（换数据源之后 `gotData` 重置） | ✓ |
| U41d | 6.2 空办公室（补充） | 牌子随缩放保持清晰；宠物条没有这块牌子 | `OfficeScene.signGeometry`（按文字宽度和倍数定大小）；宠物条空的时候只有一个 56×140 的全透明画布 | TA › emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks（缩放 1–5 的对比度和不被盖住）；SPT-S › tankAndStripGeometryMatchTheSpec（空宠物条：56×140 全透明、没有文字）；SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（没人时菜单里灰色的「今天还没人上班」） | ✓ |


### 4. 任务书 7.2 提醒

`AlertCoordinator`（判定）、`AlertPipeline`（判定 → 出口）、`NotificationService`（系统通知 + 提示面板兜底）、`ToastController`（像素提示面板）、`SoundSynth`（提示音）、`DockTileController`（Dock 角标 / 弹跳）都在 `Sources/BuddyOffice/`。B-001 把判定改成「时钟由 `now` 参数传入、设置拷成值 `AlertConfig`、出口抽成 `AlertSink`」，`AC` 用假时钟逐条测；`AF` 用假通知中心 / 假提示卡 / 假 Dock 测「系统通知被拒时兜底真的出现」（这台机器的授权状态就是「已拒绝」）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| N01 | 7.2 触发 | 等批准 / 提问 / 计划待审：连续等待满 1.5 秒后提醒 | `AlertCoordinator.handleWaiting`：`Episode.since`，`now − since >= debounce (1.5)` 才 `post`；等待种类变了重新计时 | AC › approvalAlertWaitsExactlyOneAndAHalfSecondThenFiresOnce（1.49 s 不发、1.5 s 发一次、之后同一段等待不再发）、changingTheKindOfWaitRestartsTheDebounce、aWaitBlipShorterThanTheDebounceNeverAlertsAndClearsItsNotification；AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（端到端：1.49 s 没有提示卡、1.5 s 出现） | ✓ |
| N02 | 7.2 触发 | 默认全开 | `Settings`：`notify.permission / question / finished` 默认 true；`AlertConfig` 默认值 | SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（默认全开）、everyNotifySettingReachesTheAlertConfig（新设置读出来 = `AlertConfig()`，逐项改逐项进判定）；AC › settingsSwitchesTurnTheKindsOff | ✓ |
| N03 | 7.2 触发 | 做完了：这一轮用时 ≥ 30 秒并且没有被打断 | `AlertCoordinator.observe`：`.finished`、`d >= finishedMinSeconds`（默认 30，设置页可调 5–600）；被打断是另一个 `Activity` | AC › finishedAlertNeedsAnUninterruptedTurnOfAtLeast30Seconds（29.9 s 不发、30 s 发、被打断不发、设置可关 / 可调） | ✓ |
| N04 | 7.2 触发 | 桌面会话最多等 4 秒看 postTurnSummary，是 blocked 就改成「需要你处理」 | `AlertCoordinator.handleFinished`：桌面会话等 **8 秒**（`summaryWait`），`s.blocked` 时立刻发 `.blocked`「需要你处理」；等的这段时间里下一轮已经开始就不发 | AC › aDesktopSessionWaitsEightSecondsForTheTurnSummary（8.9 s 还没发、9 s 发；blocked 立刻改成「需要你处理」）、aPendingFinishedAlertIsDroppedIfTheNextTurnAlreadyStarted | 偏离（DESIGN §10 汇总表「桌面会话「做完了」最多等 4 s 看 blocked…等 8 s」；§11「桌面会话的「做完了」最多等 8 s 看有没有变成 blocked（本轮总结约 7 s 后才落盘）」） |
| N05 | 7.2 触发 | 出错：默认关闭 | `Settings`：`notify.error = false`；`AlertCoordinator.observe` 的出错分支 | AC › errorAlertsAreOffByDefaultAndThrottledWhenOn（默认不发、打开后发一次、20 秒内不重复） | ✓ |
| N06 | 7.2 不打扰 | 桌面会话：Claude.app 在最前面，且这个会话的 `lastFocusedAt` 是所有会话里最新的 → 不提醒 | `AppModel.isUserLooking`：前台 bundle id = `com.anthropic.claudefordesktop` 且 `DesktopMeta.cache.isMostRecentlyFocused(host:)`；`AlertCoordinator.handleWaiting / handleFinished`（`notify.suppressWhenFocused`） | AC › desktopSessionYouAreLookingAtNeverAlertsForThatWholeWait（判定：在看 → 这一整段等待都不提醒；开关关掉照常提醒）；CA › mostRecentHostIsTheLargestLastFocusedAndTiesAreDeterministic、aMissingHostIsNeverMostRecentlyFocused；SPT-A › theDesktopLookingRuleUsesTheFrontmostClaudeAndTheMostRecentlyFocusedSession（钉住前台 App 的判断）；前台 App 是系统状态，单测里控制不了：I-11 | ✓（间接验证：I-11） |
| N07a | 7.2 不打扰 | 终端会话：所在 App 在最前面，先等 8 秒，再判断一次要不要提醒（等待类提醒） | `AlertCoordinator.handleWaiting`：第一次看到「在看」→ `deferredUntil = now + 8`；到点再 `isLooking`，还在看就整段等待都不提醒 | AC › terminalSessionWaitsEightSecondsThenChecksAgainWhetherYouAreStillLooking（1.5 s 起先不提醒、9.4 s 仍不、9.5 s 你走开了才提醒；一直在看则整段不提醒） | ✓ |
| N07b | 7.2 不打扰 | 同上（「做完了」提醒） | `AlertCoordinator.handleFinished`：终端会话 `isLooking` 时先 `deferredUntil = now + 8`，到点再判断（B-001 修复） | AC › aTerminalFinishedAlertAlsoWaitsEightSecondsWhenYouAreLooking（在看 → 不发；8 秒后不看了 → 发；不在看 → 立刻发；8 秒后还在看 → 不发） | ✓ |
| N08 | 7.2 节流 | 同一个 buddy 的同一类提醒，20 秒内最多一条 | `AlertCoordinator.throttle`（键 = `<key>\|<等待种类>` / `\|finished` / `\|error`，`throttleWindow = 20`） | AC › sameBuddySameKindIsThrottledForTwentySeconds（距上一条 4 s / 18 s 挡住、20.5 s 起算满 1.5 s 才放行）、differentKindsAndDifferentBuddiesAreNotThrottledAgainstEachOther；RRA › r2004_aThrottledWaitingAlertIsDeliveredWhenTheWindowPasses（被节流挡住的这段等待，窗口一过、还在等就补发一条，不再重复；原来是整段丢弃，复查 R2-004 修了）、r2014_aClockThatWentBackwardsDoesNotSuppressAlerts（时钟被拨回不压提醒） | ✓ |
| N09 | 7.2 节流 | 2 秒内同时出现的几条合并成一条，比如「3 位同事在等你」 | `AlertCoordinator.post`：2 秒窗里 ≥ 2 个不同 buddy → 先 `.clear` 各自的，再发 key `multi` 的「N 位同事在等你 / 做完了 / 有事找你」 | AC › alertsWithinTwoSecondsOfEachOtherMergeIntoOne、threeBuddiesMergeIntoThree（「3 位同事在等你」）、alertsTwoSecondsOrMoreApartStayApart（正好隔 2 秒不合并）、theSameBuddyAlertingTwiceIsNotAMerge、theMergedNotificationIsClearedWhenNobodyIsWaitingAnymore、mergedFinishedAndMixedNotificationsUseTheirOwnWords；AF › severalWaitersAreCountedAndMergedInTheFallbackToo | ✓ |
| N10 | 7.2 通知的维护 | 通知 identifier 用 `buddy.<key>`，新的通知直接替换旧的 | `SystemNotificationCenter.add`：`UNNotificationRequest(identifier: "buddy.\(key)")`（相同 identifier 系统直接替换）；提示面板同 key 也是替换 | SPT-A › notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays（钉住 identifier / userInfo / 撤销的写法）；真实的 `UNUserNotificationCenter` 只在 .app 里能用，替换语义是系统的：I-07 | ✓（间接验证：I-07） |
| N11 | 7.2 通知的维护 | 状态解除后，把已经送达的通知撤掉 | `AlertCoordinator.observe`：`.clear` → `NotificationService.clear`（`removeDelivered` + 提示卡收回） | AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（批准后：提示卡收回、`removeDelivered` 被调用、角标 / 图标恢复）；AC › aWaitBlipShorterThanTheDebounceNeverAlertsAndClearsItsNotification、theMergedNotificationIsClearedWhenNobodyIsWaitingAnymore、hidingABuddyWhoIsAlreadyAlertingClearsTheAlert | ✓ |
| N12 | 7.2 通知的维护 | 点击通知 → 跳转到对应会话（key 放在 userInfo 里） | `SystemNotificationCenter.add`：`userInfo["buddyKey"]`；`didReceive` → `onClick` → `AppModel.handleNotificationClick` → `JumpResolver.notificationClick` | JT › notificationClicksRouteCorrectly（认得的 key → 跳；合并提醒 → 打开办公室；走了的 → 什么都不做）；SPT-A › theSystemNotificationGateIsTheAppBundleAndAClickCarriesTheKey（点提示卡把 key 交给点击处理）、notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays（userInfo 两头都用 `buddyKey`）；点真实系统通知见 I-07 | ✓ |
| N13 | 7.2 文案 | 「想用 Bash：git push（等你批准）」 | `AlertCoordinator.text(for:)` → `AlertText.approvalBody`（`想用 <工具>` + Bash 时 `：<前 1–2 个词>` + `（等你批准）`） | AC › approvalAlertWaitsExactlyOneAndAHalfSecondThenFiresOnce（body 逐字 = 「想用 Bash：git push（等你批准）」）；TT › approvalWordingThatAlreadyFitsIsUnchanged、approvalBodiesFitNoMatterHowLongTheToolOrTheCommandIs；PC › shortCommandKeepsTheFirstWordsAndDropsCdPrefixesAndOptions | ✓ |
| N14 | 7.2 文案 | 「有个问题要问你」 | `AlertCoordinator.text(for:)`（计划待审「计划好了，等你看」、其他「在等你」） | AC › questionPlanAndOtherWaitsHaveTheirOwnWording（逐字） | ✓ |
| N15 | 7.2 文案 | 「做完了（用时 3 分 12 秒）」 | `AlertCoordinator.handleFinished`：`做完了（用时 \(PlateCopy.spoken(…))）` → 「3分12秒」，数字和单位之间不留空格（和桌牌「做完了 · 3分12秒」一致） | AC › finishedAlertNeedsAnUninterruptedTurnOfAtLeast30Seconds（192 秒 → 「做完了（用时 3分12秒）」）；PC › fileNamesClipsAndDurations | 偏离（DESIGN §13「通知文案里的时长写法」：「3分12秒」，任务书示例写作「3 分 12 秒」） |
| N16 | 7.2 文案 | 隐私模式下隐藏细节 | `AlertText.title(privacy:)` = 「会话」；`text(for:privacy:)` 不带工具 / 命令 | AC › privacyModeHidesTheTitleAndTheCommand（标题 = 「会话」、正文 = 「有个权限请求（等你批准）」）、titlesAreAlwaysDisplayable；PC › privacyModeNeverLeaksDetails；SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（菜单栏这一路也不出现标题 / 命令） | ✓ |
| N17 | 7.2 系统通知 | 只有 `bundleURL.pathExtension == "app"` 且有 bundle id 才调 `UNUserNotificationCenter`，否则裸跑的可执行文件会崩 | `NotificationService.available`（默认值就是这个判断），`refresh / requestAuthorizationIfNeeded / clear` 都先判断；只有 `NotificationService.swift` 碰 `UNUserNotificationCenter` | SPT-A › theSystemNotificationGateIsTheAppBundleAndAClickCarriesTheKey（默认 `available` = .app + bundle id；测试宿主不是 App，所以是 false）；NA › notAnAppBundleNeverTouchesTheNotificationCenter；AF › notYetAskedOrNotAnAppBundleAlsoFallsBack；SA › onlyNotificationServiceTouchesTheUserNotificationCenter | ✓ |
| N18 | 7.2 系统通知 | ad-hoc 签名 App 从 `~/Applications` 经 LaunchServices 启动一次后应该能用系统通知，M0 要实际测 | DESIGN §2 M0 第 2 项：API 可用，授权框里用户点了拒绝 → `denied`；因此走兜底，设置页显示授权状态并给「打开系统通知设置」按钮 | DESIGN §2 M0 第 2 项的实测记录；系统授权弹窗不能操控、也不该再弹一次：I-07。兜底链路本身 AF 全覆盖 | ✓（间接验证：I-07） |
| N18b | 7.2 系统通知 | 系统通知要能用（授权要在某个时刻主动请求）：DESIGN §2「第一次主动打开办公室窗口时请求」 | `NotificationService.officeMayHaveOpened / shouldRequestOnOfficeOpen`（B-003）：`showOffice` + `applicationDidBecomeActive` 调用；设置页按钮不受限 | NA › theFirstActiveOpenOfTheOfficeAsksExactlyOnce、aBackgroundLaunchDoesNotAskUntilTheAppIsInFront、alreadyAnsweredNeverAsksAgain、theAskedFlagSurvivesARestartButTheSettingsButtonStillWorks、theDecisionFunction | ✓ |
| N19 | 7.2 兜底 | Dock 角标显示正在等你的人数 | `DockTileController.update / badgeLabel(waiting:)` | AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（角标 "1"，批准后清掉）、severalWaitersAreCountedAndMergedInTheFallbackToo（"2"）、menuBarIconKindAndDockBadgeLabels、aHiddenBuddyDisturbsNobodyButStillCountsAsALiveSession；真实 Dock 上的角标外观见 I-08 | ✓ |
| N20a | 7.2 兜底 | `requestUserAttention(.informationalRequest)` 让 Dock 图标弹一下 | `DockTileController.Env.live.requestAttention`（`newlyWaiting && !NSApp.isActive`） | AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（弹一次）、theDockDoesNotBounceWhileTheAppIsAlreadyInFront；SPT-A › notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays（钉住真实调用是 `.informationalRequest`）；真实弹跳见 I-08 | ✓ |
| N20b | 7.2 触发（1.5 秒） | 等待满 1.5 秒后才提醒（Dock 弹跳 / 角标 / 菜单栏图标这类兜底要不要也等） | `AlertCoordinator.handleWaiting`：Dock 弹跳和弹窗共用 1.5 s 去抖（B-001 修复）；角标 / 菜单栏举手图标一开始等就出现（`waitingKeys`） | AC › waitingKeysAreImmediateButTheDockBounceUsesTheSameDebounce（1.49 s 不弹、1.5 s 弹一次、一闪而过的等待整个过程都没弹） | ✓ |
| N21 | 7.2 兜底 | 场景里的气泡 | `Performer.targetBubble`（钥匙 / 「?」/ 写字板气泡） | PM › everyRowOfTheStateToAnimationTable（等批准 / 提问 / 计划待审三行的气泡）；SPT-S › bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven | ✓ |
| N22 | 7.2 兜底 | 菜单栏图标变成举手 | `AlertPipeline.run` → `LiveAlertSink.update` → `StatusItemController.iconKind(waiting:busy:)` | AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（图标序列：等待 → `.waiting`、批准后 `.busy`、空闲后 `.normal`）、menuBarIconKindAndDockBadgeLabels；SPT-A › menuBarIconsAreEighteenPointTemplatesExceptTheColouredWaitingOne | ✓ |
| N23a | 7.2 兜底 | 授权被拒就改用像素提示面板 | `NotificationService.post`：`systemAllowed` 为 false → `toast.show`；`ToastCard`（7 种：等批准 / 提问 / 计划 / 做完了 / 需要你处理 / 出错 / 提示） | AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（`.denied`：提示卡出现、一条系统通知都没发）、notYetAskedOrNotAnAppBundleAlsoFallsBack、whenAuthorizedTheSystemNotificationIsUsedInsteadOfTheToast；TT › everyFixedAlertTextFits（文字不溢出） | ✓ |
| N23b | 7.2 兜底 | 从右上角弹簧滑入 | `ToastController`：`PixelSpring(value: 60, period: 0.36)`，起点在屏幕外右侧，靠 `visibleFrame` 右上角往下叠，最多 3 张，6 秒后收回，点一下跳转 | SPT-A › notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays（钉住弹簧参数 / 最多 3 张 / 6 秒 / 右上角坐标）；`ToastController.show` 会显示真窗口，真实滑入见 I-08；DESIGN §8 `--log-ui` 记录 | ✓（间接验证：I-08） |
| N24a | 7.2 提示音 | 运行时合成 8-bit WAV 数据，不需要外部文件；可以设置成无 / 系统提示音 / 8-bit | `SoundSynth.wav`（方波琶音，22050 Hz、8 位、单声道）、`play(mode:)`（none / system=`NSSound.beep` / 8bit）；`notify.sound` 默认 8bit | SPT-A › theSoundsAreSynthesisedAsEightBitMonoWavDataWithoutAnyFile（4 种提示音：RIFF / WAVE 头、PCM / 单声道 / 22050 Hz / 8 位、块长度对得上、时长 = 音符之和、有振幅有振荡；源码里没有任何声音文件）、theSoundModeFromTheSettingsReachesThePlayerAndEachKindHasItsOwnSound（none / system / 8bit 原样交给播放、各类提醒用各自的声音）；AF › whenSystemNotificationsAreDeniedTheFallbackAlertsReallyAppear（提示音照响）；真的发声听不到：I-08 | ✓ |
| N24b | 7.2 提示音 | 用 `NSSound(data:)` 播放 | 专门的后台串行队列 + `AVAudioPlayer`（`SoundSynth.play`，启动 3 秒后预热） | 实测：`NSSound.play()` 首次调用卡主线程 220–270 ms（DESIGN §8「提示音」行） | 偏离（DESIGN §10 汇总表「提示音 `NSSound(data:)`…后台队列 + `AVAudioPlayer`」；§8「提示音」行） |
| N25 | 7.2 重复提醒 | 设置里加一项「桌面 App 会话也提醒」，默认开着，在使用说明里讲清楚 | `Settings`：`notify.includeDesktop = true`；设置页开关；`AlertCoordinator`（`includeDesktop`）；`使用说明.txt` | SPT-A › theBuildScriptAndTheManualSayWhatTheSpecRequires（使用说明里有「可能和这里的提醒重复」和开关的名字、设置页里 `nDesktop = true`）、everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（默认开）；AC › desktopSessionsAreSkippedWhenIncludeDesktopIsOff | ✓ |


### 5. 任务书 7.3 点 buddy 跳到会话（JumpService）

`Sources/BuddyOffice/JumpService.swift`（执行）+ `JumpResolver.swift`（B-002：座位号 / key → 快照 → 跳转目标，纯函数）。所有入口（办公室 / 小鱼缸 / 宠物条 / 菜单栏 / 通知 / 提示面板）都走 `AppModel.jump(snapshot:)`，跳转后 `provider.markSeen` 清未读。真实的深链 / 激活 / 终端标签页选择需要真实的 Claude 和 Terminal（以及系统的自动化授权），单测里只能测到「决定跳到哪里」和「脚本 / URL 长什么样」，其余靠钉住源码 + `--test-jump` / `--probe-pid` 启动参数的实测记录，逐条见「间接验证清单」I-09、I-10。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| J01 | 7.3 桌面 App 会话 | 等你时 `claude://code/needs-input?session=<hostSessionId>`，其他时候 `claude://code/continue?session=…`，都用 `NSWorkspace.shared.open` | `JumpResolver.target / deepLinkURL`（`activity.needsUser` → needs-input）；`JumpService.jumpDesktop`：`NSWorkspace.shared.open(url)` | JT › deepLinkRules（continue / needs-input、等你的 5 种活动都用 needs-input）、everySeatMapsToItsOwnSessionAndItsOwnTarget（6 个会话各自的 URL）；SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住 `NSWorkspace.shared.open(url)`）；真实发出深链见 I-09（`--test-jump`，DESIGN §2 M0 第 4 项） | ✓ |
| J02 | 7.3 桌面 App 会话 | session 参数必须匹配 `^local_[A-Za-z0-9-]{1,64}$` | `JumpService.validHostID` / `JumpResolver.validHostID`（不合法 → `.activateClaude`） | JT › deepLinkRules（11 种非法 id 全部退回激活 Claude、64 位是上限刚好合法）；SmokeTests | ✓ |
| J03 | 7.3 桌面 App 会话 | 跳完 2.5 秒内 `lastFocusedAt` 没变 → 没跳成功，改为直接激活 Claude | `JumpService.jumpDesktop`：`asyncAfter(2.5)` 后 `JumpResolver.deepLinkVerdict`；**目标本来就是 `lastFocusedAt` 最新的会话时不算失败**（M0 实测：连点当前会话会误把深链停用），Claude 不在最前面就补一次激活（A-026） | JT › deepLinkVerdictAfterTwoAndAHalfSeconds（变新 → 成功；没变且不是最近聚焦 → 失败并激活 Claude；本来就是最近聚焦 → 不算失败、Claude 不在最前面才补激活）；SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住 2.5 s） | 偏离（DESIGN §2 M0 第 4 项；§10 汇总表「深链失败判据「2.5 s 内 lastFocusedAt 没变」」；§11「深链失败判据修正」） |
| J04 | 7.3 桌面 App 会话 | 连续失败 2 次后，停用深链，并给出提示 | `JumpService.jumpDesktop`：`deepLinkFailures >= 2` → `deepLinkDisabled = true` + `onNotice(标题, 正文)`（一行放得下，B-006）；设置 → 数据源诊断 →「重新启用深链」 | SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住 `>= 2` 的停用逻辑、`resetDeepLink()` 真的清零）；TT › theOldDeepLinkNoticeWasTruncatedAndTheNewOneFits（提示卡一行放得下）；JT › deepLinkRules（停用后 `.activateClaude`）；失败计数在 `jumpDesktop` 的异步闭包里，要真的 `NSWorkspace.open` 才会走到：I-09 | ✓（间接验证：I-09） |
| J05 | 7.3 终端里的会话 | 沿父进程链往上找宿主 App，最多 12 层；跳过 bundle id 是 `com.anthropic.claude-code` 的 CLI 包，也跳过纯后台的 App | `JumpService.hostApp(of:)`：`for _ in 0..<12`、`activationPolicy == .regular`、bundle id 过滤 | SPT-A › theProcessHelpersReadTheProcessTableAndTheHostLookupSkipsBackgroundApps（sysctl 读到的父进程 = `getppid()`；不存在的进程 / launchd 没有宿主；找到的宿主是普通 App 且不是 CLI 包；钉住 12 层和过滤条件）；`--probe-pid` 的实测（DESIGN §8）；真实的父进程链取决于运行环境：I-10 | ✓（间接验证：I-10） |
| J06 | 7.3 终端里的会话 | Terminal：用 sysctl 读 `kp_eproc.e_tdev`，再用 `devname()` 得到 tty | `ProcessInfoHelper.ttyName(of:)` | SPT-A › theProcessHelpersReadTheProcessTableAndTheHostLookupSkipsBackgroundApps（读到的 tty 名必须通过 `isValidTTY`、不存在的进程 = nil、钉住 `e_tdev` + `devname`）；DESIGN §8：对一个 pty 子进程返回的 tty 和 `ps` 一致；单测宿主没有可用的控制终端：I-10 | ✓（间接验证：I-10） |
| J07 | 7.3 终端里的会话 | 跳转队列里跑 AppleScript：按 `tty of tab` 找到标签页、选中、窗口提到最前、取消最小化、激活 Terminal | `JumpResolver.terminalTabScript(tty:)` + `JumpService.selectTerminalTab`（专门的脚本队列、`with timeout of 5 seconds`） | SPT-A › theTerminalScriptFollowsTheSpecifiedSteps（脚本里依次有 找 tab → `tty of tb` 等于该 tty → 选中 → 取消最小化 → 提到最前 → `activate`）；JT › theTerminalScriptHasATimeoutAndOnlyAcceptsRealTTYNames（超时 5 秒、tty 校验）；真的选中 Terminal 标签页要真实的 Terminal 和自动化授权：I-10（DESIGN §2 M0 第 6 项实测） | ✓（间接验证：I-10） |
| J08 | 7.3 终端里的会话 | 其他宿主就直接激活那个 App | `JumpService.jumpTerminal`：`bundleIdentifier == com.apple.Terminal` 才选标签页，否则 `activate(appAt:)` | SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住分支）；这台机器没有 iTerm（DESIGN §10）：I-10 | ✓（间接验证：I-10） |
| J09 | 7.3 VS Code 里的会话 | `NSWorkspace.open([cwd], withApplicationAt: VS Code)` | `JumpService.jumpVSCode`（没有 cwd 时直接激活 VS Code） | JT › terminalAndVSCodeTargets（目标 = `.vscode(cwd)`、空 cwd 当没有）；SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住 `open([URL(fileURLWithPath: cwd)], withApplicationAt:)`）；没有 VS Code 的 Claude 扩展（DESIGN §10）：I-10 | ✓（间接验证：I-10） |
| J10 | 7.3 激活的坑 | 改用 `NSWorkspace.openApplication(at:configuration:)`，设置 `activates = true` | `JumpService.activate(appAt:)`（所有激活都走它） | SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住 `cfg.activates = true` + `openApplication(at:configuration:)`；代码里没有 `activate()` / `activate(options:)`）；DESIGN §2 M0 第 5 项（从非激活状态实测：这个 API 能把 Terminal 拉到最前，`NSRunningApplication.activate()` 对 Claude 返回 false）：I-09 | ✓（间接验证：I-09） |
| J11 | 7.3 自动化授权 | Info.plist 里有 `NSAppleEventsUsageDescription`，文案「点小人跳转到「终端」里对应的标签页时才会用到。」 | `scripts/build-app.sh` 生成 Info.plist | SPT-A › theBuildScriptAndTheManualSayWhatTheSpecRequires（构建脚本里这一行逐字一致）；DESIGN §9.1：已装 App 的 Info.plist 与任务书逐个对得上 | ✓ |
| J12 | 7.3 自动化授权 | ad-hoc 签名每重新编译一次系统会再问一遍自动化授权，要写进使用说明 | `使用说明.txt` | SPT-A › theBuildScriptAndTheManualSayWhatTheSpecRequires（使用说明里有「「自动化」授权在重新编译（重新安装）之后会再问一次」）；JT › theUserManualDoesNotClaimThatThePlateIsClickable | ✓ |
| J13 | 7.3（总述） | 点 buddy 跳到那个会话；跳完清未读 | `AppModel.jump(snapshot:)`：`JumpService.shared.jump(to:)` + `provider.markSeen`；三个面 / 菜单栏 / 通知 / 提示面板都接到它 | JT › everySeatMapsToItsOwnSessionAndItsOwnTarget、afterSeatsAndSessionsChangeAClickStillResolvesToWhoSitsThereNow、danglingSeatsNeverJump、aKeyThatIsNoLongerPresentResolvesToNothing；AM › clicksOnDanglingSeatsAndInDemoModeNeverJumpForReal；SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms（钉住先跳转、再 `markSeen`）；真的跳转（Claude / Terminal 被带到前台）见 I-09 | ✓ |

### 6. 任务书 7.4 跟着 Claude 一起开、一起收

`scripts/hook-merge.py`（`Tests/hook_merge_test.py` 有 13 个测试；这次没有再运行它——它会调用 hook-merge.py，而按约定不碰 `~/.claude/settings.json` 相关的脚本，逐条对应读的是测试源码里的断言）和 `Sources/BuddyOffice/SystemHelpers.swift` 的 `AutoQuit`（B-004 之后全部可注入，`AQ` 用假定时器逐条测）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| F01 | 7.4 自动打开 | 在 `~/.claude/settings.json` 的 `hooks.SessionStart` 数组**追加**一个 matcher 组（`startup\|resume`，type command，timeout 5），原有 ccmon 组一个都不动 | `scripts/hook-merge.py`：`GROUP`；`install` 追加到 `SessionStart` 数组末尾并保留其余所有键 | HM › test_install_appends_one_group_and_keeps_everything_else（断言 matcher = `startup\|resume`、command、timeout = 5、ccmon 组原样、其他键原样）、test_install_twice_is_idempotent、test_install_creates_file_when_missing | ✓ |
| F02 | 7.4 自动打开 | 命令 `pgrep -xq BuddyOffice \|\| open -g -b local.buddy-office >/dev/null 2>&1; exit 0`：App 已经在运行时什么都不做 | `hook-merge.py`：`COMMAND` | HM › test_install_appends_one_group_and_keeps_everything_else（整串命令逐字相等）；DESIGN §9.1（沙箱外真的触发：App 没运行时被拉起、已运行时再触发不多开） | ✓ |
| F03 | 7.4 自动打开 | `-g` 让 App 在后台打开，不抢焦点 | `COMMAND` 里的 `open -g` | HM › test_install_appends_one_group_and_keeps_everything_else（整串命令里有 `open -g`）；「没抢焦点」的实测：DESIGN §9.1 | ✓ |
| F04 | 7.4 自动打开 | 输出必须全部丢掉（SessionStart 的 stdout 会被塞进 Claude 的上下文） | `COMMAND` 末尾 `>/dev/null 2>&1; exit 0` | HM › test_install_appends_one_group_and_keeps_everything_else（整串命令）；DESIGN §9.1：hook 输出里没有任何多出来的东西 | ✓ |
| F05 | 7.4 自动打开 | 官方文档确认 SessionStart 在桌面 App / 终端 / VS Code 里都会触发；只对之后新开的会话生效 | （说明性文字，没有可实现的要求） | DESIGN §9.1「跟着 Claude 开」：沙箱外跑 `claude -p "ok"`，SessionStart hook 在 CLI 自己登录失败之前已触发、App 2 秒内被后台拉起、零输出、再触发不多开；没能看到一次成功的回答（终端版 CLI 登录过期，凭据不归我们碰），见 DESIGN §10 汇总表最后一行 | ✓（间接验证：I-12） |
| F06 | 7.4 自动收起 | 监听 `NSWorkspace.didTerminateApplicationNotification`；Claude（`com.anthropic.claudefordesktop`）退出且登记表里没有活着的 interactive 会话时，60 秒后自动退出 | `AutoQuit`：`start()` 订阅 → `appTerminated(bundleID:)` → `scheduleQuit(after: 60)`；到点 `isEnabled() && !hasLiveSessions()` 才 `terminate`（只退自己） | AQ › claudeQuitsAndNobodyIsLeftSoWeQuitAfterSixtySeconds（定时 60 秒、之前不退）、onlyClaudeQuittingStartsTheCountdown、liveSessionsIncludingHiddenOnesKeepUsAlive、autoQuitNeverQuitsAnotherApp、theTestEntryPointCountsDownTheGivenSeconds；SPT-A › autoQuitListensForApplicationTermination（订阅的确实是 `NSWorkspace.didTerminateApplicationNotification` 和 `didLaunchApplicationNotification`）；AM › theAutoQuitLiveSessionCheckCountsHiddenBuddies | ✓ |
| F07 | 7.4 自动收起 | 这 60 秒里如果有会话出现，或者 Claude 重新打开了，就取消退出 | `AutoQuit.appLaunched`（Claude 重新启动 → 取消定时器）；「会话出现」靠到点时再查一次 `hasLiveSessions`（被隐藏的 buddy 也算活着，A-010） | AQ › claudeComingBackCancelsTheCountdownAndANewQuitReplacesTheOld、liveSessionsIncludingHiddenOnesKeepUsAlive、hiddenBuddiesStillCountAsLiveSessions、noPresentSessionsMeansNothingIsLive | ✓ |
| F08 | 7.4 自动收起 | 设置里可以关掉这个行为 | `Settings`：`autoQuitWithClaude` 默认 true；设置页开关；`AppModel.wireAutoQuit` 的 `isEnabled` | AQ › theSwitchIsHonouredBothWhenClaudeQuitsAndWhenTheTimerFires（关着不倒计时；倒计时期间关掉也不退）；AM › theAutoQuitLiveSessionCheckCountsHiddenBuddies（开关读设置）；SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（默认 true、设置页有开关） | ✓ |
| F09 | 7.4 启动时的样子 | App 按上次用的形态出现，这个状态记在 UserDefaults 里 | `AppModel.applySettings(initial: true)` 读 `office / tank / strip.visible`；关窗口、标题栏按钮、菜单、右键菜单都会写回这三个键 | AP › theFirstApplyDoesEverything（第一次应用：按存下的形态显示 / 隐藏各个入口）、onlyTheChangedEntriesAreTouched；SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（三个键默认值）、theThreeTitleBarButtonsClickOnlyWhenReleasedInsideAndShrinkingSwapsTheOfficeForTheTank（缩成小鱼缸写回设置）、theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（菜单开关写回设置） | ✓ |

### 7. 任务书 7.5 设置与诊断

`Sources/BuddyOffice/Settings.swift`（键 + 默认值 + 范围夹取）、`SettingsView.swift`（SwiftUI 表单，4 页：形态 / 提醒 / 其他 / 数据源诊断）。「设置 → 行为」的接线现在有测试：数值夹取 `SE`、提醒 `SPT-A › everyNotifySettingReachesTheAlertConfig`、面板 `SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize`、办公室 `SPT-A › labelsAndZoomSettingsReachTheOfficeRendering`、数据层 `EC`、入口 `AP`。SwiftUI 视图本身没法在单测里驱动，`--dump-settings` 仍可逐页出图（I-14）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数） | 测试 / 证据 | 状态 |
|---|---|---|---|---|---|
| C01 | 7.5 设置窗口 | NSWindow + `NSHostingController(SettingsView)`，里面是 SwiftUI Form | `SettingsWindowController`：`NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model:)))`（`.titled .closable`）；表单 `TabView` + `Form(.grouped)` 四页 | SPT-A › theSettingsWindowHostsTheSwiftUIForm（窗口的内容控制器就是 `NSHostingController<SettingsView>`、没显示）、everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（TabView / Form / 四个页签的名字）；真实渲染见 I-14 | ✓ |
| C02 | 7.5 配置项·办公室 | `office.visible`、`office.zoom`（0 = 自动） | `Settings`；`SettingsView`；`OfficeWindowController.render`（`OfficeLayout.effectiveZoom`）；`AppModel.applySettings` | SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（键 / 默认 / 控件）、labelsAndZoomSettingsReachTheOfficeRendering（`office.zoom` = 2 / 3 → 实际倍数；0 = 自动 ≥ 2）；AP › turningTheOfficeOnShowsItEvenIfItIsMinimized、turningTheOfficeOffHidesIt；TA › zoomIsClampedSoAtLeastOneWholeSeatFits | ✓ |
| C03 | 7.5 配置项·小鱼缸 | `tank.visible`、`tank.zoom`、`tank.opacity` | `TankPanelController.render`（缩放 1–2、不透明度 0.3–1 → `alphaValue`） | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（不透明度 0.5 → 0.5、0.1 → 夹到 0.3；缩放 1 → 1、9 → 夹到 2；窗口 = 画布 × 缩放）；SE › numbersWrittenBehindOurBackAreClampedIntoTheirValidRange；AP（`tank.visible`） | ✓ |
| C04 | 7.5 配置项·桌面宠物 | `strip.visible`、`strip.zoom` | `StripPanelController.render`（缩放 1–3） | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（1 / 2 / 3 / 7 倍 → 夹到 1–3、窗口尺寸）；SE；AP（`strip.visible`、`entryFallback`） | ✓ |
| C05 | 7.5 配置项·桌面宠物 | `strip.screen` | `StripScreenPicker`；设置页「显示在」（主屏幕 / 鼠标所在的屏幕 / 每块已连接的显示器，B-007） | SK › mainAndUnknownValuesUseThePrimaryScreen、mouseFollowsTheScreenTheMouseIsOn、aChosenScreenIsFoundByIDThenByNameAndFallsBackToThePrimaryWhenUnplugged、settingsPageOptionsAlwaysContainTheCurrentValue | ✓ |
| C06a | 7.5 配置项·桌面宠物 | `strip.level`、`strip.fullscreen` | `StripPanelController.applyLevel`（设置变化时立即应用） | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（level = desktop → `desktopIconWindow + 1`；fullscreen → 多 `.fullScreenAuxiliary`） | ✓ |
| C06b | 7.5 配置项·桌面宠物 | `strip.align`（改了应当马上生效） | `StripPanelController.render`：设置变化时 `repositionIfNeeded()`（A-006）；`scene.alignRight` | SPT-A › settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize（right / left / center：窗口位置 = `origin(align:…)`、`scene.alignRight`）；SL › rightLeftCenterAndUnknownAlignments、anyChangeOfThePlacementInputsTriggersARepositionAndNothingElseDoes | ✓ |
| C07 | 7.5 配置项·界面 | `ui.menuBarIcon`、`ui.dockIcon`、`ui.labels`（总是 / 悬停 / 关闭） | `AppModel.applySettings`（`ApplyPlanner`）；`OfficeWindowController.render` 的 `labelMode`；`OfficeScene.plateTexts` | SPT-A › labelsAndZoomSettingsReachTheOfficeRendering（always → 有桌牌文字；off / hover（没悬停）→ 没有）；AP › onlyTheChangedEntriesAreTouched（menu / dock 各自的动作）、aForcedDockIconIsWrittenBackSoTheSettingsPageDoesNotSayOff | ✓ |
| C08 | 7.5 配置项·提醒 | `notify.permission`、`.question`、`.finished`、`.finishedMinSeconds = 30`、`.includeDesktop`、`.suppressWhenFocused`、`.sound`（另有 `.error`） | `AlertConfig(settings:)`；`LiveAlertSink.post(sound:)` | SPT-A › everyNotifySettingReachesTheAlertConfig（逐项改、逐项读到）、theSoundModeFromTheSettingsReachesThePlayerAndEachKindHasItsOwnSound（`notify.sound`）；AC › settingsSwitchesTurnTheKindsOff、finishedAlertNeedsAnUninterruptedTurnOfAtLeast30Seconds、desktopSessionsAreSkippedWhenIncludeDesktopIsOff、desktopSessionYouAreLookingAtNeverAlertsForThatWholeWait | ✓ |
| C09 | 7.5 配置项·空闲 | `idle.dozeMinutes = 10`、`idle.sleepMinutes = 45`（设置里可改） | 设置页两个 Stepper → `EngineConfig.values` → `RealProvider.make` 填进 `SessionEngine.Options`（A-001）；**下次启动生效**（设置页里写明） | EC › settingsMapToEngineOptions（3 分钟 → 180 s、默认 = 引擎原默认）、outOfRangeValuesAreClampedAndSleepAlwaysComesAfterDoze、realProviderPassesTheSettingsToTheEngine；SE（默认 10 / 45） | 偏离（DESIGN §13「设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」…下次启动生效」） |
| C10 | 7.5 配置项·下班工位 | `dormant.max = 4` | `EngineConfig`（0–8）→ 引擎；`AppModel.derive` 再按 `dormant.max` 截一次（调小立刻生效，留下最近活动的） | EC › settingsMapToEngineOptions、realProviderClampsWhatItReadsFromDefaults；SE › deriveNeverTrapsWhateverTheDormantMaxIs；AM › incomingDataIsSanitizedSortedAndDerived | 偏离（DESIGN §13「最多保留 N 个下班工位」…「下次启动生效」…「「最多保留」调小立刻生效」） |
| C11 | 7.5 配置项·下班工位 | `dormant.recentHours = 3` | 设置页 Stepper → `EngineConfig.values`（1–24 小时）→ `SessionEngine.Options.dormantRecent`；下次启动生效 | EC › settingsMapToEngineOptions（5 小时 → 18000 s）、realProviderPassesTheSettingsToTheEngine | 偏离（DESIGN §13「设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」…下次启动生效」） |
| C12 | 7.5 配置项·其他 | `privacy.hideDetails` | `AppModel.privacy` → 桌牌 / 悬停卡 / 通知 / 菜单栏菜单 | PC › privacyModeNeverLeaksDetails；AC › privacyModeHidesTheTitleAndTheCommand；SPT-A › theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit（打开隐私模式后菜单里没有标题 / 命令） | ✓ |
| C13 | 7.5 配置项·其他 | `autoQuitWithClaude = true` | 见 F08 | 见 F08 | ✓ |
| C14 | 7.5 配置项·其他 | `login.enabled = false`、`hotkey.enabled` | `LoginItem.set`（`SystemHelpers.swift`）；`HotKey`；`ApplyPlanner` 只在开关变化时注册 / 注销热键 | SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage（默认 `login.enabled = false`）；HK › theLoginSwitchFallsBackToOffWhenEnablingFailed、aPendingApprovalIsNotReportedAsEnabled；AP › nothingChangedMeansNothingToDo（热键不反复注销 / 注册）；真的注册登录项 / 热键会改用户系统：I-13 | ✓（间接验证：I-13） |
| C15 | 7.5 配置项 | 外观 salt 存在 `identities.json` 里 | `IdentityResolver`（写盘含 `salt`、`reroll` 每次 +1） | IT › persistenceRoundTripKeepsAliasesSeatAndSalt、rerollGivesANewSaltEachTime；AL › rerollWaitsForTheNewSaltAndThenEveryPlaceAgrees | ✓ |
| C16 | 7.5 开机启动 | 默认关；优先 `SMAppService.mainApp.register()`，不行写 `~/Library/LaunchAgents/local.buddy-office.plist`（运行 `/usr/bin/open -b local.buddy-office`）；只有用户打开开关才写 | `LoginItem.set`：先 `register()`（enabled / requiresApproval 才算成）；否则 LaunchAgent（`RunAtLoad`，参数比规格多一个 `-g`，后台打开）；只有设置页开关和卸载脚本的 `--unregister-login`（只会关）调用它 | SPT-A › loginItemUsesTheServiceManagementFirstThenTheSpecifiedLaunchAgentAndOnlyFromTheSwitch（路径后缀、先 SMAppService 后 LaunchAgent、参数、`RunAtLoad`、唯一调用点）；HK › theLoginSwitchFallsBackToOffWhenEnablingFailed、aPendingApprovalIsNotReportedAsEnabled；DESIGN §2 M0 第 3 项、§8「开机启动」（只测了状态，没有真的打开过开关，会往登录项里加东西）：I-13 | ✓（间接验证：I-13） |
| C17 | 7.5 诊断页 | 活会话数 | `AppModel.diagnosticsText` ← `SessionEngine.diagnostics()`；`DiagnosticsFormatter.text` | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（「活会话数：3」）；HK › diagnosticsTextListsEverythingTheSettingsPageShows；EnginePresenceTests › diagnosticsReportSourcesAndPerSessionHookState（数据层 `liveSessionCount`） | ✓ |
| C18 | 7.5 诊断页 | 有没有检测到 hook、最后一个事件的时间 | `DiagnosticsFormatter.text`：`hookDetectedInSettings` + `lastHookEventAt` | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（「已在 settings.json 里注册，最后一个事件 <时间>」、「没有检测到」）；EnginePresenceTests › diagnosticsReportSourcesAndPerSessionHookState | ✓ |
| C19 | 7.5 诊断页 | 各会话的 Claude Code `version` | `DiagnosticsFormatter.text`：每个会话 pid、`v<版本>`、hook 有 / 无 | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（「v2.1.284」）；HK › diagnosticsTextListsEverythingTheSettingsPageShows（`· 重构登录　pid 123　v2.1.0　hook 有`） | ✓ |
| C20 | 7.5 诊断页 | 深链测试按钮 | `SettingsView`：「测试深链（跳到当前会话）」「重新启用深链」；`AppModel.testDeepLink` | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（没有在场的桌面会话时给出「没有在场的桌面 App 会话可以测试。」、不会真的跳；钉住两个按钮）、theJumpServiceKeepsTheSpecifiedMechanisms（`resetDeepLink()`）；真实的深链测试见 I-09 | ✓ |
| C21 | 7.5 诊断页 | 系统通知的授权状态 | `NotificationService.statusText`；设置页「授权状态：…」（打开设置页 / 点按钮后刷新，A-023）；「请求通知授权」「打开系统通知设置」「发一条测试提醒」 | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（诊断文字里有「系统通知：…」、页面上的「授权状态：」）；NA › notAnAppBundleNeverTouchesTheNotificationCenter（不可用时的说明文字） | ✓ |
| C22 | 7.5 诊断页 | 当前用的是哪些数据来源，以及每个的降级状态 | `DiagnosticsFormatter.text`：逐行列 `sourceStatus` | SPT-A › theDiagnosticsPageShowsEverythingTheSpecListsIncludingTheLastHookEventTime（「登记表: 正常」「FSEvents: 不可用，改用轮询」逐行出现）；EnginePresenceTests › diagnosticsReportSourcesAndPerSessionHookState（数据层给出的降级状态） | ✓ |


### 8. 原缺口清单的去向

原文件 §8 列了 23 条没做或偏离没记录的（8 + 15），以及 101 条有实现但没有专门测试的。现在全部有了归宿（下表按原文 §8.1 的顺序；后一部分按 §8.2 的类别）。

| 原缺口 | 最终去向 |
|---|---|
| S15b「其他 MCP」首字母画成「?」（高） | 已修（TA-012，`issues-stage.md`）：4×6 字体补了 A–Z；S15b ✓ |
| C09 / C10 / C11 设置页有、行为没接（高） | 已修（A-001，`issues-app.md`）：设置 → 数据层 `Options`，「下次启动生效」（「最多保留」调小立刻生效）；C09 / C10 / C11 = 偏离（DESIGN §13），`EC` 四个测试 |
| U28 / C06b / U26c 宠物条定位不全（高） | 已修（A-006 / B-007）：设置改了立刻定位、每 0.5 秒查 `visibleFrame`（任务书 2 秒，DESIGN §13「应用层的决定」记了）、可以指定某块屏幕；U28 = 偏离，C06b / U26c = ✓ |
| S29b2 / M10 / M11 关机是一帧硬切、亮度渐变（中） | S29b2 已修（SP-01）：关机用同一条 Bayer 抖动倒放 300 ms；开 / 关机的 16 级抖动（任务书 5 级）和「亮度渐变只覆盖开关机和昼夜」都补记进 DESIGN §13；S29b1 / S29b2 / M10 / M11 = 偏离 |
| M08 等待光晕没做（中） | 已修（SP-02）：等待灯 3 个相邻色阶 0.8 Hz；「1 Hz、2 像素轻弹」由举手挥动承担（DESIGN §13 原有记录）；M08 = 偏离 |
| 5.6 交叉项：4 帧擦除 / 先放下道具 / 等待类 ≤ 250 ms（中） | 偏离，DESIGN §13 原有记录（屏幕内容切换是硬切，回归风险大于收益） |
| S22a2 / S26a2 / S12a / S05b2 / 思考的笔（中低） | 偏离，DESIGN §13 原有记录；S28a / S08a2 已修（SP-04：未知工具打字鼠标交替、WebSearch 先打字），有 `PM` 逐行断言 |
| M16 / M17 鼠标 / 走路帧表（低） | 偏离，DESIGN §13 原有记录 |
| S27b2 待机灯开关式（低） | 已修（SP-02）：3 阶呼吸，`MT › theStandbyLightBreathesThroughThreeLevelsSlowly` |
| M13b 小鱼缸 / 宠物条先 orderFront 后渲染（低） | 已修（B-005 `PanelShow`），`PS` 三个测试 |
| N07b / N20b / N18b 提醒细节（低） | 已修（B-001 / B-003）：终端「做完了」8 秒复查、Dock 弹跳共用 1.5 秒去抖、首次打开办公室请求通知授权；`AC` / `NA` |
| 有实现、没有专门测试：N01–N16 等提醒判定（高） | `AC` 30 个测试（假时钟）+ `AF` 9 个（系统通知被拒时兜底真的出现）；文案 / 隐私 / 合并 / 节流逐条对应到测试名（§4） |
| 有实现、没有专门测试：J01–J13、F06–F08（中） | `JT`（目标解析 / 深链规则 / 判据 / 脚本）、`AQ`（自动收起）、`SPT-A` 的源码钉住与进程内检查；真实的深链 / 激活 / 终端标签页只能间接验证（I-09、I-10） |
| 有实现、没有专门测试：S03a…S27a2 姿势时间参数、动作画对没有（中） | `SPT-S` 逐条钉住：姿势帧的位置 / 频率、数字边界、屏幕内容、桌牌文字（§1） |
| 有实现、没有专门测试：C01–C21 设置 → 行为接线（中） | `SPT-A`（键 / 默认 / 控件、面板行为、办公室渲染、提醒读设置）+ `SE` / `EC` / `AP` / `SK`（§7） |
| 有实现、没有专门测试：M01–M05、M07、M13a、M14、M21 弹簧 / 呼吸 / 光标 / 眨眼 / 昼夜（中低） | `SPT-S` 逐条钉住（§2）；M21 记为偏离 |
| 有实现、没有专门测试：U01–U39 AppKit 行为（低） | 能在进程内跑的都跑了（面板 / 窗口对象只建不显示，点击、点穿、菜单、图标、设置接线）；真实鼠标 / 窗口服务器 / 系统弹窗才能验的 22 行标 ✓（间接验证），逐条列在 §9 |

### 9. 间接验证清单（主线程会原样搬进 REPORT.md）

只列**确实没法自动化测**的项：原因是真实 GUI 点击 → 窗口服务器 → 回调、系统授权弹窗、终端自动化授权、真实 Terminal 标签页选择、窗口最小化 / 全屏等 AppKit 的真实行为、系统绘制的菜单栏 / Dock，以及用户已经拒绝过对本 App 的 computer-use（不截屏、不点真窗口、不 osascript 控制别的 App）。每条一行：编号｜项｜为什么测不了｜间接证据（读了哪段代码 + 哪个测试从侧面锁住 / 哪个 `--test-*` 开关 / 哪次实测记录）｜涉及的行。

- **I-01**｜真实鼠标 → 窗口服务器 → 回调：单击 / 双击 / 按住背景拖动 / 悬停 250 ms / 点一下不激活 App / 标题栏按钮的真实点击｜合成的 `NSEvent` 不走窗口服务器的命中 / 窗口拖动 / 激活判定；三个面的悬停要真实鼠标位置和真实时钟；没有对本 App 的 computer-use 授权｜读 `PixelView.mouseDown / mouseDownAction`、`TankPanelController.click`、`PixelButton.mouseUp`；`SPT-A › doubleClickingTheTanksBackgroundGoesBackAndClickingABuddyJumps`、`theThreeTitleBarButtonsClickOnlyWhenReleasedInside…`、`theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms`（办公室的悬停延迟用真实时钟跑了）、`PD › onlyASingleClickOnTheBackgroundStartsAWindowDrag`、`PV › pixelViewAndTitleBarButtonsNeverLetAppKitStartAWindowDrag`；启动参数 `--test-tank-click`（经 `NSWindow.sendEvent` 分发：单击背景 → 交给拖窗口、双击 → 回办公室、点小人 → 跳转，PASS，`issues-app.md` A-002）、`--test-titlebar`（三个按钮，PASS）；DESIGN §2 M0 第 1 项（真实点击日志 `CLICK … appActive=false`）。旧配置下进程内自检也没能复现「点击被拖动吞掉」（A-002 的诚实结论），所以真实鼠标路径这一项仍只能真机点一下确认｜U04b、U04c、U08、U10、U21、U23、U24
- **I-02**｜桌面宠物条点穿的真实时序（30 Hz / 10 Hz 轮询）和真实鼠标下 `ignoresMouseEvents` 的效果｜`poll()` 要面板真的可见、跑在真实 RunLoop 上，频率是定时器行为，单测里没有一个可见的宠物条｜`SPT-A › theStripPollingRatesAndDistancesStayAsSpecified`（钉住 `Timer(1/30)`、`insetBy(−100, −100)`、每 3 次做 1 次）；`theStripInterceptsBuddyPixelsWithAOnePixelHaloAndLetsEverythingElseThrough`（`evaluate(at:)` 的判定和切换逻辑真的跑了）；启动参数 `--self-test` 的 `panelsSelfTest`（DESIGN §9 M2：身上拦截 / 空处点穿 / 远处点穿 PASS）｜U19、U20
- **I-03**｜办公室窗口的真实行为：点真实的关闭按钮、最小化 / 全屏、窗口位置自动保存与恢复、从 Dock 重新打开｜需要真实窗口显示和系统手势；单测里不弹窗口｜`SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindow…`（样式 + `frameAutosaveName`）、`closingTheOfficeWindowOnlyHidesItAndRemembersThatItIsClosed`（关闭按钮调用的 `windowShouldClose` 真的返回 false、写设置）、`dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified`（`applicationShouldHandleReopen` 先 `showOffice()` 再 `return true`）；`AP › aMinimizedOfficeWindowIsNotBroughtBackByAnUnrelatedSettingsWrite` 等；启动参数 `--test-minimize`（进程内真实窗口 A/B：旧判定 FAIL / 新判定 PASS，A-003）；DESIGN §9.1「窗口位置记住」实测｜U02、U03、U38
- **I-04**｜真实的多显示器插拔 / Dock 改大小 / 全屏空间里的显示｜造不出真实的显示器变化｜`SK` 4 个 + `SL` 2 个（纯函数）、`SPT-A › aScreenParametersChangeRepositionsTheStrip`（发同名通知，进程内）、`settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize`（真实 `NSScreen` 上的定位）；`issues-app.md` 第四节表｜（U18、U26–U29 的真实屏幕效果；这些行本身已 ✓ / 偏离）
- **I-05**｜`AppModel.showOffice` 里「先渲染第一帧、再把窗口显示出来」的先后顺序（显示出来之后第一帧不闪要肉眼）｜顺序是两行代码的先后，单测里没有真的显示窗口｜`SPT-A › theOfficeWindowIsAnOrdinaryTitledResizableWindow…`（窗口没显示时 `render(force:)` 已经产出第一帧）+ `dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified`（钉住 `office.render(model: self, force: true)` 在 `office.showWindow(nil)` 之前）；小鱼缸 / 宠物条那条路是真的函数 + 测试（`PS`）｜M13a
- **I-06**｜右键菜单的弹出（模态）、菜单栏图标在真实菜单栏里的观感｜`NSMenu.popUpContextMenu` 会进入模态跟踪循环；菜单栏是系统绘制｜`SPT-A › theContextMenuOffersJumpRerollHideAndOpenOfficeInThatOrder`（钉住四项及顺序）、`theStatusMenuHasBuddyRowsThenTheFiveTogglesThenDemoSettingsAndQuit`（菜单栏菜单每一项的标题 / 状态 / 点击效果真的跑了）、`menuBarIconsAreEighteenPointTemplatesExceptTheColouredWaitingOne`（图标逐像素性质）；每一项背后的行为各有测试（`JT` / `AL` / `AM` / `AF`）；DESIGN §8 `--log-ui`（菜单栏图标 = waiting）｜U25
- **I-07**｜系统通知：授权弹窗、真实通知中心的投递 / 按 identifier 替换 / 撤销、点击通知的 userInfo 路径｜`UNUserNotificationCenter` 只在 .app 里可用；授权弹窗是系统的，用户已经拒绝过一次，不该再弹｜假通知中心 `AF`（denied / authorized / notDetermined / 非 App 包）、`NA`（请求逻辑）、`SPT-A › notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays`（钉住 identifier / userInfo / 撤销 / .app 判断）、`theSystemNotificationGateIsTheAppBundleAndAClickCarriesTheKey`；DESIGN §2 M0 第 2 项实测（授权被拒 → 走兜底）｜N10、N18（另：N12 里点真实系统通知这一步）
- **I-08**｜Dock 角标 / 弹跳的真实外观、像素提示卡的真实滑入动画、提示音真的发出声音｜看不到屏幕、听不到声音；`ToastController.show` 会显示真窗口｜`AF`（假 Dock / 假提示卡 / 假声音；变异检查证明测试抓得到兜底失效，`issues-app.md` B-001）、`SPT-A › theSoundsAreSynthesisedAsEightBitMonoWavDataWithoutAnyFile`、`theSoundModeFromTheSettingsReachesThePlayerAndEachKindHasItsOwnSound`、`notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays`（钉住弹簧参数 / 最多 3 张 / 6 秒 / 右上角坐标）；DESIGN §8（演示走到「等批准」：`toast.show` 8–25 ms、Dock 角标 `1`）｜N23b（另：N19 / N20a / N24a 的真实外观）
- **I-09**｜真实的 Claude 深链与激活：`NSWorkspace.open(claude://…)`、2.5 秒后的 `lastFocusedAt` 判定与连续失败计数、`openApplication(at:configuration:)` 把 Claude 带到前台｜需要真实 Claude、登录状态和未公开的内部深链；失败计数在真 `NSWorkspace.open` 之后的异步闭包里｜`JT`（目标 / URL / 判据纯函数 / 停用后的目标）、`SPT-A › theJumpServiceKeepsTheSpecifiedMechanisms`（钉住机制，`resetDeepLink` 真的清零）、`TT`（停用提示一行放得下）；启动参数 `--test-jump <hostSessionId>` 的实测（DESIGN §8：深链发出且没被判失败，失败计数 0；测的时候屏幕停在登录窗口，看不到前台切换）；DESIGN §2 M0 第 4、5 项｜J04、J10（另：J01 / J03 / J13 的真实跳转）
- **I-10**｜终端 / VS Code / 其他宿主的真实跳转与「自动化」授权、真实的父进程链和控制终端｜需要真实 Terminal / VS Code 窗口和系统自动化授权（对当前 App 身份没答复）；这台机器没有 iTerm 和 VS Code 的 Claude 扩展；单测宿主没有可用的控制终端｜`JT`（脚本 / tty 校验 / 目标）、`SPT-A › theTerminalScriptFollowsTheSpecifiedSteps`、`theProcessHelpersReadTheProcessTableAndTheHostLookupSkipsBackgroundApps`（sysctl 读到的父进程 = `getppid()`、找到的宿主是普通 App 且不是 CLI 包、钉住 12 层与过滤条件）、`theJumpServiceKeepsTheSpecifiedMechanisms`（钉住分支）；启动参数 `--probe-pid`（DESIGN §8）；DESIGN §2 M0 第 6 项（临时 Terminal 窗口里按 tty 选标签页实测通过）、§10｜J05、J06、J07、J08、J09
- **I-11**｜前台 App 的真实读取（Claude 在最前 / 终端宿主在最前）｜`NSWorkspace.frontmostApplication` 是系统状态，单测里没法安排｜判定拆成两半分别有测试：`AC`（`isLooking` 闭包的三种情形）、`CA`（最近聚焦的判断）；`SPT-A › theDesktopLookingRuleUsesTheFrontmostClaudeAndTheMostRecentlyFocusedSession`（钉住 `AppModel.isUserLooking` 的前台判断）｜N06
- **I-12**｜真实的 SessionStart hook 触发（跟着 Claude 开）｜需要真实的 Claude 会话启动；终端版 CLI 的登录过期，没能看到一次成功的回答（凭据不归我们碰）｜DESIGN §9.1（沙箱外 `claude -p "ok"`：hook 在 CLI 登录失败之前已触发、App 2 秒内被后台拉起、零输出、再触发不多开）；`HM`（hook 内容 / 幂等 / 卸载还原；本次没有重跑，约定不跑 hook-merge.py）｜F05
- **I-13**｜开机启动的真实注册（`SMAppService` / LaunchAgent）、全局热键 ⌃⌥⌘B 的真实注册｜真注册会往用户的登录项 / 系统级快捷键里加东西｜`SPT-A › loginItemUsesTheServiceManagementFirstThenTheSpecifiedLaunchAgentAndOnlyFromTheSwitch`（钉住路径 / 参数 / 顺序 / 唯一调用点）、`dockReopenCloseAndHotkeyBehaviourIsWiredAsSpecified`（钉住键码和修饰键）；`HK`（状态映射 / 失败回退）、`AP`（热键只在开关变化时注册 / 注销）；DESIGN §2 M0 第 3 项（`SMAppService.status = notFound`）、§8「开机启动」「全局快捷键」（`RegisterEventHotKey` 返回成功）｜C14、C16、U39
- **I-14**｜设置页 SwiftUI 的真实渲染 / 控件交互（「下次启动生效」的说明文字、授权状态刷新、登录开关回退、屏幕选择器）｜SwiftUI 视图没法在单测里驱动｜背后的纯函数各有测试（`EC` / `HK` / `SK` / `NA`）；`SPT-A › everySettingOfTheSpecExistsWithItsDefaultAndHasAControlInTheSettingsPage`（每个键都有 @AppStorage 控件、四个页签的名字）、`theSettingsWindowHostsTheSwiftUIForm`；启动参数 `--dump-settings` 逐页浅 / 深色出图（DESIGN §8）｜（C01、C17–C22 的视图渲染；这些行本身已 ✓）

### 10. 遗留缺口

本次新增的 75 个测试没有失败，也没有需要改产品代码才能通过的断言：所有和任务书不一致的地方都已经走「偏离」（DESIGN §13 新增 / 原有条目），测试断言的是实际数字。下面是写测试和跑全量时发现的、不影响这份追踪判定的观察项（都是 P3，交主线程决定要不要处理；我没有改任何产品代码 / 现有测试）。

| 编号 | 严重度 | 现象 | 复现 | 期望 |
|---|---|---|---|---|
| G-01 | P3 | Edit 屏幕（`.diffEdit`）「字符逐个出现」被高亮行里原来就画着的一条白线遮住了：那一行先画一条 3–13 像素长的白线（长度按 `hash(seed, 3) % 11` 取），之后 `chars = min(14, Int(t*6))` 才接着画，所以只有超过这条线的部分才看得出「出现」，多数种子下前几个字符一开始就在了 | `ScreenContent.draw(.diffEdit, t: 0.05 …)` 数第 9 行的白色像素：随种子不同，t = 0 时就有 3–13 个（`SpecTraceScreenTests.editTypesCharactersAndWriteAddsRowsFromTheTop` 为了看清增长，专门挑了白线最短的种子） | 高亮行先不画白线（或只画暗色占位），让字符从 0 个开始一个个长出来 |
| G-02 | P3 | Grep 结果列表的高亮条走到最后一行之后停 1.2 秒，然后一帧跳回第一行（`sel` 用 `smoothstep` 只缓动了下行，`t mod 2.4` 回绕时没有缓动） | `ScreenContent.draw(.results, t:)`：t 在 1.2–2.4 秒高亮固定在第 3 行，t = 2.4 秒回到第 0 行 | 回绕也缓动（比如往返走），或到底后淡出再从头 |
| G-03 | P3（测试卫生） | 现有测试（`PixelViewTests` 建 `OfficeWindowController`、`PanelAnimationTests` / `AppModelTests` 建面板并渲染）会让 AppKit 的窗口 frame 自动保存把 `NSWindow Frame BuddyOfficeMainWindow`（有时还有 `NSWindow Frame BuddyOfficeTankPanel`）写进测试宿主进程的偏好域 `~/Library/Preferences/swiftpm-testing-helper.plist`；不是 App 自己的偏好文件（App 的域是 `local.buddy-office`），但属于测试在用户偏好目录里留的痕迹（`SPT-A` 里我给自己碰到的键加了清理：`SPA.forgetAutosavedFrames()` 和 `defer`，所以带上 `SPT-A` 的全量跑完通常是空的） | 单独跑 `scripts/dev.sh test --filter PixelViewTests --filter PanelAnimationTests`（不带 `SPT-A`），然后 `plutil -p ~/Library/Preferences/swiftpm-testing-helper.plist`：06:10 实测多出 `NSWindow Frame BuddyOfficeMainWindow` 一行（我随后用 `defaults delete` 删掉了这一个键） | 那几个测试的收尾里删掉这个键（同 `SPA.forgetAutosavedFrames()`），或者让它们用自己的 `UserDefaults(suiteName:)` |
| G-04 | P3（测试稳定性，不是本次新增的测试） | 全量 `swift test` 我连跑了 3 次：第 1、2 次（用时约 112 s / 97 s）759 个测试全过；第 3 次机器负载高（全程 181 s），出现 4 个 issue，全在数据层的现有测试里：`EnginePresenceTests › unwritableDataDirectoryDoesNotCrashAndIsReportedInDiagnostics`（`tokens.output` 是 0，期望 5）、`terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles`（0，期望 1000）、`FuzzFileIOTests`「C-024 多个线程同时原子写同一个文件…」（等 120 s 超时、最终文件 0 字节）。本次新增的 13 个套件（加上另一位定稿员的 3 个 `SpecTrace*` 套件）三次全部通过 | 机器上同时有别的构建 / 测试在跑（别的审查员的 scratch 构建）时，跑一遍全量 `scripts/dev.sh test` | 这几个测试的等待改成「等条件成立」而不是固定时长，或者加大超时；不是这次新增的测试引起的 |
| G-05 | P3（编译警告，不是本次新增的文件） | `Tests/BuddyOfficeTests/DebugLogTests.swift:58` 的 `#expect(true)` 在 debug 编译时有一条「will always pass here」警告。本次新增的两个 `SpecTraceUITests.swift` 在一个全新的 scratch 目录里从零编译（156 s）0 警告 | 全新 scratch 目录 `BUDDY_SCRATCH=<新目录> scripts/dev.sh test`，看编译输出 | 换成有意义的断言，或写成 `Bool(true)` |

**处理结果（主线程，定稿之后）**：G-01 → `QA/issues-stage.md` **SP-07**（不修：屏幕只有十几个像素宽、肉眼几乎看不出，改它会让所有 Edit 屏幕的画面变化、金图要重审；P3）；
G-02 → **SP-08**（不修：循环小动画的回绕跳变在 15 fps 下不构成闪烁，闪烁扫描全部干净；P3）；G-03 → **SP-09**（已修：`PanelAnimationTests` 收尾时清掉自动记位置的键）；
G-04 → `QA/issues-review.md` **R1a-03**（已修：等后台扫描的超时放宽到 60 秒、C-024 的 120 秒放宽到 600 秒，断言原样不动；R2 复查另外发现的 R2-005 也修了）；
G-05 → **W-01**（已修：换成真的断言；完整回归改成数所有含 warning 的行——debug 构建的「0 警告」原来数漏了这一条）。

### 11. 原疑点的最终结论

原文件 §9 的 14 条疑点，逐条给最终结论。

| # | 原疑点 | 最终结论 |
|---|---|---|
| 1 | 小鱼缸的单击 / 双击可能被「按住背景拖动」吞掉 | **已修（防御性）**：A-002：`PixelView` / `PixelButton` 的 `mouseDownCanMoveWindow = false`，背景拖动改成 `PixelView` 手动 `performDrag`（DESIGN §13「应用层的决定」·小鱼缸拖动）。进程内 `--test-tank-click`（经 `NSWindow.sendEvent`）和新测试 `SPT-A › doubleClickingTheTanksBackgroundGoesBackAndClickingABuddyJumps` 都收得到点击；旧配置下自检同样没复现「被吞」，所以修法不冒充「已复现并确认」，真实鼠标路径见 I-01 |
| 2 | 长 Bash 进度条被头挡住 | **已修**：TA-013：进度条移到第 5–6 行；`SCT › theLongBashProgressBarIsAboveTheRowsTheHeadHides`、`SPT-S › terminalHasAGreenPromptAndTheLongBarFollowsOneMinusExpMinusTOverTau`（宽度逐点等于 1−e^(−t/30)） |
| 3 | 最小化的办公室窗口被「弹回来」 | **已修**：A-003 `ApplyPlanner`（只处理相对上次有变化的入口）；`AP` 四个测试 + `--test-minimize` 真实窗口 A/B |
| 4 | 「换个造型」当场看到的 ≠ 保存下来的 | **已修**：A-007，`VisualDirector.reroll` 等新盐到了再换；`AL › rerollWaitsForTheNewSaltAndThenEveryPlaceAgrees` |
| 5 | 隐藏全部 buddy 后 Claude 退出会让 Buddy 自己退出 | **已修**：A-010，被隐藏的也算活会话（DESIGN §13「应用层的决定」·提醒）；`AQ › hiddenBuddiesStillCountAsLiveSessions`、`AM › theAutoQuitLiveSessionCheckCountsHiddenBuddies` |
| 6 | 深链停用的提示被截断 | **已修**：B-006，标题 + 正文各一行放得下；`TT › theOldDeepLinkNoticeWasTruncatedAndTheNewOneFits` |
| 7 | 被隐藏的会话仍然弹窗 / 响铃 / 计入角标 | **已修（转成决定）**：B-009「隐藏 = 不打扰」，任务书没写，DESIGN §13「应用层的决定」·提醒 已记；`AC › hiddenBuddiesAreMutedNoAlertNoBadgeNoBounce` 等 |
| 8 | 严格闪烁扫描 14 处 1–5 像素抖动 | **转成偏离**：DESIGN §13「严格闪烁扫描」已记（标准阈值下 3 个场景 × 3 个缩放全部干净，`RT` 三个闪烁测试）；不修 |
| 9 | 几处文档和代码对不上 | **已修**：① DESIGN §5 未知工具「打字和鼠标交替」— 代码改成交替（SP-04）；② DESIGN §7「5 级抖动开机」— 已改成实际的 16 级，并作为偏离记入 §13；③ DESIGN §7「走到工位 ≈ 2.5 s」— 记了 70 px/s 封顶（§13「走到工位」），`WO` 有测试；④ 使用说明「点小人（或桌牌）」— 文档改成「点小人」（B-002，`JT › theUserManualDoesNotClaimThatThePlateIsClickable`）；⑤ 使用说明空闲阈值可改 — 现在写明「下次启动生效」（`EC`，DESIGN §13） |
| 10 | 文档滚动节奏不均匀 | **已修**：SP-03，133 ms（15 fps 的整 2 帧）；`SCT › documentAndLogScrollingStepsAreWholeFramesAt15fps`、`SPT-S › documentScrollsOnePixelPerStepAndItsColourFollowsTheExtension`；与任务书 150 ms 的差记为偏离（DESIGN §13「连续滚动的步长」） |
| 11 | 最后一个入口被强制保留时设置页显示不符 | **已修**：B-008，`ApplyPlanner.settingsWriteBack`；`AP › aForcedDockIconIsWrittenBackSoTheSettingsPageDoesNotSayOff` |
| 12 | 桌面「做完了」等 8 秒后才发，这期间下一轮可能已开始 | **已修**：B-001 ④；`AC › aPendingFinishedAlertIsDroppedIfTheNextTurnAlreadyStarted` |
| 13 | 深度思考「用笔轻敲桌面」没有笔 | **转成偏离**：DESIGN §13 原有记录（「没有笔道具，用手在键盘右端小幅上下敲代替」）；S01a2 = 偏离，`SPT-S › tappingScratchingWritingAndWavingFrequencies` 钉住实际的 1.85 Hz |
| 14 | 快捷键开着时每次设置变化都注销 / 重新注册热键 | **已修**：A-016，`ApplyPlanner` 只处理变化的项；`AP › nothingChangedMeansNothingToDo`（热键开着时无关的设置写入不再注销 / 注册） |

---
