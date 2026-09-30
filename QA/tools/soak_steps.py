#!/usr/bin/env python3
"""长跑物理占用的「阶跃」分析（QA ②）：把物理占用曲线在某个时刻（默认 1507 秒 = 10:27:35 显示器被唤醒）切成前后两段，
分别算「后 1/3 中位数 − 前 1/3 中位数」和阶跃大小，看几个进程是不是在同一时刻一起跳（= 系统事件，不是某个进程自己在涨）。
  python3 QA/tools/soak_steps.py QA/evidence/soak [--at 1507] [--warm 180]
"""
import argparse, glob, os, statistics

def load(path):
    rows = []
    for ln in open(path, encoding="utf-8"):
        p = ln.split()
        if len(p) >= 4 and p[0].isdigit():
            try: rows.append((int(p[0]), float(p[1]), float(p[2])))
            except ValueError: pass
    return rows

def thirds(v):
    n = len(v) // 3
    return (statistics.median(v[:n]), statistics.median(v[-n:])) if n else (float("nan"), float("nan"))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("--at", type=int, default=1507); ap.add_argument("--warm", type=int, default=180)
    a = ap.parse_args()
    print("| 长跑 | 阶跃前（预热后）：前 1/3 → 后 1/3 中位数 | 阶跃大小（后 5 个 − 前 5 个采样的中位数） | 阶跃后：前 1/3 → 后 1/3 中位数 |")
    print("|---|---|---|---|")
    for f in sorted(glob.glob(os.path.join(a.dir, "soak-*.log"))):
        if "generator" in f: continue
        r = load(f)
        pre = [x[2] for x in r if a.warm <= x[0] < a.at - 20]; post = [x[2] for x in r if x[0] >= a.at + 20]
        near_b = [x[2] for x in r if a.at - 150 <= x[0] < a.at - 20][-5:]; near_a = [x[2] for x in r if a.at + 20 <= x[0]][:5]
        p0, p1 = thirds(pre); q0, q1 = thirds(post)
        step = statistics.median(near_a) - statistics.median(near_b) if near_a and near_b else float("nan")
        print("| %s | %.1f → %.1f MB（%+.1f）| %+.1f MB | %.1f → %.1f MB（%+.1f）|" % (os.path.basename(f)[5:-4], p0, p1, p1 - p0, step, q0, q1, q1 - q0))

main()
