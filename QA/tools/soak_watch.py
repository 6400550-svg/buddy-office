#!/usr/bin/env python3
"""长跑监视（QA ②）：盯一个进程 N 分钟，每 S 秒记一行：RSS、CPU%（cputime 增量）、线程数、打开的文件句柄数（lsof -p）、
里面有没有 .key / .sock 句柄，以及物理占用（footprint）。结束时给汇总：RSS 首 / 末 / 最大、最小二乘斜率（MB / 小时，预热 3 分钟之后）、
句柄数首 / 末 / 最大、CPU 平均 / 最大，并检查这段时间里 ~/Library/Logs/DiagnosticReports 有没有新的 BuddyOffice 崩溃报告。

用法：python3 QA/tools/soak_watch.py --pid 1234 --minutes 35 --label 演示 [--interval 30] [--out soak-演示.log]
      （要在沙箱外跑：里面用 ps / lsof / footprint。只读：不启动、不杀被监视的进程。）
"""
import argparse, glob, os, re, subprocess, sys, time


def sh(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def cpu_seconds(pid):
    out = sh(["ps", "-o", "time=", "-p", str(pid)]).strip()
    if not out:
        return None
    # [[dd-]hh:]mm:ss.cc
    days = 0
    if "-" in out:
        d, out = out.split("-", 1); days = int(d)
    parts = [float(x) for x in out.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0.0)
    return days * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]


def rss_mb(pid):
    out = sh(["ps", "-o", "rss=", "-p", str(pid)]).strip()
    return int(out) / 1024 if out else None


def threads(pid):
    out = sh(["ps", "-M", "-p", str(pid)])
    return max(0, len(out.strip().splitlines()) - 1) if out else None


def footprint_mb(pid):
    out = sh(["footprint", "-p", str(pid)], timeout=30)
    m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", out) or re.search(r"phys_footprint:\s*([\d.]+)\s*(KB|MB|GB)", out)
    if not m:
        return None
    v = float(m.group(1)); unit = m.group(2)
    return v / 1024 if unit == "KB" else (v * 1024 if unit == "GB" else v)


def fds(pid):
    out = sh(["lsof", "-p", str(pid), "-n", "-P"], timeout=40)
    lines = out.strip().splitlines()[1:]
    keys = [l for l in lines if re.search(r"\.key(\s|$)", l, re.I)]
    socks = [l for l in lines if re.search(r"\.sock(\s|$)", l, re.I)]
    kinds = {}
    for l in lines:
        cols = l.split()
        if len(cols) > 4:
            kinds[cols[4]] = kinds.get(cols[4], 0) + 1
    return len(lines), keys, socks, kinds


def slope_mb_per_hour(samples):
    """最小二乘斜率：samples = [(秒, MB)]。"""
    n = len(samples)
    if n < 3:
        return 0.0
    mx = sum(t for t, _ in samples) / n; my = sum(v for _, v in samples) / n
    den = sum((t - mx) ** 2 for t, _ in samples)
    return (sum((t - mx) * (v - my) for t, v in samples) / den) * 3600 if den else 0.0


def crash_reports(since):
    found = []
    for d in (os.path.expanduser("~/Library/Logs/DiagnosticReports"), os.path.expanduser("~/Library/Logs/DiagnosticReports/Retired")):
        for p in glob.glob(os.path.join(d, "*")):
            try:
                if "BuddyOffice" in os.path.basename(p) or "Buddy" in os.path.basename(p):
                    if os.path.getmtime(p) >= since:
                        found.append(p)
            except OSError:
                pass
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pid", type=int, required=True)
    ap.add_argument("--minutes", type=float, default=35)
    ap.add_argument("--interval", type=float, default=30)
    ap.add_argument("--label", default="soak")
    ap.add_argument("--out", default=None)
    ap.add_argument("--cpu-budget", type=float, default=None, help="预热 3 分钟后平均 CPU 的预算（%%，单核百分比）；不给就不判")
    ap.add_argument("--rss-budget", type=float, default=80.0, help="预热 3 分钟后 RSS 最大值的预算（MB）")
    ap.add_argument("--growth-budget", type=float, default=3.0, help="预热后物理占用「后 1/3 中位数 − 前 1/3 中位数」的预算（MB）")
    a = ap.parse_args()
    out = open(a.out, "w") if a.out else sys.stdout

    def log(s):
        out.write(s + "\n"); out.flush()

    t_start = time.time()
    log("# %s pid=%d 开始 %s，%.0f 分钟，每 %.0f 秒一行" % (a.label, a.pid, time.strftime("%H:%M:%S"), a.minutes, a.interval))
    log("# 秒  RSS(MB)  footprint(MB)  CPU%  线程  句柄  .key  .sock  句柄类型")
    prev_cpu = cpu_seconds(a.pid); prev_t = time.time()
    rows = []; key_hits = []; sock_hits = []; died = None
    while time.time() - t_start < a.minutes * 60:
        time.sleep(a.interval)
        if rss_mb(a.pid) is None:
            died = int(time.time() - t_start); log("# 进程在第 %d 秒不见了！" % died); break
        cur = cpu_seconds(a.pid); now = time.time()
        cpu_pct = (cur - prev_cpu) / (now - prev_t) * 100 if cur is not None and prev_cpu is not None else float("nan")
        prev_cpu, prev_t = cur, now
        n_fd, keys, socks, kinds = fds(a.pid)
        fp = footprint_mb(a.pid)
        row = (int(now - t_start), rss_mb(a.pid), fp, cpu_pct, threads(a.pid), n_fd, len(keys), len(socks))
        rows.append(row)
        key_hits += keys; sock_hits += socks
        log("%5d  %7.1f  %s  %5.2f  %3s  %4d  %d  %d  %s" % (row[0], row[1], ("%7.1f" % fp) if fp else "   n/a ", cpu_pct, row[4], n_fd, len(keys), len(socks),
                                                            ",".join("%s:%d" % kv for kv in sorted(kinds.items()))))
    warm = [(r[0], r[1]) for r in rows if r[0] >= 180]
    rss = [r[1] for r in rows]; cpu = [r[3] for r in rows if r[3] == r[3]]; fdc = [r[5] for r in rows]; fpr = [r[2] for r in rows if r[2]]
    log("# ---- 汇总 ----")
    if rows:
        log("# 采样 %d 个；RSS 首 %.1f → 末 %.1f MB，最大 %.1f MB；预热 3 分钟后 RSS 斜率 %+.2f MB/小时" % (len(rows), rss[0], rss[-1], max(rss), slope_mb_per_hour(warm)))
        if fpr:
            log("# 物理占用 首 %.1f → 末 %.1f MB，最大 %.1f MB；斜率 %+.2f MB/小时" % (fpr[0], fpr[-1], max(fpr), slope_mb_per_hour([(r[0], r[2]) for r in rows if r[2] and r[0] >= 180])))
        log("# CPU 平均 %.2f%%，最大 %.2f%%（单核百分比，含启动期）" % (sum(cpu) / len(cpu), max(cpu)))
        log("# 文件句柄 首 %d → 末 %d，最大 %d；线程 首 %s → 末 %s" % (fdc[0], fdc[-1], max(fdc), rows[0][4], rows[-1][4]))
    warm_cpu = [r[3] for r in rows if r[0] >= 180 and r[3] == r[3]]
    cpu_ok = True
    if warm_cpu:
        srt = sorted(warm_cpu)
        avg_w = sum(warm_cpu) / len(warm_cpu)
        log("# CPU 预热 3 分钟后：平均 %.2f%%，中位 %.2f%%，P95 %.2f%%，最大 %.2f%%（%d 个采样）" % (avg_w, srt[len(srt) // 2], srt[min(len(srt) - 1, int(len(srt) * 0.95))], srt[-1], len(srt)))
        if a.cpu_budget is not None:
            cpu_ok = avg_w <= a.cpu_budget
            log("# CPU 预算 ≤%.1f%%（预热后平均 %.2f%%）：%s" % (a.cpu_budget, avg_w, "✅" if cpu_ok else "✗ 超了"))
    warm_rss = [r[1] for r in rows if r[0] >= 180]
    rss_ok = (not warm_rss) or max(warm_rss) <= a.rss_budget
    if warm_rss:
        log("# RSS 预算 ≤%.0f MB（预热后最大 %.1f MB，均值 %.1f MB；全程最大 %.1f MB）：%s" % (a.rss_budget, max(warm_rss), sum(warm_rss) / len(warm_rss), max(rss), "✅" if rss_ok else "✗ 超了"))
    warm_fp = [(r[0], r[2]) for r in rows if r[2] and r[0] >= 180]
    grow_ok = True
    if len(warm_fp) >= 9:
        sl = slope_mb_per_hour(warm_fp)
        third = len(warm_fp) // 3
        med = lambda xs: sorted(xs)[len(xs) // 2]
        head, tail = med([v for _, v in warm_fp[:third]]), med([v for _, v in warm_fp[-third:]])
        grow_ok = (tail - head) <= a.growth_budget
        log("# 内存增长（预热后物理占用：前 1/3 采样的中位数 %.1f MB → 后 1/3 的中位数 %.1f MB，差 %+.1f MB，预算 ≤%+.1f MB；最小二乘斜率 %+.2f MB/小时，物理占用只有 1 MB 的分辨率，斜率仅供参考）：%s" % (head, tail, tail - head, a.growth_budget, sl, "✅ 没有增长" if grow_ok else "✗ 在涨"))
    # 线程数：前 5 个采样的中位数 vs 后 5 个采样的中位数（长跑抓到过「每弹一张提示卡永久多一个线程」：14 → 53）
    thr = [r[4] for r in rows if r[4] is not None]
    thr_grow = 0
    if len(thr) >= 10:
        med = lambda xs: sorted(xs)[len(xs) // 2]
        thr_grow = med(thr[-5:]) - med(thr[:5])
        log("# 线程数 首 %d → 末 %d，最大 %d；前 5 个采样的中位数 → 后 5 个采样的中位数：%+d（> 8 算在涨）" % (thr[0], thr[-1], max(thr), thr_grow))
    log("# .key 句柄出现次数 %d，.sock 句柄出现次数 %d" % (len(key_hits), len(sock_hits)))
    for l in key_hits[:5] + sock_hits[:5]:
        log("#   " + l)
    crashes = crash_reports(t_start)
    log("# 崩溃报告（%s 之后 ~/Library/Logs/DiagnosticReports 里的 Buddy*）：%d 份 %s" % (time.strftime("%H:%M:%S", time.localtime(t_start)), len(crashes), crashes))
    if died is not None:
        log("# ✗ 进程中途退出")
    fd_grow = (fdc[-1] - fdc[0]) if rows else 0
    ok = died is None and not key_hits and not sock_hits and not crashes and thr_grow <= 8 and fd_grow <= 8 and cpu_ok and rss_ok and grow_ok
    log("# 结果：%s" % ("✅ 进程一直在、线程数和句柄数没有增长、内存没有增长、CPU / RSS 在预算内、没有 .key / .sock 句柄、没有崩溃报告" if ok else "✗ 有问题，见上面（线程增长 %+d，句柄增长 %+d）" % (thr_grow, fd_grow)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
