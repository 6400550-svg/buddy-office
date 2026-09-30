import Testing
import Foundation
import CoreGraphics
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

// text-audit 的测试分三层：
//   1. 检测器灵敏度：8 类问题各造一个「一定违规」的输入，必须抓到；对应的「干净」输入必须不报。
//      （审计工具自己得先证明它不是摆设，再谈「0 违规」有没有意义。）
//   2. 每个修复的回归测试：把当初审计抓到的问题原样复现，修复前失败、修复后通过（证据在 QA/ISSUES.md）。
//   3. 缩减版压力矩阵：办公室 / 悬停卡片 / 小鱼缸 / 宠物条 / 提示卡 × 白天夜晚 × 隐私 × 最小和默认窗口，违规必须为 0，
//      并且要求覆盖量（组合数、文字段数、悬停卡片真的画出来）——防止「0 违规」只是因为什么都没查。

private let darkInk = TextStyle(size: 11, color: RGBA8(hex: 0x1E1518), weight: .semibold)

/// 一块纯色画布 + 恒等调色板：检测器灵敏度测试用。
private struct Rig {
    let canvas: Canvas
    let style: Resolved
    let bgIdx: UInt8
    let inkIdx: UInt8
    init(w: Int = 120, h: Int = 60, bg: UInt32 = 0xF2E6CF, ink: UInt32 = 0x1E1518) {
        var pal = MasterPalette()
        let b = pal.add("bg", RGBA8(hex: bg)), i = pal.add("ink", RGBA8(hex: ink))
        style = Resolved(map: nil, lutA: PaletteLUT.identity(pal))
        canvas = Canvas(width: w, height: h)
        canvas.fillRect(canvas.bounds, value: UInt8(b), style: style)
        bgIdx = UInt8(b); inkIdx = UInt8(i)
    }
    func input(_ texts: [TextItem] = [], regions: [AuditRegion] = [], draws: [PixelFont.DrawRecord] = [], zoom: Int = 2) -> TextAudit.Input {
        TextAudit.Input(frame: Frame(canvas: canvas, texts: texts), zoom: zoom, scale: 2, regions: regions, pixelDraws: draws, scene: "测试", combo: "灵敏度")
    }
    /// 把 body 里的像素字 draw 收集起来（只收画在这块画布上的）。
    func draws(_ body: () -> Void) -> [PixelFont.DrawRecord] {
        let (_, all) = TextAuditRunner.withDraws(body)
        return all.filter { $0.canvasID == ObjectIdentifier(canvas) }
    }
}

private func kinds(_ v: [TextAudit.Violation]) -> Set<TextAudit.Kind> { Set(v.map(\.kind)) }

// MARK: - 1. 检测器灵敏度

@Suite struct TextAuditDetectorTests {
    @Test func aCleanFrameReportsNothing() {
        let r = Rig()
        let t = TextItem("等你批准 Bash", style: darkInk, x: 10, y: 10, maxWidth: 200, container: IntRect(4, 6, 100, 20), tag: "plate.title")
        #expect(TextAudit.check(r.input([t])).isEmpty)
    }

    @Test func class1OverlappingTextIsCaught() {
        let r = Rig()
        let a = TextItem("重构登录模块", style: darkInk, x: 10, y: 10)
        let onTop = TextItem("论文引用检查", style: darkInk, x: 14, y: 12)
        let apart = TextItem("论文引用检查", style: darkInk, x: 14, y: 30)
        #expect(kinds(TextAudit.check(r.input([a, onTop]))).contains(.overlap))
        #expect(!kinds(TextAudit.check(r.input([a, apart]))).contains(.overlap))
    }

    @Test func class2TextOutsideItsContainerOrTheWindowIsCaught() {
        let r = Rig()
        let tooNarrow = TextItem("重构登录模块并且补全测试", style: darkInk, x: 10, y: 10, container: IntRect(4, 6, 20, 12), tag: "plate.title")
        #expect(kinds(TextAudit.check(r.input([tooNarrow]))).contains(.clipped))
        let offWindow = TextItem("重构登录模块", style: darkInk, x: 100, y: 10)                 // 100 美术像素 = 200 pt，文字伸到 240 pt 宽的窗口外
        #expect(kinds(TextAudit.check(r.input([offWindow]))).contains(.clipped))
        let fits = TextItem("重构登录模块", style: darkInk, x: 10, y: 10, container: IntRect(4, 6, 100, 20), tag: "plate.title")
        #expect(!kinds(TextAudit.check(r.input([fits]))).contains(.clipped))
    }

    @Test func class2HoverCardThatIsNotWhollyInsideTheWindowIsCaught() {
        let r = Rig()
        let t = TextItem("悬停卡片", style: darkInk, x: 6, y: 6, container: IntRect(-4, 2, 60, 30), tag: "card.title")     // 容器有一截在窗口左边外面
        #expect(kinds(TextAudit.check(r.input([t]))).contains(.clipped))
    }

    @Test func class3LongTextWithoutAnEllipsisIsCaught() {
        let r = Rig()
        let long = "这是一段很长很长的文字这是一段很长很长的文字"
        let noEllipsis = TextItem(long, style: darkInk, x: 10, y: 10, maxWidth: 0, container: IntRect(4, 6, 40, 20), tag: "plate.title")
        #expect(kinds(TextAudit.check(r.input([noEllipsis]))).contains(.ellipsis))
        let truncated = TextItem(long, style: darkInk, x: 10, y: 10, maxWidth: 70, container: IntRect(4, 6, 40, 20), tag: "plate.title")
        #expect(!kinds(TextAudit.check(r.input([truncated]))).contains(.ellipsis))
    }

    @Test func class4LabelsThatCoverAFaceScreenBubbleOrCardAreCaught() {
        let r = Rig()
        let plate = TextItem("重构登录模块", style: darkInk, x: 10, y: 10, tag: "plate.title")
        for kind in [AuditRegion.Kind.face, .screen, .bubble, .card] {
            let hit = AuditRegion(kind: kind, rect: IntRect(10, 8, 16, 18), seat: 0)
            #expect(kinds(TextAudit.check(r.input([plate], regions: [hit]))).contains(.covers), "桌牌文字盖住了 \(kind)")
        }
        let elsewhere = AuditRegion(kind: .face, rect: IntRect(80, 40, 16, 18), seat: 0)
        #expect(!kinds(TextAudit.check(r.input([plate], regions: [elsewhere]))).contains(.covers))
        // 悬停卡片自己的字压在脸上不算这一类（卡片本来就是浮层）；卡片矩形盖住被悬停那个人自己的脸才算
        let cardText = TextItem("重构登录模块", style: darkInk, x: 10, y: 10, tag: "card.title")
        #expect(!kinds(TextAudit.check(r.input([cardText], regions: [AuditRegion(kind: .face, rect: IntRect(10, 8, 16, 18), seat: 0)]))).contains(.covers))
    }

    @Test func class4TheHoverCardMustNotCoverItsOwnFaceButMayCoverANeighbours() {
        let r = Rig()
        let face = AuditRegion(kind: .face, rect: IntRect(10, 8, 16, 18), seat: 0)
        let ownCard = AuditRegion(kind: .card, rect: IntRect(20, 10, 40, 30), seat: 0)
        let neighboursCard = AuditRegion(kind: .card, rect: IntRect(20, 10, 40, 30), seat: 1)
        #expect(kinds(TextAudit.check(r.input(regions: [face, ownCard]))).contains(.covers))
        #expect(!kinds(TextAudit.check(r.input(regions: [face, neighboursCard]))).contains(.covers))
    }

    @Test func class5FontsBelowNinePointsAreCaught() {
        let r = Rig()
        let small = TextItem("很小的字", style: TextStyle(size: 8, color: RGBA8(hex: 0x1E1518)), x: 10, y: 10)
        let ok = TextItem("刚好的字", style: TextStyle(size: 9, color: RGBA8(hex: 0x1E1518)), x: 10, y: 10)
        #expect(kinds(TextAudit.check(r.input([small]))).contains(.fontSize))
        #expect(!kinds(TextAudit.check(r.input([ok]))).contains(.fontSize))
    }

    @Test func class6LowContrastAgainstTheRealCanvasIsCaught() {
        let r = Rig(bg: 0x8A90A4)
        let faint = TextItem("看不清的字", style: TextStyle(size: 11, color: RGBA8(hex: 0x9AA0B4), weight: .semibold), x: 10, y: 10)
        let strong = TextItem("看得清的字", style: TextStyle(size: 11, color: RGBA8(hex: 0x0B0B12), weight: .semibold), x: 10, y: 10)
        #expect(kinds(TextAudit.check(r.input([faint]))).contains(.contrast))
        #expect(!kinds(TextAudit.check(r.input([strong]))).contains(.contrast))
        // 阈值可调：4.5:1 是 WCAG AA
        var loose = r.input([faint]); loose.minContrast = 1.0
        #expect(!kinds(TextAudit.check(loose)).contains(.contrast))
    }

    @Test func class7TextNotOnWholeDevicePixelsIsCaught() {
        let r = Rig()
        let t = TextItem("对齐检查", style: darkInk, x: 10, y: 10)
        var off = r.input([t])
        off.place = { _, size, _, _, scale in CGRect(x: 10.5, y: 4, width: Double(size.width) * Double(scale), height: Double(size.height) * Double(scale)) }
        #expect(kinds(TextAudit.check(off)).contains(.alignment))
        #expect(!kinds(TextAudit.check(r.input([t]))).contains(.alignment))               // 真实的摆放函数（TextLayout.place）取整过
    }

    /// TA-011（审计工具自己的 bug）：文字有一部分在窗口上边 / 左边外面时，设备像素坐标是负数，Swift 的 `/` 向零取整会把它映射到错的画布行
    /// （差一行），对比度检查读到旁边一行的颜色，报出假阳性（41 个座位、窗口里只看得见中间几个时，看不见的桌牌被误报）。
    /// 端到端的回归是缩减矩阵测试（含 41 个座位的组合）。
    @Test func floorDivisionMapsNegativeDevicePixelsToTheRightCanvasRow() {
        for (a, b, want) in [(0, 4, 0), (3, 4, 0), (4, 4, 1), (-1, 4, -1), (-3, 4, -1), (-4, 4, -1), (-5, 4, -2), (-13, 12, -2), (-12, 12, -1), (-165, 6, -28)] {
            #expect(TextAudit.floorDiv(a, b) == want, "floorDiv(\(a), \(b)) = \(TextAudit.floorDiv(a, b))，应为 \(want)")
        }
    }

    @Test func class8PixelDigitsThatTouchAreCaught() {
        let r = Rig()
        let w = PixelFont.tiny.width(of: "12")
        let glued = r.draws {
            PixelFont.tiny.draw("12", x: 10, y: 10, value: r.inkIdx, style: r.style, on: r.canvas)
            PixelFont.tiny.draw("34", x: 10 + w, y: 10, value: r.inkIdx, style: r.style, on: r.canvas)             // 间隔 0
        }
        #expect(kinds(TextAudit.check(r.input(draws: glued))).contains(.pixelDigits))
        let apart = r.draws {
            PixelFont.tiny.draw("12", x: 10, y: 10, value: r.inkIdx, style: r.style, on: r.canvas)
            PixelFont.tiny.draw("34", x: 10 + w + 2, y: 10, value: r.inkIdx, style: r.style, on: r.canvas)
        }
        #expect(!kinds(TextAudit.check(r.input(draws: apart))).contains(.pixelDigits))
    }

    @Test func class8MissingGlyphsAndOverflowingContainersAreCaught() {
        let r = Rig()
        let missing = r.draws { PixelFont.tiny.draw("日", x: 10, y: 10, value: r.inkIdx, style: r.style, on: r.canvas) }        // 像素字体里没有这个字
        #expect(kinds(TextAudit.check(r.input(draws: missing))).contains(.pixelDigits))
        let tooWide = r.draws { PixelFont.tiny.draw("12345", x: 2, y: 2, value: r.inkIdx, style: r.style, on: r.canvas, container: IntRect(0, 0, 10, 9)) }
        #expect(kinds(TextAudit.check(r.input(draws: tooWide))).contains(.pixelDigits))
        let roomy = r.draws { PixelFont.tiny.draw("12345", x: 3, y: 3, value: r.inkIdx, style: r.style, on: r.canvas, container: IntRect(0, 0, 40, 12)) }
        #expect(TextAudit.check(r.input(draws: roomy)).isEmpty)
    }

    @Test func class8PixelDigitsPaintedOverByLaterDrawingAreCaught() {
        let r = Rig()
        let d = r.draws {
            PixelFont.tiny.draw("12", x: 10, y: 10, value: r.inkIdx, style: r.style, on: r.canvas)
            r.canvas.fillRect(IntRect(8, 8, 12, 9), value: r.bgIdx, style: r.style)                    // 后画的东西把数字盖掉
        }
        #expect(kinds(TextAudit.check(r.input(draws: d))).contains(.pixelDigits))
    }
}

// MARK: - 2. 修复的回归测试（每条对应 QA/ISSUES.md 里的一个编号）

@Suite struct TextAuditRegressionTests {
    private func plateTexts(_ f: Frame) -> [TextItem] { f.texts.filter { $0.tag.hasPrefix("plate") } }

    /// TA-001：桌牌文字对比度（白天状态行 2.91:1、夜里深色字压在被压暗的木牌上约 2:1）。
    @Test(arguments: ["12:00", "23:00", "05:30"], [2, 3, 4, 5])
    func plateTextMeetsContrastAtAnyTimeOfDay(clock: String, zoom: Int) {
        let s = TextAuditRunner.OfficeSession(count: 8, titles: .normal, states: .all, requestedZoom: zoom, clock: clock)
        let r = s.render()
        #expect(plateTexts(r.frame).count >= 8, "应该有桌牌文字可查")
        let v = r.audit().filter { $0.kind == .contrast }
        #expect(v.isEmpty, "\(clock) 缩放\(zoom)×：\(v.prefix(3).map(\.description))")
    }

    /// TA-002：桌牌（原来只有 10 像素高）放不下标题 + 状态两行，字被切 / 顶出桌牌。
    @Test(arguments: [3, 4, 5])
    func twoLinePlateTextStaysInsideThePlate(zoom: Int) {
        for tm in [AuditFixtures.TitleMode.normal, .longZh, .mixed] {
            let s = TextAuditRunner.OfficeSession(count: 8, titles: tm, states: .all, requestedZoom: zoom)
            let r = s.render()
            let twoLines = plateTexts(r.frame).filter { $0.tag == "plate.status" }
            #expect(!twoLines.isEmpty, "缩放\(zoom)× 应该有两行的桌牌")
            let v = r.audit().filter { $0.kind == .clipped || $0.kind == .overlap }
            #expect(v.isEmpty, "缩放\(zoom)× \(tm)：\(v.prefix(3).map(\.description))")
        }
    }

    /// TA-003：emoji 的字形比苹方高出一截（同样字号下上下各多出 1–2 pt），桌牌 / 卡片的行盒是按苹方量的，emoji 会顶出去。
    /// 缩到 0.78 倍之后 emoji 的笔画范围要落在苹方（中文 + 带上伸 / 下伸的拉丁字母）的笔画范围里。
    @Test(arguments: [10, 11, 12, 13])
    func emojiInkStaysInsideTheCJKInkRange(size: Int) {
        let tr = TextRenderer.shared
        let style = TextStyle(size: CGFloat(size), color: RGBA8(hex: 0x1E1518), weight: .semibold)
        guard let cjk = tr.ink("测Agpy", style: style, scale: 4)?.bbox, let emoji = tr.ink("🚀🎉✨🔥", style: style, scale: 4)?.bbox,
              let mixed = tr.ink("🚀发布🎉v2.0✨上线🔥", style: style, scale: 4)?.bbox else { Issue.record("没有笔画"); return }
        let slack = 2                                                     // 0.5 pt（scale 4 下的设备像素）
        #expect(emoji.y >= cjk.y - slack && emoji.y + emoji.h <= cjk.y + cjk.h + slack, "emoji 笔画 \(emoji.y)…\(emoji.y + emoji.h) 超出了苹方笔画 \(cjk.y)…\(cjk.y + cjk.h)")
        #expect(mixed.y >= cjk.y - slack && mixed.y + mixed.h <= cjk.y + cjk.h + slack, "混排标题笔画 \(mixed.y)…\(mixed.y + mixed.h) 超出了苹方笔画 \(cjk.y)…\(cjk.y + cjk.h)")
    }

    @Test(arguments: [2, 3, 4, 5])
    func emojiTitlesNeverLeaveTheirPlateOrCard(zoom: Int) {
        let s = TextAuditRunner.OfficeSession(count: 4, titles: .emoji, states: .demo, requestedZoom: zoom)
        let v = s.render().audit().filter { $0.kind == .clipped }
        #expect(v.isEmpty, "缩放\(zoom)×：\(v.prefix(3).map(\.description))")
    }

    /// TA-004：睡着的「zzz」两个 z 之间没有空隙，粘成一团。
    @Test func sleepingBuddysTwoZsDoNotTouch() {
        let base = StageRun.fixedBase(clock: "12:00")
        var snap = AuditFixtures.snapshots(count: 1, titles: .normal, states: .all, base: base)[0]
        let sleeping = AuditFixtures.states.first { $0.0 == "睡着" }!.1
        sleeping(&snap, base)
        snap.phase = snap.activity.phase
        let s = TextAuditRunner.OfficeSession(count: 1, requestedZoom: 3, snapshots: [snap])
        let r = s.render()
        let zs = r.draws.filter { $0.canvasID == ObjectIdentifier(r.frame.canvas) && $0.text == "z" }
        #expect(zs.count >= 2, "睡着的人头上应该有两个 z（实际 \(zs.count) 个）")
        for a in 0..<zs.count { for b in (a + 1)..<zs.count { #expect(zs[a].rect.insetBy(-1).intersection(zs[b].rect) == nil, "两个 z 贴在一起：\(zs[a].rect) \(zs[b].rect)") } }
        #expect(r.audit().filter { $0.kind == .pixelDigits }.isEmpty)
    }

    /// TA-005：「今天还没人上班」牌子——对比度 4.45:1（贴在木地板上）、又被后画的桌椅盖住（4× 时最差 1.09:1）。
    @Test(arguments: [1, 2, 3, 4, 5])
    func emptyOfficeSignIsReadableAndDrawnOnTopOfTheDesks(zoom: Int) {
        for clock in ["12:00", "23:00"] {
            let s = TextAuditRunner.OfficeSession(count: 0, requestedZoom: zoom, clock: clock)
            let r = s.render()
            let sign = r.frame.texts.filter { $0.tag == "sign" }
            #expect(sign.count == 1, "空办公室应该有一块牌子")
            #expect(r.audit().isEmpty, "缩放\(zoom)× \(clock)：\(r.audit().prefix(3).map(\.description))")
            // 牌子在最终画面里没有被桌椅盖掉：牌子左侧中部（字够不到的地方）的像素是胡桃木牌面的颜色，而不是桌椅 / 地毯
            let sr = s.scene.signRect
            let cv = r.frame.canvas
            let face = cv.idx[(sr.y + sr.h / 2) * cv.width + sr.x + 3]
            #expect(face == UInt16(Pal.dx("woodWalnut.base")), "牌子中部像素 \(face) 不是胡桃木牌面（被后画的东西盖住了？）")
        }
    }

    /// TA-006：悬停卡片盖住被悬停那个人自己的脸 / 屏幕 / 气泡（最小窗口）；TA-007：窄窗口里卡片超出窗口；TA-008：窗口再小也得有卡片。
    @Test(arguments: [TextAuditRunner.Window.standard, .smallest, .narrow, .short], [2, 3, 4])
    func hoverCardAlwaysAppearsInsideTheWindowWithoutCoveringItsOwner(win: TextAuditRunner.Window, zoom: Int) {
        for tm in [AuditFixtures.TitleMode.mixed, .longZh] {
            let s = TextAuditRunner.OfficeSession(count: 8, titles: tm, states: .demo, requestedZoom: zoom, window: win)
            s.settleCamera()
            let corners = s.cornerSeats
            #expect(!corners.isEmpty, "\(win.name) 缩放\(s.zoom)×：窗口里应该有整块看得见的座位")
            for seat in corners {
                let r = s.render(hover: seat, advance: true)
                let card = r.regions.first { $0.kind == .card }
                #expect(card != nil, "\(win.name) 缩放\(s.zoom)× 座位\(seat)：没有画出悬停卡片")
                if let card {
                    let vp = r.frame.viewport
                    #expect(card.rect.x >= vp.x && card.rect.y >= vp.y && card.rect.maxX <= vp.maxX && card.rect.maxY <= vp.maxY, "卡片 \(card.rect) 超出窗口 \(vp)")
                }
                let bad = r.audit().filter { $0.kind == .covers || $0.kind == .clipped }
                #expect(bad.isEmpty, "\(win.name) 缩放\(s.zoom)× 座位\(seat)：\(bad.prefix(3).map(\.description))")
            }
        }
    }

    /// TA-006：被卡片盖住的桌牌文字要收起来，否则文字层浮在卡片上面和卡片的字叠在一起。
    @Test func plateTextUnderTheHoverCardIsHidden() {
        for zoom in [2, 3, 4] {
            let s = TextAuditRunner.OfficeSession(count: 8, titles: .longZh, states: .demo, requestedZoom: zoom)
            s.settleCamera()
            for seat in s.cornerSeats {
                let r = s.render(hover: seat, advance: true)
                guard let card = r.regions.first(where: { $0.kind == .card }) else { Issue.record("没有卡片"); continue }
                for t in r.frame.texts where t.tag.hasPrefix("plate") {
                    #expect(OfficeScene.artBounds(t, zoom: zoom).intersection(card.rect) == nil, "缩放\(zoom)× 座位\(seat)：桌牌文字「\(t.text)」还压在卡片下面")
                }
            }
        }
    }

    /// TA-009：窗口比一个整工位还窄 / 还矮时，设置里的大倍数会把工位切掉一半（桌牌文字被切、悬停卡片无处可放）；实际缩放要夹到「至少放得下一个整工位」。
    @Test func zoomIsClampedSoAtLeastOneWholeSeatFits() {
        #expect(OfficeLayout.effectiveZoom(setting: 5, contentW: 200, contentH: 220, maxSeat: 3, allowOne: true) == 2, "最小窗口 200×220：一个工位（56×76）最多 2×")
        #expect(OfficeLayout.effectiveZoom(setting: 5, contentW: 672, contentH: 678, maxSeat: 3, allowOne: true) == 5)
        #expect(OfficeLayout.effectiveZoom(setting: 5, contentW: 900, contentH: 260, maxSeat: 3, allowOne: true) == 3, "矮窗口按高度夹")
        #expect(OfficeLayout.effectiveZoom(setting: 5, contentW: 260, contentH: 700, maxSeat: 3, allowOne: true) == 4, "窄窗口按宽度夹")
        #expect(OfficeLayout.effectiveZoom(setting: 5, contentW: 100, contentH: 200, maxSeat: 3, allowOne: false) == 2, "非 Retina 屏最小 2×")
        #expect(OfficeLayout.effectiveZoom(setting: 0, contentW: 672, contentH: 678, maxSeat: 3, allowOne: true) >= 1, "0 = 自动")
        // 任何窗口大小、任何设置：算出来的缩放下，整个工位（含桌牌）一定放得进窗口（放不进的只有 1× 也放不下的极端小窗口）
        for w in stride(from: 200, through: 900, by: 40) { for h in stride(from: 220, through: 900, by: 40) { for setting in 1...5 {
            let z = OfficeLayout.effectiveZoom(setting: setting, contentW: Double(w), contentH: Double(h), maxSeat: 5, allowOne: true)
            #expect(z >= 1 && z <= setting)
            #expect(Double(z) * Double(Metrics.cellW) <= Double(w) && Double(z) * Double(Metrics.cellH + Metrics.plateH) <= Double(h), "\(w)×\(h) 设置 \(setting)× → \(z)× 放不下一个整工位")
        } } }
    }

    /// TA-010：空标题 / 全空白标题不能变成一块空牌子。
    @Test func blankTitlesGetAPlaceholderOnPlatesAndCards() {
        #expect(PlateCopy.displayTitle("") == "（没有标题）")
        #expect(PlateCopy.displayTitle("  \n\t") == "（没有标题）")
        #expect(PlateCopy.displayTitle("重构登录模块") == "重构登录模块")
        let s = TextAuditRunner.OfficeSession(count: 4, titles: .empty, states: .demo, requestedZoom: 3)
        let titles = s.render().frame.texts.filter { $0.tag == "plate.title" }
        #expect(!titles.isEmpty)
        #expect(titles.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }, "空标题的桌牌上要有占位文字")
    }
}

// MARK: - 3. 缩减版压力矩阵

@Suite struct TextAuditMatrixTests {
    @Test func quickMatrixHasZeroViolationsAndReallyCoversTheScenes() {
        let rep = TextAuditRunner.run(.quick)
        let sample = rep.violations.prefix(5).map(\.description).joined(separator: "\n")
        #expect(rep.violations.isEmpty, "违规 \(rep.violations.count) 处：\n\(sample)")
        #expect(rep.hoverCardsMissing == 0, "悬停卡片没画出来 \(rep.hoverWithoutCard)")
        // 覆盖量：防止「0 违规」只是因为什么都没查
        #expect(rep.combos >= 1500, "只检查了 \(rep.combos) 个组合")
        #expect(rep.texts >= 9000, "只检查了 \(rep.texts) 段文字")
        #expect(rep.pixelStrings >= 600, "只检查了 \(rep.pixelStrings) 串像素字")
        for scene in ["办公室", "悬停卡片", "悬停卡片(单独)", "小鱼缸", "桌面宠物", "提示卡"] {
            #expect((rep.perScene[scene]?.combos ?? 0) > 0, "场景「\(scene)」一个组合都没查")
        }
        #expect(rep.hoverTotal >= 100)
    }
}
