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
        public var acc: String? = nil
        public var face: String? = nil
        public init() {}
    }

    /// 关键坐标（工位格坐标）。这些数字就是「比例」的定稿，改动会影响整个场景。
    enum K {
        static let cellW = 56, cellH = 64
        static let deskX = 2, deskY = 22
        static let monX = 14, monY = 2
        static let standX = 22, standY = 22
        static let kbX = 19, kbY = 25
        static let mouseX = 41, mouseY = 27
        static let mugX = 5, mugY = 26
        static let lampX = 41, lampY = 12
        static let ornX = 6, ornY = 17
        static let buddyCx = 26          // 人物中心（略偏左）
        static let headTopY = 16         // 头盒子上沿
        static let chairY = 35
    }

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

        // 人物（背面坐姿）。顺序：躯干 → 手臂 → 头 → 头发 → 椅子（靠背在人物前面，盖住下半截后背）
        let torsoName = "torso.\(p.outfit).\(p.facing.name)"
        if let torso = book.get(torsoName) {
            let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            let headBoxBottom = K.headTopY + CharacterArt.headH       // 下巴下一行
            let tx = K.buddyCx - neck.x, ty = headBoxBottom - neck.y
            c.blit(torso, x: tx, y: ty, style: roleStyle)
            let sl = torso.anchors["shoulderL"] ?? IntPoint(1, 3), sr = torso.anchors["shoulderR"] ?? IntPoint(12, 3)
            let armName = p.typingFrame % 2 == 0 ? "arm.typeUp" : "arm.typeDown"
            let arm = book[armName]
            let sh = arm.anchors["shoulder"] ?? IntPoint(2, 10)
            c.blit(arm, x: tx + sl.x - sh.x, y: ty + sl.y - sh.y, style: roleStyle)
            c.blit(arm, x: tx + sr.x - (arm.width - 1 - sh.x), y: ty + sr.y - sh.y, flipH: true, style: roleStyle)
        }
        c.blit(book["head.\(p.facing.name)"], x: K.buddyCx - 6, y: K.headTopY, style: roleStyle)
        if let fc = p.face, let fs = book.get("face.\(fc).\(p.facing.name)") { c.blit(fs, x: K.buddyCx - 6, y: K.headTopY, style: roleStyle) }
        if let hair = book.get("hair.\(p.hairStyle).\(p.facing.name)") {
            c.blit(hair, x: K.buddyCx - 6 - CharacterArt.hairPad.x, y: K.headTopY - CharacterArt.hairPad.y, style: roleStyle)
        }
        if let ac = p.acc, let sp = book.get("acc.\(ac).\(p.facing.name)") {
            if ac == "scarf" {
                let neck = book.get(torsoName)?.anchors["neck"] ?? IntPoint(7, 0)
                c.blit(sp, x: K.buddyCx - neck.x, y: K.headTopY + CharacterArt.headH - neck.y, style: roleStyle)
            } else {
                c.blit(sp, x: K.buddyCx - 6 - CharacterArt.hairPad.x, y: K.headTopY - CharacterArt.hairPad.y, style: roleStyle)
            }
        }
        if let chair = book.get("chair.\(ap.chair.name).back") {
            c.blit(chair, x: K.buddyCx - 11, y: K.chairY, style: roleStyle)
        }
        return c
    }
}
