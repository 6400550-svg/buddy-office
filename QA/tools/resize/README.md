# R2-016 真机复测（办公室窗口反复改尺寸时的内存）

复查员 R2 报告：拖办公室窗口边缘时 `PixelView` 每一步都新建 3 块 IOSurface，测试宿主进程里 300 步物理占用 57 → 261 MB 不回落，真实开发副本 +21 MB（是延迟释放还是泄漏未定论）。
这里用一个开发开关在**真实 App**（开发副本，可见窗口，`--demo --force-render`）里复测：

- `BuddyOffice --test-resize <步数> [--resize-rounds R] [--resize-random] [--resize-still]`（`Sources/BuddyOffice/SelfTests.swift`）：
  每 16 ms 给办公室窗口改一次内容尺寸（每步差 1–2 个缩放单位、来回扫，固定种子），R 轮（轮间停 1.5 秒）；
  全部做完后**先把窗口还原成开始时的尺寸**，再在 1 / 10 / 30 秒后各量一次 `phys_footprint`，同时数 `PixelView` 新建了几组 IOSurface。
  `--resize-still` 是对照组（同样的流程、不改尺寸）。日志一行一行写（`emit` 会 flush），外面的脚本可以按进度用 `footprint -p` 取分类。
- 三个版本交替跑（每个各 2 次，5 轮 × 300 步）：
  - **A** = 修复前（surface 按视口的精确宽高，`variant-A.diff`：`bucket(n) = n`）；
  - **B** = 现在交付的（64 像素一档 + `contentsRect` 裁剪）；
  - **C** = B + 「够用就不重建」（`variant-C.diff`，只在变大或面积缩到一半以下时才重建）。
- 脚本原样保存在这里（当时在临时拷贝 `resize-exp/` 里跑：`build_variants.sh` 编三个版本并打包成 bundle id 各不相同的开发副本，`fp_run.sh` 跑一个版本并用 `footprint` 取分类，`matrix.sh` 交替跑一遍）；
  原始数据在 `QA/evidence/resize/`（`matrix-summary.txt` 是汇总）。要在沙箱外跑。

结论见 `QA/ISSUES.md` 的 R2-016：占用和新建的 IOSurface 组数无关（A 约 700 组、B 约 75 组、C 约 45 组，还原尺寸后的残余都是 +5～7 MB，对照组自己也 +3 MB），
「CoreAnimation 长期保留用过的 surface」只在测试宿主进程里出现，真实 App 里没有；拖动期间占用涨到 35–50 MB 是大窗口本身的工作集，尺寸还原后回落。
