import Foundation
import BuddyCore
import PixelKit
import BuddyArt

/// 持有全部 Performer：新来的建一个、走了的收掉；多个 buddy 同时变化时按顺序错开（每个晚 90 ms，最多错开 0.6 秒）。
public final class VisualDirector {
    public private(set) var performers: [String: Performer] = [:]
    var applied: [String: BuddySnapshot] = [:]
    var pending: [String: (snap: BuddySnapshot, at: Double)] = [:]
    var appearances: [String: Appearance] = [:]

    public init() {}

    /// 有没有谁的运动需要 30 fps（见 Performer.needsFullRate）。
    public func needsFullRate(time: Double) -> Bool {
        for p in performers.values where p.needsFullRate(time: time) { return true }
        return false
    }

    /// 两个活动是不是「同一种」：工具按（类别, 名字）比，等批准 / 其他等待 / 重试不看参数，其余整个相等。
    /// （原来是拼字符串再比，每帧每人两次，冷启动时很贵。）
    static func sameKind(_ a: Activity, _ b: Activity) -> Bool {
        switch (a, b) {
        case (.tool(let x, _), .tool(let y, _)): return x.category == y.category && x.name == y.name
        case (.waitingApproval, .waitingApproval), (.waitingOther, .waitingOther), (.retrying, .retrying): return true
        case (.tool, _), (_, .tool), (.waitingApproval, _), (_, .waitingApproval), (.waitingOther, _), (_, .waitingOther), (.retrying, _), (_, .retrying): return false
        default: return a == b
        }
    }

    /// 「换个造型」正在等新盐：key → 点的那一刻快照里的旧盐。
    /// 数据层（异步）把盐 +1 并持久化，下一个快照带着新盐来了才换：坐着的人、走进 / 走出的人、衣帽架上的外套、重启之后（读到的还是这个盐）用的是同一个外观。
    var rerolling: [String: UInt64] = [:]

    /// 给每个在场的人抽外观：同时在场的不撞衫（发型+发色 或 衣服+颜色 至少一组不同）。
    /// 只和「现在在场的其他人」比：离场的人不占名额（否则见过的会话越多，新来的人越容易撞衫）。
    public func appearance(for s: BuddySnapshot) -> Appearance {
        if let a = appearances[s.key] { return a }
        let existing = performers.values.filter { $0.key != s.key }.map { $0.appearance }
        let r = Appearance.resolve(salt: s.salt, existing: existing) { salt in AppearanceSeed.seed(key: s.key, salt: salt) }
        appearances[s.key] = r.appearance
        // 缓存有界：见过的会话越来越多时只留在场的（下班工位的外套下一帧会重新算，最多几个）
        if appearances.count > 96 { appearances = appearances.filter { performers[$0.key] != nil } }
        return r.appearance
    }
    /// 用户点了「换个造型」（AppModel 同时通知数据层把盐 +1）：先不动——等快照里的盐变了再换成按新盐算出来的外观（原来是立刻换一个和盐无关的随机造型，重启后就变回另一个了）。
    public func reroll(key: String) {
        if let salt = performers[key]?.snapshot.salt { rerolling[key] = salt } else { appearances[key] = nil }
    }

    /// 每帧调用。snapshots 只含「在场」的（presence == .present）。
    public func update(snapshots: [BuddySnapshot], now: Date, time: Double, privacy: Bool) {
        let pt0 = Prof.begin()
        defer { Prof.end("director.total", pt0) }
        // 「换个造型」：新盐到了就换（离场的不再等）
        for (k, old) in Array(rerolling) {
            guard let s = snapshots.first(where: { $0.key == k }) else { rerolling.removeValue(forKey: k); continue }
            if s.salt != old {
                rerolling.removeValue(forKey: k)
                appearances[k] = nil
                performers[k]?.setAppearance(appearance(for: s))
            }
        }
        // 人员没变（绝大多数帧）就不用重建集合
        if performers.count != snapshots.count || snapshots.contains(where: { performers[$0.key] == nil }) {
            let keys = Set(snapshots.map { $0.key })
            for k in performers.keys where !keys.contains(k) { performers.removeValue(forKey: k); applied.removeValue(forKey: k); pending.removeValue(forKey: k) }
        }
        var order = 0
        var sortedAlready = true
        for i in 1..<max(1, snapshots.count) where snapshots[i - 1].seat > snapshots[i].seat { sortedAlready = false; break }
        for s in (sortedAlready ? snapshots : snapshots.sorted(by: { $0.seat < $1.seat })) {
            var effective = s
            if let p = performers[s.key] {
                let old = applied[s.key] ?? s
                let changed = !Self.sameKind(old.activity, s.activity)
                if changed && !s.activity.needsUser {
                    // 同帧多个变化：错开
                    if pending[s.key] == nil { pending[s.key] = (s, time + min(0.6, 0.09 * Double(order))); order += 1 }
                    else { pending[s.key]!.snap = s }
                }
                // 推迟记录里存的是推迟开始时的快照；只要现在的快照已经不需要它了就作废，不然到点那一帧会把过期的快照套给表演者：
                // ① 等待类（等批准 / 提问 / 计划待审）不错开，立刻套用最新快照（任务书 5.6：最多 250 ms；SP-06）；
                // ② 推迟期间活动又变回已套用的同一种类（Read → Edit → Read）：没有什么要换了（R1b-01）
                if s.activity.needsUser || !changed { pending.removeValue(forKey: s.key) }
                if let pd = pending[s.key] {
                    if time >= pd.at { effective = pd.snap; applied[s.key] = pd.snap; pending.removeValue(forKey: s.key) }
                    else { var e = old; e.title = s.title; e.tokens = s.tokens; e.helpers = s.helpers; e.unread = s.unread; e.blocked = s.blocked; effective = e }
                } else { applied[s.key] = s }
                let pu = Prof.begin()
                p.update(snapshot: effective, now: now, time: time, privacy: privacy)
                Prof.end("perf.update", pu)
            } else {
                let ap = appearance(for: s)
                let p = Performer(key: s.key, snapshot: s, appearance: ap, time: time)
                performers[s.key] = p
                applied[s.key] = s
                p.update(snapshot: s, now: now, time: time, privacy: privacy)
            }
        }
    }
}
