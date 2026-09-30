import Foundation
import PixelKit
import BuddyArt

/// 像素提示卡：系统通知没授权（或被拒）时，从右上角弹簧滑入的提示面板用它；文字用苹方，边框和图标是像素。
public enum ToastCard {
    public enum Kind { case approval, question, plan, finished, blocked, error, info }

    public static func make(kind: Kind, title: String, body: String, zoom: Int) -> HoverCard.Card {
        let ink = RGBA8(hex: 0x2E2230), dim = RGBA8(hex: 0x6E5A66)
        let tStyle = TextStyle(size: 12, color: ink, weight: .semibold)
        let bStyle = TextStyle(size: 11, color: dim)
        let tr = TextRenderer.shared
        let maxW: CGFloat = 220
        let tm = tr.measure(title, style: tStyle, maxWidth: maxW), bm = tr.measure(body, style: bStyle, maxWidth: maxW)
        let iconPt: CGFloat = 7 * CGFloat(zoom)
        let padPt: CGFloat = 10
        let wPt = padPt * 2 + iconPt + 8 + max(tm.width, bm.width)
        let hPt = max(padPt * 2 + tm.height + bm.height - 2, padPt * 2 + iconPt + 6)
        let z = CGFloat(zoom)
        let aw = Int((wPt / z).rounded(.up)) + 1, ah = Int((hPt / z).rounded(.up)) + 1
        let c = Canvas(width: aw, height: ah)
        let st = Lighting.resolved(map: nil, state: LightState(a: .day))
        let border: String
        switch kind {
        case .approval, .blocked: border = "ui.warn"
        case .question: border = "ui.info"
        case .plan: border = "ui.info"
        case .finished: border = "ui.ok"
        case .error: border = "ui.danger"
        case .info: border = "bubble.line"
        }
        c.plate(IntRect(0, 0, aw, ah), border: Pal.dx("bubble.line"), fill: Pal.dx("bubble.fill"), light: Pal.dx("white.hi"), shade: Pal.dx("bubble.sh"), style: st)
        // 左侧一条彩色边（种类）
        c.fillRect(IntRect(1, 2, 2, ah - 4), value: Pal.dx(border), style: st)
        let iconName: String
        switch kind {
        case .approval: iconName = "icon.key"
        case .question: iconName = "icon.question"
        case .plan: iconName = "icon.board"
        case .finished: iconName = "icon.paper"
        case .blocked: iconName = "icon.note"
        case .error: iconName = "icon.exclaim"
        case .info: iconName = "icon.gear"
        }
        let iy = max(2, (ah - 7) / 2)
        c.blit(BubbleArt.sprite(iconName), x: 4, y: iy, style: st)
        let tx = Double(4 + 7) + 8.0 / Double(zoom) + 1
        var items = [TextItem(title, style: tStyle, x: tx, y: Double(padPt - 3) / Double(zoom), align: .left, maxWidth: maxW)]
        items.append(TextItem(body, style: bStyle, x: tx, y: Double(padPt - 3 + tm.height - 1) / Double(zoom), align: .left, maxWidth: maxW))
        return HoverCard.Card(canvas: c, texts: items, size: IntPoint(aw, ah))
    }
}
