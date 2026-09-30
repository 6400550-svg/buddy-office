# 表现层 / 文字审计发现的问题（TA-xxx、SP-xxx）

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

