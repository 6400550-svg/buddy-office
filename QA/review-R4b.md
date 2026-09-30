# R4b 终审复查（测试可靠性 / 全局状态审计 + 表现层对抗式检查）

复查员 R4b（全新视角），2026-09-29 13:00–13:45（墙钟 45 分钟内）。**没有改项目源码 / 测试**：拷贝在
`/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/r4b/`（`.build-r4b`），原始日志都在它的 `logs/` 里（下文写作 `logs/…`）；主目录只写了这份报告。
没有碰 `~/.claude`、`.key`、`.sock`、运行中的 App、ccmon / 用量表；没有联网。

**机器状态（很重要）**：整个 45 分钟里另一位复查员和 ASan / TSan 检查同时在跑，`uptime` 的 load average 在 10 – 250 之间（6 核）。所以本轮的「失败」全部按下面第 2 节分类：**忙机器下的失败单独列出，没有一条被当成「机器忙」放掉**。

## 结论

**新发现：P0 0 条 / P1 0 条 / P2 1 条 / P3 5 条。**

- **P2（R4b-01，测试基础设施）**：TokenLedger 的默认扫描队列是 `.background` QoS，CPU 一饱和它就被饿死；**所有「等账本扫完」的测试**（1 条 QoS 断言 + 8 条读账本结果的测试 + 5 条带外层超时的模糊测试，共 14 条）用的是 10 / 20 / 60 / 90 / 120 / 180 秒的死等，饿死时间一长就间歇性变红。实测：默认并行整套 **12 遍里红 5 遍**（5 遍红的失败全部是这一类，没有别的失败），单条最小复现见下。R3a 在第 7 遍回归里见过 `4.3-42` 红过一次、当成「机器满载误报」没立项；实际它不是一条，是一族，而且**在只有「另一位复查员在编译 / 跑测试」这种日常负载下就会红**（load 75 时 1 遍、load 240 时 1 遍、load 只有 16 左右时 1 遍）。
- 上一轮 R3 修的三处（`DesktopMetaGate`、`FuzzSecurityTests` 的登记表诱饵、`OpenAudit(scope:)`）**在我这里没有再红过**（`DesktopMeta` 相关 51 个测试 × 8 个套件连跑 150 遍，0 红）。除 R4b-01 这一族之外，本轮所有连跑里**没有出现任何别的失败**。
- 表现层：`buddyctl golden` 17/17 一致；`verify`（局部重绘 vs 整张重画）在没跑过的配置上 32 250 对帧逐像素一致；`PixelFont.auditActive()` 的锁没有死锁 / 锁序环；没有找到新的 P0–P2。

## 1. 进程全局可变状态普查表

（「读并断言」= 有测试对它的值做断言；「互斥」= 有没有让别的套件不能同时碰它。`.serialized` 只管套件内部，跨套件都是并行的——我在 `logs/fio-2.log` 里核对过：`FileAccessTests`（含 3 个文件里的扩展）里的测试确实一条一条串行，但同一时刻别的套件（`C-006`、`C-014` …）在并行跑。）

| # | 全局量（位置） | 谁写 | 谁读并断言 | 互斥 / 范围限定 | 结论 |
|---|---|---|---|---|---|
| 1 | `FileIO._observer` = `openObserver`（`FileIO.swift:28/33`） | `RegistryTests.swift:228/257/286`（**不带路径过滤**，在串行套件里）；`FuzzSecurityTests.swift:62/106`、`FuzzRegressionTests.swift:741/784`（按自己临时目录前缀过滤）；`OpenAudit.install(scope:)`（OpenAuditTests，`buddydump --audit-opens`） | 同上几条 + 所有并行测试的 `FileIO.open` 都会触发回调（在它们自己的线程里） | 写者都在 `.serialized` 的 `FileAccessTests` 里；读者靠前缀过滤 / 断言形状（只断言「没有 .key」「含 1001.json」）防噪声；`openAudit_countsForbiddenAttemptsOnlyAfterInstall` 没设范围但只断言拒绝次数 | ✅ R3a P2-1 已修；`fio` 组合 3 遍全过、12 遍整套里这些测试没有红过 |
| 2 | `FileIO._forbiddenHits` = `forbiddenHits`（`FileIO.swift:29/39`） | 任何 `FileIO.open` 到 `.key` / `.sock` / `cc-socks`（含符号链接）的调用 | `RegistryTests.swift:235`（`== hitsBefore`）、`:243`（`== before + 3`）；`OpenAuditTests`（`forbiddenAttempts == 0 / 1`）；`FuzzRegression:694`（`>= before+3`）；`FuzzSecurity`（`> hits0`） | 我把 Tests/ 里造 `.key` / `.sock` / 指向 key 的符号链接的地方全查了：会真的 `FileIO.open` 它们的全在 `FileAccessTests` 扩展里；`StateRuleTests:1059`、`StateRuleChainTests:98/140`、`FuzzWatcherTests:48` 只造文件名、引擎从不去 open | ✅ 没有第二个会让计数器动的并行来源 |
| 3 | `FileIO._tmpCounter` | `writeAtomically` | — | NSLock | ✅ |
| 4 | `DesktopMeta.baseOverride`（`JumpService.swift:140`） | `RealProvider.make(--data-root)`（`RealProvider.swift:11`）；测试：`DesktopMetaFileIOTests`、`ReviewRegressionAppTests` R2-008、`EngineConfigTests`×3 | `DesktopMetaFileIOTests`、R2-008、`EngineConfigTests` | 全部走 `DesktopMetaGate`（NSLock，进出复位 nil）；没有门外的读者（`CachesTests` / `JumpTests` 用注入的 `read:`；`AppModel.isUserLooking` 只有真 Claude.app 在最前才读，见疑点 3） | ✅ 连跑 150 遍 0 红（R3b：修前 40 遍 4 红） |
| 5 | `DesktopMeta.cache`（1 秒缓存，`JumpService.swift:189`） | 生产代码 | 测试都用自己 new 的 `Cache(read:clock:)` | — | ✅ |
| 6 | `TextRenderer.shared` 的 `cache`（600 张 FIFO）/ `sizes`（4000）（`TextRenderer.swift:41`） | 所有渲染（几十个测试并行） | `TextCacheBoundTests`：`lastAgain === last`、`firstAgain !== first`、`bytes < 30 MB` | 内部 NSLock；断言只依赖「最后一次渲染到再取」之间没有 ≥ 600 条别人的新文字插进来（窗口是微秒级）；`first` 被淘汰只会因别人加得更多而更稳 | ✅ `stg` 组合（TextAudit 矩阵 + 它同时跑）3 遍全过、整套 12 遍里没红过；理论窗口见 P3-3 |
| 7 | `PixelFont.auditEnabled` / `auditSinkStorage`（`PixelFont.swift:37-44`） | 只有 `TextAuditRunner.withDraws`（`renderLock` 串行） | `TextAuditTests`（按 canvasID 过滤）、`SAN-01`（只数自己画布）、**`ScreenContentTests.swift:42`（不按 canvasID 过滤，只看 `missingGlyph`）** | `renderLock` 让所有 `withDraws` 互斥；`draw` 在 `auditLock` 里读开关，sink 在锁外调用；锁序 `renderLock → scratchLock → auditLock`，Box 锁在 sink 里且从不反向 | ✅ 没有死锁 / 锁序环；`ScreenContentTests:42` 见疑点 1 |
| 8 | `TextAuditRunner.hoverStats`（`:122`） | 只有 `run()` 写、`defer` 复位 | 只有 `run()` 的调用者（测试里只有 `TextAuditTests.swift:331` 一个） | 单调用者 | ✅ |
| 9 | `OfficeScene.inkExtentCache`（`:481`）/ `SceneClock.sec,cached` / `Lighting.resolvedCache` / `ScreenContent.staticCache` / `SeatRenderer.screenScratch` / `PaletteLUT.counter` | 渲染 | `AppLayerFixTests.swift:297` 不加锁读 `staticCache.count` | 前几个都有锁；`staticCache.count` 那处无锁（R3b-06 已知 P3） | ✅（已知 P3 不重报） |
| 10 | `Prof.enabled` / `Prof.acc`、`PixelView.surfaceSetsAllocated`、`SettingsView.initialTab`、`HotKey.current`、`SoundSynth.players`、`TitleBarButtons.cache` | App / buddyctl 自己 | 测试都不读不写 | — | ✅ |
| 11 | `Settings.shared`、`UserDefaults.standard`（测试宿主域 `swiftpm-testing-helper`：`NSWindow Frame BuddyOffice…`、`login.enabled`、`office.visible`） | `@MainActor` 的面板 / 窗口测试；`Fx.Store` 用临时文件当 suite | 同一批 `@MainActor` 测试 | 主线程串行；`defaults read swiftpm-testing-helper` 现在是空的（没有残留） | ✅（跨进程共享见疑点 5） |
| 12 | `JumpService.shared` / `NSApplication.shared` / `NSWorkspace.shared` | 主线程 | 只读 | `@MainActor` | ✅ |
| 13 | 环境变量 / 当前目录 / 临时目录 / 端口 / 固定文件名 | 无 `setenv` / `chdir` / `umask`；`TMPDIR` 只读；所有临时目录带 `UUID`；没有端口；没有固定文件名 | — | — | ✅ |
| 14 | 进程级文件描述符表 | 所有并行测试 | `FuzzSecurityTests.swift:200-202`（`after - before <= 150`） | 只靠 150 的容差；我用 `lsof` 每 0.1 s 采样整套运行，整套里最大 0.6 s 内涨幅只有 11（`lsof` 会漏数，仅作参考） | ⚠ 疑点 4 |
| 15 | **`TokenLedger` 默认 `.background` 队列**（`TokenLedger.swift:106`；`SessionEngine.swift:104` 建账本时不给队列） | 每个账本实例自己的队列，但 QoS 是共享的系统资源 | 见 R4b-01 的 11 条测试 | 无（任何限制 CPU 的东西都会饿死它） | ❌ **R4b-01** |
| 16 | 系统服务：`fseventsd` / 前台 App / NSScreen | — | `StoreTests.swift:168-180`（FSEvents 延迟）、`FileWatcherTests` | 都有 2–8 秒余量；整套 12 遍 + `fio` 第 2、3 遍没红 | ✅（忙机器上限是疑点 6） |

## 2. 实测间歇性红灯

### 2.1 跑了什么

| 组 | 命令 / 范围 | 遍数 | 结果 |
|---|---|---|---|
| **full**：整套默认并行 | `swift test --skip-build`（796 个测试 / 91 个套件，R3 后比报告里的 789 多 7 条） | **12 遍**（11 遍完整跑完、1 遍被我杀掉；`logs/full-*.log`、`logs/summary-full.txt`） | 见下表 |
| **dm**：`DesktopMeta` 全局量 | 直接跑测试可执行文件 + `--filter DesktopMetaFileIOTests EngineConfigTests ReviewRegressionAppTests AppModelTests JumpTests SettingsTests CachesTests`（51 个测试 / 8 个套件，每遍 0.4–1.5 s） | **150 遍** | **150 / 150 通过**（`logs/summary-dm.txt`） |
| **fio**：`FileIO` 全局观察口 / 计数器 + 会并行读文件的引擎测试 | `--filter FileAccessTests FuzzSecurityTests FuzzRegressionTests OpenAuditTests StoreTests EnginePresenceTests EngineScenarioTests StateRuleTests HookLogTests ReviewRegressionTests RegistryTests`（202 个测试 / 13 个套件） | 4 遍（第 4 遍被我主动杀掉） | 第 2、3 遍绿；第 1、4 遍红（**都是 R4b-01 那一族**，第 1 遍时我在另一处压着 8 个 CPU 空转进程，第 4 遍时我自己同时开着 3 个测试进程） |
| **stg**：`TextRenderer` / 像素字钩子 / 文字审计矩阵同时跑 | `--filter TextCacheBoundTests TextAudit ReviewRegressionStageTests ScreenContentTests AppLayerFixTests ExtremeValuesTests PlateCopyTests RenderingTests`（95 个测试 / 10 个套件，每遍 60–77 s） | 3 遍 | 3 / 3 通过 |

（我一度同时开 4 组循环，load 冲到 250，之后压成 1–2 组，避免把别人的检查也拖红；组间的干扰记在 `logs/summary-*.txt` 的 `load=[…]` 里。）

整套默认并行：

| 遍 | 时间 / load | 结果 | 失败的测试 |
|---|---|---|---|
| full-1 | 13:06–13:09，load 75 | **红**（181 s，2 个 issue） | 只有 `4.3-42`（`SpecTraceCoreTests.swift:389`） |
| full-2 | 13:09–13:10，load 23 | 绿（96 s） | — |
| full-3 | 13:10–13:15，load 44→240 | **红**（254 s，2 个 issue） | 只有 `4.3-42` |
| full-4 | 13:15–13:16，load 128 | 绿（92 s） | — |
| full-5 | 13:16–13:24，load 58→130（撞上我自己的 8 个 CPU 空转进程 + 另外 2 个并行测试进程，7.5 分钟后我杀掉，只有部分日志 `logs/full-5-partial.log`） | **红**（被杀） | 10 条：`4.3-42`、`C-028`、`C-004`、`C-005`、`chain2`（`StateRuleChainTests.swift:214`）、`terminalClearKeepsTheBuddy…`、`aTerminalSessionOnlyCountsItsCurrentSessionId`、`unwritableDataDirectory…`、`ledger.json 在每一个字节位置被截断`、`token 账本：随机的真实行…` |
| full-6 | 13:24–13:26，load 133 | 绿（115 s） | — |
| full-7 | 13:26–13:32，load 74 | **红**（357 s，12 个 issue） | 6 条：`4.3-42` + 5 条 `FuzzPersistenceTests` 里的账本测试（`fuzzRun` 的 120 / 180 s 外层超时） |
| full-8 | 13:32–13:33，load 52 | 绿（85 s） | — |
| full-9 | 13:33–13:34，load 23 | 绿（62 s） | — |
| full-10 | 13:34–13:36，load 18 | 绿（83 s） | — |
| full-11 | 13:36–13:37，load 10 | 绿（97 s） | — |
| full-12 | 13:37–13:40，load 16→18（我这边只有这一个进程） | **红**（150 s，2 个 issue） | 只有 `4.3-42`（`logs/full-12.log`）：**在 load 只有 16 左右时也红了** |


### 2.2 分类

**A. 忙机器下的失败（全部属于同一个根因，P2，见 R4b-01）**：full-1、3、5、7、12、fio-1、fio-4 的每一条失败都是「等 `.background` 队列上的账本扫描」超时：`4.3-42`（90 s）、`C-004/005/028`、`EnginePresenceTests` / `StateRuleTests` / `StateRuleChainTests`（chain2）里读 `tokens.output` 的 5 条、`FuzzPersistenceTests` 的 `fuzzRun(timeout: 120/180)`。**没有任何一条别的类型的失败**。

**B. 不是机器忙的失败**：**没有**。所有失败的测试（去重后共 14 条）都属于「等 `.background` 账本队列」这一族；其余 782 条在 12 遍整套 + dm 150 遍 + fio 4 遍 + stg 3 遍里一次都没红过。注意 full-12 说明「机器不忙」也不保险：整套自己就有大量默认 QoS 的 CPU 密集测试（TextAudit 矩阵、SAN-01 的空转线程、模糊测试），在 load ≈ 16 时也会把 `.background` 队列饿过 90 s。

**C. 忙机器下没红、但阈值写得偏紧的（没有失败证据，列为疑点 6）**：见文末。

## 3. 新发现

### R4b-01 【P2 测试基础设施】账本的 `.background` 队列在 CPU 饱和时被饿死，一族等它的测试间歇性变红（整套默认并行 12 遍红 5 遍）

- **位置**：根因 `Sources/BuddyCore/Ingest/TokenLedger.swift:106`（默认队列 `DispatchQueue(label: "buddy.tokenscan", qos: .background)`）与 `Sources/BuddyCore/Fusion/SessionEngine.swift:104`（引擎建账本时不给队列，测试没有注入点）。受害的测试（全部通过默认队列 + 有限时间的等待）：
  - `SpecTraceCoreTests.swift:384-390`（`4.3-42`：`sem.wait(timeout: .now() + 90)`）；
  - `FuzzRegressionTests.swift:137/139`（C-004）、`:159/161/169`（C-005）、`:502-513`（C-028：外层 `fuzzRun(timeout: 20)` 比里面的 `waitUntilIdle(timeout: 60)` 还短，`:511` 又是 10 s 死等）；
  - `EnginePresenceTests.swift:275/289/355/546-558`、`StateRuleTests.swift:768/781`、`StateRuleChainTests.swift:232`：`waitUntilIdle(timeout: 60)` 之后立刻 `#expect(tokens.output == …)`；
  - `FuzzPersistenceTests.swift:29-331`：`fuzzRun(timeout: 120/180)` 里一串 `waitUntilIdle(timeout: 60)`（截断 / 随机对照）。
- **证据 1（自然负载）**：整套默认并行 `logs/full-1.log`（load 75）、`logs/full-3.log`（load 240）各红一遍，失败输出：
  ```
  ✘ Test "4.3-42 …" recorded an issue at SpecTraceCoreTests.swift:389:9: Expectation failed: (sem.wait(timeout: .now() + 90) → .timedOut) == .success
  ↳ 扫描应该完成并回调（后台队列在机器很忙时可能排队很久）
  ✘ … SpecTraceCoreTests.swift:390:9: Expectation failed: (seen → qos_class_t(rawValue: 0)) == (QOS_CLASS_BACKGROUND → …(rawValue: 9))
  ```
  这时机器上只有「另一位复查员在编译 / 跑 ASan」，没有我自己的压力。
- **证据 2（最小复现）**：只跑这一条：`swiftpm-testing-helper … --filter theDefaultScanQueueRunsAtBackgroundQoS`。
  - 对照（空闲的一点点时）：0.061 s / 0.075 s 通过；环境负载 ≈ 95 时第一次跑是 **27.6 s**；
  - 同时开 8 个 `perl -e 'alarm 100; while(1){}'`（6 核机器，默认优先级）：**90.012 s 后 `timedOut`**（`logs/qos-stress.log`）——**单独一个测试、没有任何别的测试在跑**，说明是队列被饿死，不是测试之间互相踩。
- **证据 3（一族一起红）**：同样压力下 `fio` 组合（`logs/fio-1.log`，202 个测试 / 13 个套件，170 s，10 个 issue）红了 7 条测试（另有 `4.3-42` 在 `full-*` 里）：C-028（`FuzzRegressionTests.swift:513` `called.value → 0 >= 1`）、C-005（`:161/:169` `waitUntilIdle(timeout: 60 → 60.0)` 失败）、C-004（`:139/:141` `t.messages → 0 == 1`）、`j1 …/clear`（`StateRuleTests.swift:769/788` `tokens.output → 0 == 1000`）、`unwritableDataDirectory…`（`EnginePresenceTests.swift:358` `→ 0 == 5`）、`aTerminalSessionOnlyCountsItsCurrentSessionId`（`:560` `→ 0 == 11`）、`terminalClearKeepsTheBuddy…`（`:276` `→ 0 == 1000`）；`full-5-partial.log` 里再加 `FuzzPersistenceTests.swift:55/69`、`:245`（`fuzzRun` 的 120 / 180 s 外层超时）。`fio-4`（我自己同时开着 3 个测试进程，没有额外空转进程）也红在 C-005 / C-028。
- **为什么算 P2**：报告里「796 个测试全过」这个数字在忙机器 / 多个检查同时跑的环境里（正好就是 QA 现在的做法）不能复现；而且红的位置（`tokens.output == 0`、`waitUntilIdle → false`）看起来像账本 / 引擎逻辑坏了，会误导排查。它只会误报红，不会误报绿。
- **建议**（没改）：
  1. 引擎测试给 `SessionEngine.Options` 加一个账本队列注入点，测试传 `.userInitiated` 的队列（`TokenLedgerTests.swift:11` 已经这么做了）；或者把这些等待统一放宽到 ≥ 600 s（`FuzzSecurityTests.swift:358` 已经是 600 s 并写了原因）；
  2. `4.3-42` 不要靠「等它被调度」来断言 QoS：`4.3-43`（`SpecTraceCoreTests.swift:393`）已经把 `qos: .background` 钉在源码文字上了，这一条可以改成用 `dispatch_queue_get_qos_class(queue, nil)` 同步读，或者把 90 s 放宽；
  3. `FuzzRegressionTests.swift:505` 外层 `fuzzRun(timeout: 20)` 包着 `waitUntilIdle(timeout: 60)`：外层不能比里层短。

## P3（一句话）

1. **表现层 / 闪烁扫描覆盖缺口**：`buddyctl flicker` 在非 demo 的模式下（会话在启动时就在的场景）会报「检查 2」：`flicker --scene office --zoom 3 --mode busy6 --from 0 --to 3` → 第 6 帧 12 个孤立像素 A→B→A（范围 (49,68)-(63,76)）；`--mode crowd12` → 第 30 帧 10 个孤立像素（范围 (161,220)-(171,228)）；与时钟无关（12:00 / 06:50 / 22:30 都一样），`idle6` 干净，tank / strip 干净；条带图看是显示器开机的 Bayer 抖动渐变（300 ms）刚过渡到打字内容那一帧，约 10 个美术像素 33 ms，超过容忍度 6，肉眼几乎看不出。完整回归里的闪烁扫描只跑 demo 模式，所以从来没暴露。（`logs/flk1/`、`logs/flk2/` 里有条带图。）
2. **R3 新加的三条测试会让 3–4 个线程空转很久**：`OpenAuditTests.swift:106`、`FuzzSecurityTests.swift:142`（不 `sleep` / `yield` 的 `while !stop { FileIO.open }`），`ReviewRegressionStageTests.swift:279`（SAN-01 的 4 个 `draw` 空转）。SAN-01 单独跑 0.12 s，但和 `TextAuditRunner` 的矩阵（长时间持有 `renderLock`）同时跑时它被 `renderLock` 挡住 21–29 s（`logs/stg-1..3.log`），这段时间 4 个核在空转，会加重忙机器下的 R4b-01。
3. **`TextRenderer.image` 并发同一个 key**（`TextRenderer.swift:147-171`）：两个线程同时未命中会各渲染一次、`order` 里重复入队；淘汰时 `removeFirst` 会把还有一个副本在队列里的 key 提前从 `cache` 里删掉——只影响命中率，不影响正确性（`TextCacheBoundTests` 的 `<= 600` 上界仍成立）。
4. `fuzzRun("flush inside onChange", timeout: 20)`（`FuzzRegressionTests.swift:505-507`）外层超时比里层 `waitUntilIdle(timeout: 60)` 短（并入 R4b-01 的修法 3）。
5. `openAudit_scopeKeepsConcurrentOpensOfOtherTestsOut`（`OpenAuditTests.swift:113-116`）：「不设范围的会被记进来」这条断言依赖噪声线程在 0.3 s 窗口内被调度到；忙机器上可能落空（没见到失败；修法：等噪声线程至少 open 过一次再开审计）。

## 疑点（没有失败证据，不算问题）

1. `ScreenContentTests.swift:42` 的 `draws.filter { $0.missingGlyph }` **不按 `canvasID` 过滤**（钩子文档明说要过滤）。如果同一时刻有别的线程在 `withDraws` 之外画出带缺字符的像素字，会被它收进来误报红。我查了所有像素字调用点（数字 / `+N` / `a/b` / `z` / mcp 首字母），生产路径画不出缺字符；测试里画「日」的地方都在 `withDraws` 里（被 `renderLock` 挡开）。没有自然来源，只是一个没有设防的口子。
2. `TextCacheBoundTests` 的 `lastAgain === last`：理论上别的线程在这两次调用之间的微秒里插入 ≥ 600 条不同的文字才会红；线程恰好被抢占几十毫秒、同时有别的线程在狂渲染不同文字才做得到。stg 3 遍 + 整套 12 遍没见到。
3. `AppModel.isUserLooking`（`AppModel.swift:277-283`）在前台 App 恰好是真的 Claude.app 时会走 `DesktopMeta.cache` 去读**真实**的 `~/Library/Application Support/Claude/claude-code-sessions`；如果哪个测试用真的 `isUserLooking` 跑桌面会话的提醒，结果会取决于用户此刻在用什么 App。我没找到这样的测试（`AlertCoordinatorTests` 全用 `nobodyLooks`）。
4. `noFileDescriptorLeaksAcrossReaders`（`FuzzSecurityTests.swift:200-202`）比较的是**整个进程**的 fd 数，容差 150：只有当别的并行测试在那 0.3 s 里同时多持有 150 个 fd 才会红；我的采样里最大涨幅 11。
5. `UserDefaults.standard` 的测试宿主域（`swiftpm-testing-helper`）是**跨进程**共享的：同时有两个 `swift test` 进程（现在 QA 就是这么做的）时，`NSWindow Frame BuddyOfficeTankPanel` 等键会互相看到（`TankPanelController.swift:28` 的 `hadSavedFrame` 影响面板放哪）。整套里没见到失败，`defaults read swiftpm-testing-helper` 现在是空的。
6. 忙机器上限偏紧但没红过的阈值：`HousekeepingTests.swift:17`（超时 0.2 s，断言 `< 0.6`）、`FuzzReadersTests.swift:24`（收敛等 0.8 s）、`RobustnessTests.swift:86` / `FuzzEngineTests.swift:231`（1.5 s 的写者窗口）、`StoreTests.swift:122`（`d < 5`）、`StoreTests.swift:176-179`（FSEvents 每次最多等 2 s、`lats.count == 12`）；我在 load 240 的整套里它们都过了，只是余量比账本那族小得多。
7. 每遍完整整套的墙钟 92–254 s（按 load 变化），R3 加的 `TextAudit` 相关测试单条最长 ≈ 33 s；`Test "…" passed after 120 seconds` 这类超大耗时是「排队等协作线程池」的时间（大量 `Thread.sleep` / 信号量的同步测试占着池子），不是测试本身慢。

## 4. 表现层对抗式检查

- **`buddyctl golden`**：17 / 17 一致（`logs/golden.log`）。
- **`buddyctl verify`（局部重绘 vs 整张重画，逐像素）**：跑的是**回归脚本里没跑过的配置**（带悬停）：
  - office：时钟 03:10 / 23:59 / 05:55 × 模式 crowd12 / busy6 / demo × 视口 120×120 / 224×226 / 500×420 × 25 s：**20 250 对帧全部一致**；
  - tank：12:00 / 21:30 × busy6 / demo × 2 种视口：**6 000 对**一致；strip：12:00 / 21:30 × busy6 / crowd12 × 2 种视口：**6 000 对**一致。
- **`buddyctl flicker`**：tank / strip 在 busy6 × 06:50 干净；office 的 busy6 / crowd12 有 P3-1。
- **`PixelFont` 审计钩子的锁**：`draw` 先在 `auditLock` 里读开关（读完释放），审计打开时再取一次 sink（读完释放），**sink 在锁外调用**；`setAuditSink` 只拿 `auditLock`；`withDraws` 拿 `renderLock` → `setAuditSink`；`SeatRenderer.screenSignature` 拿 `scratchLock` → `ScreenContent.draw` → `auditLock`；`OfficeScene.inkExtent` 拿 `inkExtentLock` → `TextRenderer.lock`；sink 里只拿 `Box` 自己的锁。所有嵌套的方向一致（`renderLock → scratchLock → auditLock`、`inkExtentLock → TextRenderer.lock`），没有反向，也没有可重入（`withDraws` 里没有再进 `withDraws` 的路径：`renderFrame` / `scene.render` 都不调它）。多线程同时 `draw`：无争用一把 NSLock 约 20 ns，生产里只有主线程画（每帧几十次）；测试里 4 个空转线程 + 4000 次收集（SAN-01）单独 0.12 s，没有饥饿。
- **`VisualDirector` / `Performer` / `PlateCopy` / `PixelView` 读代码**：气泡 0.8 s 最短停留（`Performer.swift:288-296`）、`digitMask`（`:308-337`）、`privacyToggled`（`:273-278`）、`OfficeScene.PlateKey` 里带 `privacy`（`:458`）、`HoverPanelController.CardKey` 里带 `privacy`（`Panels.swift:33-38`）、隐私切换后桌牌 / 卡片按 key 重建——没发现越界 / 溢出 / 卡住 / 隐私漏细节（`PixelView` 的 surface 分桶 + `contentsRect` 的真实合成器读回 R3c 做过，我没重复）。
- **没做**：ASan / TSan、真实 GUI、隐私切换的端到端运行时探针（只读了代码；已有的 R3b-02 泄漏扫描只覆盖「一开始就是隐私模式」）。

## 统计

| 严重度 | 新增 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 1（R4b-01 账本 `.background` 队列饿死 → 一族测试间歇性红灯） |
| P3 | 5 |

## 复现命令

```
# 拷贝、编译测试（Testing 框架的参数见 scripts/dev.sh；swift build --build-tests 要带同样的 -Xswiftc / -Xlinker 参数）
rsync -a --exclude='.build*' --exclude=dist --exclude='QA/evidence' ~/Desktop/编程项目/Buddy办公室/ $SCRATCH/r4b/
# 整套默认并行（一遍）
BUDDY_SCRATCH=.build-r4b scripts/dev.sh test --skip-build
# R4b-01 最小复现：单条 + 8 个 CPU 空转进程（各自 100 s 后自己退出）
for i in 1 2 3 4 5 6 7 8; do (perl -e 'alarm 100; while(1){}' &) ; done
"$SWIFTPM_TESTING_HELPER" --test-bundle-path "$XCTEST" --filter theDefaultScanQueueRunsAtBackgroundQoS "$XCTEST" --testing-library swift-testing
# flicker 覆盖缺口
.build-r4b/debug/buddyctl flicker --scene office --zoom 3 --mode busy6 --from 0 --to 3 --dump DIR
```
