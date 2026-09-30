import Foundation
import PixelKit
import BuddyArt

/// 办公室后墙 + 地板 + 陈设。静态部分烘焙进背景缓存，动态部分（天空、指针、日历、白板、绿植、饮水机）每帧叠上去。
public final class RoomRenderer {
    public struct DynamicState {
        public var hour: Double            // 本地钟点（小数）
        public var time: Double            // 单调时间（秒，云 / 绿植 / 气泡用）
        public var day: Int                // 几号
        public var tally: Int              // 今天做完了几轮
        public init(hour: Double, time: Double, day: Int, tally: Int) { self.hour = hour; self.time = time; self.day = day; self.tally = tally }
    }

    enum Kind { case door, rack, window, clock, whiteboard, calendar, shelf, poster(Int) }
    struct Module { var kind: Kind; var x: Int; var y: Int; var w: Int }

    public let layout: OfficeLayout
    let seed: UInt64
    var modules: [Module] = []
    var glassRects: [IntRect] = []
    var clocks: [IntPoint] = []          // 表盘中心
    var calendars: [IntPoint] = []       // 日期数字左上角
    var whiteboards: [IntRect] = []      // 板面
    var plants: [IntPoint] = []          // 落地绿植：花盆左上角
    var coolers: [IntPoint] = []
    var floorItems: [(IntPoint, IntRect)] = []
    /// 衣帽架上挂外套的位置（外套左上角）；下班工位的外套挂在这里。
    public private(set) var coatSlots: [IntPoint] = []
    /// 门口的脚点（世界坐标）：进场从这里走出来，离场走回这里。
    public private(set) var doorFeet = IntPoint(16, Metrics.wallH + 3)
    /// 门洞里面（门扇那一块，门框以内）：门开着的时候里面是暗的，人从这里走出来 / 走进去。
    public private(set) var doorInterior = IntRect(0, 0, 0, 0)

    public init(layout: OfficeLayout, seed: UInt64 = 7) {
        self.layout = layout; self.seed = seed
        plan()
    }

    // MARK: 后墙规划：按宽度把陈设摆开，剩下的空隙平均分配
    static let wallSprites: [(Kind, String, Int, Bool)] = []
    func width(of k: Kind) -> Int {
        switch k { case .door: return 22; case .rack: return 12; case .window: return 36; case .clock: return 14; case .whiteboard: return 40
        case .calendar: return 14; case .shelf: return 28; case .poster: return 14 }
    }
    func plan() {
        // 优先级：门+衣帽架、窗、时钟、白板、海报、第二扇窗、日历、书架、海报、窗…；按顺序塞，塞不下就停
        var order: [Kind] = [.door, .rack, .window, .clock, .whiteboard, .poster(0), .window, .calendar, .shelf, .poster(1), .window, .poster(2), .clock, .window, .whiteboard]
        let avail = layout.worldW - 2 * 6
        var chosen: [Kind] = []
        var total = 0
        let minGap = 6
        for k in order {
            let w = width(of: k)
            let add = w + (chosen.isEmpty ? 0 : ((chosen.count == 1) ? 3 : minGap))   // 门和衣帽架挨得近
            if total + add <= avail { chosen.append(k); total += add } else if chosen.count >= 4 { break }
        }
        order = chosen
        let n = order.count
        let sumW = order.reduce(0) { $0 + width(of: $1) }
        var gaps = max(0, n - 1)
        let extra = max(0, avail - sumW)
        // 门与衣帽架之间只留 3，其余平分
        let fixed = (n >= 2) ? 3 : 0
        gaps = max(1, n - 2)
        let gapW = n >= 3 ? (extra - fixed) / gaps : 0
        var x = 6 + (n >= 3 ? 0 : (extra / 2))
        modules = []
        glassRects = []; clocks = []; calendars = []; whiteboards = []; floorItems = []; coatSlots = []
        for (i, k) in order.enumerated() {
            let w = width(of: k)
            var y = 0
            switch k {
            case .door: y = Metrics.wallH + 1 - 46
            case .rack: y = Metrics.wallH + 1 - 40
            case .window: y = 6
            case .clock: y = 8
            case .whiteboard: y = 9
            case .calendar: y = 10
            case .shelf: y = Metrics.wallH + 1 - 44
            case .poster: y = 11
            }
            modules.append(Module(kind: k, x: x, y: y, w: w))
            if case .door = k { doorFeet = IntPoint(x + 11, Metrics.wallH + 3); doorInterior = IntRect(x + 2, y + 2, 18, 43) }
            if case .rack = k { coatSlots = [IntPoint(x - 5, y + 2), IntPoint(x + 7, y + 2), IntPoint(x - 1, y + 10), IntPoint(x + 3, y + 12)] }
            switch k {
            case .window: glassRects.append(IntRect(x + 3, y + 3, 30, 24))
            case .clock: clocks.append(IntPoint(x + 6, y + 6))
            case .calendar: calendars.append(IntPoint(x + 3, y + 7))
            case .whiteboard: whiteboards.append(IntRect(x + 2, y + 2, 36, 22))
            default: break
            }
            x += w + (i == 0 && n >= 2 ? 3 : (n >= 3 ? gapW : 0))
        }
        // 两侧空地：绿植、饮水机、垃圾桶（网格外的边缘才放，不占工位）
        plants = []; coolers = []
        let gx = layout.gridX0, gx1 = layout.gridX0 + layout.cols * Metrics.cellW
        if layout.worldW - gx1 >= 26 { plants.append(IntPoint(layout.worldW - 24, Metrics.wallH + 2)) }
        if gx >= 40 && !(modules.first.map { $0.x + $0.w + 20 > gx - 4 } ?? false) { coolers.append(IntPoint(gx - 24, Metrics.wallH + 6)) }
    }

    // MARK: 静态背景烘焙
    @inline(__always) func hash(_ x: Int, _ y: Int, _ s: UInt64) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x &* 73856093 ^ y &* 19349663)) ^ s &* 0x9E3779B97F4A7C15
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        return h
    }

    public func bake(into c: Canvas, light: LightState) {
        let st = Lighting.resolved(appearance: nil, state: light)
        let W = c.width, H = c.height
        func P(_ n: String) -> UInt8 { Pal.dx(n) }
        // ---- 墙纸：奶油色 + 若隐若现的小菱形点 ----
        c.fillRect(IntRect(0, 0, W, Metrics.wallH), value: P("wall.base"), style: st)
        let wallSh = P("wall.sh")          // 循环里每个像素都查一次调色板字典（Pal.dx(String)）太贵：先取出来
        for y in 0..<Metrics.wallH { for x in 0..<W {
            if (x % 8 == 3 && y % 8 == 3) || (x % 8 == 7 && y % 8 == 7) { c.set(x, y, value: wallSh, style: st) }
        } }
        // 顶部装饰线
        c.hLine(x: 0, y: 0, length: W, value: P("trim.hi"), style: st)
        c.hLine(x: 0, y: 1, length: W, value: P("trim.base"), style: st)
        c.hLine(x: 0, y: 2, length: W, value: P("trim.sh"), style: st)
        c.hLine(x: 0, y: 3, length: W, value: P("wall.sh"), style: st)
        // ---- 护墙板（鼠尾草绿）+ 压条 + 踢脚线 ----
        let dTop = 42
        c.hLine(x: 0, y: dTop, length: W, value: P("trim.hi"), style: st)
        c.hLine(x: 0, y: dTop + 1, length: W, value: P("trim.base"), style: st)
        c.hLine(x: 0, y: dTop + 2, length: W, value: P("dado.deep"), style: st)
        let dadoBase = P("dado.base"), dadoSh = P("dado.sh"), dadoHi = P("dado.hi")
        for y in (dTop + 3)..<57 { for x in 0..<W {
            var v = dadoBase
            if x % 16 == 0 { v = dadoSh } else if x % 16 == 1 { v = dadoHi }
            if y == dTop + 3 { v = dadoSh }
            c.set(x, y, value: v, style: st)
        } }
        c.hLine(x: 0, y: 57, length: W, value: P("trim.hi"), style: st)
        c.hLine(x: 0, y: 58, length: W, value: P("trim.base"), style: st)
        c.hLine(x: 0, y: 59, length: W, value: P("trim.sh"), style: st)
        // ---- 地板：木条，交错的接缝，偶尔深浅不同 ----
        let floorBase = P("floor.base"), floorHi = P("floor.hi"), floorSh = P("floor.sh"), floorGap = P("floor.gap")
        for y in Metrics.wallH..<H { for x in 0..<W {
            let row = (y - Metrics.wallH) / 8
            let seam = (x + row * 13) % 32
            let plank = (x + row * 13) / 32
            let hv = hash(plank, row, seed) % 12
            var v = floorBase
            if hv < 2 { v = floorHi } else if hv == 2 || hv == 3 { v = floorSh }
            if (y - Metrics.wallH) % 8 == 0 { v = floorGap }
            else if seam == 0 { v = floorGap }
            else if hash(x, y, seed &+ 5) % 61 == 0 { v = floorSh }          // 木纹小点
            c.set(x, y, value: v, style: st)
        } }
        // 踢脚线落在地板上的影子
        c.fillDither(IntRect(0, Metrics.wallH, W, 2), value: P("floor.sh"), other: 0, level: 10, style: st)
        // ---- 地毯（网格下面）----
        let g = layout.gridRect
        let r = IntRect(g.x - 6, Metrics.wallH + 8, g.w + 12, g.h - 6)
        func rrect(_ rr: IntRect, _ v: UInt8, cut: Int) {
            for y in rr.y..<rr.maxY { for x in rr.x..<rr.maxX {
                let dx = min(x - rr.x, rr.maxX - 1 - x), dy = min(y - rr.y, rr.maxY - 1 - y)
                if dx + dy < cut { continue }
                c.set(x, y, value: v, style: st)
            } }
        }
        rrect(r, P("rug.sh"), cut: 4)
        rrect(r.insetBy(1), P("rug.base"), cut: 3)
        for y in (r.y + 2)..<(r.maxY - 2) { for x in (r.x + 2)..<(r.maxX - 2) where (x + y) % 6 == 0 && (x % 3 != 0) {
            c.set(x, y, value: P("rug.hi"), style: st)
        } }
        // 金色内边线
        let ri = r.insetBy(4)
        c.strokeRect(ri, value: P("rug.line"), style: st)
        // ---- 后墙陈设 ----
        for m in modules {
            switch m.kind {
            case .door: c.blit(RoomArt.sprite("room.door"), x: m.x, y: m.y, style: st)
            case .rack: c.blit(RoomArt.sprite("room.coatrack"), x: m.x, y: m.y, style: st)
            case .window: c.blit(RoomArt.sprite("room.window"), x: m.x, y: m.y, style: st)
            case .clock: c.blit(RoomArt.sprite("room.clock"), x: m.x, y: m.y, style: st)
            case .whiteboard: c.blit(RoomArt.sprite("room.whiteboard"), x: m.x, y: m.y, style: st)
            case .calendar: c.blit(RoomArt.sprite("room.calendar"), x: m.x, y: m.y, style: st)
            case .poster(let i): c.blit(RoomArt.sprite(["room.poster.mountain", "room.poster.coffee", "room.poster.planet"][i % 3]), x: m.x, y: m.y, style: st)
            case .shelf: bakeShelf(c, x: m.x, y: m.y, st: st)
            }
        }
        // 落地物件的脚下影子
        for m in modules {
            switch m.kind {
            case .door, .rack, .shelf:
                let cx = m.x + m.w / 2
                c.fillEllipse(cx: cx, cy: Metrics.wallH + 2, rx: m.w / 2 + 1, ry: 2, value: P("floor.gap"), style: st, dither: 8)
            default: break
            }
        }
        for p in plants { c.blit(RoomArt.sprite("room.plant.pot"), x: p.x, y: p.y + 14, style: st) }
        for p in coolers { c.blit(RoomArt.sprite("room.cooler"), x: p.x, y: p.y, style: st) }
    }

    func bakeShelf(_ c: Canvas, x: Int, y: Int, st: Resolved) {
        func P(_ n: String) -> UInt8 { Pal.dx(n) }
        let w = 28, h = 44
        c.fillRect(IntRect(x, y, w, h), value: P("woodWalnut.base"), style: st)
        c.strokeRect(IntRect(x, y, w, h), value: P("woodWalnut.out"), style: st)
        c.vLine(x: x + 1, y: y + 1, length: h - 2, value: P("woodWalnut.hi"), style: st)
        // 四层：每层一排书
        let shelfYs = [y + 2, y + 13, y + 24, y + 35]
        let bookColors = ["red.base", "blue.base", "gold.base", "leaf.base", "pink.base", "clothTeal.base", "clothPurple.base", "duck.base"]
        for (si, sy) in shelfYs.enumerated() {
            c.fillRect(IntRect(x + 2, sy, w - 4, 9), value: P("woodWalnut.sh"), style: st)
            var bx = x + 3
            var k = 0
            while bx < x + w - 4 {
                let bw = 2 + Int(hash(si, k, seed) % 2)
                let bh = 5 + Int(hash(si, k + 40, seed) % 4)
                let name = bookColors[Int(hash(si, k + 9, seed) % UInt64(bookColors.count))]
                let idx = Pal.master.has(name) ? name : "red.base"
                c.fillRect(IntRect(bx, sy + 9 - bh, bw, bh), value: P(idx), style: st)
                c.vLine(x: bx, y: sy + 9 - bh, length: bh, value: P("white.base"), style: st)
                bx += bw + (hash(si, k + 77, seed) % 5 == 0 ? 1 : 0)
                k += 1
            }
            c.hLine(x: x + 2, y: sy + 9, length: w - 4, value: P("woodWalnut.hi"), style: st)
        }
    }

    // MARK: 动态部分的范围和「画面指纹」（局部重绘用）
    /// 动态元素（天空、钟、日历、白板、绿植、饮水机）各自可能画到的矩形（宁大勿小）。
    public private(set) lazy var dynamicRects: [IntRect] = {
        var r: [IntRect] = glassRects
        for p in clocks { r.append(IntRect(p.x - 6, p.y - 6, 13, 13)) }
        for p in calendars { r.append(IntRect(p.x - 2, p.y - 1, 13, 9)) }
        r += whiteboards
        let leaves = RoomArt.sprite("room.plant.leaves")
        for p in plants { r.append(IntRect(p.x - 3, p.y - 7, leaves.width + 3, leaves.height + 2)) }
        for p in coolers { r.append(IntRect(p.x + 3, p.y + 1, 5, 6)) }
        return r
    }()
    static func plantPhase(_ time: Double) -> Int { Int((time / 2.5).rounded(.down)) % 4 }
    static func coolerFrame(_ time: Double) -> Int { let cyc = time.truncatingRemainder(dividingBy: 20); return cyc < 1.2 ? Int(cyc / 0.4) : -1 }
    static func cloudStep(_ time: Double) -> Int { Int((time / 3.0).rounded(.down)) }
    /// 动态部分这一刻的指纹：钟点（分钟）、云的位置、绿植、饮水机、日期、白板计数。指纹不变 ⇒ 画出来一样。
    public func dynamicSignature(_ st: DynamicState) -> UInt64 {
        var k = KeyHasher()
        k.add(Int((st.hour * 60).rounded()))
        k.add(Self.cloudStep(st.time)); k.add(Self.plantPhase(st.time)); k.add(Self.coolerFrame(st.time))
        k.add(st.day); k.add(st.tally)
        return k.h
    }

    // MARK: 动态部分
    public func drawDynamic(on c: Canvas, state: DynamicState, light: LightState) {
        let st = Lighting.resolved(appearance: nil, state: light)
        func P(_ n: String) -> UInt8 { Pal.dx(n) }
        // 天空（玻璃区）
        for r in glassRects where c.mayTouch(r) { SkyRenderer.draw(on: c, rect: r, hour: state.hour, time: state.time) }
        // 玻璃上一道很淡的反光（左上角斜线，固定不动）
        for r in glassRects where c.mayTouch(r) {
            for i in 0..<5 { c.set(r.x + 3 + i, r.y + 8 - i, value: P("glass.hi"), style: st) }
        }
        // 钟：只有时针和分针，没有秒针
        for p in clocks where c.mayTouch(IntRect(p.x - 6, p.y - 6, 13, 13)) {
            let minute = state.hour.truncatingRemainder(dividingBy: 1) * 60
            let hourAngle = (state.hour.truncatingRemainder(dividingBy: 12)) / 12 * 2 * Double.pi
            let minAngle = minute / 60 * 2 * Double.pi
            func hand(_ a: Double, _ len: Double, _ v: UInt8) {
                let n = Int(len.rounded(.up))
                for i in 0...n {
                    let x = p.x + Int((sin(a) * Double(i)).rounded()), y = p.y - Int((cos(a) * Double(i)).rounded())
                    c.set(x, y, value: v, style: st)
                }
            }
            for k in 0..<4 {   // 12 3 6 9 点的刻度
                let a = Double(k) * Double.pi / 2
                c.set(p.x + Int((sin(a) * 5).rounded()), p.y - Int((cos(a) * 5).rounded()), value: P("ink2"), style: st)
            }
            hand(hourAngle, 2.5, P("ink0")); hand(minAngle, 4.2, P("ink1"))
            c.set(p.x, p.y, value: P("red.base"), style: st)
        }
        // 日历：日期数字
        for p in calendars where c.mayTouch(IntRect(p.x - 2, p.y - 1, 13, 9)) {
            let s = String(state.day)
            let w = PixelFont.small.width(of: s)
            // 纸面在精灵的第 1…11 列（p.x = 精灵左边 + 3）：按 11 列居中。两位数（如 29）宽 9，原来的写法会伸到右边的阴影 / 边框上去
            PixelFont.small.draw(s, x: p.x - 2 + (11 - w) / 2, y: p.y, value: P("ink1"), style: st, on: c, container: IntRect(p.x - 2, p.y - 1, 11, 8))
        }
        // 白板：用「正」字计数今天完成的轮数
        for r in whiteboards where c.mayTouch(r) { drawTally(c, r, state.tally, st) }
        // 绿植：叶子 0.2 Hz 左右晃 1 像素（每 2.5 秒换一格，整数像素，不抖）
        for p in plants where c.mayTouch(IntRect(p.x - 3, p.y - 7, 40, 30)) {
            let dx = [0, 1, 1, 0][Self.plantPhase(state.time)]
            c.blit(RoomArt.sprite("room.plant.leaves"), x: p.x - 2 + dx, y: p.y - 6, style: st)
        }
        // 饮水机：每 20 秒冒一个 3 帧的气泡（在蓝色水桶里上升）
        for p in coolers where c.mayTouch(IntRect(p.x + 3, p.y + 1, 5, 6)) {
            let cyc = state.time.truncatingRemainder(dividingBy: 20)
            if cyc < 1.2 {
                let f = Self.coolerFrame(state.time)
                let by = p.y + 5 - f
                c.set(p.x + 5, by, value: P("glass.hi"), style: st)
            }
        }
    }

    /// 白板计数：每 5 轮一个「正」字，最后一个可能只写了几笔。
    func drawTally(_ c: Canvas, _ r: IntRect, _ n: Int, _ st: Resolved) {
        func P(_ nm: String) -> UInt8 { Pal.dx(nm) }
        let n = max(0, n)                       // 存的值被写成负数时按 0 画（下面 0..<负数 是运行时陷阱）
        let full = n / 5, rest = n % 5
        let perRow = 5, maxGlyphs = perRow * 3
        let ink = P("red.base")
        // 五笔：上横、中竖、中横右半、左竖、下横
        func stroke(_ gx: Int, _ gy: Int, _ k: Int) {
            switch k {
            case 0: for i in 0..<5 { c.set(gx + i, gy, value: ink, style: st) }
            case 1: for i in 1...3 { c.set(gx + 2, gy + i, value: ink, style: st) }
            case 2: for i in 3...4 { c.set(gx + i, gy + 2, value: ink, style: st) }
            case 3: for i in 1...3 { c.set(gx, gy + i, value: ink, style: st) }
            default: for i in 0..<5 { c.set(gx + i, gy + 4, value: ink, style: st) }
            }
        }
        for gI in 0..<min(maxGlyphs, full + (rest > 0 ? 1 : 0)) {
            let gx = r.x + 3 + (gI % perRow) * 7, gy = r.y + 3 + (gI / perRow) * 6
            let strokes = gI < full ? 5 : rest
            for k in 0..<strokes { stroke(gx, gy, k) }
        }
    }
}
