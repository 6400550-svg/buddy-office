#!/usr/bin/env python3
"""回归测试「修复前失败、修复后通过」的可复现验证（文字审计这一组，TA-001…TA-010 + 检测器变异）。

做法：把项目拷进一个隔离的工作树（不动项目本身），然后逐个：
  1. 先在「修复后」的源码上跑对应的测试——必须通过；
  2. 对工作树打上「撤销这个修复」的补丁（把修复前的行为原样放回去），再跑同一个测试——必须失败；
  3. 还原补丁。
检测器灵敏度测试的验证方法是「变异」：让 TextAudit.check 对某一类问题一律不报，对应的灵敏度测试必须失败。

用法：python3 QA/tools/verify_fail_before.py --tree <隔离工作树目录> [--only TA-001,TA-002,MUT-1] [--out QA/evidence/fail-before-ta.md]
      （要在沙箱外跑：里面会调 swift test。）
"""
import argparse, os, re, shutil, subprocess, sys, time

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# 每个修复：(文件, 修复后的原文, 修复前的原文)；tests = swift test --filter 的参数（正则，可多个）
FIXES = {
    "TA-001": dict(
        title="桌牌文字对比度（深色字，白天 / 夜里都 ≥ 4.5:1）",
        patches=[("Sources/BuddyStage/OfficeScene.swift",
                  "static let plateTitleInk = RGBA8(hex: 0x1E1518), plateStatusInk = RGBA8(hex: 0x261A20)",
                  "static let plateTitleInk = RGBA8(hex: 0x3A2A22), plateStatusInk = RGBA8(hex: 0x6E4C38)")],
        tests=["TextAuditRegressionTests/plateTextMeetsContrastAtAnyTimeOfDay"]),
    "TA-002": dict(
        title="桌牌高度 12 像素（原 10 像素放不下标题 + 状态两行）",
        patches=[("Sources/BuddyArt/Workstation/SeatGeometry.swift", "plateH = 12", "plateH = 10")],
        tests=["TextAuditRegressionTests/twoLinePlateTextStaysInsideThePlate"]),
    "TA-003": dict(
        title="emoji 缩到 0.78 倍（原样大小的 emoji 字形比苹方行盒高）",
        patches=[("Sources/PixelKit/TextRenderer.swift", "style.size * 0.78", "style.size * 1.0")],
        tests=["TextAuditRegressionTests/emojiInkStaysInsideTheCJKInkRange"]),
    "TA-004": dict(
        title="睡着的 zzz 两个 z 之间留 1 像素",
        patches=[("Sources/BuddyStage/SeatRenderer.swift",
                  'PixelFont.tiny.draw("z", x: ix, y: iy + 4 - (step == 0 ? 1 : 0)',
                  'PixelFont.tiny.draw("z", x: ix + 1, y: iy + 4 - (step == 0 ? 1 : 0)')],
        tests=["TextAuditRegressionTests/sleepingBuddysTwoZsDoNotTouch"]),
    "TA-005": dict(
        title="「今天还没人上班」牌子：更亮的字 + 画在桌椅上面（原来烘进背景、被桌椅盖住，字对比度 4.45:1）",
        patches=[("Sources/BuddyStage/OfficeScene.swift", "static let signInk = RGBA8(hex: 0xF8EFDD)", "static let signInk = RGBA8(hex: 0xE6D4BC)"),
                 ("Sources/BuddyStage/OfficeScene.swift",
                  "if signZoom > 0 { signRect = Self.signGeometry(zoom: signZoom, layout: lay, viewportH: viewportH) }",
                  "if signZoom > 0 { signRect = Self.signGeometry(zoom: signZoom, layout: lay, viewportH: viewportH); Self.drawSign(signRect, on: bg, light: light) }"),
                 ("Sources/BuddyStage/OfficeScene.swift",
                  "if signZoom > 0, work.mayTouch(signRect) { Self.drawSign(signRect, on: work, light: light) }",
                  "")],
        tests=["TextAuditRegressionTests/emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks"]),
    "TA-006a": dict(
        title="悬停卡片不盖住被悬停那个人自己的头 / 屏幕 / 气泡",
        patches=[("Sources/BuddyStage/OfficeScene.swift", " && !avoid.contains { r.intersection($0) != nil }", "")],
        tests=["TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner"]),
    "TA-006b": dict(
        title="被卡片盖住的桌牌文字收起来",
        patches=[("Sources/BuddyStage/OfficeScene.swift",
                  'if let hp = hoverPlacementValue { texts.removeAll { $0.tag.hasPrefix("plate") && (Self.artBounds($0, zoom: options.zoom).intersection(hp.rect) != nil) } }',
                  "")],
        tests=["TextAuditRegressionTests/plateTextUnderTheHoverCardIsHidden"]),
    "TA-007": dict(
        title="悬停卡片宽度上限按窗口宽反推（原来比窗口只多 1 像素，窄窗口里放不下）",
        patches=[("Sources/BuddyStage/OfficeScene.swift",
                  "let maxWpt = max(40, min(250, CGFloat(vp.w - 5) * z - 18)), maxHpt = max(40, CGFloat(vp.h - 5) * z)",
                  "let maxWpt = max(60, min(250, CGFloat(vp.w - 4) * z - 18)), maxHpt = max(40, CGFloat(vp.h - 4) * z - 4)")],
        tests=["TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner"]),
    "TA-008": dict(
        title="悬停卡片兜底位置（窗口小到候选位置都放不下时，网格搜索一个不盖住人的地方）",
        patches=[("Sources/BuddyStage/OfficeScene.swift", "            if hoverPlacementValue == nil {\n                let anchor", "            if false, hoverPlacementValue == nil {\n                let anchor")],
        tests=["TextAuditRegressionTests/hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner"],
        # 兜底位置只有在缩放不被夹住时才用得上：同时撤销 TA-009 的夹取，才能复现「窗口比工位还小」的情形
        extra_patches=[("Sources/BuddyStage/OfficeLayout.swift",
                        "let fit = max(allowOne ? 1 : 2, min(Int(contentW / oneColumn), Int(contentH / oneRow)))",
                        "let fit = max(allowOne ? 1 : 2, Int(contentW / oneColumn))")]),
    "TA-009": dict(
        title="实际缩放按窗口宽和高夹到「至少放得下一个整工位」",
        patches=[("Sources/BuddyStage/OfficeLayout.swift",
                  "let fit = max(allowOne ? 1 : 2, min(Int(contentW / oneColumn), Int(contentH / oneRow)))",
                  "let fit = max(allowOne ? 1 : 2, Int(contentW / oneColumn))")],
        tests=["TextAuditRegressionTests/zoomIsClampedSoAtLeastOneWholeSeatFits"]),
    "TA-010": dict(
        title="空标题 / 全空白标题显示占位文字",
        patches=[("Sources/BuddyStage/PlateCopy.swift",
                  't.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（没有标题）" : t', "t")],
        tests=["TextAuditRegressionTests/blankTitlesGetAPlaceholderOnPlatesAndCards"]),
}

FIXES["TA-011"] = dict(
    title="审计工具自身：负的设备像素坐标向下取整（原来向零取整，读错画布行 → 看不见的桌牌被误报对比度）",
    patches=[("Sources/BuddyStage/TextAudit.swift", "static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }", "static func floorDiv(_ a: Int, _ b: Int) -> Int { a / b }")],
    tests=["TextAuditDetectorTests/floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow", "TextAuditMatrixTests/quickMatrixHasZeroViolationsAndReallyCoversTheScenes"])


def _drop_latin_capitals(path):
    """撤销 TA-012：把 4×6 字体补上的 A–Z 拿掉，只留原来的 M 和 K。"""
    s = open(path, encoding="utf-8").read()
    a = s.index('        "A": [".##.", "#..#", "#..#", "####", "#..#", "#..#"]')
    b = s.index('"Z": ["####", "...#", "..#.", ".#..", "#...", "####"],') + len('"Z": ["####", "...#", "..#.", ".#..", "#...", "####"],')
    old_line = '        "M": ["#..#", "####", "####", "#..#", "#..#", "#..#"], "K": ["#..#", "#.#.", "##..", "#.#.", "#..#", "#..#"],'
    open(path, "w", encoding="utf-8").write(s[:a] + old_line + s[b:])


FIXES["TA-012"] = dict(
    title="「其他 MCP」屏幕的 server 首字母：4×6 像素字体补上 A–Z（原来只有数字和 M / K，其余落到「?」）",
    patches=[("Sources/PixelKit/PixelFont.swift", _drop_latin_capitals),
             # 原来的首字母取法：名字里第一个字母（不管字体画不画得出来），画不出来就落到「?」占位字形
             ("Sources/BuddyStage/ScreenContent.swift", "let letter = String(Self.mcpInitial(name))", "let letter = String((name.first { $0.isLetter } ?? \"M\").uppercased())")],
    tests=["ScreenContentTests/theSmallPixelFontDrawsEveryLatinCapital", "ScreenContentTests/theMcpAppScreenNeverFallsBackToThePlaceholderGlyph"])
FIXES["TA-013"] = dict(
    title="Bash 长任务的进度条移到屏幕第 5–6 行（原来在第 12–13 行，被人的头挡住）",
    patches=[("Sources/BuddyStage/ScreenContent.swift", "static let longBashBarY = 5", "static let longBashBarY = 12")],
    tests=["ScreenContentTests/theLongBashProgressBarIsAboveTheRowsTheHeadHides"])

FIXES["SP-01"] = dict(
    title="显示器关机：人离开后屏幕内容用 Bayer 抖动倒放 300 ms 熄灭（原来一帧硬切成黑屏；任务书 5.5 / 6.5 / 6.6）",
    patches=[("Sources/BuddyStage/OfficeScene.swift",
              "if screenFade[seat] == nil, let m = screenMemory[seat] {", "if false, screenFade[seat] == nil, let m = screenMemory[seat] {")],
    tests=["MonitorTests/theMonitorFadesOutOver300msInsteadOfCuttingToBlack"])
FIXES["SP-02"] = dict(
    title="指示灯 3 个色阶呼吸：待机灯 灭→半亮→亮→半亮（4 s），等待琥珀灯 暗→亮→更亮→亮（1.25 s = 0.8 Hz）（原来待机灯 2 秒亮 2 秒灭、等待灯是固定色）",
    patches=[("Sources/BuddyStage/SeatRenderer.swift",
              'case 2: return ["led.wait.lo", "led.wait", "led.wait.hi", "led.wait"][Int(gt / 0.3125) & 3]', 'case 2: return "led.wait"'),
             ("Sources/BuddyStage/SeatRenderer.swift",
              'case 3: return ["led.off", "led.mid", "led.on", "led.mid"][Int(gt) & 3]', 'case 3: return (Int(gt / 2) & 1) == 1 ? "led.on" : "led.off"')],
    tests=["MonitorTests/theStandbyLightBreathesThroughThreeLevelsSlowly", "MonitorTests/theWaitingLightCyclesThroughThreeAdjacentLevelsAt0_8Hz"])

FIXES["SP-03"] = dict(
    title="连续滚动的屏幕（文档 / 日志 / 终端）按整数个渲染帧一步（原来文档 150 ms、日志 300 ms 一步，在 15 fps 下是 2、3、2、3 帧的不均匀节奏）",
    patches=[("Sources/BuddyStage/ScreenContent.swift",
              "static func rhythm(_ t: Double, every: Double) -> Int { Int(((t + 0.02) / every).rounded(.down)) }",
              "static func rhythm(_ t: Double, every: Double) -> Int { Int((t / (every == 2.0 / 15 ? 0.15 : (every == 1.0 / 3 ? 0.3 : every))).rounded(.down)) }")],
    tests=["ScreenContentTests/documentAndLogScrollingStepsAreWholeFramesAt15fps"])

FIXES["SP-04"] = dict(
    title="WebSearch 先打字再用鼠标、未知工具打字和鼠标交替（任务书 6.5；原来 WebSearch 只用鼠标、未知工具只打字）",
    patches=[("Sources/BuddyStage/Performer.swift", '((c.name == "WebSearch" && elapsed < 2.5) ? .typing : .mouse)', ".mouse"),
             ("Sources/BuddyStage/Performer.swift", "case .unknown: return safeInt(elapsed / 3) % 2 == 0 ? .typing : .mouse", "case .unknown: return .typing")],
    tests=["PerformerMappingTests/everyRowOfTheStateToAnimationTable"])

FIXES["C-033"] = dict(
    title="表现层对时间差里的怪值（NaN / 无穷 / 天文数字）不再 `Int(x)` trap（数据层报告 C-033，由表现层修）",
    patches=[("Sources/BuddyStage/PlateCopy.swift",
              "public static func wholeSeconds(_ x: Double) -> Int { x.isFinite ? max(0, min(safeInt(x), 1_000_000_000)) : 0 }",
              "public static func wholeSeconds(_ x: Double) -> Int { max(0, Int(x)) }")],
    tests=["ExtremeValuesTests/durationFormattersNeverTrapAndCapAtAboutThirtyYears"])

FIXES["SP-05"] = dict(
    title="App 启动时就在的会话：直接坐好、显示器从左到右依次开机（100 ms 一台）（原来所有人先是空闲姿势 + 黑屏，0.8 / 1.5 秒后一起硬切）",
    patches=[("Sources/BuddyStage/Performer.swift", "let adoptNow = !started && !s.appearedAfterLaunch", "let adoptNow = false")],
    tests=["MonitorTests/monitorsOfSessionsPresentAtLaunchBootLeftToRightAt100msIntervals"])

FIXES["C-032"] = dict(
    title="应用层读桌面元数据走 FileIO 统一入口（原来直接 FileManager 读，指向 .key 的符号链接会被读到；现在由源码审计守着，不再碰全局的 FileIO 计数器，见 R2-005）",
    patches=[("Sources/BuddyOffice/JumpService.swift", "guard let d = FileIO.readAll(path), let j", "guard let d = FileManager.default.contents(atPath: path), let j")],
    tests=["DesktopMetaFileIOTests/theOfficeLayerReadsFilesOnlyThroughFileIO"])

# 检测器变异：让 check() 对某一类一律不报，对应的灵敏度测试必须失败
KINDS = [("overlap", "class1OverlappingTextIsCaught"), ("clipped", "class2"), ("ellipsis", "class3LongTextWithoutAnEllipsisIsCaught"),
         ("covers", "class4"), ("fontSize", "class5FontsBelowNinePointsAreCaught"), ("contrast", "class6LowContrastAgainstTheRealCanvasIsCaught"),
         ("alignment", "class7TextNotOnWholeDevicePixelsIsCaught"), ("pixelDigits", "class8")]
for n, (kind, test) in enumerate(KINDS, 1):
    FIXES[f"MUT-{n}"] = dict(
        title=f"检测器变异：check() 对第 {n} 类（.{kind}）一律不报",
        patches=[("Sources/BuddyStage/TextAudit.swift",
                  "func add(_ kind: Kind, _ detail: String, _ rect: CGRect? = nil, tag: String = \"\") { out.append(",
                  f"func add(_ kind: Kind, _ detail: String, _ rect: CGRect? = nil, tag: String = \"\") {{ if kind == .{kind} {{ return }}; out.append(")],
        tests=[f"TextAuditDetectorTests/{test}"])


def sh(cmd, cwd, log):
    log.write(f"\n$ {cmd}\n"); log.flush()
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    out = p.stdout + p.stderr
    log.write(out); log.flush()
    return p.returncode, out


def take_snapshot(tree):
    """把项目当前的源码拍一张快照（别的工程师可能还在改项目，验证要基于同一份稳定的源码）。"""
    snap = os.path.join(tree, "_snapshot")
    for d in ["Sources", "Tests", "scripts"]:
        os.makedirs(os.path.join(snap, d), exist_ok=True)
        subprocess.run(["rsync", "-a", "--delete", os.path.join(PROJECT, d) + "/", os.path.join(snap, d) + "/"], check=True)
    shutil.copy(os.path.join(PROJECT, "Package.swift"), os.path.join(snap, "Package.swift"))


def sync_from_project(tree):
    """工作树 ← 快照（撤销上一个补丁）。"""
    snap = os.path.join(tree, "_snapshot")
    for d in ["Sources", "Tests", "scripts"]:
        os.makedirs(os.path.join(tree, d), exist_ok=True)
        subprocess.run(["rsync", "-a", "--delete", os.path.join(snap, d) + "/", os.path.join(tree, d) + "/"], check=True)
    shutil.copy(os.path.join(snap, "Package.swift"), os.path.join(tree, "Package.swift"))


def apply(tree, patches):
    for patch in patches:
        path = os.path.join(tree, patch[0])
        if callable(patch[1]):
            patch[1](path)
            continue
        _, old, new = patch
        s = open(path, encoding="utf-8").read()
        if old not in s:
            raise SystemExit(f"补丁对不上：{patch[0]} 里找不到\n  {old[:120]}")
        open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))


def run_tests(tree, scratch, tests, log):
    """返回 (是否全部通过, 失败的断言行)。"""
    filt = " ".join(f"--filter '{t}'" for t in tests)
    for attempt in range(3):
        rc, out = sh(f"BUDDY_SCRATCH={scratch} scripts/dev.sh test {filt}", tree, log)
        if "Test run with" in out:          # 编译过了、测试真的跑了；否则是编译被打断（冷编译偶尔会），重试
            break
    fails = [l.strip() for l in out.splitlines() if l.startswith("✘") and "recorded an issue" in l]
    summary = [l.strip() for l in out.splitlines() if l.startswith("✘ Test run") or l.startswith("✔ Test run")]
    return rc == 0, fails, summary


def build_before(tree, scratch, log):
    """把 FIXES 里所有产品修复（不含 MUT 变异）一次性撤销，编出 release 版 buddyctl——「修复前」的产品行为 + 现在的审计工具，
    用来出「修复前 / 修复后」对比图（QA/tools/make_before_after.sh）。返回 buddyctl 的路径。"""
    sync_from_project(tree)
    for fid, f in FIXES.items():
        if fid.startswith("MUT-"):
            continue
        apply(tree, f["patches"])                     # extra_patches（TA-008 为了复现而额外撤销 TA-009）这里不用：TA-009 自己已经撤销了
    for attempt in range(3):
        rc, out = sh(f"BUDDY_SCRATCH={scratch} scripts/dev.sh build -c release -j 2 --product buddyctl", tree, log)
        if rc == 0 and "Build complete" in out:
            break
    return os.path.join(tree, scratch, "release", "buddyctl")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", required=True)
    ap.add_argument("--scratch", default=".build-fb")
    ap.add_argument("--only", default="")
    ap.add_argument("--resnap", action="store_true", help="重新拍源码快照（默认沿用工作树里已有的快照）")
    ap.add_argument("--build-before", action="store_true", help="撤销全部产品修复并编出 release 版 buddyctl（出前后对比图用），然后退出")
    ap.add_argument("--out", default=os.path.join(PROJECT, "QA", "evidence", "fail-before-stage.md"))
    a = ap.parse_args()
    os.makedirs(a.tree, exist_ok=True)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    ids = [x for x in a.only.split(",") if x] or list(FIXES)
    if a.resnap or not os.path.isdir(os.path.join(a.tree, "_snapshot")):
        take_snapshot(a.tree)
    log = open(os.path.join(a.tree, "verify.log"), "a", encoding="utf-8")
    if a.build_before:
        print(build_before(a.tree, a.scratch, log))
        return
    rows = []
    for fid in ids:
        f = FIXES[fid]
        sync_from_project(a.tree)
        ok_after, _, sum_after = run_tests(a.tree, a.scratch, f["tests"], log)
        apply(a.tree, f["patches"] + f.get("extra_patches", []))
        ok_before, fails_before, sum_before = run_tests(a.tree, a.scratch, f["tests"], log)
        rows.append((fid, f["title"], f["tests"], ok_after, ok_before, fails_before, sum_before))
        status = "✅ 修复前失败、修复后通过" if (ok_after and not ok_before) else "❌ 不符合预期"
        print(f"{fid}: 修复后 {'通过' if ok_after else '失败'}；修复前 {'通过（不对！）' if ok_before else '失败'} → {status}", flush=True)
    sync_from_project(a.tree)
    with open(a.out, "w", encoding="utf-8") as w:
        w.write("# 回归测试：修复前失败、修复后通过（表现层 / 文字审计组）\n\n")
        w.write(f"生成：{time.strftime('%Y-%m-%d %H:%M')}，脚本 QA/tools/verify_fail_before.py（在隔离工作树里逐个撤销修复再跑对应的测试）。\n\n")
        w.write("| 编号 | 修复 | 回归测试 | 修复后 | 撤销修复后 |\n|---|---|---|---|---|\n")
        for fid, title, tests, ok_after, ok_before, fails, _ in rows:
            w.write(f"| {fid} | {title} | `{'`、`'.join(tests)}` | {'通过' if ok_after else '**失败**'} | {'**仍然通过（测试没有抓到）**' if ok_before else '失败 ✅'} |\n")
        w.write("\n## 撤销修复后测试失败的原文（每项前几行）\n\n")
        for fid, title, tests, ok_after, ok_before, fails, summ in rows:
            w.write(f"### {fid} {title}\n\n```\n")
            for l in fails[:6]:
                w.write(l[:400] + "\n")
            for l in summ[:1]:
                w.write(l + "\n")
            w.write("```\n\n")
    print(f"写入 {a.out}")


if __name__ == "__main__":
    main()
