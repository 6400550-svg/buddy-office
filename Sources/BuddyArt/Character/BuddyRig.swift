import Foundation
import PixelKit

/// 一只 buddy 一帧的姿势输入（表现层的 Performer 每帧算出来）。所有坐标都是「buddy 图层」坐标。
public struct RigInput: Hashable {
    public var appearance: Appearance
    public var facing: Facing = .back
    /// 椅子的朝向（转身时和人同步）；nil = 和人一样。
    public var chairFacing: Facing? = nil
    public var torsoDy = 0
    public var headDx = 0, headDy = 0
    /// 头发比头晚 1 帧，所以单独一份偏移。
    public var hairDx = 0, hairDy = 0
    /// 手的目标位置（图层坐标）；nil = 自然下垂 / 放在腿上。
    public var handL: IntPoint? = nil
    public var handR: IntPoint? = nil
    public var bendL = 1, bendR = 1
    public var expression: String? = nil
    public var showLegs = true
    public init(appearance: Appearance) { self.appearance = appearance }
}

public enum BuddyRig {
    /// 图层尺寸与关键位置：头盒子左上角 (18, 12)（头顶上方留 12 行给举手、伸懒腰），头中心 x = 24；椅子靠背顶在 y = 31。
    public static let layerW = 48, layerH = 62
    public static let headX = 18, headY = 12
    public static let cx = 24
    public static let chairTop = 31

    public static func sleeve(for outfit: Outfit) -> SleeveStyle {
        switch outfit {
        case .tee: return SleeveStyle(mat: .cloth, long: false)
        case .vest: return SleeveStyle(mat: .accent, long: true)
        default: return SleeveStyle(mat: .cloth, long: true)
        }
    }

    /// 把 buddy 画进一张 layerW×layerH 的图层（不含镜像；镜像由调用方在贴图层时翻转）。
    public static func render(_ input: RigInput, style: Resolved, into c: Canvas) {
        let book = CharacterArt.book
        let ap = input.appearance
        let f = input.facing
        let cf = input.chairFacing ?? f
        let outfit = ap.outfit.name
        let frontish = (f == .front || f == .threeQuarterFront || f == .side)
        // 椅子在人物之前还是之后：背面 / 3/4 背面 → 靠背在前面（盖住下半截后背）；其余 → 在人物身后
        let chairInFront = (cf == .back || cf == .threeQuarterBack)
        func chairSprite() -> (IndexedSprite, Int)? {
            let name: String
            switch cf {
            case .back, .front: name = "chair.\(ap.chair.name).back"
            case .threeQuarterBack, .threeQuarterFront: name = "chair.\(ap.chair.name).q34"
            case .side: name = "chair.\(ap.chair.name).side"
            }
            guard let s = book.get(name) else { return nil }
            let seat = s.anchors["seatTop"] ?? IntPoint(11, 11)
            return (s, cx - seat.x)
        }
        func drawChair() {
            if let (s, x) = chairSprite() { c.blit(s, x: x, y: chairTop + (chairInFront ? 0 : 6), style: style) }
        }
        if !chairInFront { drawChair() }

        // 躯干
        var neckX = cx, torsoY = headY + CharacterArt.headH + input.torsoDy
        if let torso = book.get("torso.\(outfit).\(f.name)") ?? book.get("torso.tee.\(f.name)") {
            let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            let tx = cx - neck.x
            c.blit(torso, x: tx, y: torsoY - neck.y, style: style)
            neckX = tx + neck.x
            // 腿（正面 / 3/4 / 侧面坐姿）：画在躯干之后（大腿在腹前）
            if input.showLegs, frontish, let leg = book.get("leg.sit.\(f == .side ? "side" : (f == .front ? "front" : "q34front"))") {
                let hip = leg.anchors["hip"] ?? IntPoint(7, 0)
                c.blit(leg, x: cx - hip.x + (f == .side ? 3 : 0), y: torsoY - neck.y + torso.height - 3 + input.torsoDy * 0, style: style)
            }
            // 手臂
            let sl = torso.anchors["shoulderL"] ?? IntPoint(1, 3), sr = torso.anchors["shoulderR"] ?? IntPoint(12, 3)
            let sleeve = BuddyRig.sleeve(for: ap.outfit)
            let shL = IntPoint(tx + sl.x, torsoY - neck.y + sl.y), shR = IntPoint(tx + sr.x, torsoY - neck.y + sr.y)
            func rest(_ sh: IntPoint, left: Bool) -> IntPoint {
                frontish ? IntPoint(left ? -1 : 1, 9) : IntPoint(left ? -1 : 1, 8)
            }
            if f != .side {
                let hl = input.handL.map { IntPoint($0.x - shL.x, $0.y - shL.y) } ?? rest(shL, left: true)
                Limbs.drawArm(on: c, shoulder: shL, hand: hl, bend: input.bendL, outward: -1, sleeve: sleeve, style: style)
            }
            let hr = input.handR.map { IntPoint($0.x - shR.x, $0.y - shR.y) } ?? rest(shR, left: false)
            Limbs.drawArm(on: c, shoulder: shR, hand: hr, bend: input.bendR, outward: 1, sleeve: sleeve, style: style)
        }
        _ = neckX
        // 头
        if let head = book.get("head.\(f.name)") {
            c.blit(head, x: headX + input.headDx, y: headY + input.headDy, style: style)
        }
        if let ex = input.expression, let face = book.get("face.\(ex).\(f.name)") {
            c.blit(face, x: headX + input.headDx, y: headY + input.headDy, style: style)
        }
        // 头发 + 配饰（头发和头同步）。戴毛线帽时，丸子头 / 马尾这类顶上凸出来的头发要裁掉头盒子第 0 行以上的部分，不然会从帽子里冒出来
        let hp = CharacterArt.hairPad
        if let hair = book.get("hair.\(ap.hairStyle.name).\(f.name)") ?? book.get("hair.bob.\(f.name)") {
            let hx = headX - hp.x + input.hairDx, hy = headY - hp.y + input.hairDy
            let clip: IntRect? = ap.accessory == .beanie ? IntRect(0, hy + hp.y - 0, layerW, layerH) : nil
            c.blit(hair, x: hx, y: hy, style: style, clip: clip)
        }
        if ap.accessory != .none, ap.accessory != .scarf, let acc = book.get("acc.\(ap.accessory.name).\(f.name)") {
            c.blit(acc, x: headX - hp.x + input.hairDx, y: headY - hp.y + input.hairDy, style: style)
        }
        // 围巾：躯干上的叠层，画在头和头发之后；neck 锚点对到躯干的 neck 位置
        if ap.accessory == .scarf, let sc = book.get("acc.scarf.\(f.name)") {
            let sn = sc.anchors["neck"] ?? IntPoint(7, 0)
            c.blit(sc, x: cx - sn.x, y: headY + CharacterArt.headH + input.torsoDy - sn.y, style: style)
        }
        if chairInFront { drawChair() }
    }

    // MARK: 站立 / 走路（进场、离场用）
    /// 把站着（或走着）的 buddy 画进同一张图层坐标系：头盒子在 (headX, headY)，脚落在 y = headY + 13 + 10 + 9。
    /// facing 只用 back / side / front（走路的三个方向）；phase 是步伐周期 0…1；stride 0 = 站定。sink：坐下 / 起身时身体下沉的像素（腿跟着缩短）。
    public static func renderStanding(appearance ap: Appearance, facing f: Facing, phase: Double, moving: Bool, sink: Int = 0, waveArm: Int = 0,
                                      style: Resolved, into c: Canvas) {
        let book = CharacterArt.book
        let outfit = ap.outfit.name
        let torsoY = headY + CharacterArt.headH + sink
        let hipY = torsoY + 9
        let footY = headY + CharacterArt.headH + 10 + 9
        let sw = sin(phase * 2 * Double.pi)
        let liftA = moving ? max(0, sw) * 2.0 : 0, liftB = moving ? max(0, -sw) * 2.0 : 0
        var bob = 0
        if moving && abs(sw) > 0.8 { bob = -1 }
        // 腿（先画，躯干盖住腿根）
        switch f {
        case .side:
            let sx = moving ? Int((sw * 4).rounded()) : 0
            Limbs.drawLeg(on: c, hip: IntPoint(cx, hipY), foot: IntPoint(cx - sx, footY - Int(liftA.rounded())), style: style)
            Limbs.drawLeg(on: c, hip: IntPoint(cx, hipY), foot: IntPoint(cx + sx, footY - Int(liftB.rounded())), style: style)
        default:
            let stride = moving ? Int((sw * 1.0).rounded()) : 0
            Limbs.drawLeg(on: c, hip: IntPoint(cx - 3, hipY), foot: IntPoint(cx - 3, footY - Int(liftA.rounded()) + stride), kneeBend: -1, style: style)
            Limbs.drawLeg(on: c, hip: IntPoint(cx + 3, hipY), foot: IntPoint(cx + 3, footY - Int(liftB.rounded()) - stride), kneeBend: 1, style: style)
        }
        // 躯干 / 手臂 / 头 / 头发
        if let torso = book.get("torso.\(outfit).\(f.name)") ?? book.get("torso.tee.\(f.name)") {
            let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            let tx = cx - neck.x, ty = torsoY - neck.y + bob
            c.blit(torso, x: tx, y: ty, style: style)
            let sl = torso.anchors["shoulderL"] ?? IntPoint(1, 3), sr = torso.anchors["shoulderR"] ?? IntPoint(12, 3)
            let sleeve = BuddyRig.sleeve(for: ap.outfit)
            let swing = moving ? Int((sw * 2).rounded()) : 0
            let shL = IntPoint(tx + sl.x, ty + sl.y), shR = IntPoint(tx + sr.x, ty + sr.y)
            if f == .side {
                Limbs.drawArm(on: c, shoulder: IntPoint(cx, ty + 3), hand: IntPoint(swing * 2, 8), bend: 1, outward: 1, sleeve: sleeve, style: style)
            } else {
                Limbs.drawArm(on: c, shoulder: shL, hand: IntPoint(-1, 8 + swing), bend: 1, outward: -1, sleeve: sleeve, style: style)
                if waveArm > 0 {
                    Limbs.drawArm(on: c, shoulder: shR, hand: IntPoint(4 + (waveArm % 2), -8), bend: -1, outward: 1, sleeve: sleeve, style: style)
                } else {
                    Limbs.drawArm(on: c, shoulder: shR, hand: IntPoint(1, 8 - swing), bend: 1, outward: 1, sleeve: sleeve, style: style)
                }
            }
        }
        let hy = headY + sink + bob
        if let head = book.get("head.\(f.name)") { c.blit(head, x: headX, y: hy, style: style) }
        let hp = CharacterArt.hairPad
        if let hair = book.get("hair.\(ap.hairStyle.name).\(f.name)") ?? book.get("hair.bob.\(f.name)") {
            c.blit(hair, x: headX - hp.x, y: hy - hp.y, style: style)
        }
        if ap.accessory != .none, ap.accessory != .scarf, let acc = book.get("acc.\(ap.accessory.name).\(f.name)") {
            c.blit(acc, x: headX - hp.x, y: hy - hp.y, style: style)
        }
    }
}
