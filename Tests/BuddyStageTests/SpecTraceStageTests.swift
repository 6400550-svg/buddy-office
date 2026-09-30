import Testing
import Foundation
import BuddyCore
import PixelKit
import BuddyArt
@testable import BuddyStage

/// QA 定稿（规格追踪：任务书 5.5 / 5.6 里表现层的条目，加上 4.4 的「status_detail 只在悬停卡片里显示」）：
/// `QA/spec-trace-core-final.md` 里原来「没有专门测试」的条目在这里逐条补上断言。已经有测试钉住的不重复。
/// 全部用假时钟（自己给 time / now），不依赖真实时间。
@Suite struct SpecTraceStageTests {
    typealias T = PerformerTimingTests
    static let base = T.base
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func tool(_ name: String, _ detail: String = "") -> Activity {
        .tool(ToolCatalog.makeCall(name: name, detail: detail, at: Self.base), parallel: 1)
    }
    /// 只有活动、没有别的信息的表演者（activitySince = base）。
    private func performer(_ activity: Activity) -> Performer {
        let s = T.snap(activity, since: 0)
        return Performer(key: s.key, snapshot: s, appearance: Appearance.generate(seed: 3), time: 0)
    }
    private func pose(_ activity: Activity, elapsed: Double) -> PoseKind {
        performer(activity).targetPose(now: Self.base.addingTimeInterval(elapsed), time: elapsed)
    }

    // MARK: - 5.6 表现层节奏

    @Test("5.6-06/07/08 最短停留正好是 姿势 1.5 s / 屏幕 0.8 s / 桌牌动作文字 1.0 s：目标一变、停留一满就换，不早也不晚（差不超过一帧）")
    func dwellTimesAreExactlyOneAndAHalfPointEightAndOneSecond() {
        let d = VisualDirector()
        var poseAt: Double?, screenAt: Double?, plateAt: Double?
        // 第 0 秒起读文件（第一帧直接采用）；0.25 秒起改文件：三个通道各自在停留满之后才换
        T.run(d, from: 0, to: 3, snapshots: { t in
            t < 0.25 ? [T.snap(T.tool("Read", "/a/app.swift", at: 0), since: 0)] : [T.snap(T.tool("Edit", "/a/b.swift", at: 0.25), since: 0.25)]
        }) { t, dir in
            guard let p = dir.performers["d:a"] else { return }
            if poseAt == nil, p.pose == .typing { poseAt = t }
            if screenAt == nil, p.screen == .diffEdit { screenAt = t }
            if plateAt == nil, p.plate.contains("b.swift") { plateAt = t }
        }
        let frame = 1.0 / 30
        for (name, at, dwell) in [("姿势", poseAt, 1.5), ("屏幕", screenAt, 0.8), ("桌牌", plateAt, 1.0)] {
            guard let at else { Issue.record("\(name)一直没换"); continue }
            #expect(at >= dwell - 1e-6 && at <= dwell + frame + 1e-6, "\(name)在 \(at) 秒换，应为 \(dwell) 秒")
        }
    }

    @Test("5.6-05 连着批准好几次：两次等待之间只隔 0.6 秒，不来回转（一直面向你，只转一次身），最后一次结束 1.5 秒之后才转回去")
    func approvingSeveralTimesInARowNeverTurnsTheBuddyBackAndForth() {
        let d = VisualDirector()
        let waits: [(from: Double, to: Double)] = [(2, 3), (3.6, 4.6), (5.2, 6)]
        var samples: [(t: Double, waiting: Bool, facing: Bool, start: Double?)] = []
        T.run(d, from: 0, to: 12, snapshots: { t in
            if let w = waits.first(where: { t >= $0.from && t < $0.to }) {
                return [T.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: Self.base.addingTimeInterval(w.from))), since: w.from)]
            }
            return [T.snap(T.tool("Bash", "git push", at: 0), since: 0)]                      // 批准之后接着干活
        }) { t, dir in
            guard let p = dir.performers["d:a"] else { return }
            var waiting = false
            if case .waitingApproval = p.snapshot.activity { waiting = true }
            samples.append((t, waiting, p.facingUser, p.faceStart))
        }
        let frame = 1.0 / 30
        // 以表演者实际收到的状态为准量时间（帧时间是累加出来的，名义上的 2.0 / 6.0 秒可能差一帧的浮点误差）
        guard let firstWait = samples.first(where: { $0.waiting })?.t, let lastWait = samples.last(where: { $0.waiting })?.t else { Issue.record("没有收到等待状态"); return }
        let firstFace = samples.first { $0.facing }?.t ?? -1
        #expect(firstFace - firstWait >= 0.4 - 1e-6 && firstFace - firstWait <= 0.4 + frame + 1e-6, "等待持续 0.4 秒才转身：\(firstFace - firstWait)")
        for s in samples where s.t >= firstFace && s.t <= lastWait + 1.4 { #expect(s.facing, "t=\(s.t) 不该转回去（连着批准）") }
        #expect(Set(samples.compactMap { $0.start }).count == 1, "转身只开始过一次")
        let ended = lastWait + frame                                                          // 最后一次等待结束的那一帧
        let back = samples.first { $0.t > lastWait && !$0.facing }?.t ?? -1
        #expect(back - ended >= 1.5 - 1e-6 && back - ended <= 1.5 + frame + 1e-6, "最后一次等待结束 1.5 秒之后才转回去：\(back - ended)")
    }

    @Test("5.6-09 停留期间只记下最新的目标、跳过中间态：Read → Grep → Read 一直是「在读」；Read → Grep → Edit 直接到 Edit，屏幕 / 姿势 / 桌牌都没显示过 Grep")
    func intermediateStatesInsideTheDwellAreSkipped() {
        func run(_ activityAt: @escaping (Double) -> (Activity, Double)) -> (poses: [PoseKind], screens: [ScreenKind], plates: [String]) {
            let d = VisualDirector()
            var poses: [PoseKind] = [], screens: [ScreenKind] = [], plates: [String] = []
            T.run(d, from: 0, to: 3, snapshots: { t in let (a, since) = activityAt(t); return [T.snap(a, since: since)] }) { _, dir in
                guard let p = dir.performers["d:a"] else { return }
                if poses.last != p.pose { poses.append(p.pose) }
                if screens.last != p.screen { screens.append(p.screen) }
                if plates.last != p.plate { plates.append(p.plate) }
            }
            return (poses, screens, plates)
        }
        // A：0.3 秒换成 Grep、0.6 秒又换回 Read，都在停留期里
        let a = run { t in
            (t >= 0.3 && t < 0.6) ? (T.tool("Grep", "TODO", at: 0.3), 0.3) : (T.tool("Read", "/a/app.swift", at: 0), 0)
        }
        #expect(a.poses == [.mouse] && a.screens == [.doc("swift")] && a.plates.count == 1 && a.plates[0].contains("app.swift"),
                "Read → Grep → Read 应该一直是在读：\(a)")
        // B：0.3 秒 Grep、0.6 秒 Edit（最新的目标）
        let b = run { t in
            t < 0.3 ? (T.tool("Read", "/a/app.swift", at: 0), 0) : (t < 0.6 ? (T.tool("Grep", "TODO", at: 0.3), 0.3) : (T.tool("Edit", "/a/b.swift", at: 0.6), 0.6))
        }
        #expect(b.poses == [.mouse, .typing], "姿势跳过了 Grep 的「searching」：\(b.poses)")
        #expect(b.screens == [.doc("swift"), .diffEdit], "屏幕跳过了 Grep 的结果列表：\(b.screens)")
        #expect(b.plates.count == 2 && b.plates[1].contains("b.swift"), "桌牌跳过了「在找」：\(b.plates)")
    }

    @Test("5.6-10 同一类工具之间切换：姿势不变，只换屏幕内容（Grep → Glob：结果列表 → 文件树；Read swift → Read md：文档颜色；Edit → MultiEdit：什么都不变）")
    func sameCategoryToolsOnlySwapTheScreen() {
        func run(_ a: Activity, _ b: Activity) -> (poses: [PoseKind], screens: [ScreenKind]) {
            let d = VisualDirector()
            var poses: [PoseKind] = [], screens: [ScreenKind] = []
            T.run(d, from: 0, to: 4, snapshots: { t in t < 2 ? [T.snap(a, since: 0)] : [T.snap(b, since: 2)] }) { _, dir in
                guard let p = dir.performers["d:a"] else { return }
                if poses.last != p.pose { poses.append(p.pose) }
                if screens.last != p.screen { screens.append(p.screen) }
            }
            return (poses, screens)
        }
        let grepGlob = run(T.tool("Grep", "TODO", at: 0), T.tool("Glob", "**/*.swift", at: 2))
        #expect(grepGlob.poses == [.searching] && grepGlob.screens == [.results, .tree], "\(grepGlob)")
        let readRead = run(T.tool("Read", "/a/app.swift", at: 0), T.tool("Read", "/a/notes.md", at: 2))
        #expect(readRead.poses == [.mouse] && readRead.screens == [.doc("swift"), .doc("md")], "\(readRead)")
        let editMulti = run(T.tool("Edit", "/a/a.swift", at: 0), T.tool("MultiEdit", "/a/b.swift", at: 2))
        #expect(editMulti.poses == [.typing] && editMulti.screens == [.diffEdit], "\(editMulti)")
        // 不同类之间：姿势和屏幕都换（对照）
        let readEdit = run(T.tool("Read", "/a/app.swift", at: 0), T.tool("Edit", "/a/b.swift", at: 2))
        #expect(readEdit.poses == [.mouse, .typing] && readEdit.screens == [.doc("swift"), .diffEdit], "\(readEdit)")
    }

    @Test("5.6-13 等待类状态到来时立即插入：屏幕、桌牌、气泡在同一帧就换成等待内容（不等最短停留），身体 0.4 秒后转身")
    func waitingContentIsInsertedImmediatelyEvenInsideTheDwell() {
        let d = VisualDirector()
        var frames: [(t: Double, waiting: Bool, screen: ScreenKind, plate: String, bubble: BubbleKind?, facing: Bool)] = []
        T.run(d, from: 0, to: 2, snapshots: { t in
            if t < 0.3 { return [T.snap(T.tool("Read", "/a/app.swift", at: 0), since: 0)] }
            if t < 0.5 { return [T.snap(T.tool("Grep", "TODO", at: 0.3), since: 0.3)] }              // 屏幕 / 桌牌的停留期还没满
            return [T.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: Self.base.addingTimeInterval(0.5))), since: 0.5)]
        }) { t, dir in
            guard let p = dir.performers["d:a"] else { return }
            var waiting = false
            if case .waitingApproval = p.snapshot.activity { waiting = true }
            frames.append((t, waiting, p.screen, p.plate, p.bubble, p.facingUser))
        }
        guard let first = frames.first(where: { $0.waiting }) else { Issue.record("Performer 一直没收到等待状态"); return }
        #expect(abs(first.t - 0.5) <= 1.0 / 30 + 1e-6, "等待状态在 0.5 秒到来，同一帧就要交给表演者：\(first.t)")
        #expect(first.screen == .permission, "等待开始的那一帧屏幕就该是权限对话框：\(first.screen)")
        #expect(first.plate.contains("等你批准"), "桌牌：\(first.plate)")
        if case .approval? = first.bubble {} else { Issue.record("气泡应该是钥匙 + 工具图标：\(String(describing: first.bubble))") }
        #expect(!first.facing, "身体还没转（要持续 0.4 秒才转）")
        let turned = frames.first { $0.facing }?.t ?? -1
        #expect(turned - first.t >= 0.4 - 1e-6 && turned - first.t <= 0.4 + 1.0 / 30 + 1e-6, "0.4 秒后转身：\(turned - first.t)")
    }

    @Test("5.6-13 （SP-06）某个 buddy 正在「错开」的等待期里，等待类状态也要立即插入（≤ 250 ms），并且中间不能闪出一帧过期的旧动作")
    func aWaitingStateArrivingDuringAStaggerDelayIsInsertedImmediately() {
        let d = VisualDirector()
        let n = 10, last = n - 1
        var waitingAt: Double?, staleFrames = 0
        T.run(d, from: 0, to: 4, snapshots: { t in
            (0..<n).map { i in
                if i == last, t >= 2.1 {
                    return T.snap(.waitingApproval(tool: ToolCatalog.makeCall(name: "Bash", detail: "git push", at: Self.base.addingTimeInterval(2.1))), key: "d:\(i)", seat: i, since: 2.1)
                }
                return t < 2 ? T.snap(T.tool("Read", "/a", at: 0), key: "d:\(i)", seat: i, since: 0)
                             : T.snap(T.tool("Edit", "/b", at: 2), key: "d:\(i)", seat: i, since: 2)
            }
        }) { t, dir in
            guard t >= 2.1, let p = dir.performers["d:\(last)"] else { return }
            if case .waitingApproval = p.snapshot.activity { if waitingAt == nil { waitingAt = t } }
            else if case .tool(let c, _) = p.snapshot.activity, c.name == "Edit", waitingAt == nil { staleFrames += 1 }
        }
        // 第 10 个人的变化被错开到 2.0 + 0.6 秒才应用；等待类在 2.1 秒到来，本该立即插入
        #expect((waitingAt ?? 99) - 2.1 <= 0.25 + 1.0 / 30, "等待类晚了 \((waitingAt ?? 99) - 2.1) 秒才显示")
        #expect(staleFrames == 0, "等待期间有 \(staleFrames) 帧显示的是过期的旧动作")
    }

    @Test("5.6-23 错开最多 0.6 秒：10 个人同一帧变化，第 1…7 个依次晚 90 ms，第 8、9、10 个都是 0.6 秒（封顶）")
    func staggerIsCappedAtSixTenthsOfASecond() {
        let d = VisualDirector()
        let n = 10
        var appliedAt = [Double?](repeating: nil, count: n)
        T.run(d, from: 0, to: 4, snapshots: { t in
            (0..<n).map { i in
                t < 2 ? T.snap(T.tool("Read", "/a", at: 0), key: "d:\(i)", seat: i, since: 0) : T.snap(T.tool("Edit", "/b", at: 2), key: "d:\(i)", seat: i, since: 2)
            }
        }) { t, dir in
            for i in 0..<n where appliedAt[i] == nil && t >= 2 {
                if case .tool(let c, _) = dir.performers["d:\(i)"]!.snapshot.activity, c.name == "Edit" { appliedAt[i] = t }
            }
        }
        let ts = appliedAt.compactMap { $0 }
        #expect(ts.count == n)
        guard ts.count == n else { return }
        let frame = 1.0 / 30
        for i in 0..<n {
            let want = min(0.6, 0.09 * Double(i))
            #expect(abs((ts[i] - ts[0]) - want) <= frame + 1e-6, "第 \(i + 1) 个人晚了 \(ts[i] - ts[0]) 秒，应为 \(want)")
        }
        #expect(ts.max()! - ts.min()! <= 0.6 + frame + 1e-6)
    }

    @Test("5.6-14/15/16/17 长时间状态：Bash / WebFetch / WebSearch 超过 8 秒、Monitor、思考超过 20 秒都换成对应的姿势（边界两侧各测一次）")
    func longRunningStatesSwitchPoseAtTheirThresholds() {
        for (name, detail) in [("Bash", "npm test"), ("WebFetch", "https://github.com/x"), ("WebSearch", "hydrogen")] {
            #expect(pose(tool(name, detail), elapsed: 7.9) != .leanBack, "\(name) 7.9 秒还不该往后靠")
            #expect(pose(tool(name, detail), elapsed: 8.1) == .leanBack, "\(name) 超过 8 秒应该往后靠着盯屏幕")
        }
        #expect(pose(tool("Bash", "npm test"), elapsed: 3.5) == .restAtDesk)
        // Bash 超过 8 秒屏幕也换成「终端 + 进度条」
        #expect(performer(tool("Bash", "npm test")).targetScreen(now: Self.base.addingTimeInterval(7.9)) == .terminal)
        #expect(performer(tool("Bash", "npm test")).targetScreen(now: Self.base.addingTimeInterval(8.1)) == .terminalLong)
        // Monitor：往后靠着盯日志（6.5 表；一开始就是，超过 8 秒当然也是）
        #expect(pose(tool("Monitor", "tail -f x"), elapsed: 0.5) == .leanBack && pose(tool("Monitor", "tail -f x"), elapsed: 30) == .leanBack)
        // 思考超过 20 秒：深度思考
        #expect(pose(.thinking, elapsed: 19.9) == .thinking)
        #expect(pose(.thinking, elapsed: 20.1) == .thinkingDeep)
    }

    @Test("5.6-18/19/20 做完一轮：先等 0.4 秒（继续保持忙姿势），再伸 1.2 秒懒腰，再 3/4 侧身靠着；未读旗一直保留")
    func finishingATurnWaitsStretchesForOnePointTwoSecondsAndLeansBack() {
        // 目标姿势的边界
        let p = performer(.finished)
        p.lastBusyPose = .typing
        func target(_ el: Double) -> PoseKind { p.targetPose(now: Self.base.addingTimeInterval(el), time: el) }
        #expect(target(0.39) == .typing && target(0.41) == .stretch)
        #expect(target(1.59) == .stretch && target(1.61) == .leanSide)
        // 懒腰本身：1.2 秒一个来回（手举过头再放下），0.6 秒时举得最高
        func handY(_ t: Double) -> Double { PoseLibrary.frame(.stretch, t: t, gt: 0, seed: 0).handL?.y ?? .nan }
        #expect(handY(0.6) < handY(0) - 15, "0.6 秒时手举得最高")
        #expect(abs(handY(1.2) - handY(0)) < 1, "1.2 秒回到起点")
        #expect(handY(0.3) < handY(0) && handY(0.3) > handY(0.6) && handY(0.9) > handY(0.6))
        // 端到端（30 fps）：Edit 忙了 5 秒，然后一轮结束（未读）
        let d = VisualDirector()
        var poses: [(t: Double, pose: PoseKind)] = []
        var flagAlways = true
        T.run(d, from: 0, to: 10, snapshots: { t in
            if t < 5 { return [T.snap(T.tool("Edit", "/a/b.swift", at: 0), since: 0)] }
            var s = T.snap(.finished, since: 5, turnStart: nil); s.unread = true; s.lastTurnDuration = 5
            return [s]
        }) { t, dir in
            guard let pf = dir.performers["d:a"] else { return }
            if poses.last?.pose != pf.pose { poses.append((t, pf.pose)) }
            if t >= 5 {
                let v = pf.seatView(origin: IntPoint(0, 0), time: t, now: Self.base.addingTimeInterval(t), light: LightState(a: .day), hitID: 1, privacy: false, mirror: false)
                if !v.flag { flagAlways = false }
            }
        }
        let frame = 1.0 / 30
        guard let stretch = poses.first(where: { $0.pose == .stretch }) else { Issue.record("没有伸懒腰：\(poses)"); return }
        #expect(stretch.t - 5 >= 0.4 - 1e-6 && stretch.t - 5 <= 0.4 + frame + 1e-6, "结束 0.4 秒之后才伸懒腰：\(stretch.t - 5)")
        #expect(poses.filter { $0.t > 5 && $0.t < stretch.t }.isEmpty, "这 0.4 秒里姿势不变")
        guard let lean = poses.first(where: { $0.pose == .leanSide }) else { Issue.record("没有靠回椅背：\(poses)"); return }
        #expect(lean.t > stretch.t && lean.t - 5 >= 1.6 - 1e-6 && lean.t - 5 <= 1.9 + 3 * frame, "伸完懒腰再侧身靠着（受姿势最短停留 1.5 秒约束）：\(lean.t - 5)")
        #expect(poses.last?.pose == .leanSide)
        #expect(flagAlways, "未读旗一直保留")
    }

    @Test("5.6-19 疑点 Q-07：上一个姿势刚换过（1.5 秒最短停留还没满）时一轮结束，懒腰也不会被跳过或截短")
    func theStretchIsNotSkippedWhenThePoseJustChanged() {
        let d = VisualDirector()
        var poses: [(t: Double, pose: PoseKind)] = []
        // 4.9 秒才换成 Edit（姿势变成打字），5.0 秒就结束了
        T.run(d, from: 0, to: 10, snapshots: { t in
            if t < 4.9 { return [T.snap(T.tool("Read", "/a/app.swift", at: 0), since: 0)] }
            if t < 5.0 { return [T.snap(T.tool("Edit", "/a/b.swift", at: 4.9), since: 4.9)] }
            return [T.snap(.finished, since: 5.0, turnStart: nil)]
        }) { t, dir in
            guard let pf = dir.performers["d:a"] else { return }
            if poses.last?.pose != pf.pose { poses.append((t, pf.pose)) }
        }
        guard let i = poses.firstIndex(where: { $0.pose == .stretch }) else { Issue.record("懒腰被跳过了：\(poses)"); return }
        #expect(poses[i].t - 5.0 <= 1.6, "懒腰最晚在结束后 1.6 秒内开始（姿势最短停留 1.5 秒）：\(poses[i].t - 5.0)")
        // 懒腰整整 1.2 秒都在（手的弹簧跟随，不被下一个姿势提前截断）
        if poses.count > i + 1 { #expect(poses[i + 1].pose == .leanSide && poses[i + 1].t - poses[i].t >= 1.2) }
        #expect(poses.last?.pose == .leanSide)
    }

    // MARK: - 5.5 离场 / 进场 / 下班工位

    @Test("5.5-05 离场：起身 0.3 秒（椅子拉出来）→ 把椅子推好 → 挥手 0.7 秒 → 走出门 → 门在身后关上 0.16 秒；整个过程之后走路系统清空")
    func leavingStandsUpPushesTheChairInWavesAndWalksOut() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 340, maxSeat: 4)
        let door = RoomRenderer(layout: lay).doorFeet
        let ws = WalkerSystem()
        ws.startLeaving(key: "k", appearance: Appearance.generate(seed: 1), seat: 1, layout: lay, door: door, time: 10)
        #expect(WalkerSystem.standTime == 0.3 && WalkerSystem.waveTime == 0.7 && WalkerSystem.tail == 0.16)
        #expect(ws.chairOut(seat: 1, time: 10.0) && ws.chairOut(seat: 1, time: 10.29), "起身的 0.3 秒里椅子还是拉出来的")
        #expect(!ws.chairOut(seat: 1, time: 10.31) && !ws.chairOut(seat: 1, time: 11.0), "起身之后椅子推好（挥手 / 走路时不再拉出来）")
        #expect(!ws.chairOut(seat: 2, time: 10.1), "别的座位的椅子不受影响")
        guard let w = ws.walkers["k"] else { Issue.record("没有走路的人"); return }
        let total = WalkerSystem.standTime + WalkerSystem.waveTime + w.walkTime + WalkerSystem.tail
        ws.cleanup(time: 10 + total + 0.04)
        #expect(ws.isBusy("k"), "门还没关完，人还在")
        ws.cleanup(time: 10 + total + 0.06)
        #expect(ws.isIdle, "走完、门关上之后走路系统清空")
    }

    @Test("5.5-21 进场走到工位约 2.5 秒：路线 70–175 像素的座位走路时间正好 2.5 秒；更近的按 28 像素/秒、更远的按 70 像素/秒封顶（DESIGN.md 第 13 节记录）")
    func walkingInTakesTwoAndAHalfSecondsWhenTheRouteLengthAllowsIt() {
        let lay = OfficeLayout.compute(viewportW: 336, viewportH: 340, maxSeat: 8)
        let door = RoomRenderer(layout: lay).doorFeet
        var inRange = 0
        for seat in 0..<9 {
            let ws = WalkerSystem()
            ws.startEntering(key: "k", appearance: Appearance.generate(seed: 1), seat: seat, layout: lay, door: door, time: 0)
            guard let w = ws.walkers["k"] else { Issue.record("座位 \(seat) 没有走路的人"); continue }
            let len = WalkerSystem.length(w.points)
            if len >= 70 && len <= 175 {
                inRange += 1
                #expect(abs(w.walkTime - 2.5) < 1e-9, "座位 \(seat)：路线 \(len) 像素，走路 \(w.walkTime) 秒")
                #expect(abs((ws.finishedEntering("k", time: 100) ?? 0) - (WalkerSystem.lead + 2.5 + WalkerSystem.sitTime)) < 1e-9)
            } else if len > 175 {
                #expect(w.speed == 70 && w.walkTime > 2.5, "座位 \(seat)：远座位按 70 像素/秒封顶")
            } else {
                #expect(w.speed == 28 && w.walkTime < 2.5, "座位 \(seat)：近座位按 28 像素/秒")
            }
        }
        #expect(inRange >= 1, "这个布局里至少要有一个座位落在 70–175 像素")
    }

    @Test("5.5-07 下班工位：显示器关着、待机灯灭、没有人 / 气泡 / 道具，桌牌变暗，椅子推进去，点不到")
    func anOffDutyDeskHasItsMonitorAndLampOff() {
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 2; o.directorIsExternal = true; o.animateWalkers = false; o.retained = false; o.emptySign = false
        let all = AuditFixtures.snapshots(count: 4, titles: .normal, states: .demo, base: Self.base).map { s -> BuddySnapshot in var x = s; x.appearedAfterLaunch = false; return x }
        var off = all[3]; off.presence = .away(since: Self.base, dormant: true); off.seat = 3
        let present = Array(all.prefix(2))
        for i in 0..<20 {
            let t = Double(i) / 10
            d.update(snapshots: present, now: Self.base.addingTimeInterval(t), time: t, privacy: false)
            _ = sc.render(viewportW: 336, viewportH: 340, present: present, dormant: [off], now: Self.base.addingTimeInterval(t), time: t, options: o)
        }
        guard let v = sc.lastSeatViews.first(where: { $0.seat == 3 }) else { Issue.record("没有座位 3"); return }
        #expect(v.mode == .dormant)
        #expect(v.screen == .off && v.led == 0 && !v.lampOn, "显示器关、待机灯灭、台灯灭")
        #expect(v.rig == nil && v.bubble == nil && v.props.isEmpty && v.helperDraws.isEmpty, "没有人、气泡、道具、小助手")
        #expect(v.dim && !v.chairOut && v.hitID == 0, "桌牌变暗、椅子推进去、点不到")
        #expect(v.fade == nil, "关机渐变早就放完了，不是还在渐变")
        #expect(sc.room.coatSlots.count == 4, "门口的衣帽架有 4 个挂钩")
    }

    // MARK: - 4.4 status_detail 只在悬停卡片里显示

    @Test("4.4-08 桌面本轮总结的英文 status_detail 只在悬停卡片里显示（隐私模式也不显示）；桌牌 / 状态候选 / 办公室里所有文字都没有它")
    func theEnglishStatusDetailIsOnlyShownInTheHoverCard() throws {
        let detail = "SPEC-TRACE status detail that only the hover card may show"
        var s = T.snap(.idle, since: 0, turnStart: nil)
        s.statusDetail = detail; s.blocked = true; s.unread = true; s.idleSince = Self.base
        let now = Self.base.addingTimeInterval(30)
        // 悬停卡片里有
        let card = HoverCard.make(s, now: now, zoom: 2, privacy: false, maxWidth: 600)
        #expect(card.texts.contains { $0.text == detail }, "卡片里的文字：\(card.texts.map { $0.text })")
        // 隐私模式下悬停卡片也不显示
        let priv = HoverCard.make(s, now: now, zoom: 2, privacy: true, maxWidth: 600)
        #expect(!priv.texts.contains { $0.text.contains("SPEC-TRACE") })
        // 桌牌文案 / 状态候选
        let action = PlateCopy.activity(s, now: now, privacy: false)
        #expect(!action.contains("SPEC-TRACE") && action == "需要你处理")
        #expect(PlateCopy.statusCandidates(action: action, s, now: now).allSatisfy { !$0.contains("SPEC-TRACE") })
        #expect(!PlateCopy.statusLine(s, now: now, privacy: false).contains("SPEC-TRACE"))
        // 办公室这一帧的全部文字（桌牌标题 / 状态行）里没有
        let d = VisualDirector(), sc = OfficeScene(); sc.director = d
        var o = SceneOptions(); o.zoom = 2; o.directorIsExternal = true; o.animateWalkers = false; o.retained = false; o.emptySign = false
        s.seat = 0; s.appearedAfterLaunch = false
        d.update(snapshots: [s], now: now, time: 5, privacy: false)
        let frame = sc.render(viewportW: 336, viewportH: 340, present: [s], dormant: [], now: now, time: 5, options: o)
        #expect(!frame.texts.isEmpty && frame.texts.allSatisfy { !$0.text.contains("SPEC-TRACE") })
        // 源码：statusDetail 在表现层 / 应用层里只有悬停卡片读它（AuditFixtures 是造假数据，DemoScript 也只是赋值）
        var readers: Set<String> = []
        for target in ["BuddyStage", "BuddyOffice"] {
            let dir = Self.root.appendingPathComponent("Sources/" + target)
            guard let files = FileManager.default.enumerator(atPath: dir.path) else { Issue.record("找不到 \(dir.path)"); continue }
            for case let rel as String in files where rel.hasSuffix(".swift") {
                let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
                for line in text.split(separator: "\n") where line.contains("statusDetail") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    if !line.contains("statusDetail =") { readers.insert("\(target)/\(rel)") }
                }
            }
        }
        #expect(readers == ["BuddyStage/HoverCard.swift"], "读 statusDetail 的文件：\(readers)")
    }
}
