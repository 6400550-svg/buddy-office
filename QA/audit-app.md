# 应用层代码审查报告（audit-app）

- 审查范围：`Sources/BuddyOffice`、`Sources/BuddyStage`、`Sources/PixelKit`、`Sources/BuddyArt`、`Sources/buddyctl`（+ `buddydump`，11 行）共 90 个 Swift 文件（约 15k 行）。
  `BuddyCore` 不审，只读了被 App 层调用的 API 的线程 / 阻塞语义（`SessionStore` / `SessionEngine.shutdown/diagnostics` / `TokenLedger.flush` / `IdentityResolver` / `Paths` / `FileIO` 的写入点 / `TimeUtil`）。
- 方法：逐文件通读 + 全量 grep（`!`、`try!`、`as!`、`fatalError`、`precondition*`、每一处 `Int(`、`nonisolated(unsafe)`、`static var`、`Timer`、`addObserver`、`NSTrackingArea`、`NSPanel(`、`FileHandle`、日志输出、网络 / 进程 / 路径引用、所有字典 / 数组成员）+ 对照 DESIGN.md / PROGRESS.md。
- 铁律遵守情况：只读；没有编译、没有运行 App / 测试、没有联网、没有打开 `~/.claude/sessions/*.key`、`/tmp/cc-socks/*.sock`，没有读任何凭据，没有改 `~/.claude` 下任何东西；唯一写入的文件是本报告。为估算「主线程扫描桌面会话元数据」的耗时，只对 `~/Library/Application Support/Claude/claude-code-sessions` 做了文件个数 / 字节数的统计（`find` + `stat`，没有读文件内容）。读了本 App 的偏好设置文件 `~/Library/Preferences/local.buddy-office.plist`（3 个键：窗口位置和两天的白板计数），没有改。
- 审查日期：2026-09-29（03:00–03:40）。最后一次检查源码修改时间（03:33）时，只有 `StageCommands.swift` 和 `TextAuditRunner.swift`（都是开发工具）还在变，不影响下面的结论。

## 0. 先读这一段

**统计：发现 29 个，其中 P0 0 / P1 3 / P2 8 / P3 18。**

严重度说明（按可达性校准）：P0 = 正常使用下就会崩溃 / 数据损坏 / 违反安全红线；P1 = 明显错误的行为；P2 = 边界条件下的错误或资源问题；P3 = 小瑕疵 / 代码卫生。**只有「手动改偏好设置文件」才能触发的崩溃我记为 P2 而不是 P0**（A-004、A-005），因为正常使用（设置页的控件都有范围限制）到不了；如果你们想把「设置被外部写坏」也算 P0，把这两条升级即可。没有发现违反安全红线的地方（第 2 节第 10 项有逐条证据）。

**源码在审查期间被同时修改**（开发者在做 text-audit 相关的修复）。我记录了三次 mtime 快照（scratchpad 里的 `mtimes-1/2/3.txt`）。审查期间有改动的文件：`BuddyStage/{OfficeLayout,OfficeScene,HoverCard,PlateCopy,SeatRenderer,TextAudit,TextAuditRunner,StageCommands,AuditFixtures}.swift`、`BuddyArt/Workstation/SeatGeometry.swift`、`PixelKit/{TextRenderer,PixelFont,Frame}.swift`、`BuddyOffice/{OfficeWindowController,PixelView}.swift`、`buddyctl/main.swift`。这些文件我在最后（03:25）又重读 / 重新 grep 过与发现相关的部分，**结论对应 03:25 的版本**；`BuddyOffice` 其余文件、`Canvas.swift`、`Palette.swift` 等在审查期间没有改动。行号是 03:25 的行号，`BuddyStage` 里几个还在被改的文件（`OfficeScene.swift`、`StageCommands.swift`）行号可能继续漂移，以函数名为准。有一处已经被开发者顺手修掉（`office.zoom` 设成 99 / 负数 / 极大值不再有问题：`OfficeWindowController.render` 现在走 `OfficeLayout.effectiveZoom`，见第 2 节第 2 项）。

### P0–P2 标题清单

| 编号 | 严重度 | 标题 | 位置 |
|---|---|---|---|
| A-001 | P1 | 设置页里「打盹 / 睡着 / 最近 N 小时 / 最多保留 >4」四项完全没有接到数据层，改了不生效 | SettingsView.swift:30-33,96-101；Settings.swift:17-18；RealProvider.swift:9 |
| A-002 | P1 | 小鱼缸和标题栏三个像素按钮：真实鼠标点击可能被「窗口拖动」吞掉（可能，需真机确认） | TankPanelController.swift:30；PixelView.swift；TitleBarButtons.swift:44-75 |
| A-003 | P1 | 最小化的办公室窗口会在任何一次设置写入（含每次「做完了」的白板计数）之后被弹回来（可能） | AppModel.swift:98-101,130；Settings.swift:45-50 |
| A-004 | P2 | `dormant.max` 为负数 → `prefix(-1)` 崩溃，启动即崩、之后每次启动都崩 | AppModel.swift:56-60 |
| A-005 | P2 | 今日白板计数 ≤ -5 → `drawTally` 的 `0..<负数` 崩溃；`addTally` 在 Int.max 时溢出 | RoomRenderer.swift:302-322；Settings.swift:36-50 |
| A-006 | P2 | 桌面宠物「位置 / 显示在」改了不立即生效（`reposition()` 只有两个触发点） | StripPanelController.swift:52,110-125,136-157 |
| A-007 | P2 | 「换个造型」：坐着的 / 走路的 / 重启后的造型三者不一致，用户挑中的造型重启后丢失 | VisualDirector.swift:40；AppModel.swift:263 |
| A-008 | P2 | 同一会话第二次走进办公室：座位上已坐着人，门口又走进来一个「分身」（`seatedAt` 从不清） | OfficeScene.swift:52,183,206,215 |
| A-009 | P2 | `Canvas.writeBGRA` 在 crop 与画布不相交时退化成整张画布 → 潜在的 IOSurface 越界写（当前调用点不可达） | Canvas.swift:329-338；PixelView.swift:98-101 |
| A-010 | P2 | 「跟着 Claude 一起收」把被隐藏的 buddy 当成没有会话：还有活会话时也会自动退出 | AppModel.swift:95；SystemHelpers.swift:31-38 |
| A-011 | P2 | 座位号没有上限：被写坏的持久化座位号会让办公室分配天文数字的数组 / 画布（可能） | OfficeScene.swift:136-139,197；OfficeLayout.swift:37-53；IdentityResolver.swift:147-153 |

建议的处理顺序：先做 A-004 / A-005（5 分钟，全部读外部值的地方加范围夹取）；A-002 / A-003 先用文中的自检办法在真机上确认一次，确认后修法都很小；A-001 决定是「接线」还是「先从设置页拿掉」；A-006 / A-007 / A-008 是用户能直接看到的行为缺陷。

---

## 1. 发现

### A-001 [P1] 设置页里「打盹 / 睡着 / 最近 N 小时 / 最多保留 >4」四项完全没有接到数据层
- 位置：`BuddyOffice/SettingsView.swift:30-33`（`@AppStorage`）、`:96-101`（四个 Stepper）；`BuddyOffice/Settings.swift:17-18`（默认值）；`BuddyOffice/RealProvider.swift:9`；`BuddyOffice/AppModel.swift:56-60`；`BuddyCore/Fusion/SessionEngine.swift:15-19`（引擎自己的默认值）。
- 现象 / 触发条件：设置 → 其他 → 「空闲多久后打盹」「空闲多久后睡着」「启动时只显示最近 N 小时内的会话」调了之后什么都不变（打盹仍是 10 分钟、睡着仍是 45 分钟、下班工位仍取最近 3 小时）；「最多保留：N 个」调到 5–8 也不生效：引擎自己只保留 4 个（`dormantMax = 4`），App 只是在显示时再 `.prefix(N)`，所以只能变少不能变多。DESIGN.md 第 4 节写着「空闲 10 分钟打盹、45 分钟睡着（设置里可改）」，和实现不符。
- 根因：`SnapshotProvider` 协议没有配置入口；`RealProvider.make` 只传 `dataRoot / usePolling / persist`，`SessionStore` 用 `SessionEngine.Options` 的默认值；`idle.dozeMinutes`、`idle.sleepMinutes`、`dormant.recentHours` 在整个 Sources 里只出现在 `SettingsView`、`Settings` 的默认值和一条注释里（grep 验证过），没有任何消费者。
- 建议修法（最小）：`RealProvider.make` 读 `Settings`，把 `dozeAfter / sleepAfter / dormantMax / dormantRecent` 填进 `SessionEngine.Options`（夹到合法范围）——这样「下次启动生效」，并在设置页写明；要实时生效就给 `SessionEngine` 加可变阈值，经 ingest 队列更新。不想做就先把这三项从设置页拿掉或置灰，避免误导。
- 建议的回归测试：把「Settings → Options」的映射抽成纯函数（如 `EngineOptionsFactory.make(dozeMinutes:sleepMinutes:dormantMax:dormantHours:)`），单测：`3 分钟 → dozeAfter == 180`、0 / 负数 / 巨大值被夹住、sleep ≥ doze + 1；端到端沿用现有 `ActivityResolverTests` 的 fixture（`dozeAfter` 很小 → `.dozing`）。
- 把握程度：确认。

### A-002 [P1] 小鱼缸和标题栏三个像素按钮：真实鼠标点击可能被「窗口拖动」吞掉
- 位置：`BuddyOffice/TankPanelController.swift:30`（`panel.isMovableByWindowBackground = true`）；`BuddyOffice/PixelView.swift`（没有覆盖 `mouseDownCanMoveWindow`，`isOpaque` 也是默认的 false）；`BuddyOffice/TitleBarButtons.swift:44-75`（`PixelButton` 同样没有覆盖）；自检 `AppDelegate.swift:72-95` 的 `runTitlebarTest` 是直接调用 `b.mouseDown(with:)`，没走 NSWindow 的事件分发。
- 现象 / 触发条件：`NSView.mouseDownCanMoveWindow` 的默认值等于 `!isOpaque`，即 `PixelView` / `PixelButton` 是 true。小鱼缸面板开了「按住背景拖动」，据 AppKit 的行为（这是一个常见的坑；SDK 头文件里只写了「server-side dragging via titlebar or background」），落在这种视图上的左键按下会被当作窗口拖动的起点，`mouseDown` 不再交给视图。结果：在小鱼缸里点小人跳转、双击背景回到办公室，以及办公室标题栏里「缩成小鱼缸 / 桌面宠物 / 设置」三个按钮，都有可能收不到点击。右键不受影响（不是拖动手势）。
- 根因：`--test-titlebar`、`panelsSelfTest` 都是「直接调视图方法」或「读命中缓冲」，从来没有走过 `NSWindow.sendEvent` → WindowServer 的这条路；DESIGN.md 第 10 节也写了 GUI 点击只能间接验证。
- 建议修法：`PixelView` 和 `PixelButton` 覆盖 `override var mouseDownCanMoveWindow: Bool { false }`；小鱼缸想「拖背景」就手动做：`PixelView.mouseDown` 里 `hitID == 0 && clickCount == 1` 时 `window?.performDrag(with: event)`，双击 / 命中小人走 `onClick`，同时把 `isMovableByWindowBackground` 改回 false。这个覆盖没有副作用，即使最后发现没有这个问题也值得加。
- 建议的回归测试：单测断言 `PixelView(frame: .zero).mouseDownCanMoveWindow == false`、`PixelButton(icon:tip:).mouseDownCanMoveWindow == false`；自检里把 `--test-titlebar` 改成经 `window.sendEvent(_:)` 注入合成的 `NSEvent`（不直接调 `mouseDown`）。WindowServer 一侧的真实行为只能真机点一下确认（用户点一次小鱼缸里的人 / 标题栏按钮即可）。
- 把握程度：可能（小鱼缸约 85%，标题栏约 65%；没法运行 GUI 验证）。

### A-003 [P1] 最小化的办公室窗口会在任何一次设置写入之后被弹回来
- 位置：`BuddyOffice/AppModel.swift:98-101`（监听 `UserDefaults.didChangeNotification`）、`:130`（`if officeOn { if !(office.window?.isVisible ?? false) { showOffice(...) } }`）、`BuddyOffice/Settings.swift:45-50`（`addTally` 写 UserDefaults）。
- 现象 / 触发条件：用户把办公室窗口最小化到 Dock（`office.visible` 仍是 true）。之后只要 UserDefaults 有任何变化——某个会话做完一轮（`addTally` 写 `tally.<日期>`）、AppKit 保存小鱼缸位置、改任何设置——`applySettings` 会看到最小化的窗口 `isVisible == false`，调用 `showOffice()` → `showWindow` + `orderFrontRegardless()`，把窗口从 Dock 里弹回来（窗口菜单里有「最小化」⌘M，很容易触发）。通过 Dock 右键「隐藏」把 App 隐藏之后同理（`NSApp.isHidden` 时窗口也不是 visible）。
- 根因：把「窗口不可见」当成「被关闭了」，没有区分最小化 / 隐藏 / 关闭；`applySettings` 对所有键的变化都无差别重跑（见 A-016）。
- 建议修法：`applySettings` 里遇到 `office.window?.isMiniaturized == true` 或 `NSApp.isHidden` 时跳过；更根本的做法是记住上一次应用的设置值，只有 `office.visible` 这个键自己变了才去 order 窗口。
- 建议的回归测试：加一个自检开关 `--test-minimize`（仿 `--test-titlebar`）：最小化 → `settings.set(0.9, "tank.opacity")` → 0.3 s 后断言 `isMiniaturized == true`；或者把判断抽成纯函数 `shouldOrderOfficeFront(officeOn:isVisible:isMiniaturized:appHidden:)` 单测。
- 把握程度：可能（约 75%：取决于「最小化窗口的 `isVisible` 为 false」和「`showWindow` 会取消最小化」两条 AppKit 行为，需要跑一次确认）。

### A-004 [P2] `dormant.max` 为负数 → `prefix(-1)` 崩溃，启动即崩
- 位置：`BuddyOffice/AppModel.swift:56-60`（`refreshDerived`：`.prefix(settings.int("dormant.max"))`）；`BuddyOffice/Settings.swift:25`（`int()` 不做任何范围限制）。
- 现象 / 触发条件：`defaults write local.buddy-office dormant.max -int -1`（或偏好设置文件被写坏）。`Array.prefix(_:)` 对负数 `precondition` 失败（Package 没开 `-Ounchecked`，release 里也检查）。`refreshDerived` 在 `AppModel.start()` 里就会调用 → 启动即崩，而 SessionStart hook 会不断把 App 拉起来 → 崩溃循环，只能 `defaults delete`。设置页的 Stepper 限制在 0…8，所以只有外部改文件才会触发。
- 根因：读取外部可写的值时不做范围夹取（`zoom`、`opacity` 已经夹了，这一个漏了）。
- 建议修法：`Settings` 加带范围的访问器 `int(_ k: String, in range: ClosedRange<Int>)`，所有消费者统一用；这里 `prefix(max(0, min(8, n)))`。
- 建议的回归测试：把 `refreshDerived` 里的派生逻辑抽成静态纯函数 `AppModel.derive(snapshots:hidden:dormantMax:) -> (present, dormant)`，单测 `dormantMax` 取 `-1 / 0 / 8 / Int.max`（BuddyOffice 没有测试目标，见第 3 节结尾的建议；也可以放进 BuddyStage）。
- 把握程度：确认（Swift 标准库语义）。

### A-005 [P2] 今日白板计数 ≤ -5 → 白板绘制 `0..<负数` 崩溃；`addTally` 在 Int.max 时溢出
- 位置：`BuddyStage/RoomRenderer.swift:302-322`（`drawTally`：`for gI in 0..<min(maxGlyphs, full + (rest > 0 ? 1 : 0))`）；`BuddyOffice/Settings.swift:36-50`（`tallyToday()` 直接返回 `d.integer(forKey:)`；`addTally` 里 `+ 1`）；`BuddyOffice/OfficeWindowController.swift:93`（`opts.tally = tallyToday()`）。
- 现象 / 触发条件：`defaults write local.buddy-office tally.2026-09-29 -int -5`（或更小）：`n / 5 = -1`、`n % 5 = 0` → 区间 `0..<-1` → 运行时陷阱；当天办公室窗口每次渲染（白板可见时）就崩。写成 `Int.max`：下一次「做完了」时 `addTally` 的 `+ 1` 溢出崩溃。
- 根因：外部可写的值没有夹取；`drawTally` 假设 `n ≥ 0`。
- 建议修法：`tallyToday()` 返回 `max(0, min(v, 9999))`；`drawTally` 开头 `let n = max(0, n)`；`addTally` 先夹取再 `&+ 1`。
- 建议的回归测试：`Tests/BuddyStageTests/RenderingTests.swift` 加一条：`RoomRenderer(layout:).drawDynamic(on:state:light:)` 分别用 `tally: -5 / Int.min / Int.max` 调用不崩，且 `tally: -5` 与 `tally: 0` 的画布逐像素相同。
- 把握程度：确认。

### A-006 [P2] 桌面宠物「位置」「显示在」改了不立即生效
- 位置：`BuddyOffice/StripPanelController.swift:52`（`screensChanged`）、`:110-125`（`reposition`）、`:136-157`（`render`）；`BuddyOffice/AppModel.swift:121-137`（`applySettings` 不调 `reposition`）。
- 现象 / 触发条件：设置 → 桌面宠物 → 「位置」（靠右 / 居中 / 靠左）或「显示在」（主屏幕 / 鼠标所在的屏幕）改了之后，面板不动。`reposition()` 只有两个触发点：宠物条画布尺寸变了（有人来 / 走）、`NSApplication.didChangeScreenParametersNotification`。另外，「靠右 / 靠左」会让条内人物的排布方向立刻翻转（`scene.alignRight` 每帧读设置），于是看起来是人挤到面板一侧、面板还在原处。「鼠标所在的屏幕」只在 `reposition` 时求一次值，不会跟着鼠标。Dock 改大小 / 换位置时不一定触发 `didChangeScreenParameters`（可能）。
- 根因：`render` 的 `settingsGen != model.settingsGen` 分支只更新 `zoom` 和窗口层级，没有重新定位。
- 建议修法：在那个分支里加 `reposition()`；`strip.screen == "mouse"` 时每 0.5 秒比较一次鼠标所在屏幕，变了再 `reposition()`。
- 建议的回归测试：抽出纯函数 `StripPanelController.origin(align:visibleFrame:panelSize:margin:) -> NSPoint`，单测 `left / center / right / "xyz"`；再加自检开关（改设置 → 0.2 s 后读 `panel.frame.origin`）。
- 把握程度：确认（读代码，没有第三个调用点）；Dock 变化那一段是可能。

### A-007 [P2] 「换个造型」：坐着的、走路的、重启后的造型三者不一致
- 位置：`BuddyStage/VisualDirector.swift:40`（`reroll`）；`BuddyOffice/AppModel.swift:263`；`BuddyCore/Fusion/IdentityResolver.swift:164-169`（`reroll` 只是 `salt &+= 1` 并持久化）。
- 现象 / 触发条件：右键 buddy → 换个造型：坐着的人立刻变成一个随机造型 X（`Appearance.generate(seed: UInt64.random(...))`，和 salt 无关）；但 (1) 持久化的是 salt+1，重启后的造型是 f(salt+1) ≠ X，用户挑中的造型丢了；(2) `appearances[key]` 被清空后，下一次 `appearance(for:)` 会用当时快照里的旧 salt（`rerollAppearance` 是异步的，新 salt 要等下一个快照）重新算出旧造型并缓存 → 之后的走进 / 走出动画（`OfficeScene` 用 `director.appearance(for:)`）和衣帽架上的外套仍是旧造型。
- 根因：UI 层用随机数造了一个不和 salt 关联的外观。
- 建议修法：`director.reroll(key:)` 只清缓存 + 记下「等新 salt」；等快照里的 `salt` 变了，再 `appearances[key] = nil` 并 `performer.setAppearance(appearance(for: s))`。或者让 `SessionStore.rerollAppearance` 同步返回新 salt 直接用。
- 建议的回归测试：`BuddyStageTests`：喂 salt=1 的快照，记下 `performer.appearance`；调 `reroll`；喂 salt=2 的快照；断言 `performer.appearance == director.appearance(for: s2)`，并且等于 `Appearance.resolve(salt: 2, …)` 的结果。
- 把握程度：确认。

### A-008 [P2] 同一会话第二次走进办公室：座位上直接坐着人，门口又走进来一个「分身」
- 位置：`BuddyStage/OfficeScene.swift:52`（`seatedAt`）、`:183`（写）、`:206`、`:215-216`（读）；`BuddyCore/Fusion/SessionEngine.swift:236-241`（`.away → .live` 时 `appearedAfterLaunch = true`）。
- 现象 / 触发条件：会话 K 在 App 运行期间走进来（`seatedAt[K]` 记下坐下时刻）→ 离场 → 用同一个身份回来（关掉终端再 `--resume`；桌面 App 重启后同一个 hostSessionId 回来；演示模式每 80 秒循环一遍的 `demo5`）。回来时 `startEntering` 起了走路动画，但 `seatedAt[K]` 还是上一次的旧值（非 nil）：`if let s = sp, walkers.isBusy(s.key), seatedAt[s.key] == nil` 不成立 → 座位按「已坐好」画（开机动画已满），同时门口的走路者照常走过来，走到椅子处叠在座位上的人身上。
- 根因：`seatedAt` 只在 `nil` 时写、从不清。
- 建议修法：在「人员变化」分支里对 `pk.subtracting(nowKeys)` 的 key 执行 `seatedAt.removeValue(forKey:)`，或者在 `startEntering` 时 `seatedAt[key] = nil`。
- 建议的回归测试：`BuddyStageTests`：`OfficeScene`（`animateWalkers = true`）连续帧：K 出现 → 等走完 → K 消失 → 等走完 → K 再出现；断言再出现后的第一帧 `lastSeatViews[seat].mode == .empty && chairOut == true`（人在路上，不是已经坐好），走完之后才是 `.occupied`。
- 把握程度：确认（读代码推演；没有运行）。

### A-009 [P2] `Canvas.writeBGRA` 在 crop 与画布不相交时退化成整张画布，会越界写目标内存
- 位置：`PixelKit/Canvas.swift:329-338`（`let r = (crop ?? bounds).intersection(bounds) ?? bounds`）；调用点 `BuddyOffice/PixelView.swift:98-101`——IOSurface 按 `vp.w × vp.h` 分配，`writeBGRA` 却按「回退后的整张画布」来写。同样的 `?? bounds` 也在 `Canvas.swift:273`、`:343`，那两处目标缓冲是按 `r` 分配的，安全。
- 现象 / 触发条件：当前所有调用点的 viewport 都在画布内（`OfficeScene` 的 `vp` 被夹在世界里；小鱼缸 / 宠物条 / 提示卡 / 悬停卡用整张），所以**现在不可达**。将来任何把 viewport 传到画布外的改动（镜头 bug、窗口极小时夹错），会在共享内存（合成器正在读）上越界写整张画布——堆损坏 / 崩溃。
- 根因：用「回退成整张」代替「什么都不写」；函数不校验目标大小。
- 建议修法：`guard let r = (crop ?? bounds).intersection(bounds) else { return }`，再加 `dstWidth / dstHeight` 参数或断言 `r.w * 4 <= bytesPerRow`。
- 建议的回归测试：`PixelKit` 测试（BuddyStageTests 里也行）：分配 `(w+2)×(h+2)` 带哨兵值的缓冲，用「完全在画布外 / 部分在外 / 零宽」三种 crop 调用，断言哨兵不被改写。
- 把握程度：确认（代码事实）；可达性：当前不可达。

### A-010 [P2] 「跟着 Claude 一起收」把被隐藏的 buddy 当成「没有会话」
- 位置：`BuddyOffice/AppModel.swift:95`（`hasLiveSessions = { !(self?.present.isEmpty ?? true) }`，而 `present` 已经剔除了 hidden）；`BuddyOffice/SystemHelpers.swift:31-38`。
- 现象 / 触发条件：用户把所有在场的 buddy 都「隐藏」了（比如都是后台任务）；Claude 桌面 App 一退出 → 60 秒后 `hasLiveSessions()` 为 false → 自动退出，而终端里的 `claude` 会话其实还活着，AlertCoordinator 本来仍会为它们发「等你批准」的提醒，现在也没了。
- 根因：用于显示的过滤集合被拿去判断「是否还有活会话」。
- 建议修法：`hasLiveSessions = { self.snapshots.contains { $0.presence == .present } }`。
- 建议的回归测试：给 `AutoQuit` 注入闭包做单测：`hidden = [k]`、快照里有 present 的 `k` → `hasLiveSessions()` 必须为 true（需要 BuddyOffice 测试目标，见第 3 节结尾）。
- 把握程度：确认。

### A-011 [P2] 座位号没有上限：一个被写坏的持久化座位号会让 OfficeScene 分配天文数字的数组 / 画布
- 位置：`BuddyStage/OfficeScene.swift:136-139,197`（`maxSeat` → `OfficeLayout.compute` → `deskCount`；`presentAt = [Int](repeating: -1, count: lay.deskCount)`；`Canvas(width: worldW, height: worldH)`）、`BuddyStage/OfficeLayout.swift:37-53`、`BuddyStage/OfficeScene.swift:112`（`hitID`：`UInt16(1000 + seat)`）；数据来源 `BuddyCore/Fusion/IdentityResolver.swift:147-153`（`assignSeat` 优先沿用持久化的 seat）和 `:210`（`load` 不校验）。
- 现象 / 触发条件：`~/Library/Application Support/BuddyOffice/identities.json` 里某个身份的 `seat` 被写成很大的数（文件损坏 / 手动编辑）。`compressSeats()` 只在第一次 `poll` 里对「当时已在场」的 buddy 执行；之后才出现的身份走 `assignSeat`，它「优先坐回上次的工位（没被别人占着的话）」，会把这个巨大的座位号原样交给 App。`OfficeScene` 用 `deskCount = max(4, maxSeat + 2)` 分配 `Int` 数组和 `worldW × worldH × 8` 字节的画布（`rows = deskCount / cols`，高度按行数线性增长），没有任何上限 → 内存分配失败（崩溃）或系统卡死；座位号 ≥ 64536 时 `hitID` 的 `UInt16(1000 + seat)` 也会溢出崩溃。小鱼缸 / 宠物条只画前 8 个人，座位号只用于命中 ID 的槽位，不受影响。
- 根因：座位号被当成「小整数」，数据层和 App 层两层都没有夹取。
- 建议修法：数据层输出快照前把 `seat` 夹到 `0..<64`（超过的重新分配最小空位）；`IdentityResolver.load` 丢弃 `seat < 0 || seat > 999` 的值；App 层 `OfficeLayout.compute` 里 `let maxSeat = min(maxSeat, 63)`，`hitID` 用 `UInt16(1000 + min(seat, 999))` 作为纵深防御。
- 建议的回归测试：`BuddyStageTests`：`OfficeLayout.compute(viewportW: 224, viewportH: 226, maxSeat: 1_000_000_000).deskCount <= 66`，且 `OfficeScene.render` 用 `seat = Int.max` 的快照不崩；`BuddyCoreTests`：`identities.json` 里放 `seat: 999999999` 的身份，之后才出现的会话拿到的 seat ≤ 63。
- 把握程度：可能（读代码得出：需要一个被写坏的 identities.json；我没有确认除 `assignSeat` 之外别处还有没有夹取；正常运行时座位号 = 最小空位，恒小）。

### A-012 [P3] 主线程上的 `queue.sync` 链：退出、切换演示、打开设置页诊断
- 位置：`AppDelegate.swift:127-129`（`applicationWillTerminate → provider.stop()`）、`AppModel.swift:276-284`（`setDemo`）、`SettingsView.swift:116,124` → `AppModel.swift:287`（`diagnosticsText`）→ `BuddyCore SessionStore.swift:81-89 / 99-105`（`queue.sync`）→ `SessionEngine.shutdown` → `TokenLedger.swift:145-147`（`flush` 是对 `.background` QoS 队列的 `queue.sync`）。
- 现象：主线程同步等 ingest 队列（utility）里当前的 `poll()` 结束；`stop()` 里再等 tokenscan 队列（background）当前的扫描批次 + 写盘。平时几十毫秒；后台优先级的线程在系统很忙时可能被饿住（有 QoS 提升，没实测）；最坏约等于一个大文件的扫描批次（首次全量 0.34–0.47 s，DESIGN.md 第 9 节）。表现是 ⌘Q 后转圈或点「演示模式」卡一下。
- 建议修法：退出时给 `stop()` 一个带超时的版本（`group.wait(timeout: 0.5)`，超时就放弃 flush，下次启动会从上次偏移继续读，不会错）；设置页诊断改成 `queue.async` 取回后再回填。
- 建议的回归测试：`BuddyCoreTests`（别人在审）：tokenscan 队列忙时 `SessionStore.stop()` 在 500 ms 内返回。
- 把握程度：可能（没有实测耗时）。

### A-013 [P3] `NSAppleScript` 在后台串行队列上执行
- 位置：`BuddyOffice/JumpService.swift:12`（`queue`）、`:79-92`（`jumpTerminal`）、`:106-129`（`selectTerminalTab`）。
- 现象：(1) Apple 对 `NSAppleScript` 的线程安全没有保证（通常建议在主线程用）；(2) 自动化授权提示没有答复时，`executeAndReturnError` 最长阻塞约 2 分钟（DESIGN.md 第 2 节 M0 实测 `-1712`），它和「查宿主 App」共用同一个串行队列 `jump`，之后所有终端跳转排队等它（不影响主线程）。
- 建议修法：脚本里加 `with timeout of 5 seconds`；把「查宿主 App」和「跑脚本」拆成两个队列。
- 建议的回归测试：难写单测（依赖系统授权弹窗）；只做代码修改 + 真机手测。
- 把握程度：可能。

### A-014 [P3] 主线程同步读取并解析全部 `local_*.json`
- 位置：`BuddyOffice/JumpService.swift:152-180`（`DesktopMeta`）；调用点：`JumpService.swift:35-36,40`（点击跳转）、`AppModel.swift:238-249`（`isUserLooking`，提醒判定时）。
- 现象：每次点击桌面会话 buddy：3 层目录枚举 ×2 + 读 / 解析全部 `local_*.json` 一遍，2.5 秒后再枚举一次；提醒判定（`notify.suppressWhenFocused` 开、Claude 在最前）时也读全量。本机 41 个文件、共 695,699 字节（中位数 20,183 字节），估计每次 3–8 ms；随文件数线性增长，上千个会话时可到 100 ms 以上，点击瞬间会掉帧。
- 根因：没有复用 BuddyCore 里已有的、带缓存的 `DesktopMetaReader`（后台 `poll` 本来就在读这些文件），App 层另写了一套无缓存的。另外它绕过了 BuddyCore 里「拒绝 `.key` / `.sock`」的 `FileIO` 统一入口（这里的过滤 `hasPrefix("local_") && hasSuffix(".json")` 本身就碰不到 `.key` / `.sock`，所以不算违反红线，只是和 DESIGN.md「全部通过 FileIO 一个入口」的说法不一致）。
- 建议修法：让 `SnapshotProvider` 暴露 `lastFocusedAt(host:)` / `mostRecentlyFocusedHost`（从 metaReader 的内存索引取），或者把 `DesktopMeta` 放到后台队列 + 1 秒缓存。
- 建议的回归测试：假 home 里放 2000 个 20 KB 的元数据文件，断言改成读缓存之后 `isMostRecentlyFocused` 在主线程 < 5 ms。
- 把握程度：确认（代码事实）；耗时是估计。

### A-015 [P3] `DebugTools.log`：旧式 API、世界可读的 /tmp、无界增长、开发开关会写会话标题
- 位置：`BuddyOffice/DebugTools.swift:8-13`；`AppModel.swift:254`、`JumpService.swift:126`（`NSLog`）；生产路径上的调用点 `SystemHelpers.swift:34,35,60`；开发开关 `AppDelegate.swift:104,107`。
- 现象：(1) `FileHandle.seekToEndOfFile()` / `write(_ data:)` 是会抛 Objective-C 异常的旧接口，磁盘满 / 文件被截断时是不可捕获的崩溃；(2) 日志固定写 `/tmp/buddy-office-debug.log`（默认 0644，世界可读；同机其他用户可预先放一个符号链接让 App 往别的自己有权限的文件里追加）；(3) 生产路径也会写（热键注册、自动收起）→ 无上限追加，热键开着时每次 `applySettings` 一行（见 A-016）；(4) `--test-jump` 分支把所有会话标题（可能含对话摘要）写进这个世界可读的文件，只在开发开关下发生，但没有任何提示；(5) 两处 `NSLog("… \(x)")` 把插值后的字符串当成格式串（`AppModel.swift:254` 的演示标题、`JumpService.swift:126` 的 AppleScript 错误字典）：字符串里有 `%` 时 `NSLog` 会按格式符去读不存在的参数（未定义行为）。目前前者是固定的演示假数据、后者几乎不会含 `%`，实际风险很小，但写法应该是 `NSLog("%@", msg)`。
- 建议修法：换新式 API（`try h.seekToEnd()`、`write(contentsOf:)`）；日志放 `~/Library/Logs/BuddyOffice/`、权限 0600、超过 1 MB 轮转；标题输出改成 `title.count` 或哈希；发布版默认不写，只在 `--log-ui / --prof / --test-*` 等开发开关下写。
- 建议的回归测试：单测 `DebugTools.log` 在只读路径 / 满盘（`/dev/full`）不崩；grep 式测试：`DebugTools.log(` 的参数里不出现 `title`。
- 把握程度：确认。

### A-016 [P3] `applySettings` 被无差别重跑：热键反复重新注册 + 日志刷屏；`.settingsChanged` 是死代码
- 位置：`BuddyOffice/AppModel.swift:98-101`（监听 `UserDefaults.didChangeNotification`，不看是哪个键）、`:121-137`、`:135`（`hotkey.register()` 每次先 `unregister` 再注册并写日志）；`BuddyOffice/Settings.swift:3,23`（`.settingsChanged` 只有发送方，没有任何观察者）。
- 现象：AppKit 自己写的窗口位置（拖动窗口的每一步）、每次「做完了」的 `tally.*`、设置页的每一次点击，都会触发最多 20 次 / 秒的 `applySettings`。热键开着时每次都：注销 → 重新注册（这一瞬间按热键会丢）→ 追加一行日志。它也是 A-003 的触发源。
- 建议修法：记住上一次应用的设置快照，只有相关的键变了才做对应动作；热键只在 `hotkey.enabled` 变化时注册 / 注销；删掉 `.settingsChanged`，或者让 `AppModel` 订阅它并只在 `Settings.set` 时触发。
- 建议的回归测试：抽出 `SettingsDiff` 纯函数；断言只有 `NSWindow Frame …` 键变化时不触发任何动作。
- 把握程度：确认。

### A-017 [P3] `AppModel.wake()` 没有速率上限：鼠标在办公室窗口里移动时节拍可以超过 30 fps
- 位置：`BuddyOffice/AppModel.swift:63-66`；`BuddyOffice/OfficeWindowController.swift:52`（每个 mouseMoved 都调 `onWake`）。
- 现象：`wake()` 在「下一拍还在 20 ms 之后」时把定时器提前到 1 ms 后。稳态间隔 33 ms；当鼠标事件间隔小于约 13 ms（≥ 75 Hz，如 120 Hz 的触控板），每个 mouseMoved 都会把下一拍提前，节拍跟着鼠标事件的频率（约 75–120 Hz，每拍都渲染办公室 + 小鱼缸 + 宠物条）。
- 建议修法：`wake()` 记录上一次实际 tick 的时刻，`schedule` 的最小间隔夹到 ≥ 1/30 s（悬停要立刻出一帧，但不需要超过 30 fps）。
- 建议的回归测试：给 tick 加计数，以 120 Hz 合成 mouseMoved 喂 1 秒，断言 tick 次数 ≤ 35。
- 把握程度：可能（读代码得出；CPU 影响没测）。

### A-018 [P3] 只增不减的字典 / 键（按会话、按天累积）
- 位置：`AlertCoordinator.swift:21-23`（`prevActivity`、`finished`、`lastAlert`）、`VisualDirector.swift:11`（`appearances`）、`OfficeScene.swift:52-53`（`seatedAt`、`lastApp`）、`ScreenContent.swift:50`（`staticCache`）、UserDefaults 的 `tally.*` 和 `hidden.keys`。完整的清单和上界见第 4 节的表。
- 现象：每个见过的会话 key（桌面会话 `d:` + hostSessionId 稳定，终端会话 `t:` + sessionId 每次 `claude` 一个新的）在进程生命周期内会留下约 0.5–1 KB（`prevActivity` 里的 `Activity` 还带着最多 160 字的工具 detail，比如 Bash 命令）。一天 100 个会话、跑一个月 ≈ 3 MB，不会撑爆内存，但是没有上界；`tally.YYYY-MM-DD` 每天一个键永不清理（本机偏好文件里已经有 2 个）；`hidden.keys` 只会增加。
- 建议修法：`AlertCoordinator.observe` 里对 `prevActivity / lastAlert / finished` 按 `keys` 集合做一次修剪（和 `episodes` 一样）；`OfficeScene` 在人离场时清 `seatedAt`（同 A-008）；`appearances` 只保留当前 present 的（同 A-027）；`tally.*` 启动时删除 30 天前的键。
- 建议的回归测试：`AlertCoordinator` 喂 10,000 个不同 key 的会话依次出现又离场，断言内部字典大小不随之线性增长（需要 BuddyOffice 测试目标）；`OfficeScene`：同样喂大量 key，断言 `seatedAt.count` 有界。
- 把握程度：确认。

### A-019 [P3] 文案边界：空路径、负时间、空标题、英文原文
- 位置：`BuddyStage/PlateCopy.swift:112-125`（`"在读 " + fileName(detail)`、`在找 "…"`、`"在看 " + domain(detail)`）、`:104-105`（`idleMinutes`）；`BuddyOffice/AlertCoordinator.swift:49`（title 直接用 `s.title`）；`BuddyOffice/StatusItemController.swift:51`；`BuddyStage/HoverCard.swift:44-48,60`、`PlateCopy.swift:62-65`。
- 现象：
  - hook 行被截断而走降级解析时 `detail` 是空串（`LineSanitizer.parseDegraded` 只抠 ts / ev / tool，DESIGN.md 说超过一半的事件文件里有被截断的中文字节），桌牌会显示「在读 」（尾随空格）、`在找 ""`、「在看 」、「在改 」、「在写 」。
  - `idleMinutes` 没有 `max(0, …)`：系统时间被调回 / 时间戳在未来时显示「打盹 -3 分钟」（`duration / spoken / waitSpoken / HoverCard.ago` 都有夹取）。
  - 空白标题：桌牌和悬停卡已有占位（`PlateCopy.displayTitle`，审查期间新加的），但系统通知、像素提示卡、菜单栏菜单、右键菜单仍直接用 `s.title`，纯空白标题时是一行空白 / 「跳转到「」」。数据层不会给出空串标题（`RegistryScanner.str` 过滤空串），只可能是纯空白。
  - 悬停卡里的 `modelName · effort · permissionMode`（如 `high`、`acceptEdits`、`bypassPermissions`）、`statusDetail`（桌面本轮总结，英文原文）和 `tok` 缩写是英文，其余用户可见文字都是中文。
  - 标题没有长度限制、不去换行；桌牌 / 卡片有 `maxWidth` 省略，但菜单栏菜单和系统通知标题会被撑得很宽。
- 建议修法：`PlateCopy` 里所有 `"在读 " + x` 改成 `x.isEmpty ? "在读文件" : "在读 " + x`（其他同理）；`idleMinutes` 夹 0；所有显示标题的地方统一走 `displayTitle` + 截断到 40 字并把换行替换成空格。
- 建议的回归测试：`PlateCopyTests`：`activity` 在 `detail == ""` 时对每个类别都不出现尾随空格 / 空引号；`idleMinutes` 负值返回 0 分钟；`AlertCoordinator` 的标题用 `displayTitle`。
- 把握程度：确认。

### A-020 [P3] `Int(Double)` 对极端时间没有保护
- 位置：`BuddyStage/PlateCopy.swift:41,46,52`（`max(0, Int(seconds))`：先转换再夹取，夹取来不及）、`:104`（`Int(now.timeIntervalSince(t) / 60)`）；`BuddyStage/Performer.swift:120`（`Int(elapsed / 3)`）。
- 现象 / 触发条件：`seconds` 来自 `now.timeIntervalSince(外部时间戳)`。ISO 串（≤ 9999 年）安全；hook 的 `ts` 走 `TimeUtil.date(ms:)`（不检查范围）、登记表的 `startedAt` 等走 `date(fromJSONMillis:)`（只检查 `isFinite && > 0`），一旦有 ≥ 约 9.2e21 毫秒的值（被写坏 / 被篡改的文件），`Int(±1e18 以上)` 陷阱崩溃。正常的 Claude 数据不会出现。
- 建议修法：一个 `safeInt(_ d: Double) -> Int`（`d.isFinite ? Int(max(-1e15, min(1e15, d))) : 0`）；或者在 BuddyCore 的时间解析处把时间夹到 [2000, 2100] 年。
- 建议的回归测试：`PlateCopyTests`：`duration(.infinity)`、`duration(-1e300)`、`spoken(.nan)`、`waitSpoken(1e30)` 不崩。
- 把握程度：可能（可达性取决于 BuddyCore 是否已经在别处拦住；我只看了 `TimeUtil`）。

### A-021 [P3] 演示模式的副作用
- 位置：`BuddyOffice/AppModel.swift:208`（`settings.addTally()` 不区分 demo）、`:276-284`（`setDemo` 不重置 `gotData`）。
- 现象：演示剧本每循环一次有 2 次「做完了」（demo0 在 63 s、demo3 在 40 s），演示开着 1 小时会往真实的今日白板计数里加约 90；切换演示 / 真实数据时 `gotData` 保持 true，`snapshots = []` 到新数据到来前的 0.25–0.5 秒里，「今天还没人上班」的牌子会闪一下（`emptySign = model.gotData`）；演示模式下的提醒（声音、像素提示、系统通知）是真的发出去的。
- 建议修法：`demo` 时不计数；`setDemo` 里 `gotData = false`；演示提醒可选静音。
- 建议的回归测试：`AppModel(provider: MockSource())` 推进剧本到 63 秒，断言 `tallyToday` 不变。
- 把握程度：确认。

### A-022 [P3] `AlertCoordinator` 的几处细节
- 位置：`BuddyOffice/AlertCoordinator.swift:58,60-61`（`continue`）、`:107-119`（`post` 合并）、`:41-99`（用全部快照）。
- 现象：
  1. 等待状态的「延迟 / 被抑制」两个分支用 `continue`，同一轮循环里后面的 `prevActivity[s.key] = cur`、`finishedTurns`、`finished` 记账被跳过。多数情况没影响（waiting 时不会是 `.finished`），但「`.finished` → waiting（被抑制）→ `.finished`」之间 `prevActivity` 是旧值，会漏计 / 错计一轮。
  2. 2 秒内合并成「N 位同事在等你」时，合并对象也可能是「做完了 / 出错」；这条 `multi` 提醒永远不会被 `.clear`，系统通知 id `buddy.multi` 会一直留在通知中心，直到用户清掉；点击它时 `notifier.onClick`（`AppModel.swift:92`）按 key 找不到快照，什么都不发生（应该打开办公室）。
  3. 被用户「隐藏」的 buddy 仍会提醒，并计入 Dock 角标 / 菜单栏「N 位同事在等你」（`observe` 用的是全部快照，办公室里却看不到他）；可能是设计意图，需要确认。
- 建议修法：1 用 `defer` 或把记账放到循环体开头；2 合并后给 `multi` 一个清除时机（所有被合并的 key 都 `.clear` 时清 `multi`），并按合并对象的种类选文案；3 明确语义后二选一。
- 建议的回归测试：`AlertCoordinator` 单测（需要 BuddyOffice 测试目标）：构造「.finished → waiting（终端在前，被延迟）→ .finished」序列，断言 `finishedTurns` 总数为 2。
- 把握程度：确认（1、2）；3 是设计确认。

### A-023 [P3] 设置页显示和实际状态不同步；通知授权从不主动请求
- 位置：`SettingsView.swift:84`（`model.notifier.statusText` 不是被观察的状态，授权状态文字不会刷新）、`:106`（开机启动开关：`loginEnabled` 只是 `@AppStorage`，和 `LoginItem.isOn` / 系统里的真实状态不同步；`LoginItem.set` 返回「开启失败：…」时开关仍显示开；`SMAppService` 返回 `.requiresApproval` 时提示「已用登录项开启」但还需要用户去系统设置批准）；`AppModel.swift:128`（强制补上的 Dock 图标不写回 `ui.dockIcon`，设置页显示「关」而 Dock 里其实有图标）；`NotificationService.swift:27-29` + `AppModel.swift:300`（授权请求只有「请求通知授权」按钮和「发一条测试提醒」会发，DESIGN.md 第 2 节写的「用户第一次主动打开办公室窗口时发」没有实现，所以除非用户手动点，永远走像素提示兜底）。
- 建议修法：把 `notifier.status` / 登录项状态做成 `ObservableObject` 的 `@Published`；设置页打开时读一次真实登录项状态；强制入口时写回设置；决定是否要在「第一次打开办公室窗口」时请求授权。
- 建议的回归测试：状态映射函数单测（`LoginItem.set` 失败 → 开关回退）。
- 把握程度：确认。

### A-024 [P3] 只开「桌面宠物」且没有会话时，没有任何可点击的入口
- 位置：`BuddyOffice/AppModel.swift:128`（`if !(officeOn || tankOn || stripOn || menuOn || dockOn) { dockOn = true }`）；`BuddyStage/StripScene.swift`（没有会话时不画任何东西）；`StripPanelController.swift:79-99`（没命中就点穿）。
- 现象 / 触发条件：设置里把办公室窗口、小鱼缸、菜单栏图标、Dock 图标都关掉，只留桌面宠物（一个「纯宠物」的用法）。这时没有会话 → 宠物条是一块透明的、点穿的区域，没有任何可点的入口（也没有快捷键，除非手动开了热键）。恢复办法只有：重新启动 App（`applicationShouldHandleReopen` 会打开办公室窗口）或等有会话时右键 buddy →「设置…」。
- 根因：入口检查把「宠物条 / 小鱼缸可见」当成入口，但空的宠物条不可点。
- 建议修法：入口检查里把 `stripOn` 单独存在时视为无入口（补 Dock 图标），或者宠物条没有会话时画一个小的、可点的占位。
- 建议的回归测试：抽出 `entryFallback(office:tank:strip:menu:dock:stripHasBuddies:) -> dockOn` 纯函数单测。
- 把握程度：确认。

### A-025 [P3] 性能陷阱合集（每帧分配 / 每像素字符串查表）
- 位置与现象：
  1. `BuddyStage/SeatRenderer.swift:283`：显示器开机动画（每个人刚坐下 / 刚启动的前 0.3 秒，约 9 帧）每帧、每个座位新建一张**世界大小**的 `Canvas`（`tmp = Canvas(width: c.width, height: c.height)`）。默认 224×226 只有 0.4 MB，1 倍缩放 + 大窗口（672×678 美术像素）每次 3.6 MB × N 个座位 × 9 帧，启动瞬间有一次分配 + 清零的尖峰。应该用屏幕区大小的草稿。
  2. `BuddyStage/OfficeScene.swift:248-316`（悬停放置那一段）：悬停时每帧至少 1 次、最多 4 次 `HoverCard.make`（试 4 个缩放，`cardCache` 只在一帧内有效），放不下时的兜底搜索最坏是 (vp.w/2)×(vp.h/2)×4 次 `fits`（只在窗口很小时才走到，窗口小所以便宜），且悬停强制整张重画；`BuddyOffice/Panels.swift:36-50` 的 `HoverPanelController.show` 在小鱼缸每个 tick / 宠物条 30 Hz 轮询里每次都重建整张卡片 + `setFrameOrigin`。应该按（快照指纹，秒）缓存卡片。
  3. `BuddyStage/Walkers.swift:215`：每个走路的人每帧新建一张 48×62 的 `Canvas`。
  4. `BuddyStage/RoomRenderer.swift:109-194`（`bake`）：地板等循环里每个像素都调 `P("floor.base")` 等，即 `Pal.dx(String)` 字典查找；每次布局变化（拖动窗口边缘的每一步、每 1.25 分钟的昼夜过渡步）整个世界重烘焙。估计默认 224×226 是几毫秒，1 倍缩放大窗口几十毫秒（主线程，没实测）。应该把用到的调色板索引提到循环外。
  5. `BuddyOffice/StatusItemController.swift:36`：每 ≥ 0.09 秒给菜单栏按钮赋一次 `toolTip`（只在变化时赋就够了）。
  6. `BuddyOffice/StripPanelController.swift:60-65`：宠物条可见时常驻 30 Hz `Timer` 轮询鼠标位置（远处时 2/3 的触发直接返回）。
  7. `BuddyStage/Performer.swift:340,364,480`：`resolveFrame` 每帧分配 `steps` 数组、`seatView` 里 `helperTracks.map.sorted`。
  8. `AppModel.swift:183-184`：`tick` 耗时超过间隔时 `delay = max(0.001, …)` → 背靠背 tick，CPU 顶满（大窗口 + 悬停时有可能）。
- 建议修法 / 测试：`buddyctl bench --sleep-ms 33`（DESIGN.md 第 6 节推荐的方法）在 `crowd12` + 1 倍缩放 + 大视口下前后对比；1 的单测：`SeatRenderer.draw` 在 `v.boot < 1` 时不分配与世界等大的 Canvas（可以用 `Canvas` 的静态实例计数器验证）。
- 把握程度：确认（代码事实）；耗时是估计。

### A-026 [P3] 深链成功判据不检查 Claude 是否真的到了前台；已弃用的激活 API
- 位置：`BuddyOffice/JumpService.swift:36,42`（`ok = wasLatest || …`）；`BuddyOffice/AppModel.swift:166`（`NSApp.activate(ignoringOtherApps: true)`）。
- 现象：目标会话本来就是 `lastFocusedAt` 最新的会话时（M0 发现的特例），2.5 秒后无条件算「成功」，不检查 Claude 是否被带到了前台；如果这种情况下深链只是「预热会话」而没有前置窗口（我无法验证），点 buddy 就什么也没发生，也不会走 `activateClaude()` 兜底。`NSApp.activate(ignoringOtherApps:)` 在 macOS 14+ 已弃用（行为是协作式激活，从非激活的 `.accessory` App 里打开设置窗口时可能不前置）。
- 建议修法：2.5 秒后无论 `wasLatest` 与否，检查 `NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID`，不是就 `activateClaude()`；设置窗口改用 `NSApp.activate()` + `window.makeKeyAndOrderFront`。
- 建议的回归测试：抽出判据纯函数 `deepLinkSucceeded(wasLatest:before:after:claudeFrontmost:)` 单测；前置行为只能真机验证。
- 把握程度：可能。

### A-027 [P3] 外观「不撞衫」把已离场的人也算进去，外观依赖出现顺序
- 位置：`BuddyStage/VisualDirector.swift:11,33-38`（`existing = Array(appearances.values)`，`appearances` 从不清）；`BuddyArt/Character/Appearance.swift:105-115`（`resolve` 最多重试 24 次，返回的 `salt` 不持久化）。
- 现象：`existing` 包含所有见过的会话（含已离场），发型×发色只有 64 种、衣服×颜色 60 种，会话多了之后新来的人几乎都撞衫，重试 24 次后取最后一次；最终的 salt 没有写回，所以同一个会话在不同次启动、不同出场顺序下的外观可能不同（DESIGN.md 说「外观种子盐（持久化）」）。
- 建议修法：`existing` 只取当前 present 的；`resolve` 得出的 salt 写回 identities（或者不做撞衫避让，只按 salt 出外观）。
- 建议的回归测试：`BuddyStageTests`：同一个 key、同一个 salt，在「先来 A 再来 B」和「先来 B 再来 A」两种顺序下外观必须相同。
- 把握程度：确认。

### A-028 [P3] 时区 / 历法：`DateFormatter` 和 `Calendar.current` 的缓存
- 位置：`BuddyOffice/Settings.swift:51-52`（`static let dayFormatter`，`dateFormat = "yyyy-MM-dd"`，没设 locale / calendar / timeZone）；`BuddyStage/SceneClock.swift:17`（`Calendar.current`）。
- 现象：(1) 白板计数的键是「当地日期字符串」，用户的历法不是公历（佛历 / 日本年号 / 伊斯兰历）时 `yyyy` 是那个历法的年份，切换系统语言 / 历法后键的格式变了，当天的计数从 0 重新开始；(2) App 跑好几天（设计目标）+ 跨时区旅行 / 系统时区变化时，`static let` 的 `DateFormatter` 和 `Calendar.current` 可能仍用旧时区（Foundation 需要 `resetSystemTimeZone` 才反映变化），白板跨天时间和窗外的天空会偏；夏令时切换那一天没有问题（只做格式化，没有按 86400 秒算日期）。
- 建议修法：`dayFormatter.calendar = Calendar(identifier: .gregorian)`、`locale = en_US_POSIX`、`timeZone = .autoupdatingCurrent`；`SceneClock` 用 `Calendar.autoupdatingCurrent`。
- 建议的回归测试：单测 `Settings.dayString(_:)` 在 `th_TH` / `ja_JP@calendar=japanese` 的 locale 下输出仍是公历 `yyyy-MM-dd`（先把 formatter 的 locale 做成可注入）。
- 把握程度：可能。

### A-029 [P3] 开发工具（buddyctl / StageCommands / DemoScript / FlickerScan）参数没有校验；工具代码链接进了 App
- 位置：`BuddyStage/DemoScript.swift:162,184`（`--demo-mode crowd5d-3`：`away = -3` → `(n - away)..<n` 即 `8..<5` 崩溃；`crowd99999999` 会分配几十 GB）、`:148,217`（`--speed -1` → `Int(t / 5)` 为负 → `% tools.count` 出负下标崩溃）；`BuddyStage/FlickerScan.swift:199,214`（`flicker --fps 1`：`win = 1`、`f0 += win / 2 = 0` 死循环；默认 80 秒 × 30 fps 的整段扫描要存约 2400 帧 × 4 个平面，办公室 1 倍缩放约 8 GB）；`BuddyStage/StageCommands.swift:350`（`--sleep-ms 5000000` → `UInt32(...)` 溢出崩溃）、`HoverCard.make` 的 `zoom = 0`（`--zoom 0 --hover` → `Int(inf)` 崩溃）；`PixelKit/TextRenderer.swift:150-162`（`image()` 里 `scale = 0` → `size` 为 inf）。`AppDelegate.swift:13,50`：`--speed nan` 等。
- 现象 / 影响：只有开发者在命令行手动传非法参数才会触发，不影响用户；`FlickerScan / TextAudit* / AuditFixtures / StageCommands / StageRun` 全在 `BuddyStage` 库里，随发布版 App 一起链接（体积和攻击面，不影响功能）。
- 建议修法：CLI 层统一用 `Int(x).map { max(lo, min(hi, $0)) } ?? default` 夹取；工具代码拆到 `BuddyStageTools` 目标，只链接进 `buddyctl`。
- 建议的回归测试：`StageCommands.run(["snapshot", "--zoom", "0"])` 等对非法参数返回非零而不是崩溃。
- 把握程度：确认。

---

## 2. 逐项结论（审查清单 12 项）

### 1. 强制解包 / `try!` / `as!` / `fatalError` / `precondition` / 隐式解包
**已查，没有能被外部输入触发的问题。**
- 方法：grep `!`、`try!`、`as!`、`fatalError`、`precondition`、`preconditionFailure`、`assert` 逐个看。
- `try!`、`as!`：本审查范围内 0 处。`fatalError()`：7 处，全是 `required init?(coder:)`（`SettingsView.swift:137`、`PixelView.swift:44`、`Panels.swift:62`、`TitleBarButtons.swift:15,34,58`、`OfficeWindowController.swift:64`），永远不会被调用。
- `precondition*`：`Canvas.init`（尺寸必须为正：全部 30 多个 `Canvas(width:` 调用点我逐个看了，运行时数据决定尺寸的只有 `OfficeScene`（世界 ≥ 64 宽、内容高）、`TankScene`、`StripScene`、`ToastCard`、`HoverCard`（`Int(ceil(...)) + 1 ≥ 2`），都恒为正）、`Canvas.copy / copyRegion` 的尺寸一致检查（`bg` / `work` 总是成对重建）、`Clip.init`、`GIFExport`；`SpriteBook.subscript`、`MasterPalette.index / direct` 的 `preconditionFailure`：我 grep 了所有 `Pal.dx(` / `P(` / `sprite(` / `props[` / `book[` 的实参，运行时拼接的只有 `"bubble.\(size)"`（size ∈ 7/11/15）、`"plate.\(state)"`（4 种）、`"chair.\(name).back"`（都用 `book.get`，返回 optional）、`ledName`（led.on / led.off / led.wait）、`ToastCard` 的 `border`（5 个固定名），都是封闭集合；`BuddyArt` 里其余 `precondition` 是构建期的美术数据断言（`HairStyles / Accessories / Faces / Outfits / ShadeKit / MasterPalette`），首次用到 `CharacterArt.book` 时执行，由 `SpriteAndPaletteTests` 覆盖，不依赖外部输入。
- `!` 强制解包（当前版本逐个看过）：`AlertCoordinator.swift:54`（刚写入）、`Performer.swift:274`、`VisualDirector.swift:62`、`OfficeScene.swift:164,304`、`JumpService.swift:176`（都有前置判断 / 短路）、`SoundSynth.swift:33-34`（常量字符串 `.data(using: .ascii)!`）、`SettingsView.swift:87`（常量 URL）、`Canvas.swift:278,346`（`baseAddress!` / `NSMutableData(length:)!`）、`Appearance.swift:46-68`（`rawValue` 来自 `below(n)`，n = case 个数，恒有效）、`TextRenderer.swift:79`（`emojiFont!` 前面刚赋值）、`DebugTools.swift:11`（`line.data(using: .utf8)!`，UTF-8 编码不会失败）、`AppDelegate.swift:40,79,84`（只在 `--log-ui` / `--test-titlebar` 开发开关里，`model` 此时已经赋值）、`SheetRenderer.swift:16`（前面有 `filter == nil ||` 短路，只在工具里用）。
- 隐式解包可选值：`AppDelegate.model: AppModel!`（`AppDelegate.swift:7`）在 `applicationDidFinishLaunching` 里同步赋值，`applicationShouldHandleReopen` 用 `model.` 不带问号，理论上重开事件早于启动完成会崩，但 AppKit 在启动完成之后才发；`applicationWillTerminate` 用了 `model?`。`AppModel.office: OfficeWindowController!`（`AppModel.swift:30`）在 `start()` 里赋值，`AppDelegate` 在 `start()` 之前用的是 `model.office?.`。启动早期 / 退出时没有发现 nil 解包。

### 2. 下标和范围越界（clip / blit / region / crop / viewport；负数 / 零 / 比画布大 / 缩放 0 / 极大 / 窗口极小）
**已查，有两处需要处理：A-009（潜在的越界写，当前不可达）、A-011（座位号没有上限）。**
- `Canvas` 的所有像素访问：`pixel / objectID / masterIndex` 带边界检查；`set / setPixel / setRaw` 被 clip 约束，`setClip` 总是和 `bounds` 求交集（矩形宽高为负 / 零 → `intersection` 返回 nil → clip 置空）；`blit / blitCanvas` 的源范围是 `[max(0, cx0-x), min(w, cx1-x))`，任何位置（含负数、远超画布）都安全；`fillRect / fillEllipse / applyLightPool / clearRegion / copyRegion` 都先求交集或先判空；`writeBGRA` 见 A-009；`makeCGImage / makeDisplayImage` 的目标按 `r` 分配，安全；`contentHash` 的按 8 字节读取用 `loadUnaligned`，奇数像素单独处理。
- `IntRect.intersection` 对宽高 ≤ 0 的矩形返回 nil，所以负宽高不会泄漏成负范围。
- 缩放：`office.zoom`（0 / 负数 / 99 / Int.max）现在走 `OfficeLayout.effectiveZoom`（`setting <= 0 → 自动`；否则 `max(1, min(setting, fit))`，`fit = Int(contentW / 64)`），`vw = max(40, Int(size.width) / z)` → 恒 ≥ 40；`PixelView.show` 里的 `vp.w * z` 不会溢出。`tank.zoom` 夹 1…2、`strip.zoom` 夹 1…3、`tank.opacity` 夹 0.3…1（NaN 也安全，`min(1, NaN)` 返回 1）。`HoverCard / ToastCard` 除以 `zoom`：调用方传的都 ≥ 1。`PixelView.artPoint` 有 `zoom > 0` 的守卫。
- 窗口极小：`contentMinSize` 200×220，`OfficeLayout.compute` 在 `viewportW = 40` 时 `usable = 8` → `cols = 1`；`worldW = max(viewportW, cols*56+8)`，`worldH = max(viewportH, contentH)`；镜头 `vp.y = max(0, min(worldH - vp.h, shown))` 总在世界里。尺寸为 0 的 `pixelView.bounds`（窗口还没布局）也不会崩（`max(40, …)`）。
- 座位数组：`presentAt / dormantAt` 大小是 `deskCount = max(4, maxSeat + 2)`，写入前判断 `0 <= seat < deskCount`，所以座位号本身不会越界；但 `deskCount` 没有上限，被写坏的持久化座位号会让分配失控（A-011）。`OfficeScene.hitID(seat:)` 是 `UInt16(1000 + seat)`，seat ≥ 64536 才会溢出（同样在 A-011）。
- `PoseLibrary`（`Int(t * 7.5) % 4` 后做 `[…][k]` 下标）依赖 `t = time - poseSince >= 0`：`Performer.update` 用导演传入的时刻，`seatView` 用后读的 `model.time`，恒 ≥；`RoomRenderer.plantPhase` 同理依赖 `time >= 0`（`model.time = CACurrentMediaTime() - t0`）。这是隐含的不变量，没有任何断言或夹取；建议 `max(0, t)`（不单列）。

### 3. 整数溢出和除以零（逐个查 `Int(` 里的 Double 表达式）
**已查；发现 A-005（`addTally` 溢出）、A-020（时间差的 `Int(Double)`）。**
- 我把 `BuddyOffice / BuddyStage / PixelKit / BuddyArt` 里所有 `Int(` 逐个看了。`OfficeLayout`、`SkyRenderer`、`Walkers`、`RoomRenderer`、`ScreenContent`（`t` 是屏幕已显示秒数，有限）、`SeatRenderer`、`TextRenderer`（`ceil(w * scale)`，`w` 有限）、`TitleBarButtons` 的 `Int(scale.rounded())`、`PixelSpring` 的 `Int(value.rounded())`（弹簧半隐式积分，`omega*h ≈ 0.5` 稳定，`dt` 被夹到 0.25，`period` 被 `max(0.05,…)`，NaN 的 `dt` 不进循环）都是有限值。`min / max` 遇到 NaN 的行为我逐处确认过（不会把 NaN 传给 `Int()`）。
- 除以零：`RoomRenderer.plan` 的 `/ gaps`（`gaps ≥ 1`）、`OfficeLayout` 的 `/ cols`（`cols ≥ 1`）、`TankScene.layout`（`cols ≥ 2`）、`TankPanelController` 的 `% max(1, cols)`、`Walkers` 的 `/ speed`（≥ 28）、`/ seg`（有 `< 0.0001` 守卫）、`SkyRenderer` 的 `max(1, …)`、`Clip.frame` 的 `truncatingRemainder(total)`（total = 0 → NaN，只会走到「返回最后一帧」）。
- 溢出：所有散列都用 `&*` / `&+`；`Settings.addTally` 的 `+ 1`（A-005）；`AppModel.settingsGen &+= 1`；`StripPanelController.pollTick += 1`（2^63 次才溢出）。

### 4. 主线程上的同步文件 / 进程 IO 和其他阻塞
**已查，见第 5 节的表；发现 A-012、A-013、A-014、A-025。**
- 每个 AppKit 回调、定时器 tick、render 里调用的东西，我列了「在哪个线程、多久一次、最坏耗时」。主线程 tick（渲染 + 提醒）本身没有文件 IO；IO 只出现在「用户点击」「提醒判定」「设置页」「退出」这几条低频路径上。`SoundSynth`、`NotificationService.refresh/post`、`JumpService.jumpTerminal` 都已经放到后台队列 / 异步。

### 5. 循环引用 / 内存泄漏
**已查，没有问题。**
- 闭包：`AppModel.start()` 里所有回调、`ClosureMenuItem` 的闭包、`PixelView.onHover/onClick/onRightClick`、`Timer` 的块（`AppModel`、`StripPanelController`、`ToastController`、`AutoQuit`、`MockSource`）全是 `[weak self]`；`StatusItemController.model` 是 `weak`；`NSMenuItem.target` 本来就不持有。`AppModel ⇄ SettingsWindowController`（`SettingsView` 持有 `model`，`model.settingsWindow` 持有窗口）是个环，但两边都是 App 生命周期的单例，无害。
- 观察者：`OfficeWindowController.swift:53-54`（两个块式观察者，控制器与 App 同寿命）、`AppModel.swift:98`（同）、`StripPanelController.swift:42`（选择子式）、`AutoQuit.start`（选择子式，只调用一次）。都不需要移除。
- `Timer`：`AppModel.schedule` 每拍 `invalidate` 旧的再建新的；`StripPanelController.hide` 里 `invalidate`；`ToastController` 无 toast 时 `invalidate`；`AutoQuit.scheduleQuit` 先 `invalidate`；`MockSource.stop` 里 `invalidate`；`AppDelegate.swift:38` 的 `--log-ui` 定时器是开发开关，不 invalidate。
- `NSTrackingArea`：`PixelView.updateTrackingAreas` 先 `removeTrackingArea` 再加；`PixelButton` 先删光再加。没有重复添加。
- `CALayer`：`PixelView.textLayers` 只增不减到峰值（隐藏而不删除），有界（第 4 节的表）。

### 6. 句柄 / 系统资源泄漏
**已查，没有问题。**
- `FileHandle`：只有 `DebugTools.log`，用完 `close()`（问题见 A-015）。`IOSurface`：每个 `PixelView` 最多 3 块，尺寸变化时整组重建，旧的随 ARC 释放；`Toast` 关闭时 `PixelView` 一起释放。`CGContext / CGImage` 全是局部或进缓存（有上限）。`NSStatusItem`：只在 `setVisible` 里创建一次，关闭时 `removeStatusItem`。`NSPanel`：`FloatingPanel` 在小鱼缸 / 宠物条 / 悬停各 1 个（App 生命周期），`Toast` 每条一个、最多同时 3 个，`close(_:)` 时 `orderOut` 并移出数组，`isReleasedWhenClosed = false` 且没有调用 `close()`，随 ARC 释放。`AVAudioPlayer`：4 个缓存复用。`DispatchSource` / FSEvents：BuddyCore 的 `SessionStore.stop()` 会 `cancel` 定时器、`watcher.stop()`，`FileWatcher.deinit` 也会 `stop`，`setDemo` 反复切换不会累积。

### 7. 无限增长的缓存 / 字典 / 数组
**已查，见第 4 节的表；发现 A-018、A-008、A-027（都是慢速累积，P3）。**
- 有界的：`TextRenderer`（图 600 条 FIFO、尺寸 4000 条清空）、`Lighting.resolvedCache`（400 条清空）、`SceneClock`、`inkExtentCache`、`SeatCache` / `plateCache` / `emptyApps` / `seatSigs`（按座位号，上界是峰值桌数）、`walkers`（`cleanup` 按时长删）、`helperTracks`（离场 0.6 秒后删）、`performers / applied / pending`（按 present 修剪）、`episodes`（按快照修剪）、`toasts`（≤ 3）。

### 8. 线程安全
**已查，没有问题（一处开发用途的 `Prof` 除外）。**
- `nonisolated(unsafe)` 全部 12 处声明：`SettingsView.initialTab`（只在主线程，开发开关）、`SoundSynth.players`（只在串行 `queue` 上访问）、`SceneClock.sec/cached`（都在 `lock` 内）、`ScreenContent.staticCache`（`staticLock`）、`Lighting.resolvedCache`（`cacheLock`）、`PixelFont.auditEnabled / auditSinkStorage`（`auditLock`，`auditEnabled` 是无锁读一个 Bool，良性）、`OfficeScene.inkExtentCache`（`inkExtentLock`；持锁时调用 `TextRenderer`，锁序单向，无死锁）、`Prof.enabled/acc`（`acc` 只在 `enabled` 时写，`enabled` 只有 `--prof` / bench 开，主线程；如果测试并行开 `Prof` 会有数据竞争，仅开发用途）、`TextAuditRunner.hoverStats`（开发工具）。
- 其余共享状态：`TextRenderer`（锁）、`SpriteBook`（构造后只读）、`SeatRenderer.screenScratch`（`scratchLock`）、`HotKey.current`（Carbon 回调在主线程）、`PixelButton.cache`（主线程）。`Canvas` 标了 `@unchecked Sendable` 但没有跨线程共享的实例。`SessionStore` 回调投递到 `.main`，`AppModel` 的状态只在主线程读写。`JumpService.deepLinkFailures / deepLinkDisabled` 只在主线程读写；`hostApp(of:)` 无状态，主线程和 `jump` 队列都会调用。唯一的关注点是 `NSAppleScript` 的线程模型（A-013）。

### 9. 状态机 / 生命周期
**已查；发现 A-003、A-004、A-005、A-006、A-007、A-008、A-010、A-016、A-021、A-023、A-024。**
- 窗口关闭 / 隐藏 / 重新打开：红色关闭按钮 → `windowShouldClose` 里 `orderOut` + `office.visible = false`；Dock 点击 → `applicationShouldHandleReopen` → `showOffice()`；⌘W 没有菜单项（无操作）；最小化见 A-003。
- 显示器拔掉：办公室窗口（标题栏窗口）AppKit 会拉回屏幕；小鱼缸 `FloatingPanel` 是可移动窗口，SDK 头文件说明系统会在显示器重新配置时移动「可移动的窗口」，加上 `placed` 只在第一次出画面时检查一次「存过的位置是否还在屏幕上」，所以运行时拔屏交给系统，启动时检查一次，OK；宠物条订阅了 `didChangeScreenParametersNotification`；Toast 每次 `layout` 都取 `NSScreen.main`。`NSScreen.screens` 为空时 `targetScreen` 会返回 `NSScreen()`（不崩，全 0 矩形）。
- Dock / 菜单栏 / 快捷键 / 登录项的组合：`applySettings` 保证 `office / tank / strip / menu / dock` 至少有一个（A-024 说明宠物条单独存在时不算真正的入口；强制补上的 Dock 图标不写回设置，A-023）；快捷键不算入口（默认关）；登录项只影响开机。
- 退出流程：⌘Q / 菜单 / 自动收起 → `NSApp.terminate` → `applicationWillTerminate` → `provider.stop()`（A-012）。没有 `applicationShouldTerminate`，不会拦截。
- 自动收起计时器的取消：`terminated` → `scheduleQuit(60)`（先 `invalidate` 旧的）；`launched`（Claude 重新打开）→ 取消；到点时重新检查开关和会话（A-010）；到点条件不满足时不会重新武装，之后会话都结束了也不会再自动退出（可接受）。
- 多次快速点击：标题栏按钮、双击小鱼缸背景都经过 `Settings.set` → 50 ms 合并的 `applySettings`，幂等；连续点同一个 buddy 会各自排一个 2.5 秒的深链检查，失败计数可能被一次连点算成 2 次（设计如此）。
- 设置项被外部改成非法值：`office.zoom / tank.zoom / strip.zoom / tank.opacity / strip.align / strip.screen / strip.level / ui.labels / notify.sound` 都安全（有夹取或落到默认分支）；崩溃的有 `dormant.max`（A-004）和 `tally.*`（A-005）；`hidden.keys` 类型不对 → 当作空；`notify.finishedMinSeconds` 任意整数都能用。
- SwiftUI 的 `@AppStorage` 值超出 Picker 的 tag 范围只会在控制台打警告。

### 10. 安全红线
**已查，没有违反。逐条证据：**
- **不写 `~/.claude`**：App 层（`BuddyOffice / BuddyStage / PixelKit / BuddyArt`）grep 不到任何 `.claude`、`.monitor`、`cc-socks`、`.key` / `.sock` 文件后缀的字符串字面量（含 `"ccmon hook：…"` 这句诊断文案，只是文字）。运行时写入的位置只有：UserDefaults（本 App 域）、`~/Library/LaunchAgents/local.buddy-office.plist`（`LoginItem`，用户在设置页打开开机启动时）、`/tmp/buddy-office-debug.log`（`DebugTools`）、命令行开发开关指定的 PNG 路径（`--dump-*`）。顺带核对了 BuddyCore：运行时写盘只有 `FileIO.writeAtomically` 的两处（`~/Library/Application Support/BuddyOffice/identities.json`、`ledger.json`），`FakeTree` 只在 `replay` 里往假 home 写。改 `~/.claude/settings.json` 的只有安装脚本 `scripts/hook-merge.py`。
- **不联网**：grep `URLSession / NSURLConnection / Network / WebKit / WKWebView / CFNetwork / NWConnection / URLRequest / socket / Sparkle / 第三方 SDK` 在范围内 0 处。`URL(string:)` 的两处用途是 `x-apple.systempreferences:…` 常量（`NSWorkspace.open`）和 `claude://code/…` 深链（主机 ID 经 `^local_[A-Za-z0-9-]{1,64}$` 校验）。
- **不碰钥匙串 / 凭据 / `*.key` / `*.sock`**：grep `Security / SecItem / keychain` 0 处。桌面元数据的读取（`DesktopMeta`）用 `local_*.json` 文件名过滤，碰不到 `.key` / `.sock`；BuddyCore 的 `FileIO` 拒绝这两种后缀。
- **进程 / 脚本**：`NSAppleScript`（`JumpService.swift:106-129`）只执行固定模板，唯一的插值是 `tty`，来自 `sysctl` 的设备名（`/dev/ttysNNN`），不含引号或换行；只做「选中标签页 + 前置」，不读窗口内容；`Process / NSTask / system` 0 处；LaunchAgent 的命令是固定的 `open -g -b local.buddy-office`。
- **prompt 不出现在日志 / UI / 通知**：日志点逐个核对（`DebugTools.log`、`NSLog`、`print`）：生产路径可达的只有 `SystemHelpers.swift:34,35,60`（固定文字 / 热键结果码）和 `JumpService.swift:126`（AppleScript 错误字典，含错误号 / 消息 / App 名）；`AppModel.swift:254` 的 `NSLog("demo: 跳转到 …")` 只在演示模式（假标题）；`--prof` 才写的耗时；`AppDelegate.swift:104,107` 的 `--test-jump` 会把真实会话标题写进 `/tmp` 日志（开发开关，见 A-015）。用户可见的文字来源：会话标题（登记表 name / 桌面标题 / 会话记录里的 custom-title、ai-title / 目录名）、cwd（仅悬停卡，隐私模式隐藏）、工具 detail（Bash 命令 / 文件名 / 搜索词 / 域名，桌牌与提示，隐私模式隐藏；`AlertCoordinator.text` 的提示正文里会出现 Bash 命令的前 1–2 个词，系统通知会把它留在通知中心里，隐私模式下只写「有个权限请求」）、桌面本轮总结 `statusDetail`（悬停卡，模型生成的进度说明，不是用户 prompt，隐私模式隐藏）。BuddyCore 在解析 hook 时把 `UserPromptSubmit.extra` 置空、`AskUserQuestion.detail` 置空（`LineSanitizer.finalize`、`ToolTracker.pre`）。我没有逐行审 BuddyCore 的会话记录解析，只核对到了 App 层显示的字符串来源。
- 其他：`--data-root DIR` 会把所有读写换到一棵假的 home 树（命令行开关）；发布版二进制也接受这些开发开关，但需要有人用命令行启动。

### 11. 文案 / 文字类
**已查；发现 A-019。**
- 所有用户可见的 UI 文字（菜单、设置页、提示卡、通知、悬停卡、桌牌、工具提示、无障碍标签）都是中文；例外：悬停卡的 `effort / permissionMode / modelName`、`statusDetail` 是数据里的英文原文，`tok` 缩写，产品名（Claude、VS Code、DeepSeek、GLM、MCP、Dock）保持英文。
- 拼接边界：空 detail → 尾随空格 / 空引号；负时间只有 `idleMinutes` 没夹；标题空白 / 超长 / 含换行只有桌牌和悬停卡有保护；token = 0 不显示（`> 0` 才拼）；超大 token 数写成 `1.8B tok`；`String(format: "%d", Int)` 在 64 位上只对 < 2^31 正确，本项目里格式化的分钟数远小于此。

### 12. 其他（性能陷阱、竞态、取整、时区 / 夏令时 / 跨午夜）
- 性能：A-017、A-025。
- 跨午夜：`tallyToday()` 的 1 秒缓存最多让白板在 0 点后晚 1 秒清零；`SceneClock` 每秒重算，含日期。夏令时：只有格式化，没有按 86400 秒的日期运算，没有问题；时区 / 历法的缓存见 A-028。
- 取整：`TextLayout.place` 统一取整到设备像素，PixelView / FrameRenderer / text-audit 共用；`Int(x.rounded(.down))` 处都是有限值。
- 竞态：`AppModel.tick` 里 `Date()` 与 `model.time` 分开读（`director.update` 用的是 tick 开头读的 `t`，`render` 里再读一次更晚的 `model.time`），保证 `poseSince <= time`，没有负的 `t`。
- 数据竞态 / 死锁：`SessionStore.stop()` 是 `queue.sync`，回调用 `async` 投递到主线程，没有互等；`TextRenderer` / `OfficeScene.inkExtent` 的锁序单向。
- 迟到的回调：`setDemo` 里旧 `SessionStore` 已经 `stop()` 并被释放（回调闭包是 `[weak self]`），不会把旧快照灌回来；`MockSource` 的定时器已 `invalidate`。

---

## 3. 审查过的文件清单（每个文件一行）

图例：数字对应上面 12 项检查；`✓` = 已查没有问题；`A-xxx` = 有发现。「行数」是 03:25 的行数。

### BuddyOffice（21 个文件，约 2000 行）
| 文件 | 行数 | 查了哪些项 | 结论 |
|---|---|---|---|
| `main.swift` | 12 | 1,10 | ✓（`--unregister-login` / `--version` 只在命令行参数时执行） |
| `AppDelegate.swift` | 146 | 1,4,5,8,9,10 | A-012（退出）、A-015（`--test-jump` 写标题）；IUO `model` 见第 1 项 |
| `AppModel.swift` | 309 | 1,3,4,5,7,8,9,12 | A-003、A-004、A-007（调用方）、A-010、A-012、A-016、A-017、A-021、A-023、A-024 |
| `AlertCoordinator.swift` | 134 | 1,3,7,9,10,11 | A-018、A-022 |
| `DebugTools.swift` | 128 | 6,10 | A-015 |
| `JumpService.swift` | 180 | 1,4,5,8,9,10 | A-013、A-014、A-026 |
| `NotificationService.swift` | 67 | 5,8,9,10,11 | A-023（授权从不主动请求）；其余 ✓ |
| `OfficeWindowController.swift` | 105 | 2,3,5,9 | A-017（`onHover → wake`）；`zoom` 现在走 `effectiveZoom`，✓ |
| `Panels.swift` | 64 | 1,5,6,9 | ✓（悬停卡每 tick 重建见 A-025） |
| `PixelView.swift` | 197 | 2,5,6,7,8 | A-002（`mouseDownCanMoveWindow`）、A-009（调用点）；其余 ✓ |
| `Providers.swift` | 25 | 9 | A-001（`EmptyProvider` 无问题） |
| `RealProvider.swift` | 12 | 9,10 | A-001 |
| `Settings.swift` | 53 | 3,7,9,12 | A-004、A-005、A-016、A-018、A-028 |
| `SettingsView.swift` | 138 | 1,4,9,11 | A-001、A-012、A-023 |
| `SoundSynth.swift` | 67 | 3,4,6,8 | ✓（WAV 生成、后台队列、`players` 只在队列上访问） |
| `StatusItemController.swift` | 72 | 5,6,9,11 | A-019（标题）、A-025（toolTip）；其余 ✓ |
| `StripPanelController.swift` | 158 | 2,5,9 | A-006、A-024、A-025（30 Hz） |
| `SystemHelpers.swift` | 92 | 1,5,8,9,10 | A-010、A-015、A-016、A-023 |
| `TankPanelController.swift` | 106 | 2,9 | A-002；显示器拔掉 ✓ |
| `TitleBarButtons.swift` | 94 | 5,7,9 | A-002；`cache` 有界 ✓ |
| `ToastController.swift` | 71 | 5,6,9 | ✓（剩余 toast 不重排：外观小瑕疵，不单列） |

### BuddyStage（24 个文件，约 5000 行）
| 文件 | 行数 | 查了哪些项 | 结论 |
|---|---|---|---|
| `OfficeScene.swift` | 505 | 2,3,5,7,8,9,12 | A-008、A-011、A-018、A-025；`hitID` / `presentAt` 范围 ✓ |
| `OfficeLayout.swift` | 75 | 2,3 | A-011（`maxSeat` 无上限）；`effectiveZoom` 已夹取 ✓ |
| `RoomRenderer.swift` | 323 | 2,3,4,9,12 | A-005、A-025（`bake`） |
| `SeatRenderer.swift` | 355 | 2,3,4,8,12 | A-025（`tmp` Canvas）；`screenScratch` 有锁 ✓ |
| `Performer.swift` | 486 | 1,2,3,7,12 | A-020（`.mcp` 分支）；`helperTracks` 有界 ✓ |
| `VisualDirector.swift` | 80 | 1,7,9 | A-007、A-018、A-027 |
| `Walkers.swift` | 233 | 2,3,7 | A-025（每帧 Canvas）；✓ |
| `PoseLibrary.swift` | 199 | 2,3 | ✓（依赖 `t >= 0` 的隐含不变量） |
| `ScreenContent.swift` | 358 | 1,2,3,7,8 | A-018（`staticCache`）；所有 `Int(t/…)` 的 `t` 有限 ✓ |
| `PlateCopy.swift` | 162 | 3,10,11 | A-019、A-020 |
| `HoverCard.swift` | 92 | 2,3,10,11 | A-019、A-025；`zoom` 除法 ✓ |
| `ToastCard.swift` | 53 | 2,11 | ✓ |
| `TankScene.swift` | 183 | 2,3,7 | ✓ |
| `StripScene.swift` | 107 | 2,7,9 | A-024（空场景不画东西） |
| `SkyRenderer.swift` | 116 | 2,3 | ✓ |
| `SceneClock.swift` | 24 | 8,12 | A-028；锁 ✓ |
| `KeyHasher.swift` | 15 | 3 | ✓ |
| `DemoScript.swift` | 224 | 3,9,12 | A-021、A-029 |
| `FlickerScan.swift` | 233 | 2,3,4 | A-029（开发工具） |
| `StageRun.swift` | 197 | 3 | A-029（开发工具，`Int(hour)` 参数） |
| `StageCommands.swift` | 486 | 3 | A-029（开发工具；文件在审查期间仍在被修改） |
| `TextAudit.swift` | 237 | 2,3 | ✓（开发工具；区间上界都用 `max` 守卫） |
| `TextAuditRunner.swift` | 283 | 8 | ✓（开发工具；`hoverStats` 全局变量只在单线程 runner 里用） |
| `AuditFixtures.swift` | 127 | 3 | ✓（开发工具） |

### PixelKit（12 个文件，约 1400 行）
| 文件 | 行数 | 查了哪些项 | 结论 |
|---|---|---|---|
| `Canvas.swift` | 369 | 1,2,3,6,8 | A-009；其余 ✓ |
| `TextRenderer.swift` | 169 | 3,7,8 | ✓（FIFO 600 / 4000 有界，锁正确）；`scale = 0` 见 A-029 |
| `Frame.swift` | 89 | 2,3 | ✓ |
| `Color.swift` | 100 | 2,3 | ✓（含 `IntRect`） |
| `Palette.swift` | 192 | 1,2 | ✓（`preconditionFailure` 只在名字不存在时，实参都是封闭集合） |
| `Sprite.swift` | 126 | 1,8 | ✓ |
| `Motion.swift` | 84 | 3 | ✓（弹簧稳定、NaN 不进 `Int()`） |
| `PixelFont.swift` | 122 | 8 | ✓（审计钩子有锁） |
| `PixelRNG.swift` | 19 | 3 | ✓ |
| `Prof.swift` | 24 | 8 | ✓（仅开发开关时写 `acc`） |
| `Export.swift` | 115 | 1 | ✓（PNG / GIF / 总表，只在工具里用） |
| `Info.swift` | 1 | – | ✓ |

### BuddyArt（31 个 Swift 文件，约 6900 行；绝大部分是代码形式的精灵表）
| 文件 | 行数 | 查了哪些项 | 结论 |
|---|---|---|---|
| `Character/Appearance.swift` | 140 | 1,3 | A-027；枚举强制解包安全 ✓ |
| `Character/BuddyRig.swift` | 171 | 2,3 | ✓ |
| `Character/CharacterArt.swift` | 59 | 1,7 | ✓ |
| `Character/Limbs.swift` | 114 | 2,3 | ✓（手位置由弹簧决定，有界） |
| `Character/ShadeKit.swift` | 122 | 1,2 | ✓（`preconditionFailure` 只在构建期） |
| `Character/Helpers.swift` | 147 | 1 | ✓ |
| `Character/Blink.swift` | 34 | 2 | ✓ |
| `Character/Heads.swift` | 124 | 2 | ✓ |
| `Character/Hair.swift` | 115 | 2 | ✓ |
| `Character/HairStyles.swift` | 1299 | 1,2 | ✓（静态精灵数据 + 构建期断言） |
| `Character/Outfits.swift` | 891 | 1,2 | ✓（同上） |
| `Character/Accessories.swift` | 428 | 1,2 | ✓（同上） |
| `Character/Faces.swift` | 237 | 1,2 | ✓（同上） |
| `Character/Torso.swift` | 209 | 2 | ✓ |
| `Character/Chair.swift` | 245 | 2 | ✓ |
| `Icons/AppIconArt.swift` | 134 | 2 | ✓ |
| `Icons/Bubbles.swift` | 199 | 1,2 | ✓ |
| `Icons/ChromeArt.swift` | 84 | 1 | ✓（`"plate.\(state)"` 只有 4 种） |
| `Icons/MenuBarIcon.swift` | 87 | 2 | ✓ |
| `Palettes/Light.swift` | 111 | 2,3,7,8 | ✓（缓存 400 条清空，有锁） |
| `Palettes/MasterPalette.swift` | 174 | 1 | ✓（构建期断言：场景色 ≤ 256） |
| `Room/RoomArt.swift` | 357 | 1,2 | ✓ |
| `Workstation/SeatGeometry.swift` | 23 | 2 | ✓（`plateH` 审查期间由 10 改为 12，`Metrics.plateH` 跟着走） |
| `Workstation/CellPreview.swift` | 69 | 1,2 | ✓（预览工具） |
| `Workstation/Desk.swift` | 56 | 1 | ✓ |
| `Workstation/DeskProps.swift` | 74 | 1 | ✓ |
| `Workstation/PoseProps.swift` | 85 | 1 | ✓ |
| `Workstation/PropArt.swift` | 128 | 1,2 | ✓ |
| `Workstation/PropLegend.swift` | 53 | 1 | ✓ |
| `SheetRenderer.swift` | 23 | 2 | ✓（`filter!` 前有判空） |
| `ArtCommands.swift` | 163 | 3 | A-029（开发工具，参数无夹取） |
| `Character/STYLE.md` | – | – | 非代码，未审 |

### buddyctl / buddydump
| 文件 | 行数 | 查了哪些项 | 结论 |
|---|---|---|---|
| `buddyctl/main.swift` | 51 | 1,3 | ✓（`runProbe` 用固定参数；子命令的参数问题见 A-029） |
| `buddydump/main.swift` | 11 | – | ✓ |

### 只读了 API 语义的 BuddyCore 文件（不作为审查对象）
`SessionStore.swift`（`stop` / `diagnostics` 的 `queue.sync`、回调投递到 `.main`）、`SessionEngine.swift`（`shutdown`、`diagnostics`、`.away → .live` 时的 `appearedAfterLaunch`、`title(_:)`）、`TokenLedger.swift`（`flush` / `cancel`）、`IdentityResolver.swift`（`assignSeat` 取最小空位、`reroll`）、`Paths.swift`、`TimeUtil.swift`、`LineSanitizer.swift`、`RegistryScanner.swift` / `DesktopMetaReader.swift`（`title` 字段的过滤）、`ToolCatalog.swift`、`Hashing.swift`、`FileWatcher.swift`（首段）。

### 建议：给 BuddyOffice 加一个测试目标
`BuddyOffice` 是可执行目标，没有测试；`AlertCoordinator`、`Settings`、`AutoQuit`、`AppModel.refreshDerived`、`JumpService.validHostID / 判据` 都是可以纯逻辑测试的。SwiftPM 支持对可执行目标 `@testable import`（Package.swift 加一个 `.testTarget(name: "BuddyOfficeTests", dependencies: ["BuddyOffice"])`），或者把这些纯逻辑挪进 `BuddyStage`（已有 Swift Testing 目标）。上面 A-004、A-010、A-018、A-021、A-022 的回归测试都依赖这一步。

---

## 4. 第 7 项：缓存 / 字典 / 数组增长表

| 位置 | 类型（键） | 增长因素 | 上界 / 清理 / 驱逐 | 结论 |
|---|---|---|---|---|
| `AlertCoordinator.episodes` | `[String: Episode]`（buddy key） | 会话数 | 每次 `observe` 删除不在快照里的 key；`.away` 的保留到快照消失 | 有界（≤ 快照数） |
| `AlertCoordinator.prevActivity` | `[String: Activity]` | 见过的会话数（`Activity` 可含最多 160 字工具 detail） | 无清理 | **无界，慢**（A-018） |
| `AlertCoordinator.finished` | `[String: FinishedPending]` | 触发即删；会话在 8 秒内离场则残留 | 无 | 无界，极慢（A-018） |
| `AlertCoordinator.lastAlert` | `[String: Date]`（`key\|种类`） | 每会话最多 3 条 | 无清理 | **无界，慢**（A-018） |
| `AlertCoordinator.recent` | `[(key, at)]` | 提醒次数 | 每次 `post` 按 2 秒窗口过滤 | 有界 |
| `AlertCoordinator.waitingKeys` | `Set<String>` | – | 每次 `observe` 重建 | 有界 |
| `Settings.tallyCache` | 单个元组 | – | – | 固定 |
| UserDefaults `tally.YYYY-MM-DD` | 每天 1 个键 | 天数 | 无清理（本机 plist 已有 2 条） | **无界，极慢**（约 365 条/年，A-018） |
| UserDefaults `hidden.keys` | `[String]` | 每次「隐藏这个 buddy」加 1 项 | 只有「显示被隐藏的 buddy」整体清空 | 无界，极慢 |
| `PixelView.textLayers / textKeys / textFrames / textShown / lastTexts` | 数组 | 同屏文字段数的峰值 | 只增不减（多出的 layer 隐藏） | 有界（峰值，约几十到一百） |
| `PixelView.surfaces` | `[IOSurface]` | – | 固定 3 块，尺寸变化整组重建 | 有界 |
| `PixelButton.cache`（static） | `[String: NSImage]` | icon × state × scale | ≤ 3 × 4 × (1–3) | 有界 |
| `ToastController.toasts` | `[Toast]` | 提醒次数 | ≤ 3，`close` 时移除 | 有界 |
| `TankPanelController.seatsBySlot`、`StripPanelController.slotSeats` | `[Int: BuddySnapshot]` | – | 每帧重建，≤ 8 | 有界 |
| `SoundSynth.players` | `[Int: AVAudioPlayer]` | – | 4 个 | 有界 |
| `OfficeScene.seatedAt` | `[String: Double]` | 走路进场后坐下的会话数 | 无清理（并导致 A-008） | **无界，慢** |
| `OfficeScene.lastApp` | `[String: (Appearance, Int)]` | 在场过的会话数 | 无清理 | **无界，慢** |
| `OfficeScene.emptyApps` | `[Int: Appearance]` | 座位号 | ≤ 峰值桌数 | 有界 |
| `OfficeScene.seatSigs / seatCaches / plateCache` | `[Int: …]` | 座位号 | 只增不减，≤ 峰值桌数（`SeatCache` 每个 48×62×8 B ≈ 24 KB） | 有界 |
| `OfficeScene.inkExtentCache`（static） | `[TextStyle: InkExtent]` | 文字样式 | 3–4 个（颜色被规一化） | 有界 |
| `OfficeScene.prevKeys` | `Set<String>?` | – | 人员变化时整体替换 | 有界 |
| `WalkerSystem.walkers` | `[String: Walker]` | 进出场次数 | `cleanup(time:)` 按时长删（只在办公室渲染时调用，隐藏时不增长） | 有界 |
| `VisualDirector.performers / applied / pending` | `[String: …]` | 在场人数 | 每次 `update` 按 present 修剪 | 有界 |
| `VisualDirector.appearances` | `[String: Appearance]` | 见过的会话数 | 仅 `reroll` 删单个 | **无界，慢**；并使 `resolve` 的 `existing` 越来越大（A-027） |
| `Performer.helperTracks` | `[String: HelperTrack]` | 小助手数 | 离场 0.6 秒后删 | 有界 |
| `Performer.actionCache / candidateCache` | 单槽 | – | – | 固定 |
| `TankScene / StripScene` 的 `slotSigs / slotCaches` | `[Int: …]` | ≤ 8 | 每帧重建 / ≤ 8 | 有界 |
| `ScreenContent.staticCache`（static） | `[StaticKey: Bool]`（`ScreenKind` × seed） | `ScreenKind` 含 `.doc(扩展名)`、`.mcpApp(server 名)`、`.retry(a, b)`；seed < 977（每人一个） | 无清理 | 理论无界；实际 = 见过的（扩展名 × server × 会话）组合，几百到几千条 × 约 100 B |
| `Lighting.resolvedCache`（static） | `[ResolvedKey: Resolved]` | 外观 × 光照 × 光晕 | > 400 条整体清空 | 有界（约 1 MB） |
| `TextRenderer.cache / order`（单例） | `[Key: TextImage]` | 文字内容 × 样式 × scale × maxWidth（每秒每个忙的 buddy 一条新的状态串） | 600 条 FIFO 驱逐（非 LRU） | 有界（估计上限约 30 MB） |
| `TextRenderer.sizes` | `[Key: CGSize]` | 同上 | > 4000 条整体清空 | 有界 |
| `SceneClock.cached`、`SeatRenderer.screenScratch`、`Performer` 单槽缓存 | 单个 | – | – | 固定 |
| `CharacterArt.book / PropArt.book / BubbleArt.book / RoomArt.book / HelperArt.book / ChromeArt.book` | `SpriteBook` | 启动时构建 | 只读 | 固定 |
| `Prof.acc`（开发） | `[String: …]` | 段名 | 固定几十个 | 有界 |
| `/tmp/buddy-office-debug.log` | 文件 | 每次 `applySettings`（热键开）/ 自动收起 / 开发开关追加一行 | 无上限 | **无界，慢**（A-015） |
| 通知中心里的 `buddy.<key>` | 系统通知 | 每个 key 一条（相同 id 替换） | `buddy.multi` 永不清除 | 少量（A-022） |

---

## 5. 第 4 项：主线程同步 IO / 阻塞表

「频率」指最坏 / 典型触发频率。「最坏耗时」标了（估计）的是没有实测。

| # | 位置 | 线程 | 频率 | 做什么 | 最坏耗时 |
|---|---|---|---|---|---|
| 1 | `AppModel.tick`（渲染办公室 / 小鱼缸 / 宠物条 + `alerts.observe` + 菜单栏 / Dock 更新） | 主线程 | 30 / 15 / 10 / 4 Hz（A-017：鼠标移动时可更高） | 纯 CPU，没有文件 / 进程 IO | DESIGN.md 第 6 节：30 Hz 的冷脉冲比热循环贵 5–9 倍；CPU 预算的实测见第 9 节 |
| 2 | `AppModel.isUserLooking(.desktop)` → `DesktopMeta.isMostRecentlyFocused`（`JumpService.swift:172`） | 主线程（在 `tick` 里） | 每个「即将提醒」的桌面会话事件一次（Claude 在最前且 `notify.suppressWhenFocused` 开）；做完了的判定一次 | 3 层目录枚举 + 读 / 解析全部 `local_*.json` | 本机 41 个文件 / 0.7 MB：（估计）3–8 ms；线性增长，千级会话 100 ms 以上（A-014） |
| 3 | `AppModel.isUserLooking(.terminal)` → `JumpService.hostApp(of:)` | 主线程 | 每次提醒判定（终端会话再加 8 秒后一次） | `sysctl(KERN_PROC_PID)` ≤ 12 次 + `NSRunningApplication(processIdentifier:)` | < 1 ms |
| 4 | `JumpService.jumpDesktop`（点击 buddy / 菜单栏菜单项 / 提示卡） | 主线程 | 每次点击 | `NSWorkspace.open(url)`；`lastFocusedAt` ×1、`isMostRecentlyFocused`（全量）×1，2.5 秒后再 `lastFocusedAt` ×1 | 同 2，每次约（估计）5–10 ms |
| 5 | `JumpService.jumpTerminal` / `selectTerminalTab` | `jump` 串行队列（后台） | 每次点击终端会话 | sysctl；`NSAppleScript` | 授权提示未答复时约 2 分钟，队列被占用（A-013）；不阻塞主线程 |
| 6 | `applicationWillTerminate` → `SessionStore.stop()` | 主线程 | 退出一次 | `queue.sync`（ingest）+ `engine.shutdown()`：`ledger.cancel()`、`flush()` 里 `queue.sync`（tokenscan，`.background`）+ 写 `identities.json` / `ledger.json` | 通常 < 50 ms；最坏 ≈ 一个大文件的扫描批次（首次全量 0.34–0.47 s）（A-012） |
| 7 | `AppModel.setDemo`（菜单「演示模式」） | 主线程 | 用户点击 | 同 6 + 新建 `SessionStore` / `MockSource` | 同 6 |
| 8 | `SettingsView.onAppear` / 「刷新」/「重新启用深链」→ `AppModel.diagnosticsText()` → `SessionStore.diagnostics()` | 主线程 | 每次打开设置页 / 点按钮 | `queue.sync`（等一次 poll）；引擎里最多每 30 秒读一次 `~/.claude/settings.json`（≤ 4 MB） | 通常 < 20 ms；最坏 = 等一次 poll |
| 9 | `LoginItem.set`（设置页开关） | 主线程（SwiftUI 的 Binding setter） | 用户点击 | `SMAppService.register()`（XPC）+ `createDirectory` + `plist.write` | （估计）10–100 ms，没测 |
| 10 | `DebugTools.log`（`HotKey.register` / `AutoQuit` / `--prof` / 开发开关） | 主线程 | 每次 `applySettings`（热键开着时） | open + seek + write + close `/tmp/buddy-office-debug.log` | < 1 ms |
| 11 | `StripPanelController.poll` | 主线程 | 30 Hz（远处 10 Hz 有效） | `NSEvent.mouseLocation` + 命中缓冲查询 + 悬停卡（A-025） | 微秒级 |
| 12 | `NotificationService.post`（无系统授权时 `toast.show`） | 主线程 | 每条提醒 | `Canvas` + `NSPanel` 创建 + 首次 `PixelView.show` | DESIGN.md 实测 8–25 ms；系统通知 `add` 和 `refresh` 是异步 |
| 13 | `SoundSynth.play / prewarm` | `buddy.sound` 后台队列 | 每条提醒 | `wav()` 合成 + `AVAudioPlayer` | 不在主线程 ✓ |
| 14 | `Settings.tallyToday / addTally` | 主线程 | 每秒最多一次（缓存）/ 每次「做完了」 | `UserDefaults.integer` + `DateFormatter.string` / `UserDefaults.set` | 微秒级 |
| 15 | `TextRenderer.image / measure`（CoreText 排版） | 主线程 | 缓存未命中时（每秒每个忙的 buddy 数次） | 排版 + 绘制文字图 | 每次 0.1–0.5 ms；进程内第一次加载苹方字体数十毫秒（一次） |
| 16 | `CharacterArt.book / PropArt.book / Pal.built` 等静态初始化 | 主线程 | 首次渲染一次 | 解析 + `ShadeKit` 生成全部精灵、建调色板 | （估计）20–80 ms，没测 |
| 17 | `RoomRenderer.bake`（`OfficeScene` 布局 / 光照变化时） | 主线程 | 窗口边缘拖动每一步 + 每 1.25 分钟（昼夜过渡） | 每像素多次 `Pal.dx(String)` 查找 | （估计）默认几毫秒；1 倍缩放大窗口几十毫秒（A-025） |
| 18 | `NSWorkspace.shared.open(url)`（设置页按钮 / 深链） | 主线程 | 用户点击 | LaunchServices 调用 | 通常 < 10 ms |
| 19 | `NSWorkspace.shared.frontmostApplication` | 主线程 | 每次 `isUserLooking` | 读缓存 | 微秒级 |

---

## 6. 需要运行验证 / 我没有覆盖的部分

- 需要一次真机（或 App 内自检）确认的：A-002（小鱼缸 / 标题栏的真实点击）、A-003（最小化窗口被弹回）、A-006 的 Dock 变化那一段、A-012 / A-014 / A-025 的耗时（`buddyctl bench --sleep-ms 33`、`--prof`）、A-017 的 CPU 影响（120 Hz 触控板悬停时用 `scripts/measure.sh`）、A-026 的「深链在目标已是最近聚焦会话时是否前置 Claude」、A-028 的时区变化行为。
- 建议的最小验证方式：在 `AppDelegate` 里加 `--test-minimize`（A-003），并在 `--self-test` 里记录 `pixelView.mouseDownCanMoveWindow` 和 `panel.isMovableByWindowBackground`（A-002）；这两个都不需要任何系统授权。
- 没覆盖的：BuddyCore 的内部实现（只读了被 App 调用的 API 语义）；GUI 的实际观感；`text-audit` 的结果（开发者正在修，我只审了这些工具代码里有没有会崩的地方）；`Tests/` 目录下的测试代码；`scripts/` 里的安装 / 卸载 / 打包脚本（只看了 `build-app.sh` 里的 Info.plist：没有 `LSUIElement`，有 `NSAppleEventsUsageDescription`，ad-hoc 签名，没有 hardened runtime，没有 entitlements）。
- 没有发现、但值得开发者留意的：`Package.swift` 里 `swiftLanguageMode(.v5)`，所以 `nonisolated(unsafe)` 和全局可变状态没有编译期的并发检查；一旦切到 Swift 6 语言模式会冒出一批警告 / 错误（本审查已经把这些位置都列在第 2 节第 8 项里）。

---

## 7. 顺带发现、转交给 BuddyCore 审查者的观察（不计入上面的统计）

1. `IdentityResolver.load`（`IdentityResolver.swift:210`）对持久化的 `seat` 不做范围校验；`compressSeats()` 只在第一次 `poll` 里对「当时已在场」的 buddy 执行，之后才出现的身份走 `assignSeat`，它优先沿用持久化的座位号（`IdentityResolver.swift:147-153`）。被写坏的座位号会一路传到 App 层（见 A-011）。建议数据层对输出的 `seat` 夹到 `0..<64`，`load` 丢弃 `seat < 0 || seat > 999` 的值。
2. `TimeUtil.date(ms:)`（hook 的 `ts` 走这条）不检查有限性 / 范围；`date(fromJSONMillis:)` 只检查 `isFinite && > 0`，没有上界。见 A-020。
3. `TokenLedger.flush()` 是对 `.background` QoS 队列的 `queue.sync`，被 `SessionStore.stop()`（主线程 → ingest 队列同步）调用。见 A-012。
4. `SessionEngine.title(_:)`（`SessionEngine.swift:866-878`）对登记表 `name` / 桌面 `title` 不 trim、不限长度、不去换行（数据层保证非空串，但可以是纯空白）。见 A-019。
5. `SessionEngine.aliveRecords`（`SessionEngine.swift:194-201`）里 `entry!` 的强制解包前有 `entry == nil ||` 短路，安全。
