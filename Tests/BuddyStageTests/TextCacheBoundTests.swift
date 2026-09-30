import Testing
import Foundation
import CoreGraphics
import PixelKit

/// 文字图片缓存（`TextRenderer.shared`）的上限：QA 长跑里，读真实 / replay 数据的几路进程的物理占用在最初十几分钟会涨几 MB 到 20 MB 左右
/// （`footprint` 里涨的全是 `CG Raster Data`）——那是这个缓存被越来越多的「不同的文字」（标题、文件名、计时器）慢慢填满。
/// 它必须有上限、不会一直涨：这里钉住「最多 600 张、先进先出」，并把装满时的最坏字节数量出来。
@Suite struct TextCacheBoundTests {
    @Test("文字图片缓存有上限（600 张，先进先出）：不停地渲染新的文字，最早的被淘汰、最近的还在缓存里；装满时按桌牌大小的文字算总共约 20 MB")
    func theTextImageCacheIsBoundedAndItsFullSizeIsSmall() {
        let r = TextRenderer.shared
        let style = TextStyle(size: 11, color: RGBA8(30, 20, 20, 255), weight: .regular)
        var first: CGImage?, last: CGImage?
        var bytes = 0
        let n = 1500
        for i in 0..<n {
            let t = "重构登录模块 \(i) · 用时 \(i % 60) 秒 Auth\(i)"                 // 每一条都不一样：计时器、文件名、标题都会这样不断出新
            guard let img = r.image(t, style: style, scale: 2, maxWidth: 130) else { Issue.record("渲染失败：\(t)"); return }
            if i == 0 { first = img.image }
            if i == n - 1 { last = img.image }
            if i >= n - 600 { bytes += img.image.bytesPerRow * img.image.height }   // 最近 600 张 = 装满时缓存里的那一批
        }
        // 最近的一张还在缓存里（再取一次拿到的是同一张图）；最早的那张早被淘汰了（再取是新画的一张）
        let lastAgain = r.image("重构登录模块 \(n - 1) · 用时 \((n - 1) % 60) 秒 Auth\(n - 1)", style: style, scale: 2, maxWidth: 130)?.image
        let firstAgain = r.image("重构登录模块 0 · 用时 0 秒 Auth0", style: style, scale: 2, maxWidth: 130)?.image
        #expect(lastAgain != nil && last != nil && lastAgain! === last!, "最近渲染的一张应该还在缓存里")
        #expect(firstAgain != nil && first != nil && firstAgain! !== first!, "渲染了 \(n) 种不同的文字之后，最早的一张应该已经被淘汰（缓存有上限）")
        #expect(bytes < 30_000_000, "装满 600 张桌牌大小的文字图片共 \(bytes / 1_000_000) MB（实测约 20 MB；应 < 30 MB）")
    }
}
