import Foundation
import BuddyCore
import PixelKit
import BuddyArt

public struct FPoint: Equatable { public var x: Double; public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y } }

public enum UserAsk: Hashable { case approval, question, plan }

/// 一个 buddy 的「身体姿势」种类（和屏幕内容、桌牌文字是三个独立的通道，各有各的最短停留时间）。
public enum PoseKind: Hashable {
    case typing, typingFast, restAtDesk, mouse, searching, thinking, thinkingDeep, leanBack
    case writingPad, delegate, sendFile, alarm, compacting, retry
    case facepalm, shrug, stretch, leanSide, idle, doze, sleep
    case faceUser(UserAsk)
}

/// 桌面上要额外摆出来的道具。
public enum DeskProp: Hashable { case notepad, papers, box, tray, alarm, clipboard }

public struct PoseFrame {
    public var facing: Facing = .back
    public var torsoDy = 0.0, headDx = 0.0, headDy = 0.0
    /// 手的目标（buddy 图层坐标）；nil = 自然下垂。
    public var handL: FPoint? = nil, handR: FPoint? = nil
    /// 逐帧离散的抖动（打字），不经过弹簧。
    public var oscL = IntPoint(0, 0), oscR = IntPoint(0, 0)
    public var bendL = 1, bendR = 1
    public var props: [DeskProp] = []
    public var expression: String? = nil
    /// 手里举着的写字板（计划待审）。
    public var holdClipboard = false
    public init() {}
}

/// 关键落点（buddy 图层坐标）。
enum Spots {
    static let o = SeatGeometry.layerOrigin
    static func at(_ cx: Int, _ cy: Int) -> FPoint { FPoint(Double(cx - o.x), Double(cy - o.y)) }
    static var kbL: FPoint { at(SeatGeometry.kbX + 4, SeatGeometry.kbY + 1) }
    static var kbR: FPoint { at(SeatGeometry.kbX + 13, SeatGeometry.kbY + 1) }
    static var mouse: FPoint { at(SeatGeometry.mouseX + 1, SeatGeometry.mouseY + 2) }
    static var mug: FPoint { at(SeatGeometry.mugX + 3, SeatGeometry.mugY + 2) }
    static var pad: FPoint { at(SeatGeometry.kbX + 21, SeatGeometry.kbY + 1) }
    /// 头（背面朝向）中心附近
    static var headSideR: FPoint { FPoint(Double(BuddyRig.headX + 13), Double(BuddyRig.headY + 10)) }
    static var headBackR: FPoint { FPoint(Double(BuddyRig.headX + 9), Double(BuddyRig.headY + 8)) }
    static var faceL: FPoint { FPoint(Double(BuddyRig.headX + 4), Double(BuddyRig.headY + 12)) }
    static var shoulderR: FPoint { FPoint(Double(BuddyRig.cx + 5), Double(BuddyRig.headY + 16)) }
    static var restL: FPoint { FPoint(Double(BuddyRig.cx - 7), Double(BuddyRig.headY + 24)) }
    static var restR: FPoint { FPoint(Double(BuddyRig.cx + 6), Double(BuddyRig.headY + 24)) }
    static var lapL: FPoint { FPoint(Double(BuddyRig.cx - 4), Double(BuddyRig.headY + 29)) }
    static var lapR: FPoint { FPoint(Double(BuddyRig.cx + 4), Double(BuddyRig.headY + 29)) }
}

public enum PoseLibrary {
    @inline(__always) static func rnd(_ v: Double) -> Double { v.rounded() }

    /// 姿势在 t 秒（从这个姿势开始算）时的样子。gt 是全局时间（一些周期性小动作用）。
    public static func frame(_ kind: PoseKind, t: Double, gt: Double, seed: Int) -> PoseFrame {
        var f = PoseFrame()
        switch kind {
        case .typing, .typingFast:
            // 逐格离散的小动作，每一格 133 ms（7.5 格/秒）= 15 fps 渲染节拍的整整 2 格，节奏均匀。
            // 普通打字：4 格一轮（左手落、抬、右手落、抬）；快速打字：左右手不停交替（每只手的频率是普通的两倍）
            let step = Int(t * 7.5)
            let k = kind == .typing ? step % 4 : (step % 2) * 2
            f.handL = Spots.kbL; f.handR = Spots.kbR
            f.oscL = IntPoint(0, k == 0 ? 1 : 0); f.oscR = IntPoint(0, k == 2 ? 1 : 0)
            f.torsoDy = -0.0
        case .restAtDesk:
            f.handL = Spots.kbL; f.handR = Spots.kbR
        case .mouse, .searching:
            f.handL = Spots.kbL
            let m = Spots.mouse
            f.handR = FPoint(m.x + rnd(sin(t * 1.3) * 1.0), m.y + rnd(cos(t * 0.9) * 1.0))
            f.torsoDy = -1; f.headDy = -1                  // 前倾（朝显示器方向 = 画面往上）
            if kind == .searching { f.headDx = rnd(sin(t * 2.2) * 1.0) }
        case .thinking:
            f.handL = Spots.kbL
            f.handR = Spots.headSideR                      // 手托下巴
            f.torsoDy = 1; f.headDy = 1; f.headDx = rnd(sin(t * 0.5) * 0.6)
        case .thinkingDeep:
            f.handL = Spots.kbL
            // 用笔轻敲桌面（≤ 2 Hz）
            let m = Spots.pad
            f.handR = m
            f.oscR = IntPoint(0, Int(t * 3.75) % 2 == 0 ? 0 : 1)                 // 每格 267 ms（4 拍）
            f.torsoDy = 1; f.headDy = 1
        case .leanBack:
            f.torsoDy = 1; f.headDy = 1
            f.handL = Spots.restL; f.handR = Spots.restR
            // 每 22 秒喝一口（2.6 秒）：手去够杯子再举到嘴边
            let c = (t + Double(seed % 7)).truncatingRemainder(dividingBy: 22)
            if c > 19.4 {
                let p = (c - 19.4) / 2.6
                let mug = Spots.mug, face = Spots.faceL
                let hold = min(1, max(0, p < 0.3 ? p / 0.3 : (p < 0.7 ? 1 : (1 - (p - 0.7) / 0.3))))
                if p < 0.25 { f.handL = FPoint(Spots.restL.x + (mug.x - Spots.restL.x) * (p / 0.25), Spots.restL.y + (mug.y - Spots.restL.y) * (p / 0.25)) }
                else if p < 0.75 { f.handL = FPoint(face.x, face.y) }
                else { let q = (p - 0.75) / 0.25; f.handL = FPoint(face.x + (Spots.restL.x - face.x) * q, face.y + (Spots.restL.y - face.y) * q) }
                _ = hold
            }
        case .writingPad:
            f.handL = Spots.kbL
            f.handR = Spots.pad
            // 在便签本上写字（≤ 3 Hz）：逐帧离散的抖动，不经过弹簧（弹簧跟不上 2.5 Hz 的 1 像素来回，会在取整处闪单个像素）
            // 用同一个节拍推进 x / y：两个不同频率的振荡器会在某些帧撞出「只持续 1 帧」的中间状态，看起来就是闪一下
            let k = Int(t * 7.5) % 4                                         // 每格 133 ms（15 fps 节拍的 2 格）
            f.oscR = IntPoint([-1, 0, 1, 0][k], [0, 1, 0, 1][k])
            f.props = [.notepad]
            f.torsoDy = -1; f.headDy = -1
        case .delegate:
            f.facing = .threeQuarterBack
            f.handL = Spots.restL
            // 指一指，再抱臂督工（这里近似：指向右侧 → 手收回）
            let p = t.truncatingRemainder(dividingBy: 6)
            f.handR = p < 2.2 ? FPoint(Spots.mouse.x + 5, Spots.mouse.y - 2) : Spots.restR
        case .sendFile:
            f.handL = Spots.kbL
            let p = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            let tray = Spots.at(SeatGeometry.deskX + 7, SeatGeometry.deskY + 6)
            f.handR = p < 0.5 ? FPoint(Spots.shoulderR.x + (tray.x - Spots.shoulderR.x) * (p * 2), Spots.shoulderR.y + (tray.y - Spots.shoulderR.y) * (p * 2)) : tray
            f.props = [.tray]
            f.torsoDy = -1
        case .alarm:
            f.handL = Spots.kbL
            f.handR = Spots.at(SeatGeometry.lampX + 4, SeatGeometry.lampY + 12)
            f.oscR = IntPoint(Int(t * 5) % 2, 0)
            f.props = [.alarm]
            f.torsoDy = -1
        case .compacting:
            f.handL = Spots.at(SeatGeometry.kbX + 2, SeatGeometry.kbY + 3)
            f.handR = FPoint(Spots.at(SeatGeometry.kbX + 12, SeatGeometry.kbY + 3).x + rnd(sin(t * 3) * 3), Spots.at(0, SeatGeometry.kbY + 3).y)
            f.props = [.papers, .box]
            f.torsoDy = -1; f.headDy = -1
        case .retry:
            f.handL = Spots.kbL
            // 挠头（≤2 Hz）
            let hd = Spots.headBackR
            f.handR = FPoint(hd.x, hd.y - 3)
            f.oscR = IntPoint(Int(t * 3.75) % 2 == 0 ? 0 : 1, 0)          // 挠头（每格 267 ms）
            f.headDx = 0
        case .facepalm:
            f.handL = Spots.restL
            f.handR = Spots.headBackR
            f.headDy = 2; f.torsoDy = 0
        case .shrug:
            // 两手一摊
            f.handL = FPoint(Double(BuddyRig.cx - 15), Double(BuddyRig.headY + 24))
            f.handR = FPoint(Double(BuddyRig.cx + 15), Double(BuddyRig.headY + 24))
            f.headDy = -1; f.torsoDy = -1
        case .stretch:
            // 伸懒腰 1.2 秒：手举过头，身体往后仰再回来
            let p = min(1, t / 1.2)
            let up = sin(p * Double.pi)                    // 0 → 1 → 0
            f.handL = FPoint(Double(BuddyRig.cx - 10) - 3 * up, Double(BuddyRig.headY + 24) - 22 * up)
            f.handR = FPoint(Double(BuddyRig.cx + 10) + 3 * up, Double(BuddyRig.headY + 24) - 22 * up)
            f.torsoDy = rnd(up * 1.0); f.headDy = rnd(up * 1.0)
        case .leanSide, .idle:
            f.facing = .threeQuarterBack
            f.torsoDy = 1; f.headDy = 1
            f.handL = Spots.restL; f.handR = Spots.restR
            // 每 45 秒喝一口 + 四处看一下
            let c = (t + Double(seed % 11)).truncatingRemainder(dividingBy: 45)
            if c > 40 && c < 42.6 {
                f.handL = FPoint(Spots.faceL.x, Spots.faceL.y)
            }
            if c > 30 && c < 31.6 { f.facing = .side; f.headDx = 0 }
        case .doze:
            f.torsoDy = 1
            f.headDy = 1 + rnd(0.5 + 0.5 * sin(t * 0.7) * 1.0)
            f.handL = Spots.kbL; f.handR = Spots.kbR
        case .sleep:
            f.torsoDy = 3; f.headDy = 6
            f.handL = Spots.at(SeatGeometry.kbX + 3, SeatGeometry.kbY + 2)
            f.handR = Spots.at(SeatGeometry.kbX + 16, SeatGeometry.kbY + 2)
        case .faceUser(let ask):
            f.facing = .front
            f.handL = nil
            switch ask {
            case .approval:
                // 举手轻轻挥（1.2 Hz）
                let w = sin(t * 2 * Double.pi * 1.2)
                f.handR = FPoint(Double(BuddyRig.cx + 10) + rnd(w * 2), Double(BuddyRig.headY + 8))
                f.bendR = -1
            case .question:
                f.handR = FPoint(Double(BuddyRig.cx + 10), Double(BuddyRig.headY + 6 + Int(rnd(sin(t * 2) * 1))))
                f.bendR = -1; f.expression = "question"
            case .plan:
                f.handL = FPoint(Double(BuddyRig.cx - 8), Double(BuddyRig.headY + 26))
                f.handR = FPoint(Double(BuddyRig.cx + 8), Double(BuddyRig.headY + 26))
                f.holdClipboard = true
            }
        }
        return f
    }
}
