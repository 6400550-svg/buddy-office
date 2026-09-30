# 收尾前复查新发现的问题：修复前失败的原始输出

每一项都是**先写回归测试、在没有修复的代码上跑**得到的输出（只保留失败 / 通过的结果行，编译进度行去掉了）；修复后同一批测试全部通过（见 `QA/evidence/regression-final/summary.txt`）。
数据层 / 表现层 / 应用层的测试是在项目的隔离副本里对「撤销了修复」的代码跑的，项目本身没有为此改动。`hook-merge.py` 那两条的输出在文末。

## SP-06（规格追踪定稿抓到；等待类在错开推迟期间晚到）

```
✘ Test "5.6-13 某个 buddy 正在「错开」的等待期里，等待类状态也要立即插入（≤ 250 ms），并且中间不能闪出一帧过期的旧动作" recorded an issue at SpecTraceStageTests.swift:172:9: Expectation failed: ((waitingAt ?? 99) - 2.1 → 0.5666666666666669) <= (0.25 + 1.0 / 30 → 0.2833333333333333)
✘ Test "5.6-13 某个 buddy 正在「错开」的等待期里，等待类状态也要立即插入（≤ 250 ms），并且中间不能闪出一帧过期的旧动作" recorded an issue at SpecTraceStageTests.swift:173:9: Expectation failed: (staleFrames → 1) == 0
✘ Test "5.6-13 某个 buddy 正在「错开」的等待期里，等待类状态也要立即插入（≤ 250 ms），并且中间不能闪出一帧过期的旧动作" failed after 0.005 seconds with 2 issues.
✘ Suite SpecTraceStageTests failed after 0.006 seconds with 2 issues.
✘ Test run with 1 test in 1 suite failed after 0.006 seconds with 2 issues.
```

## R1a-01（quiet 的 busy 会话让 nextWake 停在过去 → 空转）

```
✘ Test "R1a-01 busy 又 quiet 的会话：nextWake 要么没有、要么在现在之后（不能让 SessionStore 5 ms 一次空转）" recorded an issue at ReviewRegressionTests.swift:27:13: Expectation failed: (wake == nil → false) || (wake! > h.now → false)
✘ Test "R1a-01 busy 又 quiet 的会话：nextWake 要么没有、要么在现在之后（不能让 SessionStore 5 ms 一次空转）" failed after 0.014 seconds with 6 issues.
✘ Test "R1a-01 不变量：会话在 busy / quiet / 等待 / 做完 / 打盹……任何时刻，nextWake 都不在过去" recorded an issue at ReviewRegressionTests.swift:43:9: Expectation failed: (bad → ["忙 +601.0：nextWake 在过去 527.0 秒", "忙 +900.0：nextWake 在过去 1427.0 秒", "忙 +4000.0：nextWake 在过去 5427.0 秒"]).isEmpty → false
✘ Test "R1a-01 不变量：会话在 busy / quiet / 等待 / 做完 / 打盹……任何时刻，nextWake 都不在过去" failed after 0.018 seconds with 1 issue.
✘ Suite StateRuleTests failed after 0.018 seconds with 7 issues.
✘ Test run with 2 tests in 1 suite failed after 0.018 seconds with 7 issues.
```

## R1b-01 / 02 / 03 / 04（错开推迟期间变回去 / 桌牌 1.0 s 被数字绕过 / 隐私模式漏 MCP 名 / 气泡没有最短停留）

```
✘ Test "R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留" recorded an issue at ReviewRegressionStageTests.swift:77:9: Expectation failed: (m("等你批准 Bash · 12 秒") → "等你批准 Bash · # 秒") == (m("等你批准 Bash · 3 分钟") → "等你批准 Bash · # 分钟")
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.16666666666666718) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.13333333333333375) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.3) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.29999999999999993) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.13333333333333286) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.16666666666666607) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留" recorded an issue at ReviewRegressionStageTests.swift:86:9: Expectation failed: (m("在搜 \"swift 5\"") → "在搜 "swift #"") != (m("在搜 \"swift 6\"") → "在搜 "swift #"")
✘ Test "R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留" recorded an issue at ReviewRegressionStageTests.swift:87:9: Expectation failed: (m("在读 v1") → "在读 v#") != (m("在读 v2") → "在读 v#")
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.3000000000000005) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留" recorded an issue at ReviewRegressionStageTests.swift:90:9: Expectation failed: (m("运行中 sleep 5 · 0:09") → "运行中 sleep # · #") != (m("运行中 sleep 6 · 0:09") → "运行中 sleep # · #")
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.30000000000000093) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.30000000000000004) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-03 隐私模式：MCP server 名和未知工具名也不能出现在桌牌动作 / 状态行里（任务书 6.3：隐私模式下隐藏全部细节）" failed after 0.002 seconds with 8 issues.
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.29999999999999893) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-02 数字掩码只抹「计数器位置」：· 后面的计时、重试中 a/m、×N、派了 N 个帮手、打盹 N 分钟；文件名里的数字保留" failed after 0.002 seconds with 7 issues.
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" recorded an issue at ReviewRegressionStageTests.swift:134:44: Expectation failed: (times[i] - times[i - 1] → 0.33333333333333215) >= (0.8 - 1.0 / 30 - 1e-9 → 0.7666666656666667)
✘ Test "R1b-04 工具节奏驱动的气泡也有 0.8 秒最短停留：Grep / Read 每 0.3 秒交替时，放大镜气泡不能跟着一闪一闪" failed after 0.002 seconds with 18 issues.
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.13333333333333333) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.16666666666666663) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.13333333333333336) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.1333333333333333) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" recorded an issue at ReviewRegressionStageTests.swift:55:48: Expectation failed: (times[i] - times[i - 1] → 0.16666666666666674) >= (1.0 - 1.0 / 30 - 1e-9 → 0.9666666656666667)
✘ Test "R1b-01 错开推迟期间活动变回已套用的同一种类：推迟记录作废，不能套用推迟开始时存下的过期快照" recorded an issue at ReviewRegressionStageTests.swift:30:9: Expectation failed: (sawEdit → [2.200000000000002]).isEmpty → false
✘ Test "R1b-01 错开推迟期间活动变回已套用的同一种类：推迟记录作废，不能套用推迟开始时存下的过期快照" recorded an issue at ReviewRegressionStageTests.swift:31:9: Expectation failed: (typing → [2.200000000000002, 2.233333333333335, 2.2666666666666684, 2.3000000000000016, 2.333333333333335, 2.366666666666668, 2.4000000000000012, 2.4333333333333345, 2.4666666666666677, 2.500000000000001, 2.533333333333334, 2.5666666666666673, 2.6000000000000005, 2.63333333333333
✘ Test "R1b-01 错开推迟期间活动变回已套用的同一种类：推迟记录作废，不能套用推迟开始时存下的过期快照" failed after 0.004 seconds with 2 issues.
✘ Test "R1b-02 桌牌 1.0 秒最短停留不能被文件名 / 命令 / 搜索词里的数字绕过（part1.txt → part2.txt 也是换了动作）" failed after 0.006 seconds with 100 issues.
✘ Suite ReviewRegressionStageTests failed after 0.006 seconds with 135 issues.
✘ Test run with 7 tests in 1 suite failed after 0.006 seconds with 135 issues.
```

## R1b-05 / 06（隐私开关刚变 / 只有不可见字符的标题）

```
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" recorded an issue at ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "​‌‍") == (placeholder → "（没有标题）")
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" recorded an issue at ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "﻿") == (placeholder → "（没有标题）")
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" recorded an issue at ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "⁠") == (placeholder → "（没有标题）")
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" recorded an issue at ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "‮‬") == (placeholder → "（没有标题）")
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" recorded an issue at ReviewRegressionStageTests.swift:184:13: Expectation failed: (PlateCopy.displayTitle(t) → "") == (placeholder → "（没有标题）")
✘ Test "R1b-06 只有零宽 / 控制 / 方向字符的标题也算空标题：显示占位文字，不画空桌牌" failed after 0.001 seconds with 5 issues.
✘ Test "R1b-05 打开隐私模式：桌牌动作文字当场就隐藏，不等 1.0 秒最短停留（刚换过字也一样）" recorded an issue at ReviewRegressionStageTests.swift:173:9: Expectation failed: (afterToggle.first?.1 → "在改 Payroll.swift") == "在改代码"
✘ Test "R1b-05 打开隐私模式：桌牌动作文字当场就隐藏，不等 1.0 秒最短停留（刚换过字也一样）" recorded an issue at ReviewRegressionStageTests.swift:174:9: Expectation failed: afterToggle.allSatisfy { !$0.1.contains("Payroll") && !$0.1.contains("Salaries") }
✘ Test "R1b-05 打开隐私模式：桌牌动作文字当场就隐藏，不等 1.0 秒最短停留（刚换过字也一样）" failed after 0.001 seconds with 2 issues.
✘ Suite ReviewRegressionStageTests failed after 0.002 seconds with 7 issues.
✘ Test run with 2 tests in 1 suite failed after 0.002 seconds with 7 issues.
```

## R2-001 / 002 / 003 / 004（缩放后图像层不变 / 提示卡先闪在终点 / 合并提醒里 blocked 被撤 / 被节流的提醒整段丢弃）

```
✘ Test "R2-003 两个会话先后「做完了要你处理」（blocked）：合并出来的「N 位同事有事找你」要留着，不能在同一次判定里被撤掉" recorded an issue at ReviewRegressionAppTests.swift:102:9: Expectation failed: !(cleared → <not evaluated>)
✘ Test "R2-004 「等你」提醒被 20 秒节流挡住之后：这段等待没有提醒过，节流窗口一过、还在等就补发一条（不再重复）" recorded an issue at ReviewRegressionAppTests.swift:118:9: Expectation failed: (posts.count → 1) == 2
✘ Test "R2-001 PixelView：画布没变、只有缩放变了（局部重绘的场景知道「没变」）时，图像层也要跟着新缩放变大小" recorded an issue at ReviewRegressionAppTests.swift:29:9: Expectation failed: (imageWidth() → 80.0) == (40 → 40.0)
✘ Test "R2-001 PixelView：画布没变、只有缩放变了（局部重绘的场景知道「没变」）时，图像层也要跟着新缩放变大小" recorded an issue at ReviewRegressionAppTests.swift:31:9: Expectation failed: (imageWidth() → 80.0) == (120 → 120.0)
✘ Test "R2-001 PixelView：画布没变、只有缩放变了（局部重绘的场景知道「没变」）时，图像层也要跟着新缩放变大小" recorded an issue at ReviewRegressionAppTests.swift:38:9: Expectation failed: (pv2.layer?.sublayers?.first?.frame.width → 80.0) == (40 → 40.0)
✘ Test "R2-004 「等你」提醒被 20 秒节流挡住之后：这段等待没有提醒过，节流窗口一过、还在等就补发一条（不再重复）" failed after 0.323 seconds with 1 issue.
✘ Test "R2-003 两个会话先后「做完了要你处理」（blocked）：合并出来的「N 位同事有事找你」要留着，不能在同一次判定里被撤掉" failed after 0.322 seconds with 1 issue.
✘ Test "R2-001 真实的小鱼缸控制器：运行中把缩放从 2 改成 1，下一拍图像层就是新大小（不是等画布下一次变化）" recorded an issue at ReviewRegressionAppTests.swift:53:9: Expectation failed: (imageW → 304.0) == (viewW → 152.0)
✘ Test "R2-001 PixelView：画布没变、只有缩放变了（局部重绘的场景知道「没变」）时，图像层也要跟着新缩放变大小" failed after 0.432 seconds with 3 issues.
✘ Test "R2-001 真实的小鱼缸控制器：运行中把缩放从 2 改成 1，下一拍图像层就是新大小（不是等画布下一次变化）" failed after 0.433 seconds with 1 issue.
✘ Test "R2-002 提示卡出现：orderFront 的那一刻面板已经在屏幕外的起点，不能先出现在终点位置再跳走；新提示卡到来时已有的不被拽回终点" recorded an issue at ReviewRegressionAppTests.swift:68:9: Expectation failed: ((atOrderFront.first?.minX ?? 0) → 1220.0) >= (vf.maxX → 1408.0)
✘ Test "R2-002 提示卡出现：orderFront 的那一刻面板已经在屏幕外的起点，不能先出现在终点位置再跳走；新提示卡到来时已有的不被拽回终点" recorded an issue at ReviewRegressionAppTests.swift:76:9: Expectation failed: ((b?.minX ?? 0) → 1274.0) >= (vf.maxX → 1408.0)
✘ Test "R2-002 提示卡出现：orderFront 的那一刻面板已经在屏幕外的起点，不能先出现在终点位置再跳走；新提示卡到来时已有的不被拽回终点" failed after 0.464 seconds with 2 issues.
✘ Suite ReviewRegressionAppTests failed after 0.464 seconds with 8 issues.
✘ Test run with 5 tests in 1 suite failed after 0.465 seconds with 8 issues.
```

## R2-006 / 007 / 008 / 015（隐私诊断标题 / 测试进程日志开关 / DesktopMeta 不认 --data-root / 空详情文案）

```
✘ Test "R2-015 工具详情为空（hook 行被截断走降级解析时会出现）：桌牌文案不能是「在读 」「在找 ""」「运行 」这种带尾随空格 / 空引号的半截话" recorded an issue at ReviewRegressionStageTests.swift:207:13: Expectation failed: (t == want → false) || ((name == "NotebookEdit" && !t.hasSuffix(" ")) → false)
✘ Test "R2-007 测试宿主进程的 --test-bundle-path 不算开发开关：测试里 DebugTools.enabled 必须是 false（不然被测代码里加一行 DebugTools.log 就会往用户真实的日志文件里写）" recorded an issue at ReviewRegressionAppTests.swift:146:9: Expectation failed: !(DebugTools.devFlagsPresent(["/x/swiftpm-testing-helper", "--test-bundle-path", "/x/BuddyOfficePackageTests.xctest/Contents/MacOS/BuddyOfficePackageTests"]) → true)
✘ Test "R2-015 工具详情为空（hook 行被截断走降级解析时会出现）：桌牌文案不能是「在读 」「在找 ""」「运行 」这种带尾随空格 / 空引号的半截话" recorded an issue at ReviewRegressionStageTests.swift:208:13: Expectation failed: (!t.hasSuffix(" ") → false) && (!t.contains("\"\"") → <not evaluated>)
✘ Test "R2-007 测试宿主进程的 --test-bundle-path 不算开发开关：测试里 DebugTools.enabled 必须是 false（不然被测代码里加一行 DebugTools.log 就会往用户真实的日志文件里写）" recorded an issue at ReviewRegressionAppTests.swift:147:9: Expectation failed: !(DebugTools.enabled → true → true)
✘ Test "R2-015 工具详情为空（hook 行被截断走降级解析时会出现）：桌牌文案不能是「在读 」「在找 ""」「运行 」这种带尾随空格 / 空引号的半截话" recorded an issue at ReviewRegressionStageTests.swift:208:13: Expectation failed: (!t.hasSuffix(" ") → true) && (!t.contains("\"\"") → false)
✘ Test "R2-006 隐私模式：「数据源诊断」文字和「测试深链」回执里不显示会话标题（共享屏幕时打开设置页不会露标题）" recorded an issue at ReviewRegressionAppTests.swift:135:9: Expectation failed: (!hidden.contains("秘密账号") → false) && (hidden.contains("· 会话　pid 42") → <not evaluated>)
✘ Test "R2-007 测试宿主进程的 --test-bundle-path 不算开发开关：测试里 DebugTools.enabled 必须是 false（不然被测代码里加一行 DebugTools.log 就会往用户真实的日志文件里写）" failed after 0.002 seconds with 2 issues.
✘ Test "R2-006 隐私模式：「数据源诊断」文字和「测试深链」回执里不显示会话标题（共享屏幕时打开设置页不会露标题）" recorded an issue at ReviewRegressionAppTests.swift:138:9: Expectation failed: (AppModel.deepLinkReceipt(title: "帮我转账到 6222-秘密账号", privacy: true) → "已向「帮我转账到 6222-秘密账号」发出深链跳转；2.5 秒后如果没生效会自动改为直接打开 Claude。") == "已向「会话」发出深链跳转；2.5 秒后如果没生效会自动改为直接打开 Claude。"
✘ Test "R2-006 隐私模式：「数据源诊断」文字和「测试深链」回执里不显示会话标题（共享屏幕时打开设置页不会露标题）" failed after 0.002 seconds with 2 issues.
✘ Test "R2-015 工具详情为空（hook 行被截断走降级解析时会出现）：桌牌文案不能是「在读 」「在找 ""」「运行 」这种带尾随空格 / 空引号的半截话" failed after 0.003 seconds with 18 issues.
✘ Suite ReviewRegressionStageTests failed after 0.003 seconds with 18 issues.
✘ Test "R2-008 用 --data-root 起的开发副本：应用层读桌面元数据的根目录也跟着换成假 home（不再读真实的桌面会话元数据）" recorded an issue at ReviewRegressionAppTests.swift:164:9: Expectation failed: (DesktopMeta.baseOverride → nil) == "/x/fake-home/Library/Application Support/Claude/claude-code-sessions"
✘ Test "R2-008 用 --data-root 起的开发副本：应用层读桌面元数据的根目录也跟着换成假 home（不再读真实的桌面会话元数据）" failed after 0.006 seconds with 1 issue.
✘ Suite ReviewRegressionAppTests failed after 0.006 seconds with 5 issues.
✘ Test run with 4 tests in 2 suites failed after 0.006 seconds with 23 issues.
```

## R2-014（时钟往回拨压住提醒）

```
✘ Test "R2-014 系统时钟被往回拨（手动改时间 / NTP 校正）：节流记录里「来自未来」的时间当作已过期，新的一段等待照常提醒" recorded an issue at ReviewRegressionAppTests.swift:182:9: Expectation failed: (posts.count → 1) == 2
✘ Test "R2-014 系统时钟被往回拨（手动改时间 / NTP 校正）：节流记录里「来自未来」的时间当作已过期，新的一段等待照常提醒" failed after 0.021 seconds with 1 issue.
✘ Suite ReviewRegressionAppTests failed after 0.021 seconds with 1 issue.
✘ Test run with 1 test in 1 suite failed after 0.021 seconds with 1 issue.
```

## R2-016 / R2-017（拖窗口时每步新建 IOSurface / 办公室窗口没关窗口动画）

在项目的隔离副本里撤销两处修复（`PixelView.bucket` 改回 `n`、去掉 `w.animationBehavior = .none`），只跑这四个测试（编译进度行去掉了）；修复后同一批测试全部通过。

```
✘ Test "R2-017 办公室窗口（普通 NSWindow）也关掉 AppKit 的窗口出现 / 消失动画：快速 show / hide 时动画线程不会一路涨（B-010 的同类）" recorded an issue at ReviewRegressionAppTests.swift:269:9: Expectation failed: (wc.window?.animationBehavior → NSWindowAnimationBehavior(rawValue: 0)) == (NSWindow.AnimationBehavior.none → NSWindowAnimationBehavior(rawValue: 2))
✘ Test "R2-016 拖窗口边缘（视口宽度一步一步变）：IOSurface 只在跨 64 像素的桶时才重建，不是每一步都新建一组" recorded an issue at ReviewRegressionAppTests.swift:202:9: Expectation failed: (seen.count > 0 → true) && (seen.count <= 6 → false)
✘ Test "R2-016 分桶的 surface 渲染出来和「按缩放放大的画布」逐像素一致：contentsRect 裁得正好，不偏一个像素、边上没有混色" recorded an issue at ReviewRegressionAppTests.swift:243:9: Expectation failed: (surf.width > w → false) && (surf.height > h → <not evaluated>)
✘ Test "R2-016 用桶（比视口大）的 surface 时，显示出来的部分正好是视口：contentsRect 是 视口 / surface，图层尺寸 = 视口 × 缩放，左上角的像素就是画布的像素" recorded an issue at ReviewRegressionAppTests.swift:217:9: Expectation failed: (sw >= 70 && sh >= 50 && Int(sw) % 64 == 0 → false) && (Int(sh) % 64 == 0 → <not evaluated>)
✘ Test "R2-016 用桶（比视口大）的 surface 时，显示出来的部分正好是视口：contentsRect 是 视口 / surface，图层尺寸 = 视口 × 缩放，左上角的像素就是画布的像素" recorded an issue at ReviewRegressionAppTests.swift:229:9: Expectation failed: ((layer2?.contents as? IOSurface).map { $0.width == surf.width && $0.height == surf.height } → false) == true
✘ Test "R2-016 用桶（比视口大）的 surface 时，显示出来的部分正好是视口：contentsRect 是 视口 / surface，图层尺寸 = 视口 × 缩放，左上角的像素就是画布的像素" recorded an issue at ReviewRegressionAppTests.swift:230:9: Expectation failed: (abs((layer2?.contentsRect.width ?? 0) - 100 / sw) < 1e-9 → false) && (abs((layer2?.contentsRect.height ?? 0) - 60 / sh) < 1e-9 …
✘ Suite ReviewRegressionAppTests failed after 0.092 seconds with 6 issues.
✘ Test run with 4 tests in 1 suite failed after 0.092 seconds with 6 issues.
```

另外对「逐像素一致」那条做了两个变异（`contentsRect` 改成整张 surface、`contentsRect` 的 x 偏一个像素），两个都被它抓到（`min(up, down) → 3500`，即每个方块都不对）。

## SAN-01（text-audit 像素字审计钩子的数据竞争）

原始 ASan 报告、撤销修复后的三次 ASan 崩溃、TSan 报告、修复后的通过记录在 `QA/evidence/san01/`。撤销修复（`withDraws` 改回 `box.value`、`draw` 改回不加锁读 `auditEnabled`）之后，`san01` 那一条测试：

```
Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range      （ASan 构建，连跑 3 次，3 次都是；进程退出码 1）
TSan：WARNING: ThreadSanitizer: data race ×4、Swift access race ×2 …          （5 处报告：setAuditSink 写 auditEnabled vs draw 读；withDraws 读 box.value vs sink 里的 append）
```

修复后：ASan 连跑 3 次退出码 0；TSan 连跑 2 次 0 报告，`✔ Test run with 1 test in 1 suite passed`。

## SAN-02（OpenAudit 测试被并行套件的 open 污染）

撤销修复（`OpenAudit.record` 不看范围）之后只跑 `openAudit` 那几条测试；真实发生的那一次红灯（最后一次完整回归第二遍）在 `QA/evidence/san02/failure-in-regression-run2.txt`。

```
✘ Test "open 审计：别的线程同时在打开别处的文件（并行跑的其它测试）时，限定了范围的审计不受影响，不设范围的会被记进来" recorded an issue at OpenAuditTests.swift:114:9: Expectation failed: (scoped.ok && !scoped.rows.contains { $0.name == "其他位置的文件" } → false) && …
✘ Test run with 5 tests in 1 suite failed after 0.619 seconds with 1 issue.
```

修复后：`✔ Test run with 6 tests in 2 suites passed`（含 SAN-01 那一条）。

## R3a-01 / R3a-02 / R3b-01 / R3b-02 / R3c-01 / R3c-02（最后一轮独立复查 R3 找出的 6 个 P2）

逐个撤销修复（或让保护失效），只跑对应的回归测试；完整输出在 `QA/evidence/r3/fail-before-summary.txt`，修复后的 160 个相关测试全部通过在 `QA/evidence/r3/after-fix-tests.log`。

```
R3a-02 撤销「元数据未来时间戳夹到现在」：
✘ …lastFocusedAt 在 30 天以后…recorded an issue … at ReviewRegressionTests.swift:87:9: Expectation failed: (h.snap(K.key)?.unread → false) == …
✘ …lastActivityAt 在 30 天以后…recorded an issue at ReviewRegressionTests.swift:102:9: Expectation failed: (h.snapshots → [BuddyCore.BuddySnapshot(key: "d:local_222…
R3c-01 撤销「合并卡带上一张合并卡里的人」：
✘ …三个人的等待提醒先后到…recorded an issue at ReviewRegressionAppTests.swift:282:9: Expectation failed: (lastMulti → "2 位同事在等你") == "3 位同事在等你"
R3c-02 撤销「发系统通知后核对授权、补兜底卡」：
✘ …系统通知授权在运行期间被关掉…recorded an issue at ReviewRegressionAppTests.swift:314:13: Expectation failed: (toast.shown.count == 1 → false)
✘ …recorded an issue at ReviewRegressionAppTests.swift:317:13: Expectation failed: (toast.shown.count == 2 → false)
R3b-02 三个变异（桌牌标题的隐私分支 / 悬停卡片标题的隐私分支 / 悬停卡片路径的隐私分支各失效一次）：三次都红
✘ …隐私模式端到端泄漏扫描…recorded an issue at ReviewRegressionStageTests.swift:262:9: Expectation failed: leaks.isEmpty …
R3a-01 撤销「观察口只记自己临时目录」：
✘ …登记表诱饵测试不受并行套件的 open 影响…recorded an issue at FuzzSecurityTests.swift:128:9: Expectation failed: names.allSatisfy { Paths.isRegistryFileName($0) }
```

R3b-01（`DesktopMeta.baseOverride` 被多个套件并行改写）是并行时序问题：复查员测到竞争组合连跑 40 次红 4 次 / 30 次红 4 次（`QA/review-R3b.md`、`QA/review-R3c.md`）；我自己撤销互斥后同一组合连跑 40 次没有复现红灯，修复后连跑 60 次 0 次红——如实记录，没有把「没复现」说成「复现了」。

## R4a-01 / R4b-01（最后一轮复查 R4 找出的 2 个 P2）

```
R4a-01 撤销「应用层 DesktopMeta.lastFocused 丢掉未来的聚焦时间」：
✘ …lastFocusedAt 在 30 天以后…recorded an issue at ReviewRegressionAppTests.swift:337:13: Expectation failed: (all["local_x"] == nil …
✘ …recorded an issue at ReviewRegressionAppTests.swift:338:13: Expectation failed: (DesktopMeta.mostRecentHost(all) == "local_y") …
✘ …recorded an issue at ReviewRegressionAppTests.swift:339:13: Expectation failed: (DesktopMeta.isMostRecentlyFocused(host: "local_y") && !… "local_x") …
```

R4b-01（账本 `.background` 队列在 CPU 饱和时被饿死）是调度饥饿问题：复查员测到整套默认并行 6 遍红 3 遍、单条 4.3-42 + 8 个空转进程 90 秒超时（`QA/review-R4b.md`）；我撤销修复后开 8 个空转进程跑受影响的 96 个测试**没有复现红灯**，修复后同样压力下通过（`QA/evidence/r3/fail-before-r4.txt`）——如实记录。

## R5a-01（出错提醒漏了两道闸）

撤销两道闸后只跑这条回归测试（完整输出 `QA/evidence/r3/fail-before-r5.txt`）：

```
✘ Test "R5a-01 出错提醒也过两道闸…" recorded an issue at ReviewRegressionAppTests.swift:355:9: Expectation failed: (errorPosts(origin: .desktop, includeDesktop: false, suppress: true, looking: false) → 1) == 0
✘ … recorded an issue at ReviewRegressionAppTests.swift:356:9: Expectation failed: (errorPosts(origin: .terminal, includeDesktop: false, …looking: true) → 1) == 0
✘ … recorded an issue at ReviewRegressionAppTests.swift:357:9: Expectation failed: (errorPosts(origin: .desktop, includeDesktop: true, …looking: true) → 1) == 0
✘ Test run with 1 test in 1 suite failed after 0.006 seconds with 3 issues.
```
修复后：`✔ Test run with 48 tests in 2 suites passed`（含 AlertCoordinatorTests 全部）。

## R1a-02（hook-merge.py 遇到符号链接的 settings.json）/ R1a-P3-02（备份 / 临时文件的创建权限）

```
FAIL: test_dangling_symlink_is_refused_and_creates_nothing (__main__.HookMergeTests)
AssertionError: 0 != 2
FAIL: test_symlinked_settings_keeps_the_link_and_edits_the_real_file (__main__.HookMergeTests)
AssertionError: False is not true : install 之后 settings.json 应该还是符号链接
Ran 15 tests in 0.026s  FAILED (failures=2)          ← 修复前（13 个原有 + 2 个新的）

FAIL: test_backup_and_temp_files_are_created_private_without_relying_on_chmod (__main__.HookMergeTests)
AssertionError: 420 != 384 : 替换之后的 settings.json 应该还是 0600（临时文件创建时就是 0600）
Ran 16 tests in 0.012s  FAILED (failures=1)          ← 修复前

Ran 16 tests in 0.015s  OK                          ← 修复后
```
