import Foundation
import PixelKit

/// 美术相关的命令行入口（buddyctl 和开发用的 buddyart 共用）。
public enum ArtCommands {
    public static func opt(_ a: [String], _ name: String) -> String? {
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// cell [--seed N] [--facing back|front|…] [--hair bob] [--outfit tee] [--zoom 8] [--time 12] [--out f.png]
    public static func cell(_ a: [String]) -> Int32 {
        let seed = UInt64(opt(a, "--seed") ?? "1") ?? 1
        let zoom = Int(opt(a, "--zoom") ?? "8") ?? 8
        let out = opt(a, "--out") ?? "dist/art/cell.png"
        var ap = Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15)
        var p = CellPreview.Params()
        if let f = opt(a, "--facing"), let fc = Facing.allCases.first(where: { $0.name == f }) { p.facing = fc }
        if let h = opt(a, "--hair") { p.hairStyle = h }
        if let o = opt(a, "--outfit") { p.outfit = o }
        p.acc = opt(a, "--acc"); p.face = opt(a, "--face")
        if let t = opt(a, "--time"), let hr = Double(t) { p.light = DaySchedule.state(atHour: hr) }
        p.lampOn = (opt(a, "--lamp") ?? "0") == "1"
        p.typingFrame = Int(opt(a, "--frame") ?? "0") ?? 0
        if let cs = opt(a, "--cloth"), let ci = Int(cs) { ap.clothColor = ci }
        let canvas = CellPreview.render(ap, p)
        guard let img = FrameRenderer.render(Frame(canvas: canvas), zoom: zoom, scale: 1) else { return 1 }
        do { try PNGExport.write(img, to: URL(fileURLWithPath: out)) } catch { print("\(error)"); return 1 }
        print("cell: \(out) \(img.width)x\(img.height)  \(ap.hairStyle.name)/\(ap.outfit.name) chair=\(ap.chair.name)")
        return 0
    }

    /// strip [--seed N] [--hair bob] [--outfit tee] [--acc headphones] [--face happy] [--zoom 10]
    /// 五个朝向排成一条（躯干 + 头 + 表情 + 头发 + 配饰），检查朝向之间接不接得上。
    /// --acc 可以是 headphones/glasses/beanie/hairpin（画在头发之后）或 scarf（躯干之后、头之后）。
    public static func strip(_ a: [String]) -> Int32 {
        let seed = UInt64(opt(a, "--seed") ?? "1") ?? 1
        let zoom = Int(opt(a, "--zoom") ?? "10") ?? 10
        let out = opt(a, "--out") ?? "dist/art/strip.png"
        let hair = opt(a, "--hair") ?? "bob", outfit = opt(a, "--outfit") ?? "tee"
        let acc = opt(a, "--acc"), face = opt(a, "--face")
        let ap = Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15)
        let st = Lighting.resolved(map: ap.roleMap, state: LightState(a: .day))
        let book = CharacterArt.book
        var cells: [ContactSheet.Cell] = []
        for f in Facing.allCases {
            let c = Canvas(width: 24, height: 34)
            let headX = 6, headY = 4
            let hp = CharacterArt.hairPad
            if let torso = book.get("torso.\(outfit).\(f.name)") {
                let neck = torso.anchors["neck"] ?? IntPoint(7, 0)
                c.blit(torso, x: headX + 6 - neck.x, y: headY + 13 - neck.y, style: st)
            }
            c.blit(book["head.\(f.name)"], x: headX, y: headY, style: st)
            if let fc = face, let fs = book.get("face.\(fc).\(f.name)") { c.blit(fs, x: headX, y: headY, style: st) }
            if let h = book.get("hair.\(hair).\(f.name)") { c.blit(h, x: headX - hp.x, y: headY - hp.y, style: st) }
            if let ac = acc, let sp = book.get("acc.\(ac).\(f.name)") {
                if ac == "scarf" {
                    let neck = book.get("torso.\(outfit).\(f.name)")?.anchors["neck"] ?? IntPoint(7, 0)
                    c.blit(sp, x: headX + 6 - neck.x, y: headY + 13 - neck.y, style: st)
                } else { c.blit(sp, x: headX - hp.x, y: headY - hp.y, style: st) }
            }
            if let img = FrameRenderer.render(Frame(canvas: c), zoom: zoom, scale: 1) { cells.append(.init(image: img, label: f.name)) }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: 5, title: "\(hair) / \(outfit)\(acc.map { " / " + $0 } ?? "")\(face.map { " / face:" + $0 } ?? "") / seed \(seed)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("strip: \(out)")
        return 0
    }

    /// sheet [--filter 子串] [--scale 6] [--cols 8] [--seed N] [--out 文件.png]
    public static func sheet(_ a: [String]) -> Int32 {
        let scale = Int(opt(a, "--scale") ?? "6") ?? 6
        let cols = Int(opt(a, "--cols") ?? "8") ?? 8
        let seed = UInt64(opt(a, "--seed") ?? "1") ?? 1
        let out = opt(a, "--out") ?? "dist/sheet.png"
        let filter = opt(a, "--filter")
        let ap = Appearance.generate(seed: seed &* 0x9E3779B97F4A7C15)
        let which = opt(a, "--book") ?? "char"
        let book: SpriteBook
        var map: RoleMap? = ap.roleMap
        switch which {
        case "preview": book = CharacterArt.previewBook
        case "props": book = PropArt.book; map = nil
        default: book = CharacterArt.book
        }
        guard let img = SheetRenderer.render(book: book, filter: filter, map: map, scale: scale, columns: cols,
                                             title: "sprites \(filter ?? "all")  seed \(seed)  \(ap.hairStyle.name)/\(ap.outfit.name)") else {
            print("没有匹配的精灵"); return 1
        }
        do { try PNGExport.write(img, to: URL(fileURLWithPath: out)) } catch { print("\(error)"); return 1 }
        for e in book.errors { print("⚠️ \(e)") }
        print("sheet[\(which)]: \(book.order.count) 个精灵，输出 \(out) (\(img.width)x\(img.height))，错误 \(book.errors.count) 个")
        return book.errors.isEmpty ? 0 : 1
    }
}
