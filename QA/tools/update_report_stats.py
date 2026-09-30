#!/usr/bin/env python3
"""按 issues-*.md 重算 QA/REPORT.md 第 2 节的「区域 × 严重度」表，并打印一行统计（叙述里的数字要手动核对）。
用法：python3 QA/tools/update_report_stats.py"""
import collections, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import build_issues as b

items = []
for fn, area in b.SOURCES:
    for it in b.parse(os.path.join(b.QA, fn)):
        it["area"] = area; items.append(it)
order = [("数据层（解析器 / 模糊测试）", "数据层（解析器 / 模糊测试）"), ("状态机 / 逻辑 / token / dump", "状态机 / 逻辑 / token / dump"),
         ("应用层", "应用层（BuddyOffice）"), ("表现层 / 文字审计", "表现层 / 文字审计"), ("收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的）", "收尾前的独立复查新发现")]
rows = []
tot = collections.Counter(); ftot = 0
for key, label in order:
    its = [i for i in items if i["area"] == key]
    if not its:
        continue
    c = collections.Counter(i["sev"] for i in its)
    fixed = sum(1 for i in its if b.status_class(i["状态"]) == "已修")
    rows.append("| %s | %d | %d | %d | %d | %d | %d |" % (label, c["P0"], c["P1"], c["P2"], c["P3"], len(its), fixed))
    tot.update(c); ftot += fixed
table = ["| 区域 | P0 | P1 | P2 | P3 | 合计 | 已修 |", "|---|---|---|---|---|---|---|"] + rows + \
        ["| **合计** | **%d** | **%d** | **%d** | **%d** | **%d** | **%d** |" % (tot["P0"], tot["P1"], tot["P2"], tot["P3"], len(items), ftot)]
p = os.path.join(b.QA, "REPORT.md")
s = open(p, encoding="utf-8").read()
new = "\n".join(table)
s2 = re.sub(r"\| 区域 \| P0 \|.*?\n\| \*\*合计\*\* \|[^\n]*", lambda m: new, s, count=1, flags=re.S)
if s2 == s and new not in s:
    print("没找到要替换的表", file=sys.stderr); sys.exit(1)
open(p, "w", encoding="utf-8").write(s2)
print("P0 %d / P1 %d / P2 %d / P3 %d，共 %d 条，已修 %d；P0–P2 共 %d 个（已修 %d）" % (
    tot["P0"], tot["P1"], tot["P2"], tot["P3"], len(items), ftot, tot["P0"] + tot["P1"] + tot["P2"],
    sum(1 for i in items if i["sev"] in ("P0", "P1", "P2") and b.status_class(i["状态"]) == "已修")))
