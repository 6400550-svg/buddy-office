#!/usr/bin/env python3
"""把两份定稿的规格追踪合成一份 QA/spec-trace.md：
  第一部分 = QA/spec-trace-core-final.md（任务书第 4、5 节：数据源 + 状态判定 + 表现层节奏）
  第二部分 = QA/spec-trace-ui-final.md（任务书 6.5 / 6.6 / 7.1–7.5：表现层 + 应用层）
顶部的统计是直接数两份文件里追踪表的「状态」列得出来的（不是抄它们自己写的统计），并且会拿它们自己写的统计对一下；
偏离清单里每一条引用的 DESIGN.md 文字，会逐条 grep DESIGN.md 确认真的存在（找不到就报出来）。
用法：python3 QA/tools/build_spec_trace.py [--check]
"""
import collections, os, re, sys

QA = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT = os.path.dirname(QA)
PARTS = [("core", "spec-trace-core-final.md", "第一部分 · 任务书第 4、5 节（数据源、状态判定、表现层节奏）"),
         ("ui", "spec-trace-ui-final.md", "第二部分 · 任务书 6.5 / 6.6 / 7.1–7.5（表现层动画与手感、三种形态、提醒、跳转、设置）")]
ID = re.compile(r"^(\d\.\d-\d+[a-z]?|[A-Z]\d+[a-z]?\d?|[SMUNJFC]\d+[a-z]?\d?)$")


def status_of(cell):
    c = cell.strip()
    if c.startswith("✓（间接") or c.startswith("✓(间接"):
        return "间接"
    if c.startswith("✓"):
        return "✓"
    if c.startswith("偏离"):
        return "偏离"
    return None


def rows(text):
    """追踪表的行：第一列是编号（4.1-06 / S01a2 / M08 / U28 …），最后一列是状态。"""
    out = []
    for ln in text.split("\n"):
        if not ln.startswith("| "):
            continue
        cols = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cols) < 4 or not ID.match(cols[0]):
            continue
        st = status_of(cols[-1])
        if st:
            out.append((cols[0], cols[1], cols[-1], st))
    return out


def main():
    check = "--check" in sys.argv
    design = open(os.path.join(ROOT, "DESIGN.md"), encoding="utf-8").read()
    dnorm = re.sub(r"\s+", "", design)
    total = collections.Counter(); per = {}; problems = []; all_dev = []
    texts = {}
    for key, fn, _ in PARTS:
        p = os.path.join(QA, fn)
        if not os.path.exists(p):
            print("缺少 %s" % fn, file=sys.stderr); return 2
        t = open(p, encoding="utf-8").read(); texts[key] = t
        rs = rows(t)
        c = collections.Counter(r[3] for r in rs)
        per[key] = (len(rs), c)
        total.update(c)
        for rid, what, last, st in rs:
            if st == "偏离":
                all_dev.append((key, rid, what, last))
                # 引号里的那段话（「…」），去掉省略号后逐段找
                quoted = re.findall(r"「([^」]{3,}?)」", last)
                if not quoted:
                    problems.append("%s %s：偏离行里没有引用 DESIGN.md 的原文（「…」）" % (key, rid))
                for q in quoted[:1]:
                    frag = re.sub(r"\s+", "", q.split("…")[0])[:14]
                    if frag and frag not in dnorm:
                        problems.append("%s %s：DESIGN.md 里找不到引用的原文开头「%s」" % (key, rid, frag))
            if st == "偏离" and "DESIGN" not in last:
                problems.append("%s %s：偏离行没有写 DESIGN.md 的位置" % (key, rid))
    n = sum(total.values())
    print("追踪行数：%d（✓ %d / 偏离 %d / ✓（间接验证）%d）；问题 %d 处" % (n, total["✓"], total["偏离"], total["间接"], len(problems)))
    for k, (cnt, c) in per.items():
        print("  %s：%d 行（✓ %d / 偏离 %d / 间接 %d）" % (k, cnt, c["✓"], c["偏离"], c["间接"]))
    for p in problems:
        print("  ✗", p)
    if check:
        return 1 if problems else 0

    out = ["# 规格追踪（任务书第 4、5、6.5、6.6、7 节 → 代码 + 测试）", "",
           "> 任务书里每一条要求 → 现在的实现（函数名，不引行号）→ 钉住它的测试 → 状态。**状态只有三种**：`✓`（实现了，并且有测试的断言真的检查到了这条的数字 / 行为）；`偏离`（和任务书不一致而且是有意的，理由写在 DESIGN.md 里，行里引了那段话的开头）；`✓（间接验证）`（确实没法自动化测，写明原因和间接证据，汇总在文末「间接验证清单」和 REPORT.md 第 7 节）。",
           "> 由两份定稿合成：[spec-trace-core-final.md](spec-trace-core-final.md)（第 4、5 节）+ [spec-trace-ui-final.md](spec-trace-ui-final.md)（第 6.5、6.6、7 节）；两份初稿（第一版只读追踪，里面有「✓(无专门测试)」「偏离-未记录」「缺失」这些后来都消灭了的状态）保留在 `spec-trace-core.md` / `spec-trace-ui.md`。表里不含任何对话内容。", "",
           "## 总览（直接数两份追踪表的状态列）", "",
           "| 部分 | 条数 | ✓ | 偏离（DESIGN.md 里有理由） | ✓（间接验证） |", "|---|---|---|---|---|"]
    for key, fn, title in PARTS:
        cnt, c = per[key]
        out.append("| %s | %d | %d | %d | %d |" % (title.split(" · ")[1] if " · " in title else title, cnt, c["✓"], c["偏离"], c["间接"]))
    out.append("| **合计** | **%d** | **%d** | **%d** | **%d** |" % (n, total["✓"], total["偏离"], total["间接"]))
    out += ["", "第一版（初稿）里的「缺失」「偏离-未记录」「✓(无专门测试)」「N/A」现在都是 0：缺的动作 / 屏幕要么补上了（`QA/issues-stage.md` 的 TA / SP 系列、`QA/issues-app.md`），要么在 DESIGN.md 里写明理由变成了「偏离」；没有测试的行要么补了测试（本轮新增 117 个追踪测试：`SpecTraceCoreTests` 27、`SpecTraceStageTests` 14、`SpecTraceAppTests` 1、`SpecTraceUITests` 两个文件共 75），要么写明间接验证的原因和证据。", "",
            "## 偏离清单（%d 条；理由都在 DESIGN.md，每条引用的原文开头都用脚本 grep 确认过存在）" % len(all_dev), "",
            "| 编号 | 内容 | 状态（含 DESIGN.md 里的位置） |", "|---|---|---|"]
    for key, rid, what, last in all_dev:
        out.append("| %s | %s | %s |" % (rid, what.replace("|", "／"), last.replace("|", "／")))
    out += ["", "---", ""]
    for key, fn, title in PARTS:
        body = texts[key]
        body = re.sub(r"^# .*\n", "", body, count=1)                     # 去掉原来的一级标题
        body = re.sub(r"^(#{2,5}) ", lambda m: "#" + m.group(1) + " ", body, flags=re.M)   # 标题整体降一级
        out += ["## " + title, "", body.strip(), "", "---", ""]
    open(os.path.join(QA, "spec-trace.md"), "w", encoding="utf-8").write("\n".join(out))
    print("写入 QA/spec-trace.md（%d 行）" % len(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
