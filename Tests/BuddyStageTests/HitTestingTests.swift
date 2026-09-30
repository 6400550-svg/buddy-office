import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 命中缓冲（画布的对象 ID 平面）：点击一个 buddy 只会命中他自己的座位，绝不会跳到别人的会话。
/// 应用层的跳转是「命中 ID → 座位 → 座位上的会话」（见 BuddyOfficeTests 里的 JumpTarget 测试），这一半保证「屏幕上点到哪个像素 → 哪个座位」是对的。
@Suite struct HitTestingTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func hitIdsRoundTripAndAreClampedForCrazySeatNumbers() {
        for seat in [0, 1, 7, 63, 998] {
            #expect(OfficeScene.seat(fromHitID: OfficeScene.hitID(seat: seat)) == seat)
        }
        #expect(OfficeScene.seat(fromHitID: 0) == nil, "ID 0 = 没点到任何东西")
        #expect(OfficeScene.seat(fromHitID: 999) == nil, "1000 以下不是座位")
        for crazy in [1_000, 64_535, 64_536, 1_000_000, Int.max] { _ = OfficeScene.hitID(seat: crazy) }     // 座位号再离谱也不崩（UInt16 溢出会 trap）
    }

    /// 每一个带座位 ID 的像素，都落在那个座位自己的格子（含人物 / 椅子伸出格子的那一圈）里。
    @Test(arguments: [1, 4, 6, 12, 20], [168, 224, 336, 448])
    func everyPixelOfASeatsIdLiesInsideThatSeatsOwnCell(count: Int, viewportW: Int) {
        let snaps = AuditFixtures.snapshots(count: count, titles: .normal, states: .all, base: Self.base)
        let director = VisualDirector()
        TextAuditRunner.settle(director, snaps, base: Self.base)
        let scene = OfficeScene(); scene.director = director
        var o = SceneOptions(); o.zoom = 2; o.directorIsExternal = true; o.animateWalkers = false; o.retained = false
        let f = scene.render(viewportW: viewportW, viewportH: 4000, present: snaps, dormant: [], now: Self.base.addingTimeInterval(6), time: 6, options: o)
        let c = f.canvas, lay = scene.layout
        var stray = 0, hitSeats = Set<Int>(), firstStray: String? = nil
        for y in 0..<c.height { for x in 0..<c.width {
            let id = c.ids[y * c.width + x]
            guard let seat = OfficeScene.seat(fromHitID: id) else { continue }
            hitSeats.insert(seat)
            let org = lay.cellOrigin(seat: seat)
            if !SeatRenderer.seatRegion(IntPoint(org.x, org.y)).contains(x, y) { stray += 1; if firstStray == nil { firstStray = "像素 (\(x),\(y)) 的 ID 是座位 \(seat)，格子在 (\(org.x),\(org.y))" } }
        } }
        #expect(stray == 0, "\(count) 个人 / 视口 \(viewportW)：\(stray) 个像素的座位 ID 落在别人的格子里：\(firstStray ?? "")")
        for s in snaps { #expect(hitSeats.contains(s.seat), "座位 \(s.seat) 上的人点不到（画布上没有他的 ID）") }
        #expect(hitSeats.count == count, "画布上出现了 \(hitSeats.count) 个座位的 ID，应该正好是 \(count) 个人的")
    }

    /// 没有人的座位（空位 / 下班工位）不带 ID：点一张空桌子不会跳去任何会话。
    @Test func emptyAndOffDutySeatsAreNotClickable() {
        let snaps = Array(AuditFixtures.snapshots(count: 6, titles: .normal, states: .demo, base: Self.base).prefix(3))
        let dormant = Array(AuditFixtures.snapshots(count: 6, titles: .normal, states: .demo, base: Self.base).suffix(2)).enumerated().map { (i, s) -> BuddySnapshot in
            var d = s; d.seat = 3 + i; d.key += "-off"; d.presence = .away(since: Self.base, dormant: true); return d
        }
        let director = VisualDirector()
        TextAuditRunner.settle(director, snaps, base: Self.base)
        let scene = OfficeScene(); scene.director = director
        var o = SceneOptions(); o.zoom = 2; o.directorIsExternal = true; o.animateWalkers = false; o.retained = false
        let f = scene.render(viewportW: 336, viewportH: 600, present: snaps, dormant: dormant, now: Self.base.addingTimeInterval(6), time: 6, options: o)
        var seats = Set<Int>()
        for i in 0..<(f.canvas.width * f.canvas.height) { if let s = OfficeScene.seat(fromHitID: f.canvas.ids[i]) { seats.insert(s) } }
        #expect(seats == Set(snaps.map(\.seat)), "只有在场的人可点：\(seats.sorted())")
    }
}
