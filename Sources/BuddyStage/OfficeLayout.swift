import Foundation
import PixelKit
import BuddyArt

/// 办公室的尺寸常量（美术像素）。
public enum Metrics {
    public static let cellW = SeatGeometry.cellW, cellH = SeatGeometry.cellH, plateH = SeatGeometry.plateH
    public static var rowH: Int { cellH + plateH }
    public static let wallH = 60
    public static let sideMargin = 16
    public static let bottomMargin = 18
    public static let minDesks = 4
    public static let maxCols = 6
    /// 座位号的上限（0..<64）：办公室按座位号分配桌子，被写坏的持久化座位号不能让它去分配天文数字的数组 / 画布。
    public static let maxSeats = 64
}

/// 办公室布局：由（视口宽度，工位数）纯计算得出；列数带迟滞，避免拖动窗口时来回跳。
public struct OfficeLayout: Equatable {
    public let cols: Int
    public let rows: Int
    public let deskCount: Int
    /// 世界尺寸（美术像素）。世界宽度 = 视口宽度；世界高度 ≥ 视口高度（矮了就把地板向下延伸）。
    public let worldW: Int
    public let worldH: Int
    public let gridX0: Int

    public var contentH: Int { Metrics.wallH + rows * Metrics.rowH + Metrics.bottomMargin }

    public var gridRect: IntRect { IntRect(gridX0, Metrics.wallH, cols * Metrics.cellW, rows * Metrics.rowH) }

    /// 工位格左上角（世界坐标）。
    public func cellOrigin(seat: Int) -> IntPoint {
        IntPoint(gridX0 + (seat % cols) * Metrics.cellW, Metrics.wallH + (seat / cols) * Metrics.rowH)
    }

    /// - Parameters:
    ///   - maxSeat: 当前最大的工位号（没有人时传 -1）。桌子数 = max(4, maxSeat + 2)：永远留一个空位。
    ///   - prevCols: 上一次的列数（做迟滞）：只有宽度超出 ±8 px 才换列数。
    public static func compute(viewportW: Int, viewportH: Int, maxSeat: Int, prevCols: Int? = nil) -> OfficeLayout {
        let desks = max(Metrics.minDesks, min(maxSeat, Metrics.maxSeats - 1) + 2)        // 座位号封顶：被写坏的持久化座位号不能让办公室去分配天文数字的桌子 / 画布
        let usable = Double(viewportW - 2 * Metrics.sideMargin)
        let raw = usable / Double(Metrics.cellW)
        var cols = max(1, min(Metrics.maxCols, Int(raw.rounded(.down))))
        if let p = prevCols, p >= 1, p <= Metrics.maxCols {
            let hyst = 8.0 / Double(Metrics.cellW)
            if cols > p { cols = (raw >= Double(p + 1) + hyst) ? cols : p }        // 想变多：要多出 8 px 才换
            else if cols < p { cols = (raw < Double(p) - hyst) ? cols : p }        // 想变少：要少掉 8 px 才换
        }
        cols = max(1, min(cols, desks))
        let rows = (desks + cols - 1) / cols
        let w = max(viewportW, cols * Metrics.cellW + 2 * 4)
        let contentH = Metrics.wallH + rows * Metrics.rowH + Metrics.bottomMargin
        return OfficeLayout(cols: cols, rows: rows, deskCount: desks, worldW: w, worldH: max(viewportH, contentH),
                            gridX0: (w - cols * Metrics.cellW) / 2)
    }

    /// 实际用的缩放：设置里的倍数（0 = 自动），但不超过「至少放得下一个整工位（一列宽、一行高，含桌牌）」的最大倍数——
    /// 窗口比一个工位还窄 / 还矮时，再大的倍数会把工位切掉一半：桌牌文字被切、悬停卡片也找不到不盖住人的位置（text-audit 量出来的）。
    public static func effectiveZoom(setting: Int, contentW: Double, contentH: Double, maxSeat: Int, allowOne: Bool = false) -> Int {
        let auto = autoZoom(contentW: contentW, contentH: contentH, maxSeat: maxSeat, allowOne: allowOne)
        if setting <= 0 { return auto }
        let oneColumn = Double(Metrics.cellW + 2 * 4)
        let oneRow = Double(Metrics.cellH + Metrics.plateH + 2 * 2)
        let fit = max(allowOne ? 1 : 2, min(Int(contentW / oneColumn), Int(contentH / oneRow)))
        return max(1, min(setting, fit))
    }

    /// 在窗口内容区（点）里自动选缩放：2…5 之间放得下全部工位（再加 1 个空位）的最大倍数；放不下取 2（镜头滚动）。
    /// 1 倍只允许在 Retina 屏上用（保证 1 美术像素至少 2 个设备像素），所以 allowOne 由调用方传 backingScale >= 2。
    public static func autoZoom(contentW: Double, contentH: Double, maxSeat: Int, allowOne: Bool = false) -> Int {
        let lo = allowOne ? 1 : 2
        for z in stride(from: 5, through: lo, by: -1) {
            let l = compute(viewportW: Int(contentW / Double(z)), viewportH: Int(contentH / Double(z)), maxSeat: maxSeat)
            if l.contentH <= Int(contentH / Double(z)) { return z }
        }
        return lo
    }
}
