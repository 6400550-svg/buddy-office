import AppKit
import PixelKit
import BuddyStage

/// 开发 / 自检用：把窗口内容渲染成 PNG（不需要屏幕录制权限），并用合成的鼠标位置验证命中测试和悬停。
/// 用法：open -g -n "Buddy 办公室.app" --args --demo --show --dump-window /tmp/w.png --after 3 --quit-after-dump
enum DebugTools {
    /// 日志：~/Library/Logs/BuddyOffice/debug.log（目录 0700、文件 0600，超过 1 MB 轮转成 debug.log.1）。
    /// 只在开发开关下写（--log-ui / --prof / --self-test / --probe-pid / --test-* / --dump-*）：发布版默认什么都不写。
    /// 日志里不写会话标题（可能含对话摘要）——要提标题用 titleForLog。
    static let logDirectory = NSHomeDirectory() + "/Library/Logs/BuddyOffice"
    static var logPath: String { logDirectory + "/debug.log" }

    static func devFlagsPresent(_ args: [String]) -> Bool {
        // `--test-bundle-path` 是 Swift Testing 宿主进程自己的参数，不是开发开关（不然测试进程里日志开关恒为开，R2-007）
        args.contains { $0 == "--log-ui" || $0 == "--prof" || $0 == "--self-test" || $0 == "--probe-pid" || ($0.hasPrefix("--test-") && $0 != "--test-bundle-path") || $0.hasPrefix("--dump-") }
    }
    static let enabled = devFlagsPresent(CommandLine.arguments)

    static func log(_ s: String) {
        guard enabled else { return }
        write(s, toPath: logPath)
    }

    /// 日志里代替会话标题的写法（只留字数）。
    static func titleForLog(_ title: String) -> String { "〈标题 \(title.count) 字〉" }

    /// 追加一行。所有失败（磁盘满 / 只读 / 文件被截断 / 路径是符号链接）都静默放弃——写日志不能让 App 崩，
    /// 也不能跟着符号链接往别处写（同机其他用户可以预先放一个链接）。用新式 FileHandle API（旧的 seekToEndOfFile / write 出错时抛 Objective-C 异常，捕不住）。
    static func write(_ s: String, toPath path: String, maxBytes: Int = 1_000_000, now: Date = Date()) {
        guard let data = "\(now) \(s)\n".data(using: .utf8) else { return }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if (try? fm.destinationOfSymbolicLink(atPath: path)) != nil { return }
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size + data.count > maxBytes {
                try? fm.removeItem(atPath: path + ".1")
                try? fm.moveItem(atPath: path, toPath: path + ".1")
            }
            if !fm.fileExists(atPath: path), !fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) { return }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: data)
        } catch { /* 放弃 */ }
    }

    /// 本进程的物理占用（phys_footprint，和「活动监视器」的「内存」一列同一个口径），单位 MB；取不到返回 -1。
    static func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func opt(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 把内容视图的图层树渲染成 PNG（用 CALayer.render，不需要屏幕录制权限）。
    static func dumpWindow(_ w: NSWindow?, to path: String) {
        guard let w = w, let v = w.contentView, let layer = v.layer else { log("dump: no window"); return }
        let scale = w.backingScaleFactor
        let pw = Int(v.bounds.width * scale), ph = Int(v.bounds.height * scale)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { log("dump: no ctx"); return }
        ctx.scaleBy(x: scale, y: scale)
        // 视图是 flipped（左上原点），CALayer.render 用的是左下原点：翻转一下
        ctx.translateBy(x: 0, y: v.bounds.height); ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
        guard let img = ctx.makeImage() else { log("dump: no image"); return }
        do { try PNGExport.write(img, to: URL(fileURLWithPath: path)) } catch { log("dump: \(error)"); return }
        log("dump: wrote \(path) \(pw)x\(ph) window=\(w.frame) backing=\(scale) sublayers=\(layer.sublayers?.count ?? 0)")
    }

    /// 把任意 PixelView 的图层树渲染成 PNG。
    static func dumpView(_ v: NSView, scale: CGFloat, to path: String) {
        guard let layer = v.layer, v.bounds.width > 0 else { log("dumpView: empty"); return }
        let pw = Int(v.bounds.width * scale), ph = Int(v.bounds.height * scale)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: 0, y: v.bounds.height); ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
        if let img = ctx.makeImage() { try? PNGExport.write(img, to: URL(fileURLWithPath: path)); log("dumpView: wrote \(path) \(pw)x\(ph)") }
    }

    /// 把任意视图按它的绘制路径渲染成 PNG（SwiftUI 也行，不需要屏幕录制权限）。
    static func dumpViewBitmap(_ v: NSView, to path: String) {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { log("dumpViewBitmap: no rep"); return }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { log("dumpViewBitmap: no png"); return }
        do { try data.write(to: URL(fileURLWithPath: path)); log("dumpViewBitmap: wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)") } catch { log("dumpViewBitmap: \(error)") }
    }

    /// 设置窗口逐页渲染：浅色 / 深色各一遍。--dump-settings PREFIX：写 PREFIX-light-0.png … PREFIX-dark-3.png。
    static func dumpSettings(model: AppModel, prefix: String, done: @escaping () -> Void) {
        var jobs: [(String, Int)] = []
        for mode in ["light", "dark"] { for tab in 0..<4 { jobs.append((mode, tab)) } }
        func next() {
            guard let (mode, tab) = jobs.first else { done(); return }
            jobs.removeFirst()
            NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            SettingsView.initialTab = tab
            let wc = SettingsWindowController(model: model)
            wc.showWindow(nil)
            wc.window?.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // 连窗口的外框（标题栏 + 窗口背景）一起画：只画 contentView 的话，深色下没有自己背景的页（数据源诊断）和页签条会是一片白底白字，看不出真实的样子
                if let v = wc.window?.contentView { dumpViewBitmap(v.superview ?? v, to: "\(prefix)-\(mode)-\(tab).png") }
                wc.window?.orderOut(nil)
                next()
            }
        }
        next()
    }

    /// 自检：用真实的 PixelView 帧对几个位置做命中测试。
    static func selfTest(model: AppModel) {
        guard let oc = model.office else { return }
        let pv = oc.pixelView
        log("selftest: view bounds=\(pv.bounds) zoom=\(pv.zoom) layout=\(oc.scene.layout)")
        var okAll = true
        // 每个在场的 buddy 的座位：在它的格子中央偏上（头/身体的位置）应该命中它的 ID；空白地板应该是 0
        for v in oc.scene.lastSeatViews where v.mode == .occupied {
            let o = v.origin
            var hit = 0
            // 在人物区域内扫一遍
            for dy in stride(from: 16, to: 50, by: 2) { for dx in stride(from: 20, to: 40, by: 2) {
                let px = CGFloat((o.x + dx - (pv.frame_?.viewport.x ?? 0)) * pv.zoom) + CGFloat(pv.zoom) / 2
                let py = CGFloat((o.y + dy - (pv.frame_?.viewport.y ?? 0)) * pv.zoom) + CGFloat(pv.zoom) / 2
                if pv.hitID(at: NSPoint(x: px, y: py)) == OfficeScene.hitID(seat: v.seat) { hit += 1 }
            } }
            let ok = hit > 10
            okAll = okAll && ok
            log("selftest: seat \(v.seat) body hit samples=\(hit) \(ok ? "PASS" : "FAIL")")
        }
        // 墙上没有 buddy：应该是 0
        let wall = pv.hitID(at: NSPoint(x: 20, y: 20))
        log("selftest: wall hit=\(wall) \(wall == 0 ? "PASS" : "FAIL")")
        okAll = okAll && wall == 0
        log("selftest: RESULT \(okAll ? "PASS" : "FAIL")")
    }

    /// 桌面宠物条 / 小鱼缸的自检：命中测试、点穿切换。
    static func panelsSelfTest(model: AppModel) {
        let strip = model.strip
        guard strip.panel.isVisible else { log("panels: strip not visible"); return }
        let f = strip.panel.frame
        log("panels: strip frame=\(f) zoom=\(strip.zoom)")
        // 在宠物条画面里找一个 buddy 的像素（对象 ID 缓冲），再挪到透明处
        var solid: NSPoint?, empty: NSPoint?
        if let fr = strip.pixelView.frame_ {
            let z = strip.zoom
            for y in stride(from: 0, to: fr.canvas.height, by: 2) { for x in stride(from: 0, to: fr.canvas.width, by: 2) {
                let id = fr.canvas.objectID(x, y)
                let pt = NSPoint(x: f.minX + CGFloat(x * z + z / 2), y: f.maxY - CGFloat(y * z + z / 2))
                if id >= 3000 && id < 4000 && solid == nil { solid = pt }
                if id == 0 && fr.canvas.hitID(x: x, y: y, dilate: true) == 0 && empty == nil && y > fr.canvas.height / 2 { empty = pt }
            } }
        }
        var ok = true
        if let s = solid { let ignore = strip.evaluate(at: s); log("panels: over buddy → ignoresMouseEvents=\(ignore) \(!ignore ? "PASS" : "FAIL")"); ok = ok && !ignore } else { log("panels: no buddy pixel found FAIL"); ok = false }
        if let e = empty { let ignore = strip.evaluate(at: e); log("panels: over empty → ignoresMouseEvents=\(ignore) \(ignore ? "PASS" : "FAIL")"); ok = ok && ignore }
        let far = strip.evaluate(at: NSPoint(x: f.minX - 500, y: f.minY - 500))
        log("panels: far away → ignoresMouseEvents=\(far) \(far ? "PASS" : "FAIL")"); ok = ok && far
        log("panels: RESULT \(ok ? "PASS" : "FAIL") toggles=\(strip.toggles)")
    }
}
