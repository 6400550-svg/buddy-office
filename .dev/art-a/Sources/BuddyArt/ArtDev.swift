import Foundation
import CoreGraphics
import PixelKit

/// 开发用（只在 .dev/art-a 的拷贝里，不交付）：dump / faces / look 三个预览命令。
public enum ArtDev {
    static func opt(_ a: [String], _ name: String) -> String? { ArtCommands.opt(a, name) }

    static let charOf: [UInt8: Character] = {
        var m: [UInt8: Character] = [0: "."]
        for (c, v) in Role.chars where v != 0 { m[v] = c }
        return m
    }()

    /// dump --name head.front  → 以字符表打印一个精灵（带行列号），--seed 不需要。
    public static func dump(_ a: [String]) -> Int32 {
        guard let name = opt(a, "--name") else { print("用法：dump --name head.front"); return 2 }
        guard let s = CharacterArt.book.get(name) else { print("没有这个精灵：\(name)"); return 1 }
        var header = "   "
        for x in 0..<s.width { header += String(x % 10) }
        print("\(name)  \(s.width)x\(s.height)  anchors=\(s.anchors)")
        print(header)
        for y in 0..<s.height {
            var line = String(format: "%2d ", y)
            for x in 0..<s.width { line.append(charOf[s.value(x, y)] ?? "?") }
            print(line)
        }
        return 0
    }

    /// asc --facing back [--hair bob] [--face happy] [--acc beanie]
    /// 头 + 表情 + 头发（+ 配饰）合成后的字符图（16×20 画布坐标；头盒子左上角在 (2,3)），设计配饰时对着它画。
    public static func asc(_ a: [String]) -> Int32 {
        let hair = opt(a, "--hair") ?? "bob"
        let book = CharacterArt.book
        let facs = (opt(a, "--facing") ?? "back").split(separator: ",").compactMap { n in Facing.allCases.first { $0.name == n } }
        for f in facs {
            var g = [[Character]](repeating: [Character](repeating: ".", count: 16), count: 20)
            func put(_ s: IndexedSprite, _ dx: Int, _ dy: Int) {
                for y in 0..<s.height { for x in 0..<s.width {
                    let v = s.value(x, y)
                    if v != 0, x + dx >= 0, x + dx < 16, y + dy >= 0, y + dy < 20 { g[y + dy][x + dx] = charOf[v] ?? "?" }
                } }
            }
            put(book["head.\(f.name)"], 2, 3)
            if let fc = opt(a, "--face"), let fs = book.get("face.\(fc).\(f.name)") { put(fs, 2, 3) }
            if let h = book.get("hair.\(hair).\(f.name)") { put(h, 0, 0) }
            if let ac = opt(a, "--acc"), let sp = book.get("acc.\(ac).\(f.name)"), ac != "scarf" { put(sp, 0, 0) }
            print("== \(f.name)  (canvas 16x20, head box origin (2,3))")
            print("   " + (0..<16).map { String($0 % 10) }.joined())
            for y in 0..<20 { print(String(format: "%2d ", y) + String(g[y])) }
        }
        return 0
    }

    /// variants --accs glassesA,glassesB --facing front --seeds 10,25 [--face happy] [--zoom 12] [--vh 16] --out x.png
    /// 同一个朝向下并排比较几个配饰变体：列 = 变体，行 = seed。
    public static func variants(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "12") ?? 12
        let vh = Int(opt(a, "--vh") ?? "16") ?? 16
        let out = opt(a, "--out") ?? "dist/art/variants.png"
        var o = LookOpts()
        o.hair = opt(a, "--hair") ?? "bob"
        o.outfit = opt(a, "--outfit") ?? "tee"
        o.face = opt(a, "--face")
        let names = (opt(a, "--accs") ?? "").split(separator: ",").map(String.init)
        let facs = (opt(a, "--facing") ?? "front").split(separator: ",").compactMap { n in Facing.allCases.first { $0.name == n } }
        let seeds = parseSeeds(a, "10,25")
        var cells: [ContactSheet.Cell] = []
        for seed in seeds {
            let ap = appearance(seed)
            for f in facs {
                for n in names {
                    o.acc = n
                    let c = compose(ap, f, o)
                    if let img = FrameRenderer.render(Frame(canvas: c, viewport: IntRect(2, 0, 20, vh)), zoom: zoom, scale: 1) {
                        cells.append(.init(image: img, label: "\(n) \(f.name) s\(seed)"))
                    }
                }
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: names.count, title: "variants \(names) seeds=\(seeds)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("variants: \(out)")
        return 0
    }

    /// cells --accs headphones,beanie --seeds 3,5 [--facing back] [--face happy] [--zoom 8] --out x.png
    /// 工位里的背影（只截人物附近）：列 = 配饰，行 = seed。
    public static func cells(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "8") ?? 8
        let out = opt(a, "--out") ?? "dist/art/cells.png"
        let names = (opt(a, "--accs") ?? "none").split(separator: ",").map(String.init)
        let seeds = parseSeeds(a, "3,5")
        let facing = Facing.allCases.first { $0.name == (opt(a, "--facing") ?? "back") } ?? .back
        var cells: [ContactSheet.Cell] = []
        for seed in seeds {
            for n in names {
                let ap = appearance(seed)
                var p = CellPreview.Params()
                p.facing = facing
                p.hairStyle = opt(a, "--hair") ?? "bob"
                p.outfit = opt(a, "--outfit") ?? "tee"
                p.acc = n == "none" ? nil : n
                p.face = opt(a, "--face")
                let canvas = CellPreview.render(ap, p)
                let frame = Frame(canvas: canvas, viewport: IntRect(12, 8, 30, 36))
                if let img = FrameRenderer.render(frame, zoom: zoom, scale: 1) { cells.append(.init(image: img, label: "\(n) \(facing.name) s\(seed)")) }
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: names.count, title: "cells \(names) seeds=\(seeds)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("cells: \(out)")
        return 0
    }

    /// check：围巾的格子是否都落在躯干上；毛线帽有没有让帽沿上面的头发露出来。
    public static func check(_ a: [String]) -> Int32 {
        let book = CharacterArt.book
        let hair = opt(a, "--hair") ?? "bob", outfit = opt(a, "--outfit") ?? "tee"
        var bad = 0
        for f in Facing.allCases {
            if let sc = book.get("acc.scarf.\(f.name)"), let t = book.get("torso.\(outfit).\(f.name)") {
                for y in 0..<sc.height { for x in 0..<sc.width where sc.value(x, y) != 0 && t.value(x, y) == 0 {
                    print("scarf.\(f.name): (\(x),\(y)) 不在躯干上"); bad += 1
                } }
            }
            if let bn = book.get("acc.beanie.\(f.name)"), let h = book.get("hair.\(hair).\(f.name)") {
                // 每一列：帽子最下面一格之上的头发格必须被帽子盖住
                for x in 0..<bn.width {
                    var bot = -1
                    for y in 0..<bn.height where bn.value(x, y) != 0 { bot = y }
                    if bot < 0 { continue }
                    for y in 0..<bot where h.value(x, y) != 0 && bn.value(x, y) == 0 {
                        print("beanie.\(f.name): 头发 (\(x),\(y)) 没被盖住"); bad += 1
                    }
                }
                // 帽子外面（左右）露出来的头发：帽子这一行的左右端之外、帽子最低行以上的头发
                for y in 0..<bn.height {
                    var x0 = bn.width, x1 = -1
                    for x in 0..<bn.width where bn.value(x, y) != 0 { x0 = min(x0, x); x1 = max(x1, x) }
                    if x1 < 0 { continue }
                    for x in 0..<bn.width where h.value(x, y) != 0 && bn.value(x, y) == 0 && (x < x0 || x > x1) {
                        // 只报告帽子最低那一行以上的
                        var lowest = 0
                        for yy in 0..<bn.height { for xx in 0..<bn.width where bn.value(xx, yy) != 0 { lowest = max(lowest, yy) } }
                        if y < lowest - 2 { print("beanie.\(f.name): 帽子外侧的头发 (\(x),\(y))"); bad += 1 }
                    }
                }
            }
        }
        print("check: \(bad) 处")
        return bad == 0 ? 0 : 1
    }

    struct LookOpts {
        var hair = "bob", outfit = "tee"
        var face: String? = nil
        var acc: String? = nil
        var bare = false
        var canvasW = 24, canvasH = 34
    }

    /// 合成一个朝向（躯干 + 头 + 表情 + 头发 + 配饰）到 24×34 的画布，头盒子左上角在 (6,4)。
    static func compose(_ ap: Appearance, _ f: Facing, _ o: LookOpts, light: LightState = LightState(a: .day)) -> Canvas {
        let st = Lighting.resolved(map: ap.roleMap, state: light)
        let book = CharacterArt.book
        let c = Canvas(width: o.canvasW, height: o.canvasH)
        let headX = 6, headY = 4
        let hp = CharacterArt.hairPad
        var neck = IntPoint(7, 0)
        if let torso = book.get("torso.\(o.outfit).\(f.name)") {
            neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            c.blit(torso, x: headX + 6 - neck.x, y: headY + 13 - neck.y, style: st)
        }
        c.blit(book["head.\(f.name)"], x: headX, y: headY, style: st)
        if let fc = o.face, fc != "neutral", let fs = book.get("face.\(fc).\(f.name)") { c.blit(fs, x: headX, y: headY, style: st) }
        if !o.bare, let h = book.get("hair.\(o.hair).\(f.name)") { c.blit(h, x: headX - hp.x, y: headY - hp.y, style: st) }
        if let ac = o.acc, let sp = book.get("acc.\(ac).\(f.name)") {
            if ac == "scarf" { c.blit(sp, x: headX + 6 - neck.x, y: headY + 13 - neck.y, style: st) }
            else { c.blit(sp, x: headX - hp.x, y: headY - hp.y, style: st) }
        }
        return c
    }

    static func parseSeeds(_ a: [String], _ def: String) -> [UInt64] {
        (opt(a, "--seeds") ?? def).split(separator: ",").compactMap { UInt64($0) }
    }

    static func appearance(_ seed: UInt64) -> Appearance { Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15) }

    /// seeds 一览：打印每个 seed 的肤色 / 发色 / 衣服色 / 点缀色，方便挑样本。
    public static func seeds(_ a: [String]) -> Int32 {
        let n = Int(opt(a, "--n") ?? "40") ?? 40
        for s in 1...n {
            let ap = appearance(UInt64(s))
            print("seed \(s): skin=\(ap.skin) hair=\(ap.hairColor) cloth=\(ap.clothColor) acc=\(ap.accessoryColor) (\(ap.accessory.name))")
        }
        return 0
    }

    /// faces --seeds 3,5 --expr happy,question --facings front,q34front,side --zoom 10 [--bare 1] [--hair bob] --out f.png
    /// 每个 seed 一张，列 = 表情（第一列是中性脸），行 = 朝向。
    public static func faces(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "10") ?? 10
        let out = opt(a, "--out") ?? "dist/art/faces.png"
        var o = LookOpts()
        o.hair = opt(a, "--hair") ?? "bob"
        o.bare = (opt(a, "--bare") ?? "0") == "1"
        o.outfit = opt(a, "--outfit") ?? "tee"
        o.acc = opt(a, "--acc")
        let vh = Int(opt(a, "--vh") ?? "16") ?? 16
        let exprs = (opt(a, "--noneutral") == "1" ? [] : ["neutral"]) + (opt(a, "--expr") ?? "happy,question,worried,sleepy,wow").split(separator: ",").map(String.init)
        let facs = (opt(a, "--facings") ?? "front,q34front,side").split(separator: ",").compactMap { n in Facing.allCases.first { $0.name == n } }
        let seeds = parseSeeds(a, "3")
        var cells: [ContactSheet.Cell] = []
        for seed in seeds {
            let ap = appearance(seed)
            for f in facs {
                for e in exprs {
                    o.face = e
                    let c = compose(ap, f, o)
                    // 只取头部附近：画布 x 4..20, y 1..27
                    let frame = Frame(canvas: c, viewport: IntRect(4, 2, 16, vh))
                    if let img = FrameRenderer.render(frame, zoom: zoom, scale: 1) {
                        cells.append(.init(image: img, label: "\(e) \(f.name) s\(seed)"))
                    }
                }
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: exprs.count, title: "faces seeds=\(seeds) hair=\(o.hair)\(o.bare ? " (bare)" : "")"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("faces: \(out)")
        return 0
    }

    /// look --acc headphones --seeds 3,5,9 [--face happy] [--hair bob] [--outfit tee] [--zoom 10] --out x.png
    /// 每个 seed 一行，列 = 五个朝向。
    public static func look(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "10") ?? 10
        let out = opt(a, "--out") ?? "dist/art/look.png"
        var o = LookOpts()
        o.hair = opt(a, "--hair") ?? "bob"
        o.outfit = opt(a, "--outfit") ?? "tee"
        o.face = opt(a, "--face")
        o.acc = opt(a, "--acc")
        o.bare = (opt(a, "--bare") ?? "0") == "1"
        let facs = (opt(a, "--facings") ?? "back,q34back,side,q34front,front").split(separator: ",").compactMap { n in Facing.allCases.first { $0.name == n } }
        let seeds = parseSeeds(a, "3,5,9")
        var cells: [ContactSheet.Cell] = []
        for seed in seeds {
            let ap = appearance(seed)
            for f in facs {
                let c = compose(ap, f, o)
                if let img = FrameRenderer.render(Frame(canvas: c), zoom: zoom, scale: 1) {
                    cells.append(.init(image: img, label: "\(f.name) s\(seed)"))
                }
            }
        }
        let cols = Int(opt(a, "--cols") ?? "") ?? facs.count
        guard let sheet = ContactSheet.render(cells: cells, columns: cols, title: "\(o.hair)/\(o.outfit)\(o.acc.map { " / " + $0 } ?? "")\(o.face.map { " / face:" + $0 } ?? "") seeds=\(seeds)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("look: \(out)")
        return 0
    }
}
