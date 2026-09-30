# Buddy 办公室 · 设计与实测记录

> 这份文档记录：环境实测结论、每个里程碑的验收结果、我自己做的每一个小决定、已知限制。
> 任务书是 `~/Desktop/Buddy办公室-开发提示词.md`；这里只写任务书没有覆盖、或和任务书实测不一致的地方。

## 1. 环境与构建

| 项 | 结论 |
|---|---|
| 工具链 | 只有 Command Line Tools：Swift 6.3.2、SDK MacOSX26.5。没有 Xcode / actool / metal，所以 UI 全用代码写、美术全是代码形式的精灵。 |
| `swift build` / `swift test` | **在 Claude Code 沙箱里跑不了**：SwiftPM 用 Foundation 原子写文件，会去写系统的用户临时目录（`/var/folders/…/T`），沙箱不允许，报 "Operation not permitted"（`--disable-sandbox --manifest-cache local` 也救不了，试过）。所以这两条一律在沙箱外跑。产出的可执行文件本身可以在沙箱里跑。 |
| `swiftc` 直接编译 | 沙箱里可以，前提是 `CLANG_MODULE_CACHE_PATH=$TMPDIR/clang-mc`。 |
| Swift Testing | `swift test` 默认找不到 `Testing` 模块，要手动补：`-Xswiftc -F<CLT>/Library/Developer/Frameworks -Xswiftc -plugin-path -Xswiftc <CLT>/usr/lib/swift/host/plugins/testing -Xlinker -F… -Xlinker -rpath -Xlinker …`。已经包进 `scripts/dev.sh test`。 |
| 大小写坑 | macOS 默认不区分大小写：`Sources/BuddyArt` 和 `Sources/buddyart` 是同一个目录，所以开发用的小工具起名 `artctl`，别和库同名。 |
| 隔离开发包 | `.dev/core`（数据层）和 `.dev/art`（PixelKit + BuddyArt）是只编译一部分的小包，源码目录是符号链接。目的是两条线并行开发时，一边的半成品不会挡住另一边的编译。`BUDDY_PKG=.dev/art BUDDY_SCRATCH=.build-art scripts/dev.sh build`。 |
| 无头渲染 | CoreGraphics + CoreText（苹方）+ ImageIO 在沙箱里可以直接出 PNG，整数倍放大逐像素精确（`buddyctl probe` 验证过）。 |
| 屏幕 | 逻辑分辨率 1408×881 pt，Retina ×2；Dock 在下方，`visibleFrame.minY` ≈ 80–82 pt（Dock 大小会变）。 |

## 2. M0 可行性小样：逐项结论

小样是 `scripts/m0/proto.swift`，用 `scripts/m0/build-proto.sh` 编译成 ad-hoc 签名的 `Buddy 办公室.app` 装到 `~/Applications`，通过 LaunchServices 启动（`open`），日志在 `/tmp/buddy-m0.log`。

| # | 项 | 结论 | 说明 |
|---|---|---|---|
| 1 | 透明无边框面板 + 对象 ID 缓冲点穿 | **行** | 每 33 ms 读 `NSEvent.mouseLocation`，命中不透明像素（外扩 1 px）才把 `ignoresMouseEvents` 设为 false。用 `CGWarpMouseCursorPosition` 脚本化验证：身体、头 = 拦截；身体中间挖的透明洞、面板外 = 点穿；洞边 1 px 外扩生效（6/6）。真实鼠标点击也验证了：用户点到小人时日志里 `CLICK … appActive=false`——**点一下不会激活 App**（`acceptsFirstMouse = true` + `.nonactivatingPanel`）。不需要辅助功能权限。 |
| 2 | 系统通知（ad-hoc 签名） | **API 可用，但授权被拒** | 从 `~/Applications` 经 LaunchServices 启动后，`getNotificationSettings` 正常（`notDetermined`），`requestAuthorization` 会弹系统授权框，回调在用户操作后到来：`granted=false`，`UNErrorDomain Code=1 "Notifications are not allowed for this application"`，之后状态 `denied`。所以**通知必须有兜底**：任务书里的像素提示面板（右上角弹簧滑入）+ Dock 角标 + 菜单栏举手图标 + 场景气泡，全部照做。设置页要显示授权状态，被拒时给一个「打开系统通知设置」按钮。后台（`open -g`）启动的 App 不一定会立刻弹授权框，所以授权请求放到「用户第一次主动打开办公室窗口 / 点设置里的开关」的时候发。 |
| 3 | `SMAppService` | **status = `.notFound`** | ad-hoc 签名的 App 放在 `~/Applications`，`SMAppService.mainApp.status` 是 `notFound`。没有调用 `register()`（会真的往用户的登录项里加东西，M0 只测状态）。**锁定方案**：用户打开「开机启动」开关时，先试 `SMAppService.mainApp.register()`；抛错或之后状态不是 enabled / requiresApproval，就改写 `~/Library/LaunchAgents/local.buddy-office.plist`（`/usr/bin/open -b local.buddy-office`）。预计在这台机器上实际走的是 LaunchAgent。 |
| 4 | 深链 `claude://code/continue?session=local_…` | **行** | 用自己所在会话的 `local_ead11c7d-…` 测：`NSWorkspace.open` 返回 true；Claude 主日志同一时刻出现 `[WarmLifecycle:preview] Warming up session local_ead11c7d-…`，说明 Claude 收到并处理了。**坑**：目标会话本来就是当前聚焦会话时，`lastFocusedAt` 不会变——所以任务书里「2.5 秒内 lastFocusedAt 没变就算失败」的判据要修正：**目标已经是 lastFocusedAt 最新的那个会话时，不算失败**，否则连点当前会话两次就会误把深链停用。 |
| 5 | 激活方式 | **`NSWorkspace.openApplication(at:configuration:)` + `activates = true`** | 从非激活状态（我们的 App 不在前台）实测：用它把 Terminal 拉到最前 = 行；`NSRunningApplication.activate()` 对 Claude 返回 false、前台没变 = **不行**（macOS 14+ 协作式激活，任务书说的坑属实）。 |
| 6 | osascript 按 tty 选中终端标签页 | **行** | 小样自己开一个临时 Terminal 窗口（`tty=/dev/ttys012`），按 `tty of tab` 找到并选中，窗口提前、取消最小化、激活 Terminal，前台变成 `com.apple.Terminal`。第一次需要用户点「好」授权自动化（未答复会等 2 分钟后 `-1712 AppleEvent timed out`，所以要在后台队列里跑，别卡 UI）。测试窗口用完已关闭。 |
| 7 | SessionStart hook 命令 | **行** | 在沙箱外直接执行 `pgrep -xq BuddyOffice \|\| open -g -b local.buddy-office >/dev/null 2>&1; exit 0`：App 没运行时拉起（后台、不抢焦点），退出码 0、**零输出**；已经在运行时什么都不做、不会多开。`open -b` 靠 LaunchServices 按 bundle id 找到 `~/Applications` 里的 App（`lsregister -f` 之后立即可用）。 |
| 8 | buddyctl 无头写 PNG | **行** | 沙箱内运行，含中文文字（苹方）和像素字体；整数倍放大逐像素精确（0 处不一致）。 |
| 9 | 构建 | 见第 1 节 | |

**锁定的三个方案**
1. 提醒：系统通知（授权了就用）+ 像素提示面板（授权被拒或没授权时兜底，且始终有 Dock 角标 / 菜单栏图标 / 场景气泡）。
2. 开机启动：先 `SMAppService`，失败改 LaunchAgent。
3. 激活：`NSWorkspace.openApplication(at:configuration:)`，`activates = true`。

## 3. 美术与引擎的决定（M2–M4 逐步补充）

- **调色板**：任务书要求「主调色板不超过 48 色」。人物有 5 种肤色 + 8 种发色 + 10 种衣服色，每组 3–4 阶，硬压到 48 做不到。做法：场景核心色（含自发光的屏幕/灯/UI 色）刻意收紧、排在前 256 项（道具、房间精灵的格子里直接存这个索引，UInt8）；人物色阶排在后面，**只通过每个 buddy 自己的 RoleMap（角色 → 16 位索引）引用**。一个 buddy 同屏只用 1 肤色 + 1 发色 + 1 衣色 + 1 裤色的色阶。
- **颜色解析链**：角色 → RoleMap → 主调色板索引 → 时段 LUT → RGBA，和任务书一致；索引 16 位、LUT 长度按调色板项数。
- **时段**：日出 / 日落用固定钟点（黎明 05:30–06:40、白天 07:00–17:30、黄昏 17:50–18:50、夜晚 19:10 起），每次切换用 4×4 Bayer 抖动过渡 20 分钟，每个像素只翻转一次。没有用真实日出日落算法（没有定位，也不联网）。
- **画布三个平面**：RGBA（预乘）+ 主调色板索引（灯光、光晕二次着色用）+ 对象 ID（命中测试、闪烁扫描按对象检查用）。全部整数坐标。
- **描边**：选择性描边——右下边缘用最深的描边色，左上边缘用阴影色（比描边浅一级）；内部左上贴边一圈高光、右下贴边一圈阴影，不做枕头式阴影。轮廓先用位图画好，交给 `ShadeKit` 自动上色，细节再用 ASCII 覆盖。
- **中文文字**：CoreText + 苹方，按设备分辨率渲染成 CGImage 并缓存；窗口和无头快照用同一个函数。

## 4. 数据源与状态规则

数据层（`Sources/BuddyCore`，M1）的完整设计、实测时序、约 40 条小决定、性能数字和测试清单都在 [`Sources/BuddyCore/README.md`](Sources/BuddyCore/README.md)。这里只记要点。

**只读、纯本机、不联网**，读这些东西（全部通过 `FileIO` 一个入口，它会拒绝 `*.key` / `*.sock`）：

| 数据源 | 路径 | 用途 |
|---|---|---|
| 活会话登记表 | `~/.claude/sessions/<pid>.json`（只碰 `^\d+\.json$`；同目录的 `<pid>.<sha>.key` 是密钥，**一次都没打开过**，测试里用假的不可读 `.key` + `FileIO.openObserver` 断言） | 谁活着、标题、status（busy / waiting / idle）、waitingFor、pid、procStart、hostSessionId |
| ccmon hook 事件流 | `~/.claude/.monitor/<sessionId>.events.jsonl`（按登记表里的 sessionId 拼文件名，绝不扫描目录） | 工具一开始 / 结束、Stop、Notification、压缩 —— 让动作更及时；没装 ccmon 的 hook 时退回用会话记录推断 |
| 会话记录 | `~/.claude/projects/<项目>/<sessionId>.jsonl` + `subagents/` | 打断、错误、token 用量、子代理；**只留事实，不留对话内容（prompt 永远不显示、不写日志）** |
| 桌面会话元数据 | `~/Library/Application Support/Claude/claude-code-sessions/<账号>/<组织>/local_<uuid>.json` | 下班工位、lastFocusedAt（清未读、判断深链有没有生效）、桌面的本轮总结（blocked） |
| 进程信息 | `kill(pid, 0)` + `sysctl(KERN_PROC_PID)` | 存活、PID 被复用（procStart 和实际启动时间差 > 2 秒）、tty、父进程链（终端跳转） |

**身份**：桌面会话 key = `d:` + hostSessionId（`/clear`、resume、重启都是同一个人）；其余 `t:` + 第一次见到的 sessionId，靠别名表接住 `/clear` 和 `--resume`。工位号稳定并持久化（`~/Library/Application Support/BuddyOffice/identities.json`，保留 7 天），启动时按上次的顺序重新从 0 压缩。

**动作判定**（`ActivityResolver`，纯函数：信号 + 当前时间 → 动作）：
- waiting：`waitingFor` 是 permission / sandbox request，或文本含 permission / allow → 等批准（工具取最新打开的主线程调用，Notification 点了名就取那个）；input needed / dialog open → 提问（此时 ExitPlanMode 开着 → 计划待审）；其余 → 其他等待。
- busy：压缩中 → 整理上下文；`api_error` 后 `retryInMs + 15 s` 内没有新行 → 重试中（第几次 / 共几次）；有打开的主线程工具 → 显示最新那个（并行个数 ×N）；都不是 → 思考中。
- idle：被打断（3 s）→ 做完了（5 s）→ 出错（一直保持到打盹）→ 空闲；空闲 10 分钟打盹、45 分钟睡着（设置里可改）。**绝不因为时间旧就判死**：一个忙了 61 分钟的会话一直是 busy（replay 里有这一步）。
- 叠加标记：未读（一轮做完后亮，跳转 / lastFocusedAt 晚于本轮结束 / 下一轮开始清掉）、blocked（桌面本轮总结要你处理，保持到下一轮）、安静（只换画法，不判死）。

**实测里和任务书不一致的地方**（详见 BuddyCore README）：Stop 事件比登记表翻 idle 早 40–60 ms（所以「登记表还是 busy 但 Stop 已到」才是常态）；桌面的本轮总结在一轮结束后约 7 秒才落盘（比任务书写的 4 秒长，App 层等 8 秒）；AskUserQuestion / ExitPlanMode 的 Notification 文本也是 "needs your permission to use X"，所以要看打开的工具名而不是只看文本；子代理会话记录是按 block 实时写的，中间行 `stop_reason` 全是 null。

## 5. 工具归类（`ToolCatalog`）

| 类别 | 工具 | 动画（姿势 / 屏幕 / 气泡） |
|---|---|---|
| read | Read、NotebookRead | 前倾握鼠标 / 文档滚动（颜色随扩展名） / — |
| search | Grep、Glob、LS | 握鼠标、头左右扫 / 结果列表 或 文件树 / 放大镜 |
| edit | Edit、MultiEdit | 打字（每格 133 ms，4 格一轮） / 编辑器、字符逐个出现 / — |
| write | Write、NotebookEdit | 快速打字（左右手不停交替） / 一行行出现 / — |
| bash | Bash、BashOutput、KillShell、TaskOutput、TaskStop | ≤ 3 s 打字，3–8 s 手歇着，> 8 s 靠椅背 / 终端（> 8 s 加进度条 1−e^(−t/30)） / — |
| monitor | Monitor | 靠椅背 / 日志滚动 / — |
| web | WebFetch、WebSearch | 握鼠标 / 浏览器 或 搜索结果 / — |
| browser / computer | `mcp__Claude_Browser__*`、`mcp__claude-in-chrome__*` / `mcp__computer-use__*` | 握鼠标 / 浏览器指针 或 桌面窗口 / — |
| delegate | Agent、Task、Workflow、SendMessage | 有前台小助手：转 3/4 面向他们 / 小助手列表 / 小助手坐凳子滑进来 |
| todo | TodoWrite、TaskCreate/Update/List/Get | 便签本上写字 / 清单逐项打勾 / — |
| skill | Skill、ToolSearch、ListSkills | 握鼠标 / 手册页 或 图标网格 / 书 或 工具箱 |
| planEnter / planExit | EnterPlanMode / ExitPlanMode | 写字 / 大纲文档 / — |
| sendFile | SendUserFile | 托盘 / 文件滑进盘里 / — |
| schedule | ScheduleWakeup、Cron* | 拨桌上的闹钟 / 钟面 / 闹钟 |
| mcp | 其他 `mcp__<server>__*` | 打字和鼠标交替 / 带 server 首字母的应用面板 / — |
| unknown | 其余（含 AskUserQuestion、StructuredOutput） | 打字和鼠标交替 / 齿轮窗口 / — |

## 6. 渲染引擎

- **画布**：`Canvas` 三个平面（预乘 RGBA、主调色板索引 16 位、对象 ID 16 位），全部整数坐标。同样的输入永远得到逐像素相同的输出，所以快照、金图、闪烁扫描、局部重绘的对比都成立。
- **局部重绘（retained）**：办公室 / 小鱼缸 / 宠物条都保留上一帧的画布。每个工位每帧算三份「画面指纹」（屏幕内容 / 人 / 其余一切：桌子、道具、气泡、小助手、灯、桌牌底板…），只有指纹变了的那一块才重画——先用 `Canvas.copyRegion` 把这块还原成静态背景，再把碰到它的所有东西**按原来的顺序**重画一遍，画笔全部受 `Canvas.clip` 约束，所以结果和整张重画逐像素相同。走路的人 / 悬停卡片这类跨工位的浮层出现时（以及它们消失的那一帧）整张重画。人物图层（48×62）另有缓存，姿势没变就直接贴。
- **怎么保证指纹没漏项**：`buddyctl verify`（和 `Tests/BuddyStageTests` 里的缩减版）把同样的输入喂给「局部重绘」和「每帧整张重画」两份场景，逐帧比较三个平面。跑过 4 个时段（含白天黑夜 Bayer 过渡的边界秒）× 3 种视口 × 3 种数据（演示剧本 / 6 忙 / 6 空闲）× 悬停 × 三个场景，共十几万对帧，全部逐像素一致。这个对比抓到过一个真 bug：两个小助手落在同一个槽位时前后顺序取决于字典遍历顺序（现在显式排序）。
- **节拍**：一次性定时器，每拍结束时按需要排下一拍——转身 / 气泡弹出 / 走路 / 小助手滑动 → 30 fps；有人在忙 → 15 fps（打字节拍 133 ms = 15 fps 的整 2 格，所以节奏均匀）；全员空闲 → 10 fps；没有任何显示面可见 → 4 次/秒（只维持提醒、菜单栏、Dock 角标）。新数据不叫醒渲染（下一拍最多 100 ms 就会带上）；鼠标悬停 / 窗口重新可见 / 设置变化会立刻叫醒。
- **画面输出**：窗口色彩空间设成 sRGB（我们出的图就是 sRGB，系统不用每帧在 CPU 上转换颜色——这是实测里最大的一笔开销），图层内容用三块轮换的 IOSurface（BGRA，写之前确认没被合成器占用，不撕裂；宽高向上取整到 64 像素一档、只在跨档时重建，用 `contentsRect` 裁出视口——拖窗口边缘时不再每一步新建一组，QA R2-016）；文字是单独一层 CALayer（苹方，按设备分辨率渲染并缓存，只有内容 / 位置变了才碰）。
- **性能实测的教训**：30 Hz 的短脉冲比热循环里同样的工作贵 5–9 倍（缓存冷 / 频率没爬起来），所以 `buddyctl bench --sleep-ms 33` 才是估 CPU 的办法；`sample` 看不到内核时间，`ps -M` 看每个线程。大头是：每帧的 Calendar / DateFormatter / 正则 / `String(format:)`、把枚举拼成字符串比较、每个工位每帧重建 `Resolved` 表、以及 NSSound 首次播放卡主线程 250 ms（现在放后台队列）。

## 7. 表现层与动画的决定

- **节奏**（任务书 5.6）：姿势最短停留 1.5 s、屏幕 0.8 s、桌牌动作文字 1.0 s（停留期间只记最新目标，跳过中间态）；等待状态持续 0.4 s 才转身（7 步转身序列 60–90 ms 一步）；等待结束后再面向你 1.5 s 才转回去；同一帧多个变化，每个晚 90 ms、最多错开 0.6 s；`Tests/BuddyStageTests/PerformerTimingTests` 逐条测。
- **弹簧**：ζ ≈ 0.75，从静止起步，输出取整并带 ±0.6 px 迟滞，|v| < 0.5 px/s 且贴近终点时吸附。呼吸 4 秒一个周期 1 像素（带迟滞）。
- **打字节拍 133 ms 一格（任务书写 8 fps ≈ 125 ms）**：渲染节拍稳态是 15 fps（66.7 ms），133 ms = 整 2 格，每一格显示的时长完全均匀；125 ms 会变成 133/133/133/…偶尔 200 ms 的不均匀。快速打字改成「左右手不停交替」（每只手 3.75 Hz，仍 < 4 Hz 上限），和普通打字（每只手 1.9 Hz、有停顿）区分得开。写字（≈ 7.5 Hz 的 4 格）、敲笔 / 挠头（3.75 Hz 的 2 格）也都对齐到这个格子。
- **头发不滞后**：任务书想要「头发比头晚 1 帧」的跟随感，实测 1 像素的头部位移加上 1 帧头发滞后会在头 / 发交界处留下 1 帧的错位（A→B→A），闪烁扫描会抓到，肉眼也像闪一下。头本身已经由弹簧带动、比躯干晚，跟随感够了，所以头发和头同步。
- **表情**：面向你的时候脸上有表情——等批准先是平静地挥手，> 10 秒着急（worried），> 120 秒困了（sleepy）；提问是疑问（question，> 300 秒困）；计划做好了是开心（happy）。背对的时候看不见脸，所以没有表情。
- **进场 / 离场（走路 + 开门）**：进场：门先开一条缝（0.1 s）→ 人从门洞里走出来（门洞里只画在门洞里面，被墙挡住的部分不画）→ 走到工位（走路速度上限 70 px/s，远的座位要走 2–5 s；QA 时量过演示布局里从门走到 5 号座位约 4.5 s）→ 坐下（0.3 s）→ 显示器开机（Bayer 抖动渐变，16 级，300 ms）；离场：起身、推椅子、挥手，再走进门洞，门在他身后关上，屏幕同时用同样的抖动倒放 300 ms 熄灭（不是一帧硬切成黑屏；只有办公室有，小鱼缸 / 宠物条没有离场动画，桌子直接空出来）。门扇按开度 0 / 1 / 2 三档画（关 / 半开 / 全开）。之前是人在门口凭空出现 / 消失（一整个 36 像素高的精灵一帧就没了），现在不会了。
- **超过 8 个人 / 3 个小助手**：办公室没有人数上限（列数随窗口宽度在 1–6 之间自适应）；小鱼缸和宠物条最多画 8 个人，多出来的用一块「+N」牌子告诉你（小鱼缸在右下角；宠物条在最右边多出一小列，牌子没有对象 ID、鼠标穿过去）；每个人身边最多画 3 个小助手，再多的用一个「+N」小标签。`buddyctl snapshot --mode crowd12` 可以出 12 个人（一号位带 5 个小助手）的画面，`verify` / 测试里也有这一档。
- **小鱼缸 / 宠物条**：每个工位画进一张 56×74 的草稿再裁切贴上（沿用 M4 的做法）；宠物条透明，对象 ID 缓冲做像素级命中，命中外扩 1 px，30 Hz 读 `NSEvent.mouseLocation`（鼠标离得远于 100 pt 降到 10 Hz）。
- **昼夜**：固定钟点表 + 4×4 Bayer 抖动 20 分钟过渡，钟点只精确到分钟（钟、太阳、天色一分钟内肉眼看不出变化，动态部分的指纹一分钟才变一次）。
- **App 图标**：铺满的圆角方形（macOS 26 以后旧式带边距的图标会被套上灰框），16 px 和 32 px 是手工摆的像素，更大的尺寸按整数倍最近邻放大；夜里的小办公室：亮着的显示器、背对你的小人、台灯。

## 8. 集成（M6）逐项实测

| 项 | 怎么测的 | 结果 |
|---|---|---|
| 真实会话进办公室 | 我自己所在的会话（桌面 App）一直在场，动作随我干活变化（`buddyctl dump` 和 App 窗口自渲染对得上） | ✓ |
| 深链跳转 | App 里 `--test-jump <我自己的 hostSessionId>`：`NSWorkspace.open` 发出，目标本来就是 lastFocusedAt 最新的会话所以不算失败（M0 发现的坑），失败计数 0。**测的时候屏幕停在登录窗口（用户不在），看不到前台切换**，只能证明链接发出且没被判失败 | 间接验证 |
| 终端跳转 | 没有活着的终端会话；`ttyName(of:)` 对一个 pty 子进程返回的 tty 和 `ps` 一致；`hostApp(of:)` 沿父进程链找宿主；AppleScript 选标签页在 M0 小样里实测过（临时 Terminal 窗口）。自动化授权对当前 App 身份没答复，没法再在这里跑一遍端到端 | 函数级验证 + M0 |
| 系统通知被拒 → 兜底 | 演示模式走到「等批准」：像素提示面板弹出（`toast.show` 8–25 ms），Dock 角标 `1`、菜单栏图标 `waiting`，等待结束角标 / 图标恢复；`buddyctl cards` 出各种类的提示卡和悬停卡的总览，文字无溢出 | ✓ |
| 提示音 | 运行时合成的 8-bit 短音。**实测 `NSSound.play()` 首次调用卡主线程 220–270 ms，之后每次 15–70 ms**（画面会顿一下）→ 改成专门的后台串行队列 + `AVAudioPlayer`，启动 3 秒后预热 | ✓ 主线程不再卡 |
| 自动收起 | `--data-root` 假 home：没有会话 → N 秒后退出；有一个活会话 → 不退出；会话进程结束 → 退出。（**没有真的去退出用户的 Claude**，用 `--test-autoquit N` 模拟「Claude 刚退出」） | ✓ 三种情形 |
| 全局快捷键 ⌃⌥⌘B | `RegisterEventHotKey` 返回成功；没法在这里真的按键（需要辅助功能授权） | 注册成功 + 间接 |
| 隐私模式 | `PlateCopyTests.privacyModeNeverLeaksDetails`：文件名、命令、搜索词、域名一个都不出现 | ✓ |
| 设置窗口 | `--dump-settings` 逐页在浅色 / 深色下渲染成 PNG，亲眼看过（表单可读、开关状态对；标签条在离屏渲染里选中项文字显示为空白，是 `cacheDisplay` 离屏的假象，真实窗口里有） | ✓ |
| 开机启动 | 只测了状态（ad-hoc 签名下 `SMAppService` 是 notFound）；开关的方案是先 `SMAppService.register()`，不行写 `~/Library/LaunchAgents/local.buddy-office.plist`；卸载脚本通过 `BuddyOffice --unregister-login` 让 App 自己注销 | 没有真的打开过开关（会往用户登录项里加东西） |
| 数据源诊断页 | 活会话数、ccmon hook 是否注册、最后事件时间、每个会话 pid / 版本 / hook、系统通知状态、深链状态、各数据源状态 | ✓ |

## 9. 验收结果

| 里程碑 | 结果 |
|---|---|
| M1 数据层 | `swift test` 227 个（BuddyCoreTests）通过；`buddyctl replay` 43 步全过，写文件 → 快照回调延迟 p50 52 ms / p95 94 ms / max 122 ms；真实 4 个桌面会话与 dump 一致；token 与用量表一致到个位数；性能见 BuddyCore README |
| M2 窗口 | 无头 PNG 逐像素精确；点穿 / 悬停自检 PASS（办公室 5–6 个工位命中、宠物条 over-buddy = 拦截 / over-empty = 点穿 / far = 点穿） |
| M3 美术 | 8 种发型 × 5 朝向、6 种衣服 × 5 朝向、椅子 3 款、配饰 5 种、表情 5 种；`SpriteAndPaletteTests`：精灵网格 0 错误、朝向齐全、描边与填充 ΔL ≥ 0.15（抓到并修了黑发 0.143）、发色两两 ΔE ≥ 12 |
| M4 场景 | 07:00 / 12:00 / 18:30 / 23:00 快照逐张看过；小鱼缸、宠物条同 |
| M5 表现层 | 闪烁扫描全部干净：办公室 1 / 2 / 3 倍（视口按倍数换算：1 倍 672×678 美术像素）、小鱼缸、宠物条，白天 / 夜里 / 光照过渡，**演示剧本 0–80 秒完整一遍**（最早的版本因为时间映射写成 `12 + t mod 60`，只扫了 12–72 秒再加一段重复的 12–32 秒，M7 收尾时发现并改成真正的 0–80 秒；扫描的时间轴和 GIF、金图用的是同一条）；金图 17 个哈希固定（`Tests/BuddyStageTests/golden.txt`，时间点都是剧本秒数）；replay 通过 |
| M6 集成 | 见第 8 节 |
| M7 打包 | 见下面 9.1；构建 / 安装命令见第 12 节 |

全部 Swift 测试：`scripts/dev.sh test` → 797 个测试、91 个套件通过，约 1～1.5 分钟（QA 阶段从 269 个涨到 797 个；0 个被跳过、0 个已知问题）；`python3 Tests/hook_merge_test.py` 16 个通过。debug（含测试目标）和 release 干净编译都是 0 警告（QA 阶段改成数所有含 warning 的行——宏展开里的警告只打印成 `note: … to silence this warning`，只数 `warning:` 会漏；漏掉的那一条 `#expect(true)` 已改成真的断言）。库目标（PixelKit / BuddyArt / BuddyStage / BuddyCore）在 debug 构建里也开了 `-O`（`Package.swift` 里的 `optimizedLibs`）：渲染循环在 -Onone 下慢约 30 倍，闪烁扫描 / 局部重绘对比会跑上十几分钟；溢出 / 越界检查仍然开着。

**性能**（发布版，办公室窗口开着；任务书 8.5 的预算）：

| 项 | 预算 | 实测 |
|---|---|---|
| 内存（RSS） | ≤ 80 MB | **QA 最后一次 35 分钟 × 7 路长跑（装好的 1.0.1，`QA/evidence/soak/`）：真实占用（`phys_footprint`）全程 23–48 MB**：演示 / 空闲整整 35 分钟平在 23–28 MB；读数据的几路头十几分钟会涨（装好的 App 25 → 33 MB，真实数据开发副本 39 → 48 MB），原因是文字图片缓存（`TextRenderer`，上限 600 张先进先出，装满约 20 MB）在被填满，装满后不再涨（开发副本装满后平了 14 分钟），不是泄漏（`leaks` 7 个进程全是 0）。`ps` 的 RSS：启动头几分钟 72–92 MB、预热后最大 70.7–87.2 MB、35 分钟末了落回 22–37 MB——多出来的是系统框架的共享只读页，系统内存紧张时会被回收；按 `ps` RSS 口径，replay / replay 压力 / 真实数据开发副本 3 路的瞬时最大值（80.7–87.2 MB）略超 80 MB，不是我们自己的内存 |
| 全员空闲 | ≤ 1% | **0.73%**（idle6，35 分钟，QA 长跑）；不开窗口 0.4% |
| 6 个都在忙 | ≤ 3% | **1.17%**（busy6 + 办公室窗口 + `--force-render`，35 分钟，QA 长跑）。**三个形态一起开会叠加**：3.09%（预算按办公室窗口算，这一路放宽到 ≤ 5%） |
| 真实数据（1 忙 + 3 空闲） | — | **装好的 App 处理你的真实数据，35 分钟 0.65%**（开发副本 1.25%）；replay（6 个会话、接近真实的节奏 + 噪声）2.27%；replay 压力（每约 10 秒一次提醒 + 提示音 + 提示卡）4.85%（不判预算）。早先的短测：真实数据 1.0%，装好的版本启动后 90 秒起采样 60 秒 0.60% |
| 登记表变化 → 画面 | p95 ≤ 150 ms | 数据层回调 p95 34 ms（最新 replay；M1 时测过 94–122 ms）+ 渲染的下一拍 ≤ 66 ms（新数据不叫醒渲染），端到端推算 ≲ 110 ms |

### 9.1 M7 打包 / 安装 / 跟着 Claude 开收 / 长时间运行：逐项实测（2026-09-29）

| 项 | 怎么测的 | 结果 |
|---|---|---|
| 一键安装 | 沙箱外真的跑 `bash 安装.command --yes`：检查开发工具 → 编译 release → 生成图标（`buddyctl icon` → `iconutil`）→ 组装 → ad-hoc 签名 → 装到 `~/Applications/Buddy 办公室.app` → 追加 hook → 打开 | ✓ 版本 1.0.0；Info.plist 的键和任务书 9.1 逐个对得上；`codesign --verify --strict` 通过（Identifier `local.buddy-office`，Signature adhoc）；隔离标记已清（`xattr` 里只剩系统自己加的 `com.apple.provenance`） |
| settings.json 的改动 | 安装前后把两份文件按 JSON 逐键比较，再看文本 diff | ✓ 唯一差别：`hooks.SessionStart` 数组末尾多了一个组（matcher `startup\|resume`，命令 `pgrep -xq BuddyOffice \|\| open -g -b local.buddy-office >/dev/null 2>&1; exit 0`，timeout 5）；去掉这个组之后和备份 `settings.json.bak-20260929-013402` 逐键相同（ccmon 的 10 个 hook 原样），文件权限保持 0600。文本 diff 里除了那 10 行，还有一处：原文件末尾没有换行，第一次安装时脚本无条件加了一个（无害）——已改成「保持原文件末尾换行的有无」，并加了测试（装了再卸 = 逐字节还原） |
| 幂等 / 卸载 / 非法 JSON | `Tests/hook_merge_test.py` 13 项：装两次只有一条；装了再卸和安装前逐字节一致（含末尾换行的有无，ccmon 的 hook 原样）；空组连组一起删；原文件不是合法 JSON → 拒绝、退出码 2、文件没动；文件不存在 → 新建；保留权限；备份内容 = 原文件 | ✓ |
| 卸载脚本 | 用假 HOME（假的 `~/Applications`、假的 settings.json 里有 ccmon 的 hook）+ 空壳的 pgrep / pkill / osascript / launchctl（不碰真在跑的 App）：hook-merge 安装 → `卸载.command --yes` → 再卸一次 → 交互式（不带 `--yes`）回答 y | ✓ App 删除、开机启动项注销、hook 去掉后 settings.json 和安装前**逐字节一致**、`--yes` 保留偏好和数据、回答 y 删除数据、再卸一次什么都不改 |
| 跟着 Claude 开 | 先让 App 退出，再在沙箱外跑 `claude -p "ok"`（PATH 里的终端版 claude）：CLI 自己因为 OAuth 登录过期报 `Failed to authenticate`（退出码 1，stdout 只有这一行，stderr 空），**但 SessionStart hook 在那之前已经触发**：App 2 秒内被后台拉起（`open -g`，没抢焦点），输出里没有任何 hook 多出来的东西；再触发一次（App 已在运行）什么都不做，`pgrep` 里始终只有一个进程 | ✓ 拉起 + 零输出 + 不重复；**没能看到一次成功的回答**：终端版 CLI 的登录过期了，凭据不归我碰，没有去重新登录 |
| 跟着 Claude 收 | `--data-root` 假 home + `--test-autoquit N`（假装 Claude 刚退出）：没有会话 → N 秒后退出；有一个活会话 → 不退出；会话进程结束 → 退出（详见第 8 节）。**没有真的退出用户的 Claude** | ✓ |
| 退出时落盘 | 任务书 4.3 要求 token 账本「最多 30 秒写一次，退出时也写一次」：发现 App 退出时没有调用 `provider.stop()`（账本最多丢 30 秒的增量，下次启动会从上次存的偏移继续读，不会错，只是多读一点）→ 补了 `applicationWillTerminate`：先叫后台扫描停下，再把身份和账本 flush | ✓ 补上并实测：假 home 里一个假会话，第 4 秒往会话记录追加一行（落在 30 秒写盘节流窗口里，`ledger.json` 还是旧的 1000），App 自己退出后 `ledger.json` 里已经有这一行（1010）；进程正常退出、没有崩溃报告 |
| 窗口位置记住 | 发现每次启动都无条件 `center()`，把 `setFrameAutosaveName` 恢复的位置盖掉了 → 只有第一次运行（没有存过位置）才居中 | ✓ 修了 |
| 最终重装 + hook 端到端 | 收尾改完代码后再跑一次 `bash 安装.command --yes`（build 202609290242）；然后让 App 退出（AppleScript quit），直接执行 settings.json 里那条 hook 命令 | ✓ 装好的 App 被拉起（进程路径在 `~/Applications`，hook 退出码 0、没有任何输出）；再触发一次不多开；`mdfind` 里 bundle id `local.buddy-office` 只对应装好的这一个（安装脚本删掉了 `dist/` 下的编译产物、M0 小样也删了）；settings.json 仍然只有那一个 hook 组 |
| 长时间运行 | `scripts/soak.sh`：每 30 秒采样一次 RSS 和 CPU（utime+stime 的增量），各跑 35 分钟：① 正式安装的 App 附着采样（真实数据）② 开发副本 `--demo --demo-mode busy6 --show --force-render`（6 个人一直在忙，办公室窗口开着） | ✓ **内存平稳、CPU 达标。** ① 正式安装的 App（真实数据，70 个采样）：`ps` RSS 启动后第 30 秒 72 MB、第 60–90 秒 61 MB，**第 120 秒回落到 29 MB 之后就一直平**（5–15 分钟均值 28.9 MB，25–35 分钟均值 25.5 MB，最小 24.1、最大 34.2）；CPU 均值 0.48%（0.30–0.63%）。② 开发副本 busy6（6 个人一直在忙，办公室窗口开着）：RSS 第 30 秒 85 MB（启动瞬间，映射系统框架的共享页，2 分钟内回落）、120 秒之后 27–33 MB，5–15 分钟均值 31.3、25–35 分钟均值 27.6 MB；CPU 均值 0.86%（前段 0.86%、后段 0.85%，最大 0.97%，第一个采样 2.17% 是启动期）。**`ps` 的 RSS 在系统内存紧张时是 25–33 MB、宽松时 72–85 MB（共享页，见上），`Physical footprint` 一直是 26–28 MB。** |

## 10. 已知限制

- 系统通知授权目前是「拒绝」状态（M0 第 2 项）；被拒时靠兜底提醒（像素提示面板 + Dock 角标 + 菜单栏举手图标 + 场景气泡）。
- 没有活着的终端 / VS Code 会话：这两条数据路径和跳转路径只靠 fixture / 函数级测试，真实的终端会话登记表字段没核对过。终端跳转需要第一次授权「自动化」，重新编译（换了 ad-hoc 签名）之后会再问一次。
- 没碰到真实的「等批准」：本会话是 bypassPermissions；用合成数据和历史 hook 日志验证（Notification 点名的工具 = 最新打开的工具，18/18）。PreCompact / PostCompact / compact_boundary 没有任何真实样本。
- 归属规则（hook 里没有 agent_id）本质上是猜，判错只影响主 buddy，到下一个轮次边界纠正。
- 三个形态一起开时 CPU 叠加（每个面各自渲染）；预算按办公室窗口算。
- 文字图片缓存（`TextRenderer.shared`）上限 600 张、先进先出，装满约 20 MB（桌牌大小、2×）：读数据的进程头十几分钟物理占用会随缓存被填满涨到 40–50 MB，之后不再涨；最坏情况 ≈ 基线 26 MB + 20 MB，低于 80 MB 预算（QA SOAK-01，`TextCacheBoundTests` 钉住上限）。
- 闪烁扫描对检查 2（同一像素 4 帧内 A→B→A）有个容忍度：一帧里 ≤ 6 个孤立像素只记录不报错（走路 / 手臂 IK 取整时偶尔有 1–3 个像素的抖动，肉眼看不出）；走路的人和门是「本来就在动」的区域，扫描不把它们里面的像素摆动当闪烁。`buddyctl flicker --strict` 容忍度为 0。
- GUI 的点穿和悬停、通知的系统授权弹窗、终端跳转的自动化授权，都只能间接验证（自渲染窗口 + 命中缓冲单元测试 + App 日志），因为用户拒绝了对本 App 的 computer-use 授权，`screencapture` 也不能用。
- 没有 iTerm、没有 VS Code 的 Claude 扩展：这两条跳转路径按通用方式实现，只做了代码层面的检查。
- 「跟着 Claude 开」只验证到 hook 触发这一步（`claude -p "ok"` 因为终端版 CLI 的 OAuth 登录过期而报 `Failed to authenticate`，没能看到成功的回答；不碰凭据，没去重新登录）。hook 命令本身全部输出都丢掉，所以不会有东西混进 Claude 的上下文。
- 任务书 7.1 里标了「可选」的 Dock 图标实时迷你画面没做（Dock 角标 + 图标弹跳 + 菜单栏举手图标 + 场景气泡已经够用，而且 Dock 图标每秒重绘会多出一路渲染、占 CPU 预算）。

### 与任务书不一致 / 没做的地方（汇总）

| 任务书 | 我的做法 | 原因 |
|---|---|---|
| 主调色板 ≤ 48 色 | 场景核心色收紧在前 256 项，人物色阶另放（每个 buddy 同屏只用一套） | 5 肤色 + 8 发色 + 10 衣色 × 每组 3–4 阶，硬压到 48 做不到（第 3 节） |
| 打字 4 帧 × 125 ms | 133 ms 一格 | 渲染稳态 15 fps（66.7 ms）的整 2 格，节奏才均匀（第 7 节） |
| 头发比头晚 1 帧 | 头发和头同步 | 1 像素位移 + 1 帧滞后会在头 / 发交界处留下 A→B→A，闪烁扫描抓到、肉眼也像闪一下 |
| 提示音 `NSSound(data:)` | 后台队列 + `AVAudioPlayer` | `NSSound.play()` 首次调用卡主线程 220–270 ms（第 8 节） |
| 深链失败判据「2.5 s 内 lastFocusedAt 没变」 | 目标本来就是最近聚焦的会话时不算失败 | M0 实测：连点当前会话会误把深链停用 |
| 桌面会话「做完了」最多等 4 s 看 blocked | 等 8 s | 本轮总结实测约 7 s 后才落盘 |
| 「Dock 图标里显示实时的迷你画面」（可选） | 没做 | 见第 10 节 |
| 登记表变化 → 画面 p95 ≤ 150 ms | 数据层回调 + 渲染的下一拍：最新一次 replay 里写文件 → 快照回调 p50 27 / p95 34 / max 41 ms（孤立变化 p50 13 / p95 24 ms），下一拍 ≤ 66 ms（新数据不叫醒渲染；M1 时测过 p95 94–122 ms），端到端约 ≤ 110 ms | 屏幕上的延迟没有直接测（不能截屏），是「数据层实测 + 渲染节拍上限」加起来的推算 |
| 首次扫描 44 MB ≤ 2 s | 0.34–0.47 s（后台，M1 实测） | 达标 |
| RSS ≤ 80 MB | `Physical footprint` 26–28 MB；`ps` RSS 25–85 MB 波动 | 多出来的是系统框架的共享只读页（第 9 节） |
| 「跟着 Claude 开」用 `claude -p "ok"` 验证 | hook 触发 + App 被拉起 + 零输出；没看到成功的回答 | 终端版 CLI 登录过期（第 9.1 节） |

**收尾时补上的漏项**（逐条对照任务书时发现）：办公室窗口标题栏的三个像素按钮（7.1）、空办公室的「今天还没人上班」牌子（6.2）、退出时把 token 账本写盘（4.3）、办公室窗口位置记住（7.1）、宠物条 / 小鱼缸「+N」超出提示。

## 11. 我做的小决定（汇总）

- 主调色板超过 48 色（见第 3 节）；玩家色阶另放；场景核心色 < 256 直接存索引。
- 时段用固定钟点表，不算真实日出日落（没有定位、不联网）。
- 钟点精确到分钟；天空的云每 3 秒挪 1 像素。
- 桌牌文字只有「动作」部分受 1.0 s 最短停留约束；本轮用时 / token 每秒实时拼（字符串按秒缓存）。
- 悬停卡片 250 ms 出；卡片画进场景（办公室）或单独的面板（小鱼缸 / 宠物条）。
- 提醒判定只看快照的变化（不依赖数据层发事件），真实数据和演示数据都能用；桌面会话的「做完了」最多等 8 s 看有没有变成 blocked（本轮总结约 7 s 后才落盘）。
- 深链失败判据修正（目标本来就是最近聚焦的会话时不算失败）；连续 2 次没生效就停用，设置里可重新启用。
- 开发版 App 用单独的 bundle id（`local.buddy-office.dev`）：正式版的 hook 是 `open -g -b local.buddy-office`，不能让它挑中开发版（实测 LaunchServices 会挑 `dist/dev` 里的副本）；偏好设置也因此互不干扰。
- 演示模式的数据 4 Hz 推送（不是 20 Hz）：演示剧本每次生成 6 个快照，冷启动下每次约 2 ms，20 Hz 会让「演示」比真实数据还占 CPU。
- 桌面 App 里退出后 60 秒自动收起，期间有会话出现或 Claude 重新打开就取消。
- **标题栏像素按钮**（任务书 7.1，第一版漏了）：办公室窗口标题栏右侧用 `NSTitlebarAccessoryViewController(.trailing)` 放三个像素按钮——缩成小鱼缸 / 桌面宠物 / 设置。每个 12×12 美术像素（1 像素 = 2 pt，24 pt 见方）：木牌底板 4 种状态（普通 / 悬停变亮 / 按下图标下沉一格 / 对应形态开着 = 金色描边）+ 10×10 的图标（`ChromeArt`，`buddyctl sheet --book chrome` 可以看）。自己画（最近邻放大，不糊），有悬停提示文字和无障碍标签。「缩成小鱼缸」= 办公室窗口收起 + 小鱼缸出现；小鱼缸上双击背景 = 回到办公室（小鱼缸收起）；桌面宠物按钮是开关，不动办公室。`--test-titlebar`：用合成的鼠标事件点这三个按钮，逐步把结果写进日志（都对）。顺手修了一个潜在问题：小鱼缸双击 / 菜单 / 右键菜单打开办公室时没有把 `office.visible` 记成 true，之后随便改一项设置，`applySettings` 看到它还是 false 又会把窗口收起来。
- **桌牌文字的颜色（QA 改过两次）**：最初是固定的深棕色（标题 `0x3A2A22`、状态 `0x6E4C38`），压在被昼夜时段 LUT 压暗的木板上，白天状态行只有 2.91:1、夜里最差 1.5:1；中间试过「夜里换浅奶油色」，`text-audit` 量出来夜里中灰木板上浅色字只有 2.6:1，是错的。现在桌牌文字全天用深色（标题 `0x1E1518`、状态 `0x261A20`）：木板白天 L≈0.55、夜里 ≈0.26 的中灰、昼夜抖动过渡中间的棋盘格上，对比度都 ≥ 4.5:1；下班工位的桌牌是深胡桃木，用浅色字。桌牌底板从 10 像素高改成 12 像素（两行文字放得下），排版按真实笔画范围居中；缩放 1× 时桌牌只有 12 pt 高，不画桌牌文字（悬停卡片里有全部信息）。
- **宠物条来一个人不再整排往左跳**：靠右时窗口右边缘固定，每来一个人窗口向左长一格，原来是槽位从左往右排，所以整排人瞬间左移一格。现在靠右时槽位从右往左排（第 0 个人在最右），新来的人从左边长出来，已经坐着的人在屏幕上一动不动（有测试：来第 6 个人前后，原来 5 个人的画面逐像素相同）；朝向（镜像）改成只看槽位奇偶，不再按画布中线算（中线每来一个人就挪一下，靠中线的人会突然翻面）。
- 压力测试 fixture：`buddyctl snapshot --mode crowd12` 后面几个人用刁钻的标题和数字（很长的中文 / 英文、emoji、全角字符、单个字、18 亿 token、62 分钟的一轮）。它抓到三处真问题：① 气泡（向上探出格子 4 px）盖住上一排桌牌右半截的文字 → 气泡整体往下挪 4 px，落在自己的格子里；② 标题里有 emoji 时系统回退到别的字体，整行的 ascent / descent 更大，把基线挪下去、压到桌牌第二行上 → 行高只按苹方算（有测试）；③ token 数到十亿以上写成「1827.2M」又长又不好读 → 改成「1.8B」。
- 办公室窗口第一次运行居中，之后用上次的位置（`setFrameAutosaveName`）；小鱼缸第一次出现在主屏幕右上角（菜单栏下面 16 pt），之后也记住位置；人数变化窗口跟着变大 / 变小时，上边缘不动，靠右的窗口右边缘不动（向左长）、靠左的左边缘不动，并且不许长出屏幕（第一次实测时窗口是先按「空办公室」的宽度放到右上角、人来了以后向右长出了屏幕，所以改成了按靠近的那一侧固定）。存过的位置如果已经不在任何屏幕上，AppKit 恢复窗口时会把它夹回屏幕内。退出时（`applicationWillTerminate`）把身份和 token 账本写盘。
- **不能在项目里留同 bundle id 的 .app**：`open -g -b local.buddy-office`（hook）是让 LaunchServices 按 bundle id 找 App，它会扫到项目里 `dist/` 下的编译产物 / M0 小样，可能挑中它们而不是 `~/Applications` 里装好的这个。所以安装脚本装完会把 `dist/Buddy 办公室.app` 注销（`lsregister -u`）并删掉，再 `lsregister -f` 登记装好的那个；M0 小样的 .app 已经删掉（源码还在 `scripts/m0/`）。
- 安装脚本只改 `~/.claude/settings.json` 一处（追加一个 SessionStart hook 组），先备份、原子替换、校验、保留权限；非法 JSON 拒绝改。卸载脚本删除时不动别的 hook。

## 12. 构建、安装、卸载、重新生成金图

```bash
scripts/dev.sh build|test            # 开发构建 / 测试（要在沙箱外）
QA/tools/full_regression.sh          # 完整回归：干净 debug / release 构建（数警告）、全部测试、text-audit、verify、金图、闪烁、真实数据核对（约 30–40 分钟）
QA/tools/run_soaks.sh 35 <可执行文件> <输出目录>   # 长跑：演示 / 空闲 / 真实数据 / replay 同时跑，结束时用 leaks 扫一遍
scripts/build-app.sh                 # 编译 release → 图标 → 组装 → ad-hoc 签名 → dist/Buddy 办公室.app
bash 安装.command [--yes]             # 编译 + 安装到 ~/Applications + 可选：跟着 Claude 自动打开
bash 卸载.command [--yes]             # 退出、注销开机启动、删除 App、去掉 hook、可选删偏好设置
buddyctl golden --update             # 有意改了画法之后重新生成金图（先亲眼看过新画面）
buddyctl verify --seconds 60 --hover # 局部重绘 vs 整张重画，改渲染代码后必跑
python3 Tests/hook_merge_test.py     # hook-merge.py 的测试
```

开发用 .app：`scripts/dev-app.sh .build/release/BuddyOffice "dist/dev/Buddy 办公室 release.app"`；量 CPU：`scripts/measure.sh`；长时间运行：`scripts/soak.sh <标签> <分钟> [App 参数…]`。

## 13. QA 阶段：文字审计、逐条追踪、发现的问题和偏离（2026-09-29）

全部记录在 `QA/`：`ISSUES.md`（每个问题：编号 / 严重度 / 现象 / 根因 / 修法 / 回归测试 / 状态）、`spec-trace.md`（任务书第 4、5、6.5、7 节逐条对应到代码和测试）、`REPORT.md`（最后一次完整回归的数字、修复前后对比图、只能间接验证的项）。

- **文字审计（`buddyctl text-audit`）**：按 CoreText 渲染出来的真实笔画（扫描 alpha，不是估算）检查一帧画面里的文字，8 类：文字互相重叠 / 超出容器或被裁切 / 该省略没省略 / 盖住脸、屏幕、气泡或别的卡片 / 字号 < 9 pt / 对比度 < 4.5:1（文字色对文字底下真实的画布像素）/ 没有对齐到整数设备像素 / 像素数字粘连（缺字形、贴边、被人物盖住、两串贴在一起）。窗口、无头出图、审计三处共用同一个文字摆放函数（`TextLayout.place`），所以审计看到的就是屏幕上真实的位置。压力矩阵：办公室 / 悬停卡片（四个角）/ 小鱼缸 / 宠物条 / 提示卡 × 所有缩放 × 会话数 0、1、4、8、12、20（另加 41 个座位，让全部 41 种状态同时出现）× 标题（40 字长中文、没有空格的长英文、emoji 混排、空标题）× 白天 / 夜里 × 隐私模式 × 最小 / 很窄 / 矮宽 / 默认窗口，共 8598 个组合、10 万段文字、1.8 万串像素字，0 违规。审计自己有灵敏度测试（8 类各造一个必须抓到的违规）和变异验证，见 `QA/tools/verify_fail_before.py`。
- **其它检查手段（脚本都在 `QA/tools/`，命令见 `QA/REPORT.md` 第 9 节）**：数据层解析器的确定性模糊测试（`Fuzz*Tests`，种子固定）；状态机的假时钟规则测试（`StateRule*Tests`）+ 变异检查（`mutation_check.py`，60 个小变异，证明测试真的把数字钉住了）；独立核对（`token_crosscheck.py`：独立实现 / 用量表 `parse_line` / `ledger.json` / `dump` 四个口径；`dump_vs_registry.py`：dump 对登记表逐会话）；长跑（`run_soaks.sh` + `soak_watch.py`：RSS / 物理占用 / CPU / 线程 / 文件句柄 / 密钥和 socket 句柄 / 崩溃报告 / 系统 `leaks`；`replay_soak.py` 往假 home 持续写数据，带蜜罐密钥文件）；AddressSanitizer / ThreadSanitizer（`asan_run.sh`、`asan_tests.sh`、`tsan_run.sh`）；真实环境的 open 审计（`buddydump --audit-opens 秒数`：数据层只读地跑真实的 `~/.claude`，按类别汇总一共打开过哪些文件，确认没有打开过密钥文件 / socket、保险一次都没拒绝；汇总里只有类别和个数，不列文件名）。
- **新增的行为（都是审计 / 追踪抓到的缺口，见 `QA/issues-stage.md`）**：桌牌 12 像素高、文字全天深色；悬停卡片位置搜索（不盖住那个人自己的头 / 屏幕 / 气泡，窗口再小也有兜底位置）；缩放按窗口宽和高夹到「至少放得下一个整工位」；「其他 MCP」屏幕首字母（4×6 字体补 A–Z）；Bash 长任务进度条移到头挡不住的地方；显示器关机的抖动渐变；指示灯 3 阶呼吸 / 等待光晕；连续滚动的屏幕按整数帧一步；WebSearch 先打字、未知工具打字和鼠标交替。
- **仍然存在的简化 / 偏离（任务书 6.5 / 6.6 / 5.6，理由写在这里）**：
  - **屏幕内容 4 帧从上往下擦除、不同类工具之间先放下道具再开始新动作、等待类最多等过渡帧播完 ≤ 250 ms**：没做。屏幕内容切换是硬切（每个屏幕本身有自己的逐行出现动画），桌面道具随姿势一起出现 / 消失；姿势 / 屏幕 / 桌牌文字各有最短停留（1.5 / 0.8 / 1.0 s），不会来回闪。理由：擦除过渡要在 `Performer` 里加一个「过渡帧」状态，每个通道之间互相等待，和「最短停留 + 错开 90 ms」的现有节奏叠在一起，回归风险大于收益；没有出现黑帧、白帧或闪烁（标准闪烁扫描 3 个场景 × 3 个缩放全部干净）。
  - **重试时「轻敲显示器」、需要你处理时「点点便利贴」、Skill 时「翻手册」、NotebookEdit 的单元格屏幕、思考超过 20 秒的「用笔轻敲桌面」（没有笔道具，用手在键盘右端小幅上下敲代替）**：没做对应的专门动作 / 道具。重试是挠头 + 转圈屏幕 + 「2/10」像素数字；blocked 是靠着 + 静止的黄色「!」便利贴气泡；Skill 是握鼠标 + 手册屏幕 + 书气泡；NotebookEdit 用 Write 的一行行出现的屏幕。信息都在（屏幕 + 气泡 + 桌牌文字），只是少了一个手部小动作。
  - **鼠标「2 帧 × 300 ms」、走路「侧面 6 帧 × 110 ms / 正面背面 4 帧 × 130 ms」**：鼠标是 ±1 像素的正弦漂移，走路是 1.6 步 / 秒的连续相位，输出都取整到整像素，逐格离散，视觉上等价；连续相位不会在帧表边界上卡顿。
  - **「等待光晕」的「1 Hz、2 像素轻弹」**：由已有的举手挥动（1.2 Hz）承担；光晕本身是待机灯的 3 个相邻色阶（0.8 Hz）。
  - **小鱼缸 / 宠物条没有离场时的显示器关机渐变**：它们没有离场动画，那个人的工位直接空出来。
  - **走到工位「约 2.5 秒」（任务书 5.5）**：走路速度 = 路程 / 2.5 s，夹在 28–70 像素 / 秒之间；路线长于 175 像素（离门远的座位）时受 70 像素 / 秒的封顶，要走 3–5 秒（不是无限快）。有测试（`WalkersAndOffDutyTests`）。
  - **登记表「半截文件每隔 50 ms 重试一次，最多 5 次」（任务书 4.1）**：按「共 5 次读（首读 + 4 次重试，窗口 200 ms）」理解；「5 次重试（共 6 次读）」也说得通。半截文件微秒级就写完，两种读法在实践中没有区别；现有测试 `RegistryScannerTests` 把前一种写成了断言，没有改。
  - **设置里「空闲多久打盹 / 睡着」「启动时只显示最近 N 小时」「最多保留 N 个下班工位」**：下次启动生效（设置页里写明）。`SessionEngine.Options` 是不可变的，热更新要改数据层的线程模型；「最多保留」调小立刻生效（App 层再截一次）。
  - **严格闪烁扫描**（`buddyctl flicker --strict`，容忍度 0）在办公室场景有 14 处 1–5 个孤立像素的 A→B→A（33 ms 一帧，手臂 IK 取整 / 走路的人的边缘）；标准阈值（≤ 6 像素只记录）下 3 个场景 × 3 个缩放全部干净。见第 10 节。

### 应用层的决定（QA 修复时定的，详见 `QA/issues-app.md`）
- **提醒**：「隐藏这个 buddy」= 不打扰（不弹窗 / 不响铃 / 不进 Dock 角标和菜单栏计数 / 不让 Dock 弹跳；白板照数；仍算活会话，自动收起不会把他当成没有会话）——任务书没写，这样处理。Dock 弹跳和弹窗共用 1.5 秒去抖；终端会话「做完了」在宿主 App 在最前面时先等 8 秒再判断；等 8 秒后发的「做完了」若下一轮已经开始就不发；合并提醒按种类说「N 位同事在等你 / 做完了 / 有事找你」，所有被合并的人都不再等时撤掉。演示模式不计入真实的今日白板（演示的提醒保留，DESIGN §8 用它验证兜底提醒）。系统通知被拒时的兜底（像素提示卡 + Dock 角标和弹跳 + 菜单栏图标）有测试（`AlertFallbackTests`，假通知中心 + 假提示卡 + 假 Dock）。
- **通知授权**：第一次「App 在前台且办公室窗口可见」时请求一次；后台启动（`open -g`）不问；被拒 / 已答复 / 问过一次之后不再自动弹；设置页里的按钮不受限。
- **点击**：命中缓冲里点到的是座位，办公室窗口按座位号找当时那份快照的会话；小鱼缸 / 宠物条按快照 key 跳（两帧之间座位换了人也不会跳错，人走了就什么都不发生）；下班工位、空座位、越界座位点不到。桌牌底板没有对象 ID，点不了——使用说明改成「点小人」，行为没动。深链 2.5 秒判定：目标本来就是最近聚焦的会话时仍不算失败（M0 实测），但 Claude 不在最前面就补一次激活。
- **小鱼缸拖动**：`isMovableByWindowBackground` 改成背景单击时 `PixelView` 手动 `performDrag`（`PixelView` / `PixelButton` 的 `mouseDownCanMoveWindow` 为 false），保证单击小人跳转、双击回办公室、标题栏按钮收得到点击。**真实 WindowServer 的鼠标路径没法在没有 GUI 授权的情况下验证**（进程内合成事件走 `NSWindow.sendEvent` 时，旧配置下回调也能收到，没有复现「被吞」），所以这是防御性修复。
- **面板不要 AppKit 的窗口动画**：`FloatingPanel`（提示卡 / 悬停卡 / 小鱼缸 / 宠物条）`animationBehavior = .none`。长跑预演抓到：AppKit 的 order-in / order-out 动画在 GCD 工作线程上跑 `-[NSAnimation _runBlocking]`，面板被反复 `setFrameOrigin` 时永远不返回，每弹一张提示卡永久占住一个线程（14 → 53 个线程 / 3 分钟）。
- **设置**：所有 UserDefaults 数值统一夹进合法范围（`Settings.int / double`）；只处理相对上一次应用有变化的键（`ApplyPlanner`：最小化 / 隐藏的办公室窗口不会被无关的设置写入弹回来）；至少保留一个入口——只剩空的桌面宠物条时强制补 Dock 图标（启动那一刻除外），并把 `ui.dockIcon` 写回设置，设置页显示和实际一致。
- **桌面宠物**：位置 / 显示在改了立即生效；每 0.5 秒（任务书写 2 秒）检查 `visibleFrame` / 鼠标所在屏幕；新增「指定某块屏幕」（设置页列出已连接的显示器，按 ID 和名字记住，被拔掉回主屏幕）。
- **提示卡文案保证一行放得下**（用 CoreText 量过）：深链停用说明改成标题「深链跳转没有生效」+ 正文「已改为直接打开 Claude，可在设置里重试」；等批准的「想用 X：命令（等你批准）」放不下时依次截短命令 → 去掉命令 → 截短工具名 → 通用文案。
- **窗口出现**：小鱼缸 / 宠物条先渲染第一帧再 `orderFront`（任务书 6.6）。
- **日志**：`~/Library/Logs/BuddyOffice/debug.log`（0600，超过 1 MB 轮转），只在开发开关下写，不写会话标题；新增自检开关 `--test-minimize`、`--test-tank-click`、`--test-resize N`（办公室窗口反复改尺寸时量 `phys_footprint` 和新建的 IOSurface 组数，见 QA/tools/resize/），`--test-titlebar` 改成经 `NSWindow.sendEvent` 分发。
- **外观**「不撞衫」只和在场的人比；撞衫后的调整盐不持久化（同一个会话在不同次启动下外观可能不同）——要持久化需要改数据层，作为 P3 留下。
- **自动收起**：到点时条件不满足（还有会话）不会重新武装（沿用原设计）；只会退出自己（有源码审计），不会退出 Claude。
- **Package.swift**：新增测试目标 `BuddyOfficeTests`（依赖 BuddyOffice / BuddyStage / BuddyCore / PixelKit / BuddyArt）。
- **合并提醒的人数（终审 R3c-01）**：任务书 7.2 的「2 秒内连着来几条合并成一条」，合并卡替换上一张合并卡（同一个 key）时，把上一张还在屏幕上（6 秒内）合并进去的人也算进去（「在等你」的合并卡只带还在等的人）；只在最近 2 秒里本来就要合并（≥ 2 人）时才这样，单条提醒的行为不变。
- **出错提醒（R5a-01）**：和等待类 / 做完了一样过两道闸——桌面会话要开着「桌面 App 里的会话也提醒」，你正在看那个会话时不提醒。
- **系统通知授权在运行期间被关掉（终审 R3c-02）**：走系统通知发出去之后再读一次真实的授权状态，已经被拒就补一张像素提示卡（缓存也更新，之后的提醒直接走兜底）；被撤掉（`clear`）的提醒不补。
- **桌面会话元数据里的未来时间戳（终审 R3a-02 / R4a-01）**：比「现在」晚一天以上的 `createdAt` / `lastActivityAt` 按「现在」算，`lastFocusedAt` 直接丢掉（当作没聚焦过：夹成「现在」的话它会永远比真实的聚焦更新，「最近聚焦的」就永远是它）。BuddyCore 的 `DesktopMetaReader`（带引擎的时钟）和应用层 `DesktopMeta.lastFocused(path:)` 各有一份读取，两处都处理。

### 表现层 / 应用层的偏离（任务书 6.5 / 6.6 / 7；规格追踪定稿时补记，逐条对应见 `QA/spec-trace-ui-final.md`）
下面这些偏离原来只写在代码注释或 `QA/issues-stage.md` 里，这里补上：每条写清偏离了什么、为什么、影响；「测试」是钉住**实际数字**的那一条，谁改了实现它会红，提醒同时改这里。

- **气泡弹出 7 → 11 → 15 px（任务书 6.6 气泡）**：任务书写「11–15 px，用 3 帧由小变大弹出，不用非整数缩放」。实现：三帧各 60 ms，尺寸 7 / 11 / 15 px（三档都是手绘的整数尺寸精灵，共用左下角，只长大不换位置），稳定态 15 px 在任务书的 11–15 px 里，第一帧 7 px 比下限 11 小一档。理由：气泡精灵只手绘了 7 / 11 / 15 三档整数尺寸，不做非整数缩放；从 7 px 起步让「由小变大」的弹出更明显。影响：只有弹出的前 60 ms 比任务书的下限小。测试：`SpecTraceMotionTests.bubblesPopInInThreeIntegerSizesAndEveryIconIsSevenBySeven`。
- **显示器开机 / 关机是 16 级 Bayer 抖动渐变（任务书 6.5 进场 / 离场、6.6 亮度变化「5 级调色板渐变，300 ms」）**：时长 300 ms 与任务书一致，绝不闪白 / 黑帧；但不是 5 级调色板渐变，而是和昼夜过渡同一套 4×4 Bayer 抖动（进度量化成 16 级，每个像素只翻转一次），关机是同一条曲线倒放。理由：抖动渐变直接用屏幕内容自己的颜色，对所有屏幕内容都成立，不用为每一种内容另造 5 阶暗色调色板，也不会引入调色板之外的颜色（场景里所有亮度过渡都是 Bayer 抖动，见第 3、7 节）；16 级比 5 级更细。影响：中间帧是抖动的点阵，而不是整块屏幕一档一档变暗。测试：`SpecTraceSceneTests.theMonitorBootsInSixteenDitherLevelsOverThreeHundredMilliseconds`、`MonitorTests.theMonitorFadesOutOver300msInsteadOfCuttingToBlack`。
- **连续滚动的步长（任务书 6.5 Read「文档每 150 ms 滚 1 像素」）**：实现：文档每 133 ms 整屏上移恰好 1 像素（15 fps 渲染节拍的整 2 帧），终端输出每 400 ms（6 帧）、日志每 333 ms（5 帧）一步。理由：办公室稳态 15 fps（一帧 66.7 ms），150 ms 一步会变成 2、3、2、3 帧的不均匀节奏，滚起来一顿一顿（第 7 节给打字专门解决过同样的问题）；时刻加了 20 ms 偏移，让帧落在一步中间，计时抖动不会让某一步多 / 少一帧。影响：文档滚动比任务书快约 12%（每秒 7.5 步，任务书 6.7 步）。测试：`SpecTraceScreenTests.documentScrollsOnePixelPerStepAndItsColourFollowsTheExtension`、`ScreenContentTests.documentAndLogScrollingStepsAreWholeFramesAt15fps`。
- **背对镜头的动作用位移近似（任务书 6.5「头微低」「抱着手臂」「指一指，然后抱臂督工」「手扶额头」）**：人物大部分时间背对镜头（6.1：从背后看的坐姿约露出 24 px），交叉的手臂、低头、额头这类正面细节看不见。实现：Read / Grep 等「前倾，头微低」= 躯干和头一起上移 1 像素（朝显示器的方向），头相对躯干没有再低一档；Bash > 8 秒「往后靠、抱着手臂」= 躯干和头一起下沉 1 像素、双手落在身侧；Agent 前台「指一指，然后抱臂督工」= 前 2.2 秒右手伸向一侧、之后收回身侧（6 秒一轮）；出错「手扶额头」= 头低 2 像素、右手举到后脑。理由：这几个姿势的意思（前倾 / 后靠 / 指 / 捂头）靠整体位移和手的落点就读得出来，交叉的手臂和额头要画在看不见的一面。影响：少的是手臂交叉这类细节。测试：`SpecTracePoseTests.bodiesLeanAndHandsGoWhereTheTableSays`、`SpecTraceExtraStageTests.posesOfTheDashRowsCarryNoPropsAndTheSupervisorPointsThenFolds`。
- **TodoWrite 写字的竖直分量 3.75 Hz（任务书 6.5「在便签本上写（≤ 3 Hz）」）**：实现：写字图案 4 格一轮（每格 133 ms）：横向每 0.533 秒一个来回（1.875 Hz），竖直方向每 267 ms 一个来回（3.75 Hz，仍在 6.6「任何摆动都不超过 4 Hz」以内）。理由：写字、打字、挠头、敲笔都对齐到 15 fps 渲染节拍的整 2 格（第 7 节）；x / y 用同一个节拍推进——两个不同频率的振荡器会撞出「只持续 1 帧」的中间状态，看起来就是闪一下；整数像素的 1 像素来回也只能落在这个格子上。影响：竖直的敲击比任务书的 3 Hz 快 25%。测试：`SpecTracePoseTests.tappingScratchingWritingAndWavingFrequencies`、`SpecTracePoseTests.noPoseSwingsFasterThanFourHertz`。
- **转身第 7 步「举手」（任务书 6.6「3 帧，依次 70 / 70 / 90 ms，过冲 1 像素后回落」；转身「约 0.75 秒」）**：实现：前 6 步（背面下沉 1 px 80 ms → 3/4 背 70 → 侧面 60 → 3/4 正 70 → 正面 90 → 回弹 80，共 450 ms，椅子同步转动）与任务书逐步一致；举手由手的弹簧完成（响应周期 0.26 s、ζ = 0.75）：约 0.1 秒升到位，理论过冲 0.45 像素小于 ±0.6 像素的取整迟滞，画面上没有整像素的过冲；转身 + 举手到位共约 0.55 秒（任务书约 0.75 秒）。理由：手的位移和身体其余部分一样走弹簧（6.6 对弹簧的统一要求：从静止起步、带过冲、取整迟滞防闪）；离散 3 帧会让手在两个整像素位置之间「动一下、停一下」，正是 6.6 不要的。影响：举手比任务书快约 0.1–0.2 秒，没有 1 像素的回落。测试：`SpecTraceMotionTests.theTurnIsSixSpecifiedStepsWithTheChairFollowingAndThenTheHandRises`。
- **MCP 浏览器的「小幅度点击」和「扩散圈」（任务书 6.5 MCP 浏览器）**：实现：手是鼠标手的 ±1 像素缓慢漂移（和 Read 相同），没有单独的点击动作；屏幕上的点击处是指针四周 4 个变暗的像素（`scr.dark`），每 3 秒一次、约 0.36 秒，不做逐帧向外扩散。理由：24×15 的屏幕里，3 像素的指针加一圈 4 个变暗像素已经读得出「点了一下」，多帧扩散在这个尺寸上多出来的只是更多会闪的像素；只用调色板变暗、时长 0.36 秒 ≥ 250 ms、期间白色像素数不变（6.6 不闪白）。影响：少了「扩散」的过程。测试：`SpecTraceScreenTests.mcpBrowserPointerMovesAndTheClickRingOnlyDarkensThePalette`。
- **亮度变化 ≥ 250 ms 渐变只覆盖显示器开关机和昼夜（任务书 6.6「亮度变化：至少用 250 ms 渐变」）**：实现：显示器开机 / 关机（300 ms）和白天黑夜（20 分钟）是渐变；屏幕内容切换（如暗桌面 → 白色权限对话框）、台灯开关、待机灯 / 等待灯的色阶变化是一步到位的（灯是单个像素，3 个相邻色阶每阶停 0.3–1 秒）。理由：屏幕内容之间没有「亮度」可渐变——它们是不同的画面，交叉淡化会出现两个画面叠在一起的中间帧；屏幕内容有 0.8 秒的最短停留，每个屏幕自己有逐行出现的动画（见上面「屏幕内容 4 帧从上往下擦除…没做」一条）；没有黑帧、白帧（标准闪烁扫描全部干净）。影响：内容切换是硬切。测试：`RenderingTests.officeHasNoFlickerAtEveryZoom`、`SpecTraceExtraStageTests.noFrameIsBlackAndTheMonitorNeverFadesToPureBlack`。
- **并行工具的「×3」写在桌牌文字里（任务书 6.5 附注「显示一个小标签「×3」」）**：实现：桌牌状态行的动作文案后面接「 ×3」（如「在找 "TODO" ×3」），悬停卡片里同样显示，不是单独画的一个小标签。理由：桌牌已经是全部动作信息所在的地方，「×N」跟着动作文字最省地方，不用再占一块像素牌子。影响：无。测试：`SpecTracePlateTests.everyRowOfTheTableShowsItsPlateText`。
- **通知文案里的时长写法（任务书 7.2「做完了（用时 3 分 12 秒）」）**：实现：写成「做完了（用时 3分12秒）」，数字和单位之间不留空格，和桌牌上的「做完了 · 3分12秒」（任务书 6.5 自己的写法）一致，全 App 只有一种读法（`PlateCopy.spoken`）。影响：无。测试：`AlertCoordinatorTests.finishedAlertNeedsAnUninterruptedTurnOfAtLeast30Seconds`。

### 数据层 / 状态机的偏离（任务书第 4、5 节；规格追踪定稿时补记，逐条对应见 `QA/spec-trace-core-final.md`）
下面这些偏离原来只写在 `Sources/BuddyCore/README.md`「我做的小决定」或 `QA/issues-logic.md` 里，这里补上：每条写清偏离了什么、为什么、影响。

- **缺 `kind` 的登记记录按 interactive 显示（任务书 4.1）**：任务书写「`kind` 只显示 `interactive`」。实现：`kind` 存在且不是 interactive → 不画；`kind` 缺省 → 当 interactive。理由：所有字段都按可选处理，`kind` 缺失不能让一个真会话从办公室里消失（老版本的登记表可能没有这个字段）。影响：如果哪种后台会话恰好不带 `kind`，会多画一个同事；实测所有后台类型都带 `kind`。测试：`RegistryTests.onlyInteractiveSessionsAreShown`、`EnginePresenceTests.nonInteractiveSessionsNeverBecomeGhostColleagues`。
- **不移植用量表的 cost-state「后台调用补差」（任务书 4.3 token）**：任务书说「把用量表里的 Python 算法移植成 Swift」。移植了 `parse_line`、按字节偏移增量读取、按 `message.id` 去重取最大值、桌面会话合并 prior、子代理；没有移植 `read_cost_state` / `background_recs`（把只在进程退出时才写进 `cost-state` 行、会话记录里没有的后台调用补进合计）。理由：跑着的会话还没有 cost-state，历史会话的差额很小，补差还要另读一批数据。影响：极少数会话的合计比用量表少一点（只差后台调用那一块）；实测 4 个活会话 + 1 个 44 MB 历史会话 + 1 个带 prior 的桌面会话，四项分别和消息条数与用量表 `parse_line` 逐位相同（`QA/issues-logic.md` 第 4 节）。测试：`SpecTraceCoreTests.costStateLinesAreIgnored`、`StateRuleChainTests.py1_tokenCrosscheckScriptOnAFakeTree`。
- **登记表没有 / 不认识 `status` 时靠 hook 推断阶段，两个临时修正各多一个条件（任务书 5.1）**：任务书写「基础以登记表的 status 为准；两个临时修正…」。实现：`status` 缺失或取值不认识时（记录仍保留）、hook 正常，就按「最近的 UserPromptSubmit 比最近的 Stop 新 → busy，否则 idle」推断；临时修正 1（登记表 idle + 更新的提示 → 暂时 busy）另要求这条提示晚于最近一次 Stop；临时修正 2（登记表 busy + 更新的 Stop → 暂时 idle）另要求这个 Stop 不早于最近一次提示。理由：hook 和登记表相差几十毫秒，排队的下一轮（Stop 之后马上又来一条提示）不能被前一轮的 Stop 当成 idle，也不能被更早的 Stop 反复打回 busy。影响：正常流程没有变化（实测 Stop 比登记表翻 idle 早 40–60 ms）；只是多出了对没有 / 认不出状态的记录的推断。测试：`ActivityResolverTests.missingRegistryStatusFallsBackToHooks`、`registryBusyButNewerStopIsTemporarilyIdle`，`StateRuleTests` m1 / m2。
- **轮次边界只关「边界时刻之前或同时开始」的主线程调用，`SessionEnd` 也算边界（任务书 5.2）**：任务书写「遇到 Stop、UserPromptSubmit、SessionStart、登记表变成 idle、会话记录出现 `stop_hook_summary`，就关掉主线程的全部打开调用」。实现：关掉的是开始时间不晚于这个边界时间戳的主线程调用，小助手名下的记录不动；另外 `SessionEnd` 也当边界。理由：会话记录里的 `stop_hook_summary` 落盘比 hook 晚，它的时间戳可能比之后才开始的新调用旧，那些新调用不能被一条旧边界误关；`SessionEnd` 之后主线程不可能还有开着的调用。影响：只有时间戳比开着的调用还旧的边界关不掉它，其余和任务书一致。测试：`ToolTrackerTests.aBoundaryOlderThanAnOpenCallDoesNotCloseIt`，`StateRuleTests` b1…b5、b9。
- **整理上下文的会话记录判据和时间窗口（任务书 5.4 busy 1）**：任务书写「有 PreCompact 但还没有 PostCompact，或者会话记录显示正处在 `compact_boundary` 压缩中 → 整理上下文」。实现：(a) PreCompact 之后一直没有 PostCompact，超过 15 分钟就不再显示（防 hook 丢了永远显示），`SessionStart source=compact` 也当 PostCompact；(b) 会话记录的判据是「`compact_boundary` 之后 120 秒内没有新的 assistant / user 行」，但 hook 已经说压缩结束了（PostCompact / `SessionStart(compact)` 不早于边界前 5 秒）就不再用它。理由：真实日志（这台机器上 3 次自动压缩）里 `compact_boundary` 是压缩**结束**时才写的（比 PreCompact 晚 88–104 秒，比 PostCompact 晚约 0.02 秒），任务书「正处在 compact_boundary 压缩中」的假设不成立；照字面用的话，每次压缩结束后还会继续显示「整理上下文」2.4–3.8 秒（最坏 120 秒），盖住压缩完的第一个工具。影响：有 hook 的会话里 `compact_boundary` 不再单独触发；没有 hook 的会话只有这一个信号，行为不变。测试：`ActivityResolverTests.compactingExpiresIfPostCompactNeverArrives`，`StateRuleTests` o1 / o2（用真实时序）。第 10 节里「PreCompact / PostCompact / compact_boundary 没有任何真实样本」的说法因此已经过时。
- **出错优先于做完了，并一直保持到打盹（任务书 5.4 idle）**：任务书 idle 的顺序是「被打断 → 做完了 → 出错 → 空闲」，出错没有给时长。实现：被打断 → 出错 → 做完了 → 空闲，出错一直保持到开始打盹（10 分钟）。理由：出错的一轮（重试到上限，或最后一条 assistant 是合成的 API 错误）通常也有 Stop / `stop_hook_summary`，按任务书的顺序会先闪 5 秒绿色的「做完了」再变成出错；错误不能一闪而过。影响：出错的一轮直接显示「出错了」，不先显示「做完了」。测试：`StateRuleTests` d1…d6（d6：两种证据同时有 → 出错）、`ActivityResolverTests.erroredStaysUntilDozing`。
- **被你自己打断的一轮不亮未读（任务书 5.4 叠加标记）**：任务书写「未读：一轮做完后亮起」。实现：正常做完和出错亮未读，被你自己打断的不亮。理由：打断是你刚按的，你正在看这个会话，不需要再提醒你去看。影响：被打断之后没有未读旗。测试：`EngineScenarioTests.aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted`，`StateRuleTests` e1 / e2。
- **`stop_reason` 为 null 不一律当作被打断（任务书 4.3）**：任务书写「stop_reason：tool_use / end_turn / null（null 表示被打断）」。实现：null 只有同时带 `isAbortedMidStream` 才算打断。理由：子代理的会话记录是按 block 实时写的，中间行的 `stop_reason` 全是 null（第 4 节末段）；主会话里只有被打断的消息才是 null 且带 `isAbortedMidStream`。影响：子代理里的 null 行不会被当成打断。测试：`TranscriptTests.abortedMidStreamAssistantIsAnInterrupt`。
- **不用 hook 的 `SessionStart source=clear` 佐证进程别名（任务书 4.5）**：任务书写「进程别名（同一个进程执行了 `/clear`，hook 里的 `SessionStart source=clear` 可以佐证）」。实现没有用这条佐证：登记表里 pid 和启动时间没变、只是 sessionId 换了，进程别名 `proc:<pid>@<启动时间>` 就足够认出同一个 buddy，不依赖 hook 是不是在工作；PID 复用由 procStart 挡住。影响：无，`/clear` 之后仍是同一个人、同一个工位。测试：`IdentityTests.terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess`，`StateRuleTests` j1。
- **`hookActive` 多了一条「掉线」判据（任务书 4.2）**：任务书写「当前会话有 `ts ≥ startedAt − 5s` 的事件，就说明 hook 在正常工作；以后用户卸掉了 ccmon，要自动退回用会话记录判断工具」。实现：在这条判据之外，会话记录比 hook 的最后一个事件领先超过 15 秒也当作 hook 掉线（用户中途卸掉 ccmon：hook 安静、会话记录还在长）。理由：任务书没有给「已经在跑的会话中途掉线」怎么发现；只看 `startedAt` 会让掉线的会话一直显示「思考中」。影响：没有工具的长时间生成里，会话记录可能比 hook 晚 15 秒以上才落盘，`hookActive` 会短暂为 false，只是让工具判断改用会话记录，不会判死会话。测试：`HookDropoutTests`（`EngineScenarioTests.swift`）。
- **启动时显示器依次开机的总延迟封顶 1.5 秒（任务书 5.5）**：任务书写「App 启动时就已经在跑的会话直接坐好，显示器从左到右依次开机，每台间隔 100 ms」。实现：按座位号从左到右每台晚 100 ms，总延迟封顶 1.5 秒（第 16 台起和第 15 台一起开）。理由：启动时人很多时，别让最后一台等好几秒。影响：启动时超过 15 个会话才会碰到。测试：`MonitorTests.monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals`。

