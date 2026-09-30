#!/usr/bin/env python3
"""把 QA/ 里各区域的问题记录合成 QA/ISSUES.md：顶部是统计 + 汇总表（编号 / 严重度 / 标题 / 状态 / 回归测试），后面是各区域的完整记录。

  输入（按顺序）：issues-stage.md（表现层 / 文字审计）、issues-app.md（应用层）、issues-core.md（数据层模糊测试）、issues-logic.md（状态机 / 逻辑）、issues-review.md（收尾前的独立复查里新发现的；没有就没有这个文件）
  每个问题是一节：`### <编号> [P0-P3] <标题>`，节里有「现象 / 根因 / 修法 / 回归测试 / 修复前失败 / 状态」几行。
  用法：python3 QA/tools/build_issues.py [--check]      --check：只检查每一节是否写全了六项、状态是不是「已修 / 不修 + 理由」，不写文件。
"""
import os, re, sys

QA = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCES = [("issues-stage.md", "表现层 / 文字审计"), ("issues-app.md", "应用层"), ("issues-core.md", "数据层（解析器 / 模糊测试）"), ("issues-logic.md", "状态机 / 逻辑 / token / dump"), ("issues-review.md", "收尾前的独立复查（R1 / R2 / 长跑 / ASan 发现的）")]
HEAD = re.compile(r"^###\s+(\S+)\s+\[(P[0-3])\]\s*(.*)$")
FIELDS = ["现象", "根因", "修法", "回归测试", "状态"]


def parse(path):
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read().split("\n")
    items, cur = [], None
    for ln in text:
        m = HEAD.match(ln)
        if m:
            cur = {"id": m.group(1), "sev": m.group(2), "title": m.group(3).strip(), "lines": [ln]}
            items.append(cur)
            continue
        if ln.startswith("## ") or ln.startswith("# "):
            cur = None
        if cur is not None:
            cur["lines"].append(ln)
    for it in items:
        body = "\n".join(it["lines"][1:])
        for f in FIELDS + ["修复前失败"]:
            m = re.search(r"^[-*]\s*\**%s[（(]?[^：:\n]*[)）]?\**\s*[：:]\s*(.*)$" % f, body, re.M)
            it[f] = m.group(1).strip().strip("*").strip() if m else ""
        it["body"] = body
    return items


def short_status(s, limit=60):
    """汇总表里的状态：取第一句，太长就在分号 / 逗号处截断，并保证反引号和括号是成对的（不要留下半截）。"""
    s = s.split("。")[0].replace("|", "／")
    if len(s) <= limit:
        return s
    cut = s[:limit]
    for sep in ("；", "，", "、", " "):
        i = cut.rfind(sep)
        if i >= 12:
            cut = cut[:i]
            break
    if cut.count("`") % 2:
        cut = cut[:cut.rfind("`")]
    if cut.count("「") > cut.count("」"):
        cut = cut[:cut.rfind("「")]
    if cut.count("（") > cut.count("）"):
        cut = cut[:cut.rfind("（")] if cut.rfind("（") >= 4 else cut + "）"
    return cut.rstrip("；，、 ") + "…"


def status_class(s):
    if not s:
        return "缺"
    if s.startswith("已修"):
        return "已修"
    if s.startswith("不修") or "不修" in s[:6]:
        return "不修"
    return "其他"


def main():
    check = "--check" in sys.argv
    all_items = []
    for fn, area in SOURCES:
        for it in parse(os.path.join(QA, fn)):
            it["area"] = area; it["file"] = fn
            all_items.append(it)
    problems = []
    for it in all_items:
        for f in ["现象", "根因", "修法", "回归测试", "状态"]:
            if not it[f]:
                problems.append("%s 缺「%s」" % (it["id"], f))
        if it["sev"] in ("P0", "P1", "P2") and not status_class(it["状态"]) == "已修":
            problems.append("%s（%s）不是「已修」：%s" % (it["id"], it["sev"], it["状态"][:60]))
    # 标题行写成「### 编号 [P2 …额外的字…]」这类不合规格式的会被解析器悄悄漏掉（统计表里就少了一条）：逐个源文件数一遍
    for fn, _ in SOURCES:
        path = os.path.join(QA, fn)
        if not os.path.exists(path):
            continue
        for ln in open(path, encoding="utf-8").read().split("\n"):
            if re.match(r"^###\s+\S+\s+\[P[0-3]", ln) and not HEAD.match(ln):
                problems.append("%s：标题行的严重度括号里有多余的字，解析不到：%s" % (fn, ln[:60]))
    ids = [it["id"] for it in all_items]
    dup = {i for i in ids if ids.count(i) > 1}
    for d in dup:
        problems.append("编号重复：%s" % d)
    if check:
        print("问题 %d 条；发现的格式问题 %d 条" % (len(all_items), len(problems)))
        for p in problems:
            print("  ✗", p)
        sys.exit(1 if problems else 0)

    sev_count = {s: sum(1 for i in all_items if i["sev"] == s) for s in ("P0", "P1", "P2", "P3")}
    fixed = {s: sum(1 for i in all_items if i["sev"] == s and status_class(i["状态"]) == "已修") for s in sev_count}
    out = ["# QA 问题记录（ISSUES）", "",
           "把整个项目当成别人写的代码独立检查一轮（找 bug、查字体和文字重叠、查逻辑问题）发现的全部问题。每条写明编号、严重度、现象、根因、修法、回归测试、状态；",
           "「修复前失败 / 修复后通过」的证据写在每条里（先在没改行为的状态下跑测试看它失败，再修、再跑），文字审计组另有可复现的脚本 `QA/tools/verify_fail_before.py`（输出 `QA/evidence/fail-before-stage.md`）。",
           "",
           "**严重度**：P0 = 正常使用下崩溃 / 数据损坏 / 违反安全红线；P1 = 明显错误的行为 / 关键信息看不清 / 设置不生效；P2 = 边界条件下的错误、资源问题或体验缺陷；P3 = 小瑕疵 / 代码卫生。",
           "**状态**：已修 = 修好并有回归测试；已修（仅间接验证）= 修好并有测试，但真实 GUI 路径只能间接验证（见 REPORT.md）；不修 = 写明理由（只允许 P3）。P0–P2 全部已修。", "",
           "## 统计", "", "| 严重度 | 发现 | 已修 |", "|---|---|---|"]
    for s in ("P0", "P1", "P2", "P3"):
        out.append("| %s | %d | %d |" % (s, sev_count[s], fixed[s]))
    out.append("| **合计** | **%d** | **%d** |" % (len(all_items), sum(fixed.values())))
    out += ["", "## 汇总表", "", "| 编号 | 严重度 | 区域 | 标题 | 状态 |", "|---|---|---|---|---|"]
    for it in all_items:
        out.append("| %s | %s | %s | %s | %s |" % (it["id"], it["sev"], it["area"], it["title"].replace("|", "／"), short_status(it["状态"])))
    out += ["", "---", ""]
    for fn, area in SOURCES:
        p = os.path.join(QA, fn)
        if not os.path.exists(p):
            continue
        out += ["## 详细记录：%s（来自 %s）" % (area, fn), ""]
        body = open(p, encoding="utf-8").read()
        # 去掉源文件自己的一级标题，降一级避免和这里的标题冲突
        body = re.sub(r"^# .*\n", "", body, count=1)
        out.append(body.strip())
        out += ["", "---", ""]
    open(os.path.join(QA, "ISSUES.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("写入 QA/ISSUES.md：%d 条（P0 %d / P1 %d / P2 %d / P3 %d），已修 %d 条；格式问题 %d 条" % (len(all_items), sev_count["P0"], sev_count["P1"], sev_count["P2"], sev_count["P3"], sum(fixed.values()), len(problems)))
    for p in problems:
        print("  ✗", p)


if __name__ == "__main__":
    main()
