import Foundation
import PixelKit
import BuddyArt

/// 人物图层缓存：人的姿势没变（指纹相同）时不用重新画 48×62 的图层，直接贴上去。每个工位一份。
public final class SeatCache {
    var personSig: UInt64 = 0
    var valid = false
    let layer = Canvas(width: BuddyRig.layerW, height: BuddyRig.layerH)
    public init() {}
}

/// 一个工位的三份「画面指纹」：屏幕内容、人、其余的一切（桌子 / 道具 / 气泡 / 小助手 / 灯 / 桌牌…）。
/// 只有屏幕变了 → 只重画屏幕那一小块；只有人变了 → 只重画人所在的矩形。
public struct SeatSigs: Equatable {
    public var rest: UInt64 = 0, person: UInt64 = 0, screen: UInt64 = 0
    /// 三份合在一起的一个值（小鱼缸 / 宠物条按整格重画时用）。
    public var combined: UInt64 { var k = KeyHasher(); k.add(Int(truncatingIfNeeded: rest)); k.add(Int(truncatingIfNeeded: person)); k.add(Int(truncatingIfNeeded: screen)); return k.h }
}

/// 画一个工位格（56×64 + 桌牌带 10）：桌子、显示器（含屏幕内容）、桌面小件、人、气泡、桌牌底板。
public enum SeatRenderer {
    static func P(_ n: String) -> UInt8 { Pal.dx(n) }
    typealias G = SeatGeometry

    /// 桌牌文字放在 TextItem 里，由 OfficeScene 收集。这里只画底板。
    public static func draw(_ v: SeatView, on c: Canvas, light: LightState, gt: Double, plateStyle: PlateStyle = .normal, cache: SeatCache? = nil) {
        let o = v.origin
        var pt = Prof.begin()
        let day = Lighting.resolved(appearance: nil, state: light)
        let props = PropArt.book
        let occupied = v.mode == .occupied
        let ap = v.appearance
        let roleStyle: Resolved = {
            let glowAmt = min(0.6, light.darkness * 0.7)
            return Lighting.resolved(appearance: ap, state: light, glow: v.glow, glowAmount: glowAmt)
        }()

        // ---- 地面软影（抖动，不是半透明）：桌子下、椅子下 ----
        c.fillDither(IntRect(o.x + 4, o.y + 47, 48, 3), value: P("floor.gap"), other: 0, level: 6, style: day)
        c.fillEllipse(cx: o.x + G.buddyCx - 3, cy: o.y + 60, rx: 11, ry: 3, value: P("floor.gap"), style: day, dither: 7)

        // ---- 空桌 / 下班：椅子推进去（画在桌子之前，被桌沿挡住一截）----
        if !occupied, !v.chairOut, let chair = CharacterArt.book.get("chair.\(ap.chair.name).back") {
            let rm = Lighting.resolved(appearance: ap, state: light)
            let seatTop = chair.anchors["seatTop"] ?? IntPoint(11, 11)
            c.blit(chair, x: o.x + G.buddyCx - seatTop.x, y: o.y + G.chairY - 13, style: rm)
        }

        // ---- 桌子 ----
        let deskName = ap.chair == .wood ? "desk.walnut" : "desk.oak"
        c.blit(props[deskName], x: o.x + G.deskX, y: o.y + G.deskY, style: day)

        // ---- 桌面小件：杯子（随人）、摆件、盆栽 ----
        c.blit(CharacterArt.book["mug"], x: o.x + G.mugX, y: o.y + G.mugY, style: Lighting.resolved(appearance: ap, state: light))
        switch ap.ornament {
        case .duck: c.blit(props["orn.duck"], x: o.x + G.ornX, y: o.y + G.ornY + 1, style: day)
        case .figure: c.blit(props["orn.figure"], x: o.x + G.ornX + 1, y: o.y + G.ornY - 2, style: day)
        case .photoFrame: c.blit(props["orn.frame"], x: o.x + G.ornX, y: o.y + G.ornY + 1, style: day)
        case .cactus: c.blit(props["orn.cactus"], x: o.x + G.ornX - 1, y: o.y + G.ornY - 1, style: day)
        case .luckyCat: c.blit(props["orn.cat"], x: o.x + G.ornX, y: o.y + G.ornY - 1, style: day)
        case .none: break
        }
        // 台灯 + 光圈
        c.blit(props[v.lampOn ? "lamp.on" : "lamp.off"], x: o.x + G.lampX, y: o.y + G.lampY + 2, style: day)

        // ---- 姿势道具（放在桌面上）----
        for p in v.props {
            switch p {
            case .notepad: c.blit(props["prop.notepad"], x: o.x + G.kbX + 21, y: o.y + G.kbY - 1, style: day)
            case .papers: c.blit(props["prop.papers"], x: o.x + G.kbX + 8, y: o.y + G.kbY + 1, style: day)
            case .box: c.blit(props["prop.box"], x: o.x + G.kbX - 5, y: o.y + G.kbY, style: day)
            case .tray: c.blit(props["prop.tray"], x: o.x + G.deskX + 3, y: o.y + G.deskY + 4, style: day)
            case .alarm: c.blit(props["prop.alarm"], x: o.x + G.lampX - 6, y: o.y + G.lampY + 10, style: day)
            case .clipboard: break
            }
        }

        Prof.end("seat.props", pt)
        // ---- 显示器 ----
        pt = Prof.begin()
        drawMonitor(v, on: c, light: light, gt: gt, day: day)
        Prof.end("seat.monitor", pt)
        pt = Prof.begin()

        // ---- 键盘 / 鼠标 ----
        c.blit(props["keyboard"], x: o.x + G.kbX, y: o.y + G.kbY, style: day)
        c.blit(props["mouse"], x: o.x + G.mouseX, y: o.y + G.mouseY, style: day)

        // ---- 椅子拉出来（人还没坐下 / 刚起身）：像坐着的时候那样画在桌子前面 ----
        if !occupied, v.chairOut, let chair = CharacterArt.book.get("chair.\(ap.chair.name).back") {
            let rm = Lighting.resolved(appearance: ap, state: light)
            let seatTop = chair.anchors["seatTop"] ?? IntPoint(11, 11)
            c.blit(chair, x: o.x + G.buddyCx - seatTop.x, y: o.y + G.chairY, style: rm)
        }

        Prof.end("seat.kbChair", pt)
        // ---- 人（整只画进图层，再贴过来）----
        pt = Prof.begin()
        let lo = G.layerOrigin
        if occupied, let ri = v.rig, c.mayTouch(IntRect(o.x + lo.x, o.y + lo.y, BuddyRig.layerW, BuddyRig.layerH)) {
            let psig = personSignature(v, light: light)
            let layer: Canvas
            if let cache = cache, cache.valid, cache.personSig == psig { layer = cache.layer }
            else {
                layer = cache?.layer ?? Canvas(width: BuddyRig.layerW, height: BuddyRig.layerH)
                layer.clear()
                let pr = Prof.begin()
                BuddyRig.render(ri, style: roleStyle, into: layer)
                Prof.end("seat.rigRender", pr)
                if v.holdClipboard, let cb = props.get("prop.clipboard") {
                    layer.blit(cb, x: BuddyRig.cx - 8, y: BuddyRig.headY + 20, style: day)
                }
                cache?.personSig = psig; cache?.valid = true
            }
            c.blitCanvas(layer, x: o.x + lo.x, y: o.y + lo.y, flipH: v.mirror, id: v.hitID)
        }

        Prof.end("seat.rigTotal", pt)
        pt = Prof.begin()
        // ---- 台灯光圈（夜里 / 忙的时候更明显）----
        if v.lampOn && light.darkness > 0.05 {
            // 白天灯开着也看不出光圈（灯头本身会亮）；越暗光圈越明显
            let s = min(0.85, 0.2 + 0.7 * light.darkness)
            c.applyLightPool(cx: o.x + G.lampX + 3, cy: o.y + G.lampY + 24, rx: 16, ry: 7, lut: Lighting.luts.lamp, strength: s)
        }

        // ---- 小助手：坐在带轮凳子上，抱着笔记本，从旁边滑进来（最多 3 个，多了显示 +N）----
        if occupied {
            let slots = [IntPoint(2, 40), IntPoint(42, 40), IntPoint(9, 43)]
            for h in v.helperDraws {
                let pos = slots[min(2, h.slot)]
                let rm = Lighting.resolved(appearance: h.appearance, state: light)
                let look = helperLook(h)
                let frame = look.frame == 1 ? "helper.front.1" : "helper.front.0"
                let bob = look.bob
                let spr = HelperArt.sprite(frame)
                c.blit(spr, x: o.x + pos.x + h.dx, y: o.y + pos.y + bob, style: rm, clip: IntRect(o.x - 6, o.y, G.cellW + 12, G.cellH))
            }
            if v.extraHelpers > 0 {
                let t = "+\(v.extraHelpers)"
                let w = PixelFont.small.width(of: t)
                let plateR = IntRect(o.x + 26 - w / 2 - 2, o.y + 36, w + 4, 9)
                c.plate(plateR, border: P("ink1"), fill: P("bubble.fill"), style: day)
                PixelFont.small.draw(t, x: o.x + 26 - w / 2, y: o.y + 37, value: P("ink1"), style: day, on: c, container: plateR)
            }
        }

        // ---- 气泡 ----
        if let b = v.bubble, occupied { drawBubble(b.kind, age: b.age, at: IntPoint(o.x + G.buddyCx + 8, o.y + G.headTopY - 8), gt: gt, on: c, day: day, id: v.hitID) }

        // ---- 桌牌底板 ----
        drawPlate(v, on: c, day: day, style: plateStyle)
        Prof.end("seat.lampHelpersBubblePlate", pt)
    }

    // MARK: 随时间变化的离散量（画的时候和算「画面指纹」的时候共用同一份，改一处不会漏另一处）
    static func bubbleSize(age: Double) -> Int { age < 0.06 ? 7 : (age < 0.12 ? 11 : 15) }
    /// 气泡（含尾巴）在场景里的矩形：drawBubble 画的就是这个位置（text-audit 也用它）。
    static func bubbleRect(origin o: IntPoint, size: Int) -> IntRect {
        let sprite = BubbleArt.sprite("bubble.\(size)")
        return IntRect(o.x + G.buddyCx + 8 + 4, o.y + G.headTopY - 8 + 8 - size - 1, sprite.width, sprite.height)
    }
    /// 头（脸）所在的矩形：眨眼白名单用的也是它。
    static func headRect(origin o: IntPoint) -> IntRect {
        let lo = G.layerOrigin
        return IntRect(o.x + lo.x + BuddyRig.headX - 2, o.y + lo.y + BuddyRig.headY - 2, 16, 18)
    }
    /// 思考气泡里三个点的上下位置（-1 / 0 / 1）。
    static func thinkDy(_ gt: Double, _ i: Int) -> Int {
        let ph = (gt * 0.7 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
        return Int((sin(ph * 2 * Double.pi) * 1.0).rounded())
    }
    static func zzzStep(_ gt: Double) -> Int { Int(gt / 0.9) % 3 }
    /// 待机灯用哪一档：0 关 / 1 绿 / 2 琥珀 / 3 呼吸待机。
    /// 不许开关式闪烁（任务书 6.6）：待机灯是 3 个色阶的呼吸（灭 → 半亮 → 亮 → 半亮，周期 4 秒 = 0.25 Hz）；
    /// 等你的时候琥珀灯在 3 个相邻色阶之间循环（暗 → 亮 → 更亮 → 亮，周期 1.25 秒 = 0.8 Hz，任务书 6.6「等待时的光晕」）。
    static func ledName(_ v: SeatView, gt: Double) -> String {
        if v.mode != .occupied { return "led.off" }
        switch v.led {
        case 1: return "led.on"
        case 2: return ["led.wait.lo", "led.wait", "led.wait.hi", "led.wait"][Int(gt / 0.3125) & 3]
        case 3: return ["led.off", "led.mid", "led.on", "led.mid"][Int(gt) & 3]
        default: return "led.off"
        }
    }
    /// 小助手：走路时两帧交替，坐着时每 1.2 秒起伏 1 像素（0.4 Hz 以内）。
    static func helperLook(_ h: HelperDraw) -> (frame: Int, bob: Int) {
        ((h.moving && Int(h.time / 0.15) % 2 == 1) ? 1 : 0, (!h.moving && Int(h.time / 1.2) % 2 == 1) ? 1 : 0)
    }
    static func bootLevel(_ v: SeatView) -> Int { v.boot < 1 ? Int((v.boot * 16).rounded(.down)) : 99 }
    /// 关机渐变这一帧还亮着几级（0…16，16 = 全亮）；没有在关机 = -1。
    static func fadeLevel(_ v: SeatView) -> Int { v.mode != .occupied ? v.fade.map { 16 - Int(($0.progress * 16).rounded(.down)) } ?? -1 : -1 }

    static let screenScratch = Canvas(width: 24, height: 18)
    private static let scratchLock = NSLock()
    /// 屏幕这一帧的指纹：把屏幕内容画到一小块草稿上取哈希（0 = 静态内容，不用比）。
    static func screenSignature(_ v: SeatView, light: LightState, gt: Double) -> UInt64 {
        guard v.mode == .occupied, v.screen != .off, !ScreenContent.isStatic(v.screen, seed: v.screenSeed) else { return 0 }
        let crt = v.appearance.monitor == .crt
        let day = Lighting.resolved(appearance: nil, state: light)
        scratchLock.lock(); defer { scratchLock.unlock() }
        screenScratch.clear()
        ScreenContent.draw(v.screen, on: screenScratch, rect: IntRect(0, 0, 24, crt ? 18 : 15), t: v.screenT, gt: gt, seed: v.screenSeed, style: day)
        return screenScratch.contentHash() | 1
    }

    /// 人物图层的指纹：姿势输入 + 拿写字板 + 光照 / 夜间屏幕反光（镜像和命中号在贴图层时才用，不影响图层本身）。
    static func personSignature(_ v: SeatView, light: LightState) -> UInt64 {
        var k = KeyHasher()
        k.add(v.rig); k.add(v.holdClipboard)
        k.add(light.a.rawValue); k.add(light.b.rawValue); k.add(light.level)
        k.add(v.glow)
        return k.h
    }

    /// 这个工位这一帧的三份「画面指纹」（所有会影响像素的输入，含随时间变化的离散量和屏幕内容）。
    /// 指纹和上一帧相同 ⇒ 对应那一块画出来的像素和上一帧完全一样，局部重绘就可以跳过。
    /// 漏掉任何一项都会被 `buddyctl verify`（局部重绘 vs 整张重画的逐像素对比）抓到。
    public static func signatures(_ v: SeatView, light: LightState, gt: Double, plateStyle: PlateStyle = .normal) -> SeatSigs {
        var k = KeyHasher()
        k.add(v.origin.x); k.add(v.origin.y)
        k.add(v.mode == .occupied ? 1 : (v.mode == .dormant ? 2 : 0))
        k.add(v.appearance)
        k.add(light.a.rawValue); k.add(light.b.rawValue); k.add(light.level)
        k.add(v.chairOut); k.add(v.lampOn); k.add(v.flag); k.add(v.dim)
        k.add(plateStyle == .normal)
        for p in v.props { k.add(p) }
        k.add(-7)
        k.add(v.hitID); k.add(v.mirror)
        k.add(v.glow)
        k.add(ledName(v, gt: gt))
        if v.mode == .occupied {
            for h in v.helperDraws {
                let l = helperLook(h)
                k.add(h.slot); k.add(h.dx); k.add(l.frame); k.add(l.bob); k.add(h.appearance)
            }
            k.add(v.extraHelpers)
            if let b = v.bubble {
                let size = bubbleSize(age: b.age)
                k.add(b.kind); k.add(size)
                if size == 15 {
                    switch b.kind {
                    case .think: for i in 0..<3 { k.add(thinkDy(gt, i)) }
                    case .zzz: k.add(zzzStep(gt))
                    default: break
                    }
                }
            } else { k.add(-3) }
        }
        var sc = KeyHasher()
        sc.add(v.mode == .occupied ? v.screen : .off)
        sc.add(v.screenSeed)
        sc.add(bootLevel(v))
        sc.add(fadeLevel(v))
        sc.add(v.appearance.monitor)
        sc.add(Int(bitPattern: UInt(truncatingIfNeeded: screenSignature(v, light: light, gt: gt))))
        var out = SeatSigs()
        out.rest = k.h; out.screen = sc.h
        out.person = v.mode == .occupied ? personSignature(v, light: light) : 0
        return out
    }
    public static func signature(_ v: SeatView, light: LightState, gt: Double, plateStyle: PlateStyle = .normal) -> UInt64 {
        signatures(v, light: light, gt: gt, plateStyle: plateStyle).combined
    }

    // 三块区域（世界坐标）
    static func seatRegion(_ o: IntPoint) -> IntRect { IntRect(o.x - 6, o.y - 6, G.cellW + 12, G.cellH + G.plateH + 6) }
    static func screenRegion(_ o: IntPoint) -> IntRect { IntRect(o.x + G.monX + 2, o.y + G.monY + 1, 24, 18) }
    static func personRegion(_ o: IntPoint) -> IntRect { let lo = G.layerOrigin; return IntRect(o.x + lo.x, o.y + lo.y, BuddyRig.layerW, BuddyRig.layerH) }

    public enum PlateStyle { case normal, none }

    static func drawMonitor(_ v: SeatView, on c: Canvas, light: LightState, gt: Double, day: Resolved) {
        let o = v.origin, props = PropArt.book
        let crt = v.appearance.monitor == .crt
        // 支架
        if !crt { c.blit(props["monitor.stand"], x: o.x + G.standX, y: o.y + G.standY, style: day) }
        let sr = crt ? IntRect(o.x + 11 + 5, o.y + 0 + 3, 24, 18) : IntRect(o.x + G.monX + 2, o.y + G.monY + 2, 24, 15)
        var kind = v.screen
        if v.mode != .occupied { kind = .off }
        // 开机 / 关机：Bayer 抖动渐变，16 级 300 ms（boot 0…1 决定有多少像素已经亮起；关机是倒放：人离开后屏幕原来的内容一格一格熄灭）
        var lit = v.boot, content = kind, contentT = v.screenT, contentSeed = v.screenSeed
        if v.mode != .occupied, let f = v.fade { lit = 1 - f.progress; content = f.kind; contentT = f.t; contentSeed = f.seed }
        let fading = v.mode != .occupied && v.fade != nil
        if lit < 1 || fading, c.mayTouch(sr) {
            let base = Resolved(map: nil, lutA: Lighting.luts.lut(light.a), lutB: nil, progress: 0)
            ScreenContent.draw(.off, on: c, rect: sr, t: 0, gt: gt, seed: v.screenSeed, style: base)
            let lvl = Int((lit * 16).rounded(.down))
            if lvl > 0 {
                let tmp = Canvas(width: c.width, height: c.height)
                ScreenContent.draw(content, on: tmp, rect: sr, t: contentT, gt: gt, seed: contentSeed, style: day)
                for y in sr.y..<sr.maxY { for x in sr.x..<sr.maxX where Resolved.bayer4[(y & 3) * 4 + (x & 3)] < lvl {
                    let p = tmp.pixel(x, y)
                    if p != 0 { c.setPixel(x, y, rgba: p, master: tmp.masterIndex(x, y)) }
                } }
            }
        } else if c.mayTouch(sr) {
            ScreenContent.draw(kind, on: c, rect: sr, t: v.screenT, gt: gt, seed: v.screenSeed, style: day)
        }
        if crt {
            // CRT 屏比平板高 3 行：下面补一条屏幕底色
            c.fillRect(IntRect(sr.x, sr.y + 15, 24, 3), value: P(kind == .off ? "plastic.sh" : "scr.bg2"), style: day)
            c.blit(props["monitor.crt"], x: o.x + 11, y: o.y + 0, style: day)
        } else {
            c.blit(props["monitor.bezel"], x: o.x + G.monX, y: o.y + G.monY, style: day)
        }
        // 待机灯
        let ledX = crt ? o.x + 11 + 26 : o.x + G.monX + 23, ledY = crt ? o.y + 23 : o.y + G.monY + 18
        c.set(ledX, ledY, value: P(ledName(v, gt: gt)), style: day)
        // 未读小旗：插在显示器右上角
        if v.flag && v.mode == .occupied {
            c.blit(props["prop.flag"], x: o.x + G.monX + 26, y: o.y + G.monY - 4, style: day)
        }
    }

    // 气泡：3 帧由小变大（7 → 11 → 15），之后稳定显示
    static func drawBubble(_ kind: BubbleKind, age: Double, at p: IntPoint, gt: Double, on c: Canvas, day: Resolved, id: UInt16) {
        let size = bubbleSize(age: age)
        let body = BubbleArt.sprite("bubble.\(size)")
        // 三种尺寸共用「气泡身体的左下角」：小的完全落在大的里面（弹出时只是长大，不会换位置），尾巴在身体下面
        let x = p.x + 4, y = p.y + 8 - size - 1
        c.blit(body, x: x, y: y, style: day)
        guard size == 15 else { return }
        let ic = body.anchors["icon"] ?? IntPoint(4, 4)
        let ix = x + ic.x, iy = y + ic.y
        func blit(_ n: String, dx: Int = 0, dy: Int = 0) { c.blit(BubbleArt.sprite(n), x: ix + dx, y: iy + dy, style: day) }
        switch kind {
        case .think:
            // 三个点缓缓升起（错开相位，整数像素，慢）
            for i in 0..<3 {
                let dy = thinkDy(gt, i)
                c.fillRect(IntRect(ix + 1 + i * 2, iy + 3 + dy, 1, 1), value: P("bubble.line"), style: day)
                c.fillRect(IntRect(ix + 1 + i * 2, iy + 4 + dy, 1, 1), value: P("ink3"), style: day)
            }
        case .approval(let toolIcon):
            blit("icon.key", dx: -1, dy: -1)
            if let t = BubbleArt.book.get(toolIcon) { c.blit(t.cropped(IntRect(0, 0, 7, 7)), x: ix + 3, y: iy + 3, style: day) }
        case .question: blit("icon.question")
        case .plan: blit("icon.board")
        case .search: blit("icon.magnifier")
        case .book: blit("icon.book")
        case .toolbox: blit("icon.toolbox")
        case .note: blit("icon.note")
        case .mug: blit("icon.mug")
        case .zzz:
            let step = zzzStep(gt)
            let inner = IntRect(x + 1, y + 1, body.width - 2, size - 2)
            // 两个 z 各 3 像素宽，中间隔 1 像素（7 像素的图标区刚好放下），不粘在一起
            PixelFont.tiny.draw("z", x: ix, y: iy + 4 - (step == 0 ? 1 : 0), value: P("bubble.line"), style: day, on: c, container: inner)
            PixelFont.tiny.draw("z", x: ix + 4, y: iy + 1 + (step == 1 ? 1 : 0), value: P("ink3"), style: day, on: c, container: inner)
        }
    }

    static func drawPlate(_ v: SeatView, on c: Canvas, day: Resolved, style: PlateStyle) {
        guard style == .normal else { return }
        let o = v.origin
        let r = IntRect(o.x + 2, o.y + G.cellH, G.cellW - 4, G.plateH)
        let dim = v.dim || v.mode == .dormant
        c.plate(r, border: P(dim ? "woodWalnut.out" : "woodOak.out"), fill: P(dim ? "woodWalnut.base" : "woodOak.hi"),
                light: P(dim ? "woodWalnut.hi" : "trim.hi"), shade: P(dim ? "woodWalnut.sh" : "woodOak.base"), style: day)
    }
}
