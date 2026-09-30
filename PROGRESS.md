# 进度（给我自己恢复上下文用；对外的记录在 DESIGN.md）

任务书：`~/Desktop/Buddy办公室-开发提示词.md`（M0–M7，独立做完，自己验证，不问用户）。
**用户拒绝了 computer-use 对本 App 的授权**（2026-09-28）——GUI 只能用「自渲染 + 命中测试自检」间接验证，最后如实汇报；不要再问、也不要用 screencapture 绕过。

## 1.1.0（2026-09-30）：加了 Codex（GPT）数据源，见 DESIGN.md 第 14 节；`CodexTests` 12 个 + 全部 810 个测试通过

## 状态：M0–M7 全部完成（2026-09-29），已装到 `~/Applications/Buddy 办公室.app` 并在运行

- [x] M0 可行性小样（DESIGN.md 第 2 节）
- [x] M1 数据层（BuddyCore，README.md 里有发现和限制）
- [x] M2 引擎 + 窗口　[x] M3 角色美术　[x] M4 工位 + 房间 + 场景　[x] M5 表现层
- [x] M6 整合（DESIGN.md 第 8 节逐项）　[x] M7 打包 / 安装 / 跟着 Claude 开收 / 长时间运行（DESIGN.md 第 9 节）
- 之后如果有新需求（比如用户发来 QA 任务书）：先读 DESIGN.md 第 10 节「已知限制」和第 11 节「小决定」，再动手。

## QA 阶段（2026-09-29，用户的 /goal：把整个项目当成别人写的代码独立检查一轮）
- 全部记录在 `QA/`：`ISSUES.md`（每条问题：编号 / 严重度 / 现象 / 根因 / 修法 / 回归测试 / 状态）、`spec-trace.md`（任务书第 4、5、6.5、7 节逐条对应到代码和测试）、`REPORT.md`（最后一次完整回归的数字、修复前后对比图、只能间接验证的项）、`evidence/`（修复前失败的证据、回归日志、长跑日志）、`img/`、`tools/`（`verify_fail_before.py`、`full_regression.sh`、`run_soaks.sh` 等，用法写在各自开头的注释里）。
- 新工具：`buddyctl text-audit`（按 CoreText 真实笔画检查 8 类文字问题）；`BuddyOfficeTests` 测试目标；`QA/tools/replay_soak.py`（假 home 数据发生器，带蜜罐 .key）。
- 重装：`bash 安装.command --yes`（版本 1.0.1）。**跑长时间测试之前别装**（安装会 `pkill -x BuddyOffice`）。

## 怎么构建 / 运行
- 构建、测试：`scripts/dev.sh build|test`（**要在沙箱外跑**，`dangerouslyDisableSandbox: true`；原因见 DESIGN.md 第 1 节）。发布版：`BUDDY_SCRATCH=.build scripts/dev.sh build -c release`。
- 打包 + 安装：`bash 安装.command --yes`（会 `pkill -x BuddyOffice`，**别在有长时间运行的开发副本在跑的时候执行**）；卸载：`bash 卸载.command --yes`。
- 开发用 .app：`scripts/dev-app.sh .build/release/BuddyOffice "dist/dev/Buddy 办公室 release.app"`（bundle id `local.buddy-office.dev`，和正式版互不干扰）。GUI 要在沙箱外 `open -g -n <app> --args …`；**`open` 不传环境变量，只能用命令行参数**。
- 无头工具 `.build/release/buddyctl`（沙箱里能跑）：`dump | replay | snapshot | flicker | verify | golden | gif | screens | cards | bench | sheet | cell | strip | walk | room | icon | probe`。
  - **`verify`**：局部重绘 vs 每帧整张重画，逐像素对比（office / tank / strip，多个时段、尺寸、光照过渡、悬停、`--modes demo,busy6,idle6,crowd12`）。**改渲染代码后必跑**。
  - **`golden [--update]`**：金图哈希（`Tests/BuddyStageTests/golden.txt`）；有意改了画法之后先亲眼看过新画面再 `--update`。
  - **`snapshot`** 常用：`--scene office|tank|strip --from 41 --to 41 --zoom 3 --scale 2 --w 224 --h 226 --clock 12:00 [--hover N] [--mode demo|busy6|idle6|crowd12|crowd10d4|empty] [--crop x,y,w,h]`（crowdN = N 个人 + 刁钻的标题 / 数字，crowd10d4 = 10 个座位其中 4 个是下班工位，empty = 一个会话都没有；demo 模式的 t 就是剧本秒数）。
  - **`bench --sleep-ms 33`** 模拟 App 里 30 Hz 的「冷」脉冲（每帧耗时是热循环的 5–9 倍，别用热循环的数字估 CPU）。
- 量 CPU：`scripts/measure.sh`；长时间运行：`scripts/soak.sh <标签> <分钟> [App 参数…]`（`SOAK_PID=<pid>` 附着到已在运行的进程）。App 调试参数：`--demo [--demo-mode busy6|idle6|crowd12] --show --force-render --tank --strip --no-windows --prof --dump-window PNG --after N --self-test --quit-after-dump --data-root DIR --cgimage --log-ui --test-jump <local_id> --test-autoquit N --test-titlebar --dump-titlebar PNG --dump-settings PREFIX --test-minimize --test-tank-click --test-resize N [--resize-rounds R --resize-random --resize-still]`；日志 `~/Library/Logs/BuddyOffice/debug.log`（0600，超过 1 MB 轮转；只有开发开关才写）。
- GUI 几何检查（不需要任何权限）：`scripts/winlist.swift`（调 `CGWindowListCopyWindowInfo`）按 pid 列窗口的层级 / 位置 / 大小（发现过小鱼缸放置和生长的 bug）。**不要用 osascript 去问 Finder 之类**（会弹「自动化」授权、卡住）。
- 沙箱里 /tmp 不可写：图片输出到 scratchpad（`/private/tmp/claude-501/-Users-USER-Desktop/<session>/scratchpad`）。

## 记着的坑
- `Sources/BuddyArt` 和 `Sources/buddyart` 同名（不区分大小写）；小工具叫 `artctl`（独立包里）。
- `nonisolated(unsafe)` 静态变量初始化顺序：调色板用一个 `Built` 结构整体建好。
- 精灵角色值和 master 索引分两套：角色精灵 = Role 号（经 RoleMap，16 位）；道具精灵 = 直接主调色板索引（前 256 项，`Pal.dx`）。
- 字典遍历顺序每个实例不同：凡是「谁盖在谁上面」的绘制顺序必须显式排序（helperDraws / walkers 都修过）。
- 测试并行跑：共享缓存（Lighting / 文字测量 / SceneClock / ScreenContent.isStatic）都加了锁。
- 用户是在 Claude 桌面 App 的 Code 标签里；我自己的会话 = sessionId 20c4bcc8-f611-4701-b1d3-f910aaa5248d / host local_ead11c7d-1a62-4a18-849c-c6e4b371d05c（测试深链用）。
- 用户对 M0 期间的系统弹窗：通知授权 = 拒绝；终端自动化 = 允许。
- 只有安装脚本（`scripts/hook-merge.py`）能改 `~/.claude/settings.json`，App 运行时绝不写 `~/.claude` 下任何东西；不碰 `*.key`、`/tmp/cc-socks`、ccmon、用量表、Claude.app。
