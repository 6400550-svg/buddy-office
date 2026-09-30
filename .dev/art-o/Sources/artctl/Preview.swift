import Foundation
import CoreGraphics
import BuddyArt
import PixelKit

/// 我自己的隔离包里的预览工具（不交付）：把「衣服 × 朝向 × 外观」排成一张大表，方便对比。
enum Preview {
    static func opt(_ a: [String], _ n: String) -> String? { ArtCommands.opt(a, n) }
    static func list(_ s: String?) -> [String] { (s ?? "").split(separator: ",").map(String.init) }

    /// 外观：seed 决定；--cloth / --acc / --skin / --hc 可以按 seed 顺序逐个覆盖（一个数 = 全部相同）
    static func appearance(seed: UInt64, index: Int, a: [String]) -> Appearance {
        var ap = Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15)
        func pick(_ name: String) -> Int? {
            let l = list(opt(a, name)).compactMap { Int($0) }
            if l.isEmpty { return nil }
            return l.count == 1 ? l[0] : l[min(index, l.count - 1)]
        }
        if let c = pick("--cloth") { ap.clothColor = c }
        if let c = pick("--acc") { ap.accessoryColor = c }
        if let c = pick("--skin") { ap.skin = c }
        if let c = pick("--hc") { ap.hairColor = c }
        return ap
    }

    static func bare(_ ap: Appearance, hair: String, outfit: String, facing f: Facing, zoom: Int, withArms: Bool, crop: IntRect? = nil) -> CGImage? {
        let st = Lighting.resolved(map: ap.roleMap, state: LightState(a: .day))
        let book = CharacterArt.book
        let c = Canvas(width: 24, height: 34)
        let headX = 6, headY = 4
        let hp = CharacterArt.hairPad
        if let torso = book.get("torso.\(outfit).\(f.name)") {
            let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
            let tx = headX + 6 - neck.x, ty = headY + 13 - neck.y
            c.blit(torso, x: tx, y: ty, style: st)
            if withArms {
                let sl = torso.anchors["shoulderL"] ?? IntPoint(1, 3), sr = torso.anchors["shoulderR"] ?? IntPoint(12, 3)
                let arm = book["arm.typeUp"]
                let sh = arm.anchors["shoulder"] ?? IntPoint(2, 10)
                c.blit(arm, x: tx + sl.x - sh.x, y: ty + sl.y - sh.y, style: st)
                c.blit(arm, x: tx + sr.x - (arm.width - 1 - sh.x), y: ty + sr.y - sh.y, flipH: true, style: st)
            }
        }
        c.blit(book["head.\(f.name)"], x: headX, y: headY, style: st)
        if let h = book.get("hair.\(hair).\(f.name)") { c.blit(h, x: headX - hp.x, y: headY - hp.y, style: st) }
        var fr = Frame(canvas: c)
        if let cr = crop { fr.viewport = cr }
        return FrameRenderer.render(fr, zoom: zoom, scale: 1)
    }

    static func scene(_ ap0: Appearance, hair: String, outfit: String, facing f: Facing, zoom: Int, crop: IntRect? = nil) -> CGImage? {
        var ap = ap0
        if let of = Outfit.allCases.first(where: { $0.name == outfit }) { ap.outfit = of }
        if let hs = HairStyle.allCases.first(where: { $0.name == hair }) { ap.hairStyle = hs }
        var p = CellPreview.Params()
        p.facing = f; p.hairStyle = hair; p.outfit = outfit
        let canvas = CellPreview.render(ap, p)
        var fr = Frame(canvas: canvas)
        fr.viewport = crop ?? IntRect(8, 12, 36, 34)
        return FrameRenderer.render(fr, zoom: zoom, scale: 1)
    }

    /// outfits [--outfit a,b] [--facing x,y] [--seeds 1,2,3] [--mode bare|arms|scene] [--hair bob] [--zoom 8] [--cloth n,n] [--acc n,n] [--out f.png]
    static func outfits(_ a: [String]) -> Int32 {
        let outfits = list(opt(a, "--outfit") ?? "tee,hoodie,cardigan,shirt,vest,jacket")
        let facings = list(opt(a, "--facing") ?? "back,q34back,side,q34front,front").compactMap { n in Facing.allCases.first { $0.name == n } }
        let seeds = list(opt(a, "--seeds") ?? "1,2,3").compactMap { UInt64($0) }
        let hair = opt(a, "--hair") ?? "bob"
        let mode = opt(a, "--mode") ?? "bare"
        let zoom = Int(opt(a, "--zoom") ?? "8") ?? 8
        let out = opt(a, "--out") ?? "dist/art/outfits.png"
        var crop: IntRect? = nil
        if let c = opt(a, "--crop") {
            let v = c.split(separator: ",").compactMap { Int($0) }
            if v.count == 4 { crop = IntRect(v[0], v[1], v[2], v[3]) }
        }
        var cells: [ContactSheet.Cell] = []
        for (i, seed) in seeds.enumerated() {
            let ap = appearance(seed: seed, index: i, a: a)
            for o in outfits {
                for f in facings {
                    let img: CGImage?
                    switch mode {
                    case "scene": img = scene(ap, hair: hair, outfit: o, facing: f, zoom: zoom, crop: crop)
                    case "arms": img = bare(ap, hair: hair, outfit: o, facing: f, zoom: zoom, withArms: true, crop: crop)
                    default: img = bare(ap, hair: hair, outfit: o, facing: f, zoom: zoom, withArms: false, crop: crop)
                    }
                    if let im = img { cells.append(.init(image: im, label: "\(o) \(f.name) s\(seed) cl\(ap.clothColor) ac\(ap.accessoryColor)")) }
                }
            }
        }
        let cols = facings.count > 1 ? facings.count : max(1, min(outfits.count, 6))
        guard let sheet = ContactSheet.render(cells: cells, columns: cols, title: "\(mode) / \(hair)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("outfits: \(out) \(sheet.width)x\(sheet.height)")
        return 0
    }

    /// seeds [--n 40]：列出前 N 个 seed 的肤色 / 发色 / 衣服色 / 点缀色
    static func seeds(_ a: [String]) -> Int32 {
        let n = Int(opt(a, "--n") ?? "40") ?? 40
        let clothNames = ["red", "orange", "yellow", "green", "teal", "sky", "indigo", "purple", "pink", "cream"]
        let accNames = ["red", "yellow", "mint", "sky", "lilac", "white"]
        for s in 1...n {
            let ap = Appearance.generate(seed: UInt64(s) &* 0x9E3779B97F4A7C15)
            print("seed \(s): skin\(ap.skin) hair\(ap.hairColor) cloth=\(clothNames[ap.clothColor])(\(ap.clothColor)) acc=\(accNames[ap.accessoryColor])(\(ap.accessoryColor))")
        }
        return 0
    }

    /// dump [--filter torso.shirt]：把精灵打印成角色字符（方便手改）
    static func dump(_ a: [String]) -> Int32 {
        let filter = opt(a, "--filter") ?? "torso."
        var inv: [UInt8: Character] = [:]
        for (ch, v) in Role.chars { inv[v] = ch }
        for n in CharacterArt.book.order where n.contains(filter) {
            let s = CharacterArt.book[n]
            let an = s.anchors.sorted { $0.key < $1.key }.map { "\($0.key)=(\($0.value.x),\($0.value.y))" }.joined(separator: " ")
            print("// \(n)  \(s.width)x\(s.height)  \(an)")
            for y in 0..<s.height { print(String((0..<s.width).map { inv[s.pixels[y * s.width + $0]] ?? "?" })) }
            print("")
        }
        return 0
    }
}
