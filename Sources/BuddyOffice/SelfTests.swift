import AppKit
import PixelKit
import BuddyCore
import BuddyStage

/// 开发自检（不需要任何系统授权；用假 home + 演示数据跑：`BuddyOffice --demo --no-persist --test-…`）。
/// 和单元测试互补：这里走的是真实的 AppKit 事件分发（NSWindow.sendEvent）和真实的窗口状态，不是直接调视图方法。
extension AppDelegate {
    static func emit(_ tag: String, _ s: String) {
        DebugTools.log("\(tag): \(s)")
        print("\(tag): \(s)")
        fflush(stdout)                       // 重定向到文件时 stdout 是整块缓冲：马上写出去，外面的脚本才能按进度取样
    }

    /// 合成一个鼠标事件（窗口坐标：左下原点，点）。
    static func mouseEvent(_ type: NSEvent.EventType, at p: NSPoint, in w: NSWindow, clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                           context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)!
    }
    /// 经 NSWindow.sendEvent 点一下（按下 + 抬起）——AppKit 自己决定这次按下是拖窗口还是交给视图。
    static func click(_ w: NSWindow, at windowPoint: NSPoint, count: Int = 1) {
        w.sendEvent(mouseEvent(.leftMouseDown, at: windowPoint, in: w, clickCount: count))
        w.sendEvent(mouseEvent(.leftMouseUp, at: windowPoint, in: w, clickCount: count))
    }

    /// --test-minimize（A-003）：把办公室窗口最小化到 Dock，之后写一项无关的设置和一次白板计数（每轮做完都会写），
    /// 1 秒后窗口必须仍然是最小化的（旧的 applySettings 会把它弹回来）。
    func runMinimizeTest() {
        guard args.contains("--test-minimize") else { return }
        let tag = "minimize-test"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let w = self.model.office.window
            Self.emit(tag, "开始：办公室窗口 isVisible=\(w?.isVisible == true)，最小化它")
            w?.miniaturize(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            let w = self.model.office.window
            Self.emit(tag, "最小化之后：isMiniaturized=\(w?.isMiniaturized == true) isVisible=\(w?.isVisible == true)；现在写设置 + 白板计数")
            self.model.settings.set(0.9, "tank.opacity")
            self.model.settings.addTally()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
            let w = self.model.office.window
            let ok = w?.isMiniaturized == true
            Self.emit(tag, "写了设置和白板计数 1.3 秒后：isMiniaturized=\(ok) isVisible=\(w?.isVisible == true) → \(ok ? "PASS（没被弹回来）" : "FAIL（被弹回来了）")")
            NSApp.terminate(nil)
        }
    }

    /// --test-resize <步数>（R2-016）：像拖窗口边缘那样，每 16 ms 给办公室窗口改一次内容尺寸（每步差一个缩放单位，来回扫），
    /// `--resize-rounds R` 轮（默认 1，轮与轮之间停 1.5 秒）；`--resize-random`：每步取随机尺寸（最坏情况的压力测试）。
    /// 开始前、每轮做完、全部做完后 1 / 10 / 30 秒各量一次物理占用（phys_footprint），并数新建了几组 IOSurface，写进日志再退出。
    /// 全部做完后先把窗口还原成开始时的尺寸再量（不然「窗口变大了」本身就会让占用变大）；`--resize-still`：对照组，走同样的流程但不改尺寸。
    /// 要在窗口真的出画面的环境里跑：`--demo --force-render`。
    func runResizeTest() {
        guard let steps = DebugTools.opt(args, "--test-resize").flatMap({ Int($0) }), steps > 0 else { return }
        let tag = "resize-test"
        let rounds = max(1, DebugTools.opt(args, "--resize-rounds").flatMap { Int($0) } ?? 1)
        let random = args.contains("--resize-random"), still = args.contains("--resize-still")
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15                    // 固定种子：几个版本走的是同一条尺寸序列
        func rnd() -> Int { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Int(truncatingIfNeeded: seed >> 11) & 0x7FFF_FFFF }
        func mb(_ v: Double) -> String { String(format: "%.1f", v) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            guard let w = self.model.office.window, let cv = w.contentView else { Self.emit(tag, "FAIL 没有办公室窗口"); NSApp.terminate(nil); return }
            let z = CGFloat(max(1, self.model.office.zoom))
            let vf = (w.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1400, height: 900)
            let minW: CGFloat = 320, minH: CGFloat = 300
            let maxW = max(minW + 100, min(1400, vf.width - 40)), maxH = max(minH + 100, min(900, vf.height - 40))
            let origW = cv.bounds.width, origH = cv.bounds.height
            var cw = origW, ch = origH
            var dw: CGFloat = 1, dh: CGFloat = 1
            let base = DebugTools.physFootprintMB()
            let sets0 = PixelView.surfaceSetsAllocated
            Self.emit(tag, "开始：内容 \(Int(cw))×\(Int(ch)) 缩放 \(Int(z)) 基线 \(mb(base)) MB；\(rounds) 轮 × \(steps) 步（\(still ? "对照组：不改尺寸" : random ? "随机尺寸" : "小步来回扫")，范围 \(Int(minW))–\(Int(maxW)) × \(Int(minH))–\(Int(maxH))）")
            func finish() {
                if !still { w.setContentSize(NSSize(width: origW, height: origH)) }
                for delay in [1.0, 10.0, 30.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        let now = DebugTools.physFootprintMB()
                        Self.emit(tag, "全部做完后 \(Int(delay)) 秒：占用 \(mb(now)) MB（比基线 \(now >= base ? "+" : "")\(mb(now - base)) MB），累计新建 IOSurface 组 \(PixelView.surfaceSetsAllocated - sets0)")
                        if delay == 30 { Self.emit(tag, "RESULT 增长 \(mb(now - base)) MB"); NSApp.terminate(nil) }
                    }
                }
            }
            var round = 0
            func runRound() {
                if round == rounds { finish(); return }
                round += 1
                var i = 0
                Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { t in
                    if i == steps {
                        t.invalidate()
                        Self.emit(tag, "第 \(round) 轮做完：占用 \(mb(DebugTools.physFootprintMB())) MB，累计新建 IOSurface 组 \(PixelView.surfaceSetsAllocated - sets0)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { runRound() }
                        return
                    }
                    i += 1
                    if random {
                        cw = minW + CGFloat(rnd() % Int(maxW - minW)); ch = minH + CGFloat(rnd() % Int(maxH - minH))
                    } else {
                        cw += dw * z * CGFloat(1 + rnd() % 2)
                        if cw > maxW { cw = maxW; dw = -1 } else if cw < minW { cw = minW; dw = 1 }
                        if rnd() % 2 == 0 {
                            ch += dh * z
                            if ch > maxH { ch = maxH; dh = -1 } else if ch < minH { ch = minH; dh = 1 }
                        }
                    }
                    if !still { w.setContentSize(NSSize(width: cw.rounded(), height: ch.rounded())) }
                }
            }
            runRound()
        }
    }

    /// --test-tank-click（A-002）：打开小鱼缸，用合成的鼠标事件经 NSWindow.sendEvent 依次：单击背景（应该交给「拖窗口」）、
    /// 双击背景（应该走「回到办公室」的回调）、点小人（应该走跳转的回调）。performDrag 换成只计数的闭包（真的拖动会进入一个等真实鼠标抬起的模态循环）。
    func runTankClickTest() {
        guard args.contains("--test-tank-click") else { return }
        let tag = "tank-click-test"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.model.settings.set(true, "tank.visible") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            let tank = self.model.tank, pv = tank.pixelView, panel = tank.panel
            guard panel.isVisible, pv.frame_ != nil else { Self.emit(tag, "FAIL 小鱼缸没有出现 / 没有画面"); NSApp.terminate(nil); return }
            var buddy: NSPoint?, background: NSPoint?
            for vy in stride(from: 4, to: Int(pv.bounds.height) - 4, by: 2) { for vx in stride(from: 4, to: Int(pv.bounds.width) - 4, by: 2) {
                let p = NSPoint(x: vx, y: vy), id = pv.hitID(at: p)
                if buddy == nil, id >= 2000, id < 3000 { buddy = p }
                if background == nil, id == 0, vy > Int(pv.bounds.height) / 2 { background = p }
            } }
            guard let b = buddy, let bg = background else { Self.emit(tag, "FAIL 找不到小人 / 背景像素（buddy=\(String(describing: buddy)) 背景=\(String(describing: background))）"); NSApp.terminate(nil); return }
            var dragged = 0, doubleClicked = 0
            var clicked: String?
            pv.performDrag = { _ in dragged += 1 }
            tank.onDoubleClickBackground = { doubleClicked += 1 }
            tank.onClickBuddy = { clicked = $0.key }
            Self.click(panel, at: pv.convert(bg, to: nil), count: 1)
            let a = dragged == 1 && doubleClicked == 0 && clicked == nil
            Self.emit(tag, "单击背景：拖窗口 \(dragged) 次、回办公室 \(doubleClicked) 次 → \(a ? "PASS" : "FAIL")")
            Self.click(panel, at: pv.convert(bg, to: nil), count: 2)
            let d = doubleClicked == 1
            Self.emit(tag, "双击背景：回办公室回调 \(doubleClicked) 次 → \(d ? "PASS" : "FAIL（点击被吞掉了）")")
            Self.click(panel, at: pv.convert(b, to: nil), count: 1)
            let c = clicked != nil
            Self.emit(tag, "点小人：跳转回调收到 \(clicked ?? "无") → \(c ? "PASS" : "FAIL（点击被吞掉了）")")
            Self.emit(tag, "RESULT \(a && d && c ? "PASS" : "FAIL")")
            NSApp.terminate(nil)
        }
    }
}
