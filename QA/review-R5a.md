# R5a 终审复查（按「同一类问题」清扫；全新视角）

2026-09-29 14:13–14:27（墙钟约 14 分钟，时间盒 35 分钟内）。范围：`Sources/BuddyOffice/**`（重点）、`Sources/BuddyCore/**` 里对外部时间 / 数字的使用、`scripts/hook-merge.py`。
所有编译 / 测试 / 探针都在拷贝 `…/scratchpad/r5a/`（`BUDDY_SCRATCH=.build-r5a`）里做，探针文件在拷贝里：`Tests/BuddyOfficeTests/R5aProbeTests.swift`、`R5aSimTests.swift`。
主目录除本报告外没有改动。没有碰 `~/.claude`、`.key`、`.sock`、ccmon、用量表、Claude.app、运行中的 App；没有起开发副本（所以没有偏好域要清理、没有进程要杀）；没有联网。
读过用户真实的桌面会话元数据目录里 43 个 `local_*.json` 的 `lastFocusedAt` **数字字段**（只看类型和范围，没有读标题 / 内容），用来判断某个坏值是否可达。

## 结论

**新发现：P0 0 条 / P1 0 条 / P2 1 条 / P3 6 条。**
按验收条款 ⑤（最后一轮不许再出新的 P0–P2），这一轮**没有过关**：有 1 条 P2（出错提醒漏掉了其他提醒都有的两道闸），有确定性复现。修法很小（在 `.errored` 分支补两个条件）。
四个类别里：类别 3（提醒状态机）用「闸门对照表 + 新维度随机模拟」找到了这条 P2 和一条 P3；类别 1 / 2 / 4 没有找到 P2（详见「检查过什么」），各有几条 P3 / 疑点。

## P2

### R5a-01 [P2] 「出错」提醒漏了另外两道闸：`notify.includeDesktop` 关着时桌面会话出错照样弹；你正在看那个会话时出错照样弹

- **位置**：`Sources/BuddyOffice/AlertCoordinator.swift:160`（`if case .errored = cur, was != cur, config.error, throttle(...)`）。
  对照：等待类 `:178-181`（`desktopOK`、`isLooking` 两道闸都有）、做完了 `:154`（`includeDesktop`）和 `:200`（`isLooking`）。出错分支只有 `config.error` + 节流两个条件。
- **为什么是这一类**：和 R3a-02 → R4a-01 同一个模式——「同一条规则在几个入口里各写了一遍，有一个漏了」。三种提醒（等待 / 做完了 / 出错）各自实现「只发给桌面会话要开开关」「你在看就不发」，出错这条两个都没实现。
- **用户看得到的承诺**：`使用说明.txt:119`「Claude 桌面 App 自己也可能发系统通知，可能和这里的提醒重复；不想重复就在「设置 → 提醒」里关掉「桌面 App 里的会话也提醒」」；设置页文案（`SettingsView.swift:85`）；`使用说明.txt:88`「你正在看那个会话时不提醒」；任务书 7.2「不打扰」「重复提醒」。用户打开「出错时也提醒」、关掉「桌面 App 里的会话也提醒」之后，桌面会话出错仍然会弹提示卡 / 系统通知 / 响提示音——正是用户想避免的那种和 Claude.app 自己通知重复的情况。
- **证据 1（确定性最小复现，探针 `R5aErrorGateTests`，`scripts/dev.sh test --filter R5aErrorGate`）**：`AlertConfig` 里 `error = true`，其余默认；喂一个 `.thinking` 再喂 `.errored`：
  ```
  R5A ERRGATE desktop, includeDesktop=false: posts=["error 出错了"]                       ← 应该没有
  R5A ERRGATE control (waiting, same conditions) posts=0                                   ← 同条件下「等批准」是 0 条
  R5A ERRGATE terminal, user is looking, suppressWhenFocused=true: posts=["error 出错了"]  ← isLooking 恒真，仍然弹
  R5A ERRGATE control (waiting, same conditions) posts=0
  R5A ERRGATE desktop, user is looking, suppressWhenFocused=true: posts=["error 出错了"]
  R5A ERRGATE control (waiting, same conditions) posts=0
  ```
- **证据 2（随机模拟，`R5aSimTests.settingsHidePrivacyChurn`，250 个种子 × 3000 步，2–5 个会话 terminal / desktop 混合，每步 2% 概率切换一项设置、隐藏 / 取消隐藏、隐私模式）**：`24 484` 条提醒里 `desktop post while includeDesktop off (kind error): 401`，例：`seed 2 t=495.9 body=出错了`。
- **现有测试为什么没抓到**：`AlertCoordinatorTests.desktopSessionsAreSkippedWhenIncludeDesktopIsOff`（:340）只覆盖等待类和做完了；`errorAlertsAreOffByDefaultAndThrottledWhenOn`（:352）只用终端会话、`isLooking` 恒假。
- **为什么算 P2**：设置页的开关在一个组合下不生效（出错默认关，所以要用户主动打开出错提醒才触发；不是 P1）；边界组合 + 确定性复现。「你在看就不发」这一半可以说是出错更该提醒——建议按使用说明写的来（所有提醒统一），或者把使用说明改成「出错提醒不受这一条限制」。
- **建议修法**（没改）：`.errored` 分支加 `(s.origin != .desktop || config.includeDesktop)`；`config.suppressWhenFocused, isLooking(s)` 时不发（出错是一次性事件，不需要像等待类那样先等 8 秒）；补两条测试（桌面 + `includeDesktop=false`、`isLooking` 恒真各一条）。

## P3（一句话）

1. **R5a-02 [P3]** 排队等待中的「做完了」（桌面会话等 8 秒看总结 / 终端会话宿主在最前时推迟 8 秒）在这段窗口里不再读设置：用户在这 8 秒里把「做完了」提醒关掉、把「桌面 App 里的会话也提醒」关掉、或把最短用时调高，这一条照发（`AlertCoordinator.swift:154` 只在转换那一拍判断 `config.finished / finishedMinSeconds / includeDesktop`，`:157` `handleFinished` 不再检查）。探针 `R5aProbeTests.pendingFinishedIgnoresSettingsTurnedOffMeanwhile`：三种关法都仍然发出 `("d:x", 标题, "做完了（用时 45秒）")`；对照：隐私模式在这 8 秒里打开是生效的（标题变成「会话」）。随机模拟里 `finished post while notify.finished off: 7`、`desktop post while includeDesktop off (kind finished): 4`。
2. **R5a-03 [P3]** 桌面元数据 `lastFocusedAt` 的两份读取器对「坏值」的取舍仍不完全一致（R4a-01 只补了未来这一侧）：应用层 `DesktopMeta.lastFocused`（`JumpService.swift:154-160`）接受 `true`→1、`false`→0、`0`、`-5`、`1000`（1970 年）、`915148800000`（1999 年）；引擎侧 `TimeUtil.date(fromJSONMillis:)` 全部当 nil（布尔和 2000–2200 之外）。探针 `R5aTwoReadersTests`：`true app=1 engine=nil`、`zero app=0 engine=nil`、`negative app=-5 engine=nil`、`year-1999 app=915148800000 engine=nil`；未来 / 字符串 / null / `1e400` 两边一致。**不可达**：用户真实的 43 个文件 `lastFocusedAt` 全部是 ≥ 2000 年的数字。建议 `lastFocused` 直接复用 `TimeUtil.date(fromJSONMillis:)`（一行）。
3. **R5a-04 [P3]** `hook-merge.py` 遇到嵌套很深的 JSON（20 万层）时 `json.loads` 抛 `RecursionError`，不在 `except (UnicodeDecodeError, ValueError)` 里，`install` / `uninstall` / `status` 都是栈追踪 + 退出码 1，而不是友好的「拒绝…什么都没改」+ 退出码 2（`scripts/hook-merge.py:44-47`）。实测：`install` / `uninstall` 退出码 1，文件没动、没有留备份（`load` 在 `backup` 之前）。Swift 侧 `SafeJSON` 对同样的数据是「深度 > 100 当坏数据」。同族的 `1e400`、孤立代理项（R3a P3）已知。真实 settings.json 不会这样。
4. **R5a-05 [P3]** 隐私模式在提示卡 / 系统通知已经带着真标题显示的时候打开：已经出现的提示卡（≤ 6 秒）和通知中心里已送达的通知不会被撤或改写（`AppModel` 的设置变化路径只 `refreshDerived / wake / scheduleApply`，没有碰 `notifier`）。新发的提醒是对的（R4a 模拟 ⑩ 与本轮模拟都是 0 泄漏）。
5. **R5a-06 [P3]** 合并卡「N 位同事在等你」的 N 还会把「刚被隐藏 / 已经离场」但仍在 2 秒 `recent` 窗口里的会话算进去（`AlertCoordinator.swift:221`）；模拟里 1 例 `N=5 alertable=4`。是 R4a-02 的子情形（那条的修法「`recent` ∩ 现在还在等」同时能解决）。
6. **R5a-07 [P3]** `strip.align` 遇到认不出的取值（手改偏好设置）时，位置按「靠右」（`StripPanelController.swift:114-119` 的 `default`），而场景的 `alignRight` 只认字面量 `"right"`（`:170`），二者不一致；设置页只会写 left / center / right，不可达。

## 疑点（没有证据，不算问题）

- **`TankPanelController.placed` 是一次性的**（`TankPanelController.swift:22-23 / :90-96`）：「存过的位置已经不在任何屏幕上就放回右上角」只在第一次出画面时判断一次。小鱼缸在外接屏上显示过 → 收起 → 拔掉外接屏 → 再打开：`orderFront` 的可能仍是旧位置（我推测无边框面板不会被 AppKit 自动挪回，没有验证）。宠物条每 0.5 秒 `repositionIfNeeded` 不受影响。本机单屏，造不出。修法：`show(model:)` 里每次都做一遍可见性检查。
- **`DockTileController.lastCount` 缓存**（`SystemHelpers.swift:20-27`）：只在人数变化时才写 `dockTile.badgeLabel`。如果 Dock 图标开关（`.regular` ↔ `.accessory`）把系统那边的角标弄丢了，而等你的人数没变，角标不会重新出现。`NSApp.dockTile.badgeLabel` 读回来永远是自己写的值，没法在这里验证系统那边的真实显示。
- **`SoundSynth` 缓存 `AVAudioPlayer`**（`SoundSynth.swift:41-58`）：`play()` 的返回值没看；默认输出设备变了（耳机 / 蓝牙 / HDMI）之后缓存的播放器是否还能出声，我没法在这里验证。
- **「你在看」只看最前面的 App**：显示器休眠但没锁屏、或人走开而终端仍是最前面 App 时，一整段等待会被当成「你一直在看」而永远不提醒（`ep.alerted = true`，`AlertCoordinator.swift:181-183`）。任务书 7.2 就是这么写的（不违规）；锁屏 / 屏保时最前面的 App 会变成 loginwindow / ScreenSaverEngine（我记得是这样，没有验证），所以只剩「只关显示器」这一种。没有任何空闲检测（`CGEventSource.secondsSinceLastEventType`）或锁屏 / 休眠通知（grep 过：整个 Sources 里没有）。
- **`AutoQuit` 只在「Claude 退出」那一刻起一个 60 秒计时，到点判断一次**（`SystemHelpers.swift:65-83`）：那时还有终端会话就不退，之后终端会话都结束了也不会再判断。任务书 7.4 就是这么写的；只是「跟着 Claude 收」对纯终端用户永远不会收。
- 没有任何 `beginActivity` / App Nap 处理（grep 过）。R3c 在开发副本上测了 4 分钟没有看到定时器被拉长，我没有重复。

## 检查过什么（覆盖清单）

### 类别 1：同一份外部数据的两个读取器，坏值处理是否一致

- **方法**：`grep` 全部 `JSONSerialization / SafeJSON / FileIO.readAll / as? Double / as? NSNumber / .intValue / Int(` 的用点（Sources 全部，含 BuddyOffice / BuddyStage / BuddyCore），逐个确认读的是哪份数据、谁是第二份读取器。
- **桌面元数据**：应用层 `DesktopMeta.readAll / lastFocused / Cache / mostRecentHost` vs 引擎 `DesktopMetaReader.parse / clampingFuture / refresh`。逐字段对照（布尔、0、负数、1970、1999、未来 30 天、字符串、null、`1e400`），跑了探针 → R5a-03（只有不可达的低值一侧还不一致）。另外对照了 key 口径（应用层按文件名、引擎按文件里的 `sessionId`、副本文件 `local_x copy.json`）：副本在应用层是另一个 host，但副本的 `lastFocusedAt` 只会比原件旧，`mostRecentHost` 的并列取值也偏向原件，推演下没有可见错误。
- **登记表 / hook / 会话记录 / identities / ledger**：只有一个读取器（`RegistryScanner` / `HookLogReader`+`LineSanitizer` / `TranscriptReader`+`TranscriptLine` / `IdentityResolver.load` / `TokenLedger.loadPersisted`）；比较了 `TranscriptLine.intValue`（2^40）与 `TokenLedger.restoredCount`（2^50）、`SubagentReader` 的 `spawnDepth`、`DesktopMetaReader.completedTurns`（`NSNumber.intValue` 是 ObjC 饱和转换，不 trap）、`IdentityResolver` 的 `salt / seat`、`RegistryScanner` 的 `pid`——都有范围或饱和，没有找到漏网的。外部时间戳：逐个看了 `TimeUtil.date(fromJSONMillis:/saneMs:)` 的所有调用点与 `ActivityResolver` / `SessionEngine` 里对 `statusUpdatedAt` 的比较（`<= now` 的几处已夹；`ActivityResolver` 几处 `p > statusUpdatedAt` 在 statusUpdatedAt 为未来时只会让「暂时修正」不生效，下一次登记表改写即恢复，不构成可见错误）。
- **settings.json**：Swift `SessionEngine.detectHookInSettings`（读 ccmon 的 `hook.sh`，仅诊断）与 `hook-merge.py`（读我们自己的 `local.buddy-office`）读的是不同的 hook，不是同一份数据的两份解析；`hook-merge.py` 在临时文件上试了：20 万层嵌套（→ R5a-04）、5000 位整数（`Exceeds the limit` 被 `ValueError` 接住，友好拒绝，没问题）、重复键（后者覆盖，`status` 正常）。
- **UserDefaults**：`Settings`（夹范围）与 `SettingsView` 的 `@AppStorage`（不夹）是同一批键的两份读取：取值越界时设置页控件与实际生效值不同，但只是显示；`strip.align` 的两处读取 → R5a-06。`hiddenKeys` 里混入非字符串会让 `stringArray` 整个返回 nil（所有隐藏项消失）：手改才会触发，没有列。
- **`buddyctl dump` 与引擎**：`DumpCommand` 直接用引擎快照，时间差换算（`Int(min(max(sec,0),1e10))`、`s < 10 / 90 / 5400` 分档）都有保护。

### 类别 2：启动时读一次、之后当成不变的系统 / 外部状态

- 读过：`AppModel`（`isUserLooking` 每次现读 `frontmostApplication`；`DesktopMeta.cache` 用 `systemUptime` 1 秒缓存，单调时钟）、`NotificationService`（R3c-02 的补卡路径：读码 + 已有的 `r3c02_…` 测试；`liveKeys` / `refresh` 的线程）、`ToastController`（`NSScreen.main` 每次 `show` 现取）、`StripPanelController`（30 Hz 里每 0.5 秒 `repositionIfNeeded`，屏幕 / Dock / 鼠标所在屏都会重取）、`TankPanelController`（→ 疑点：`placed` 一次性）、`OfficeWindowController` / `PixelView`（`backingScaleFactor` 每帧现取，`lastTextScale` 变了会重排）、`SceneClock`（`Calendar.autoupdatingCurrent`）、`Settings.dayString`（`.autoupdatingCurrent` 时区）、`LoginItem`（`isOn` 每次现读，设置页 `.onAppear` 对一遍）、`HotKey`、`AutoQuit`、`DockTileController`（→ 疑点：`lastCount`）、`SoundSynth`（→ 疑点）、`JumpService.hostApp(of:)`（每次沿父进程链现查）、`ScreenPicker`。
- 没有找到有证据的 P2：能证实的「启动时读一次」只有上面几条疑点，都需要真实屏幕 / Dock / 音频设备变化，这里造不出。
- `Settings.tallyToday` 的 1 秒缓存用的是墙钟（`timeIntervalSinceReferenceDate`），时钟往回拨时缓存要等到时钟追上才刷新：属于 R3c-P3-04 同一类（时钟回拨），白板「正」字最多陈旧「回拨量」那么久，没有单列。

### 类别 3：提醒状态机（对抗式）

- 读了：`AlertCoordinator`、`AlertPipeline`（`LiveAlertSink`）、`NotificationService`、`ToastController`、`AppModel.tick / applySettings / setDemo / jump / handleNotificationClick`、`StatusItemController`、`DockTileController`。
- **闸门对照表**（等待 / 做完了 / 出错 三种提醒 × 各道闸）：`enabled` 开关、`includeDesktop`、`isLooking`、去抖、节流、隐私、隐藏 → 出错分支缺 `includeDesktop` 和 `isLooking`（→ R5a-01）；做完了的排队等待里不再读设置（→ R5a-02）。
- **新维度随机模拟**（`R5aSimTests`，假时钟，逐拍喂快照）：250 个种子 × 3000 步 ≈ 75 万拍、24 484 条提醒；2–5 个会话（一半种子含桌面会话）；步长 60% 是 0.09 s、其余 0.05–0.6 / 0.6–3 / 3–30 s；活动随机（思考 / 等批准 / 提问 / 计划 / 其他等待 / 做完了（5–90 s，桌面 25% blocked，持续 5 s 后转空闲）/ 出错 / 空闲）；**每步 2% 概率**在这些里随机改一项：`notify.permission / question / finished / error / includeDesktop / suppressWhenFocused` 开关、`finishedMinSeconds`（5/30/60/120）、隐藏 / 取消隐藏一个会话、隐私模式开关。检查的不变量：
  ① 隐私模式下任何提醒标题 / 正文不含「SECRET」——**0 违反**；
  ② 已被隐藏的会话不发提醒（`post for muted key`）——**0**；
  ③ `waitingKeys` 恒等于「没被隐藏、活动是等待类」的集合（Dock 角标 / 菜单栏图标的数据源，`sink.update` 每拍都会调，`iconKind` / `badgeLabel` 是纯函数）——**0 不符**；
  ④ 等待类提醒不在 `permission` / `question` 关着时发——**0**；
  ⑤ 出错提醒不在 `error` 关着时发——**0**；
  ⑥ 做完了提醒不在 `finished` 关着时发——**7 违反**（R5a-02，都是排队窗口里）；
  ⑦ 桌面会话的提醒不在 `includeDesktop` 关着时发——**405 违反**（401 条是出错 = R5a-01；4 条是做完了 = R5a-02）；
  ⑧ 合并卡人数不超过没被隐藏的会话数——**1 违反**（R5a-06）。
  另外单独用探针确认了：「取消隐藏后同一段等待会重新计时并再提醒一次」是设计取向（B-009），不算问题。
- **单条卡与合并卡同 key 替换 / `multiShown`**：读码推演 + 沿用 R4a 的 180 万拍结论（本轮模拟里 `who` 与 `waitingKeys` 的关系没有出新违反）；`multiKey = "multi"` 不会和会话 key（`t:` / `d:` 前缀）冲突；`clear` 在 `NotificationService` 里会让飞行中的补卡作废。
- **Dock 角标 / 菜单栏图标 / `waitingKeys` 三者**：`waitingKeys.count` 同时喂 `DockTileController.update` 和 `StatusItemController.update`；`busy` 由 `present`（已去掉隐藏的）数，与 `waiting`（`alertable`）口径一致。`Activity.phase == .waiting` 与 `attention(of:)` 覆盖的四种活动完全一致（对照过 `Activity.swift`）。
- 已有测试在我的拷贝里全过：`AlertCoordinatorTests / AlertFallbackTests / NotificationAuthTests / ToastTextTests` 共 50 个。

### 类别 4：隐私模式的文字

- **提示卡 / 系统通知**：标题一律走 `AlertText.title(_, privacy:)`（隐私 →「会话」）；等批准正文走 `text(for:privacy:)`（隐私 →「有个权限请求（等你批准）」）；做完了 /「需要你处理」/「出错了」正文不含数据；合并卡标题固定「Buddy 办公室」；`JumpService.onNotice` 是固定文案；`UNNotificationContent.userInfo` 只有 `buddyKey`（`t:<sessionId>`）。模拟 ① 覆盖了标题 + 正文 + 隐私开关随机切换。
- **菜单栏菜单**：`StatusItemController.menuNeedsUpdate` 用 `AlertText.title` + `PlateCopy.activity(privacy:)`；tooltip 只有人数。**右键菜单**：「跳转到「…」」用 `AlertText.title(privacy:)`。**Dock 菜单**：没有实现 `applicationDockMenu`；角标只是数字。**主菜单 / 窗口标题 / 标题栏按钮的辅助功能标签**：固定文案。
- **设置页诊断**：`DiagnosticsFormatter.text(privacy:)` 用「会话」，其余行是计数 / 状态文字（对照了 `SessionEngine.diagnostics()` 里 `sourceStatus` 的全部字符串：没有路径 / 标题 / 工具）；「测试深链」回执有 `deepLinkReceipt(privacy:)`；R3c-P3-06（诊断文字生成后再开隐私不刷新）已知，未重报。
- **悬停卡**：`HoverCard.make(privacy:)`——标题、路径（cwd）、`statusDetail` 都受 `privacy` 控制；模型名 / 推理强度 / 权限模式不受控（不是标题 / 路径 / 工具详情 / MCP server 名，没有列）；`HoverPanel` 的 `CardKey` 含 `privacy`，隐私切换会重画。
- **日志**：`DebugTools.log` 只在开发开关下写，标题走 `titleForLog`（只留字数）；`AppModel.jump` 的 `NSLog("demo: 跳转到 …")` 只在演示模式（演示标题是剧本里固定的）；`NSLog("BuddyOffice: 终端跳转 AppleScript 出错 \(e)")` 里是 AppleScript 的错误字典，不含会话标题。
- **`buddyctl` 输出**：`dump` 的「细节」列 / `--json` 的 `title`、`activityDetail` 会打印标题和工具详情（R3a-P3-06 已知，未重报）。
- 没找到泄漏点（P3 只有 R5a-05：隐私打开之前已经出现的提示卡 / 通知）。

## 统计

| 严重度 | 新增 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 1（R5a-01 出错提醒漏了 `includeDesktop` / `isLooking` 两道闸） |
| P3 | 6（R5a-02 … R5a-07） |
