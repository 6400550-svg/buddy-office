#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mutation_check.py —— Buddy 办公室 QA：状态机规则的变异测试（证明测试真的把具体数字钉住了）。

对 Sources/BuddyCore 里和任务书第 4.1 / 5 节规则有关的数字 / 分支做 60 个小变异（0.25 秒批次 → 0.3 / 0.2、3 秒 → 4 / 2、
30 分钟 → 29 / 31、EPERM 当死了……），每个变异各编译一次、跑两组测试：
  · 我的测试：`--filter StateRule`（StateRuleTests / StateRuleProcessTests / StateRuleInvariantTests；不含要 Python 的 StateRuleChainTests）；
  · 已有测试：其余的 BuddyCoreTests（跳过别的 QA 正在写的 Fuzz* 和 FileAccess）。
只要有一组测试失败，这个变异就算被「杀死」；两组都通过 = 存活（要么是测试没钉住这个数字，要么是等价变异）。

**不会改动仓库里的任何文件**：在 --work 目录（默认 $TMPDIR/buddy-mutation）里放一份 BuddyCore 源码 / 测试的副本，变异只打在副本上，
每个变异前都会重新和仓库同步。要在**沙箱外**运行（swift test 需要），并且别和别的编译同时跑（8 GB 内存）。
用法：
  python3 QA/tools/mutation_check.py --list
  python3 QA/tools/mutation_check.py [--only M02 M27 …] [--work DIR] [--json results.jsonl]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# (id, 说明, 文件, 旧, 新)
M = [
 ("M01", "批次间隔 0.25→0.3", "Fusion/ToolTracker.swift", "batchGap: TimeInterval = 0.25", "batchGap: TimeInterval = 0.3"),
 ("M02", "批次间隔 0.25→0.2", "Fusion/ToolTracker.swift", "batchGap: TimeInterval = 0.25", "batchGap: TimeInterval = 0.2"),
 ("M03", "悬空兜底 30→29 分钟", "Fusion/ToolTracker.swift", "staleAfter: TimeInterval = 30 * 60", "staleAfter: TimeInterval = 29 * 60"),
 ("M04", "悬空兜底 30→31 分钟", "Fusion/ToolTracker.swift", "staleAfter: TimeInterval = 30 * 60", "staleAfter: TimeInterval = 31 * 60"),
 ("M05", "Post 配对不是先进先出（名字+detail）", "Fusion/ToolTracker.swift", "var idx = open.firstIndex(where: {", "var idx = open.lastIndex(where: {"),
 ("M06", "Post 只按名字时不是最早的", "Fusion/ToolTracker.swift", "        if idx == nil {\n            idx = open.firstIndex(where: {", "        if idx == nil {\n            idx = open.lastIndex(where: {"),
 ("M07", "新一批不关旧批次悬空的调用", "Fusion/ToolTracker.swift", "closeAll(owner: .main, at: at, reason: .superseded)", "_ = 0"),
 ("M08", "兜底：>= 而不是 >（恰好 30 分钟就关）", "Fusion/ToolTracker.swift", "let stale = age > ToolTracker.staleAfter", "let stale = age >= ToolTracker.staleAfter"),
 ("M09", "兜底：登记表 idle 或小助手 → 登记表 idle 且小助手", "Fusion/ToolTracker.swift", "(registryIdle || t.owner == .helper)", "(registryIdle && t.owner == .helper)"),
 ("M10", "轮次边界不关任何调用", "Fusion/ToolTracker.swift", "if t.owner == .main && t.call.startedAt <= at { record(t, at: at, reason: .turnBoundary) } else { keep.append(t) }", "keep.append(t)"),
 ("M11", "临时 busy 窗口 3→4", "Fusion/ActivityResolver.swift", "tempBusyWindow: TimeInterval = 3", "tempBusyWindow: TimeInterval = 4"),
 ("M12", "临时 busy 窗口 3→2", "Fusion/ActivityResolver.swift", "tempBusyWindow: TimeInterval = 3", "tempBusyWindow: TimeInterval = 2"),
 ("M13", "被打断持续 3→4", "Fusion/ActivityResolver.swift", "interruptedDuration: TimeInterval = 3", "interruptedDuration: TimeInterval = 4"),
 ("M14", "被打断持续 3→2", "Fusion/ActivityResolver.swift", "interruptedDuration: TimeInterval = 3", "interruptedDuration: TimeInterval = 2"),
 ("M15", "做完了持续 5→6", "Fusion/ActivityResolver.swift", "finishedDuration: TimeInterval = 5", "finishedDuration: TimeInterval = 6"),
 ("M16", "做完了持续 5→4", "Fusion/ActivityResolver.swift", "finishedDuration: TimeInterval = 5", "finishedDuration: TimeInterval = 4"),
 ("M17", "重试余量 15→16 秒", "Fusion/ActivityResolver.swift", "retrySlack: TimeInterval = 15", "retrySlack: TimeInterval = 16"),
 ("M18", "重试余量 15→14 秒", "Fusion/ActivityResolver.swift", "retrySlack: TimeInterval = 15", "retrySlack: TimeInterval = 14"),
 ("M19", "sandbox request 不算等批准", "Fusion/ActivityResolver.swift", 'wf == "permission prompt" || wf == "sandbox request"', 'wf == "permission prompt"'),
 ("M20", "dialog open 不算提问", "Fusion/ActivityResolver.swift", 'wf == "input needed" || wf == "dialog open"', 'wf == "input needed"'),
 ("M21", "等批准时 ExitPlanMode 不是计划待审", "Fusion/ActivityResolver.swift", "            if latest?.category == .planExit { return .planReview }\n            if latest?.name == \"AskUserQuestion\" { return .asking }", "            if latest?.name == \"AskUserQuestion\" { return .asking }"),
 ("M22", "等批准时 AskUserQuestion 不是提问", "Fusion/ActivityResolver.swift", "            if latest?.name == \"AskUserQuestion\" { return .asking }\n", ""),
 ("M23", "打盹 10→9 分钟", "Fusion/SessionEngine.swift", "dozeAfter: TimeInterval = 10 * 60", "dozeAfter: TimeInterval = 9 * 60"),
 ("M24", "睡着 45→44 分钟", "Fusion/SessionEngine.swift", "sleepAfter: TimeInterval = 45 * 60", "sleepAfter: TimeInterval = 44 * 60"),
 ("M25", "quiet 10→9 分钟", "Fusion/SessionEngine.swift", "quietAfter: TimeInterval = 10 * 60", "quietAfter: TimeInterval = 9 * 60"),
 ("M26", "quiet 10→11 分钟", "Fusion/SessionEngine.swift", "quietAfter: TimeInterval = 10 * 60", "quietAfter: TimeInterval = 11 * 60"),
 ("M27", "离场防抖 3→2 秒", "Fusion/SessionEngine.swift", "awayDebounce: TimeInterval = 3", "awayDebounce: TimeInterval = 2"),
 ("M28", "离场防抖 3→4 秒", "Fusion/SessionEngine.swift", "awayDebounce: TimeInterval = 3", "awayDebounce: TimeInterval = 4"),
 ("M29", "收回工位 8→7 秒", "Fusion/SessionEngine.swift", "awayLinger: TimeInterval = 8", "awayLinger: TimeInterval = 7"),
 ("M30", "收回工位 8→9 秒", "Fusion/SessionEngine.swift", "awayLinger: TimeInterval = 8", "awayLinger: TimeInterval = 9"),
 ("M31", "Stop 宽限 0.4→0.6", "Fusion/SessionEngine.swift", "stopGrace: TimeInterval = 0.4", "stopGrace: TimeInterval = 0.6"),
 ("M32", "Stop 宽限 0.4→0.2", "Fusion/SessionEngine.swift", "stopGrace: TimeInterval = 0.4", "stopGrace: TimeInterval = 0.2"),
 ("M33", "下班工位上限 4→5", "Fusion/SessionEngine.swift", "dormantMax = 4", "dormantMax = 5"),
 ("M34", "下班工位 12→11 小时", "Fusion/SessionEngine.swift", "dormantExpire: TimeInterval = 12 * 3600", "dormantExpire: TimeInterval = 11 * 3600"),
 ("M35", "下班工位不看归档", "Fusion/SessionEngine.swift", "let m = metaReader.meta(host: host), !m.isArchived { dormant = true }", "let m = metaReader.meta(host: host), m.title != nil || true { dormant = true }"),
 ("M36", "未读：lastFocusedAt >= 也清", "Fusion/SessionEngine.swift", "let e = st.lastTurnEndedAt, f > e { st.unread = false }", "let e = st.lastTurnEndedAt, f >= e { st.unread = false }"),
 ("M37", "未读：lastFocusedAt 不清未读", "Fusion/SessionEngine.swift", "if st.unread, let f = st.meta?.lastFocusedAt, let e = st.lastTurnEndedAt, f > e { st.unread = false }", "_ = 0"),
 ("M38", "被打断也亮未读", "Fusion/SessionEngine.swift", "if kind != .interrupted { st.unread = true }", "st.unread = true"),
 ("M39", "没有 Stop：hook 正常 → 做完了，没有 hook → 被打断（反了）", "Fusion/SessionEngine.swift", "return sig.hookActive ? .interrupted : .finished", "return sig.hookActive ? .finished : .interrupted"),
 ("M40", "出错：重试到上限 → 超过上限", "Fusion/SessionEngine.swift", "e.max > 0, e.attempt >= e.max, e.at >= floor,", "e.max > 0, e.attempt > e.max, e.at >= floor,"),
 ("M41", "轮次边界：Stop 不关调用", "Fusion/SessionEngine.swift", "st.lastStopAt = ev.ts\n                st.tracker.turnBoundary(at: ev.ts)", "st.lastStopAt = ev.ts"),
 ("M42", "轮次边界：UserPromptSubmit 不关调用", "Fusion/SessionEngine.swift", "st.lastPromptAt = ev.ts\n                st.tracker.turnBoundary(at: ev.ts)", "st.lastPromptAt = ev.ts"),
 ("M43", "轮次边界：SessionStart 不关调用", "Fusion/SessionEngine.swift", "case HookEvent.sessionStart:\n                st.tracker.turnBoundary(at: ev.ts)", "case HookEvent.sessionStart:"),
 ("M44", "轮次边界：登记表变 idle 不关调用", "Fusion/SessionEngine.swift", "            st.tracker.turnBoundary(at: now)\n            let ended", "            let ended"),
 ("M45", "轮次边界：stop_hook_summary 不关调用", "Fusion/SessionEngine.swift", "            st.tracker.turnBoundary(at: sh)", "            _ = sh"),
 ("M46", "前台只认 Agent 不认 Task", "Fusion/SessionEngine.swift", '.filter { $0.call.name == "Agent" || $0.call.name == "Task" }', '.filter { $0.call.name == "Agent" }'),
 ("M47", "兜底用的登记表 idle 恒为 false", "Fusion/SessionEngine.swift", "registryIdle: st.record?.status == .idle)", "registryIdle: false)"),
 ("M48", "(回退我的修复) 宽限期内先报做完了", "Fusion/SessionEngine.swift", "            st.turnEnd = .none\n        }\n        // busy ↔ waiting", "            st.turnEnd = .finished\n        }\n        // busy ↔ waiting"),
 ("M49", "前台 Agent 间隔 0.15→0.2", "Fusion/HelperAttributor.swift", "foregroundGap: TimeInterval = 0.15", "foregroundGap: TimeInterval = 0.2"),
 ("M50", "前台 Agent 间隔 0.15→0.1", "Fusion/HelperAttributor.swift", "foregroundGap: TimeInterval = 0.15", "foregroundGap: TimeInterval = 0.1"),
 ("M51", "扣住 0.4→0.5 秒", "Fusion/HelperAttributor.swift", "holdLimit: TimeInterval = 0.4", "holdLimit: TimeInterval = 0.5"),
 ("M52", "扣住 0.4→0.3 秒", "Fusion/HelperAttributor.swift", "holdLimit: TimeInterval = 0.4", "holdLimit: TimeInterval = 0.3"),
 ("M53", "主会话 idle 不归小助手", "Fusion/HelperAttributor.swift", "if c.mainIdle { return .helper }", "if c.mainIdle { return .main }"),
 ("M54", "PID 复用容差 2→3 秒", "Ingest/ProcessProbe.swift", "startTolerance: TimeInterval = 2", "startTolerance: TimeInterval = 3"),
 ("M55", "PID 复用容差 2→1 秒", "Ingest/ProcessProbe.swift", "startTolerance: TimeInterval = 2", "startTolerance: TimeInterval = 1"),
 ("M56", "EPERM 当作死了", "Ingest/ProcessProbe.swift", "case EPERM: break", "case EPERM: return ProcessStatus(state: .dead)"),
 ("M57", "sysctl 失败(unknown)当作死了", "Ingest/ProcessProbe.swift", "case .unknown: return .alive", "case .unknown: return .dead"),
 ("M58", "登记表重试间隔 50→100 ms", "Ingest/RegistryScanner.swift", "retryInterval: TimeInterval = 0.05", "retryInterval: TimeInterval = 0.1"),
 ("M59", "登记表重试上限 5→6", "Ingest/RegistryScanner.swift", "maxRetries = 5", "maxRetries = 6"),
 ("M60", "登记表：非 interactive 也显示", "Ingest/RegistryScanner.swift", 'if let k = kind, k != "interactive" { return .some(nil) }', "_ = kind"),
]


def sync(work):
    pkg = os.path.join(work, "pkg")
    os.makedirs(os.path.join(pkg, "Sources"), exist_ok=True)
    os.makedirs(os.path.join(pkg, "Tests"), exist_ok=True)
    shutil.copyfile(os.path.join(ROOT, ".dev", "core", "Package.swift"), os.path.join(pkg, "Package.swift"))
    link = os.path.join(pkg, "Sources", "buddydump")
    if not os.path.islink(link):
        os.symlink(os.path.join(ROOT, "Sources", "buddydump"), link)
    subprocess.run(["rsync", "-a", "--delete", os.path.join(ROOT, "Sources", "BuddyCore") + "/", os.path.join(pkg, "Sources", "BuddyCore") + "/"], check=True)
    subprocess.run(["rsync", "-a", "--delete", "--exclude", "Fuzz*", os.path.join(ROOT, "Tests", "BuddyCoreTests") + "/",
                    os.path.join(pkg, "Tests", "BuddyCoreTests") + "/"], check=True)
    return pkg


def run_tests(work, pkg, flt):
    env = dict(os.environ, BUDDY_PKG=pkg, BUDDY_SCRATCH=os.path.join(work, "build"))
    p = subprocess.run([os.path.join(ROOT, "scripts", "dev.sh"), "test", "-j", "2"] + flt, cwd=ROOT, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
    return p.stdout.decode("utf-8", "replace")


def failed_tests(out):
    names = set()
    for m in re.finditer(r'^✘ Test (?:case passing 1 argument (seed → \d+) to )?(?:"([^"]+)"|(\w+)\(\))', out, re.M):
        short = (m.group(2).split(" ")[0]) if m.group(2) else m.group(3)
        names.add(short + (" " + m.group(1) if m.group(1) else ""))
    return sorted(names)


def main():
    ap = argparse.ArgumentParser(description="状态机规则的变异测试（只改副本，不改仓库）")
    ap.add_argument("--list", action="store_true", help="只列出全部变异")
    ap.add_argument("--only", nargs="*", help="只跑这些编号")
    ap.add_argument("--work", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "buddy-mutation"))
    ap.add_argument("--json", help="把每个变异的结果追加到这个 jsonl 文件")
    args = ap.parse_args()
    if args.list:
        for mid, desc, rel, _o, _n in M:
            print(mid, desc, "(%s)" % rel)
        return 0
    os.makedirs(args.work, exist_ok=True)
    counts = {}
    for mid, desc, rel, old, new in M:
        if args.only and mid not in args.only:
            continue
        pkg = sync(args.work)
        target = os.path.join(pkg, "Sources", "BuddyCore", rel)
        text = open(target, encoding="utf-8").read()
        if old not in text:
            rec = {"id": mid, "desc": desc, "status": "no-match"}
        else:
            open(target, "w", encoding="utf-8").write(text.replace(old, new, 1))
            t0 = time.time()
            mine = run_tests(args.work, pkg, ["--filter", "StateRule", "--skip", "StateRuleChain"])
            if "error:" in mine and "Test run with" not in mine:
                rec = {"id": mid, "desc": desc, "status": "compile-error", "log": [l for l in mine.splitlines() if "error:" in l][:3]}
            else:
                existing = failed_tests(run_tests(args.work, pkg, ["--skip", "StateRule", "--skip", "Fuzz", "--skip", "FileAccess"]))
                caught = failed_tests(mine)
                rec = {"id": mid, "desc": desc, "mine": caught, "existing": existing,
                       "status": "caught" if caught else ("caught-by-existing-only" if existing else "survived"),
                       "secs": round(time.time() - t0)}
        counts[rec["status"]] = counts.get(rec["status"], 0) + 1
        print(mid, rec["status"], ",".join(rec.get("mine") or rec.get("existing") or []), flush=True)
        if args.json:
            with open(args.json, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print("汇总：", json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
