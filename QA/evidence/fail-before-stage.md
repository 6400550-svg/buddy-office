# 回归测试：修复前失败、修复后通过（表现层 / 文字审计组）

生成：2026-09-29 05:14，脚本 QA/tools/verify_fail_before.py（在隔离工作树里逐个撤销修复再跑对应的测试）。

| 编号 | 修复 | 回归测试 | 修复后 | 撤销修复后 |
|---|---|---|---|---|
| TA-001 | 桌牌文字对比度（深色字，白天 / 夜里都 ≥ 4.5:1） | `TextAuditRegressionTests/plateTextMeetsContrastAtAnyTimeOfDay` | 通过 | 失败 ✅ |
| TA-002 | 桌牌高度 12 像素（原 10 像素放不下标题 + 状态两行） | `TextAuditRegressionTests/twoLinePlateTextStaysInsideThePlate` | 通过 | 失败 ✅ |
| TA-003 | emoji 缩到 0.78 倍（原样大小的 emoji 字形比苹方行盒高） | `TextAuditRegressionTests/emojiInkStaysInsideTheCJKInkRange` | 通过 | 失败 ✅ |
| TA-004 | 睡着的 zzz 两个 z 之间留 1 像素 | `TextAuditRegressionTests/sleepingBuddysTwoZsDoNotTouch` | 通过 | 失败 ✅ |
| TA-005 | 「今天还没人上班」牌子：更亮的字 + 画在桌椅上面（原来烘进背景、被桌椅盖住，字对比度 4.45:1） | `TextAuditRegressionTests/emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks` | 通过 | 失败 ✅ |
| TA-006a | 悬停卡片不盖住被悬停那个人自己的头 / 屏幕 / 气泡 | `TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner` | 通过 | 失败 ✅ |
| TA-006b | 被卡片盖住的桌牌文字收起来 | `TextAuditRegressionTests/plateTextUnderTheHoverCardIsHidden` | 通过 | 失败 ✅ |
| TA-007 | 悬停卡片宽度上限按窗口宽反推（原来比窗口只多 1 像素，窄窗口里放不下） | `TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner` | 通过 | 失败 ✅ |
| TA-008 | 悬停卡片兜底位置（窗口小到候选位置都放不下时，网格搜索一个不盖住人的地方） | `TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner` | 通过 | 失败 ✅ |
| TA-009 | 实际缩放按窗口宽和高夹到「至少放得下一个整工位」 | `TextAuditRegressionTests/zoomIsClampedSoAtLeastOneWholeSeatFits` | 通过 | 失败 ✅ |
| TA-010 | 空标题 / 全空白标题显示占位文字 | `TextAuditRegressionTests/blankTitlesGetAPlaceholderOnPlatesAndCards` | 通过 | 失败 ✅ |
| TA-011 | 审计工具自身：负的设备像素坐标向下取整（原来向零取整，读错画布行 → 看不见的桌牌被误报对比度） | `TextAuditDetectorTests/floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow`、`TextAuditMatrixTests/quickMatrixHasZeroViolationsAndReallyCoversTheScenes` | 通过 | 失败 ✅ |
| TA-012 | 「其他 MCP」屏幕的 server 首字母：4×6 像素字体补上 A–Z（原来只有数字和 M / K，其余落到「?」） | `ScreenContentTests/theSmallPixelFontDrawsEveryLatinCapital`、`ScreenContentTests/theMcpAppScreenNeverFallsBackToThePlaceholderGlyph` | 通过 | 失败 ✅ |
| TA-013 | Bash 长任务的进度条移到屏幕第 5–6 行（原来在第 12–13 行，被人的头挡住） | `ScreenContentTests/theLongBashProgressBarIsAboveTheRowsTheHeadHides` | 通过 | 失败 ✅ |
| SP-01 | 显示器关机：人离开后屏幕内容用 Bayer 抖动倒放 300 ms 熄灭（原来一帧硬切成黑屏；任务书 5.5 / 6.5 / 6.6） | `MonitorTests/theMonitorFadesOutOver300msInsteadOfCuttingToBlack` | 通过 | 失败 ✅ |
| SP-02 | 指示灯 3 个色阶呼吸：待机灯 灭→半亮→亮→半亮（4 s），等待琥珀灯 暗→亮→更亮→亮（1.25 s = 0.8 Hz）（原来待机灯 2 秒亮 2 秒灭、等待灯是固定色） | `MonitorTests/theStandbyLightBreathesThroughThreeLevelsSlowly`、`MonitorTests/theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz` | 通过 | 失败 ✅ |
| SP-03 | 连续滚动的屏幕（文档 / 日志 / 终端）按整数个渲染帧一步（原来文档 150 ms、日志 300 ms 一步，在 15 fps 下是 2、3、2、3 帧的不均匀节奏） | `ScreenContentTests/documentAndLogScrollingStepsAreWholeFramesAt15fps` | 通过 | 失败 ✅ |
| SP-04 | WebSearch 先打字再用鼠标、未知工具打字和鼠标交替（任务书 6.5；原来 WebSearch 只用鼠标、未知工具只打字） | `PerformerMappingTests/everyRowOfTheStateToAnimationTable` | 通过 | 失败 ✅ |
| C-033 | 表现层对时间差里的怪值（NaN / 无穷 / 天文数字）不再 `Int(x)` trap（数据层报告 C-033，由表现层修） | `ExtremeValuesTests/durationFormattersNeverTrapAndCapAtAboutThirtyYears` | 通过 | 失败 ✅ |
| SP-05 | App 启动时就在的会话：直接坐好、显示器从左到右依次开机（100 ms 一台）（原来所有人先是空闲姿势 + 黑屏，0.8 / 1.5 秒后一起硬切） | `MonitorTests/monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals` | 通过 | 失败 ✅ |
| MUT-1 | 检测器变异：check() 对第 1 类（.overlap）一律不报 | `TextAuditDetectorTests/class1OverlappingTextIsCaught` | 通过 | 失败 ✅ |
| MUT-2 | 检测器变异：check() 对第 2 类（.clipped）一律不报 | `TextAuditDetectorTests/class2` | 通过 | 失败 ✅ |
| MUT-3 | 检测器变异：check() 对第 3 类（.ellipsis）一律不报 | `TextAuditDetectorTests/class3LongTextWithoutAnEllipsisIsCaught` | 通过 | 失败 ✅ |
| MUT-4 | 检测器变异：check() 对第 4 类（.covers）一律不报 | `TextAuditDetectorTests/class4` | 通过 | 失败 ✅ |
| MUT-5 | 检测器变异：check() 对第 5 类（.fontSize）一律不报 | `TextAuditDetectorTests/class5FontsBelowNinePointsAreCaught` | 通过 | 失败 ✅ |
| MUT-6 | 检测器变异：check() 对第 6 类（.contrast）一律不报 | `TextAuditDetectorTests/class6LowContrastAgainstTheRealCanvasIsCaught` | 通过 | 失败 ✅ |
| MUT-7 | 检测器变异：check() 对第 7 类（.alignment）一律不报 | `TextAuditDetectorTests/class7TextNotOnWholeDevicePixelsIsCaught` | 通过 | 失败 ✅ |
| MUT-8 | 检测器变异：check() 对第 8 类（.pixelDigits）一律不报 | `TextAuditDetectorTests/class8` | 通过 | 失败 ✅ |
| C-032 | 应用层读桌面元数据走 FileIO 统一入口（原来直接 FileManager 读，指向 .key 的符号链接会被读到） | `DesktopMetaFileIOTests/readsLastFocusedThroughFileIOAndNeverOpensAKeyFileEvenThroughASymlink` | 通过 | 失败 ✅ |

## 撤销修复后测试失败的原文（每项前几行）

### TA-001 桌牌文字对比度（深色字，白天 / 夜里都 ≥ 4.5:1）

```
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "23:00", zoom → 3 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「重构登录模块」(plate.title) 对比度最差 3.79:1 < 4.5:1（846/952 个笔画像素不达标） @(271,757 130×21), [6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 62:11」(plate.status) 对比度最差 2.11:1 < 4.5:1（588/588 个笔画像素不达标） @(200,784 272×19), [6·对比度低于 4.5:1
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "12:00", zoom → 5 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 62:11」(plate.status) 对比度最差 4.29:1 < 4.5:1（588/588 个笔画像素不达标） @(534,1304 272×19), [6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 0:18 」(plate.status) 对比度最差 4.29:1 < 4.5:1（574/574 个笔画像素不达标） @(538,2064 264×19), [6·
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "12:00", zoom → 4 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 62:11」(plate.status) 对比度最差 4.29:1 < 4.5:1（588/588 个笔画像素不达标） @(312,1044 272×19), [6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 0:18 」(plate.status) 对比度最差 4.29:1 < 4.5:1（574/574 个笔画像素不达标） @(764,1044 264×19), [6·
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "12:00", zoom → 3 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 62:11」(plate.status) 对比度最差 4.29:1 < 4.5:1（588/588 个笔画像素不达标） @(200,784 272×19), [6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 0:18 」(plate.status) 对比度最差 4.29:1 < 4.5:1（574/574 个笔画像素不达标） @(540,784 264×19), [6·对比
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "23:00", zoom → 2 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「思考中」(plate.single) 对比度最差 3.79:1 < 4.5:1（306/306 个笔画像素不达标） @(195,511 57×20), [6·对比度低于 4.5:1] 办公室 ：「思考中」(plate.single) 对比度最差 3.79:1 < 4.5:1（306/306 个笔画像素不达标） @(419,511 57×20), [6·对比度低于 4.5:1] 办公室 ：「在读 OAut
✘ Test plateTextMeetsContrastAtAnyTimeOfDay(clock:zoom:) recorded an issue with 2 arguments clock → "23:00", zoom → 4 at TextAuditTests.swift:194:9: Expectation failed: (v → [[6·对比度低于 4.5:1] 办公室 ：「重构登录模块」(plate.title) 对比度最差 3.79:1 < 4.5:1（952/952 个笔画像素不达标） @(383,1017 130×21), [6·对比度低于 4.5:1] 办公室 ：「思考中 · 本轮 62:11」(plate.status) 对比度最差 2.11:1 < 4.5:1（588/588 个笔画像素不达标） @(312,1044 272×19), [6·对比度低于 4.5
✘ Test run with 1 test in 1 suite failed after 0.113 seconds with 11 issues.
```

### TA-002 桌牌高度 12 像素（原 10 像素放不下标题 + 状态两行）

```
✘ Test twoLinePlateTextStaysInsideThePlate(zoom:) recorded an issue with 1 argument zoom → 3 at TextAuditTests.swift:206:13: Expectation failed: (v → [[2·超出容器或被裁切] 办公室 ：「在改 LoginView.s」(plate.status) 超出了容器（笔画 (241,1222 191×22) 不在容器内部 (186,1194 300×48) 里） @(241,1222 191×22), [2·超出容器或被裁切] 办公室 ：「运行 git status 」(plate.status) 超出了容器（笔画 (888,1222 239×22) 不在容器内部 (858,1194 300×48) 里） @(888,1222 239×22), [
✘ Test twoLinePlateTextStaysInsideThePlate(zoom:) recorded an issue with 1 argument zoom → 3 at TextAuditTests.swift:206:13: Expectation failed: (v → [[2·超出容器或被裁切] 办公室 ：「在改 LoginView.s」(plate.status) 超出了容器（笔画 (241,1222 191×22) 不在容器内部 (186,1194 300×48) 里） @(241,1222 191×22), [2·超出容器或被裁切] 办公室 ：「运行 git status 」(plate.status) 超出了容器（笔画 (888,1222 239×22) 不在容器内部 (858,1194 300×48) 里） @(888,1222 239×22), [
✘ Test twoLinePlateTextStaysInsideThePlate(zoom:) recorded an issue with 1 argument zoom → 3 at TextAuditTests.swift:206:13: Expectation failed: (v → [[2·超出容器或被裁切] 办公室 ：「在改 LoginView.s」(plate.status) 超出了容器（笔画 (241,1222 191×22) 不在容器内部 (186,1194 300×48) 里） @(241,1222 191×22), [2·超出容器或被裁切] 办公室 ：「运行 git status 」(plate.status) 超出了容器（笔画 (888,1222 239×22) 不在容器内部 (858,1194 300×48) 里） @(888,1222 239×22), [
✘ Test run with 1 test in 1 suite failed after 0.095 seconds with 3 issues.
```

### TA-003 emoji 缩到 0.78 倍（原样大小的 emoji 字形比苹方行盒高）

```
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 10 at TextAuditTests.swift:219:9: Expectation failed: (emoji.y >= cjk.y - slack → false) && (emoji.y + emoji.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 10 at TextAuditTests.swift:220:9: Expectation failed: (mixed.y >= cjk.y - slack → false) && (mixed.y + mixed.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 11 at TextAuditTests.swift:219:9: Expectation failed: (emoji.y >= cjk.y - slack → false) && (emoji.y + emoji.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 11 at TextAuditTests.swift:220:9: Expectation failed: (mixed.y >= cjk.y - slack → false) && (mixed.y + mixed.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 12 at TextAuditTests.swift:219:9: Expectation failed: (emoji.y >= cjk.y - slack → false) && (emoji.y + emoji.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test emojiInkStaysInsideTheCJKInkRange(size:) recorded an issue with 1 argument size → 12 at TextAuditTests.swift:220:9: Expectation failed: (mixed.y >= cjk.y - slack → false) && (mixed.y + mixed.h <= cjk.y + cjk.h + slack → <not evaluated>)
✘ Test run with 1 test in 1 suite failed after 0.016 seconds with 8 issues.
```

### TA-004 睡着的 zzz 两个 z 之间留 1 像素

```
✘ Test sleepingBuddysTwoZsDoNotTouch() recorded an issue at TextAuditTests.swift:241:63: Expectation failed: (zs[a].rect.insetBy(-1).intersection(zs[b].rect) → IntRect(x: 77, y: 66, w: 1, h: 4)) == nil
✘ Test sleepingBuddysTwoZsDoNotTouch() recorded an issue at TextAuditTests.swift:242:9: Expectation failed: (r.audit().filter { $0.kind == .pixelDigits } → [[8·像素数字粘连] 办公室 ：像素字「z」和「z」贴在一起（间隔 < 1 像素） @(444,402 18×30)]).isEmpty → false
✘ Test run with 1 test in 1 suite failed after 0.017 seconds with 2 issues.
```

### TA-005 「今天还没人上班」牌子：更亮的字 + 画在桌椅上面（原来烘进背景、被桌椅盖住，字对比度 4.45:1）

```
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 2 at TextAuditTests.swift:253:13: Expectation failed: (r.audit() → [[6·对比度低于 4.5:1] 办公室 ：「今天还没人上班」(sign) 对比度最差 4.45:1 < 4.5:1（735/735 个笔画像素不达标） @(594,665 153×21)]).isEmpty → false
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 1 at TextAuditTests.swift:253:13: Expectation failed: (r.audit() → [[6·对比度低于 4.5:1] 办公室 ：「今天还没人上班」(sign) 对比度最差 4.45:1 < 4.5:1（735/735 个笔画像素不达标） @(595,667 153×21)]).isEmpty → false
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 5 at TextAuditTests.swift:258:13: Expectation failed: (face → 35) == (UInt16(Pal.dx("woodWalnut.base")) → 106)
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 4 at TextAuditTests.swift:253:13: Expectation failed: (r.audit() → [[6·对比度低于 4.5:1] 办公室 ：「今天还没人上班」(sign) 对比度最差 1.16:1 < 4.5:1（578/735 个笔画像素不达标） @(596,661 153×21)]).isEmpty → false
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 4 at TextAuditTests.swift:258:13: Expectation failed: (face → 32) == (UInt16(Pal.dx("woodWalnut.base")) → 106)
✘ Test emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom:) recorded an issue with 1 argument zoom → 3 at TextAuditTests.swift:253:13: Expectation failed: (r.audit() → [[6·对比度低于 4.5:1] 办公室 ：「今天还没人上班」(sign) 对比度最差 4.45:1 < 4.5:1（735/735 个笔画像素不达标） @(596,985 153×21)]).isEmpty → false
✘ Test run with 1 test in 1 suite failed after 0.043 seconds with 9 issues.
```

### TA-006a 悬停卡片不盖住被悬停那个人自己的头 / 屏幕 / 气泡

```
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 4 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 3 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 4 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 3 at TextAuditTests.swift:279:17: Expectation failed: (bad → [[4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的脸（16×16 像素） @(172,144 64×64), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的屏幕（24×5 像素） @(152,144 96×20), [4·盖住脸/屏幕/气泡/卡片] 办公室 ：悬停卡片盖住了座位 0 自己的
✘ Test run with 1 test in 1 suite failed after 0.200 seconds with 6 issues.
```

### TA-006b 被卡片盖住的桌牌文字收起来

```
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 66, y: 125, w: 15, h: 9)) == nil
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 89, y: 125, w: 46, h: 9)) == nil
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 158, y: 125, w: 21, h: 9)) == nil
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 158, y: 125, w: 21, h: 9)) == nil
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 208, y: 125, w: 33, h: 9)) == nil
✘ Test plateTextUnderTheHoverCardIsHidden() recorded an issue at TextAuditTests.swift:293:21: Expectation failed: (OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) → IntRect(x: 266, y: 125, w: 4, h: 9)) == nil
✘ Test run with 1 test in 1 suite failed after 0.087 seconds with 24 issues.
```

### TA-007 悬停卡片宽度上限按窗口宽反推（原来比窗口只多 1 像素，窄窗口里放不下）

```
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "很窄", wPt: 260, hPt: 700), zoom → 3 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "很窄", wPt: 260, hPt: 700), zoom → 3 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "很窄", wPt: 260, hPt: 700), zoom → 3 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test run with 1 test in 1 suite failed after 0.325 seconds with 3 issues.
```

### TA-008 悬停卡片兜底位置（窗口小到候选位置都放不下时，网格搜索一个不盖住人的地方）

```
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 3 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 4 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 3 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 4 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win:zoom:) recorded an issue with 2 arguments win → Window(name: "最小", wPt: 200, hPt: 220), zoom → 2 at TextAuditTests.swift:273:17: Expectation failed: (card → nil) != nil
✘ Test run with 1 test in 1 suite failed after 0.178 seconds with 6 issues.
```

### TA-009 实际缩放按窗口宽和高夹到「至少放得下一个整工位」

```
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:301:9: Expectation failed: (OfficeLayout.effectiveZoom(setting: 5, contentW: 200, contentH: 220, maxSeat: 3, allowOne: true) → 3) == 2
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:303:9: Expectation failed: (OfficeLayout.effectiveZoom(setting: 5, contentW: 900, contentH: 260, maxSeat: 3, allowOne: true) → 5) == 3
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:311:13: Expectation failed: (Double(z) * Double(Metrics.cellW) <= Double(w) → true) && (Double(z) * Double(Metrics.cellH + Metrics.plateH) <= Double(h) → false)
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:311:13: Expectation failed: (Double(z) * Double(Metrics.cellW) <= Double(w) → true) && (Double(z) * Double(Metrics.cellH + Metrics.plateH) <= Double(h) → false)
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:311:13: Expectation failed: (Double(z) * Double(Metrics.cellW) <= Double(w) → true) && (Double(z) * Double(Metrics.cellH + Metrics.plateH) <= Double(h) → false)
✘ Test zoomIsClampedSoAtLeastOneWholeSeatFits() recorded an issue at TextAuditTests.swift:311:13: Expectation failed: (Double(z) * Double(Metrics.cellW) <= Double(w) → true) && (Double(z) * Double(Metrics.cellH + Metrics.plateH) <= Double(h) → false)
✘ Test run with 1 test in 1 suite failed after 0.008 seconds with 135 issues.
```

### TA-010 空标题 / 全空白标题显示占位文字

```
✘ Test blankTitlesGetAPlaceholderOnPlatesAndCards() recorded an issue at TextAuditTests.swift:317:9: Expectation failed: (PlateCopy.displayTitle("") → "") == "（没有标题）"
✘ Test blankTitlesGetAPlaceholderOnPlatesAndCards() recorded an issue at TextAuditTests.swift:318:9: Expectation failed: (PlateCopy.displayTitle("  \n\t") → "
✘ Test blankTitlesGetAPlaceholderOnPlatesAndCards() recorded an issue at TextAuditTests.swift:323:9: Expectation failed: titles.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
✘ Test run with 1 test in 1 suite failed after 0.037 seconds with 3 issues.
```

### TA-011 审计工具自身：负的设备像素坐标向下取整（原来向零取整，读错画布行 → 看不见的桌牌被误报对比度）

```
✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → 0) == (want → -1)
✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → 0) == (want → -1)
✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → -1) == (want → -2)
✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → -1) == (want → -2)
✘ Test floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() recorded an issue at TextAuditTests.swift:143:13: Expectation failed: (TextAudit.floorDiv(a, b) → -27) == (want → -28)
✘ Test run with 2 tests in 2 suites failed after 9.488 seconds with 6 issues.
```

### TA-012 「其他 MCP」屏幕的 server 首字母：4×6 像素字体补上 A–Z（原来只有数字和 M / K，其余落到「?」）

```
✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:21:13: Expectation failed: (PixelFont.small → PixelFont(name: "4x6", height: 6, glyphs: ["-": ["....", "....", "####", "....", "....", "...."], "/": ["...#", "..#.", "..#.", ".#..", ".#..", "#..."], "?": [".##.", "#..#", "..#.", ".#..", "....", ".#.."], ":": ["#", ".", ".", "#", ".", "."], "2": [".##.", 
✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:23:13: Expectation failed: (rows.count → 0) == 6
✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:24:13: Expectation failed: (Set(rows.map(\.count)).count → 0) == 1
✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:25:13: Expectation failed: (rows.joined() → "").contains("#")
✘ Test theMcpAppScreenNeverFallsBackToThePlaceholderGlyph() recorded an issue at ScreenContentTests.swift:44:13: Expectation failed: (bad → [PixelKit.PixelFont.DrawRecord(font: "4x6", text: "N", rect: PixelKit.IntRect(x: 10, y: 5, w: 4, h: 6), container: Optional(PixelKit.IntRect(x: 0, y: 0, w: 24, h: 15)), missingGlyph: true, spacing: 1, pixels: [PixelKit.PixelFont.DrawRecord.Pixel(x: 11, y: 5, i
✘ Test theSmallPixelFontDrawsEveryLatinCapital() recorded an issue at ScreenContentTests.swift:21:13: Expectation failed: (PixelFont.small → PixelFont(name: "4x6", height: 6, glyphs: ["-": ["....", "....", "####", "....", "....", "...."], "/": ["...#", "..#.", "..#.", ".#..", ".#..", "#..."], "?": [".##.", "#..#", "..#.", ".#..", "....", ".#.."], ":": ["#", ".", ".", "#", ".", "."], "2": [".##.", 
✘ Test run with 2 tests in 1 suite failed after 0.020 seconds with 102 issues.
```

### TA-013 Bash 长任务的进度条移到屏幕第 5–6 行（原来在第 12–13 行，被人的头挡住）

```
✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }
✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }
✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }
✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }
✘ Test theLongBashProgressBarIsAboveTheRowsTheHeadHides() recorded an issue at ScreenContentTests.swift:56:13: Expectation failed: barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }
✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 5 issues.
```

### SP-01 显示器关机：人离开后屏幕内容用 Bayer 抖动倒放 300 ms 熄灭（原来一帧硬切成黑屏；任务书 5.5 / 6.5 / 6.6）

```
✘ Test theMonitorFadesOutOver300msInsteadOfCuttingToBlack() recorded an issue at MonitorTests.swift:60:9: Expectation failed: ((after.first?.lit ?? 0) → 0) > (Int(Double(before.max() ?? 0) * 0.6) → 235)
✘ Test theMonitorFadesOutOver300msInsteadOfCuttingToBlack() recorded an issue at MonitorTests.swift:70:9: Expectation failed: (levels.count → 1) >= 5
✘ Test run with 1 test in 1 suite failed after 0.054 seconds with 2 issues.
```

### SP-02 指示灯 3 个色阶呼吸：待机灯 灭→半亮→亮→半亮（4 s），等待琥珀灯 暗→亮→更亮→亮（1.25 s = 0.8 Hz）（原来待机灯 2 秒亮 2 秒灭、等待灯是固定色）

```
✘ Test theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz() recorded an issue at MonitorTests.swift:137:9: Expectation failed: (Set(seq.map(\.name)) → ["led.wait"]) == (["led.wait.lo", "led.wait", "led.wait.hi"] → ["led.wait", "led.wait.lo", "led.wait.hi"])
✘ Test theStandbyLightBreathesThroughThreeLevelsSlowly() recorded an issue at MonitorTests.swift:128:9: Expectation failed: (Set(seq.map(\.name)) → ["led.on", "led.off"]) == ["led.off", "led.mid", "led.on"]
✘ Test theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz() recorded an issue at MonitorTests.swift:139:9: Expectation failed: (tr.count >= 30 → false) && (tr.count <= 34 → <not evaluated>)
✘ Test theStandbyLightBreathesThroughThreeLevelsSlowly() recorded an issue at MonitorTests.swift:130:23: Expectation failed: (!(t.from == "led.off" && t.to == "led.on") → false) && (!(t.from == "led.on" && t.to == "led.off") → <not evaluated>)
✘ Test theStandbyLightBreathesThroughThreeLevelsSlowly() recorded an issue at MonitorTests.swift:130:23: Expectation failed: (!(t.from == "led.off" && t.to == "led.on") → true) && (!(t.from == "led.on" && t.to == "led.off") → false)
✘ Test theStandbyLightBreathesThroughThreeLevelsSlowly() recorded an issue at MonitorTests.swift:130:23: Expectation failed: (!(t.from == "led.off" && t.to == "led.on") → false) && (!(t.from == "led.on" && t.to == "led.off") → <not evaluated>)
```

### SP-03 连续滚动的屏幕（文档 / 日志 / 终端）按整数个渲染帧一步（原来文档 150 ms、日志 300 ms 一步，在 15 fps 下是 2、3、2、3 帧的不均匀节奏）

```
✘ Test documentAndLogScrollingStepsAreWholeFramesAt15fps() recorded an issue at ScreenContentTests.swift:88:13: Expectation failed: runs.allSatisfy { $0 == frames }
✘ Test documentAndLogScrollingStepsAreWholeFramesAt15fps() recorded an issue at ScreenContentTests.swift:91:13: Expectation failed: jittered.allSatisfy { $0 == frames }
✘ Test documentAndLogScrollingStepsAreWholeFramesAt15fps() recorded an issue at ScreenContentTests.swift:88:13: Expectation failed: runs.allSatisfy { $0 == frames }
✘ Test documentAndLogScrollingStepsAreWholeFramesAt15fps() recorded an issue at ScreenContentTests.swift:91:13: Expectation failed: jittered.allSatisfy { $0 == frames }
✘ Test run with 1 test in 1 suite failed after 0.070 seconds with 4 issues.
```

### SP-04 WebSearch 先打字再用鼠标、未知工具打字和鼠标交替（任务书 6.5；原来 WebSearch 只用鼠标、未知工具只打字）

```
✘ Test everyRowOfTheStateToAnimationTable() recorded an issue at PerformerMappingTests.swift:81:13: Expectation failed: (p.targetPose(now: now, time: row.elapsed) → .mouse) == (row.pose → .typing)
✘ Test everyRowOfTheStateToAnimationTable() recorded an issue at PerformerMappingTests.swift:81:13: Expectation failed: (p.targetPose(now: now, time: row.elapsed) → .typing) == (row.pose → .mouse)
✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 2 issues.
```

### C-033 表现层对时间差里的怪值（NaN / 无穷 / 天文数字）不再 `Int(x)` trap（数据层报告 C-033，由表现层修）

```
```

### SP-05 App 启动时就在的会话：直接坐好、显示器从左到右依次开机（100 ms 一台）（原来所有人先是空闲姿势 + 黑屏，0.8 / 1.5 秒后一起硬切）

```
✘ Test monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() recorded an issue at MonitorTests.swift:108:9: Expectation failed: ((firstLit[0] ?? 9) → 0.5666666666666667) < 0.15
✘ Test monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() recorded an issue at MonitorTests.swift:109:76: Expectation failed: (abs((b - a) - 0.1) → 0.1666666666666666) < 0.045
✘ Test monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() recorded an issue at MonitorTests.swift:109:76: Expectation failed: (abs((b - a) - 0.1) → 0.1) < 0.045
✘ Test monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals() recorded an issue at MonitorTests.swift:109:76: Expectation failed: (abs((b - a) - 0.1) → 0.1) < 0.045
✘ Test run with 1 test in 1 suite failed after 0.028 seconds with 4 issues.
```

### MUT-1 检测器变异：check() 对第 1 类（.overlap）一律不报

```
✘ Test class1OverlappingTextIsCaught() recorded an issue at TextAuditTests.swift:58:9: Expectation failed: (kinds(TextAudit.check(r.input([a, onTop]))) → []).contains(.overlap)
✘ Test run with 1 test in 1 suite failed after 0.022 seconds with 1 issue.
```

### MUT-2 检测器变异：check() 对第 2 类（.clipped）一律不报

```
✘ Test class2HoverCardThatIsNotWhollyInsideTheWindowIsCaught() recorded an issue at TextAuditTests.swift:75:9: Expectation failed: (kinds(TextAudit.check(r.input([t]))) → []).contains(.clipped)
✘ Test class2TextOutsideItsContainerOrTheWindowIsCaught() recorded an issue at TextAuditTests.swift:65:9: Expectation failed: (kinds(TextAudit.check(r.input([tooNarrow]))) → [BuddyStage.TextAudit.Kind.ellipsis]).contains(.clipped)
✘ Test class2TextOutsideItsContainerOrTheWindowIsCaught() recorded an issue at TextAuditTests.swift:67:9: Expectation failed: (kinds(TextAudit.check(r.input([offWindow]))) → []).contains(.clipped)
✘ Test run with 2 tests in 1 suite failed after 0.099 seconds with 3 issues.
```

### MUT-3 检测器变异：check() 对第 3 类（.ellipsis）一律不报

```
✘ Test class3LongTextWithoutAnEllipsisIsCaught() recorded an issue at TextAuditTests.swift:82:9: Expectation failed: (kinds(TextAudit.check(r.input([noEllipsis]))) → [BuddyStage.TextAudit.Kind.clipped]).contains(.ellipsis)
✘ Test run with 1 test in 1 suite failed after 0.040 seconds with 1 issue.
```

### MUT-4 检测器变异：check() 对第 4 类（.covers）一律不报

```
✘ Test class4TheHoverCardMustNotCoverItsOwnFaceButMayCoverANeighbours() recorded an issue at TextAuditTests.swift:106:9: Expectation failed: (kinds(TextAudit.check(r.input(regions: [face, ownCard]))) → []).contains(.covers)
✘ Test class4LabelsThatCoverAFaceScreenBubbleOrCardAreCaught() recorded an issue at TextAuditTests.swift:92:13: Expectation failed: (kinds(TextAudit.check(r.input([plate], regions: [hit]))) → []).contains(.covers)
✘ Test class4LabelsThatCoverAFaceScreenBubbleOrCardAreCaught() recorded an issue at TextAuditTests.swift:92:13: Expectation failed: (kinds(TextAudit.check(r.input([plate], regions: [hit]))) → []).contains(.covers)
✘ Test class4LabelsThatCoverAFaceScreenBubbleOrCardAreCaught() recorded an issue at TextAuditTests.swift:92:13: Expectation failed: (kinds(TextAudit.check(r.input([plate], regions: [hit]))) → []).contains(.covers)
✘ Test class4LabelsThatCoverAFaceScreenBubbleOrCardAreCaught() recorded an issue at TextAuditTests.swift:92:13: Expectation failed: (kinds(TextAudit.check(r.input([plate], regions: [hit]))) → []).contains(.covers)
✘ Test run with 2 tests in 1 suite failed after 0.011 seconds with 5 issues.
```

### MUT-5 检测器变异：check() 对第 5 类（.fontSize）一律不报

```
✘ Test class5FontsBelowNinePointsAreCaught() recorded an issue at TextAuditTests.swift:114:9: Expectation failed: (kinds(TextAudit.check(r.input([small]))) → []).contains(.fontSize)
✘ Test run with 1 test in 1 suite failed after 0.008 seconds with 1 issue.
```

### MUT-6 检测器变异：check() 对第 6 类（.contrast）一律不报

```
✘ Test class6LowContrastAgainstTheRealCanvasIsCaught() recorded an issue at TextAuditTests.swift:122:9: Expectation failed: (kinds(TextAudit.check(r.input([faint]))) → []).contains(.contrast)
✘ Test run with 1 test in 1 suite failed after 0.008 seconds with 1 issue.
```

### MUT-7 检测器变异：check() 对第 7 类（.alignment）一律不报

```
✘ Test class7TextNotOnWholeDevicePixelsIsCaught() recorded an issue at TextAuditTests.swift:134:9: Expectation failed: (kinds(TextAudit.check(off)) → []).contains(.alignment)
✘ Test run with 1 test in 1 suite failed after 0.008 seconds with 1 issue.
```

### MUT-8 检测器变异：check() 对第 8 类（.pixelDigits）一律不报

```
✘ Test class8PixelDigitsPaintedOverByLaterDrawingAreCaught() recorded an issue at TextAuditTests.swift:178:9: Expectation failed: (kinds(TextAudit.check(r.input(draws: d))) → []).contains(.pixelDigits)
✘ Test class8MissingGlyphsAndOverflowingContainersAreCaught() recorded an issue at TextAuditTests.swift:165:9: Expectation failed: (kinds(TextAudit.check(r.input(draws: missing))) → []).contains(.pixelDigits)
✘ Test class8PixelDigitsThatTouchAreCaught() recorded an issue at TextAuditTests.swift:154:9: Expectation failed: (kinds(TextAudit.check(r.input(draws: glued))) → []).contains(.pixelDigits)
✘ Test class8MissingGlyphsAndOverflowingContainersAreCaught() recorded an issue at TextAuditTests.swift:167:9: Expectation failed: (kinds(TextAudit.check(r.input(draws: tooWide))) → []).contains(.pixelDigits)
✘ Test run with 3 tests in 1 suite failed after 0.001 seconds with 4 issues.
```

### C-032 应用层读桌面元数据走 FileIO 统一入口（原来直接 FileManager 读，指向 .key 的符号链接会被读到）

```
✘ Test readsLastFocusedThroughFileIOAndNeverOpensAKeyFileEvenThroughASymlink() recorded an issue at DesktopMetaFileIOTests.swift:33:9: Expectation failed: log.paths.contains { $0.hasSuffix("local_a.json") }
✘ Test readsLastFocusedThroughFileIOAndNeverOpensAKeyFileEvenThroughASymlink() recorded an issue at DesktopMetaFileIOTests.swift:35:9: Expectation failed: (FileIO.forbiddenHits → 0) > (hitsBefore → 0)
✘ Test run with 1 test in 1 suite failed after 0.004 seconds with 2 issues.
```

