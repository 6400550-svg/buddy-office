#!/usr/bin/env python3
"""把 QA/evidence/fail-before-stage.md 里「撤销修复后测试失败的原文」摘成一行，写进 QA/issues-stage.md 每一节的「修复前失败」里
（表现层这一组的证据是 verify_fail_before.py 在隔离工作树里逐个撤销修复得到的，原文在 evidence 里；这里让每条记录自己就带着那一行）。
已经有「修复前失败」行的节不动；可以重复运行。
用法：python3 QA/tools/add_fail_before_lines.py
"""
import os, re

QA = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ev = open(os.path.join(QA, "evidence", "fail-before-stage.md"), encoding="utf-8").read()
sections = {}
_cur, _in = None, False
for l in ev.split("\n"):
    m = re.match(r"^### (\S+) ", l)
    if m:
        _cur, _in = m.group(1), False
        continue
    if _cur and l.startswith("```"):
        if not _in:
            _in = True; sections.setdefault(_cur, [])
        else:
            _in = False; _cur = None
        continue
    if _cur and _in:
        sections[_cur].append(l)

def summarize(lines):
    first = next((l for l in lines if l.startswith("✘") and "recorded an issue" in l), None) or next((l for l in lines if l.strip()), "")
    first = re.sub(r"\s+", " ", first).strip()
    if len(first) > 190:
        first = first[:190] + "…"
    last = next((l for l in reversed(lines) if "Test run with" in l), "")
    m = re.search(r"with (\d+) issues?", last)
    return first, (m.group(1) if m else "?")

path = os.path.join(QA, "issues-stage.md")
text = open(path, encoding="utf-8").read().split("\n")
out, cur, done, i = [], None, 0, 0
head = re.compile(r"^###\s+(\S+)\s+\[(P[0-3])\]")
# 先找出每一节的范围
starts = [(k, head.match(l).group(1)) for k, l in enumerate(text) if head.match(l)]
def section_end(s, j):
    e = starts[j + 1][0] if j + 1 < len(starts) else len(text)
    for k in range(s + 1, e):
        if text[k].startswith("## ") or text[k].strip() == "---":
            return k
    return e
bounds = {sid: (s, section_end(s, j)) for j, (s, sid) in enumerate(starts)}
insert_at = {}
for sid, (s, e) in bounds.items():
    body = text[s:e]
    if any(l.startswith("- 修复前失败") for l in body):
        continue
    key = sid if sid in sections else ({"TA-006": "TA-006a"}.get(sid))   # TA-006 在 evidence 里分成 006a / 006b 两项，取 a
    if key is None:
        continue
    first, n = summarize(sections[key])
    st = next((s + k for k, l in enumerate(body) if l.startswith("- 状态")), None)
    if st is None:
        continue
    insert_at[st] = "- 修复前失败：撤销这个修复后重跑回归测试 → 失败（%s 个 issue）：`%s`；修复后通过。各项的完整原文见 [evidence/fail-before-stage.md](evidence/fail-before-stage.md) 的「%s」一节（QA/tools/verify_fail_before.py 在隔离工作树里逐个撤销修复得到）。" % (n, first.replace("`", "'"), sid)
for k, l in enumerate(text):
    if k in insert_at:
        out.append(insert_at[k]); done += 1
    out.append(l)
open(path, "w", encoding="utf-8").write("\n".join(out))
print("写入 %d 处「修复前失败」" % done)
