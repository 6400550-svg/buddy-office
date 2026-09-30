# R3b 终审复查报告（表现层 + 像素引擎 + 文字审计 + 测试质量）

复查员 R3b，2026-09-29 11:53–12:30（时间盒 50 分钟内）。没有改项目源码 / 测试：编译、插桩（变异开关）和探针全在我自己的拷贝
`/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/r3b/`（`.build-r3b`）里；探针文件是拷贝里的 `Tests/BuddyStageTests/R3bProbeTests.swift`。

## 结论

**表现层的运行时行为：没有发现新的 P0 / P1。** 上一轮改的几处（VisualDirector 的 pending 作废、Performer 的 digitMask / 气泡 0.8 s / lastPrivacy、PlateCopy 的隐私 / 空 detail 文案、TextAuditRunner.Box.get / PixelFont.auditActive）行为都对，没有引入新的闪烁 / 卡住 / 等待类被拖后。
**发现 2 条 P2，都在测试基础设施上**：一个跨套件的全局量会让一条现有测试间歇性红灯（实测 10%）；隐私模式「桌牌标题 / 悬停卡片标题和路径不显示」这条最核心的隐私行为没有任何测试钉住（变异后 379 个测试全绿）。另有 5 条 P3。

## 新发现

### R3b-01 【P2 测试基础设施】`DesktopMeta.baseOverride` 是被多个套件同时改写的全局量：`R2-008` 测试间歇性红灯（跨套件并行）

- 位置：全局量 `Sources/BuddyOffice/JumpService.swift:140`（`nonisolated(unsafe) static var baseOverride`）；写它的有 `Sources/BuddyOffice/RealProvider.swift:11`（`RealProvider.make(args: [... "--data-root" ...])` 会永久改写它）、
  `Tests/BuddyOfficeTests/DesktopMetaFileIOTests.swift:28,44-45`（`.serialized` 只管这个套件内部）、`Tests/BuddyOfficeTests/ReviewRegressionAppTests.swift:158-164`（R2-008）、
  `Tests/BuddyOfficeTests/EngineConfigTests.swift:43,58,71`（调 `RealProvider.make(--data-root …)`，**从不复位**，改完就一直留在进程里）。
- 现象：所有测试在同一个进程里并行跑，这几个套件互相踩。R2-008 断言「`baseOverride` 就是我刚传的假 home」，中间被别的套件改掉就红；反过来 `DesktopMetaFileIOTests.readsLastFocused…` 读的目录被别人换掉就读到 `[:]`（或者在 override 为 nil 时读到用户真实的 `~/Library/Application Support/Claude/claude-code-sessions`）。
- 复现（拷贝里、已编好测试，沙箱外）：
  `BUDDY_SCRATCH=.build-r3b scripts/dev.sh test --skip-build --filter DesktopMetaFileIOTests --filter EngineConfigTests --filter ReviewRegressionAppTests --filter AppModelTests`，连跑 40 次：**4 次失败（第 4、16、20、27 次，10%）**，输出：
  - `ReviewRegressionAppTests.swift:164:9: Expectation failed: (DesktopMeta.baseOverride → "/var/folders/…/T/desktopmeta-342D819A-…") == "/x/fake-home/Library/Application Support/Claude/claude-code-sessions"`
  - 另一次同时还有 `:161:9: (DesktopMeta.base → "/x/fake-home/Library/…").hasPrefix(NSHomeDirectory() → "~")` 失败（EngineConfigTests 留下的 override 漏进了 R2-008 的「先复位为 nil」之后的检查）。
  整个 `BuddyOfficeTests` 目标单独连跑 12 次 0 失败——要几个套件在同一时刻碰巧交错才红，所以完整回归（4 遍全绿、「会抢全局量的组合连跑 20 次」清单里没有 R2-008 / EngineConfigTests）没有抓到。
- 后果：「789 个测试全过」这个数字会间歇性变成 788；和 R2-005 / SAN-02 同一类。
- 建议（我没改）：把所有碰 `DesktopMeta.baseOverride` / 调 `RealProvider.make(--data-root)` 的测试放进同一个 `.serialized` 套件（或用同一把锁），每个都在 `defer` 里复位；或者让 `RealProvider.make` 的 DesktopMeta 根目录走参数注入而不是全局量。

### R3b-02 【P2 测试基础设施 / 断言缺失】隐私模式「桌牌标题、悬停卡片标题和路径不显示」没有任何测试钉住

- 位置：`Sources/BuddyStage/OfficeScene.swift:509`（`options.privacy ? "会话" : …` 桌牌标题）、`Sources/BuddyStage/HoverCard.swift:40`（卡片标题）、`:42`（卡片里的项目路径 `cwd`）。
- 证据（变异测试）：在我的拷贝里给这三处各加一个环境变量开关，让隐私分支失效，**跑完整个 `BuddyStageTests` + `BuddyOfficeTests`（379 个测试 / 57 个套件）全部通过**：
  - 变异 20（桌牌在隐私模式下显示真标题）→ 0 个失败；变异 23（悬停卡片标题在隐私模式下显示真标题）→ 0 个失败；变异 21（悬停卡片在隐私模式下显示项目路径）→ 0 个失败。
  - 对照：同一批变异里，MCP / 未知工具名的隐私分支（16、17）、statusDetail 的隐私分支（22）、空 detail 文案（18）、displayTitle（15）都被现有测试杀死了。
- 为什么算 P2：这是任务书 6.3「隐私模式下隐藏全部细节」最直接的一条，上一轮 R1b-03（MCP server 名漏进桌牌）就是因为 `text-audit`「隐私 × 2」的矩阵只查排版、不查文案才漏掉的；现在标题 / 路径这两条同样没人看着，任何人重构 `plateTexts` / `HoverCard.make` 都可能悄悄把标题露出来而所有测试仍然全绿。**当前行为是对的**：我另写了端到端泄漏扫描（18 种工具 × 长 / 短耗时 × 工具 / 等批准，标题、路径、statusDetail、工具详情、server 名都带「SECRETXYZ」，隐私模式下走 Director → OfficeScene（在场 + 下班工位 + 悬停）→ HoverCard，收集所有文字层文字、桌牌动作、状态候选）：**0 处泄漏**。
- 建议：补两条测试——办公室一帧里所有 `TextItem.text` 都不含真标题（在场 + 下班 + 悬停），`HoverCard.make(privacy: true)` 的 texts 不含标题和 cwd。

### P3（一句话）

1. **R3b-03（P3）**：桌牌 / 悬停卡片标题里的阿拉伯文、天城文（印地语）、叠字符号、泰文，笔画会被文字图片的边缘裁掉（`text-audit` 的「超出容器或被裁切」能抓到：我的 22 种怪标题 × 4 缩放 × 3 窗口 × 隐私开关里 570 处，全在 plate.title / card.title）。是已知 R1b-P3-05（只提了泰文 / 藏文 / Zalgo）的扩展：阿拉伯文和天城文同样中招；希伯来文、全角、增补平面汉字、ZWJ 家庭 emoji、国旗、肤色 emoji、10000 字长标题都 0 违规。
2. **R3b-04（P3）**：`PlateCopy.displayTitle`（`PlateCopy.swift:60-70`）的「不可见字符」清单不全：只有 U+3164（韩文填充符）、U+2800（盲文空白）、U+034F、U+FE0F / U+FE00（变体选择符）、U+17B4/5、U+1160、U+FFA0、U+180B–D，或只有组合附加符的标题，不会换成占位「（没有标题）」，仍然画出一块看起来空的牌子（探针 `invisibleTitles` 实测这 10 类没被替换）。数据层不会给出这种标题，纯防御。
3. **R3b-05（P3）**：隐私模式下 MCP 屏幕（`ScreenKind.mcpApp`，`Performer.swift:168` / `ScreenContent.swift:278-283`）仍然画 server 名的首字母（`SECRETXYZsrv` → 屏幕上画一个「S」，扫描里唯一的泄漏点）。任务书那句「隐私模式下隐藏全部细节」写在桌牌缩写规则下，屏幕图标不算文字，所以只记 P3。
4. **R3b-06（P3）**：`Tests/BuddyStageTests/AppLayerFixTests.swift:297` 在测试里不加锁地读全局 `ScreenContent.staticCache.count`，而别的并行测试正在（加锁地）改它；理论上有数据竞争（Swift 字典读写并行）。我没能复现出崩溃 / 红灯，所以不算 P2。
5. **R3b-07（P3）**：`OfficeScene.render` 悬停的座位号是 `Int.max` / `Int.min` 时 `lay.cellOrigin(seat:)` 乘法溢出崩溃（探针 `oneWildSeat` mode=hover；同样的座位号在办公室 / 下班 / 小鱼缸 / 宠物条里都不崩）。UI 里不可达（悬停座位来自命中缓冲的 ID，最大 999），只是纵深防御。

## 疑点（没有证据，不算问题）

- `VisualDirector` 推迟期间拿旧快照拼的 `effective`（`VisualDirector.swift:89`）不更新 `seat`；座位号在推迟的 0.6 秒内变化时表演者的 `seat` 会晚一拍。座位号一直是稳定的，没有找到能触发的路径。
- `DrawRecord.canvasID` 用 `ObjectIdentifier(canvas)`：别的线程画过像素字、之后被释放的画布，地址理论上会被审计线程的新画布复用，造成「别人的记录被算到我这一帧」的假阳性（只会多报，不会漏报）。我写了压力探针（3 个后台线程不停地建画布 + 画像素字，审计线程 15863 次 `withDraws` 里分配新画布）：0 次撞上，所以只记疑点；如果要根治可以给 `Canvas` 加一个自增序号当 ID。
- `HousekeepingTests.aStuckStopCannotHoldTheMainThreadForLongerThanTheTimeout` 断言 `waited < 0.6`（超时 0.2 秒），机器满载时有 3 倍余量，没见到失败。
- 变异 35（悬停卡片放置时不再避开气泡，`OfficeScene.swift:290`）：`TextAuditTests` 和完整悬停矩阵（1360 个组合）都不红——说明现有组合里「卡片会盖住气泡」这条从来没有被触发过（等价变异 / 或这条避让没被任何组合用到）。

## 检查过什么（覆盖清单）

**读过的代码**：QA/ISSUES.md 汇总表、REPORT.md 第 2 / 7 / 8 节；VisualDirector / Performer（全文）/ PlateCopy / OfficeScene / TankScene / StripScene / ScreenContent（全屏幕种类）/ Walkers / OfficeLayout / HoverCard / ToastCard / TextAudit / TextAuditRunner / AuditFixtures / StageRun（compareRetained 的覆盖面）/ PixelKit 的 Canvas / PixelFont / TextRenderer / Motion（Spring）/ Frame（TextLayout）；SceneClock / Lighting 缓存的加锁；Tests 里全局量（`nonisolated(unsafe)` 全表）的读写者。

**跑过的**：
- 在自己的拷贝里 release 编 `buddyctl`、debug 编测试；`buddyctl golden` 17/17 一致，并把 17 张金图导出成 PNG，亲眼看了 `office@1200_t=5`、`office@1200_t=41`（等批准 / 提问 / 重试 / 做完了 / 打盹 / 空椅子都对，桌牌文字清楚、没有互相压）。
- **随机序列不变量**（探针 `randomSequenceInvariants`）：40 个种子 × 4 个人 × 40 秒 × 30 fps，活动在 14 类（思考 / 三种等待 / 做完 / 空闲 / 压缩 / 16 种工具）里随机跳、停留 0.05–3.7 秒，每 10 秒切一次隐私模式（每 3 个种子一组）。检查：① 等待类当帧生效（SP-06）② 屏幕换得不快于 0.8 s（等待屏除外）③ 工具气泡之间换得不快于 0.8 s ④ 桌牌动作换得不快于 1.0 s（数字计数器、等待类、隐私刚切换除外）。**0 处违反。**
- **不卡住**（探针 `settlesToTarget`）：60 个种子 × 5 个人 × 60 秒，活动稳定 2.6 秒之后屏幕 / 气泡 / 桌牌动作必须等于目标：**0 处卡住**。
- **digitMask**（探针 `digitMaskStableAcrossTimers`）：9 种工具 × 并行 1 / 2 / 12 × 计时 0–4000 秒，只有计时变化时掩码必须不变：0 处不稳。
- **变异测试（在拷贝里加 `R3B_MUT` 环境变量开关，一次编译、逐个开）**：气泡最短停留（3）/ 气泡只对工具气泡生效（4）/ 隐私刚切换绕过（6）/ digitMask 三种（7、8、9）/ 桌牌等待类绕过（10）/ 屏幕等待类绕过（11）/ Director 作废两条件（12、13）/ displayTitle（15）/ MCP 与未知工具隐私分支（16、17）/ 空 detail 通用文案（18）/ 卡片 statusDetail 隐私（22）：**全部被现有测试杀死**。存活的：14（等价：`changed && !needsUser` 改成 `changed`，之后 `needsUser` 还会作废，行为不变）、5（`held` 里的 `!adoptNow` 是死代码：`bubbleHoldSince` 初值 -100，第一帧本来就不会被拦）、20 / 21 / 23（R3b-02）。
- **文字审计灵敏度变异**（整条管线，不是造出来的输入）：两行桌牌行距改成 -3（30）/ 状态行下移 9（31）/ 文字最大宽度 ×3（32）/ 桌牌字改浅色（33）/ 悬停卡片不避头和屏幕（34）/ 悬停时不收起被盖住的桌牌字（36）：`TextAuditTests` 分别红 12 / 50 / 76 / 16 / 9 / 65 个——审计器对真实布局错误是灵敏的。
- **怪标题** × 缩放 2–5 × 3 种窗口 × 隐私开关 × 悬停四角：22 种（阿拉伯文、希伯来文、换行、制表符、回车、叠字符号、全角、增补平面、ZWJ 家庭 emoji、国旗、肤色、盲文空白、韩文填充符、零宽、对象替换符、NUL、40 位数字、连续方括号、多空格、1 万字、泰文、天城文）：只有 R3b-03。
- **非 Retina（scale 1）文字审计**（`--quick` 的组合 + 3 种窗口 × 缩放 2–5，3004 个组合，8 类检查）：0 违规（`text-audit` 命令行没有 `--scale`，主矩阵只跑 scale 2）。
- **极端值不崩**：办公室视口 (1,1) (0,0) (5,5) (40,40) (3000,20) (20,3000) (-10,-10) × 0 / 1 / 5 / 70 个会话 × 缩放 1 / 2 / 5 × 隐私开关 × 悬停 + `FrameRenderer.render`，1536 帧；`HoverCard.make` 的 maxWidth / maxHeight 取 0、负数、NaN、无穷；`TextRenderer` 字号 0–5000 × maxWidth 0 / 负数 / 极小 / 极大 × scale 1 / 2 / 8；`PixelFont.draw` 在 1×1 画布 + 坐标 ±1000 / 1e6；座位号 Int.max / Int.min / -1 / 999999 / 64 / 重复 key（办公室 / 下班 / 小鱼缸 / 宠物条）：只有 R3b-07。
- **隐私端到端泄漏扫描**：见 R3b-02；只有 R3b-05。
- **全局状态 / 并行**：`SceneClock`、`Lighting.resolvedCache`、`ScreenContent.staticCache`、`TextRenderer` 缓存的加锁都对；`TextAuditRunner.renderLock`、`hoverStats`（目前只有一个测试调 `run`，没有并行冲突）、`PixelFont` 审计钩子（`auditActive()` 在锁里读没问题）；跨套件的 `DesktopMeta.baseOverride` → R3b-01。BuddyStage + BuddyOffice 整体（379 个测试）在我的拷贝里完整跑了 3 遍（变异 20 / 21 / 23 各一遍，探针套件同时在跑），`BuddyOfficeTests` 目标单独连跑 12 遍，除 R3b-01 外没有别的间歇性红灯。
- 缓存 / 字典有没有无界增长：`appearances`（≤96 才修剪，见在场的人数上限）、`plateCache` / `seatCaches` / `emptyApps`（按座位号，桌子数封顶 64）、`TextRenderer`（600 张 / 4000 条）、`resolvedCache`（400）、`staticCache`（4096）、`screenMemory` / `screenFade`（按座位号）、`helperTracks`（离场 0.6 秒后清掉）：都有界。

**没覆盖到 / 没时间做**：`buddyctl verify` 的全量逐像素对比（用已有的 RenderingTests 里的局部重绘对比代替，全部通过）；ASan / TSan；BuddyCore 数据层；真实 GUI。

## 统计

| 严重度 | 新发现条数 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 2（R3b-01 跨套件全局量致间歇红灯；R3b-02 隐私标题 / 路径没有测试钉住） |
| P3 | 5（R3b-03 … R3b-07） |
