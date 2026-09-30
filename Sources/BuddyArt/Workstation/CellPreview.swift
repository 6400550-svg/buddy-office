import Foundation
import PixelKit

/// 工位预览：把桌子、显示器、人物各部件叠成一个 56×64 的工位格（只用来看效果、定比例；真正的场景由 BuddyStage 负责）。
public enum CellPreview {
    public struct Params {
        public var facing: Facing = .back
        public var hairStyle: String = "bob"
        public var outfit: String = "tee"
        public var light = LightState(a: .day)
        public var screenLit = true
        public var lampOn = false
        public var typingFrame = 0
        public var mirror = false
        public var face: String? = nil
        public init() {}
    }

    typealias K = SeatGeometry

    public static func render(_ ap: Appearance, _ p: Params = Params(), width: Int = 56, height: Int = 74) -> Canvas {
        let c = Canvas(width: width, height: height)
        let dayStyle = Lighting.resolved(map: nil, state: p.light)
        let roleStyle = Lighting.resolved(map: ap.roleMap, state: p.light)
        // 地板底色（预览）
        c.fillRect(c.bounds, value: Pal.dx("floor.base"), style: dayStyle)
        for y in stride(from: 6, to: height, by: 16) { c.hLine(x: 0, y: y, length: width, value: Pal.dx("floor.gap"), style: dayStyle) }

        let book = CharacterArt.book, props = PropArt.book
        let deskName = ap.chair == .wood ? "desk.walnut" : "desk.oak"
        c.blit(props[deskName], x: K.deskX, y: K.deskY, style: dayStyle)
        // 桌面小件
        c.blit(book["mug"], x: K.mugX, y: K.mugY, style: roleStyle)
        let ornName: String? = {
            switch ap.ornament { case .duck: return "orn.duck"; case .figure: return "orn.figure"; case .photoFrame: return "orn.frame"
            case .cactus: return "orn.cactus"; case .luckyCat: return "orn.cat"; case .none: return nil }
        }()
        if let o = ornName { c.blit(props[o], x: K.ornX, y: K.ornY, style: dayStyle) }
        c.blit(props[p.lampOn ? "lamp.on" : "lamp.off"], x: K.lampX, y: K.lampY, style: dayStyle)
        // 显示器
        c.blit(props["monitor.stand"], x: K.standX, y: K.standY, style: dayStyle)
        if p.screenLit {
            let scr = Pal.dx("scr.bg")
            c.fillRect(IntRect(K.monX + 2, K.monY + 2, 24, 15), value: scr, style: dayStyle)
            // 占位内容：几行「代码」
            let cols = ["scr.cyan", "scr.green", "scr.amber", "scr.pink", "scr.white"].map { Pal.dx($0) }
            for r in 0..<6 {
                let x0 = K.monX + 4 + (r % 3) * 2
                c.hLine(x: x0, y: K.monY + 4 + r * 2, length: 5 + (r * 5) % 11, value: cols[r % cols.count], style: dayStyle)
            }
        }
        c.blit(props["monitor.bezel"], x: K.monX, y: K.monY, style: dayStyle)
        c.blit(props["keyboard"], x: K.kbX, y: K.kbY, style: dayStyle)
        c.blit(props["mouse"], x: K.mouseX, y: K.mouseY, style: dayStyle)

        // 人物：整只画进一张图层，再按需要翻转、贴到工位格里
        var ri = RigInput(appearance: ap)
        ri.facing = p.facing
        let layer = Canvas(width: BuddyRig.layerW, height: BuddyRig.layerH)
        let ox = K.buddyCx - BuddyRig.cx, oy = K.headTopY - BuddyRig.headY
        let leftHand = IntPoint(K.kbX + 4 - ox, K.kbY + 1 + (p.typingFrame % 2 == 0 ? 0 : 1) - oy)
        let rightHand = IntPoint(K.mouseX + 1 - ox, K.mouseY + 2 + (p.typingFrame % 2 == 0 ? 1 : 0) - oy)
        if p.facing == .back || p.facing == .threeQuarterBack { ri.handL = leftHand; ri.handR = rightHand }
        ri.expression = p.face
        BuddyRig.render(ri, style: roleStyle, into: layer)
        c.blitCanvas(layer, x: ox, y: oy, flipH: p.mirror)
        return c
    }
}
