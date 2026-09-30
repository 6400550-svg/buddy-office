#!/usr/bin/env python3
"""把 QA/tools/run_soaks.sh 产出的 soak-*.log 汇成一张 Markdown 表（QA/REPORT.md 第 5 节用）。

直接从每个日志里的数据行算（不依赖汇总行的文字），所以旧格式的日志也能汇总：
  时长、RSS（首 → 末 / 预热后最大 / 预热后均值）、物理占用（首 → 末 / 最大 / 预热后斜率）、CPU（预热 3 分钟后的平均 / 中位 / P95 / 最大）、
  线程（首 → 末 / 最大）、文件句柄（首 → 末 / 最大）、.key / .sock 句柄出现次数、崩溃报告份数。
用法：python3 QA/tools/soak_table.py QA/evidence/soak [--warm 180]
"""
import argparse, glob, os, re, sys

ROW = re.compile(r"^\s*(\d+)\s+([\d.]+)\s+(n/a|[\d.]+)\s+(nan|[\d.]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s")


def slope_per_hour(xs):
    n = len(xs)
    if n < 3:
        return 0.0
    mx = sum(t for t, _ in xs) / n
    my = sum(v for _, v in xs) / n
    den = sum((t - mx) ** 2 for t, _ in xs)
    return (sum((t - mx) * (v - my) for t, v in xs) / den) * 3600 if den else 0.0


def med(xs):
    return sorted(xs)[len(xs) // 2]


def parse(path, warm):
    label, rows, crash = os.path.basename(path), [], "?"
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("# ") and " pid=" in line and "开始" in line and not rows:
            label = line[2:].split(" pid=")[0].strip()
        m = ROW.match(line)
        if m:
            t, rss, fp, cpu, thr, fd, keys, socks = m.groups()
            rows.append((int(t), float(rss), None if fp == "n/a" else float(fp), None if cpu == "nan" else float(cpu), int(thr), int(fd), int(keys), int(socks)))
        m = re.search(r"崩溃报告.*?：(\d+) 份", line)
        if m:
            crash = m.group(1)
    if not rows:
        return None
    w = [r for r in rows if r[0] >= warm] or rows
    cpu = sorted(r[3] for r in w if r[3] is not None)
    fp = [(r[0], r[2]) for r in w if r[2] is not None]
    return {
        "label": label, "secs": rows[-1][0], "n": len(rows),
        "rss_first": rows[0][1], "rss_last": rows[-1][1], "rss_max_warm": max(r[1] for r in w), "rss_mean_warm": sum(r[1] for r in w) / len(w),
        "fp_first": fp[0][1] if fp else None, "fp_last": fp[-1][1] if fp else None, "fp_max": max(v for _, v in fp) if fp else None, "fp_slope": slope_per_hour(fp),
        "fp_growth": (med([v for _, v in fp[-(len(fp) // 3):]]) - med([v for _, v in fp[:len(fp) // 3]])) if len(fp) >= 9 else 0.0,
        "cpu_mean": sum(cpu) / len(cpu) if cpu else float("nan"), "cpu_med": cpu[len(cpu) // 2] if cpu else float("nan"),
        "cpu_p95": cpu[min(len(cpu) - 1, int(len(cpu) * 0.95))] if cpu else float("nan"), "cpu_max": cpu[-1] if cpu else float("nan"),
        "thr_first": rows[0][4], "thr_last": rows[-1][4], "thr_max": max(r[4] for r in rows),
        "fd_first": rows[0][5], "fd_last": rows[-1][5], "fd_max": max(r[5] for r in rows),
        "keys": sum(r[6] for r in rows), "socks": sum(r[7] for r in rows), "crash": crash,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--warm", type=float, default=180, help="预热多少秒之后才算（默认 180）")
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.dir, "soak-*.log")))
    res = [r for r in (parse(f, a.warm) for f in files) if r]
    if not res:
        print("没有找到 soak-*.log", file=sys.stderr)
        return 2
    print("| 长跑 | 时长 | RSS（ps）首 → 末 / 预热后最大 | 物理占用 首 → 末 / 最大 / 后 1/3 比前 1/3 | CPU 预热后 平均 / P95 / 最大 | 线程 首 → 末 / 最大 | 文件句柄 首 → 末 / 最大 | .key / .sock 句柄 | 崩溃报告 |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in res:
        fp = "%.0f → %.0f / %.0f MB / %+.1f MB" % (r["fp_first"], r["fp_last"], r["fp_max"], r["fp_growth"]) if r["fp_first"] is not None else "n/a"
        print("| %s | %d 分 %d 秒（%d 个采样） | %.1f → %.1f / %.1f MB | %s | %.2f%% / %.2f%% / %.2f%% | %d → %d / %d | %d → %d / %d | %d / %d | %s 份 |" % (
            r["label"], r["secs"] // 60, r["secs"] % 60, r["n"], r["rss_first"], r["rss_last"], r["rss_max_warm"], fp,
            r["cpu_mean"], r["cpu_p95"], r["cpu_max"], r["thr_first"], r["thr_last"], r["thr_max"], r["fd_first"], r["fd_last"], r["fd_max"], r["keys"], r["socks"], r["crash"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
