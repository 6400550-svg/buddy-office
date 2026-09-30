# R4a 终审复查（R3 六个 P2 的修复回归 + 相邻代码，全新视角）

2026-09-29 12:59–13:40（墙钟约 40 分钟，中间被一次锁等待白白吃掉约 10 分钟，见「没覆盖到」）。
所有编译 / 测试 / 探针都在拷贝 `…/scratchpad/r4a/`（`BUDDY_SCRATCH=.build-r4a`）里做，探针文件 `Tests/BuddyOfficeTests/R4aProbeTests.swift`、`R4aProbe2Tests.swift`
和 `AlertCoordinator` 里两个只读的调试访问器（`debugMulti` / `debugRecentCount`）**只在拷贝里**；主目录除本报告外没有改动。没有碰 `~/.claude`、`.key`、`.sock`、
运行中的 App；没有起开发副本（所以没有偏好域要清理）。

## 结论

**新发现：P0 0 条 / P1 0 条 / P2 1 条 / P3 4 条。按验收条款 ⑤（最后一轮不许再出新的 P0–P2）这一轮没有过关：1 条 P2（R3a-02 的修复只夹了引擎侧的读取器，应用层还有第二个读取器没夹）。**
R3c-01（合并卡）、R3c-02（通知补卡）、测试基础设施三处修复本身：**没有发现回归**（随机模拟 + 读码，见覆盖清单）。

## P2

### R4a-01 [P2] 桌面元数据的未来时间戳：应用层 `DesktopMeta.readAll()` 没夹，一个远在未来的 `lastFocusedAt` 让「你正在看这个会话」判定永久错位（R3a-02 只修了引擎侧的 `DesktopMetaReader`）

- **位置**：`Sources/BuddyOffice/JumpService.swift:154-169`（`DesktopMeta.lastFocused(path:)` 直接 `j["lastFocusedAt"] as? Double`，`readAll()` / `mostRecentHost` 取最大值）→ `:187`（`Cache.isMostRecentlyFocused`）→ `AppModel.swift:277-283`（`isUserLooking` 的桌面分支）→ `AlertCoordinator.handleWaiting` / `handleFinished` 的 `isLooking`。
  另一处同样没夹的读取：`JumpService.swift:39-45`（`jump(to:)` 里的 `wasLatest` / 2.5 秒后的 `after`）。
  R3a-02 的修法（`DesktopMetaReader.clampingFuture`，`DesktopMetaReader.swift:~85`）只在引擎自己的读取器里夹；应用层是独立的第二份读取 + 解析，走的是原始值。
- **现象**：两个桌面会话 X、Y，X 的元数据里 `lastFocusedAt` 比现在晚 30 天（桌面 App 的时钟被拨快过 / 虚拟机恢复后时钟不对——和 R3a-02 同一个前提），Y 是用户真正在看的：
  - `DesktopMeta.mostRecentHost` 永远是 X（Y 的真实时间戳永远追不上 30 天后）。
  - Claude 在最前面时：**X 的等批准 / 提问 / 做完了永远被当成「你一直在看」而不提醒**（`handleWaiting` 里 `ep.alerted = true; return []`，整段等待都不提醒；提醒丢失，只剩 Dock 角标 / 菜单栏）；
    **Y（用户真正在看的那个）反而被当成没在看**，照样弹提示卡 / 系统通知（无谓打扰）。
- **证据（拷贝里的探针 `R4aProbe2Tests.appLayerDesktopMetaIsNotClamped`，`--filter R4aProbe`，假 `baseOverride` 目录、两个 `local_*.json`，X = 现在 + 30 天，Y = 现在）**：
  ```
  R4M1 mostRecent=Optional("local_x") X-looking=true Y-looking=false          ← 应用层（提醒判定用的那条路）
  R4M2 engine-side lastFocused x=1790713722.626643 y=1790713722.623 now=1790713722.62395   ← 引擎侧：x 已被夹成读文件时的「现在」，两者并列
  ```
  同一份数据，引擎侧认为 X 的聚焦时间 ≈ 现在，应用层认为 X 比 Y 晚 30 天。
- **为什么算 P2**：和 R3a-02（当时定 P2）同一类、同一个可达性前提（要有一个未来时间戳，正常使用不会遇到），但后果是「提醒丢失 / 无谓打扰」，而且是同一个修复的漏网之鱼；不算 P1 因为 Dock 角标 / 菜单栏仍然亮，且只在 Claude 桌面 App 在最前面时才出现。
- **建议修法**（我没改）：在 `DesktopMeta.lastFocused(path:)` 里把 `v > now_ms + 86_400_000` 的值夹成 `now_ms`（和引擎侧同一个阈值），或让应用层直接读 `SessionEngine` 已经夹过的 `meta.lastFocusedAt`；再补一条测试（X = 现在 + 30 天，Y = 现在 → `Cache.isMostRecentlyFocused(host: "local_y")` 不能是 false）。

## P3（一句话）

1. **R4a-02 [P3]** 合并卡「N 位同事在等你」的 N 可能比真正还在等的人数多：`post` 里 `recent` 窗口（2 秒）里的人不管现在还在不在等都算进 `who`（`AlertCoordinator.swift:219-222`），carry 部分用的 `waitingKeys` 又是上一拍的旧值（`:231`，`waitingKeys` 到 `observe` 末尾才更新）。典型：A 刚提醒、0.3 秒后被批准，1.7 秒后 B 的提醒到 → 合并卡写「2 位同事在等你」，其实只有 B 在等，B 自己的具体提示卡（工具 + 命令）也被换成了这张泛泛的卡。随机模拟里 72 561 条提醒中 12 772 张合并卡有 424 张（3.3%，模拟里状态切换比真实频繁得多）N 偏大；**不是 R3c-01 引入的**（`recent` 的行为原来就有），R3c-01 的欠计问题确实修好了（欠计 0 次）。证据：`R4A overstatedExamples` 里 `seed 3 t=580.08 who=["t:23","t:8"] waiting=["t:8"] … body=2 位同事在等你`。修法：`who` 里只留「现在还在等」的人（`recent` 的 key ∩ 本拍的 waiting 集合）。
2. **R4a-03 [P3]** 「有事找你 / 做完了」型合并卡（`waitingBased == false`）盖住了正在等的人之后，这些人处理完了系统通知中心里那条「N 位同事有事找你」不会被撤（`observe` 只撤 waiting 型的合并卡；单独的「做完了 / 出错」通知本来也不撤，属同一取向），提示卡 6 秒后自己收。
3. **R4a-04 [P3]** `NotificationService.statusText`（`NotificationService.swift:~76`）把 `.ephemeral` 显示成「已授权」，但 `systemAllowed` 只认 `.authorized` / `.provisional`（`:82`，`.ephemeral` 走兜底提示卡）；`.ephemeral` 只属于 App Clip（探针里 `UNAuthorizationStatus.ephemeral` 在 macOS 上直接编译不过），macOS 上不可达，只是两处口径不一致。
4. **R4a-05 [P3]** `NotificationService.post` 的 `liveKeys.count > 200 → removeAll()`（`:96`）会把仍然有效的 key 也清掉：恰好在「授权刚被关掉、补卡的回调还在路上」的窗口里且累计 200 个从没被撤过的 key（做完了 / 出错的 key 不会被撤）时，那几条的补卡会被丢掉。需要三个条件同时成立，只列出。
5.（R3a-02 的语义边界，不算问题，只记录）`clampingFuture` 夹的是「读文件那一刻的 `now`」，文件签名不变就不再重读：未来时间戳被固定成 T0（之后一直是 T0，不会随时间前进）——对下班工位到期（`since` = T0，从 T0 起算 12 小时）、未读（T0 之后结束的轮次照常亮）都是想要的效果；时钟被拨回（用户把系统时间调回去）而文件没变时，缓存里那份「原来不算未来、现在算未来」的值不会被重新夹，下次 App 启动才会夹（和 hook / 会话记录的夹法同一个取向：读的那一刻夹）。

## 疑点（没有证据，不算问题）

- `NotificationService.post` 里两次 `refresh` 的回调若乱序到达（同一个 `multi` key 的合并链在同一拍里连发两次），旧文案的补卡可能压过新文案；系统的 `getNotificationSettings` 回调实际是按序的，而且只在「授权刚被关掉」的那个极短窗口里才有补卡，我没有办法造出乱序。
- `.authorized` 但用户把「通知样式」设成「无」时不弹兜底卡（`alertSetting` 没看）：R3c 已列过，仍然没法在这里造出来。

## 检查过什么（覆盖清单）

**读过的文件**：`QA/ISSUES.md` 汇总表、`QA/REPORT.md` 章节目录、`review-R3a/R3b/R3c.md` 全文；`AlertCoordinator.swift`、`AlertPipeline.swift`、`NotificationService.swift`、`ToastController.swift`（全文）；
`AppModel.swift` 的提醒接线（`tick` 末尾、`isUserLooking`、`jump`、通知点击）；`JumpService.swift` 的 `DesktopMeta` 全部；`RealProvider.swift`、`Providers.swift`；
`DesktopMetaReader.swift`（全文）、`SessionEngine.swift` 里所有用 `meta.createdAt / lastActivityAt / lastFocusedAt` 的地方（`:295 / :323-328 / :340-358 / :369-370 / :844`）、`bootstrapDormants` / `maintainAway`；
测试侧：`DesktopMetaGate.swift` 与它包起来的 6 条测试（`DesktopMetaFileIOTests` ×2、`EngineConfigTests` ×3、`ReviewRegressionAppTests` R2-008）、R3c-01/02 的回归测试、`Fakes.swift` / `Fixtures.swift`、
`FuzzSecurityTests` / `FuzzRegressionTests` / `OpenAuditTests` / `RegistryTests`（`FileAccessTests`）里所有碰 `FileIO.openObserver` / `forbiddenHits` 的地方，逐个确认所属套件是否是 `.serialized` 的 `FileAccessTests`（含扩展），以及非串行套件里有没有会让 `forbiddenHits` 加一的写法（`symlink` 指向 `.key` 的全部 22 处、`.key` / `.sock` 字面量的全部使用点）。

**跑过的**（都在拷贝里）：
- **AlertCoordinator 随机模拟**（`R4aProbeTests.randomSimulation`，假时钟，逐拍喂快照）：先 300 种子 × 1 500 步（45 万拍），再 **600 种子 × 3 000 步 = 180 万拍、72 561 条提醒、12 772 张合并卡**；每个种子 2–5 个会话（terminal / desktop 混合，一半种子纯 terminal），
  每拍 6% 概率切活动（思考 / 等批准 / 提问 / 计划待审 / 其他等待 / 做完了（5–90 s、桌面会话 25% blocked）/ 空闲 / 出错）、0.4% 切「隐藏」、0.3% 切离场、0.4% 换成新会话（新 key，会话来去）、0.3% 切隐私模式；
  步长 60% 是 0.09 s（真实 tick）、其余 0.05–0.6 s / 0.6–3 s / 3–30 s（时间跳）；`isLooking` 是 (key, 时间) 的确定性函数（12% 的时间在「看」），`notify.error` 随机开关。
  检查的不变量（每拍）：① 每个「正在等且已经提醒过」的人，在他被覆盖后 6 秒内（提示卡寿命）始终有一张卡盖着（自己的卡或合并卡）——**0 违反**；② 「在等你」合并卡的文案人数 = 它盖着的人数（`debugMulti.keys.count`）——**0 不符**；③ 合并卡在被合并的人都不等了之后必撤 / 没有「合并状态在、卡不在」或反过来——**0**；
  ④ 同一段等待同一种类只提醒 1 次——**0 重复**；⑤ 1.5 秒去抖（个体提醒必在等待段开始 ≥ 1.5 s 后）——**0**；⑥ 20 秒节流（同 key 同类提醒间隔 ≥ 20 s）——**0**（第一版模型把 `.other` 和 `.approval` 记成同一类，出现 312 条假报，已改正）；⑦ 2 秒合并窗口（两个个体提醒不同 key 间隔 ≥ 2 s）——**0**；
  ⑧ 不丢提醒（一段等待 ≥ 45 s、期间从没被「在看」、开着该类提醒 → 必有提醒）——**0**；⑨ 无界增长（`bookkeepingCounts` 各字典 ≤ 存活会话数、`lastAlert ≤ 40`、`recent ≤ 40`）——**0**；⑩ 隐私模式下任何提醒的标题 / 正文不含「SECRET」——**0**；⑪ 被隐藏的 buddy 不发任何提醒——**0**；⑫ `waitingKeys` 恒等于「在场、没被隐藏、活动是等待类」的集合（Dock 角标 / 菜单栏的数据源）——**0 不符**；⑬ 没有人在等时不残留「在等你」型合并卡——**0**。
  唯一的发现：合并卡人数偏大（R4a-02），第一版模型里 178 条「无卡盖着」是我没把 6 秒寿命算进去的模型错误，改正后 0。
- **NotificationService / ToastController 探针**（`R4aProbe2Tests`）：真实 `ToastController`（`orderFront` 换成空操作）连发 6 张 → 只剩 3 张（k5 k4 k3）；同 key 重发替换；全部 dismiss + 200 次 step 后清零。
  `NotificationService` 用「后台线程延迟回调」的假通知中心测各种授权状态：**这一组只有部分有效**——我的测试台里初始 `refresh` 的主线程回调没有被主线程 run loop 送出来（`systemAllowed` 一直是 false），所以实际测到的是 `.notDetermined` 走兜底的路径（1 条 post → 1 张卡、0 条系统通知，无重复），
  「已授权 → 被关 → 补卡」的异步路径**没有被这个探针测到**；那条路径由仓库自己的同步假中心测试（`r3c02_…`）覆盖，我另外靠读码确认：补卡回调在主线程（`refresh` 里 `Thread.isMainThread` 判断 + `DispatchQueue.main.async`）、`liveKeys` 只在主线程读写、`clear` 会让飞行中的补卡作废、缓存更新后后续提醒直接走兜底、不会「系统通知 + 提示卡」同时给用户两次（授权仍在时回调里 `systemAllowed` 为真不补卡）。
- **DesktopMeta 探针**：R4a-01（见上）。
- **完整并行回归**（`BuddyCoreTests|BuddyOfficeTests`，`--skip R4aProbe`）：见下方「完整并行回归」一节。

**读了没找到问题的地方**：`DesktopMetaGate`（`NSLock` 非递归：6 条被包的测试里没有嵌套 `exclusive`，持锁的测试体不需要主线程也不 `await`，所以 `@MainActor` 的 R2-008 在主线程等锁不会和持锁者互相等；`RealProvider.make` 的全部调用点——`EngineConfigTests` ×3、R2-008——都在门里；`AppModelTests` 用假 provider，不碰 `baseOverride`）；
`FuzzSecurityTests` 两条按 `dir.path` 前缀过滤的观察口没有削弱断言（正向断言 `last.records[1001]…`、`fileCount == 8`、`forbiddenHits > hits0` 都在；`names.allSatisfy` 只是不再被别人的路径污染）；`OpenAuditTests` 的 `scope`；`FileAccessTests`（`.serialized`，含三处扩展）里所有 `openObserver` 使用者；
`clampingFuture` 的所有调用点（只有 `refresh()` 一处）、引擎里用到元数据时间戳的全部位置（下班工位选取 / 到期 / 未读 / 座位排序）在「夹成 T0」下的行为。

**没覆盖到 / 没时间做**：① 「授权被关 → 补卡」的异步真路径没有被探针测到（见上）；② 没做 ASan / TSan（另有人在跑）；③ 没有真实 GUI / 真实系统通知；④ 没有对 `SessionEngine` 做新的随机模拟（R3a 已做，我只读了 `clampingFuture` 相关路径）；⑤ 时间盒里有约 10 分钟被一次「另一个 SwiftPM 实例占着 `.build-r4a`」的锁等待吃掉（我自己前一个后台运行还在跑）。

## 完整并行回归

拷贝里（含我的两个探针文件，`--skip R4aProbe` 跳过它们）`scripts/dev.sh test --filter "BuddyCoreTests|BuddyOfficeTests"` 默认并行连跑 4 次：**4/4 全过，每次 614 个测试 / 67 个套件，0 失败**（36–44 秒/次；日志 `r4a-full1..4.log`）。
没有死锁（`DesktopMetaGate` 的 6 条测试每次都跑完）、没有间歇红灯（R3a P2-1 的登记表诱饵测试、R3b-01 / R3c-03 的 R2-008 都稳定通过）。样本只有 4 次，R3a / R3b 当时的红灯概率是 10–25%，所以这只是「没再看到」而不是证明。

## 统计

| 严重度 | 新增 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 1（R4a-01 应用层 `DesktopMeta.readAll()` 未夹未来时间戳） |
| P3 | 4（R4a-02 … R4a-05；另有 1 条只记录的语义边界） |
