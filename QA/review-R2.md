# R2 独立复查报告（应用层：`Sources/BuddyOffice` + `Tests/BuddyOfficeTests` + `Package.swift`）

- 复查员：全新的眼睛（没看过前几轮的过程，只读了 `QA/audit-app.md`、`QA/issues-app.md`、DESIGN.md 第 8–13 节、任务书第 7 节）。
- 日期：2026-09-29，05:15–06:35（约 80 分钟）。
- 被查版本：05:20 拍的源码快照（`Sources/BuddyOffice` 30 个文件约 3140 行、`Tests/BuddyOfficeTests` 27 个文件 2181 行，全部通读）。评审期间共享源码树又有改动：`hook-merge.py`（06:14，符号链接处理，我看了 diff，没问题）、`PanelAnimationTests.swift`、新增 `SpecTraceAppTests.swift` / `SpecTraceUITests.swift`（共 714 行，我也读了）——我在 06:18 重新拷了一份最新树跑过（179 个测试，连跑 6 次全过）；`Sources/BuddyOffice` 自快照以来逐文件比过校验和，没有任何变化，所以下面的结论对现在的源码仍然成立。
- 方法：逐文件通读 + 对着修复记录挑刺；纯逻辑用 fuzz / 变异；AppKit 胶水类在私有目录的拷贝里「只建不显示」地跑；开发副本（私有 bundle id，假 home）长跑 + 外部观测；每条发现都有可复现的证据。**没有改项目里的任何源码和测试**；实验全在 `scratchpad/r2-app/`（项目拷贝 + 构建目录，1.3 GB）里，已整个删掉，只在 `scratchpad/r2-app-keep/` 留了 144 KB：`r2-fixes.diff`（四个候选补丁）、`probes/`（我的探针测试源码和窗口几何观测工具）、`evidence/`（原始输出：提示卡观测、长跑汇总、探针输出、竞态失败示例）。

## 0. 结论摘要

**统计：新发现 17 条 —— P0 0 / P1 0 / P2 6（4 条产品 + 1 条测试基础设施 + R2-016 未定论）/ P3 11（其中 R2-015 是前几轮已知、仍未修的遗留）。没有触碰任何安全红线。**（R2-016 / R2-017 是 06:31 之后的实验发现的，只做了实验、没有验证修法；R2-013 主线程已经在我写报告的同时改掉了，我读过新版 `measure.sh` / `soak.sh`，逻辑对。）

| 编号 | 级别 | 一句话 | 把握 |
|---|---|---|---|
| R2-001 | P2 | 小鱼缸 / 宠物条改「缩放」后，像素图层的大小不跟着变（画面只占 1/4 或 2/3），要等画布下一次变化才恢复（全员空闲时最长 5.1 秒） | 确认（真实控制器头测复现） |
| R2-002 | P2 | 提示卡每次出现都先「闪」在终点位置，再跳到屏幕外起点、再滑入；系统通知被拒（用户的实际情况）时每条提醒都是这条路 | 确认（外部测到 23/25 张） |
| R2-003 | P2 | 合并提醒里只要有 `blocked`，「N 位同事……」在同一次判定里先发出、马上又被撤掉，用户什么都看不到 | 确认（fuzz + 全流水线） |
| R2-004 | P2 | 被 20 秒节流挡掉的「等你」提醒，这一整段等待再也不会提醒（哪怕一直等 2 分钟） | 确认（规格取舍，见正文） |
| R2-005 | P2（测试） | 新加的 `DesktopMetaFileIOTests` 会改全局的 `FileIO.forbiddenHits / openObserver`，和 BuddyCoreTests 里断言这两个全局量「相等」的测试抢——单独放一起跑 70% 失败 | 确认 |
| R2-006 | P3 | 隐私模式没盖住设置页「数据源诊断」和「测试深链」回执里的会话标题 | 确认 |
| R2-007 | P3 | 测试进程里 `DebugTools.enabled == true`（`--test-bundle-path` 匹配了 `--test-` 前缀） | 确认（目前没有测试因此写日志，潜在） |
| R2-008 | P3 | `DesktopMeta` 不认 `--data-root`：假 home 运行时仍读真实的桌面会话元数据 | 确认 |
| R2-009 | P3 | 「只剩宠物条时补 Dock 图标」只在设置变化时重算，宠物条里的人都走了之后没有入口 | 确认（读代码） |
| R2-010 | P3 | 宠物条 3 倍 + ≥ 9 人时比 1408 pt 宽的屏幕还宽（origin.x = -16），最左边的人被挤出屏幕 | 确认（量过） |
| R2-011 | P3 | `setDemo` 不清旧数据源的 `onUpdate`，切换那一刻排在主队列里的尾巴回调会写进新状态 | 可能（概率低） |
| R2-012 | P3 | 主菜单没有 ⌘W / ⌘H / 编辑菜单 | 确认 |
| R2-013 | P3 | `scripts/measure.sh` / `soak.sh` 用 `pkill -f "<路径>"` 按子串杀进程，并行跑多个 QA 时会误杀 | 确认（开发脚本） |
| R2-014 | P3 | 系统时钟往回拨时，去抖 / 节流判定会把提醒压住（拨多久压多久） | 确认（逻辑层；现实里触发很少） |
| R2-015 | P3 | A-019 遗留：工具详情为空时文案是「在读 」「在找 ""」「运行 」（仍未修） | 确认（快照上跑过，之后相关代码没变） |
| R2-016 | P2（未定论） | 办公室窗口每次改尺寸 `PixelView` 都新建 IOSurface，CoreAnimation 长期保留用过的：测试宿主 300 步 +200 MB 不回落，真实开发副本 +21 MB（一次 60 秒内回落、一次 2 分钟没回落） | 确认有增长，「泄漏还是延迟释放」未定论 |
| R2-017 | P3 | 办公室窗口没关 `animationBehavior`：show / hide 快速反复 300 轮线程 24 → 70（B-010 的同类；设 `.none` 后不再涨） | 确认（测试宿主）；真实触发频率低 |

**最重要的 3 条**：R2-002（每条兜底提醒都闪一下，违背「零闪帧」）、R2-004（连续审批时被节流的提醒整段丢弃）、R2-001（改缩放后画面错位）。R2-003 紧随其后（触发条件窄，但行为是「提醒消失」）。

**已修好的东西这一轮的验证结果**（不重复报）：B-010（提示卡线程泄漏）在 15 分钟长跑里确认已修——线程数 9–14 平着，句柄 66–67 平着（见第 2 节）；A-002 / A-003 / B-002 的进程内自检 `--test-tank-click` / `--test-minimize` / `--test-titlebar` 在快照构建上全部 PASS；A-004 / A-005 / A-011 / A-029 的「设置被外部写坏」在运行中的开发副本上注入 12 个坏值，进程没崩、值被夹进合法范围。

**4 条产品 P2 的修法我都在私有拷贝里验证过**：R2-001 / 002 / 003 / 004 各写了补丁，跑 `BuddyOfficeTests`（含新增的 SpecTrace 套件和我的 16 个探针）195 个测试全过；R2-002 的修法还在开发副本上外部量过——13 张提示卡一张都没有再出现「先在终点」。补丁见各条「建议修法」。（P3 和测试基础设施那几条只给了建议，没有逐条验证。）

**安全红线**（逐条证据）：
- 没有打开任何 `~/.claude/sessions/*.key`、没有连任何 `/tmp/cc-socks/*.sock`、没读凭据 / 钥匙串：我所有读会话数据的开发副本都带 `--data-root` 指向我自己造的假 home（`scratchpad/r2-app/soak-home{,2,3}`；跑进程内自检的那个副本用 `--demo` 的内置假数据），没有一个进程读过真实的 `~/.claude`；**唯一的例外**是 R2-008 说的那条：App 层的 `DesktopMeta` 不认 `--data-root`，所以只要 Claude 桌面 App 在最前面、我的假会话在等你，开发副本就会（经 `FileIO`，和正式版一样）读真实的 `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json` 里的 `lastFocusedAt`——这是桌面会话元数据，不是密钥 / 凭据，也不在 `~/.claude` 下；`soak_watch` 89 个采样里 `.key` 句柄 0、`.sock` 句柄 0；生成器的 `.key` 蜜罐（普通文件 + FIFO）`honeypot_key_opened: 0`。**诚实说明**：假 home 的路径太长（超过 unix socket 的 104 字节），生成器的 `.sock` 蜜罐没建起来（报告里那条 `violations=1` 就是它，不是 App 违规），所以「没连 .sock」只有 `lsof` 的 0 作证。
- 我自己没读 `~/.claude` 下任何文件内容：只对 `settings.json` 做过 `stat`（mtime 01:34:02，早于评审开始，没被改过）；没跑 `安装.command` / `卸载.command` / `hook-merge.py install|uninstall`（连指向假文件的也没跑，`hook-merge.py` 只做了静态阅读和语法检查）。
- 没动 ccmon 文件、用量表、Claude.app：唯一碰过 Claude 的是 `NSRunningApplication.runningApplications(withBundleIdentifier:)` 读出 Claude 桌面 App 的进程对象，放进**私有**的 `NotificationCenter` 里测 AutoQuit 的通知接线，没有发信号、没有退出它。
- 没有 kill 用户的进程：用户装好的 App（pid 8520，02:43 起）全程没碰，评审结束时还在跑。我只 kill 过我自己起的 pid：89722 / 94112 / 2060 / 12761 / 20103 / 34011 / 34545（开发副本 r2 / r3 / r4 / r6 / r7 / r8 两次）、94656（我的 churn 脚本）、159（我的采样脚本）。没有 pkill 按名字杀过任何东西。（测试宿主 `swiftpm-testing-helper` 是我跑 `swift test` 起的、自己退出的，没有杀。）
- 不联网、没引入第三方依赖、没显示 / 记录用户 prompt（假 home 里的会话是生成器造的）。
- **我留下的痕迹**：scratchpad（`r2-app/` 已删，只留 `r2-app-keep/`）；`~/Library/Preferences/local.buddy-office.r{2..8}.plist`（我的私有 bundle id，已 `defaults delete` 并删除文件）；`~/Library/Logs/BuddyOffice/debug.log` 里多了约 90 行（我的开发副本带 `--log-ui` / 自检开关时按设计追加的，没有会话标题）；LaunchServices 里登记过我的 r2–r8 开发包（已 `lsregister -u`）。
- 也没有对 `local.buddy-office` 做 computer-use / 截屏 / osascript：窗口几何用的是 PROGRESS.md 认可的 `CGWindowListCopyWindowInfo`（只读位置 / 大小，不读内容）。
- 说明：评审期间我的开发副本（长跑 + 提示卡）在你的屏幕上短暂出现过窗口和右上角的提示卡（05:27–06:17，私有 bundle id，提示音已设成「无」）。同一时间主线程也在跑自己的 soak，所以我记的 CPU 数字偏高（debug 构建 + 多个进程抢核），只用来看趋势。

## 1. 发现

### R2-001 [P2] 缩放变了但画布没变时，`PixelView` 的图像层不跟着变大小（小鱼缸 / 宠物条）
- 位置：`Sources/BuddyOffice/PixelView.swift:105-135`（`show`）：`imageLayer.frame` 只在 `needImage` 为真的分支里赋值（`:124`、`:131`），而 `needImage` 只看「画布变没变 / 视口变没变 / 哈希」（`:107`、`:112`）——**没有把缩放算进去**；文字层的判断（`updateTexts`，`:164`）倒是包含缩放。调用方：`TankPanelController.render`（`TankPanelController.swift:63-98`）、`StripPanelController.render`（`StripPanelController.swift:159-180`）：缩放变了它们会 `setContentSize` / `pixelView.frame = …`，但 `TankScene` / `StripScene` 的画布内容和缩放无关（只有空办公室的牌子用到），`Frame.changeKnown == true && canvasChanged == false`（局部重绘：什么都没变就是 false）。
- 现象：设置里把小鱼缸从 2 倍改成 1 倍——窗口缩成一半，图像层还是原来的 2 倍大，只看得到画面的左上角 1/4；宠物条从 2 倍改成 3 倍——窗口变大，图像层只占 2/3，其余是空的；文字层已经按新缩放摆了，所以文字和图对不上。直到场景画布下一次变化才恢复。
- 复现（真实类、只建不显示，`Tests/BuddyOfficeTests/` 里加一个文件即可）：
  ```swift
  @MainActor @Test func tankImageLayerFollowsZoom() {
      let store = Fx.Store(); defer { store.cleanUp() }
      let p = FakeProvider(); let m = AppModel(provider: p, args: [], settings: store.settings)
      p.onUpdate?((0..<3).map { Fx.snap("t:\($0)", seat: $0, activity: .idle) })
      let tank = m.tank
      _ = tank.render(model: m, force: true)                       // 2 倍
      tank.zoom = 1                                                  // 设置改成 1 倍之后的下一拍
      _ = tank.render(model: m, force: true)
      #expect(tank.pixelView.layer!.sublayers!.first!.frame.width == tank.pixelView.frame.width)   // 实际 304 ≠ 152
  }
  ```
  实测输出：`tank zoom2: view=(304,180) imageLayer=(0,0,304,180)；zoom→1 之后：view=(152,90) imageLayer=(0,0,304,180)`（连续 5 拍都是这样）；宠物条 2→3：`view=(504,420) imageLayer=(0,0,336,280)`。
- 能持续多久：全员空闲的场景里画布变化的最大间隔是 5.1 秒（idle / dozing / sleeping 三种各 115 秒里变化 290 / 463 / 357 次，平均不到 0.5 秒）；有人在忙时画布每拍都变，几乎看不出来。
- 根因：显示层的「什么时候该更新图像层」没把缩放当输入。
- 建议修法（我已验证）：`PixelView` 记 `lastImageZoom`，`needImage` 两个分支各加 `|| z != lastImageZoom`，更新图像层时 `lastImageZoom = z`。补丁：
  ```swift
  private var lastImageZoom = 0
  needImage = frame.canvasChanged || vp != lastViewport || lastHash == 0 || z != lastImageZoom
  needImage = newHash != lastHash || vp != lastViewport || z != lastImageZoom
  … lastHash = …; lastViewport = vp; lastImageZoom = z; changed = true      // 两处
  ```
  验证：上面那个测试 0/5 过期；`BuddyOfficeTests` 全过。
- 建议的回归测试：上面的 tank 测试 + 同样的 strip 测试（2→3）+ 纯 `PixelView` 的测试（`show(zoom: 2)` 后 `show(canvasChanged: false, zoom: 1)`，`changeKnown` 真 / 假两种）。
- 为什么现有测试没抓到：`PixelViewTests` / `PixelViewDragTests` 只测鼠标；没有任何测试拿真实的 `TankPanelController` 改缩放后再渲染；`SpecTraceUITests.settingsDriveTheTankAndTheStripAndTheStripHasTheSpecifiedSize` 每次都新建控制器、只在第一次渲染时读缩放，所以看不到「运行中改缩放」。

### R2-002 [P2] 提示卡出现时先闪在终点位置，再跳到屏幕外起点、再滑入
- 位置：`Sources/BuddyOffice/ToastController.swift:31-51`（`show`）、`:57-61`（`layout`）。`show` 里先 `layout(screen:)`（`:45`）——`layout` 把**每一张**提示卡的面板放到终点 `x = targetX`（`:60`）——然后才 `t.spring.snap(to: 宽 + 20)`（`:47`）设弹簧起点、`t.panel.orderFrontRegardless()`（`:49`）。面板在屏幕上的真实位置要等下一个 1/60 秒的 `step()`（`:74`）才变成「终点 + 弹簧偏移」。
- 现象：面板先以终点位置出现（完全可见，图层内容已经画好），停 1 帧到十几帧，然后跳到屏幕右边外面，再弹簧滑回来——「闪现 → 消失 → 滑入」。另外，新提示卡到来时 `layout` 会把**已经在滑动 / 正在离场**的提示卡也拽回终点（同一个 `:60`），又一次跳动。用户的通知授权是「拒绝」（DESIGN §2 M0 第 2 项），所以**每一条提醒**都走这条路。用户的偏好是「零闪帧、动作软、不许启停」。
- 复现 / 测量（外部只读，`CGWindowListCopyWindowInfo`，开发副本 + 假 home 生成器，`--no-windows`，只有提示卡）：
  - 第一轮（240 秒，1.5 ms 轮询）25 张提示卡：**23 张**的第一次观察位置就是终点 x（如 `1310`），下一次观察才是屏幕外起点 `1411`，然后 `1401, 1388, 1374 …` 滑入。
  - 第二轮（带时间戳，5.4 ms 间隔）11 张：在终点位置停留 **4 / 6 / 12 / 18 / 19 / 21 / 22 / 23 / 24 / 125 / 293 ms**（中位 21 ms ≈ 1.3 帧；最大 293 ms ≈ 17 帧——推测是 debug 构建里主线程正忙、`orderFront` 之后的 `step()` 被推迟；release 构建的具体数字我没量，但「先摆终点再 order」的顺序是结构性的）。
- 根因：「先摆终点、再 order、再靠下一拍改成起点」。`ToastFit` / 弹簧常数都对，是顺序错了。
- 建议修法（我已验证，外部再量 13 张：**没有任何一张再被观察到停在终点位置**，首次观察都是 `1416 / 1409 / 1401`，即屏幕外起点或已在滑入）：
  ```swift
  // show()：先定弹簧起点，再摆位置
  t.spring.snap(to: Double(t.size.width) + 20)
  t.spring.target = 0
  layout(screen: screen)
  t.panel.orderFrontRegardless()
  // layout()：x 带上弹簧当前偏移（重排时不把滑动中的提示卡拽回终点）
  t.panel.setFrameOrigin(NSPoint(x: CGFloat(t.targetX + t.spring.value), y: y))
  ```
- 建议的回归测试：给 `ToastController` 加一个可注入的「orderFront」（或抽出纯函数 `ToastLayout.origin(...)`）：断言 orderFront 被调用那一刻 `panel.frame.minX >= visibleFrame.maxX`（在屏幕外）；再断言新提示卡到来时已有提示卡的 x 不变。现有的 `SpecTraceAlertTests.notificationMaintenanceAndFallbackConstantsStayAsTheSpecSays` 只钉了 `vf.maxY - 10` 之类的常数字符串，钉不住顺序，我的补丁不会让它红。

### R2-003 [P2] 合并提醒里含 `blocked` 时，同一次判定里先发出又立刻撤掉
- 位置：`Sources/BuddyOffice/AlertCoordinator.swift:212-226`（`post`）和 `:162-164`（撤除）。`post` 里 `attention`（决定文案「在等你」和 `waitingBased`）把 `.blocked` 也算进去（`:219`）；但 `blocked`（一轮做完、要你处理）的会话是 idle，**不在 `waitingKeys` 里**。于是 `observe` 末尾的 `m.waitingBased && m.keys.isDisjoint(with: waiting)`（`:163`）当场为真，把刚发出的 `multi` 又 `.clear` 掉。
- 复现：两个桌面会话都 `busy`；t=1 A 做完且 `blocked`；t=2 B 做完且 `blocked`。同一次 `observe(t=2)` 的输出：
  `[CLEAR d:a, CLEAR d:b, POST multi「2 位同事在等你」, CLEAR multi]`。
  走完整条流水线（`AlertFallbackTests.Rig`，被拒 / 已授权两种）：提示卡 `shown = [d:a「需要你处理」, multi]`、`dismissed = [d:a, d:b, multi]`；系统通知 `added = [d:a, multi]`、`removed = [d:a, d:b, multi]`（`add` 之后立刻 `removeDelivered`，能不能删掉还要看时序）。用户看到的是：A 的提示被撤、合并的一闪而过，之后什么都没有。
  fuzz（400 个种子 × 500 步，3 个会话、随机状态 / 静音 / 在看）：`multi 发出后在同一次里被撤` 146 次；其余不变量（静音的不出提醒、关掉的种类不出、同 buddy 同种类 20 秒内不重复）0 次违反。
- 根因：`blocked` 的语义是「做完了要你处理」（事件），和「正在等」（状态）不是一回事，却被塞进同一个 `attention` 集合。
- 建议修法（已验证）：`attention` 只认 `.approval / .question / .plan`；blocked 参与合并时走「有事找你」的文案（和 finished 混合一样），不当成「按等待清除」。补丁：
  `let attention = kinds.allSatisfy { $0 == .approval || $0 == .question || $0 == .plan }`
- 建议的回归测试：`AlertCoordinatorTests` 加：两个桌面会话 2 秒内先后 blocked → 同一次 `observe` 的输出里有 `.post(multi)` 且没有 `.clear(multi)`，之后每一拍也没有；`AlertFallbackTests` 同样场景断言 `toast.dismissed` 里没有 `multi`。

### R2-004 [P2] 被 20 秒节流挡掉的「等你」提醒，这一整段等待再也不会提醒
- 位置：`AlertCoordinator.swift:182-185`（`handleWaiting`）：先 `ep.alerted = true`（`:182`），后 `guard throttle(...) else { return [] }`（`:184`）。被节流挡住时这段等待已经被标成「提醒过」，之后每一拍都在 `guard !ep.alerted` 处直接返回。
- 现象：Claude 连着要批准几个工具：第一个 1.5 秒后提醒；用户 5 秒内批准了、随后走开；第二个请求在 8 秒时开始等——满 1.5 秒时距上一条只有 8 秒，被节流挡掉，且**永远不再提醒**，哪怕一直等到 2 分钟。Dock 角标、菜单栏举手图标、Dock 弹跳还在（兜底），但提示卡 / 系统通知 / 提示音都没有。
- 复现：`observe` 假时钟：t=0 起等、t≈1.53 第一条；t=1.7–3.0 批准（busy）；t=4 起一直等到 t=120。实测提醒时刻 = `["1.53"]`，只有一条。
- 规格：任务书 7.2「同一个 buddy 的同一类提醒，20 秒内最多一条」——字面上满足，但把「最多一条」做成了「挡掉的这条永远丢弃」；测试 `sameBuddySameKindIsThrottledForTwentySeconds` 把「被挡掉」当成正确结果，没有检查「窗口过去后还在等」会怎样。我把它标 P2（行为和提醒的目的相悖），如果你们认为规格就是「丢弃」，请在 DESIGN.md 写明。
- 建议修法（已验证）：先节流、后置位，文案放在节流之后（被节流的那些拍不做提示卡宽度测量）：
  ```swift
  guard throttle("\(s.key)|\(att)", now: now) else { return [] }      // 被挡住：alerted 不置位，下一拍接着试
  ep.alerted = true
  let (kind, body) = Self.text(for: s, att: att, privacy: privacy)
  return post(key: s.key, kind: kind, title: title, body: body, now: now)
  ```
  验证：同一段模拟的提醒时刻变成 `["1.53", "21.55"]`（第一条 + 20 秒窗口一过就补发一条）；既有的全部 `AlertCoordinatorTests` 不用改；上面 fuzz 里「同 buddy 同种类 20 秒内不重复」仍是 0 次违反。
- 建议的回归测试：上面的场景；断言 t=5.5 没有（仍在节流）、t∈[21.5, 22] 之间恰好一条、之后不再重复。
- 附：`handleFinished` 里被节流的「做完了」（`:203`）同样直接丢弃，这条是事件型提醒，丢掉可以接受，但最好和上面一起写进 DESIGN.md。

### R2-005 [P2 测试基础设施] `DesktopMetaFileIOTests` 与 BuddyCoreTests 的 `FileAccessTests` 抢全局的 `FileIO.forbiddenHits / openObserver`
- 位置：`Tests/BuddyOfficeTests/DesktopMetaFileIOTests.swift:23-36`（05:16 加的，C-032）：设置 `FileIO.openObserver`、故意让符号链接 `local_evil.json → .key` 触发保险（`forbiddenHits += 1`）。`Tests/BuddyCoreTests/RegistryTests.swift:214-247` 的 `FileAccessTests`：`keyFilesAreNeverOpened` 断言 `FileIO.forbiddenHits == hitsBefore`、`safetyNetRefusesKeyAndSocketPaths` 断言 `== before + 3`——这两个全局量的「精确相等」。BuddyCore 那边为此把所有会触发保险的测试塞进一个 `.serialized` 套件（`FuzzRegressionTests.swift:673` 的注释写得很清楚），但 `.serialized` 只管套件内部，**跨套件（更别说跨 target，所有测试编进同一个进程）照样并行**。
- 复现：`scripts/dev.sh test --filter "safetyNetRefusesKeyAndSocketPaths|keyFilesAreNeverOpened|DesktopMetaFileIOTests"` 连跑 80 次，**56 次失败**：`RegistryTests.swift:235:9: Expectation failed: (FileIO.forbiddenHits → 1) == (hitsBefore → 0)`。把整个 BuddyCoreTests + BuddyOfficeTests 一起跑（532 个测试）4 次没撞上（取决于调度），所以完整回归里是偶发红灯，不是必现。
- 反方向理论上也成立：`DesktopMetaFileIOTests` 断言 `log.paths.contains …local_a.json`，依赖 `openObserver` 没被别的套件替换 / 置 nil（我没有单独观察到这一种失败，只观察到上面那一种）。
- 建议修法：BuddyOffice 这边别去碰全局观察口——「没有打开 .key」用蜜罐的办法证明（QA/tools 里已有：`.key` 文件 atime 设成等于 mtime，读完 `stat` 看 atime 有没有被推进），「读到的结果」用 `readAll() == [...]`（`local_evil` 被跳过）；或者给 FileIO 加「按线程 / 按作用域」的观察口（`FileIO.withObserver { … }`，计数也按作用域）；或者把 BuddyCore 那两个断言改成不受别人影响的相对断言。
- 建议的回归测试：把上面的 `--filter` 组合放进 `QA/tools/full_regression.sh`，要求 20 次里 0 次失败。

### R2-006 [P3] 隐私模式没盖住设置页「数据源诊断」和「测试深链」回执里的会话标题
- 位置：`BoundedWait.swift:21`（`DiagnosticsFormatter.text` 逐行写 `s.title`）、`AppModel.swift:356-360`（`testDeepLink` 返回「已向「\(s.title)」发出深链跳转」）。任务书 / 使用说明写的是「隐私模式：桌牌、卡片、通知里隐藏全部细节（只写「会话」）」，菜单栏菜单、右键菜单、提示卡、悬停卡都走了 `AlertText.title(privacy:)`，只有这两处漏了。
- 复现：`privacy.hideDetails = true`、一个标题为「帮我转账到 6222-秘密账号」的会话：`StatusItemController.menuNeedsUpdate` 的菜单项是 `["🙋 会话　等你批准 · 0 秒", …]`（没有标题，OK）；`DiagnosticsFormatter.text(...)` 的输出 `contains("秘密账号") == true`。
- 影响：设置窗口是用户自己开的，风险小；但隐私模式就是为了「录屏 / 共享屏幕」，那时打开诊断页会露标题。
- 建议修法：`diagnosticsText` / `testDeepLink` 里标题走 `AlertText.title(_, privacy: privacy)`；`DiagnosticsFormatter.text` 加 `privacy` 参数。回归测试：`HousekeepingTests.diagnosticsTextListsEverythingTheSettingsPageShows` 旁边加隐私模式版本。

### R2-007 [P3] 测试进程里 `DebugTools.enabled` 恒为真
- 位置：`DebugTools.swift:14-17`：`devFlagsPresent` 认 `$0.hasPrefix("--test-")`，而 Swift Testing 的宿主进程 `swiftpm-testing-helper` 的参数里有 `--test-bundle-path`。
- 复现：我在私有拷贝里加一个测试打印：`R2PROBE args=[".../swiftpm-testing-helper", "--test-bundle-path", …]`、`DebugTools.enabled=true`。
- 影响：现在没有测试因此写日志（我跑了整个 `BuddyOfficeTests`，`~/Library/Logs/BuddyOffice/debug.log` 行数、mtime 都没变），是潜在陷阱：以后谁在被测代码路径里加一行 `DebugTools.log`，测试就会往用户真实的日志文件里写。`DebugLogTests.onlyDevelopmentFlagsTurnLoggingOn` 传的是自己编的参数数组，看不到这个问题。
- 建议修法：`devFlagsPresent` 改成精确匹配一个白名单（`--test-jump`、`--test-autoquit`、`--test-titlebar`、`--test-minimize`、`--test-tank-click`、`--test-hotkey`），别用前缀。回归测试：`#expect(!DebugTools.enabled)`（在测试进程里）。

### R2-008 [P3] `DesktopMeta` 不认 `--data-root`
- 位置：`JumpService.swift:140-141`：`base = baseOverride ?? NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions"`，而 BuddyCore 的 `Paths.desktopSessionsDir` 是 `home + …`（跟着 `--data-root` 走）。
- 现象：用 `--data-root <假 home>` 起开发副本（QA / 长跑 / 自检都靠它隔离真实数据）时，App 层「点击跳转前后读 `lastFocusedAt`」「提醒判定里的 `isMostRecentlyFocused`」仍然读**真实**的桌面会话元数据（只读 `lastFocusedAt`，不违反红线，但违反「假 home 整体替换」的约定，也让 QA 的「没有碰真实数据」不完全成立）。
- 建议修法：`DesktopMeta` 的根目录由 `AppModel` 从同一个 `Paths` 注入；或者至少在 `--data-root` 时把 `baseOverride` 设成 `Paths(home:).desktopSessionsDir`。

### R2-009 [P3] 入口兜底只在「设置变了」时重算（A-024 的残留）
- 位置：`AppModel.swift:165`：`entryFallback(f, stripHasBuddies: !present.isEmpty, …)` 只在 `applySettings` 里算，而 `applySettings` 只由 `UserDefaults.didChangeNotification` 触发（`:123-126`）。
- 现象：纯宠物用法（办公室 / 小鱼缸 / 菜单栏 / Dock 全关，只开宠物条）：有会话时宠物条算入口，不补 Dock 图标；会话都走了之后 `present` 变空，但没人重算——宠物条变成一块点穿的空白，没有任何入口，直到下一次设置写入（一轮做完写白板计数才会）或重启。反过来，任何一次「恰好在没人时发生的设置写入」会补上 Dock 图标并把 `ui.dockIcon` **永久**写成 true（`:182`），用户关掉 Dock 图标的选择被悄悄改掉。
- 复现（真实 `AppModel` + 真实窗口 / 面板 / `NSApp.activationPolicy`，进程内，不 `start()`）：办公室 / 小鱼缸 / 菜单栏 / Dock 全关、只开宠物条，喂 1 个会话、`applySettings` 之后 `(办公室, 小鱼缸, 宠物条, Dock) = (false, false, true, false)`；再喂空列表（会话都走了，`present = 0`），没有任何重算，状态仍是 `(false, false, true, false)`——一块点穿的空宠物条，没有任何入口。
- 建议修法：`present.isEmpty` 变化（有人变没人 / 没人变有人）时也 `scheduleApply()`；写回 `ui.dockIcon` 改成「只强制、不写回」或写回前问用户。

### R2-010 [P3] 宠物条 3 倍 + ≥ 9 人时比屏幕还宽
- 位置：`StripPanelController.swift:113-122`（`origin`）没有把 x 夹进 `visibleFrame`；`StripScene` 8 人 = 448 美术像素，超过 8 人再加 24 的「+N」列。
- 实测（`NSScreen.main.visibleFrame.width = 1408`）：3 倍：6 人 1008（in）、8 人 1344（in）、**9 人 1416，`origin.x = -16`**（最左边的人被挤出屏幕，点不到）、12 人同 9 人。靠左 / 居中同理。小鱼缸没有这个问题（有夹取，`TankPanelController.swift:83-84`；我测了 0/1/2/3/8/12/20/1/0/5 人序列，窗口始终在可见区域内）。
- 建议修法：`origin` 里 `x = max(vf.minX, min(x, vf.maxX - w))`，宽度仍超出时降一级缩放（只在渲染时，不改设置）。

### R2-011 [P3，可能] `setDemo` 不清旧数据源的 `onUpdate`
- 位置：`AppModel.swift:326-335`：停旧数据源、换新的，但旧的 `onUpdate` 闭包仍指向 `self`（`wire`，`:63`）。`SessionStore.process` 用 `callbackQueue.async { [weak self] … onUpdate?(snaps) }` 投递（`SessionStore.swift:203`），`setDemo` 执行的那一刻已经排在主队列里的回调会在它返回之后执行，写回 `snapshots` 和 `gotData = true`。
- 概率低（要恰好排在主队列里，约每次切换 1–2%）；后果轻（演示模式里闪一帧真实会话，或「今天还没人上班」牌子闪一下）。
- 验证办法：`FakeProvider` 里 `setDemo(true)` 之后再调 `real.onUpdate?([...])`，`model.snapshots` 会被写回旧数据。修法一行：`setDemo` 里旧 provider 停之前 `provider.onUpdate = nil`。

### R2-012 [P3] 主菜单没有 ⌘W / ⌘H / 编辑菜单
- 位置：`AppDelegate.swift:137-151`（`buildMenu`）：应用菜单只有「设置…」「退出」，窗口菜单只有「办公室」「最小化」。用户在办公室窗口里按 ⌘W 什么都不发生；诊断页文字选中后 ⌘C 可能复制不了（没有编辑菜单的 `copy:`——可能，未验证）；⌘H 隐藏 App 没有入口。
- 建议：窗口菜单加「关闭」（⌘W，调用 `windowShouldClose` 的同一条路）、应用菜单加「隐藏」（⌘H）、加标准的编辑菜单。

### R2-013 [P3] `scripts/measure.sh`、`scripts/soak.sh` 用 `pkill -f "$APP/Contents/MacOS"` 按路径子串杀进程
- 位置：`measure.sh:9,18`、`soak.sh:12,30`。默认 `$APP` 是 `dist/dev/Buddy 办公室 release.app`，并行跑多个 QA（这次评审期间就有好几路同时在跑）时会误杀别人用同一个路径起的开发副本；`BUDDY_APP` 指到装好的 App 时会杀掉用户的 App。建议改成记下自己起的 pid、只 kill 它（`run_soaks.sh` 已经是这样做的）。本次评审没有运行这两个脚本。

### R2-014 [P3] 系统时钟往回拨时，去抖 / 节流把提醒压住
- 位置：`AlertCoordinator.swift`：`now.timeIntervalSince(ep.since) >= debounce`（`:172`）、`throttle` 的 `now - t < 20`（`:208`）、`lastAlert.filter { now - $0.value < 20 }`（`:131`）全部用墙钟 `Date()`，没有对「负的差」做处理。时钟被拨回 N 秒（手动改时间 / 休眠唤醒后 NTP 校正）：`lastAlert` 里的记录一直「没过期」，直到时钟追上——N 秒内这个 buddy 的这一类提醒发不出来。
- 复现（逻辑层，已跑）：`observe` 假时钟：t=1000 起等、t≈1001.6 发出第一条、t=1003 批准；然后把 now 拨回 t=100 起新的一段等待——**第一条提醒出现在 t=1022.0**（期望 ≈ 101.5，即压了约 15 分钟）。
- 修法：把负的差当成「已过期」（`max(0, …)`，或 `now < t → 视为过期并覆盖`）。现实里触发很少（手动拨时间、大的 NTP 步进），所以只列 P3。

### R2-015 [P3] A-019 的遗留仍未修：工具详情为空时桌牌 / 菜单栏文案出现「在读 」「在找 ""」
- 状态：`QA/issues-app.md` A-019 写着「未修（在协调者名下的文件）」并转交，我在 05:20 的快照上跑探针确认**当时还是这样**；之后 `PlateCopy.swift` 只在 06:29 改了 `.mcp / .unknown` 两行的隐私处理（`diff` 过），空 detail 的写法没变，所以现在应该仍是这样（不是新问题，是别让它掉在地上）。位置：`Sources/BuddyStage/PlateCopy.swift` 的 `toolText`（拼 `"在读 " + fileName(detail)` 之类）。
- 复现（`Fx.call(name, "")` 空 detail）：`Read=[在读 ] Grep=[在找 ""] WebFetch=[在看 ] Edit=[在改 ] Write=[在写 ] Bash=[运行 ] WebSearch=[在搜 ""]`（`Glob=[在翻文件]` 是唯一处理过的）。
- 什么时候会出现：hook 行被截断（工具详情最多 160 字，截在多字节字符中间时 JSON 解析失败，走 `LineSanitizer.parseDegraded` 只抠 ts / ev / tool，`detail` 为空）。用户写中文，Grep 的搜索词 / Bash 命令 / 中文路径较长时最容易碰到；桌牌、悬停卡、菜单栏菜单都会显示这些文案，`在找 ""` 是看得见的怪字。
- 建议修法：每个类别在 detail 为空时退回无细节的说法（「在读文件」「在搜索」「在看网页」「在改文件」「在写文件」「在运行命令」）；`PlateCopyTests` 断言各类别在空 detail 时没有尾随空格 / 空引号。

### R2-016 [P2，未定论] 办公室窗口每次改尺寸，`PixelView` 都新建 3 块 IOSurface，CoreAnimation 会长期保留用过的 surface
- 位置：`PixelView.swift:144-157`（`nextSurface`）：`surfaceW != w || surfaceH != h` 就重建 3 块 `IOSurface`（`:146`）。拖窗口边缘时每一步的视口都不一样，于是每一步都新建。
- 证据（06:31 之后的实验，不是修法验证）：
  - 测试宿主进程里（可见窗口 + 真实合成，`OfficeWindowController` 随机尺寸 300 次，每次转 16 ms runloop）：物理占用 57 → 261 MB，**之后 6 秒、orderOut 之后都不回落**；`footprint` 分类：IOSurface 294 MB / 465 个区域。只驱动 `PixelView`（合成画布，没有场景）：26 → 70 MB；只驱动 `OfficeScene`（没有窗口）：24 → 25 MB（没有涨）——所以问题在显示层，不在场景。
  - 独立最小复现（`NSWindow` + 一个 `CALayer`，每次新尺寸建 IOSurface、**写满**一块、设成 `layer.contents`、旧的丢弃）：300 步 +46 MB 不回落；把 layer 的 contents 置 nil / 移除图层 / 摘掉视图 / 关闭窗口都放不掉；**换成固定大小的 3 块复用 + `contentsRect` 裁剪：300 步 0 增长**。（没写过的 surface 页面不常驻，不计入占用，所以我第一版独立复现没测出来。）
  - 真实开发副本（`--demo`，我在私有拷贝里加了个「5 秒后每 16 ms 随机改一次窗口内容尺寸、共 300 次」的实验开关，用 `footprint -p` 从外面量）：22 → 43–44 MB（+21 MB）；**第一次 60 秒内回落到 23 MB，第二次 2 分钟以上没回落**——是延迟释放还是泄漏，我没能定论。
- 为什么标 P2 但「未定论」：真实 App 里增量比测试宿主小得多（+21 MB / 300 步），也可能最终会释放；但如果不释放，用户每拖一次窗口边缘就多几十 MB，长期运行会超出 80 MB 预算。QA 的长跑从来没有缩放过窗口，所以没测到。
- 建议修法（独立复现里验证过「0 增长」）：surface 按固定大小（或把宽高向上取整到 64 像素的桶）分配一次、循环复用，用 `contentsRect` 裁出需要的那块；只在跨桶时才重建。回归测试：可见窗口里随机尺寸 300 次，`phys_footprint` 增长 < 20 MB。真机确认办法：开发副本里拖窗口边缘 10 秒，`footprint -p <pid>` 前后各量一次并 60 秒后再量。

### R2-017 [P3] 办公室窗口（普通 `NSWindow`）没关 `animationBehavior`：快速 show / hide 会一路涨线程（B-010 的同类）
- 位置：`OfficeWindowController.swift:32-51`（窗口创建，没有 `animationBehavior = .none`）；B-010 只修了 `FloatingPanel`（`Panels.swift:24`）。
- 复现（测试宿主里，真实的 `AppModel.showOffice(persist: false)` + `orderOut`，每轮间隔 4 ms）：只有小鱼缸 / 只有宠物条 300 轮线程 7 → 7（平）；**只有办公室窗口 300 轮线程 24 → 70**；把办公室窗口设成 `animationBehavior = .none` 之后再来 300 轮：70 → 70（不再涨）。
- 真实触发的频率低（要在窗口出现 / 消失动画还没播完时又 order 一次：热键连按、`expandToOffice()` 之后 50 ms 里 `applySettings` 又 `showOffice` 一次），所以只标 P3；一行修：`w.animationBehavior = .none`（设置窗口同理，但它只在用户点开时才 show）。回归测试：在 `PanelAnimationTests` 里加 `OfficeWindowController().window!.animationBehavior == .none`。

## 2. 已经查过、没问题（验证过的关键点）

**运行时长跑（开发副本 r2，假 home + replay 生成器，办公室 + 小鱼缸 + 宠物条全开、`--force-render`，15 分钟，`soak_watch` 每 10 秒一行）**
- 线程数：首 10 → 末 9，最大 14，前 5 / 后 5 个采样的中位数差 +1（低于「> 8 算在涨」的门槛）；期间不断有提示卡弹出（同一份假数据在另一个副本里 240 秒量到 25 张；这个副本的 `tally` 涨到 20+）——B-010（`FloatingPanel.animationBehavior = .none`）的修复在这条路上有效。
- 文件句柄：66 → 66，最大 67（`CHR:3, DIR:28, KQUEUE:1, REG:34` 全程不变）；`.key` 句柄 0、`.sock` 句柄 0；`~/Library/Logs/DiagnosticReports` 里没有新的 Buddy 崩溃报告。
- RSS 首 93 → 末 31.5 MB（启动瞬间的共享页回落）；物理占用前 12 分钟 30–33 MB 平；之后我注入「缩放 3 倍 + 小鱼缸 1 倍 + 一批坏值」，物理占用 3 分钟内从 33 涨到 57–58 MB，然后**平稳**（之后 2.5 分钟的采样不再涨；我随后停掉了这个副本，没有观察更久）——判断是 `TextRenderer` 的 600 条 FIFO 缓存在新样式下重新填满（`TextRenderer.swift` 里上限 600 条，每条 30–70 KB），不是泄漏，仍在 80 MB 预算内；这是推断，没有单独量缓存大小。
- 设置被外部写坏（运行中注入 12 项：`office.zoom=99`、`tank.zoom=0`、`strip.zoom=9`、`strip.align=xyz`、`strip.screen=id:abc`、`strip.level / ui.labels=weird`、`dormant.max=-1`、`tally.<今天>=-5`、`tank.opacity=-3`、`notify.finishedMinSeconds=-9`、`hidden.keys=[a,b]`、`idle.dozeMinutes=0`）：进程没崩；宠物条被夹成 3 倍（窗口 1008 宽）、小鱼缸夹成 1 倍（200×146）、白板计数当 0 处理。（注：`defaults write` 是**别的进程**写的，App 的 `UserDefaults.didChangeNotification` 收不到，要等 App 自己下一次写偏好——白板计数——才会重新读；这不影响正常使用，只是「外部脚本改设置」不会即时生效。）
- 进程内自检（快照构建，开发副本、假数据）：`--test-minimize`（`isMiniaturized=true` 之后写设置 + 白板计数，仍是最小化 → PASS）、`--test-tank-click`（单击背景交给拖窗口 1 次 / 双击背景回办公室 1 次 / 点小人跳转回调 → PASS）、`--test-titlebar`（三个按钮 + 缩成小鱼缸 + 双击回办公室 + 改无关设置后办公室不被收起 → 全部对）。
- AutoQuit 的真实通知接线（现有测试从不调 `start()`）：用私有 `NotificationCenter` + 真的 Claude `NSRunningApplication` 对象（只读）发 `didTerminate` / `didLaunch`：`didTerminate` → 排一个 60 秒的任务，`didLaunch` → 取消。「非 NSObject 的 Swift 类 + `@objc` 选择子」这种注册方式是有效的。
- 办公室窗口渲染 fuzz：9 种窗口尺寸（200×220 … 3000×2000、260×3000、3000×260）× 7 种缩放设置（0…5、99）× 5 种人数（0…40，含座位号 60 的下班工位）= 315 次 `OfficeWindowController.render`：不崩，图像层大小恒等于「视口 × 缩放」，且不超出视图。
- `applySettings` 状态机（真实 AppKit，进程内 fuzz）：真实的 `AppModel` + `OfficeWindowController` / `TankPanelController` / `StripPanelController` / `NSApp.setActivationPolicy`，70 步随机翻转五个入口开关（办公室 / 小鱼缸 / 宠物条 / 菜单栏 / Dock），中间随机让会话都走了 / 又来了；每一步核对：办公室窗口、小鱼缸、宠物条的 `isVisible`、activationPolicy 都等于「设置套上入口兜底」的结果，至少有一个入口，强制补的 Dock 图标写回了设置——**0 个问题**（唯一的漏洞是上面 R2-009 那种「不重跑」的情形）。快捷键开关没放进 fuzz（会注册真的全局热键），只读代码。
- 小鱼缸 / 宠物条位置：人数序列 0/1/2/3/8/12/20/1/0/5，靠右 / 左 / 中 / 认不出的取值，窗口始终在 `visibleFrame` 内（唯一例外见 R2-010）。
- 合成提示音：4 种 WAV 数据都能被 `AVAudioPlayer` 载入，时长 0.22 / 0.22 / 0.30 / 0.28 秒（新加的 `SpecTraceAlertTests` 已经逐字节测了头部）。
- 隐私模式覆盖：菜单栏菜单不露标题 / 命令（测过）；右键菜单、提示卡、系统通知、悬停卡都走 `AlertText.title` / `privacy` 参数（漏的两处见 R2-006）。
- 编译：debug 全量 0 警告；`BuddyOfficeTests` 快照上 143 个全过；最新树 179 个连跑 6 次全过（每次 1.2–1.4 秒）；带我的补丁 + 我的 16 个探针 + 新的 SpecTrace 套件共 195 个全过。

**设置键 → 消费者（逐个核对，全部接了线）**
| 键 | 消费者 |
|---|---|
| `office.visible` | `AppModel.applySettings` / `showOffice` / `toggleOffice` / `windowShouldClose` / 菜单栏开关 |
| `office.zoom` | `OfficeWindowController.render` → `OfficeLayout.effectiveZoom`（`Settings.int` 夹 0…5） |
| `tank.visible` / `tank.zoom` / `tank.opacity` | `applySettings` → `TankPanelController.show/hide`；`render` 里按 `settingsGen` 读缩放（1…2）、`alphaValue`（0.3…1） |
| `strip.visible` / `strip.zoom` / `strip.screen` / `strip.align` / `strip.level` / `strip.fullscreen` | `StripPanelController`（`render` 的 `settingsGen` 分支：缩放 1…3、`applyLevel`、`repositionIfNeeded`；`scene.alignRight`） |
| `ui.menuBarIcon` / `ui.dockIcon` | `applySettings` → `StatusItemController.setVisible` / `setActivationPolicy`（强制补 Dock 图标会写回，见 R2-009） |
| `ui.labels` | `OfficeWindowController.labelMode` |
| `notify.permission / question / finished / finishedMinSeconds / includeDesktop / suppressWhenFocused / error` | `AlertConfig(settings:)`，每次判定都重新读 |
| `notify.sound` | `LiveAlertSink.post` → `SoundSynth.play` |
| `idle.dozeMinutes / idle.sleepMinutes / dormant.recentHours` | `EngineConfig` → `RealProvider.make`（下次启动生效，设置页写明） |
| `dormant.max` | `AppModel.derive`（立刻）+ `EngineConfig`（下次启动） |
| `privacy.hideDetails` | `AppModel.privacy` → 各面板 / 提醒 / 菜单（漏两处见 R2-006） |
| `autoQuitWithClaude` | `AutoQuit.isEnabled` |
| `login.enabled` | 只是设置页里的缓存；真实状态以 `LoginItem.isOn` 为准，设置页出现时对一次 |
| `hotkey.enabled` | `applySettings` → `HotKey.register/unregister`（只在开关变化时） |
| `hidden.keys` | `AppModel.derive` / `AlertCoordinator(muted:)` |

**代码审查里逐条确认过的点**
- 线程边界：`AppModel` / 面板 / 视图全部只在主线程改；后台线程里只有 `SessionStore.stop()`（不碰 AppKit）、`diagnostics()`、`SoundSynth` 队列（`AVAudioPlayer`，不是 UI）、`JumpService.queue`（`NSRunningApplication` 只读 + sysctl）、`JumpService.scriptQueue`（`NSAppleScript`——M0 在后台队列实测过；线程安全性没有文档保证，属于「可能」项，加了 5 秒超时 + 两个队列拆分之后风险可接受）；通知授权回调 `refresh` 里明确切回主线程；`BoundedWait` 的信号量初始值 0，超时后迟到的 `signal()` 不会触发 libdispatch 的「信号量释放时值小于初值」崩溃。
- `nonisolated(unsafe)` 共 3 处（`SoundSynth.players`、`SettingsView.initialTab`、`DesktopMeta.baseOverride`）都只在单线程 / 队列上访问；`HotKey.current` 只在 Carbon 回调（主线程）用。
- 循环引用 / 注销：所有 Timer 块、通知块、菜单闭包都是 `[weak self]`；`AppModel.timer` 每拍 invalidate 旧的；`StripPanelController.timer` 在 `hide()` 里 invalidate；`ToastController.timer` 空了就停；`AutoQuit` 的定时任务先取消旧的；`HotKey.register` 先 `unregister`（`RemoveEventHandler`）；观察者都与 App 同寿命。
- 注入面：AppleScript 唯一插值是 tty，先过 `^/dev/tty[A-Za-z0-9]{1,16}$`；深链 URL 唯一插值是 host id，先过 `^local_[A-Za-z0-9-]{1,64}$`（`"local_abc\n"` 也被拒，`JumpTests.deepLinkRules` 里有）；`NSLog` 都是 `%@` 形式；`DebugTools.write` 不跟符号链接、0700 / 0600、1 MB 轮转、所有失败静默。
- 读文件都走 `FileIO`（含 C-032 之后的 `DesktopMeta`）：拒绝 `.key` / `.sock` / 命名管道 / 符号链接绕过；App 层源码里没有 `.claude` / `.monitor` / `cc-socks` / `.key` / `.sock` 字面量（`SourceAuditTests` + 我的 grep）。
- 设置范围夹取：`Settings.intRanges` / `doubleRanges` 覆盖了所有数值项；`SeatSanitizer` + `OfficeLayout` + `hitID` 三层座位号防线；`tallyToday` / `addTally` 不溢出；`hidden.keys` 类型不对当空。
- 状态机（读代码 + 纯函数测试）：`ApplyPlanner` 只处理变化项；最小化 / ⌘H 不会被弹回来；`showOffice` 先 `deminiaturize` 再 order；`office.visible` 与窗口状态的每种组合（关闭 / 最小化 / 隐藏 / 再打开）走通；`applySettings` 里写回 `ui.dockIcon` 不会死循环（第二次写回列表为空）；自动收起的各种时序（Claude 退出 → 60 秒内重开 → 有会话 / 被隐藏的会话 / 设置里关掉）都按预期；到点条件不满足不重新武装是已知限制（已记录）。
- 深链 / 跳转：`deepLinkVerdict` 的 7 种组合；点击用渲染那一刻的快照再按 key 找最新的；悬空座位 / 下班工位不跳；VS Code / 终端 / 其他宿主的分支；`hostApp(of:)` 最多 12 层、跳过 CLI 包和后台 App。
- 提醒判定的其余部分：去抖 1.5 秒 / 合并 2 秒 / 终端 8 秒复查 / 桌面 8 秒等总结 / 隐藏 = 不打扰 / 记账字典有界（1500 个会话进出后 `prevActivity / finished / episodes ≤ 1`）；fuzz 里「静音的不出提醒、关掉的种类不出、同种类 20 秒内不重复」0 次违反。
- 安装 / 卸载 / hook（只读）：`hook-merge.py` 原子替换 + 备份 + 保留权限 + 保持末尾换行；06:14 新增的符号链接处理（`resolve` + `backup(near=)`）我读过 diff：改写落在真实文件上、链接不动、备份放在链接旁边、链接指向的目录不存在就拒绝，逻辑对；`安装.command` 里的 `pkill -x BuddyOffice` 是重装时的预期行为；`卸载.command` 的 `A || B && C` 优先级是对的；Info.plist 有 `NSAppleEventsUsageDescription`、无 `LSUIElement`。
- `Package.swift`：测试目标 `@testable import` 可执行目标 OK；`unsafeFlags(["-O"], .when(configuration: .debug))` 只在根包里用；没有第三方依赖。

**没能验证的担心**（没有 GUI 授权 / 造不出真实环境；没有列成发现，留给真机确认）
- App Nap：App 没有 `beginActivity` 之类的退出手段。只有菜单栏图标、没有窗口时，主线程 1 秒定时器在我的无窗口开发副本上出现 0 / 1 / 2 秒的间隔抖动（63 个间隔里 0 秒 11 个、2 秒 13 个，最大 2 秒——日志时间戳只精确到秒，抖动也可能来自截断），没有测「提醒延迟」本身；如果真机上「等你批准」的提示比 1.5 秒晚了很多，先看这一条。
- Dock 角标在「Dock 图标关 → 再开」（`setActivationPolicy` 来回切）之后会不会丢：`DockTileController` 只在等你的人数变化时才重设角标（`lastCount`）。
- 运行时拔掉小鱼缸所在的外接屏：小鱼缸只在第一次出画面时检查过「存的位置还在不在屏幕上」，之后交给系统；系统是否总会把它挪回可见区域没验证。
- 全屏 Space / 多显示器下宠物条的 `collectionBehavior` 组合、提示卡在全屏 App 上方的表现：只能真机看。

## 3. 测试质量

**能抓到真东西的**（变异 / 我的补丁验证过）：`AlertCoordinatorTests`（去抖 / 节流边界值都是 0.5 的整数倍，Double 算术精确）、`ApplyPlanTests`、`SettingsTests`（每个带范围的键 × 负数 / 极大 / NaN / ±∞）、`JumpTests`（每个座位映射到自己的会话）、`TickPacerTests`、`EngineConfigTests.realProviderPassesTheSettingsToTheEngine`（造出真的 `SessionStore` 看 `options`）、新的 `SpecTraceUITests` 里拿真实的 `TankPanelController` / `StripPanelController` / `OfficeWindowController` 渲染后找像素点击、量点穿的那几条。

**断言太松 / 复述实现 / fake 与真实不一致 / 没覆盖**（每条附加强办法）：
1. **`AppModel` 的胶水没有测试**：我做了 4 处变异——`tick` 里 `pipeline.run(hidden: hidden)` 改成 `hidden: []`、删掉 `applySettings` 里的 `settingsWriteBack` 循环、删掉 `showOffice` 里的 `officeMayHaveOpened()` 调用、把 `autoQuit.hasLiveSessions` 改回旧的 `!present.isEmpty`——**只有最后一处被 `AppModelTests.theAutoQuitLiveSessionCheckCountsHiddenBuddies` 抓到，前三处全部存活**（对 06:18 的最新树——含新增的 SpecTrace 套件——重跑前三处：195 个测试仍然全过，一条都没红）。`AlertFallbackTests.Rig.run` 直接调 `AlertPipeline.run`（自己传 `hidden` / `present`），绕过了 `AppModel.tick`。加强：把 `tick` 里「提醒那一段」和 `applySettings` 的「执行 plan」抽成可注入的（`Env` 闭包：`setActivationPolicy`、`orderOut`、`tank.show` …）再测；或者给 `AppModel` 一个测试用的 `NoWindowsHost`。
2. **`PanelShowTests`** 只测 3 行的辅助函数，不测控制器真的用了它：把 `TankPanelController.show` 改回「先 orderFront 后渲染」测试应该仍全绿（读代码判断——`SpecTraceUITests` 明说绝不 orderFront，所以没人执行 `show`；这一条我没有单独跑变异）。加强：控制器测试里断言 `orderFront` 之前 `pixelView.frame_ != nil`（`SpecTraceUITests` 对办公室窗口做了，小鱼缸 / 宠物条没有）。
3. **`PanelAnimationTests`** 只断言 `animationBehavior == .none`（复述那一行实现）；B-010 真正的症状（线程数随提示卡增长）没有自动化回归。加强：开发开关 `--test-toast-threads`：连弹 100 张提示卡，`task_threads` 数量增长 ≤ 2；或者在长跑脚本里把「线程数中位数后 5 个 − 前 5 个 ≤ +1」作为红线（`soak_watch` 已经有）。
4. **新的 `SpecTraceUITests` 有一批「源码钉住」**（`m.contains("tb.tank.onClick = { [weak self] in self?.shrinkToTank() }")`、`toast.contains("PixelSpring(value: 60, period: 0.36)")`、`s.contains("if pollTick % 15 == 0 { repositionIfNeeded() }")` 等）：这是在复述实现——换个变量名就红，行为坏了（`shrinkToTank` 的函数体、提示卡的**顺序**——R2-002）却不红。文件开头已经诚实说明是「间接证据」；我的补丁没有让其中任何一条变红，说明它们既不挡也不拦。加强：把「顺序 / 常数」类的断言换成行为断言（比如 R2-002 的「orderFront 那一刻在屏幕外」）；保留的钉住类放进单独的套件并标注「改实现要同步改这里」。
5. **`AutoQuitTests` 不走真实通知**：`AutoQuit(center: NotificationCenter(), …)`，`start()` 从来没被调用；`SpecTraceUITests.autoQuitListensForApplicationTermination` 补了「订阅了这两个通知名」，但不发通知。我的探针发了（见第 2 节，有效）。加强：用私有 `NotificationCenter` 发 `didTerminate`（userInfo 里放一个 `NSRunningApplication`）并断言排了 60 秒的任务。
6. **`NotificationAuthTests` / `AlertFallbackTests` 的 `FakeCenter` 是同步的**：真实的 `UNUserNotificationCenter` 回调在后台队列、之后 `refresh` 切回主线程；fake 让 `Thread.isMainThread` 分支永远为真。加强：`FakeCenter` 加一个 `async: Bool`（回调 `DispatchQueue.global().async` 再等待），至少跑一遍。
7. **`TickPacerTests.simulate`** 在测试里重新实现了 `AppModel.wake / schedule / tick` 的协议（离散事件模拟）——`AppModel` 的实际用法变了它不会知道。加强：给 `AppModel` 注入时钟和定时器（像 `AutoQuit.Scheduler` 那样），驱动真的 `wake()`。
8. **`DebugLogTests.failuresNeverCrash`** 以 `#expect(true)` 收尾，只证明没崩；加强：断言失败之后下一次写到好的路径仍然成功、失败的路径下没有留下文件 / 目录。`onlyDevelopmentFlagsTurnLoggingOn` 传合成的数组（R2-007 的盲点）。
9. **`AlertCoordinatorTests.waitingBranchNeverSkipsThePerSnapshotBookkeeping`** 是特征测试（QA 文档自己承认当前流程里不可观察）；**`sameBuddySameKindIsThrottledForTwentySeconds`** 把「被挡掉」当作正确结果、不检查「窗口过去后还在等」（R2-004）；**`mergedFinishedAndMixedNotificationsUseTheirOwnWords`** 没覆盖 blocked+blocked（R2-003）。加强：见各条的回归测试。
10. **`EngineConfigTests.theDataRootArgumentReachesTheEngine`** 末尾用 `src.contains("SessionStore(options:")` 之类断言源码文本，而前面已经有真实对象的断言，这一段冗余且脆。
11. **`SourceAuditTests.code()`** 把一行里第一个 `//` 之后的都当注释去掉——字符串里的 `claude://…` 之后同一行的内容审计看不到（现在没有这样的行，但审计有盲区）。加强：先去掉字符串字面量再去注释。
12. **`HousekeepingTests.aStuckStopCannotHold…`** 用墙钟阈值（超时 0.2 秒、断言 < 0.6 秒），机器很忙时可能红。加强：断言「返回 false」和「work 还没跑完」，不断言具体耗时，或把阈值放宽到 5 倍。
13. **跨套件的全局状态**：R2-005（`FileIO`）；另外 `DesktopMeta.baseOverride` 是全局可变量，靠 `defer` 复位——别的套件并行读 `DesktopMeta.readAll()` 时会看到临时值（现在没有别的套件读，但没有防护）；新的 `SpecTraceUITests` 在测试进程里 `NSApplication.shared`、往 `UserDefaults.standard` 写 `office.visible` 又删（已有清理，但和并行套件共享同一个域）。
14. **变异存活的另一批**：`SoundSynth`（已被新测试覆盖）、`LoginItem.apply`（只测状态映射）、`HotKey`（0 覆盖）、`StripPanelController.poll` 的 30 / 10 Hz 切换（只有源码钉住）。这几处都是 GUI 边缘，可以接受，但要在 DESIGN 里标明是「间接验证」。

## 4. 附录：环境与复现

- 机器：Darwin 27.2，Swift 6.3；构建目录 `scratchpad/r2-app/build`（debug；库带 `-O`，App 目标 `-Onone`，所以 CPU 数字偏高）。
- 我的探针测试（源码在 `scratchpad/r2-app-keep/probes/`，原来在私有拷贝里；拷贝已删）：`R2Probe`（PixelView 缩放）、`R2Probe2`（空闲场景画布变化间隔）、`R2Probe3`（真实 Tank / Strip 控制器改缩放）、`R2Probe4`（AutoQuit 真实通知）、`R2Probe5` / `6` / `11`（AlertCoordinator 场景 / fuzz / 全流水线）、`R2Probe7`（隐私 + 面板位置）、`R2Probe8`（WAV）、`R2Probe9`（办公室渲染 fuzz）、`R2Probe10`（宠物条 3 倍宽度），以及 195 个测试那次之后才加的 `R2Probe12`（时钟回拨，R2-014）、`R2Probe13`（空 detail 文案，R2-015）、`R2Probe14`（`applySettings` 真实 AppKit fuzz + R2-009）、`R2Probe15`–`R2Probe23`（06:31 之后：show / hide 线程 / 句柄 / 内存、窗口缩放风暴、IOSurface 独立复现，R2-016 / R2-017）。第二个私有拷贝 `scratchpad/r2b/`（含我加了缩放风暴开关的开发副本 r8）也已删除；`r2-app-keep/` 里多了这些探针和输出。需要的话，各条「复现」里的代码可以直接贴进 `Tests/BuddyOfficeTests/`。
- 外部观测工具（只读窗口几何）：`toastwatch` / `toastwatch2`（`CGWindowListCopyWindowInfo`，按 pid + 窗口层级 25 过滤，记录每张新提示卡最初几次的 x 位置和时间戳）。
- 长跑：`replay_soak.py`（假 home，6 个会话、噪声 + 蜜罐）+ `soak_watch.py`，日志副本在 `scratchpad/r2-app-keep/evidence/soak-r2.log`。
- 候选修法的补丁：`scratchpad/r2-app-keep/r2-fixes.diff`（`PixelView.swift`、`AlertCoordinator.swift` 两处、`ToastController.swift`，每处十行以内），见 R2-001 / 002 / 003 / 004 的「建议修法」。这是对 05:20 快照做的 diff；`Sources/BuddyOffice` 之后没有变化，可以直接 `patch -p0`（路径前缀是 `orig/` 和 `proj/Sources/BuddyOffice/`，要调一下）。
- 一次性观察：`FuzzRegressionTests`「C-014 token 账本」（`waitUntilIdle(20)`）和 `EnginePresenceTests.terminalClearKeepsTheBuddy…` 在我机器忙（同时有 5 路 soak）时各红过一次——都是数据层的 `.background` 队列被饿住的超时类断言，不是应用层的问题，转给数据层复查员。
