# 应用层修复记录（issues-app）

- 范围：`QA/audit-app.md`（A-001…A-029）+ `QA/spec-trace-ui.md` / `QA/spec-trace-core.md` 里属于应用层（`Sources/BuddyOffice`，少量 `BuddyStage` / `PixelKit`）的缺口和疑点（编号 B-0xx）。
- 日期：2026-09-29。全程遵守安全红线：没有打开 `~/.claude/sessions/*.key`、没有连 `/tmp/cc-socks/*.sock`、没有读凭据 / 钥匙串；运行时不写 `~/.claude`；没有碰 `~/.claude/settings.json`、ccmon、用量表、Claude.app；没有退出用户的 Claude、没有 kill 任何已经在跑的 BuddyOffice、没有运行 `安装.command`、没有写 `~/Applications`；不联网、没有第三方依赖。
- 没有对 `local.buddy-office` 做 computer-use：没有截屏、没有 osascript 控制别的 App；GUI 行为只能间接验证（读代码 + 单测 + 自检开关），逐项记在末尾「只能间接验证的项」。
- 编译目录：`.build-app`（自己的，没动别人的）。测试命令：`BUDDY_SCRATCH=.build-app scripts/dev.sh test --filter …`。
- **Package.swift 改了一处**：新增 `.testTarget(name: "BuddyOfficeTests", dependencies: ["BuddyOffice", "BuddyStage", "BuddyCore", "PixelKit", "BuddyArt"], swiftSettings: v5)`。`@testable import BuddyOffice`（executableTarget）可以正常编 / 跑（SwiftPM 会把 main 符号改名），测的都是抽出来的纯逻辑，没有起 NSApplication、没有弹窗口。
- 「修复前失败」的取法：每条先写测试，在没改行为的状态下跑；新抽出来的纯函数先按**修复前的判定**写一个骨架（保证能编译、行为和旧代码一致），让测试在断言上失败，再改行为、再跑。会让整个测试进程崩溃的（陷阱类：`prefix(-1)`、`0..<负数`、Int 溢出）单独 `--filter` 跑，记下崩溃那一行。

（下面每个问题一节，按修复顺序追加。）

---

## 一、P1 / P2（audit-app.md A-001 … A-011）

### A-001 [P1] 设置页「打盹 / 睡着 / 最近 N 小时 / 最多保留」四项没接到数据层
- 现象：设置 → 其他里调了什么都不变（打盹仍 10 分钟、睡着仍 45 分钟、下班工位仍取最近 3 小时）；「最多保留」调到 5–8 也不生效（引擎只保留 4 个，App 只是再 `.prefix(N)`）。
- 根因：`RealProvider.make` 只传 `dataRoot / usePolling / persist`，`SessionEngine.Options` 用默认值；`idle.*`、`dormant.recentHours` 全仓库没有消费者。
- 修法（选「下次启动生效」：`SessionEngine.options` 是 `let`、`SessionStore.options` 也是 `let`，热更新要改 BuddyCore，而 BuddyCore 在别人名下）：
  - 新增 `Sources/BuddyOffice/EngineConfig.swift`：纯函数 `EngineConfig.values(dozeMinutes:sleepMinutes:dormantMax:recentHours:)`（范围和设置页控件一致：打盹 1–120 分钟、睡着 2–240 分钟、下班工位 0–8、最近 1–24 小时；睡着至少比打盹晚 1 分钟——状态机先判 `idleFor >= sleepAfter`，睡着 ≤ 打盹时永远走不到「打盹」）+ `apply(to:settings:)`。
  - `RealProvider.make(args:settings:)` 读 `Settings`（`Settings.shared` 默认）填进 `SessionEngine.Options` 再造 `SessionStore`。`setDemo(false)` 重新走 `Providers.make`，所以切回真实数据时也会重新读一遍。
  - `SettingsView`：「下班工位」一节末尾加了说明「以上四项在下次启动 Buddy 办公室后生效（「最多保留」调小会立刻生效）。」
  - `AppModel.derive` 仍会按 `dormant.max` 再截一次（调小立刻生效）；见 A-004。
- 回归测试：`Tests/BuddyOfficeTests/EngineConfigTests.swift`：`settingsMapToEngineOptions`（3 分钟 → `dozeAfter == 180`、默认值 = 引擎原默认）、`outOfRangeValuesAreClampedAndSleepAlwaysComesAfterDoze`（0 / 负数 / 巨大值被夹住、睡着 ≥ 打盹 + 1 分钟）、`realProviderPassesTheSettingsToTheEngine`（造出的 `SessionStore.options.engine` 带着设置里的值，只造对象不 `start`）、`realProviderClampsWhatItReadsFromDefaults`。
- 修复前失败：先放骨架（`values(...)` 返回引擎默认值、`apply` 什么都不做，等于旧行为）：`EngineConfigTests.swift:10:9: Expectation failed: (v.dozeAfter → 600.0) == (180 → 180.0)`；`EngineConfigTests.swift:45:13: Expectation failed: (e.dozeAfter → 600.0) == (180 → 180.0)`（`realProviderPassesTheSettingsToTheEngine`）。
- 修复后：上面 4 个测试通过（Batch 1 合计 `✔ Test run with 39 tests in 9 suites passed`）。
- 状态：已修（「下次启动生效」）。数据层热更新（`SessionStore.applyConfig`）建议由 BuddyCore 那边的人做，见末尾「转交 / 建议」。

### A-002 [P1] 小鱼缸 / 标题栏按钮的点击可能被「窗口拖动」吞掉
- 根因：`--test-titlebar`、`panelsSelfTest` 都是「直接调视图方法」或「读命中缓冲」，从来没有走过 `NSWindow.sendEvent` → WindowServer 的这条路；DESIGN.md 第 10 节也写了 GUI 点击只能间接验证。（摘自 audit-app.md）
- 现象（读代码 + AppKit 行为推断）：`NSView.mouseDownCanMoveWindow` 默认 `!isOpaque`（= true），小鱼缸面板开了 `isMovableByWindowBackground`，落在 `PixelView` 上的左键按下被当成拖动起点，`mouseDown` 收不到 → 点小人跳转、双击回办公室、标题栏三个按钮（`PixelButton` 同样没覆盖）可能收不到点击。
- 修法：
  - `PixelView`、`PixelButton` 覆盖 `mouseDownCanMoveWindow` 为 `false`。
  - 小鱼缸的「按住背景拖动」改成手动：`TankPanelController` 把 `isMovableByWindowBackground` 改回 `false`，`pixelView.dragsWindowOnBackground = true`；`PixelView.mouseDown` 里用纯函数 `PixelView.mouseDownAction(hitID:clickCount:dragsWindowOnBackground:)` 判定——按下的地方不是小人（对象 ID 为 0）且是单击 → `window?.performDrag(with:)`；点到小人 / 双击照常走 `onClick`（跳转 / 回办公室）。
- 回归测试：`Tests/BuddyOfficeTests/PixelViewTests.swift`（`@MainActor`）：`pixelViewAndTitleBarButtonsNeverLetAppKitStartAWindowDrag`（`PixelView`、`PixelButton`、`TitleBarButtonBar` 的三个按钮 `mouseDownCanMoveWindow == false`）；`Tests/BuddyOfficeTests/PixelViewDragTests.swift`（见下方 A-002 补充：合成 `NSEvent` 走 `PixelView.mouseDown`）。
- 修复前失败：`PixelViewTests.swift:9:9: Expectation failed: (PixelView(frame: .zero).mouseDownCanMoveWindow → true) == false`（`PixelButton`、三个标题栏按钮同样是 true）。
- 进程内的真实 AppKit 自检（新增 `--test-tank-click`，`Sources/BuddyOffice/SelfTests.swift`；用 `--demo --no-persist`、假 home 跑，没有碰真实数据）：小鱼缸用合成 `NSEvent` 经 `NSWindow.sendEvent`（真实的 AppKit 事件分发）依次单击背景 / 双击背景 / 点小人——修复后：单击背景 → 交给「拖窗口」1 次、双击 → 回办公室回调 1 次、点小人 → 收到 `d:local_demo1` 的跳转回调，`RESULT PASS`。`--test-titlebar` 也改成经 `sendEvent` 分发（原来直接调 `mouseDown`），三个按钮 + 缩成小鱼缸 + 回办公室全部照常。
- **诚实的结论**：把旧配置（`isMovableByWindowBackground = true`、没有 `mouseDownCanMoveWindow` 覆盖）还原后跑同一个自检，**「双击背景」和「点小人」的回调照样收到了**（只有「单击背景交给拖窗口」这一项因为机制换了而是 0 次）——也就是说审计里担心的「点击被拖动吞掉」在进程内的合成事件下**没能复现**（合成事件不走 WindowServer 的「窗口拖动」判定，真实鼠标路径是否吞点击仍然只能真机点一下确认）。所以 A-002 的修法是防御性的：不会有副作用，即使原本没有这个问题也值得加（审计原话）；不要把它当成「已复现并已确认修好」。
- 状态：已修（防御性；旧问题未能复现，真实鼠标路径仅间接验证）；见末尾「只能间接验证的项」。

### A-003 [P1] 最小化的办公室窗口会在任何一次设置写入之后被弹回来
- 现象：窗口最小化到 Dock（`office.visible` 仍是 true，`isVisible` 是 false）；之后任何 UserDefaults 变化（做完一轮写白板计数、AppKit 存窗口位置、改任何设置）→ `applySettings` 看到「窗口不可见」→ `showOffice()` → 弹回来。⌘H 隐藏整个 App 后同理。
- 根因：把「窗口不可见」当成「被关闭了」，没有区分最小化 / 隐藏 / 关闭；`applySettings` 对所有键无差别重跑（见 A-016）。
- 修法：新增 `Sources/BuddyOffice/ApplyPlan.swift`：`FormInputs`（六项入口开关）、`ApplyPlanner.plan(previous:current:window:)`（纯函数）——只处理**相对上一次应用有变化**的项；办公室窗口只有 `office.visible` 这个开关自己变了才 `show` / `hide`，窗口是最小化 / 被隐藏 / 别的原因不可见都不会被弹回来。`AppModel.applySettings` 记住 `lastApplied` 并按 plan 执行；`showOffice` 里明确要开办公室时会先 `deminiaturize`（用户从菜单 / Dock / 热键打开时，最小化的窗口也恢复出来）。
- 回归测试：`Tests/BuddyOfficeTests/ApplyPlanTests.swift`：`aMinimizedOfficeWindowIsNotBroughtBackByAnUnrelatedSettingsWrite`、`aHiddenAppDoesNotGetItsOfficeWindowPoppedBackEither`、`turningTheOfficeOnShowsItEvenIfItIsMinimized`、`turningTheOfficeOffHidesIt`。
- 修复前失败（骨架 = 旧判定 `officeOn && !isVisible → show`）：`ApplyPlanTests.swift:15:9: Expectation failed: (plan.office → .show) == nil`；`ApplyPlanTests.swift:21:9: Expectation failed: (plan.office → .show) == nil`（隐藏的 App）。
- **真实 AppKit 上的证据（这条不是只靠纯函数）**：
  1. 一个只控制自己一个小窗口的探针（`swiftc` 编的独立小程序，跑完自己退出）：最小化后 `isMiniaturized=true isVisible=false`；旧判定 `!window.isVisible` 为 true（会去 `showOffice`）；执行旧逻辑的 `showWindow(nil)` + `orderFrontRegardless()` 之后 `isMiniaturized=false isVisible=true`——**审计里「可能（75%）」的两条 AppKit 行为都得到证实：最小化窗口的 `isVisible` 是 false，`showWindow` + `orderFrontRegardless` 会把它从 Dock 里弹回来。**
  2. 新增自检 `--test-minimize`（`SelfTests.swift`，App 里真实的 `applySettings` 链路）：把办公室窗口最小化、再写一项无关设置（小鱼缸透明度）和一次白板计数，1.3 秒后看是否还是最小化。**修复前的判定（把 `ApplyPlanner.plan` 临时换成旧规则，其余不变）：`minimize-test: 写了设置和白板计数 1.3 秒后：isMiniaturized=false isVisible=true → FAIL（被弹回来了）`；修复后：`isMiniaturized=true isVisible=false → PASS（没被弹回来）`。**
- 状态：已修（真实窗口 A/B 验证过）。

### A-004 [P2] `dormant.max` 为负数 → `prefix(-1)` 崩溃，启动即崩
- 现象：`defaults write local.buddy-office dormant.max -int -1`（或偏好设置文件被写坏）。`Array.prefix(_:)` 对负数 `precondition` 失败（Package 没开 `-Ounchecked`，release 里也检查）。`refreshDerived` 在 `AppModel.start()` 里就会调用 → 启动即崩，而 SessionStart hook 会不断把 App 拉起来 → 崩溃循环，只能 `defaults delete`。设置页的 Stepper 限制在 0…8，所以只有外部改文件才会触发。（摘自 audit-app.md）
- 根因：读取外部可写的值时不做范围夹取（`zoom`、`opacity` 已经夹了，这一个漏了）。（摘自 audit-app.md）
- 修法：`Settings` 加范围表 `intRanges` / `doubleRanges`，`int(_:)` / `double(_:)` 读出来统一夹进合法范围（`dormant.max` 0…8、`dormant.recentHours` 1…24、`idle.dozeMinutes` 1…120、`idle.sleepMinutes` 2…240、`notify.finishedMinSeconds` 5…600、`office.zoom` 0…5、`tank.zoom` 1…2、`strip.zoom` 1…3、`tank.opacity` 0.3…1，NaN 取上界）——所有消费者不用各自再防；`AppModel.refreshDerived` 里的派生逻辑抽成静态纯函数 `AppModel.derive(snapshots:hidden:dormantMax:)`，里面自己再夹 `0…8`（双保险），超出时留下**最近活动**（`away.since` 最晚）的几个、仍按座位顺序排（顺带解决 spec-trace-core 疑点 Q-03：原来留下的是座位号小的）。`Settings` 加了 `init(defaults:)`（测试传私有 suite，不碰用户偏好文件）。
- 回归测试：`Tests/BuddyOfficeTests/SettingsTests.swift`：`numbersWrittenBehindOurBackAreClampedIntoTheirValidRange`（每个带范围的键 × 负数 / 0 / 正常 / 极大 / `Int.min` / `Int.max` / NaN / ±∞）、`deriveNeverTrapsWhateverTheDormantMaxIs`（`-1 / Int.min / 0 / 1 / 8 / Int.max`）。
- 修复前失败：`SettingsTests.swift:13:17: Expectation failed: (s.int("dormant.max") → -1) == (want → 0)`（另有 99 → 99、`Int.max` 原样返回）；单独跑 `deriveNeverTrapsWhateverTheDormantMaxIs`：`Swift/Collection.swift:1329: Fatal error: Can't take a prefix of negative length from a collection`，进程崩溃。
- 状态：已修。

### A-005 [P2] 今日白板计数 ≤ -5 → `drawTally` 的 `0..<负数` 崩溃；`addTally` 在 Int.max 时溢出
- 现象：`defaults write local.buddy-office tally.2026-09-29 -int -5`（或更小）：`n / 5 = -1`、`n % 5 = 0` → 区间 `0..<-1` → 运行时陷阱；当天办公室窗口每次渲染（白板可见时）就崩。写成 `Int.max`：下一次「做完了」时 `addTally` 的 `+ 1` 溢出崩溃。（摘自 audit-app.md）
- 根因：外部可写的值没有夹取；`drawTally` 假设 `n ≥ 0`。（摘自 audit-app.md）
- 修法：`Settings.tallyToday()` 返回值夹在 0…9999（`tallyRange`）；`addTally()` 先夹再 `+ 1` 再夹（存的是 `Int.max` 时原来的 `+ 1` 溢出）；`RoomRenderer.drawTally` 开头 `let n = max(0, n)`（负数当 0 画，和 `n = 0` 逐像素相同）。
- 回归测试：`SettingsTests.tallyReadFromTheFileIsClamped`、`SettingsTests.addTallyDoesNotOverflow`；`Tests/BuddyStageTests/AppLayerFixTests.swift`：`whiteboardTallyNeverTrapsAndNegativeCountsAsZero`（`-1 / -4 / -5 / -6 / -100 / Int.min / Int.min + 1` 的画布哈希 = `0` 的；`75` 和 `Int.max` 一样）。
- 修复前失败：`SettingsTests.swift:49:17: Expectation failed: (fresh.tallyToday() → -5) == (want → 0)`（`Int.min`、`123456`、`Int.max` 同样原样返回）；单独跑 `addTallyDoesNotOverflow` 与 `whiteboardTallyNeverTrapsAndNegativeCountsAsZero`：`error: Process '…swiftpm-testing-helper…' exited with unexpected signal code 5`（SIGTRAP，测试进程崩溃）。
- 状态：已修。

### A-006 [P2] 桌面宠物「位置 / 显示在」改了不立即生效
- 现象：设置 → 桌面宠物 → 「位置」（靠右 / 居中 / 靠左）或「显示在」（主屏幕 / 鼠标所在的屏幕）改了之后，面板不动。`reposition()` 只有两个触发点：宠物条画布尺寸变了（有人来 / 走）、`NSApplication.didChangeScreenParametersNotification`。另外，「靠右 / 靠左」会让条内人物的排布方向立刻翻转（`scene.alignRight` 每帧读设置），于是看起来是人挤到面板一侧、面板还在原处。「鼠标所在的屏幕」只在 `reposition` 时求一次值，不会跟着鼠标。Dock 改大小 / 换位置时不一定触发 `didChangeScreenParameters`（可能）。（摘自 audit-app.md）
- 根因：`render` 的 `settingsGen != model.settingsGen` 分支只更新 `zoom` 和窗口层级，没有重新定位。（摘自 audit-app.md）
- 修法（`StripPanelController`）：抽出纯函数 `StripPanelController.origin(align:visibleFrame:panelSize:margin:)`；`Placement`（位置 / 所在屏幕 frame / `visibleFrame` / 条的大小）+ `needsReposition(last:now:)`；`repositionIfNeeded()` 在 ① `render` 的「设置变了」分支、② `poll()` 每 0.5 秒（`pollTick % 15`）里调用——设置里改了「位置」「显示在」立刻挪；「鼠标所在的屏幕」跟着鼠标；Dock 改大小 / 挪位置（`visibleFrame` 变了，屏幕参数通知不一定来）也会挪（顺带补上任务书 7.1「每 2 秒检查一次 visibleFrame」——spec-trace-ui U28 / C06b 缺口）。
- 回归测试：`Tests/BuddyOfficeTests/StripPlacementTests.swift`：`rightLeftCenterAndUnknownAlignments`（左 / 中 / 右 / 认不出的取值 / 负原点屏幕 / Dock 在左边）、`anyChangeOfThePlacementInputsTriggersARepositionAndNothingElseDoes`。
- 修复前失败（骨架 = 旧规则：只有条的大小变了才重新定位）：`StripPlacementTests.swift:32:9: Expectation failed: StripPanelController.needsReposition(last: …)`（改「位置」）、`:34:9`（换屏幕）、`:36:9`（Dock 改了大小）。`origin(...)` 是把原来的算术原样抽出来，测试第一次就是绿的。
- 状态：已修（仅间接验证：`NSScreen` / `NSPanel.setFrameOrigin` 的真实效果没有真屏幕可看；判定和算术都有测试）。

### A-007 [P2] 「换个造型」：坐着的 / 走路的 / 重启后的造型三者不一致
- 现象：右键 buddy → 换个造型：坐着的人立刻变成一个随机造型 X（`Appearance.generate(seed: UInt64.random(...))`，和 salt 无关）；但 (1) 持久化的是 salt+1，重启后的造型是 f(salt+1) ≠ X，用户挑中的造型丢了；(2) `appearances[key]` 被清空后，下一次 `appearance(for:)` 会用当时快照里的旧 salt（`rerollAppearance` 是异步的，新 salt 要等下一个快照）重新算出旧造型并缓存 → 之后的走进 / 走出动画（`OfficeScene` 用 `director.appearance(for:)`）和衣帽架上的外套仍是旧造型。（摘自 audit-app.md）
- 根因：UI 层用随机数造了一个不和 salt 关联的外观。（摘自 audit-app.md）
- 修法：`VisualDirector.reroll(key:)` 不再立刻换一个和盐无关的随机造型，只记下「等新盐」（`rerolling[key] = 当前盐`）；数据层（异步）把盐 +1 并持久化后，下一个快照带着新盐来了（`update(snapshots:)` 开头检测 `salt != 旧盐`）才清缓存、按新盐重算并 `performers[key].setAppearance(...)`——坐着的人、走进 / 走出的人（`director.appearance(for:)`）、衣帽架上的外套、重启之后（读到的还是这个盐）是同一个外观。演示模式（`MockSource`）原来 `rerollAppearance` 是空函数，现在也把盐 +1（叠加偏移量），所以演示里「换个造型」照常有效。
- 回归测试：`AppLayerFixTests.rerollWaitsForTheNewSaltAndThenEveryPlaceAgrees`（新盐到之前外观不变；到了之后 = `Appearance.generate(seed: AppearanceSeed.seed(key:salt: 2))` = 重启后的样子 = `director.appearance(for:)`）、`rerollOnlyTouchesTheChosenBuddy`（别人不受影响；盐一直没变就一直等，不瞎换）。
- 修复前失败（临时还原旧实现跑）：`AppLayerFixTests.swift:180:9: Expectation failed: (d.performers["t:R"]!.appearance → Appearance(skin: 0, hairStyle: buzz, …) == before)`（新盐还没到就变了）、`:185:9`（换完后不等于按新盐算出来的）、`:186:9`（`director.appearance(for:)` 又是另一个）；`:203:9`（别人的外观也被动了——盐一直没变时旧实现的随机造型早就换掉了）。
- 状态：已修。

### A-008 [P2] 同一会话第二次走进办公室：座位上已坐着人，门口又走进来一个「分身」
- 现象：会话 K 在 App 运行期间走进来（`seatedAt[K]` 记下坐下时刻）→ 离场 → 用同一个身份回来（关掉终端再 `--resume`；桌面 App 重启后同一个 hostSessionId 回来；演示模式每 80 秒循环一遍的 `demo5`）。回来时 `startEntering` 起了走路动画，但 `seatedAt[K]` 还是上一次的旧值（非 nil）：`if let s = sp, walkers.isBusy(s.key), seatedAt[s.key] == nil` 不成立 → 座位按「已坐好」画（开机动画已满），同时门口的走路者照常走过来，走到椅子处叠在座位上的人身上。（摘自 audit-app.md）
- 根因：`seatedAt` 只在 `nil` 时写、从不清。（摘自 audit-app.md）
- 修法：`OfficeScene.render` 的「人员变化」分支里，对 `pk.subtracting(nowKeys)`（离场的人）`seatedAt.removeValue(forKey:)`，同时清 `lastApp`（离场动画启动后就不再需要；顺带解决 A-018 里这两个字典只增不减）。`options.animateWalkers == false` 时也清。
- 回归测试：`AppLayerFixTests.aSessionThatComesBackWalksInAgainInsteadOfSittingDownAtOnce`（30 fps 连续帧：出现 → 走完坐好 → 消失 → 离场走完 → 再出现：第一帧 `mode == .empty && chairOut == true` 且 `walkers.isBusy`；走完之后才 `.occupied`）、`departedSessionsAreForgottenByTheScene`（`animate` 真 / 假两档：离场的人不留在 `seatedAt` / `lastApp` 里，还在的人不动）。
- 修复前失败：`AppLayerFixTests.swift:141:9: Expectation failed: (seatView()?.mode → .occupied) == .empty`、`:142:9: Expectation failed: (seatView()?.chairOut → false) == true`；`:162:9: Expectation failed: (scene.seatedAt["t:a"] → 2.0) == nil`。
- 状态：已修。

### A-009 [P2] `Canvas.writeBGRA` 在 crop 与画布不相交时退化成整张画布（潜在越界写）
- 现象：当前所有调用点的 viewport 都在画布内（`OfficeScene` 的 `vp` 被夹在世界里；小鱼缸 / 宠物条 / 提示卡 / 悬停卡用整张），所以**现在不可达**。将来任何把 viewport 传到画布外的改动（镜头 bug、窗口极小时夹错），会在共享内存（合成器正在读）上越界写整张画布——堆损坏 / 崩溃。（摘自 audit-app.md）
- 根因：用「回退成整张」代替「什么都不写」；函数不校验目标大小。（摘自 audit-app.md）
- 修法：`guard let r = (crop ?? bounds).intersection(bounds), bytesPerRow >= r.w * 4 else { return }`——不相交（含宽高 ≤ 0）什么都不写，一行放不下也不写；`r ⊆ crop`，所以按 `vp.w × vp.h` 分配的 IOSurface 永远放得下。`makeDisplayImage` 自己算的 `r` 不受影响。
- 回归测试：`AppLayerFixTests.writeBGRAWithACropOutsideTheCanvasWritesNothing`（带哨兵值的缓冲：完全在画布外 / 负坐标 / 零宽 / 零高 / 负宽 / 贴着右边缘外 6 种 crop，哨兵一个字节都不动）、`writeBGRAWithAPartlyOutsideCropWritesOnlyTheOverlap`（部分相交只写相交那块、落在目标左上角；`bytesPerRow` 太小时不写）。
- 修复前失败：`AppLayerFixTests.swift:47:13: Expectation failed: buf.allSatisfy { $0 == sentinel }`（`crop IntRect(x: 2, y: 2, w: 0, h: 4) 和画布不相交：目标内存一个字节都不该动`，6 种 crop 全部失败）；`AppLayerFixTests.swift:68:9: Expectation failed: tiny.allSatisfy { $0 == sentinel }`。
- 状态：已修（当前所有调用点不可达，属纵深防御）。

### A-010 [P2] 「跟着 Claude 一起收」把被隐藏的 buddy 当成没有会话
- 现象：用户把所有在场的 buddy 都「隐藏」了（比如都是后台任务）；Claude 桌面 App 一退出 → 60 秒后 `hasLiveSessions()` 为 false → 自动退出，而终端里的 `claude` 会话其实还活着，AlertCoordinator 本来仍会为它们发「等你批准」的提醒，现在也没了。（摘自 audit-app.md）
- 根因：用于显示的过滤集合被拿去判断「是否还有活会话」。（摘自 audit-app.md）
- 修法：`AppModel.hasLiveSessions(snapshots:)`（静态纯函数：任何 `presence == .present` 的快照，不管用户有没有隐藏）；`autoQuit.hasLiveSessions` 改用它（原来是 `!present.isEmpty`，而 `present` 已经剔除了隐藏的）。
- 回归测试：`Tests/BuddyOfficeTests/AutoQuitTests.swift`：`hiddenBuddiesStillCountAsLiveSessions`、`noPresentSessionsMeansNothingIsLive`（只有下班工位不算活会话）。
- 修复前失败（骨架 = 旧语义：走 `derive` 之后的 `present`）：`AutoQuitTests.swift:11:9: Expectation failed: AppModel.hasLiveSessions(snapshots: …)`（所有在场 buddy 被隐藏 → 被判成没有会话）。
- 状态：已修（`AutoQuit` 自身的 60 秒逻辑见 B-4）。

### A-011 [P2] 座位号没有上限
- 现象：`~/Library/Application Support/BuddyOffice/identities.json` 里某个身份的 `seat` 被写成很大的数（文件损坏 / 手动编辑）。`compressSeats()` 只在第一次 `poll` 里对「当时已在场」的 buddy 执行；之后才出现的身份走 `assignSeat`，它「优先坐回上次的工位（没被别人占着的话）」，会把这个巨大的座位号原样交给 App。`OfficeScene` 用 `deskCount = max(4, maxSeat + 2)` 分配 `Int` 数组和 `worldW × worldH × 8` 字节的画布（`rows = deskCount / cols`，高度按行数线性增长），没有任何上限 → 内存分配失败（崩溃）或系统卡死；座位号 ≥ 64536 时 `hitID` 的 `UInt16(1000 + seat)` 也会溢出崩溃。小鱼缸 / 宠物条只画前 8 个人，座位号只用于命中 ID 的槽位，不受影响。（摘自 audit-app.md）
- 根因：座位号被当成「小整数」，数据层和 App 层两层都没有夹取。（摘自 audit-app.md）
- 修法（App 层三道防线；**Core 的 `IdentityResolver` 那部分没动，见末尾「转交」**）：
  1. `AppModel.wire`：数据一进来先过 `SeatSanitizer.sanitize`（`ApplyPlan.swift`）——座位号不在 `0..<64` 的改成最小的空位（按 key 排序依次拿，确定性；其余人不动；空位不够就保持原样），之后按 `(seat, key)` 排序。
  2. `OfficeLayout.compute`：`min(maxSeat, Metrics.maxSeats - 1) + 2`（新增 `Metrics.maxSeats = 64`），任何座位号都不会让桌子数 / 画布高度失控，`Int.max` 也不再 `+ 2` 溢出。
  3. `OfficeScene.hitID(seat:)`：座位号夹在 0…999（`UInt16(1000 + …)` 不再溢出，也不会撞进 2000+ 的小鱼缸 ID 段）；`seat(fromHitID:)` 只认 1000…1999（原来 ≥ 1000 都认，2000+ 的小鱼缸 ID 会被误当成座位）。
- 回归测试：`Tests/BuddyOfficeTests/SeatSanitizerTests.swift`（3 个：野座位号变成最小空位 / 正常列表原样返回 / 座位不够不崩）；`AppLayerFixTests`：`layoutCapsTheDeskCountWhateverTheSeatNumberIs`、`layoutSurvivesTheLargestSeatNumbers`（`Int.max / Int.max - 1 / Int.min / -1`）、`hitIDsNeverOverflowAndStayInTheOfficeRange`、`officeSceneRendersWithWildSeatNumbers`（`Int.max`、`5_000_000_000`、`-3` 的快照照常渲染）。
- 修复前失败：`AppLayerFixTests.swift:74:9: Expectation failed: (l.deskCount → 1000000002) <= (Metrics.maxSeats + 2 → 66)`、`:75:9: (l.worldH → 25333333462) < 100000`；`SeatSanitizerTests.swift:15:9: Expectation failed: r.allSatisfy { (0..<SeatSanitizer.maxSeats).contains($0.seat) }`；`layoutSurvivesTheLargestSeatNumbers` / `hitIDsNeverOverflow…` / `officeSceneRendersWithWildSeatNumbers` 单独跑都是 `exited with unexpected signal code 5`（`maxSeat + 2` 溢出 / `UInt16(1000 + 70000)` 溢出）。
- 状态：已修（App 层）；Core 侧「输出快照前夹到 0..<64、`IdentityResolver.load` 丢弃 `seat < 0 || seat > 999`」转交。

---

## 二、额外范围（spec-trace-ui / spec-trace-core 的应用层缺口和疑点，编号 B-0xx）

### B-001 [P2] AlertCoordinator 零单测 + 系统通知被拒时兜底提醒确实会出现
- 修法：把提醒逻辑重构成可注入时钟 / 可注入出口的纯逻辑（见下面「重构」一条）。
- 现象：AlertCoordinator（1.5 s 去抖 / 20 s 节流 / 2 s 合并 / 8 s 等待）零单测；系统通知被拒时的兜底提醒（提示卡 + Dock 角标 + 菜单栏图标）没有任何测试证明会出现；另有 Dock 弹跳没去抖、合并提醒永不撤、终端「做完了」不复查等行为缺口。
- 根因：提醒逻辑直接读 UserDefaults 和真实时钟，出口（系统通知 / 提示卡 / Dock / 菜单栏）没有抽象，没法喂假时钟、没法断言兜底。
- 来源：spec-trace-ui N01–N16 / N20b / N07b、疑点 12；spec-trace-core 5.6-03、Q-04；audit-app A-018 / A-019 / A-022。
- 重构（`Sources/BuddyOffice/AlertCoordinator.swift`、`AlertPipeline.swift`、`NotificationService.swift`、`SystemHelpers.swift`、`StatusItemController.swift`）：
  - `AlertCoordinator.observe(_:now:config:muted:isLooking:privacy:)`：设置拷成值 `AlertConfig`（不碰 UserDefaults），时钟就是 `now` 参数——测试用假时钟；逻辑拆成 `handleWaiting` / `handleFinished` / `post`（逐个快照的记账放在循环最前面，`continue` 不会再跳过它，A-022 ①）。
  - 出口抽成 `AlertSink` 协议（`post / clear / addTally / update(waiting:busy:newlyWaiting:)`），`AlertPipeline.run` = AppModel.tick 里原来的提醒那一段；`LiveAlertSink` 接 `NotificationService`（系统通知 / 提示卡 / 提示音）+ 菜单栏图标 + Dock（`DockTileController.Env` 可注入）。`NotificationService` 的系统通知中心（`NotificationCenterClient`）、提示卡（`ToastPresenting`）、提示音、`available` 都可注入。
  - 行为修正（都有红灯测试）：① Dock 弹跳和弹窗共用 1.5 秒去抖（原来等待一开始就弹，一闪而过的等待也会让 Dock 图标弹一下，N20b）；② 「N 位同事在等你」合并提醒：所有被合并的人都不再等时撤掉它（原来 `buddy.multi` 永远留在通知中心，A-022 ②），合并对象是「做完了」时文案是「N 位同事做完了」、混着来是「N 位同事有事找你」（原来一律说「在等你」）；③ 终端会话的「做完了」在宿主 App 在最前面时先等 8 秒再判断一次（N07b，原来立刻判断、在看就直接丢掉）；④ 等了 8 秒之后才发的「做完了」，这 8 秒里下一轮已经开始就不发（疑点 12）；⑤ 记账字典有界：`prevActivity / finished / lastAlert` 随会话消失和 20 秒节流窗口清理（A-018）；⑥ 走了的 / 被隐藏的会话的等待记录立刻撤掉（原来 away 的会话要等从快照里消失）；⑦ 标题统一走 `AlertText.title`：空白标题用占位、换行换成空格、最多 40 字（A-019 的 AlertCoordinator 部分）。
- 回归测试：`Tests/BuddyOfficeTests/AlertCoordinatorTests.swift`（30 个，假时钟）：去抖 1.49 s 不发 / 1.5 s 发、一段等待只发一次、各类文案与隐私模式、设置开关、一闪而过的等待、换种类重新计时、20 秒节流（4 s / 18 s 内挡住，20 s 整放行）、不同种类 / 不同 buddy 互不节流、2 秒合并（2 人 / 3 人 / 刚好隔 2 秒不合并 / 同一 buddy 不合并）、合并提醒的撤除与文案、做完了（30 秒门槛 / 被打断 / 设置 / 白板计数）、桌面 8 秒等本轮总结与 blocked、终端 8 秒复查、出错默认关、includeDesktop、记账有界、`continue` 不跳记账。`Tests/BuddyOfficeTests/AlertFallbackTests.swift`：**系统通知被拒时兜底提醒确实会出现**——授权状态 `.denied` 时，等待满 1.5 秒后提示卡出现（`toast.shown`，kind / 文案 / key 对）、一条系统通知都没发（`center.added.isEmpty`）、Dock 角标 `"1"`、Dock 弹一下（App 不在前台）、菜单栏图标变 `.waiting`、提示音照响，等待结束后提示卡收回、角标清掉、图标恢复；另有已授权走系统通知、`notDetermined` / 非 App 包同样兜底、App 在前台不弹跳、多人角标与合并、隐藏 = 不打扰、演示模式不计白板。
- 修复前失败（旧逻辑 + 新测试，节选）：`AlertCoordinatorTests.swift:370:9: Expectation failed: !((c → AlertCoordinator).newlyWaiting → true → true)`（Dock 弹跳没有去抖）；`:192:9: Expectation failed: (Self.clears(none) → ["t:b"]).contains(AlertCoordinator.multiKey → "multi")`（合并提醒永远不撤）；`:207:9: … (m[0].body == "2 位同事做完了" → false)`（合并「做完了」的文案）；`:327:9: Expectation failed: (p.count == 1 → false)`（终端「做完了」没有 8 秒复查）；`:278:9: Expectation failed: (obs(9, Self.busy("d:a", origin: .desktop)) → [(key: "d:a", kind: finished, …)])`（下一轮已开始还发「做完了」）；`:441:9: Expectation failed: (n.prevActivity → 1500) <= 1`、`:444:9: (n.lastAlert → 3000) <= 12`（记账无界）。兜底链路本身是原来就有的行为（此前没有任何测试），所以另做了**变异检查**证明测试能抓到它坏掉：临时把 `systemAllowed` 改成恒为 `available`、并去掉 `sink.update(...)`，`AlertFallbackTests` 立刻失败——`AlertFallbackTests.swift:54:9: Expectation failed: (r.toast.shown.count → 0) == 1`、`:57:9: (r.center.added → [(key: "t:a", …)]).isEmpty`、`:48:9: (r.icons.last → nil) == .waiting`、`:49:9: (r.dock.badge → nil) == "1"`、`:58:9: (r.dock.attention → 0) == 1`；恢复后全部通过。
- 修复后：`AlertCoordinatorTests` 30 个、`AlertFallbackTests` 9 个（含参数化）全部通过。
- 端到端（release 版 App，`--demo --speed 4 --log-ui --no-persist --data-root <假 home> --show`，裸可执行文件所以 `available == false`＝系统通知不可用、走兜底）：`--log-ui` 日志里演示走到「等批准」时出现 `等你=1 Dock 角标=1 菜单栏图标=waiting`，等待结束后恢复 `等你=0 Dock 角标=无 菜单栏图标=busy`，来回多次，没有崩溃。
- 状态：已修。关于 A-022 ③（被隐藏的 buddy 是否该提醒）见 B-009。

### B-002 [P2] 「点击 buddy 不会跳到别人的会话」：JumpService 目标解析抽成纯函数 + 桌牌点击核对
- 现象：点击 buddy 只该跳到自己的会话，但「命中 ID → 座位 → 会话」这条链没有测试；小鱼缸 / 宠物条按座位号跳转，两帧之间座位换了人会跳错；合并提醒（key multi）点了没反应；使用说明写「点小人（或桌牌）」但桌牌点不了。
- 根因：跳转目标解析散在 AppModel / JumpService 里、依赖 AppKit，没法单测；小鱼缸 / 宠物条传的是座位号；桌牌底板像素不带对象 ID。
- 修法：新增 `Sources/BuddyOffice/JumpResolver.swift`：`JumpResolver.snapshot(forSeat:in:)`（只认在场会话，下班工位 / 空座位 / 越界座位号什么都不发生）、`snapshot(forKey:in:)`、`target(for:deepLinkDisabled:)`（`.desktopDeepLink / .activateClaude / .vscode / .terminal / .none`）、`notificationClick(key:in:)`、`deepLinkVerdict(...)`、`terminalTabScript(tty:)`。`JumpService.jump(to:)` 只负责执行 `JumpResolver.target(...)` 的结果。
  - 小鱼缸 / 宠物条原来点击时传的是「座位号」，`AppModel.jump(seat:)` 再按座位号找会话——两帧之间座位换了人就可能跳到别人；现在它们传渲染那一刻的快照（`onClickBuddy`），`AppModel.jump(snapshot:)` 再按 **key** 重新找最新的那份（会话已经走了就什么都不做）。办公室窗口的命中 ID 只编码座位号，所以走 `JumpResolver.snapshot(forSeat:)`（点的时候和渲染同一份 `snapshots`，窗口 ≤ 66 ms）。
  - 点通知 / 提示卡：合并提醒（key `multi`）原来按 key 找不到快照、什么都不发生，现在打开办公室（`AppModel.handleNotificationClick`）。
  - **桌牌点击**：使用说明.txt 写「点小人（或桌牌）」，但桌牌底板上的像素不带对象 ID（`SeatRenderer.drawPlate`），点不了。选择**改文档**（更省事、不改产品行为）：`使用说明.txt` 里改成「点小人」——**这是文档改动，行为没动；请写进 DESIGN.md 偏离条目**。
- 回归测试：`Tests/BuddyOfficeTests/JumpTests.swift`（11 个）：每个座位映射到自己的会话和目标（6 个会话、三种来源、座位号和数组顺序故意错开）、座位 / 会话变动后不串（走了的人座位换了新人、搬座位、按 key 跟着人走）、悬空座位点击不跳（无人 / 下班工位 / 越界 / 负数 / `Int.max`）、深链规则（needs-input / continue、停用、非法 host id 的 11 种）、终端 / VS Code 目标、通知点击路由、深链 2.5 秒判定、终端脚本超时与 tty 校验、桌牌带里没有任何可点像素、使用说明不再说点桌牌能跳。
- 修复前失败：`JumpTests.swift:154:9: Expectation failed: (offending → ["· 点小人（或桌牌）：桌面 App 会话用深链直接跳到对应的会话；终端会话切到对应的终端标签页；"]).isEmpty → false`（使用说明 vs 实现）。其余是把原来内联在 `AppModel` / `JumpService` 里的判定抽成纯函数，第一次跑就是绿的；深链判定里**唯一的行为变化**（目标本来就是最近聚焦的会话、Claude 不在最前面时补一次激活，见 A-026）用变异检查确认：把这一支改回旧行为 → `JumpTests.swift:121:9: Expectation failed: (… deepLinkVerdict(wasLatest: true, before: 100, after: 100, claudeFrontmost: false) → DeepLinkVerdict(succeeded: true, activateClaude: false)) == (V(succeeded: true, activateClaude: true) …)`。
- 状态：已修（实际点击 → 窗口服务器 → `NSWorkspace.open` 那一段属只能间接验证，见末尾）。

### B-003 [P3] 首次打开办公室时请求通知授权（DESIGN §2 M0）
- 根因：没有在首次显示办公室时触发授权请求的代码。
- 现象：DESIGN 写「授权请求放到用户第一次主动打开办公室窗口的时候发」，代码里只有设置页按钮和「发一条测试提醒」会请求（spec-trace-ui N18b / audit-app A-023）。
- 修法（`NotificationService`）：`officeMayHaveOpened(appActive:officeVisible:)`——先读一次系统里的真实授权状态，再按纯函数 `shouldRequestOnOfficeOpen(status:alreadyAsked:appActive:officeVisible:available:)` 决定：系统里还是 `notDetermined`、我们没问过（`notify.authRequested` 标记，发出请求时写入）、App 在前台、办公室窗口可见、是 App 包——才请求。所以：后台启动（hook 用 `open -g`）不问，等用户第一次真的点开办公室（Dock / 菜单 / 热键 / 小鱼缸双击）再问；**拒绝 / 已答复 / 问过没答复之后都不再自动弹**（设置页的按钮不受限）。调用点：`AppModel.showOffice`（`orderFront` 之后）、`AppDelegate.applicationDidBecomeActive`（安装脚本 `open` 启动、办公室窗口已经在时）。
- 回归测试：`Tests/BuddyOfficeTests/NotificationAuthTests.swift`（假通知中心）：第一次主动打开只问 1 次、答复（拒绝）后再打开 5 次也不再问；后台 / 窗口不可见不问；已答复（denied / authorized / provisional）不问；非 App 包不碰通知中心；「问过」标记跨实例（重启）保留、设置页按钮仍然能发；决策函数 6 个分支。
- 修复前失败（变异：把 `officeMayHaveOpened` 改成什么都不做，即旧行为）：`NotificationAuthTests.swift:18:9: Expectation failed: (c.requests → 0) == 1`、`:22:9: Expectation failed: (n.status → UNAuthorizationStatus(rawValue: 0)) == (.denied → UNAuthorizationStatus(rawValue: 1))`。
- 状态：已修（真正的系统授权弹窗只能真机看，见末尾）。

### B-004 [P3] 自动收起（AutoQuit）可测：Claude 退出且没有活会话 60 秒后退出
- 现象：自动收起（Claude 退出且没有活会话 60 秒后自己退出）的判定和定时全无测试，也没有证据说明它不会退出用户的 Claude。
- 根因：定时器和退出动作写死在 AutoQuit 里，不可注入，无法在测试里推进时间。
- 修法：`AutoQuit` 的定时器（`Scheduler`）、通知中心、退出动作（`terminate`，默认 `NSApp.terminate`——只退出我们自己）、日志都可注入；通知回调只做「取 bundle id」，逻辑在 `appTerminated(bundleID:)` / `appLaunched(bundleID:)`；`hasLiveSessions` 由 `AppModel.hasLiveSessions(snapshots:)` 提供（被隐藏的也算活着，见 A-010）。
- 回归测试：`AutoQuitTests.swift`：Claude 退出 → 60 秒后退出自己且 60 秒之前不退、有活会话（含被隐藏的）不退、只有 Claude 退出才开始倒计时（Safari / `com.anthropic.claude-code` CLI 包 / 自己 / nil 都不）、开关关着不倒计时且倒计时期间关掉也不退、Claude 重新打开取消 / 再退出一次替换老的倒计时、`--test-autoquit` 入口；**不退出用户的 Claude**：`autoQuitNeverQuitsAnotherApp` 源码审计（`SystemHelpers.swift` 里没有 `forceTerminate`、没有 `NSRunningApplication.terminate()`，只有 `self.terminate()` 闭包和默认的 `NSApp.terminate(nil)`）。
- 修复前失败：这一条本身是「原来没法测」；行为上唯一的缺陷是 A-010（隐藏的 buddy 被当成没有会话，红灯见 A-010）。
- 已知限制（沿用原设计，未改）：到点时条件不满足（还有会话）不会重新武装，之后会话都结束了也不会再自动退出。
- 状态：已修。

### B-005 [P3] 小鱼缸 / 宠物条先渲染第一帧再显示（spec-trace-ui M13b，协调者补充）
- 现象：小鱼缸 / 宠物条先 orderFront 再渲染第一帧，可能先露出一帧底色（任务书 6.6：窗口出现时先渲染好第一帧再显示）。
- 根因：show() 里的顺序反了，而 render 又要求面板已经可见。
- 修法：`PanelShow.show(isVisible:renderFirstFrame:orderFront:)`——还没在屏幕上：先 `render(model:force: true)` 出第一帧，再 `orderFrontRegardless()`；已经在屏幕上不重复 orderFront。`TankPanelController.show(model:)` / `StripPanelController.show(model:)` 用它；两者的 `render(model:force:)` 开头的 `guard panel.isVisible` 放开成 `PanelShow.shouldRender(isVisible:force:)`。办公室窗口：`AppModel.showOffice` 原来就是先 `office.render(model:force: true)` 再 `showWindow`，检查过，无需改。
- 回归测试：`Tests/BuddyOfficeTests/PanelShowTests.swift`：先渲染后显示的顺序、已显示不重复 orderFront、没出现的面板只在要出第一帧时才渲染。
- 修复前失败（骨架 = 旧顺序）：`PanelShowTests.swift:11:9: Expectation failed: (log → ["orderFront"]) == ["render", "orderFront"]`；`PanelShowTests.swift:23:9: Expectation failed: PanelShow.shouldRender(isVisible: false, force: true)`。
- 状态：已修（首帧不闪的真实观感只能真机看；顺序有测试）。

### B-006 [P3] 深链停用的提示卡文案被截断（spec-trace-ui 疑点 6，协调者补充）
- 根因：文案没按提示卡的宽度写，也没有测试量过。
- 现象：`JumpService` 那条说明文案长，ToastCard 单行最宽 220 pt，看图显示「…直接打开 Clau…」，「可在设置 → 数据源诊断里重新测试」看不到。
- 修法：`JumpService.onNotice` 改成（标题, 正文）两段，`JumpService.deepLinkDisabledNotice = ("深链跳转没有生效", "已改为直接打开 Claude，可在设置里重试")`，各一行放得下；`AlertCoordinator.text(for:)` 的「想用 X：命令（等你批准）」里工具名 / 命令来自数据、可以很长，新增 `AlertText.approvalBody(tool:command:fits:)`：放不下依次截短命令 → 去掉命令 → 截短工具名 → 退到「有个权限请求（等你批准）」，放得下的原样不变；`ToastFit.bodyFits` 用 ToastCard 自己产出的文字项 + TextRenderer 出图看有没有被省略号截断（没有改 ToastCard 的排版）。
- 回归测试：`Tests/BuddyOfficeTests/ToastTextTests.swift`：旧文案确实被截断（`truncated == [old]`）而新文案放得下；所有固定提醒文案（含 N = 2…99 的合并文案）放得下；13 组工具名 / 命令（含超长单词、超长中文、超长 MCP 名）的等批准文案放得下；放得下的原样不变；缩短顺序（注入 `fits`）。
- 修复前失败（真实量出来的截断）：`ToastTextTests.swift:48:13: Expectation failed: (Self.truncated(title: "会话", body: body) → ["想用 Bash：averyveryveryveryverylongsinglewordcommandwithnospaces（等你批准）"]).isEmpty → false`（另有 `some-very-long-command-name-here`、超长未知工具名、超长中文命令共 4 组）。
- 状态：已修。会话标题本身（用户 / 模型给的，最多 40 字）在提示卡里仍可能被省略号截断——那是 ToastCard 的设计（标题一行、省略号），没有改。

### B-007 [P3] 桌面宠物「每 2 秒检查 visibleFrame」+「指定某块屏幕」（spec-trace-ui U28 / C06b / U26c，协调者补充）
- 修法：见下面两条：每 0.5 秒比较一次 visibleFrame；`StripScreenPicker` 支持指定某块屏幕。
- 现象：宠物条缺「每 2 秒检查 visibleFrame」（Dock 改大小 / 移动而屏幕参数没变时不会跟着挪），也没有「指定某块屏幕」的入口。
- 根因：reposition 只有两个触发点（画布尺寸变化、屏幕参数通知）；屏幕选择只认「主屏幕 / 鼠标所在屏幕」。
- 每 2 秒检查 visibleFrame：见 A-006——`StripPanelController.poll()` 每 0.5 秒（比任务书要求的 2 秒更勤，成本只是一次 `NSScreen.screens` + 几个矩形比较）调一次 `repositionIfNeeded()`，`Placement`（位置 / 所在屏幕 / `visibleFrame` / 大小）变了才 `reposition()`；设置里改了「位置」「显示在」也立刻生效。所以「Dock 改大小 / 挪位置而屏幕参数没变」和「鼠标所在的屏幕跟着鼠标」都覆盖了。
- 指定某块屏幕：**实现了**（成本不高，没有列成偏离）。`Sources/BuddyOffice/ScreenPicker.swift`：纯函数 `StripScreenPicker.pick(pref:screens:mouse:)`——`main` / `mouse` / `id:<NSScreenNumber>|<名字>`（旧版本只写 `id:<n>` 也认）；先按 ID 找，重新插拔显示器 ID 变了就按名字找，都找不到（被拔掉）回主屏幕；`options(current:screens:)` 给设置页选择器（主屏幕 / 鼠标所在的屏幕 / 每块已连接的显示器，当前存的那块被拔掉时多一项「显示器：名字（未连接）」，选择器不会指向不存在的选项）。`StripPanelController.targetScreen` 用它；`SettingsView` 的「显示在」选择器列出已连接的显示器。
- 回归测试：`Tests/BuddyOfficeTests/ScreenPickerTests.swift`（4 个）：主屏幕 / 未知取值（含 `id:abc`、超出 UInt32、`ID:1`）→ 主屏幕；鼠标跟屏幕（含不在任何屏幕上）；按 ID → 按名字 → 拔掉回主屏幕、名字里带竖线；设置页选项永远包含当前值且 tag 不重复。
- 修复前失败：原来 `targetScreen` 里只有 `main` / `mouse` / `id:<n>`（无入口、不认名字）——新增纯函数，没有旧实现可对照，第一次跑就是绿的；设置页入口无法单测（SwiftUI）。
- 状态：已修（仅间接验证：真实多显示器插拔没法在这里做）。

### B-008 [P3] 强制保留的 Dock 图标：设置页显示和实际一致（spec-trace-ui 疑点 11，协调者补充）
- 现象：五个入口全关时强制保留 Dock 图标，但设置里的 ui.dockIcon 仍是「关」：设置页显示「关」，Dock 图标却在。
- 根因：强制保留只改了运行时状态，没有写回设置。
- 修法：`ApplyPlanner.settingsWriteBack(raw:effective:)`：入口被强制补上 Dock 图标时把 `ui.dockIcon` 也写成 true（`AppModel.applySettings` 执行）；设置页 `@AppStorage("ui.dockIcon")` 读的就是这个键，所以显示「开」。只在真的被强制时写，用户关掉 Dock 图标而别的入口还开着时不动。（和 A-024 一起：只剩一块空的宠物条时也算没有入口。）
- 回归测试：`ApplyPlanTests.aForcedDockIconIsWrittenBackSoTheSettingsPageDoesNotSayOff`（+ A-024 的 `aLoneEmptyPetStripIsNotAnEntryPoint` / `atLeastOneEntryIsAlwaysKept`）。
- 修复前失败（变异：写回函数返回空）：`ApplyPlanTests.swift:89:9: Expectation failed: (wb.count == 1 && wb[0].key == "ui.dockIcon" → false)`；`ApplyPlanTests.swift:94:13: Expectation failed: (s → BuddyOffice.Settings).bool("ui.dockIcon")`。
- 状态：已修。

### B-009 [P3] 被隐藏的 buddy 是否还提醒（spec-trace-ui 疑点 8、audit-app A-022 ③；**这是协调者定的选择**）
- 现象：被「隐藏这个 buddy」的会话仍会弹窗 / 响铃 / 计入 Dock 角标。
- 根因：AlertCoordinator.observe 收到的是未过滤的快照；任务书没规定隐藏后要不要提醒。
- 任务书 7.1 只写了「右键菜单有：隐藏这个 buddy」，没有写隐藏之后提醒怎么办。按协调者的指示选择「**隐藏 = 不打扰**」：被隐藏的 buddy 不弹窗、不响铃、不计入 Dock 角标 / 菜单栏「N 位同事在等你」、不让 Dock 弹跳；隐藏时他已经在提醒的，那条提醒立刻撤掉；重新显示时当作一段新的等待重新计时。
- 例外：① 白板上的「正」字照常数（那是「今天做完了几轮」，和提醒无关）；② 被隐藏的 buddy 仍算活会话（`AppModel.hasLiveSessions`，终端里的 claude 还在跑，A-010）。
- 修法：`AlertCoordinator.observe(... muted:)`（`AppModel.tick` 传 `settings.hiddenKeys`）；`AlertPipeline.run(... hidden:)`。
- 回归测试：`AlertCoordinatorTests.hiddenBuddiesAreMutedNoAlertNoBadgeNoBounce`、`hidingABuddyWhoIsAlreadyAlertingClearsTheAlert`、`aHiddenBuddysFinishedTurnsStillCountForTheWhiteboardButNeverAlert`；`AlertFallbackTests.aHiddenBuddyDisturbsNobodyButStillCountsAsALiveSession`。
- 修复前失败：`AlertCoordinatorTests.swift:394:9: Expectation failed: (c.waitingKeys → ["t:v", "t:h"]) == ["t:v"]`；`:396:9: (Self.posts(out).map { $0.key } → ["t:h", "multi"]) == ["t:v"]`；`:411:9: (Self.clears(hidden) == ["t:a"] → false)`；`:425:9: (Self.posts(out) → [(key: "t:h", kind: finished, …)])`。
- 状态：已修。**建议写进 DESIGN.md：「隐藏 = 不打扰（任务书未写）」**。

### B-010 [P1] FloatingPanel 的窗口出现 / 消失动画在工作线程上不返回 → 线程数随使用时间无限增长（协调者在 replay 长跑预演里发现）
- 现象：replay 长跑预演里 App 的线程数从 14 一路涨到 53，每弹一张提示卡涨一个；`sample` 看到每个多出来的线程都卡在 `-[NSAnimation _runBlocking] → NSRunLoop runMode → mach_msg`（`com.apple.root.user-interactive-qos` 工作线程）。长时间运行最终会耗尽线程。
- 根因：`FloatingPanel`（提示卡 / 悬停卡 / 小鱼缸 / 宠物条）没有关 AppKit 的窗口 order-in / order-out 动画（`animationBehavior` 默认 `.default`）；这些面板自己用弹簧滑动 / 直接显示隐藏，被反复 `setFrameOrigin`（提示卡 60 Hz、悬停卡每个 tick 定位），AppKit 的动画永远不返回，永久占住一个 GCD 工作线程。
- 修法：协调者在 `Sources/BuddyOffice/Panels.swift` 的 `FloatingPanel.init` 末尾加了 `animationBehavior = .none`（带注释）；提示卡（`ToastController.Toast.panel`）、悬停卡（`HoverPanelController.panel`）、小鱼缸、宠物条都是 `FloatingPanel`，一处覆盖。
- 同类用法检查（协调者要求）：`OfficeWindowController` 的窗口在人数变化时**不会** `setFrame`（只有 `setFrameAutosaveName` / 第一次运行 `center()` / 用户缩放，画面渲染进 `pixelView`，窗口大小不跟人数走）；设置窗口只在用户点开时 `showWindow`；源码里没有任何 `NSWindow.setFrame(_:display:animate:)`。也就是说「反复 setFrame 又 order」只有 `FloatingPanel` 一族，没有别的窗口需要处理。
- 回归测试：`Tests/BuddyOfficeTests/PanelAnimationTests.swift`（`@MainActor`，只建面板、不 orderFront）：`everyFloatingPanelHasWindowAnimationsTurnedOff`（`FloatingPanel(size:)`、`level: .statusBar`、`HoverPanelController().panel`、`ToastController.Toast(key:).panel`、`TankPanelController().panel`、`StripPanelController().panel` 全部 `animationBehavior == .none`）；`noWindowOtherThanTheFloatingPanelsIsRepeatedlyReframed`（源码审计：没有 `.setFrame(`；办公室窗口控制器里没有 `setContentSize` / `setFrameOrigin`）。
- 修复前失败（撤销那一行再跑）：`PanelAnimationTests.swift:11:9: Expectation failed: (FloatingPanel(size: NSSize(width: 100, height: 50)).animationBehavior → NSWindowAnimationBehavior(rawValue: 0)) == (.none → NSWindowAnimationBehavior(rawValue: 2))`，同样失败的还有 `:12`（statusBar 层）、`:13`（悬停卡）、`:14`（提示卡）、`:15`（小鱼缸）、`:16`（宠物条）共 6 处；恢复那一行后通过。
- 状态：已修。线程数不再涨的真实验证（replay 长跑 + `sample`）由协调者另外做。

---

## 三、P3（audit-app.md A-012 … A-029）

### A-012 [P3] 主线程上的 queue.sync 链：退出 / 切换演示 / 设置页诊断
- 根因：退出 / 切换演示 / 打开设置页诊断时，主线程用 `queue.sync` 等数据层队列（含后台 QoS 的扫描队列）当前这一批做完。
- 现象：主线程同步等 ingest 队列（utility）里当前的 `poll()` 结束；`stop()` 里再等 tokenscan 队列（background）当前的扫描批次 + 写盘。平时几十毫秒；后台优先级的线程在系统很忙时可能被饿住（有 QoS 提升，没实测）；最坏约等于一个大文件的扫描批次（首次全量 0.34–0.47 s，DESIGN.md 第 9 节）。表现是 ⌘Q 后转圈或点「演示模式」卡一下。（摘自 audit-app.md）
- 修法：`BoundedWait.run(timeout:_:)`（`BoundedWait.swift`）：退出时 `applicationWillTerminate` 把真实数据的 `provider.stop()` 放到后台、最多等 1.5 秒，超时就放弃 flush（下次启动从上次偏移继续读；两个文件都是原子写，退出时被打断也不会写坏）；演示的 `stop()` 仍在主线程（它的 Timer 在主线程）。`AppModel.setDemo` 里旧数据源的停止走可注入的 `stopProvider`（真实数据放后台、演示留主线程）。设置页诊断改成后台取 `provider.diagnostics()`（对 ingest 队列的 `queue.sync`）、回主线程拼文字（`DiagnosticsFormatter`）再回填（`AppModel.diagnosticsText { … }`）。
- 回归测试：`HousekeepingTests.aStuckStopCannotHoldTheMainThreadForLongerThanTheTimeout`（work 睡 1 秒、timeout 0.2 秒 → 返回 false 且只等了 < 0.6 秒、work 还没跑完）、`fastWorkFinishesBeforeWeReturn`、`diagnosticsTextListsEverythingTheSettingsPageShows`；`AppModelTests.switchingTheDataSourceResetsTheFirstDataFlagAndStopsTheOldOne`（旧数据源被停掉一次）。
- 修复前失败：无（新增行为，没有可对照的旧实现）。
- 状态：已修（仅间接验证：真实 `SessionStore.stop()` 在系统忙时的耗时没有量；超时只是上限）。

### A-013 [P3] NSAppleScript 在后台串行队列上执行、授权弹窗未答复时卡满 2 分钟
- 根因：`NSAppleScript.executeAndReturnError` 没有超时，且和「查宿主 App」共用同一个串行队列：授权弹窗没人答复时整条队列卡满约 2 分钟。
- 现象：(1) Apple 对 `NSAppleScript` 的线程安全没有保证（通常建议在主线程用）；(2) 自动化授权提示没有答复时，`executeAndReturnError` 最长阻塞约 2 分钟（DESIGN.md 第 2 节 M0 实测 `-1712`），它和「查宿主 App」共用同一个串行队列 `jump`，之后所有终端跳转排队等它（不影响主线程）。（摘自 audit-app.md）
- 修法：脚本包在 `with timeout of 5 seconds … end timeout` 里（自动化授权没人答复时最多 5 秒，之后照常 `activate` 宿主 App，只是没选中标签页）；「查宿主 App / 读 tty」（sysctl，很快）和「跑 AppleScript」拆成两个队列（`jump` / `jump.script`），脚本卡住不拖后面的终端跳转；tty 进脚本前校验 `^/dev/tty[A-Za-z0-9]{1,16}$`（来自 sysctl + `devname` 本来就安全，多守一道，脚本是字符串插值）；脚本生成抽成 `JumpResolver.terminalTabScript(tty:)`。
- 回归测试：`JumpTests.theTerminalScriptHasATimeoutAndOnlyAcceptsRealTTYNames`。
- 修复前失败（变异：去掉 timeout 包装）：`JumpTests.swift:127:9: Expectation failed: (script.hasPrefix("with timeout of 5 seconds") → false)`。
- 状态：已修（仅间接验证：真实的自动化授权弹窗 / Terminal 标签页选择没法在这里跑）。

### A-014 [P3] 主线程同步读取并解析全部 local_*.json
- 现象：每次点击桌面会话 buddy：3 层目录枚举 ×2 + 读 / 解析全部 `local_*.json` 一遍，2.5 秒后再枚举一次；提醒判定（`notify.suppressWhenFocused` 开、Claude 在最前）时也读全量。本机 41 个文件、共 695,699 字节（中位数 20,183 字节），估计每次 3–8 ms；随文件数线性增长，上千个会话时可到 100 ms 以上，点击瞬间会掉帧。（摘自 audit-app.md）
- 根因：没有复用 BuddyCore 里已有的、带缓存的 `DesktopMetaReader`（后台 `poll` 本来就在读这些文件），App 层另写了一套无缓存的。另外它绕过了 BuddyCore 里「拒绝 `.key` / `.sock`」的 `FileIO` 统一入口（这里的过滤 `hasPrefix("local_") && hasSuffix(".json")` 本身就碰不到 `.key` / `.sock`，所以不算违反红线，只是和 DESIGN.md「全部通过 FileIO 一个入口」的说法不一致）。（摘自 audit-app.md）
- 修法：`DesktopMeta.readAll()` 一次遍历读全部 lastFocusedAt，`mostRecentHost` 确定性取最新（并列取 id 最小）；`jumpDesktop` 点击时原来读 3 遍目录（before / wasLatest / 2.5 秒后），现在 2 遍；提醒判定（每个 tick 都可能问）走 `DesktopMeta.cache`（1 秒 TTL 的 `DesktopMeta.Cache`，读盘 / 时钟可注入），同一秒里问多少次只读一次盘。**没有**把读盘挪到后台线程（点击时那 1 次仍在主线程，3–8 ms 量级）、也没有改用 BuddyCore 里带缓存的 `DesktopMetaReader`（要给 `SnapshotProvider` 加接口，BuddyCore 在别人名下）。**后续（主线程收尾时）**：读目录 / 读文件改走 `FileIO.listDirectory / readAll`（数据层报告 C-032 的后半：绕过 FileIO），回归测试 `DesktopMetaFileIOTests`（源码审计 `theOfficeLayerReadsFilesOnlyThroughFileIO`：应用层没有绕过 FileIO 的读文件写法，修复前失败；FIFO 诱饵读不卡住；不碰全局的 FileIO 计数器，见 R2-005）。
- 回归测试：`Tests/BuddyOfficeTests/CachesTests.swift`：`mostRecentHostIsTheLargestLastFocusedAndTiesAreDeterministic`、`theMetadataCacheReadsOncePerSecondNotOncePerCall`（50 次询问只读 1 次、过 1 秒才重读、时钟回拨也刷新）、`aMissingHostIsNeverMostRecentlyFocused`。
- 修复前失败：无（新增缓存 / 纯函数）；原来每次调用 `isMostRecentlyFocused` 都重列目录读全部文件（读代码可见），现在同一秒内 0 次。
- 状态：已修（部分：见上「没有」）。

### A-015 [P3] DebugTools.log：旧式 API、世界可读的 /tmp、无界增长、`--test-jump` 会写会话标题、`NSLog` 把插值当格式串
- 根因：调试日志用会抛 ObjC 异常的旧式 FileHandle 接口、固定写世界可读的 /tmp 文件、无上限追加；开发开关还会把会话标题写进去；NSLog 把插值后的字符串当格式串。
- 现象：(1) `FileHandle.seekToEndOfFile()` / `write(_ data:)` 是会抛 Objective-C 异常的旧接口，磁盘满 / 文件被截断时是不可捕获的崩溃；(2) 日志固定写 `/tmp/buddy-office-debug.log`（默认 0644，世界可读；同机其他用户可预先放一个符号链接让 App 往别的自己有权限的文件里追加）；(3) 生产路径也会写（热键注册、自动收起）→ 无上限追加，热键开着时每次 `applySettings` 一行（见 A-016）；(4) `--test-jump` 分支把所有会话标题（可能含对话摘要）写进这个世界可读的文件，只在开发开关下发生，但没有任何提示；(5) 两处 `NSLog("… \(x)")` 把插值后的字符串当成格式串（`AppModel.swift:254` 的演示标题、`JumpService.swift:126` 的 AppleScript 错误字典）：字符串里有 `%` 时 `NSLog` 会按格式符去读不存在的参数（未定义行为）。目前前者是固定的演示假数据、后者几乎不会含 `%`，实际风险很小，但写法应该是 `NSLog("%@", msg)`。（摘自 audit-app.md）
- 修法：`DebugTools.write(_:toPath:maxBytes:)`：新式 `FileHandle` API（`seekToEnd` / `write(contentsOf:)` / `close` 都在 do-catch 里，所有失败静默放弃）、目录 0700 + 文件 0600、超过 1 MB 轮转成 `debug.log.1`（只留一份旧的）、路径是符号链接就不跟着写；默认路径改成 `~/Library/Logs/BuddyOffice/debug.log`（**PROGRESS.md 里还写着 `/tmp/buddy-office-debug.log`，需要你改**）；`DebugTools.enabled` 只在开发开关下为真（`--log-ui / --prof / --self-test / --probe-pid / --test-* / --dump-*`），发布版默认什么都不写；`--test-jump` 的两条日志用 `DebugTools.titleForLog`（只写字数）；两处 `NSLog("…\(x)")` 改成 `NSLog("%@", "…")`（`AppModel.jump`、`JumpService.selectTerminalTab`）。
- 回归测试：`Tests/BuddyOfficeTests/DebugLogTests.swift`（9 个）：追加到私有目录 / 私有文件（0600 / 0700）、轮转、符号链接不跟、各种失败不崩（路径下面是文件 / 只读目录 / 打不开的路径 / 空路径）、只有开发开关才启用、标题不进日志；源码审计：`DebugTools.log(` 的实参里没有 `.title`、没有 `NSLog` 的格式串里带插值（并有自检证明这个审计抓得到修复前的两种写法）。
- 修复前失败（变异：把 `write` 还原成旧的 `seekToEndOfFile` / `write` 实现）：`DebugLogTests.swift:14:6: Caught error: … "debug.log" couldn't be opened because there is no such file`（私有目录 / 权限）、`:30:9: Expectation failed: (cur → 15690) <= (2_000 → 2000)` 且没有 `.1`（无轮转）、`:44:9: Expectation failed: try String(contentsOfFile: target, …) == "原内容\n"`（符号链接被跟着写进了别的文件）。「写满盘时旧 API 抛 Objective-C 异常崩溃」在 macOS 上造不出来（没有 `/dev/full`），只做了「打不开 / 创建不了的路径不崩」的测试，旧 API 那条读文档 + 代码。
- 状态：已修。

### A-016 [P3] applySettings 被无差别重跑：热键反复重新注册 + 日志刷屏；`.settingsChanged` 死代码
- 根因：所有 UserDefaults 变化都无差别触发 `applySettings` 全量重跑（含热键的注销 / 重新注册和日志）。
- 现象：AppKit 自己写的窗口位置（拖动窗口的每一步）、每次「做完了」的 `tally.*`、设置页的每一次点击，都会触发最多 20 次 / 秒的 `applySettings`。热键开着时每次都：注销 → 重新注册（这一瞬间按热键会丢）→ 追加一行日志。它也是 A-003 的触发源。（摘自 audit-app.md）
- 回归测试：见下方各条里写的测试名。
- 修法与测试：见 A-003（`ApplyPlanner.plan(previous:current:window:)` 只处理变化的项，`nothingChangedMeansNothingToDo` / `onlyTheChangedEntriesAreTouched` 断言热键开着时无关的写入不会再注销 / 注册）。`Notification.Name.settingsChanged` 仍只有发送方、没有观察者——没删（`Settings.set` 发它，删了没有收益，留着不影响行为；有意留下）。
- 状态：已修（`.settingsChanged` 死代码保留）。

### A-017 [P3] wake() 没有速率上限
- 根因：鼠标移动事件每次都直接调 `wake()` 排下一拍，没有速率上限。
- 现象：`wake()` 在「下一拍还在 20 ms 之后」时把定时器提前到 1 ms 后。稳态间隔 33 ms；当鼠标事件间隔小于约 13 ms（≥ 75 Hz，如 120 Hz 的触控板），每个 mouseMoved 都会把下一拍提前，节拍跟着鼠标事件的频率（约 75–120 Hz，每拍都渲染办公室 + 小鱼缸 + 宠物条）。（摘自 audit-app.md）
- 修法：`TickPacer`（`TickPacer.swift`）：`wake()` 只能把下一拍提前到「上一拍之后满 1/30 秒」（`wakeDelay(now:)`），已排的下一拍距现在 ≤ 20 ms 时不动；`delayAfterTick` 让 tick 耗时超过间隔时也至少隔 4 ms（原来 1 ms 后背靠背，A-025 ⑧）。`AppModel` 用它。
- 回归测试：`TickPacerTests.aHighRateMouseCannotDriveTheTicksAboveThirtyFps`（离散事件模拟 75 / 120 / 240 / 1000 Hz 的鼠标事件持续 1 秒：tick 次数在 25…35 之间）、`wakingStillPullsALateTickForwardImmediately`、`aHeavyTickNeverSchedulesTheNextOneBackToBack`。
- 修复前失败（骨架 = 无速率上限）：`TickPacerTests.swift:35:13: Expectation failed: (n → 74) <= 35`（75 Hz）、`(n → 120) <= 35`、`(n → 240) <= 35`、`(n → 500) <= 35`（1000 Hz）；`:53:9: Expectation failed: (TickPacer.delayAfterTick(interval: 1.0 / 30, elapsed: 0.05) → 0.001) >= 0.004`。
- 状态：已修（真实 CPU 影响没量；逻辑有测试）。

### A-018 [P3] 只增不减的字典 / 键
- 根因：按会话 / 按天累积的字典和键没有清理路径。
- 现象：每个见过的会话 key（桌面会话 `d:` + hostSessionId 稳定，终端会话 `t:` + sessionId 每次 `claude` 一个新的）在进程生命周期内会留下约 0.5–1 KB（`prevActivity` 里的 `Activity` 还带着最多 160 字的工具 detail，比如 Bash 命令）。一天 100 个会话、跑一个月 ≈ 3 MB，不会撑爆内存，但是没有上界；`tally.YYYY-MM-DD` 每天一个键永不清理（本机偏好文件里已经有 2 个）；`hidden.keys` 只会增加。（摘自 audit-app.md）
- 修法：见下方各「已修」条目的写法。
- 回归测试：见下方各条里写的测试名。
- 已修：`AlertCoordinator.prevActivity / finished / lastAlert`（B-001）；`OfficeScene.seatedAt / lastApp`（A-008）；`VisualDirector.appearances`（超过 96 条只留在场的，A-027）；UserDefaults 的 `tally.YYYY-MM-DD`（`Settings.staleTallyKeys` / `pruneOldTallies`，启动时删 30 天前的和认不出日期的；测试 `HousekeepingTests.tallyKeysOlderThanThirtyDaysAreStale` / `pruningRemovesOnlyOurStaleTallyKeys`，变异后 `HousekeepingTests.swift:60:13: Expectation failed: (d.object(forKey: "tally.2026-01-01") → 5) == nil`）；`ScreenContent.staticCache`（超过 4096 条整体清空，`AppLayerFixTests.theStaticScreenCacheIsBounded`）。
- 不修：`hidden.keys`（用户每点一次「隐藏这个 buddy」加一项，一年最多几十项、每项几十字节；没有「这个会话已经不存在了」的可靠信号可以据此清理，清错了会让隐藏的 buddy 突然出现）；`PixelView.textLayers`（有界：峰值段数）。
- 状态：已修（除上面两项有理由不修）。

### A-019 [P3] 文案边界：空路径 / 负时间 / 空标题 / 英文原文
- 根因：显示文案默认字段非空、非负、带中文，没有考虑空路径、负时间、空标题、英文原文的边界。
- 现象：- hook 行被截断而走降级解析时 `detail` 是空串（`LineSanitizer.parseDegraded` 只抠 ts / ev / tool，DESIGN.md 说超过一半的事件文件里有被截断的中文字节），桌牌会显示「在读 」（尾随空格）、`在找 ""`、「在看 」、「在改 」、「在写 」。（摘自 audit-app.md）
- 修法：见下方各「已修」条目的写法。
- 回归测试：见下方各条里写的测试名。
- 已修（BuddyOffice 一侧）：所有显示标题的地方统一走 `AlertText.title`（空白标题用占位「（没有标题）」、换行换成空格、最多 40 字、隐私模式「会话」）——系统通知 / 提示卡（`AlertCoordinator`）、菜单栏菜单（`StatusItemController`）、右键菜单「跳转到「…」」（`AppModel.showContextMenu`）；测试 `AlertCoordinatorTests.titlesAreAlwaysDisplayable`（变异后 `AlertCoordinatorTests.swift:465:9: Expectation failed: (AlertText.title("", privacy: false) → "") == "（没有标题）"`）。`idleMinutes` 的负时间：协调者已在 PlateCopy 里处理（`wholeSeconds`）。
- **未修（在协调者名下的文件，按要求没动）**：`PlateCopy.toolText` 里 detail 为空串时的「在读 」「在找 ""」「在看 」「在改 」「在写 」（hook 行被截断走降级解析时会出现，建议每个类别在 detail 为空时退回「在读文件」这类无细节的说法，并在 `PlateCopyTests` 里断言各类别都没有尾随空格 / 空引号）；悬停卡里 `effort / permissionMode / modelName / statusDetail` 是英文原文（`HoverCard.swift`，同样在协调者名下）。
- 状态：已修（BuddyOffice 一侧）；PlateCopy / HoverCard 的部分转交。

### A-020 [P3] Int(Double) 对极端时间没有保护
- 根因：`Int(Double)` 对 NaN / 无穷 / 超出范围的值是运行时陷阱，从外部时间戳算出来的差值转 Int 前没有保护。
- 现象：`seconds` 来自 `now.timeIntervalSince(外部时间戳)`。ISO 串（≤ 9999 年）安全；hook 的 `ts` 走 `TimeUtil.date(ms:)`（不检查范围）、登记表的 `startedAt` 等走 `date(fromJSONMillis:)`（只检查 `isFinite && > 0`），一旦有 ≥ 约 9.2e21 毫秒的值（被写坏 / 被篡改的文件），`Int(±1e18 以上)` 陷阱崩溃。正常的 Claude 数据不会出现。（摘自 audit-app.md）
- 修法：新增 `safeInt(_:)`（`BuddyStage/SafeMath.swift`：NaN → 0，其余夹到 ±2^53）；`Performer.targetPose` 的 `Int(elapsed / 3)` 两处改用它；协调者在 `PlateCopy`（`wholeSeconds`）/ `HoverCard.ago` 里基于它做了另外几处；BuddyOffice 里 `HoverPanelController.CardKey` 用它取整时间戳。`FlickerScan` 的 `Int(fps)` 也用它（A-029）。
- 回归测试：`AppLayerFixTests.safeIntNeverTraps`、`aPerformerSurvivesInsaneToolTimestamps`（工具开始时间在 ±10^22 / 10^19 秒的 MCP / 未知工具）；`CachesTests.theHoverCardIsRebuiltOnlyWhenItsContentCanHaveChanged`（`Date(timeIntervalSince1970: .infinity)` 不崩）。
- 修复前失败：`Int(elapsed / 3)` 对 ±10^22 是运行时陷阱（Swift 语义，读代码确认；没有单独跑旧代码——`Performer.swift` 已经是协调者在改的文件）。
- 状态：已修。

### A-021 [P3] 演示模式的副作用
- 根因：演示模式和真实数据共用同一套提醒 / 白板计数出口，没有区分。
- 现象：演示剧本每循环一次有 2 次「做完了」（demo0 在 63 s、demo3 在 40 s），演示开着 1 小时会往真实的今日白板计数里加约 90；切换演示 / 真实数据时 `gotData` 保持 true，`snapshots = []` 到新数据到来前的 0.25–0.5 秒里，「今天还没人上班」的牌子会闪一下（`emptySign = model.gotData`）；演示模式下的提醒（声音、像素提示、系统通知）是真的发出去的。（摘自 audit-app.md）
- 修法：演示模式不计入真实的今日白板（`AlertPipeline.run(… demo:)`）；`setDemo` 里 `gotData = false`（换数据源之后、新数据到来之前不显示「今天还没人上班」牌子）。演示模式的提醒（声音 / 提示卡 / 系统通知）**保留**：DESIGN §8 用演示走到「等批准」来验证兜底提醒，静音会破坏这个自检；有需要可以另加开关。
- 回归测试：`AlertFallbackTests.demoModeNeverAddsToTheRealTally`；`AppModelTests.switchingTheDataSourceResetsTheFirstDataFlagAndStopsTheOldOne`。
- 修复前失败（变异：去掉 `gotData = false`）：`AppModelTests.swift:30:9: Expectation failed: (r.model.demo → true) && (!r.model.gotData → false)`。白板计数：原来 `settings.addTally()` 不区分 demo（读代码），新测试里 demo 的 `tallyToday() == 0`。
- 状态：已修。

### A-022 [P3] AlertCoordinator 的几处细节
- 根因：`AlertCoordinator.observe` 分支里的 `continue` 会跳过逐快照记账；合并提醒没有撤除路径；隐藏的 buddy 没有过滤。
- 现象：1. 等待状态的「延迟 / 被抑制」两个分支用 `continue`，同一轮循环里后面的 `prevActivity[s.key] = cur`、`finishedTurns`、`finished` 记账被跳过。多数情况没影响（waiting 时不会是 `.finished`），但「`.finished` → waiting（被抑制）→ `.finished`」之间 `prevActivity` 是旧值，会漏计 / 错计一轮。（摘自 audit-app.md）
- 修法：见下方各「已修」条目的写法。
- 回归测试：见下方各条里写的测试名。
- 见 B-001（① `continue` 跳记账 → 记账挪到循环最前面，有专门的 `waitingBranchNeverSkipsThePerSnapshotBookkeeping`——当前流程里这个缺陷不可观察，测试是特征测试；② 合并提醒不撤 / 点了没反应 / 文案 → 修；③ 隐藏的 buddy → B-009）。
- 状态：已修。

### A-023 [P3] 设置页显示和实际状态不同步；通知授权从不主动请求
- 现象：设置页里「通知授权状态」文字和「开机启动」开关显示的和系统真实状态不一致；通知授权从不主动请求（见 B-003）。
- 根因：授权状态读的是非观察的状态、不会自己刷新；登录项开启失败时开关没有回退。
- 修法：授权状态文字改成 `@State authText`，打开设置页 / 点「请求通知授权」之后 `notifier.refresh` 再刷新（原来读的是非观察状态，不会自己刷新）；开机启动开关：`LoginItem.set` 返回 `(note, isOn)`，开启失败开关回退成关，`SMAppService.requiresApproval` 不再说「已开启」而是「已提交登录项，还需要在「系统设置 → 通用 → 登录项与扩展」里允许」，打开设置页时按 `LoginItem.isOn` 对一次真实状态；强制补上的 Dock 图标写回 `ui.dockIcon`（B-008）；授权请求见 B-003。
- 回归测试：`HousekeepingTests.theLoginSwitchFallsBackToOffWhenEnablingFailed` / `aPendingApprovalIsNotReportedAsEnabled`；`NotificationAuthTests`；`ApplyPlanTests.aForcedDockIconIsWrittenBack…`。
- 修复前失败（变异：开关状态恒等于请求值）：`HousekeepingTests.swift:70:9: Expectation failed: !(LoginItem.switchState(requested: true, note: "开启失败：The file couldn’t be saved.") → true)`。
- 状态：已修（设置页视图本身无法单测，`SettingsView` 的接线读代码）。

### A-024 [P3] 只开「桌面宠物」且没有会话时，没有任何可点击的入口
- 现象：设置里把办公室窗口、小鱼缸、菜单栏图标、Dock 图标都关掉，只留桌面宠物（一个「纯宠物」的用法）。这时没有会话 → 宠物条是一块透明的、点穿的区域，没有任何可点的入口（也没有快捷键，除非手动开了热键）。恢复办法只有：重新启动 App（`applicationShouldHandleReopen` 会打开办公室窗口）或等有会话时右键 buddy →「设置…」。（摘自 audit-app.md）
- 根因：入口检查把「宠物条 / 小鱼缸可见」当成入口，但空的宠物条不可点。（摘自 audit-app.md）
- 修法：`ApplyPlanner.entryFallback(_:stripHasBuddies:initial:)`：只剩宠物条时，条里有人才算入口；一个人都没有（点穿的空白）也补上 Dock 图标。**`initial`（启动那一刻，第一批数据还没到）按「有人」处理**——否则纯宠物用法每次启动都会多出一个 Dock 图标；这是我为了不改变产品外观做的取舍，代价是「App 启动时就没有会话的纯宠物用户」在有会话之前仍然没有入口（会话出现、或用户再次点开 App，`applicationShouldHandleReopen` 会打开办公室）。
- 回归测试：`ApplyPlanTests.aLoneEmptyPetStripIsNotAnEntryPoint` / `atLeastOneEntryIsAlwaysKept`。
- 修复前失败（骨架 = 旧规则：宠物条一律算入口）：`ApplyPlanTests.swift:68:9: Expectation failed: (ApplyPlanner.entryFallback(strip, stripHasBuddies: false, initial: false) → FormInputs(office: fal…`（dock 仍是 false）。
- 状态：已修。**建议写进 DESIGN.md**：只剩空宠物条时强制补 Dock 图标（启动那一刻除外）。

### A-025 [P3] 性能陷阱合集
- 现象：几处每帧 / 每 tick 的性能陷阱：悬停卡片每 tick 重建、走路的人每帧新建 Canvas、菜单栏 toolTip 每次赋值、tick 背靠背、开机动画每帧世界大小的 Canvas 等。
- 根因：缓存 / 复用缺失，见下面各项。
- 修法：见下方各「已修」条目的写法。
- 回归测试：见下方各条里写的测试名。
- 已修：⑤ 菜单栏 toolTip 只在变化时赋值（`StatusItemController.update`）；⑧ tick 背靠背（`TickPacer.delayAfterTick`，A-017）；② 悬停卡片每 tick 重建（`HoverPanelController` 按 `CardKey`＝快照 + 秒 + 缩放 + 隐私 缓存，`CachesTests.theHoverCardIsRebuiltOnlyWhenItsContentCanHaveChanged`）；③ 走路的人每帧新建 Canvas（`WalkerSystem` 复用一张草稿）；④ `RoomRenderer.bake` 每像素 `Pal.dx(String)` 字典查找（地板 / 护墙板 / 墙纸的循环里把颜色取到循环外）。③④ 是纯重构：用 A/B 验证画面逐字节没变——把这两处还原成旧写法，`buddyctl golden` 的 12 条哈希与还原前逐行相同；`RenderingTests` 里局部重绘 == 整张重画、闪烁扫描、确定性等 100 多个用例通过。
- 不修：① `SeatRenderer.swift:283` 开机动画每帧世界大小的 Canvas、② 里 `OfficeScene` 悬停放置的多次 `HoverCard.make`、⑦ `Performer` 每帧分配——都在协调者名下的文件 / 段落里（按要求没动）；⑥ 宠物条 30 Hz 轮询：任务书 7.1 明确要求「每秒 30 次读取 `NSEvent.mouseLocation`」，是规格，不是缺陷。
- 状态：已修（除上面不修的）。耗时改善没有实测。

### A-026 [P3] 深链成功判据不检查 Claude 是否真的到了前台；已弃用的激活 API
- 根因：深链成功判据只看 `lastFocusedAt` 有没有变，没考虑目标本来就是最近聚焦的会话，也不检查 Claude 是否到了前台；用了已弃用的激活 API。
- 现象：目标会话本来就是 `lastFocusedAt` 最新的会话时（M0 发现的特例），2.5 秒后无条件算「成功」，不检查 Claude 是否被带到了前台；如果这种情况下深链只是「预热会话」而没有前置窗口（我无法验证），点 buddy 就什么也没发生，也不会走 `activateClaude()` 兜底。`NSApp.activate(ignoringOtherApps:)` 在 macOS 14+ 已弃用（行为是协作式激活，从非激活的 `.accessory` App 里打开设置窗口时可能不前置）。（摘自 audit-app.md）
- 修法：`JumpResolver.deepLinkVerdict(wasLatest:before:after:claudeFrontmost:)`：目标本来就是最近聚焦的会话（`lastFocusedAt` 不会变，M0 实测）仍不算失败，但 Claude 不在最前面就补一次 `activateClaude()`；`showSettings` 用 `NSApp.activate()`（macOS 14+ 的协作式激活，替换 `activate(ignoringOtherApps:)`）。
- 回归测试：`JumpTests.deepLinkVerdictAfterTwoAndAHalfSeconds`。
- 修复前失败（变异：`wasLatest` 时不补激活）：`JumpTests.swift:121:9: Expectation failed: (… deepLinkVerdict(wasLatest: true, before: 100, after: 100, claudeFrontmost: false) → DeepLinkVerdict(succeeded: true, activateClaude: false)) == (V(succeeded: true, activateClaude: true) …`。
- 状态：已修（前置行为只能真机验证）。

### A-027 [P3] 外观「不撞衫」把已离场的人也算进去、外观依赖出现顺序
- 根因：撞衫避让的候选集合包含已离场的人；避让后最终用的盐没有持久化，外观依赖出现顺序。
- 现象：`existing` 包含所有见过的会话（含已离场），发型×发色只有 64 种、衣服×颜色 60 种，会话多了之后新来的人几乎都撞衫，重试 24 次后取最后一次；最终的 salt 没有写回，所以同一个会话在不同次启动、不同出场顺序下的外观可能不同（DESIGN.md 说「外观种子盐（持久化）」）。（摘自 audit-app.md）
- 修法：见下方各「已修」条目的写法。
- 回归测试：见下方各条里写的测试名。
- 已修：`existing` 只取「现在在场的其他人」（`performers`，排除自己），缓存有界（A-007 / A-018）；测试 `appearanceCacheIsBoundedByWhoIsHereNotByWhoWasEverSeen`（400 个会话依次出现 / 离场，缓存 ≤ 100；红灯 `AppLayerFixTests.swift:216:9: (d.appearances.count → 400) <= 100`）。
- **未修**：撞衫避让后最终用的 salt 没有写回 identities（`Appearance.resolve` 返回的 salt 不持久化），所以同一个会话在不同次启动 / 不同出场顺序下的外观可能不同——要持久化只能改数据层（`IdentityResolver`），转交；**建议写进 DESIGN.md**：「外观种子盐（持久化）」实际是「基础盐持久化，撞衫后的调整盐不持久化」。
- 状态：已修（部分）。

### A-028 [P3] 时区 / 历法：DateFormatter 和 Calendar.current 的缓存
- 根因：日期键用当前 locale 的日历（佛历 / 日本年号下年份不同），DateFormatter 没固定 locale / calendar / 时区。
- 现象：(1) 白板计数的键是「当地日期字符串」，用户的历法不是公历（佛历 / 日本年号 / 伊斯兰历）时 `yyyy` 是那个历法的年份，切换系统语言 / 历法后键的格式变了，当天的计数从 0 重新开始；(2) App 跑好几天（设计目标）+ 跨时区旅行 / 系统时区变化时，`static let` 的 `DateFormatter` 和 `Calendar.current` 可能仍用旧时区（Foundation 需要 `resetSystemTimeZone` 才反映变化），白板跨天时间和窗外的天空会偏；夏令时切换那一天没有问题（只做格式化，没有按 86400 秒算日期）。（摘自 audit-app.md）
- 修法：白板计数的日期键用固定的公历 + `en_US_POSIX` + `TimeZone.autoupdatingCurrent`（`Settings.makeDayFormatter`，`locale` 在 `calendar` 之前设置）；`SceneClock` 用 `Calendar.autoupdatingCurrent`（跟着系统时区变）。
- 回归测试：`SettingsTests.dayKeysStayGregorianInAnyLocale`（佛历 / 日本年号 / 伊斯兰历 / 波斯历 locale 下都是 `2027-01-15`；太平洋时间的日期边界）。
- 修复前失败：`SettingsTests.swift:73:13: Expectation failed: (Settings.dayString(date, locale: Locale(identifier: id), timeZone: utc) → "2570-01-15") == "2027-01-15"`（佛历）、`→ "0009-01-15"`（日本年号）。
- 状态：已修（`SceneClock` 的时区跟随只能读代码，没有单测）。

### A-029 [P3] 开发工具参数没有校验；工具代码链接进了 App
- 根因：开发工具的命令行参数没有范围校验（负数、NaN、天文数字）；工具代码和 App 链接在同一个模块。
- 现象：只有开发者在命令行手动传非法参数才会触发，不影响用户；`FlickerScan / TextAudit* / AuditFixtures / StageCommands / StageRun` 全在 `BuddyStage` 库里，随发布版 App 一起链接（体积和攻击面，不影响功能）。（摘自 audit-app.md）
- 修法：见下方各「已修」条目的写法。
- 已修：`--demo-mode crowd5d-3`（away = -3 → `8..<5` 崩溃）、`crowd99999999`（分配几十 GB）→ 夹到 `n ≤ 200`、`away ≥ 0`；`--speed -1 / nan / inf`（`MockSource` 夹到 0.05…16）；`DemoScript.snapshots(mode:t:)` 的负数 / NaN / 天文数字时间；`FlickerScan` 的 `--fps 1`（滑窗 `f0 += win / 2` = 0 死循环）。
- 回归测试：`AppLayerFixTests.demoModesWithNonsenseParametersDoNotCrashOrExplode`、`aMockSourceWithNonsenseSpeedStaysSane`、`flickerScanWithATinyOrInsaneFrameRateTerminates`。
- 修复前失败（变异：还原旧写法）：`demoModesWithNonsenseParametersDoNotCrashOrExplode` → 测试进程崩溃（`exited with unexpected signal code`）；`AppLayerFixTests.swift:254:13: Expectation failed: (m.speed >= 0.05 → false)`、`:255:13: (m.scriptTime >= 0 → false)`；`flickerScanWithATinyOrInsaneFrameRateTerminates` → **死循环，150 秒不结束，被我杀掉**（用 python 子进程带超时 + 进程组 SIGKILL）。
- 不修：`StageCommands`（`--sleep-ms` 溢出、`--zoom 0`）、`PixelKit/TextRenderer.image(scale: 0)`——在协调者 / 文字审计名下的文件；把工具代码拆到 `BuddyStageTools` 目标只链接进 `buddyctl`——架构改动，不属于这次 QA 修复范围（只影响体积和攻击面，不影响功能）。
- 状态：已修（除上面不修的）。

---

## 四、只能间接验证的项（没有对本 App 的 computer-use 授权：不截屏、不操控别的 App、不点真实的系统弹窗）

| 项 | 为什么只能间接 | 间接证据 |
|---|---|---|
| A-002 真实鼠标点击是否被「窗口拖动」吞掉；手动 `performDrag` 的拖动手感 | 合成的 `NSEvent` 不走 WindowServer 的「窗口拖动」判定，没法用真实鼠标 | `mouseDownCanMoveWindow == false` 单测（`PixelView` / `PixelButton` / 三个标题栏按钮）；`mouseDownAction` 纯函数；合成 `NSEvent` 走 `PixelView.mouseDown` 的单测；进程内 `--test-tank-click` 经 `NSWindow.sendEvent` 单击背景 / 双击背景 / 点小人全部 PASS。**旧配置下进程内自检也没有复现「点击被吞」**（见 A-002），所以这条只能说是防御性修复 |
| A-003 用户真实手势（点黄色最小化按钮 / ⌘M / ⌘H）之后的窗口行为 | 不能操作真实窗口手势 | 进程内真实窗口 A/B：`--test-minimize`（旧判定 FAIL、新判定 PASS）+ 独立探针证实 AppKit 行为（`showWindow` + `orderFrontRegardless` 会把最小化窗口弹回来）；⌘H（`NSApp.isHidden`）只有纯函数测试 |
| A-006 / B-007 / B-005 多显示器、Dock 改大小 / 挪位置、鼠标换屏幕、窗口出现时首帧不闪 | 造不出真实的显示器变化；不能截屏看首帧 | `origin(...)` / `needsReposition` / `StripScreenPicker` / `PanelShow` 纯函数测试 |
| B-001 提示卡真实滑入 / 收回的观感、Dock 角标和弹跳、菜单栏图标的真实样子、提示音 | 不能看屏幕、不能听 | `AlertFallbackTests`：假通知中心（`.denied`）+ 假提示卡 + 假 Dock + 图标种类，逐项断言 + 变异检查证明测试抓得到兜底失效；`ToastTextTests` 用 CoreText 量真实文字宽度；DESIGN §8 记录过一次真实演示 |
| B-003 真实的系统通知授权弹窗（用户已经拒绝过一次） | 系统弹窗不能操控，也不该再弹一次 | `NotificationAuthTests`：假通知中心，覆盖第一次主动打开 / 后台不问 / 已答复不问 / 问过不再问 / 非 App 包 |
| B-002 / A-013 / A-026 真实深链、AppleScript 选终端标签页、Claude 被带到前台 | 需要真实 Claude / Terminal 和自动化授权 | `JumpResolver` 纯函数（目标 / 深链 URL / 2.5 秒判定 / 脚本文本与超时 / tty 校验）单测；DESIGN §8 的 `--test-jump` 记录 |
| B-004 真实 `didTerminateApplicationNotification`、真的 `NSApp.terminate` | 不能退出用户的 Claude、不能 kill 进程 | 假定时器 + 假「退出自己」的单测（60 秒 / 活会话 / 开关 / 取消 / 替换）+ 源码审计（AutoQuit 里只有 `self.terminate()` 和 `NSApp.terminate(nil)`）；`--test-autoquit N` 沿用 |
| A-012 真实 `SessionStore.stop()` 在系统忙时的阻塞时长 | 没量 | 只验证「超时机制」（`BoundedWait`：睡 1 秒的 work 只等 0.2 秒） |
| A-023 `SMAppService` / LaunchAgent 的真实注册 | 会往用户登录项里加东西 | 只测状态映射 / 开关回退（`LoginItem.note` / `switchState`） |
| A-017 / A-025 CPU 和耗时的真实改善 | 没有跑 `scripts/measure.sh` / `buddyctl bench` | 调度规则 / 缓存命中次数的单测；A/B 证明两处重构画面逐字节不变 |
| A-028 时区 / 历法在真实系统设置改变时的表现 | 不能改系统设置 | 日期键的 locale 参数化单测（佛历 / 日本年号 / 伊斯兰历 / 波斯历） |
| 设置页本身（`SettingsView`）的接线：「下次启动生效」说明、授权状态刷新、登录开关回退、屏幕选择器 | SwiftUI 视图没法在单测里驱动 | 读代码；背后的纯函数都有测试；`--dump-settings` 仍可出图 |

## 五、建议写进 DESIGN.md 的偏离条目 / 决定

1. **设置里「空闲 / 睡着 / 最近 N 小时 / 最多保留」四项：下次启动生效**（「最多保留」调小立刻生效）。原因：`SessionEngine.Options` / `SessionStore.options` 是 `let`，热更新要改 BuddyCore。设置页已写明。（A-001）
2. **隐藏 = 不打扰**：被隐藏的 buddy 不弹窗 / 不响铃 / 不进 Dock 角标和菜单栏计数 / 不让 Dock 弹跳；白板照数；仍算活会话（自动收起不能把他当成没有会话）。任务书未写，按协调者的指示。（B-009 / A-010）
3. **使用说明：「点小人（或桌牌）」→「点小人」**：桌牌没有命中 ID，点不了；选择改文档而不是让桌牌可点。（B-002）
4. **只剩空的桌面宠物条时强制补 Dock 图标**（启动那一刻除外），并把 `ui.dockIcon` 写回设置，设置页显示和实际一致。（A-024 / B-008）
5. **通知授权**：第一次「App 在前台且办公室窗口可见」时请求（`applicationDidBecomeActive` + `showOffice`）；后台启动（`open -g`）不问；被拒 / 已答复 / 问过一次之后不再自动弹（`notify.authRequested` 标记）；设置页按钮不受限。（B-003）
6. **提醒细节**：Dock 弹跳和弹窗共用 1.5 秒去抖；终端会话「做完了」在宿主 App 在最前面时也先等 8 秒再判断；等 8 秒后发的「做完了」若下一轮已经开始就不发；合并提醒按种类说「N 位同事在等你 / 做完了 / 有事找你」，「在等你」类的合并提醒在所有被合并的人都不再等时撤掉，点它打开办公室。（B-001）
7. **提示卡文案保证一行放得下**：深链停用说明改成 标题「深链跳转没有生效」+ 正文「已改为直接打开 Claude，可在设置里重试」；等批准的「想用 X：命令（等你批准）」放不下时依次截短命令 → 去掉命令 → 截短工具名 → 通用文案。（B-006）
8. **深链 2.5 秒判定**：目标本来就是最近聚焦的会话时仍不算失败（M0），但 Claude 不在最前面就补一次激活。（A-026）
9. **桌面宠物**：位置 / 显示在改了立即生效；每 0.5 秒（任务书写 2 秒）检查 `visibleFrame` / 鼠标所在屏幕；新增「指定某块屏幕」（设置页列出已连接的显示器，按 ID 和名字记住，被拔掉回主屏幕）。（A-006 / B-007）
10. **小鱼缸拖动**：`isMovableByWindowBackground` 改成 `PixelView` 在背景单击时手动 `performDrag`；`PixelView` / `PixelButton` 的 `mouseDownCanMoveWindow` 为 false。（A-002）
11. **日志**：`~/Library/Logs/BuddyOffice/debug.log`（0600，1 MB 轮转），只在开发开关下写，不写会话标题（PROGRESS.md / DESIGN §8 里的 `/tmp/buddy-office-debug.log` 要改）。（A-015）
12. **演示模式**不计入真实的今日白板；演示模式的提醒（声音 / 提示卡 / 系统通知）保留。（A-021）
13. **外观「不撞衫」只和在场的人比**；撞衫后的调整盐不持久化（同一个会话在不同次启动下外观可能不同），要持久化需要数据层配合。（A-027）
14. **自动收起的已知限制**：到点时条件不满足（还有会话）不会重新武装。（B-004，沿用原设计）
15. **新增自检开关**：`--test-minimize`、`--test-tank-click`（`SelfTests.swift`）；`--test-titlebar` 改成经 `NSWindow.sendEvent` 分发；开发开关集合（会打开日志）：`--log-ui / --prof / --self-test / --probe-pid / --test-* / --dump-*`。
16. **Package.swift**：新增测试目标 `BuddyOfficeTests`（依赖 BuddyOffice / BuddyStage / BuddyCore / PixelKit / BuddyArt）。

## 六、转交 / 建议（不在我能动的文件里，或需要别人决定）

1. **BuddyCore（数据层那位）**：① A-011：输出快照前把 `seat` 夹到 `0..<64`（超过的重新分配最小空位），`IdentityResolver.load` 丢弃 `seat < 0 || seat > 999` 的持久化值，并加测试（identities.json 里放 `seat: 999999999`，之后才出现的会话拿到的 seat ≤ 63）——App 层已经三道防线（`SeatSanitizer` / `OfficeLayout` / `hitID`），但 Core 应该自己守住；② A-001：`SessionStore` 加 `applyConfig(dozeAfter:sleepAfter:dormantMax:dormantRecent:)`（在 ingest 队列上改引擎阈值，别重建引擎），App 就能把「下次启动生效」升级成实时生效；③ A-027：撞衫避让后的 salt 写回 identities；④ A-014：`SnapshotProvider` 暴露 `lastFocusedAt(host:)`，App 层的 `DesktopMeta` 就可以整个去掉。
2. **PlateCopy / HoverCard（协调者）**：A-019：`PlateCopy.toolText` 里 detail 为空串时的「在读 」「在找 ""」「在看 」「在改 」「在写 」（hook 行被截断走降级解析时出现）——每个类别在 detail 为空时退回无细节的说法，`PlateCopyTests` 断言各类别都没有尾随空格 / 空引号；悬停卡的 `effort / permissionMode / modelName / statusDetail` 英文原文。
3. **SeatRenderer / OfficeScene 悬停放置 / Performer（协调者）**：A-025 ① 开机动画每帧世界大小的 `Canvas` 草稿、② 悬停放置最坏的多次 `HoverCard.make`、⑦ `Performer` 每帧分配。
4. **StageCommands / TextRenderer（文字审计那位）**：A-029 剩下的：`--sleep-ms` 溢出、`--zoom 0`、`TextRenderer.image(scale: 0)`。
5. **golden.txt**：整套测试里唯一的失败是 `RenderingTests.goldenFrameHashesAreStable`（12 条哈希与 `Tests/BuddyStageTests/golden.txt` 不一致）——来自协调者后来的画法改动（关机渐变 / 指示灯 / 桌牌等，golden.txt 04:21 更新，之后还在改）。我的两处 BuddyStage 重构（`RoomRenderer.bake` 取值提到循环外、`WalkerSystem` 复用草稿画布）做过 A/B：把它们还原成旧写法，`buddyctl golden` 的 12 条哈希与还原前逐行相同——所以不是我的改动造成的；画法稳定之后需要 `buddyctl golden --update`（先亲眼看过新画面）。
5b. **PROGRESS.md**：「App 调试参数」里日志路径 `/tmp/buddy-office-debug.log` 已经不对（见上 11），并可以补上 `--test-minimize` / `--test-tank-click`。
6. **BuddyCoreTests 的 chain1**（检查 RealProvider.swift 源码结构）：断言早已被它的作者更新成 `SessionStore(options:` / `SessionEngine.Options(paths:` / `SessionStore.Options(engine:`，和现在的 `RealProvider` 一致、通过；「把 `--data-root` 传进去」这层意图我没有去改那份测试，而是在 `EngineConfigTests.theDataRootArgumentReachesTheEngine` 里从行为上断言（`--data-root /x/fake-home/` → `store.options.engine.paths == Paths(home: "/x/fake-home")`，不给就是 `Paths.real`），并断言 `RealProvider.swift` 里有 `DebugTools.opt(args, "--data-root")` 和 `Paths(home:`。

## 七、构建与测试汇总（2026-09-29）

- 用自己的编译目录 `.build-app`（先整个删掉重来）：`BUDDY_SCRATCH=.build-app scripts/dev.sh build` → debug 干净编译 115 秒，**0 警告**；`… build -c release` → 127 秒，**0 警告**。
- `BUDDY_SCRATCH=.build-app scripts/dev.sh test`（整套：BuddyCore + BuddyStage + BuddyOffice）：**632 个测试 / 70 个套件，其中只有 `RenderingTests.goldenFrameHashesAreStable` 失败**（原因见「转交」5，不是我的改动）；其余全部通过，包括数据层那两位新加的 StateRule / Fuzz 系列。
- 我新增：`Tests/BuddyOfficeTests`（23 个套件、141 个 `@Test`，含参数化）+ `Tests/BuddyStageTests/AppLayerFixTests.swift`（19 个 `@Test`）——共 **160 个 `@Test`**。我的测试文件在 debug 构建里 0 警告。
- 「修复前失败」证据的三种取法：① 旧行为骨架 / 旧 API 直接红（陷阱类单独跑，记下崩溃）；② 变异（临时把修法还原成旧写法，取红灯行，然后恢复——所有变异都已恢复，文件与修复后一致）；③ 真实 AppKit A/B（A-003）。没有旧实现可对照的新增行为（BoundedWait、DesktopMeta.Cache、ScreenPicker……）在各条里写明「无」。
- 运行时痕迹：我的单测原来会在 `~/Library/Preferences` 里留下 `local.buddy-office.tests.<UUID>.plist`（53 个，已全部删除；`Fx.Store` 现在把偏好文件放在临时目录并在清理时删除）；GUI 自检用裸可执行文件跑，写进了 `BuddyOffice` 域（窗口位置等，已删掉我写的 `tank.opacity` / `tally` 两个键）和 `~/Library/Logs/BuddyOffice/debug.log`（0600）。
- 有一次为了清理挂死的测试进程用了 `pkill -f BuddyOfficePackageTests.xctest`（按名字），**可能误杀过别人同时在跑的测试进程**（名字对所有 scratch 目录都一样）；之后只按自己的 pid / 进程组 kill。
