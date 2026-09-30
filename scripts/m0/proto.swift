// M0 可行性小样：把「Buddy 办公室」要依赖的系统能力逐项实测一遍，结果写进 /tmp/buddy-m0.log。
// 用法：scripts/m0/build-proto.sh 编译并装到 ~/Applications，然后
//   open -n "~/Applications/Buddy 办公室.app" --args --m0 hit,notif,sm,deeplink,activate,tty
// 每一项都会写出 "RESULT <名字> PASS/FAIL/INFO …"。
import AppKit
import UserNotifications
import ServiceManagement
import Foundation

let logURL = URL(fileURLWithPath: "/tmp/buddy-m0.log")
let logQueue = DispatchQueue(label: "m0.log")
func mlog(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) \(s)\n"
    logQueue.sync {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else { try? line.write(to: logURL, atomically: false, encoding: .utf8) }
    }
}
func result(_ name: String, _ verdict: String, _ detail: String = "") { mlog("RESULT \(name) \(verdict) \(detail)") }

// MARK: - 像素精灵 + 对象 ID 缓冲（命中测试用）
let sw = 40, sh = 30, zoom = 3
var rgba = [UInt8](repeating: 0, count: sw * sh * 4)
var idbuf = [UInt16](repeating: 0, count: sw * sh)
func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: (UInt8, UInt8, UInt8), id: UInt16) {
    for y in y0..<y1 { for x in x0..<x1 {
        let i = y * sw + x
        rgba[i * 4] = c.0; rgba[i * 4 + 1] = c.1; rgba[i * 4 + 2] = c.2; rgba[i * 4 + 3] = 255
        idbuf[i] = id
    } }
}
func clear(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    for y in y0..<y1 { for x in x0..<x1 {
        let i = y * sw + x
        rgba[i * 4 + 3] = 0; rgba[i * 4] = 0; rgba[i * 4 + 1] = 0; rgba[i * 4 + 2] = 0; idbuf[i] = 0
    } }
}
func buildSprite() {
    fill(8, 4, 32, 12, (230, 160, 90), id: 1)      // 头
    fill(6, 12, 34, 28, (90, 130, 200), id: 1)     // 身体
    clear(16, 16, 24, 22)                           // 身体中间挖一个透明洞：洞里应该点得穿
}

func artHit(px: Int, py: Int) -> UInt16 {
    // 命中范围向外扩 1 像素
    for dy in -1...1 { for dx in -1...1 {
        let x = px + dx, y = py + dy
        if x >= 0, y >= 0, x < sw, y < sh, idbuf[y * sw + x] != 0 { return idbuf[y * sw + x] }
    } }
    return 0
}

final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ProtoView: NSView {
    var clicks = 0
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        clicks += 1
        let p = convert(event.locationInWindow, from: nil)
        let id = artHit(px: Int(p.x) / zoom, py: Int(p.y) / zoom)
        mlog("CLICK at (\(Int(p.x)),\(Int(p.y))) art=(\(Int(p.x) / zoom),\(Int(p.y) / zoom)) id=\(id) appActive=\(NSApp.isActive)")
    }
    override func makeBackingLayer() -> CALayer { CALayer() }
    func setup() {
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.actions = ["contents": NSNull()]
        let cs = CGColorSpaceCreateDeviceRGB()
        var premult = rgba
        for i in 0..<(sw * sh) {
            let a = Int(premult[i * 4 + 3])
            for k in 0..<3 { premult[i * 4 + k] = UInt8(Int(premult[i * 4 + k]) * a / 255) }
        }
        let data = Data(premult) as CFData
        if let prov = CGDataProvider(data: data),
           let img = CGImage(width: sw, height: sh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: sw * 4, space: cs,
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            layer?.contents = img
        }
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: StripPanel!
    var view: ProtoView!
    var pollTimer: DispatchSourceTimer?
    var toggles = 0
    var tests: [String] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        mlog("=== launch pid=\(getpid()) bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath) ext=\(Bundle.main.bundleURL.pathExtension)")
        mlog("args=\(CommandLine.arguments.dropFirst())")
        buildSprite()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        mlog("screen frame=\(screen.frame) visible=\(sf) scale=\(screen.backingScaleFactor)")
        let w = CGFloat(sw * zoom), h = CGFloat(sh * zoom)
        panel = StripPanel(contentRect: NSRect(x: sf.maxX - w - 40, y: sf.minY, width: w, height: h),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        view = ProtoView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.setup()
        panel.contentView = view
        panel.orderFrontRegardless()
        startPolling()

        if let i = CommandLine.arguments.firstIndex(of: "--m0"), i + 1 < CommandLine.arguments.count {
            tests = CommandLine.arguments[i + 1].split(separator: ",").map(String.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.runNext() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // 每秒 30 次读鼠标位置，命中不透明像素才拦截鼠标
    func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.pollMouse() }
        t.resume()
        pollTimer = t
    }
    func pollMouse() {
        let loc = NSEvent.mouseLocation
        let f = panel.frame
        var id: UInt16 = 0
        if f.insetBy(dx: -2, dy: -2).contains(loc) {
            let px = Int((loc.x - f.minX) / CGFloat(zoom))
            let py = Int((f.maxY - loc.y) / CGFloat(zoom))
            id = artHit(px: px, py: py)
        }
        let shouldIgnore = (id == 0)
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
            toggles += 1
            mlog("toggle ignoresMouseEvents=\(shouldIgnore) mouse=(\(Int(loc.x)),\(Int(loc.y))) id=\(id)")
        }
    }

    func runNext() {
        guard !tests.isEmpty else { mlog("=== all tests dispatched"); return }
        let t = tests.removeFirst()
        mlog("--- test \(t)")
        switch t {
        case "hit": testHit { self.runNext() }
        case "notif": testNotif { self.runNext() }
        case "sm": testSM(); runNext()
        case "deeplink": testDeepLink { self.runNext() }
        case "activate": testActivate { self.runNext() }
        case "tty": testTTY { self.runNext() }
        case "quit": mlog("quit"); NSApp.terminate(nil)
        default: result(t, "FAIL", "unknown test"); runNext()
        }
    }

    // T1 点穿：把鼠标挪到不透明处 / 透明洞里 / 远处，看 ignoresMouseEvents 是否按预期切换
    func testHit(done: @escaping () -> Void) {
        let f = panel.frame
        let mainH = NSScreen.screens[0].frame.height
        func warp(artX: Int, artY: Int) {
            let nsX = f.minX + (CGFloat(artX) + 0.5) * CGFloat(zoom)
            let nsY = f.maxY - (CGFloat(artY) + 0.5) * CGFloat(zoom)
            CGWarpMouseCursorPosition(CGPoint(x: nsX, y: mainH - nsY))
        }
        var checks: [(String, Bool)] = []
        let steps: [(String, Int, Int, Bool)] = [
            ("body", 20, 24, false), ("hole", 20, 19, true), ("head", 20, 8, false),
            ("outside", 2, 2, true), ("holeEdge1px", 15, 19, false), ("holeCenter", 19, 18, true),
        ]
        var i = 0
        func next() {
            if i >= steps.count {
                let ok = checks.allSatisfy { $0.1 }
                result("hit", ok ? "PASS" : "FAIL", checks.map { "\($0.0)=\($0.1 ? "ok" : "BAD")" }.joined(separator: " ") + " toggles=\(toggles)")
                CGWarpMouseCursorPosition(CGPoint(x: 10, y: 10))
                done(); return
            }
            let s = steps[i]; i += 1
            warp(artX: s.1, artY: s.2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                checks.append((s.0, self.panel.ignoresMouseEvents == s.3))
                next()
            }
        }
        next()
    }

    // T2 系统通知
    func testNotif(done: @escaping () -> Void) {
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
            result("notif", "FAIL", "not an app bundle"); done(); return
        }
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            mlog("notif settings before: auth=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue) sound=\(s.soundSetting.rawValue) badge=\(s.badgeSetting.rawValue)")
            c.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
                mlog("notif requestAuthorization granted=\(granted) err=\(String(describing: err))")
                c.getNotificationSettings { s2 in
                    mlog("notif settings after: auth=\(s2.authorizationStatus.rawValue)")
                    if granted {
                        let content = UNMutableNotificationContent()
                        content.title = "Buddy 办公室"
                        content.body = "M0 测试通知：想用 Bash（等你批准）"
                        let req = UNNotificationRequest(identifier: "buddy.m0", content: content, trigger: nil)
                        c.add(req) { e in
                            mlog("notif add error=\(String(describing: e))")
                            result("notif", e == nil ? "PASS" : "FAIL", "granted=true add-error=\(String(describing: e))")
                            DispatchQueue.main.async { done() }
                        }
                    } else {
                        result("notif", "INFO", "granted=false status=\(s2.authorizationStatus.rawValue) err=\(String(describing: err))")
                        DispatchQueue.main.async { done() }
                    }
                }
            }
        }
    }

    // T3 SMAppService 状态（只读，不注册，不改用户的登录项）
    func testSM() {
        let s = SMAppService.mainApp.status
        let name: String
        switch s {
        case .notRegistered: name = "notRegistered"
        case .enabled: name = "enabled"
        case .requiresApproval: name = "requiresApproval"
        case .notFound: name = "notFound"
        @unknown default: name = "unknown"
        }
        result("sm", "INFO", "SMAppService.mainApp.status=\(name)(\(s.rawValue)) (只读，未调用 register)")
    }

    func desktopMetaFocus(_ localId: String) -> Double? {
        let base = NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions"
        let fm = FileManager.default
        guard let accts = try? fm.contentsOfDirectory(atPath: base) else { return nil }
        for a in accts {
            guard let orgs = try? fm.contentsOfDirectory(atPath: base + "/" + a) else { continue }
            for o in orgs {
                let p = base + "/" + a + "/" + o + "/" + localId + ".json"
                if let d = fm.contents(atPath: p),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let v = j["lastFocusedAt"] as? Double { return v }
            }
        }
        return nil
    }

    // T4 深链：用自己所在会话的 local_… 测（跳到的就是当前界面）
    func testDeepLink(done: @escaping () -> Void) {
        let localId = "local_ead11c7d-1a62-4a18-849c-c6e4b371d05c"
        let before = desktopMetaFocus(localId)
        let url = URL(string: "claude://code/continue?session=\(localId)")!
        let ok = NSWorkspace.shared.open(url)
        mlog("deeplink open returned \(ok) focusBefore=\(String(describing: before))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let after = self.desktopMetaFocus(localId)
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            let changed = (before != nil && after != nil && after! > before!)
            result("deeplink", ok && changed ? "PASS" : (ok ? "INFO" : "FAIL"),
                   "opened=\(ok) lastFocusedAt \(String(describing: before)) -> \(String(describing: after)) changed=\(changed) frontmost=\(front)")
            done()
        }
    }

    // T5 激活：从非激活状态，用 NSWorkspace.openApplication(activates:) 把别的 App 拉到最前
    func testActivate(done: @escaping () -> Void) {
        let termURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
        mlog("activate start: appActive=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: termURL, configuration: cfg) { app, err in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let f1 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                mlog("activate(A) openApplication Terminal err=\(String(describing: err)) front=\(f1)")
                let a = (f1 == "com.apple.Terminal")
                // 对比：NSRunningApplication.activate() 在我们不是活跃 App 时能不能成功
                let runningClaude = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first
                let r = runningClaude?.activate(options: [.activateAllWindows]) ?? false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let f2 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                    mlog("activate(B) NSRunningApplication.activate returned \(r) front=\(f2)")
                    let b = (f2 == "com.anthropic.claudefordesktop")
                    // 最后：用 openApplication 回到 Claude
                    NSWorkspace.shared.openApplication(at: claudeURL, configuration: cfg) { _, e2 in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            let f3 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                            result("activate", a ? "PASS" : "FAIL",
                                   "openApplication→Terminal front=\(f1) ok=\(a); NSRunningApplication.activate→Claude returned=\(r) front=\(f2) ok=\(b); openApplication→Claude front=\(f3)")
                            done()
                        }
                    }
                }
            }
        }
    }

    // T6 终端跳转：自己开一个临时 Terminal 窗口，再按 tty 找到那个标签页并选中
    func testTTY(done: @escaping () -> Void) {
        DispatchQueue.global().async {
            func run(_ src: String) -> (String?, String?) {
                var err: NSDictionary?
                let s = NSAppleScript(source: src)
                let r = s?.executeAndReturnError(&err)
                return (r?.stringValue, err.map { "\($0)" })
            }
            let (tty, e1) = run("""
            tell application "Terminal"
              set t to do script "echo buddy-m0-test"
              delay 0.6
              return tty of t
            end tell
            """)
            mlog("tty create: tty=\(tty ?? "nil") err=\(e1 ?? "nil")")
            guard let tty = tty, !tty.isEmpty else {
                result("tty", "FAIL", "could not create terminal tab: \(e1 ?? "?")"); DispatchQueue.main.async { done() }; return
            }
            // 先把别的窗口盖到前面，再跳
            let (_, e2) = run("""
            tell application "Terminal"
              repeat with w in windows
                repeat with tb in tabs of w
                  if (tty of tb) is "\(tty)" then
                    set selected of tb to true
                    set miniaturized of w to false
                    set index of w to 1
                    activate
                    return "found"
                  end if
                end repeat
              end repeat
              return "notfound"
            end tell
            """)
            let (front, _) = ("", "")
            _ = front
            DispatchQueue.main.async {
                let f = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                result("tty", e2 == nil && f == "com.apple.Terminal" ? "PASS" : "FAIL", "tty=\(tty) selectScriptErr=\(e2 ?? "nil") front=\(f)")
                // 关掉临时窗口（先解析 id 再关）
                DispatchQueue.global().async {
                    _ = run("""
                    tell application "Terminal"
                      repeat with w in windows
                        if (tty of first tab of w) is "\(tty)" then close w saving no
                      end repeat
                    end tell
                    """)
                    DispatchQueue.main.async { done() }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
