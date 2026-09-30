import AppKit
import PixelKit
import BuddyCore
import BuddyStage

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var args: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        args = Array(CommandLine.arguments.dropFirst())
        let demo = args.contains("--demo")
        let speed = Double(DebugTools.opt(args, "--speed") ?? "1") ?? 1
        let provider: SnapshotProvider = demo ? MockSource(speed: speed, mode: DebugTools.opt(args, "--demo-mode") ?? "demo") : Providers.make(args: args)
        model = AppModel(provider: provider, args: args)
        model.demo = demo
        buildMenu()
        Prof.enabled = args.contains("--prof")
        model.office?.forceRender = false
        model.start()
        model.office.forceRender = args.contains("--force-render")
        runJumpTest()
        runTitlebarTest()
        runMinimizeTest()
        runTankClickTest()
        runResizeTest()
        // 开发自检：--probe-pid <pid>：打印这个进程的 tty、父进程链上找到的宿主 App（验证终端跳转用到的两个函数）
        if let pid = DebugTools.opt(args, "--probe-pid").flatMap({ Int32($0) }) {
            let host = JumpService.shared.hostApp(of: pid)
            DebugTools.log("probe-pid \(pid): tty=\(ProcessInfoHelper.ttyName(of: pid) ?? "nil") parent=\(ProcessInfoHelper.parent(of: pid).map(String.init) ?? "nil") host=\(host?.bundleIdentifier ?? "nil") (\(host?.localizedName ?? "-"))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
        if let prefix = DebugTools.opt(args, "--dump-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                DebugTools.dumpSettings(model: self.model, prefix: prefix) { NSApp.terminate(nil) }
            }
        }
        // 开发自检：--log-ui：每秒把 Dock 角标、菜单栏图标种类、等你的人数写进日志（演示模式下验证兜底提醒）
        if args.contains("--log-ui") {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let m = self.model!
                DebugTools.log("ui: 等你=\(m.alerts.waitingKeys.count) Dock 角标=\(NSApp.dockTile.badgeLabel ?? "无") 菜单栏图标=\(m.status.currentKindName) 在场=\(m.present.count)")
            }
        }
        // 开发自检：--test-autoquit <秒>：假装 Claude 刚退出，N 秒后按真实规则判断要不要退出（不会真的去退出用户的 Claude）
        if let sec = DebugTools.opt(args, "--test-autoquit").flatMap(Double.init) {
            DebugTools.log("autoquit: 模拟 Claude 退出，\(sec) 秒后判断（开关 \(model.settings.bool("autoQuitWithClaude") ? "开" : "关")）")
            model.autoQuit.scheduleQuit(after: sec)
        }
        // 调试：过一会儿把窗口渲染成 PNG / 跑自检
        let after = Double(DebugTools.opt(args, "--after") ?? "3") ?? 3
        if let path = DebugTools.opt(args, "--dump-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self = self else { return }
                DebugTools.dumpWindow(self.model.office?.window, to: path)
                if self.args.contains("--self-test") { DebugTools.selfTest(model: self.model); DebugTools.panelsSelfTest(model: self.model) }
                if let tp = DebugTools.opt(self.args, "--dump-titlebar") {
                    DebugTools.dumpViewBitmap(self.model.office.titleBar.bar, to: tp)
                    let b = self.model.office.titleBar.bar
                    let w = self.model.office.window
                    DebugTools.log("titlebar: bar frame=\(b.frame) 在窗口里的位置=\(b.superview != nil ? b.convert(b.bounds, to: nil) : .zero) 窗口 frame=\(w?.frame ?? .zero) 按钮 on: 小鱼缸=\(b.tank.on) 宠物=\(b.strip.on)")
                }
                if let pp = DebugTools.opt(self.args, "--dump-panels") {
                    DebugTools.dumpView(self.model.tank.pixelView, scale: 2, to: pp + "-tank.png")
                    DebugTools.dumpView(self.model.strip.pixelView, scale: 2, to: pp + "-strip.png")
                }
                if self.args.contains("--quit-after-dump") { NSApp.terminate(nil) }
            }
        }
    }

    /// 开发自检：--test-titlebar：用合成的鼠标事件点标题栏上的三个按钮，把每一步的结果写进日志（然后退出）。
    func runTitlebarTest() {
        guard args.contains("--test-titlebar") else { return }
        func click(_ b: PixelButton) {
            guard let w = b.window else { DebugTools.log("titlebar-test: 按钮不在窗口里"); return }
            let p = b.convert(NSPoint(x: b.bounds.midX, y: b.bounds.midY), to: nil)
            b.mouseEntered(with: Self.mouseEvent(.mouseMoved, at: p, in: w))
            Self.click(w, at: p)                     // 经 NSWindow.sendEvent 分发（真实的 AppKit 路径：先判断这次按下是不是窗口拖动，再交给视图）
        }
        func state(_ s: String) {
            let m = self.model!
            DebugTools.log("titlebar-test: \(s) → 办公室 \(m.office.window?.isVisible == true ? "开" : "关") · 小鱼缸 \(m.tank.isVisible ? "开" : "关") · 宠物 \(m.strip.isVisible ? "开" : "关") · 设置窗口 \(m.settingsWindow?.window?.isVisible == true ? "开" : "关") · 按钮亮着：小鱼缸 \(m.office.titleBar.bar.tank.on) 宠物 \(m.office.titleBar.bar.strip.on)")
        }
        let bar = { self.model.office.titleBar.bar }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { state("开始") ; click(bar().strip) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { state("点了「桌面宠物」"); click(bar().strip) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { state("又点了一次「桌面宠物」"); click(bar().settings) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { state("点了「设置」"); click(bar().tank) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { state("点了「缩成小鱼缸」"); self.model.tank.onDoubleClickBackground?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { state("双击小鱼缸的背景（回到办公室）"); self.model.settings.set(0.9, "tank.opacity") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { state("随便改了一项设置（小鱼缸透明度）之后，办公室窗口不该被收起来"); NSApp.terminate(nil) }
    }

    /// 开发自检：--test-jump <hostSessionId>：6 秒后（等数据读到）对那个桌面会话发一次深链跳转，8 秒后把结果写进日志再退出。
    /// 用来验证 JumpService 对真实会话生效（测试目标只能是我自己这个会话，别的会话别乱跳）。
    func runJumpTest() {
        guard let host = DebugTools.opt(args, "--test-jump") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self else { return }
            guard let s = self.model.snapshots.first(where: { $0.hostSessionId == host }) else {
                DebugTools.log("test-jump: 没有找到 hostSessionId=\(host) 的会话；现有：\(self.model.snapshots.map { ($0.hostSessionId ?? "-") + "/" + DebugTools.titleForLog($0.title) })"); NSApp.terminate(nil); return
            }
            let before = DesktopMeta.lastFocusedAt(host: host)
            DebugTools.log("test-jump: 跳转 \(DebugTools.titleForLog(s.title)) origin=\(s.origin) activity=\(s.activity.phase) valid=\(JumpService.validHostID(host)) lastFocusedAt(before)=\(before.map { String($0) } ?? "nil")")
            JumpService.shared.jump(to: s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let after = DesktopMeta.lastFocusedAt(host: host)
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                DebugTools.log("test-jump: 结果 lastFocusedAt(after)=\(after.map { String($0) } ?? "nil") 深链失败次数=\(JumpService.shared.deepLinkFailures) 已停用=\(JumpService.shared.deepLinkDisabled) 最前面的 App=\(front)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showOffice()
        Settings.shared.set(true, "office.visible")
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    /// 用户真的把 App 带到前台（Dock / 安装脚本打开）：办公室窗口已经在了就请求通知授权（后台启动时窗口早就在了，那时 App 还不在前台，没问）。
    func applicationDidBecomeActive(_ notification: Notification) { model?.officeMayHaveOpened() }

    /// 退出时把身份和 token 账本写盘（任务书 4.3：最多 30 秒写一次，退出时也写一次）。
    /// SessionStore.stop() → engine.shutdown()：先叫后台扫描停下，再 flush。
    /// 真实数据的 stop() 会同步等后台队列（当前一次 poll + token 扫描 + 写盘），放到后台最多等 1.5 秒；超时就放弃 flush
    /// （下次启动从上次偏移继续读，不会错；两个文件都是原子写，退出时被打断也不会写坏）。演示的 stop() 要在主线程上（它的 Timer 在主线程）。
    func applicationWillTerminate(_ notification: Notification) {
        guard let m = model else { return }
        if m.demo { m.provider.stop(); return }
        let p = m.provider
        if !BoundedWait.run(timeout: 1.5, { p.stop() }) { DebugTools.log("exit: provider.stop() 超过 1.5 秒没有返回，不再等") }
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem("设置…", key: ",") { [weak self] in self?.model.showSettings() })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Buddy 办公室", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(ClosureMenuItem("办公室") { [weak self] in self?.model.showOffice() })
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        NSApp.mainMenu = main
    }
}
