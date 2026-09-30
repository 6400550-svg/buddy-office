import Testing
import Foundation
import PixelKit
import BuddyArt
@testable import PixelKit
@testable import BuddyStage

/// 屏幕内容：关键信息不被人的头挡住、「其他 MCP」屏幕的首字母都画得出来。
@Suite struct ScreenContentTests {
    private func draw(_ k: ScreenKind, t: Double, seed: Int = 7) -> Canvas {
        let c = Canvas(width: 24, height: 15)
        let style = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        ScreenContent.draw(k, on: c, rect: IntRect(0, 0, 24, 15), t: t, gt: t, seed: seed, style: style)
        return c
    }

    /// TA-012：「其他 MCP」屏幕本该画 server 名字的首字母，4×6 像素字体原来只有数字和 M / K，其余字母都落到「?」占位字形
    /// （demo 里的 notion 画成「?」）。
    @Test func theSmallPixelFontDrawsEveryLatinCapital() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            #expect(PixelFont.small.hasGlyph(ch), "4×6 字体缺少字母 \(ch)")
            let rows = PixelFont.small.glyphs[ch] ?? []
            #expect(rows.count == 6, "\(ch) 应该是 6 行，实际 \(rows.count)")
            #expect(Set(rows.map(\.count)).count == 1, "\(ch) 每一行的宽度要一致：\(rows)")
            #expect(rows.joined().contains("#"), "\(ch) 是空的")
        }
    }

    @Test func aMcpServersInitialIsALetterTheFontCanDraw() {
        #expect(ScreenContent.mcpInitial("notion") == "N")
        #expect(ScreenContent.mcpInitial("ccd_session") == "C")
        #expect(ScreenContent.mcpInitial("Slack") == "S")
        #expect(ScreenContent.mcpInitial("123-abc") == "A")
        for name in ["", "计划", "日本語", "___", "123", "😀", "Émile"] { #expect(ScreenContent.mcpInitial(name) == "M" || PixelFont.small.hasGlyph(ScreenContent.mcpInitial(name)), "「\(name)」") }
        for name in ["notion", "ccd_session", "scheduled-tasks", "terminal", "computer-use", "1a59c906-04da-521d-bda7-7f71b9f9e01c", "Ünïcode", "计划"] {
            #expect(PixelFont.small.hasGlyph(ScreenContent.mcpInitial(name)), "「\(name)」的首字母画不出来")
        }
    }

    @Test func theMcpAppScreenNeverFallsBackToThePlaceholderGlyph() {
        for name in ["notion", "slack", "ccd_session", "terminal", "计划", "", "Zed"] {
            let (_, draws) = TextAuditRunner.withDraws { _ = draw(.mcpApp(name), t: 1) }
            let bad = draws.filter { $0.missingGlyph }
            #expect(bad.isEmpty, "「\(name)」的 MCP 屏幕上有字符落到了「?」：\(bad.map(\.text))")
        }
    }

    /// TA-013：Bash 长任务的进度条原来画在屏幕第 12–13 行，正好被人的头挡住，只露出最左边一小段；要放在第 12 行以上。
    @Test func theLongBashProgressBarIsAboveTheRowsTheHeadHides() {
        for t in [1.0, 10, 30, 45, 90] {
            let c = draw(.terminalLong, t: t)
            let dark = UInt16(Pal.dx("scr.dark")), green = UInt16(Pal.dx("scr.green"))
            // 进度条：整行（第 1…22 列）都是「轨道深色 / 进度绿色」的行
            let barRows = (0..<15).filter { y in (1...22).allSatisfy { x in let v = c.idx[y * c.width + x]; return v == dark || v == green } }
            #expect(!barRows.isEmpty, "t=\(t)：找不到进度条")
            #expect(barRows.allSatisfy { $0 < ScreenContent.headOcclusionTopRow }, "t=\(t)：进度条在第 \(barRows) 行，第 \(ScreenContent.headOcclusionTopRow) 行以下会被头挡住")
            #expect(c.idx[barRows[0] * c.width + 1] == green, "t=\(t)：进度条最左边应该已经有进度")
        }
    }

    @Test func aLongBashBarGrowsButNeverFillsUp() {
        func filled(_ t: Double) -> Int {
            let c = draw(.terminalLong, t: t); let y = ScreenContent.longBashBarY
            return (1...22).filter { c.idx[y * c.width + $0] == UInt16(Pal.dx("scr.green")) }.count
        }
        #expect(filled(2) < filled(20) && filled(20) < filled(60))
        #expect(filled(100_000) < 22, "进度条永远不会假装跑满")
    }

    /// 连续滚动的屏幕在办公室稳态的 15 fps 渲染节拍下，每一步恰好占整数帧（原来文档 150 ms 一步 = 2、3、2、3 帧，日志 300 ms 一步 = 4、5、4、5 帧，滚起来一顿一顿）。
    private func runLengths(_ k: ScreenKind, fps: Double, seconds: Double, jitter: Double = 0) -> [Int] {
        var runs: [Int] = [], last: [UInt32]? = nil
        var rng = SystemRandomNumberGenerator()
        for i in 0..<Int(seconds * fps) {
            let t = Double(i) / fps + (jitter > 0 ? Double.random(in: -jitter...jitter, using: &rng) : 0)
            let c = draw(k, t: max(0, t))
            let px = (0..<(c.width * c.height)).map { c.rgba[$0] }
            if let l = last, l == px { runs[runs.count - 1] += 1 } else { runs.append(1) }
            last = px
        }
        return Array(runs.dropFirst().dropLast())
    }

    @Test func documentAndLogScrollingStepsAreWholeFramesAt15fps() {
        for (kind, frames) in [(ScreenKind.doc("swift"), 2), (.log, 5)] {
            let runs = runLengths(kind, fps: 15, seconds: 20)
            #expect(runs.count > 20, "\(kind)：滚动应该一直在走（\(runs.count) 步）")
            #expect(runs.allSatisfy { $0 == frames }, "\(kind)：每一步应该是 \(frames) 帧，实际 \(Set(runs).sorted())")
            // 计时有 ±10 ms 的抖动也不会让某一步多 / 少一帧
            let jittered = runLengths(kind, fps: 15, seconds: 20, jitter: 0.010)
            #expect(jittered.allSatisfy { $0 == frames }, "\(kind) 有抖动：每一步应该是 \(frames) 帧，实际 \(Set(jittered).sorted())")
        }
    }

    @Test func rhythmStepsAreEvenAndNeverSkip() {
        // 终端输出的滚动步长是 6 帧
        var runs: [Int] = [], lastStep = -1
        for i in 0..<300 {
            let step = ScreenContent.rhythm(Double(i) / 15, every: ScreenContent.terminalScrollEvery)
            if step != lastStep { runs.append(1); lastStep = step } else { runs[runs.count - 1] += 1 }
        }
        #expect(runs.dropFirst().dropLast().allSatisfy { $0 == 6 }, "\(runs)")
    }
}
