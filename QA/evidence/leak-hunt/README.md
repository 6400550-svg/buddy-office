# 长跑里「物理占用在爬」的追查（SOAK-01）

背景：最后一次 35 分钟长跑（`../soak/`）里，读数据的几路进程的物理占用在爬，`soak_watch` 的「后 1/3 − 前 1/3 ≤ +3 MB」判据报 ✗。追查结论写在 `QA/ISSUES.md` 的 SOAK-01 和 `QA/REPORT.md` 第 5 节：**不是泄漏，是有上限（600 张）的文字图片缓存在被填满，装满约 20 MB；另有一处显示器唤醒造成的同一秒阶跃。**

| 文件 | 是什么 |
|---|---|
| `soak-step-analysis.md` | 把长跑的物理占用曲线在 1507 秒（10:27:35，`pmset -g log`：Display is turned on）切成前后两段：七个进程同一秒各跳 +1～+7 MB，前后各自是平的 / 缓慢填充 |
| （`../soak/soak-*.log`） | 最后一次长跑的原始曲线（每 30 秒一行：RSS、物理占用、CPU、线程、句柄） |
| `experiment1-alerts-vs-none-series.txt`、`fp-*.txt`、`heap-class-diff.md` | 实验 1：同一份 8 个会话的压力 replay，B 有「等批准」提醒、C 没有；都静音、16 分钟。两路一样地缓慢上涨（27 → 30 / 27 → 29 MB），**提醒不是原因**；`footprint` 分类里涨的是 `CG Raster Data`（0.8 → 3.8 MB），`Malloc Small` 反而降了；heap 里增长最多的是 CGImage / CFData（文字图片） |
| `experiment2-stress-replay-fill-series.txt` | 实验 2：更快的 replay（`--stress`，12 个会话）24 分钟：`CG Raster Data` 0.27 → 7.2 MB，区域数（≈ 缓存里的图片数）8 → 226，涨幅逐渐放缓 |
| `experiment3-demo-speed20-series.txt` | 实验 3：演示数据加速 20 倍：文字不出新的，`CG Raster Data` 一直是 0.4～1.3 MB——不读数据的进程不涨 |

上限的量化：`Tests/BuddyStageTests/TextCacheBoundTests.swift`：缓存 600 张（先进先出），装满 600 张桌牌大小的文字图片共 20.6 MB；基线约 26 MB + 20 MB ≈ 46 MB，和真实数据开发副本装满后停住的 46 MB 吻合。脚本在 `QA/tools/leak_hunt/`（当时用的是临时目录里的开发副本，路径按当时的写）。

## 附：replay 两路各有 1 个 `unix` 句柄，是什么

最后一次长跑里 replay 和 replay 压力两路从某个时刻起各多了 1 个 `unix` 类型的句柄（压力档 180 秒起、calm 档 843 秒起，之后一直是 1 个，不增长）；演示 / 空闲 / 真实数据（装好的 App 和开发副本）从头到尾没有。追查（开发副本 + 压力 replay，每 10 秒 `lsof -p` 一次）：

- 静音（`notify.sound = none`）的进程：9 分钟里没有出现；
- 有提示音（`8bit`）的进程：**50 秒就出现**（`BuddyOffi … 23u unix 0x… 0t0 ->0x…`：匿名的、不带路径、对端是另一个内核对象）。

结论：它是第一次播放提示音时 `AVAudioPlayer` 建立的音频系统连接，不是网络、不是 `.key` / `.sock` 文件；replay 发生器里的蜜罐 socket 的 `honeypot_sock_connected` 全程 0。（`soak_watch.py` 对 `.sock` 的检查看的是句柄的路径名，匿名的 unix 句柄它看不出对端——所以这里补了「静音进程没有、有声进程才有」的对照。）
