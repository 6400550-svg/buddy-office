# R5b 终审复查（套件稳定性确认 + 表现层清扫）

复查员 R5b（全新视角），2026-09-29 14:23–14:43。**没有改项目源码 / 测试**：拷贝在
`/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/r5b/`（`.build-r5b`），日志在它的 `logs/`（下文写作 `logs/…`），只往主目录写了这份报告。
没有碰 `~/.claude`、`.key`、`.sock`、运行中的 App、ccmon / 用量表；没有联网。
**提前收尾**：14:42 主线程要求马上停止制造负载、腾出机器跑最后一次完整回归，我按要求杀掉了自己的连跑脚本和 8 个空转进程（只杀了自己命令行里带 `alarm 400` / `.build-r5b` 的，事后核对没有残留）——所以**「有 8 个空转进程的整套连跑」这一项没有完成**（见下面的「没覆盖到」）。

## 结论

**新发现：P0 0 条 / P1 0 条 / P2 1 条 / P3 1 条。**

- **P2（R5b-01，测试基础设施）**：`FuzzSecurityTests.noFileDescriptorLeaksAcrossReaders` 会间歇性变红，**单独一条测试跑也红**（不是别的测试并行抢的）：它靠「`Thread.sleep(0.3)` 之后进程的文件描述符数比开始时多出不超过 150」来判定没有泄漏，而它自己启动 / 停止的 40 个 `FSEventStream` 的句柄是 FSEvents 异步释放的，机器一忙就来不及。R4b 把它记成「疑点 4（怀疑是别的并行测试多持有 fd）」，这次找到了真正的来源并有可复现的证据（见下）。
- R4b-01（账本 `.background` 队列被饿死那一族）：**这一轮没有再红过**——但因为有 8 个空转进程的整套连跑被叫停，没能在「同样的压力」下复测，见「没覆盖到」。无负载 / 中等负载（机器上另有 30–190 的负载，见下表）下整套 8 遍全绿。
- 表现层：`text-audit` 全矩阵 8598 个组合 0 违规；`verify`（局部重绘 vs 整张重画，换了一套没跑过的时钟 / 视口 / 模式，带悬停）25 800 对帧全部一致；`golden` 17 / 17 一致；`flicker` 7 个没跑过的配置全干净；没有找到新的 P0–P2（含 ToastCard 隐私）。

## 1. 套件稳定性：跑了什么、结果

机器一直有别人的负载（另一位复查员 / 主线程在编译、跑测试；整个时段 load average 在 6–198 之间，6 核），所以下表里「无人为负载」= 我没有开空转进程，**不是空闲机器**，每一行都写了当时的 load。

### 1.1 默认并行整套（`swift test --skip-build`，797 个测试 / 91 个套件）

| 栏 | 遍数 | 结果 | 明细（`logs/summary-nol.txt`） |
|---|---|---|---|
| **无人为负载** | **8 遍** | **8 / 8 全绿** | nol-1 76 s（load 12→24）、nol-2 101 s（24→34）、nol-3 175 s（34→34，此时我自己同时开着 4 组过滤连跑，load 35）、nol-4 136 s（34→17）、nol-5 66 s（17→14）、nol-6 95 s（14→12）、nol-7 65 s（12→11）、nol-8 66 s（11→11） |
| **有负载（8 个 `perl -e 'alarm N; while(1){}'` 空转）** | **0 遍完成** | — | ld-1 开跑后（14:40）机器 load 冲到 190，14:42 我按主线程要求杀掉（那时日志里 0 个失败，但没跑完，不作数） |

### 1.2 `--filter` 连跑（直接跑测试可执行文件，`logs/filterloop.sh`）

| 组 | 覆盖的全局状态 | 过滤的套件 | 遍数 | 结果 |
|---|---|---|---|---|
| dm | `DesktopMeta.baseOverride` | `DesktopMetaFileIOTests EngineConfigTests ReviewRegressionAppTests AppModelTests JumpTests SettingsTests CachesTests`（52 个测试 / 8 个套件） | **40** | 40 / 40 全绿 |
| fio | `FileIO.openObserver / forbiddenHits` | `FileAccessTests FuzzSecurityTests FuzzRegressionTests OpenAuditTests RegistryTests`（63 个测试 / 5 个套件，每遍约 6 s） | **40** | **39 绿 / 1 红**（第 1 遍，就是 R5b-01） |
| stg | `TextRenderer.shared` / `PixelFont` 审计钩子 | `TextCacheBoundTests ScreenContentTests ReviewRegressionStageTests AppLayerFixTests PlateCopyTests`（46 个测试 / 5 个套件） | **40** | 40 / 40 全绿 |
| ui | `UserDefaults.standard` / 面板 / 固定键 | `SpecTraceUITests ReviewRegressionAppTests PanelAnimationTests SettingsTests PanelShowTests AppModelTests StripPlacementTests ScreenPickerTests TickPacerTests`（115 个测试 / 21 个套件） | **35** | 35 / 35 全绿 |
| eng | 引擎 / 账本队列 / FSEvents / 固定临时目录 | `EnginePresenceTests EngineScenarioTests StateRuleTests HookLogTests ReviewRegressionTests StoreTests StateRuleChainTests`（144 个测试 / 9 个套件，每遍 22–33 s；R4b-01 那族测试全在里面） | **10** | 10 / 10 全绿（load 12–46） |
| fdalone | 只跑 `noFileDescriptorLeaksAcrossReaders` 这一条 | 同名单条 | 25（load 32–57）+ 40（load 14–24） | **25 遍里 1 红**（load 57）；40 遍 0 红（load 14–24） |

这几组是同时开着跑的（dm / fio / stg / ui 一起，加上 nol-2…4），所以中间有一段整机 load 在 35–65：**这就是这几组的「有负载」**，但不是规定的 8 个空转进程，只算参考。`TextAudit` 矩阵和 SAN-01 / `TextCacheBoundTests` 同时跑的组合（R4b 的 stg 组）没有单独连跑，它们在 8 遍整套里是同时跑的（8 / 8 全绿）。

### 1.3 表现层命令

| 命令 | 结果 |
|---|---|
| `buddyctl text-audit --max 0` | 8598 个组合、103 668 段文字、17 974 串像素字（82.7 s）：8 类全部 **0 违规**；悬停卡片没画出来的 0（`logs/text-audit.log`） |
| `buddyctl verify --hover`（没跑过的配置） | office：时钟 00:30 / 17:20 / 11:11 × 模式 demo / crowd12 / idle6 × 视口 96×90 / 300×150 / 640×700 × 20 s：**16 200 对帧全部一致**；tank：04:44 / 20:05 × demo / crowd12 × 96×90 / 500×300：**4 800 对**；strip：04:44 / 20:05 × busy6 / idle6 × 96×90 / 500×300：**4 800 对**，全部一致 |
| `buddyctl golden` | 17 / 17 一致 |
| `buddyctl flicker`（没跑过的配置） | office 4× 00:10 / 2× 17:45 / 5× 05:59，tank 5× 21:00 / 3× busy6 12:34，strip 4× 09:15 / 2× crowd12 23:30（1201–1801 帧 / 组）：**7 组全部干净**（每组另有 8–19 处 ≤ 6 个孤立像素、已被容忍的抖动） |

## 2. 新发现

### R5b-01 【P2 测试基础设施】`noFileDescriptorLeaksAcrossReaders` 靠「睡 0.3 秒后 fd 数涨幅 ≤ 150」判断泄漏，而 FSEvents 的 fd 是异步释放的，机器一忙就间歇性变红（单独跑这一条也红）

- **位置**：`Tests/BuddyCoreTests/FuzzSecurityTests.swift:152-203`（关键行：`:191-194` 反复起停 40 个 `FileWatcher`、`:199` `Thread.sleep(0.3)`、`:202` `#expect(after - before <= 150)`）；计数函数 `:369-373`（扫 fd 0..<4096 里 `fcntl(F_GETFD)` 有效的个数，整个进程）。
- **证据 1（整个 fio 组合里 40 遍红 1 遍）**：`logs/fio-FAIL-1.log`
  ```
  ✘ Test "句柄泄漏：…" recorded an issue at FuzzSecurityTests.swift:202:9: Expectation failed: (after - before → 438) <= 150
  ↳ 文件描述符从 4 涨到了 442
  ```
- **证据 2（这一条单独跑，也红）**：`filterloop.sh fdalone 25 noFileDescriptorLeaksAcrossReaders`（load 32–57）第 23 遍红（`logs/fdalone-FAIL-23.log`）：`↳ 文件描述符从 3 涨到了 185`（超过 150），进程里除了这一条测试什么都没有——所以不是别的并行测试多持有了 fd（R4b 疑点 4 的猜测），是它自己的 `FileWatcher` 起停。
- **根因（最小复现，不依赖项目代码）**：`logs/../probe/fsfd.swift`（一个独立的 Swift 文件：和 `FileWatcher.start/stop` 一样的 `FSEventStreamCreate / SetDispatchQueue / Start / Stop / Invalidate / Release`，循环 40 次，然后数 fd）。6 遍输出：
  ```
  before=3 peak=362 immediately=115 @0.3s=0 @1.0s=0
  before=3 peak=382 immediately=367 @0.3s=0
  before=3 peak=366 immediately=336 @0.3s=0
  before=3 peak=443 immediately=440 @0.3s=381 @1.0s=0     ← 0.3 秒后还有 381 个没放掉
  before=3 peak=146 immediately=65  @0.3s=0
  before=3 peak=290 immediately=287 @0.3s=0
  ```
  即 `Stop / Invalidate / Release` 返回时每个 stream 还占约 10 个 fd（40 个共 ≈ 440，正好是失败信息里的 438 / 442），由 FSEvents 在后台异步关掉；平时几十毫秒内放完，机器忙（load 57 时 1/25，load 14–24 时 0/40 + 0/40）时 0.3 秒不够，而容忍度 150 又比 40 个 stream 的瞬时占用（约 440）小得多。不是泄漏（1 秒后回到 0），是这条断言的等待窗口写得太紧。
- **频率**：fio 组 1 / 40；单条 1 / 25（load 32–57）、0 / 40（load 14–24）；默认并行整套 8 遍（load 6–35）没红——它在整套里也会红，只是在我这几遍的负载下没撞上。
- **为什么算 P2**：报告里「797 个测试全过」在忙机器上会间歇性变成 796；红的位置写着「文件描述符从 4 涨到了 442」，看起来像句柄泄漏（正好是这个项目最在意的那一类问题），会误导排查。它只会误报红，不会误报绿。
- **建议（没改）**：把 `Thread.sleep(0.3)` 换成轮询等待——`after` 回落到 `before + 一个小容差` 或最多等 ~10 秒再断言；或者把容忍度放到 ≥ 40 × 12 + 150。断言的意图（几千次读取器循环不泄漏）用「等 fd 数稳定后」判断才准。

## P3（一句话）

1. **R5b-P3-01**：`SpecTraceUITests`（Office）`theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms`（`:277-285`）里 `onHover?(p)` 和取 `t0` 是相邻两句，测试线程恰好在这两句之间被挂起 ≥ 250 ms 时，`CACurrentMediaTime() - t0 < 0.2` 的保护会失效而误报「还没有卡片」失败；窗口极窄（没见到失败），修法：在 `onHover` 之前取 `t0`。

## 3. 超时 / 时间阈值 / 后台队列普查表

「8 个空转下会不会红」一栏：**红 = 有失败证据；未复测 = 8 个空转的整套连跑被叫停，只能给静态判断（没有证据，不算问题）**；「没红」= 在我这几遍 load 30–65 的并行 / 过滤连跑里没红过。

| 位置 | 阈值 | 等的是什么 | 8 个空转下 |
|---|---|---|---|
| `FuzzSecurityTests.swift:199-202` | 睡 0.3 s、fd 涨幅 ≤ 150 | 40 个 FSEventStream 的 fd 被异步释放 | **红（R5b-01）**：load 57 时单条 1 / 25；探针里 0.3 s 后还剩 381 |
| `SpecTraceCoreTests.swift:393`（4.3-42） | `sem.wait(90)` | `.background` 默认队列上的账本扫描回调；没等到就不断言（R4 已改成同步读队列 QoS） | 不会红，最坏多占 90 s |
| 所有 `waitUntilIdle(timeout: 60)`（约 45 处：`FuzzPersistenceTests` / `FuzzRegressionTests` / `EnginePresenceTests` / `StateRuleTests` / `StateRuleChainTests` / `TokenLedgerTests` / `SpecTraceCoreTests` / `FuzzSecurityTests:187`） | 60 s | 账本扫描；R4 起全部传 `.userInitiated` 队列（`Support.swift:93` `testLedgerQueue()`）或无 QoS 的标签队列（`SpecTraceCoreTests:267/296`、`TokenLedgerTests:11`） | 未复测（整套 8 遍 + eng 10 遍没红）；队列已不是 `.background`，R4b-01 的根因在测试侧已去掉 |
| `FuzzSupport.swift:79-95` `fuzzRun`（线程 userInitiated，超时 10 / 15 / 20 / 30 / 60 / 90 / 120 / 180 / 240 s，共约 60 处） | 各自超时，`C-028` 已放宽到 90 s | 纯 CPU 的模糊测试体 | 未复测；体本身几毫秒到几秒，余量 ≥ 10× |
| `StoreTests.swift:16-19` `rec.wait(timeout: 8)`（18 处） | 8 s | `SessionStore` 的 `.utility` 队列 + 回调队列把快照送出来 | 未复测；整套 8 遍 / eng 10 遍没红 |
| `StoreTests.swift:79-96` | 1 s 里每 3 ms 一条 hook；`i > 100`、3 ≤ `n` ≤ 28 | 主线程自己的节奏 + `.utility` 队列限速回调 | 未复测；`i > 100` 要求平均每轮 < 10 ms，机器极忙时最先紧（**疑点**） |
| `StoreTests.swift:98-107` | 睡 2.5 s、`1 ≤ n ≤ 6` | 心跳回调（`.utility` 队列 `asyncAfter`） | 未复测；`n ≥ 1` 要求队列在 2.5 s 里至少被调度一次 |
| `StoreTests.swift:109-123` | `wait(8)`、`d < 5` | 打断 → 空闲的精确唤醒 | 未复测 |
| `StoreTests.swift:169-181` | 每次等 2 s、12 次都要到 | FSEvents 延迟 | 没红（eng 10 遍 + 整套 8 遍） |
| `TokenLedgerTests.swift:197` | 扫 44 MB `secs < 2.0`（墙钟） | 账本在 `test.tokenscan` 队列上扫大文件 | 未复测；空闲时约几百毫秒，余量约 4–6×（**疑点**，没量实际耗时） |
| `HousekeepingTests.swift:14-16` | 超时 0.2 s、`waited < 0.6` | 测试线程醒来的及时性 | 未复测；余量 3×（**疑点**） |
| `HousekeepingTests.swift:23` | `BoundedWait.run(timeout: 2)` | GCD 全局队列在 2 s 内把 `n += 1` 跑掉 | 没红 |
| `FuzzReadersTests.swift:24-28` | 收敛最多等 0.8 s（每 20 ms 扫一次） | 同步扫描 + 50 ms 重试的墙钟 | 没红（fio / 整套） |
| `RobustnessTests.swift:86` / `FuzzEngineTests.swift:231-252` | 1.5 s 写者窗口 / stop 20 s / 收线程 20 s | 写者线程被调度 | 没红 |
| `FuzzWatcherTests.swift:34 / 52` | 5 s / 8 s | FSEvents 送达 | 没红 |
| `OpenAuditTests.swift:105-116` | 等噪声线程 open 过一次（最多 10 s）、审计窗口各 0.3 s | 噪声线程被调度（R4 已改成先等） | 没红（fio 40 遍） |
| `FuzzSecurityTests.swift:356-358` | 600 s | 4 个写者线程 | 不会红 |
| `SpecTraceUITests.swift:277-285`（Office） | 250 ms 悬停 / 0.35 s 睡 | 真时钟；「还没有」那半已被 `< 0.2` 保护 | 没红（ui 35 遍）；见 P3 |
| `SpecTraceCoreTests.swift:375` | 睡 0.3 s 后断言「没有写盘」 | 反向断言 | 不会红 |
| `ReviewRegressionStageTests.swift:276-297`（SAN-01） | 4 个 `sched_yield` 线程 × 4000 次收集 | `renderLock` | 没红（stg 40 遍 + 整套 8 遍）；不再空转 |

## 没覆盖到（如实交代）

- **规定的「≥ 4 遍、8 个空转进程」整套连跑一遍都没完成**：14:40 开始的第 1 遍在机器 load 冲到 190 时被主线程要求停止（我把脚本和 8 个空转进程都杀了）。所以 R4b-01 那一族「在同样压力下不再红」我**只有间接证据**：账本队列改成 `.userInitiated` 之后，整套 8 遍（load 6–35，含我自己 4 组并行连跑时的 load 35）+ eng 组 10 遍 + fio 40 遍全部没有一条属于那一族的失败；没有得到「8 个空转」这个具体压力下的结果，也没有对 `StoreTests` 的 `.utility` 队列那几条（表里「未复测」）在重压下下结论。
- 「30–40 遍」的过滤连跑覆盖了 `DesktopMeta` / `FileIO` 观察口 / `TextRenderer` + 像素字钩子 / `UserDefaults` 面板测试；没有把 `TextAudit` 矩阵和 `TextCacheBoundTests` / SAN-01 同时开着连跑多遍（只在 8 遍整套里同时跑过）。
- 阈值表里标「疑点」的两条（`TokenLedgerTests:197` 的 2.0 s、`StoreTests:79-96` 的 `i > 100`）没有量实际耗时。
- 表现层只读了 `ToastCard` / `AlertCoordinator` / `ToastController` / `HoverCard` / `PlateCopy` / `VisualDirector` / `PixelView`，没重读 `Performer` / `OfficeScene` 全文（R3b 用随机序列不变量 / 变异做过，源码自 R4b 起没有改动）；隐私检查是读代码，没有新写运行时探针。
- ToastCard 隐私（读代码结论）：`ToastCard.make` 只画调用者传来的 `title / body`；`AlertCoordinator` 里隐私模式下标题恒为「会话」（`AlertText.title`，`:23`）、批准提示恒为「有个权限请求（等你批准）」（`text(for:)`，`:250-254`）、其余正文都是固定文案（做完了 + 用时 / 需要你处理 / 出错了 / 「N 位同事…」，合并卡标题固定「Buddy 办公室」）；系统通知的 `userInfo` 只带内部 key（不显示）。没有发现带会话标题、路径、工具详情的路径。

## 统计

| 严重度 | 新增 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 1（R5b-01 `noFileDescriptorLeaksAcrossReaders` 的 0.3 s 窗口 / FSEvents 异步释放 fd） |
| P3 | 1 |

## 复现命令

```
# 拷贝、编译测试（参数同 scripts/dev.sh；swift build --build-tests 要带同样的 -Xswiftc / -Xlinker）
rsync -a --exclude='.build*' --exclude=dist --exclude='QA/evidence' ~/Desktop/编程项目/Buddy办公室/ $SCRATCH/r5b/
# R5b-01：单条连跑（load 高时会红；1 / 25）
HELPER=/Library/Developer/CommandLineTools/usr/libexec/swift/pm/swiftpm-testing-helper
XCTEST=.build-r5b/debug/BuddyOfficePackageTests.xctest/Contents/MacOS/BuddyOfficePackageTests
DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  "$HELPER" --test-bundle-path "$XCTEST" --filter noFileDescriptorLeaksAcrossReaders "$XCTEST" --testing-library swift-testing
# 根因探针（独立于项目代码）
swiftc -O $SCRATCH/r5b/probe/fsfd.swift -o fsfd && for i in 1 2 3 4 5 6; do ./fsfd; done
```
