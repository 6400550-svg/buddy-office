#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
token_crosscheck.py —— Buddy 办公室 QA：独立的 token 交叉核对（只用 Python 标准库；不联网；全程只读）。

**完全不参考 Swift 实现**，只按用量表（~/.token-meter/plugins/tokens.1m.py）的规则算：

  * 只统计带 "usage" 的 assistant 行（用量表的判据是 message.role == "assistant"；任务书写的是 type == assistant，
    两个判据都实现了，并且把「两个判据不一致的行数」报出来）；
  * 必须有 message.id、合法的 timestamp（ISO 8601）、model 不是 "<synthetic>"、usage 非空；
  * 缓存写 = ephemeral_5m + ephemeral_1h；细分对不上 cache_creation_input_tokens 时全部当 5m；
  * 按 message.id 去重，每个字段（input / output / 缓存写 5m / 缓存写 1h / 缓存读）分别取最大值；
  * 本会话总量 = input + output + 缓存写 + 缓存读；
  * 桌面会话要把桌面元数据里 cliSessionId 与 priorCliSessionIds 对应的会话记录相加；终端会话只算当前 sessionId；
  * 子代理文件（<sid>/subagents/agent-*.jsonl，含 subagents/workflows/wf_*/agent-*.jsonl）也算。

对每个活会话（<root>/.claude/sessions/<pid>.json，文件名必须匹配 ^\\d+\\.json$，**绝不打开 .key**）算出 token，
并和三处比较：
  1. 「用量表口径」：直接 import ~/.token-meter/plugins/tokens.1m.py 里的 parse_line（只读；不写缓存、不写 .pyc）
     配上用量表的合并规则，和上面独立重写的那一份互相对照；
  2. App 的 ledger.json（<root>/Library/Application Support/BuddyOffice/ledger.json）：
     按 ledger 里记录的每个文件的 offset 只读到那个位置为止（文件在增长，所以必须这样）；
  3. `buddyctl dump --once --json` 的 tokens（--dump-json FILE，或 --run-dump 让脚本自己跑）。
     文件在增长时，用 --snapshot DIR：先把每个文件当前大小以内的 token 事实（**去掉了全部对话内容**，只留
     type / timestamp / sessionId / message.{id,role,model,usage}）冻结成一棵假 home，再让两边都读这份冻结的数据。

**隐私**：输出里只有计数、id 前缀、数字；不输出、不保存任何对话内容（冻结快照里也没有）。
用法示例：
  python3 QA/tools/token_crosscheck.py                       # 真实数据 vs 用量表 vs ledger.json
  python3 QA/tools/token_crosscheck.py --run-dump --snapshot "$TMPDIR/tc-snap"    # 再加 dump（冻结快照）
  python3 QA/tools/token_crosscheck.py --root /path/to/fake-home --json           # 假数据（FakeTree）
  python3 QA/tools/token_crosscheck.py --selftest                                   # 自检
退出码：0 = 全部一致；1 = 有不一致；2 = 用法 / 环境错误。
"""
import argparse
import glob
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True      # 不在用量表目录里留 .pyc

REG_NAME = re.compile(r"[0-9]+\.json")             # fullmatch → ^\d+\.json$（只接受 ASCII 数字）
ISO_RE = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:[.,](\d+))?(Z|z|[+-]\d{2}(?::?\d{2})?)?$")
FIELDS = ("input", "output", "cw5m", "cw1h", "cr")


# ─────────────────────────── 独立实现（按用量表的语义自己写） ───────────────────────────

def _int(v):
    """usage 里的数字：None / 不是数字 → 0（用量表的 `x or 0`）。"""
    if isinstance(v, bool):
        return 0
    if isinstance(v, (int, float)):
        return int(v)
    return 0


def iso_ok(ts):
    """timestamp 是不是合法的 ISO 8601（和 datetime.fromisoformat(ts.replace('Z','+00:00')) 一样宽松，
    但不依赖 Python 版本：3.9 的 fromisoformat 不认 2 位小数、Z 等）。"""
    if not isinstance(ts, str):
        return False
    m = ISO_RE.match(ts.strip())
    if not m:
        return False
    y, mo, d, hh, mi, ss = (int(m.group(i)) for i in range(1, 7))
    return 1 <= mo <= 12 and 1 <= d <= 31 and hh < 24 and mi < 60 and ss < 61 and y >= 1


class LineStats(object):
    """一个文件里各类行的计数（只有数字）。"""
    __slots__ = ("usage_lines", "counted", "dupes", "no_msg", "role_not_assistant", "no_usage_or_id", "synthetic",
                 "bad_ts", "bad_json", "role_type_disagree")

    def __init__(self):
        for k in self.__slots__:
            setattr(self, k, 0)

    def add(self, o):
        for k in self.__slots__:
            setattr(self, k, getattr(self, k) + getattr(o, k))

    def as_dict(self):
        return dict((k, getattr(self, k)) for k in self.__slots__)


def parse_usage_line(text, stats, strict_type=False):
    """一行文本 → (message.id, [input, output, cw5m, cw1h, cr]) 或 None。规则见文件头。"""
    if '"usage"' not in text:
        return None
    stats.usage_lines += 1
    try:
        d = json.loads(text)
    except ValueError:
        stats.bad_json += 1
        return None
    if not isinstance(d, dict):
        stats.bad_json += 1
        return None
    msg = d.get("message")
    if not isinstance(msg, dict):
        stats.no_msg += 1
        return None
    role_ok = msg.get("role") == "assistant"
    type_ok = d.get("type") == "assistant"
    if role_ok != type_ok:
        stats.role_type_disagree += 1
    if not (type_ok if strict_type else role_ok):
        stats.role_not_assistant += 1
        return None
    u = msg.get("usage")
    mid = msg.get("id")
    model = msg.get("model") or ""
    if not u or not mid or not isinstance(u, dict):
        stats.no_usage_or_id += 1
        return None
    if model == "<synthetic>":
        stats.synthetic += 1
        return None
    if not iso_ok(d.get("timestamp")):
        stats.bad_ts += 1
        return None
    cw_total = _int(u.get("cache_creation_input_tokens"))
    cc = u.get("cache_creation") or {}
    if not isinstance(cc, dict):
        cc = {}
    cw1h = _int(cc.get("ephemeral_1h_input_tokens"))
    cw5m = _int(cc.get("ephemeral_5m_input_tokens"))
    if cw1h + cw5m != cw_total:          # 没有细分（或对不上）：全部当 5m
        cw5m, cw1h = cw_total, 0
    return str(mid), [_int(u.get("input_tokens")), _int(u.get("output_tokens")), cw5m, cw1h,
                      _int(u.get("cache_read_input_tokens"))]


def read_prefix(path, limit=None):
    """读文件的前 limit 字节（None = 打开那一刻的整个文件），砍到最后一个换行（半行不算）。
    返回 (bytes, 实际用到的字节数)。文件在增长时，读到的永远是一个完整行边界上的前缀。"""
    with open(path, "rb") as f:
        size = os.fstat(f.fileno()).st_size
        n = size if limit is None else min(limit, size)
        data = f.read(n)
    end = data.rfind(b"\n")
    if end < 0:
        return b"", 0
    return data[:end + 1], end + 1


def merge_max(dst, mid, vec):
    """同一条 message.id 多次出现：每个字段取最大值。返回 True = 这是一条新消息。"""
    old = dst.get(mid)
    if old is None:
        dst[mid] = list(vec)
        return True
    for i in range(len(vec)):
        if vec[i] > old[i]:
            old[i] = vec[i]
    return False


def scan_file(path, limit=None, strict_type=False, parser=None):
    """一个文件 → (messages{mid: vec}, LineStats, 用到的字节数)。messages 只含文件内去重后的结果。"""
    data, used = read_prefix(path, limit)
    msgs = {}
    st = LineStats()
    for raw in data.splitlines():
        if b'"usage"' not in raw:
            continue
        text = raw.decode("utf-8", "replace")
        if parser is None:
            r = parse_usage_line(text, st, strict_type)
        else:
            r = parser(text, st)
        if r is None:
            continue
        mid, vec = r
        if merge_max(msgs, mid, vec):
            st.counted += 1
        else:
            st.dupes += 1
    return msgs, st, used


def total_of(vec):
    return sum(vec)


def breakdown(msgs):
    """一组消息 → {input, output, cacheWrite, cacheRead, total, messages}。"""
    a = [0, 0, 0, 0, 0]
    for v in msgs.values():
        for i in range(5):
            a[i] += v[i]
    return {"input": a[0], "output": a[1], "cacheWrite": a[2] + a[3], "cacheRead": a[4],
            "total": sum(a), "messages": len(msgs)}


# ─────────────────────────── 登记表 / 桌面元数据 / 会话记录文件 ───────────────────────────

def paths_for(root):
    home = root
    return {
        "sessions": os.path.join(home, ".claude", "sessions"),
        "projects": os.path.join(home, ".claude", "projects"),
        "desktop": os.path.join(home, "Library", "Application Support", "Claude", "claude-code-sessions"),
        "ledger": os.path.join(home, "Library", "Application Support", "BuddyOffice", "ledger.json"),
    }


def pid_alive(pid):
    """kill(pid, 0)：成功或 EPERM = 存活，ESRCH = 已死。"""
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return True      # 探测不了：当作还活着（和 App 的口径一致：绝不因为探测失败判死）


def read_registry(sessions_dir, check_liveness):
    """读 <pid>.json（只碰 ^\\d+\\.json$；.key 一次都不打开，连 stat 都不做）。"""
    out = []
    try:
        names = sorted(os.listdir(sessions_dir))
    except OSError:
        return out, "登记表目录读不了"
    for name in names:
        if not REG_NAME.fullmatch(name):
            continue
        try:
            with open(os.path.join(sessions_dir, name), "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue          # 写了一半 / 消失了：这个脚本只做核对，不重试
        if not isinstance(j, dict):
            continue
        pid, sid = j.get("pid"), j.get("sessionId")
        if not isinstance(pid, int) or isinstance(pid, bool) or not isinstance(sid, str) or not sid:
            continue
        kind = j.get("kind")
        out.append({
            "pid": pid, "sid": sid, "host": j.get("hostSessionId") or None,
            "kind": kind, "interactive": (kind is None or kind == "interactive"),
            "alive": (pid_alive(pid) if check_liveness else True),
        })
    return out, None


def read_metas(desktop_dir):
    """桌面会话元数据：只取 token 合并需要的字段。返回 (host→meta, cliId→host)。"""
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
        priors = [x for x in (j.get("priorCliSessionIds") or []) if isinstance(x, str) and x]
        cli = j.get("cliSessionId") if isinstance(j.get("cliSessionId"), str) and j.get("cliSessionId") else None
        by_host[host] = {"host": host, "cli": cli, "priors": priors}
    for host, m in by_host.items():
        for pid_ in m["priors"]:
            by_cli.setdefault(pid_, host)
    for host, m in by_host.items():
        if m["cli"]:
            by_cli[m["cli"]] = host
    return by_host, by_cli


def group_sids(rec, by_host, by_cli):
    """这个会话要统计的全部 CLI 会话 id：桌面会话 = priorCliSessionIds + cliSessionId（+ 登记表里的当前 id）。"""
    meta = None
    if rec["host"]:
        meta = by_host.get(rec["host"])
    if meta is None:
        h = by_cli.get(rec["sid"])
        if h:
            meta = by_host.get(h)
    sids = []
    if meta is not None:
        for x in meta["priors"] + ([meta["cli"]] if meta["cli"] else []):
            if x not in sids:
                sids.append(x)
    if rec["sid"] not in sids:
        sids.append(rec["sid"])
    return sids, meta


def safe_id(s):
    return bool(s) and len(s) <= 80 and re.fullmatch(r"[A-Za-z0-9_-]+", s) is not None


def group_files(projects_dir, sids):
    """全部要统计的文件：每个 sid 的 <proj>/<sid>.jsonl + 子代理 agent-*.jsonl（含 workflows/wf_*/）。
    返回 [(path, kind)]，kind = main / agent。"""
    files = []
    for sid in sids:
        if not safe_id(sid):
            continue
        for p in sorted(glob.glob(os.path.join(projects_dir, "*", sid + ".jsonl"))):
            files.append((p, "main"))
        base = os.path.join(projects_dir, "*", sid, "subagents")
        pats = [os.path.join(base, "agent-*.jsonl"), os.path.join(base, "workflows", "*", "agent-*.jsonl")]
        for pat in pats:
            for p in sorted(glob.glob(pat)):
                files.append((p, "agent"))
    seen, out = set(), []
    for p, k in files:
        if p not in seen:
            seen.add(p)
            out.append((p, k))
    return out


# ─────────────────────────── 用量表原版的 parse_line（只读 import） ───────────────────────────

def load_meter(path):
    if not os.path.isfile(path):
        return None, "找不到 %s" % path
    try:
        loader = importlib.machinery.SourceFileLoader("tokens_1m_readonly", path)
        spec = importlib.util.spec_from_loader("tokens_1m_readonly", loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)          # 模块级代码只读 config.json；main() 在 __main__ 守卫里，不会执行
    except Exception as e:               # noqa: BLE001 —— 用量表坏了不能拖垮核对
        return None, "import 用量表失败：%s" % type(e).__name__
    if not hasattr(mod, "parse_line"):
        return None, "用量表里没有 parse_line"
    return mod, None


def meter_parser(mod):
    """把用量表的 parse_line 适配成 (mid, [input, output, cw5m, cw1h, cr])。"""
    def parse(text, st):
        r = mod.parse_line(text)
        if r is None:
            return None
        mid, rec, _d = r
        return str(mid), [int(rec[2]), int(rec[3]), int(rec[4]), int(rec[5]), int(rec[6])]
    return parse


# ─────────────────────────── 核对一个会话 ───────────────────────────

def compute_group(files, limits, strict_type=False, parser=None):
    """一组文件（一个会话）→ 去重后的总量。limits: {path: 最大读取字节数 or None}。"""
    merged = {}
    st = LineStats()
    per_file = []
    for path, kind in files:
        try:
            msgs, s, used = scan_file(path, limits.get(path), strict_type, parser)
        except OSError:
            per_file.append({"path": path, "kind": kind, "missing": True})
            continue
        st.add(s)
        for mid, vec in msgs.items():
            merge_max(merged, mid, vec)
        per_file.append({"path": path, "kind": kind, "bytes": used, "own": breakdown(msgs)})
    return merged, st, per_file


def load_ledger(path):
    try:
        with open(path, "rb") as f:
            j = json.loads(f.read())
    except (OSError, ValueError):
        return None
    if not isinstance(j, dict) or j.get("version") != 1 or not isinstance(j.get("files"), dict):
        return None
    return j["files"]


def ledger_limits(files, ledger):
    """ledger 里记了每个文件的 dev / ino / offset：文件还是同一个 inode 且没变短，就只读到 offset。"""
    limits, used, missing, moved = {}, 0, [], []
    for path, _k in files:
        e = ledger.get(path) if ledger else None
        if not e:
            missing.append(path)
            continue
        try:
            st = os.stat(path)
        except OSError:
            moved.append(path)
            continue
        if st.st_ino != e.get("ino") or st.st_dev != e.get("dev") or st.st_size < e.get("offset", 0):
            moved.append(path)
            continue
        limits[path] = int(e.get("offset", 0))
        used += 1
    return limits, missing, moved


def ledger_sum(files, ledger):
    a = {"input": 0, "output": 0, "cacheWrite": 0, "cacheRead": 0, "messages": 0}
    for path, _k in files:
        e = ledger.get(path)
        if not e:
            continue
        a["input"] += int(e.get("input", 0))
        a["output"] += int(e.get("output", 0))
        a["cacheWrite"] += int(e.get("cw", 0))
        a["cacheRead"] += int(e.get("cr", 0))
        a["messages"] += int(e.get("n", 0))
    a["total"] = a["input"] + a["output"] + a["cacheWrite"] + a["cacheRead"]
    return a


def same(a, b, keys=("input", "output", "cacheWrite", "cacheRead", "total")):
    return all(a.get(k) == b.get(k) for k in keys)


def fmt(b):
    if b is None:
        return "-"
    return "%d/%d/%d/%d=%d" % (b["input"], b["output"], b["cacheWrite"], b["cacheRead"], b["total"])


# ─────────────────────────── 冻结快照（去掉全部对话内容） ───────────────────────────

# 冻结快照里只留「认人 + 算 token」需要的字段：不带标题 / cwd / 会话名 / 桌面本轮总结（那些是从对话里来的）
REG_KEEP = ("pid", "sessionId", "startedAt", "procStart", "pidDomain", "version", "kind", "entrypoint",
            "hostSessionId", "status", "statusUpdatedAt", "updatedAt")
META_KEEP = ("sessionId", "cliSessionId", "priorCliSessionIds", "isArchived", "createdAt", "lastActivityAt",
             "lastFocusedAt", "completedTurns")


def reduce_usage_line(text):
    """一条带 usage 的行 → 只留 token 事实的最小 JSON（没有 content / 文字 / 工具输入）。"""
    try:
        d = json.loads(text)
    except ValueError:
        return None
    if not isinstance(d, dict):
        return None
    msg = d.get("message")
    if not isinstance(msg, dict):
        return None
    out = {"type": d.get("type"), "timestamp": d.get("timestamp"), "sessionId": d.get("sessionId"),
           "message": {"id": msg.get("id"), "role": msg.get("role"), "model": msg.get("model"),
                       "usage": msg.get("usage")}}
    return json.dumps(out, ensure_ascii=False, separators=(",", ":"))


def build_snapshot(root, dest, recs, by_host, by_cli):
    """冻结：把每个要统计的文件当前大小以内的 token 事实写进 dest 下的假 home。返回 {原路径: 冻结时的字节数}。"""
    p = paths_for(root)
    q = paths_for(dest)
    os.makedirs(q["sessions"], exist_ok=True)
    os.makedirs(os.path.join(q["desktop"], "acct", "org"), exist_ok=True)
    limits = {}
    all_files = []
    used_hosts = set()
    for r in recs:
        sids, meta = group_sids(r, by_host, by_cli)
        all_files.extend(group_files(p["projects"], sids))
        if meta is not None:
            used_hosts.add(meta["host"])
    # 登记表：只留白名单字段
    for r in recs:
        if r.get("synthetic"):
            red = {"pid": r["pid"], "sessionId": r["sid"], "hostSessionId": r["host"], "kind": "interactive",
                   "entrypoint": "claude-desktop", "status": "idle",
                   "statusUpdatedAt": int((time.time() - 3600) * 1000)}
            with open(os.path.join(q["sessions"], "%d.json" % r["pid"]), "w", encoding="utf-8") as f:
                json.dump(red, f)
            continue
        src = os.path.join(p["sessions"], "%d.json" % r["pid"])
        try:
            with open(src, "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue
        red = dict((k, j[k]) for k in REG_KEEP if k in j)
        with open(os.path.join(q["sessions"], "%d.json" % r["pid"]), "w", encoding="utf-8") as f:
            json.dump(red, f, ensure_ascii=False)
    # 桌面元数据：只留白名单字段
    for p_ in sorted(glob.glob(os.path.join(p["desktop"], "*", "*", "local_*.json"))):
        try:
            with open(p_, "rb") as f:
                j = json.loads(f.read())
        except (OSError, ValueError):
            continue
        host = j.get("sessionId") or os.path.basename(p_)[:-5]
        if host not in used_hosts:
            continue
        red = dict((k, j[k]) for k in META_KEEP if k in j)
        with open(os.path.join(q["desktop"], "acct", "org", os.path.basename(p_)), "w", encoding="utf-8") as f:
            json.dump(red, f, ensure_ascii=False)
    # 会话记录：冻结每个文件当前的字节数（砍到行边界），只写 token 事实
    seen = set()
    for path, _kind in all_files:
        if path in seen:
            continue
        seen.add(path)
        rel = os.path.relpath(path, p["projects"])
        parts = rel.split(os.sep)
        parts[0] = "-snapshot"                       # 项目目录名不带真实 cwd
        target = os.path.join(q["projects"], *parts)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        try:
            data, used = read_prefix(path, None)
        except OSError:
            continue
        limits[path] = used
        with open(target, "w", encoding="utf-8") as out:
            for raw in data.splitlines():
                if b'"usage"' not in raw:
                    continue
                red = reduce_usage_line(raw.decode("utf-8", "replace"))
                if red:
                    out.write(red + "\n")
    return limits


# ─────────────────────────── dump ───────────────────────────

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


def run_dump_table(binary, data_root):
    """`buddyctl dump --once --poll`（默认的表格输出）的文本。"""
    cmd = [binary] + ([] if os.path.basename(binary) == "buddydump" else ["dump"]) + ["--once", "--poll"]
    if data_root:
        cmd += ["--data-root", data_root]
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def fmt_tok(n):
    """和 Swift 的 DumpFormatter.fmtTok 一样的缩写（表格里的 token 列）。"""
    if n >= 1000000000:
        return "%.2fB" % (n / 1e9)
    if n >= 1000000:
        return "%.1fM" % (n / 1e6)
    if n >= 1000:
        return "%.0fK" % (n / 1e3)
    return str(n)


def table_line_for(text, pid):
    """表格里 pid 那一行（pid 后面跟着存活标记 ✓ ✗ ≠ ? ·）。"""
    for line in (text or "").splitlines():
        if re.search(r"(?<![0-9])%d[✓✗≠?·]" % pid, line):
            return line
    return None


def dump_index(rows):
    idx = {}
    for row in rows or []:
        if row.get("presence") != "present":
            continue
        idx[row.get("sessionId")] = row
        if row.get("pid") is not None:
            idx[("pid", row["pid"])] = row
    return idx


def dump_breakdown(row):
    t = row.get("tokens") or {}
    return {"input": t.get("input", 0), "output": t.get("output", 0), "cacheWrite": t.get("cacheWrite", 0),
            "cacheRead": t.get("cacheRead", 0), "total": t.get("total", 0), "messages": t.get("messages", 0),
            "scanComplete": t.get("scanComplete", True)}


# ─────────────────────────── 主流程 ───────────────────────────

def crosscheck(args):
    real_home = os.path.expanduser("~")
    root = os.path.abspath(args.root) if args.root else real_home
    is_real = (root == real_home)
    p = paths_for(root)
    check_liveness = (args.liveness == "check") or (args.liveness == "auto" and is_real)
    recs, err = read_registry(p["sessions"], check_liveness)
    result = {"root": "real-home" if is_real else "custom-root", "problems": [], "sessions": [], "notes": []}
    if err:
        result["problems"].append(err)
    live = [r for r in recs if r["interactive"] and r["alive"]]
    for r in recs:
        if not (r["interactive"] and r["alive"]):
            result["notes"].append("跳过 pid %d（%s）" % (r["pid"], "非 interactive" if not r["interactive"] else "进程已死"))
    by_host, by_cli = read_metas(p["desktop"])
    spare_pids = [os.getpid(), os.getppid()]
    for h in args.extra_host or []:
        m = by_host.get(h)
        sid = (m["cli"] or (m["priors"][-1] if m["priors"] else None)) if m else None
        if not m or not sid or not spare_pids:
            result["problems"].append("--extra-host 找不到这个桌面会话（或它没有 CLI 会话 id）：%s" % h[:14])
            continue
        if not args.snapshot and args.run_dump:
            result["problems"].append("--extra-host 要配合 --snapshot 才能让 dump 看到它")
        live.append({"pid": spare_pids.pop(0), "sid": sid, "host": h, "kind": "interactive", "interactive": True,
                     "alive": True, "synthetic": True})

    meter = None
    if not args.no_meter:
        meter, merr = load_meter(os.path.expanduser(args.meter))
        if merr:
            result["notes"].append("用量表 parse_line 对照不可用：" + merr)
    meter_parse = meter_parser(meter) if meter else None

    ledger = None if args.no_ledger else load_ledger(args.ledger or p["ledger"])
    if not args.no_ledger and ledger is None:
        result["notes"].append("ledger.json 读不了 / 不存在：跳过 ledger 对照")

    # 每个活会话 = 一组文件
    groups = []
    for r in live:
        sids, meta = group_sids(r, by_host, by_cli)
        groups.append((r, sids, meta, group_files(p["projects"], sids)))

    # ---- 冻结快照 + dump ----
    dump_rows, snap_limits = None, {}
    want_dump = bool(args.run_dump or args.dump_json)
    if args.dump_json:
        try:
            with open(args.dump_json, "rb") as f:
                dump_rows = json.loads(f.read())
        except (OSError, ValueError):
            result["problems"].append("dump JSON 读不了")
    sizes_before = {}
    if args.snapshot:
        snap_root = os.path.abspath(args.snapshot)
        if os.path.exists(snap_root) and os.listdir(snap_root):
            result["problems"].append("--snapshot 目录必须是空的 / 不存在：%s" % snap_root)
            result["ok"] = False
            return result
        snap_limits = build_snapshot(root, snap_root, live, by_host, by_cli)
        result["notes"].append("已冻结 %d 个文件的当前内容（去掉了全部对话内容）；两边都只读到冻结的大小" % len(snap_limits))
        if args.run_dump:
            dump_rows, derr = run_dump(args.buddyctl, snap_root)
            if derr:
                result["problems"].append(derr)
    elif args.run_dump:
        for _r, _s, _m, files in groups:
            for path, _k in files:
                try:
                    sizes_before[path] = os.stat(path).st_size
                except OSError:
                    sizes_before[path] = None
        dump_rows, derr = run_dump(args.buddyctl, args.root)
        if derr:
            result["problems"].append(derr)
    didx = dump_index(dump_rows) if dump_rows is not None else {}
    table_text = None
    if args.run_dump and (args.snapshot or args.root) and not result["problems"]:
        table_text = run_dump_table(args.buddyctl, os.path.abspath(args.snapshot) if args.snapshot else args.root)

    ok_all = True
    all_group_msgs = []
    for r, sids, meta, files in groups:
        entry = {"pid": r["pid"], "sid8": r["sid"][:8], "desktop_meta": meta is not None, "sids": len(sids),
                 "files": len(files), "agent_files": sum(1 for _p, k in files if k == "agent")}
        # 冻结的大小；没有快照就读打开那一刻的整个文件
        limits = dict((pp, snap_limits.get(pp)) for pp, _k in files) if snap_limits else {}
        # (1) 独立实现
        msgs, st, _pf = compute_group(files, limits, args.strict_type)
        mine = breakdown(msgs)
        entry["mine"] = mine
        entry["lines"] = st.as_dict()
        all_group_msgs.append((r["sid"][:8], set(msgs.keys())))
        # (2) 用量表原版 parse_line + 用量表的合并规则（同样的文件范围）
        if meter_parse:
            m_msgs, _mst, _pf2 = compute_group(files, limits, False, meter_parse)
            entry["meter"] = breakdown(m_msgs)
            entry["mine_vs_meter"] = same(mine, entry["meter"]) and mine["messages"] == entry["meter"]["messages"]
            ok_all = ok_all and entry["mine_vs_meter"]
        # (3) ledger.json：每个文件只读到 ledger 记录的 offset
        if ledger is not None:
            lim, missing, moved = ledger_limits(files, ledger)
            entry["ledger_files"] = len(lim)
            entry["ledger_missing_files"] = len(missing)
            entry["ledger_moved_files"] = len(moved)
            if files and len(lim) == len(files):
                l_msgs, _s, _p2 = compute_group(files, lim, args.strict_type)
                mine_l = breakdown(l_msgs)
                led = ledger_sum(files, ledger)
                entry["mine_at_ledger_offsets"] = mine_l
                entry["ledger"] = led
                entry["mine_vs_ledger"] = same(mine_l, led) and mine_l["messages"] == led["messages"]
                ok_all = ok_all and entry["mine_vs_ledger"]
            else:
                entry["mine_vs_ledger"] = None      # 有文件没登记（有 prior 的组每次重扫，不写断点）/ 文件换了：无法对照
        # (4) dump 的 token 列
        if want_dump:
            row = didx.get(r["sid"]) or didx.get(("pid", r["pid"]))
            if row is None:
                entry["dump"] = None
                entry["mine_vs_dump"] = False
                result["problems"].append("dump 里找不到 pid %d 的会话" % r["pid"])
                ok_all = False
            else:
                d = dump_breakdown(row)
                entry["dump"] = d
                grew = False
                if sizes_before:
                    for path, _k in files:
                        try:
                            now_size = os.stat(path).st_size
                        except OSError:
                            now_size = None
                        if now_size != sizes_before.get(path):
                            grew = True
                entry["unstable"] = grew
                entry["mine_vs_dump"] = same(mine, d) and mine["messages"] == d["messages"]
                if table_text is not None:
                    line = table_line_for(table_text, r["pid"])
                    entry["table_token_cell"] = (line is not None and fmt_tok(mine["total"]) in line)
                    ok_all = ok_all and bool(entry["table_token_cell"])
                if grew and not entry["mine_vs_dump"]:
                    entry["mine_vs_dump"] = None     # 对照期间文件在增长：不可比（请用 --snapshot）
                else:
                    ok_all = ok_all and bool(entry["mine_vs_dump"])
        result["sessions"].append(entry)

    # 不同会话之间有没有共享的 message.id（共享的话，全局去重会把它记在先扫到的那个会话上）
    shared = {}
    for i in range(len(all_group_msgs)):
        for j in range(i + 1, len(all_group_msgs)):
            common = all_group_msgs[i][1] & all_group_msgs[j][1]
            if common:
                shared["%s&%s" % (all_group_msgs[i][0], all_group_msgs[j][0])] = len(common)
    result["cross_session_shared_message_ids"] = shared
    result["ok"] = bool(ok_all) and not result["problems"]
    return result


def print_report(res):
    print("token 交叉核对（root=%s）" % res["root"])
    for n in res["notes"]:
        print("  · " + n)
    for pr in res["problems"]:
        print("  ! " + pr)
    if not res["sessions"]:
        print("  （没有可核对的活会话）")
    for e in res["sessions"]:
        head = "pid %-6d sid %s  文件 %d（子代理 %d）%s" % (
            e["pid"], e["sid8"], e["files"], e["agent_files"], "  含 prior 会话" if e["sids"] > 1 else "")
        print(head)
        print("   独立实现    输入/输出/缓存写/缓存读=合计 : %s  消息 %d" % (fmt(e["mine"]), e["mine"]["messages"]))
        if "meter" in e:
            print("   用量表 parse_line + 合并规则          : %s  消息 %d   → %s" % (
                fmt(e["meter"]), e["meter"]["messages"], "一致" if e["mine_vs_meter"] else "不一致"))
        if "ledger" in e:
            print("   ledger.json 读到 offset 为止 独立实现 : %s" % fmt(e["mine_at_ledger_offsets"]))
            print("               ledger.json 记录            : %s  消息 %d   → %s" % (
                fmt(e["ledger"]), e["ledger"]["messages"], "一致" if e["mine_vs_ledger"] else "不一致"))
        elif "ledger_files" in e:
            print("   ledger.json 无法逐文件对照（%d/%d 个文件有登记；有 prior 会话的组每次重扫、不写断点）" % (
                e["ledger_files"], e["files"]))
        if "dump" in e and e["dump"]:
            verdict = "一致" if e["mine_vs_dump"] else ("不可比（对照期间文件在增长，请用 --snapshot）" if e["mine_vs_dump"] is None else "不一致")
            print("   dump 的 token 列                        : %s  消息 %d%s   → %s" % (
                fmt(e["dump"]), e["dump"]["messages"], "" if e["dump"].get("scanComplete") else "（扫描未完成）", verdict))
            if "table_token_cell" in e:
                print("   dump 表格里的 token 列（缩写）           : %s   → %s" % (
                    fmt_tok(e["mine"]["total"]), "一致" if e["table_token_cell"] else "不一致"))
        li = e["lines"]
        if li["role_type_disagree"]:
            print("   注意：%d 行 message.role 和 type 的判据不一致" % li["role_type_disagree"])
    if res.get("cross_session_shared_message_ids"):
        print("  会话之间共享的 message.id：%s（全局去重会把它们记在先扫到的会话上）" % json.dumps(
            res["cross_session_shared_message_ids"]))
    print("结论：" + ("全部一致" if res.get("ok") else "存在不一致 / 问题"))


# ─────────────────────────── 自检 ───────────────────────────

def _selftest():
    """造一棵合成的 home 树，手算期望值，验证这个脚本自己的规则（不依赖 Swift）。"""
    tmp = tempfile.mkdtemp(prefix="tc-selftest-")
    try:
        def ts(n):
            return "2026-09-29T04:%02d:%02d.123Z" % (n // 60, n % 60)

        def line(sid, mid, t, inp=0, out=0, cw=0, cr=0, w5=None, w1=None, model="claude-opus-5-5", role="assistant",
                 typ="assistant", extra=None):
            u = {"input_tokens": inp, "output_tokens": out, "cache_creation_input_tokens": cw,
                 "cache_read_input_tokens": cr}
            if w5 is not None:
                u["cache_creation"] = {"ephemeral_5m_input_tokens": w5, "ephemeral_1h_input_tokens": w1}
            d = {"type": typ, "timestamp": ts(t), "sessionId": sid,
                 "message": {"id": mid, "role": role, "model": model, "usage": u, "content": [{"type": "text", "text": "SECRET-TEXT"}]}}
            if extra:
                d.update(extra)
            return json.dumps(d)

        s1, s2, s3 = "aaaaaaaa-0000-4000-8000-000000000001", "bbbbbbbb-0000-4000-8000-000000000002", \
                     "cccccccc-0000-4000-8000-000000000003"
        proj = os.path.join(tmp, ".claude", "projects", "-fake")
        os.makedirs(os.path.join(proj, s1, "subagents", "workflows", "wf_1"))
        os.makedirs(os.path.join(tmp, ".claude", "sessions"))
        meta_dir = os.path.join(tmp, "Library", "Application Support", "Claude", "claude-code-sessions", "a", "o")
        os.makedirs(meta_dir)
        # 桌面会话：当前 s1，prior s2；s3 是一个终端会话
        with open(os.path.join(proj, s1 + ".jsonl"), "w") as f:
            f.write("\n".join([
                line(s1, "m1", 1, inp=10, out=1, cw=100, cr=1000),                    # m1：多次写入，每个字段取最大值
                line(s1, "m1", 2, inp=10, out=50, cw=100, cr=900),
                line(s1, "m2", 3, out=7, cw=300, w5=100, w1=200),                     # 细分对得上：300
                line(s1, "m3", 4, out=5, cw=500, w5=1, w1=2),                         # 细分对不上：全部当 5m = 500
                line(s1, "syn", 5, out=999, model="<synthetic>"),                     # 合成：不算
                line(s1, "nots", 6, out=999).replace('"timestamp"', '"ts_"'),         # 没有 timestamp：不算
                json.dumps({"type": "user", "timestamp": ts(7), "message": {"role": "user", "content": "x", "usage": {"input_tokens": 777}}}),
                line(s1, "empty", 8, out=5).replace('"usage": {', '"usage": {}, "x": {', 1),   # usage 非空判据的占位（下面单独测）
            ]) + "\n")
            f.write(line(s1, "half", 9, out=12345))                                    # 没有换行的半行：不算
        with open(os.path.join(proj, s2 + ".jsonl"), "w") as f:
            f.write("\n".join([line(s2, "m2", 3, out=7, cw=300, w5=100, w1=200),        # 和 s1 重叠的一条（resume 复制历史）
                               line(s2, "p1", 1, out=20)]) + "\n")
        with open(os.path.join(proj, s1, "subagents", "agent-a1.jsonl"), "w") as f:
            f.write(line(s1, "h1", 2, out=40, cr=4) + "\n")
        with open(os.path.join(proj, s1, "subagents", "workflows", "wf_1", "agent-w1.jsonl"), "w") as f:
            f.write(line(s1, "w1", 2, out=6) + "\n")
        with open(os.path.join(proj, s1, "subagents", "workflows", "wf_1", "journal.jsonl"), "w") as f:
            f.write(line(s1, "j1", 2, out=100000) + "\n")                              # 不是 agent-* 的不算
        with open(os.path.join(proj, s3 + ".jsonl"), "w") as f:
            f.write(line(s3, "t1", 1, inp=3, out=4, cw=5, cr=6) + "\n")
            f.write(line(s3, "m2", 3, out=7, cw=300, w5=100, w1=200) + "\n")       # 和 s1 共享的一条消息（跨会话重复）
        regd = os.path.join(tmp, ".claude", "sessions")
        for pid, sid, host, kind in ((1001, s1, "local_1", "interactive"), (1002, s3, None, None), (1003, s2, None, "job")):
            j = {"pid": pid, "sessionId": sid, "name": "SECRET-NAME", "cwd": "/SECRET-CWD"}
            if host:
                j["hostSessionId"] = host
            if kind:
                j["kind"] = kind
            with open(os.path.join(regd, "%d.json" % pid), "w") as f:
                json.dump(j, f)
        with open(os.path.join(regd, "1001.abcdef.key"), "w") as f:      # 一个 .key：必须一次都不被打开
            f.write("SECRET")
        os.chmod(os.path.join(regd, "1001.abcdef.key"), 0)
        with open(os.path.join(meta_dir, "local_1.json"), "w") as f:
            json.dump({"sessionId": "local_1", "cliSessionId": s1, "priorCliSessionIds": [s2], "title": "SECRET-TITLE",
                       "cwd": "/SECRET-CWD", "postTurnSummary": {"status_detail": "SECRET-SUMMARY"}}, f)

        class A(object):
            root = tmp
            liveness = "skip"
            meter = "~/.token-meter/plugins/tokens.1m.py"
            no_meter = False
            no_ledger = True
            ledger = None
            run_dump = False
            dump_json = None
            snapshot = None
            buddyctl = None
            strict_type = False
            extra_host = []
        res = crosscheck(A)
        assert not res["problems"], res["problems"]
        by_pid = dict((e["pid"], e) for e in res["sessions"])
        assert set(by_pid) == {1001, 1002}, "kind=job 的会话不该被统计：%s" % sorted(by_pid)
        # 桌面会话 s1 + prior s2：
        #   m1: input 10, output max(1,50)=50, cw 100, cr max(1000,900)=1000 → 1160
        #   m2: out 7, cw 300 → 307（s2 里重叠的那条只算一次）
        #   m3: out 5, cw 500（当 5m）→ 505
        #   p1: 20；h1: 40+4=44；w1: 6
        want = 1160 + 307 + 505 + 20 + 44 + 6
        got = by_pid[1001]["mine"]
        assert got["total"] == want, (got, want)
        assert got["messages"] == 6, got
        assert got["input"] == 10 and got["output"] == 50 + 7 + 5 + 20 + 40 + 6, got
        assert got["cacheWrite"] == 100 + 300 + 500 and got["cacheRead"] == 1000 + 4, got
        assert by_pid[1002]["mine"]["total"] == 18 + 307, by_pid[1002]["mine"]
        assert res["cross_session_shared_message_ids"] == {"aaaaaaaa&cccccccc": 1}, res["cross_session_shared_message_ids"]
        # 冻结快照里不能有任何对话内容 / 标题
        snap = os.path.join(tmp, "snap")
        recs = [r for r in read_registry(regd, False)[0] if r["interactive"]]
        by_host, by_cli = read_metas(meta_dir[:meta_dir.index("claude-code-sessions") + len("claude-code-sessions")])
        limits = build_snapshot(tmp, snap, recs, by_host, by_cli)
        assert limits, "快照里应该冻结了文件"
        blob = b""
        for dp, _dn, fns in os.walk(snap):
            for fn in fns:
                with open(os.path.join(dp, fn), "rb") as f:
                    blob += f.read()
        for secret in (b"SECRET-TEXT", b"SECRET-TITLE", b"SECRET-CWD", b"SECRET-NAME", b"SECRET-SUMMARY"):
            assert secret not in blob, "冻结快照里出现了不该有的内容：%r" % secret
        if "meter" in by_pid[1001]:
            assert by_pid[1001]["mine_vs_meter"] and by_pid[1002]["mine_vs_meter"], "用量表口径和独立实现不一致"
        return True
    finally:
        try:
            os.chmod(os.path.join(tmp, ".claude", "sessions", "1001.abcdef.key"), 0o600)
        except OSError:
            pass
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Buddy 办公室 QA：独立的 token 交叉核对（只读，不联网，不输出对话内容）")
    ap.add_argument("--root", help="假 home 目录（FakeTree / --data-root 用）；默认真实的 home")
    ap.add_argument("--liveness", choices=["auto", "check", "skip"], default="auto",
                    help="要不要用 kill(pid,0) 过滤已死的会话：auto = 真实 home 检查，--root 时跳过")
    ap.add_argument("--meter", default="~/.token-meter/plugins/tokens.1m.py", help="用量表脚本（只读 import 它的 parse_line）")
    ap.add_argument("--no-meter", action="store_true", help="不 import 用量表")
    ap.add_argument("--ledger", help="ledger.json 路径（默认 <root>/Library/Application Support/BuddyOffice/ledger.json）")
    ap.add_argument("--no-ledger", action="store_true", help="不和 ledger.json 对照")
    ap.add_argument("--run-dump", action="store_true", help="运行 buddyctl dump --once --poll --json 并对照它的 token 列")
    ap.add_argument("--dump-json", help="用已经跑好的 dump JSON 文件对照（文件在增长时会有误差，建议用 --snapshot）")
    ap.add_argument("--buddyctl", default=None, help="buddyctl 路径（默认 <项目>/.build/release/buddyctl）")
    ap.add_argument("--snapshot", help="冻结快照目录（必须为空）：文件在增长时让两边读同一份冻结的数据")
    ap.add_argument("--extra-host", action="append", default=[], metavar="local_<uuid>",
                    help="把这个桌面会话（元数据里有 cliSessionId / priorCliSessionIds）当作活会话一起核对，用来验证 prior 会话相加；"
                         "只有配合 --snapshot 才能让 dump 也看到它（登记表是合成的，写在快照里，绝不写真实的 ~/.claude）")
    ap.add_argument("--strict-type", action="store_true", help="只按任务书的 type == assistant 判据（默认按用量表的 message.role）")
    ap.add_argument("--json", action="store_true", help="输出 JSON（只有数字）")
    ap.add_argument("--selftest", action="store_true", help="自检（合成数据，手算期望值）")
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
    if (args.run_dump or args.snapshot) and not os.path.isfile(args.buddyctl) and args.run_dump:
        print("找不到 buddyctl：%s" % args.buddyctl, file=sys.stderr)
        return 2
    res = crosscheck(args)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, sort_keys=True, indent=1))
    else:
        print_report(res)
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
