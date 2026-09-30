#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dump_vs_registry.py —— Buddy 办公室 QA：把 `buddyctl dump --once --json` 和活会话登记表逐个会话核对
（只用 Python 标准库；不联网；全程只读；输出里只有 id / 计数 / 布尔值，**不输出任何标题文字和对话内容**）。

核对项（每个活会话）：
  1. pid、sessionId、hostSessionId、来源（entrypoint → 桌面 / VS Code / 终端）、key 前缀（d: / t:）；
  2. status：dump 里的 registryStatus 必须等于登记表的 status；waitingFor 同理；
     phase（修正后的阶段）必须等于「登记表 status + 两个临时修正」的独立推算（用 hook 日志里的 Stop / UserPromptSubmit 的
     ts，只读 ts 和 ev，不读 extra）：登记表 idle 但有更新的 UserPromptSubmit（且比它晚不到 3 秒）→ busy；
     登记表 busy 但有更新的 Stop → idle；
  3. 标题：登记表 name → 桌面 title → custom-title → ai-title → cwd 文件夹名 → "会话 <sid 前 8 位>"，
     独立算出期望标题，和 dump 的 title 比较（只输出「一致 / 不一致」和期望标题来自哪一级，不输出文字）；
  4. 集合：dump 里 presence == present 的会话 == 登记表里 kind 缺省或 interactive、进程还活着的会话
     （dump 没有多出登记表里不存在的活会话，也没有漏掉 interactive 的活会话；非 interactive 的绝不能出现）。
登记表只读文件名匹配 ^\\d+\\.json$ 的文件，**.key 一次都不打开**（连 stat 都不做）。
跑 dump 前后各读一次登记表：这期间变过的会话标记为「不稳定」，不算不一致（请重跑）。

用法：
  python3 QA/tools/dump_vs_registry.py                      # 真实数据：读 ~/.claude/sessions + 运行 .build/release/buddyctl
  python3 QA/tools/dump_vs_registry.py --root FAKE_HOME --dump-json dump.json --liveness skip
  python3 QA/tools/dump_vs_registry.py --selftest
退出码：0 = 全部一致；1 = 有不一致；2 = 用法 / 环境错误。
"""
import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True

REG_NAME = re.compile(r"[0-9]+\.json")            # fullmatch → ^\d+\.json$
HOOK_RE = re.compile(rb'"ts"\s*:\s*(\d+).*?"ev"\s*:\s*"([A-Za-z]+)"', re.S)
TEMP_BUSY_WINDOW = 3.0
TAIL_WINDOW = 512 * 1024                            # 会话记录标题只在尾部窗口里找的对照用


def safe_id(s):
    return bool(s) and len(s) <= 80 and re.fullmatch(r"[A-Za-z0-9_-]+", s) is not None


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return True


def paths_for(root):
    return {
        "sessions": os.path.join(root, ".claude", "sessions"),
        "monitor": os.path.join(root, ".claude", ".monitor"),
        "projects": os.path.join(root, ".claude", "projects"),
        "desktop": os.path.join(root, "Library", "Application Support", "Claude", "claude-code-sessions"),
    }


def read_registry(sessions_dir, check_liveness):
    """{pid: 记录}。只读 ^\\d+\\.json$；写了一半的读不了就跳过（返回 None 表示目录读不了）。"""
    try:
        names = sorted(os.listdir(sessions_dir))
    except OSError:
        return None
    out = {}
    for name in names:
        if not REG_NAME.fullmatch(name):
            continue
        try:
            with open(os.path.join(sessions_dir, name), "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue
        if not isinstance(j, dict):
            continue
        pid, sid = j.get("pid"), j.get("sessionId")
        if not isinstance(pid, int) or isinstance(pid, bool) or not isinstance(sid, str) or not sid:
            continue
        kind = j.get("kind")

        def s(k):
            v = j.get(k)
            return v if isinstance(v, str) and v else None
        out[pid] = {
            "pid": pid, "sid": sid, "host": s("hostSessionId"), "kind": kind if isinstance(kind, str) else None,
            "interactive": (kind is None or kind == "interactive"), "entrypoint": s("entrypoint"), "name": s("name"),
            "cwd": s("cwd"), "status": s("status"), "waitingFor": s("waitingFor"),
            "su": j.get("statusUpdatedAt") if isinstance(j.get("statusUpdatedAt"), (int, float)) else None,
            "alive": pid_alive(pid) if check_liveness else True,
        }
    return out


def origin_of(entrypoint):
    if entrypoint in ("claude-desktop", "claude-desktop-3p", "local-agent"):
        return "desktop"
    if entrypoint == "claude-vscode":
        return "vscode"
    return "terminal"


def read_metas(desktop_dir):
    by_host, by_cli = {}, {}
    for p in sorted(glob.glob(os.path.join(desktop_dir, "*", "*", "local_*.json"))):
        try:
            with open(p, "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue
        if not isinstance(j, dict):
            continue
        host = j.get("sessionId") or os.path.basename(p)[:-5]

        def s(k):
            v = j.get(k)
            return v if isinstance(v, str) and v else None
        m = {"host": host, "cli": s("cliSessionId"),
             "priors": [x for x in (j.get("priorCliSessionIds") or []) if isinstance(x, str) and x],
             "title": s("title"), "cwd": s("cwd")}
        by_host[host] = m
    for host, m in by_host.items():
        for x in m["priors"]:
            by_cli.setdefault(x, host)
    for host, m in by_host.items():
        if m["cli"]:
            by_cli[m["cli"]] = host
    return by_host, by_cli


def find_transcript(projects_dir, sid):
    if not safe_id(sid):
        return None
    for p in sorted(glob.glob(os.path.join(projects_dir, "*", sid + ".jsonl"))):
        return p
    return None


def transcript_titles(path, tail_only=False):
    """会话记录里最后一条 custom-title / ai-title（只解析标题行，不看别的行）。"""
    out = {}
    try:
        with open(path, "rb") as f:
            size = os.fstat(f.fileno()).st_size
            if tail_only and size > TAIL_WINDOW:
                f.seek(size - TAIL_WINDOW)
                f.readline()                       # 丢掉窗口开头可能的半行
            data = f.read()
    except OSError:
        return out
    for raw in data.split(b"\n"):
        # 标题行很短；key 的顺序不一定是 type 在前（假数据里是乱序的），所以不能只看行首 40 字节
        if len(raw) > 65536 or (b'"custom-title"' not in raw and b'"ai-title"' not in raw):
            continue
        try:
            d = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(d, dict):
            continue
        if d.get("type") == "custom-title" and isinstance(d.get("customTitle"), str) and d["customTitle"]:
            out["custom"] = d["customTitle"]
        elif d.get("type") == "ai-title" and isinstance(d.get("aiTitle"), str) and d["aiTitle"]:
            out["ai"] = d["aiTitle"]
    return out


def custom_title_file(transcript):
    """<sid>/custom-title.json：{"customTitle": ...}"""
    if not transcript or not transcript.endswith(".jsonl"):
        return None
    try:
        with open(transcript[:-6] + "/custom-title.json", "rb") as f:
            j = json.loads(f.read(65536))
    except (OSError, ValueError):
        return None
    t = j.get("customTitle") if isinstance(j, dict) else None
    return t if isinstance(t, str) and t else None


def expected_title(rec, meta, transcript, tail_only=False):
    """标题优先级：登记表 name → 桌面 title → custom-title → ai-title → cwd 文件夹名 → "会话 <sid 前 8 位>"。
    返回 (标题, 来源)。"""
    if rec["name"]:
        return rec["name"], "登记表 name"
    if meta and meta["title"]:
        return meta["title"], "桌面 title"
    tt = transcript_titles(transcript, tail_only) if transcript else {}
    custom = tt.get("custom") or custom_title_file(transcript)
    if custom:
        return custom, "custom-title"
    if tt.get("ai"):
        return tt["ai"], "ai-title"
    cwd = rec["cwd"] or (meta["cwd"] if meta else None)
    if cwd:
        last = os.path.basename(cwd.rstrip("/")) if cwd != "/" else ""
        if last:
            return last, "cwd 文件夹名"
    return "会话 " + rec["sid"][:8], "会话 <sid 前 8 位>"


def hook_marks(monitor_dir, sid):
    """hook 日志（只按 sessionId 拼文件名）里最近的 UserPromptSubmit / Stop 的 ts（毫秒）。只读 ts 和 ev。"""
    if not safe_id(sid):
        return None, None
    path = os.path.join(monitor_dir, sid + ".events.jsonl")
    try:
        with open(path, "rb") as f:
            size = os.fstat(f.fileno()).st_size
            f.seek(max(0, size - (1 << 20)))
            data = f.read()
    except OSError:
        return None, None
    prompt = stop = None
    for raw in data.split(b"\n"):
        m = HOOK_RE.search(raw)
        if not m:
            continue
        ts, ev = int(m.group(1)), m.group(2)
        if ev == b"UserPromptSubmit":
            prompt = max(prompt or ts, ts)
        elif ev == b"Stop":
            stop = max(stop or ts, ts)
    return prompt, stop


def expected_phase(rec, prompt_ms, stop_ms, now_ms):
    """登记表 status + 两个临时修正（任务书 5.1）。"""
    st = rec["status"]
    su = rec["su"] or 0
    if st == "idle" and prompt_ms and prompt_ms > su and prompt_ms > (stop_ms or 0) and prompt_ms <= now_ms \
            and (now_ms - prompt_ms) / 1000.0 < TEMP_BUSY_WINDOW:
        return "busy"
    if st == "busy" and stop_ms and stop_ms > su and stop_ms >= (prompt_ms or 0):
        return "idle"
    return st


def run_dump(binary, data_root):
    # buddyctl 有 dump 子命令；buddydump 本身就是 dump
    cmd = [binary] + ([] if os.path.basename(binary) == "buddydump" else ["dump"]) + ["--once", "--poll", "--json"]
    if data_root:
        cmd += ["--data-root", data_root]
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "运行 dump 失败：%s" % type(e).__name__
    if r.returncode != 0:
        return None, "dump 退出码 %d" % r.returncode
    try:
        return json.loads(r.stdout.decode("utf-8", "replace")), None
    except ValueError:
        return None, "dump 输出不是 JSON"


def sig_of(rec):
    return (rec["sid"], rec["host"], rec["status"], rec["waitingFor"], rec["su"], rec["name"], rec["alive"])


def short_hash(s):
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:8]


def compare(args):
    real_home = os.path.expanduser("~")
    root = os.path.abspath(args.root) if args.root else real_home
    is_real = (root == real_home)
    p = paths_for(root)
    check_liveness = (args.liveness == "check") or (args.liveness == "auto" and is_real)
    res = {"root": "real-home" if is_real else "custom-root", "problems": [], "sessions": [], "notes": []}

    before = read_registry(p["sessions"], check_liveness)
    if before is None:
        res["problems"].append("登记表目录读不了")
        res["ok"] = False
        return res

    dump_time = time.time()
    if args.dump_json:
        try:
            with open(args.dump_json, "rb") as f:
                rows = json.loads(f.read())
        except (OSError, ValueError):
            res["problems"].append("dump JSON 读不了")
            res["ok"] = False
            return res
    else:
        rows, err = run_dump(args.buddyctl, args.root)
        if err:
            res["problems"].append(err)
            res["ok"] = False
            return res
    after = read_registry(p["sessions"], check_liveness) or {}
    now_ms = int(dump_time * 1000)
    if not isinstance(rows, list):
        res["problems"].append("dump JSON 不是数组")
        res["ok"] = False
        return res

    by_host, by_cli = read_metas(p["desktop"])
    present = [r for r in rows if r.get("presence") == "present"]
    not_present = [r for r in rows if r.get("presence") != "present"]
    res["dump_rows"] = len(rows)
    res["dump_present"] = len(present)
    res["dump_dormant_or_away"] = len(not_present)

    expected_live = dict((pid, r) for pid, r in before.items() if r["interactive"] and r["alive"])
    by_pid = {}
    dup_pids = set()
    for r in present:
        pid = r.get("pid")
        if pid in by_pid:
            dup_pids.add(pid)
        by_pid[pid] = r
    ok_all = True

    # ---- 集合：不多不少 ----
    extra = sorted(pid for pid in by_pid if pid not in expected_live)
    missing = sorted(pid for pid in expected_live if pid not in by_pid)
    res["extra_in_dump"] = extra
    res["missing_in_dump"] = missing
    for pid in extra:
        # 多出来的可能是：登记表在跑 dump 期间才出现 / 消失（不稳定），或者真的是幽灵
        stable = (pid not in before) == (pid not in after)
        cause = "登记表里没有" if pid not in before else ("非 interactive（kind=%s）" % before[pid]["kind"]
                                                    if not before[pid]["interactive"] else "进程已死")
        res["problems"].append("dump 里多出 pid %s（%s）%s" % (pid, cause, "" if stable else "，登记表在对照期间变过"))
        ok_all = False
    for pid in missing:
        stable = pid in after
        res["problems"].append("dump 漏掉 pid %d（kind=%s，interactive，进程活着）%s" % (
            pid, expected_live[pid]["kind"], "" if stable else "，登记表在对照期间消失了"))
        ok_all = False
    for pid in dup_pids:
        res["problems"].append("dump 里 pid %s 出现了多行" % pid)
        ok_all = False
    for pid, r in before.items():
        if not r["interactive"] and (pid in by_pid or any(x.get("sessionId") == r["sid"] for x in present)):
            res["problems"].append("非 interactive 的会话（pid %d，kind=%s）出现在 dump 里" % (pid, r["kind"]))
            ok_all = False

    # ---- 逐个会话 ----
    for pid in sorted(set(expected_live) & set(by_pid)):
        rec, row = expected_live[pid], by_pid[pid]
        e = {"pid": pid, "sid8": rec["sid"][:8], "origin": origin_of(rec["entrypoint"]), "checks": {}}
        stable = pid in after and sig_of(after[pid]) == sig_of(rec)
        e["stable"] = stable
        chk = e["checks"]
        chk["pid"] = row.get("pid") == pid
        chk["sessionId"] = row.get("sessionId") == rec["sid"]
        chk["hostSessionId"] = (row.get("hostSessionId") or None) == (rec["host"] or None) or \
            (rec["host"] is None and (row.get("hostSessionId") or "").startswith("local_"))   # 没有 host 时可以由桌面元数据补出来
        chk["origin"] = row.get("origin") == e["origin"]
        key = row.get("key") or ""
        if rec["host"]:
            chk["key"] = key == "d:" + rec["host"]
        else:
            chk["key"] = key.startswith("t:") or key.startswith("d:")
        chk["liveness"] = row.get("liveness") == "alive"
        chk["registryStatus"] = row.get("registryStatus") == rec["status"]
        chk["waitingFor"] = (row.get("waitingFor") or None) == (rec["waitingFor"] or None)
        prompt_ms, stop_ms = hook_marks(p["monitor"], rec["sid"])
        e["expected_phase"] = expected_phase(rec, prompt_ms, stop_ms, now_ms)
        e["dump_phase"] = row.get("phase")
        chk["phase"] = row.get("phase") == e["expected_phase"]
        # 标题
        host = rec["host"] or by_cli.get(rec["sid"])
        meta = by_host.get(host) if host else None
        transcript = find_transcript(p["projects"], rec["sid"])
        want, source = expected_title(rec, meta, transcript)
        got = row.get("title")
        e["title_source"] = source
        chk["title"] = (got == want)
        if not chk["title"] and transcript and source not in ("登记表 name", "桌面 title"):
            want_tail, src_tail = expected_title(rec, meta, transcript, tail_only=True)
            if got == want_tail:
                chk["title"] = True
                e["title_note"] = "标题只在会话记录的尾部窗口里找得到（%s）" % src_tail
        if not chk["title"]:
            e["title_debug"] = {"expected_len": len(want), "expected_sha1": short_hash(want),
                                "dump_len": len(got or ""), "dump_sha1": short_hash(got or "")}
        bad = [k for k, v in chk.items() if not v]
        e["ok"] = not bad
        e["failed"] = bad
        if bad and not stable:
            e["ok"] = None            # 登记表在对照期间变过：不算不一致，请重跑
        elif bad:
            ok_all = False
        res["sessions"].append(e)

    res["ok"] = bool(ok_all) and not res["problems"]
    return res


def print_report(res):
    print("dump 与登记表核对（root=%s）" % res["root"])
    for n in res["notes"]:
        print("  · " + n)
    for pr in res["problems"]:
        print("  ! " + pr)
    print("  dump 共 %d 行：present %d，下班 / 离场 %d" % (
        res.get("dump_rows", 0), res.get("dump_present", 0), res.get("dump_dormant_or_away", 0)))
    print("  集合：dump 多出 %s，漏掉 %s" % (res.get("extra_in_dump", []), res.get("missing_in_dump", [])))
    for e in res["sessions"]:
        marks = "  ".join("%s=%s" % (k, "√" if v else "×") for k, v in e["checks"].items())
        verdict = "一致" if e["ok"] else ("不稳定（对照期间登记表变过，请重跑）" if e["ok"] is None else "不一致：" + ",".join(e["failed"]))
        print("  pid %-6d %s %-7s 标题来源=%s 阶段(推算/dump)=%s/%s" % (
            e["pid"], e["sid8"], e["origin"], e["title_source"], e["expected_phase"], e["dump_phase"]))
        print("      %s   → %s" % (marks, verdict))
        if e.get("title_note"):
            print("      注：" + e["title_note"])
        if e.get("title_debug"):
            print("      标题差异（只给长度和 sha1 前 8 位）：%s" % json.dumps(e["title_debug"]))
    print("结论：" + ("全部一致" if res.get("ok") else "存在不一致 / 问题"))


def _selftest():
    tmp = tempfile.mkdtemp(prefix="dvr-selftest-")
    try:
        me = os.getpid()
        sess = os.path.join(tmp, ".claude", "sessions")
        mon = os.path.join(tmp, ".claude", ".monitor")
        proj = os.path.join(tmp, ".claude", "projects", "-x")
        meta_dir = os.path.join(tmp, "Library", "Application Support", "Claude", "claude-code-sessions", "a", "o")
        for d in (sess, mon, proj, meta_dir):
            os.makedirs(d)
        sid = "aaaaaaaa-0000-4000-8000-000000000001"
        with open(os.path.join(sess, "%d.json" % me), "w") as f:
            json.dump({"pid": me, "sessionId": sid, "kind": "interactive", "entrypoint": "cli", "status": "idle",
                       "statusUpdatedAt": 1000, "cwd": "/a/b/项目"}, f)
        with open(os.path.join(sess, "999999.json"), "w") as f:          # 非 interactive：不该出现
            json.dump({"pid": 999999, "sessionId": "bbbbbbbb-0000-4000-8000-000000000002", "kind": "job"}, f)
        rec = read_registry(sess, False)[me]
        # 标题链：全空 → cwd 文件夹名
        assert expected_title(rec, None, None) == ("项目", "cwd 文件夹名")
        rec2 = dict(rec, cwd=None)
        assert expected_title(rec2, None, None) == ("会话 aaaaaaaa", "会话 <sid 前 8 位>")
        with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
            f.write(json.dumps({"type": "ai-title", "aiTitle": "AI", "sessionId": sid}) + "\n")
            f.write(json.dumps({"type": "assistant", "message": {"content": "x"}}) + "\n")
        tp = find_transcript(os.path.join(tmp, ".claude", "projects"), sid)
        assert expected_title(rec, None, tp) == ("AI", "ai-title")
        with open(tp, "a") as f:
            f.write(json.dumps({"type": "custom-title", "customTitle": "自定义", "sessionId": sid}) + "\n")
        assert expected_title(rec, None, tp) == ("自定义", "custom-title")
        assert expected_title(rec, {"title": "桌面", "cwd": None}, tp) == ("桌面", "桌面 title")
        assert expected_title(dict(rec, name="登记"), {"title": "桌面", "cwd": None}, tp) == ("登记", "登记表 name")
        # 阶段推算
        r_idle = dict(rec, status="idle", su=1000)
        assert expected_phase(r_idle, 2000, None, 3000) == "busy"          # 更新的 prompt，1 秒内
        assert expected_phase(r_idle, 2000, None, 6000) == "idle"          # 超过 3 秒
        assert expected_phase(r_idle, 2000, 2500, 3000) == "idle"          # prompt 之后又有 Stop
        r_busy = dict(rec, status="busy", su=1000)
        assert expected_phase(r_busy, 500, 5000, 5100) == "idle"           # 更新的 Stop
        assert expected_phase(r_busy, 6000, 5000, 6100) == "busy"          # Stop 之后又有 prompt
        # 整体：造一份合成 dump
        row = {"pid": me, "sessionId": sid, "key": "t:" + sid, "origin": "terminal", "presence": "present",
               "registryStatus": "idle", "waitingFor": None, "phase": "idle", "title": "自定义", "liveness": "alive"}
        dj = os.path.join(tmp, "d.json")
        with open(dj, "w") as f:
            json.dump([row], f)

        class A(object):
            pass
        a = A()
        a.root, a.dump_json, a.liveness, a.buddyctl = tmp, dj, "skip", None
        r = compare(a)
        assert r["ok"], r
        row["title"] = "错的"
        with open(dj, "w") as f:
            json.dump([row], f)
        r = compare(a)
        assert not r["ok"] and r["sessions"][0]["failed"] == ["title"], r
        row["title"] = "自定义"
        row["waitingFor"] = "permission prompt"
        with open(dj, "w") as f:
            json.dump([row], f)
        r = compare(a)
        assert not r["ok"] and r["sessions"][0]["failed"] == ["waitingFor"], r
        row["waitingFor"] = None
        with open(dj, "w") as f:
            json.dump([row, dict(row, pid=424242, sessionId="x")], f)
        r = compare(a)
        assert not r["ok"] and r["extra_in_dump"] == [424242], r
        with open(dj, "w") as f:
            json.dump([], f)
        r = compare(a)
        assert not r["ok"] and r["missing_in_dump"] == [me], r
        # kind=job 的登记表（不该画成幽灵同事）出现在 dump 里：要报出来
        with open(dj, "w") as f:
            json.dump([row, dict(row, pid=999999, sessionId="bbbbbbbb-0000-4000-8000-000000000002")], f)
        r = compare(a)
        assert not r["ok"] and 999999 in r["extra_in_dump"] and any("非 interactive" in x for x in r["problems"]), r
        return True
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Buddy 办公室 QA：buddyctl dump 与活会话登记表逐个核对（只读，不输出标题文字）")
    ap.add_argument("--root", help="假 home 目录；默认真实的 home")
    ap.add_argument("--liveness", choices=["auto", "check", "skip"], default="auto",
                    help="用 kill(pid,0) 判断进程是否活着：auto = 真实 home 检查，--root 时跳过（假 pid 不存在）")
    ap.add_argument("--buddyctl", default=None, help="buddyctl 路径（默认 <项目>/.build/release/buddyctl）")
    ap.add_argument("--dump-json", help="用已经跑好的 `buddyctl dump --once --json` 输出文件，不再自己运行")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--selftest", action="store_true", help="自检")
    args = ap.parse_args(argv)
    if args.selftest:
        try:
            _selftest()
        except AssertionError as e:
            print("自检失败：%s" % (e,))
            return 1
        print("自检通过")
        return 0
    if args.buddyctl is None:
        here = os.path.dirname(os.path.abspath(__file__))
        args.buddyctl = os.path.normpath(os.path.join(here, "..", "..", ".build", "release", "buddyctl"))
    if not args.dump_json and not os.path.isfile(args.buddyctl):
        print("找不到 buddyctl：%s" % args.buddyctl, file=sys.stderr)
        return 2
    res = compare(args)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, sort_keys=True, indent=1))
    else:
        print_report(res)
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
