# QA 问题记录（ISSUES）

把整个项目当成别人写的代码独立检查一轮（找 bug、查字体和文字重叠、查逻辑问题）发现的全部问题。每条写明编号、严重度、现象、根因、修法、回归测试、状态；
「修复前失败 / 修复后通过」的证据写在每条里（先在没改行为的状态下跑测试看它失败，再修、再跑），文字审计组另有可复现的脚本 `QA/tools/verify_fail_before.py`（输出 `QA/evidence/fail-before-stage.md`）。

**严重度**：P0 = 正常使用下崩溃 / 数据损坏 / 违反安全红线；P1 = 明显错误的行为 / 关键信息看不清 / 设置不生效；P2 = 边界条件下的错误、资源问题或体验缺陷；P3 = 小瑕疵 / 代码卫生。
**状态**：已修 = 修好并有回归测试；已修（仅间接验证）= 修好并有测试，但真实 GUI 路径只能间接验证（见 REPORT.md）；不修 = 写明理由（只允许 P3）。P0–P2 全部已修。

## 统计

| 严重度 | 发现 | 已修 |
|---|---|---|
| P0 | 6 | 6 |
| P1 | 12 | 12 |
| P2 | 48 | 48 |
| P3 | 127 | 72 |
| **合计** | **193** | **138** |

## 汇总表

| 编号 | 严重度 | 区域 | 标题 | 状态 |
|---|---|---|---|---|
| TA-001 | P1 | 表现层 / 文字审计 | 桌牌文字对比度不足（白天状态行 2.91:1，夜里最差 1.5:1） | 已修 |
| TA-002 | P1 | 表现层 / 文字审计 | 桌牌放不下标题 + 状态两行，字被切 / 顶出桌牌 | 已修 |
| TA-003 | P3 | 表现层 / 文字审计 | emoji 标题的字形比苹方高出一截 | 已修 |
| TA-004 | P3 | 表现层 / 文字审计 | 睡着的「zzz」两个 z 粘在一起 | 已修 |
| TA-005 | P2 | 表现层 / 文字审计 | 空办公室的「今天还没人上班」牌子：字对比度 4.45:1，还被后画的桌椅盖住（4× 时最差 1.09:1） | 已修 |
| TA-006 | P2 | 表现层 / 文字审计 | 悬停卡片盖住被悬停那个人自己的脸 / 屏幕 / 气泡；卡片下面的桌牌文字浮在卡片上 | 已修 |
| TA-007 | P3 | 表现层 / 文字审计 | 窄窗口里悬停卡片比窗口还宽 1 像素，放不下 | 已修 |
| TA-008 | P3 | 表现层 / 文字审计 | 窗口再小也要有悬停卡片（兜底位置） | 已修 |
| TA-009 | P3 | 表现层 / 文字审计 | 窗口比一个整工位还窄 / 还矮时，设置里的大倍数把工位切掉一半 | 已修 |
| TA-010 | P3 | 表现层 / 文字审计 | 空标题 / 全空白标题变成一块空牌子 | 已修 |
| TA-011 | P3 | 表现层 / 文字审计 | 审计工具自己的 bug：窗口上边外面的文字，对比度读错画布行（假阳性） | 已修（工具） |
| TA-012 | P2 | 表现层 / 文字审计 | 「其他 MCP」屏幕的 server 首字母画成「?」 | 已修 |
| TA-013 | P2 | 表现层 / 文字审计 | Bash 长任务的进度条被人的头挡住 | 已修 |
| SP-01 | P2 | 表现层 / 文字审计 | 显示器关机是一帧硬切成黑屏（任务书 5.5 / 6.6：关机也是 300 ms 渐变，绝不黑帧） | 已修 |
| SP-02 | P3 | 表现层 / 文字审计 | 指示灯是开关式的（任务书 6.6：不许开关式闪烁；等待时的光晕 3 个相邻色阶 0.8 Hz） | 已修 |
| SP-03 | P3 | 表现层 / 文字审计 | 连续滚动的屏幕节奏不均匀 | 已修 |
| SP-04 | P3 | 表现层 / 文字审计 | WebSearch 只用鼠标、未知工具只打字（任务书 6.5：先打字再用鼠标 / 打字和鼠标交替） | 已修 |
| SP-05 | P2 | 表现层 / 文字审计 | App 启动时就在的会话：显示器不是依次开机，而是所有人一起「啪」地亮起（任务书 5.5：直接坐好，显示器从左到右依次开机，每台间隔 100 ms） | 已修 |
| SP-06 | P2 | 表现层 / 文字审计 | 某个人正在「错开」推迟里时，变成等待类（等批准 / 提问 / 计划待审）的状态晚到最多 0.6 秒，还会先闪一帧过期的旧动作（任务书 5.6：等待类最多 250 ms 就立即插入） | 已修 |
| SP-07 | P3 | 表现层 / 文字审计 | Edit 屏幕「字符逐个出现」被高亮行里原来就画着的一条白线遮住了一部分 | 不修（P3，理由见修法；记录在 QA/REPORT.md 第 8 节） |
| SP-08 | P3 | 表现层 / 文字审计 | Grep 结果列表的高亮条走到最后一行后停 1.2 秒，然后一帧跳回第一行 | 不修（P3，理由见修法；记录在 QA/REPORT.md 第 8 节） |
| SP-09 | P3 | 表现层 / 文字审计 | 既有测试在测试宿主进程的偏好域里留痕迹（`NSWindow Frame BuddyOfficeTankPanel`） | 已修 |
| A-001 | P1 | 应用层 | 设置页「打盹 / 睡着 / 最近 N 小时 / 最多保留」四项没接到数据层 | 已修（「下次启动生效」） |
| A-002 | P1 | 应用层 | 小鱼缸 / 标题栏按钮的点击可能被「窗口拖动」吞掉 | 已修（防御性；旧问题未能复现，真实鼠标路径仅间接验证）；见末尾「只能间接验证的项」 |
| A-003 | P1 | 应用层 | 最小化的办公室窗口会在任何一次设置写入之后被弹回来 | 已修（真实窗口 A/B 验证过） |
| A-004 | P2 | 应用层 | `dormant.max` 为负数 → `prefix(-1)` 崩溃，启动即崩 | 已修 |
| A-005 | P2 | 应用层 | 今日白板计数 ≤ -5 → `drawTally` 的 `0..<负数` 崩溃；`addTally` 在 Int.max 时溢出 | 已修 |
| A-006 | P2 | 应用层 | 桌面宠物「位置 / 显示在」改了不立即生效 | 已修（仅间接验证：`NSScreen` / `NSPanel.setFrameOrigin` 的真实效果没有真屏幕可看）… |
| A-007 | P2 | 应用层 | 「换个造型」：坐着的 / 走路的 / 重启后的造型三者不一致 | 已修 |
| A-008 | P2 | 应用层 | 同一会话第二次走进办公室：座位上已坐着人，门口又走进来一个「分身」 | 已修 |
| A-009 | P2 | 应用层 | `Canvas.writeBGRA` 在 crop 与画布不相交时退化成整张画布（潜在越界写） | 已修（当前所有调用点不可达，属纵深防御） |
| A-010 | P2 | 应用层 | 「跟着 Claude 一起收」把被隐藏的 buddy 当成没有会话 | 已修（`AutoQuit` 自身的 60 秒逻辑见 B-4） |
| A-011 | P2 | 应用层 | 座位号没有上限 | 已修（App 层）；Core 侧… |
| B-001 | P2 | 应用层 | AlertCoordinator 零单测 + 系统通知被拒时兜底提醒确实会出现 | 已修 |
| B-002 | P2 | 应用层 | 「点击 buddy 不会跳到别人的会话」：JumpService 目标解析抽成纯函数 + 桌牌点击核对 | 已修（实际点击 → 窗口服务器 → `NSWorkspace.open` 那一段属只能间接验证，见末尾） |
| B-003 | P3 | 应用层 | 首次打开办公室时请求通知授权（DESIGN §2 M0） | 已修（真正的系统授权弹窗只能真机看，见末尾） |
| B-004 | P3 | 应用层 | 自动收起（AutoQuit）可测：Claude 退出且没有活会话 60 秒后退出 | 已修 |
| B-005 | P3 | 应用层 | 小鱼缸 / 宠物条先渲染第一帧再显示（spec-trace-ui M13b，协调者补充） | 已修（首帧不闪的真实观感只能真机看；顺序有测试） |
| B-006 | P3 | 应用层 | 深链停用的提示卡文案被截断（spec-trace-ui 疑点 6，协调者补充） | 已修 |
| B-007 | P3 | 应用层 | 桌面宠物「每 2 秒检查 visibleFrame」+「指定某块屏幕」（spec-trace-ui U28 / C06b / U26c，协调者补充） | 已修（仅间接验证：真实多显示器插拔没法在这里做） |
| B-008 | P3 | 应用层 | 强制保留的 Dock 图标：设置页显示和实际一致（spec-trace-ui 疑点 11，协调者补充） | 已修 |
| B-009 | P3 | 应用层 | 被隐藏的 buddy 是否还提醒（spec-trace-ui 疑点 8、audit-app A-022 ③；**这是协调者定的选择**） | 已修 |
| B-010 | P1 | 应用层 | FloatingPanel 的窗口出现 / 消失动画在工作线程上不返回 → 线程数随使用时间无限增长（协调者在 replay 长跑预演里发现） | 已修 |
| A-012 | P3 | 应用层 | 主线程上的 queue.sync 链：退出 / 切换演示 / 设置页诊断 | 已修（仅间接验证：真实 `SessionStore.stop()` 在系统忙时的耗时没有量；超时只是上限） |
| A-013 | P3 | 应用层 | NSAppleScript 在后台串行队列上执行、授权弹窗未答复时卡满 2 分钟 | 已修（仅间接验证：真实的自动化授权弹窗 / Terminal 标签页选择没法在这里跑） |
| A-014 | P3 | 应用层 | 主线程同步读取并解析全部 local_*.json | 已修（部分：见上「没有」） |
| A-015 | P3 | 应用层 | DebugTools.log：旧式 API、世界可读的 /tmp、无界增长、`--test-jump` 会写会话标题、`NSLog` 把插值当格式串 | 已修 |
| A-016 | P3 | 应用层 | applySettings 被无差别重跑：热键反复重新注册 + 日志刷屏；`.settingsChanged` 死代码 | 已修（`.settingsChanged` 死代码保留） |
| A-017 | P3 | 应用层 | wake() 没有速率上限 | 已修（真实 CPU 影响没量；逻辑有测试） |
| A-018 | P3 | 应用层 | 只增不减的字典 / 键 | 已修（除上面两项有理由不修） |
| A-019 | P3 | 应用层 | 文案边界：空路径 / 负时间 / 空标题 / 英文原文 | 已修（BuddyOffice 一侧）；PlateCopy / HoverCard 的部分转交 |
| A-020 | P3 | 应用层 | Int(Double) 对极端时间没有保护 | 已修 |
| A-021 | P3 | 应用层 | 演示模式的副作用 | 已修 |
| A-022 | P3 | 应用层 | AlertCoordinator 的几处细节 | 已修 |
| A-023 | P3 | 应用层 | 设置页显示和实际状态不同步；通知授权从不主动请求 | 已修（设置页视图本身无法单测，`SettingsView` 的接线读代码） |
| A-024 | P3 | 应用层 | 只开「桌面宠物」且没有会话时，没有任何可点击的入口 | 已修 |
| A-025 | P3 | 应用层 | 性能陷阱合集 | 已修（除上面不修的） |
| A-026 | P3 | 应用层 | 深链成功判据不检查 Claude 是否真的到了前台；已弃用的激活 API | 已修（前置行为只能真机验证） |
| A-027 | P3 | 应用层 | 外观「不撞衫」把已离场的人也算进去、外观依赖出现顺序 | 已修（部分） |
| A-028 | P3 | 应用层 | 时区 / 历法：DateFormatter 和 Calendar.current 的缓存 | 已修（`SceneClock` 的时区跟随只能读代码，没有单测） |
| A-029 | P3 | 应用层 | 开发工具参数没有校验；工具代码链接进了 App | 已修（除上面不修的） |
| C-001 | P0 | 数据层（解析器 / 模糊测试） | 登记表 `procStart` 里年份 / 时分秒是天文数字 → 整个 App 崩溃 | 已修复 |
| C-002 | P0 | 数据层（解析器 / 模糊测试） | `identities.json` 里有一个天文数字的时间 → 每次启动都崩溃（崩溃循环） | 已修复 |
| C-003 | P0 | 数据层（解析器 / 模糊测试） | hook 行的 `ts` 不做范围检查：接受 1970 年 / 550 万年 / 无穷，并且让归属判断崩溃 | 已修复 |
| C-004 | P0 | 数据层（解析器 / 模糊测试） | 会话记录里 `usage` 的数字太大 → 相加溢出，崩溃（解析线程 / 账本扫描线程） | 已修复 |
| C-005 | P0 | 数据层（解析器 / 模糊测试） | `ledger.json` 里的计数是天文数字 / 负数 → 恢复后累加、求和都会溢出崩溃 | 已修复 |
| C-006 | P1 | 数据层（解析器 / 模糊测试） | 时间戳在未来的 hook 事件会把「归属扣留」永远扣下去，整个 hook 队列卡死 | 已修复 |
| C-007 | P1 | 数据层（解析器 / 模糊测试） | `FileIO` 的「绝不打开 .key / .sock」保险可以被绕过 | 已修复 |
| C-008 | P1 | 数据层（解析器 / 模糊测试） | 数据文件位置上是命名管道（FIFO）→ 读取线程永远卡在 `open()` | 已修复 |
| C-009 | P2 | 数据层（解析器 / 模糊测试） | `identities.json` 载入没有上界：别名 / 工位号 / 身份个数都可以是任意大 | 已修复 |
| C-010 | P2 | 数据层（解析器 / 模糊测试） | 桌面元数据的 `priorCliSessionIds` 没有上界：O(n²) + 每个 id 都要列一遍 projects 目录 | 已修复 |
| C-011 | P2 | 数据层（解析器 / 模糊测试） | `ToolTracker.open` 没有上界 | 已修复 |
| C-012 | P0 | 数据层（解析器 / 模糊测试） | 嵌套 ≥ 约 470 层的 JSON 把 512 KB 栈的 GCD 工作线程压爆（SIGBUS） | 已修复 |
| C-013 | P3 | 数据层（解析器 / 模糊测试） | `TranscriptReader.bootstrap(tailWindow:)` 传 0 死循环、传负数 trap | 已修复 |
| C-014 | P2 | 数据层（解析器 / 模糊测试） | 按会话累积的缓存 / 账本里没有 buddy 在用的文件永远不清理，还每次都被扫描 | 已修复 |
| C-015 | P3 | 数据层（解析器 / 模糊测试） | 读过一条很长的行之后，`JSONLTailer` 的半行缓冲一直占着几 MB 内存 | 已修复 |
| C-016 | P3 | 数据层（解析器 / 模糊测试） | `TokenLedger` 的 `version` / `persistenceOK` / `isScanning` 在别的线程无锁读取（数据竞争） | 已修复 |
| C-017 | P3 | 数据层（解析器 / 模糊测试） | 登记表 `pid` 不校验：布尔 / 小数 / 超出 Int32 的数被强转成别的 pid；记录里的 pid 和文件名不一致时用哪个没有规定 | 已修复 |
| C-018 | P3 | 数据层（解析器 / 模糊测试） | 会话记录里 AskUserQuestion 的 `key` 没有像 hook 那样置空 | 已修复 |
| C-019 | P3 | 数据层（解析器 / 模糊测试） | 文件事件分流按前缀匹配、不看目录边界；空会话 id 会匹配一切 | 已修复 |
| C-020 | P3 | 数据层（解析器 / 模糊测试） | 两个桌面元数据文件声称同一个 `sessionId`（用户复制出的副本）→ 每次刷新都互相覆盖、报告「变了」 | 已修复 |
| C-021 | P3 | 数据层（解析器 / 模糊测试） | 子代理的 `.meta.json` 一直不存在时，每次 poll 都 `open` 它一遍 | 已修复 |
| C-022 | P3 | 数据层（解析器 / 模糊测试） | `FileWatcher.resolved` 是递归的：几百层的不存在路径把 512 KB 栈压爆 | 已修复 |
| C-023 | P3 | 数据层（解析器 / 模糊测试） | 外部 JSON 里的字符串字段没有长度上限 | 已修复 |
| C-024 | P3 | 数据层（解析器 / 模糊测试） | `FileIO.writeAtomically` 的临时文件名是固定的：多线程同时写同一个文件会得到两次内容的混合 | 已修复 |
| C-025 | P1 | 数据层（解析器 / 模糊测试） | 会话记录里 `turn_duration` / `api_error` 的数字没有范围：天文数字会流进快照，让表现层的 `Int(秒数)` 换算 trap | 已修复（数据层保证范围） |
| C-026 | P1 | 数据层（解析器 / 模糊测试） | 时间戳远在未来的 hook 事件 / 会话记录行，把「取最大时间」的状态永远毒化（会话被卡在 idle） | 已修复 |
| C-027 | P3 | 数据层（解析器 / 模糊测试） | `Paths(home:)` 去掉结尾斜杠是 O(n²) | 已修复 |
| C-028 | P3 | 数据层（解析器 / 模糊测试） | `TokenLedger.flush()` 在扫描队列上调用会对自己所在的队列 `sync` → 崩溃 / 死锁 | 已修复 |
| C-029 | P2 | 数据层（解析器 / 模糊测试） | `HookLogReader.poll()` 一次交出的事件没有上界 | 已修复 |
| C-030 | P3 | 数据层（解析器 / 模糊测试） | 几处小的整数换算 / 参数校验（FileIO 与 dump） | 已修复 |
| C-031 | P3 | 数据层（解析器 / 模糊测试） | 既有测试文件里有编译警告（不是本轮新增的） | 已修（主线程接手；改的是取值的写法，没有削弱断言） |
| C-032 | P3 | 数据层（解析器 / 模糊测试） | BuddyOffice 的 `JumpService.DesktopMeta` 在调用线程同步读取全部桌面元数据文件，并且绕过 `FileIO` | 已修（主线程接手：读目录 / 读文件改走 `FileIO`）… |
| C-033 | P3 | 数据层（解析器 / 模糊测试） | BuddyStage 对数据层给出的时间差做 `Int(…)` 换算，自己没有防护 | 已修（表现层负责人接手） |
| L-001 | P2 | 状态机 / 逻辑 / token / dump | 一轮结束时证据还不够的 0.4 秒里，引擎先报「做完了」再改口成「被打断 / 出错」 | 已修复 |
| L-002 | P1 | 状态机 / 逻辑 / token / dump | 设置里的「空闲多久后打盹 / 睡着」「启动时只显示最近 N 小时」是摆设 | 已修（由应用层修复，同 `issues-app.md` A-001；「下次启动生效」） |
| L-003 | P2 | 状态机 / 逻辑 / token / dump | 压缩结束后仍显示「整理上下文」（`compact_boundary` 是压缩**结束**时才写的） | 已修复 |
| L-004 | P3 | 状态机 / 逻辑 / token / dump | 登记表半截文件「最多 5 次」的口径 | 不修（P3，任务书措辞有歧义；影响几乎为零——半截文件微秒级就写完）… |
| L-005 | P3 | 状态机 / 逻辑 / token / dump | 既有测试文件里有编译警告 | 已修（主线程收尾时把 `:250` 和 `:262` 两处都改成了先取值再 `#expect`，断言的意思不变）… |
| R1a-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 会话「忙但 10 分钟没有任何新数据」（quiet）时，引擎的 `nextWake` 永远停在过去 → SessionStore 每 5 ms 空转一次 | 已修 |
| R1a-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `hook-merge.py`：settings.json 是符号链接时，install / uninstall 会把链接换成一个普通文件 | 已修 |
| W-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 测试目标里有一条编译警告：`DebugLogTests.swift:58` 的 `#expect(true)`（永远通过） | 已修 |
| R1a-03 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 数据层测试套件的质量：机器满载时误报红灯、一个阈值没被任何测试钉住、FSEvents 起不来时几条监听断言静默通过 | 已修（放宽超时、补边界测试、让静默跳过可见；没有削弱任何断言） |
| R1b-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 错开推迟期间活动又变回已套用的同一种类：到点那一帧套用了过期的中间快照（SP-06 的同一根因，只修了一半） | 已修 |
| R1b-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 桌牌动作文字的 1.0 s 最短停留被「数字抹平」绕过 | 已修 |
| R1b-03 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 隐私模式没有隐藏 MCP server 名和未知工具名（桌牌、状态行、悬停卡片都会显示「在用 acme-secre…」） | 已修 |
| R1b-04 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （低概率；任务书没写）气泡通道没有最短停留，会随工具节奏一闪一闪 | 已修 |
| R1b-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 打开隐私模式时，桌牌动作文字还会被「1.0 s 最短停留」多留最多 1 秒 | 已修 |
| R1b-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 只有零宽 / 控制 / 方向字符的标题会画出一块空桌牌 | 已修 |
| R2-001 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 缩放变了但画布没变时，`PixelView` 的图像层不跟着变大小（小鱼缸 / 宠物条） | 已修 |
| R2-002 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 提示卡出现时先闪在终点位置，再跳到屏幕外起点、再滑入（系统通知被拒时每条提醒都这样） | 已修（真实观感 / 提示卡的真实滑入动画只能间接验证，见 REPORT 第 7 节） |
| R2-003 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 合并提醒里含 `blocked` 时，「N 位同事……」在同一次判定里先发出又立刻撤掉，用户什么都看不到 | 已修 |
| R2-004 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 被 20 秒节流挡掉的「等你」提醒，这一整段等待再也不会提醒 | 已修 |
| R2-005 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）我加的 `DesktopMetaFileIOTests` 和 BuddyCoreTests 的 `FileAccessTests` 抢全局的 `FileIO.forbiddenHits / openObserver` | 已修 |
| SAN-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试 / 审计工具的线程安全）text-audit 的像素字审计钩子有数据竞争：`withDraws` 读收集结果时和别的线程晚到的 append 竞争（ASan 抓到 heap-use-after-free） | 已修 |
| SAN-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）`OpenAuditTests` 的两条测试被并行跑的别的测试的 open 污染，间歇性变红（最后一次完整回归的第二遍红过一次） | 已修 |
| SOAK-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 读真实 / replay 数据的进程，物理占用在最初十几分钟会涨 4～20 MB（文字图片缓存被慢慢填满，上限 600 张 ≈ 20 MB） | 不修（不是泄漏：缓存有上限 = 600 张、装满约 20 MB，长跑里已经装满的那一路实测停在 46 MB 不再涨）… |
| R3a-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）红线测试 `fuzz_registryScannerWithDecoyFiles` 在默认并行的 `swift test` 里间歇性变红（8 次里 2 次）：观察口没有按自己的临时目录过滤 | 已修 |
| R3a-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 桌面会话元数据里的未来时间戳没有像其他数据源那样夹紧：一个 `lastFocusedAt` 让「未读」永远不亮，一个 `lastActivityAt` 让下班工位的幽灵座位占位、超过 12 小时也不走 | 已修 |
| R3b-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）`DesktopMeta.baseOverride` 被多个套件并行改写，R2-008 的测试间歇性变红（终审 R3b 40 次里 4 次，R3c 30 次里 4 次；R3c-03 是同一条） | 已修（修复前失败的证据是复查员的测量，我这边没能复现；如实写在这里） |
| R3b-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 隐私模式下桌牌标题、悬停卡片标题和项目路径的隐藏，没有任何测试钉住（变异全部存活） | 已修 |
| R3c-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 合并提醒「N 位同事在等你」的 N 是「最近 2 秒里发出的条数」，不是「被合并 / 正在等的人数」；被并进去的人的提示卡被撤掉后不会补回来 | 已修 |
| R3c-02 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 系统通知授权在运行期间被关掉后，兜底提示卡不出现（直到 App 下一次被激活 / 打开设置页） | 已修（真实的系统授权流程只能间接验证，见 REPORT 第 7 节） |
| R3a-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | hook-merge.py 会把 `1e400` 这类溢出成无穷大的数字写成 `Infinity`（不是合法 JSON），读回校验发现不了（`inf == inf`） | 不修（真实的 settings.json 里不会有这种数… |
| R3a-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | hook-merge.py 遇到孤立代理项字符（`"\ud800"`）时 `UnicodeEncodeError` 直接抛栈追踪；目标目录只读时留下一份备份 | 不修（不损坏数据，真实 settings.json 里不会有孤立代理项 |
| R3a-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `SessionEngine.processInbox` 用 `inbox.removeFirst()` 逐个出队：一次 poll 里积压 2 万条 hook 事件时是 O(n²) | 不修（真实使用里积压最多一两千条；只有 App 被挂起很久后的第一次 poll 可能卡 1 秒，且事件数有上限 |
| R3a-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `SubagentReader.helpers` / `order` 在会话存续期间只增不减 | 不修（没有实测影响，几百个小助手的会话极少 |
| R3a-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `BuddyCoreInfo.version = "0.1.0"` 没有任何人引用，注释还说 build-app.sh 也从这里读（实际读 `VERSION`） | 不修（无功能影响 |
| R3a-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `buddyctl dump` 的文档头说「绝不打印对话内容」，但表里「细节」列会打印工具 detail（命令 / 路径 / URL / 搜索词）和「桌面总结」 | 不修（开发命令，输出在用户自己的终端里；只是措辞过宽 |
| R3a-P3-07 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `dump --audit-opens` 文档说「只读地」，但和 `--persist` 一起给时会读写真实的 identities.json / ledger.json | 不修（开发命令，只有手敲两个开关一起给才会 |
| R3a-P3-08 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | Core 的 `SessionEngine.Options.dormantMax` 为负数时 `prefix(-1)` / `dropFirst(-1)` 会 trap | 不修（App 里不可达（设置的值先被夹过） |
| R3b-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 阿拉伯文 / 天城文 / 叠字符号 / 泰文标题在桌牌和悬停卡片里会被裁掉一截 | 不修（极少见的文字，只影响观感，不会溢出到别的元素上 |
| R3b-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `displayTitle` 的不可见字符清单不全：U+3164、U+2800、U+034F、变体选择符、只有组合附加符等 10 类标题仍会画出一块空桌牌 | 不修（极少见的标题，后果只是一块空牌子 |
| R3b-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 隐私模式下 MCP 屏幕仍画 server 名的首字母 | 不修（只泄漏一个字母；改它要动 ScreenContent 的画法和金图）… |
| R3b-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `AppLayerFixTests.swift:297` 在测试里不加锁地读全局 `staticCache.count` | 不修（只在测试里，没有复现 |
| R3b-P3-07 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 悬停的座位号为 `Int.max` / `Int.min` 时 `OfficeScene.render` 乘法溢出崩溃 | 不修（不可达 |
| R3c-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 时钟往回拨时（R2-014 的残留）：桌面会话「做完了」的 8 秒等待里时钟拨回，这条待发提醒卡到时钟追上为止；`recent` 里「来自未来」的记录被当成「刚发过」而错误合并 | 不修（极端场景（拨钟 + 桌面「做完了」的 8 秒窗口内）；后果只是一条提醒晚到 |
| R3c-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `AlertText.approvalBody` 对超长工具名在主线程上每次缩短 1 个字符就量一次提示卡宽度 | 不修（只有被写坏 / 恶意的 hook 数据能触发… |
| R3c-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 设置页「数据源诊断」的 `diag` 文字只在 `.onAppear` 和按钮里生成：先看过诊断，再在同一个设置窗口里打开隐私模式，切到诊断页看到的仍是带标题的旧文字 | 不修（窄：设置窗口重新打开就刷新 |
| R3c-P3-07 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 办公室里点小人是「命中座位号 → 点击那一刻按座位号找会话」，座位刚换主人的 ≤ 100 ms 内点旧画面会跳到新主人的会话 | 不修（窗口极小（一帧内换主人） |
| R3c-P3-08 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 开发副本在设置页里开关「开机启动」，会读写和正式版**同一个** LaunchAgent 文件 `~/Library/LaunchAgents/local.buddy-office.plist` | 不修（只影响开发副本 + 手动去点那个开关 |
| R3c-P3-09 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `StripPanelController.model` 是强引用、`AppModel` 持有 `strip`：循环引用 | 不修（App 全程只有一个 AppModel |
| R4a-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | R3a-02 的修复漏了应用层的第二个读取器：`DesktopMeta.readAll()` 没处理未来的 `lastFocusedAt`，一个会话永远是「最近聚焦的」，提醒丢失 / 无谓打扰 | 已修 |
| R4b-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）账本的 `.background` 队列在 CPU 饱和时被饿死，一族等它的测试间歇性变红（复查员整套默认并行 6 遍红 3 遍） | 已修（修复前失败的证据是复查员的测量，我这边没能复现） |
| R4a-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 合并卡「N 位同事在等你」的 N 可能比真正还在等的人数多 | 不修（极窄（两条提醒 < 2 秒且第一个人马上被批准），后果只是数字偏大 |
| R4a-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 「有事找你 / 做完了」型合并卡盖住了正在等的人之后，这些人处理完了系统通知中心里那条「N 位同事有事找你」不会被撤 | 不修（只是系统通知中心里多留一条 |
| R4a-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `NotificationService.statusText` 把 `.ephemeral` 显示成「已授权」，但 `systemAllowed` 只认 `.authorized` / `.provisional` | 不修（不可达 |
| R4a-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `NotificationService.post` 的 `liveKeys.count > 200 → removeAll()` 会把仍然有效的 key 也清掉 | 不修（三个条件同时成立才触发 |
| R4b-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `buddyctl flicker` 在非 demo 的模式（`--mode busy6` / `crowd12`，会话在启动时就在）的开头几帧会报「检查 2」：显示器开机的抖动渐变刚过渡到打字内容那一帧有约 10–12 个孤立像素 A→B→A（33 ms） | 不修（和严格模式下已知的那 13 处同一性质（1–5 个孤立像素，肉眼看不出）；改渐变会动金图 |
| R4b-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | R3 新加的三条测试会让 3–4 个线程空转很久 | 已修（顺手） |
| R4b-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `TextRenderer.image` 并发同一个 key 时，两个线程同时未命中会各渲染一次、`order` 里重复入队；淘汰时会把还有一个副本在队列里的 key 提前从缓存里删掉 | 不修（只影响命中率 |
| R4b-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `fuzzRun("flush inside onChange", timeout: 20)` 外层超时比里层 `waitUntilIdle(timeout: 60)` 短 | 已修（顺手） |
| R4b-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `openAudit_scopeKeepsConcurrentOpensOfOtherTestsOut` 的「不设范围的会被记进来」断言依赖噪声线程在 0.3 s 窗口内被调度到；忙机器上可能落空 | 已修（顺手） |
| R5a-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 出错提醒漏了两道闸：「桌面 App 里的会话也提醒」关着时桌面会话出错仍会提醒；你正在看那个会话时出错也照样提醒 | 已修 |
| R5a-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 排队等待中的「做完了」（最长 8 秒）不再读设置，用户在窗口里关掉提醒或 `includeDesktop` 后仍会发出一条 | 不修（极窄（8 秒窗口内改设置），后果只是多一条提醒 |
| R5a-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 应用层 `DesktopMeta.lastFocused` 接受布尔、0、负数、1999 年的值，引擎读取器拒绝 | 不修（不可达；R4a-01 只补了未来值 |
| R5a-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `hook-merge.py` 遇到嵌套很深的 JSON 时抛未捕获的 `RecursionError`，退出码 1 | 不修（真实的 settings.json 不会嵌套几百层 |
| R5a-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 隐私模式打开前已经出现的提示卡和已送达的系统通知不会被撤 | 不修（提示卡 6 秒后自己收；系统通知留在通知中心 |
| R5a-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 合并卡的人数还会把刚被隐藏的会话算进去（R4a-P3-02 的子情形） | 不修（极窄，数字偏大 |
| R5a-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `strip.align` 遇到认不出的值时，位置和场景对齐方向不一致 | 不修（手改偏好设置才触发 |
| R5b-01 | P2 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （测试基础设施）`noFileDescriptorLeaksAcrossReaders` 睡 0.3 秒就断言 fd 涨幅 ≤ 150，而 FSEvents 流停掉后的 fd 是异步释放的，机器一忙就间歇性变红（单独跑这一条也红） | 已修（修复前失败的证据是复查员的测量） |
| R5b-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `theOfficeHoverCardAppearsOnlyAfterTheMouseHasRestedFor250ms` 里 `onHover` 和取 `t0` 是相邻两句，测试线程恰好在两句之间被挂起 ≥ 250 ms 时保护会失效 | 已修（顺手） |
| R1a-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | hook-merge.py 的备份 / 临时文件先按默认 umask（0644）创建、写完内容再 chmod | 已修 |
| R1a-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `scripts/build-app.sh`：`swift build … ／ tail -4` 在 `set -e` 下没有 pipefail，编译失败被吞掉 | 已修 |
| R1a-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `安装.command`：`rm -rf "$DEST"` 之后 `mv "$STAGE" "$DEST"` 失败就没有 App 了（没有回滚） | 已修 |
| R2-006 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 隐私模式没盖住设置页「数据源诊断」和「测试深链」回执里的会话标题 | 已修 |
| R2-007 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 测试宿主进程里 `DebugTools.enabled` 恒为真（`--test-bundle-path` 匹配了 `--test-` 前缀） | 已修 |
| R2-008 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `DesktopMeta` 不认 `--data-root`：用假 home 起的开发副本仍读真实的桌面会话元数据 | 已修 |
| R2-013 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `scripts/measure.sh`、`scripts/soak.sh` 用 `pkill -f "$APP/Contents/MacOS"` 按路径子串杀进程 | 已修 |
| R2-014 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 系统时钟往回拨时，提醒的去抖 / 节流把提醒压住 | 已修 |
| R2-015 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | （A-019 的遗留）工具详情为空时桌牌 / 菜单栏文案出现「在读 」「在找 ""」「运行 」这种半截话 | 已修 |
| R2-016 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 拖窗口边缘时办公室 `PixelView` 每一步都新建 3 块 IOSurface（复查员评 P2「未定论」：测试宿主里占用 57 → 261 MB 不回落；真实 App 里复测没有复现保留，降为 P3） | 已修（作为降开销 / 防万一的改动：新建次数降到约 1/10；真实的内存保留没有复现，见「复测」） |
| R2-017 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 办公室窗口（普通 `NSWindow`）没关 `animationBehavior`：快速 show / hide 时窗口动画线程一路涨（B-010 的同类） | 已修（线程数随 show / hide 增长的真实症状只在测试宿主里量过，见 REPORT 第 7 节） |
| R1a-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | hook-merge.py 整体重写会规范化用户的 JSON 排版（缩进 2 空格、CRLF→LF；键顺序保留） | 不修（内容语义不变、键顺序保留、有备份；要保留原排版得自己写一个保持格式的 JSON 编辑器，收益太小（P3） |
| R1a-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `hook-merge.py --settings` 是最后一个参数时 `IndexError` 回溯 | 不修（仅测试用开关，不影响安装 / 卸载（P3） |
| R1a-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `hook-merge.py` 遇到带 UTF-8 BOM 的 settings.json 会以「不是合法 JSON」拒绝（提示不准） | 不修（拒绝的行为是安全的，Claude Code 自己写的 settings.json 没有 BOM（P3） |
| R1a-P3-07 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `TokenLedger.writeLedger`：仍被跟踪但还没扫完的文件（启动后立刻退出）的旧断点会被丢掉；持锁时对每个旧断点 `stat` 一次 | 不修（只影响冷启动重扫的时间，账本不会错（P3） |
| R1a-P3-08 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `FileWatcher.start()`：`~/.claude` 启动时不存在（Claude Code 还没装）则 FSEvents 起不来，整个运行期停在 50–100 ms 轮询 | 不修（没装 Claude Code 时这个 App 没有意义；轮询本身正确（P3） |
| R1a-P3-09 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `SessionEngine.bootstrapDormants`：首次 poll 时登记表恰好读不出来，会把实际在跑的桌面会话先当成下班工位，再「走回来」 | 不修（极窄的时间窗（登记表半截文件），后果只是一次多余的走路动画（P3） |
| R1a-P3-10 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `ProcessProbe`：僵尸进程被当成活的 | 不修（僵尸进程很快被回收，登记表里的记录也会被 Claude Code 清掉（P3） |
| R1a-P3-12 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `hook-merge.py`：用户特意设成只读（0444）的 settings.json 也会被替换（模式保持 0444） | 不修（写 settings.json 是用户明确要求的安装动作；模式保持 0444、有备份（P3） |
| R1b-P3-01 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 对负的 `time` 不设防（`PoseLibrary.frame(.writingPad, t < -0.134)` 下标越界、`RoomRenderer.plantPhase(time < 0)`） | 不修（不可达（P3）；真要防再加 `max(0, t)` |
| R1b-P3-02 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `OfficeScene` 里 `walkers.cleanup` 在 `finishedEntering` 之前，进场走完后只有 50 ms 的窗口能记下坐下时刻 | 不修（纯观感，只在主线程严重卡顿时发生（P3） |
| R1b-P3-03 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `Canvas.cropped(rect)` 在 rect 和画布不相交时返回 1×1 的左上角像素（A-009 修了 `writeBGRA`，同类的没跟着改） | 不修（不可达（P3） |
| R1b-P3-04 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 开发用 CLI 两处会 trap：`buddyctl snapshot --cells 0`、`buddyctl cell --cloth 99 / -1` | 不修（开发命令行的非法参数（和 A-029 同类，P3） |
| R1b-P3-05 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 泰文 / 藏文 / Zalgo 这类叠字符号的标题，符号被文字图片上边缘裁掉一截 | 不修（极少见的文字，只影响观感（P3） |
| R1b-P3-06 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `drawMonitor` 开机 / 关机渐变期间每个座位每帧新建一张世界大小的草稿 `Canvas` | 不修（`buddyctl bench` 实测办公室每帧总共 0.18 ms，可忽略（A-025 同类，P3） |
| R1b-P3-07 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 气泡像素没有命中 ID：办公室里点气泡没反应、宠物条里鼠标穿过气泡 | 不修（任务书只要求点小人跳转；顺手把注释和行为对齐留给以后（P3） |
| R1b-P3-10 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 摄像机注释和代码不一致：注释写「滚动到有人要你或最后一行」，代码在没人等你时保持上一个目标 | 不修（请设计者确认是不是有意的（P3） |
| R2-009 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 入口兜底只在「设置变了」时重算（A-024 的残留） | 不修（极窄的用法… |
| R2-010 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 宠物条 3 倍 + ≥ 9 人时比 1408 pt 宽的屏幕还宽（origin.x = -16），最左边的人被挤出屏幕 | 不修（极端组合，可以把缩放调小或减少会话（P3） |
| R2-011 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | `setDemo` 不清旧数据源的 `onUpdate`，切换那一刻排在主队列里的尾巴回调会写进新状态 | 不修（可能但概率很低，后果只是切换瞬间多一帧旧快照（P3） |
| R2-012 | P3 | 收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的） | 主菜单没有 ⌘W / ⌘H / 编辑菜单 | 不修（红色关闭按钮可用，退出有 ⌘Q；补标准菜单是 UI 增强（P3） |

---

## 详细记录：表现层 / 文字审计（来自 issues-stage.md）

来源：新增的 `buddyctl text-audit`（按 CoreText 真实笔画检查 8 类文字问题，见 `Sources/BuddyStage/TextAudit*.swift`）+ 任务书 6.5 / 6.6 逐条追踪（`spec-trace-ui.md`）。
严重度：P0 崩溃 / 数据损坏 / 违反安全红线；P1 明显错误的行为 / 关键信息看不清；P2 边界条件下的错误或体验缺陷；P3 小瑕疵 / 工具卫生。
「修复前失败」的证据是 `QA/tools/verify_fail_before.py` 在隔离工作树里逐个撤销修复、再跑同一个回归测试得到的（输出在 `QA/evidence/fail-before-stage.md`）。

## 第一次全量审计的数字（修复前，2026-09-29 03:1x，1880 个组合）

| 类别 | 违规数 |
|---|---|
| 1 文字互相重叠 | 0 |
| 2 超出容器或被裁切 | 4082 |
| 3 该省略没省略 | 0 |
| 4 盖住脸 / 屏幕 / 气泡 / 卡片 | 80 |
| 5 字号小于 9 pt | 0 |
| 6 对比度低于 4.5:1 | 3742 |
| 7 没有对齐到整数像素 | 0 |
| 8 像素数字粘连 | 232 |
| **合计** | **8136** |

修复后同一个矩阵 0；之后把矩阵扩大到 8598 个组合（含 41 个座位「所有状态同时出现」、窗口只露出一部分的座位、悬停卡片四个角）再审，又抓到 TA-011 / TA-012（见下），全部修完后 **0 违规**。

---

### TA-001 [P1] 桌牌文字对比度不足（白天状态行 2.91:1，夜里最差 1.5:1）
- 现象：办公室里每个座位桌牌上的标题 / 状态文字，白天状态行只有 2.91:1（标题 3.79:1）；夜里被压暗的木板上更糟，最差 1.52:1，几乎看不清。第一次审计 3742 处。
- 根因：文字是单独的一层、颜色固定的棕色（标题 `0x3A2A22`、状态 `0x6E4C38`），而桌牌木板会被昼夜的时段 LUT 压暗（白天 L≈0.55，夜里 ≈0.26）。中途一次「夜里换浅色字」的修法被审计推翻（浅色字压在夜里的中灰木板上只有 2.6:1）。
- 修法：桌牌文字全天用深色（标题 `0x1E1518`、状态 `0x261A20`）：木板白天 / 夜里 / 抖动过渡的半亮半暗棋盘格上都 ≥ 4.5:1；下班工位的桌牌是深胡桃木，用浅色字（`0xF8EFDD` / `0xF0E2CB`）。`OfficeScene.plateTitleInk` 等。
- 回归测试：`TextAuditRegressionTests/plateTextMeetsContrastAtAnyTimeOfDay`（3 个时刻 × 4 个缩放）+ 全矩阵第 6 类。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（11 个 issue）：`✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "23:00", zoom → 3 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1]…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-001」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-002 [P1] 桌牌放不下标题 + 状态两行，字被切 / 顶出桌牌
- 现象：缩放 ≥ 3× 时，桌牌上第二行状态的笔画超出桌牌内部（例：笔画 (241,1221 191×22) 不在容器内部 (186,1194 300×48) 里）；4082 处。
- 根因：桌牌底板只有 10 个美术像素（内部 8 个），两行文字的真实笔画高度（标题 11 pt + 状态 10 pt）放不下；排版又是按行盒高度居中，而不是按笔画范围。
- 修法：桌牌高度 10 → 12 像素（`SeatGeometry.plateH`，整个布局的行距同步 +2）；文字按真实笔画范围（`inkExtent`，用「测Agpy」量）在桌牌内部垂直居中，两行之间留 1.5 pt；缩放 1× 时桌牌只有 12 pt 高、放不下字，不画桌牌文字（悬停卡片里有全部信息）。
- 回归测试：`TextAuditRegressionTests/twoLinePlateTextStaysInsideThePlate`（缩放 3 / 4 / 5 × 正常 / 长中文 / 混排标题）+ 全矩阵第 2 类。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（3 个 issue）：`✘ Test twoLinePlateTextStaysInsideThePlate(zoom:) recorded an issue with 1 argument zoom → 3 at TextAuditTests.swift:206:13: Expectation failed: (v → [[2·超出容器或被裁切] 办公室 ：「在改 LoginView.s」(plat…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-002」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。DESIGN.md「与任务书不一致」表新增一行。

### TA-003 [P3] emoji 标题的字形比苹方高出一截
- 现象：标题里有 emoji 时，系统回退到 Apple Color Emoji，同样字号下字形上下各多出 1–2 pt，顶出桌牌 / 卡片的边。
- 根因：桌牌 / 卡片的行盒按苹方量，emoji 字形更高。
- 修法：`TextRenderer` 把 emoji 缩到 0.78 倍（`AppleColorEmoji` 字体，同一行里中文不变）；缩放之后 emoji 的笔画范围落在苹方（中文 + 拉丁字母的上伸 / 下伸）的笔画范围里。
- 回归测试：`TextAuditRegressionTests/emojiInkStaysInsideTheCJKInkRange`（10–13 pt）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（8 个 issue）：`✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 10 at TextAuditTests.swift:219:9: Expectation failed: (emoji.y >= cjk.y - slack → false) && (emoji.y …`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-003」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-004 [P3] 睡着的「zzz」两个 z 粘在一起
- 现象：睡着 / 打盹的人头上的气泡里，两个 3 像素宽的 z 挨着（间隔 0）。232 处「像素数字粘连」。
- 根因：第一个 z 画在 `ix + 1`、第二个画在 `ix + 4`，两个都是 3 像素宽，正好贴上。
- 修法：第一个 z 画在 `ix`，中间隔 1 像素（7 像素的图标区刚好放下）。
- 回归测试：`TextAuditRegressionTests/sleepingBuddysTwoZsDoNotTouch`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（2 个 issue）：`✘ Test sleepingBuddysTwoZsDoNotTouch() recorded an issue at TextAuditTests.swift:241:63: Expectation failed: (zs[a].rect.insetBy(-1).intersection(zs[b].rect) → IntRect(x: 77, y: 66, w: 1, h:…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-004」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-005 [P2] 空办公室的「今天还没人上班」牌子：字对比度 4.45:1，还被后画的桌椅盖住（4× 时最差 1.09:1）
- 现象：一个会话都没有时办公室中间的牌子，文字对比度不够，缩放 4× 时牌子被后画的桌椅盖住一大块。
- 根因：牌子在背景里烘焙（先于桌椅画），位置在视口正中，正好压在桌子上；字色 `0xE6D4BC` 在胡桃木牌面上 4.45:1。
- 修法：牌子改成在合成时画在桌椅上面；位置挪到最后一张桌子后面那个空格子的地毯上（那里本来就是给下一个同事留的空位），排满一整排时才放视口正中；字色 `0xF8EFDD`。
- 回归测试：`TextAuditRegressionTests/emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks`（缩放 1–5 × 白天 / 夜里；断言牌面像素是胡桃木色）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（9 个 issue）：`✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 2 at TextAuditTests.swift:253:13: Expectation failed: (r.audit() → [[6·对比度低于 4.5:1] 办公…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-005」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-006 [P2] 悬停卡片盖住被悬停那个人自己的脸 / 屏幕 / 气泡；卡片下面的桌牌文字浮在卡片上
- 现象：窗口小的时候悬停卡片盖住那个人的脸、屏幕或气泡（80 处）；办公室的文字层在画布上面，被卡片盖住的桌牌文字不会被盖住，浮在卡片上和卡片的字叠在一起。
- 根因：卡片位置只夹进视口，不管人在哪；桌牌文字和卡片没有互相知道。
- 修法：位置搜索——依次试「他右下 / 左下 / 正上方 / 正下方（横向夹进窗口）/ 两侧」，要求整张卡片都在窗口里、不盖住他的头 / 屏幕 / 气泡；放不下先去掉次要的行把卡片缩小（4 档）；被卡片盖住的桌牌文字收起来。
- 回归测试：`TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner`（4 种窗口 × 3 个缩放 × 四个角的座位）、`plateTextUnderTheHoverCardIsHidden`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（6 个 issue）：`✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swi…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-006」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-007 [P3] 窄窗口里悬停卡片比窗口还宽 1 像素，放不下
- 根因：卡片宽度上限按「窗口宽 − 4」个美术像素反推，比「左右各留 2 像素」的要求多出 1 个美术像素。
- 现象：窗口很窄（260 pt）时悬停卡片放不进去（卡片宽度上限按窗口宽度减 4 算，比窗口两侧各留 2 像素多出 1 个美术像素）。
- 修法：上限反推为「窗口宽 − 5」个美术像素对应的点数。
- 回归测试：同 TA-006 的悬停测试（含「很窄」窗口）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（3 个 issue）：`✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "很窄", wPt: 260, hPt: 700), zoom → 3 at TextAuditTests.swi…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-007」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-008 [P3] 窗口再小也要有悬停卡片（兜底位置）
- 根因：每个候选位置都要求「整张在窗口里 + 不盖住那个人」；最小窗口里同时满足的位置不存在，原来的处理是干脆不画。
- 现象：最小窗口（200×220 pt）里，各候选位置都会盖住那个人，卡片整个不画：鼠标悬停没有任何反应，桌牌上又只有被省略的一行。
- 修法：候选位置都放不下时，在窗口里每隔 2 像素搜一个离首选位置最近、又不盖住头 / 屏幕 / 气泡的地方（压在身体 / 椅子 / 桌牌上，桌牌文字收起来）。text-audit 现在把「悬停组合里没画出卡片」也判为失败（`Report.hoverCardsMissing`），不会再因为没有卡片而「0 违规」。
- 回归测试：同 TA-006（断言每个悬停都有卡片）+ `TextAuditMatrixTests`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（6 个 issue）：`✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swi…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-008」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-009 [P3] 窗口比一个整工位还窄 / 还矮时，设置里的大倍数把工位切掉一半
- 根因：实际缩放只按窗口宽度夹（至少放得下一列），窗口高度不参与：窗口比一个工位还矮时工位被切掉一半。
- 现象：最小窗口 200×220 pt 里选 5× / 3×，工位只露出一半，桌牌看不见，悬停卡片找不到不盖住人的位置。
- 修法：`OfficeLayout.effectiveZoom` 把倍数夹到「至少放得下一个整工位（一列宽 64、一行高 80 美术像素，含桌牌）」：最小窗口最多 2×，矮宽窗口（900×260）最多 3×。
- 回归测试：`TextAuditRegressionTests/zoomIsClampedSoAtLeastOneWholeSeatFits`（含 200…900 × 220…900 × 设置 1–5 的全组合断言）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（135 个 issue）：`✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:301:9: Expectation failed: (OfficeLayout.effectiveZoom(setting: 5, contentW: 200, contentH: 220, max…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-009」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-010 [P3] 空标题 / 全空白标题变成一块空牌子
- 现象：标题为空 / 全空白时桌牌是一块空牌子、卡片标题一行空白。
- 根因：显示层直接使用数据层给出的标题，没有占位。
- 修法：`PlateCopy.displayTitle`：空白标题显示「（没有标题）」（数据层不会给出空标题，但显示层不能因此出空牌子）。
- 回归测试：`TextAuditRegressionTests/blankTitlesGetAPlaceholderOnPlatesAndCards`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（3 个 issue）：`✘ Test blankTitlesGetAPlaceholderOnPlatesAndCards() recorded an issue at TextAuditTests.swift:317:9: Expectation failed: (PlateCopy.displayTitle("") → "") == "（没有标题）"`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-010」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-011 [P3] 审计工具自己的 bug：窗口上边外面的文字，对比度读错画布行（假阳性）
- 现象：41 个座位、窗口里只看得见中间几个时，看不见的桌牌被报「对比度 3.34:1」（60/588 个笔画像素，正好超过 10% 的阈值）。
- 根因：文字有一部分在窗口上边外面时设备像素坐标是负的，Swift 的 `/` 向零取整，把它映射到差一行的画布行。
- 修法：`TextAudit.floorDiv`（向下取整）。
- 回归测试：`TextAuditDetectorTests/floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow`；端到端由缩减矩阵测试（含 41 座位组合）兜底。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（6 个 issue）：`✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → 0) == (want → -1)`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-011」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修（工具）。

### TA-012 [P2] 「其他 MCP」屏幕的 server 首字母画成「?」
- 根因：4×6 像素字体只画了数字和 M / K / x；首字母的取法不管字体有没有这个字形。
- 现象：4×6 像素字体只有数字和 M / K / x；notion、ccd_session、terminal 等几乎所有 MCP 的首字母都落到「?」占位字形（演示里 notion 画成「?」）。审计扩大到 41 种状态同时出现之后才抓到（此前的矩阵最多 20 个座位，够不到这种状态）；spec-trace S15b 也独立发现了。
- 修法：4×6 字体补 A–Z；首字母取名字里第一个字体画得出的字母，全是中文 / 数字 / 符号时用 M。
- 回归测试：`ScreenContentTests/theSmallPixelFontDrawsEveryLatinCapital`、`aMcpServersInitialIsALetterTheFontCanDraw`、`theMcpAppScreenNeverFallsBackToThePlaceholderGlyph`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（102 个 issue）：`✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:21:13: Expectation failed: (PixelFont.small → PixelFont(name: "4x6", height: 6, glyphs: ["-": […`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-012」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### TA-013 [P2] Bash 长任务的进度条被人的头挡住
- 根因：进度条按屏幕倒数第 3 行摆（第 12–13 行），而人的头挡住第 12 行以下。
- 现象：终端 + 进度条（任务书 6.5「按 1−e^(−t/τ) 增长，永远不会假装跑满」）画在屏幕第 12–13 行，正好是人的头挡住的区域，只露出最左边一小段绿色；这条「长任务还在跑」的关键信息看不出来。
- 修法：进度条移到提示符下面（第 5–6 行），输出行下移（只剩两行）。
- 回归测试：`ScreenContentTests/theLongBashProgressBarIsAboveTheRowsTheHeadHides`、`aLongBashBarGrowsButNeverFillsUp`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（5 个 issue）：`✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「TA-013」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### SP-01 [P2] 显示器关机是一帧硬切成黑屏（任务书 5.5 / 6.6：关机也是 300 ms 渐变，绝不黑帧）
- 根因：离场后座位立刻变成「没人」，屏幕直接按 off 画，没有保留最后的内容去做渐变。
- 现象：人离开时屏幕在一帧里变黑（看图 t=60.00→60.03），开机却是 16 级 Bayer 抖动渐变。
- 修法：`OfficeScene` 记住每个座位上一次有人时屏幕的内容；人一离开，把那块内容用 Bayer 抖动倒放 300 ms（`SeatView.fade`）；渐变期间整张重画（局部重绘和整张重画逐像素一致由 `buddyctl verify` 与测试保证）。小鱼缸 / 宠物条没有离场动画，桌子直接空出来（DESIGN 记为简化）。DESIGN 里「5 级」改成实际的 16 级。
- 回归测试：`MonitorTests/theMonitorFadesOutOver300msInsteadOfCuttingToBlack`、`retainedRenderingStaysIdenticalWhileTheMonitorFadesOut`、`anEmptySeatNeverFades`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（2 个 issue）：`✘ Test theMonitorFadesOutOver300msInsteadOfCuttingToBlack() recorded an issue at MonitorTests.swift:60:9: Expectation failed: ((after.first?.lit ?? 0) → 0) > (Int(Double(before.max() ?? 0) *…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「SP-01」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### SP-02 [P3] 指示灯是开关式的（任务书 6.6：不许开关式闪烁；等待时的光晕 3 个相邻色阶 0.8 Hz）
- 根因：指示灯只有「亮 / 灭」两档（调色板里只有 led.on / led.off / led.wait），没有中间色阶。
- 现象：待机灯 2 秒亮 2 秒灭；等待（等批准 / 提问 / 计划待审）时的琥珀灯是固定色，没有「光晕」。
- 修法：待机灯 3 阶呼吸（灭 → 半亮 → 亮 → 半亮，周期 4 s）；等待灯 3 个相邻色阶循环（暗 → 亮 → 更亮 → 亮，周期 1.25 s = 0.8 Hz）。主调色板加 3 个自发光色。「1 Hz、2 像素的轻弹」由已有的举手挥动（1.2 Hz）承担，DESIGN 记为简化。
- 回归测试：`MonitorTests/theStandbyLightBreathesThroughThreeLevelsSlowly`、`theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz`、`activeAndAbsentLightsStayPut`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（? 个 issue）：`✘ Test theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz() recorded an issue at MonitorTests.swift:137:9: Expectation failed: (Set(seq.map(\.name)) → ["led.wait"]) == (["led.wait.lo", "…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「SP-02」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### SP-03 [P3] 连续滚动的屏幕节奏不均匀
- 根因：滚动步长是 150 / 300 ms 这种和 15 fps 渲染节拍（66.7 ms）不成整数倍的时间，帧落在步的边界上。
- 现象：文档每 150 ms 滚一行、日志每 300 ms 滚一行，办公室稳态 15 fps（66.7 ms 一帧）时每步占 2、3、2、3 帧（日志 4、5、4、5），滚起来一顿一顿；DESIGN 第 7 节给打字专门解决过同样的问题，这里漏了。
- 修法：文档 133 ms（2 帧）、终端 400 ms（6 帧）、日志 333 ms（5 帧）一步；时刻加 20 ms 偏移让帧落在一步中间，计时抖动不会多 / 少一帧。
- 回归测试：`ScreenContentTests/documentAndLogScrollingStepsAreWholeFramesAt15fps`（含 ±10 ms 抖动）、`rhythmStepsAreEvenAndNeverSkip`。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（4 个 issue）：`✘ Test documentAndLogScrollingStepsAreWholeFramesAt15fps() recorded an issue at ScreenContentTests.swift:88:13: Expectation failed: runs.allSatisfy { $0 == frames }`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「SP-03」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### SP-04 [P3] WebSearch 只用鼠标、未知工具只打字（任务书 6.5：先打字再用鼠标 / 打字和鼠标交替）
- 现象：WebSearch 只用鼠标、未知工具只打字（任务书 6.5：先打字再用鼠标 / 打字和鼠标交替）。
- 根因：targetPose 里这两类没有随时间切换的分支。
- 修法：WebSearch 开头 2.5 秒打字再用鼠标；未知工具每 3 秒在打字和鼠标之间换。
- 回归测试：`PerformerMappingTests/everyRowOfTheStateToAnimationTable`（6.5 表每一行的姿势 / 屏幕 / 气泡逐行断言，这一层之前只有金图哈希）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（2 个 issue）：`✘ Test everyRowOfTheStateToAnimationTable() recorded an issue at PerformerMappingTests.swift:81:13: Expectation failed: (p.targetPose(now: now, time: row.elapsed) → .mouse) == (row.pose → .t…`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「SP-04」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。

### SP-05 [P2] App 启动时就在的会话：显示器不是依次开机，而是所有人一起「啪」地亮起（任务书 5.5：直接坐好，显示器从左到右依次开机，每台间隔 100 ms）
- 现象：启动时已经在跑的会话，每个人先是空闲姿势 + 黑屏，0.8 秒（屏幕最短停留）后所有屏幕同一帧亮起（没有开机抖动，因为开机渐变已经在黑屏期间放完了），1.5 秒后姿势一起变成真正的动作。实测四个座位的屏幕首次亮起时间 0.567 / 0.833 / 0.833 / 0.833 秒。spec-trace 只看到了「同时开机」，没意识到连开机动画都丢了。
- 根因：`Performer` 三个通道的「最短停留」（姿势 1.5 s、屏幕 0.8 s）对第一次赋值也生效；`OfficeScene` 的开机进度对所有人都从出生时刻算起。
- 修法：`appearedAfterLaunch == false` 的表演者第一帧就采用真正的姿势 / 屏幕（不等最短停留）；办公室里这些人的开机进度往后推 `座位序号 × 100 ms`（按座位号从左到右，总延迟封顶 1.5 s）。启动之后才来的人是走进来坐下再开机，不变。
- 回归测试：`MonitorTests/monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals`（四台屏幕首次亮起的间隔 = 0.1 s ± 0.045，第一台在 0.15 s 内）。
- 修复前失败：撤销这个修复后重跑回归测试 → 失败（4 个 issue）：`✘ Test monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() recorded an issue at MonitorTests.swift:108:9: Expectation failed: ((firstLit[0] ?? 9) → 0.5666666666666667) < 0.15`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「SP-05」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。
- 状态：已修。


### SP-06 [P2] 某个人正在「错开」推迟里时，变成等待类（等批准 / 提问 / 计划待审）的状态晚到最多 0.6 秒，还会先闪一帧过期的旧动作（任务书 5.6：等待类最多 250 ms 就立即插入）
- 现象：同一帧里多个人变化时，第 k 个人的变化被错开成「晚 min(0.6, 0.09 × k) 秒才应用」。这个人在推迟期间又变成等待类时，表演者一直显示推迟之前的旧动作，推迟到点那一帧套用的是推迟开始时存下的**过期**快照（不是等待态），下一帧才切到等待。实测（10 个人同一帧 Read → Edit，第 10 个人在 2.1 秒变成等批准）：等待状态晚了 0.567 秒才显示（应 ≤ 0.25 秒），中间有 1 帧显示的是过期的 Edit。是规格追踪定稿（`QA/spec-trace-core-final.md` 遗留缺口 G-1）时发现的。
- 根因：`VisualDirector.update` 里只有「变了 && 不是等待类」才登记 / 刷新 pending，等待类分支什么都不做，但下面 `if let pd = pending[s.key]` 仍然按「没到点就沿用旧快照、到点套用 pd.snap」处理，把等待类拦在推迟后面。
- 修法：等待类快照到来时先清掉这个人的 pending（`if s.activity.needsUser { pending.removeValue(forKey: s.key) }`），直接套用最新快照；不影响别的人的错开。
- 回归测试：`SpecTraceStageTests/aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately`（原来是用 `withKnownIssue` 钉住这个缺口，修好之后去掉了包装）；`PerformerTimingTests` 的错开测试（5 人相邻 ≈ 90 ms、10 人封顶 0.6 秒）照常通过。
- 修复前失败：`✘ Test aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately() recorded an issue at SpecTraceStageTests.swift:172:9: Expectation failed: ((waitingAt ?? 99) - 2.1 → 0.5666666666666669) <= (0.25 + 1.0 / 30)`；`…:173:9: Expectation failed: (staleFrames → 1) == 0`（2 个 issue）；修复后 `✔ Test run with 27 tests in 3 suites passed`（SpecTraceStageTests + PerformerTimingTests + PerformerMappingTests）。
- 状态：已修。


### SP-07 [P3] Edit 屏幕「字符逐个出现」被高亮行里原来就画着的一条白线遮住了一部分
- 现象：Edit 屏幕（`.diffEdit`）里高亮的那一行先画一条 3–13 像素长的白线（长度按 `hash(seed, 3) % 11` 取），之后 `chars = min(14, Int(t*6))` 才接着往后画字符，所以只有超过这条线的部分才看得出「逐个出现」，多数种子下前几个字符一开始就在了。是规格追踪定稿（`QA/spec-trace-ui-final.md` §10 G-01）写测试时发现的。
- 根因：高亮行的底线和逐字出现的内容画在同一行，底线没有跟着 `chars` 一起增长。
- 修法：不修。屏幕内容只有十几个像素宽，「逐个出现」少了前几个字符肉眼几乎看不出；改它会让所有 Edit 屏幕的画面变化，金图和 `SpecTraceUITests` 里钉住当前画法的断言都要重审，风险大于收益（P3）。
- 回归测试：无（`SpecTraceScreenTests/editTypesCharactersAndWriteAddsRowsFromTheTop` 钉住当前行为，为了看清增长专门挑了白线最短的种子）。
- 状态：不修（P3，理由见修法；记录在 QA/REPORT.md 第 8 节）。

### SP-08 [P3] Grep 结果列表的高亮条走到最后一行后停 1.2 秒，然后一帧跳回第一行
- 现象：`ScreenContent.draw(.results, t:)`：`sel` 用 `smoothstep` 只缓动了「往下走」，`t mod 2.4` 回绕时没有缓动；t = 1.2–2.4 秒高亮固定在第 3 行，t = 2.4 秒一帧回到第 0 行。是规格追踪定稿（`QA/spec-trace-ui-final.md` §10 G-02）发现的。
- 根因：循环动画的回绕没有做往返 / 淡出。
- 修法：不修。屏幕内容是十几个像素宽的循环小动画，回绕那一帧的跳变在 15 fps 下不构成「闪烁」（闪烁扫描全部干净），而且改它会让所有 Grep 屏幕的画面变化、金图要重审（P3）。
- 回归测试：无。
- 状态：不修（P3，理由见修法；记录在 QA/REPORT.md 第 8 节）。

### SP-09 [P3] 既有测试在测试宿主进程的偏好域里留痕迹（`NSWindow Frame BuddyOfficeTankPanel`）
- 现象：`PanelAnimationTests` 建了一个 `TankPanelController()`，AppKit 会按 `setFrameAutosaveName` 把面板位置写进测试宿主进程（`swiftpm-testing-helper`）的偏好域 `~/Library/Preferences/swiftpm-testing-helper.plist`。不是 App 的偏好文件，但属于测试在用户偏好目录里留的痕迹（`QA/spec-trace-ui-final.md` §10 G-03，定稿员在 05:38 看到过这个键）。
- 根因：测试没有在收尾时清掉自动记位置的键。
- 修法：`PanelAnimationTests.everyFloatingPanelHasWindowAnimationsTurnedOff` 收尾时 `UserDefaults.standard.removeObject(forKey: "NSWindow Frame BuddyOfficeTankPanel")`（所有断言原样保留，只加了清理）；新增的 `SpecTraceUITests` 里本来就有 `forgetAutosavedFrames()`。
- 回归测试：这条本身就是测试卫生；跑完 `BuddyOfficeTests` 之后 `plutil -p ~/Library/Preferences/swiftpm-testing-helper.plist` 里没有 `NSWindow Frame` 键（`QA/evidence/regression-final/summary.txt` 的「测试痕迹」一行）。
- 状态：已修。

---

## 审计工具本身的改进（不是产品问题）

- `text-audit` 覆盖补全：所有 41 种状态同时出现（办公室 41 个座位；小鱼缸 / 宠物条最多画 8 个人，用 `stateOffset` 依次错开，每种状态至少出现一次）；悬停矩阵改成「至少露出 40% 的座位」里离四个角最近的（窗口比一个工位还小时也能悬停）；`--window WxH` 调试选项；违规图片带坐标、大画面只截违规附近。
- 检测器灵敏度：8 类各造一个必须抓到的违规输入 + 对应的干净输入（`TextAuditDetectorTests`）；变异验证（让 `check()` 对某一类一律不报，对应的灵敏度测试必须失败）见 `verify_fail_before.py` 的 `MUT-1…8`。

## 不修 / 只能间接验证
- 闪烁扫描的严格模式（容忍度 0）在办公室场景有 14 处 1–5 个孤立像素的 A→B→A（33 ms 一帧，手臂 IK 取整 / 走路的人边缘）。标准阈值（≤ 6 像素容忍，DESIGN 第 10 节）下 3 个场景 × 3 个缩放、每个 2398 帧全部干净。这 14 处肉眼看不出，不修，如实记录。

## 顺手接下的、数据层报告转交给表现层的项
- **C-033 [P3]**（`issues-core.md`）表现层对时间差里的 NaN / 无穷 / 天文数字直接 `Int(x)` 会 trap：`PlateCopy.wholeSeconds`（基于 `safeInt`，夹到 0…10 亿秒）用在 `duration / spoken / waitSpoken / idleMinutes`，`HoverCard.ago` 同样；`Performer` 里 MCP / 未知工具的 `safeInt(elapsed / 3)`。回归测试 `ExtremeValuesTests`（格式化函数不 trap、快照里所有时间都是怪值时桌牌 / 卡片 / 表演者 / 整个场景渲染不崩）。修复前失败：`wholeSeconds` 换回 `Int(x)` 后测试进程 SIGTRAP。已修。
- **C-031 [P3]** 既有测试文件 `HelperAttributionTests.swift:262` 里的两条编译警告（`#expect((a?.b ?? []).isEmpty)` 宏展开）：把取值拿到宏外面（`let shown = … ?? []; #expect(shown.isEmpty)`），断言的意思不变。已修。

## 新增覆盖（不对应 bug，为了让规格追踪里「只有金图哈希、没有语义断言」的行有测试）
- `PerformerMappingTests`：任务书 6.5「状态 → 动画」表逐行断言（姿势 / 屏幕 / 气泡）+ 思考 > 20 s、Bash 3 / 8 s、WebSearch 先打字、其他 MCP / 未知工具打字鼠标交替、被打断 1.5 s、做完 0.4 / 1.6 s、后台小助手、blocked 便利贴。
- `WalkersAndOffDutyTests`：进场（约 2.5 秒、远座位走路速度封顶、启动时就在的直接坐好）、离场（起身 → 挥手 → 走出门 → 门关上）、下班工位（椅子推进去、桌牌变暗、点不到、外套挂在衣帽架上）。
- `HitTestingTests`：命中缓冲（对象 ID 平面）——每个座位 ID 的像素都落在那个座位自己的格子里、每个在场的人都点得到、下班 / 空座位点不到、座位号再离谱 `hitID` 也不崩。这是「点击 buddy 不会跳到别人的会话」在渲染这一半的证据（应用层这一半是 `BuddyOfficeTests/JumpTests`）。
- `SourceAuditCoreTests`（BuddyCoreTests 里）：数据层 / 画布 / 美术 / 表现层 / 命令行工具的源码审计——不联网、不碰凭据、不起子进程、读文件只有 FileIO 一个入口（白名单 5 个文件，改名 / 删除会红）、读数据的代码里不出现 `.key` / `.sock` 字面量。应用层有自己的一份 `SourceAuditTests`。

---

## 详细记录：应用层（来自 issues-app.md）

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

---

## 详细记录：数据层（解析器 / 模糊测试）（来自 issues-core.md）

> 日期：2026-09-29　范围：`Sources/BuddyCore/**`（31 个 Swift 文件）　方法：把它当成别人写的代码，独立审查 + 确定性模糊测试。
> 铁律遵守情况：全程只用临时目录里的假数据；没有打开过任何 `*.key`、没有连过任何 `*.sock`、没有读过任何凭据；没有改 `~/.claude`、ccmon、用量表、Claude.app；没有联网、没有 pkill、没有动正在运行的 App；
> 没有削弱 / 跳过 / 删除任何已有测试，也没有屏蔽编译警告（BuddyCore 在两套配置——隔离包 -Onone、根包 -O——下都是 0 警告；release 配置我没有单独编）。
> 只改了 `Sources/BuddyCore/**` 和 `Tests/BuddyCoreTests/**`（新增测试全在 `Fuzz*.swift` 里，另外在 `FileAccessTests` 的**扩展**里加了几个必须和它串行跑的测试——没改别人的测试文件）。

## 0. 结论与统计

**发现 33 个**：P0 6 个 / P1 5 个 / P2 5 个 / P3 17 个；**已修复 30 个**，3 个未修复（都是范围外，见 C-031 / C-032 / C-033）。另有 2 条「已确认不是问题」（C-034 / C-035，不计入上面的数）。
**新增测试 86 个**（`Tests/BuddyCoreTests/Fuzz*.swift`；其中 31 个是回归测试，对应每一条已修复且能构造出失败输入的发现，其余是模糊 / 属性 / 压力测试）。

测试命令与结果（都在沙箱外跑；scratch 目录 `.build-qa-core`，`-j 2`，收工时已删除）：

| 命令 | 结果 |
|---|---|
| `BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core scripts/dev.sh test --filter BuddyCoreTests -j 2`（隔离数据层包；BuddyCore 用 -Onone）| **374 个测试（33 个套件）：373 通过、1 失败**。失败的是别的 QA 的 `StateRuleChainTests/chain1`：它检查 `Sources/BuddyOffice/RealProvider.swift` 的源码文本里有 `SessionStore(dataRoot:`，应用层把它改成 `SessionStore(options:)` 之后这条断言过时了，与 BuddyCore 无关。其余包括我新增的 86 个全部通过 |
| `BUDDY_SCRATCH=.build-qa-core scripts/dev.sh test --filter BuddyCoreTests -j 2`（根包；BuddyCore 用 -O）| **374 个测试（33 个套件）：373 通过、1 失败**（同一个 `chain1`）。全量约 49 秒（隔离包因为 -Onone 更慢，约 70 秒）；编译期只有两条 `HelperAttributionTests.swift` 里既有的警告（C-031） |
| `BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core-tsan scripts/dev.sh test --sanitize=thread --filter BuddyCoreTests -j 2`（ThreadSanitizer）| 374 个测试，**0 条 `WARNING: ThreadSanitizer`**（只有 `chain1` 失败）。检测器验证过：把 C-016 的加锁读取撤销，`FuzzEngineTests|TokenLedgerTests` 立刻报 9 条 data race |
| `… BUDDY_SCRATCH=.build-qa-core-asan … --sanitize=address --filter BuddyCoreTests`（AddressSanitizer）| 374 个测试，**0 条 AddressSanitizer 报告**（第一次全量里 C-024 在消毒器下写得太慢超时，已把那个测试改轻、单独重跑通过；另一个失败是 `chain1`）；另用 `MallocScribble=1 MallocPreScribble=1 MallocGuardEdges=1` 跑了 170 个解析 / 模糊 / 账本测试，通过 |
| `BUDDY_SCRATCH=.build-qa-core scripts/dev.sh build -j 2`（根包全部目标：BuddyCore / PixelKit / BuddyArt / BuddyStage / BuddyOffice / buddyctl / buddydump）| Build complete，**0 警告 0 错误** |

修复前失败的证据：崩溃类是「整个测试进程 SIGTRAP / SIGBUS」（`swift test` 报 `exited with unexpected signal code 5 / 10`，崩溃报告里能看到出事的函数和行号），其它是 `Expectation failed` / 超时。
每条都在文件里写了关键一行。凡是回归测试后来又改过、或者修复和测试是一起写的，我都**临时撤销修复重新跑了一遍**证明测试确实会失败，然后恢复（C-006 / C-012 / C-019 / C-023 / C-025 / C-026 / C-027 / C-028 / C-029 / C-030 / 句柄泄漏检测器）。

**本轮最重要的几条**：
1. 一批「外部数据里的一个坏数字就让整个 App 崩溃」：`procStart` 年份（C-001）、`identities.json` 里的时间（C-002，**每次启动都崩，崩溃循环**）、hook 的 `ts`（C-003）、usage 数字（C-004）、账本数字（C-005）；根因都是 Swift 整数溢出 / `Int(Double)` 换算直接 trap。
2. 深嵌套 JSON 会把 512 KB 栈的 GCD 工作线程压爆（C-012，SIGBUS）。
3. `FileIO` 的「绝不打开 .key」保险可以被符号链接、大小写、NUL 绕过（C-007）；命名管道能把读取线程永远卡在 open 上（C-008）。
4. 一条时间戳在未来的 hook 事件，会让登记表明明是 busy 的会话永远显示 idle（C-026），或者让整个 hook 队列卡死（C-006）。

---

## 1. 问题清单

### C-001 [P0] 登记表 `procStart` 里年份 / 时分秒是天文数字 → 整个 App 崩溃
- 现象：登记表（`~/.claude/sessions/<pid>.json`）的 `procStart` 字段是 `"Tue Sep 29 03:23:08 9223372036854775807"`，或者小时写成 `-9223372036854775808:00:00` 时，`TimeUtil.parseProcStart` 在 ingest 线程上直接 trap，App 崩溃。
- 根因：`Util/TimeUtil.swift:90-93`：年份只检查 `> 1970`，没有上界；`daysFromCivil`（:73）里 `era * 146097` 对 Int.max 级别的年份溢出；时分秒只检查 `< 24 / < 60`，没检查非负，`t[0] * 3600` 对 Int.min 溢出（:95）。
- 修法：年份限制在 1971…9999；时、分、秒必须 ≥ 0（不合格返回 nil，记录仍可用，只是没有 `procStart`）。
- 回归测试：`FuzzRegressionTests/c001_procStartExtremeValuesDoNotTrap`；另有 `FuzzParserTests/timeProcStartAndJSONMillisFuzz`（畸形组合 6000 个 + 格式化再解析恒等）。
- 修复前失败的证据：`SIGTRAP`，崩溃栈 `Swift runtime failure: arithmetic overflow` ← `static TimeUtil.daysFromCivil(year:month:day:) TimeUtil.swift 73` ← `static TimeUtil.parseProcStart(_:) TimeUtil.swift 94`。
- 修复后：`✔ Test "C-001 procStart 的年份 / 时分秒是天文数字时不崩溃（登记表 procStart 字段）" passed`。
- 状态：已修复。

### C-002 [P0] `identities.json` 里有一个天文数字的时间 → 每次启动都崩溃（崩溃循环）
- 现象：`identities.json` 是合法 JSON，但某条身份的 `createdAt` / `lastSeenAt` 是 `1e300`、`17591000001234567890`、`18446744073709551615` 之类（一个数字被写坏 / 手动改过）。载入没事，第一次存盘（新会话出现就会触发）在 `Int64(Double)` 里 trap；文件没被覆盖，**下次启动照旧崩**。
- 根因：`Util/TimeUtil.swift:6` `millis(_:)` 是 `Int64((d.timeIntervalSince1970 * 1000).rounded())`，超出 Int64 范围直接 trap；`IdentityResolver.swift:185` 存盘时对每个身份都调它；`TimeUtil.date(fromJSONMillis:)`（:9-14）对任何有限正数都放行，所以坏时间戳能载入并留在内存里。
- 修法：`millis` 改成饱和（超出夹在 Int64 两端，NaN 当 0）；`date(fromJSONMillis:)` 统一改成「合理范围 2000-01-01…2200-01-01 之外都当坏数据」（同时拒绝布尔）；identities 载入时时间戳不合理的用「现在」代替；`formatISO` / `formatProcStart` / `debugClock` 也夹住极端日期。
- 回归测试：`c002_millisSaturates`、`c002_identityFileWithAbsurdTimesCannotCrashLoop`（载入 → 存盘 → 再载入，文件合法、时间都在合理范围）。
- 修复前失败的证据：`Fatal error: Double value cannot be converted to Int64 because the result would be greater than Int64.max`；崩溃栈 `TimeUtil.millis(_:) TimeUtil.swift 6` ← `closure #2 in IdentityResolver.saveIfNeeded(force:) IdentityResolver.swift 185`。
- 修复后：两个测试 passed。
- 状态：已修复。

### C-003 [P0] hook 行的 `ts` 不做范围检查：接受 1970 年 / 550 万年 / 无穷，并且让归属判断崩溃
- 现象：① `{"ts":0,…}`、`{"ts":1,…}`、`{"ts":-5,…}`、`{"ts":true,…}`、`{"ts":1e30,…}`、400 位的数字都被当成合法事件（`ts` 变成 1970 年、5576335 年、+inf）；② 只要主线程有一个前台 Agent/Task 开着，这种事件就会让 `HelperAttributor.decide` 在 `Int(…)` 换算里 trap。
- 根因：`Ingest/LineSanitizer.swift:73-74`（严格解析）和 :80-84（降级解析）直接 `TimeUtil.date(ms:)`，没有范围检查；降级路径里 `scanNumber` 把 `1759100000123e5` 当成 `1759100000123`；`Fusion/HelperAttributor.swift:71` 是 `Int((event.ts.timeIntervalSince(since) * 1000).rounded()) >= …`。
- 修法：hook `ts` 必须在合理范围（2000…2200 年，布尔 / 无穷 / 0 / 负数都拒绝，整行当坏行跳过）；降级扫描里数字后面必须紧跟 `, } ]` 或空白、最多 20 位；`decide` 改成 Double 比较，不做 Int 换算。
- 回归测试：`c003_absurdHookTimestampsAreRejectedAtParseTime`（15 种坏 ts × 严格 / 降级两条路径）、`c003_attributionSurvivesAbsurdEventTimes`（`±1e30 / ±1e300 / ±inf`）。
- 修复前失败的证据：`Expectation failed: (LineSanitizer.parseHookLine(full) → HookEvent(ts: 5576335-12-29 12:18:20 +0000, ev: "PreToolUse" …)) == nil`（19 个 issue）；崩溃：`Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max` ← `HelperAttributor.decide(event:context:now:) HelperAttributor.swift 71`。
- 修复后：两个测试 passed。
- 状态：已修复。

### C-004 [P0] 会话记录里 `usage` 的数字太大 → 相加溢出，崩溃（解析线程 / 账本扫描线程）
- 现象：一行 assistant 记录里 `input_tokens` / `cache_read_input_tokens` 之类是 `9223372036854775807`（或者 `cache_creation` 的 5m / 1h 两项都很大），解析这一行就 trap；账本的后台扫描线程也会崩。
- 根因：`Ingest/TranscriptLine.swift:164-167` `intValue` 只做 `max(0, n.intValue)`（`NSNumber.intValue` 对超范围的数会饱和成 Int.max），然后 :103 `usage.cacheWrite1h + usage.cacheWrite5m` 和 `TranscriptReader.swift:96-97` `u.input + u.cacheWriteTotal + u.cacheRead` 都是普通 `+`。
- 修法：每个 token 计数夹到 `[0, 2^40]`（≈ 1.1 万亿，比任何真实的单条消息大几个数量级），三项相加不可能溢出。
- 回归测试：`c004_hugeUsageNumbersDoNotOverflow`（解析 + `TranscriptFacts.apply` + `TokenLedger` 扫描）；`FuzzParserTests/transcriptLineRandomAndTypeConfusion`（2500 个字段类型随机的行，usage 一律在范围内、缓存写拆分对得上总数）。
- 修复前失败的证据：`SIGTRAP`，`Swift runtime failure: arithmetic overflow` ← `static TranscriptLineParser.parse(object:) TranscriptLine.swift 103`。
- 修复后：passed。
- 状态：已修复。

### C-005 [P0] `ledger.json` 里的计数是天文数字 / 负数 → 恢复后累加、求和都会溢出崩溃
- 现象：账本条目里 `input` / `output` / `cw` / `cr` / `n` 是 `9223372036854775807`、`-1000`、`1e300`、`18446744073709551615`：恢复之后 `TokenBreakdown.total`（界面每次都会读）溢出 trap；之后追加的新消息 `+=` 也溢出；负数则让「token 只增不减」不成立。
- 根因：`Ingest/TokenLedger.swift` 的 `restore` 用 `NSNumber.intValue` 直接赋值，没有范围；`totals(forKey:)` / `handle` 都是普通 `+=`；`Model/BuddySnapshot.swift:30` `total` 是四个 Int 直接相加。
- 修法：恢复出来的计数夹到 `[0, 2^50]`；账本里所有累加改成饱和加法（`TokenLedger.sat`）；`TokenBreakdown.total` 也是饱和加法。
- 回归测试：`c005_ledgerWithAbsurdCountersIsSanitized`（四种坏值 × 恢复 + 追加新行 + 写盘）；`FuzzPersistenceTests/ledgerFieldwiseMutations`、`ledgerRandomCorruption`（字段缺失 / 错误类型 / 天文数字 / 随机字节破坏，统计值非负、追加后只增不减）。
- 修复前失败的证据：`SIGTRAP`，`Swift runtime failure: arithmetic overflow` ← `TokenBreakdown.total.getter BuddySnapshot.swift 30`。
- 修复后：passed。
- 状态：已修复。

### C-006 [P1] 时间戳在未来的 hook 事件会把「归属扣留」永远扣下去，整个 hook 队列卡死
- 现象：有后台小助手活跃时，主线程的 PreToolUse 要先扣住最多 400 ms（等会话记录里的 tool_use 落盘来比对）。如果这个事件的 `ts` 在未来（时钟被拨回 / 坏数据，哪怕只是几分钟），扣留要等到「现在」追上 `ts + 0.4 s` 才结束；期间它后面的所有事件（Post、Stop……）都排在收件箱里出不来，收件箱一直涨。
- 根因：`Fusion/HelperAttributor.swift:83-84` `deadline = event.ts + 0.4`，`now < deadline ? .hold : .main`；`SessionEngine.processInbox`（:530-536）遇到 `.hold` 就整个 return。
- 修法：记住「第一次扣它的时刻」，扣留时限取 `min(事件时间戳, 第一次扣留时刻) + 0.4 s`（正常事件行为不变）。
- 回归测试：`c006_attributionHoldIsBoundedEvenWithFutureTimestamps`（未来 1 小时 / 1 年 / 100 年，都要在 0.5 秒内决定）。
- 修复前失败的证据（撤销修复后重跑）：`未来 3600 秒的事件：1 秒后还在扣留（hook 队列被卡死）`、`未来 31536000 秒…`、`未来 3153600000 秒…`。
- 修复后：passed。另外 C-026 的入口处把比现在晚一天以上的事件按「现在」算，双重保险。
- 状态：已修复。

### C-007 [P1] `FileIO` 的「绝不打开 .key / .sock」保险可以被绕过
- 现象：① 名字合法但是符号链接指向 `.key` 的文件（`1001.json -> 1001.<sha>.key`）：`FileIO.readAll` 读出了 key 的内容（测试里读到 34 字节的假内容）；② `1001.abc.KEY`、`A.SOCK`、`/tmp/CC-SOCKS/x` 大小写变体（macOS 默认的 APFS 大小写不敏感，`ABC.KEY` 打开的就是 `abc.key`）不被认出来；③ 路径里带 NUL（`x.key\0.json`）：名字判断看到的是 `.json`，C 字符串在 NUL 处截断，实际打开的是 `x.key`（测试里 `FileIO.open` 真的返回了 fd）；④ 经过目录符号链接（`cc-alias -> cc-socks`）也能绕过 `cc-socks` 检查。
- 根因：`Util/FileIO.swift:43-58`：只对路径字符串做**大小写敏感**的后缀 / 子串判断，不看 NUL，不看符号链接的真实路径，不核对打开之后的 fd。
- 修法：`isForbidden` 不区分大小写 + 拒绝含 NUL 的路径 + 路径里任何一段叫 `cc-socks` 都算；`open` 在文件存在时先 `realpath` 解析再判断（被拒绝的路径连 `open` 都不调用，观察口里也不会出现）；打开之后再用 `fcntl(F_GETPATH)` 核对 fd 自己的真实路径；只允许打开普通文件。
- 回归测试（都在串行套件 `FileAccessTests` 的扩展里，因为要用全局的 `forbiddenHits` / `openObserver`）：`c007_symlinkToKeyFileIsRefused`、`c007_caseVariantsNulAndDotDotAreForbidden`；模糊测试 `fuzz_forbiddenOracleOnRandomPaths`（3 万个随机路径和独立判断逐个对照）、`fuzz_variantsNeverOpenForbiddenFiles`（27 种变体：大小写 / `./` / `//` / `..` / 结尾斜杠 / 符号链接链 / 目录符号链接 / 相对符号链接 / NUL，全部打不开，观察口里一个都没有）、`fuzz_registryScannerWithDecoyFiles`（诱饵目录：假 `.key`（含不可读的）、名字差一点点的、目录、FIFO、指向 `.key` 的符号链接：只读合法的 `<pid>.json`，被 open 的文件名全部匹配 `^\d+\.json$`）。
- 修复前失败的证据：`Expectation failed: (FileIO.readAll(dir.file("1001.json")) → 34 bytes) == nil`；`FileIO.open(dir.file("1001.json")) → 3`；`FileIO.isForbidden(path: "/h/.claude/sessions/1001.abc.KEY")` 为 false（12 个 issue）；`FileIO.open(nul) → 4`。
- 修复后：全部 passed；已有的 `FileAccessTests` 4 个测试照常通过。
- 状态：已修复。**没修（也修不了）的一种：硬链接**——同一个 inode 的另一个名字（`ln 1001.<sha>.key 1002.json`）从路径上看不出来，见「剩余风险」。

### C-008 [P1] 数据文件位置上是命名管道（FIFO）→ 读取线程永远卡在 `open()`
- 现象：`~/.claude/sessions/<pid>.json`、桌面元数据 `local_x.json`、hook 文件等的位置上如果是一个 FIFO，`open(O_RDONLY)` 会一直阻塞到有写者出现，ingest 队列（整个数据层）从此卡死。
- 根因：`Util/FileIO.swift:57` `Darwin.open(path, O_RDONLY | O_CLOEXEC)` 没有 `O_NONBLOCK`，也不检查文件类型。
- 修法：`O_NONBLOCK` 打开，打开后 `fstat` 不是普通文件（管道 / 设备 / socket / 目录）就关掉返回 -1。
- 回归测试：`c008_fifoDoesNotBlockTheReader`（`readAll` / `JSONLTailer` / `DesktopMetaReader.refresh` 遇到 FIFO 都要在 15 秒内返回）；诱饵目录测试里也有 FIFO。
- 修复前失败的证据：`超时（疑似死循环 / 卡死）：DesktopMetaReader.refresh(FIFO)（>5 秒）` + `readAll(FIFO)` 超时（4 个 issue，测试跑了 10 秒）。
- 修复后：passed（0.04 秒）。
- 状态：已修复。

### C-009 [P2] `identities.json` 载入没有上界：别名 / 工位号 / 身份个数都可以是任意大
- 现象：一个身份挂 5 万个别名、工位号是 `Int.max` / `-5` / `4294967296`、上万条身份，都原样载入（内存里长期占着，别名索引也跟着涨；工位号一路传到界面层，见应用层 A-011）。
- 根因：`Fusion/IdentityResolver.swift:200-217` `load` 对 `aliases` / `seat` / 条目数都不设限；`maxAliases` 这个常量定义了但没人用；`lastPersistedSeen` 在身份过期后不清理（:219-225）。
- 修法：载入时别名按 host 6 / sid 30 / proc 4 保留最近的、去重、丢掉别的前缀和过长的；工位号只认 0…999，别的当作没分配；身份最多 2000 个（留最近见到的）；key 长度 ≤ 200；未来的时间当作刚见过；`pruneExpired` 同步清理 `lastPersistedSeen`。（应用层 QA 建议的「load 丢弃 seat < 0 / > 999」已做；「输出夹到 0..<64」没做——Core 输出的座位号是最小空位，超过 64 个人同时在场时夹到 64 会撞座位，应用层的 `SeatSanitizer` 已经处理。）
- 回归测试：`c009_identityFileIsBoundedOnLoad`；`FuzzPersistenceTests/identitiesTruncatedAtEveryByte`（每个字节位置截断）、`identitiesCorruption`（随机破坏 250 个 + 每个字段缺失 / 换成 16 种错误类型）：载入后不变量成立（seat / 别名数 / 时间），再 resolve、存盘、重载是恒等的。
- 修复前失败的证据：`(id.aliases.count → 50000) <= (IdentityResolver.maxAliases → 40)`、`(r.all.count → 5009) <= 2000`、`(id.seat >= -1 → false)`（8 个 issue）。
- 修复后：passed。
- 状态：已修复。

### C-010 [P2] 桌面元数据的 `priorCliSessionIds` 没有上界：O(n²) + 每个 id 都要列一遍 projects 目录
- 现象：元数据里 `priorCliSessionIds` 有 1.2 万项时，`allCliSessionIds`（去重用 `contains`）要算 16 秒（-Onone；-O 也是秒级）；引擎还会对每个 id 去 `TranscriptLocator.find`（列 projects/ 目录），几十万项会把 ingest 队列拖死。
- 根因：`Ingest/DesktopMetaReader.swift:52` `allCliSessionIds` 是 O(n²)；:145 解析时不设上限、不校验 id 格式。
- 修法：只留最近 256 个、只认 `Paths.isSafeID` 的 id；`allCliSessionIds` 用 Set 去重（O(n)）。
- 回归测试：`c010_priorCliSessionIdsAreBounded`；`FuzzParserTests/desktopMetaTruncationAndTypeConfusion`。
- 修复前失败的证据：`别名个数应有上界：12001`（测试花了 16 秒）。
- 修复后：passed（0.1 秒）。
- 状态：已修复。

### C-011 [P2] `ToolTracker.open` 没有上界
- 现象：hook 文件被刷屏（或坏数据：一堆 PreToolUse 没有 PostToolUse，时间戳相同所以永远不开新的一批）时，`open` 数组无限增长，每次 `post` 还要线性扫描。
- 根因：`Fusion/ToolTracker.swift:65-81` `pre` 只追加；只有 Post / 轮次边界 / 新一批 / 30 分钟兜底才会关。
- 修法：`maxOpen = 512`，超出把最老的当作被取代关掉。
- 回归测试：`c011_toolTrackerOpenListIsBounded`；`FuzzParserTests/toolTrackerAndAttributorRandomSequences`（随机序列：乱序 / 同一毫秒 / 名字被截断 / 时间倒流，open 有上界且 seq 严格递增）。
- 修复前失败的证据：`(t.open.count → 30000) <= 1024`。
- 修复后：passed。
- 状态：已修复。

### C-012 [P0] 嵌套 ≥ 约 470 层的 JSON 把 512 KB 栈的 GCD 工作线程压爆（SIGBUS）
- 现象：任何一个被解析的 JSON（hook 行 / 会话记录行 / 登记表 / 桌面元数据 / 子代理 meta / 账本 / 身份文件 / custom-title.json / settings.json）里只要有一个嵌套 470～512 层的对象，`JSONSerialization` 递归解析就会栈溢出，整个 App 崩溃（SIGBUS）。超过 512 层它自己的深度上限才会报错，所以更深的反而没事。
- 根因：8 处 `JSONSerialization.jsonObject` 都直接解析外部输入；数据层跑在 GCD 工作线程上（栈 512 KB），每层对象嵌套约吃 1 KB 栈（实测：512 KB 栈上 450 层没事、480 层崩）。
- 修法：新增 `Util/SafeJSON.swift`，解析前先用一遍 O(n) 的扫描数嵌套深度（字符串 / 转义里的括号不算，对 UTF-16 编码同样有效），> 100 层一律当坏数据；8 个解析点全部改走 `SafeJSON.object`。
- 回归测试：`c012_deeplyNestedJSONDoesNotOverflowTheStack`（在 512 KB 栈的线程上，深度 200～10 万的对象 / 数组分别塞进 hook 行 / 会话记录行 / 登记表 / 桌面元数据，正常的浅 JSON 照常解析，字符串里的括号不算）。
- 修复前失败的证据（`maxDepth` 改成 `Int.max` 重跑）：`CRASH: SIGBUS`，栈 `newJSONValue` ← `newJSONObject` ← `newJSONValue` …（Foundation 的递归解析）。第一次是在 `FuzzTailerTests/hookLineJSONLevel` 里意外撞到的。
- 修复后：passed（0.009 秒）。
- 状态：已修复。

### C-013 [P3] `TranscriptReader.bootstrap(tailWindow:)` 传 0 死循环、传负数 trap
- 现象：`tailWindow: 0` → 循环里 `window *= 4` 永远是 0，永远出不来；`tailWindow < 0` → `UInt64(window)` trap。（`SessionEngine.Options.transcriptTailWindow` / `hookTailWindow` 是公开的可配置项，App 没设，但接口不该这么脆。）
- 根因：`Ingest/TranscriptReader.swift:164-174`；`Ingest/JSONLTailer.swift:72-73` `UInt64(window)`。
- 修法：`bootstrap` 里 `max(1, tailWindow)`；`seekToTail` 里负数当 0。
- 回归测试：`c013_bootstrapWithNonPositiveWindowTerminates`（0 / -1 / Int.min / 1，TranscriptReader 和 HookLogReader 都测）。
- 修复前失败的证据：`Expectation failed: finished`（`tailWindow: 0` 超时 = 死循环）；`tailWindow: -1` 崩溃：`JSONLTailer.seekToTail(window:) JSONLTailer.swift 72`。
- 修复后：passed。
- 状态：已修复。

### C-014 [P2] 按会话累积的缓存 / 账本里没有 buddy 在用的文件永远不清理，还每次都被扫描
- 现象：App 长时间运行、会话来来去去之后：`SessionEngine.transcriptPathCache` / `transcriptMissAt`（按 sessionId）只增不减（300 个会话之后各 150 条）；`TokenLedger` 的 `files` / `fileList` / 去重表 `messages` 只增不减（`removeGroup` 只删分组，文件状态「万一它又回来」全留着），而且**每次扫描都把出现过的所有文件 stat 一遍、有增长的还会 open 读**（测试里已经没人用的文件被反复 open）。
- 根因：`Fusion/SessionEngine.swift:84-86` 两个字典从不清理；`Ingest/TokenLedger.swift:52-56, 102-104, 155-174`。
- 修法：引擎每 30 秒清一次（miss 记录过 10 秒就没用了；路径缓存只留还有 buddy 在用的会话）；账本里没有任何分组在用的文件标记为「没人用」，不再扫描，超过 64 个就把最早没人用的清出去（断点转存进 `ledger.json`，回来时从断点恢复，去重表里属于它的条目一起删掉）；`removeGroup` 同时清 `groupNoLedger`。
- 回归测试：`c014_engineCachesStayBoundedWhenSessionsComeAndGo`（300 个会话来去，缓存 ≤ 32）；`FileAccessTests/c014_ledgerDoesNotKeepScanningOrHoardingDetachedFiles`（用观察口证明没人用的文件不再被 open；文件数 ≤ 100、去重表 ≤ 100；被清出去的会话回来，统计值正确、写盘的账本合法）；`FuzzEngineTests/engineWithHundredsOfSessionsComingAndGoing`（每批 150 个会话，含重复 sessionId / 重复 host，全部离场后缓存回落）。
- 修复前失败的证据：`(c.transcriptPaths → 150) <= 32`、`(c.transcriptMisses → 150) <= 32`；`(ledger.trackedFileCount → 302) <= 100`、`(ledger.dedupeEntryCount → 303) <= 200`、`!(opened.value → [".../a.jsonl", …])`（没人用的文件还在被 open）。
- 修复后：passed。
- 状态：已修复。

### C-015 [P3] 读过一条很长的行之后，`JSONLTailer` 的半行缓冲一直占着几 MB 内存
- 现象：读过一条 3 MiB 的行之后，半行缓冲的容量仍是 3162080 字节（`removeAll(keepingCapacity: true)`）；几十个读取器同时跟踪时每个都留着自己见过的最大一块。
- 根因：`Ingest/JSONLTailer.swift:179` 等处。
- 修法：容量超过 64 KiB 就直接释放（`clearPending()`）。
- 回归测试：`c015_pendingBufferIsReleasedAfterALargeLine`。
- 修复前失败的证据：`(t.pendingCapacity → 3162080) <= (256 * 1024 → 262144)`。
- 修复后：passed。
- 状态：已修复。

### C-016 [P3] `TokenLedger` 的 `version` / `persistenceOK` / `isScanning` 在别的线程无锁读取（数据竞争）
- 现象：这三个公开状态在扫描队列上（持锁）写，`SessionEngine.poll()` / 诊断页在 ingest 队列 / 主线程无锁读——形式上是数据竞争（实际是机器字，多半无害，但 TSAN 会报）。
- 根因：`Ingest/TokenLedger.swift` 里它们是 `public private(set) var`。
- 修法：改成持锁读取的计算属性（`_version` 等私有存储）。
- 回归测试：普通 `swift test` 里数据竞争不会让断言失败，所以没有常规测试；用 ThreadSanitizer 验证：`BUDDY_PKG=.dev/core BUDDY_SCRATCH=.build-qa-core-tsan scripts/dev.sh test --sanitize=thread --filter 'FuzzEngineTests|TokenLedgerTests' -j 2`（`FuzzEngineTests/storePublicAPIUnderConcurrentUse` 让 4 个线程同时乱用 `SessionStore` 的公开 API，同时数据在变）。
- 修复前失败的证据（撤销加锁后重跑，9 条）：`WARNING: ThreadSanitizer: Swift access race … Modifying access of Swift variable … by thread T11 (mutexes: write M0): #0 TokenLedger.pass() … Previous read of size 8 … by thread T12: #0 TokenLedger.version.getter TokenLedger.swift:100 #1 SessionEngine.poll() SessionEngine.swift:177 #2 Harness.poll()`。
- 修复后：全量 374 个测试在 TSAN 下 0 条警告。
- 状态：已修复。

### C-017 [P3] 登记表 `pid` 不校验：布尔 / 小数 / 超出 Int32 的数被强转成别的 pid；记录里的 pid 和文件名不一致时用哪个没有规定
- 现象：`{"pid":true}` → pid 1（launchd，永远「活着」）；`4294967297` → 1；`9223372036854775807` / `1e30` → -1；`1.5` → 1；`0` / 负数原样放行。引擎探测存活用的是文件名的 pid，界面 / 终端跳转显示的却是记录里的 pid，两者不一致时会拿错进程。
- 根因：`Ingest/RegistryScanner.swift:196,206` `pidNum.int32Value`。
- 修法：`pid` 必须是 1…Int32.max 的整数（布尔 / 小数 / 范围外 = 不可用）；扫描时以**文件名里的 pid** 为准（记录里的只是冗余信息，不会因此隐藏会话）。
- 回归测试：`c017_registryPidMustBeARealPid`；`FuzzParserTests/registryJSONLevelAgreesWithOracle`（4000 个随机 JSON 和独立判断一致）。
- 修复前失败的证据：`pid=true → RegistryRecord(pid: 1 …)`、`pid=4294967297 → pid: 1`、`pid=9223372036854775807 → pid: -1`、`(r.records[1001]?.pid → 2002) == 1001`。
- 修复后：passed。
- 状态：已修复。

### C-018 [P3] 会话记录里 AskUserQuestion 的 `key` 没有像 hook 那样置空
- 现象：`ToolDetail.key(name: "AskUserQuestion", input: ["description": …])` 返回那个 description；README 说「AskUserQuestion 的 detail 在解析和追踪两层都置空」，会话记录这一层漏了（只在没有 hook 时的回退路径会用到，但任务书第 4 节明确写了这个坑）。
- 根因：`Ingest/TranscriptLine.swift:177-196`。
- 修法：AskUserQuestion（含被截断 / 带空白的名字）一律返回空串。
- 回归测试：`c018_askUserQuestionTranscriptKeyIsAlwaysEmpty`；`FuzzTailerTests/hookKnownPitfallsUnderMutation`（hook 那一层的变异：截断的转义 / 非法字节 / 超长，300 次）。
- 修复前失败的证据：`ToolDetail.key(name: "AskUserQuestion", …) → "第一个选项的说明"`。
- 修复后：passed。
- 状态：已修复。

### C-019 [P3] 文件事件分流按前缀匹配、不看目录边界；空会话 id 会匹配一切
- 现象：`~/.claude/sessions-old/…`、`sessions2`、`.monitor-old/…`、`claude-code-sessions-backup/…` 的变化都会触发一次 poll；已跟踪的会话 id 集合里如果有空串，`path.contains("")` 让 monitor / projects 下所有文件的变化都触发。（只会多 poll，不会出错。）
- 根因：`Fusion/SessionStore.swift:228-240` `hasPrefix(pre.sessions)`、`tracked.contains(where: { path.contains($0) })`。
- 修法：抽成纯函数 `SessionStore.shouldPoke(paths:prefixes:tracked:)`，按目录边界匹配（`path == dir || hasPrefix(dir + "/")`），空 id 不匹配。
- 回归测试：`c019_fileEventRoutingRespectsDirectoryBoundaries`。
- 修复前失败的证据（撤销边界判断后重跑）：`!(poke("/h/.claude/sessions-old/123.json") → true)`、`!(poke("/h/.claude/sessions2") → true)`、`…claude-code-sessions-backup/x.json`、`…/.monitor-old/…events.jsonl`（4 个 issue）。
- 修复后：passed。
- 状态：已修复。

### C-020 [P3] 两个桌面元数据文件声称同一个 `sessionId`（用户复制出的副本）→ 每次刷新都互相覆盖、报告「变了」
- 现象：`local_x.json` 和 `local_x copy.json` 内容里 `sessionId` 相同：`refresh()` 每次都重读两个文件、来回覆盖索引、都返回 `[local_x]`（测试里 5 次刷新报了 5 次变化），引擎每次都当作元数据变了。
- 根因：`Ingest/DesktopMetaReader.swift:89-103`：索引键是文件**内容里**的 sessionId，跳过检查用的却是**文件名**推出的 host。
- 修法：同一个 host 有多个文件时确定性地选一个（文件名恰好是 `<host>.json` 的优先，否则路径小的优先），其余记进「副本表」（路径 → 签名 + 压住它的 host），没变就不再重读，赢家没了副本才转正；「没变就不重读」的判断改用 `pathToHost`。
- 回归测试：`c020_duplicateHostIdsDoNotThrash`；`FuzzReadersTests/desktopMetaRefreshOnJunkTree`（目录 / FIFO / 符号链接（含指向别的元数据文件的）/ 垃圾 / 超过 4 MiB / 深嵌套 / 古怪文件名，重复刷新 5 次没有抖动，改一个 / 删一个只报告它）。
- 修复前失败的证据：`文件没变，refresh 却报告了 5 次变化`（`changes → 5`）。
- 修复后：passed。
- 状态：已修复。

### C-021 [P3] 子代理的 `.meta.json` 一直不存在时，每次 poll 都 `open` 它一遍
- 现象：老版本的子代理没有 meta 文件；引擎每个 poll（忙时 20 Hz）对每个没有 meta 的小助手都 `open()` 一次（失败）。60 个 poll 里 open 了 62 次。
- 根因：`Ingest/SubagentReader.swift:68` `if h.meta == nil { loadMeta(h) }` 在每次 poll 里都执行。
- 修法：只在「列目录」的节拍上重试（忙时 0.15 秒、闲时 1 秒）。
- 回归测试：`FileAccessTests/c021_missingSubagentMetaIsNotRetriedOnEveryPoll`（meta 后来出现能读到）；`FuzzReadersTests/subagentReaderOnJunkDirectory`。
- 修复前失败的证据：`没有 meta 文件时被反复 open 了 62 次`（`metaOpens → 62`）。
- 修复后：passed。
- 状态：已修复。

### C-022 [P3] `FileWatcher.resolved` 是递归的：几百层的不存在路径把 512 KB 栈压爆
- 现象：`FileWatcher.resolved(<3000 层的不存在路径>)` 在 GCD 工作线程上 SIGBUS（每层递归都有一个 `realpath` 的大栈帧）。（路径来自 `Paths`，正常只有几层；`--data-root` 传一个畸形值才会碰到。）
- 根因：`Ingest/FileWatcher.swift:79-88`。
- 修法：改成循环（收集未解析的末尾几级，找到最深的存在的祖先再接回去，语义不变）。
- 回归测试：`FuzzWatcherTests/c022_resolvedHandlesEveryKindOfPath`（空串 / 根 / 一堆斜杠 / `..` / 超长 / 含 NUL / 3000 层深路径；结果幂等）。
- 修复前失败的证据：`CRASH: SIGBUS`，栈 `___chkstk_darwin` ← `realpath$DARWIN_EXTSN` ← `static FileWatcher.resolved(_:) FileWatcher.swift 81 / 86 / 86 / 86 …`。
- 修复后：passed。
- 状态：已修复。

### C-023 [P3] 外部 JSON 里的字符串字段没有长度上限
- 现象：登记表的 `name` / `cwd`、元数据的 `title`、hook 的 `tool` / `detail` / `extra`、会话记录里的 id / 模型 / 工具名 / 标题……都可以是几 MB 的字符串，会被复制进每一份快照、写进 identities.json（别名 / key）。
- 根因：所有 `as? String` 的解析点。
- 修法：`SafeJSON.string / id`：标签类字段截到 2048、detail 4096、名字 / 模型 200、状态类 64（按 Unicode 标量截）；**id 类字段太长当没有、不截断**（截断会让不同的 id 变相等，去重 / 配对会错）；hook 的 `ev` > 64 字符整行当坏行；降级扫描的字符串 / 数字扫描到上限就停。
- 回归测试：`c023_hugeStringFieldsAreClipped`（登记表 / 桌面元数据 / hook 行（严格 + 降级）/ 会话记录 / 标题，都塞 90 万字的字段）。
- 修复前失败的证据（上限改成 1 亿重跑）：`Expectation failed: ((r.cwd?.count ?? 0) <= 2048 && … → false)`、`(r.hostSessionId → "aaaa…(5000 个)")`、`((m?.title?.count ?? 0) <= 2048 → false)`。
- 修复后：passed。
- 状态：已修复。

### C-024 [P3] `FileIO.writeAtomically` 的临时文件名是固定的：多线程同时写同一个文件会得到两次内容的混合
- 现象：`path.tmp<pid>` 每次调用都一样；两个线程同时写同一个目标时互相 `O_TRUNC`、交错写入，然后 rename 出去的是混合内容。（App 里没有这种并发——身份和账本各写各的、都在各自的串行队列上——但这是公开的通用接口。）
- 根因：`Util/FileIO.swift:131`。
- 修法：临时文件名 = `path.tmp<pid>-<递增计数>`（计数在锁里）。
- 回归测试：`FuzzFileIOTests/c024_concurrentAtomicWritersNeverProduceMixedContent`（4 个线程写长度不同、字节不同的内容，另一个线程不停读：读到的永远是某一次完整的内容，最终文件完整，没有残留临时文件）。
- 修复前失败的证据：`读到了 32 次混合 / 不完整的内容（共读 1844 次）`（第一版参数较重；为了在 ASAN 等慢环境下也能跑完，后来把内容缩小、加了读者的休眠，撤销修复重跑：`读到了 2 次混合 / 不完整的内容（共读 78 次）`）。
- 修复后：passed。
- 状态：已修复。

### C-025 [P1] 会话记录里 `turn_duration` / `api_error` 的数字没有范围：天文数字会流进快照，让表现层的 `Int(秒数)` 换算 trap
- 现象：`turn_duration` 的 `durationMs` 是 `1e300`（或 `-1e300`）→ `lastTurnDuration = 1e297` 进入快照；BuddyStage 的 `PlateCopy.spoken`（`max(0, Int(seconds))`）对它做 `Int(…)` 换算会直接 trap（**主线程崩溃**）。`retryInMs` / `retryAttempt` / `maxRetries` 同理（重试次数会显示在桌牌上）。
- 根因：`Ingest/TranscriptLine.swift:141-146` 直接取 `NSNumber.doubleValue / intValue`；`Fusion/SessionEngine.swift:757-760` 把 `ms / 1000` 当作 `lastTurnDuration`。
- 修法：解析时夹到合理范围（`durationMs` 0…1e12 ms、`retryInMs` 0…1 小时、次数 0…1000），范围外 / 布尔 / 非数字当作没有。（表现层自己没有防护，见 C-033。）
- 回归测试：`c025_durationsAndRetryCountsAreBounded`（10 种坏值 × `turn_duration` / `api_error`，事实里也没有）；`FuzzEngineTests/engineSurvivesExtremeValuesEverywhere` 的快照不变量里检查 `lastTurnDuration` 有限且非负。
- 修复前失败的证据（撤销范围后重跑）：`Expectation failed: (l?.durationMs → -1e+300)`、`durationMs=-1e300 应当被当作没有：Optional(-1e+300)`、`api_error 的 1e300 应当被当作没有`。
- 修复后：passed。
- 状态：已修复（数据层保证范围）。

### C-026 [P1] 时间戳远在未来的 hook 事件 / 会话记录行，把「取最大时间」的状态永远毒化（会话被卡在 idle）
- 现象：hook 里一条 `Stop` 的 `ts` 是一年以后（时钟被拨快过 / 坏数据）：`lastStopAt` 变成一年后，`ActivityResolver.effectivePhase` 里「登记表 busy 但有比 statusUpdatedAt 更新的 Stop → 暂时当作 idle」的条件永远成立——之后**每一轮**登记表都是 busy，界面却一直显示空闲，直到 App 重启（甚至更久，只要那一行还在读取窗口里）。会话记录里一条未来的 assistant 行同样毒化 `lastAssistantAt / lastLineAt / lastAssistantOrUserAt`（hookActive 误判、重试 / 出错判断失效）。
- 根因：`Fusion/SessionEngine.swift:489-498` `ingestHook` 直接 `max(…, e.ts)`；`Ingest/TranscriptReader.swift` 的 `apply` 也是；`Fusion/ActivityResolver.swift:44-47` 的 Stop 判断没有 `<= now` 保护（Prompt 那一条有）。
- 修法：引擎入口处把比「现在」晚一天以上的 hook 事件时间戳按「现在」算；`TranscriptReader` 接受一个时钟（引擎传 `options.now`，子代理读取器同理），比现在晚一天以上的行时间戳按「现在」算（不注入时钟就不改，所以直接构造读取器的旧测试 / 工具不受影响）。
- 回归测试：`c026_farFutureTimestampsDoNotPoisonState`（一年后的 Stop + 一年后的 assistant 行，之后新一轮开始：要显示 `Read`，事实里 `lastAssistantAt / lastLineAt / hookMaxTs / lastStopAt` 都不超过现在 + 1 天）。
- 修复前失败的证据（撤销后重跑）：`新一轮开始之后应该是「Read」，实际 Optional(BuddyCore.Activity.idle)（被未来的 Stop 毒化成了 idle）`。
- 修复后：passed。
- 状态：已修复。

### C-027 [P3] `Paths(home:)` 去掉结尾斜杠是 O(n²)
- 现象：`home` 是几十万个斜杠时卡 10 秒以上（每次循环都对整个字符串 `count`）。
- 根因：`Paths.swift:12` `while h.count > 1 && h.hasSuffix("/") { h.removeLast() }`。
- 修法：转成字节数组，从后往前数一遍。
- 回归测试：`c027_pathsInitIsLinear`（也验证 `""` / `"/"` / `"//"` / 带空格 / emoji 的语义不变）。
- 修复前失败的证据（撤销后重跑）：`超时（疑似死循环 / 卡死）：Paths.init（>10 秒）`。
- 修复后：passed（0.009 秒）。
- 状态：已修复。

### C-028 [P3] `TokenLedger.flush()` 在扫描队列上调用会对自己所在的队列 `sync` → 崩溃 / 死锁
- 现象：`onChange` 回调（在扫描队列上执行）里调 `flush()`，libdispatch 直接报「dispatch_sync called on queue already owned by current thread」并崩溃。（`SessionStore` 的 `onChange` 只是异步 poke，不会碰到；但这是公开接口。）
- 根因：`Ingest/TokenLedger.swift:145-147` `queue.sync { … }`。
- 修法：用 `DispatchSpecificKey` 判断当前是否就在扫描队列上，是就直接写。
- 回归测试：`c028_flushFromInsideOnChangeDoesNotDeadlock`。
- 修复前失败的证据（撤销后重跑）：`CRASH: SIGTRAP`，栈 `__DISPATCH_WAIT_FOR_QUEUE__` ← `_dispatch_sync_f_slow` ← `TokenLedger.flush() TokenLedger.swift 198` ← `closure in c028…` ← `TokenLedger.pass()`。
- 修复后：passed。
- 状态：已修复。

### C-029 [P2] `HookLogReader.poll()` 一次交出的事件没有上界
- 现象：hook 文件一下子有几十万行时（App 被挂起很久 / 文件被换成一个大文件）一次 poll 把所有事件（60000 个测试事件）全堆进数组，随后又被复制进收件箱；100 MB 的文件会是上百万个事件、几百 MB 内存。
- 根因：`Ingest/HookLogReader.swift:32-46`。
- 修法：一次最多交出最新的 20000 个（摊还 O(1) 地丢旧的），并置 `reset`，引擎据此作废旧事件推出来的状态（`resetHookState`），再吃最新这批。
- 回归测试：`c029_hookReaderBoundsEventsPerPoll`（6 万行：交出 ≤ 20000 个、最后一个事件就是最后一行、之后的增量读取照常）。
- 修复前失败的证据（撤销上限后重跑）：`一次 poll 交出了 60000 个事件`；`丢掉了旧事件，应当通知调用者作废…`。
- 修复后：passed。
- 状态：已修复。

### C-030 [P3] 几处小的整数换算 / 参数校验（FileIO 与 dump）
- 现象：① `FileIO.readAll(path, maxBytes: 负数)` 在 `UInt64(maxBytes)` 里 trap；② `FileStat` 的修改时间 `tv_sec * 1_000_000_000` 在秒数很大时溢出（APFS 会把时间夹在 ±9223372036 秒内，所以本机构造不出这个输入；网络盘 / 别的文件系统可能有）；③ `DumpFormatter.clock(sec)` 对天文数字 / NaN 做 `Int(sec)` trap（dump 工具）；④ `writeAtomically` 写到一半失败时（磁盘满）不删临时文件。
- 根因：`Util/FileIO.swift:73-74, 83, 131-133`；`Tools/DumpCommand.swift:245`。
- 修法：`readAll` 负数上限返回 nil；`FileIO.mtimeNs` 饱和乘 / 加；`clock` 夹范围 + 处理 NaN；写失败时 unlink 临时文件。
- 回归测试：`c030_smallIntegerConversionsDoNotTrap`（①②③；④ 需要磁盘满，构造不出来，只修不测）；`FuzzFileIOTests/specialFiles` 也覆盖 ①。
- 修复前失败的证据（三处分别撤销后重跑）：① `Fatal error: Negative value is not representable`；② `static FileIO.mtimeNs(sec:nsec:) FileIO.swift 109` `arithmetic overflow`；③ `Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max`。
- 修复后：passed。
- 状态：已修复。

### C-031 [P3] 既有测试文件里有编译警告（不是本轮新增的）
- 现象：`Tests/BuddyCoreTests/HelperAttributionTests.swift:262`：`#expect((h.snap(DesktopFixture.key)?.helpers ?? []).isEmpty)` → `warning: left side of nil coalescing operator '??' has non-optional type '[HelperSnapshot]?', so the right side is never used`（宏展开里还有一条 `expression of type 'Bool?' is unused`）。DESIGN.md 里说的「debug 和 release 构建都是 0 警告」指的是库目标，测试目标里有这一条。
- 根因：`snap(_:)?.helpers` 已经是可选链，`?? []` 是多余的（而且 `isEmpty` 作用在 `Optional` 上，可选为 nil 时的行为和作者想的不一样：`nil?.isEmpty` 是 nil，`#expect(nil)` 会失败）。
- 修法：把取值拿到宏外面（`let shown = h.snap(DesktopFixture.key)?.helpers ?? []`，再 `#expect(shown.isEmpty)`），断言的意思不变。数据层负责人当时按分工没有改既有测试文件，由主线程接手。
- 回归测试：这条本身就是测试文件里的警告；修复后 debug 测试目标 0 警告（`QA/evidence/regression-final/summary.txt`）。
- 状态：已修（主线程接手；改的是取值的写法，没有削弱断言）。

### C-032 [P3] BuddyOffice 的 `JumpService.DesktopMeta` 在调用线程同步读取全部桌面元数据文件，并且绕过 `FileIO`
- 根因：应用层另写了一套无缓存的读取，没有复用数据层带缓存的 DesktopMetaReader，也绕过 FileIO；点击处理在主线程调用。
- 回归测试：见 issues-app.md A-014（`CachesTests`：读盘次数）。
- 现象：`Sources/BuddyOffice/JumpService.swift:152-176`：`isMostRecentlyFocused` / `lastFocusedAt(host:)` 每次都 `contentsOfDirectory` 三层目录、把每个 `local_*.json`（每个约 20 KB）整个读进来解析，而且直接用 `FileManager.default.contents(atPath:)`——不走 `FileIO`（违背「FileIO 是唯一入口」的约定；它只读 `local_*.json`，不会碰 `.key`，所以没有违反安全红线）。从点击处理（主线程）调用时，桌面元数据文件多的话会卡界面。
- 修法（已做的部分：改走 FileIO）：改用 BuddyCore 已经建好的索引（快照里带 `lastFocusedAt` 就不用再读文件），或者至少放到后台队列并走 `FileIO.readAll`。**没改**：BuddyOffice 不在我的范围内。
- 状态：已修（主线程接手：读目录 / 读文件改走 `FileIO`，见 `DesktopMetaFileIOTests`（源码审计 + FIFO 诱饵；不碰全局的 FileIO 计数器，见 R2-005）；缓存和读盘次数见 issues-app.md A-014。点击时仍在主线程读一遍（3–8 ms 量级），作为 P3 接受）。

### C-033 [P3] BuddyStage 对数据层给出的时间差做 `Int(…)` 换算，自己没有防护
- 根因：表现层对数据层给出的时间差直接 `Int(x)`，没有自己的范围保护（数据层现在已经夹住了这些值，所以此前不可达）。
- 现象：`Sources/BuddyStage/PlateCopy.swift:46, 52, 104`、`Performer.swift:120` 等处对 `TimeInterval` 直接 `Int(x)`，超出 Int 范围会 trap。现在数据层保证了这些值在合理范围（C-002 / C-003 / C-025 / C-026），所以不可达；但表现层如果自己也夹一下（`min(max(x, 0), 1e9)`）就是双保险，以后数据层再出新的坏值也不会主线程崩溃。
- 修法：`PlateCopy.wholeSeconds`（基于 `safeInt`，夹到 0…10 亿秒）用在 `duration / spoken / waitSpoken / idleMinutes`，`HoverCard.ago`；`Performer` 里 MCP / 未知工具的 `safeInt(elapsed / 3)`。见 `issues-stage.md` 末尾。
- 回归测试：`ExtremeValuesTests`（3 个测试；修复前把 `wholeSeconds` 换回 `Int(x)`，测试进程 SIGTRAP）。
- 状态：已修（表现层负责人接手）。

### C-034 [—] 已确认不是问题：`FileWatcher` 的 FSEvents 回调里用 `passUnretained(self)`，对象释放后排队的回调块会不会解引用野指针
- 怀疑：`stop()` / `deinit` 之后，队列里已经排着的回调块还会执行，`takeUnretainedValue()` 访问已释放的对象。
- 验证：`FuzzWatcherTests/stopWhileCallbacksAreQueuedDoesNotTouchFreedMemory`：先把回调队列堵住，造一批文件事件让 FSEvents 把回调块投递进去，然后 `stop()` + 释放对象，再放行队列；重复 20 轮，**配合 `MallocScribble=1 MallocPreScribble=1`（释放的内存填 0x55）**也没有崩溃，说明 `FSEventStreamStop / Invalidate` 之后排队的回调块不再执行。
- 状态：已确认不是问题（保留测试作为回归保护）。

### C-035 [—] 已确认不是问题：句柄泄漏
- 怀疑：`FileIO.open` 的调用点、`opendir`、`FSEventStream`、`DispatchSourceTimer` 有没有成对释放。
- 验证：逐个读了每个 `open / opendir / FSEventStreamCreate / makeTimerSource` 的释放路径（`defer { close(fd) }`、`defer { closedir }`、`FSEventStreamStop → Invalidate → Release`、`stop()` 里 `timer.cancel()`）；`FuzzFileIOTests/noFileDescriptorLeaksAcrossReaders`：把所有读取器在 8 种文件（正常 / 目录 / FIFO / .key / 指向 .key 的符号链接 / 普通符号链接 / 不存在 / 被删）上跑 400 轮 + FSEvents 启停 40 次，文件描述符个数不涨。**检测器本身也验证过**：故意让 `readAll` 少一个 `close`，同一个测试报 `文件描述符从 3 涨到了 1207`。
- 状态：已确认不是问题。

---

## 2. 已审查文件 / 检查项清单

检查项：**A** 强制解包 / `try!` / `as!` / `fatalError`；**B** 下标 / 指针越界；**C** 整数溢出 / `Int(Double)` / 无符号下溢；**D** 除零；**E** 无界增长；**F** 句柄 / 资源成对释放；**G** 闭包循环引用；**H** 共享可变状态的锁；**I** 主线程同步文件 IO；**J** 外部输入 / 路径安全。

| 文件 | 行数 | 查了什么 | 结论 |
|---|---|---|---|
| `Paths.swift` | 62 | A–D、J：`isSafeID` / `isRegistryFileName` / `hookLogPath` 和按字节写的独立判断对照 2 万个随机串（Unicode 数字、换行、NUL、组合字符、超长） | 规则正确；`init` 去斜杠 O(n²) → C-027 |
| `Model/Activity.swift` | 82 | 枚举 / 值类型；`ToolCall` 无算术 | 无问题 |
| `Model/BuddySnapshot.swift` | 200 | C：`TokenBreakdown.total` | 溢出 → C-005（改饱和加法）；其余是数据结构 |
| `Util/FileIO.swift` | 186 | A–C、F、H、J：保险绕过 / FIFO / 溢出 / 临时文件；全部 `open` 调用点；锁 | C-007 / C-008 / C-024 / C-030；`_observer`、`_forbiddenHits`、`_tmpCounter` 都在锁里；源码扫描测试保证它是唯一读入口 |
| `Util/TimeUtil.swift` | 180 | B、C：所有下标（`parseISO` 的 `bytes[i + 1]` 等都有长度保护）；乘法；`Int(Double)`；格式化 | C-001 / C-002 / C-003（范围）；`parseISO` 加了合理范围；格式化夹范围 |
| `Util/Hashing.swift` | 35 | C、D：`&*` / `&+` 都是回绕运算；`below(_:)` 有 `max(n,1)` | 无问题 |
| `Util/Info.swift` | 4 | 常量 | 无问题 |
| `Util/SafeJSON.swift`（新增） | 68 | 深度扫描 / 字符串上限 | C-012 / C-023 的修复本身；被 8 个解析点使用 |
| `Ingest/DesktopMetaReader.swift` | 200 | B、C、E、J：`refresh` 三层目录遍历、`parse` 全部字段类型、索引一致性 | C-010 / C-020 / C-023；`refresh` 每 0.5 秒 stat 全部元数据文件（O(文件数)）→ 剩余风险 |
| `Ingest/FileWatcher.swift` | 96 | A、B、F、G：`unsafeBitCast(eventPaths)`（`UseCFTypes` 标志下成立）、`eventFlags[i]`（`i < count`）、Stream 的 Create/Start/Stop/Invalidate/Release 成对、`passUnretained` 的生命周期 | C-022（递归）；C-034（生命周期，已确认不是问题） |
| `Ingest/HookLogReader.swift` | 58 | E | C-029 |
| `Ingest/JSONLTailer.swift` | 205 | B、C、E、F：`memchr` 指针算术、`pending` 上界、`committedOffset` 下溢、超长行 / 半行 / 轮转 / 截短；**和独立实现逐行对照** | 逻辑无 bug（0 个发现，见覆盖矩阵）；C-013（窗口参数）/ C-015（容量）；`defer { close }` 齐全 |
| `Ingest/LineSanitizer.swift` | 151 | B、C、E、J：严格 / 降级两条解析路径、截断到每个字节、非法 UTF-8、坏转义 | C-003 / C-023；降级扫描的数字终止符 |
| `Ingest/ProcessProbe.swift` | 104 | C、J：`pid <= 0` 不发信号、`startTime(of:)` 的 sysctl 结果处理、`classify` 极端时间 | 无问题（`kill(pid, 0)` 只做存在性检查；sysctl 返回 0 字节时按 nil） |
| `Ingest/RegistryScanner.swift` | 231 | A、C、E、J：`entry!.nextRetryAt!`（前面一行刚设过）、重试节拍、`Int32(文件名)`、`pidNum.int32Value` | C-001（procStart）/ C-017 / C-023；只 stat / open 匹配 `^\d+\.json$` 的文件 |
| `Ingest/SubagentReader.swift` | 209 | E、J：helpers / order 增长、meta 重试、目录遍历只认 `agent-*.jsonl` | C-021 / C-023；helpers 只增不减（与磁盘上的文件数成正比，每个约几 KB）→ 剩余风险 |
| `Ingest/TokenLedger.swift` | 392 | C、E、H：累加、恢复、锁、`queue.sync`、文件 / 去重表增长 | C-004 / C-005 / C-014 / C-016 / C-028；**和独立实现逐项对照**（含跨文件去重、断点恢复） |
| `Ingest/TranscriptLine.swift` | 238 | C、E：usage 数字、tool 名 / id、`ToolDetail` | C-004 / C-018 / C-023 / C-025 |
| `Ingest/TranscriptReader.swift` | 231 | A、C、E：`apiError!.at`（前面有 nil 判断）、`bootstrap` 循环、`TranscriptLocator.find` | C-013 / C-026；`Paths.isSafeID` 保证不会拼出 `../` |
| `Fusion/ActivityResolver.swift` | 192 | C：纯函数，只有 `Date` 运算，随机信号 2 万组 | 无问题（阶段和动作一致、`nextChange` 一定在未来）；输入里的未来时间戳问题在入口处解决（C-026） |
| `Fusion/BuddyState.swift` | 132 | E：`inbox` / 读取器 | 无问题（`resetSessionScope` 全部作废） |
| `Fusion/HelperAttributor.swift` | 121 | C、E：`Int(…)`、`claimed` 清理、扣留 | C-003 / C-006；`claimed` 每次 update 清理（600 秒）✓ |
| `Fusion/IdentityResolver.swift` | 264 | A–C、E：载入 / 存盘 / 别名 / 工位 / 时间 | C-002 / C-009；别名 / 索引的清理逻辑正确 |
| `Fusion/SessionEngine.swift` | 1063 | A–C、E、J：`entry!` / `meta!` / `lastMetaRefreshAt!`（都紧跟在 nil 判断之后）、缓存、拼路径（`hookLogPath` / `locateTranscript` 都过 `isSafeID`）、轮次判定 | C-014 / C-026；整机随机灌数据（3 个种子 × 500 步）无崩溃、快照不变量成立 |
| `Fusion/SessionSignals.swift` | 65 | 数据结构 | 无问题 |
| `Fusion/SessionStore.swift` | 250 | F、G、H、I：定时器 / 监听器的释放、`[weak self]`、队列使用、20 Hz 限速、并发 API | C-019；线程安全用 4 个线程同时乱用公开 API + 数据变化压力测试验证（无死锁 / 崩溃）；`diagnostics()` 是 `queue.sync`，主线程会等一次 tick（见下面 I 项） |
| `Fusion/ToolCatalog.swift` | 55 | 字符串处理 | 无问题（随机字符串 3000 个，含 `…` / emoji / RTL / NUL） |
| `Fusion/ToolTracker.swift` | 150 | E | C-011 |
| `Tools/DumpCommand.swift` | 290 | C：`Int(sec)`、`String(format:)` | C-030 |
| `Tools/FakeTree.swift` | 323 | A：`raw.baseAddress!`（只在循环体里、`count > 0` 才进） | 无问题；只写文件（测试夹具），不读 |
| `Tools/ReplayCommand.swift` | 631 | 根目录安全（必须是空目录或不存在）、除零（`pct` 有非空保护）、`Int(…)` | 无问题 |

**A 全仓库扫描**：`try!` / `as!` / `fatalError` / `precondition` / `assert` 在 BuddyCore 里 **0 处**；`!` 强制解包共 10 处（SessionEngine 6 处、RegistryScanner 1 处、TranscriptReader 1 处、FakeTree 2 处），逐个确认前面都有 nil / 长度保护。
**I 主线程同步文件 IO**：`grep` 了 `Sources/BuddyOffice`：BuddyCore 的公开同步读文件函数（`FileIO.*`、`TranscriptLocator.find`、各个 Reader）**没有一个被 BuddyOffice 直接调用**；App 只通过 `SessionStore`：`start()` 是 `queue.async`、`markSeen` / `rerollAppearance` 是 `async`；`stop()`（`applicationWillTerminate` / 切换演示模式时）和 `diagnostics()`（设置页打开 / 刷新时）是 `queue.sync`——主线程会等 ingest 队列跑完当前那一次 tick（毫秒级，首次 tick 读尾部窗口也只有几十毫秒），退出时 `TokenLedger.flush()` 会再等一次当前文件的后台扫描（最长约一个大文件的扫描时间，README 里 44 MB 是 0.3–0.5 秒）。
唯一直接读数据文件的是 BuddyOffice 自己的 `JumpService.DesktopMeta`（C-032）。

## 3. 成员集合（缓存 / 字典 / 数组）上界表

| 位置 | 集合 | 键 / 内容 | 上界或清理 | 结论 |
|---|---|---|---|---|
| `RegistryScanner.entries` | `[Int32: Entry]` | pid | 每次扫描删掉目录里已经没有的 pid | ✓ |
| `RegistryScanner.cachedListing` | 单个 | 目录列表 | 单个值，2 秒过期 | ✓ |
| `DesktopMetaReader.index / pathToHost / cliIndex` | 字典 | host / 路径 / cliSessionId | 文件消失时删；`cliIndex` 每次变化重建；prior ids ≤ 256/个 | ✓（C-010） |
| `DesktopMetaReader.shadowed` | 字典 | 副本路径 | 文件消失 / 赢家消失时删 | ✓（C-020 新增） |
| `SubagentReader.helpers / order` | 字典 + 数组 | 子代理文件 | 与磁盘文件数成正比；读取器随 buddy 离场 / 换会话释放；已完成的只留几 KB | 有界（按文件数）；剩余风险 |
| `TranscriptFacts.openToolUses / recentToolUses` | 数组 | 工具调用 | 64 / 32，超出丢最老 | ✓ |
| `TokenLedger.files / fileList / filesById` | 字典 + 数组 | 跟踪的文件 | 没人用的 ≤ 64（转存断点后清出） | ✓（C-014） |
| `TokenLedger.messages` | `[UInt64: Rec]` | message.id 哈希 | 随文件清出一起删；单文件受文件大小限制 | ✓（C-014） |
| `TokenLedger.persisted` | 字典 | 账本里的断点 | 只增加被清出去的文件；写盘时丢掉磁盘上已不存在的文件 | ✓ |
| `TokenLedger.groups / groupNoLedger` | 字典 / 集合 | buddy key | `removeGroup` 都删（原来漏了 `groupNoLedger`） | ✓ |
| `IdentityResolver.identities / aliasIndex` | 字典 | key / 别名 | 载入 ≤ 2000 个、别名 ≤ 40/个；7 天过期（存盘时清理） | ✓（C-009） |
| `IdentityResolver.lastPersistedSeen` | 字典 | key | 过期时同步删（原来漏了） | ✓（C-009） |
| `ToolTracker.open / closed` | 数组 | 调用 | 512 / 64 | ✓（C-011） |
| `HelperAttributor.claimed` | 字典 | tool_use id | 每次 update 清理 600 秒前的 | ✓ |
| `BuddyState.inbox` | 数组 | hook 事件 | 每次 poll 排空；扣留最多 400 ms（C-006）；一次交入 ≤ 20000（C-029） | ✓ |
| `HookLogReader.PollResult.events` | 数组 | 事件 | ≤ 20000/次 | ✓（C-029） |
| `JSONLTailer.pending` | `[UInt8]` | 半行 | ≤ maxLine + 一个块；读完释放 | ✓（C-015） |
| `SessionEngine.buddies` | 字典 | buddy key | 离场 8 秒后删；下班工位 ≤ 4、12 小时过期 | ✓ |
| `SessionEngine.resolvedKeys / livenessCache` | 字典 | pid | 每次 poll 清理已经不在的 pid | ✓ |
| `SessionEngine.transcriptPathCache / transcriptMissAt` | 字典 | sessionId | 每 30 秒清理 | ✓（C-014） |
| `SessionStore.lastSnapshots / latestSnapshots` | 数组 | 快照 | 与 buddy 数成正比 | ✓ |

## 4. 其它审查项（句柄 / 闭包 / 线程 / 锁）

- **句柄**：`FileIO.open` 的三个调用点（`readAll`、`JSONLTailer.poll`、`JSONLTailer.seekToTail`）都是 `defer { close(fd) }`；`listDirectory` 是 `defer { closedir }`；`FSEventStream`：Create 失败不需要释放、Start 失败走 `Invalidate + Release`、`stop()` 是 `Stop → Invalidate → Release`，`deinit` 也调 `stop()`；`SessionStore` 的 `DispatchSourceTimer` 在 `stop()` 里 `cancel()`。实测见 C-035。
- **循环引用**：`SessionStore` 里所有回调都是 `[weak self]`（`TokenLedger.onChange`、`FileWatcher` handler、定时器 handler、`callbackQueue.async`）；`TokenLedger.poke` 的 `queue.async` 是 `[weak self]`；没有发现循环引用。
- **锁**：`FileIO`（观察口 / 计数 / 临时文件计数）、`TokenLedger`（除 C-016 之外的状态都在锁里，`flush` / `waitUntilIdle` 逻辑见上）、`FakeProcessProbe` / `VirtualClock` / `SessionStore.latestSnapshots` 都有锁；`SessionEngine` 及其读取器只在 ingest 队列上使用（由 `SessionStore` 保证，`applicationWillTerminate` 也是 `queue.sync`）。
- **主线程**：见上面 I 项。

## 5. 「解析器 × 模糊类别」覆盖矩阵

列：**A** 每个字节位置截断（含多字节 / `\uXXXX` 中间）；**B** 随机字节（0/1/2/7/64/4096/1 MiB）；**C** 半行 / 只有换行 / 很多空行；**D** 超长行（1.5 MB / 恰好 4 MiB / 4 MiB+1 / 16 MiB）；**E** 非法 UTF-8；**F** 写到一半（逐步追加）/ 截短 / 轮转 / 换 inode；**G** JSON 层面（深嵌套 / 超出 Int64 / 负数 / 浮点当整数 / 类型错误 / null / 重复键 / 超长键 / 空对象数组）；**H** 持久化文件被截断 / 乱码 / version 不对 / 字段缺失。「—」= 该类别对这个解析器不适用（原因在括号里）。

| 解析器 | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| `JSONLTailer`（poll / seekToTail / committedOffset / seek） | `tailerResumeFromCommittedOffset`（100 个恢复点）、`tailerSeekToTailAlignsToLineStart`（150 个窗口） | `tailerRandomBytesOfEveryLength` | `tailerHalfLinesAndBlankLines`、`tailerMatchesTheReferenceOnRandomFiles`（120 轮 × 极小块 / 极小行上限，逐行对独立实现） | `tailerOversizeLineBoundaries`（4 档 + 半行补完） | `tailerMatchesTheReference…`（片段里含非法字节） | `tailerIncrementalAppendsEqualOneShot`、`tailerSurvivesTruncationRotationAndReplacement` | —（字节级） | — |
| `LineSanitizer` / `HookLogReader` | `hookLineTruncatedAtEveryByte`（8 个样本 × 每个字节） | `hookLineRandomBytes` | `hookReaderIncrementalEqualsOneShot` | `hookLineJSONLevel`（1 MiB 键 / 值）、`RobustnessTests.aHugeGarbageLine…`、`c029`（6 万行） | `hookLineWithInvalidUTF8Everywhere`（24 种 × 行首 / 行尾 / 每个字段）、坏转义 13 种 | `hookReaderIncrementalEqualsOneShot`、`c029` | `hookLineJSONLevel`（30 种）、`c003` | — |
| `TranscriptLineParser` / `TranscriptReader` / `TranscriptFacts`（含 token usage） | `transcriptLineTruncatedAtEveryByte`（9 种行 × 每个字节） | `transcriptLineRandomAndTypeConfusion` | `transcriptReaderIncrementalEqualsOneShot` | `FuzzEngineTests.engineSurvivesExtremeValuesEverywhere`（1 / 4 / 4 MiB+1 的行）、tailer 那一组 | `transcriptLineRandomAndTypeConfusion`（变异里插入非法 UTF-8） | `transcriptReaderIncrementalEqualsOneShot`、引擎整机（截短 / 删除 / 换掉） | `transcriptLineRandomAndTypeConfusion`（2500 个随机类型）、`c004`、`c012`、`c025` | — |
| `RegistryScanner`（parse + scan） | `registryTruncatedAtEveryByteIsHalfWritten` | `registryRandomBytesAndMutations` | `registryScannerConvergesUnderRandomRewrites`（清空） | 由 `FileIO.readAll(maxBytes)` 覆盖（`specialFiles`） | `registryRandomBytesAndMutations` | `registryScannerConvergesUnderRandomRewrites`（半写 / 垃圾 / 删除 / 换类型 60 轮）、`fuzz_registryScannerWithDecoyFiles` | `registryJSONLevelAgreesWithOracle`（4000 个 + 独立判断）、`c001`、`c017` | — |
| `DesktopMetaReader`（parse + refresh） | `desktopMetaTruncationAndTypeConfusion` | 同左 | — | `desktopMetaRefreshOnJunkTree`（4 MiB+10） | 同 B | `desktopMetaRefreshOnJunkTree`（改 / 删 / 来回折腾） | `desktopMetaTruncationAndTypeConfusion`（3000 个 + 独立判断）、`c010`、`c020`、`c023` | — |
| `SubagentReader`（poll + meta） | —（jsonl 走 TranscriptReader） | `subagentReaderOnJunkDirectory`（垃圾 meta / 记录） | 同左 | — | 同左 | `subagentReaderOnJunkDirectory`（追加 / 截短 / 删除 / 新文件） | `subagentReaderOnJunkDirectory`（`FuzzJSON` 的 meta） | — |
| `TokenLedger`（扫描 + `ledger.json`） | `ledgerTruncatedAtEveryByte`（前 90 / 后 90 / 随机 50 个位置） | `ledgerGarbageDirectoryAndUnreadable`（0…1 MiB 垃圾） | `ledgerMatchesIndependentReference`（垃圾行 / 半行） | 已有 `aBigFileIsScannedFast` + 引擎整机 | 同 A（`ledgerRandomCorruption` 插入非法 UTF-8） | `ledgerMatchesIndependentReference`（追加 + 重启断点续读）、`ledgerGroupAcrossFilesMatchesReference`（跨文件去重） | `ledgerFieldwiseMutations`（version / files / 每个字段 13 种错误类型）、`c004`、`c005` | 同 G + `ledgerRandomCorruption`（100 个）、`ledgerGarbageDirectoryAndUnreadable` |
| `IdentityResolver`（`identities.json`） | `identitiesTruncatedAtEveryByte` | `identitiesCorruption`（0…1 MiB 垃圾） | — | — | `identitiesCorruption` | — | `identitiesCorruption`（每个字段 16 种错误类型）、`c002`、`c009` | 全部；`engineOverwritesGarbagePersistenceFiles`（引擎启动时两个文件都是垃圾） |
| `TimeUtil`（parseISO / parseProcStart / JSON 毫秒 / 格式化） | `timeISOFuzz`、`timeProcStartAndJSONMillisFuzz`（每个前缀） | 同左 | — | — | 同左（变异插入非法 UTF-8；Unicode 数字） | — | `timeProcStartAndJSONMillisFuzz`（NSNumber 各种形态：布尔 / UInt64.max / Int64.min / NaN / 无穷） | — |
| `ProcessProbe`（`SystemProcessProbe` / `classify`） | — | `processProbeFuzz`（随机 pid 2000 个 + 极端 pid） | — | — | — | — | `processProbeFuzz`（极端时间的 `classify` 组合） | — |
| `FileWatcher`（路径 / 分流） | — | — | — | — | `weirdFileNamesArriveIntact`（Unicode / 换行 / 空格 / 超长） | `stopWhileCallbacksAreQueued…` | `c022`（畸形路径）、`c019`（分流） | — |
| `FileIO` / `Paths` | — | `specialFiles`、`pathRulesAgreeWithByteOracle`（2 万个） | `specialFiles`（空文件） | `specialFiles`（maxBytes 边界） | `pathRulesAgreeWithByteOracle`（组合字符 / NUL / RTL） | `specialFiles`（读的时候被截断）、`c024` | — | — |
| 引擎整机（所有数据源一起） | — | — | — | 4 MiB 级长行 | 是 | `engineSurvivesExtremeValuesEverywhere`（3 个种子 × 500 步，含 4e9 秒的时间大跳跃）、`engineWithHundredsOfSessionsComingAndGoing` | 极端值随机灌入每个数据源 | 是 |

任务书第 4 节的已知坑对应用例：tool 名被截断（`hookKnownPitfallsUnderMutation`：48 个截断长度 × 前缀匹配）；`\u` 转义被截断（`hookLineTruncatedAtEveryByte` 的「转义」样本、`hookLineWithInvalidUTF8Everywhere` 的坏转义）；AskUserQuestion 的 detail 不能当问题（hook 层 300 次变异 + 会话记录层 C-018）；Codex 文件不能碰（`hookKnownPitfallsUnderMutation`：非 sessionId 一律拼不出路径；`FileAccessTests.codexHookFilesInTheSameDirectoryAreNeverTouched` 已有）；用户输入永不留下（hook 层 200 次变异 + `transcriptFactsNeverKeepConversationText`：用户输入 / 助手文字 / 工具结果 / thinking 的内容不出现在任何解析结果里）。

## 6. 「绝不打开 `*.key` / `*.sock`」保护是否无法绕过

结论：**现在绕不过去**（修复前有四条绕过，C-007）。

| 绕过方式 | 修复前 | 现在 |
|---|---|---|
| 大小写（`.KEY` / `.Sock` / `CC-SOCKS`） | 认不出来 | 认得出（不区分大小写；开尔文符号 K 也算） |
| 符号链接（`<pid>.json → *.key`，链式，目录符号链接，相对符号链接） | 读到内容 | `realpath` 解析后拒绝，`open` 都不调用；打开后 `F_GETPATH` 再核对一次 |
| `../`、`./`、`//`、结尾 `/` | `..` 靠 `lastPathComponent` 已经能挡 | 仍能挡（27 种变体测试） |
| 路径里的 NUL | 真的打开了 | 直接拒绝 |
| 带空格 / Unicode / 换行的路径 | 名字判断只看后缀，不受影响 | 同左（诱饵目录里有 `new\nline.json`、`٣٤.json` 等） |
| `<pid>.json` 与 `<pid>.<sha256>.key` 的边界 | `isRegistryFileName` 只认 `^\d+\.json$`（≤ 10 位 ASCII 数字），`.key` 文件连 stat 都不碰 | 同左；和按字节写的独立判断对照 2 万个随机串一致 |
| 命名管道 / 设备 / socket / 目录 | `open` 会阻塞（C-008） | 只打开普通文件 |
| **硬链接**（同一个 inode 的另一个名字） | 挡不住 | **仍然挡不住**：从路径和 `F_GETPATH` 都看不出这个 inode 也叫 `.key`；要求攻击者能在 `~/.claude/sessions` 里建硬链接，那时他自己已经能读 key 了 → 剩余风险 |

**`FileIO` 是不是所有读取的唯一入口**：`grep` 了 `Sources/BuddyCore` 里所有 `open( / Darwin.open / FileHandle / Data(contentsOf / String(contentsOf / contentsOfFile / fopen / read( / pread( / URL(fileURLWithPath / FileManager`：读取只有 `FileIO`（`open` / `readAll` / `stat` / `fstat` / `listDirectory`）；`pread` 只出现在 `FileIO.swift` 和 `JSONLTailer.swift`（读的是 `FileIO.open` 给的 fd）；`Tools/FakeTree.swift` 有 `open(O_WRONLY…)`，是造假数据的**写**；`URL(fileURLWithPath:)` 只在 `FileIO.writeAtomically`；`FileManager` 只在工具（建 / 删临时目录）里。这条约定现在有测试守着：`FuzzFileIOTests/fileIOIsTheOnlyReaderInSources`（源码扫描，任何人以后在别处加 `open(` 都会失败）。
`FileWatcher.resolved` 用 `realpath`（只解析路径，不读文件内容）。BuddyOffice 里唯一绕过 FileIO 的是 `JumpService.DesktopMeta`（C-032，只读 `local_*.json`）。

## 7. 剩余风险（没修 / 修不了 / 需要别人决定）

1. **硬链接**指向 `.key` 的文件读取保险挡不住（见上）。威胁模型里攻击者已经在同一用户下，只作记录。
2. **同一个 inode 原地重写、而且新内容比旧偏移长**的情况，`JSONLTailer` 无法察觉（只看 inode 和大小）；会话记录 / hook 文件是只追加的，所以正常使用不会碰到。
3. **过去的时间戳没有夹**：只夹了「比现在晚一天以上」的（C-026）；一条时间戳很旧（比如 2001 年）的行不会毒化「取最大值」类的事实，但会让「最早」类的取值（`estimateTurnStart` 取 `min`）变成很久以前 → 本轮用时显示为几十年。数值仍在合理范围（不会溢出）。
4. **`JSONLTailer.poll` 一次读完所有新增字节**（没有单次预算）：App 被挂起几小时后醒来，一个 50 MB 的增量会在 ingest 队列上解析 0.5～1 秒。`HookLogReader` 有事件数上界（C-029），会话记录没有（要加预算需要改「事实是否已追平」的语义，属于设计变更，没动）。
5. **`SubagentReader.helpers` 只增不减**（每个几 KB，与磁盘上的子代理文件数成正比）；一次 Workflow 派几百个子代理时会有几 MB。
6. **`DesktopMetaReader.refresh` 每 0.5 秒 stat 全部 `local_*.json`**：元数据文件很多（上千个）时是每秒几千次 stat。要优化需要目录级签名（元数据是原地重写，目录签名不变，做不了）。
7. **退出时 `TokenLedger.flush()` 会等当前文件的后台扫描**（在主线程，最长约一个大文件的扫描时间）。
8. ThreadSanitizer / AddressSanitizer 各把全量测试跑了一遍（0 条报告），但只覆盖测试触发的路径；真实 App 里 FSEvents、主线程回调和 ingest 队列的交织没有在消毒器下跑过（用户拒绝了对 App 的 GUI 自动化，见 PROGRESS.md）。
9. **表现层没有自己的防护**（C-033）和 BuddyOffice 的直接读文件（C-032）在我的范围外。
10. 测试用的是 `.dev/core` 隔离包（BuddyCore 用 `-Onone`）+ 根包（BuddyCore 用 `-O`）两套配置各跑一遍；没有在 release 配置下跑测试（`Package.swift` 的 `optimizedLibs` 只对 debug 生效）。

---

## 详细记录：状态机 / 逻辑 / token / dump（来自 issues-logic.md）

> 日期：2026-09-29　范围：任务书 4.1 / 5 节的状态机规则（`Sources/BuddyCore/Fusion` 一层）、token 统计的独立交叉核对、`buddyctl dump` 与登记表的一致性
> 方法：把它当成别人写的代码——先读任务书和源码，再用**假时钟回放**、**独立的参考模型**、**独立的 Python 脚本**、**变异测试**和**真实数据**逐条核对；只在新测试证明确实有 bug 时才动 `Fusion/**`。
> 铁律遵守情况：真实数据只读了 `~/.claude/sessions/<pid>.json`（文件名按 `^\d+\.json$` 过滤，`.key` 一次没打开过，连 stat 都没做）、按登记表 sessionId 拼出的 `~/.claude/.monitor/<id>.events.jsonl`、`~/.claude/projects` 下的会话记录、桌面元数据、`~/.token-meter/plugins/tokens.1m.py` 和 App 自己的 `ledger.json`，全部只读；没有连过任何 `*.sock`，没有读过任何凭据 / 钥匙串；没有改 `~/.claude`、ccmon、用量表（我 import 用量表时设了 `sys.dont_write_bytecode`，它的 `__pycache__` 还是 9 月 28 日 22:09 的那一份）、Claude.app；没有联网、没有 `pkill` App、没有碰正在运行的 `~/Applications/Buddy 办公室.app`、没有运行安装 / 卸载脚本；脚本 / 报告 / 日志里**没有任何对话内容**（只有计数、id 前缀、数字；标题只输出「来自哪一级」和「一致 / 不一致」；两个 Python 脚本的输出里有没有泄漏由 Swift 测试 `py1` / `py2` 逐字检查，冻结快照里有没有泄漏由 `token_crosscheck.py --selftest` 检查）。
> 没有削弱 / 跳过 / 删除任何已有测试；没有屏蔽编译警告（我新增的文件 0 警告）；没有改 Package.swift、BuddyStage、BuddyOffice、PixelKit、BuddyArt、buddyctl、别人的测试文件。
> 我改动的文件：新增 `Tests/BuddyCoreTests/StateRule{,Process,Chain,Invariant}Tests.swift`、`QA/tools/{token_crosscheck,dump_vs_registry,hooklog_replay,mutation_check}.py`、本文件；改了两处 `Sources/BuddyCore/Fusion`（`SessionEngine.swift`：L-001；`ActivityResolver.swift`：L-003）。

## 0. 结论与统计

**发现 5 个**：P0 0 / P1 1 / P2 2 / P3 2；**由我修复 2 个**（L-001、L-003）；1 个（L-002）在我发现之后已被别的代理接线修好（= `issues-app.md` A-001，我没有改 BuddyOffice）；2 个未修复（L-004 / L-005，都在范围外，且和别的 QA 的条目重复：`spec-trace-core.md` Q-08 / `issues-core.md` C-031）。
另有 7 条「已确认不是问题」（第 1 节末尾，不计入上面的数）。

**新增测试 63 个**（4 个套件；`z1` / `z2` 各带 16 个种子，共 93 个用例）：
`StateRuleTests` 52 个（任务书规则 a…n 逐条 + 清单外的 o）、`StateRuleProcessTests` 4 个（真进程）、`StateRuleChainTests` 5 个（dump 与 App 同一条数据链路 + 两个 Python 脚本在 FakeTree 上跑）、`StateRuleInvariantTests` 2 个（随机回放：参考模型对拍 / 快照不变量）。
另有 4 个 Python 工具（`token_crosscheck.py`、`dump_vs_registry.py`、`hooklog_replay.py`、`mutation_check.py`），前两个带 `--selftest`（Python 3.14 和系统的 3.9 都跑过）。

### 测试命令与结果（都在沙箱外跑；scratch 目录 `.build-qa-logic`，`-j 2`，收工时已删除）

| 命令 | 结果 |
|---|---|
| `cd ~/Desktop/编程项目/Buddy办公室 && BUDDY_SCRATCH=.build-qa-logic scripts/dev.sh test --filter StateRule -j 2`（根包，任务书指定的命令；**收工前删掉 scratch 目录后冷编译重跑的最终一次**） | **63 个测试（4 个套件）：63 通过、0 失败**（测试本身约 2.4 秒）。中途有几次因为别的代理正在改源码（`input file … was modified during the build`）编译失败，隔 20–30 秒重试通过。冷编译的 60 行警告全部来自别人的 `HelperAttributionTests.swift:250`（见 L-005），我的文件 0 警告。 |
| 同上，私有沙箱里跑**全部** BuddyCoreTests（不含别的 QA 正在写的 `Fuzz*`；沙箱 = 把源码 / 测试 rsync 到 `$TMPDIR` 下的隔离包，免得别人改到一半的文件挡住编译） | **290 个测试（25 个套件）：290 通过、0 失败**（约 24 秒）——即原有的 227 个全部还通过 + 我的 63 个。 |
| 稳定性：`--filter StateRule` 连跑 4 次；再在 6 个 CPU 满载进程下跑 1 次；收工前又用编好的测试包连续跑 12 次（`--skip-build`） | 17 次全部 63 / 63 通过（真进程、子进程、虚拟时钟三类测试都没有时序敏感的偶发失败）。**唯一一次例外**：收工前有一次官方命令跑到 1.5 秒左右进程无声地结束——日志截断、没有汇总行、`exit=1`、也没有崩溃报告。我对自己的测试进程发 `SIGTERM` / `SIGKILL` 复现出了**一模一样**的现象，而我的测试里没有 `exit` / `kill` / `try!`，所以这是测试进程被外部杀掉（多个代理共用这台机器），不是测试崩溃；立刻重跑 63 / 63。同一时段 `~/Library/Logs/DiagnosticReports` 里的三份 `swiftpm-testing-helper` 崩溃报告（04:46 / 04:49）都出自别的代理的 `AppLayerFixTests.demoModesWithNonsenseParametersDoNotCrashOrExplode`（`DemoScript.snapshots` 里 NaN → Int / 区间下界大于上界，BuddyStage，范围外，看样子正在被修）。 |
| 修复前失败（在私有副本里把修复撤回，不动真实源码）：L-001 撤回 → `e2`、`e5` | **失败**：`Expectation failed: (h.snap(key)?.activity → .finished) != (Activity.finished → .finished)`（e2）；e5 的 `seen` 序列是 `[finished, finished, finished, interrupted, …]`（e2 一个 issue、e5 三个）。恢复修复后 2 / 2 通过。 |
| L-003 撤回 → `o1`、`o2` | **失败**（6 个 issue）：`Expectation failed: (s?.activity → .compacting) == (expected → .thinking)`、`(K.tool(h.snap(key))?.call.name → nil) == "Bash"`、`(ActivityResolver.resolve(sig(postCompact: 199.98), now: at(201)) → .compacting) == .thinking`。恢复修复后 2 / 2 通过。 |
| 变异测试（第 3 节）：60 个变异 + 手工补的 2 个 | 我的测试杀死 57 个、只被已有测试杀死 4 个、存活 1 个（`M47`，等价变异：引擎层不可达）。 |
| `python3 QA/tools/{token_crosscheck,dump_vs_registry}.py --selftest`（3.14 与 `/usr/bin/python3` 3.9） | 4 / 4 通过。 |

**本轮最重要的几条**
1. **L-003（真实数据发现的）**：真实日志里现在有 3 组 `PreCompact / PostCompact / compact_boundary`（这台机器本会话的 3 次自动压缩），时序和任务书 / README 的假设相反——`compact_boundary` 是压缩**结束**时才写的（比 `PreCompact` 晚 88–104 秒），引擎却把它当「正处在压缩中」，结果每次压缩结束后要等下一条 assistant 行落盘（实测 2.4–3.8 秒，最坏 120 秒）才不再显示「整理上下文」，把压缩完的第一个工具盖住。已修。
2. **L-001**：一轮没有 Stop、也还没有打断标记就结束时，引擎先报 0.4 秒「做完了」再改口成「被打断 / 出错」，而 App 的提醒（`AlertCoordinator`）看到 `.finished` 就会发「做完了」提醒。已修。
3. **token 统计四个口径逐位一致**（独立重写的实现 == 用量表原版 `parse_line` == App 的 `ledger.json` == `buddyctl dump`），真实的 4 个活会话 + 1 个带 prior 的桌面会话都是个位数相同；`dump` 与登记表核对 4 / 4 一致。
4. 变异测试证明：已有测试把大多数数字钉住了（重试余量 15 秒、做完了 5 秒、被打断 3 秒、临时 busy 3 秒、PID 复用 2 秒、0.15 / 0.4 秒……），但**没有钉住**的有 18 个（第 3 节列出）：30 分钟兜底的精确边界、引擎的 45 分钟睡着、quiet 的 10 分钟、离场防抖 3 秒的下界、8 秒收回工位的下界、0.4 秒宽限期的下界、各个「轮次边界」在引擎层的效果、`Task` 也算前台委派……新测试把它们都钉上了。

---

## 1. 问题清单

### L-001 [P2] 一轮结束时证据还不够的 0.4 秒里，引擎先报「做完了」再改口成「被打断 / 出错」
- 现象：登记表翻 idle、hook 正常、但还没有 Stop 事件也没有打断 / 错误的会话记录行时（例如打断标记落盘比登记表晚、或者出错证据晚到），`transition` 把 `turnEnd` 先置成 `.finished`，`finalizePendingEnd` 在 `classify` 返回 nil（宽限期 0.4 秒内）时不改，于是快照在这 0.4 秒里是 `.finished`，之后才变成 `.interrupted`。`AlertCoordinator.observe`（`Sources/BuddyOffice/AlertCoordinator.swift`：`case .finished = s.activity, was != cur, let d = s.lastTurnDuration` 那一段，`wait` 对终端会话是 0）看到 `.finished` 且用时 ≥ 30 秒就登记「做完了」提醒，终端会话当场发出去、桌面会话 8 秒后发——而且之后变成 `.interrupted` 也不会撤销。「被打断」的那一轮还会让白板「正」字多记一笔。
- 根因：`Sources/BuddyCore/Fusion/SessionEngine.swift`（`transition` 里 `newPhase == .idle` 分支，`st.turnEnd = .finished`）。
- 修法：证据不够时先置 `.none`（动作是 `.idle`），证据够了由同一次 `update` 里的 `finalizePendingEnd → complete()` 定下来；宽限期满还没有证据也会定下来（`nextWake` 已经安排在 `endedAt + 0.4 秒`）。正常流程（Stop 先到、比登记表早 40–60 ms）不受影响——分类在同一次 `update` 里完成，不会出现中间态。
- 回归测试：`StateRuleTests › e2_hookInferredInterruptNeverShowsFinished`、`e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst`（Stop / 打断标记在登记表翻 idle 之前 60 ms 到 … 之后 350 ms 到、都没有，共 9 种到达顺序，每 50 ms 记一次动作，断言中途绝不出现错误的结论、最终结论对、只发一次结束事件）。
- 修复前失败的证据：`Expectation failed: (h.snap(key)?.activity → .finished) != (Activity.finished → .finished)`（StateRuleTests.swift:368，e2）；e5：`seen → [finished, finished, finished, interrupted, …]`。
- 修复后：e2、e5 通过；变异 M48（把修复撤回）被 e2、e5 杀死。整套 BuddyCoreTests 290 / 290 通过。
- 残留（`spec-trace-core.md` Q-13 也提到）：宽限期内动作是 `.idle`——舞台会先切到空闲桌面再切到「做完了 / 被打断」，比先闪绿色 ✓ 好，但还不是「保持 busy 直到判定」。想更彻底，可以在宽限期内保持上一个 busy 动作（要让 `phase` 和登记表暂时不一致，我没有这么改）。
- 状态：**已修复**

### L-002 [P1] 设置里的「空闲多久后打盹 / 睡着」「启动时只显示最近 N 小时」是摆设
- 现象：`idle.dozeMinutes` / `idle.sleepMinutes` / `dormant.recentHours` 只存进 UserDefaults，没有任何代码把它们传给 `SessionEngine.Options.dozeAfter / sleepAfter / dormantRecent`（`RealProvider.make` 只造默认 Options；`SessionStore.options` 是 `let`）；`dormant.max` 只在 `AppModel.refreshDerived` 里按座位号 `.prefix`，引擎里那几个名额仍占着座位。任务书 5.4「两个时间都可以在设置里改」/ 7.5 没有实现。我用「设置键 → 消费者」的静态统计核实过：三个键在 `Sources/BuddyOffice` 里除了设置页和默认值没有任何读取者。数据层这一半是好的（`EngineScenarioTests.dozeAndSleepThresholdsAreConfigurable`、我的 `g1`）。
- 根因：BuddyOffice 没接线（不在我的修改范围）。
- 修法：由别的代理处理——我写完发现后不久（03:54 起）`Sources/BuddyOffice/EngineConfig.swift` / `RealProvider.swift` / `Tests/BuddyOfficeTests` 出现，现在 `RealProvider.make` 已经用 `SessionEngine.Options(paths:)` 加 `EngineConfig.apply(to:settings:)` 覆盖四项设置再 `SessionStore(options:)`（「下次启动生效」）。这和 `issues-app.md` A-001 是同一条。
- 回归测试：别的代理的 `Tests/BuddyOfficeTests/EngineConfigTests.swift`；我这边没有重复写（我曾写过一个 `withKnownIssue` 的静态检查，接线出现后就删掉了）。
- 修复前失败：同 A-001（应用层的 `EngineConfigTests`；放上「旧行为骨架」——设置不传给引擎——后失败：`EngineConfigTests.swift:10:9: Expectation failed: (v.dozeAfter → 600.0) == (180 → 180.0)`；修复后通过）。
- 状态：已修（由应用层修复，同 `issues-app.md` A-001；「下次启动生效」）。我的 `chain1` 里对 App 造 `SessionStore` 方式的断言已跟着新的 `RealProvider` 更新。

### L-003 [P2] 压缩结束后仍显示「整理上下文」（`compact_boundary` 是压缩**结束**时才写的）
- 现象：真实日志（这台机器，20c4bcc8 那个会话的 3 次自动压缩）里：`PreCompact(auto)` → 88–104 秒后 → 会话记录先写一行 `isCompactSummary` 的 user 行（比边界早 0.4 秒）→ hook 的 `SessionStart(source=compact)` → `PostCompact`（晚 0.02–0.03 秒）→ `compact_boundary`（比 `SessionStart(compact)` 晚 0.04–0.07 秒）→ 2.4–3.8 秒后才是第一条 assistant 行（第一个 `PreToolUse` 在 3–5 秒后）。压缩**开始**时会话记录里什么都没有。引擎的会话记录规则（`ActivityResolver.busyActivity` 1b）却是「`compact_boundary` 之后没有新的 assistant / user 行 → 整理上下文（最多 120 秒）」，而且排在「有打开的工具」之前——所以每次压缩**结束**后，即使 hook 已经报了 `PostCompact`，buddy 还会继续显示「整理上下文」，把压缩完的第一个工具盖住，直到下一条 assistant 行落盘（实测 2.4–3.8 秒；主会话记录要等整条消息生成完才写盘，慢的时候更久，兜底 120 秒）。
- 根因：`Sources/BuddyCore/Fusion/ActivityResolver.swift`（`busyActivity` 里 `compactBoundaryAt` 那一段）。任务书 5.4「或者会话记录显示正处在 compact_boundary 压缩中」以及 README / DESIGN 的「没有任何真实样本，只用合成 fixture 测」都是在没有真实数据时的假设；现在有真实样本，假设不成立。
- 修法：hook 已经说压缩结束了（`postCompactAt`——`PostCompact` 或 `SessionStart(compact)` 都会写它——不早于 `compact_boundary` 前 5 秒，`boundaryHookSlack`）就不再用 `compact_boundary` 显示整理上下文；没有 hook 的会话（只有这一个信号）照旧。已有的 `ActivityResolverTests.compactingFromTranscriptBoundary` 不受影响（它没有 postCompactAt）。
- 回归测试：`StateRuleTests › o1_compactionEndsWhenTheHooksSayItEnded`（用真实时序：PreCompact → 100 秒 → isCompactSummary 行 / SessionStart(compact) / PostCompact / compact_boundary → 4.6 秒后 `PreToolUse`；断言压缩中显示整理上下文、结束后不再显示、第一个工具马上显示）、`o2_boundaryHookSlackIsFiveSeconds`（5 秒口径：4.9 秒算、5.1 秒不算；没有 hook 仍是整理上下文；120 秒兜底）。
- 修复前失败的证据：`Expectation failed: (s?.activity → .compacting) == (expected → .thinking)`；`(K.tool(h.snap(key))?.call.name → nil) == "Bash"`；`(ActivityResolver.resolve(sig(postCompact: 199.98), now: at(201)) → .compacting) == .thinking`。
- 修复后：o1、o2 通过；BuddyCoreTests 290 / 290 通过。
- 顺带：Core README / DESIGN 里「PreCompact / PostCompact / compact_boundary 没有任何真实样本」的说法已经过时（文档不在我的修改范围，未改）。
- 状态：**已修复**

### L-004 [P3] 登记表半截文件「最多 5 次」的口径
- 现象：任务书 4.1「每隔 50 ms 重试一次，最多 5 次」，实现是「首读 + 4 次重试 = 共 5 次读」（`RegistryScanner.maxRetries = 5`，`failures < 5` 才排下一次）；更自然的读法是 5 次**重试**（共 6 次读，窗口 250 ms 而不是 200 ms）。现有测试 `RegistryScannerTests.halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms` 把「共 5 次」写成了断言（变异 M59 被它杀死）。实际影响几乎为零（半截文件微秒级就写完）。
- 根因：任务书措辞有歧义；实现选了一种读法。
- 修法：若要改成 5 次重试，改 `RegistryScanner`（Ingest，不在我的范围）并同时改那条已有测试的断言（我不能改）。
- 回归测试：我的 `n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine`（引擎层：12 次 50 ms 心跳之后仍是上一份好记录、`nextWake` ≤ 50 ms、写完整后立刻更新）只钉「保留 + 50 ms」，不钉次数。
- 状态：不修（P3，任务书措辞有歧义；影响几乎为零——半截文件微秒级就写完；已在 DESIGN.md §13 记录「5 次」按总读次数理解及理由）。

### L-005 [P3] 既有测试文件里有编译警告
- 根因：Swift Testing 宏展开对 `(a?.b ?? []).isEmpty` 这种写法会报两条编译警告。
- 回归测试：本身就是测试文件里的警告；修复后测试目标 0 警告（见 QA/evidence/regression-final/summary.txt）。
- 现象：根包 `swift test` 首次全量编译输出里有 120 行含 `warning:` 的行，全部来自 `Tests/BuddyCoreTests/HelperAttributionTests.swift` 里两处 `#expect((h.snap(DesktopFixture.key)?.helpers ?? []).isEmpty)`：这种写法在 Swift Testing 宏展开里报 `left side of nil coalescing operator '??' has non-optional type '[HelperSnapshot]?'` 和 `expression of type 'Bool?' is unused`。DESIGN.md「debug 和 release 构建都是 0 警告」只对库目标成立。我的新测试避开了这种写法（先取值再 `#expect`），0 警告。
- 后续（收工前，删掉 scratch 目录后冷编译重跑）：04:49 有人把其中一处（现在的 `:262`）改成了先取值再 `#expect(shown.isEmpty)`，`issues-core.md` C-031 因此标成「已修」；但**另一处 `HelperAttributionTests.swift:250` 还是原样**，冷编译仍有 60 行警告（就是那一处，重复出现在 15 次编译批次里）。
- 修法：把 `:250` 也改成 `let shown = h.snap(DesktopFixture.key)?.helpers ?? []` 再 `#expect(shown.isEmpty)`（和 `:262` 一样），或者 `#expect(h.snap(DesktopFixture.key)?.helpers.isEmpty == true)`。没改：任务书规定不改别人的测试文件。
- 状态：已修（主线程收尾时把 `:250` 和 `:262` 两处都改成了先取值再 `#expect`，断言的意思不变；同 `issues-core.md` C-031）。

### 已确认不是问题（不计入统计）
- **N-1 `type == "assistant"` 与 `message.role == "assistant"` 的判据差异**（`spec-trace-core.md` Q-09）：真实数据里 5372 行带 `usage` 的行（4 个活会话）两个判据 0 行不一致；两边都只统计 assistant。
- **N-2 30 分钟兜底在引擎层不可达**：变异 M47（把 `expireStale` 的 `registryIdle` 恒置 false）存活——因为登记表 idle 时主线程的调用早被「轮次边界（登记表变 idle）」关掉了，兜底只对小助手名下的记录起作用（`b8` 钉着）；规则本身由 `ToolTracker` 单元测试 `b7` 钉在精确边界（30:00 不关、30:00.001 关）。是防御性代码，不是 bug。
- **N-3 一条从不变成 busy 的提示**（比如本地处理的斜杠命令）留下的「幻影一轮」：`turnStarted` → 3 秒后 `turnFinished(duration: 0, interrupted: true)`，`lastTurnDuration` 被改成 0、`lastTurnEndedAt` 不变、未读被清。实验确认过；App 不消费事件（`AppModel` 里 `onEvent = { _ in }`），`lastTurnDuration` 只在 `.finished` 时显示，所以没有可见影响；「下一轮开始时清未读」是任务书的规则。
- **N-4 `isCompactSummary` 的 user 行被当作「人的一次输入」**（`isPrompt`）：只影响「没有 hook 的会话」里 `f.lastPromptAt`；本轮开始时间取最早的候选（登记表 busy 时间 / hook 提示），不受影响。
- **N-5 会话标题只在会话记录的尾部窗口（512 KB）里找**：真实数据 47 个会话文件里所有 `custom-title` / `ai-title` 行都在尾部窗口内（离文件末尾最远 28,312 字节，Claude Code 会反复把标题行写在末尾）。
- **N-6 `hookActive` 的「掉线」启发式**（会话记录比 hook 领先 > 15 秒就当 hook 掉线，`spec-trace-core.md` Q-06）：没有 Stop 又没有任何打断证据时会把「被打断」判成「做完了」，但所有打断形态（用户行、`isAbortedMidStream`）都有会话记录证据，只剩极窄的路径；README 已记录这个启发式。
- **N-7 同一批次里相隔 > 0.25 秒的并行调用会被提前「取代」**：真实 hook 日志独立回放里 8aab9e77（没有子代理）65 个 Pre 里 6 个被取代、另有 5 个 Post 找不到对应的 Pre（多半就是被提前取代的那些）；对应 README 的已知限制，只影响「×N」的个数和「当前工具」。

---

## 2. 规则 × 测试 × 状态 对照表

「已有测试」列括号里写的是**变异测试证明它有没有把具体数字钉住**（见第 3 节）。新测试的完整函数名见第 6 节。

| 规则 | 任务书出处 | 验证它的已有测试（数字有没有钉住） | 新增测试 | 结论 |
|---|---|---|---|---|
| (a) 并行工具：同一毫秒两个 Read 先进先出配对；距离上一个主线程 Pre 超过 0.25 秒算新一批 | 5.2 Pre / Post | `ToolTrackerTests.parallelCallsInTheSameMillisecondShareABatch`、`identicalParallelCallsCloseFirstInFirstOut`（FIFO 已钉，M05）、`postFallsBackToToolNameThenIgnores`、`callsWithin250msOfThePreviousPreStayInTheSameBatch`（用 0.2 / 0.3 两点夹住 0.25，M01 / M02 都杀；但没有恰好 0.25 / 0.251）。引擎层没有 | a1（引擎层：同一毫秒三个 Read、FIFO、名字优先）、a2（恰好 0.25 秒同批 / 0.251 秒新批）、a3（detail 对不上退回「最早的同名」）、z1 | ✓ |
| (b) 悬空工具：被新一批取代；轮次边界（Stop / UserPromptSubmit / SessionStart / 登记表 idle / stop_hook_summary）关掉主线程全部打开调用；idle 且开着超过 30 分钟强制关 | 5.2 | `ToolTrackerTests.newBatchClosesOlderOpenCallsAsSuperseded`、`permissionDeniedDanglingIsClosedByTheNextBatch`、`turnBoundariesCloseAllMainCalls`、`aBoundaryOlderThanAnOpenCallDoesNotCloseIt`、`staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle`（只钉「29 分钟不关、31 分钟关」，M03 / M08：已有测试杀不死）、`helperOwnedRecordsExpireRegardless`。**引擎层五种边界一个都没有** | b1 Stop、b2 UserPromptSubmit、b3 SessionStart、b9 SessionEnd、b4 登记表 idle、b5 stop_hook_summary（含「比调用旧的不能误关」）、b6 被下一批取代 + 晚到的 Post、b7 30 分钟精确边界、b8 小助手名下 29 / 31 分钟、z1 | ✓（30 分钟兜底对主线程在引擎层不可达，见 N-2） |
| (c) 重试：显示第 n / 共 m 次；`retryInMs` + 15 秒后没有新行则不再显示 | 5.4 busy 2 | `ActivityResolverTests.retryingWithinRetryInMsPlus15Seconds`（118.9 / 119.1 秒，M17 / M18 都杀）、`retryingBeatsOpenTools`；`EngineScenarioTests.retryingThenBackToThinkingWhenTheRetryWindowPasses`（16 / 16.5 秒）；`TranscriptTests.apiErrorIsRecordedWithRetryInfo` | c1（引擎层：3/10、retryInMs 2.5 秒 → 17.4 秒还在、17.6 秒消退）、c2（新的 user 行也清掉重试） | ✓ |
| (d) 出错：重试到上限 / 最后一条 assistant 是合成的 API 错误 | 5.4 idle 3 | `EngineScenarioTests.erroredTurnStaysErroredUntilItStartsDozing`（两个信号同时给）、`ActivityResolverTests.erroredStaysUntilDozing`、`TranscriptTests.syntheticApiErrorAssistantIsRecognized`（M40 只有我的 d1 杀） | d1（只有重试到上限）、d2（只有合成错误消息）、d3（5/10 且之后恢复 → 不算）、d4（到上限但之后又有 assistant 行 → 不算）、d5（打断后的 "No response requested." 不算错误）、d6（出错优先于做完了） | ✓ |
| (e) 被打断：会话记录里的 `[Request interrupted by user`（比上次轮次结束更晚）和「hook 正常但 busy→idle 没有 Stop」两种形式，持续 3 秒 | 5.4 idle 1 | `ActivityResolverTests.interruptedLasts3SecondsThenIdle`（2.9 / 3.1 秒，M13 / M14 杀）；`EngineScenarioTests.aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted`、`interruptDetectedFromTheTranscriptWithoutAnyHook`、`abortedMidStreamAlsoCountsAsAnInterrupt`、`aNormalStopAfterAnEarlierInterruptIsNotInterrupted`；`TranscriptTests.userInterruptTextIsDetectedInBothShapes`、`abortedMidStreamAssistantIsAnInterrupt`；`StoreTests.timeDrivenChangesHappenOnTimeNotOnTheNextHeartbeat`（0.4 秒宽限的下界没钉，M32：已有测试杀不死） | e1（转录标记：登记表 idle 起 2.9 秒在、3.1 秒消）、e2（hook 推断：**不能先报做完了** → L-001）、e3（无 hook → 做完了）、e4（宽限期内 Stop 到 → 做完了）、e5（9 种证据到达顺序） | ✓（L-001 已修） |
| (f) 做完一轮：5 秒；桌面会话最多等 4 秒看 postTurnSummary，blocked 叠加「需要你处理」保持到下一轮；未读的三个清除条件 | 5.4 idle 2 / 叠加标记 | `ActivityResolverTests.finishedLasts5SecondsThenIdle`（4.9 / 5.1 秒，M15 / M16 杀）；`EngineScenarioTests.aNormalTurnProducesTheExpectedActivitiesAndEvents`、`startingTheNextTurnClearsUnread`；`EnginePresenceTests.focusingTheSessionInTheDesktopAppClearsUnread`、`blockedComesFromTheDesktopSummaryAndLastsUntilTheNextTurn`、`aSummaryForAnOlderAssistantMessageIsNotBlocked`、`aBlockedSummaryAlreadyThereAtLaunchShowsBlocked`；`StoreTests.markSeenAndRerollAreSafeFromAnyThread`（「严格晚于」M36：已有测试杀不死） | f1（引擎层 4.9 / 5.1 秒 + 未读保留）、f2（三个清除条件，lastFocusedAt 早于 / 等于 / 晚 1 毫秒于本轮结束）、f3（completed 不亮 blocked、blocked 7 秒后才落盘也亮、只发一次、保持到下一轮） | ✓；「最多等 4 秒」：数据层没有等待逻辑，App 层 `AlertCoordinator.summaryWait` = 8 秒（DESIGN.md「与任务书不一致」表已记录：本轮总结实测约 7 秒后才落盘）——**已记录的偏离**；`AlertCoordinator` 在 App 目标里，BuddyCoreTests 测不到，别的代理新增了 `Tests/BuddyOfficeTests/AlertCoordinatorTests.swift`（含「被打断的一轮不提醒」），我没有复核它的断言 |
| (g) 空闲 10 分钟打盹、45 分钟睡着（设置里可改） | 5.4 idle 4 | `ActivityResolverTests.idleThenDozingThenSleepingAtTheThresholds`（9:59 / 10:00 / 44:59 / 45:00，但测的是 `SessionSignals` 的默认值，不是引擎的默认值；M24：已有测试杀不死）、`EngineScenarioTests.dozeAndSleepThresholdsAreConfigurable`、`attachingToALongIdleSessionShowsTheRightSleepState` | g1（引擎默认值：599.9 秒 idle、600.1 秒 dozing、2699.9 秒 dozing、2700.1 秒 sleeping）、z2（随机回放里每一步检查空闲时间窗口） | ✓；「设置里可改」的接线：L-002（已被别的代理修） |
| (h) busy 连续 2 小时不判死，只是 quiet 换画法 | 4.1 / 5.4 叠加标记 | `EngineScenarioTests.aSessionBusyForAnHourNeverDies`（62 分钟，每分钟一步；只抽查 < 9 分钟不是 quiet、≥ 11 分钟是 quiet，10 分钟边界没钉，M25 / M26：已有测试杀不死）、`aWaitingSessionStaysWaitingNoMatterHowLong`、`ActivityResolverTests.aSessionBusyForAnHourIsStillBusy` | h1（虚拟时钟**一次推进 2 小时** + 60 次反复心跳：在场、busy、还是那个工具、quiet、没有任何事件）、h2（quiet 恰好 10 分钟；hook 有新事件 / 会话记录长了一行都立刻清掉） | ✓ |
| (i) 进程被回收：登记文件消失 → 防抖 3 秒 → 离场；桌面 + 元数据在 + 没归档 → 下班工位；其他 8 秒后收回；同一身份带新进程回来坐回原工位；PID 复用（相差 > 2 秒）判死；EPERM 当活着；sysctl 失败当「未知」= 活着 | 4.1 / 5.5 | `EnginePresenceTests.departureIsDebouncedBy3SecondsAndComingBackCancelsIt`、`aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat`、`aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves`、`aFreedSeatIsReusedByTheNextNewcomer`、`aSeatHeldByADormantBuddyIsNotGivenToNewcomers`、`pidReuseIsTreatedAsTheOldProcessBeingGone`、`unknownProbeStateMeansAlive`、`aDeadPidWithALeftoverRegistryFileIsGone`、`dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted`、`departedSessionsCompeteForTheFourDormantSeats`、`dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions`；`ProcessProbeTests.classification`（1.9 / 2.5 / −3 秒；M54 / M55 杀）、`systemProbeSeesThisProcess`（pid 1 = EPERM）。防抖 3 秒只钉了上界（M27：已有测试杀不死）、8 秒只钉了上界（M29：已有测试杀不死） | i1（防抖 2.95 / 3.05 秒 + 事件只发一次 + 8 秒收回 7.9 / 8.1 秒）、i2（下班工位 vs 归档）、i3（8 秒内带新进程回来）、i4（容差恰好 2.0 / 2.001 秒）、i5（kill 成功但 sysctl 读不到）、i6（PID 复用同样先防抖）；**真进程**：r1（sysctl 启动时间就是启动的时候）、r2（pid 1：EPERM 当活着）、r3（真的子进程被回收：2.9 / 3.1 秒）、r4（PID 复用：procStart 差 10 秒） | ✓ |
| (j) /clear（同进程）和 --resume（新进程同 sessionId）之后还认得是同一个人；key = `d:`+host / `t:`+第一次见到的 sessionId；工位号和外观盐不变 | 4.5 | `IdentityTests`（`desktopKeyIsDPrefixPlusHostSessionId`、`terminalKeyIsTPrefixPlusFirstSeenSessionId`、`hostAliasWinsEvenWhenPidAndSessionIdChange`、`desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing`、`terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess`、`terminalResumeInANewProcessKeepsTheSameBuddyViaSessionAlias`、`persistenceRoundTripKeepsAliasesSeatAndSalt` 等）；`EnginePresenceTests.terminalClearKeepsTheBuddyButSwitchesToTheNewSessionFiles`、`terminalResumeInANewProcessGivesTheSameBuddyBack`、`identitiesAndAppearanceSurviveARestart` | j1（桌面 /clear：key / 工位 / 盐不变、旧工具不带过来、token = 新旧两份之和）、j2（终端 key 穿过 /clear + 进程退出 + resume 新 sessionId 仍是 `t:` + 第一次见到的）、j3（桌面 resume 登记表没有 host：靠元数据 cliSessionId / prior 认出） | ✓ |
| (k) 子代理归属：前台 Agent / Task 开着且事件晚 ≥ 0.15 秒 → 小助手；主会话 idle → 后台小助手；有后台小助手活跃先扣 400 ms；SubagentStop 只当提示 | 5.3 | `HelperAttributorTests`（`rule1MainIdleMeansBackgroundHelper`、`rule2ForegroundAgentOpenAndEventLaterThan150ms`、`rule3…` 四个、`eachToolUseIsClaimedOnlyOnce` 等，0.15 的上界和 0.4 的两侧钉住：M49 / M51 / M52 杀）、`HelperAttributionEngineTests` 八个；`0.1` 的下界没钉（M50：已有测试杀不死） | k1（`Task` 也算前台委派；0.149 秒的同批并行调用归主线程、恰好 0.15 秒归小助手）、k2（SubagentStop 让下一次 poll 马上重读桌面元数据；不改变工具 / 阶段）、k3（扣住 0.39 / 0.41 秒）、z1（规则 1、2 在随机事件流里对拍） | ✓ |
| (l) 等待类判定：permission prompt / sandbox request → 等批准（工具取最新打开的主线程调用，没有则从 Notification 解析 `use <T>`）；input needed / dialog open → 提问；ExitPlanMode 开着 → 计划待审；其他 → 其他等待 | 5.4 waiting | `ActivityResolverTests` 十个（`permissionPromptIsApprovalWithTheNewestOpenTool`、`sandboxRequestIsApproval`、`inputNeededAndDialogOpenAreQuestions`、`exitPlanModeWhileWaitingIsPlanReview`、`askUserQuestionNotificationSaysPermissionButItIsAQuestion`、`nonPermissionWaitsFromTerminalSessions`、`unknownWaitingTextIsClassifiedByKeywords`、`approvalToolComesFromTheNotificationWhenNothingIsOpen`、`notificationNamesTheToolAmongParallelOnes`、`missingWaitingForFallsBackToNotificationText`）；`EngineScenarioTests.waitingVariantsThroughTheEngine`、`attentionKindChangesWhileStillWaitingEmitAFreshEvent`、`waitingAtStartupIsReportedImmediately` | l1（引擎层：Notification 解析 `use Bash`、最新打开的调用、sandbox request）、l2（提问 / 计划待审 / AskUserQuestion 的 detail 永远为空）、l3（其他等待附原始文本 + 批准后 `needsUserCleared`）、z1 | ✓ |
| (m) phase 的两个临时修正：登记表 idle 但有更新的 UserPromptSubmit → 暂时 busy（最多 3 秒）；登记表 busy 但有更新的 Stop → 暂时 idle | 5.1 | `ActivityResolverTests.registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds`（103.4 / 103.6 秒，M11 / M12 杀）、`registryBusyButNewerStopIsTemporarilyIdle`、`waitingIsNeverOverriddenByHooks`、`missingRegistryStatusFallsBackToHooks`；`EngineScenarioTests.promptEventThatArrivesBeforeTheRegistryFlipsCountsAsBusyOnce`、`aPromptThatNeverBecomesBusyExpiresAfter3Seconds` | m1（引擎层 2.9 / 3.1 秒、只开始一轮）、m2（Stop 后又来提示 → 又是 busy）、z1（每一步阶段和独立参考模型一致） | ✓ |
| (n) 登记表读取规则：半截 JSON 保留上一份好记录并每 50 ms 重试至多 5 次；kind 不是 interactive 的不画；只打开 `^\d+\.json$` | 4.1 | `RegistryScannerTests.halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms`（M58 / M59 杀）、`emptyFileDuringTruncateIsTreatedAsHalfWritten`、`onlyInteractiveSessionsAreShown`（M60）、`fileNamePattern`、`missingFieldsAreOptionalButPidAndSessionIdAreRequired`；`FileAccessTests.keyFilesAreNeverOpened`、`safetyNetRefusesKeyAndSocketPaths`；`EnginePresenceTests.nonInteractiveSessionsNeverBecomeGhostColleagues`；`RobustnessTests.aRegistryFileThatIsADirectoryOrHasWeirdTypesIsIgnored` | n1（引擎层：半截文件后 12 次心跳仍在场、`nextWake` ≤ 50 ms、写完整后立刻更新）、n2（`RegistryScanner` 只 `read` 匹配名的文件、`.key` / `.bak` / 非数字名 / 多段名连 stat 都不做） | ✓；「最多 5 次」的口径：L-004 |
| (o) 清单外：整理上下文（PreCompact / PostCompact / compact_boundary） | 5.4 busy 1 | `EngineScenarioTests.compactionThroughHooks`、`ActivityResolverTests.compactingWhenPreCompactHasNoPostCompact`、`compactingExpiresIfPostCompactNeverArrives`、`compactingFromTranscriptBoundary` | o1、o2（真实时序） | ✓（L-003 已修） |
| 任务 3：dump 与 App 同一条数据链路 | — | — | chain1（结构）、chain2（真的 dump 可执行文件 == App 构造方式的 SessionStore）、chain3（SessionStore == 直接用 SessionEngine）、py1 / py2（两个 Python 脚本在 FakeTree 上） | ✓ |

---

## 3. 变异测试（证明测试真的把数字钉住了）

`QA/tools/mutation_check.py` 对 `Sources/BuddyCore` 的**副本**做 60 个小变异（只改副本，不改仓库；每个变异前都和仓库重新同步），每个变异编译一次，跑「我的测试」和「已有测试」两组。结果：**55 个被我的测试杀死；4 个（M33 M34 M59 M60）只被已有测试杀死；1 个存活（M47，等价变异，见 N-2）**。另外手工补了两个：`M61`（`SessionEnd` 不再是轮次边界）被 `b9` 杀死；`M62`（出错的重试上限判据 `>=` → `>`）被 `d1`、`d6` 杀死。

「已有测试」一列为空（—）的，就是**已有测试没有钉住这个数字 / 分支**，只有我的测试杀得到：M03 M06 M08（30 分钟兜底的精确边界、Post 只按名字时关最早的）、M24（引擎的 45 分钟睡着）、M25 M26（quiet 的 10 分钟）、M27（离场防抖的下界）、M29（8 秒收回的下界）、M32（0.4 秒宽限的下界）、M36（未读「严格晚于」）、M40（出错的重试上限判据）、M41–M45（五种轮次边界在引擎层的效果）、M46（`Task` 也算前台委派）、M50（0.15 秒的下界）。

| # | 变异 | 我的测试杀死 | 已有测试杀死 | 结果 |
|---|---|---|---|---|
| M01 | 批次间隔 0.25→0.3 | a2、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch | 杀死 |
| M02 | 批次间隔 0.25→0.2 | a2、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch | 杀死 |
| M03 | 悬空兜底 30→29 分钟 | b7 | — | 杀死 |
| M04 | 悬空兜底 30→31 分钟 | b7、b8 | helperOwnedRecordsExpireRegardless、staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle | 杀死 |
| M05 | Post 配对不是先进先出（名字+detail） | a1、z1 | identicalParallelCallsCloseFirstInFirstOut | 杀死 |
| M06 | Post 只按名字时不是最早的 | a3、z1 | — | 杀死 |
| M07 | 新一批不关旧批次悬空的调用 | a2、b6、k1、z1 | callsWithin250msOfThePreviousPreStayInTheSameBatch、newBatchClosesOlderOpenCallsAsSuperseded、permissionDeniedDanglingIsClosedByTheNextBatch | 杀死 |
| M08 | 兜底：>= 而不是 >（恰好 30 分钟就关） | b7 | — | 杀死 |
| M09 | 兜底：登记表 idle 或小助手 → 登记表 idle 且小助手 | b7、z1 | helperOwnedRecordsExpireRegardless、staleCallsAreForceClosedOnlyWhenTheRegistryIsIdle | 杀死 |
| M10 | 轮次边界不关任何调用 | b1、b2、b3、b4 等6个 | turnBoundariesCloseAllMainCalls | 杀死 |
| M11 | 临时 busy 窗口 3→4 | m1 | aPromptThatNeverBecomesBusyExpiresAfter3Seconds、registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds | 杀死 |
| M12 | 临时 busy 窗口 3→2 | m1 | registryIdleButNewerPromptIsTemporarilyBusyForAtMost3Seconds | 杀死 |
| M13 | 被打断持续 3→4 | e1、e2、z2 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted、interruptedLasts3SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M14 | 被打断持续 3→2 | e1、e2、e5 | interruptedLasts3SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M15 | 做完了持续 5→6 | f1、z2 | aNormalTurnProducesTheExpectedActivitiesAndEvents、attachingToAnIdleSessionThatJustFinishedShowsFinishedForTheRemainingTime、finishedLasts5SecondsThenIdle 等4个 | 杀死 |
| M16 | 做完了持续 5→4 | f1 | finishedLasts5SecondsThenIdle、nextChangeTellsWhenTimeWillChangeTheResult | 杀死 |
| M17 | 重试余量 15→16 秒 | c1 | nextChangeTellsWhenTimeWillChangeTheResult、retryingThenBackToThinkingWhenTheRetryWindowPasses、retryingWithinRetryInMsPlus15Seconds | 杀死 |
| M18 | 重试余量 15→14 秒 | c1 | nextChangeTellsWhenTimeWillChangeTheResult、retryingThenBackToThinkingWhenTheRetryWindowPasses、retryingWithinRetryInMsPlus15Seconds | 杀死 |
| M19 | sandbox request 不算等批准 | l1、z1 | sandboxRequestIsApproval、waitingVariantsThroughTheEngine | 杀死 |
| M20 | dialog open 不算提问 | l2、z1 | exitPlanModeWhileWaitingIsPlanReview、inputNeededAndDialogOpenAreQuestions、waitingVariantsThroughTheEngine | 杀死 |
| M21 | 等批准时 ExitPlanMode 不是计划待审 | l2、z1 | exitPlanModeWhileWaitingIsPlanReview | 杀死 |
| M22 | 等批准时 AskUserQuestion 不是提问 | l2、z1 | askUserQuestionNotificationSaysPermissionButItIsAQuestion | 杀死 |
| M23 | 打盹 10→9 分钟 | g1 | erroredTurnStaysErroredUntilItStartsDozing | 杀死 |
| M24 | 睡着 45→44 分钟 | g1 | — | 杀死 |
| M25 | quiet 10→9 分钟 | h2 | — | 杀死 |
| M26 | quiet 10→11 分钟 | h2 | — | 杀死 |
| M27 | 离场防抖 3→2 秒 | i1、i6、r3、r4 | — | 杀死 |
| M28 | 离场防抖 3→4 秒 | i1、i2、i3、i6 等7个 | aDesktopSessionWithMetadataGoesToADormantSeatAndComesBackToTheSameSeat、aFreedSeatIsReusedByTheNextNewcomer、aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves 等5个 | 杀死 |
| M29 | 收回工位 8→7 秒 | i1 | — | 杀死 |
| M30 | 收回工位 8→9 秒 | i1、j2 | aFreedSeatIsReusedByTheNextNewcomer、aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves、terminalResumeInANewProcessGivesTheSameBuddyBack | 杀死 |
| M31 | Stop 宽限 0.4→0.6 | e2、e3 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted | 杀死 |
| M32 | Stop 宽限 0.4→0.2 | e5 | — | 杀死 |
| M33 | 下班工位上限 4→5 | — | departedSessionsCompeteForTheFourDormantSeats、dormantSeatsAtLaunchComeFromRecentlyActiveDesktopSessions | 只被已有测试杀死 |
| M34 | 下班工位 12→11 小时 | — | dormantSeatsExpireAfter12HoursOrWhenArchivedOrDeleted | 只被已有测试杀死 |
| M35 | 下班工位不看归档 | i2 | aSessionWithoutMetadataOrWithAnArchivedOneJustLeaves | 杀死 |
| M36 | 未读：lastFocusedAt >= 也清 | f2 | — | 杀死 |
| M37 | 未读：lastFocusedAt 不清未读 | f2 | focusingTheSessionInTheDesktopAppClearsUnread | 杀死 |
| M38 | 被打断也亮未读 | e1、e2 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted | 杀死 |
| M39 | 没有 Stop：hook 正常 → 做完了，没有 hook → 被打断（反了） | e2、e3、e5 | aTurnWithoutAStopEventWhileHooksWorkIsInferredAsInterrupted、timeDrivenChangesHappenOnTimeNotOnTheNextHeartbeat | 杀死 |
| M40 | 出错：重试到上限 → 超过上限 | d1 | — | 杀死 |
| M41 | 轮次边界：Stop 不关调用 | z1 | — | 杀死 |
| M42 | 轮次边界：UserPromptSubmit 不关调用 | b2、z1 | — | 杀死 |
| M43 | 轮次边界：SessionStart 不关调用 | b3、z1 | — | 杀死 |
| M44 | 轮次边界：登记表变 idle 不关调用 | b4、z1 | — | 杀死 |
| M45 | 轮次边界：stop_hook_summary 不关调用 | b5 | — | 杀死 |
| M46 | 前台只认 Agent 不认 Task | k1、z1 | — | 杀死 |
| M47 | 兜底用的登记表 idle 恒为 false | — | — | 存活（等价变异） |
| M48 | (回退我的修复) 宽限期内先报做完了 | e2、e5 | — | 杀死 |
| M49 | 前台 Agent 间隔 0.15→0.2 | k1、z1 | rule2ForegroundAgentOpenAndEventLaterThan150ms | 杀死 |
| M50 | 前台 Agent 间隔 0.15→0.1 | k1、z1 | — | 杀死 |
| M51 | 扣住 0.4→0.5 秒 | k3 | eachToolUseIsClaimedOnlyOnce、rule3HoldEndsEarlyWhenTheTranscriptCatchesUp、rule3NoMatchHoldsFor400msThenGoesToMain 等4个 | 杀死 |
| M52 | 扣住 0.4→0.3 秒 | k3 | eachToolUseIsClaimedOnlyOnce、rule3HoldEndsEarlyWhenTheTranscriptCatchesUp、rule3NoMatchHoldsFor400msThenGoesToMain | 杀死 |
| M53 | 主会话 idle 不归小助手 | b8、z1 | idleMainSessionsBackgroundHelperEventsGoToTheHelper、rule1MainIdleMeansBackgroundHelper | 杀死 |
| M54 | PID 复用容差 2→3 秒 | i4、i6、r1 | classification | 杀死 |
| M55 | PID 复用容差 2→1 秒 | i4、r1 | classification、pidReuseIsTreatedAsTheOldProcessBeingGone | 杀死 |
| M56 | EPERM 当作死了 | r2 | systemProbeSeesThisProcess | 杀死 |
| M57 | sysctl 失败(unknown)当作死了 | i4 | classification、unknownProbeStateMeansAlive | 杀死 |
| M58 | 登记表重试间隔 50→100 ms | n1 | halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms | 杀死 |
| M59 | 登记表重试上限 5→6 | — | halfWrittenFileKeepsTheLastGoodRecordAndRetriesEvery50ms | 只被已有测试杀死 |
| M60 | 登记表：非 interactive 也显示 | — | nonInteractiveSessionsNeverBecomeGhostColleagues、onlyInteractiveSessionsAreShown | 只被已有测试杀死 |
| M61 | 轮次边界：SessionEnd 不关调用（手工） | b9 | — | 杀死 |
| M62 | 出错：重试到上限 → 超过上限（手工，验证 d6） | d1、d6 | — | 杀死 |

---

## 4. 任务 2：token 交叉核对（`QA/tools/token_crosscheck.py`）

**规则**（只按用量表 `tokens.1m.py` 的语义自己重写，没有移植 Swift 代码）：只统计带 `"usage"` 的 assistant 行（用量表判据 `message.role`，任务书判据 `type`，两个都实现并报出不一致的行数）；要有 `message.id`、合法 timestamp、model 不是 `<synthetic>`、usage 非空；缓存写 = 5m + 1h，细分对不上总数就全当 5m；按 `message.id` 去重、每个字段取最大值；总量 = input + output + 缓存写 + 缓存读；桌面会话把 `cliSessionId` 与 `priorCliSessionIds` 对应的会话记录相加，子代理文件（含 `workflows/wf_*/`）也算。
**四个口径**：① 独立实现；② 直接 import 用量表原版的 `parse_line` + 它的合并规则（只读，不写缓存、不写 `.pyc`）；③ App 的 `ledger.json`——按 ledger 里记录的每个文件的 `offset` 只读到那个位置（文件在增长）；④ `buddyctl dump --once --json` 的 `tokens`，外加默认表格里的 `token(ctx)` 列（缩写，检查 `fmtTok` 排版）。文件在增长时用 `--snapshot DIR`：先把每个文件当前大小以内的 token 事实**去掉全部对话内容**（只留 `type / timestamp / sessionId / message.{id,role,model,usage}`；登记表和桌面元数据也只留认人和算 token 需要的字段，不带标题 / cwd / 本轮总结）冻结成一棵假 home，两边都读这份冻结的数据（我这一侧读的是**原文件**冻结时的大小，不是快照文件，所以也验证了快照的裁剪）。
**能对真实数据跑，也能对 FakeTree 假数据跑**（`--root`）；`--extra-host local_<uuid>` 可以把一个桌面会话（带 prior）当作活会话一起核对（登记表是合成的、只写在快照里，绝不写真实的 `~/.claude`）。

### 4.1 真实数据（2026-09-29 04:28，冻结快照；输入 / 输出 / 缓存写 / 缓存读 = 合计，消息数）

| 会话（pid / sid 前 8 位） | 文件 | 独立实现 | 用量表 `parse_line` | ledger.json（读到 offset） | dump `tokens` | dump 表格列 | 一致？ |
|---|---|---|---|---|---|---|---|
| 25245 / 8aab9e77 | 1 | 94/218197/293045/9487490 = **9,998,826**（47 条） | 同 | 同（47 条） | 同（47 条） | 10.0M | 是 |
| 35991 / 20c4bcc8（本会话，忙着，1 个主文件 + 10 个子代理文件） | 11 | 6140/6289195/14493696/1550678757 = **1,571,467,788**（3069 条） | 同（3069） | ledger 读到 offset：6132/6286643/14485753/1547568224 = 1,568,346,752（3065 条）——**独立实现在同一 offset 处也是这个数**（逐位一致） | 同独立实现（3069） | 1.57B | 是 |
| 65995 / d95629cf | 5（4 个子代理） | 446/369189/1396978/31362169 = **33,128,782**（204 条） | 同 | 同 | 同 | 33.1M | 是 |
| 80510 / cdc48c29 | 1 | 206/138872/875085/22591481 = **23,605,644**（102 条） | 同 | 同 | 同 | 23.6M | 是 |
| 桌面会话 local_3b2f8a28…（**带 prior**，`--extra-host`；不是活会话，登记表合成；取自另一次运行，文件不再增长） | 2 | 26/26291/60673/1105167 = **1,192,157**（13 条） | 同 | 无（有 prior 的组每次重扫，不写断点） | 同 | — | 是（README 里那个「两个文件合计，重叠那条只算一次」的数） |

结论：**每个会话四项分别、消息条数、合计都逐位一致**；忙着的那个会话在冻结的同一时刻两边读到同一个数；ledger 用「读到 offset 为止」的办法对上了。收工前（05:04）又用 `--run-dump --snapshot` 复核了一次，结论同样是「全部一致」（本会话那一行随着对话在涨：3327 条 / 1,737,257,991，ledger 读到 offset 处 3325 条 / 1,736,342,427，独立实现在同一 offset 处也是这个数；另外三个会话的数字和上表相同）。真实数据里跨会话共享的 `message.id` 为 0（全局去重把重复消息记给先扫到的那个会话，这里没有触发）；`role` 与 `type` 判据不一致的行数为 0。
**没有发现任何不一致，所以没有需要修的 token 相关代码，也没有相关回归测试要补**；这个交叉核对本身的回归测试是 `StateRuleChainTests › py1_tokenCrosscheckScriptOnAFakeTree`。

### 4.2 FakeTree 假数据（`py1`）
3 个会话（A 桌面：prior + 当前 + 子代理 + 重复消息 + 合成消息 + 多次写入取最大值；B 终端；C 下班工位），手算期望值 A = 5503、B = 26。独立实现 == 用量表 `parse_line` == 真的 dump 可执行文件 == 手算期望值；假 home 里还放了 `kind=job`、进程已死、`.key`（权限 000）、名字不对（`abc.json`、`.json.bak`）的登记文件，都不该被统计（`--liveness check`）。脚本输出里没有 `桌面标题A` / `终端自定义B` / `sleep 30` 之类的内容。

### 4.3 脚本自己的自检
`python3 QA/tools/token_crosscheck.py --selftest`：合成一棵树，手算期望值验证规则（多次写入取最大值、5m / 1h 细分、合成消息、没有 timestamp、usage 为空、非 assistant、没有换行的半行、`journal.jsonl` 不算、prior 相加、`kind=job` 不统计、跨会话共享的消息 id 报出来、冻结快照里没有任何 `SECRET-*`）。

---

## 5. 任务 3：dump 与登记表的一致性（`QA/tools/dump_vs_registry.py`）

逐个会话核对：pid、sessionId、hostSessionId、来源、key 前缀、liveness、`registryStatus`（== 登记表 status）、`waitingFor`、`phase`（== 登记表 status + 两个临时修正，独立用 hook 里的 Stop / UserPromptSubmit 的 ts 推算，只读 ts 和 ev）、标题（登记表 name → 桌面 title → custom-title → ai-title → cwd 文件夹名 → 「会话 <sid 前 8 位>」，只输出来自哪一级和一致 / 不一致）；集合：dump 的 present 会话 == 登记表里 `kind` 缺省或 interactive 且进程活着的会话（不多出、不漏掉、非 interactive 绝不出现）。跑 dump 前后各读一次登记表，中途变过的会话标记「不稳定」而不是「不一致」。

**真实数据（2026-09-29 04:28）**：dump 共 4 行（present 4，下班 / 离场 0）；多出 []，漏掉 []；4 个会话（pid 25245 / 35991 / 65995 / 80510，都是桌面会话，标题都来自登记表 `name`）的 10 项检查全部通过（`pid sessionId hostSessionId origin key liveness registryStatus waitingFor phase title`）；阶段推算 / dump：idle/idle、busy/busy、idle/idle、idle/idle。**全部一致**（收工前 05:04 又跑了一次，结果相同）。
**假数据（`py2`）**：桌面标题来自「桌面 title」、终端标题来自「custom-title」（会话记录里 key 顺序是乱的，第一版脚本的「只看行首 40 字节」预过滤漏掉了它，已改成整行判断——这是我自己脚本的 bug，测试抓到的）。`--selftest` 还覆盖：标题链每一级、阶段推算的两个临时修正、多出的 pid、漏掉的 pid、`kind=job` 出现在 dump 里。

### 5.1 「buddyctl dump 与 App 用的是同一条数据链路」的证明（`StateRuleChainTests`）
- **chain1 结构**：`DumpCommand.swift` 里只造 `SessionStore(options:)`（`SessionEngine.Options(paths:)` → `SessionStore.Options(engine:)` → `store.debugRows()`），源码里没有 `RegistryScanner` / `TokenLedger(` / `HookLogReader` / `TranscriptReader` / `DesktopMetaReader` / `IdentityResolver` / `ToolTracker` / `ActivityResolver`——它自己不读任何数据源、不判定任何状态；App 的 `RealProvider.make` 也是 `SessionEngine.Options(paths:)` → `EngineConfig.apply`（只覆盖设置里的四项）→ `SessionStore.Options(engine:)` → `SessionStore(options:)`；`buddyctl` / `buddydump` 的 `main.swift` 只转发 `runDumpCommand`。
- **chain2 行为**：同一棵假 home 树（会话用真 pid：测试进程和它的父进程，这样 dump 可执行文件里真的 `SystemProcessProbe` 也认为它们活着），真的 `buddyctl`（根包）/ `buddydump`（隔离包）`dump --once --poll --json --data-root <树>` 的输出，和 App 构造方式的 `SessionStore` 用 `DumpFormatter.renderJSON` 序列化的结果**逐字段相同**（`NSDictionary` 相等，A / B / C 三个会话），并且语义上也对：token 手算期望值、标题链、阶段、下班工位。
- **chain3**：App 构造方式的 `SessionStore.pollNow()` 快照和直接 `SessionEngine.poll()` 的快照在 seat / title / phase / activity / presence / tokens / pid / 叠加标记 / 各时间戳上逐字段相等。

---

## 6. 新增测试清单（完整函数名）

- `StateRuleTests`（52）：`a1_sameMillisecondParallelReadsPairFirstInFirstOut`、`a2_batchGapIsExactly250ms`、`a3_postFallsBackToTheEarliestOpenCallOfTheSameName`、`b1_stopEventClosesDanglingMainCalls`、`b2_userPromptSubmitClosesDanglingMainCalls`、`b3_sessionStartClosesDanglingMainCalls`、`b9_sessionEndClosesDanglingMainCalls`、`b4_registryTurningIdleClosesDanglingMainCalls`、`b5_stopHookSummaryInTheTranscriptClosesOnlyCallsStartedBeforeIt`、`b6_danglingCallIsSupersededByTheNextBatch`、`b7_staleCallIsForceClosedOnlyAfterMoreThan30MinutesWhileRegistryIdle`、`b8_helperOwnedRecordsExpireAfter30Minutes`、`c1_retryShowsAttemptAndExpiresAtRetryInMsPlus15Seconds`、`c2_aNewUserLineEndsTheRetryDisplay`、`d1_erroredByExhaustedRetriesAlone`、`d2_erroredBySyntheticApiErrorMessageAlone`、`d3_notErroredWhenRetriesRecovered`、`d4_notErroredWhenAnAssistantLineFollowsTheLastRetry`、`d5_noResponseRequestedAfterAnInterruptIsNotAnError`、`d6_erroredWinsOverFinishedWhenBothEvidencesExist`、`e1_transcriptInterruptLastsThreeSeconds`、`e2_hookInferredInterruptNeverShowsFinished`、`e3_withoutHooksTheEndOfATurnIsFinishedNotInterrupted`、`e4_aStopWithinTheGraceKeepsFinished`、`e5_evidenceArrivalOrderNeverChangesTheVerdictOrShowsAWrongOneFirst`、`f1_finishedLastsFiveSeconds`、`f2_unreadClearsInExactlyThreeWays`、`f3_blockedOverlayFollowsTheDesktopSummary`、`g1_dozeAt10MinutesSleepAt45Minutes`、`h1_twoHoursOfBusyIsQuietNotDead`、`h2_quietThresholdAndItsResets`、`i1_departureDebounceThenReclaimAfter8Seconds`、`i2_dormantSeatOnlyForDesktopSessionsWithLiveUnarchivedMetadata`、`i3_theSameIdentityComingBackDuringTheLingerSitsInTheSameSeat`、`i4_pidReuseToleranceIsExactlyTwoSeconds`、`i5_aliveWithoutAStartTimeStaysPresent`、`i6_pidReuseGoesThroughTheSameDebounce`、`j1_desktopClearInTheSameProcessKeepsTheBuddy`、`j2_terminalKeyStaysTheFirstSeenSessionIdAcrossClearAndResume`、`j3_desktopResumeIsRecognizedThroughTheMetadataCliSessionIds`、`k1_foregroundTaskAttributionBoundaryAt150ms`、`k2_subagentStopIsOnlyASummaryHint`、`k3_unmatchedEventIsHeldForExactly400ms`、`l1_approvalToolIsParsedFromTheNotificationWhenNothingIsOpen`、`l2_questionsAndPlanReview`、`l3_otherWaitsCarryTheRawText`、`m1_promptBeforeTheRegistryFlipsIsTemporarilyBusyForAtMost3Seconds`、`m2_stopBeforeTheRegistryFlipsIsTemporarilyIdle`、`n1_aHalfWrittenRegistryKeepsTheLastGoodRecordThroughTheEngine`、`n2_onlyPidJsonFilesAreOpened`、`o1_compactionEndsWhenTheHooksSayItEnded`、`o2_boundaryHookSlackIsFiveSeconds`。
- `StateRuleProcessTests`（4，真进程 / 真的 `SystemProcessProbe`，虚拟时钟）：`r1_realStartTimeAndLiveness`、`r2_epermCountsAsAlive`、`r3_recycledProcessIsDebouncedBy3Seconds`、`r4_pidReuseWithARealProcess`。
- `StateRuleChainTests`（5）：`chain1_sourcesShowTheSameSessionStoreChain`、`chain2_dumpExecutableMatchesTheAppChain`、`chain3_storeAndRawEngineAgree`、`py1_tokenCrosscheckScriptOnAFakeTree`、`py2_dumpVsRegistryScriptOnAFakeTree`。
- `StateRuleInvariantTests`（2 × 16 个种子）：`z1_referenceModelAgreesWithTheEngine`（独立参考模型：只按 5.1 阶段 / 5.2 工具追踪 / 5.3 前台归属 / 5.4 等待类写，和引擎在 500 步随机事件流——登记表翻转、Stop / 提示 / SessionStart、同一毫秒的 Pre 小批、Post、0.25 秒边界附近的间隔、几十秒、10–70 分钟的大跳——上逐步对拍阶段、主线程打开的调用个数和顺序、忙碌 / 等待时的动作；杀死了 M01 M02 M05 M06 M07 M09 M10 M19–M22 M41–M44 M46 M49 M50 M53 共 19 个变异）、`z2_snapshotInvariantsHoldUnderRandomReplay`（更脏的 400 步：会话记录里的打断 / 错误 / 重试 / 压缩、小助手写文件、桌面元数据、Notification、markSeen……；杀死 M13、M15；每一步检查：phase == activity.phase、idle 时没有 turnStartedAt、非 idle 时没有 idleSince / 未读 / blocked、quiet 只在 busy、并行个数 == 打开的主线程调用、提醒事件和动作对得上、一轮开始 / 结束事件配对、**空闲时间窗口**：打断 ≤ 3 秒、做完了 ≤ 5 秒、空闲 < 10 分钟、打盹 10–45 分钟、睡着 ≥ 45 分钟）。
- 支撑：`StateRuleKit`（`StateRuleTests.swift` 里；idleSession / startTurn / goto 等）；`BUDDY_REPO_ROOT` 环境变量可以指定项目根目录（私有沙箱里跑 chain 测试用）。

---

## 7. 已记录的偏离（实现和任务书不同，但 DESIGN.md / Core README 里有理由，不算 bug）

| 偏离 | 记录在哪 | 我的验证 |
|---|---|---|
| 「做完了」桌面会话等本轮总结：任务书最多 4 秒，实现 8 秒（App 层 `AlertCoordinator.summaryWait`；数据层没有等待逻辑，blocked 在元数据一更新就给出） | DESIGN.md「与任务书不一致」表；Core README | f3（blocked 7 秒后才落盘也亮、保持到下一轮） |
| 「出错」优先于「做完了」，并且一直保持到打盹（10 分钟）；任务书的顺序会让出错的一轮先闪 5 秒「做完了」 | Core README「我做的小决定」 | d1、d6、既有 `erroredTurnStaysErroredUntilItStartsDozing` |
| 被打断的 hook 推断先等 0.4 秒（`stopGrace`）没有 Stop 才判定 | Core README「我做的小决定」 | e2–e5（L-001 补上了宽限期内不能报错误结论） |
| 「登记表还是 busy 但 Stop 已到」才是常态（Stop 比登记表翻 idle 早 40–60 ms） | Core README「数据源实测结论」 | m2、e5（Stop 在登记表之前 60 ms 到） |
| `ExitPlanMode` / `AskUserQuestion` 的 Notification 文本也叫 "needs your permission to use X"，所以看打开的工具名：`ExitPlanMode` 开着 → 计划待审（不只在「提问」类等待下），`AskUserQuestion` 开着 → 提问 | Core README「数据源实测结论」 | l2 |
| 等批准的工具：Notification 点了名就取名字对得上的那个打开的调用（并行时不会张冠李戴），否则最新打开的，再否则解析 `use <T>` | Core README「我做的小决定」 | l1、既有 `notificationNamesTheToolAmongParallelOnes` |
| 缺 `kind` 的登记记录当 interactive；`pid` / `sessionId` 缺失的忽略；不认识的 `status` → nil | Core README「我做的小决定」 | 既有 `RegistryScannerTests` |
| 30 分钟兜底：小助手名下的记录一律丢；主线程的只在登记表 idle 时强制关 | Core README「我做的小决定」 | b7、b8（主线程那一半在引擎层不可达，见 N-2） |
| 会话记录 `stop_hook_summary` 只关「在它之前开始」的调用 | Core README「我做的小决定」 | b5 |
| 下班工位：启动时取 `lastActivityAt` 3 小时内、没归档、没有活进程的桌面会话，最多 4 个；满 12 小时 / 归档 / 元数据被删移除 | Core README | 既有 `dormantSeats…` 系列（M33 / M34 被它们杀死） |

---

## 8. 这一轮用真实日志核实的时序事实（不是 bug，但改变了对若干规则的信心）

| 事实（这台机器，2.1.284，4 个活会话的 hook 日志 / 会话记录） | 对哪条规则 |
|---|---|
| **压缩**：3 组 `PreCompact(auto)` → `SessionStart(compact)` 分别晚 103.4 / 87.9 / 91.5 秒；`PostCompact` 比 `SessionStart(compact)` 晚 20–30 毫秒；`compact_boundary`（会话记录）比 `SessionStart(compact)` 晚 40–70 毫秒；边界前 0.4 秒有一行 `isCompactSummary` 的 user 行；压缩开始时会话记录里什么都没有；边界后 2.4 / 3.4 / 3.8 秒才是第一条 assistant 行 | L-003 |
| **打断没有 Stop**：10 个 `[Request interrupted by user` 标记，最近的 Stop 事件都在 60 秒以外 | (e)：「hook 正常但没有 Stop」的推断成立 |
| **`stop_hook_summary` 与 Stop**：和 Stop 事件 1 : 1，比 Stop 晚 4–59 毫秒（各会话的中位数 4–8 毫秒） | (b) 的 `stop_hook_summary` 边界、(e) 的 `stopMarker` |
| **`api_error`**：25 行，`retryAttempt` 1–9 / `maxRetries` 10，`retryInMs` 512–39,720；相邻两次重试的间隔 ≈ 上一条的 `retryInMs`；没有一条到上限的样本 | (c)、(d)：字段与 `retryInMs + 15 秒` 的窗口一致；「出错」只能用合成 fixture 测 |
| **合成 assistant 行的形状**：2 条 `isApiErrorMessage: true`（`<synthetic>`、`stop_sequence`）、2 条 `isAbortedMidStream`（`stop_reason: null`）、1 条 `No response requested.`（`<synthetic>`、不是错误） | (d)、(e) 的解析假设都对 |
| **hook 日志独立回放**（`QA/tools/hooklog_replay.py`，把 4 个会话的日志按 5.2 独立回放一遍，所有 Pre 都当主线程；日志一直在增长，这是 04:4x 的一次）：Pre 4135 = Post 关 3746（名字 + detail 相同 3637、只能按名字配 109）+ 被取代 388 + 轮次边界 0 + 末尾残留 1（正在运行的那个 Bash）；找不到对应的 Post 331；同一毫秒的 Pre 对 5 个（「同一毫秒两个 Read」实测存在）；相邻 Pre 间隔在 240–260 毫秒的 21 个 | (a)(b)：规则自洽。0.25 秒附近确有 21 处间隔，但阈值不会因为浮点误差在边界上「抖」：毫秒时间戳相减时，0.25 秒和 3 秒恰好是 2^-22 秒（1.79e9 附近 double 的间距）的整数倍，25 万次随机基数下差恒等于 0.25 / 3.0；150 毫秒和 400 毫秒不是整数倍，会抖（`HelperAttributor` 已经按毫秒取整处理了 0.15 秒） |
| **Notification**：真实样本只有 AskUserQuestion（5 条）和 ExitPlanMode（5 条）的 "needs your permission to use X"（其余会话没有）；没有「真的权限提示」样本 | (l)：README 已记录，本轮没有新增 |
| **登记表**：4 个都是 `kind` = `interactive`、`entrypoint` = `claude-desktop`，`waitingFor` 都缺省；没有终端会话 | (n)：终端 / VS Code 路径仍只靠 fixture（README 已记录） |

---

## 9. 剩余风险

1. **晚到的证据不会回头改判**：`complete()` 之后 `pendingEnd` 就清了。登记表翻 idle 后 0.4 秒内没有 Stop / 打断行 / 错误行，会按「hook 正常 → 被打断」（或无 hook → 做完了）定下来；如果出错的证据（`api_error` 到上限、合成错误消息）比登记表晚 > 0.4 秒才落盘（主会话记录写盘可能延迟），就会被判成「被打断」而不是「出错」，且不会更正。真实日志里没有到上限的样本，无法量化。
2. **App 层的数字不在我的测试范围**：`AlertCoordinator` 的 1.5 秒、20 秒节流、8 秒等 blocked、30 秒最短用时在 App 目标里，BuddyCoreTests 测不到；别的代理新增了 `Tests/BuddyOfficeTests/AlertCoordinatorTests.swift`，我没有复核它的断言。数据层给它的输入我已经保证：宽限期内不再有假的 `.finished`（L-001）。
3. **终端 / VS Code 会话、真实的权限提示、`sandbox request` / `dialog open` / `goal proposal` / `worker request`、`turn_duration` 没有真实样本**：只靠 fixture。
4. **归属规则（5.3）本质是猜**：hook 里没有 agent_id；我的 z1 对拍验证了规则 1、2 在随机事件流里被正确实现，但规则 3（扣住 + 会话记录比对）只有确定性的场景测试。
5. **我的所有回放都走纯轮询引擎 + 虚拟时钟**：FSEvents 链路由已有的 `StoreTests` / `ReplayTests(--fsevents)` 覆盖，我没有重复。
6. **同一 `message.id` 出现在两个不同会话的文件里**（resume 复制历史）时，全局去重会把它记给先扫到的那个会话，各会话的合计取决于扫描顺序；真实数据里当前为 0 处，没有验证过这条路径的真实数据（`token_crosscheck.py` 会把它报出来）。
7. **测试基础设施**：多个 QA 同时在改同一个仓库，`swift build` 会因为「input file was modified during the build」偶发失败（不是产品问题）。我用私有沙箱（把源码 / 测试 rsync 到 `$TMPDIR`）绕开；官方命令本身在收工前反复因此失败（隔 20–30 秒重试），最后一次冷编译通过（63 / 63）。另外测试进程偶尔会被别人杀掉（现象见第 0 节「稳定性」一行，我用 `SIGTERM` / `SIGKILL` 自己复现过同样的日志截断 + `exit=1`），看到这种「没有汇总行的 `exit=1`」先重跑，不要当成测试失败。
8. 变异测试只覆盖数字和明显的分支（60 + 2 个），不是全部逻辑。

---

## 10. 怎么复现

```bash
# 测试（沙箱外）
cd ~/Desktop/编程项目/Buddy办公室
BUDDY_SCRATCH=.build-qa-logic scripts/dev.sh test --filter StateRule -j 2

# token 交叉核对（真实数据 / 冻结快照 / 假数据 / 自检）
python3 QA/tools/token_crosscheck.py
python3 QA/tools/token_crosscheck.py --run-dump --snapshot "$TMPDIR/tc-snap"      # 目录必须为空
python3 QA/tools/token_crosscheck.py --root <假 home> --liveness check --run-dump --json
python3 QA/tools/token_crosscheck.py --selftest

# dump 与登记表
python3 QA/tools/dump_vs_registry.py            # 需要 .build/release/buddyctl（已编译好的；不重新编）
python3 QA/tools/dump_vs_registry.py --selftest

# 真实 hook 日志的独立回放（只输出计数）
python3 QA/tools/hooklog_replay.py

# 变异测试（沙箱外，别和别的编译同时跑；只改副本）
python3 QA/tools/mutation_check.py --list
python3 QA/tools/mutation_check.py --only M02 M27 --json "$TMPDIR/mut.jsonl"
```

---

## 详细记录：收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的）（来自 issues-review.md）

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

---

