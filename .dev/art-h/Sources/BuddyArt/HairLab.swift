import Foundation
import CoreGraphics
import PixelKit

/// 发型实验室（只在 .dev/art-h 这份拷贝里存在，不交付）：
///  · lab      一张图里同时看「5 个朝向 × 多种发色/肤色/衣服色/点缀色」，可换背景、换时段、只看某几个朝向、裁到头部；
///  · labcell  并排若干个工位（背影坐姿）；
///  · dump     把精灵按字符倾倒出来对坐标；
///  · check    检查每个发型有没有盖住脸的禁区、耳朵、后颈；
///  · 所有命令都支持 `--live 路径/HairStyles.swift`：不用重新编译，直接从源码里把 addHairFull(...) 的字面量读出来替换掉精灵。
public enum HairLab {
    static let skinsPreset = [1, 0, 2, 3, 1, 4, 0, 2, 3, 1]
    static let clothPreset = [5, 0, 3, 7, 2, 9, 1, 4, 6, 8]

    static func opt(_ a: [String], _ n: String) -> String? { ArtCommands.opt(a, n) }

    static func appearance(seed: UInt64, hairColor: Int, skin: Int, cloth: Int, accent: Int? = nil) -> Appearance {
        var a = Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15)
        a.hairColor = hairColor; a.skin = skin; a.clothColor = cloth
        if let ac = accent { a.accessoryColor = ac }
        return a
    }

    static func light(_ name: String?) -> LightState {
        switch name ?? "day" {
        case "night": return LightState(a: .night)
        case "dusk": return LightState(a: .dusk)
        case "dawn": return LightState(a: .dawn)
        default: return LightState(a: .day)
        }
    }

    static func facings(_ a: [String]) -> [Facing] {
        guard let s = opt(a, "--facings") else { return Facing.allCases }
        let names = s.split(separator: ",").map(String.init)
        return Facing.allCases.filter { names.contains($0.name) }
    }

    // MARK: 从源码读取字面量（免编译迭代）
    static func facing(named n: String) -> Facing? {
        switch n {
        case "back": return .back
        case "threeQuarterBack": return .threeQuarterBack
        case "side": return .side
        case "threeQuarterFront": return .threeQuarterFront
        case "front": return .front
        default: return nil
        }
    }

    @discardableResult
    static func loadLive(_ a: [String]) -> Int {
        guard let paths = opt(a, "--live") else { return 0 }
        var n = 0
        for path in paths.split(separator: ",").map(String.init) { n += loadLiveFile(path) }
        return n
    }

    static func loadLiveFile(_ path: String) -> Int {
        guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { print("读不到 \(path)"); return 0 }
        let pattern = #"addHairFull\(book,\s*"(\w+)",\s*\.(\w+),\s*(?:x0:\s*(-?\d+),\s*)?(?:y0:\s*(-?\d+),\s*)?mask:\s*"""(.*?)"""(?:,\s*detail:\s*"""(.*?)""")?\s*\)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return 0 }
        let ns = src as NSString
        var n = 0
        for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            guard let style = g(1), let fn = g(2), let f = facing(named: fn), let mask = g(5) else { continue }
            let x0 = Int(g(3) ?? "0") ?? 0, y0 = Int(g(4) ?? "0") ?? 0
            let sp = CharacterArt.hairFullSprite(name: "hair.\(style).\(f.name)", x0: x0, y0: y0, mask: mask, detail: g(6) ?? "")
            CharacterArt.book.add(sp)
            n += 1
        }
        return n
    }

    // MARK: 渲染小人
    /// 24×34 的小人（躯干 + 头 + 头发），背景可选。
    static func figure(_ ap: Appearance, hair: String, outfit: String, facing f: Facing, bg: String, light ls: LightState, bare: Bool = false) -> Canvas {
        let c = Canvas(width: 24, height: 34)
        let scene = Lighting.resolved(map: nil, state: ls)
        let st = Lighting.resolved(map: ap.roleMap, state: ls)
        switch bg {
        case "wall": c.fillRect(c.bounds, value: Pal.dx("wall.base"), style: scene)
        case "floor": c.fillRect(c.bounds, value: Pal.dx("floor.base"), style: scene)
        case "dado": c.fillRect(c.bounds, value: Pal.dx("dado.base"), style: scene)
        case "screen": c.fillRect(c.bounds, value: Pal.dx("scr.bg"), style: scene)
        case "dark": c.fillRect(c.bounds, value: Pal.dx("ink1"), style: scene)
        default: break
        }
        let book = CharacterArt.book
        let headX = 6, headY = 4
        let hp = CharacterArt.hairPad
        if !bare, let torso = book.get("torso.\(outfit).\(f.name)") {
            let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            c.blit(torso, x: headX + 6 - neck.x, y: headY + 13 - neck.y, style: st)
        }
        if !bare { c.blit(book["head.\(f.name)"], x: headX, y: headY, style: st) }
        if let h = book.get("hair.\(hair).\(f.name)") { c.blit(h, x: headX - hp.x, y: headY - hp.y, style: st) }
        return c
    }

    /// lab --hair X [--colors 0,3,5,7] [--outfit tee] [--bg wall] [--light day] [--zoom 8] [--seed 1]
    ///     [--facings back,side] [--crop 1] [--live path] [--out f.png]
    public static func lab(_ a: [String]) -> Int32 {
        loadLive(a)
        let hairs = (opt(a, "--hair") ?? "bob").split(separator: ",").map(String.init)
        let hair = hairs.joined(separator: "+")
        let outfit = opt(a, "--outfit") ?? "tee"
        let zoom = Int(opt(a, "--zoom") ?? "8") ?? 8
        let seed = UInt64(opt(a, "--seed") ?? "1") ?? 1
        let bgs = (opt(a, "--bg") ?? "wall").split(separator: ",").map(String.init)
        let ls = light(opt(a, "--light"))
        let crop = (opt(a, "--crop") ?? "0") == "1"
        let bare = (opt(a, "--bare") ?? "0") == "1"
        let colors = (opt(a, "--colors") ?? "0,3,5,7").split(separator: ",").compactMap { Int($0) }
        let fs = facings(a)
        let out = opt(a, "--out") ?? "dist/art/lab.png"
        var cells: [ContactSheet.Cell] = []
        for hname in hairs {
            for (i, hc) in colors.enumerated() {
                let ap = appearance(seed: seed, hairColor: hc, skin: skinsPreset[i % skinsPreset.count],
                                    cloth: clothPreset[(i + Int(seed)) % clothPreset.count], accent: (i + 1) % 6)
                for f in fs {
                    let cv = figure(ap, hair: hname, outfit: outfit, facing: f, bg: bgs[i % bgs.count], light: ls, bare: bare)
                    let vp: IntRect? = crop ? IntRect(2, 0, 20, 26) : nil
                    if let img = FrameRenderer.render(Frame(canvas: cv, viewport: vp), zoom: zoom, scale: 1) {
                        cells.append(.init(image: img, label: "\(hname) \(f.name) hair\(hc) skin\(ap.skin) acc\(ap.accessoryColor)"))
                    }
                }
            }
        }
        let cols = Int(opt(a, "--cols") ?? "") ?? (fs.count > 1 ? fs.count : colors.count)
        guard let sheet = ContactSheet.render(cells: cells, columns: cols, padding: 6, labelHeight: 14, title: "\(hair) / \(outfit) / bg:\(bgs.joined(separator: ",")) / \(opt(a, "--light") ?? "day")"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("lab: \(out)")
        return 0
    }

    /// labcell --hair X [--n 4] [--facing back] [--zoom 6] [--light day] [--live path] [--out f.png]
    /// 并排 n 个工位（背影坐姿），发色/肤色/衣服/椅子各不相同。
    public static func labcell(_ a: [String]) -> Int32 {
        loadLive(a)
        let hair = opt(a, "--hair") ?? "bob"
        let outfit = opt(a, "--outfit") ?? "tee"
        let n = Int(opt(a, "--n") ?? "4") ?? 4
        let zoom = Int(opt(a, "--zoom") ?? "6") ?? 6
        let seed = UInt64(opt(a, "--seed") ?? "1") ?? 1
        let colors = (opt(a, "--colors") ?? "0,3,5,6,1,7,2,4").split(separator: ",").compactMap { Int($0) }
        let out = opt(a, "--out") ?? "dist/art/labcell.png"
        var p = CellPreview.Params()
        p.hairStyle = hair; p.outfit = outfit
        if let f = opt(a, "--facing"), let fc = Facing.allCases.first(where: { $0.name == f }) { p.facing = fc }
        p.light = light(opt(a, "--light"))
        p.lampOn = (opt(a, "--lamp") ?? "0") == "1"
        var cells: [ContactSheet.Cell] = []
        let hairsList = (opt(a, "--hairs") ?? "").split(separator: ",").map(String.init)
        let count = hairsList.isEmpty ? n : hairsList.count
        for i in 0..<count {
            if !hairsList.isEmpty { p.hairStyle = hairsList[i] }
            let hc = colors[i % colors.count]
            var ap = appearance(seed: seed &+ UInt64(i), hairColor: hc, skin: skinsPreset[i % skinsPreset.count],
                                cloth: clothPreset[(i + Int(seed)) % clothPreset.count], accent: (i + 1) % 6)
            ap.chair = ChairStyle(rawValue: i % 3)!
            let cv = CellPreview.render(ap, p)
            if let img = FrameRenderer.render(Frame(canvas: cv), zoom: zoom, scale: 1) {
                cells.append(.init(image: img, label: "\(p.hairStyle) hair\(hc) skin\(ap.skin) cloth\(ap.clothColor) \(ap.chair.name)"))
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: min(count, Int(opt(a, "--cols") ?? "4") ?? 4), padding: 6, labelHeight: 14, title: "\(hair) / \(outfit) / \(p.facing.name)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("labcell: \(out)")
        return 0
    }

    /// dump --sprite hair.bob.back [--live path]：按字符倾倒（带行列标尺，行列号是头盒子坐标）。
    public static func dump(_ a: [String]) -> Int32 {
        loadLive(a)
        guard let name = opt(a, "--sprite"), let s = CharacterArt.book.get(name) else { print("没有这个精灵"); return 1 }
        var rev: [UInt8: Character] = [:]
        for (ch, r) in Role.chars where r != 0 { rev[r] = ch }
        let isHair = name.hasPrefix("hair.")
        let ox = isHair ? CharacterArt.hairPad.x : 0, oy = isHair ? CharacterArt.hairPad.y : 0
        var head = "      "
        for x in 0..<s.width { head += String(format: "%2d", x - ox) }
        print(head)
        for y in 0..<s.height {
            var line = String(format: "%3d | ", y - oy)
            for x in 0..<s.width {
                let v = s.pixels[y * s.width + x]
                line += " " + String(v == 0 ? "." : (rev[v] ?? "?"))
            }
            print(line)
        }
        return 0
    }

    /// check [--hair X] [--live path]：脸的禁区、耳朵、后脑覆盖。
    public static func check(_ a: [String]) -> Int32 {
        loadLive(a)
        let only = opt(a, "--hair")
        let book = CharacterArt.book
        // 背面 / 3/4 背面必须盖住整个后脑（含耳朵，第 10 行以上）；短发/寸头例外（露出耳朵和后颈）
        let coverBack: Set<String> = ["ponytail", "bun", "twinBuns", "long", "bob", "curly"]
        let earsAlways: Set<String> = ["messy", "buzz"]                                  // 任何朝向耳朵都要露出来
        let earsSide: Set<String> = ["ponytail", "bun", "twinBuns", "messy", "buzz"]     // 侧面耳朵 (3–4, 8–10) 要露出来
        var problems = 0
        for style in ["ponytail", "bun", "twinBuns", "long", "bob", "messy", "buzz", "curly"] {
            if let o = only, o != style { continue }
            for f in Facing.allCases {
                guard let s = book.get("hair.\(style).\(f.name)"), let head = book.get("head.\(f.name)") else {
                    if only != nil || style != "bob" { print("缺：hair.\(style).\(f.name)") }
                    continue
                }
                let hp = CharacterArt.hairPad
                func has(_ x: Int, _ y: Int) -> Bool {
                    let sx = x + hp.x, sy = y + hp.y
                    return sx >= 0 && sy >= 0 && sx < s.width && sy < s.height && s.pixels[sy * s.width + sx] != 0
                }
                func skull(_ x: Int, _ y: Int) -> Bool {
                    x >= 0 && y >= 0 && x < head.width && y < head.height && head.pixels[y * head.width + x] != 0
                }
                var bad: [String] = []
                func forbid(_ what: String, _ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>) {
                    var hit: [String] = []
                    for y in ys { for x in xs where has(x, y) { hit.append("(\(x),\(y))") } }
                    if !hit.isEmpty { bad.append("\(what) 被盖住 \(hit.count) 格：\(hit.prefix(8).joined(separator: " "))") }
                }
                switch f {
                case .front: forbid("脸", 2...9, 6...12)
                case .threeQuarterFront: forbid("脸", 3...9, 6...12)
                case .side: forbid("脸", 7...11, 6...12)
                case .threeQuarterBack: forbid("耳/脸颊", 10...11, 8...10)
                case .back: break
                }
                if earsAlways.contains(style) {
                    switch f {
                    case .back, .front: forbid("耳朵", 0...0, 8...8); forbid("耳朵", 11...11, 8...8)
                    case .threeQuarterFront: forbid("耳朵", 0...0, 8...8)
                    default: break
                    }
                }
                if earsSide.contains(style), f == .side { forbid("耳朵", 3...4, 8...10) }
                if coverBack.contains(style), f == .back || f == .threeQuarterBack {
                    var open: [String] = []
                    for y in 0..<head.height { for x in 0..<head.width where skull(x, y) && !has(x, y) && y <= 10 {
                        if f == .threeQuarterBack && x >= 10 && (8...10).contains(y) { continue }
                        open.append("(\(x),\(y))")
                    } }
                    if !open.isEmpty { bad.append("后脑没盖住 \(open.count) 格：\(open.prefix(8).joined(separator: " "))") }
                }
                // 孤立的小碎点（≤2 格，8 连通；肤色阴影 j 和寸头的发茬不算）
                if style != "buzz" {
                    var seen = Set<Int>()
                    var strays: [String] = []
                    for sy in 0..<s.height { for sx in 0..<s.width {
                        let i = sy * s.width + sx
                        guard s.pixels[i] != 0, s.pixels[i] != Role.skinSh, !seen.contains(i) else { continue }
                        var stack = [(sx, sy)], comp: [(Int, Int)] = []
                        seen.insert(i)
                        while let (cx, cy) = stack.popLast() {
                            comp.append((cx, cy))
                            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                                let nx = cx + dx, ny = cy + dy
                                guard nx >= 0, ny >= 0, nx < s.width, ny < s.height else { continue }
                                let j = ny * s.width + nx
                                if s.pixels[j] != 0, s.pixels[j] != Role.skinSh, !seen.contains(j) { seen.insert(j); stack.append((nx, ny)) }
                            } }
                        }
                        if comp.count <= 2 { strays.append("(\(comp[0].0 - hp.x),\(comp[0].1 - hp.y))×\(comp.count)") }
                    } }
                    if !strays.isEmpty { bad.append("孤立小碎点 \(strays.joined(separator: " "))") }
                }
                if !bad.isEmpty { problems += bad.count; print("✗ \(s.name)：" + bad.joined(separator: "；")) }
            }
        }
        print(problems == 0 ? "check: 没有问题" : "check: \(problems) 个问题")
        return problems == 0 ? 0 : 1
    }
}
