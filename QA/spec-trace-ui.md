# UI 规格追踪（任务书 6.5 / 6.6 / 7.1–7.5）

> 范围：`~/Desktop/Buddy办公室-开发提示词.md` 的 6.5（状态 → 动画表 + 两条附注）、6.6（与 6.5 相关的数字）、7.1 三种形态 + 菜单栏 + Dock、7.2 提醒、7.3 点 buddy 跳到会话、7.4 跟着 Claude 开 / 收、7.5 设置与诊断。
> 方法：逐条读代码 → 能出图的用 `.build/release/buddyctl` 出图亲眼看 → 有单元测试的对到测试名 → 只能读代码的如实标「无专门测试」。全程只读：没改任何源码 / 测试文件，没编译，没运行 App，没碰 `~/.claude`。
> 时间与版本：追踪时间 2026-09-29 02:50–03:45（PDT）。**`.build/release/buddyctl` 是 02:32 编的**；02:54 之后别的工位在改 `BuddyStage/OfficeScene / HoverCard / TankScene / StripScene / PlateCopy / PixelFont / OfficeLayout` 和 `BuddyOffice/OfficeWindowController / PixelView`（文本审计 / 布局相关），所以下面「看图」的结论对应 02:32 的二进制，行号取自我最后一次读到的源码，**以函数名为准，行号可能漂移**。
> **BuddyOffice 没有测试目标**（`Package.swift` 只有 `BuddyCoreTests` 和 `BuddyStageTests`）：7.1–7.5 里凡是 AppKit 层的逻辑（窗口 / 面板 / 提醒判定 / 跳转 / 自动收起 / 设置接线）都没有单元测试，证据只能是读代码、`--test-*` 启动参数的记录（`DESIGN.md` 第 8、9 节）和我读到的 `/tmp/buddy-office-debug.log`。

**结论摘要**：共 267 条——✓ 134、✓(无专门测试) 101、偏离（已记录）7、偏离-未记录 15、缺失 8、N/A 2。6.5 表本身（116 条）做得很扎实：96 条有测试或我亲眼确认，问题集中在 4 处「动作没做 / 画错」（S15b 首字母画成「?」、S22a2 / S26a2 两个动作缺失、S29b2 关机渐变缺失）。7.x 的 AppKit 层（`BuddyOffice`）**没有测试目标**：U / N / J / F / C 共 127 条里有 83 条只能标「无专门测试」（其余靠 BuddyStage / BuddyCore 的测试、`hook_merge_test.py` 或我看图 / 读日志）；其中 3 个设置项（空闲 / 睡着 / 下班工位保留时间）设置页有、行为没接（C09 / C10 / C11），宠物条的 Dock 跟随、改设置即时生效、指定屏幕都不完整（U28 / C06b / U26c）。另有 1 个需要真机点一下确认的高风险疑点：小鱼缸的点击 / 双击可能被「按住背景拖动」吞掉（疑点 1）。详见第 8–10 节。

## 0. 图例与证据索引

**状态**（只有这六种）：`✓` 实现了且有测试 / 我亲眼确认的证据；`✓(无专门测试)` 实现了，只有读代码 + 间接证据；`偏离`（后面写 DESIGN.md 里记录理由的位置）；`偏离-未记录`（和任务书不同，DESIGN.md 里找不到理由）；`缺失`（任务书要求但没做，或做了但设置 / 数据没接上）；`N/A`（任务书自己说了可选 / 不适用）。

**编号**：`S<行号><a身体 b屏幕 c道具·气泡 d桌牌>` = 6.5 表的第几行的哪一列；`S30/S31` = 表后两条附注；`M` = 6.6；`U` = 7.1；`N` = 7.2；`J` = 7.3；`F` = 7.4；`C` = 7.5。

**看图索引**（都是 `buddyctl snapshot --scene office … --clock 12:00 --w 224 --h 300 --scale 1`，`--crop` 用世界坐标：座位 s 的格子原点 = (28 + (s%3)×56, 60 + (s/3)×74)，裁 (ox−2, oy−2, 60, 78)（这是 02:32 二进制的几何；当前源码里桌牌带已被别的工位从 10 px 改成 12 px，行距变 76，所以现在复现要把 74 换成 76）；demo 剧本时间轴见 `Sources/BuddyStage/DemoScript.swift`）。**必须用 15 fps 以上取样**（`--fps 15`）：`Performer` 的最短停留 / 转身状态机按调用间隔推进，稀疏取样（比如 0.5 fps）会看到「刚切换」的假象；`--fps 30` 才看得到走进来的开机（15 fps 会漏掉走路结束的那一帧，屏幕直接亮着）。

| 代号 | 内容 | 命令要点 |
|---|---|---|
| [A] | 座位 0（重构登录模块）t=1…39 每 2 秒一格：思考 / Read / Grep / Glob / Edit / Write / Bash 短→长 | `--from 1 --to 41 --fps 15 --zoom 4 --crop 26,58,60,78 --cells 20 --cols 5` |
| [B] | 座位 0 t=39…77：等批准 / 提问 / 计划待审 / 做完了 / 需要你处理 / 思考 | 同上 `--from 39 --to 79` |
| [C] [D] | 座位 1（论文引用检查）t=1…39 / 39…77：空闲 / WebFetch / WebSearch / Agent 前台 3 帮手 / Agent 后台 / 整理上下文 / 重试 / 出错 / 思考 / 被打断 / 空闲 | `--crop 82,58,60,78` |
| [E] [F] | 座位 2（健身计划 app）t=1…39 / 39…77：Todo / Skill / ToolSearch / MCP 浏览器 / computer-use / notion / SendUserFile / 闹钟 / Monitor / 做计划 / FooTool / 思考（74 s 起是 > 20 s 的深度思考） | `--crop 138,58,60,78` |
| [G] [H] | 座位 3（DeepSeek）t=1…39 / 41…63：Read / Edit / Bash / 等批准 Edit / Grep / 做完了（未读小旗）/ 空闲 | `--crop 26,132,60,78` |
| [I] | 座位 4（GLM）t=1…75：空闲 → 打盹 → 睡着 | `--crop 82,132,60,78 --from 1 --to 79` |
| [J] | 座位 5 进场：门开一条缝 → 人从门洞走出 → 沿左侧过道走到工位 | `--from 14.93 --to 15.73 --zoom 3 --crop 0,20,72,110`；`--from 14 --to 21 --zoom 2 --crop 0,30,200,190` |
| [K] | 座位 5 坐下 + 显示器开机（**30 fps**，f0177–f0185 = t 19.90–20.17） | `--from 14 --to 20.6 --fps 30 --zoom 4 --crop 138,132,60,78` |
| [L] | 座位 5 离场（起身 → 挥手 → 走向门；屏幕在 t=60.03 一帧变黑） | `--from 58.5 --to 61.5 --fps 30` 同上裁切 |
| [M] | 座位 0 转身序列（30 fps，t 40.36–41.36）与气泡弹出（t 40.03–40.17） | `--from 40.36 --to 41.36 --fps 30 --zoom 3 --crop 26,58,60,78` |
| [N] | 32 种屏幕内容 × 2 个时刻总览（红框 = 头通常挡住的区域） | `buddyctl screens --zoom 8` |
| [O] | 提示卡（toast）7 种 + 悬停卡（demo 各状态） | `buddyctl cards --zoom 2 --scale 2` |
| [P] | 办公室里的悬停卡（座位 0 / 座位 3 = DeepSeek） | `--from 41 --to 41 --hover 0` / `--hover 3` |
| [Q] | 小鱼缸 / 宠物条（6 人，t=41） | `--scene tank`（或 `--scene strip`）`--from 41 --to 41 --zoom 3` |
| [R] | 12 人的小鱼缸 / 宠物条（「+4」）、5 个小助手（「+2」：`c12seat1`，办公室 `--w 336`、裁 60,50,66,90）、座位 7 的「10/10」重试屏幕（`c12retry`）、空办公室 / 空小鱼缸 / 空宠物条 | `--mode crowd12`；`--mode empty` |
| [S] | 标题栏像素按钮精灵（4 种底板 + 3 个图标） | `buddyctl sheet --book chrome --scale 12` |
| [T] | 菜单栏图标三种（**没有 buddyctl 命令**：我用 Python 把 `MenuBarIcon.swift` 里的字符行按同样的调色渲染成 PNG） | 自制 |
| [U] | 放大 8–10 倍的单帧（`--from t --to t --zoom 8`，4 秒预热；单帧只用来看「画成什么样」，节奏用连续取样）：`think3`（座位 0，t=3）、`th65`、`th77`（座位 2，t=65 / 77）、`bash36`（座位 0，t=36）、`mcpapp26`（座位 2，t=26）、`send30`、`alarm34`、`plan44`（t=44.5）、`todo3`（座位 2）、`deleg20`、`deleg23`、`pt16`、`compact37`、`retry43`、`facep48`、`shrug55`（座位 1，t=55.3） | `--zoom 8`/`10` 单帧 |
| [V] | 全员空闲模式（`--mode idle6`）座位 0 的 50 秒：四处看（侧身）、喝水 | `--mode idle6 --from 0 --to 50` |
| [W] | 座位 0 头部 12 倍逐帧：眨眼（t 46.57 半闭 / 46.70 闭 / 46.77 半闭） | `--crop 49,74,16,17 --zoom 12` |
| [X] | 座位 0 键盘区逐帧：Edit（t 16.0–16.8）与 Write（t 21.0–21.8），15 fps | `--from 16.0 --to 16.8 --fps 15 --zoom 10 --crop 38,78,34,16`（Write 把 from / to 换成 21.0 / 21.8） |
| [Y] | 用逐帧图的 md5 判断节拍（不看图，只看「这一帧和上一帧是否不同」；15 / 30 fps，`--zoom 6–8`）：深度思考（座位 2，`--from 75 --to 77 --crop 166,78,20,14`）、重试（座位 1，`--from 42 --to 44 --crop 108,74,20,16`）、Todo（座位 2，`--from 3 --to 5 --crop 160,80,34,14`）、Bash 打字 → 静止（座位 0，`--from 23 --to 32 --crop 38,80,34,10`）、等批准举手（座位 0，`--from 42 --to 46 --fps 30 --crop 60,72,20,22`） | `md5 -q f0000.png …` |

证据图片放在 `/tmp/claude-501/qa-ui/`（会话临时目录，不入库；按上表的命令可以复现；命令里的 `--out` 我都写到了 `$TMPDIR` 下）。

**测试索引**（我没有运行 Swift 测试；`DESIGN.md` 第 9 节记录 269 个测试、25 个套件通过；下面只写名字）：`PF` = `Tests/BuddyStageTests/PerformerTimingTests.swift`；`PC` = `PlateCopyTests.swift`；`RT` = `RenderingTests.swift`；`SP` = `SpriteAndPaletteTests.swift`；`AR` = `Tests/BuddyCoreTests/ActivityResolverTests.swift`；`HM` = `Tests/hook_merge_test.py`（**我跑了：13 个全过**，只用临时目录）。另外我亲自跑了只读的 `buddyctl golden`（17 条全部一致）、`buddyctl flicker`（办公室 1 / 2 / 3 倍、小鱼缸、宠物条，demo 0–79.9 s，各 2398 帧，全部干净，另有 12–15 处 ≤ 6 像素抖动被容忍）和 `--strict`（14 处 1–5 个孤立像素，见疑点）。

**DESIGN.md 里的「偏离」记录位置**（下面「偏离」状态引用它们）：§7「打字节拍 133 ms 一格」；§7「进场 / 离场（走路 + 开门）」；§8「提示音」行；§10「与任务书不一致 / 没做的地方（汇总）」表的各行；§10 已知限制最后一条（Dock 迷你画面）；§11 小决定；§2 M0 第 4 项（深链判据）。

## 1. 任务书 6.5 状态 → 动画（每行 × 四列）

列缩写：a = 身体动作；b = 屏幕（24×15）；c = 道具 / 气泡；d = 桌牌文字。「—」列合并在 S00。文件名都在 `Sources/BuddyStage/` 下：`PoseLibrary.swift`（姿势）、`Performer.swift`（状态 → 姿势 / 屏幕 / 气泡的映射：`targetPose` L102、`targetScreen` L141、`targetBubble` L180）、`ScreenContent.swift`（屏幕）、`SeatRenderer.swift`（气泡 / 道具 / 小旗 / 待机灯）、`PlateCopy.swift`（桌牌文案）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| S01a1 | 6.5 思考·身体 | 略微后靠，手托下巴 | `PoseLibrary.swift:80` `.thinking`（torsoDy 1、headDy 1、右手到 `headSideR`）；`Performer.swift:106` | 看图 [U] think3 / th65：右手举到头的右侧（从背后看＝托腮）、左手在键盘上；「略微后靠」的 1 px 下沉读自代码（静帧看不出） | ✓ |
| S01a2 | 6.5 思考·身体 | > 20 秒后用笔轻敲桌面（≤ 2 Hz） | `PoseLibrary.swift:84` `.thinkingDeep`（右手落到键盘右端，y 每 267 ms 换一格 ＝ 1.875 Hz）；`Performer.swift:106`（el > 20） | 看图 [F]/[U] th77（座位 2，t=77，思考已 23 s）：手落在桌面右侧；没有画笔的精灵。节拍：[Y] 右手区域 15 fps 逐帧哈希，状态每 4 帧（267 ms）换一次、8 帧一轮 = 1.875 Hz ≤ 2 Hz | ✓ |
| S01b | 6.5 思考·屏幕 | IDE 界面，光标静止 | `ScreenContent.swift:115` `.ide`（光标位置固定，颜色 3 阶 0.5 Hz 呼吸 `:108 cursorColor`） | 看图 [N] ide、[A] t=1,3；`RT.staticScreenClassificationMatchesWhatIsActuallyDrawn`（断言 `.ide` 不是静态＝光标在呼吸） | ✓ |
| S01c | 6.5 思考·气泡 | 思考气泡，三个点缓缓升起 | `Performer.swift:183`；`SeatRenderer.swift:170` `thinkDy`、`:310` `drawBubble(.think)`（三点错相位 0.7 Hz，−1/0/1 px） | 看图 [A] t=1,3、[U] think3：三个点高度各不相同 | ✓ |
| S01d | 6.5 思考·桌牌 | 「思考中」 | `PlateCopy.swift:78` | `PC.activityTextForEveryState` | ✓ |
| S02a | 6.5 Read·身体 | 前倾，手放鼠标，头微低 | `PoseLibrary.swift:74` `.mouse`（torsoDy −1、headDy −1、右手在鼠标上）；`Performer.swift:112` | 看图 [A] t=5,7、[G] t=1–5：右手落在鼠标上；「前倾、头微低」的 1 px 位移读自代码（静帧看不出） | ✓ |
| S02b | 6.5 Read·屏幕 | 文档每 150 ms 滚 1 像素；颜色随扩展名 | `ScreenContent.swift:124` `.doc`（`:131` `Int(t/0.15)`；swift 橙／py·sh 绿／js·ts 琥珀／md·txt 白／json·yaml·toml 青／html·css 粉／其余蓝）；扩展名 `PlateCopy.fileExtension` | 看图 [N] doc swift / doc md 两个时刻内容不同；[A] t=5,7 橙色、[G] t=1–5（notes.md）白色；`PC.fileNamesClipsAndDurations`（扩展名小写） | ✓ |
| S02d | 6.5 Read·桌牌 | 「在读 app.swift」 | `PlateCopy.swift:112` | `PC.activityTextForEveryState`（`在读 LoginView.swift`） | ✓ |
| S03a | 6.5 Grep/Glob·身体 | 同上（前倾握鼠标），头轻轻左右扫 | `PoseLibrary.swift:74` `.searching`（`headDx = round(sin(2.2t))` ∈ −1…1，约 0.35 Hz）；`Performer.swift:113` | 看图 [A] t=9–13 手在鼠标上；左右扫只读代码，静态取样看不出 | ✓(无专门测试) |
| S03b | 6.5 Grep/Glob·屏幕 | 结果列表，高亮条缓动 / 文件树展开 | `ScreenContent.swift:140` `.results`（高亮条按 smoothstep 换行）／`:149` `.tree`（每 0.35 s 多展开一行，最多 5 行）；`Performer.swift:151`（Grep→results，Glob·LS→tree） | 看图 [N] results / tree 两个时刻（高亮行不同 / 展开行数不同）、[A] t=9–13 | ✓ |
| S03c | 6.5 Grep/Glob·气泡 | 放大镜图标 | `Performer.swift:185`（search 类→`.search`）；`SeatRenderer.swift` `icon.magnifier` | 看图 [A] t=9,11,13（Grep / Glob 都有放大镜） | ✓ |
| S03d | 6.5 Grep/Glob·桌牌 | 「在找 "TODO"」／「在翻文件」 | `PlateCopy.swift:113–115`（词最多 12 字 `clip`） | `PC.activityTextForEveryState`（`在找 "TODO" ×3`）、`PC.fileNamesClipsAndDurations`（clip 12）；「在翻文件」只有看图 [A] t=13 | ✓ |
| S04a | 6.5 Edit·身体 | 打字（4 帧 × 8 fps，每只手 2 Hz） | `PoseLibrary.swift:64` `.typing`：**133 ms 一格**（7.5 格/秒），4 格一轮 → 每只手 1.875 Hz | 看图 [X] Edit 段（15 fps 逐帧，我比对了 13 张图的哈希）：状态序列 A A B B A A C C A A B B，每个状态恰好 2 帧（133 ms）、4 个状态一轮（0.53 s）。偏离理由：渲染稳态 15 fps（66.7 ms），133 ms＝整 2 格，节奏均匀 | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| S04b | 6.5 Edit·屏幕 | 编辑器：一行高亮，字符逐个出现，左侧绿色 diff 标记 | `ScreenContent.swift:157` `.diffEdit`（高亮行、`chars = min(14, Int(t*6))` 逐字出现、左侧绿点、光标呼吸） | 看图 [N] diffEdit（t=1.0 与 6.3 字符数不同，左边有绿标记）、[A] t=15–19 | ✓ |
| S04d | 6.5 Edit·桌牌 | 「在改 x.swift」 | `PlateCopy.swift:116` | `PC.activityTextForEveryState`（`在改 Session.swift`） | ✓ |
| S05a | 6.5 Write·身体 | 打字更快 | `PoseLibrary.swift:64` `.typingFast`（左右手不停交替，每只手 3.75 Hz < 4 Hz；DESIGN §7 记了这个做法） | 看图 [X] Write 段（哈希比对）：状态序列 A B A B …，每态 2 帧（133 ms），左右手轮流，每只手 267 ms 一次 = 3.75 Hz，是 Edit（每只手 0.53 s 一次）的 2 倍；没有单元测试 | ✓ |
| S05b1 | 6.5 Write·屏幕 | 一行行从上往下出现 | `ScreenContent.swift:167` `.notebook`（每 0.28 s 多一行，最多 6 行，末行光标） | 看图 [N] notebook（t=1.0 与 6.3 行数不同）、[A] t=21,23 粉色行逐行出现 | ✓ |
| S05b2 | 6.5 NotebookEdit·屏幕 | notebook 单元格 | `Performer.swift:153`：NotebookEdit 和 Write 同属 write 类，走同一个 `.notebook`，画的是同样的逐行，没有单元格样式 | 读代码（`ToolCatalog` 把 NotebookEdit 并进 write）；DESIGN §5 表写「一行行出现」，没提单元格 | 偏离-未记录 |
| S05d | 6.5 Write·桌牌 | 「在写 x.swift」 | `PlateCopy.swift:117` | 看图 [A] t=21,23「在写 Session.swift」；`PC.activityTextForEveryState` 没有 Write 用例 | ✓ |
| S06a | 6.5 Bash ≤ 8 s·身体 | 快速敲一阵，然后手歇下来 | `Performer.swift:116`：≤ 3 s `.typing`，3–8 s `.restAtDesk`（`PoseLibrary.swift:72`，手停在键盘上）。「快速敲」用的是普通 `.typing`，不是 `.typingFast` | 看图 [A] t=25（打字）、t=27–31（手静止）；[Y] 键盘区 15 fps 逐帧：t=23–26 每 2 帧变一次（133 ms 打字节拍），t=26 之后基本不变（只剩呼吸的偶发变化），t=31 起换成靠背；没有单元测试 | ✓ |
| S06b | 6.5 Bash ≤ 8 s·屏幕 | 黑底终端，绿色提示符，一行行输出 | `ScreenContent.swift:172` `.terminal`（`>` 提示符 + 输出行每 0.4 s 上滚） | 看图 [N] terminal、[A] t=25–31、[G] t=15–21 | ✓ |
| S06d | 6.5 Bash ≤ 8 s·桌牌 | 「运行 git status」 | `PlateCopy.swift:118–121`、`shortCommand :7`（去掉 `cd … &&`，只留前 1–2 个词） | `PC.shortCommandKeepsTheFirstWordsAndDropsCdPrefixesAndOptions`、`PC.activityTextForEveryState`（`运行 git status`）；[G] t=15「运行 python3 run.py」 | ✓ |
| S07a1 | 6.5 Bash > 8 s·身体 | 往后靠、抱着手臂 | `PoseLibrary.swift:91` `.leanBack`（torsoDy 1、headDy 1，双手落在身侧 `restL/restR`）；`Performer.swift:116` | 看图 [A] t=33–39、[U] bash36：后靠，手臂看不见；「抱臂」是近似（手放身侧，从背后看不出差别） | ✓(无专门测试) |
| S07a2 | 6.5 Bash > 8 s·身体 | 每 20 秒最多喝一口 | `PoseLibrary.swift:95–103`：22 s 一圈，圈尾 2.6 s 手去够杯子再举到嘴边 | 只读代码；demo 里 Bash 只持续 17 s，没拍到喝水 | ✓(无专门测试) |
| S07b | 6.5 Bash > 8 s·屏幕 | 终端 + 进度条，按 1−e^(−t/τ) 增长，永远不会假装跑满 | `ScreenContent.swift:184–186`（τ = 30 s，宽度上限 94 %；t 从切到长 Bash 屏幕算起） | 看图 [N] terminalLong t=1.0 / 6.3（进度条变长）；注意：进度条在第 12–13 行，正好在头部遮挡区，见疑点 | ✓ |
| S07c | 6.5 Bash > 8 s·道具 | 马克杯 | 每个工位桌上都有马克杯（`SeatRenderer.swift` mug blit），喝水动作去够它；`BubbleKind.mug` / `icon.mug` 定义了但 `targetBubble` 从不返回 | 看图 [U] bash36：杯子在桌左 | ✓(无专门测试) |
| S07d | 6.5 Bash > 8 s·桌牌 | 「运行中 npm test · 1:23」 | `PlateCopy.swift:120`（elapsed > 8 → `运行中 <cmd> · m:ss`） | 看图 [A] t=33「运行中 npm test · 0:10 · 本轮 0:33 …」；单元测试没有 > 8 s 的分支 | ✓ |
| S08a1 | 6.5 WebFetch·身体 | 握鼠标 | `Performer.swift:118`（`.web` → `.mouse`；> 8 s 换 `.leanBack`） | 看图 [C] t=3–7 | ✓ |
| S08a2 | 6.5 WebSearch·身体 | 先打字再用鼠标 | `Performer.swift:118`：WebSearch 和 WebFetch 一样只有 `.mouse`，没有「先打字」 | 看图 [C] t=9–13（一直是握鼠标）；DESIGN §5 表只写「握鼠标」，没有理由 | 偏离-未记录 |
| S08b | 6.5 Web·屏幕 | 浏览器：地址栏，页面块逐个加载 / 搜索结果 | `ScreenContent.swift:188` `.browser`（每 0.5 s 多一块，最多 4 块）／`:197` `.search`（搜索框字逐个出现 + 结果条）；`Performer.swift:156` | 看图 [C] t=3–13、[N] browser / search | ✓ |
| S08d | 6.5 Web·桌牌 | 「在看 github.com」／「在搜 …」 | `PlateCopy.swift:123–125`（URL 只留域名，搜索词最多 12 字） | `PC.fileNamesClipsAndDurations`（`domain`、`clip`）；[C] t=3「在看 nature.com」、t=9「在搜 "hydrogen emb…"」 | ✓ |
| S09a1 | 6.5 Agent 前台·身体 | 转成 3/4 朝向对着小助手 | `PoseLibrary.swift:114` `.delegate`（facing = `.threeQuarterBack`，座位在右半边时镜像） | 看图 [C] t=15–25、[U] deleg20：3/4 朝向，椅子同步转 | ✓ |
| S09a2 | 6.5 Agent 前台·身体 | 指一指，然后抱臂督工 | `PoseLibrary.swift:118–119`：每 6 s 一轮，前 2.2 s 手臂伸向一侧，之后手收回身侧（代码注释写明是近似） | 看图 [C]（连续取样）t=15,17 与 t=21,23 手臂伸向帮手、t=19 收回（6 s 一轮）；单帧 [U] deleg20 / pt16：t=16 手臂水平伸向左边两个帮手；「抱臂」同 S07a1 是近似 | ✓(无专门测试) |
| S09b | 6.5 Agent 前台·屏幕 | 小助手列表 + 进度 | `ScreenContent.swift:206` `.helpers`（三个彩色方块 + 进度条） | 看图 [C] t=15–25、[N] helpers | ✓ |
| S09c | 6.5 Agent 前台·道具 | 小助手坐着带轮凳子、抱着笔记本滑进来（最多 3 个，多了 +N） | `Performer.swift:380` `syncHelpers`（弹簧滑入，3 个槽位）；`SeatRenderer.swift:130–146`（小助手精灵 + 「+N」牌） | 看图 [U] deleg20（带轮凳子、抱笔记本）、[R] c12seat1（5 个帮手 → 「+2」）；`RT.retainedRenderingMatchesFullRedrawWithMoreThanEightPeople`（只保证逐像素一致） | ✓ |
| S09d | 6.5 Agent 前台·桌牌 | 「派了 2 个帮手」 | `PlateCopy.swift:128–131` | 看图 [C]「派了 3 个帮手」、[R]「派了 5 个帮手」；没有单元测试 | ✓ |
| S10a | 6.5 Agent 后台·身体 | 回去干自己的活 | `Performer.swift:121`（没有前台未完成的帮手 → `.typing`） | 看图 [C] t=27–33 恢复打字 | ✓ |
| S10b | 6.5 Agent 后台·屏幕 | —（规格没写） | `Performer.swift:159` 仍显示小助手列表 | 看图 [C] t=27–33；规格是「—」，多画不冲突 | ✓ |
| S10c | 6.5 Agent 后台·道具 | 小助手留在旁边 | 后台帮手照样在 `syncHelpers` 里保留（`active = !done`） | 看图 [C] t=27–33 青色帮手站在旁边 | ✓ |
| S10d | 6.5 Agent 后台·桌牌 | 「帮手在后台干活」 | `PlateCopy.swift:130` | 看图 [C] t=27–33 | ✓ |
| S11a | 6.5 TodoWrite·身体 | 在便签本上写（≤ 3 Hz） | `PoseLibrary.swift:105` `.writingPad`（4 格一轮，每格 133 ms → 1.875 Hz，x/y 同一节拍离散抖动） | 看图 [U] todo3：右手落在右侧便签本上；节拍：[Y] 手部区域逐帧哈希 A A B B A A C C（每态 2 帧 = 133 ms，4 态一轮 = 1.875 Hz ≤ 3 Hz） | ✓ |
| S11b | 6.5 TodoWrite·屏幕 | 清单逐项打勾 | `ScreenContent.swift:215` `.checklist`（每 0.7 s 多勾一项，循环） | 看图 [N] checklist（t=1.0 与 6.3 勾数不同）、[E] t=3 | ✓ |
| S11c | 6.5 TodoWrite·道具 | 便签本 | `.notepad` 桌面道具（`SeatRenderer.swift` `prop.notepad`） | 看图 [U] todo3 | ✓ |
| S11d | 6.5 TodoWrite·桌牌 | 「在列计划」 | `PlateCopy.swift:132` | 看图 [E] t=1–3；没有单元测试 | ✓ |
| S12a | 6.5 Skill/ToolSearch·身体 | 翻手册 / 点鼠标 | `Performer.swift:112`：Skill 和 ToolSearch 都是 `.mouse`，没有「翻手册」 | 读代码；DESIGN §5 表只写「握鼠标」，没有理由 | 偏离-未记录 |
| S12b | 6.5 Skill/ToolSearch·屏幕 | 手册页 / 图标网格，高亮在移动 | `ScreenContent.swift:223` `.manual`（每 1.6 s 翻页）／`:228` `.iconGrid`（高亮每 0.5 s 移一格） | 看图 [E] t=5–13、[N] manual / iconGrid | ✓ |
| S12c | 6.5 Skill/ToolSearch·气泡 | 书 / 工具箱 | `Performer.swift:187`（Skill→book，ToolSearch→toolbox） | 看图 [E] t=7,9 书、t=11,13 工具箱 | ✓ |
| S12d | 6.5 Skill/ToolSearch·桌牌 | 「在看技能手册」／「在翻工具箱」 | `PlateCopy.swift:133` | 看图 [E] t=5–13 | ✓ |
| S13a | 6.5 MCP 浏览器·身体 | 握鼠标，小幅度点击 | `Performer.swift:119` `.mouse`（鼠标手 ±1 px 缓慢漂移，没有「点击」动作） | 看图 [E] t=15–17 手在鼠标上 | ✓(无专门测试) |
| S13b | 6.5 MCP 浏览器·屏幕 | 浏览器，指针在动；点击处有扩散圈，只用调色板变暗，不闪 | `ScreenContent.swift:236` `.mcpBrowser`（指针沿环形路径；点击时指针四周 4 个 `scr.dark` 像素，每 3 s 一次约 0.36 s，静止的一圈、不「扩散」） | 看图 [N] mcpBrowser t=1.0 / 6.3、[E] t=15–17 | ✓ |
| S13d | 6.5 MCP 浏览器·桌牌 | 「在操作浏览器」 | `PlateCopy.swift:126` | 看图 [E] t=15–17 | ✓ |
| S14a | 6.5 computer-use·身体 | 握鼠标 | `Performer.swift:119` | 看图 [E] t=19–23 | ✓ |
| S14b | 6.5 computer-use·屏幕 | 桌面上有窗口和指针 | `ScreenContent.swift:247` `.desktop` | 看图 [N] desktop、[E] t=19–23 | ✓ |
| S14d | 6.5 computer-use·桌牌 | 「在操作电脑」 | `PlateCopy.swift:127` | 看图 [E] t=19–23 | ✓ |
| S15a | 6.5 其他 MCP·身体 | 打字和鼠标交替 | `Performer.swift:120`（`Int(elapsed/3) % 2`：每 3 s 换，受姿势最短停留 1.5 s 约束） | 只读代码；demo 里 notion 只有 5 s，看不出交替 | ✓(无专门测试) |
| S15b | 6.5 其他 MCP·屏幕 | 带 server 首字母的应用面板 | `ScreenContent.swift:255–261`：用 `PixelFont.small`（4×6）画首字母；**这个字体只有数字、`M`、`K`、`x` 和少数符号，其余字母落到「?」占位字形** | 看图 [N]「mcpApp N」画出的是「?」；[U] mcpapp26（demo 里的 notion，本该是 N）同样是「?」。BUG | 偏离-未记录 |
| S15d | 6.5 其他 MCP·桌牌 | 「在用 <server>」 | `PlateCopy.swift:138`（server 截 10 字） | 看图 [E] t=25,27「在用 notion」 | ✓ |
| S16a | 6.5 SendUserFile/定时/Monitor·身体 | 把纸放进发件盘／拨桌上的闹钟／往后靠 | `PoseLibrary.swift:120` `.sendFile`、`:127` `.alarm`、`:91` `.leanBack`（Monitor）；`Performer.swift:117,123,124` | 看图 [U] send30（手伸向左侧托盘）、alarm34（手在右侧闹钟上）、[F] t=39–41（Monitor 后靠） | ✓ |
| S16b | 6.5 SendUserFile/定时/Monitor·屏幕 | 文件滑进盘里／钟面／日志滚动 | `ScreenContent.swift:337` `.outbox`、`:343` `.clock`、`:349` `.log` | 看图 [N] outbox / clock / log、[E] t=29–35、[F] t=37–41 | ✓ |
| S16c | 6.5 SendUserFile/定时/Monitor·道具 | 发件盘／闹钟（Monitor 无） | `.tray` / `.alarm` 桌面道具（`SeatRenderer.swift` `prop.tray` / `prop.alarm`） | 看图 [U] send30（灰色托盘）、alarm34（白色闹钟）；[F] t=39 Monitor 桌上无多余道具 | ✓ |
| S16d | 6.5 SendUserFile/定时/Monitor·桌牌 | 「发给你一个文件」／「定了闹钟」／「在盯日志」 | `PlateCopy.swift:136,137,122` | 看图 [E] t=29,33,37 | ✓ |
| S17a | 6.5 EnterPlanMode·身体 | 在笔记本上写 | `Performer.swift:122` → `.writingPad` | 看图 [U] plan44、[F] t=43–47 | ✓ |
| S17b | 6.5 EnterPlanMode·屏幕 | 大纲文档 | `ScreenContent.swift:275` `.plan` | 看图 [N] plan、[U] plan44 | ✓ |
| S17c | 6.5 EnterPlanMode·道具 | 笔记本 | `.notepad` | 看图 [U] plan44 | ✓ |
| S17d | 6.5 EnterPlanMode·桌牌 | 「在做计划」 | `PlateCopy.swift:134` | 看图 [F] t=43–47 | ✓ |
| S18a | 6.5 等批准·身体 | 转身面向你，举手轻轻挥（1.2 Hz） | `Performer.swift:227`（持续 0.4 s 才转身）；`PoseLibrary.swift:183`（手 x = ±2 px × sin(2π·1.2·t)）；转身序列 `Performer.swift:340` | `PF.waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5`、`PF.aWaitingBlipShorterThan0_4SecondsDoesNotTurnTheBuddy`；看图 [M]（转身 7 步）、[B] t=41–47（举手）；[Y] 举手区域 30 fps 逐帧哈希：25 帧一轮 ＝ 0.83 s ＝ 1.2 Hz | ✓ |
| S18b | 6.5 等批准·屏幕 | 权限对话框，带两个按钮 | `ScreenContent.swift:262` `.permission`（灰「拒绝」+ 绿「允许」）；`Performer.swift:168`（映射）、`:253`（等待类立即切屏，不受 0.8 s 最短停留限制） | 看图 [N] permission、[B] t=41；[M] t=40.03 屏幕一帧切到对话框 | ✓ |
| S18c | 6.5 等批准·气泡 | 钥匙气泡 + 工具图标 | `Performer.swift:191,201`（bash / edit·write / web·browser / read·search / 其他）；`SeatRenderer.swift` `drawBubble(.approval)` | 看图 [B] t=41（Bash 图标）、[G] t=25（Edit 铅笔） | ✓ |
| S18d | 6.5 等批准·桌牌 | 「等你批准 Bash · 2 分钟」 | `PlateCopy.swift:88`、`waitSpoken :51` | `PC.activityTextForEveryState`（`等你批准 Bash · 5 秒`）、`PC.fileNamesClipsAndDurations`（`waitSpoken(120) == "2 分钟"`） | ✓ |
| S19a | 6.5 提问·身体 | 转身举手 | `PoseLibrary.swift:188`（手小幅起伏）＋表情 question（`Performer.swift:356`） | 同 S18a 的状态机测试；看图 [B] t=49–55 | ✓ |
| S19b | 6.5 提问·屏幕 | 带选项的对话框 | `ScreenContent.swift:269` `.question`（「?」+ 3 个选项） | 看图 [N] question、[B] t=49–55 | ✓ |
| S19c | 6.5 提问·气泡 | 「?」气泡 | `Performer.swift:193` | 看图 [B] t=49–55 | ✓ |
| S19d | 6.5 提问·桌牌 | 「有问题问你」 | `PlateCopy.swift:89` | `PC.activityTextForEveryState` | ✓ |
| S20a | 6.5 计划待审·身体 | 转身举起一块写字板 | `PoseLibrary.swift:191`（`holdClipboard`）；`SeatRenderer.swift` 把 `prop.clipboard` 贴进人物图层 | 看图 [B] t=57–61（写字板举在胸前，表情开心） | ✓ |
| S20b | 6.5 计划待审·屏幕 | 计划文档 | `.plan`（`Performer.swift:170`） | 看图 [B] t=57–61 | ✓ |
| S20c | 6.5 计划待审·气泡 | 写字板气泡 | `Performer.swift:194`（`icon.board`） | 看图 [B] t=57–61 | ✓ |
| S20d | 6.5 计划待审·桌牌 | 「计划好了，等你看」 | `PlateCopy.swift:90` | `PC.activityTextForEveryState` | ✓ |
| S21a | 6.5 整理上下文·身体 | 把一摞纸塞进箱子 | `PoseLibrary.swift:133` `.compacting`（双手在纸堆 / 箱子间来回，x ±3 px） | 看图 [U] compact37、[C] t=35–41：双手在桌左纸堆与箱子之间动；不是逐帧的「塞」 | ✓ |
| S21b | 6.5 整理上下文·屏幕 | 一行行被压成一块 | `ScreenContent.swift:279` `.compact`（3 s 一轮，行越来越短越挤） | 看图 [N] compact、[C] t=35–39 | ✓ |
| S21c | 6.5 整理上下文·道具 | 纸堆 / 箱子 | `.papers` + `.box` 桌面道具 | 看图 [U] compact37 | ✓ |
| S21d | 6.5 整理上下文·桌牌 | 「在整理记忆」 | `PlateCopy.swift:79` | `PC.activityTextForEveryState` | ✓ |
| S22a1 | 6.5 重试中·身体 | 挠头 | `PoseLibrary.swift:138` `.retry`（右手到后脑上方，x 每 267 ms 换一格 = 1.875 Hz ≤ 2 Hz） | 看图 [U] retry43、[D] t=41–45：右臂举到头侧；节拍：[Y] 手部区域逐帧哈希每 4 帧（267 ms）换一态，8 帧一轮 = 1.875 Hz ≤ 2 Hz | ✓ |
| S22a2 | 6.5 重试中·身体 | 轻敲显示器（≤ 2 Hz） | 没有这个动作（只有挠头） | 读代码；DESIGN 没记 | 缺失 |
| S22b | 6.5 重试中·屏幕 | 缓慢转动的循环箭头 + 像素数字「2/10」 | `ScreenContent.swift:290` `.retry`（4 帧箭头，约 0.6 Hz；「10/10」太宽时换成 3×3 小转圈） | 看图 [U] retry43、[N] retry 2/10；crowd12 里「10/10」也放得下（`DemoScript` crowd 模式专门造的） | ✓ |
| S22d | 6.5 重试中·桌牌 | 「网络不稳，重试中 2/10」 | `PlateCopy.swift:80` | `PC.activityTextForEveryState` | ✓ |
| S23a | 6.5 出错·身体 | 手扶额头 | `PoseLibrary.swift:145` `.facepalm`（右手到后脑、头低 2 px） | 看图 [U] facep48、[D] t=47–49：头低下，右臂向上贴着头；从背后看不到脸 | ✓(无专门测试) |
| S23b | 6.5 出错·屏幕 | 静止的橙色三角警告 | `ScreenContent.swift:307` `.warning` | 看图 [N] warning t=1.0 与 6.3 完全相同、[D] t=47–49；`RT.staticScreenClassificationMatchesWhatIsActuallyDrawn`（静态判定与真实一致） | ✓ |
| S23d | 6.5 出错·桌牌 | 「出错了」 | `PlateCopy.swift:95` | `PC.activityTextForEveryState` | ✓ |
| S24a | 6.5 被打断·身体 | 两手一摊「哇哦」，1.5 秒 | `PoseLibrary.swift:149` `.shrug`；`Performer.swift:130`（el < 1.5 → shrug，之后 `.leanSide`） | 看图 [U] shrug55（双手摊向两侧）、[D] t=55 → 57 转侧身；`AR.interruptedLasts3SecondsThenIdle` | ✓ |
| S24b | 6.5 被打断·屏幕 | 停止标志 | `ScreenContent.swift:312` `.stop` | 看图 [N] stop、[D] t=55–57 | ✓ |
| S24d | 6.5 被打断·桌牌 | 「被你打断了」 | `PlateCopy.swift:92` | `PC.activityTextForEveryState` | ✓ |
| S25a | 6.5 做完了·身体 | 伸懒腰，然后 3/4 侧身靠着 | `Performer.swift:131–133`（先 0.4 s 保持原姿势 → 1.2 s 伸懒腰 `PoseLibrary.swift:154` → `.leanSide`） | 看图 [H] t=41（双臂举过头）→ t=42.8 侧身；[B] t=65 / 67 | ✓ |
| S25b | 6.5 做完了·屏幕 | 绿色 ✓ | `ScreenContent.swift:315` `.done` | 看图 [B] t=63–67、[H] t=41–44 | ✓ |
| S25c | 6.5 做完了·道具 | 未读时显示器上插一面小旗 | `SeatRenderer.swift:305` `prop.flag`（`v.flag = snapshot.unread`，`Performer.swift:472`） | 看图 [H] t=41–61 小旗一直在；[B] t=75 新一轮开始后小旗消失 | ✓ |
| S25d | 6.5 做完了·桌牌 | 「做完了 · 3分12秒」 | `PlateCopy.swift:93–94`、`spoken :45` | `PC.fileNamesClipsAndDurations`（`spoken(192) == "3分12秒"`）；[B] t=63「做完了 · 1分3秒」；`PC.activityTextForEveryState` 没有 finished 用例 | ✓ |
| S26a1 | 6.5 需要你处理·身体 | 3/4 侧身 | `.idle` 姿势 = 3/4 侧身靠着（`PoseLibrary.swift:161`） | 看图 [B] t=69–73 | ✓ |
| S26a2 | 6.5 需要你处理·身体 | 点点便利贴 | 没有这个动作：blocked 时身体和普通空闲完全一样 | 读代码（`blocked` 只影响气泡和桌牌） | 缺失 |
| S26c | 6.5 需要你处理·气泡 | 静止的黄色「!」便利贴 | `Performer.swift:196`（idle 且 blocked → `.note`）；`icon.note` 无动画 | 看图 [B] t=69–73 | ✓ |
| S26d | 6.5 需要你处理·桌牌 | 「需要你处理」 | `PlateCopy.swift:96` | 看图 [B] t=69–73；`PC.activityTextForEveryState` 只有非 blocked 的「空闲」 | ✓ |
| S27a1 | 6.5 空闲·身体 | 3/4 侧身靠着，每 30–60 秒喝一口、四处看 | `PoseLibrary.swift:161` `.leanSide/.idle`：45 s 一圈，t≈30 s 起 1.6 s 侧身四处看、t≈40 s 起 2.6 s 喝一口 | 看图 [V] t=23.3（座位 0，侧身看；每个 buddy 相位不同）；喝水段没有拍到 | ✓ |
| S27a2 | 6.5 打盹·身体 | 头一点一点往下垂 | `PoseLibrary.swift:171` `.doze`（头 y = 1 + round(0.5 + 0.5·sin 0.7t)，1–2 px，约 0.11 Hz） | 看图 [I] t=20–40：头比空闲低；「点头」的节奏只读代码 | ✓(无专门测试) |
| S27a3 | 6.5 睡着·身体 | 趴在手臂上 | `PoseLibrary.swift:175` `.sleep`（躯干 +3、头 +6、双手搭键盘） | 看图 [I] t=43–75 | ✓ |
| S27b1 | 6.5 空闲/打盹/睡着·屏幕 | 暗色桌面／慢速屏保／关屏 | `ScreenContent.swift:319` `.idleDesktop`、`:323` `.screensaver`（小方块每 0.8 s 挪一格）、`.off`；`Performer.swift:174–176` | 看图 [I]（t=1–17 暗桌面 + 三个图标；20–40 屏保；43+ 关屏）、[N] | ✓ |
| S27b2 | 6.5 空闲/打盹/睡着·屏幕 | 待机灯缓慢呼吸 | `SeatRenderer.swift:176` `ledName`：4 s 周期，2 s 亮 / 2 s 灭，**只有开 / 关两档**（没有中间色阶） | 看图 [I] t=62.9–74.5：绿点时有时无 | 偏离-未记录 |
| S27c | 6.5 打盹/睡着·气泡 | z 气泡；空闲有马克杯 | `Performer.swift:195`（打盹 / 睡着 → `.zzz`，三步错位的两个 z）；桌面马克杯常驻 | 看图 [I] t=20–75（zzz 气泡） | ✓ |
| S27d | 6.5 空闲/打盹/睡着·桌牌 | 「空闲」／「打盹 12 分钟」／「睡着了」 | `PlateCopy.swift:96–98`、`idleMinutes`；触发阈值 10 / 45 分钟在数据层 | `PC.activityTextForEveryState`（空闲、睡着了）、`AR.idleThenDozingThenSleepingAtTheThresholds`；[I]「打盹 0 分钟」（demo 的 idleSince = 当下） | ✓ |
| S28a | 6.5 未知工具·身体 | 打字和鼠标交替 | `Performer.swift:125`：`.unknown → .typing`（只打字，没有鼠标）。DESIGN §5 工具表却写「打字和鼠标交替」→ 文档与代码不一致 | 看图 [F] t=49–53 只有打字 | 偏离-未记录 |
| S28b | 6.5 未知工具·屏幕 | 带齿轮的通用窗口 | `ScreenContent.swift:328` `.gear`（8 齿 + 中心，2 帧慢转） | 看图 [N] gear、[F] t=49–53 | ✓ |
| S28d | 6.5 未知工具·桌牌 | 「在用 <Tool>」 | `PlateCopy.swift:139`（工具名截 14 字） | 看图 [F] t=49–53「在用 FooTool」 | ✓ |
| S29a1 | 6.5 进场·身体 | 从门口走进来坐下 | `Walkers.swift`：门开缝 `lead 0.10 s` → 人从门洞走出 → 走到椅子前 → 坐下 `sitTime 0.3 s`（下沉 0 / 2 / 4 px 三档）；`OfficeScene.swift` `startEntering` | `RT.enteringWalkerAppearsOnlyAfterTheDoorStartedOpening`；看图 [J]（门开缝 t=15.06、人出现 15.20）、[K] | ✓ |
| S29a2 | 6.5 离场·身体 | 起身挥手走出门 | `Walkers.swift`：起身 `standTime 0.3 s` → 挥手 `waveTime 0.7 s` → 走进门洞 → 门关 `tail 0.16 s` | `RT.walkersAreNeverDrawnOutsideTheDoorwayWhileInsideIt`；看图 [L]（t=60.03 起身、60.5–60.9 面向你挥手、61.1 起走） | ✓ |
| S29b1 | 6.5 进场·屏幕 | 开机：5 级调色板渐变，300 ms | `SeatRenderer.swift:278–288` + `OfficeScene.swift:215`：4×4 Bayer 抖动，`Int(boot×16)` 共 16 级、0.3 s（30 fps 下约 9 步）。不是「5 级调色板渐变」 | 看图 [K] f0179→f0183：稀疏点 → 满屏，约 0.3 s。DESIGN §7 写的是「显示器 5 级抖动开机」，与代码的 16 级也对不上 | 偏离（DESIGN §7「进场 / 离场（走路 + 开门）」） |
| S29b2 | 6.5 离场·屏幕 | 关机：5 级调色板渐变，300 ms | 没有：离场时该工位变成 `.empty`，`drawMonitor` 直接画关屏（`SeatRenderer.swift:276`） | 看图 [L] f0045（t=60.00）屏幕还是暗桌面 + 三个图标，f0046（t=60.03）整块屏幕在一帧里变成纯黑（桌牌也同一帧变成暗色的下班牌）；离场时若屏幕是亮的（忙）就是亮屏直接变黑；DESIGN 没记 | 缺失 |
| S30 | 6.5 附注·并行工具 | 显示一个小标签「×3」 | `PlateCopy.swift:83`：动作文案后加 ` ×N`（在桌牌上，不是单独的小标签） | `PC.activityTextForEveryState`（`在找 "TODO" ×3`）；[A] t=9,11「×2」 | ✓ |
| S31 | 6.5 附注·转身 | 朝过道那一侧转；镜像的朝向直接水平翻转图像 | `OfficeScene.swift:211`（工位在世界中线右半边 → 向左转）；`TankScene.swift:85`；`StripScene.swift:59`（槽位奇偶）；`SeatRenderer.swift` `blitCanvas(… flipH: v.mirror)` | 看图 [B]（座位 0 转向右）、[C]（座位 1 在中间列 → 转向左）；[Q] | ✓ |
| S00 | 6.5 各行「—」列 | Read / Edit / Write / Bash / Web / MCP 浏览器 / computer-use / 重试 / 出错 / 被打断 / 未知工具 的道具·气泡列，需要你处理的屏幕列：没有额外要求 | `Performer.swift:180` `targetBubble` 对这些状态返回 nil；需要你处理时屏幕是暗桌面 | 看图 [A][C][E][G]：这些状态都没有多余气泡 / 道具 | ✓ |

## 2. 任务书 6.6 动作手感与防闪烁（和 6.5 相关的数字）

`Motion.swift` = `Sources/PixelKit/Motion.swift`。BuddyStage 里**没有任何针对弹簧 / 呼吸 / 眨眼 / 气泡 / 转身序列的单元测试**（`Tests/BuddyStageTests` 里 grep `PixelSpring`、`breathPhase`、`blink` 均无结果），这几条的证据是读代码、闪烁扫描和我看的图。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| M01 | 6.6 弹簧 | 从静止起步（v0 = 0），阻尼比 ζ ≈ 0.75，带轻微过冲和跟随 | `Motion.swift:15` `PixelSpring.init(zeta: 0.75)`、`snap(to:)` 速度清零；`Performer.swift:75–76`（各弹簧响应周期 0.26–0.34 s） | 无单元测试；`buddyctl flicker` 全部干净间接证明没有来回跳 | ✓(无专门测试) |
| M02 | 6.6 弹簧 | 输出取整到整像素，带 ±0.6 px 迟滞 | `Motion.swift:41`（`abs(value − shown) > 0.6` 才换格） | 同上 | ✓(无专门测试) |
| M03 | 6.6 弹簧 | \|v\| < 0.5 px/s（且贴近终点）直接吸附到终点 | `Motion.swift:38–40` | 同上 | ✓(无专门测试) |
| M04 | 6.6 弹簧 | 永远不要「动一下、停一下」的生硬感 | 身体 / 头 / 手的位移全部走 `PixelSpring`（`Performer.swift:401` `stepSprings`）；打字 / 写字这类逐格离散小动作按节拍直接给整数偏移（`oscL/oscR`） | `RT.officeHasNoFlickerAtEveryZoom`、`RT.tankAndStripHaveNoFlicker`、`RT.officeHasNoFlickerAtNightAndDuringLightTransition`；我跑了 `buddyctl flicker`（办公室 1/2/3 倍、小鱼缸、宠物条，各 2398 帧）全部干净。「生硬」是主观的，没有断言 | ✓(无专门测试) |
| M05 | 6.6 呼吸 | 每个 buddy 一直有呼吸起伏：4 秒一周期，1 像素 | `Performer.swift:405–407`（`breathPhase(period 4)`，`> 0.62` 上、`< 0.38` 下，带迟滞）；`:450` 头随呼吸上下 1 px（躯干不动，`:407` 是空操作） | 无单元测试；只读代码（静态取样看不出 1 px） | ✓(无专门测试) |
| M06 | 6.6 频率上限 | 任何摆动都不超过 4 Hz | 最快的是 `.typingFast`：每只手 3.75 Hz（`PoseLibrary.swift:64`）；其余 ≤ 1.9 Hz；`FlickerScan.swift` 检查 4（质心 1 秒内过零 > 8 次 = 4 Hz 即报错） | `RT.officeHasNoFlickerAtEveryZoom` 等（含检查 4）；我跑的 `buddyctl flicker` 0 个发现 | ✓ |
| M07 | 6.6 不许开关式闪烁 | 光标要么静止，要么在 3 个色阶间以 0.5 Hz 呼吸 | `ScreenContent.swift:108` `cursorColor()`（`breathPhase(period 2.0)` = 0.5 Hz，`scr.dark / dim / white` 三阶） | `RT.staticScreenClassificationMatchesWhatIsActuallyDrawn`（断言 `.ide` 会变）；频率和阶数只读代码 | ✓(无专门测试) |
| M08 | 6.6 不许开关式闪烁 | 等待时的光晕在 3 个相邻色阶间以 0.8 Hz 循环，外加 1 Hz、2 像素的轻弹 | 没有：全仓库没有「等待光晕」（`v.glow` 是夜里屏幕光染头发，属 6.7）。等待时的提示只有琥珀色待机灯（`led.wait`）、气泡、举手 | grep「光晕」「halo」只在调色板注释里出现；DESIGN 没记 | 缺失 |
| M09 | 6.6 眨眼 | 每 5–8 秒一次，3 帧，总时长 ≥ 240 ms，只动眼睛；闪烁扫描里加白名单 | `Performer.swift:429` `blinkExpression`（12.8 s 里两次，间隔 5.4 s / 7.4 s；半闭 90 ms → 闭 80 ms → 半闭 90 ms = 260 ms；只在正面 / 3/4 正面 / 侧面）；`Blink.swift`（覆盖层只改眼睛像素）；`StageRun.swift` `meta.allowRects = blinkRects` | 看图 [W]：t=46.57 半闭、46.70 闭、46.77 半闭（座位 0 面向用户时）；扫描白名单是代码 | ✓ |
| M10 | 6.6 亮度变化 | 亮度变化至少用 250 ms 渐变 | 只有显示器开机（0.3 s，S29b1）和昼夜（Bayer 20 分钟）是渐变。台灯开关（`v.lampOn` 换精灵 + 光圈）、待机灯、屏幕内容切换（暗桌面 → 白色对话框）全是一帧硬切 | 看图 [M] t=40.00→40.03：黑色终端在一帧里变成白色权限对话框；[L] t=60.00→60.03：屏幕一帧变黑；DESIGN 没记 | 偏离-未记录 |
| M11 | 6.6 亮度变化 | 显示器开机是 5 级调色板渐变，用时 300 ms | 同 S29b1：Bayer 16 级抖动 0.3 s | 看图 [K] | 偏离（DESIGN §7「进场 / 离场（走路 + 开门）」写的「5 级抖动开机」） |
| M12 | 6.6 亮度变化 | 绝不闪白，绝不黑帧，也绝不淡出到全黑 | `FlickerScan.swift` 检查 1（平均亮度相邻帧变化 > 0.06、16×16 块变化 > 0.35 又变回）、检查 5（硬切） | `RT.officeHasNoFlickerAtEveryZoom / …AtNightAndDuringLightTransition / tankAndStripHaveNoFlicker`；我跑的 `buddyctl flicker` 0 个发现；严格模式 14 处 1–5 像素抖动见疑点 | ✓ |
| M13a | 6.6 窗口出现时 | 先渲染好第一帧，再把窗口显示出来（办公室） | `AppModel.swift:141–146` `showOffice`（`office.render(force: true)` 之后才 `showWindow`）；`ToastController.swift:31–41`、`Panels.swift:36–49`（提示面板 / 悬停卡片也是先画后 orderFront） | 只读代码 | ✓(无专门测试) |
| M13b | 6.6 窗口出现时 | 同上（小鱼缸 / 宠物条） | `TankPanelController.swift:45` / `StripPanelController.swift:46` `show()` 先 `orderFrontRegardless()`；`render` 开头 `guard panel.isVisible`（`Tank :60`、`Strip :138`），所以首帧要等窗口出现之后的下一个节拍才画，小鱼缸会先露出底色（深紫褐色） | 只读代码；宠物条背景透明，看不出来 | 偏离-未记录 |
| M14 | 6.6 白天 / 黑夜切换 | 4×4 Bayer 抖动，约 20 分钟完成，每个像素只翻转一次 | `SceneClock` / `Lighting`（DESIGN §3「时段」：黎明 05:30–06:40 等，固定钟点表，20 分钟 Bayer 抖动） | `RT.officeHasNoFlickerAtNightAndDuringLightTransition`（05:30:20、18:49:30 两个过渡时刻无闪烁）；「每像素只翻转一次」没有被断言（属 6.7，这里只交叉引用） | ✓(无专门测试) |
| M15 | 6.6 帧时长·打字 | 4 帧，每帧 125 ms | `PoseLibrary.swift:64`：每格 133 ms | 同 S04a | 偏离（DESIGN §7「打字节拍 133 ms 一格」＋§10 汇总表「打字 4 帧 × 125 ms」） |
| M16 | 6.6 帧时长·鼠标 | 2 帧，每帧 300 ms | `PoseLibrary.swift:74–77`：鼠标手用 `sin(1.3t)` / `cos(0.9t)` 取整成 ±1 px 的缓慢漂移（周期约 4.8 s / 7 s），不是 2 个 300 ms 的帧 | 读代码；DESIGN 没记 | 偏离-未记录 |
| M17 | 6.6 帧时长·走路 | 侧面走路 6 帧 × 110 ms；正面 / 背面 4 帧 × 130 ms | `Walkers.swift:174`：所有朝向共用 1.6 步/秒的连续相位（0.625 s 一周期），`BuddyRig.renderStanding` 按 sin 取整摆腿 / 手臂，不是逐帧表 | 看图 [J]；`buddyctl walk` 每方向出 8 帧；DESIGN 没记 | 偏离-未记录 |
| M18 | 6.6 帧时长·坐下 / 起立 | 3 帧 | `Walkers.swift:187,195`：下沉 0 / 2 / 4 px 三档，各约 0.1 s（`sitTime` / `standTime` 0.3 s） | 看图 [K]（19.6 站在椅后 → 19.8 下沉 → 19.93 坐好）、[L]（60.03 起身） | ✓ |
| M19 | 6.6 转身 | 约 0.75 秒，椅子同步转动 | `Performer.swift:340`（6 步共 450 ms）+ 举手弹簧 ≈ 0.7 s；`chairFacing: f` 让椅子跟着变朝向 | 看图 [M]：椅子在 3/4、侧面、3/4 正面帧里同步变化（侧面帧里椅子单独画在桌边） | ✓ |
| M20 | 6.6 转身 | 6 步：背面下沉 1 px 80 ms → 3/4 背 70 → 侧面 60 → 3/4 正 70 → 正面 90 → 回弹 1 px 80 | `Performer.swift:340`（`(.back,.08,+1) (.34back,.07) (.side,.06) (.34front,.07) (.front,.09) (.front,.08,−1)`） | 看图 [M]（30 fps 逐帧，与 33 ms 一帧的粒度粗略对应）：t≈40.46–40.53 下沉、40.56–40.59 3/4 背、40.63–40.66 侧面、40.69–40.73 3/4 正、40.76–40.83 正面、40.86 起回弹 | ✓ |
| M21 | 6.6 转身 | 第 7 步：举手 3 帧，70 / 70 / 90 ms，过冲 1 像素后回落 | 不是 3 个离散帧：由手的弹簧完成（`Performer.swift:359` 注释；period 0.26 s、ζ 0.75），效果是约 0.2 s 的举手 + 过冲 | 看图 [M] t=40.93–41.09：手升起后小幅晃动；没有单元测试 | ✓(无专门测试) |
| M22 | 6.6 气泡 | 11–15 px，用 3 帧由小变大弹出，不用非整数缩放 | `SeatRenderer.swift:158` `bubbleSize`：age < 60 ms → 7 px、< 120 ms → 11 px、之后 15 px（三档共用左下角，长大不换位置）；起步是 7 px，规格写的是 11–15 | 看图 [M] t=40.03 / 40.10 / 40.17：小 → 中 → 大；`RT.seatSignatureChangesExactlyWhenPixelsCanChange`（指纹含气泡尺寸） | ✓ |
| M23 | 6.6 气泡 | 图标是 7×7 | `BubbleArt`（`Bubbles.swift:44–197` 逐个 7 行 × 7 列的字符网格） | `SP.spriteBooksHaveNoErrors`（BubbleArt.book 的网格宽度一致、角色合法）；看图 [M][B]（气泡内图标） | ✓ |

## 3. 任务书 7.1 三种形态 + 菜单栏 + Dock

文件都在 `Sources/BuddyOffice/`（AppKit 层，**无测试目标**）。`--test-titlebar` / `--self-test` / `--log-ui` / `--test-hotkey` 是 App 的启动参数（`AppDelegate.swift`、`DebugTools.swift`），结果记在 `DESIGN.md` 第 8、9 节；我只读到 `/tmp/buddy-office-debug.log`（02:27 的一次 `--test-titlebar`，7 行）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| U01 | 7.1 办公室窗口 | 普通 NSWindow：带标题栏、可缩放，内容铺满，标题栏透明 | `OfficeWindowController.swift:33–40`（`.titled .closable .miniaturizable .resizable .fullSizeContentView`、`titlebarAppearsTransparent`、`titleVisibility = .hidden`、`contentView = pixelView`）；`contentResizeIncrements` = 缩放倍数（`:88`） | 无测试；`--dump-window` 自渲染（DESIGN §8/§9），没有真窗口截图 | ✓(无专门测试) |
| U02 | 7.1 办公室窗口 | 窗口位置自动保存 | `OfficeWindowController.swift:41–43`（`setFrameAutosaveName("BuddyOfficeMainWindow")`，记下有没有存过）；`AppModel.swift:145`（只有第一次运行才 `center()`） | DESIGN §9.1「窗口位置记住」（实测发现并修了每次都居中的 bug）；无测试 | ✓(无专门测试) |
| U03 | 7.1 办公室窗口 | 点关闭只是隐藏，App 继续运行 | `OfficeWindowController.swift:66`（`windowShouldClose` → `orderOut` + `office.visible=false`）；`AppDelegate.swift:123`（`applicationShouldTerminateAfterLastWindowClosed` = false） | 无测试 | ✓(无专门测试) |
| U04a | 7.1 办公室窗口 | 标题栏像素按钮：缩成小鱼缸 | `TitleBarButtons.swift`（`NSTitlebarAccessoryViewController(.trailing)`）；`AppModel.swift:104,151` `shrinkToTank`（`tank.visible=true`、`office.visible=false`） | 我读到的日志：`titlebar-test: 点了「缩成小鱼缸」→ 办公室 关 · 小鱼缸 开 …`（`--test-titlebar` 用合成鼠标事件点按钮） | ✓ |
| U04b | 7.1 办公室窗口 | 标题栏像素按钮：打开桌面宠物 | `AppModel.swift:105`（开关 `strip.visible`，不动办公室） | 日志：点一次「桌面宠物」→ 宠物 开、按钮亮；再点 → 关 | ✓ |
| U04c | 7.1 办公室窗口 | 标题栏像素按钮：设置 | `AppModel.swift:106` → `showSettings` | 日志：点「设置」→ 设置窗口 开 | ✓ |
| U04d | 7.1 办公室窗口 | （美术）12×12 木牌底板 4 种状态 + 10×10 图标，最近邻放大 | `Sources/BuddyArt/Icons/ChromeArt.swift`（`plate.normal/hover/pressed/on` + `chrome.tank/strip/gear`）；`TitleBarButtons.swift:44–94` `PixelButton`（悬停 / 按下 / 形态开着 = 金边） | 看图 [S]：4 种底板（普通 / 悬停变亮 / 按下变暗 / 金色描边）+ 金鱼缸 / 带小黄鸭的显示器 / 齿轮 | ✓ |
| U05a | 7.1 办公室窗口 | 悬停卡片直接画在场景里 | `OfficeScene.swift:251` 起（`options.hoverSnapshot` → `HoverCard.make` → `blitCanvas` 进场景，越界翻到左侧、夹进视口；这段别的工位正在改，行号会漂） | 看图 [P] 座位 0 / 3：卡片在人右侧，含标题 / 路径 / 来源 / 模型·effort·权限 / 状态 / 本轮 / token 分项 / 上下文（demo 数据没有 `sessionStartedAt` 和 `statusDetail`，「会话已开」「status_detail」两行只读了代码 `HoverCard.swift:52,60`） | ✓ |
| U05b | 7.1 办公室窗口（另见 6.3） | 悬停 250 ms 后出卡片 | `OfficeWindowController.swift:97–101`（`model.time − hoverSince >= 0.25`） | 只读代码 | ✓(无专门测试) |
| U06 | 7.1 小鱼缸 | NSPanel，无边框、不抢焦点（nonactivating） | `Panels.swift:7–21` `FloatingPanel`（`.borderless, .nonactivatingPanel`、`canBecomeKey/Main = false`、`hidesOnDeactivate = false`） | 只读代码 | ✓(无专门测试) |
| U07 | 7.1 小鱼缸 | `level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` | `Panels.swift:10,15,18`（默认参数 `.floating`；`collectionBehavior` 与规格一致） | 只读代码 | ✓(无专门测试) |
| U08 | 7.1 小鱼缸 | 按住背景可以拖动；`canBecomeKey = false` | `TankPanelController.swift:30` `isMovableByWindowBackground = true`；`Panels.swift:8` | 只读代码。注意：`PixelView` 没覆盖 `mouseDownCanMoveWindow`（默认 `!isOpaque` = true），点击可能被窗口拖动吞掉，见疑点 | ✓(无专门测试) |
| U09a | 7.1 小鱼缸 | 工位格 48×56 的紧凑版，排 1–2 行 | `TankScene.swift:8`（`cellW 48 cellH 56`）、`:26` `layout(count:)`（`shown = min(8, max(count, 2))`，≤ 4 个一行，否则 4 列 2 行）；每格用 56×74 草稿裁切（`:14`、`blitCanvas(scratch, x0−4, y0−2)`） | 看图 [Q] 小鱼缸（4 + 2 人两排）、[R] tankc12（4 + 4 两排）；`RT.tankAndStripShowAnOverflowBadgeBeyondEightPeople` 断言 `layout(count:).extra` | ✓ |
| U09b | 7.1 小鱼缸 | 最多显示 8 个人，更多的显示 "+N" | `TankScene.swift:30`（`extra = count − 8`）、`:115–120`（右下角木牌 + 像素数字） | `RT.tankAndStripShowAnOverflowBadgeBeyondEightPeople`（6/8/9/12 人）；看图 [R] tankc12「+4」 | ✓ |
| U09c | 7.1 小鱼缸 | 顶部有一条窄墙，上面有窗户和挂钟 | `TankScene.swift:8`（`wallH 26`）、`bake` 画墙 / 窗框 / 挂钟，`drawSky` 画天空和钟针 | 看图 [Q]、[R] tankempty（窗户里有太阳和云、右边挂钟） | ✓ |
| U10 | 7.1 小鱼缸 | 双击回到办公室 | `TankPanelController.swift:53–56`（点空白处 `count >= 2` → `onDoubleClickBackground`）→ `AppModel.swift:156` `expandToOffice`（小鱼缸收起 + `showOffice`） | 日志：`双击小鱼缸的背景（回到办公室）→ 办公室 开 · 小鱼缸 关`——但 `--test-titlebar` 是直接调 `onDoubleClickBackground` 回调，没走真实点击（见疑点：拖动可能吞掉点击） | ✓(无专门测试) |
| U11 | 7.1 小鱼缸 | 悬停卡片用单独的 HoverPanel 显示 | `Panels.swift:25–52` `HoverPanelController`（`.statusBar` 层、`ignoresMouseEvents`）；`TankPanelController.swift:95–103`（250 ms 后 `hover.show`） | 只读代码；卡片内容同 [O] | ✓(无专门测试) |
| U12 | 7.1 桌面宠物条 | NSPanel，无边框、不抢焦点，背景透明（`isOpaque = false`、`.clear`），没有阴影 | `Panels.swift:12–14`（`isOpaque = false`、`backgroundColor = .clear`）；`StripPanelController.swift:31` `hasShadow = false`、`PixelView.makeTransparent`；宠物条画布没有墙和地板 | 看图 [Q] strip41（透明背景，只有人和桌子） | ✓ |
| U13 | 7.1 桌面宠物条 | 窗口只和那一群 buddy 一样宽 | `StripScene.swift:42–43`（`w = n×56 + 「+N」列宽`）；`StripPanelController.swift:149–154`（窗口尺寸 = 画布 × 缩放） | `RT.tankAndStripShowAnOverflowBadgeBeyondEightPeople`（断言宽度 = `min(8,n)×cellW + (n>8 ? badgeColW : 0)`）；`RT.stripKeepsSeatedBuddiesStillWhenSomeoneNewArrives` | ✓ |
| U14 | 7.1 桌面宠物条 | 高度 = (64 + 20 气泡 + 56 卡片) × 缩放；底边贴 `visibleFrame.minY` | `StripScene.swift:9,12`（`cardH 56 + bubbleH 20 + cellH 64` = 140）；`StripPanelController.swift:122`（`y = vf.minY`） | 看图 [Q] strip41：画布 336×140（3 倍 = 1008×420）；高度没有单元测试；贴底位置只读代码 | ✓(无专门测试) |
| U15 | 7.1 桌面宠物条 | 默认靠右，可以改成靠左或居中 | `Settings.swift:13`（`strip.align` 默认 `right`）；`StripPanelController.swift:117–121`（left / center / right）；注意：改设置后不会立刻重新定位（`render` 里只有画布尺寸变了才 `reposition`），见缺口 | 只读代码 | ✓(无专门测试) |
| U16 | 7.1 桌面宠物条 | 地上画一层抖动的影子 | `SeatRenderer.swift:39–41`（桌下 / 椅下 `floor.gap` 抖动填充，所有场景共用） | 看图 [Q] strip41：椅子下有抖动的暗色影子 | ✓ |
| U17 | 7.1 桌面宠物条 | 窗口层级默认 `.floating`，可以改成桌面层级 | `StripPanelController.swift:127–131` `applyLevel`（`strip.level` = desktop 时 `desktopIconWindow + 1`）；设置页「层级」 | 只读代码 | ✓(无专门测试) |
| U18 | 7.1 桌面宠物条 | `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`；全屏桌面空间里默认不显示 | `StripPanelController.swift:131–133`（`strip.fullscreen` 默认 false，只有打开才加 `.fullScreenAuxiliary`） | 只读代码 | ✓(无专门测试) |
| U19 | 7.1 桌面宠物条·点穿 | 每秒 30 次读 `NSEvent.mouseLocation`；鼠标离得超过 100 pt 降到 10 次 | `StripPanelController.swift:60–75`（30 Hz 定时器；`insetBy(−100,−100)` 之外每 3 次只做 1 次 = 10 Hz） | 只读代码；`--self-test` 里 `DebugTools.panelsSelfTest` 测「在人身上拦截 / 空处点穿 / 远处点穿」（DESIGN §9 M2 记 PASS），频率没测 | ✓(无专门测试) |
| U20 | 7.1 桌面宠物条·点穿 | 对象 ID 缓冲做命中测试，外扩 1 像素，据此切换 `ignoresMouseEvents` | `Canvas.swift:119` `hitID(dilate:)`（8 邻域外扩 1 个美术像素）；`StripPanelController.swift:79–89` `evaluate` | `RT.personPixelsCarryTheirSeatIDAndTheWallCarriesNone`（人的像素带座位 ID、墙没有）；`--self-test` 的 `panelsSelfTest`（外扩后仍为 0 的空处才算「点穿」） | ✓ |
| U21 | 7.1 桌面宠物条·点穿 | `acceptsFirstMouse = true`，点一下不会把 App 激活 | `PixelView.swift:52`；`FloatingPanel` 是 nonactivating | DESIGN §2 M0 第 1 项（真实点击日志 `CLICK … appActive=false`）；无自动化测试 | ✓(无专门测试) |
| U22 | 7.1 桌面宠物条·点穿 | 不需要辅助功能权限 | 只用 `NSEvent.mouseLocation`；grep `AXIsProcessTrusted / CGEventTap / addGlobalMonitor` 无结果 | 我 grep 了 `Sources/` | ✓ |
| U23 | 7.1 桌面宠物条·交互 | 悬停 250 ms 出卡片（三个面都一样） | `StripPanelController.swift:92–97`、`TankPanelController.swift:97–103`、`OfficeWindowController.swift:97–101` | 只读代码 | ✓(无专门测试) |
| U24 | 7.1 桌面宠物条·交互 | 左键点击跳到会话 | `StripPanelController.swift:34–37`（`onClick` → `AppModel.jump(seat:)`）；小鱼缸 / 办公室同样接到 `jump` | 只读代码 | ✓(无专门测试) |
| U25 | 7.1 桌面宠物条·交互 | 右键菜单：跳转、换个造型、隐藏这个 buddy、打开办公室 | `AppModel.swift:259–274` `showContextMenu`（四项都有，另有「显示被隐藏的 buddy」「设置…」） | 只读代码；「换个造型」的一致性问题见疑点 | ✓(无专门测试) |
| U26a | 7.1 宠物条·多屏 | 可以选主屏幕 | `StripPanelController.swift:102–108`（默认 `screens.first`）；设置页「主屏幕」 | 只读代码 | ✓(无专门测试) |
| U26b | 7.1 宠物条·多屏 | 可以选鼠标所在的屏幕 | `StripPanelController.swift:105`（`strip.screen == "mouse"`）；设置页「鼠标所在的屏幕」——只在 `reposition()`（画布尺寸变 / 屏幕参数变）时取一次，不会跟着鼠标走；改设置也不会立刻重新定位 | 只读代码 | ✓(无专门测试) |
| U26c | 7.1 宠物条·多屏 | 指定某块屏幕（按 ID 和名字记住） | 代码只认 `id:<NSScreenNumber>`（`StripPanelController.swift:106`），没用名字；设置页只有「主屏幕」「鼠标所在的屏幕」两个选项，没有让用户挑某块屏幕的入口 | 读代码和 `SettingsView.swift:61`；DESIGN 没记 | 缺失 |
| U27 | 7.1 宠物条·多屏 | 监听 `didChangeScreenParametersNotification` | `StripPanelController.swift:42,52`（→ `reposition`） | 只读代码 | ✓(无专门测试) |
| U28 | 7.1 宠物条·多屏 | 每 2 秒检查一次 `visibleFrame`（Dock 移动 / 改变大小） | 没有这个定时器：`reposition()` 只在画布尺寸变化和屏幕参数通知时调用（`:154`、`:52`）；Dock 大小 / 位置变了而屏幕参数没变时，宠物条不会跟着挪 | 全仓库 grep `visibleFrame` 只在 `reposition` 和小鱼缸里；DESIGN 没记 | 缺失 |
| U29 | 7.1 宠物条·多屏 | 所在屏幕被拔掉时回到主屏幕 | `StripPanelController.swift:107`（找不到 `id:` 的屏幕 → `screens.first`）＋ `:52` 屏幕参数通知触发重新定位 | 只读代码 | ✓(无专门测试) |
| U30 | 7.1 菜单栏 | 图标是 18 pt 像素模板图，有「正常 / 有人在忙」两种 | `Sources/BuddyArt/Icons/MenuBarIcon.swift`（18×18 美术像素，2 倍最近邻成 36 px 当 18 pt）；`StatusItemController.swift:27–37`（`isTemplate = kind != .waiting`） | 看图 [T]（我按代码里的字符行重绘：一台显示器 + 人的半身像；忙的那张显示器里多了文字行；模板图只用黑色 + 透明，深色菜单栏里应反白）；真实菜单栏里的效果没看到 | ✓(无专门测试) |
| U31 | 7.1 菜单栏 | 有人等你时换成彩色的举手图标，不做成模板图 | `StatusItemController.swift:29–34`（`waiting > 0` → `.waiting`，`isTemplate = false`） | 看图 [T]（黄色屏幕带「!」、橙色衣服、举起的手）；`--log-ui` 会打印 `菜单栏图标=waiting`（DESIGN §8 记录通过） | ✓(无专门测试) |
| U32 | 7.1 菜单栏·菜单 | 每个 buddy 一行：状态图标、标题、当前动作，点击跳转 | `StatusItemController.swift:40–53`（用 emoji 当状态图标：等你＝举手的人 / 忙＝键盘 / 有未读＝小旗 / 空闲＝咖啡杯；标题 + `PlateCopy.activity`；点击 `onJump`；没人时显示「今天还没人上班」） | 只读代码 | ✓(无专门测试) |
| U33 | 7.1 菜单栏·菜单 | 开关：办公室窗口 / 小鱼缸 / 桌面宠物 / 菜单栏图标 / Dock 图标 | `StatusItemController.swift:55–64`（五项，打勾状态取自设置） | 只读代码 | ✓(无专门测试) |
| U34 | 7.1 菜单栏·菜单 | 演示模式（看看所有动作） | `StatusItemController.swift:66–68` → `AppModel.swift:276` `setDemo`（换成 `MockSource`，跳转在演示里只写日志） | 演示剧本本身有金图 / 闪烁扫描；开关只读代码 | ✓(无专门测试) |
| U35 | 7.1 菜单栏·菜单 | 设置… / 退出，顺序：buddy 行 → 开关 → 演示模式 → 设置 → 退出 | `StatusItemController.swift:54–70`（分隔线位置与规格一致） | 只读代码 | ✓(无专门测试) |
| U36 | 7.1 Dock | 默认显示 Dock 图标；隐藏时切换成 `.accessory` | `AppModel.swift:129`（`dockOn ? .regular : .accessory`）；`Settings.swift:14`（`ui.dockIcon` 默认 true） | 只读代码 | ✓(无专门测试) |
| U37 | 7.1 Dock | 所有入口里至少要保留一个可见 | `AppModel.swift:128`（五个入口全关时强制 `dockOn = true`）。注意：设置页里那个开关仍显示「关」，与实际不符 | 只读代码 | ✓(无专门测试) |
| U38 | 7.1 Dock | 从 Dock 重新打开 App 时显示办公室窗口 | `AppDelegate.swift:118` `applicationShouldHandleReopen`（`showOffice` + `office.visible = true`） | 只读代码 | ✓(无专门测试) |
| U39 | 7.1 Dock（可选） | 全局快捷键 ⌃⌥⌘B 开关办公室窗口，不需要辅助功能权限 | `SystemHelpers.swift:46–66` `HotKey`（Carbon `RegisterEventHotKey`，⌃⌥⌘B）；`Settings.swift:19` `hotkey.enabled` 默认 false；`AppModel.swift:135`、`--test-hotkey` | DESIGN §8「全局快捷键」：`RegisterEventHotKey` 返回成功；没法真的按键。我没有跑 | ✓(无专门测试) |
| U40 | 7.1 Dock（可选） | Dock 图标里显示实时的迷你画面（最多每秒 2 帧） | 没做 | DESIGN §10「已知限制」最后一条与汇总表「Dock 图标里显示实时的迷你画面（可选）」（理由：Dock 角标 + 弹跳 + 菜单栏举手 + 场景气泡够用，且多一路渲染占 CPU 预算） | N/A（任务书标了「可选」；DESIGN §10 记录） |

**补充核对：6.2「空办公室」牌子（最近补上的，和 7.1 的窗口 / 小鱼缸相关）**

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| U41a | 6.2 空办公室（补充） | 一个会话都没有时，办公室里显示一块牌子「今天还没人上班」 | `OfficeScene.swift:85` `signText`、`:89` `signGeometry`（摆在最后一张桌子后面那个空格子的地毯上；正好排满一整排时摆视口正中）、`:99` `drawSign`（深色胡桃木 + 浅色字，和下班工位的桌牌同款）；`render` 里 `signZoom`（`present` 和 `dormant` 都空才有） | `RT.emptyOfficeAndTankShowTheNobodyIsInSign`（空 → 有牌子；来 2 个人 → 没有；只剩下班工位 → 没有；人走光 → 又回来）；`RT.retainedRenderingMatchesFullRedrawWithNobodyAtAll`；看图 [R] officeempty：牌子在第 5 格地毯上，中文清晰 | ✓ |
| U41b | 6.2 空办公室（补充） | 小鱼缸里同样显示 | `TankScene.swift:51` `signRect`（地板正中）、`render(… emptySign:)` | 同上测试（小鱼缸部分）；看图 [R] tankempty | ✓ |
| U41c | 6.2 空办公室（补充） | App 刚启动、第一批数据到来之前不显示（否则每次启动先闪一下） | `AppModel.swift:26,50`（`gotData`）→ `OfficeWindowController.swift:95`、`TankPanelController.swift:69`（`emptySign = model.gotData`） | `RT.emptyOfficeAndTankShowTheNobodyIsInSign`（`emptySign = false` 时办公室和小鱼缸都不出牌子） | ✓ |
| U41d | 6.2 空办公室（补充） | 牌子随缩放保持清晰（文字按设备分辨率渲染，牌子按文字宽度和倍数定大小）；宠物条没有这块牌子 | `OfficeScene.signGeometry`（`ceil(文字宽 / 倍数) + 16`）；宠物条空的时候只有一个 56×140 的全透明画布 | 看图 [R] stripempty（整块透明，鼠标全部穿过）；菜单栏菜单在没人时显示灰色的「今天还没人上班」（`StatusItemController.swift:44`） | ✓ |

## 4. 任务书 7.2 提醒

`AlertCoordinator`（判定）、`NotificationService`（系统通知 + 提示面板兜底）、`ToastController`（像素提示面板）、`SoundSynth`（提示音）、`SystemHelpers.DockTileController`（Dock 角标 / 弹跳）都在 `Sources/BuddyOffice/`，**没有单元测试**；`ToastCard` 在 `Sources/BuddyStage/`。判定逻辑只看快照的变化（DESIGN §11 小决定），所以理论上可以喂假快照测，但目前没人测。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| N01 | 7.2 触发 | 等批准 / 提问 / 计划待审：连续等待满 1.5 秒后提醒 | `AlertCoordinator.swift:50–57`（`Episode.since`，`now − since >= 1.5` 才 `post`；等待种类变了重新计时） | 无测试（`PF` 测的是 0.4 s 转身，不是这条） | ✓(无专门测试) |
| N02 | 7.2 触发 | 默认全开 | `Settings.swift:15–16`（`notify.permission / question / finished` 默认 true） | 只读代码 | ✓(无专门测试) |
| N03 | 7.2 触发 | 做完了：这一轮用时 ≥ 30 秒并且没有被打断 | `AlertCoordinator.swift:76–80`（只在 `.finished` 时，被打断是另一个 `Activity`；`d >= notify.finishedMinSeconds`，默认 30，设置页可调 5–600） | 只读代码 | ✓(无专门测试) |
| N04 | 7.2 触发 | 桌面会话最多等 4 秒看 postTurnSummary，是 blocked 就改成「需要你处理」 | `AlertCoordinator.swift:81–90`：桌面会话等 **8 秒**（`wait = origin == .desktop ? 8 : 0`），`s.blocked` 时发 `.blocked`「需要你处理」 | 理由：本轮总结实测约 7 秒后才落盘 | 偏离（DESIGN §10 汇总表「桌面会话「做完了」最多等 4 s 看 blocked → 等 8 s」；§11 小决定） |
| N05 | 7.2 触发 | 出错：默认关闭 | `Settings.swift:16` `notify.error = false`；`AlertCoordinator.swift:93–95` | 只读代码 | ✓(无专门测试) |
| N06 | 7.2 不打扰 | 桌面会话：Claude.app 在最前面，且这个会话的 `lastFocusedAt` 是所有会话里最新的 → 不提醒 | `AppModel.swift:238–243` `isUserLooking`（前台 bundle id = `com.anthropic.claudefordesktop` 且 `DesktopMeta.isMostRecentlyFocused(host:)`，`JumpService.swift:172`）；`AlertCoordinator.swift:59,85`（受 `notify.suppressWhenFocused` 控制） | 只读代码 | ✓(无专门测试) |
| N07a | 7.2 不打扰 | 终端会话：所在 App 在最前面，先等 8 秒再判断一次要不要提醒（等待类提醒） | `AlertCoordinator.swift:59–61`（第一次看到「在看」→ `deferredUntil = now + 8`；到点再 `isLooking`，还在看就整段等待都不提醒）；`AppModel.swift:245–247`（宿主 App = 父进程链上的 App） | 只读代码 | ✓(无专门测试) |
| N07b | 7.2 不打扰 | 同上（「做完了」提醒） | `AlertCoordinator.swift:81–90`：`wait` 对终端会话是 0，`isLooking` 立刻判断，在看就直接不提醒，没有「8 秒后再判断一次」 | 读代码；DESIGN 没记 | 偏离-未记录 |
| N08 | 7.2 节流 | 同一个 buddy 的同一类提醒，20 秒内最多一条 | `AlertCoordinator.swift:101–105` `throttle`（键 = `<key>\|<等待种类>` / `\|finished` / `\|error`） | 只读代码 | ✓(无专门测试) |
| N09 | 7.2 节流 | 2 秒内同时出现的几条合并成一条，比如「3 位同事在等你」 | `AlertCoordinator.swift:107–119`（2 秒窗里 ≥ 2 个不同 buddy → 先 `.clear` 各自的，再发 key `multi` 的「N 位同事在等你」）。第一条其实已经先弹出来了，再被撤掉换成合并的 | 只读代码 | ✓(无专门测试) |
| N10 | 7.2 通知的维护 | 通知 identifier 用 `buddy.<key>`，新的通知直接替换旧的 | `NotificationService.swift:44`（`UNNotificationRequest(identifier: "buddy.\(key)")`）；提示面板同 key 也是替换（`ToastController.swift:25`） | 只读代码 | ✓(无专门测试) |
| N11 | 7.2 通知的维护 | 状态解除后，把已经送达的通知撤掉 | `AlertCoordinator.swift:67–69`（`.clear`）→ `NotificationService.swift:56–59`（`removeDeliveredNotifications` + 提示面板收回） | 只读代码 | ✓(无专门测试) |
| N12 | 7.2 通知的维护 | 点击通知 → 跳转到对应会话（key 放在 userInfo 里） | `NotificationService.swift:42`（`userInfo["buddyKey"]`）、`:63–66`（`didReceive` → `onClick`）→ `AppModel.swift:92`（按 key 找到快照 → `jump`）；提示面板点击同 `ToastController.swift:32` | 只读代码 | ✓(无专门测试) |
| N13 | 7.2 文案 | 「想用 Bash：git push（等你批准）」 | `AlertCoordinator.swift:121–128`（`想用 <工具>` + Bash 时 `：<前 1–2 个词>` + `（等你批准）`；没有工具名时「有个权限请求（等你批准）」） | `PC.shortCommandKeepsTheFirstWordsAndDropsCdPrefixesAndOptions` 只测缩写；整句组装无测试 | ✓(无专门测试) |
| N14 | 7.2 文案 | 「有个问题要问你」 | `AlertCoordinator.swift:129`（计划待审「计划好了，等你看」、其他「在等你」） | 只读代码 | ✓(无专门测试) |
| N15 | 7.2 文案 | 「做完了（用时 3 分 12 秒）」 | `AlertCoordinator.swift:87`（`做完了（用时 \(PlateCopy.spoken(…))）` → 「3分12秒」，数字和单位之间没有空格） | `PC.fileNamesClipsAndDurations`（`spoken(192) == "3分12秒"`）；整句无测试 | ✓(无专门测试) |
| N16 | 7.2 文案 | 隐私模式下隐藏细节 | `AlertCoordinator.swift:49,124`（标题「会话」，正文不带工具 / 命令） | `PC.privacyModeNeverLeaksDetails` 只测桌牌文案；通知这一路无测试 | ✓(无专门测试) |
| N17 | 7.2 系统通知 | 只有 `bundleURL.pathExtension == "app"` 且有 bundle id 才调 `UNUserNotificationCenter`，否则裸跑的可执行文件会崩 | `NotificationService.swift:11` `available`，`:15,20,27,57` 都先判断 | 只读代码 | ✓(无专门测试) |
| N18 | 7.2 系统通知 | ad-hoc 签名 App 从 `~/Applications` 经 LaunchServices 启动一次后应该能用系统通知，M0 要实际测 | DESIGN §2 M0 第 2 项：API 可用，授权框里用户点了拒绝 → `denied`；因此走兜底，设置页显示授权状态并给「打开系统通知设置」按钮（`SettingsView.swift:84–89`） | 只有 DESIGN 里的实测记录，我没重测 | ✓(无专门测试) |
| N18b | 7.2 系统通知 | 系统通知要能用（授权要在某个时刻主动请求） | `NotificationService.swift:27` `requestAuthorizationIfNeeded` 只被两处调用：设置页「请求通知授权」按钮（`SettingsView.swift:86`）和「发一条测试提醒」（`AppModel.swift:300`）。DESIGN §2 M0 第 2 项写的是「授权请求放到用户第一次主动打开办公室窗口 / 点设置里的开关的时候发」，但 `showOffice` / `showSettings` 只调 `notifier.refresh()`（读状态）不请求；全新安装的用户不点那个按钮就永远收不到系统通知（只有兜底面板） | grep `requestAuthorization`（3 处，上面两处 + 定义）；当前这台机器是「已拒绝」，所以没有可见后果 | 偏离-未记录 |
| N19 | 7.2 兜底 | Dock 角标显示正在等你的人数 | `SystemHelpers.swift:9–12`（`badgeLabel = "\(waiting)"`）；`AppModel.swift:218–221` | `--log-ui`（DESIGN §8：演示走到「等批准」时 Dock 角标 `1`，结束后恢复）；我没重跑 | ✓(无专门测试) |
| N20a | 7.2 兜底 | `requestUserAttention(.informationalRequest)` 让 Dock 图标弹一下 | `SystemHelpers.swift:12`（`newlyWaiting && !NSApp.isActive`） | 只读代码 | ✓(无专门测试) |
| N20b | 7.2 触发（1.5 秒） | 等待满 1.5 秒后才提醒（规格没明说 Dock 弹跳 / 角标 / 菜单栏图标这类兜底要不要也等） | `AlertCoordinator.swift:53`：`newlyWaiting = true` 在等待一开始就置位，所以 Dock 弹跳、角标、菜单栏举手图标在 0 秒就出现；只有弹窗 / 系统通知 / 提示音等满 1.5 秒（`:57`）。一闪而过的等待会让 Dock 图标弹一下 | 读代码 | 偏离-未记录 |
| N21 | 7.2 兜底 | 场景里的气泡 | `Performer.swift:191–194`（钥匙 / 「?」/ 写字板气泡） | 看图 [B]（S18c / S19c / S20c） | ✓ |
| N22 | 7.2 兜底 | 菜单栏图标变成举手 | `AppModel.swift:218–220` → `StatusItemController.swift:29`（`waiting > 0` → `.waiting`） | `--log-ui`（DESIGN §8：`菜单栏图标=waiting`）；图标画法见 U31 | ✓(无专门测试) |
| N23a | 7.2 兜底 | 授权被拒就改用像素提示面板 | `NotificationService.swift:46–50`；`Sources/BuddyStage/ToastCard.swift`（7 种：等批准 / 提问 / 计划 / 做完了 / 需要你处理 / 出错 / 提示，像素边框 + 图标 + 苹方文字） | 看图 [O] 前 9 张（文字不溢出；长标题用省略号）；DESIGN §8 记录 `toast.show` 8–25 ms | ✓ |
| N23b | 7.2 兜底 | 从右上角弹簧滑入 | `ToastController.swift:12,36–41,49–53,61–69`（`PixelSpring(value: 60, period: 0.36)`，起点在屏幕外右侧，靠 `visibleFrame` 右上角往下叠，最多 3 张，6 秒后收回，点一下跳转） | 只有 DESIGN §8 的 `--log-ui` 记录；我没看到真实滑入 | ✓(无专门测试) |
| N24a | 7.2 提示音 | 运行时合成 8-bit WAV 数据，不需要外部文件；可以设置成无 / 系统提示音 / 8-bit | `SoundSynth.swift:8–36`（方波琶音，22050 Hz、8 位）、`:55–66` `play(mode:)`（none / system=`NSSound.beep` / 8bit）；`Settings.swift:16` 默认 8bit；`SettingsView.swift:81` | 只读代码 | ✓(无专门测试) |
| N24b | 7.2 提示音 | 用 `NSSound(data:)` 播放 | 实际是专门的后台串行队列 + `AVAudioPlayer`（`SoundSynth.swift:40–52`，启动 3 秒后预热） | 理由：`NSSound.play()` 首次调用卡主线程 220–270 ms | 偏离（DESIGN §10 汇总表「提示音 `NSSound(data:)`」；§8「提示音」行） |
| N25 | 7.2 重复提醒 | 设置里加一项「桌面 App 会话也提醒」，默认开着，在使用说明里讲清楚 | `Settings.swift:16` `notify.includeDesktop = true`；`SettingsView.swift:79`；`AlertCoordinator.swift:56,77`；`使用说明.txt:119` | 我读了使用说明：写明「Claude 桌面 App 自己也可能发系统通知，可能和这里的提醒重复；不想重复就在「设置 → 提醒」里关掉…」 | ✓ |

## 5. 任务书 7.3 点 buddy 跳到会话（JumpService）

`Sources/BuddyOffice/JumpService.swift`。所有入口（办公室 / 小鱼缸 / 宠物条 / 菜单栏 / 通知 / 提示面板）都走 `AppModel.jump(snapshot:)`（L252–257），跳转后 `provider.markSeen` 清未读。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| J01 | 7.3 桌面 App 会话 | 等你时 `claude://code/needs-input?session=<hostSessionId>`，其他时候 `claude://code/continue?session=…`，都用 `NSWorkspace.shared.open` | `JumpService.swift:31–37`（`s.activity.needsUser ? "needs-input" : "continue"`） | DESIGN §2 M0 第 4 项（用自己所在会话实测：`open` 返回 true，Claude 主日志出现 `Warming up session`）；§8 `--test-jump`（链接发出）；无自动化测试 | ✓(无专门测试) |
| J02 | 7.3 桌面 App 会话 | session 参数必须匹配 `^local_[A-Za-z0-9-]{1,64}$` | `JumpService.swift:18–20` `validHostID`（不合法就改为直接激活 Claude，`:32`） | `--test-jump` 日志里打印 `valid=`；无自动化测试 | ✓(无专门测试) |
| J03 | 7.3 桌面 App 会话 | 跳完 2.5 秒内 `lastFocusedAt` 没变 → 没跳成功，改为直接激活 Claude | `JumpService.swift:38–53`：2.5 秒后比较 before / after；**目标本来就是 `lastFocusedAt` 最新的会话时不算失败**（`wasLatest`） | 理由：连点当前会话会误把深链停用（M0 实测） | 偏离（DESIGN §2 M0 第 4 项；§10 汇总表「深链失败判据「2.5 s 内 lastFocusedAt 没变」」；§11 小决定） |
| J04 | 7.3 桌面 App 会话 | 连续失败 2 次后，停用深链，并给出提示 | `JumpService.swift:44–51`（`deepLinkFailures >= 2` → `deepLinkDisabled = true` + `onNotice`）；`AppModel.swift:93`（提示 = 像素提示面板 `.info`）；设置 → 数据源诊断 →「重新启用深链」（`SettingsView.swift:118`） | 只读代码。注意：提示卡单行 220 pt 宽，看图 [O] `toast info` 显示成「深链跳转没有生效，已改为直接打开 Clau…」，真实文案更长，「可在设置 → 数据源诊断里重新测试」那半句看不到，见疑点 | ✓(无专门测试) |
| J05 | 7.3 终端里的会话 | 沿父进程链往上找宿主 App，最多 12 层；跳过 bundle id 是 `com.anthropic.claude-code` 的 CLI 包，也跳过纯后台的 App | `JumpService.swift:95–104` `hostApp(of:)`（`for _ in 0..<12`、`activationPolicy == .regular`、bundle id 过滤） | `--probe-pid <pid>` 启动参数（DESIGN §8：`hostApp(of:)` 沿父进程链找宿主，函数级验证）；无自动化测试 | ✓(无专门测试) |
| J06 | 7.3 终端里的会话 | Terminal：用 sysctl 读 `kp_eproc.e_tdev`，再用 `devname()` 得到 tty | `JumpService.swift:133–148` `ProcessInfoHelper.ttyName` | DESIGN §8：对一个 pty 子进程返回的 tty 和 `ps` 一致；无自动化测试 | ✓(无专门测试) |
| J07 | 7.3 终端里的会话 | 跳转队列里跑 AppleScript：按 `tty of tab` 找到标签页、选中、窗口提到最前、取消最小化、激活 Terminal | `JumpService.swift:106–129` `selectTerminalTab`（`set selected of tb to true`、`set miniaturized of w to false`、`set index of w to 1`、`activate`，串行队列里执行，结束后再 `activate(appAt:)`） | DESIGN §2 M0 第 6 项（临时 Terminal 窗口实测通过）；现 App 身份下的自动化授权没答复，端到端没再跑（§8「终端跳转」） | ✓(无专门测试) |
| J08 | 7.3 终端里的会话 | 其他宿主就直接激活那个 App | `JumpService.swift:87–89` | 只读代码（这台机器没有 iTerm，DESIGN §10） | ✓(无专门测试) |
| J09 | 7.3 VS Code 里的会话 | `NSWorkspace.open([cwd], withApplicationAt: VS Code)` | `JumpService.swift:70–76`（没有 cwd 时直接激活 VS Code） | 只读代码（没有 VS Code 的 Claude 扩展，DESIGN §10） | ✓(无专门测试) |
| J10 | 7.3 激活的坑 | 改用 `NSWorkspace.openApplication(at:configuration:)`，设置 `activates = true` | `JumpService.swift:63–67`（所有激活都走它） | DESIGN §2 M0 第 5 项（从非激活状态实测：这个 API 能把 Terminal 拉到最前；`NSRunningApplication.activate()` 对 Claude 返回 false） | ✓(无专门测试) |
| J11 | 7.3 自动化授权 | Info.plist 里有 `NSAppleEventsUsageDescription`，文案「点小人跳转到「终端」里对应的标签页时才会用到。」 | `scripts/build-app.sh:47` | 我用 `plutil -p` 读了已装 App 的 `Info.plist`：这个键的值和规格逐字一致 | ✓ |
| J12 | 7.3 自动化授权 | ad-hoc 签名每重新编译一次系统会再问一遍自动化授权，要写进使用说明 | `使用说明.txt:118`「「自动化」授权在重新编译（重新安装）之后会再问一次。」；`:34`、`:140` | 我读了使用说明 | ✓ |
| J13 | 7.3（总述） | 点 buddy 跳到那个会话；跳完清未读 | `AppModel.swift:252–257`（`JumpService.jump` + `provider.markSeen`）；办公室 / 小鱼缸 / 宠物条的 `onClick`、菜单栏、通知、提示面板都接到它 | 只读代码；`--test-jump <hostSessionId>` 对我自己的会话发出深链且没被判失败（DESIGN §8，「测的时候屏幕停在登录窗口，看不到前台切换」） | ✓(无专门测试) |

## 6. 任务书 7.4 跟着 Claude 一起开、一起收

`scripts/hook-merge.py`（`Tests/hook_merge_test.py` 有 13 个测试，我跑了，全过）和 `Sources/BuddyOffice/SystemHelpers.swift` 的 `AutoQuit`（无测试）。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| F01 | 7.4 自动打开 | 在 `~/.claude/settings.json` 的 `hooks.SessionStart` 数组**追加**一个 matcher 组（`startup\|resume`，type command，timeout 5），原有 ccmon 组一个都不动 | `scripts/hook-merge.py:20` `GROUP`；`install` 追加到 `SessionStart` 数组末尾并保留其余所有键 | `HM.test_install_appends_one_group_and_keeps_everything_else`（断言 matcher、command、timeout、ccmon 组原样、其他键原样）；我运行了 `python3 Tests/hook_merge_test.py`（用了 `PYTHONDONTWRITEBYTECODE=1`，只写临时目录）：13 个全过 | ✓ |
| F02 | 7.4 自动打开 | 命令 `pgrep -xq BuddyOffice \|\| open -g -b local.buddy-office >/dev/null 2>&1; exit 0`：App 已经在运行时什么都不做 | `hook-merge.py:19` `COMMAND`（与规格逐字相同） | `HM` 上面那条断言整串命令；DESIGN §9.1（沙箱外真的触发：App 没运行时被拉起、已运行时再触发不多开，`pgrep` 里始终只有一个进程） | ✓ |
| F03 | 7.4 自动打开 | `-g` 让 App 在后台打开，不抢焦点 | `COMMAND` 里的 `open -g` | `HM` 断言命令里有 `open -g`；「没抢焦点」只有 DESIGN §9.1 的实测记录 | ✓(无专门测试) |
| F04 | 7.4 自动打开 | 输出必须全部丢掉（SessionStart 的 stdout 会被塞进 Claude 的上下文） | `COMMAND` 末尾 `>/dev/null 2>&1; exit 0`；`pgrep -q` 本身不输出 | `HM` 断言整串命令；DESIGN §9.1：hook 输出里没有任何多出来的东西（`claude -p "ok"` 因终端版 CLI 的 OAuth 登录过期失败，但 hook 在那之前已触发；没看到成功的回答，DESIGN §10 汇总表最后一行） | ✓ |
| F05 | 7.4 自动打开 | 官方文档确认 SessionStart 在桌面 App / 终端 / VS Code 里都会触发；只对之后新开的会话生效 | （说明性文字，没有可测要求） | — | N/A（背景说明，不是实现要求） |
| F06 | 7.4 自动收起 | 监听 `NSWorkspace.didTerminateApplicationNotification`；Claude（`com.anthropic.claudefordesktop`）退出且登记表里没有活着的 interactive 会话时，60 秒后自动退出 | `SystemHelpers.swift:20–37` `AutoQuit`（`terminated` → `scheduleQuit(after: 60)`；到点 `isEnabled() && !hasLiveSessions()` 才 `NSApp.terminate`）；`JumpService.swift:16` `claudeBundleID`；`AppModel.swift:94–96` | `--test-autoquit N` 启动参数（假装 Claude 刚退出；DESIGN §8 / §9.1 记录：没有会话 → N 秒后退出、有一个活会话 → 不退、会话进程结束 → 退出）；我没重跑，没有自动化测试 | ✓(无专门测试) |
| F07 | 7.4 自动收起 | 这 60 秒里如果有会话出现，或者 Claude 重新打开了，就取消退出 | `SystemHelpers.swift:39–41`（Claude 重新启动 → 取消定时器）；「会话出现」靠到点时再查一次 `hasLiveSessions`（`:33`）。注意：`hasLiveSessions = !present.isEmpty`，而 `present` 已经剔除了用户「隐藏的 buddy」（`AppModel.swift:58,95`） | 只读代码；隐藏边界见疑点 | ✓(无专门测试) |
| F08 | 7.4 自动收起 | 设置里可以关掉这个行为 | `Settings.swift:19` `autoQuitWithClaude` 默认 true；`SettingsView.swift:105`；`AppModel.swift:94` | 只读代码 | ✓(无专门测试) |
| F09 | 7.4 启动时的样子 | App 按上次用的形态出现，这个状态记在 UserDefaults 里 | `AppModel.swift:109` `applySettings(initial: true)` 读 `office/tank/strip.visible`；关窗口（`OfficeWindowController.swift:68`）、标题栏按钮、菜单、右键菜单都会写回这三个键 | 只读代码；`--test-titlebar` 日志里可见键随操作变化 | ✓(无专门测试) |

## 7. 任务书 7.5 设置与诊断

`Sources/BuddyOffice/Settings.swift`（键 + 默认值）、`SettingsView.swift`（SwiftUI 表单，4 页：形态 / 提醒 / 其他 / 数据源诊断）。`--dump-settings PREFIX` 逐页浅 / 深色渲染成 PNG（DESIGN §8：亲眼看过，「标签条在离屏渲染里选中项文字显示为空白」是离屏假象）；我没有运行 GUI，所以没重看。

| 编号 | 任务书位置 | 要求（缩写，保留关键数字） | 实现（文件:函数或行号） | 验证它的测试或证据 | 状态 |
|---|---|---|---|---|---|
| C01 | 7.5 设置窗口 | NSWindow + `NSHostingController(SettingsView)`，里面是 SwiftUI Form | `SettingsView.swift:128–137`（`NSWindow(contentViewController: NSHostingController(rootView: SettingsView(...)))`，`.titled .closable`）；表单 `:44–126`（`TabView` + `Form(.grouped)`） | DESIGN §8 `--dump-settings`；无自动化测试 | ✓(无专门测试) |
| C02 | 7.5 配置项·办公室 | `office.visible`、`office.zoom`（0 = 自动） | `Settings.swift:11`；`SettingsView.swift:48–49`（开关 + 自动 / 1–5 倍）；接线 `AppModel.applySettings`、`OfficeWindowController.swift:82,86`（`OfficeLayout.effectiveZoom`） | 只读代码 | ✓(无专门测试) |
| C03 | 7.5 配置项·小鱼缸 | `tank.visible`、`tank.zoom`、`tank.opacity` | `Settings.swift:12`；`SettingsView.swift:53–55`；接线 `TankPanelController.swift:61–66`（缩放 1–2、不透明度 0.3–1 → `alphaValue`） | 只读代码 | ✓(无专门测试) |
| C04 | 7.5 配置项·桌面宠物 | `strip.visible`、`strip.zoom` | `Settings.swift:13`；`SettingsView.swift:58–59`；`StripPanelController.swift:141–142`（缩放 1–3） | 只读代码 | ✓(无专门测试) |
| C05 | 7.5 配置项·桌面宠物 | `strip.screen` | `Settings.swift:13`；`SettingsView.swift:61`（只有「主屏幕」「鼠标所在的屏幕」两项；代码另认 `id:`，见 U26c） | 只读代码 | ✓(无专门测试) |
| C06a | 7.5 配置项·桌面宠物 | `strip.level`、`strip.fullscreen` | `SettingsView.swift:62–63`；`StripPanelController.swift:127–133`（设置变化时 `applyLevel` 立即应用） | 只读代码 | ✓(无专门测试) |
| C06b | 7.5 配置项·桌面宠物 | `strip.align`（改了应当马上生效） | `SettingsView.swift:60`；`StripPanelController.swift:117–121`。注意：设置变化时 `render` 只重读缩放和层级（`:140–143`）并更新 `scene.alignRight`（`:147`），**不重新定位窗口**：`strip.align` / `strip.screen` 改了以后，窗口留在原地，只有画布尺寸变（人数 / 缩放变）或屏幕参数通知才会挪；靠右 / 靠左时槽位顺序却立刻翻了 | 读代码（对照 `StripPanelController.render` 与 `reposition` 的调用点） | 偏离-未记录 |
| C07 | 7.5 配置项·界面 | `ui.menuBarIcon`、`ui.dockIcon`、`ui.labels`（总是 / 悬停 / 关闭） | `Settings.swift:14`；`SettingsView.swift:50,66–67`；接线 `AppModel.applySettings`、`OfficeWindowController.swift:83`、`OfficeScene.swift`（`plateTexts` 的 `labels` 判断，`RT` 没测标签模式） | 只读代码 | ✓(无专门测试) |
| C08 | 7.5 配置项·提醒 | `notify.permission`、`.question`、`.finished`、`.finishedMinSeconds = 30`、`.includeDesktop`、`.suppressWhenFocused`、`.sound`（另有 `.error`） | `Settings.swift:15–16`；`SettingsView.swift:74–81`；接线 `AlertCoordinator.swift:55–56,59,77–85,93`、`NotificationService.post(sound:)` | 只读代码 | ✓(无专门测试) |
| C09 | 7.5 配置项·空闲 | `idle.dozeMinutes = 10`、`idle.sleepMinutes = 45`（设置里可改） | 设置页有两个 Stepper（`SettingsView.swift:96–97`）、默认值有（`Settings.swift:17`），但**没有接到数据层**：`SessionEngine.Options.dozeAfter / sleepAfter` 用硬编码默认（`SessionEngine.swift:15–16`），`RealProvider.make` → `SessionStore(dataRoot:usePolling:persist:)` 不读 UserDefaults，全仓库没有别处传这两个值。改了没有效果 | grep `dozeMinutes / sleepMinutes / dozeAfter / sleepAfter`：只有设置页、默认值、数据层默认；数据层本身支持自定义阈值（`AR.idleThenDozingThenSleepingAtTheThresholds` 用了 `dozeAfter = 60`）；DESIGN / 使用说明都说「设置 → 其他 里可以改」 | 缺失 |
| C10 | 7.5 配置项·下班工位 | `dormant.max = 4` | `SettingsView.swift:100`（Stepper 0–8）；`AppModel.swift:60`（`.prefix(dormant.max)`，只能把数量往小调）；数据层 `dormantMax = 4` 已经卡在 4（`SessionEngine.swift:18`），5–8 没有效果 | 读代码 | 偏离-未记录 |
| C11 | 7.5 配置项·下班工位 | `dormant.recentHours = 3` | `SettingsView.swift:101`（「启动时只显示最近 N 小时内的会话」）、`Settings.swift:18`；数据层 `dormantRecent` 硬编码 3 小时（`SessionEngine.swift:19`），没接线 | 同 C09 | 缺失 |
| C12 | 7.5 配置项·其他 | `privacy.hideDetails` | `SettingsView.swift:104`；接线 `AppModel.swift:78`（`privacy`）→ 桌牌 / 悬停卡 / 通知 / 菜单栏菜单 | `PC.privacyModeNeverLeaksDetails`（桌牌文案不含文件名 / 命令 / 搜索词 / 域名）；卡片与通知两路无测试 | ✓ |
| C13 | 7.5 配置项·其他 | `autoQuitWithClaude = true` | 见 F08 | 见 F08 | ✓(无专门测试) |
| C14 | 7.5 配置项·其他 | `login.enabled = false`、`hotkey.enabled` | `Settings.swift:19`；`SettingsView.swift:68,106`；接线 `LoginItem.set`（`SystemHelpers.swift:72`）、`HotKey`（`AppModel.swift:135`） | 只读代码 | ✓(无专门测试) |
| C15 | 7.5 配置项 | 外观 salt 存在 `identities.json` 里 | `Sources/BuddyCore/Fusion/IdentityResolver.swift:184`（写盘含 `salt`）、`:162` `reroll`（每次 +1） | `IT`：`IdentityTests`（`back.identity.salt == 1`，含「换个造型」的新盐）、`rerollGivesANewSaltEachTime` | ✓ |
| C16 | 7.5 开机启动 | 默认关；优先 `SMAppService.mainApp.register()`，不行写 `~/Library/LaunchAgents/local.buddy-office.plist`（运行 `/usr/bin/open -b local.buddy-office`）；只有用户打开开关才写 | `SystemHelpers.swift:69–92` `LoginItem.set`（先 `register()`，状态 enabled / requiresApproval 才算成；否则写 LaunchAgent，`RunAtLoad`，参数是 `open -g -b local.buddy-office`（比规格多一个 `-g`，无害））；`SettingsView.swift:106` 只在开关变化时调用；`main.swift:4` `--unregister-login` 供卸载脚本 | DESIGN §2 M0 第 3 项、§8「开机启动」：只测了状态（`notFound`），没有真的打开过开关；无自动化测试 | ✓(无专门测试) |
| C17 | 7.5 诊断页 | 活会话数 | `AppModel.swift:288` ← `SessionEngine.diagnostics()`（`SessionEngine.swift:925–935`） | `EnginePresenceTests.diagnosticsReportSourcesAndPerSessionHookState`（`liveSessionCount == 1`） | ✓ |
| C18 | 7.5 诊断页 | 有没有检测到 hook、最后一个事件的时间 | `AppModel.swift:290`（`hookDetectedInSettings`、`lastHookEventAt`） | 同上（`hookDetectedInSettings`）；`EngineScenarioTests`（没装 hook → `hook: 没检测到`） | ✓ |
| C19 | 7.5 诊断页 | 各会话的 Claude Code `version` | `AppModel.swift:291`（每个会话：pid、`v<版本>`、hook 有 / 无） | 数据层：`EnginePresenceTests.diagnosticsReport…`（逐会话 hook 状态）；版本号的显示只读代码 | ✓(无专门测试) |
| C20 | 7.5 诊断页 | 深链测试按钮 | `SettingsView.swift:117–118`（「测试深链（跳到当前会话）」「重新启用深链」）；`AppModel.swift:304` `testDeepLink` | 只读代码 | ✓(无专门测试) |
| C21 | 7.5 诊断页 | 系统通知的授权状态 | `AppModel.swift:292`（`notifier.statusText`）；提醒页同样显示，另有「请求通知授权」「打开系统通知设置」「发一条测试提醒」（`SettingsView.swift:84–89`） | 只读代码 | ✓(无专门测试) |
| C22 | 7.5 诊断页 | 当前用的是哪些数据来源，以及每个的降级状态 | `AppModel.swift:294–295`（逐行列 `sourceStatus`） | `EnginePresenceTests`（`登记表: 正常`、`hook: 正常`、`登记表: 目录读不了`、`token 账本: 写不了磁盘`） | ✓ |

## 8. 缺口

汇总所有「缺失 / 偏离-未记录 / ✓(无专门测试)」，按严重度从高到低。编号对应上面各表。

### 8.1 缺失和偏离-未记录（共 23 条：缺失 8、偏离-未记录 15）

| 严重度 | 编号 | 现象 | 建议 |
|---|---|---|---|
| 高 | S15b | 「其他 MCP」屏幕本该画 server 首字母，`PixelFont.small`（4×6）只有数字和 `M`、`K`、`x`，其余字母落到「?」占位字形：demo 里的 notion 画成「?」。常见的 MCP（例如 `ccd_*`、`scheduled-tasks`、`terminal`、UUID 命名的……）除 M 开头外全是「?」 | 给 4×6 字体补 A–Z（或改用 3×5 的 `tiny` 补全的字母）；`ScreenContent.draw(.mcpApp)` 遇到缺字形时画几何图案而不是「?」；在测试里断言 `PixelFont.small.hasGlyph` 覆盖所有可能的首字母。另一路正在做的 text-audit 已经有 `missingGlyph` 钩子，可以直接加这条 |
| 高 | C09、C11、C10 | 设置页有「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」，但没接到数据层：`SessionEngine.Options` 用硬编码默认（10 / 45 分钟、3 小时、最多 4 个），`RealProvider` 不读 UserDefaults；`dormant.max` 只能往小调（Stepper 到 8，数据层封顶 4）。使用说明也写了这几项可以改 | `RealProvider.make` 读设置填 `Options`；设置变化时热更新（或重建 provider）；补一个「设置 → Options」映射测试。修好之前先把这三项从设置页藏掉，别让界面说谎 |
| 高 | U28、C06b、U26c | 宠物条定位不全：① 规格的「每 2 秒检查 `visibleFrame`」没有（Dock 改大小 / 移动而屏幕参数没变时不会跟着挪）；② 改 `strip.align` / `strip.screen` 后不重新定位（`render` 只在画布尺寸变时 `reposition`，靠右 / 靠左的槽位顺序却立刻翻了）；③ 没有「指定某块屏幕（按 ID 和名字记住）」的入口，代码只认 `id:`、没用名字 | 设置变化时调 `reposition()`；加 2 秒定时器比较 `visibleFrame`；设置页加屏幕列表（存 ID + 名字，找不到按名字匹配再回主屏） |
| 中 | S29b2、M10（M11） | 离场时屏幕在一帧里硬切成黑（看图 [L] t=60.00→60.03；离场前是忙的话会是亮屏直接变黑），台灯开关 / 待机灯 / 屏幕内容切换也都是硬切；规格要 5 级调色板渐变 300 ms 的关机、亮度变化 ≥ 250 ms 渐变。开机是 16 级 Bayer（DESIGN 写的却是「5 级」） | 把开机的 Bayer 过程倒放做关机；台灯 / 屏幕切换用 2–3 级 Bayer 过渡；顺手把 DESIGN §7 的「5 级」改成实际的 16 级 |
| 中 | M08 | 「等待时的光晕」（3 个相邻色阶 0.8 Hz + 1 Hz、2 像素轻弹）整个没做，DESIGN 也没记；等你的时候只有转身举手、气泡、琥珀待机灯 | 在举手的人身后 / 显示器外框加一圈 3 阶琥珀光晕（呼吸，不是开关）；手臂弹簧目标叠加 1 Hz、2 px；更新闪烁扫描白名单 |
| 中 | （5.6 交叉项） | 屏幕内容「4 帧从上往下擦除」、「不同类工具之间先放下道具再开始新动作」、「等待类最多等过渡帧播完 ≤ 250 ms」都没有实现（grep `擦除 / wipe` 无结果，DESIGN 没记）；实际观感是屏幕一帧硬切，桌面道具（便签本、托盘、闹钟）随姿势一起瞬间出现 / 消失。不在我的表里，但直接影响 6.5 的观感 | 由负责 5.6 的工位跟进；实现时 `Performer` 需要一个「过渡帧」状态 |
| 中低 | S22a2、S26a2、S28a、S12a、S08a2、S05b2 | 动作细节缺口：重试没有「轻敲显示器」；blocked 没有「点点便利贴」；未知工具只打字（DESIGN §5 表却写「打字和鼠标交替」，文档和代码不一致）；Skill 没有「翻手册」；WebSearch 没有「先打字再用鼠标」；NotebookEdit 没有单元格屏幕 | 要么补动作，要么在 DESIGN §10 汇总表各记一行「简化 + 理由」；S28a 至少先让文档和代码一致 |
| 低 | M16、M17 | 鼠标不是「2 帧 × 300 ms」而是 ±1 px 的正弦漂移；走路不是「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」而是 1.6 步/秒的连续相位 | 在 DESIGN 里记一条理由（都是取整后逐格离散的，视觉上等价） |
| 低 | S27b2 | 待机灯「缓慢呼吸」只有开 / 关两档，2 秒亮 2 秒灭（`SeatRenderer.swift:176`），是慢速开关而不是渐变 | 加一档暗绿（3 阶）或在 DESIGN 记为已知简化 |
| 低 | M13b | 小鱼缸 / 宠物条先 `orderFront` 再渲染第一帧，小鱼缸可能先露出一帧底色 | `show()` 里先 `render(force:)` 再 `orderFront`（`render` 的 `guard panel.isVisible` 要放开） |
| 低 | N07b、N20b、N18b | ① 终端会话的「做完了」提醒没有「先等 8 秒再判断一次」；② Dock 弹跳 / 角标 / 菜单栏举手图标没有 1.5 秒去抖，一闪而过的等待也会让 Dock 图标弹一下；③ 全新安装不点设置页按钮就永远不会请求系统通知授权（DESIGN §2 写的是首次打开办公室窗口时请求） | ① 复用 `deferredUntil`；② 把 `newlyWaiting` 也放在 1.5 秒之后；③ 首次 `showOffice` 且状态是 `notDetermined` 时请求一次 |

### 8.2 ✓(无专门测试)（共 101 条）

`BuddyOffice` **没有测试目标**，所以 7.1–7.5 的 AppKit 层逻辑整体没有自动化测试（U 32、N 22、J 10、F 5、C 14 = 83 条）；BuddyStage 里姿势 / 屏幕 / 气泡的映射表、弹簧 / 呼吸 / 眨眼只有金图哈希（锁像素，不锁语义）和闪烁扫描（S 9、M 9 = 18 条）。

| 严重度 | 编号 | 缺什么 | 建议 |
|---|---|---|---|
| 高 | N01–N03、N05–N16、N20a、N22、N23b、N24a | 提醒判定（1.5 秒去抖、不打扰、8 秒等待、20 秒节流、2 秒合并、文案）全无测试，而这些恰恰是「时间 + 状态」的组合逻辑、最容易回归。`AlertCoordinator.observe` 只依赖快照、`Settings`、一个 `isLooking` 闭包，可以直接喂假快照 | 加 `BuddyOfficeTests`（`@testable import BuddyOffice`，macOS 上 SwiftPM 支持测试可执行目标）或把 `AlertCoordinator` / `AutoQuit` / `JumpService` 的判据抽到不依赖 AppKit 的库；用假时钟逐条测 N01–N16 |
| 中 | J01、J02、J04–J10、J13、F06–F08 | 深链 URL / 失败判据 / 连续失败停用、终端宿主查找、自动收起的 60 秒逻辑无测试（靠 `--test-jump` / `--test-autoquit` 启动参数和 DESIGN 的记录） | 把 `validHostID`、`deepLink` 成功判据、`AutoQuit` 的定时逻辑抽成纯函数 / 可注入时钟，加单测；GUI 部分（AppleScript 选标签页）列人工验收 |
| 中 | S03a、S07a1、S07a2、S07c、S09a2、S13a、S15a、S23a、S27a2 | 姿势的时间参数（Bash 3 / 8 秒、喝水 22 秒一圈、深度思考 20 秒、打盹点头）和「动作是不是画对了」没有断言 | 表驱动测试：给 `Performer` 喂 `(Activity, 时间)` 断言 `pose / screen / bubble / plate` 四元组；再加一个「姿势 → 关键手位」的轻量断言 |
| 中 | C01–C08、C13、C14、C16、C19–C21、U15、U17–U19 | 设置 → 行为的接线没有测试，所以 C09 / C11 / C06b 这种「设置页有、行为没接」漏了三处才被读代码发现 | 给每个 `Settings` 键写一条「改值 → 目标对象的属性变了」的测试（可以用 `UserDefaults(suiteName:)`） |
| 中低 | M01–M05、M07、M13a、M14、M21 | `PixelSpring`（ζ、±0.6 px 迟滞、吸附）、呼吸、光标呼吸、举手过冲没有单测；现在靠闪烁扫描间接保证 | 直接对 `PixelSpring.step` 写属性测试：从静止起步、不在整数 ±0.6 内来回跳、稳定后 `shown` 不再变 |
| 低 | U01–U03、U05b、U06–U08、U10、U11、U14、U21、U23–U27、U29–U39 | 窗口 / 面板 / 菜单栏 / Dock 的 AppKit 行为（层级、collectionBehavior、点穿、拖动、右键菜单、隐藏 Dock 图标）只能真机验 | 写一份人工验收清单（附在 `使用说明.txt` 或 QA 目录）：每项一步操作 + 期望；尤其是小鱼缸的「点小人跳转 / 双击回办公室 / 拖动」三步（见疑点 1） |

### 8.3 几条关键发现的复现命令（都只读，输出写到 `$TMPDIR`）

```
# S15b：其他 MCP 的首字母显示成「?」——看输出里「mcpApp N」那一格；或看 demo 座位 2 在 t≈26 的「在用 notion」
.build/release/buddyctl screens --zoom 8 --out "$TMPDIR/screens.png"
.build/release/buddyctl snapshot --scene office --from 22 --to 26 --fps 15 --zoom 8 --scale 1 --w 224 --h 300 --crop 138,58,60,78 --out "$TMPDIR/mcp"

# S29b2 / M10：离场时屏幕一帧变黑（f0045 = t 60.00，f0046 = t 60.03）
.build/release/buddyctl snapshot --scene office --from 58.5 --to 61.5 --fps 30 --zoom 4 --scale 1 --w 224 --h 300 --crop 138,132,60,78 --out "$TMPDIR/leave"

# 疑点 8：严格模式下 14 处 1–5 像素抖动
.build/release/buddyctl flicker --scene office --zoom 3 --strict --from 0 --to 79.9

# 金图（只比对，不要加 --update）
.build/release/buddyctl golden
```

## 9. 疑点

读代码 / 看图时怀疑有问题、但我没法在无 GUI 的环境里确认的地方（按怀疑程度和影响排序）。

| # | 位置 | 怀疑 | 理由 |
|---|---|---|---|
| 1 | `TankPanelController.swift:30` + `PixelView.swift`（没有 `mouseDownCanMoveWindow`） | 小鱼缸里的单击（跳转）和双击空白（回办公室）在真机上可能根本收不到 | `isMovableByWindowBackground = true` 时，AppKit 对 `mouseDownCanMoveWindow == true`（默认 = `!isOpaque`，`PixelView` 不是 opaque）的视图把按下当窗口拖动，自定义视图的 `mouseDown:` 收不到（常见坑，标准解法是覆盖 `mouseDownCanMoveWindow`；SDK 的 `NSWindow.h` 里 `movable` 的注释也说背景拖动是「server-side dragging」，即窗口服务器代办，事件不会走到视图）。`--test-titlebar` 里「双击小鱼缸的背景」是直接调 `onDoubleClickBackground` 回调，没走真实点击。**需要手点确认**。修法：命中对象 ID ≠ 0 时返回 false、空白处返回 true，双击自己数 |
| 2 | `ScreenContent.swift:184–186`（长 Bash 进度条） | 进度条几乎被头挡住，「按 1−e^(−t/τ) 增长」看不出来 | 条在第 12–13 行，`buddyctl screens` 的红框（头通常挡住的区域 = 第 12–14 行 × 第 7–19 列）几乎盖住整条；看图 [U] bash36 只在最左边露出一小段绿色 |
| 3 | `AppModel.swift:98–100`、`:130` | 最小化到 Dock 的办公室窗口会被「弹回来」 | 任何 UserDefaults 变化（包括每轮做完写一次的白板计数 `Settings.swift:45–50`、窗口位置自动保存）都会触发 `applySettings`；`officeOn && !isVisible` → `showOffice` → `showWindow`，而最小化的窗口 `isVisible == false` 且 `makeKeyAndOrderFront` 会把它恢复（读代码推断） |
| 4 | `VisualDirector.swift:40`、`AppModel.swift:263` | 「换个造型」当场看到的造型 ≠ 保存下来的造型 | `reroll` 用随机种子立刻给 `Performer` 换装，同时数据层 `salt + 1` 持久化；重启后 / 走路进出场（`director.appearance(for:)`）用的是 salt 派生的外观，两者不同源 |
| 5 | `AppModel.swift:95`、`:58` | 用户隐藏了全部 buddy 后，Claude 退出会导致 Buddy 自己在 60 秒后退出 | `AutoQuit.hasLiveSessions = !present.isEmpty`，而 `present` 已经剔除了「隐藏的 buddy」 |
| 6 | `ToastCard.swift:14` + `JumpService.swift:49` | 深链停用的提示被截断 | 提示卡文字最宽 220 pt、单行省略；看图 [O]「toast info」显示为「…直接打开 Clau…」，真实文案更长，「可在设置 → 数据源诊断里重新测试」看不到 |
| 7 | `AppModel.swift:206` | 被「隐藏这个 buddy」的会话仍然弹窗 / 响铃 / 计入 Dock 角标 | `alerts.observe` 收到的是未过滤的 `snapshots`；规格没说隐藏后要不要提醒，但用户大概率不想 |
| 8 | `buddyctl flicker --strict` | 严格模式（容忍度 0）有 14 处 1–5 个孤立像素 A→B→A | 分布在 t≈6、14.1、14.6、20、26、28.8、31.2、38.3，最集中的是 t=40.6–41.2（座位 3 伸懒腰起手，id1003）；`RT` 容忍 ≤ 6 个（DESIGN §10）。用户一贯要「零闪烁」 |
| 9 | 文档 vs 代码 | 几处文档和实现对不上 | DESIGN §5 未知工具「打字和鼠标交替」（S28a）；DESIGN §7「显示器 5 级抖动开机」（实为 16 级）；DESIGN §7「走到工位 ≈ 2.5 s」（速度上限 70 px/s，demo 布局里从门走到座位 5 约 4.5 s，看图 [J]）；使用说明「点小人（或桌牌）」（`SeatRenderer.swift:347` `drawPlate` 不带对象 ID，桌牌点不了）；使用说明说空闲阈值可改（C09） |
| 10 | `ScreenContent.swift:131` | 文档滚动的节奏不均匀 | 每 150 ms 滚一行，但办公室稳态 15 fps 出画（66.7 ms 一帧）→ 每 4 次里有 1 次间隔 200 ms、3 次 133 ms（30 fps 时才均匀）；DESIGN §7 为打字专门解决过同类问题，这里没处理 |
| 11 | `AppModel.swift:128` + `SettingsView.swift:67` | 最后一个入口被强制保留时，设置页开关状态与实际不符 | 五个入口全关时强制 `dockOn = true`，但 `ui.dockIcon` 仍是 false，设置页显示「关」而 Dock 图标在 |
| 12 | `AlertCoordinator.swift:81–90` | 桌面会话「做完了」提醒等 8 秒后才发，即使这 8 秒里下一轮已经开始 | 没有在发之前再检查 `s.activity`；「做完了」通知会在忙着的会话上冒出来 |
| 13 | `PoseLibrary.swift:84`（深度思考） | 「用笔轻敲桌面」没有笔 | 手落在键盘右端小幅上下敲，看图 [U] th77；没有笔的精灵（`PropArt` 里没有 pen） |
| 14 | `AppModel.swift:135` | 快捷键开着时，每次设置变化都会注销 / 重新注册热键 | `applySettings` 里 `hotkey.register()` 先 `unregister()`；白板计数每轮写一次 defaults 就重注册一次，无害但没必要 |

## 10. 统计

总条数：**267**（6.5 表 116 条 = 每行 × 四列 + 两条附注 + 「—」列合并 1 条；6.6 共 24；7.1 共 52；7.2 共 30；7.3 共 13；7.4 共 9；7.5 共 23）。

| 状态 | 条数 | 占比 |
|---|---|---|
| ✓ | 134 | 50.2% |
| ✓(无专门测试) | 101 | 37.8% |
| 偏离（DESIGN.md 里有记录） | 7 | 2.6% |
| 偏离-未记录 | 15 | 5.6% |
| 缺失 | 8 | 3.0% |
| N/A | 2 | 0.7% |
| 合计 | 267 | 100% |

按章节：

| 章节 | 合计 | ✓ | ✓(无专门测试) | 偏离 | 偏离-未记录 | 缺失 | N/A |
|---|---|---|---|---|---|---|---|
| 6.5 状态 → 动画（含 S30 / S31 两条附注、S00） | 116 | 96 | 9 | 2 | 6 | 3 | 0 |
| 6.6 动作手感与防闪烁（与 6.5 相关的数字） | 24 | 8 | 9 | 2 | 4 | 1 | 0 |
| 7.1 三种形态 + 菜单栏 + Dock（含 U41 空办公室牌子补充核对） | 52 | 17 | 32 | 0 | 0 | 2 | 1 |
| 7.2 提醒 | 30 | 3 | 22 | 2 | 3 | 0 | 0 |
| 7.3 点 buddy 跳到会话 | 13 | 2 | 10 | 1 | 0 | 0 | 0 |
| 7.4 跟着 Claude 一起开 / 收 | 9 | 3 | 5 | 0 | 0 | 0 | 1 |
| 7.5 设置与诊断 | 23 | 5 | 14 | 0 | 2 | 2 | 0 |

说明：① 「✓」里的证据分五种——单元测试 / 我跑的 `buddyctl`（golden、flicker、snapshot、screens、cards、sheet）看图 / 我对逐帧图做的 md5 节拍比对（[Y]）/ 我读到的 `--test-titlebar` 日志 / 我跑的 `hook_merge_test.py`；② `BuddyOffice` 没有测试目标，所以 7.x 里绝大多数只能是「✓(无专门测试)」；③ 「偏离」的 7 条都在 DESIGN.md 里找到了位置（S04a、M15 = §7「打字节拍 133 ms 一格」+ §10 汇总表；S29b1、M11 = §7「进场 / 离场」；N04 = §10 汇总表 + §11；N24b = §10 汇总表 + §8；J03 = §2 M0 第 4 项 + §10 汇总表 + §11）；④ 两条 N/A：U40（Dock 迷你画面，可选）、F05（背景说明）。
