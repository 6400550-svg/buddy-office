import Foundation
import CoreGraphics
import PixelKit

/// 精灵总表：把注册表里的精灵按名字过滤后排成网格放大，用来逐个检查轮廓（buddyctl sheet）。
public enum SheetRenderer {
    public static func image(of sprite: IndexedSprite, map: RoleMap?, scale: Int, pad: Int = 1, light: LightState = LightState(a: .day)) -> CGImage? {
        let c = Canvas(width: sprite.width + pad * 2, height: sprite.height + pad * 2)
        let st = Lighting.resolved(map: map, state: light)
        c.blit(sprite, x: pad, y: pad, style: st)
        return FrameRenderer.render(Frame(canvas: c), zoom: scale, scale: 1)
    }

    public static func render(book: SpriteBook, filter: String?, map: RoleMap?, scale: Int, columns: Int = 8,
                              title: String? = nil, light: LightState = LightState(a: .day)) -> CGImage? {
        let names = book.order.filter { filter == nil || filter!.isEmpty || $0.contains(filter!) }
        let cells: [ContactSheet.Cell] = names.compactMap { n in
            guard let img = image(of: book[n], map: map, scale: scale, light: light) else { return nil }
            return ContactSheet.Cell(image: img, label: n)
        }
        return ContactSheet.render(cells: cells, columns: columns, title: title)
    }
}
