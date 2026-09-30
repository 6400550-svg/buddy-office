# R3c 终审复查（应用层 / AppKit 胶水）

复查员：R3c（全新视角）　范围：`Sources/BuddyOffice/**`　方法：只读主目录；所有编译 / 测试 / 探针都在 scratch 拷贝（`.build-r3c`）里做；开发副本只用 `local.buddy-office.dev.r3c`，实验完已 kill 自己的 pid、`defaults delete` 并删掉了自己的偏好 plist。

## 结论

**新发现：P0 = 0，P1 = 0，P2 = 3，P3 = 6。**
「没有新的 P0–P1」；但按验收条款 ⑤（不许再出新的 P0–P2）这一轮**没有过关**：有 3 条 P2（一条提醒逻辑、一条通知兜底、一条测试基础设施），每条都有可复现的证据。修法都很小。

## P2

### R3c-01 [P2] 合并提醒「N 位同事在等你」的 N 是「最近 2 秒里发出的条数」，不是「正在等的人数」；被并进去的人的提示卡被撤掉后不会补回来
- 位置：`AlertCoordinator.swift:215-228`（`post`：`recent` 滑动窗口 + `.clear` 每个 `who` + 再发一张 key 为 `multi` 的卡）。
- 现象：A 在 t=1.5 提醒、B 在 t=1.9 提醒（合并成「2 位同事在等你」，A、B 各自的卡被撤掉）；C 在 t=3.5 提醒时，窗口里只剩 B、C（A 的记录已经 ≥ 2 s），于是又撤掉 B、C 各自的卡，并用同一个 key 把合并卡换成**还是「2 位同事在等你」**——实际有 3 个人在等，A 已经没有任何卡片覆盖了，只有 Dock 角标 / 菜单栏还知道有 3 个。B、C 处理完时合并卡被撤掉（`multiShown.keys = {B,C}` 与 `waiting` 不相交），A 还在等但界面上再没有任何提示卡。
- 证据（scratch 拷贝里的探针 `R3cProbeTests.mergedCountUsesASlidingWindowNotTheNumberWaiting`，逐 0.1 s 喂快照）：
  ```
  t=1.5 post t:a 想用 Bash：git push（等你批准）
  t=1.9 clear t:a / clear t:b / post multi 2 位同事在等你
  t=3.5 clear t:b / clear t:c / post multi 2 位同事在等你
  waitingKeys=["t:a","t:b","t:c"]   → #expect(lastMulti == "3 位同事在等你") 失败：实际 "2 位同事在等你"
  ```
  随机模拟（3 个会话、1500 个随机场景、terminal / desktop 混合）里，共 1186 次「在等你」合并提醒，其中 349 次（29%）的 N 小于「已经提醒过且仍在等」的人数（我的模型：某 key 的等待段被记过「已覆盖」且当前仍是等待类）。同一个模拟里没有发现「重复提醒」「整段等待没被任何提醒覆盖」「静默后记账残留」（各 0 / 1500）。
- 为什么是 P2：边界条件（三个人的提醒到达时刻两两 < 2 s、首尾 ≥ 2 s）下，提醒内容错误 + 一个人的可见提醒被撤掉后不再补；正常路径不受影响。
- 建议：合并提醒的 N 用「当前仍在等、且已经提醒过的 key 集合」（`waitingKeys ∩ 已提醒`）而不是 `recent` 窗口里的 key；或者合并时把上一张 multi 的 keys 并进 `who`。
- 现有测试为什么没抓到：`AlertCoordinatorTests` 的合并用例只有 2 个人 / 同一个 2 s 窗口。

### R3c-02 [P2] 系统通知授权在运行期间被关掉后，兜底提示卡不会出现（直到 App 下一次被激活）
- 位置：`NotificationService.swift:90-104`（`systemAllowed` 用缓存的 `status`）；`status` 只在这几处刷新：`init`（:52）、`officeMayHaveOpened`（AppModel.swift:200，来自 `showOffice` / `applicationDidBecomeActive`）、`showSettings`（AppModel.swift:220）。没有任何周期性 / 发通知前的刷新。
- 现象：App 启动时授权是 `.authorized`（缓存），之后用户在「系统设置 → 通知」里把它关了，Buddy 一直在后台（菜单栏 App，办公室窗口被别的窗口盖住时不会被激活）：`post` 仍走 `client.add(...)`，系统直接吞掉，**没有提示卡**，只剩 Dock 角标 / 菜单栏图标 / 提示音。这正是 B-001 要求「系统通知被拒时兜底提醒确实会出现」的反面。
- 证据（探针 `authorizationRevokedWhileRunningStillNeedsTheFallbackToast`：`FakeCenter(.authorized)` → `NotificationService(available: true)` → `center.status = .denied` → `post`）：
  ```
  added=1 toasts=0
  Expectation failed: (toast.shown.count → 0) == 1
  ```
- 建议：`post` 时若缓存是 `.authorized`，先异步 `refresh` 再决定（或者 `add` 之前 / 之后拉一次 `getNotificationSettings`，`.denied` 就补一张提示卡）；或者在 App 收到 `NSWorkspace.didActivateApplicationNotification` / 每 N 分钟刷新一次。
- 备注：反方向（缓存 `.denied`、实际已授权）只会多出一张提示卡，无害。

### R3c-03 [P2，测试基础设施] `ReviewRegressionAppTests` 的 R2-008 用例和 `DesktopMetaFileIOTests` 抢全局 `DesktopMeta.baseOverride`，间歇性变红
- 位置：全局 `nonisolated(unsafe) static var baseOverride`（`JumpService.swift` 的 `DesktopMeta`）；写它的三处：`ReviewRegressionAppTests.swift:158-164`（先置 nil，再由 `RealProvider.make` 置成假 home，最后 defer 置 nil）、`DesktopMetaFileIOTests.swift:27-29`、`:44-46`。`DesktopMetaFileIOTests` 是 `.serialized`，但只在它自己的 suite 内串行，不同 suite 之间照样并行——和 R2-005 是同一类问题，R2-008 新加的用例又造了一个。
- 证据（scratch 拷贝，`swift test --skip-build`，未加任何探针时）：
  - 只跑这两个 suite（`--filter DesktopMetaFileIOTests --filter ReviewRegressionAppTests`）30 次：**4 次红**。失败输出：
    `ReviewRegressionAppTests.swift:164:9: Expectation failed: (DesktopMeta.baseOverride → "/var/folders/.../T/desktopmeta-D751F563-…") == "/x/fake-home/Library/Application Support/Claude/claude-code-sessions"`
  - 整个 `BuddyOfficeTests` 目标（`--filter BuddyOfficeTests --skip R3c`，193 个测试）20 次：**1 次红**，同一个用例、同一条断言。
  - 反过来 `DesktopMetaFileIOTests` 里 `readAll()` 也可能读到别人设置的路径（同一种竞争，我这边没抓到红，但机制一样）。
- 影响：最后一次完整回归的「全绿」不是必然的；红了的时候看起来像是 R2-008 的修复回退了。
- 建议：把三个用到 `baseOverride` 的用例放进同一个 `.serialized` suite，或者让 `RealProvider.make` 的用例不去改全局（例如把 `baseOverride` 换成传参 / 任务局部值）。

## P3（一句话标题）
- R3c-04 [P3] 时钟往回拨时（R2-014 的残留）：桌面会话「做完了」的 8 s 等待里时钟拨回，`AlertCoordinator.swift:195`（`now - f.since >= wait` 为负）会让这条待发提醒卡到时钟追上为止（探针 `finishedPendingSurvivesAClockStepBack`：拨回 1 小时后 30 秒内 0 条，之后 1 小时才补发一条过期的「做完了」）；`recent`（:216）里「来自未来」的记录也会被当成「刚发过」而错误合并。
- R3c-05 [P3] `AlertText.approvalBody`（AlertCoordinator.swift:44-49）对超长工具名在主线程上每次缩短 1 个字符就量一次提示卡宽度：2048 字（数据层对标签类字段的上限）的工具名实测 754 ms（拉丁字母）/ 1257 ms（中文），普通名字 4–7 ms；只有被写坏 / 恶意的 hook 数据能触发，且每个 buddy 每 20 s 最多一次。
- R3c-06 [P3] 设置页「数据源诊断」的 `diag` 文字只在 `.onAppear` 和按钮里生成：先看过诊断（含会话标题），再在同一个设置窗口里打开隐私模式，切到诊断页看到的仍是带标题的旧文字（R2-006 只保证生成时隐私生效）。同理「授权状态」文字 `authText` 也只在 onAppear 刷新。
- R3c-07 [P3] 办公室里点小人是「命中座位号 → 点击那一刻按座位号找会话」（`AppModel.jump(seat:)`），小鱼缸 / 宠物条是按渲染那一刻的快照再按 key 找。座位在最近一帧（≤ 100 ms）里换了主人时，点办公室里的旧画面会跳到新主人的会话。窗口极小，只列出。
- R3c-08 [P3] 开发副本（`BUDDY_BUNDLE_ID=local.buddy-office.dev…`）在设置页里开关「开机启动」，会读写和正式版**同一个** LaunchAgent 文件 `~/Library/LaunchAgents/local.buddy-office.plist`（SystemHelpers.swift `LoginItem.agentURL`）：关开关会把用户真实 App 的登录项删掉。只影响开发副本；我没有点过。
- R3c-09 [P3] `StripPanelController.model` 是强引用、`AppModel` 持有 `strip`：循环引用；App 生命周期内无影响（测试里每个 `AppModel` 都会泄漏一份，无碍）。

## 疑点（没有证据，不算问题）
- 提示卡的滑入起点是 `vf.maxX + 8`（屏幕外右侧）；如果主屏幕右边接着另一块显示器，起点会落在那块屏幕上，滑入的前几十毫秒会在邻屏上出现一次。本机只有一块屏幕（1408×851），没法验证。
- `.authorized` 但用户把「通知样式」设成「无」时，App 认为系统通知可用，不弹兜底卡（`UNNotificationSettings.alertSetting / alertStyle` 没看）；没法在这里造出这个系统状态。
- App Nap：开发副本 `--no-windows --demo --log-ui` 后台跑 4 分 19 秒，每秒一次的重复定时器 257 次间隔全是 1 s，没有看到定时器被拉长；只是一个条件下的负结果，没有证明真实使用（办公室窗口被别的窗口盖住）下不会被 App Nap。
- R2-016 之前没有任何测试用**真实合成器**验证过 `contentsRect` 的原点方向（现有测试用 `CALayer.render(in:)`）：我补做了实测，结论是**没问题**，见下面「覆盖清单」。

## 覆盖清单（查了什么）

**读完的源码**：`AppModel`、`AlertCoordinator`、`AlertPipeline`、`NotificationService`、`ToastController`、`PixelView`、`OfficeWindowController`、`Panels`（FloatingPanel / HoverPanelController）、`PanelShow`、`TankPanelController`、`StripPanelController`、`ScreenPicker`、`ApplyPlan`、`Settings`、`SettingsView`、`EngineConfig`、`Providers` / `RealProvider`、`TickPacer`、`BoundedWait`、`StatusItemController`、`SoundSynth`、`SystemHelpers`（DockTile / AutoQuit / HotKey / LoginItem）、`AppDelegate`、`main`、`JumpResolver`、`JumpService`（含 `DesktopMeta` / `ProcessInfoHelper`）、`DebugTools`、`SelfTests`（含 `--test-resize`、`physFootprintMB`）、`TitleBarButtons`；`Fakes` / `Fixtures` / `AppModelTests` / `PixelView*Tests` / `PanelAnimationTests` / `ReviewRegressionAppTests` 里 R2-001/008/014/016/017 相关的测试。

**跑过的**：
- scratch 拷贝完整编译；`BuddyOfficeTests` 全目标 193 个测试通过（基线）。
- 探针（`R3cProbeTests.swift`）：合并提醒计数、授权运行期撤销、`approvalBody` 超长工具名耗时（50 / 400 / 2048 字，拉丁 / 中文）、时钟回拨后 `finished` 待发、`TickPacer` 极端值（∞ / NaN）、`Settings` 极端值（`tank.opacity` = NaN / 1e300、`office.zoom` = "abc"、`notify.finishedMinSeconds` = Int.max、`idle.dozeMinutes` = Int.min：全部被夹进合法范围，无崩溃）。
- 随机模拟（`R3cFuzzTests.swift`）：`AlertCoordinator` 3 个会话 × 700 步 × 1500 个种子 × 两种配置（纯 terminal / terminal+desktop 混合），检查「等待段 ≥ 30 s 没被任何提醒覆盖」「同一段等待多次个体提醒」「全员静默后记账残留」——全部 0；另统计合并计数偏小（R3c-01）。
- **真实合成器读回**（在 scratch 拷贝里加的自检，开发副本里用真实 `PixelView` + IOSurface + `contentsRect`，再用 `CGWindowListCreateImage` 读回自己的 2× Retina 窗口，逐个美术像素块比对）：视口 70×50（桶 128×64）→ 100×60（同桶）→ 130×90（跨桶 192×128）→ 回到 70×50，四个阶段各 3500 / 6000 / 11700 / 3500 块，**0 块颜色不对（最大偏差 0）**，图层外面是 PixelView 的底色（没有残影 / 混色 / 位置偏移）。R2-016 在真实合成器上是对的。
- 开发副本自检：`--test-minimize`（PASS）、`--test-tank-click`（单击拖窗口 / 双击回办公室 / 点小人：全 PASS）、`--test-titlebar`（跑完，结果在日志里）。
- 重复跑测试找间歇性红灯：R3c-03（上面）。

**读代码逐项检查、没发现问题的**：R2-003 / R2-004 / R2-014 的状态机推演（先节流后置位：被挡住时不置位、下一拍重试，窗口一过补发，不重复、不丢、不卡）；ToastController R2-002 的顺序（先 `snap` 再 `layout` 再 `orderFront`，layout 的 x 带弹簧偏移，泄漏 / 定时器 / 关闭路径）；`OfficeWindowController` `animationBehavior = .none` 对最小化 / 全屏 / 关闭 / 出现无副作用（这个属性只管 order-in / order-out 的窗口动画；`--test-minimize` 实测最小化正常）；`DebugTools.devFlagsPresent` 的 `--test-bundle-path` 例外；`RealProvider` 的 `DesktopMeta.baseOverride`；`BoundedWait` / 隐私诊断文案；点击跳转目标解析（只认在场、按 key 重找、深链 host id 正则、tty 正则、AppleScript 超时）；`AutoQuit`（只有 `NSApp.terminate`、只认 `com.anthropic.claudefordesktop`、被隐藏的 buddy 也算活会话、Claude 重开会取消）；`LoginItem` 回退（SMAppService 不行 → LaunchAgent；失败开关回退成关）；`applySettings` 没有自触发死循环（写回 `ui.dockIcon` 后 raw == effective）；主线程读文件（App 层所有读文件都走 `FileIO`，其余只有 UserDefaults 和 LaunchAgent 的存在性检查）；没有任何路径打开 `.key` / `.sock` 或联网（`URLSession` 审计测试 + 我自己 grep）；线程规则（`NSAppleScript` 在串行后台队列、`UNUserNotificationCenter` 回调回主线程、`SoundSynth` 的播放器只在自己的串行队列上、`onUpdate` 在主队列回调）；`try!` / `as!` / `fatalError` / 强制解包：只有常量 URL 和 ASCII 字面量。
- 我**没有**做的：没有在真实多显示器 / 全屏 Space / Dock 移动下验证面板定位（本机单屏，也没法造）；没有真实点击 / 拖动；没有真实的系统通知授权流程；没有改任何源码 / 测试；没有碰 `~/.claude`、`.key`、`.sock`、用户正在运行的 App。
- 副作用说明：开发副本带 `--log-ui` / `--test-*` 开关运行，往 `~/Library/Logs/BuddyOffice/debug.log`（该文件本来就存在，前几轮 QA 用过）追加了几百行 `ui:` / `minimize-test` 等日志；没有别的写入。

## 统计
| 严重度 | 新发现 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 3（R3c-01 提醒逻辑、R3c-02 通知兜底、R3c-03 测试基础设施） |
| P3 | 6（R3c-04 … R3c-09） |
