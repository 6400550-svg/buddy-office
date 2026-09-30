import Foundation
import CoreGraphics
import PixelKit
import BuddyArt
import BuddyCore

/// 表现层的命令行入口（buddyctl 和开发用的 stagectl 共用）。
public enum StageCommands {
    static func opt(_ a: [String], _ n: String) -> String? {
        guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    public static func run(_ a: [String]) -> Int32 {
        guard let c = a.first else { print("用法：stagectl room [--w 224 --h 226 --seats 6 --hour 12 --zoom 3 --out f.png]"); return 2 }
        let rest = Array(a.dropFirst())
        switch c {
        case "room": return room(rest)
        case "snapshot": return snapshot(rest)
        case "flicker": return flicker(rest)
        case "bench": return bench(rest)
        case "cards": return cards(rest)
        case "golden": return golden(rest)
        case "gif": return gif(rest)
        case "screens": return screens(rest)
        case "verify": return verify(rest)
        case "text-audit": return textAudit(rest)
        default: print("未知子命令 \(c)"); return 2
        }
    }

    static func roomSheet(_ a: [String], hours: [Double]) -> Int32 {
        let w = Int(opt(a, "--w") ?? "224") ?? 224, h = Int(opt(a, "--h") ?? "226") ?? 226
        let seats = Int(opt(a, "--seats") ?? "6") ?? 6
        let zoom = Int(opt(a, "--zoom") ?? "2") ?? 2
        let out = opt(a, "--out") ?? "dist/stage/roomsheet.png"
        var cells: [ContactSheet.Cell] = []
        for hour in hours {
            let layout = OfficeLayout.compute(viewportW: w, viewportH: h, maxSeat: seats - 1)
            let room = RoomRenderer(layout: layout)
            let c = Canvas(width: layout.worldW, height: layout.worldH)
            let light = DaySchedule.state(atHour: hour)
            room.bake(into: c, light: light)
            room.drawDynamic(on: c, state: .init(hour: hour, time: 12, day: 28, tally: 7), light: light)
            if let img = FrameRenderer.render(Frame(canvas: c, viewport: IntRect(0, 0, layout.worldW, min(layout.worldH, 120))), zoom: zoom, scale: 1) {
                cells.append(.init(image: img, label: String(format: "%.1f h  %@→%@ @%d", hour, "\(light.a)", "\(light.b)", light.level)))
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: 2, title: "room  \(w)x\(h)"),
              (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("roomsheet: \(out)"); return 0
    }

    /// 只画房间（没有人）：看布局、后墙、地板、天空。
    static func room(_ a: [String]) -> Int32 {
        if let hs = opt(a, "--hours") { return roomSheet(a, hours: hs.split(separator: ",").compactMap { Double($0) }) }
        let w = Int(opt(a, "--w") ?? "224") ?? 224, h = Int(opt(a, "--h") ?? "226") ?? 226
        let seats = Int(opt(a, "--seats") ?? "6") ?? 6
        let hour = Double(opt(a, "--hour") ?? "12") ?? 12
        let zoom = Int(opt(a, "--zoom") ?? "3") ?? 3
        let tally = Int(opt(a, "--tally") ?? "7") ?? 7
        let out = opt(a, "--out") ?? "dist/stage/room.png"
        let layout = OfficeLayout.compute(viewportW: w, viewportH: h, maxSeat: seats - 1)
        let room = RoomRenderer(layout: layout)
        let c = Canvas(width: layout.worldW, height: layout.worldH)
        let light = DaySchedule.state(atHour: hour)
        room.bake(into: c, light: light)
        room.drawDynamic(on: c, state: .init(hour: hour, time: 12, day: 28, tally: tally), light: light)
        guard let img = FrameRenderer.render(Frame(canvas: c), zoom: zoom, scale: 1) else { return 1 }
        do { try PNGExport.write(img, to: URL(fileURLWithPath: out)) } catch { print("\(error)"); return 1 }
        print("room: \(out) \(img.width)x\(img.height) layout cols=\(layout.cols) rows=\(layout.rows) world=\(layout.worldW)x\(layout.worldH) light=\(light.a)->\(light.b)@\(light.level)")
        return 0
    }

    /// snapshot --script demo --from 0 --to 10 --fps 5 --zoom 3 --clock 12:00 --w 224 --h 226 --out DIR
    /// 输出确定性的 PNG 帧（文字合成进去）+ contact.png 总览 + report.txt。
    static func snapshot(_ a: [String]) -> Int32 {
        let from = Double(opt(a, "--from") ?? "0") ?? 0, to = Double(opt(a, "--to") ?? "10") ?? 10
        let fps = Double(opt(a, "--fps") ?? "2") ?? 2
        let zoom = Int(opt(a, "--zoom") ?? "3") ?? 3
        let w = Int(opt(a, "--w") ?? "224") ?? 224, h = Int(opt(a, "--h") ?? "226") ?? 226
        let clock = opt(a, "--clock") ?? "12:00"
        let out = opt(a, "--out") ?? "dist/stage/snap"
        let scale = Int(opt(a, "--scale") ?? "1") ?? 1
        var crop: IntRect? = nil
        if let cs = opt(a, "--crop") { let n = cs.split(separator: ",").compactMap { Int($0) }; if n.count == 4 { crop = IntRect(n[0], n[1], n[2], n[3]) } }
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        let hour = (parts.first ?? 12) + (parts.count > 1 ? parts[1] / 60 : 0)
        var cal = Calendar.current; cal.timeZone = TimeZone.current
        var dc = cal.dateComponents([.year, .month, .day], from: Date()); dc.hour = Int(hour); dc.minute = Int((hour - Double(Int(hour))) * 60); dc.second = 0
        let base = cal.date(from: dc) ?? Date()
        let sceneKind = opt(a, "--scene") ?? "office"
        let mode = opt(a, "--mode") ?? "demo"            // demo（默认剧本）/ busy6 / idle6 / crowdN（N 个人，检查用）
        func scriptSnaps(_ t: Double) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) { DemoScript.snapshots(mode: mode, t: t, base: base) }
        let director = VisualDirector()
        let scene = OfficeScene(); scene.director = director
        let tank = TankScene(), strip = StripScene()
        var opts = SceneOptions(); opts.zoom = zoom; opts.tally = 7; opts.directorIsExternal = true
        var t = from
        var frames: [CGImage] = []
        var idx = 0
        var report = "script=\(mode) from=\(from) to=\(to) fps=\(fps) zoom=\(zoom) clock=\(clock) viewport=\(w)x\(h)\n"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        // 预热：让 performer 从剧本 0 秒开始正常推进到 from
        var warm = max(0, from - 4)
        while warm < from {
            let s = scriptSnaps(warm)
            let nw = base.addingTimeInterval(warm)
            director.update(snapshots: s.present, now: nw, time: warm, privacy: false)
            _ = scene.render(viewportW: w, viewportH: h, present: s.present, dormant: s.dormant, now: nw, time: warm, options: opts)
            warm += 1.0 / 15
        }
        while t <= to + 1e-9 {
            let s = scriptSnaps(t)
            let nt = base.addingTimeInterval(t)
            director.update(snapshots: s.present, now: nt, time: t, privacy: false)
            var frame: Frame
            switch sceneKind {
            case "tank": frame = tank.render(director: director, present: s.present, now: nt, time: t, privacy: false, zoom: zoom)
            case "strip": frame = strip.render(director: director, present: s.present, now: nt, time: t, privacy: false)
            default:
                if let hs = opt(a, "--hover").flatMap(Int.init), let snap = s.present.first(where: { $0.seat == hs }) { opts.hoverSeat = hs; opts.hoverSnapshot = snap }
                frame = scene.render(viewportW: w, viewportH: h, present: s.present, dormant: s.dormant, now: nt, time: t, options: opts)
            }
            if let cr = crop { frame.viewport = cr }
            if let img = FrameRenderer.render(frame, zoom: zoom, scale: scale, background: sceneKind == "strip" ? RGBA8(hex: 0x6E7A8C) : nil) {
                let name = String(format: "%@/f%04d.png", out, idx)
                try? PNGExport.write(img, to: URL(fileURLWithPath: name))
                frames.append(img)
                report += String(format: "f%04d t=%.2f hash=%016llx\n", idx, t, frame.canvas.contentHash())
            }
            idx += 1; t += 1.0 / fps
        }
        // 总览：最多 12 张均匀抽样
        let maxCells = Int(opt(a, "--cells") ?? "12") ?? 12
        let step = max(1, frames.count / maxCells)
        var cells: [ContactSheet.Cell] = []
        var i = 0
        while i < frames.count && cells.count < maxCells { cells.append(.init(image: frames[i], label: String(format: "t=%.2fs", from + Double(i) / fps))); i += step }
        if let sheet = ContactSheet.render(cells: cells, columns: Int(opt(a, "--cols") ?? "4") ?? 4, title: "demo \(clock)") { try? PNGExport.write(sheet, to: URL(fileURLWithPath: out + "/contact.png")) }
        try? report.write(toFile: out + "/report.txt", atomically: false, encoding: .utf8)
        print("snapshot: \(frames.count) 帧 → \(out)")
        return 0
    }



    static func modeSnapshots(_ mode: String, t: Double, base: Date) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) {
        DemoScript.snapshots(mode: mode, t: t, base: base)
    }

    /// verify：局部重绘（retained）和每帧整张重画逐像素对比。任何一帧不一致就报出来（帧号、位置），以非零退出。
    ///   verify [--scene office|tank|strip] [--clocks 12:00,22:30,06:50,18:55] [--modes demo,busy6,idle6] [--seconds 40] [--sizes 224x226,224x340,340x300] [--hover] [--dump-bad DIR]
    static func verify(_ a: [String]) -> Int32 {
        let clocks = (opt(a, "--clocks") ?? "12:00,22:30,06:50,18:55").split(separator: ",").map(String.init)
        let modes = (opt(a, "--modes") ?? "demo,busy6,idle6").split(separator: ",").map(String.init)
        let seconds = Double(opt(a, "--seconds") ?? "40") ?? 40
        let sizes: [(Int, Int)] = (opt(a, "--sizes") ?? "224x226,224x340,340x300").split(separator: ",").compactMap { t in
            let p = t.split(separator: "x").compactMap { Int($0) }; return p.count == 2 ? (p[0], p[1]) : nil }
        let sceneKind = opt(a, "--scene") ?? "office"
        var bad = 0, pairs = 0, skipped = 0
        for clock in clocks { for mode in modes { for (w, h) in sizes {
            let r = StageRun.compareRetained(scene: sceneKind, clock: clock, mode: mode, seconds: seconds, viewport: (w, h), hover: a.contains("--hover"))
            pairs += r.frames; skipped += r.skipped
            if let b = r.firstBad {
                bad += 1
                print("✗ [\(sceneKind)] \(clock) \(mode) \(w)x\(h)：帧 \(b.frame) t=\(String(format: "%.2f", b.time)) 不一致：\(b.count) 个像素，范围 \(b.bbox)；\(b.note)")
                if let dir = opt(a, "--dump-bad"), b.count > 0 {
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    let crop = IntRect(max(0, b.bbox.x - 20), max(0, b.bbox.y - 20), min(b.retained.canvas.width, b.bbox.maxX + 20) - max(0, b.bbox.x - 20), min(b.retained.canvas.height, b.bbox.maxY + 20) - max(0, b.bbox.y - 20))
                    for (nm, fr) in [("retained", b.retained), ("full", b.full)] {
                        var f2 = fr; f2.viewport = crop; f2.texts = []
                        if let img = FrameRenderer.render(f2, zoom: 8, scale: 1) { try? PNGExport.write(img, to: URL(fileURLWithPath: "\(dir)/\(sceneKind)-\(clock)-\(mode)-\(w)x\(h)-f\(b.frame)-\(nm).png")) }
                    }
                }
            } else { print("✓ [\(sceneKind)] \(clock) \(mode) \(w)x\(h)：\(r.frames) 帧逐像素一致") }
        } } }
        print("verify: \(pairs) 对帧，其中 \(skipped) 帧局部重绘判定「没变」直接跳过；\(bad == 0 ? "全部一致 ✅" : "\(bad) 组配置有不一致 ❌")")
        return bad == 0 ? 0 : 1
    }


    /// gif --scene office|tank|strip --script demo --from 0 --to 40 --fps 12.5 --zoom 3 --clock 12:00 [--w 224 --h 226] --out demo.gif
    /// 用 ImageIO 导出动图（每帧文字也合成进去）。GIF 的时间精度是 1/100 秒，帧率取 100 的整因数（12.5 fps = 每帧 8 厘秒）最均匀。
    static func gif(_ a: [String]) -> Int32 {
        let sceneKind = opt(a, "--scene") ?? "office"
        let from = Double(opt(a, "--from") ?? "0") ?? 0, to = Double(opt(a, "--to") ?? "40") ?? 40
        let fps = Double(opt(a, "--fps") ?? "12.5") ?? 12.5
        let zoom = Int(opt(a, "--zoom") ?? "3") ?? 3
        let out = opt(a, "--out") ?? "dist/demo.gif"
        let clock = opt(a, "--clock") ?? "12:00"
        let mode = opt(a, "--mode") ?? "demo"
        let vp = StageRun.officeViewport(zoom: 3)
        let w = Int(opt(a, "--w") ?? "\(vp.w)") ?? vp.w, h = Int(opt(a, "--h") ?? "\(vp.h)") ?? vp.h
        let base = StageRun.fixedBase(clock: clock)
        let director = VisualDirector()
        let scene = OfficeScene(); scene.director = director
        let tank = TankScene(), strip = StripScene()
        var opts = SceneOptions(); opts.zoom = zoom; opts.tally = 7; opts.directorIsExternal = true
        // 预热：从 from 前 4 秒开始推进（让弹簧 / 停留状态和真实运行一致）
        let step = 1.0 / 30
        // 先数一遍要出多少帧（和下面的循环同一套算术），好让写入器一帧一帧写、不用把上千帧都攥在内存里
        var total = 0
        do { var tt = max(0, from - 4), ns = from; while tt <= to + 1e-9 { if tt + 1e-9 >= ns { total += 1; ns += 1.0 / fps }; tt += step } }
        guard total > 0 else { print("没有帧"); return 1 }
        // 小鱼缸 / 宠物条的画布宽度随人数变：GIF 每一帧必须一样大（第一帧定下画面尺寸，后面更大的帧会被裁掉），
        // 所以按整段剧本里最多的人数定一个固定尺寸，小的帧贴在右边（宠物条靠右）/ 左上（小鱼缸），空出来的地方填底色。
        var maxCount = 0
        do { var tt = from; while tt <= to + 1e-9 { maxCount = max(maxCount, DemoScript.snapshots(mode: mode, t: tt, base: base).present.count); tt += 0.5 } }
        var pad: (w: Int, h: Int)? = nil
        if sceneKind == "strip" { pad = ((min(8, max(1, maxCount)) * Metrics.cellW + (maxCount > 8 ? StripScene.badgeColW : 0)) * zoom, StripScene.totalH * zoom) }
        else if sceneKind == "tank" { let l = TankScene.layout(count: maxCount); pad = (l.w * zoom, l.h * zoom) }
        let padColor = sceneKind == "strip" ? RGBA8(hex: 0x6E7A8C) : RGBA8(hex: 0x2B2226)
        func padded(_ img: CGImage) -> CGImage {
            guard let pad = pad, img.width != pad.w || img.height != pad.h,
                  let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: pad.w, height: pad.h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
            ctx.setFillColor(CGColor(srgbRed: CGFloat(padColor.r) / 255, green: CGFloat(padColor.g) / 255, blue: CGFloat(padColor.b) / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pad.w, height: pad.h))
            ctx.interpolationQuality = .none
            let x = sceneKind == "strip" ? pad.w - img.width : 0                 // 宠物条靠右；小鱼缸贴左上
            ctx.draw(img, in: CGRect(x: x, y: pad.h - img.height, width: img.width, height: img.height))
            return ctx.makeImage() ?? img
        }
        let delay = max(0.02, (100.0 / fps).rounded() / 100)
        let writer: GIFExport.Writer
        do { writer = try GIFExport.Writer(url: URL(fileURLWithPath: out), frameCount: total) } catch { print("\(error)"); return 1 }
        var written = 0, firstSize = (0, 0)
        var t = max(0, from - 4)
        var nextShot = from
        while t <= to + 1e-9 {
            let s = DemoScript.snapshots(mode: mode, t: t, base: base)
            let nt = base.addingTimeInterval(t)
            director.update(snapshots: s.present, now: nt, time: t, privacy: false)
            var frame: Frame
            switch sceneKind {
            case "tank": frame = tank.render(director: director, present: s.present, now: nt, time: t, privacy: false, zoom: zoom)
            case "strip": frame = strip.render(director: director, present: s.present, now: nt, time: t, privacy: false)
            default: frame = scene.render(viewportW: w, viewportH: h, present: s.present, dormant: s.dormant, now: nt, time: t, options: opts)
            }
            if t + 1e-9 >= nextShot {
                if let raw = FrameRenderer.render(frame, zoom: zoom, scale: 1, background: sceneKind == "strip" ? RGBA8(hex: 0x6E7A8C) : nil) {
                    let img = padded(raw)
                    if written == 0 { firstSize = (img.width, img.height) }
                    writer.add(img, delay: delay); written += 1
                }
                nextShot += 1.0 / fps
            }
            t += step
        }
        guard written == total else { print("帧数对不上：应有 \(total) 帧，实际 \(written) 帧"); return 1 }
        do { try writer.finish() } catch { print("\(error)"); return 1 }
        let size = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int) ?? 0
        print("gif: \(written) 帧，\(firstSize.0)×\(firstSize.1)，每帧 \(Int(delay * 1000)) ms，\(size / 1024) KB → \(out)")
        return 0
    }


    /// screens [--zoom 8] [--out screens.png]：每种屏幕内容在几个时刻的样子（半透明红框 = 人的头通常会挡住的区域），检查关键信息有没有被挡。
    static func screens(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "8") ?? 8
        let out = opt(a, "--out") ?? "dist/stage/screens.png"
        let day = Lighting.resolved(appearance: nil, state: LightState(a: .day))
        let kinds: [(String, ScreenKind)] = [("off", .off), ("ide", .ide), ("doc swift", .doc("swift")), ("doc md", .doc("md")), ("results", .results), ("tree", .tree), ("diffEdit", .diffEdit),
            ("notebook", .notebook), ("terminal", .terminal), ("terminalLong", .terminalLong), ("browser", .browser), ("search", .search), ("helpers", .helpers), ("checklist", .checklist),
            ("manual", .manual), ("iconGrid", .iconGrid), ("mcpBrowser", .mcpBrowser), ("desktop", .desktop), ("mcpApp N", .mcpApp("N")), ("permission", .permission), ("question", .question),
            ("plan", .plan), ("compact", .compact), ("retry 2/10", .retry(2, 10)), ("warning", .warning), ("stop", .stop), ("done", .done), ("idleDesktop", .idleDesktop),
            ("screensaver", .screensaver), ("gear", .gear), ("outbox", .outbox), ("clock", .clock), ("log", .log)]
        var cells: [ContactSheet.Cell] = []
        for (name, k) in kinds {
            for (t, gt) in [(1.0, 1.0), (6.3, 7.0)] {
                let c = Canvas(width: 24, height: 15)
                ScreenContent.draw(k, on: c, rect: IntRect(0, 0, 24, 15), t: t, gt: gt, seed: 5, style: day)
                // 头通常挡住的区域：屏幕第 12 行以下、第 7–19 列
                let cover = Canvas(width: 24, height: 15)
                cover.blitCanvas(c, x: 0, y: 0)
                for y in 12..<15 { for x in 7..<20 { let p = cover.pixel(x, y); cover.setRaw(x, y, color: RGBA8(UInt8(min(255, Int(p & 0xFF) / 2 + 120)), UInt8(Int((p >> 8) & 0xFF) / 2), UInt8(Int((p >> 16) & 0xFF) / 2), 255)) }}
                if let im = FrameRenderer.render(Frame(canvas: cover), zoom: zoom, scale: 1) { cells.append(.init(image: im, label: "\(name)  t=\(t)")) }
            }
        }
        guard let sheet = ContactSheet.render(cells: cells, columns: 6, title: "screens"), (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("screens: \(cells.count) 张 → \(out)"); return 0
    }

    /// cards [--zoom 2] [--scale 2] [--out cards.png]：把提示卡（各种类）和悬停卡（演示剧本里的各种状态）排成一张总览，检查文字有没有溢出 / 重叠。
    static func cards(_ a: [String]) -> Int32 {
        let zoom = Int(opt(a, "--zoom") ?? "2") ?? 2, scale = Int(opt(a, "--scale") ?? "2") ?? 2
        let out = opt(a, "--out") ?? "dist/stage/cards.png"
        var cells: [ContactSheet.Cell] = []
        let bg = RGBA8(hex: 0x8A94A8)
        func add(_ card: HoverCard.Card, _ label: String) {
            if let im = FrameRenderer.render(Frame(canvas: card.canvas, texts: card.texts), zoom: zoom, scale: scale, background: bg) { cells.append(.init(image: im, label: label)) }
        }
        let kinds: [(ToastCard.Kind, String, String)] = [
            (.approval, "等你批准", "重构登录模块 · Bash"), (.question, "有问题问你", "论文引用检查"), (.plan, "计划好了", "健身计划 app"),
            (.finished, "做完了", "DeepSeek 试验 · 用时 3分12秒"), (.blocked, "需要你处理", "重构登录模块"), (.error, "出错了", "打盹的会话"), (.info, "Buddy 办公室", "深链跳转没有生效，已改为直接打开 Claude。"),
            (.approval, "这是一个非常非常长的会话标题用来检查省略号有没有出现在该出现的地方", "等你批准 Bash · 2 分钟，这一行也很长很长很长很长很长"),
            (.approval, "会话", "有人在等你（隐私模式）"),
        ]
        for (k, t, b) in kinds { add(ToastCard.make(kind: k, title: t, body: b, zoom: zoom), "toast \(k)") }
        let base = Date()
        for t in [4.0, 10, 20, 41, 50, 58, 64, 68] {
            let snap = DemoScript.snapshots(at: t, base: base.addingTimeInterval(-t))
            for s in (snap.present + snap.dormant).prefix(3) { add(HoverCard.make(s, now: base, zoom: zoom, privacy: false), "hover t=\(Int(t)) \(s.title)") }
        }
        if let s = DemoScript.snapshots(at: 20, base: base.addingTimeInterval(-20)).present.first { add(HoverCard.make(s, now: base, zoom: zoom, privacy: true), "hover 隐私模式") }
        guard let sheet = ContactSheet.render(cells: cells, columns: 4, title: "cards"), (try? PNGExport.write(sheet, to: URL(fileURLWithPath: out))) != nil else { return 1 }
        print("cards: \(cells.count) 张 → \(out)"); return 0
    }

    /// bench --scene office|tank|strip --mode demo|busy6|idle6 --frames 600 --clock 12:00 --zoom 3 [--w 224 --h 340] [--prof]
    /// 按 30 fps 的节奏连续渲染，报告每帧平均耗时（导演更新 / 场景 / 哈希 / 出图）。用来核对性能预算。
    static func bench(_ a: [String]) -> Int32 {
        let sceneKind = opt(a, "--scene") ?? "office"
        let mode = opt(a, "--mode") ?? "demo"
        let frames = Int(opt(a, "--frames") ?? "600") ?? 600
        let zoom = Int(opt(a, "--zoom") ?? "3") ?? 3
        let w = Int(opt(a, "--w") ?? "224") ?? 224, h = Int(opt(a, "--h") ?? "340") ?? 340
        let clock = opt(a, "--clock") ?? "12:00"
        let fps = Double(opt(a, "--fps") ?? "30") ?? 30
        let sleepMs = Double(opt(a, "--sleep-ms") ?? "0") ?? 0          // 每帧之间真的睡一会儿：模拟 App 里「30 Hz 的短脉冲」（缓存是冷的、可能在能效核上）
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        let hour = (parts.first ?? 12) + (parts.count > 1 ? parts[1] / 60 : 0)
        var cal = Calendar.current; cal.timeZone = TimeZone.current
        var dc = cal.dateComponents([.year, .month, .day], from: Date()); dc.hour = Int(hour); dc.minute = Int((hour - Double(Int(hour))) * 60); dc.second = 0
        let base = cal.date(from: dc) ?? Date()
        let director = VisualDirector()
        let scene = OfficeScene(); scene.director = director
        let tank = TankScene(), strip = StripScene()
        var opts = SceneOptions(); opts.zoom = zoom; opts.tally = 7; opts.directorIsExternal = true
        func snaps(_ t: Double) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) { modeSnapshots(mode, t: t, base: base) }
        // 预热 5 秒
        var t = 0.0
        while t < 5 {
            let s = snaps(t); let nt = base.addingTimeInterval(t)
            director.update(snapshots: s.present, now: nt, time: t, privacy: false)
            switch sceneKind {
            case "tank": _ = tank.render(director: director, present: s.present, now: nt, time: t, privacy: false)
            case "strip": _ = strip.render(director: director, present: s.present, now: nt, time: t, privacy: false)
            default: _ = scene.render(viewportW: w, viewportH: h, present: s.present, dormant: s.dormant, now: nt, time: t, options: opts)
            }
            t += 1 / fps
        }
        Prof.reset(); Prof.enabled = a.contains("--prof")
        var tDir = 0.0, tScene = 0.0, tHash = 0.0, tImg = 0.0
        var changed = 0
        var lastHash: UInt64 = 0
        func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
        for _ in 0..<frames {
            if sleepMs > 0 { usleep(UInt32(sleepMs * 1000)) }
            let s = snaps(t); let nt = base.addingTimeInterval(t)
            let a0 = now()
            director.update(snapshots: s.present, now: nt, time: t, privacy: false)
            let a1 = now()
            let frame: Frame
            switch sceneKind {
            case "tank": frame = tank.render(director: director, present: s.present, now: nt, time: t, privacy: false, zoom: zoom)
            case "strip": frame = strip.render(director: director, present: s.present, now: nt, time: t, privacy: false)
            default: frame = scene.render(viewportW: w, viewportH: h, present: s.present, dormant: s.dormant, now: nt, time: t, options: opts)
            }
            let a2 = now()
            let hsh = frame.canvas.contentHash()
            let a3 = now()
            if hsh != lastHash { _ = frame.canvas.makeCGImage(crop: frame.viewport); changed += 1; lastHash = hsh }
            let a4 = now()
            tDir += Double(a1 - a0); tScene += Double(a2 - a1); tHash += Double(a3 - a2); tImg += Double(a4 - a3)
            t += 1 / fps
        }
        let f = Double(frames)
        let total = (tDir + tScene + tHash + tImg) / 1e6 / f
        print(String(format: "bench[%@ %@ %@ zoom %d]: %d 帧  导演 %.3f ms  场景 %.3f ms  哈希 %.3f ms  出图 %.3f ms  合计 %.3f ms/帧 → 30 fps 约占一个核 %.2f%%  （画面有变化的帧 %d / %d）",
                     sceneKind, mode, clock, zoom, frames, tDir / 1e6 / f, tScene / 1e6 / f, tHash / 1e6 / f, tImg / 1e6 / f, total, total * 30 / 10, changed, frames))
        if Prof.enabled { print(Prof.report(frames: frames)) }
        return 0
    }

    /// flicker --scene office|tank|strip --from 0 --to 79.9 --fps 30 --zoom 3 [--clock 12:00] [--mode demo|busy6|idle6] [--strict] [--dump DIR]：
    /// 对演示剧本跑闪烁扫描，有一项不合格就以非零退出。办公室的视口按缩放倍数换算（1 倍 = 672×678 美术像素）。
    /// --dump DIR：把检查 2 抓到的每一处（含被容忍的）放大 8 倍输出成条带图（前 3 帧到后 2 帧，红线 = 出问题的那一帧，黄框 = 出问题的像素）。
    static func flicker(_ a: [String]) -> Int32 {
        let sceneKind = opt(a, "--scene") ?? "office"
        let zoom = Int(opt(a, "--zoom") ?? "3") ?? 3
        var vp: (w: Int, h: Int)? = nil
        if let w = opt(a, "--w").flatMap(Int.init), let h = opt(a, "--h").flatMap(Int.init) { vp = (w, h) }
        let r = StageRun.flicker(scene: sceneKind, zoom: zoom, clock: opt(a, "--clock") ?? "12:00", mode: opt(a, "--mode") ?? "demo",
                                 from: Double(opt(a, "--from") ?? "0") ?? 0, to: Double(opt(a, "--to") ?? "79.9") ?? 79.9,
                                 fps: Double(opt(a, "--fps") ?? "30") ?? 30, strict: a.contains("--strict"), viewport: vp, dump: opt(a, "--dump") != nil)
        if let dir = opt(a, "--dump") {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for s in r.strips { try? PNGExport.write(s.image, to: URL(fileURLWithPath: String(format: "%@/%@-f%05d-%dpx%@.png", dir, sceneKind, s.frame, s.count, s.tolerated ? "-容忍" : ""))) }
            print("dump: \(r.strips.count) 张条带图 → \(dir)")
        }
        if r.findings.isEmpty {
            print("flicker[\(sceneKind) zoom \(zoom)]: \(r.frames) 帧，全部干净 ✅（另有 \(r.tolerated) 处 ≤ 6 个孤立像素的抖动，已容忍）"); return 0
        }
        print("flicker[\(sceneKind) zoom \(zoom)]: \(r.frames) 帧，发现 \(r.findings.count) 个问题：")
        for x in r.findings.prefix(40) { print("  " + x.description) }
        return 1
    }

    /// text-audit [--quick] [--scene office,hover,tank,strip,cards,toast] [--images DIR] [--max N] [--window WxH]…：
    /// 文字审计（8 类问题，见 TextAudit）在所有压力组合下跑一遍；有违规以非零退出。
    static func textAudit(_ a: [String]) -> Int32 {
        if a.contains("--probe") { return textProbe(a) }
        var cfg = a.contains("--quick") ? TextAuditRunner.Config.quick : TextAuditRunner.Config()
        if let sc = opt(a, "--scene") { cfg.scenes = Set(sc.split(separator: ",").map(String.init)) }
        // --window 672x4000（可重复）：只用这些窗口尺寸（点）；调试「窗口里看不见的座位」时用一个很高的窗口把整个办公室一次看全
        var custom: [TextAuditRunner.Window] = []
        for (i, x) in a.enumerated() where x == "--window" && i + 1 < a.count {
            let parts = a[i + 1].split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { custom.append(.init(name: "自定义\(parts[0])x\(parts[1])", wPt: parts[0], hPt: parts[1])) }
        }
        if !custom.isEmpty { cfg.windows = custom }
        cfg.imageDir = opt(a, "--images")
        cfg.filter = opt(a, "--filter")
        cfg.saveAll = a.contains("--all-images")
        if a.contains("--all-images") { cfg.maxImages = Int(opt(a, "--max-images") ?? "40") ?? 40 }
        let maxShow = Int(opt(a, "--max") ?? "40") ?? 40
        let rep = TextAuditRunner.run(cfg, log: { print("  · \($0)") })
        print("text-audit：\(rep.combos) 个组合、\(rep.texts) 段文字、\(rep.pixelStrings) 串像素字，用时 \(String(format: "%.1f", rep.seconds)) 秒")
        for (k, v) in rep.perScene.sorted(by: { $0.key < $1.key }) { print("  \(k)：\(v.combos) 个组合，\(v.violations) 处违规") }
        for k in TextAudit.Kind.allCases { print("  \(k.rawValue) \(k.title)：\(rep.count(k))") }
        if rep.hoverTotal > 0 { print("  悬停卡片：\(rep.hoverTotal) 个悬停组合里没画出卡片的：\(rep.hoverWithoutCard.isEmpty ? "0" : rep.hoverWithoutCard.sorted { $0.key < $1.key }.map { "\($0.key)窗口 \($0.value)" }.joined(separator: "，"))") }
        if a.contains("--hover-missing") { for c in rep.hoverMissingExamples { print("  没画卡片：\(c)") } }
        // 悬停卡片必须每次都画得出来（窗口再小也有兜底位置）：一张都不许缺，否则「悬停组合 0 违规」可能只是因为根本没有卡片
        if rep.hoverCardsMissing > 0 { print("text-audit：✗ 有 \(rep.hoverCardsMissing) 个悬停组合没画出卡片（--hover-missing 列出）") }
        if rep.violations.isEmpty { if rep.hoverCardsMissing == 0 { print("text-audit：违规 0 ✅"); return 0 }; return 1 }
        // 按（类别，场景，文字种类）分组，一眼看出是哪几个根因
        var groups: [String: Int] = [:]
        var example: [String: String] = [:]
        for v in rep.violations {
            let key = "\(v.kind.rawValue)·\(v.kind.title) | \(v.scene) | \(v.tag.isEmpty ? "-" : v.tag)"
            groups[key, default: 0] += 1
            if example[key] == nil { example[key] = v.combo + "：" + v.detail }
        }
        print("分组：")
        for (k, n) in groups.sorted(by: { $0.value > $1.value }) { print("  \(n)\t\(k)\n      例：\(example[k] ?? "")") }
        print("text-audit：共 \(rep.violations.count) 处违规（每类只列前几条）：")
        var shown: [TextAudit.Kind: Int] = [:]
        for v in rep.violations {
            shown[v.kind, default: 0] += 1
            if shown[v.kind]! <= max(1, maxShow / 8) { print("  ✗ " + v.description) }
        }
        for p in rep.savedImages.prefix(20) { print("  图：\(p)") }
        return 1
    }

    /// text-audit --probe：打印桌牌文字的排版数字（每个缩放下：桌牌内部高度、两行字的笔画范围），调排版用。
    static func textProbe(_ a: [String]) -> Int32 {
        let tr = TextRenderer.shared
        let title = TextStyle(size: 11, color: RGBA8(0, 0, 0, 255), weight: .semibold)
        let status = TextStyle(size: 10, color: RGBA8(0, 0, 0, 255), weight: .regular)
        for (name, st) in [("title", title), ("status", status)] {
            for sample in ["测试Agpy", "测试", "Agpy 0:41", "🚀发布"] {
                guard let ink = tr.ink(sample, style: st, scale: 2), let b = ink.bbox else { continue }
                let m = tr.measure(sample, style: st)
                print("\(name) 「\(sample)」 盒 \(m.width)×\(m.height) pt；图 \(ink.pixelWidth)×\(ink.pixelHeight) px；笔画 y \(b.y)…\(b.maxY - 1)（上空 \(b.y) 下空 \(ink.pixelHeight - b.maxY) px）")
            }
        }
        for z in 1...5 { print("缩放 \(z)×：桌牌 \(Metrics.plateH) 美术像素 = \(Metrics.plateH * z) pt = \(Metrics.plateH * z * 2) px；内部（去掉上下各 1 美术像素）\((Metrics.plateH - 2) * z * 2) px") }
        return 0
    }

    /// golden [--update] [--dump DIR] [--file Tests/BuddyStageTests/golden.txt]：算金图哈希；--update 写文件，否则和文件比对（不一致以非零退出）。
    /// --dump DIR：把每一条金图的画面（3 倍，含文字）存成 PNG，先亲眼看过再 --update。
    static func golden(_ a: [String]) -> Int32 {
        let file = opt(a, "--file") ?? "Tests/BuddyStageTests/golden.txt"
        if let dir = opt(a, "--dump") {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for p in StageRun.goldenPlan {
                guard let f = StageRun.frame(scene: p.scene, at: p.t, clock: p.clock),
                      let img = FrameRenderer.render(f, zoom: 3, scale: 1, background: p.scene == "strip" ? RGBA8(hex: 0x6E7A8C) : nil) else { continue }
                let name = StageRun.goldenName(p).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "")
                try? PNGExport.write(img, to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
            print("golden: \(StageRun.goldenPlan.count) 张画面 → \(dir)")
        }
        let now = StageRun.goldenHashes()
        let text = now.map { "\($0.name) \(String(format: "%016llx", $0.hash))" }.joined(separator: "\n") + "\n"
        if a.contains("--update") {
            do { try text.write(toFile: file, atomically: false, encoding: .utf8) } catch { print("写不了 \(file)：\(error)"); return 1 }
            print("golden: 已写入 \(now.count) 条 → \(file)"); return 0
        }
        guard let old = try? String(contentsOfFile: file, encoding: .utf8) else { print("没有金图文件 \(file)；先运行 golden --update"); return 1 }
        var expected: [String: String] = [:]
        for l in old.split(separator: "\n") { let p = l.split(separator: " "); if p.count == 2 { expected[String(p[0])] = String(p[1]) } }
        var bad = 0
        for (n, h) in now {
            let got = String(format: "%016llx", h)
            if expected[n] != got { bad += 1; print("✗ \(n) 期望 \(expected[n] ?? "（没有）") 实际 \(got)") }
        }
        print(bad == 0 ? "golden: \(now.count) 条全部一致 ✅" : "golden: \(bad) 条不一致 ❌")
        return bad == 0 ? 0 : 1
    }
}
