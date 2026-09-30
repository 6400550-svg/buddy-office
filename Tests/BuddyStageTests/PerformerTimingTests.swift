import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// 表现层节奏（任务书 5.6）：三个通道的最短停留、等待类的确认 / 保持时间、同帧多个变化的错开、工位编号稳定。
/// 全部用假时钟（自己给 time / now），不依赖真实时间。
@Suite struct PerformerTimingTests {
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func snap(_ activity: Activity, key: String = "d:a", seat: Int = 0, since: Double = 0, turnStart: Double? = 0) -> BuddySnapshot {
        var s = BuddySnapshot(key: key, seat: seat, salt: 0, title: "会话 \(key)", sessionId: key, origin: .desktop, now: base)
        s.activity = activity; s.phase = activity.phase
        s.activitySince = base.addingTimeInterval(since)
        if let t = turnStart, activity.phase != .idle { s.turnStartedAt = base.addingTimeInterval(t) }
        s.hookActive = true
        return s
    }
    static func tool(_ name: String, _ detail: String, at: Double) -> Activity {
        .tool(ToolCatalog.makeCall(name: name, detail: detail, at: base.addingTimeInterval(at)), parallel: 1)
    }

    /// 以 30 fps 推进 director，返回每一帧调用 body（time, performer）。
    static func run(_ director: VisualDirector, from: Double, to: Double, snapshots: (Double) -> [BuddySnapshot], _ body: (Double, VisualDirector) -> Void) {
        var t = from
        while t <= to + 1e-9 {
            director.update(snapshots: snapshots(t), now: base.addingTimeInterval(t), time: t, privacy: false)
            body(t, director)
            t += 1.0 / 30
        }
    }

    /// 一个量每次变化的时刻。
    static func changeTimes<T: Equatable>(_ series: [(Double, T)]) -> [Double] {
        var out: [Double] = []
        for i in 1..<series.count where series[i].1 != series[i - 1].1 { out.append(series[i].0) }
        return out
    }

    // MARK: 最短停留
    @Test func poseNeverChangesFasterThanEvery1_5Seconds() {
        let d = VisualDirector()
        var series: [(Double, PoseKind)] = []
        // 每 0.4 秒在「读文件（握鼠标）」和「改代码（打字）」之间来回切
        Self.run(d, from: 0, to: 14, snapshots: { t in
            let n = Int(t / 0.4)
            let a = n % 2 == 0 ? Self.tool("Read", "/a.swift", at: Double(n) * 0.4) : Self.tool("Edit", "/b.swift", at: Double(n) * 0.4)
            return [Self.snap(a, since: Double(n) * 0.4)]
        }) { t, dir in if let p = dir.performers["d:a"] { series.append((t, p.pose)) } }
        let times = Self.changeTimes(series)
        #expect(times.count >= 3, "姿势应该变过几次")
        for i in 1..<times.count { #expect(times[i] - times[i - 1] >= 1.5 - 1.0 / 30 - 1e-9, "姿势 \(times[i - 1]) → \(times[i]) 只隔了 \(times[i] - times[i - 1]) 秒") }
    }

    @Test func screenNeverChangesFasterThanEvery0_8Seconds() {
        let d = VisualDirector()
        var series: [(Double, ScreenKind)] = []
        Self.run(d, from: 0, to: 10, snapshots: { t in
            let n = Int(t / 0.2)
            let a = n % 2 == 0 ? Self.tool("Grep", "TODO", at: Double(n) * 0.2) : Self.tool("WebFetch", "https://a.com", at: Double(n) * 0.2)
            return [Self.snap(a, since: Double(n) * 0.2)]
        }) { t, dir in if let p = dir.performers["d:a"] { series.append((t, p.screen)) } }
        let times = Self.changeTimes(series)
        #expect(times.count >= 3)
        for i in 1..<times.count { #expect(times[i] - times[i - 1] >= 0.8 - 1.0 / 30 - 1e-9, "屏幕 \(times[i - 1]) → \(times[i])") }
    }

    @Test func plateActionTextNeverChangesFasterThanEverySecond() {
        let d = VisualDirector()
        var series: [(Double, String)] = []
        Self.run(d, from: 0, to: 10, snapshots: { t in
            let n = Int(t / 0.3)
            let a = n % 2 == 0 ? Self.tool("Read", "/a.swift", at: Double(n) * 0.3) : Self.tool("Edit", "/b.swift", at: Double(n) * 0.3)
            return [Self.snap(a, since: Double(n) * 0.3)]
        }) { t, dir in if let p = dir.performers["d:a"] { series.append((t, p.plate)) } }
        let times = Self.changeTimes(series)
        #expect(times.count >= 3)
        for i in 1..<times.count { #expect(times[i] - times[i - 1] >= 1.0 - 1.0 / 30 - 1e-9, "桌牌 \(times[i - 1]) → \(times[i])") }
    }

    // MARK: 等待类：0.4 s 才转身；结束后再保持 1.5 s 才转回去
    @Test func waitingTurnsAroundAfter0_4SecondsAndTurnsBackAfter1_5() {
        let d = VisualDirector()
        var facing: [(Double, Bool)] = []
        let waitFrom = 2.0, waitTo = 6.0
        Self.run(d, from: 0, to: 10, snapshots: { t in
            if t >= waitFrom && t < waitTo { return [Self.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: Self.base.addingTimeInterval(waitFrom))), since: waitFrom)] }
            return [Self.snap(t < waitFrom ? Self.tool("Read", "/a", at: 0) : .thinking, since: t < waitFrom ? 0 : waitTo)]
        }) { t, dir in if let p = dir.performers["d:a"] { facing.append((t, p.facingUser)) } }
        func at(_ t: Double) -> Bool { facing.min(by: { abs($0.0 - t) < abs($1.0 - t) })!.1 }
        #expect(!at(waitFrom + 0.36), "等了 0.36 秒还不该转身")
        #expect(at(waitFrom + 0.44), "等了 0.44 秒应该已经在转了")
        #expect(at(waitTo + 1.4), "等待结束后 1.4 秒还应该面向你（连着批准几次不会来回转）")
        #expect(!at(waitTo + 1.6), "等待结束后 1.6 秒应该转回去了")
    }

    @Test func aWaitingBlipShorterThan0_4SecondsDoesNotTurnTheBuddy() {
        let d = VisualDirector()
        var everFacing = false
        Self.run(d, from: 0, to: 5, snapshots: { t in
            if t >= 2 && t < 2.3 { return [Self.snap(.waitingApproval(tool: nil), since: 2)] }
            return [Self.snap(.thinking, since: 0)]
        }) { _, dir in if dir.performers["d:a"]?.facingUser == true { everFacing = true } }
        #expect(!everFacing)
    }

    // MARK: 错开：同一帧里多个人变化，每个晚 90 ms，最多错开 0.6 s
    @Test func simultaneousChangesAreStaggeredBy90msEach() {
        let d = VisualDirector()
        let n = 5
        var appliedAt = [Double?](repeating: nil, count: n)
        Self.run(d, from: 0, to: 4, snapshots: { t in
            (0..<n).map { i in
                t < 2 ? Self.snap(Self.tool("Read", "/a", at: 0), key: "d:\(i)", seat: i, since: 0)
                      : Self.snap(Self.tool("Edit", "/b", at: 2), key: "d:\(i)", seat: i, since: 2)
            }
        }) { t, dir in
            for i in 0..<n where appliedAt[i] == nil && t >= 2 {
                if case .tool(let c, _) = dir.performers["d:\(i)"]!.snapshot.activity, c.name == "Edit" { appliedAt[i] = t }
            }
        }
        let ts = appliedAt.compactMap { $0 }
        #expect(ts.count == n)
        for i in 1..<ts.count {
            #expect(ts[i] > ts[i - 1], "第 \(i) 个人应该比前一个晚")
            #expect(abs((ts[i] - ts[i - 1]) - 0.09) < 0.04, "间隔 \(ts[i] - ts[i - 1]) 应该约 0.09 秒")
        }
        #expect(ts.last! - ts.first! <= 0.6 + 1.0 / 30)
    }

    // MARK: 工位编号稳定
    @Test func seatsStayPutWhenTheSnapshotOrderChanges() {
        let d = VisualDirector()
        let scene = OfficeScene(); scene.director = d
        var opts = SceneOptions(); opts.directorIsExternal = true; opts.animateWalkers = false
        let snaps = (0..<4).map { Self.snap(Self.tool("Read", "/a", at: 0), key: "d:\($0)", seat: $0, since: 0) }
        func views(_ order: [BuddySnapshot]) -> [(Int, Appearance, SeatView.Mode)] {
            d.update(snapshots: order, now: Self.base, time: 5, privacy: false)
            _ = scene.render(viewportW: 224, viewportH: 226, present: order, dormant: [], now: Self.base, time: 5, options: opts)
            return scene.lastSeatViews.map { ($0.seat, $0.appearance, $0.mode) }
        }
        let a = views(snaps)
        let b = views(snaps.reversed())
        #expect(a.count == b.count)
        for i in 0..<a.count { #expect(a[i].0 == b[i].0 && a[i].1 == b[i].1 && a[i].2 == b[i].2, "工位 \(i) 换了顺序之后变了") }
        // 桌子数 = max(4, 最大工位号 + 2)：永远留一个空位
        #expect(scene.layout.deskCount == max(4, 3 + 2))
    }

    // MARK: 不撞衫
    @Test func simultaneousBuddiesDoNotWearTheSameOutfit() {
        let d = VisualDirector()
        let snaps = (0..<8).map { Self.snap(.idle, key: "d:local_\($0)", seat: $0, since: 0, turnStart: nil) }
        d.update(snapshots: snaps, now: Self.base, time: 0, privacy: false)
        let aps = snaps.map { d.appearance(for: $0) }
        for i in 0..<aps.count { for j in (i + 1)..<aps.count { #expect(!aps[i].collides(with: aps[j]), "\(i) 和 \(j) 撞衫了") } }
    }
}
