# QA/ 目录说明

2026-09-29 对整个项目做的一轮独立 QA：找 bug、查字体和文字重叠、查逻辑问题，发现的全部修好，重新安装。**先读 [REPORT.md](REPORT.md)。**

| 文件 / 目录 | 是什么 |
|---|---|
| [REPORT.md](REPORT.md) | 最终报告：发现与修复、最后一次完整回归的实际数字、修复前后对比图、长跑结果、逐条追踪摘要、只能间接验证的项、没修的和已知限制、怎么复现 |
| [ISSUES.md](ISSUES.md) | 全部问题（编号 / 严重度 P0–P3 / 现象 / 根因 / 修法 / 回归测试 / 修复前失败的那一行输出 / 状态）。由下面四份区域记录自动合成（`python3 QA/tools/build_issues.py`） |
| [spec-trace.md](spec-trace.md) | 任务书第 4、5、6.5、7 节逐条对应到代码和测试；每条是 ✓ 或写明理由的偏离（理由在 DESIGN.md §13） |
| `issues-stage.md` / `issues-app.md` / `issues-core.md` / `issues-logic.md` / `issues-review.md` | 四个区域（表现层 + 文字审计 / 应用层 / 数据层解析器 + 模糊测试 / 状态机 + token + dump）的原始记录，外加 `issues-review.md`（收尾前三位全新复查员新发现的问题），里面有各自的方法、覆盖矩阵、测试命令 |
| `audit-app.md` | 应用层、表现层、像素引擎、命令行工具的静态审查（强制解包 / 越界 / 溢出 / 主线程 IO / 循环引用 / 句柄 / 缓存增长 / 线程安全等 12 项清单） |
| `spec-trace-core.md` / `spec-trace-ui.md` | 逐条追踪的初稿（`spec-trace.md` 的来源） |
| `review-R1a.md` / `review-R1b.md` / `review-R2.md`、`review-R3a/b/c.md`、`review-R4a/b.md`、`review-R5a/b.md` | 收尾阶段的四轮独立复查（每轮全新的复查员，只读、在自己的拷贝里做探针）：发现、最小复现、「已检查、没问题」的覆盖清单；收敛情况见 REPORT 第 6 节末尾 |
| `img/` | `text-overlap-before-after.png`（文字重叠修复前后）、`text-audit-overview.png`（12 个压力组合总览）、`settings-light-dark.png`（设置页 4 页 × 浅色 / 深色） |
| `evidence/` | 原始日志：`regression-final/`（最后一次完整回归）、`soak/`（最后的长跑，含 `leaks` 扫描）、`asan/` `asan-tests/` `tsan/`（Sanitizer）、`install/`（重新安装和安装后检查）、`fail-before-stage.md`（表现层每个修复「撤销 → 测试红」的逐条验证）、`fail-before-review.md`（收尾前复查和收尾时新发现的问题：修复前失败的原始输出）、`resize/`（R2-016 在真实 App 里的窗口缩放内存复测）、`san01/` `san02/`（收尾时 ASan / 回归抓到的两个测试基础设施问题）、`r3/`（R3 / R4 / R5 复查找出的问题：修复前失败 / 修复后通过）、`leak-hunt/`（长跑内存曲线的追查）、`open-audit-real-*.txt`（真实环境 open 审计）、`soak-prelim/`（预演的长跑，含当时抓到 B-010 的那次）…… |
| `tools/` | 全部可复现的脚本（见 REPORT.md 第 9 节）；`tools/resize/` 是 R2-016 复测用的脚本（当时在临时拷贝里跑，说明见里面的 README） |
