# R1b 独立复查（表现层 / 像素引擎）

> 复查员 R1b，2026-09-29 05:55–06:35。范围：`Sources/BuddyStage`、`PixelKit`、`BuddyArt`、`buddyctl`、`Tests/BuddyStageTests`。
> 基线：05:55 拷到 scratch 的项目快照（之后只有 `Tests/BuddyStageTests/SpecTraceUITests.swift` 是别人新加的，我读了它的用例清单）。
> 铁律：项目目录里除本文件外一个字节没动；所有实验（编译、测试、fuzz、变异）都在 scratch 副本 `…/scratchpad/r1b/proj` 里做。
> 方法：读全部代码 + 写了十几组探针测试（随机世界差分 fuzz、Canvas 参考模型差分、Director / Performer 时序、文字语料、隐私文案、美术全外观、text-audit 补钟点…），**能复现的才算发现**。

## 1. 结论

**有 4 个新的 P2（都已用最小测试复现）、若干 P3；没有新的 P0 / P1。**

| 编号 | 严重度 | 一句话 |
|---|---|---|
| R1b-01 | P2 | `VisualDirector` 错开推迟期间，活动又变回原来的种类：到点那一帧套用的是**过期的中间快照**，姿势 / 屏幕 / 桌牌被带偏 1.5 s / 0.8 s / 1.0 s |
| R1b-02 | P2 | 桌牌动作文字的 1.0 s 最短停留被 `digitMask` 绕过：文件名 / 命令里只差数字（`part1.txt` → `part2.txt`）时文字每次工具切换都立刻换（实测 4 秒里桌牌文字换了 26 次） |
| R1b-03 | P2 | 隐私模式没有隐藏 MCP server 名和未知工具名（桌牌、状态行、悬停卡片都显示「在用 acme-secre…」），违反任务书 6.3「隐私模式下隐藏全部细节」 |
| R1b-04 | P2（低概率、规格没写） | 气泡通道没有最短停留：Grep / Read 每 0.3 s 交替时，放大镜气泡 6 秒内开关 19 次，而姿势才变 3 次、屏幕 6 次 |

「局部重绘 vs 整张重画」这条线我重点做了：**随机世界差分（5.76 万帧办公室 + 70 % 的帧同时跑小鱼缸 / 宠物条）0 处不一致**，而且用「整张重画且关掉人物图层缓存」当第三方基准，连 `verify` 抓不到的缓存键漏项也能抓到（见 §4 第 1 组）。

## 2. 发现

**探针里共用的两个辅助函数**（下面的最小复现都用它们；完整文件在 §6 的 scratch 目录 `Tests/R1bTests/Probes.swift`）：

```swift
let base = Date(timeIntervalSince1970: 1_800_000_000)
func tool(_ n: String, _ d: String = "x", at: Double) -> Activity { .tool(ToolCatalog.makeCall(name: n, detail: d, at: base.addingTimeInterval(at)), parallel: 1) }
func snap(_ a: Activity, key: String, seat: Int, since: Double) -> BuddySnapshot {
    var s = BuddySnapshot(key: key, seat: seat, salt: 0, title: "会话 \(key)", sessionId: key, origin: .desktop, now: base)
    s.activity = a; s.phase = a.phase; s.activitySince = base.addingTimeInterval(since)
    if a.phase != .idle { s.turnStartedAt = base }
    s.hookActive = true
    return s
}
```

### R1b-01　P2　错开推迟期间活动变回去：套用了过期的中间快照（SP-06 的同一根因，只修了一半）

- **和已记录问题的关系**：`ISSUES.md` 的 SP-06（已修）修的是「推迟期间变成**等待类**」这一条路径（`if s.activity.needsUser { pending.removeValue }`）。同一个根因——「推迟记录里存着一份过期的中间快照、到点原样套用」——在「推迟期间**变回已套用的同一种类**」这条路径上没有被修：那时 `changed == false`，pending 既不清也不更新。SP-06 的回归测试（`aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately`）只覆盖等待类，所以没抓到。
- **现象**：多个人同一帧换活动时，除第一个人以外每个人的新快照会被推迟 90 ms × 序号（≤ 0.6 s）。如果这个人的活动在推迟到点**之前**又变回了「已套用状态」的同一种类（Read → Edit → Read），`VisualDirector` 不清掉那条推迟记录，到点那一帧把推迟开始时存下的 Edit 快照当成 `effective` 套给 Performer。Performer 看到一帧 Edit，姿势通道（已停留 ≥ 1.5 s）立刻换成打字，之后 1.5 s 内他明明在 Read 却在打字（屏幕 0.8 s、桌牌 1.0 s 同理），最后才换回来。
- **复现**（`Tests/R1bTests/Probes.swift` → `R1bDirector`，scratch 里 `scripts/dev.sh test --filter R1bDirector`）：
  ```swift
  // 3 个人；t=2.0 三个人同时 Read → Edit（错开 0 / 90 / 180 ms）；第 3 个人在 t=2.05（他自己的推迟到点之前）变回 Read
  var t = 0.0
  while t < 5 {
      var snaps: [BuddySnapshot] = []
      for i in 0..<3 {
          let editing = t >= 2.0 && !(i == 2 && t >= 2.05)
          snaps.append(snap(editing ? tool("Edit", at: 2.0) : tool("Read", at: 0), key: "d:\(i)", seat: i, since: editing ? 2.0 : 0))
      }
      d.update(snapshots: snaps, now: base + t, time: t, privacy: false)
      if case .tool(let c, _) = d.performers["d:2"]!.snapshot.activity, c.name == "Edit" { sawEdit.append(t) }
      poses.append((t, d.performers["d:2"]!.pose)); t += 1.0 / 30
  }
  ```
  实测输出：`seat-2 performer saw Edit at [2.2]`；`poses after t=2: 2.00:mouse, 2.20:typing, 2.40:typing … 3.60:typing, 3.80:mouse`——他一直在 Read，姿势却是打字，持续 1.6 秒。期望：`sawEdit` 为空、姿势一直是 `.mouse`。
- **根因**：`Sources/BuddyStage/VisualDirector.swift:77-87`。`changed = !sameKind(old.activity, s.activity)` 为 false（已经变回 `applied` 的种类）时，只有 `changed && !needsUser` 才会写 / 更新 `pending`，所以旧的 `pending[key]`（存着中间态 Edit 快照）原封不动留着；紧接着 `if let pd = pending[s.key], time >= pd.at { effective = pd.snap … }` 到点就把它套用。
- **触发条件**：至少两个人同一帧换活动（推迟 > 0），且后一个人在 ≤ 0.6 s 内换回同一种类。Read → Grep → Read 这类连发很常见；多个会话同时在忙时就会撞上。
- **建议修法**：在 `if let pd = pending[s.key]` 之前加一句 `if !changed { pending.removeValue(forKey: s.key) }`（目标已经等于已套用状态，推迟记录作废）。
- **建议补的回归测试**：就是上面这段（断言 `sawEdit.isEmpty`，且 2.2–3.5 s 内姿势不是 `.typing`）。

### R1b-02　P2　桌牌文字 1.0 s 最短停留被「数字抹平」绕过

- **现象**：`Performer.update` 里为了让「1:23 → 1:24」这种计时器数字不受最短停留约束，用 `digitMask`（把连续数字 / 冒号抹成 `#`）比较新旧文字，抹平后相同就**立刻**更新且不刷新 `plateSince`。但文件名 / 命令 / 搜索词里的数字也被抹掉了：`在读 part1.txt` → `在读 part2.txt`（动作一样，对象不一样）每次工具切换都立刻换字，完全不受 1.0 s 约束。
- **复现**（`R1bPlate.digitOnlyDifferencesInFileNamesBypassTheOneSecondHold`）：每 0.15 s 换一个 `Read /a/part<n>.txt`，30 fps 推进 4 秒，记录 `performer.plate` 每次变化的时刻：
  ```swift
  let d = VisualDirector(); var changes: [Double] = []; var last = ""; var t = 0.0
  while t < 4 {
      let n = Int(t / 0.15)
      d.update(snapshots: [snap(tool("Read", "/a/part\(n).txt", at: t), key: "d:a", seat: 0, since: t)], now: base.addingTimeInterval(t), time: t, privacy: false)
      let p = d.performers["d:a"]!.plate
      if p != last { changes.append(t); last = p }
      t += 1.0 / 30
  }
  // 期望：相邻两次变化间隔 >= 1.0 - 1/30；实际见下
  ```
  ```
  changes at [0.00, 0.17, 0.30, 0.47, 0.60, 0.77, 0.90, 1.07, 1.20, … 3.93]  （首次出现之后又换了 26 次，间隔 0.13–0.17 s；任务书 5.6 要求 ≥ 1.0 s）
  ```
  同样的路径：`chunk1.md → chunk2.md`、`test_1.py → test_2.py`、`sleep 1 → sleep 5`、WebSearch 「swift 5」→「swift 6」、`v1 → v2`。
- **根因**：`Sources/BuddyStage/Performer.swift:262-271`（`digitMask` 在 :287-295）。抹数字的范围比「计时器」大得多。
- **建议修法**：只把「计数器位置」的数字抹掉——`PlateCopy` 里计数器都在固定位置：` · N:NN` / ` · N 分钟` / ` · N 秒`（等批准 / 运行中）、`重试中 N/M`、` ×N`、`派了 N 个帮手`、`打盹 N 分钟`。比较时只处理这几种后缀 / 模式（例如只抹「最后一个 ` · ` 之后」和这几个固定前缀后面的数字），文件名里的数字保留。
- **建议补的回归测试**：`R1bPlate.digitOnlyDifferencesInFileNamesBypassTheOneSecondHold`（断言相邻两次变化间隔 ≥ 1.0 − 1/30），再加一条「计时器数字仍然每秒都换、不受约束」防止修过头。

### R1b-03　P2　隐私模式下桌牌 / 状态行 / 悬停卡片仍显示 MCP server 名和未知工具名

- **现象**：任务书 6.3「隐私模式下隐藏全部细节」。`PlateCopy.toolText` 里读文件 / 命令 / URL / 搜索词都判了 `privacy`，唯独 `.mcp` 和 `.unknown` 两类没判：`在用 acme-secre…`、`在用 linear`、`在用 SomeInternalTo…` 原样显示。MCP server 名常常就是内部系统 / 客户 / 项目名（`mcp__acme-internal-crm__…`），隐私模式正是为了共享屏幕时不泄露这些。桌牌状态行（`statusCandidates`）和悬停卡片的动作行都用同一个函数，所以三处都泄露。
- **复现**（`R1bPrivacy.privacyModeHidesToolDetailsIncludingServerAndToolNames`）：
  ```swift
  let s = snap(tool("mcp__acme-secret-crm__query", "x", at: 0), key: "d:a", seat: 0, since: 0)
  PlateCopy.activity(s, now: base + 1, privacy: true)   // "在用 acme-secre…"
  PlateCopy.activity(snap(tool("mcp__linear__create_issue", …)), now: …, privacy: true)   // "在用 linear"
  ```
  期望：隐私模式下是「在用外部工具」之类不带名字的文案。
- **根因**：`Sources/BuddyStage/PlateCopy.swift:141-142`（`case .mcp` / `case .unknown` 没有 `privacy ? … : …`）。
- **建议修法**：`.mcp`：`privacy ? "在用外部工具" : "在用 " + …`；`.unknown`：`privacy ? "在用工具" : …`。（屏幕上的 server 首字母只有一个字母，不算泄露。）
- **备注**：`buddyctl text-audit` 的隐私矩阵只检查排版，不检查文案内容，所以这一项没被抓到。

### R1b-04　P2（低概率；规格没写）　气泡没有最短停留，会随工具节奏一闪一闪

- **现象**：任务书 5.6 只给姿势 / 屏幕 / 桌牌文字三个通道定了最短停留；气泡（`bubble`）通道没有：`if tb != bubble { … bubble = tb }` 目标一变就变。Grep（放大镜气泡）和 Read（无气泡）每 0.3 s 交替时：
  ```
  R1B bubble: bubble changes 19, pose changes 3, screen changes 6 in 6 s
  ```
  气泡每 0.3 s 弹出 / 消失一次（3 帧弹出动画 + 瞬间消失），而它旁边的姿势 / 屏幕都稳稳不动。用户明确说过「零闪烁」，任务书 6.6 也写了「不许开关式闪烁」。真实会话里 Grep / Glob 和别的工具 < 0.5 s 交替（并行工具、连续搜索后立刻读）就会触发；模型「思考」的间隙里气泡是 `.think`，节奏是秒级，基本不受影响。
- **复现**（`R1bBubble.searchBubbleFollowsTheToolCadenceWhileEverythingElseIsHeld`）：
  ```swift
  let d = VisualDirector(); var t = 0.0
  var bubble: [(Double, Bool)] = [], pose: [(Double, PoseKind)] = [], screen: [(Double, ScreenKind)] = []
  while t < 6 {
      let n = Int(t / 0.3)
      let a = n % 2 == 0 ? tool("Grep", "TODO", at: Double(n) * 0.3) : tool("Read", "/a.swift", at: Double(n) * 0.3)
      d.update(snapshots: [snap(a, key: "d:a", seat: 0, since: Double(n) * 0.3)], now: base.addingTimeInterval(t), time: t, privacy: false)
      let p = d.performers["d:a"]!
      bubble.append((t, p.bubble != nil)); pose.append((t, p.pose)); screen.append((t, p.screen)); t += 1.0 / 30
  }
  // 统计相邻帧变化次数：bubble 19、pose 3、screen 6
  ```
- **根因**：`Sources/BuddyStage/Performer.swift:275-276`（气泡通道没有停留时间）。
- **建议修法**：气泡也加一个最短停留（例如「出现之后至少保持 0.8 s 才允许换 / 消失」，等待类气泡不受限，与屏幕通道同一规则）；或者只对 `.search` / `.book` / `.toolbox` 这类「工具气泡」加。
- **说明**：这条属于「设计缺口」，不违反任务书的字面要求；如果认为不需要，降成 P3 也说得过去。

## 3. 疑点（没能复现成用户可见问题 / 需要人拍板）

1. **摄像机只跟「有人要你」，不去最后一行**（`OfficeScene.swift:266-276`）：注释写「滚动到有人要你或最后一行；否则 0」，代码在没人等你时保持上一个目标（初始 0），不会滚到最后一行。世界比视口高（工位很多 + 手动放大倍数，或窗口很矮）时，下面几排的人在他们不等你的时候一直看不到，也没有滚轮滚动。自动缩放在 Retina 上可以降到 1 倍，正常场景放得下，所以只在极端情况出现；没当成 bug 报，请设计者确认是不是有意的。
2. **`VisualDirector.appearance(for:)` 的缓存超过 96 条时只留在场的人**（`VisualDirector.swift:47-48`）：下班工位（外套 / 空桌）的外观下一帧重新按「当时在场的人」抽，可能和之前不一样——长时间运行、见过 96 个以上不同会话之后才会发生，肉眼表现是衣帽架上的外套换了个颜色。没有构造出来，只是读代码推断（缓存裁剪本身是 A-027 的修法，这里说的是裁剪之后的副作用）。
3. **`OfficeScene.screenFade` / `screenMemory`**（`OfficeScene.swift:244-255`）：座位号缩小到不再被遍历（`deskCount` 一次缩小 ≥ 2）时，正在熄灭的座位的 `screenFade` 项不会被清掉，`steady` 会一直为 false（每帧整张重画，只是耗 CPU）；同时 `screenMemory` 的旧内容以后可能在那个座位空着时冒出一次幽灵熄灭。要求两个最大座位号同一帧一起消失，实际不太可能，没有复现。
4. **`walkers` 的路线在起步时按当时的布局算好**：走路的 2.5–5 秒里窗口缩放导致列数变化，走路的人会朝旧的座位位置走（可能穿过桌子）。纯观感，没测。

## 4. 已检查、没问题（按文件 / 主题）

**第 1 组：局部重绘一致性（最重点）**
- 我写了随机世界差分（`Tests/R1bTests/FuzzRetained.swift`）：12 组 × 4 个种子 × 1200 帧 = 5.76 万帧办公室（局部重绘 vs 每帧整张重画），其中 70 % 的帧同时跑小鱼缸和宠物条（也是 retained vs 整张）。每一帧比较 rgba / 调色板索引 / 对象 ID 三个平面、视口、文字层（内容和坐标），以及「`canvasChanged == false` 时像素必须没变」。随机改变的输入：人数 0–20、座位号（稀疏，池子 4 / 8 / 14 / 30）、快照顺序（含偶尔不排序）、活动（30 多种，含并行 ×N、重试次数、等批准 / 提问 / 计划待审）、未读 / blocked、小助手 0–5 个（含 done）、下班工位进出、下班回来（appearedAfterLaunch 随机）、窗口视口（40…448 × 40…400，含比一个工位还小的）、缩放 1–5、标签模式、隐私、白板计数、空牌子开关、走路动画开关、悬停（含悬停一个不在场 / 空座位）、小鱼缸缩放、宠物条靠左 / 靠右切换、时钟（6 个起点 × 3 种流速，跨黎明 / 黄昏 Bayer 过渡）、帧间隔 1/30、1/15、1/10。**0 处不一致。**
- 基准的第三方版本：B 侧同时**关掉人物图层缓存**（scratch 里加了 `noSeatCache`，不改项目）——`verify` 的两侧共用同一套 `SeatCache`，缓存键漏项两边一样错，抓不到；用不带缓存的整张重画当基准就能抓到。同样 5.76 万帧 **0 处不一致**（`personSignature` 覆盖了 rig / holdClipboard / light.a,b,level / glow，读代码也是齐的）。
- 变异验证（证明这个 fuzz 有牙）：从 `SeatRenderer.signatures` 里删掉 `v.flag` → 72 处报错；删掉衣帽架外套指纹 `ck.h != coatSig` → 26 处；删掉 `personSignature` 的 `light.level`：在「两边共用缓存」的版本里**抓不到**（0 处，验证了上一条说的 `verify` 盲区），换成「无缓存基准」后 **54 处报错、12 组里 9 组失败**——这个基准补上了 `verify` 的盲区。变异都在 scratch 副本里做，做完立刻还原（还原后 diff 为空）。
- 读代码核对：`SeatRenderer.signatures` 三份指纹逐项对照 `SeatRenderer.draw` 的每个输入（origin / mode / appearance / light / chairOut / lampOn / flag / dim / props / hitID / mirror / glow / led 档 / 小助手 slot·dx·帧·起伏·外观 / extraHelpers / 气泡 kind·尺寸·思考点·zzz 步 / 屏幕 kind·seed·boot 级·fade 级·显示器种类·动态内容哈希）——全在；`RoomRenderer.dynamicRects` 覆盖了动态绘制的全部像素（钟 13×13、日历 13×9、白板 36×22、绿植 leaves 范围、饮水机 5×6、玻璃）；`dynamicSignature`（分钟 / 云步 / 绿植相位 / 饮水机帧 / 几号 / 白板计数）覆盖 `drawDynamic` 的全部输入。
- 重复 key（同一个 key 出现在两个座位）：`R1bDupFuzz` 4 组 × 3 个种子 × 800 帧（同样的随机世界，每帧 60 % 概率多塞一份同 key 不同座位的快照）：不崩、局部重绘和整张重画仍然逐像素一致。
- 宠物条 `alignRight` 运行中切换：所有槽位新位置都会被 `sig` 里的 x0 变化标脏，旧位置集合等于新位置集合，没有残影。小鱼缸 `bgKey` 覆盖 cols / rows / 光照 / 牌子缩放。

**第 2 组：状态 → 动画映射与过渡规则（任务书 6.5 / 6.6 / 5.6）**
- 6.5 表逐行对照 `Performer.targetPose / targetScreen / targetBubble` 与 `PerformerMappingTests` 的 40 多行：全部一致（含 Bash 3 / 8 s、WebSearch 先打字、MCP / 未知工具每 3 s 交替、思考 > 20 s、被打断 1.5 s、做完 0.4 / 1.6 s、blocked 便利贴）。DESIGN §13 记录的偏离（擦除过渡、等待类 ≤ 250 ms 插入等）我没有重复报。
- 最短停留 1.5 / 0.8 / 1.0 s、等待 0.4 s 转身 / 1.5 s 转回、错开 90 ms（上限 0.6 s）、离场再回来：`VisualDirector` 在人走后清掉 `performers / applied / pending / rerolling`，`OfficeScene` 清掉 `seatedAt / lastApp`，没有残留（除 §2 R1b-01 的推迟记录问题）。字典遍历顺序：`helperDraws`、走路的人、外观抽取 `existing` 都显式排序 / 按座位序，没有不确定性。
- `Double` 时间边界：`dt` 夹在 0…0.25（NaN 时得 0.25、负数得 0，不 trap）；`min-stay` 比较用 `>=`，浮点误差最多晚一帧（测试也是这样容忍的）；`now`（墙钟）和 `time`（`CACurrentMediaTime − t0`，单调）是两个时间轴，App 里渲染用的 `time` 总是晚于 update 用的 `t`，所以 `time − poseSince ≥ 0`。
- `PlateCopy` 各种极端时间（NaN / ±∞ / 1e300 / distantPast…）：`ExtremeValuesTests` 已覆盖，我又读了一遍 `wholeSeconds / safeInt` 的用法，没发现漏网的 `Int(Double)`（全仓库 grep 了 `Int(` + `.rounded` / `*` / `/`，剩下的都依赖「time ≥ 0」，见 P3-1）。

**第 3 组：文字与布局**
- `TextRenderer`：缓存有界（图片 600 张、尺寸 4000 条，超了整体丢）；`lock` 覆盖全部读写；`Key` 里 `CGFloat` 有 NaN 才会失效，没有调用点会传 NaN；`emoji` 缩放的 UTF-16 偏移累加正确。
- 我写了文字语料探针（`R1bText`）：37 个字符串（泰文 / 阿拉伯文 / 希伯来文 / 天城文 / 藏文 / 缅文 / Zalgo / 数学字母 / 制表符 / 换行 / NUL / 纯零宽 / 双向覆盖 / 键帽 / 肤色 / 家庭 ZWJ / 旗帜 / 全角 / 半角假名 / CJK 扩展 / 私用区 / 400 个 W / 4000 个汉字 / 300 个 emoji…）× 3 种字号 × 4 种 maxWidth × 2 种缩放：没有 NaN / 无穷尺寸；有 maxWidth 时图片宽度始终 ≤ maxWidth + 边距、自然宽度超了一定带「…」；换行 / 制表符 / NUL / 零宽不会撑宽或截断。只有几种复杂文字的叠加符号被图片上下边缘裁掉（P3-5）。
- 文字审计补钟点（`R1bAudit`）：`text-audit` 默认只有 12:00 / 23:00 两个钟点；我用它自己的 `TextAuditRunner` 补跑了 16 个钟点（05:35–06:50 的黎明过渡各点、17:40–19:12 的黄昏过渡各点、12:00、23:00）× 办公室 / 悬停 × 人数 1 / 4 / 8 / 12 × 标题（正常 / 长中文 / emoji / 混排）× 两种状态集（演示 / 全状态）× 缩放 2–4 × 默认 / 很窄窗口：7296 个组合、17 万段文字、2 万串像素字，**0 违规**（对比度在昼夜抖动棋盘格上也够）。
- 布局极端：`OfficeLayout.compute` 对 viewport −500…20000、maxSeat −10…Int.max/4 全组合，`effectiveZoom` 对 setting −1…9、内容尺寸 0…1e6 全组合：不 trap，`deskCount ≤ 65`，`cols ≥ 1`。`HoverCard.make`：zoom 1–5 × maxWidth 1…10000 × maxHeight nil…1000 × 标题（空 / 换行 / 2048 字 / 零宽 / emoji）；`ToastCard.make`：5000 字标题 / 换行正文 / 3000 个 W：尺寸都 > 0、不 trap。
- `PixelFont`：`width(of:)` 里 `text.count` 在循环里是 O(n²)，但只用在像素数字 / 「+N」 / 日期上，字符串很短，不算问题；缺字形落到 `?`，文本审计会抓。

**第 4 组：Canvas 原始指针**
- `Tests/R1bTests/CanvasFuzz.swift`：6 组 × 6000 张随机画布（1–40 见方），每张 4 次随机操作，参数含 ±2^40、负尺寸、零尺寸、越界矩形、随机剪裁：`fillRect / blit（翻转 / 剪裁 / id）/ blitCanvas（翻转 / 剪裁 / id）/ clearRegion / copyRegion / setClip / withClip`，逐点对比朴素参考实现，`writeBGRA`（缓冲末尾 64 字节哨兵不许被写）、`makeCGImage`、`makeDisplayImage`、`cropped` 也一起跑：**全部一致，没有越界、没有崩溃**。（我没有另外编一份 ASan 版本；每条指针路径的下标都对着剪裁 / 相交后的范围读过一遍，参考模型差分里的越界读会表现为对不上。）
- `contentHash` 奇数像素尾部处理正确；`init` 的 `precondition` 只挡非正尺寸；`writeBGRA` 有 `bytesPerRow` 和相交检查，`PixelView` 传的 `vp` 总在画布内（`OfficeScene` 夹过）。
- `applyLightPool` 的强度 ≤ 0.85 / 0.7，不会出现无穷；`lut.table[Int(m)]` 的 `m` 来自 `Resolved.master`，总小于调色板项数。

**第 5 组：资源上界 / 线程安全**
- 有界：`TextRenderer` 600 / 4000、`Lighting.resolvedCache` 400、`ScreenContent.staticCache` 4096、`VisualDirector.appearances` 96（+在场）、`plateCache / seatCaches / emptyApps / screenMemory / screenFade` 都以座位数 ≤ 65 为界、`seatedAt / lastApp` 人走清掉、`walkers` 走完清掉、`helperTracks` 离场 0.6 s 后清掉、`inkExtentCache` 只有几种样式。
- `nonisolated(unsafe)` 静态变量：`SceneClock.sec/cached`（`lock`）、`ScreenContent.staticCache`（`staticLock`，每次访问都在锁里）、`Lighting.resolvedCache`（`cacheLock`）、`OfficeScene.inkExtentCache`（`inkExtentLock`）、`SeatRenderer.screenScratch`（`scratchLock`，且 `isStatic` 在锁外调用，不会死锁）、`PixelFont.auditEnabled`（只在 text-audit 打开）、`Prof.enabled`（只在 bench）：没有无锁访问。
- 每帧分配：`drawMonitor` 在开机 / 关机渐变（300 ms）里为每个座位新建一张和世界一样大的 `Canvas` 当草稿（P3-6）；其他每帧只有小数组。

**第 6 组：测试有没有钉住行为（`Tests/BuddyStageTests`）**
- 没有 `withKnownIssue`、没有 `#expect(true)`；`_ = scene.render(...)` 这类烟测都配了别的断言（`ExtremeValuesTests` 只断言「不崩」，那正是它的目的）。`PerformerMappingTests` 是 6.5 表的语义断言（不是靠金图）；`PerformerTimingTests` 有 1.5 / 0.8 / 1.0 / 0.4 / 1.5 / 90 ms 的精确数值断言；`RenderingTests` 有「静态判定和真实一致」「命中缓冲每个像素都在自己格子里」等语义断言；`SpecTraceUITests`（新增）有弹簧 / 呼吸 / 眨眼 / 转身步骤 / 开机 16 级 / 昼夜逐像素只翻一次等数值断言。金图哈希只是补充。
- **盲区**（不是空断言，是没覆盖到）：`verify` / `compareRetained` 只比较画布三个平面，不比较文字层和视口；两侧共用 `SeatCache`；悬停只在第一个人身上；没有窗口尺寸变化、座位号不连续、快照乱序、悬停换人 / 人走。这些我的 fuzz 都补上了，结果一致。R1b-01 / 02 / 04 都是现有测试的输入没覆盖到的组合（`simultaneousChangesAreStaggeredBy90msEach` 没有「推迟期间变回去」；`plateActionTextNeverChangesFasterThanEverySecond` 的两个文件名里没有数字；气泡通道根本没有对应的最短停留测试）。

**第 7 组：buddyctl**
- 18 组畸形参数（`--zoom 0/-3`、`--scale 0`、`--fps 0/nan`、`--w 0`、`--w -5`、`--from nan`、`--clock 99:99`、`--mode crowd0/crowd-5`、`--crop 0,0,0,0 / 负数`、`--hover 999/-1`、`--cols 0`、`--scene tank --zoom 0`）：都是 0 帧 / 1 帧正常退出，不崩、不挂；只有 `--cells 0` 会崩。BuddyArt 的 `cell / sheet / strip / walk` 也试了几组畸形参数：`cell --cloth 99 / -1` 会崩，其余都是正常退出（P3-4）。

**第 8 组：BuddyArt（人物 / 美术）**
- `R1bArt`：6 种衣服 × 8 种发型 × 6 种配饰 × 5 个朝向（× 随机椅子 / 显示器 / 光照级 / 表情 7 种 / 手位置：空、(0,0)、很远 (200,200)、负数、正常）共 2304 次 `BuddyRig.render / renderStanding`：不崩（手正好落在肩上 d = 0、够不着时的 `elbow` 都走通）；`SpriteBook` 缺名字会 `preconditionFailure`，但 `book.get` 有回退，全外观空间没有触发。
- `PoseLibrary.frame` 对 24 种姿势 × 3 个种子 × 130 秒：所有手位置 / 躯干 / 头偏移有限且 < 120 / < 12 像素（不会把 IK 拖到几千像素外）。

## 5. P3（一行带过）

1. **对负的 `time` 不设防**：`PoseLibrary.frame(.writingPad, t < −0.134)` 的 `[…][Int(t*7.5) % 4]` 下标越界（已用 exit test 复现会崩）、`RoomRenderer.plantPhase(time < 0)` 同样；App 里 `time = CACurrentMediaTime() − t0` 单调且渲染晚于 update，不可达。
2. `OfficeScene` 里 `walkers.cleanup` 在 `finishedEntering` 之前，进场走完后只有 50 ms 的窗口能记下坐下时刻；帧间隔 > 50 ms（12 fps 以下）会丢掉「坐下后显示器 300 ms 开机」（`R1bWalkers` 实测 dt = 0.08 时丢、≤ 0.06 时不丢）；走路期间节拍是 30 fps，只在主线程卡顿时发生，纯观感。
3. （A-009 修了 `writeBGRA`，同类的没跟着改）`Canvas.cropped(rect)` 在 rect 和画布不相交时返回 1×1 的左上角像素，所以 `blitCanvas(srcRect: 画布外)` 会画出 1 个像素；`makeCGImage(crop: 画布外)` 退化成整张画布。当前没有调用点用 `srcRect`，`vp` 也总在画布内，不可达。
4. 开发用 CLI 两处会 trap：`buddyctl snapshot --cells 0`（`StageCommands.swift` 的 `max(1, frames.count / maxCells)` 除零）、`buddyctl cell --cloth 99` / `--cloth -1`（`Pal.clothRamps[…]` 下标越界，`ArtCommands.swift:26`）。
5. 泰文 / 藏文 / Zalgo 这类叠字符号的标题，符号被文字图片上边缘裁掉一截（图片高度按苹方的 ascent / descent 定，回退字体更高）；不会溢出到别的元素上，只是有点被切。`text-audit` 的语料里没有这些文字。
6. `drawMonitor` 开机 / 关机渐变期间每个座位每帧新建一张世界大小的草稿 `Canvas`（`SeatRenderer.swift:291`）：启动时最多几个座位 × 9 帧，窗口很大时每张几 MB，只影响那 0.3 s 的 CPU / 内存抖动。
7. 气泡像素没有命中 ID：`drawBubble(…, id:)` 的 `id` 参数根本没用（`SeatRenderer.swift:318-353`），办公室里点气泡没反应、宠物条里鼠标穿过气泡（`StripScene` 顶部注释却说「鼠标只有碰到 buddy（或气泡）时才被拦下」；`R1bHit` 实测办公室 / 宠物条气泡 0/270 个像素带 ID）。任务书只要求点小人跳转，所以只算 P3；如果想让气泡可点，把 `id` 传给 `blit / fillRect`（并把气泡矩形放进 `HitTestingTests` 的「在自己格子里」断言）。
8. 打开隐私模式时，桌牌动作文字还会被「1.0 s 最短停留」多留最多 1 秒（刚变过文字的话）；标题 / 悬停卡片是立即隐藏的。
9. `PlateCopy.displayTitle` 只处理「空白」标题，纯零宽字符 / 控制字符的标题（U+200B、U+FEFF…）会画出一块空白桌牌；数据层不过滤这类字符。
10. 摄像机注释和代码不一致（见 §3 疑点 1）。

## 6. 附：怎么重跑我的探针

scratch 副本：`/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/r1b/proj`（Package.swift 里去掉了 App / 数据层测试目标、加了 `R1bTests`；`OfficeScene / TankScene / StripScene` 各加了一个 `noSeatCache` 开关用来做无缓存基准，**项目目录里没有这个改动**）。

```
cd <scratch>/proj
BUDDY_SCRATCH=<scratch>/build-t scripts/dev.sh test -j 2 --filter "R1bDirector|R1bPlate|R1bPrivacy|R1bBubble|R1bHit|R1bText|R1bMisc|R1bCanvas|R1bWalkers|R1bArt|R1bAudit|R1bRetainedFuzz|R1bDupFuzz"
```
`swift test` 要在沙箱外跑。探针里「预期失败」的是：`R1bDirector`（R1b-01）、`R1bPlate.digitOnly…`（R1b-02）、`R1bPrivacy`（R1b-03）、`R1bBubble`（R1b-04）、`R1bHit`（P3-7）、`R1bText`（P3-5）、`R1bCanvas` 里两个 P3-3 的断言；其余（含 12 组随机世界 fuzz）都是通过。
