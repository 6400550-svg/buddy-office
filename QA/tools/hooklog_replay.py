#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hooklog_replay.py —— Buddy 办公室 QA：把**真实的 ccmon hook 日志**按任务书 5.2 的工具追踪规则独立回放一遍
（只用 Python 标准库；只读；不联网）。只输出计数 / 直方图，**不输出任何命令、路径、提示词**。

只打开 `<root>/.claude/.monitor/<sessionId>.events.jsonl`，sessionId 来自登记表（^\\d+\\.json$，绝不打开 .key），
绝不扫描 .monitor 目录（里面一多半是 Codex 的）。每行只取 ts / ev / tool / detail 四个字段，detail 只用来配对，从不输出；
UserPromptSubmit 的 extra（用户输入）根本不读。

回放的规则（任务书 5.2，不含 5.3 的子代理归属——没有 agent_id，所以只统计「所有 Pre 都当主线程」）：
  * Pre：距上一个 Pre 超过 0.25 秒 = 新的一批，把更早批次里还开着的调用全部关掉（被取代）；
  * Post：按「工具名 + detail 都相同」关最早的；没有就按工具名关最早的；还没有就忽略（计入「找不到对应的 Post」）；
  * 轮次边界 Stop / UserPromptSubmit / SessionStart / SessionEnd：关掉此前开始的全部调用；
输出：每个会话的 Pre 总数、被 Post 关掉、被下一批取代、被轮次边界关掉、文件末尾残留、找不到对应的 Post、
同一毫秒的 Pre 对数、相邻 Pre 间隔落在 [0.24, 0.26] 秒里的个数（阈值附近的敏感度）。
用法：python3 QA/tools/hooklog_replay.py [--root HOME]
"""
import argparse
import json
import os
import re
import sys

sys.dont_write_bytecode = True
REG_NAME = re.compile(r"[0-9]+\.json")
HOOK_FALLBACK = re.compile(r'"ts"\s*:\s*(\d+).*?"ev"\s*:\s*"([A-Za-z]+)"(?:.*?"tool"\s*:\s*"([^"]*)")?', re.S)
BATCH_GAP_MS = 250


def safe_id(s):
    return bool(s) and len(s) <= 80 and re.fullmatch(r"[A-Za-z0-9_-]+", s) is not None


def session_ids(root):
    d = os.path.join(root, ".claude", "sessions")
    out = []
    for name in sorted(os.listdir(d)):
        if not REG_NAME.fullmatch(name):
            continue
        try:
            with open(os.path.join(d, name), "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue
        sid = j.get("sessionId") if isinstance(j, dict) else None
        if isinstance(sid, str) and safe_id(sid) and (j.get("kind") in (None, "interactive")):
            out.append(sid)
    return out


def events(path):
    """[(ts_ms, ev, tool, detail)]；只取这四个字段。"""
    out = []
    try:
        data = open(path, "rb").read()
    except OSError:
        return out
    for raw in data.split(b"\n"):
        if not raw:
            continue
        text = raw.decode("utf-8", "replace")
        try:
            d = json.loads(text)
            ts, ev = d.get("ts"), d.get("ev")
            if isinstance(ts, (int, float)) and isinstance(ev, str):
                out.append((int(ts), ev, (d.get("tool") or "").rstrip("…"), d.get("detail") or ""))
            continue
        except ValueError:
            pass
        m = HOOK_FALLBACK.search(text)
        if m:
            out.append((int(m.group(1)), m.group(2), (m.group(3) or "").rstrip("…"), ""))
    return out


def replay(evs):
    open_calls = []          # [name, detail, ts]
    last_pre = None
    st = {"pre": 0, "post_closed": 0, "superseded": 0, "boundary": 0, "unmatched_post": 0, "same_ms_pairs": 0,
          "gap_near_250ms": 0, "max_parallel": 0, "residual": 0, "post_exact": 0, "post_name_only": 0}
    for ts, ev, tool, detail in evs:
        if ev == "PreToolUse":
            st["pre"] += 1
            if last_pre is not None:
                gap = ts - last_pre
                if gap == 0:
                    st["same_ms_pairs"] += 1
                if 240 <= gap <= 260:
                    st["gap_near_250ms"] += 1
            if last_pre is None or ts - last_pre > BATCH_GAP_MS:
                st["superseded"] += len(open_calls)
                open_calls = []
            last_pre = ts
            open_calls.append([tool, "" if tool == "AskUserQuestion" else detail, ts])
            st["max_parallel"] = max(st["max_parallel"], len(open_calls))
        elif ev == "PostToolUse":
            d = "" if tool == "AskUserQuestion" else detail
            idx = next((i for i, c in enumerate(open_calls) if c[0] == tool and c[1] == d), None)
            if idx is not None:
                st["post_exact"] += 1
            else:
                idx = next((i for i, c in enumerate(open_calls) if c[0] == tool), None)
                if idx is not None:
                    st["post_name_only"] += 1
            if idx is None:
                st["unmatched_post"] += 1
            else:
                open_calls.pop(idx)
                st["post_closed"] += 1
        elif ev in ("Stop", "UserPromptSubmit", "SessionStart", "SessionEnd"):
            keep = [c for c in open_calls if c[2] > ts]
            st["boundary"] += len(open_calls) - len(keep)
            open_calls = keep
            if last_pre is not None and last_pre <= ts:
                last_pre = None
    st["residual"] = len(open_calls)
    return st


def main(argv=None):
    ap = argparse.ArgumentParser(description="真实 hook 日志的独立回放（工具追踪规则，只输出计数）")
    ap.add_argument("--root", help="假 home 目录；默认真实的 home")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root) if args.root else os.path.expanduser("~")
    mon = os.path.join(root, ".claude", ".monitor")
    total = {}
    print("hook 日志独立回放（root=%s）" % ("real-home" if not args.root else "custom-root"))
    for sid in session_ids(root):
        path = os.path.join(mon, sid + ".events.jsonl")
        if not os.path.isfile(path):
            print("  sid %s  没有 hook 日志" % sid[:8])
            continue
        evs = events(path)
        st = replay(evs)
        print("  sid %s  事件 %d | Pre %d = Post 关 %d（名字+detail 相同 %d、只能按名字 %d）+ 被取代 %d + 轮次边界 %d + 末尾残留 %d | 找不到对应的 Post %d | "
              "同一毫秒的 Pre 对 %d | 相邻 Pre 间隔在 240–260 ms 的 %d | 最大并行 %d" % (
                  sid[:8], len(evs), st["pre"], st["post_closed"], st["post_exact"], st["post_name_only"], st["superseded"], st["boundary"],
                  st["residual"], st["unmatched_post"], st["same_ms_pairs"], st["gap_near_250ms"], st["max_parallel"]))
        assert st["pre"] == st["post_closed"] + st["superseded"] + st["boundary"] + st["residual"], "每个 Pre 必须恰好被关一次或留在末尾"
        for k, v in st.items():
            total[k] = total.get(k, 0) + v if k != "max_parallel" else max(total.get(k, 0), v)
    if total:
        print("  合计  Pre %d = Post 关 %d（名字+detail 相同 %d、只能按名字 %d）+ 被取代 %d + 轮次边界 %d + 末尾残留 %d | 找不到对应的 Post %d | "
              "同一毫秒的 Pre 对 %d | 240–260 ms %d" % (
                  total["pre"], total["post_closed"], total["post_exact"], total["post_name_only"], total["superseded"], total["boundary"],
                  total["residual"], total["unmatched_post"], total["same_ms_pairs"], total["gap_near_250ms"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
