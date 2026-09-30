# 收尾前的独立复查里新发现的问题（issues-review）

> 来源：修完全部已知问题、做完规格追踪定稿之后，派了几位**全新的**复查员（R1a 数据层、R1b 表现层 / 像素引擎、R2 应用层）重新读代码找 P0–P2，各自的报告是 `QA/review-R1a.md` / `review-R1b.md` / `review-R2.md`。
> 这里只放他们新发现、并且确认之后修掉的问题（编号沿用他们的：R1a-xx / R1b-xx / R2-xx）。「修复前失败」都是先写回归测试、在没改行为的代码上跑出来的。

### R1a-01 [P2] 会话「忙但 10 分钟没有任何新数据」（quiet）时，引擎的 `nextWake` 永远停在过去 → SessionStore 每 5 ms 空转一次
- 现象：任何一个会话只要处于 busy 并且 10 分钟没有 hook / 会话记录增长（长命令、后台任务、卡住的会话、合盖睡眠后醒来），引擎每次 poll 给出的 `nextWake` 都是一个已经过去的时间，`SessionStore.arm()` 里 `delay = min(delay, max(0.005, w − now))` 变成 5 ms，ingest 队列上每秒空转 100+ 次（每次都是一整轮 poll：扫登记表、读 hook 日志、读会话记录……）。复查员实测：1 个 busy 会话，30 秒时 2 次 poll / 秒、CPU 0.1%；虚拟时间跳过 11 分钟后 ~142 次 poll / 秒、进程 CPU 2.7%；会话越多越贵，200 Hz 的定时器唤醒也让整机进不了低功耗（耗电）。随机时间线模糊测试（60 个种子 × 260 步）里 2936 次 `nextWake <= now` **全部**出自 quiet 状态，其余状态 0 次。
- 根因：`SessionEngine.update` 里 `st.quiet = phase == .busy && now − lastGrowthAt >= quietAfter` 之后紧跟 `if phase == .busy { wakeAt(lastGrowthAt + quietAfter) }`——进入 quiet 之后这个时间点永远 ≤ now，而 `wakeAt` 不过滤过去的时间。现有测试为什么没抓到：`nextWake` 只在 3 处测试里断言「不是 nil」，没有任何测试断言「在现在之后」；性能测试里的会话一直在增长，从没进过 quiet。
- 修法：只在「还没 quiet」时登记「变 quiet 的那一刻」（`if phase == .busy && !st.quiet { wakeAt(…) }`）；变 quiet 之前仍然会在那一刻醒来（测试断言了），之后没有多余的唤醒。
- 回归测试：`Tests/BuddyCoreTests/ReviewRegressionTests.swift`：`r1a01_quietBusySessionNeverAsksForAnImmediateRepoll`（dt = 599 / 601 / 602 / 700 / 1200 / 3600 / 7200 秒：`nextWake` 要么 nil 要么在现在之后；变 quiet 之前的唤醒不晚于那一刻）、`r1a01_nextWakeIsNeverInThePastOnATimeline`（busy → quiet → 做完 → 空闲的整条时间线，任何时刻 `nextWake` 都不在过去）。
- 修复前失败：`ReviewRegressionTests.swift:27:13: Expectation failed: (wake == nil → false) || (wake! > h.now → false)`（6 个 issue，dt = 601 … 7200 都是）；时间线那条：`Expectation failed: (bad → ["忙 +601.0：nextWake 在过去 527.0 秒", "忙 +900.0：nextWake 在过去 1427.0 秒", …])`。修复后 `✔ Test run with 2 tests in 1 suite passed`，`StateRule*` / `EngineScenario*` / `StoreTests` / `HelperAttribution*` 等相关套件不变（120 个测试通过；另有 3 个 `StateRuleChainTests` 需要项目里的 QA/tools 脚本，在没有 QA 目录的隔离副本里跑不了，完整回归里通过）。
- 状态：已修。

### R1a-02 [P2] `hook-merge.py`：settings.json 是符号链接时，install / uninstall 会把链接换成一个普通文件
- 现象：`~/.claude/settings.json` 是指向 dotfiles 仓库的符号链接（很常见）时，`install` 之后链接没了，变成普通文件；dotfiles 里真正的那份**没有**加上 hook。`uninstall` 同样会再换一次。用户的 dotfiles 管理被悄悄破坏，之后重新链接会覆盖掉 hook，或者两份内容分叉。（这台机器的 settings.json 是普通文件、不受影响；这是别人的机器上会碰到的边界。）
- 根因：`write_atomic()` 在 `dirname(abspath(path))` 里建临时文件再 `os.replace(tmp, path)`，`path` 是链接本身，`replace` 替换的是链接而不是它指向的文件。`backup()` / `os.stat(path)` 都跟随链接，所以备份内容和权限是对的，只有最后一步不对。
- 修法：新增 `resolve(path)`：是符号链接就改用 `realpath`（临时文件建在真实文件所在目录、`replace` 真实路径，链接保持不变；权限取真实文件的）；备份仍放在链接旁边（`~/.claude/`），不往 dotfiles 仓库里丢文件；链接指向的目录不存在就拒绝（退出码 2），不替用户凭空建出目录。
- 回归测试：`Tests/hook_merge_test.py`：`test_symlinked_settings_keeps_the_link_and_edits_the_real_file`（install 后链接还在、真实文件和链接读出来都有 hook、权限 0600、备份在链接旁边且不在 dotfiles 目录、装两次只有一条、卸载后链接还在且真实文件和安装前逐字节相同）、`test_dangling_symlink_is_refused_and_creates_nothing`（悬空链接：拒绝、不建目录、没有备份）。
- 修复前失败：`AssertionError: False is not true : install 之后 settings.json 应该还是符号链接`；`AssertionError: 0 != 2`（悬空链接原来被当成普通路径覆盖掉了）。修复后 `Ran 15 tests … OK`（原来 13 个照常通过）。
- 状态：已修。真实的 `~/.claude/settings.json` 没有被这次修复触碰（`hook-merge.py status` 仍是「已安装」，安装前后 sha256 一致的检查在 `QA/evidence/install/verify.txt`）。

### W-01 [P3] 测试目标里有一条编译警告：`DebugLogTests.swift:58` 的 `#expect(true)`（永远通过）
- 现象：debug 构建（含测试目标）每次都打印 `note: '#expect(_:_:)' will always pass here; use 'Bool(true)' to silence this warning (from macro 'expect')`。**之前我数警告只数了 `warning:`**，而宏展开里的警告只打印成这一行 note，所以「debug 构建 0 警告」的说法是错的（release 构建确实是 0）。规格追踪定稿员（`spec-trace-ui-final.md` §10 G-05）在自己的编译日志里看到了它。
- 根因：测试 `failuresNeverCrash` 用 `#expect(true)` 表示「没崩就行」，是一条空断言。
- 修法：换成真的断言（除了不崩，还要什么都没写出来：没有凭空建出目录 / 文件，只读目录里也没有日志），没有用 `Bool(true)` 去消音；完整回归脚本改成数所有含 "warning" 的行（不只是 `warning:`）。
- 回归测试：这条本身就是测试；完整回归的 debug / release 构建「警告」一行（数所有含 warning 的行）= 0。
- 修复前失败：`DebugLogTests.swift:58:17: note: '#expect(_:_:)' will always pass here; use 'Bool(true)' to silence this warning`（`QA/tools/full_regression.sh` 新的数法在修复前的 debug 构建日志里数出 20 行）。
- 状态：已修。

### R1a-03 [P2] 数据层测试套件的质量：机器满载时误报红灯、一个阈值没被任何测试钉住、FSEvents 起不来时几条监听断言静默通过
- 现象：① 机器负载 60–180（同时有好几路 swift build / test）时，完整测试里 `StateRuleTests` j1、`FuzzSecurityTests` C-024、`EnginePresenceTests` 的 desktopTokensMerge… / aTerminalSession… 等（复查员第三次全量跑时至少 6 条：C-005、C-028、C-024、4.3-42 和上面两条）随机失败；负载正常时稳定通过，单独跑也通过——「有人在编译时 `swift test` 随机红」，会让人习惯性忽略红灯。完整回归演练（负载约 100）里失败了 3 条断言，规格追踪定稿员的全量运行（`spec-trace-ui-final.md` §10 G-04）里也是同一批。② 变异检查（把阈值 ±1）里 `SessionEngine.hookDropoutGap 15 → 16` **存活**：没有任何测试卡在「会话记录比 hook 的最后一个事件领先超过 15 秒才算 hook 掉线」这个边界上（DESIGN §13 把它写成了规格）。③ `StoreTests`、`FuzzWatcherTests` 里 FSEvents 起不来就 `return`（沙箱里会这样），测试是绿的但什么也没验证，报告里看不出来。（复查员还说「`hook-merge.py` 完全没有自动化测试」——有，`Tests/hook_merge_test.py` 原来 13 个，R1a-02 之后 15 个。）
- 根因：① 测试等后台 token 扫描用的是固定的短超时（5 / 10 / 15 / 20 / 30 秒；扫描队列是 `.background`，整机繁忙时会被饿死），C-024 只给 120 秒；② 没有边界测试；③ 静默 `return`。
- 修法：**只放宽 / 加强，没有削弱任何断言**：① 所有 34 处 `waitUntilIdle(timeout: 5…30)` 统一放宽到 60 秒，C-024 的 120 秒 → 600 秒（等的是「条件成立」，成立就立刻返回，所以正常情况一点没变慢）；② 新增 `r1a03_hookDropoutBoundaryIsFifteenSeconds`（领先 1 / 14 / 14.9 秒还算在工作，15.1 / 30 / 300 秒算掉线，并钉住常量 = 15）；③ 两处静默 `return` 前打印「FSEvents 不可用（沙箱？），跳过监听断言」，完整回归数这句话（应为 0）。
- 回归测试：`Tests/BuddyCoreTests/ReviewRegressionTests.swift`：`r1a03_hookDropoutBoundaryIsFifteenSeconds`；完整回归的「Swift 测试」「FSEvents 不可用而被跳过的监听断言」两行。
- 修复前失败：① `StateRuleTests.swift:788:9: Expectation failed: (s?.tokens.output → 1000) == (1000 + 7 → 1007)`；`FuzzSecurityTests.swift:341:9: Expectation failed: (done.wait(timeout: .now() + 120) → .timedOut) == .success`（完整回归演练里，负载约 100 时）；② 把 `hookDropoutGap` 改成 16 之后新测试变红：`ReviewRegressionTests.swift:54:9: Expectation failed: (SessionEngine.hookDropoutGap → 16.0) == 15` 和 15.1 秒那一档（原来这个变异存活）。
- 状态：已修（放宽超时、补边界测试、让静默跳过可见；没有削弱任何断言）。

### R1b-01 [P2] 错开推迟期间活动又变回已套用的同一种类：到点那一帧套用了过期的中间快照（SP-06 的同一根因，只修了一半）
- 现象：多个人同一帧换活动时，除第一个人以外每个人的新快照被推迟 90 ms × 序号（≤ 0.6 s）。如果这个人的活动在推迟到点**之前**又变回「已套用状态」的同一种类（Read → Edit → Read），`VisualDirector` 不清掉那条推迟记录，到点那一帧把推迟开始时存下的 Edit 快照当成 `effective` 套给表演者：他明明一直在 Read，却被套了一帧 Edit，姿势通道（已停留 ≥ 1.5 s）立刻换成打字，之后 1.5 s 内他在 Read 却在打字（屏幕 0.8 s、桌牌 1.0 s 同理）。复查员实测：`seat-2 performer saw Edit at [2.2]`、姿势 2.2–3.6 秒是打字。Read → Grep → Read 这类连发很常见，多个会话同时在忙时就会撞上。SP-06 的回归测试只覆盖「变成等待类」，所以没抓到。
- 根因：`VisualDirector.update`：`changed`（新快照的种类 ≠ 已套用的种类）为 false 时，只有 `changed && !needsUser` 才会写 / 更新 `pending`，旧的 `pending[key]`（存着中间态 Edit）原封不动留着，紧接着 `if let pd = pending[s.key], time >= pd.at { effective = pd.snap … }` 到点就把它套用了。
- 修法：`if s.activity.needsUser || !changed { pending.removeValue(forKey: s.key) }`——推迟记录只在「现在的快照还需要它」时才保留（等待类不错开，SP-06；变回已套用的同一种类没有什么要换了，本条）。
- 回归测试：`Tests/BuddyStageTests/ReviewRegressionStageTests.swift`：`r1b01_aStaggeredChangeThatRevertsBeforeItsTurnIsDropped`（3 个人 2.0 秒同时 Read → Edit，第 3 个人 2.05 秒变回 Read：表演者从没看到过 Edit、姿势不是打字；第 1 个人照常打字）。
- 修复前失败：`ReviewRegressionStageTests.swift:30:9: Expectation failed: (sawEdit → [2.200000000000002]).isEmpty → false`；`:31:9: Expectation failed: (typing → [2.2, 2.233, 2.266, …])`（2 个 issue）。修复后通过。
- 状态：已修。

### R1b-02 [P2] 桌牌动作文字的 1.0 s 最短停留被「数字抹平」绕过
- 现象：`Performer.update` 里为了让「1:23 → 1:24」这种计时器数字不受最短停留约束，用 `digitMask`（把连续数字 / 冒号抹成 `#`）比较新旧文字，抹平后相同就**立刻**更新且不刷新 `plateSince`。但文件名 / 命令 / 搜索词里的数字也被抹掉了：`在读 part1.txt` → `在读 part2.txt`（对象不一样）每次工具切换都立刻换字，完全不受 1.0 s 约束（复查员实测：每 0.15 s 换一个文件，4 秒里桌牌文字换了 26 次，间隔 0.13–0.17 s；任务书 5.6 要求 ≥ 1.0 s）。同样的路径：`chunk1.md → chunk2.md`、`sleep 1 → sleep 5`、WebSearch「swift 5」→「swift 6」、`v1 → v2`。
- 根因：`digitMask` 抹数字的范围比「计时器」大得多。
- 修法：只抹「计数器位置」的数字：最后一个「 · 」之后的整段（计时 / 用时：`1:23`、`12 秒`、`3分12秒`）、`重试中 a/m`、` ×N`、`派了 N 个帮手`、`打盹 N 分钟 / 小时`；文件名 / 命令 / 搜索词里的数字保留（换了就是换了动作，受最短停留约束）。
- 回归测试：`ReviewRegressionStageTests`：`r1b02_digitsInFileNamesAndCommandsDoNotBypassThePlateHold`（4 种：Read part\<n\>.txt / Bash sleep \<n\> / WebSearch swift \<n\> / Read v\<n\>，每 0.15 秒换一个，相邻两次变化 ≥ 1.0 秒）、`r1b02_timerDigitsStillTickEverySecond`（防修过头：Bash 运行中的计时器数字 10–20 秒里每秒都立刻换）、`r1b02_digitMaskOnlyMasksCounterPositions`（掩码逐类断言）。
- 修复前失败：`ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.1666…) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666…)`（100 个 issue，4 种各 ~25 次）；掩码测试 7 个 issue（`m("在读 v1") != m("在读 v2")` 等）。修复后通过。
- 状态：已修。

### R1b-03 [P2] 隐私模式没有隐藏 MCP server 名和未知工具名（桌牌、状态行、悬停卡片都会显示「在用 acme-secre…」）
- 现象：任务书 6.3「隐私模式下隐藏全部细节」。`PlateCopy.toolText` 里读文件 / 命令 / URL / 搜索词都判了 `privacy`，唯独 `.mcp` 和 `.unknown` 两类没判：`在用 acme-secre…`、`在用 linear`、`在用 SomeInternalTo…` 原样显示。MCP server 名常常就是内部系统 / 客户 / 项目名（`mcp__acme-internal-crm__…`），隐私模式正是为了共享屏幕时不泄露这些。桌牌状态行和悬停卡片的动作行都用同一个函数，所以三处都泄露。`text-audit` 的隐私矩阵只检查排版、不检查文案内容，所以之前没被抓到。
- 根因：`PlateCopy.toolText` 的 `case .mcp` / `case .unknown` 没有 `privacy ? … : …`。
- 修法：隐私模式下 `.mcp` →「在用外部工具」、`.unknown` →「在用工具」。（屏幕上的 server 首字母只有一个字母，不算泄露；等批准提示卡的正文原来就判了隐私。）
- 回归测试：`ReviewRegressionStageTests/r1b03_privacyModeHidesMcpServerAndUnknownToolNames`（5 种活动 × 动作文字 / 状态行，8 个关键词都不能出现；不开隐私模式时文案照旧）。
- 修复前失败：`r1b03… failed after 0.002 seconds with 8 issues`（如 `隐私模式下桌牌动作「在用 acme-secre…」泄露了 acme`）。修复后通过。
- 状态：已修。

### R1b-04 [P2] （低概率；任务书没写）气泡通道没有最短停留，会随工具节奏一闪一闪
- 现象：任务书 5.6 只给姿势 / 屏幕 / 桌牌文字三个通道定了最短停留；气泡通道没有：目标一变就变。Grep（放大镜气泡）和 Read（无气泡）每 0.3 s 交替时，6 秒里气泡开关 19 次，而它旁边的姿势才变 3 次、屏幕 6 次。用户明确说过「零闪烁」，任务书 6.6 也写了「不许开关式闪烁」。（复查员把它标成「设计缺口、不违反任务书字面要求，降成 P3 也说得过去」；我按 P2 修，因为代价很小。）
- 根因：`Performer.update` 里 `if tb != bubble { … bubble = tb }`，气泡通道没有停留时间。
- 修法：工具节奏驱动的气泡（放大镜 / 书 / 工具箱 / 思考 / 没有气泡）也遵守 0.8 s 最短停留（和屏幕通道同一规则；App 启动时就在的会话第一帧不受限）；等待类气泡（钥匙 / 问号 / 计划 / 便利贴 / zzz）立即，不受限。
- 回归测试：`ReviewRegressionStageTests`：`r1b04_toolBubblesAreHeldForAtLeast0_8Seconds`（Grep / Read 每 0.3 秒交替 6 秒：相邻两次气泡变化 ≥ 0.8 秒）、`r1b04_waitingBubblesAreNeverHeld`（防修过头：等批准的钥匙气泡在等待开始的同一帧出现；批准完成后气泡最多再等一个最短停留就没了；新来的人第一帧就有气泡）。
- 修复前失败：`ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.3) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666…)`（18 个 issue）。修复后通过。
- 状态：已修。

### R1b-05 [P3] 打开隐私模式时，桌牌动作文字还会被「1.0 s 最短停留」多留最多 1 秒
- 现象：桌牌动作文字（含文件名 / 命令）受 1.0 s 最短停留约束；用户刚好在文字刚换过之后打开隐私模式，旧的带细节的文字（「在改 Payroll.swift」）还会挂最多 1 秒才换成「在改代码」（标题 / 悬停卡片是立即隐藏的）。隐私模式的用途正是共享屏幕时马上藏起来。
- 根因：`Performer.update` 对动作文字变化统一套用最短停留，没有区分「隐私开关刚变」。
- 修法：记住上一帧的隐私开关，刚变的那一帧文字当场更新（不受最短停留约束）。
- 回归测试：`ReviewRegressionStageTests/r1b05_turningPrivacyOnHidesThePlateActionImmediately`（2.0 秒换成 Edit、2.3 秒打开隐私：打开的那一帧桌牌就是「在改代码」，之后没有任何一帧含文件名）。
- 修复前失败：`ReviewRegressionStageTests.swift:173:9: Expectation failed: (afterToggle.first?.1 → "在改 Payroll.swift") == "在改代码"`（2 个 issue）。修复后通过。
- 状态：已修。

### R1b-06 [P3] 只有零宽 / 控制 / 方向字符的标题会画出一块空桌牌
- 现象：`PlateCopy.displayTitle` 只处理「空白」标题（TA-010），标题是纯零宽字符 / 控制字符 / 方向控制字符（U+200B、U+FEFF、U+2060、U+202E……）时不算空，桌牌 / 悬停卡片上画出一块什么都看不见的牌子；数据层不过滤这类字符。
- 根因：判断空标题用的是 `trimmingCharacters(in: .whitespacesAndNewlines)`，不含这些不可见字符。
- 修法：`displayTitle` 改成「标题里所有字符都是不可见字符（空白 / 控制 / 零宽 / 方向控制 / 字节序标记 / 软连字符）才算空」，显示占位文字；有可见字符的标题（哪怕夹着零宽字符）原样。
- 回归测试：`ReviewRegressionStageTests/r1b06_invisibleOnlyTitlesGetThePlaceholder`（9 种只有不可见字符的标题 → 占位文字；`a\u{200B}`、中文标题、emoji 原样）。
- 修复前失败：`ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "​‌‍") == (placeholder → "（没有标题）")`（5 个 issue：零宽 / FEFF / WORD JOINER / 双向控制 / 空白夹零宽）。修复后通过。
- 状态：已修。

### R2-001 [P2] 缩放变了但画布没变时，`PixelView` 的图像层不跟着变大小（小鱼缸 / 宠物条）
- 现象：设置里把小鱼缸从 2 倍改成 1 倍——窗口缩成一半，图像层还是原来的 2 倍大，只看得到画面的左上角 1/4；宠物条从 2 倍改成 3 倍——窗口变大，图像层只占 2/3，其余是空的；文字层已经按新缩放摆了，所以文字和图对不上。直到场景画布下一次变化才恢复（全员空闲时最长 5.1 秒；有人在忙时画布每拍都变，几乎看不出来）。复查员实测：`tank zoom2: view=(304,180) imageLayer=(0,0,304,180)；zoom→1 之后：view=(152,90) imageLayer=(0,0,304,180)`；宠物条 2→3：`view=(504,420) imageLayer=(0,0,336,280)`。
- 根因：`PixelView.show` 里 `imageLayer.frame` 只在 `needImage` 为真的分支里赋值，而 `needImage` 只看「画布变没变 / 视口变没变 / 哈希」，没有把缩放算进去（文字层的判断倒是包含缩放）；`TankScene` / `StripScene` 的画布内容和缩放无关，局部重绘时 `canvasChanged == false`。现有测试都是每次新建控制器、只在第一次渲染时读缩放，看不到「运行中改缩放」。
- 修法：`PixelView` 记 `lastImageZoom`，`needImage` 两个分支（场景知道变没变 / 要自己哈希）各加 `|| z != lastImageZoom`，更新图像层时一起记下。
- 回归测试：`Tests/BuddyOfficeTests/ReviewRegressionAppTests.swift`：`r2001_theImageLayerFollowsTheZoomWhenOnlyTheZoomChanged`（纯 PixelView：2 → 1 → 3 倍，画布没变，图像层宽 80 → 40 → 120；不知道变没变的场景也一样）、`r2001_theTankFollowsAZoomChangeOnTheNextRender`（真实的小鱼缸控制器：运行中 2 → 1，图像层宽 = 窗口内容宽）。
- 修复前失败：`ReviewRegressionAppTests.swift:29:9: Expectation failed: (imageWidth() → 80.0) == (40 → 40.0)`、`:31:9 (imageWidth() → 80.0) == (120 → 120.0)`、`:53:9: Expectation failed: (imageW → 304.0) == (viewW → 152.0)`（4 个 issue）。修复后通过。
- 状态：已修。

### R2-002 [P2] 提示卡出现时先闪在终点位置，再跳到屏幕外起点、再滑入（系统通知被拒时每条提醒都这样）
- 现象：`ToastController.show` 先 `layout` 把面板放到终点 `x = targetX`、`orderFront`，然后才设弹簧起点；面板在屏幕上的真实位置要等下一个 1/60 秒的 `step()` 才变成「终点 + 弹簧偏移」——所以是「闪现 → 消失 → 滑入」。另外新提示卡到来时 `layout` 会把已经在滑动 / 正在离场的提示卡也拽回终点。用户的通知授权是「拒绝」，**每一条提醒**都走这条路，违背「零闪帧」。复查员外部测量（`CGWindowListCopyWindowInfo`，开发副本）：25 张提示卡里 23 张的第一次观察位置就是终点；另一轮 11 张在终点位置停留 4–293 ms（中位 21 ms）。
- 根因：「先摆终点、再 order、再靠下一拍改成起点」，顺序错了（弹簧常数都对）。
- 修法：先定弹簧起点（屏幕外右侧）、再 `layout`、最后才显示；`layout` 的 x 带上弹簧当前偏移（`targetX + spring.value`），重新排版时不把滑动中的提示卡拽回终点。测试接缝：`ToastController.orderFront`（默认 `orderFrontRegardless`，测试里换成只记录的）、`step()` 和 `toasts` 改成 internal。复查员的外部再量：13 张提示卡没有一张再出现「先在终点」。
- 回归测试：`ReviewRegressionAppTests/r2002_aToastIsOffscreenWhenItIsOrderedFrontAndNeighboursAreNotYanked`（`orderFront` 那一刻面板 minX ≥ 屏幕右边缘；第一张滑到位后来第二张，第一张的 x 不变；第二张 orderFront 时也在屏幕外）。
- 修复前失败：`ReviewRegressionAppTests.swift:68:9: Expectation failed: ((atOrderFront.first?.minX ?? 0) → 1220.0) >= (vf.maxX → 1408.0)`、`:76:9 … (b?.minX → 1274.0) >= 1408.0`（2 个 issue）。修复后通过。
- 状态：已修（真实观感 / 提示卡的真实滑入动画只能间接验证，见 REPORT 第 7 节）。

### R2-003 [P2] 合并提醒里含 `blocked` 时，「N 位同事……」在同一次判定里先发出又立刻撤掉，用户什么都看不到
- 现象：`AlertCoordinator.post` 里 `attention`（决定文案「在等你」和 `waitingBased`）把 `.blocked` 也算进去；但 `blocked`（一轮做完、要你处理）的会话是 idle，不在 `waitingKeys` 里，于是 `observe` 末尾 `m.waitingBased && m.keys.isDisjoint(with: waiting)` 当场为真，把刚发出的合并提醒又 `.clear` 掉。两个桌面会话先后「做完了要你处理」：同一次 `observe` 的输出是 `[CLEAR d:a, CLEAR d:b, POST multi「2 位同事在等你」, CLEAR multi]`；走完整条流水线，提示卡 `shown = [d:a, multi]`、`dismissed = [d:a, d:b, multi]`，用户看到的是 A 的提示被撤、合并的一闪而过。fuzz（400 个种子 × 500 步）里「multi 发出后在同一次里被撤」146 次。
- 根因：`blocked` 的语义是「做完了要你处理」（事件），和「正在等」（状态）不是一回事，却被塞进同一个 `attention` 集合。
- 修法：`attention` 只认 `.approval / .question / .plan`；blocked 参与合并时走「有事找你」的文案（和 finished 混合一样），不当成「按等待清除」。
- 回归测试：`ReviewRegressionAppTests/r2003_aMergedAlertWithBlockedSessionsIsNotClearedImmediately`（两个桌面会话先后 blocked：合并提醒发出，之后每一拍都没有 `.clear(multi)`）。
- 修复前失败：`ReviewRegressionAppTests.swift:102:9: Expectation failed: !(cleared → <not evaluated>)`。修复后通过。
- 状态：已修。

### R2-004 [P2] 被 20 秒节流挡掉的「等你」提醒，这一整段等待再也不会提醒
- 现象：`AlertCoordinator.handleWaiting` 先 `ep.alerted = true`、后 `guard throttle(...)`：被节流挡住时这段等待已经被标成「提醒过」，之后每一拍都在 `guard !ep.alerted` 处直接返回。Claude 连着要批准几个工具：第一个 1.5 秒后提醒；用户 5 秒内批准了、随后走开；第二个请求在 8 秒时开始等——满 1.5 秒时距上一条只有 8 秒，被节流挡掉，且**永远不再提醒**，哪怕一直等到 2 分钟（Dock 角标 / 菜单栏图标 / 弹跳还在，但提示卡、系统通知、提示音都没有）。复查员实测提醒时刻 = `["1.53"]`，只有一条。
- 根因：任务书 7.2「同一个 buddy 的同一类提醒，20 秒内最多一条」被做成了「挡掉的这条永远丢弃」，测试 `sameBuddySameKindIsThrottledForTwentySeconds` 把「被挡掉」当成正确结果，没有检查「窗口过去后还在等」会怎样。
- 修法：先节流、后置位，文案（含提示卡宽度测量）放在节流之后：被挡住时 `alerted` 不置位，下一拍接着试，窗口一过、还在等就补发一条（不重复）。（`handleFinished` 里被节流的「做完了」是事件型提醒，丢掉可以接受，不动。）
- 回归测试：`ReviewRegressionAppTests/r2004_aThrottledWaitingAlertIsDeliveredWhenTheWindowPasses`（t=0 起等、1.5 秒第一条、批准、4 秒起第二次一直等到 120 秒：恰好两条，第二条在节流窗口刚过时（20–24 秒）；既有的全部 `AlertCoordinatorTests` 不用改）。
- 修复前失败：`ReviewRegressionAppTests.swift:118:9: Expectation failed: (posts.count → 1) == 2`。修复后通过。
- 状态：已修。

### R2-005 [P2] （测试基础设施）我加的 `DesktopMetaFileIOTests` 和 BuddyCoreTests 的 `FileAccessTests` 抢全局的 `FileIO.forbiddenHits / openObserver`
- 现象：`DesktopMetaFileIOTests`（C-032 的回归测试）设置全局的 `FileIO.openObserver`，还故意让指向 `.key` 的符号链接触发保险（`forbiddenHits += 1`）；`FileAccessTests` 里有测试断言 `FileIO.forbiddenHits == hitsBefore` / `== before + 3` 的精确值。BuddyCore 那边把会触发保险的测试塞进一个 `.serialized` 套件，但 `.serialized` 只管套件内部，**跨套件 / 跨 target（所有测试编进同一个进程）照样并行**。复查员：`--filter "safetyNetRefusesKeyAndSocketPaths|keyFilesAreNeverOpened|DesktopMetaFileIOTests"` 连跑 80 次，**56 次失败**（`RegistryTests.swift:235:9: Expectation failed: (FileIO.forbiddenHits → 1) == (hitsBefore → 0)`）；整套一起跑（532 个测试）4 次没撞上，所以完整回归里是偶发红灯，不是必现。
- 根因：我写的测试碰了全局状态，而别的测试依赖这个全局状态的精确值。
- 修法：`DesktopMetaFileIOTests` 不再碰 `openObserver`、也不制造会让 `forbiddenHits` 加一的诱饵：改成 FIFO 诱饵（读不卡住、被跳过）+ 应用层源码审计 `theOfficeLayerReadsFilesOnlyThroughFileIO`（BuddyOffice 源码里没有绕过 FileIO 的读文件写法：`FileManager.default.contents(`、`contentsOfDirectory`、`Data(contentsOf:` …）；「不跟着符号链接读 .key」由 BuddyCore 的 `FuzzSecurityTests` / `FuzzRegressionTests` 证明（它们本来就在串行套件里）。
- 回归测试：`DesktopMetaFileIOTests`（3 个）；`QA/tools/full_regression.sh` 里加了「竞争组合连跑 20 次」的一步（复查员建议）。
- 修复前失败：复查员的测量：80 次里 56 次失败；源码审计那条在撤销 C-032 的修复（`JumpService` 改回 `FileManager.default.contents`）之后变红（`QA/tools/verify_fail_before.py` 的 C-032 一步）。修复后同样的组合连跑 30 次 0 次失败。
- 状态：已修。

### SAN-01 [P2] （测试 / 审计工具的线程安全）text-audit 的像素字审计钩子有数据竞争：`withDraws` 读收集结果时和别的线程晚到的 append 竞争（ASan 抓到 heap-use-after-free）
- 现象：最后一次 ASan 下跑表现层 + 应用层测试（`QA/tools/asan_tests.sh`）时，`TextAuditMatrixTests.quickMatrixHasZeroViolationsAndReallyCoversTheScenes` 在 `TextAudit.check` 里读像素数组时报 `heap-use-after-free`（原始报告在 `QA/evidence/san01/original-asan-report.txt`）；同一套测试在上一轮 ASan 里是干净的——竞争窗口很窄，碰运气才出。只影响 `buddyctl text-audit` 和测试（App 运行时 `auditEnabled` 恒为 false，不走这条路径），但它意味着「text-audit 0 违规」这个数字背后的收集有时会读到坏内存。
- 根因：`PixelFont.draw` 在审计打开时把记录交给全局 sink，sink 是在锁外调用的；`TextAuditRunner.withDraws` 在 `setAuditSink(nil)` 之后直接读 `box.value`，而别的线程（并行跑的其它测试，文档里就写着会被收进来）里「已经取到 sink、还没 append 完」的那次 draw 会在 box 的锁里改同一个数组 → 数据竞争，读到的数组缓冲区可能已经被换掉 / 释放。另外 `draw` 里没加锁地读 `auditEnabled`，和 `setAuditSink` 里加锁的写也是数据竞争（TSan 报告）。
- 修法：`Box.get()` 在锁里取拷贝，`withDraws` 用它；`PixelFont.draw` 用 `auditActive()`（在 `auditLock` 里读开关；一次没有争用的 NSLock 约 20 ns，每帧只有几十次 draw）。
- 回归测试：`ReviewRegressionStageTests/san01_withDrawsIsSafeWhileOtherThreadsKeepDrawingPixelText`（4 个后台线程不停地画像素字，主线程收集 4000 次并逐条读像素；自己画的那一条必须每次恰好一条）。QA/tools/tsan_run.sh 现在也把整个表现层 + 应用层测试套件放在 TSan 下跑一遍。
- 修复前失败：`QA/evidence/san01/`：撤销修复后在 ASan 构建下连跑 3 次，3 次都以 `Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range` 崩掉（进程退出码 1）；TSan 报 5 处（`PixelFont.setAuditSink` 写开关 vs `draw` 读开关；`withDraws` 读 `box.value` vs sink 里的 append，含 Swift access race）。修复后 ASan 连跑 3 次通过、TSan 连跑 2 次 0 报告（`san01-after-tsan2-1.log`）。普通（无 Sanitizer）运行下这条测试撤销修复后不一定红——窗口很窄，要靠 Sanitizer 才确定地抓到，这一点如实写在测试注释里。
- 状态：已修。

### SAN-02 [P2] （测试基础设施）`OpenAuditTests` 的两条测试被并行跑的别的测试的 open 污染，间歇性变红（最后一次完整回归的第二遍红过一次）
- 现象：最后一次完整回归第二遍里，`open 审计：在一棵放了诱饵的假 home 上跑一遍数据层…` 红了：`offenders` 里是 `/var/folders/…/buddy-replay-fse-…/.claude/projects/…/subagents/agent-*.jsonl` 三个路径（别的测试——replay 测试——读它们自己的临时目录）；同一份代码的第一遍全绿。原始输出在 `QA/evidence/san02/failure-in-regression-run2.txt`。
- 根因：我加的 `OpenAudit` 装的是进程全局的 `FileIO.openObserver`，同一个进程里并行跑的别的套件（`.serialized` 只管本套件内部）的 open 也被观察到，被记成「其他位置的文件」→ `offenders` 非空。同一条测试文件里的另一条（`totalOpens == 4`）有同样的问题。这和 R2-005 是同一类（全局状态被并行套件污染），我加 `OpenAudit` 时没有想到。
- 修法：`OpenAudit.install(scope:)` / `OpenAudit.run(…, scope:)`：只记这个前缀下的路径；测试里把范围缩到自己的假 home。真实环境里（`buddydump --audit-opens`）不设范围（进程里的每一次 open 都要看）。
- 回归测试：`FileAccessTests` 扩展里的 `openAudit_scopeKeepsConcurrentOpensOfOtherTestsOut`（另一个线程在审计期间不停地打开别处的文件：限定范围的审计 `ok`，不设范围的会把那些 open 记成「其他位置的文件」）；原来的两条测试改成限定范围。
- 修复前失败：`QA/evidence/san02/before-fix-openAudit-tests.log`：让 `record` 不看范围（= 修复前的行为）之后，新测试红：`Expectation failed: (scoped.ok && !scoped.rows.contains { $0.name == "其他位置的文件" } … → false)`；修复后同一批测试通过（`after-fix-…log`）。
- 状态：已修。另外把「OpenAuditTests + 竞争组合」加进了 `full_regression.sh` 的连跑 20 次那一步。

### SOAK-01 [P3] 读真实 / replay 数据的进程，物理占用在最初十几分钟会涨 4～20 MB（文字图片缓存被慢慢填满，上限 600 张 ≈ 20 MB）
- 现象：最后一次 35 分钟长跑里，读数据的几路（真实数据开发副本 39 → 48 MB、replay 26 → 31、replay 压力 27 → 36）的物理占用一直在爬，`soak_watch` 的「后 1/3 中位数 − 前 1/3 中位数 ≤ +3 MB」判据报了 ✗；不读数据的演示 / 空闲几路完全平（23–28 MB）。`footprint` 分类里涨的**全是** `CG Raster Data`（一个 replay 进程 0.8 MB → 3.8 MB，区域数 24 → 119），`Malloc Small` 反而略降；`leaks` 全部 0 leaks。
- 根因：不是泄漏，是有上限的缓存在被填满：`TextRenderer.shared` 缓存渲染好的文字图片（标题、文件名、计时器每秒不同的文字……都是新的 key），先进先出、上限 600 张；每张（桌牌大小、2× 缩放）约 34 KB，装满 ≈ 20 MB。真实数据里的文字变化快，开发副本大约 11 分钟就装满，之后 14 分钟曲线平的（46 MB = 26 MB 基线 + 20 MB）；replay 里新文字出得慢（每分钟约 12 张），到长跑结束还没装满（压力档 35 分钟 27 → 36 MB）。另有一处与 App 无关的阶跃：10:27:35 显示器被唤醒（`pmset -g log`：Display is turned on），七个进程同一秒各跳了 +1～+7 MB（含不读数据的演示进程），跳完又是平的。
- 修法：不改。缓存有上限、装满后不再涨，最坏 ≈ 基线 + 20 MB ≈ 50 MB，低于 80 MB 预算；把上限降下来会让悬停 / 桌牌文字更频繁地重画，换来的只是最坏情况少几 MB。加了测试钉住这个上限和装满时的字节数。
- 回归测试：`TextCacheBoundTests`（渲染 1500 种不同的文字：最早的被淘汰、最近的还在缓存里；装满 600 张桌牌大小的文字图片共约 20 MB，断言 < 30 MB）。
- 状态：不修（不是泄漏：缓存有上限 = 600 张、装满约 20 MB，长跑里已经装满的那一路实测停在 46 MB 不再涨；见 REPORT 第 5 节的分解和 `QA/evidence/leak-hunt/`）。

### R3a-01 [P2] （测试基础设施）红线测试 `fuzz_registryScannerWithDecoyFiles` 在默认并行的 `swift test` 里间歇性变红（8 次里 2 次）：观察口没有按自己的临时目录过滤
- 现象：终审复查员 R3a 在 `BuddyCoreTests|BuddyOfficeTests` 并行连跑 8 次（608 个测试），第 1、7 次红，同一条同一处：`FuzzSecurityTests.swift:128 names.allSatisfy { Paths.isRegistryFileName($0) }`，被 open 的文件名里有 `agent-aafga30000000000.jsonl` / `5e1a0000-….events.jsonl`——别的并行套件在它们自己临时目录里的 open。这是「绝不打开 `.key` / 非 `<pid>.json`」红线的直接证据之一；只会误报红、不会误报绿，但「789 个测试全过」在默认并行方式下复现不了。同一根因还有 `FuzzSecurityTests` 的符号链接那条和 `FuzzRegressionTests` 里两条（断言对陌生路径敏感）。
- 根因：`FileIO.openObserver` 是进程全局的，这几条测试装观察口时把观察到的每个路径都当成自己的（SAN-02 只把 `OpenAudit` 自己的测试限定了范围，兄弟测试没动）。
- 修法：四处观察口都改成只记自己临时目录前缀下的路径（`if p.hasPrefix(dir.path)`）。
- 回归测试：`FuzzSecurityTests`（`FileAccessTests` 扩展）里的 `r3aP21_theRegistryDecoyTestIsNotFooledByOtherThreadsOpens`：另一个线程一直在打开别处的 jsonl 文件时原样调用那条测试，必须通过。
- 修复前失败：`QA/evidence/r3/fail-before-summary.txt`：撤销范围过滤后这条测试红：`FuzzSecurityTests.swift:128:9: Expectation failed: names.allSatisfy { Paths.isRegistryFileName($0) }`；复查员的原始失败在 `QA/review-R3a.md`。修复后通过。
- 状态：已修。

### R3a-02 [P2] 桌面会话元数据里的未来时间戳没有像其他数据源那样夹紧：一个 `lastFocusedAt` 让「未读」永远不亮，一个 `lastActivityAt` 让下班工位的幽灵座位占位、超过 12 小时也不走
- 现象：hook、会话记录、identities.json 都把「比现在晚一天以上」的时间戳夹回现在（C-006 / C-026，当时定为 P1），桌面元数据（`DesktopMetaReader.parse` 只查了 2000–2200 年）漏了。复查员的假时钟探针：`lastFocusedAt` = 30 天以后 → 一轮做完后 `unread = false`（一小时前则 `true`）；5 个下班工位候选里一个 `lastActivityAt` = 30 天以后 → 它排第一、挤掉真候选，推进 13 小时后别的都到期了它还在。需要 Claude 桌面 App 写出未来的时间（时钟被拨快过 / 虚拟机恢复后时钟不对），不是正常使用会遇到的，所以定 P2。
- 根因：`SessionEngine` 用 `meta.lastFocusedAt`（`f > e → unread = false`）和 `meta.lastActivityAt`（下班工位的选取 / 到期）时没有夹紧。
- 修法：`DesktopMetaReader` 带引擎的时钟，读到元数据时把比现在晚一天以上的 `createdAt` / `lastActivityAt` 夹成「现在」、`lastFocusedAt` 直接丢掉（`clampingFuture`；最初是也夹成「现在」，最后一轮复查 R4a-01 指出夹成现在的聚焦时间会永远比真实的更新，改成丢弃）；`SessionEngine` 把自己的 `options.now` 传进去。应用层的第二个读取器见 R4a-01。
- 回归测试：`ReviewRegressionTests`（`StateRuleTests` 扩展）：`r3aP22_aFutureLastFocusedAtDoesNotSuppressUnread`（一小时前 / 30 天以后都是未读）、`r3aP22_aFutureLastActivityAtDoesNotPinADormantSeatForever`（最多 4 个下班工位；13 小时后全部到期）。
- 修复前失败：`QA/evidence/r3/fail-before-summary.txt`：`ReviewRegressionTests.swift:87:9: Expectation failed: (h.snap(K.key)?.unread → false) == …`；`:102:9 … (h.snapshots → […d:local_222…])` 13 小时后还在。修复后通过。
- 状态：已修。

### R3b-01 [P2] （测试基础设施）`DesktopMeta.baseOverride` 被多个套件并行改写，R2-008 的测试间歇性变红（终审 R3b 40 次里 4 次，R3c 30 次里 4 次；R3c-03 是同一条）
- 现象：`ReviewRegressionAppTests.swift:164` 期望 `/x/fake-home/…`，实际读到 `/var/folders/…/desktopmeta-…`。写这个全局量的有 `DesktopMetaFileIOTests`（两处）、R2-008 的用例、`EngineConfigTests` 里带 `--data-root` 的三条（后者改完从不复位，override 会一直留在进程里）。`.serialized` 只管套件内部，跨套件照样并行。完整回归没抓到：4 遍完整回归全绿；「会抢全局量的组合连跑 20 次」清单里没有这几条。
- 根因：和 R2-005 / SAN-02 同一类：测试写进程全局状态、跨套件并行；R2-008 新加的用例又造了一个。
- 修法：新增 `DesktopMetaGate.exclusive { … }`（一把全局锁，进出都把 `baseOverride` 复位成 nil），写它 / 依赖它的 6 条测试（`DesktopMetaFileIOTests` 两条、R2-008、`EngineConfigTests` 三条）都走这把锁。
- 回归测试：这一类没法写成确定性的单元测试（是并行时序问题）；`full_regression.sh` 里「会抢全局量的组合连跑 20 次」这一步的清单加上了 `DesktopMetaFileIOTests|EngineConfigTests|ReviewRegressionAppTests`。
- 修复前失败：复查员的测量（`QA/review-R3b.md`、`QA/review-R3c.md`）：竞争组合连跑 40 次 4 次红 / 30 次 4 次红，输出同上。**我自己撤销互斥后同一个组合连跑 40 次没有复现红灯**（时序问题，这台机器这会儿的负载下没撞上），修复后连跑 60 次 0 次红（`QA/evidence/r3/fail-before-summary.txt`）。
- 状态：已修（修复前失败的证据是复查员的测量，我这边没能复现；如实写在这里）。

### R3b-02 [P2] 隐私模式下桌牌标题、悬停卡片标题和项目路径的隐藏，没有任何测试钉住（变异全部存活）
- 现象：复查员给 `OfficeScene.swift:509`、`HoverCard.swift:40`、`HoverCard.swift:42` 三处隐私分支各做了一个失效的变异，整套 BuddyStage + BuddyOffice 379 个测试全部通过——以后有人重构这几处、悄悄把标题露出来，所有测试仍全绿（R1b-03 就是这样漏掉的）。当前行为是对的（复查员的端到端泄漏扫描 0 处泄漏）。
- 根因：隐私模式的文字隐藏发生在好几处，逐处的测试只覆盖了 `PlateCopy` 的动作 / 状态行，没有端到端的「标题 / 路径 / 详情不出现在任何文字层里」的断言。
- 修法：不改产品代码；补端到端泄漏扫描测试。
- 回归测试：`ReviewRegressionStageTests/r3b02_privacyModeLeaksNothingIntoAnyTextTheUIProduces`：18 种工具 × 忙 / 等批准 × 刚开始 / 做了很久，会话标题、项目路径、statusDetail、工具详情、MCP server 名都带同一个标记串，走完 Director、办公室（在场 / 下班 / 悬停）、悬停卡片，所有文字层里不能出现它。
- 修复前失败：把三处隐私分支各失效一次（三个变异），这条测试三次都红（`QA/evidence/r3/fail-before-summary.txt`：`ReviewRegressionStageTests.swift:262:9: Expectation failed: leaks.isEmpty …`）。
- 状态：已修。

### R3c-01 [P2] 合并提醒「N 位同事在等你」的 N 是「最近 2 秒里发出的条数」，不是「被合并 / 正在等的人数」；被并进去的人的提示卡被撤掉后不会补回来
- 现象：A 在 1.5 秒提醒、B 在 1.9 秒提醒（合并成「2 位同事在等你」，A、B 各自的卡被撤掉）；C 在 3.5 秒提醒（比 B 晚 1.6 秒、比 A 晚 2.0 秒）：窗口里只剩 B、C，合并卡写成还是「2 位同事在等你」，三个人在等、A 没有任何卡盖着了，A、B、C 处理完之前界面上再没有 A 的提示。复查员的随机模拟（3 个会话 × 1500 个场景）里 1186 次合并提醒有 349 次（29%）N 偏小。
- 根因：`AlertCoordinator.post` 用 2 秒滑动窗口 `recent` 数人，合并卡替换上一张同 key 的合并卡时没有把上一张已经合并进去的人带上。
- 修法：上一张合并卡还在屏幕上（`mergeCarry` = 6 秒，提示卡的寿命）时，新的合并卡把它合并进去的人也算进去（「在等你」的合并卡只带还在等的人）；只在最近 2 秒里本来就要合并（≥ 2 人）时才这么做，单条提醒的行为不变。
- 回归测试：`ReviewRegressionAppTests`：`r3c01_theMergedCountIncludesEveryoneAlreadyFoldedIntoTheCard`（三个人先后到，最后一张合并卡「3 位同事在等你」）、`r3c01_aPersonWhoStoppedWaitingIsNotCarriedIntoTheNextMergedCard`（A 已经处理掉就是「2 位」）。
- 修复前失败：`ReviewRegressionAppTests.swift:282:9: Expectation failed: (lastMulti → "2 位同事在等你") == "3 位同事在等你"`（`QA/evidence/r3/fail-before-summary.txt`）。修复后通过。
- 状态：已修。

### R3c-02 [P2] 系统通知授权在运行期间被关掉后，兜底提示卡不出现（直到 App 下一次被激活 / 打开设置页）
- 现象：`NotificationService.post` 用缓存的授权状态：启动 / 办公室窗口出现 / App 被激活 / 打开设置页时才刷新。用户在「系统设置 → 通知」里把它关了而 Buddy 一直在后台（菜单栏 App，办公室窗口被盖住时不会被激活），`post` 仍把提醒交给系统，被悄悄吞掉，没有像素提示卡，只剩 Dock 角标 / 菜单栏图标 / 提示音——B-001 要求的「系统通知被拒时兜底提醒确实会出现」的反面。复查员的假通知中心探针：`added=1 toasts=0`。
- 根因：授权状态只在少数几个时刻刷新，发通知前 / 后没有核对。
- 修法：走系统通知发出之后再读一次真实状态（`refresh`）；已经被拒了、这条提醒也没被撤掉，就补一张兜底提示卡（缓存也随之更新，之后的提醒直接走兜底）；`liveKeys` 记着还有效的提醒（`clear` 时移除，上限 200）。
- 回归测试：`ReviewRegressionAppTests/r3c02_aRevokedSystemAuthorizationStillGetsTheFallbackToast`（一直授权：只走系统、没有卡；关掉之后补一张卡、缓存更新、之后的提醒直接走兜底）。
- 修复前失败：让核对失效后这条测试红：`ReviewRegressionAppTests.swift:314:13: Expectation failed: (toast.shown.count == 1 → false)`、`:317:13 (toast.shown.count == 2 → false)`。修复后通过。
- 状态：已修（真实的系统授权流程只能间接验证，见 REPORT 第 7 节）。

### R3a-P3-01 [P3] hook-merge.py 会把 `1e400` 这类溢出成无穷大的数字写成 `Infinity`（不是合法 JSON），读回校验发现不了（`inf == inf`）
- 现象：`scripts/hook-merge.py:123-130`：`printf '{"a": 1e400}' > s.json; hook-merge.py install --settings s.json` 输出 `"a": Infinity`（`node` 的 `JSON.parse` 会拒绝）。
- 根因：`json.dump` 默认允许 NaN / Infinity。
- 修法：不修（真实的 settings.json 里不会有这种数（Claude Code 自己写的是有限数）；要修就是 `allow_nan=False` 并把 `ValueError` 转成 `Refuse`。）
- 回归测试：无。
- 状态：不修（真实的 settings.json 里不会有这种数（Claude Code 自己写的是有限数）；要修就是 `allow_nan=False` 并把 `ValueError` 转成 `Refuse`。）

### R3a-P3-02 [P3] hook-merge.py 遇到孤立代理项字符（`"\ud800"`）时 `UnicodeEncodeError` 直接抛栈追踪；目标目录只读时留下一份备份
- 现象：退出码 1；原文件没动、临时文件清掉了，备份留下。
- 根因：写文件前没有把编码错误转成 `Refuse`。
- 修法：不修（不损坏数据，真实 settings.json 里不会有孤立代理项。）
- 回归测试：无。
- 状态：不修（不损坏数据，真实 settings.json 里不会有孤立代理项。）

### R3a-P3-03 [P3] `SessionEngine.processInbox` 用 `inbox.removeFirst()` 逐个出队：一次 poll 里积压 2 万条 hook 事件时是 O(n²)
- 现象：复查员实测 2 000 条 19 ms、20 000 条 1.09 s、20 万条（被截成最新 2 万）2.59 s。
- 根因：数组头部出队。
- 修法：不修（真实使用里积压最多一两千条；只有 App 被挂起很久后的第一次 poll 可能卡 1 秒，且事件数有上限。）
- 回归测试：无。
- 状态：不修（真实使用里积压最多一两千条；只有 App 被挂起很久后的第一次 poll 可能卡 1 秒，且事件数有上限。）

### R3a-P3-04 [P3] `SubagentReader.helpers` / `order` 在会话存续期间只增不减
- 现象：工作流派几百个小助手的会话里，每次列目录都要对所有没结束的小助手 stat 一遍；没测到实际数字。
- 根因：每个子代理文件一个 `TranscriptReader`，会话结束才释放。
- 修法：不修（没有实测影响，几百个小助手的会话极少。）
- 回归测试：无。
- 状态：不修（没有实测影响，几百个小助手的会话极少。）

### R3a-P3-05 [P3] `BuddyCoreInfo.version = "0.1.0"` 没有任何人引用，注释还说 build-app.sh 也从这里读（实际读 `VERSION`）
- 现象：过期的死代码 + 误导性注释。
- 根因：版本号后来挪到了 VERSION 文件。
- 修法：不修（无功能影响。）
- 回归测试：无。
- 状态：不修（无功能影响。）

### R3a-P3-06 [P3] `buddyctl dump` 的文档头说「绝不打印对话内容」，但表里「细节」列会打印工具 detail（命令 / 路径 / URL / 搜索词）和「桌面总结」
- 现象：`DumpCommand.swift:176-180`；`--json` 里有 `title` 和 `activityDetail`。QA 证据目录里没有这类内容（复查员 grep 过）。
- 根因：文档说得比行为宽。
- 修法：不修（开发命令，输出在用户自己的终端里；只是措辞过宽。）
- 回归测试：无。
- 状态：不修（开发命令，输出在用户自己的终端里；只是措辞过宽。）

### R3a-P3-07 [P3] `dump --audit-opens` 文档说「只读地」，但和 `--persist` 一起给时会读写真实的 identities.json / ledger.json
- 现象：`DumpCommand.swift:44/69`：和运行中的 App 抢同一份文件。
- 根因：两个开关没有互斥。
- 修法：不修（开发命令，只有手敲两个开关一起给才会。）
- 回归测试：无。
- 状态：不修（开发命令，只有手敲两个开关一起给才会。）

### R3a-P3-08 [P3] Core 的 `SessionEngine.Options.dormantMax` 为负数时 `prefix(-1)` / `dropFirst(-1)` 会 trap
- 现象：`SessionEngine.swift:331/347`。
- 根因：A-004 只在 App 层夹了（`EngineConfig.values`），Core 公开接口本身没夹。
- 修法：不修（App 里不可达（设置的值先被夹过）。）
- 回归测试：无。
- 状态：不修（App 里不可达（设置的值先被夹过）。）

### R3b-P3-03 [P3] 阿拉伯文 / 天城文 / 叠字符号 / 泰文标题在桌牌和悬停卡片里会被裁掉一截
- 现象：`text-audit` 抓得到，复查员的探针里 570 处（R1b-P3-05 的扩展）。
- 根因：图片高度按苹方的 ascent / descent 定，回退字体更高。
- 修法：不修（极少见的文字，只影响观感，不会溢出到别的元素上。）
- 回归测试：无。
- 状态：不修（极少见的文字，只影响观感，不会溢出到别的元素上。）

### R3b-P3-04 [P3] `displayTitle` 的不可见字符清单不全：U+3164、U+2800、U+034F、变体选择符、只有组合附加符等 10 类标题仍会画出一块空桌牌
- 现象：R1b-06 修了零宽 / 方向控制 / 控制字符，这几类没在清单里。
- 根因：清单是列举式的。
- 修法：不修（极少见的标题，后果只是一块空牌子。）
- 回归测试：无。
- 状态：不修（极少见的标题，后果只是一块空牌子。）

### R3b-P3-05 [P3] 隐私模式下 MCP 屏幕仍画 server 名的首字母
- 现象：端到端泄漏扫描里唯一的泄漏点（桌牌 / 状态行 / 悬停卡片 / 下班工位的文字层都是 0 处）。
- 根因：`ScreenContent.mcpInitial(name)` 没有隐私分支。
- 修法：不修（只泄漏一个字母；改它要动 ScreenContent 的画法和金图；文字层的隐藏已经由 R3b-02 的端到端测试钉住。）
- 回归测试：无。
- 状态：不修（只泄漏一个字母；改它要动 ScreenContent 的画法和金图；文字层的隐藏已经由 R3b-02 的端到端测试钉住。）

### R3b-P3-06 [P3] `AppLayerFixTests.swift:297` 在测试里不加锁地读全局 `staticCache.count`
- 现象：理论上的数据竞争，复查员没复现出红灯。
- 根因：测试里读全局量没加锁。
- 修法：不修（只在测试里，没有复现。）
- 回归测试：无。
- 状态：不修（只在测试里，没有复现。）

### R3b-P3-07 [P3] 悬停的座位号为 `Int.max` / `Int.min` 时 `OfficeScene.render` 乘法溢出崩溃
- 现象：UI 里不可达：悬停座位来自命中缓冲，最大 999。
- 根因：没有对座位号设防。
- 修法：不修（不可达。）
- 回归测试：无。
- 状态：不修（不可达。）

### R3c-P3-04 [P3] 时钟往回拨时（R2-014 的残留）：桌面会话「做完了」的 8 秒等待里时钟拨回，这条待发提醒卡到时钟追上为止；`recent` 里「来自未来」的记录被当成「刚发过」而错误合并
- 现象：`AlertCoordinator.swift:195`（`now - f.since >= wait` 为负）；探针：拨回 1 小时后 30 秒内 0 条，之后 1 小时才补发一条过期的「做完了」。
- 根因：R2-014 只处理了节流记录和等待段的 `since`，没处理 `finished` 待发和 `recent`。
- 修法：不修（极端场景（拨钟 + 桌面「做完了」的 8 秒窗口内）；后果只是一条提醒晚到。）
- 回归测试：无。
- 状态：不修（极端场景（拨钟 + 桌面「做完了」的 8 秒窗口内）；后果只是一条提醒晚到。）

### R3c-P3-05 [P3] `AlertText.approvalBody` 对超长工具名在主线程上每次缩短 1 个字符就量一次提示卡宽度
- 现象：2048 字的工具名实测 754 ms（拉丁字母）/ 1257 ms（中文），普通名字 4–7 ms。
- 根因：逐字符缩短 + 每次用 CoreText 量宽。
- 修法：不修（只有被写坏 / 恶意的 hook 数据能触发（数据层对标签类字段有 2048 字上限），且每个 buddy 每 20 秒最多一次。）
- 回归测试：无。
- 状态：不修（只有被写坏 / 恶意的 hook 数据能触发（数据层对标签类字段有 2048 字上限），且每个 buddy 每 20 秒最多一次。）

### R3c-P3-06 [P3] 设置页「数据源诊断」的 `diag` 文字只在 `.onAppear` 和按钮里生成：先看过诊断，再在同一个设置窗口里打开隐私模式，切到诊断页看到的仍是带标题的旧文字
- 现象：`authText`（授权状态文字）同理只在 onAppear 刷新。
- 根因：R2-006 只保证生成时隐私生效。
- 修法：不修（窄：设置窗口重新打开就刷新。）
- 回归测试：无。
- 状态：不修（窄：设置窗口重新打开就刷新。）

### R3c-P3-07 [P3] 办公室里点小人是「命中座位号 → 点击那一刻按座位号找会话」，座位刚换主人的 ≤ 100 ms 内点旧画面会跳到新主人的会话
- 现象：`AppModel.jump(seat:)`；小鱼缸 / 宠物条是按渲染那一刻的快照再按 key 找。
- 根因：办公室的命中缓冲只带座位号。
- 修法：不修（窗口极小（一帧内换主人）。）
- 回归测试：无。
- 状态：不修（窗口极小（一帧内换主人）。）

### R3c-P3-08 [P3] 开发副本在设置页里开关「开机启动」，会读写和正式版**同一个** LaunchAgent 文件 `~/Library/LaunchAgents/local.buddy-office.plist`
- 现象：`SystemHelpers.swift` `LoginItem.agentURL`：关开关会把用户真实 App 的登录项删掉。复查员没有点过。
- 根因：文件名没有跟 bundle id 走。
- 修法：不修（只影响开发副本 + 手动去点那个开关。）
- 回归测试：无。
- 状态：不修（只影响开发副本 + 手动去点那个开关。）

### R3c-P3-09 [P3] `StripPanelController.model` 是强引用、`AppModel` 持有 `strip`：循环引用
- 现象：App 生命周期内无影响（测试里每个 `AppModel` 会泄漏一份）。
- 根因：互相强引用。
- 修法：不修（App 全程只有一个 AppModel。）
- 回归测试：无。
- 状态：不修（App 全程只有一个 AppModel。）

### R4a-01 [P2] R3a-02 的修复漏了应用层的第二个读取器：`DesktopMeta.readAll()` 没处理未来的 `lastFocusedAt`，一个会话永远是「最近聚焦的」，提醒丢失 / 无谓打扰
- 现象：最后一轮复查 R4a：会话 X 的 `lastFocusedAt` 比现在晚 30 天（桌面 App 的时钟被拨快过），Y 是用户真正在看的，Claude 在最前面：X 的等批准 / 提问 / 做完了永远被当成「你一直在看」而不提醒（只剩 Dock 角标 / 菜单栏），Y 反而被当成没在看、照样弹提示卡。探针输出：`mostRecent=Optional("local_x") X-looking=true Y-looking=false`（引擎侧同一份数据 X 已被处理）。
- 根因：应用层（`JumpService.swift` 的 `DesktopMeta`：提醒判定的 `isMostRecentlyFocused`、点击跳转前后的 `lastFocusedAt`）是独立的第二份读取 + 解析，走原始值；R3a-02 只改了 BuddyCore 里的 `DesktopMetaReader`。
- 修法：`DesktopMeta.lastFocused(path:)` 把比现在晚一天以上（或不是有限数）的聚焦时间丢掉（当作没有）；同时引擎侧的 `lastFocusedAt` 也改成丢弃（夹成「现在」的话它会永远比真实的聚焦更新，同样的错位）。
- 回归测试：`ReviewRegressionAppTests/r4a01_theAppLayerDropsAFutureLastFocusedAt`（X = 现在 + 30 天、Y = 现在 5 秒前：`readAll` 里没有 X，`mostRecentHost` 是 Y，`isMostRecentlyFocused(host: "local_x")` 为 false）。
- 修复前失败：`QA/evidence/r3/fail-before-summary.txt`（R4 一节）。
- 状态：已修。

### R4b-01 [P2] （测试基础设施）账本的 `.background` 队列在 CPU 饱和时被饿死，一族等它的测试间歇性变红（复查员整套默认并行 6 遍红 3 遍）
- 现象：最后一轮复查 R4b：机器被别的进程占满时（同时跑几路检查，复查员那时 load 75–240），`SpecTraceCoreTests` 的 4.3-42（`sem.wait(timeout: 90)` 超时）、C-004 / C-005 / C-028、`EnginePresenceTests` / `StateRuleTests` / `StateRuleChainTests` 里读 `tokens.output` 的几条、`FuzzPersistenceTests` 的 `fuzzRun(timeout: 120/180)` 都红——全是「等 `.background` 队列上的账本扫描」超时；红的位置（`tokens.output == 0`、`waitUntilIdle → false`）看起来像账本 / 引擎逻辑坏了，会误导排查。最小复现：只跑 4.3-42 这一条 + 8 个 CPU 空转进程 → 90 秒后超时（不是测试之间互相踩，是队列被饿死）。只会误报红、不会误报绿。
- 根因：`TokenLedger` 的默认队列是 `.background`（设计如此：第一次扫大文件不抢前台 CPU），引擎测试没有注入点，只能等它被调度；另外 C-028 的外层 `fuzzRun(timeout: 20)` 比里面的 `waitUntilIdle(timeout: 60)` 还短。
- 修法：`TokenLedger.init(queue:)` 改成可选（nil = 默认 `.background` 队列，`makeDefaultQueue()`），`SessionEngine.Options.ledgerQueue` 把它透传；所有引擎测试（`Harness` 等 9 处）和直接建账本的测试（13 处）传 `.userInitiated` 的队列（`testLedgerQueue()`）；4.3-42 改成同步读默认队列的 QoS 属性（不用等被调度），实际跑的 QoS 只在等到回调时才断言；C-028 的外层超时放宽到 90 秒。「默认队列就是 `.background`」仍由 4.3-42（属性）和 4.3-43（源码）钉住。
- 回归测试：这一类是「机器满载」下的调度问题，没法写成确定性的单元测试；验证办法是复查员的最小复现——修复后同样的压力（整套默认并行 + 8 个 CPU 空转进程）下重跑（`QA/evidence/r3/` 里的 R4 一节）。
- 修复前失败：复查员的测量（`QA/review-R4b.md`：整套默认并行 6 遍红 3 遍；4.3-42 单条 + 8 个空转进程 90 秒后 `timedOut`）。**我自己撤销修复（测试的账本队列改回 `.background`）、开 8 个 CPU 空转进程再跑受影响的 96 个测试没有复现红灯**（`QA/evidence/r3/fail-before-r4.txt`：调度饥饿是否出现取决于机器当时的状态，我这一次没撞上）；修复后同样的压力下 96 个测试通过。如实写在这里，没有把「没复现」说成「复现了」。
- 状态：已修（修复前失败的证据是复查员的测量，我这边没能复现）。

### R4a-P3-02 [P3] 合并卡「N 位同事在等你」的 N 可能比真正还在等的人数多
- 现象：2 秒窗口 `recent` 里的人不管现在还在不在等都算进去，carry 部分用的 `waitingKeys` 是上一拍的旧值：A 刚提醒、0.3 秒后被批准，1.7 秒后 B 的提醒到 → 「2 位同事在等你」，其实只有 B 在等。随机模拟里 12 772 张合并卡有 424 张（3.3%，模拟里状态切换比真实频繁得多）；不是 R3c-01 引入的。
- 根因：`recent` 只按时间窗口数人。
- 修法：不修（极窄（两条提醒 < 2 秒且第一个人马上被批准），后果只是数字偏大。）
- 回归测试：无。
- 状态：不修（极窄（两条提醒 < 2 秒且第一个人马上被批准），后果只是数字偏大。）

### R4a-P3-03 [P3] 「有事找你 / 做完了」型合并卡盖住了正在等的人之后，这些人处理完了系统通知中心里那条「N 位同事有事找你」不会被撤
- 现象：`observe` 只撤「在等你」型的合并卡；单独的「做完了 / 出错」通知本来也不撤，属同一取向。提示卡 6 秒后自己收。
- 根因：设计取向。
- 修法：不修（只是系统通知中心里多留一条。）
- 回归测试：无。
- 状态：不修（只是系统通知中心里多留一条。）

### R4a-P3-04 [P3] `NotificationService.statusText` 把 `.ephemeral` 显示成「已授权」，但 `systemAllowed` 只认 `.authorized` / `.provisional`
- 现象：`.ephemeral` 只属于 App Clip，macOS 上编译不过，不可达。
- 根因：两处口径不一致。
- 修法：不修（不可达。）
- 回归测试：无。
- 状态：不修（不可达。）

### R4a-P3-05 [P3] `NotificationService.post` 的 `liveKeys.count > 200 → removeAll()` 会把仍然有效的 key 也清掉
- 现象：需要「授权刚被关掉、补卡的回调还在路上」且累计 200 个从没被撤过的 key（做完了 / 出错的 key 不会被撤）三个条件同时成立，那几条的补卡会被丢掉。
- 根因：上限的清法是整个清空。
- 修法：不修（三个条件同时成立才触发。）
- 回归测试：无。
- 状态：不修（三个条件同时成立才触发。）

### R4b-P3-01 [P3] `buddyctl flicker` 在非 demo 的模式（`--mode busy6` / `crowd12`，会话在启动时就在）的开头几帧会报「检查 2」：显示器开机的抖动渐变刚过渡到打字内容那一帧有约 10–12 个孤立像素 A→B→A（33 ms）
- 现象：`flicker --scene office --zoom 3 --mode busy6 --from 0 --to 3` → 第 6 帧 12 个；`crowd12` → 第 30 帧 10 个；与时钟无关，`idle6` / tank / strip 干净。约 10 个美术像素、超过容忍度 6，肉眼几乎看不出。完整回归的闪烁扫描只跑 demo 模式，所以没暴露。
- 根因：300 ms 显示器开机渐变（Bayer 抖动）交界的那一帧。
- 修法：不修（和严格模式下已知的那 13 处同一性质（1–5 个孤立像素，肉眼看不出）；改渐变会动金图。）
- 回归测试：无。
- 状态：不修（和严格模式下已知的那 13 处同一性质（1–5 个孤立像素，肉眼看不出）；改渐变会动金图。）

### R4b-P3-02 [P3] R3 新加的三条测试会让 3–4 个线程空转很久
- 现象：`OpenAuditTests` / `FuzzSecurityTests` 的噪声线程、SAN-01 的 4 个 `draw` 空转；SAN-01 和 `TextAuditRunner` 矩阵（长时间持有 `renderLock`）同时跑时被挡 21–29 s，这段时间 4 个核在空转，会加重忙机器下的 R4b-01。
- 根因：没有 sleep / yield。
- 修法：已经顺手改了：噪声线程每次之间睡 0.5 ms，SAN-01 的 worker 每次 `sched_yield()`（仍能在 ASan / TSan 下抓到竞争）。
- 回归测试：随 R4b-01 / SAN-01 / SAN-02 的测试一起。
- 状态：已修（顺手）

### R4b-P3-03 [P3] `TextRenderer.image` 并发同一个 key 时，两个线程同时未命中会各渲染一次、`order` 里重复入队；淘汰时会把还有一个副本在队列里的 key 提前从缓存里删掉
- 现象：只影响命中率，不影响正确性（`<= 600` 的上界仍成立）。
- 根因：未命中到入缓存之间没有占位。
- 修法：不修（只影响命中率。）
- 回归测试：无。
- 状态：不修（只影响命中率。）

### R4b-P3-04 [P3] `fuzzRun("flush inside onChange", timeout: 20)` 外层超时比里层 `waitUntilIdle(timeout: 60)` 短
- 现象：并入 R4b-01 的修法（放宽到 90 秒）。
- 根因：外层没跟着里层改。
- 修法：已随 R4b-01 一起改了。
- 回归测试：随 R4b-01 / SAN-01 / SAN-02 的测试一起。
- 状态：已修（顺手）

### R4b-P3-05 [P3] `openAudit_scopeKeepsConcurrentOpensOfOtherTestsOut` 的「不设范围的会被记进来」断言依赖噪声线程在 0.3 s 窗口内被调度到；忙机器上可能落空
- 现象：没见到失败。
- 根因：没有等噪声线程真的 open 过。
- 修法：已经顺手改了：审计开始前先等噪声线程至少 open 过一次。
- 回归测试：随 R4b-01 / SAN-01 / SAN-02 的测试一起。
- 状态：已修（顺手）

### R5a-01 [P2] 出错提醒漏了两道闸：「桌面 App 里的会话也提醒」关着时桌面会话出错仍会提醒；你正在看那个会话时出错也照样提醒
- 现象：最后一轮复查 R5a：打开「出错时也提醒」、关掉「桌面 App 里的会话也提醒」后，桌面会话出错仍然弹提示卡、发系统通知、响提示音；你正在看那个会话时也一样（等待类和做完了都不会）。`使用说明.txt` 第 119 行让用户关掉这个开关来避免和 Claude.app 自己的通知重复，第 88 行写了「你正在看那个会话时不提醒」。复查员的随机模拟（250 个种子 × 3000 步、24 484 条提醒）里有 401 条是桌面会话在 `includeDesktop` 关着时发出的出错提醒。
- 根因：`AlertCoordinator.observe` 的 `.errored` 分支只检查 `config.error` 和节流，没有等待类（`handleWaiting`）和做完了（`handleFinished`）都有的 `includeDesktop` 与 `isLooking` 两道闸；`desktopSessionsAreSkippedWhenIncludeDesktopIsOff` 只覆盖了等待类和做完了，`errorAlertsAreOffByDefaultAndThrottledWhenOn` 只测了终端会话。
- 修法：`.errored` 分支补两个条件：`s.origin != .desktop || config.includeDesktop`、`!(config.suppressWhenFocused && isLooking(s))`（节流仍放在最后）。
- 回归测试：`ReviewRegressionAppTests/r5a01_errorAlertsRespectTheDesktopAndLookingGates`（桌面 + includeDesktop 关 / 你在看 / 桌面且在看 → 0 条；终端没人看 / 桌面开着没在看 / 「正在看时不提醒」关着 → 1 条）。
- 修复前失败：撤销两道闸后这条测试红：`ReviewRegressionAppTests.swift:355:9 / :356:9 / :357:9 Expectation failed: (errorPosts(…) → 1) == 0`（3 个 issue，`QA/evidence/r3/fail-before-r5.txt`）。修复后通过。
- 状态：已修。

### R5a-P3-01 [P3] 排队等待中的「做完了」（最长 8 秒）不再读设置，用户在窗口里关掉提醒或 `includeDesktop` 后仍会发出一条
- 现象：`finished[s.key]` 记着的待发提醒在等待期间不再核对当前的 `config`。
- 根因：待发记录只在入队时按当时的设置判断。
- 修法：不修（极窄（8 秒窗口内改设置），后果只是多一条提醒。）
- 回归测试：无。
- 状态：不修（极窄（8 秒窗口内改设置），后果只是多一条提醒。）

### R5a-P3-02 [P3] 应用层 `DesktopMeta.lastFocused` 接受布尔、0、负数、1999 年的值，引擎读取器拒绝
- 现象：真实的 43 个桌面会话文件里没有这类值，不可达。
- 根因：应用层的解析比引擎读取器松。
- 修法：不修（不可达；R4a-01 只补了未来值。）
- 回归测试：无。
- 状态：不修（不可达；R4a-01 只补了未来值。）

### R5a-P3-03 [P3] `hook-merge.py` 遇到嵌套很深的 JSON 时抛未捕获的 `RecursionError`，退出码 1
- 现象：文件没动，也没有留备份。
- 根因：没有限制嵌套深度。
- 修法：不修（真实的 settings.json 不会嵌套几百层。）
- 回归测试：无。
- 状态：不修（真实的 settings.json 不会嵌套几百层。）

### R5a-P3-04 [P3] 隐私模式打开前已经出现的提示卡和已送达的系统通知不会被撤
- 现象：隐私模式只影响之后生成的文字。
- 根因：没有在开关切换时清理已显示的提示卡。
- 修法：不修（提示卡 6 秒后自己收；系统通知留在通知中心。）
- 回归测试：无。
- 状态：不修（提示卡 6 秒后自己收；系统通知留在通知中心。）

### R5a-P3-05 [P3] 合并卡的人数还会把刚被隐藏的会话算进去（R4a-P3-02 的子情形）
- 现象：2 秒窗口里的人不管现在还在不在场 / 是否被隐藏都算。
- 根因：`recent` 只按时间窗口数人。
- 修法：不修（极窄，数字偏大。）
- 回归测试：无。
- 状态：不修（极窄，数字偏大。）

### R5a-P3-06 [P3] `strip.align` 遇到认不出的值时，位置和场景对齐方向不一致
- 现象：只有手改偏好设置才会触发。
- 根因：没有校验设置值。
- 修法：不修（手改偏好设置才触发。）
- 回归测试：无。
- 状态：不修（手改偏好设置才触发。）

### R5b-01 [P2] （测试基础设施）`noFileDescriptorLeaksAcrossReaders` 睡 0.3 秒就断言 fd 涨幅 ≤ 150，而 FSEvents 流停掉后的 fd 是异步释放的，机器一忙就间歇性变红（单独跑这一条也红）
- 现象：最后一轮复查 R5b：`FileIO` 相关组合连跑 40 遍红 1 遍（`文件描述符从 4 涨到了 442`），这一条单独连跑 25 遍（load 32–57）红 1 遍（`从 3 涨到了 185`）。红的地方写着 fd 在涨，看起来像句柄泄漏，会误导排查；只会误报红。
- 根因：测试自己起停 40 个 `FSEventStream`，每个停掉时还占约 10 个 fd，由系统在后台异步关掉（复查员的独立探针：6 遍里 1 遍 0.3 秒后仍有 381 个，1 秒后全部回到 0）；断言前只等了固定的 0.3 秒。不是泄漏。
- 修法：改成轮询等 fd 数回落到 `before + 150` 以内（最多 15 秒）再断言；阈值 150 不变（真泄漏是几千个，回落不了）。
- 回归测试：就是这条测试本身（修的是它的等待方式）。
- 修复前失败：复查员的原始失败输出见 `QA/review-R5b.md`（`FuzzSecurityTests.swift:202:9: Expectation failed: (after - before → 438) <= 150`）；时序问题，我没有另外复现。
- 状态：已修（修复前失败的证据是复查员的测量）。

### R5b-P3-01 [P3] `theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms` 里 `onHover` 和取 `t0` 是相邻两句，测试线程恰好在两句之间被挂起 ≥ 250 ms 时保护会失效
- 现象：窗口极窄，没见到失败。
- 根因：先悬停、后取时间。
- 修法：先取 `t0` 再悬停（已顺手改了）。
- 回归测试：这条测试本身。
- 状态：已修（顺手）

### R1a-P3-02 [P3] hook-merge.py 的备份 / 临时文件先按默认 umask（0644）创建、写完内容再 chmod
- 现象：`~/.claude` 是 0755，备份 / 临时文件在创建到 chmod 之间有一个极短的窗口，同机其他用户能读到 settings.json 的内容（可能带 env 密钥）。
- 根因：`backup()` / `write_atomic()` 用 `open()`（默认 0666 & ~umask）创建后才 `os.chmod`。
- 修法：新增 `create_private(path, mode, how)`：`os.open(..., O_EXCL, mode)` 直接按原文件的权限创建（不跟随已有的文件 / 链接），之后仍 `chmod` 一次。
- 回归测试：`Tests/hook_merge_test.py: test_backup_and_temp_files_are_created_private_without_relying_on_chmod`（把 `os.chmod` 换成空操作：替换后的 settings.json 和备份都必须仍是 0600）。
- 修复前失败：`AssertionError: 420 != 384 : 替换之后的 settings.json 应该还是 0600（临时文件创建时就是 0600）`（0644 ≠ 0600）。修复后 `Ran 16 tests … OK`。
- 状态：已修。

### R1a-P3-05 [P3] `scripts/build-app.sh`：`swift build … | tail -4` 在 `set -e` 下没有 pipefail，编译失败被吞掉
- 现象：有旧的 `.build/release/BuddyOffice` 时，编译失败也会把旧版本打包、`安装.command` 把旧版本装上去（而且用户以为装的是新版）。
- 根因：管道的退出码是 `tail` 的，不是 `swift build` 的。
- 修法：`set -eo pipefail`。（这次重装另外由 `QA/tools/verify_install.sh` 检查「没有比装好的可执行文件更新的源码」。）
- 回归测试：shell 脚本，没有单元测试；`bash -n` 通过，并且这次真的用它编译、打包、安装了一遍（`QA/evidence/install/`）。
- 修复前失败：无自动化的「修复前失败」（脚本级）：复查员用「有旧二进制时故意让编译失败」复现；这里改动是一行 `set -o pipefail`。
- 状态：已修。

### R1a-P3-06 [P3] `安装.command`：`rm -rf "$DEST"` 之后 `mv "$STAGE" "$DEST"` 失败就没有 App 了（没有回滚）
- 现象：磁盘满 / 权限出错时，用户原来能用的 App 也没了。
- 根因：先删旧的、再移新的，两步之间没有保护。
- 修法：先把旧版本移到 `~/Applications/.Buddy 办公室.old.app`，新版本移进去失败就把旧版本放回去并报错，成功才删旧的。
- 回归测试：shell 脚本，没有单元测试；`bash -n` 通过，这次的真实安装走了「旧版本移开 → 新版本放进去 → 删旧的」这条成功路径。
- 修复前失败：无自动化的「修复前失败」（脚本级）；回滚分支只做了代码审查（`mv` 失败的分支很难在真机上造出来）。
- 状态：已修。

### R2-006 [P3] 隐私模式没盖住设置页「数据源诊断」和「测试深链」回执里的会话标题
- 现象：隐私模式就是为了录屏 / 共享屏幕，那时打开设置页的诊断页会露出会话标题（菜单栏菜单、右键菜单、提示卡、悬停卡都已经走了隐私处理，只有这两处漏了）。
- 根因：`DiagnosticsFormatter.text` 逐行写 `s.title`；`AppModel.testDeepLink` 的回执里写 `s.title`。
- 修法：`DiagnosticsFormatter.text(…, privacy:)`（默认 false，老调用方不受影响）、`AppModel.deepLinkReceipt(title:privacy:)`：隐私模式下写「会话」。
- 回归测试：`ReviewRegressionAppTests/r2006_privacyModeHidesSessionTitlesInTheDiagnosticsAndTheDeepLinkReceipt`。
- 修复前失败：`Expectation failed: (!hidden.contains("秘密账号") → false) && (hidden.contains("· 会话　pid 42") …)`。修复后通过。
- 状态：已修。

### R2-007 [P3] 测试宿主进程里 `DebugTools.enabled` 恒为真（`--test-bundle-path` 匹配了 `--test-` 前缀）
- 现象：现在没有测试因此写日志，是潜在陷阱：以后谁在被测代码路径里加一行 `DebugTools.log`，测试就会往用户真实的 `~/Library/Logs/BuddyOffice/debug.log` 里写。
- 根因：`devFlagsPresent` 用前缀匹配，而 Swift Testing 宿主进程 `swiftpm-testing-helper` 自己的参数里有 `--test-bundle-path`。
- 修法：`--test-bundle-path` 不算开发开关（其余 `--test-*` / `--dump-*` 照旧）。
- 回归测试：`ReviewRegressionAppTests/r2007_theTestHostsOwnArgumentsAreNotDevelopmentFlags`（测试进程里 `DebugTools.enabled == false`，14 个真正的开发开关仍然有效）。
- 修复前失败：`Expectation failed: !(DebugTools.enabled → true …)`。修复后通过。
- 状态：已修。

### R2-008 [P3] `DesktopMeta` 不认 `--data-root`：用假 home 起的开发副本仍读真实的桌面会话元数据
- 现象：QA / 长跑 / 自检都靠 `--data-root` 隔离真实数据，但应用层「点击跳转前后读 lastFocusedAt」「提醒判定里的 isMostRecentlyFocused」仍读**真实**的桌面会话元数据（只读 `lastFocusedAt`，不违反红线，但违反「假 home 整体替换」的约定）。
- 根因：`DesktopMeta.base` 用 `NSHomeDirectory()`，和 BuddyCore 的 `Paths.desktopSessionsDir`（跟着 `--data-root` 走）不是同一个来源。
- 修法：`RealProvider.make` 收到 `--data-root` 时把 `DesktopMeta.baseOverride` 设成 `Paths(home:).desktopSessionsDir`。
- 回归测试：`ReviewRegressionAppTests/r2008_theDataRootArgumentAlsoMovesTheDesktopMetaBase`。
- 修复前失败：`Expectation failed: (DesktopMeta.baseOverride → nil) == "/x/fake-home/Library/Application Support/Claude/claude-code-sessions"`。修复后通过。
- 状态：已修。

### R2-013 [P3] `scripts/measure.sh`、`scripts/soak.sh` 用 `pkill -f "$APP/Contents/MacOS"` 按路径子串杀进程
- 现象：并行跑多个 QA 时会误杀别人用同一个路径起的开发副本；`BUDDY_APP` 指到装好的 App 时会杀掉用户的 App。
- 根因：开发脚本按路径子串 `pkill`。
- 修法：已经有同路径的副本在跑就退出并说明（别人的进程不杀）；只记下并关掉自己起的那个 pid（`QA/tools/run_soaks.sh` 本来就是这样）。
- 回归测试：shell 脚本，没有单元测试；`bash -n` 通过。
- 修复前失败：无自动化的「修复前失败」（开发脚本）。
- 状态：已修。

### R2-014 [P3] 系统时钟往回拨时，提醒的去抖 / 节流把提醒压住
- 现象：时钟被拨回 N 秒（手动改时间 / 休眠唤醒后 NTP 校正）：`lastAlert` 里的记录一直「没过期」，N 秒内这个 buddy 的这一类提醒发不出来。复查员实测：拨回之后的第一条提醒出现在 t=1022（期望 ≈101.5，压了约 15 分钟）。
- 根因：`AlertCoordinator` 的去抖 / 节流全用墙钟差，没有处理「负的差」。
- 修法：节流记录里「来自未来」的时间（差 < 0）当作已过期；等待段的 `since` 在未来时重新计时。
- 回归测试：`ReviewRegressionAppTests/r2014_aClockThatWentBackwardsDoesNotSuppressAlerts`。
- 修复前失败：`Expectation failed: (posts.count → 1) == 2`（拨回之后那段等待没有提醒）。修复后通过。
- 状态：已修。

### R2-015 [P3] （A-019 的遗留）工具详情为空时桌牌 / 菜单栏文案出现「在读 」「在找 ""」「运行 」这种半截话
- 现象：hook 行被截断（工具详情最多 160 字，截在多字节字符中间时 JSON 解析失败，走降级解析、`detail` 为空）时，桌牌、悬停卡、菜单栏菜单显示「在读 」「在找 ""」「在搜 ""」……；`在找 ""` 是看得见的怪字。前几轮记为「转交协调者、未修」，复查员确认还没修。
- 根因：`PlateCopy.toolText` 直接拼 `"在读 " + fileName(detail)`，没有处理空 detail。
- 修法：每个类别在 detail 为空（或只有空白）时退回无细节的说法：「在读文件」「在找东西」「在改代码」「在写文件」「在运行命令」「在搜索」「在看网页」；「运行中 <命令> · 用时」里命令为空就省掉命令。
- 回归测试：`ReviewRegressionStageTests/r2015_emptyToolDetailsFallBackToGenericCopy`。
- 修复前失败：`Expectation failed: (!t.hasSuffix(" ") → false) && (!t.contains("\"\"") …)`（如「在读 」「在找 ""」，18 个 issue）。修复后通过。
- 状态：已修。

### R2-016 [P3] 拖窗口边缘时办公室 `PixelView` 每一步都新建 3 块 IOSurface（复查员评 P2「未定论」：测试宿主里占用 57 → 261 MB 不回落；真实 App 里复测没有复现保留，降为 P3）
- 现象：复查员的报告：测试宿主进程里（可见窗口 + 真实合成，`OfficeWindowController` 随机尺寸 300 次）物理占用 57 → 261 MB，6 秒后 / `orderOut` 之后都不回落（IOSurface 294 MB / 465 个区域）；真实开发副本里 22 → 43–44 MB，一次 60 秒内回落、一次 2 分钟没回落。触发方式：拖窗口边缘时（窗口的 `contentResizeIncrements` = 缩放倍数，每 1 个缩放单位一步）视口每一步都变，`nextSurface` 每步都新建一组 3 块（60 Hz 拖动 ≈ 每秒 180 个 IOSurface 内核对象）。
- 根因：surface 按视口的精确宽高分配，视口一变就整组重建。
- 修法：surface 的宽高向上取整到 64 像素的倍数（「桶」），只在跨桶时才重建，用 `contentsRect`（= 视口 / surface）裁出视口那一块；图层大小仍是 视口 × 缩放。
- 复测（我自己的，新增开发开关 `BuddyOffice --test-resize`，脚本和原始数据在 `QA/tools/resize/`、`QA/evidence/resize/`）：真实 App（开发副本、可见窗口）里 A（修复前）/ B（现在交付的）/ C（B + 「够用就不重建」）三个版本交替各跑 2 次（每次 5 轮 × 300 步小步来回扫，做完后**先把窗口还原成原尺寸**再量）：新建 IOSurface 组 A ≈ 690–710、B ≈ 72–78、C ≈ 41–47（B 降到约 1/10）；尺寸还原 30 秒后占用比基线 A +5.9 / +5.0、B +5.8 / +7.1、C +7.1 / +7.5 MB，不改尺寸的对照组自己 +3.3 MB —— 差别在噪声里，和新建组数无关；`footprint` 分类里 IOSurface 始终只有 1.7–2.9 MB（4–7 个区域），没有堆积；拖动期间占用涨到 35–50 MB（偶尔某一轮 70 MB）是窗口变大后的工作集（Malloc / CG Raster Data），尺寸还原后回落。复查员在开发副本里看到的「+21 MB 不回落」，和我没还原尺寸时量到的 +17～20 MB 一致——窗口最后停在了更大的尺寸上，不是保留。结论：「CoreAnimation 长期保留用过的 surface」只在测试宿主进程里出现（那不是真正的 GUI App，没人消费 CA 的提交队列），真实 App 里没有。
- 回归测试：`ReviewRegressionAppTests/r2016_resizingDoesNotAllocateANewSurfaceSetForEverySmallStep`（100 步宽度每步 +1：用过的不同 IOSurface ≤ 6 块）、`r2016_theShownPartOfABucketedSurfaceIsExactlyTheViewport`（contentsRect / 图层尺寸 / 左上角与右下角像素；同一个桶里视口变了 surface 不重建）、`r2016_aBucketedSurfaceRendersPixelIdenticallyToTheScaledCanvas`（把图层渲染成位图，每个 z×z 方块的中心像素都等于画布像素；对 contentsRect 的两个变异——整张 surface / 偏一个像素——都会红）。
- 修复前失败：见 `QA/evidence/fail-before-review.md`「R2-016 / R2-017」一节：`(seen.count <= 6 → false)`、`Int(sw) % 64 == 0 → false`、同一个桶里视口变了 surface 尺寸也变了、contentsRect 不对（共 6 个 issue）。
- 状态：已修（作为降开销 / 防万一的改动：新建次数降到约 1/10；真实的内存保留没有复现，见「复测」）。

### R2-017 [P3] 办公室窗口（普通 `NSWindow`）没关 `animationBehavior`：快速 show / hide 时窗口动画线程一路涨（B-010 的同类）
- 现象：复查员在测试宿主里用真实的 `AppModel.showOffice(persist: false)` + `orderOut`（每轮间隔 4 ms）反复 300 轮：只开小鱼缸 / 只开宠物条时线程数 7 → 7（平），只开办公室窗口时 24 → 70；把办公室窗口设成 `animationBehavior = .none` 之后再来 300 轮：70 → 70（不再涨）。真实使用里触发频率低（要在窗口出现 / 消失动画还没播完时又 order 一次：热键连按、`expandToOffice()` 之后 50 ms 里 `applySettings` 又 `showOffice` 一次）。
- 根因：B-010 只给 `FloatingPanel` 设了 `animationBehavior = .none`；办公室窗口是普通 `NSWindow`，创建时没有设。AppKit 的出现 / 消失动画在工作线程上跑 `NSAnimation`，动画没播完又被打断时线程不回收。
- 修法：`OfficeWindowController.init` 里 `w.animationBehavior = .none`（设置窗口只在用户点开时才 show，不受影响）。
- 回归测试：`ReviewRegressionAppTests/r2017_theOfficeWindowHasWindowAnimationsTurnedOff`（`OfficeWindowController().window!.animationBehavior == NSWindow.AnimationBehavior.none`；和 `PanelAnimationTests` 对 `FloatingPanel` 的检查是一对）。
- 修复前失败：见 `QA/evidence/fail-before-review.md`「R2-016 / R2-017」一节（撤销这一行之后测试红，`animationBehavior` 是 `.default`）。
- 状态：已修（线程数随 show / hide 增长的真实症状只在测试宿主里量过，见 REPORT 第 7 节）。

### R1a-P3-01 [P3] hook-merge.py 整体重写会规范化用户的 JSON 排版（缩进 2 空格、CRLF→LF；键顺序保留）
- 现象：用户自己排版的 settings.json 改完之后缩进变了。
- 根因：`json.dump(indent=2)`。
- 修法：内容语义不变、键顺序保留、有备份；要保留原排版得自己写一个保持格式的 JSON 编辑器，收益太小（P3）。
- 回归测试：无。
- 状态：不修（内容语义不变、键顺序保留、有备份；要保留原排版得自己写一个保持格式的 JSON 编辑器，收益太小（P3）。）

### R1a-P3-03 [P3] `hook-merge.py --settings` 是最后一个参数时 `IndexError` 回溯
- 现象：只有测试用开关，写错命令行时给出回溯而不是一句用法。
- 根因：`args[i + 1]` 没判断越界。
- 修法：仅测试用开关，不影响安装 / 卸载（P3）。
- 回归测试：无。
- 状态：不修（仅测试用开关，不影响安装 / 卸载（P3）。）

### R1a-P3-04 [P3] `hook-merge.py` 遇到带 UTF-8 BOM 的 settings.json 会以「不是合法 JSON」拒绝（提示不准）
- 现象：安全（拒绝、什么都没改），但提示说「不是合法 JSON」并不准确。
- 根因：`json.loads` 不吃 BOM。
- 修法：拒绝的行为是安全的，Claude Code 自己写的 settings.json 没有 BOM（P3）。
- 回归测试：无。
- 状态：不修（拒绝的行为是安全的，Claude Code 自己写的 settings.json 没有 BOM（P3）。）

### R1a-P3-07 [P3] `TokenLedger.writeLedger`：仍被跟踪但还没扫完的文件（启动后立刻退出）的旧断点会被丢掉；持锁时对每个旧断点 `stat` 一次
- 现象：下次启动重扫，只是慢一点；几千个断点时 `totals()` 会被挡几十毫秒。
- 根因：`files[k] == nil` 条件 + 持锁 stat。
- 修法：只影响冷启动重扫的时间，账本不会错（P3）。
- 回归测试：无。
- 状态：不修（只影响冷启动重扫的时间，账本不会错（P3）。）

### R1a-P3-08 [P3] `FileWatcher.start()`：`~/.claude` 启动时不存在（Claude Code 还没装）则 FSEvents 起不来，整个运行期停在 50–100 ms 轮询
- 现象：没装 Claude Code 时 App 没有会话可看；装了之后要重启 App 才会切回 FSEvents。
- 根因：启动时一次性判断。
- 修法：没装 Claude Code 时这个 App 没有意义；轮询本身正确（P3）。
- 回归测试：无。
- 状态：不修（没装 Claude Code 时这个 App 没有意义；轮询本身正确（P3）。）

### R1a-P3-09 [P3] `SessionEngine.bootstrapDormants`：首次 poll 时登记表恰好读不出来，会把实际在跑的桌面会话先当成下班工位，再「走回来」
- 现象：只影响启动瞬间的观感。
- 根因：首次 poll 的一次性判断。
- 修法：极窄的时间窗（登记表半截文件），后果只是一次多余的走路动画（P3）。
- 回归测试：无。
- 状态：不修（极窄的时间窗（登记表半截文件），后果只是一次多余的走路动画（P3）。）

### R1a-P3-10 [P3] `ProcessProbe`：僵尸进程被当成活的
- 现象：已经退出但还没被父进程回收的会话进程，登记表没清时会多显示一位「在场」的同事，直到回收。
- 根因：`kill(pid, 0)` 对僵尸进程成功。
- 修法：僵尸进程很快被回收，登记表里的记录也会被 Claude Code 清掉（P3）。
- 回归测试：无。
- 状态：不修（僵尸进程很快被回收，登记表里的记录也会被 Claude Code 清掉（P3）。）

### R1a-P3-12 [P3] `hook-merge.py`：用户特意设成只读（0444）的 settings.json 也会被替换（模式保持 0444）
- 现象：绕过了「只读保护」的意图（目录可写就能 `os.replace`）。
- 根因：原子替换的语义。
- 修法：写 settings.json 是用户明确要求的安装动作；模式保持 0444、有备份（P3）。
- 回归测试：无。
- 状态：不修（写 settings.json 是用户明确要求的安装动作；模式保持 0444、有备份（P3）。）

### R1b-P3-01 [P3] 对负的 `time` 不设防（`PoseLibrary.frame(.writingPad, t < -0.134)` 下标越界、`RoomRenderer.plantPhase(time < 0)`）
- 现象：已用 exit test 复现会崩。
- 根因：App 里 `time = CACurrentMediaTime() − t0` 单调且渲染晚于 update，不可达。
- 修法：不可达（P3）；真要防再加 `max(0, t)`。
- 回归测试：无。
- 状态：不修（不可达（P3）；真要防再加 `max(0, t)`。）

### R1b-P3-02 [P3] `OfficeScene` 里 `walkers.cleanup` 在 `finishedEntering` 之前，进场走完后只有 50 ms 的窗口能记下坐下时刻
- 现象：帧间隔 > 50 ms（12 fps 以下）会丢掉「坐下后显示器 300 ms 开机」（`dt = 0.08` 时丢、≤ 0.06 时不丢）。
- 根因：走路期间节拍是 30 fps，只在主线程卡顿时发生。
- 修法：纯观感，只在主线程严重卡顿时发生（P3）。
- 回归测试：无。
- 状态：不修（纯观感，只在主线程严重卡顿时发生（P3）。）

### R1b-P3-03 [P3] `Canvas.cropped(rect)` 在 rect 和画布不相交时返回 1×1 的左上角像素（A-009 修了 `writeBGRA`，同类的没跟着改）
- 现象：`blitCanvas(srcRect: 画布外)` 会画出 1 个像素；`makeCGImage(crop: 画布外)` 退化成整张画布。
- 根因：当前没有调用点用 `srcRect`，`vp` 也总在画布内，不可达。
- 修法：不可达（P3）。
- 回归测试：无。
- 状态：不修（不可达（P3）。）

### R1b-P3-04 [P3] 开发用 CLI 两处会 trap：`buddyctl snapshot --cells 0`、`buddyctl cell --cloth 99 / -1`
- 现象：只有手敲非法参数才会崩，不影响 App。
- 根因：`max(1, frames.count / maxCells)` 除零；`Pal.clothRamps[…]` 下标越界。
- 修法：开发命令行的非法参数（和 A-029 同类，P3）。
- 回归测试：无。
- 状态：不修（开发命令行的非法参数（和 A-029 同类，P3）。）

### R1b-P3-05 [P3] 泰文 / 藏文 / Zalgo 这类叠字符号的标题，符号被文字图片上边缘裁掉一截
- 现象：不会溢出到别的元素上，只是有点被切。
- 根因：图片高度按苹方的 ascent / descent 定，回退字体更高。
- 修法：极少见的文字，只影响观感（P3）。
- 回归测试：无。
- 状态：不修（极少见的文字，只影响观感（P3）。）

### R1b-P3-06 [P3] `drawMonitor` 开机 / 关机渐变期间每个座位每帧新建一张世界大小的草稿 `Canvas`
- 现象：启动时最多几个座位 × 9 帧，窗口很大时每张几 MB，只影响那 0.3 s 的 CPU / 内存抖动。
- 根因：渐变的实现方式。
- 修法：`buddyctl bench` 实测办公室每帧总共 0.18 ms，可忽略（A-025 同类，P3）。
- 回归测试：无。
- 状态：不修（`buddyctl bench` 实测办公室每帧总共 0.18 ms，可忽略（A-025 同类，P3）。）

### R1b-P3-07 [P3] 气泡像素没有命中 ID：办公室里点气泡没反应、宠物条里鼠标穿过气泡
- 现象：`StripScene` 顶部注释写「鼠标只有碰到 buddy（或气泡）时才被拦下」，代码没有这样做。
- 根因：`drawBubble(…, id:)` 的 `id` 参数根本没用。
- 修法：任务书只要求点小人跳转；顺手把注释和行为对齐留给以后（P3）。
- 回归测试：无。
- 状态：不修（任务书只要求点小人跳转；顺手把注释和行为对齐留给以后（P3）。）

### R1b-P3-10 [P3] 摄像机注释和代码不一致：注释写「滚动到有人要你或最后一行」，代码在没人等你时保持上一个目标
- 现象：世界比视口高（工位很多 + 手动放大倍数，或窗口很矮）时，下面几排的人在他们不等你的时候一直看不到。
- 根因：自动缩放在 Retina 上可以降到 1 倍，正常场景放得下，只在极端情况出现。
- 修法：请设计者确认是不是有意的（P3）。
- 回归测试：无。
- 状态：不修（请设计者确认是不是有意的（P3）。）

### R2-009 [P3] 入口兜底只在「设置变了」时重算（A-024 的残留）
- 现象：纯宠物条用法：会话都走了之后宠物条变成一块点穿的空白、没有任何入口，直到下一次设置写入或重启；反过来，一次恰好在没人时发生的设置写入会补上 Dock 图标并把 `ui.dockIcon` 永久写成 true。
- 根因：`applySettings` 只由 `UserDefaults.didChangeNotification` 触发。
- 修法：极窄的用法（办公室 / 小鱼缸 / 菜单栏 / Dock 全关，只开宠物条）；改动要动设置写回的语义，风险大于收益（P3）。
- 回归测试：无。
- 状态：不修（极窄的用法（办公室 / 小鱼缸 / 菜单栏 / Dock 全关，只开宠物条）；改动要动设置写回的语义，风险大于收益（P3）。）

### R2-010 [P3] 宠物条 3 倍 + ≥ 9 人时比 1408 pt 宽的屏幕还宽（origin.x = -16），最左边的人被挤出屏幕
- 现象：量过；只在放大 3 倍且同时 ≥ 9 个会话时出现。
- 根因：宠物条按人数线性变宽，没有按屏幕夹。
- 修法：极端组合，可以把缩放调小或减少会话（P3）。
- 回归测试：无。
- 状态：不修（极端组合，可以把缩放调小或减少会话（P3）。）

### R2-011 [P3] `setDemo` 不清旧数据源的 `onUpdate`，切换那一刻排在主队列里的尾巴回调会写进新状态
- 现象：可能，概率低。
- 根因：旧 `SessionStore` 的回调闭包 `[weak self]`，但已经排队的块还会执行。
- 修法：可能但概率很低，后果只是切换瞬间多一帧旧快照（P3）。
- 回归测试：无。
- 状态：不修（可能但概率很低，后果只是切换瞬间多一帧旧快照（P3）。）

### R2-012 [P3] 主菜单没有 ⌘W / ⌘H / 编辑菜单
- 现象：办公室窗口里按 ⌘W 什么都不发生；⌘H 隐藏 App 没有入口；诊断页文字选中后 ⌘C 可能复制不了（未验证）。
- 根因：`buildMenu` 只做了「设置…」「退出」「办公室」「最小化」。
- 修法：红色关闭按钮可用，退出有 ⌘Q；补标准菜单是 UI 增强（P3）。
- 回归测试：无。
- 状态：不修（红色关闭按钮可用，退出有 ⌘Q；补标准菜单是 UI 增强（P3）。）
