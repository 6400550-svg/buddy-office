import AppKit
import QuartzCore
import UserNotifications
import BuddyCore
import PixelKit
import BuddyArt
import BuddyStage

/// 应用的「大脑」：拿数据、分发给各个显示面（办公室窗口 / 小鱼缸 / 桌面宠物条），按节拍渲染，并驱动提醒 / 菜单栏 / Dock。
final class AppModel {
    var provider: SnapshotProvider
    let args: [String]
    private(set) var snapshots: [BuddySnapshot] = [] { didSet { refreshDerived() } }       // 新数据不用叫醒渲染：下一个节拍（≤ 66 ms）就会带上
    /// 在场的 / 下班的（已按「隐藏的会话」过滤）。数据或设置变化时重算，不是每帧都算。
    private(set) var present: [BuddySnapshot] = []
    private(set) var dormant: [BuddySnapshot] = []
    /// 设置每变一次 +1：各个面板据此决定要不要重新读设置（不用每帧读 UserDefaults）。
    private(set) var settingsGen = 0
    /// 上一次被「叫醒」（新数据 / 设置 / 悬停 / 窗口重新可见）的时刻：之后半秒内用满帧率。
    private var wakeAt: CFTimeInterval = 0
    private var lastAlerts: CFTimeInterval = 0
    let settings: Settings
    let director = VisualDirector()
    let t0 = CACurrentMediaTime()
    /// 第一批数据到了吗：没到之前办公室是空的，但那不是「今天还没人上班」，所以不显示那块牌子（否则每次启动都先闪一下）。
    private(set) var gotData = false
    var timer: Timer?
    var demo = false

    var office: OfficeWindowController!
    let tank = TankPanelController()
    let strip = StripPanelController()
    let status = StatusItemController()
    let dock = DockTileController()
    let notifier = NotificationService()
    let pipeline: AlertPipeline
    var alerts: AlertCoordinator { pipeline.coordinator }
    let autoQuit = AutoQuit()
    let hotkey = HotKey()
    var settingsWindow: SettingsWindowController?
    private var settingsObserver: NSObjectProtocol?
    private var pendingApply = false

    /// 切换演示 / 真实数据时造新的数据源、停掉旧的（测试可以换成假的：测试里不能去起真的 SessionStore 读真实数据）。
    var makeRealProvider: ([String]) -> SnapshotProvider = { Providers.make(args: $0) }
    var makeDemoProvider: () -> SnapshotProvider = { MockSource(speed: 1) }
    /// 停掉旧数据源：真实数据的 stop() 要等后台队列（写盘 + 等 token 扫描）放到后台；演示的 stop() 要在创建它的主线程上（它的 Timer 在主线程）。
    var stopProvider: (SnapshotProvider, _ wasDemo: Bool) -> Void = { p, wasDemo in
        if wasDemo { p.stop() } else { DispatchQueue.global(qos: .utility).async { p.stop() } }
    }

    init(provider: SnapshotProvider, args: [String], settings: Settings = .shared) {
        self.provider = provider
        self.args = args
        self.settings = settings
        let settings = self.settings, status = self.status
        pipeline = AlertPipeline(sink: LiveAlertSink(notifier: notifier, dock: dock, updateStatus: { status.update(waiting: $0, busy: $1) }, settings: settings))
        wire(provider)
    }

    private func wire(_ p: SnapshotProvider) {
        // 座位号先清洗（被写坏的持久化座位号不能让办公室去分配天文数字的桌子），再按座位排序
        p.onUpdate = { [weak self] snaps in self?.gotData = true; self?.snapshots = SeatSanitizer.sanitize(snaps).sorted { ($0.seat, $0.key) < ($1.seat, $1.key) } }
        p.onEvent = { _ in }
    }

    var time: Double { CACurrentMediaTime() - t0 }
    var hidden: Set<String> { settings.hiddenKeys }
    func refreshDerived() {
        (present, dormant) = Self.derive(snapshots: snapshots, hidden: hidden, dormantMax: settings.int("dormant.max"))
    }
    /// 数据层快照 → 显示用的「在场的 / 下班的」（去掉用户隐藏的）。纯函数，单测直接喂。
    /// dormantMax 夹在 0…8（Array.prefix(负数) 是运行时陷阱）；下班工位超出时留下最近活动的（away.since 最晚的）几个，仍按座位顺序排。
    static func derive(snapshots: [BuddySnapshot], hidden hide: Set<String>, dormantMax: Int) -> (present: [BuddySnapshot], dormant: [BuddySnapshot]) {
        let present = snapshots.filter { $0.presence == .present && !hide.contains($0.key) }
        var dormant = snapshots.filter { s in if case .away(_, let d) = s.presence { return d && !hide.contains(s.key) }; return false }
        let cap = max(0, min(dormantMax, 8))
        if dormant.count > cap {
            func since(_ s: BuddySnapshot) -> Date { if case .away(let t, _) = s.presence { return t }; return .distantPast }
            let keep = Set(dormant.sorted { (since($0), $1.seat) > (since($1), $0.seat) }.prefix(cap).map { $0.key })
            dormant = dormant.filter { keep.contains($0.key) }
        }
        return (present, dormant)
    }
    /// 还有没有活着的会话（「跟着 Claude 一起收」用）：被用户隐藏的 buddy 也算——他只是不在办公室里显示，终端里的 claude 还在跑。
    static func hasLiveSessions(snapshots: [BuddySnapshot]) -> Bool { snapshots.contains { $0.presence == .present } }
    /// 新数据、设置变化、鼠标悬停、窗口重新可见：马上恢复满帧率，并让下一个节拍尽快渲染（但两拍之间不少于 1/30 秒，见 TickPacer）。
    func wake() {
        wakeAt = CACurrentMediaTime()
        if let d = pacer.wakeDelay(now: wakeAt) { schedule(after: d) }        // 已经排好的下一拍还早：提前
    }
    private var pacer = TickPacer()
    /// 一次性定时器，每拍结束时按当时的需要排下一拍（不再是固定 30 Hz 的重复定时器：没什么要画的时候一秒只醒 4 次）。
    private func schedule(after d: TimeInterval) {
        let delay = max(0.001, d)
        timer?.invalidate()
        let tm = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
        tm.tolerance = 0.003
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        pacer.scheduled(after: delay, now: CACurrentMediaTime())
    }
    var privacy: Bool { settings.bool("privacy.hideDetails") }

    // MARK: 启动
    func start() {
        office = OfficeWindowController()
        office.onClickSeat = { [weak self] seat in self?.jump(seat: seat) }
        office.onRightClick = { [weak self] seat, ev, view in self?.showContextMenu(seat: seat, event: ev, in: view) }
        // 小鱼缸 / 宠物条点的是「那一刻画在那里的那个人」：按快照的 key 重新找最新的那份再跳（座位号可能在两帧之间换了人）
        tank.onClickBuddy = { [weak self] s in self?.jump(snapshot: s) }
        tank.onDoubleClickBackground = { [weak self] in self?.expandToOffice() }
        tank.onRightClick = { [weak self] seat, ev, view in self?.showContextMenu(seat: seat, event: ev, in: view) }
        strip.onClickBuddy = { [weak self] s in self?.jump(snapshot: s) }
        strip.onRightClick = { [weak self] seat, ev, view in self?.showContextMenu(seat: seat, event: ev, in: view) }
        status.model = self
        status.onJump = { [weak self] s in self?.jump(snapshot: s) }
        notifier.onClick = { [weak self] key in self?.handleNotificationClick(key: key) }
        JumpService.shared.onNotice = { [weak self] title, body in self?.notifier.toast.show(key: "notice", kind: .info, title: title, body: body) }
        wireAutoQuit()
        autoQuit.start()
        hotkey.onFire = { [weak self] in self?.toggleOffice() }
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.settingsGen &+= 1; self.refreshDerived(); self.wake(); self.scheduleApply()
        }
        office.onWake = { [weak self] in self?.wake() }
        let tb = office.titleBar.bar
        tb.tank.onClick = { [weak self] in self?.shrinkToTank() }
        tb.strip.onClick = { [weak self] in guard let self = self else { return }; self.settings.set(!self.settings.bool("strip.visible"), "strip.visible") }
        tb.settings.onClick = { [weak self] in self?.showSettings() }
        settings.pruneOldTallies()
        refreshDerived()
        provider.start()
        applySettings(initial: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { SoundSynth.prewarm() }
        tick()
    }

    /// 「跟着 Claude 一起收」的两个判断：开关；还有没有活会话（被隐藏的 buddy 也算，见 A-010）。
    func wireAutoQuit() {
        autoQuit.isEnabled = { [weak self] in self?.settings.bool("autoQuitWithClaude") ?? false }
        autoQuit.hasLiveSessions = { [weak self] in Self.hasLiveSessions(snapshots: self?.snapshots ?? []) }
    }

    func scheduleApply() {
        if pendingApply { return }
        pendingApply = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.pendingApply = false; self?.applySettings(initial: false) }
    }

    /// 上一次应用的入口设置：只有变化的部分才去动窗口 / 面板 / 菜单栏 / 热键（AppKit 自己写的窗口位置、每轮做完写的白板计数……也会触发
    /// UserDefaults 变化通知，原来每次都无差别重跑：最小化的办公室窗口被弹回来、热键反复注销 / 重新注册）。
    private var lastApplied: FormInputs?

    /// 按设置显示 / 隐藏各个形态、菜单栏、Dock、快捷键。所有入口里至少保留一个可见。
    func applySettings(initial: Bool) {
        var f = FormInputs(office: settings.bool("office.visible"), tank: settings.bool("tank.visible"), strip: settings.bool("strip.visible"),
                           menu: settings.bool("ui.menuBarIcon"), dock: settings.bool("ui.dockIcon"), hotkey: settings.bool("hotkey.enabled"))
        if args.contains("--show") { f.office = true }
        if args.contains("--tank") { f.tank = true }
        if args.contains("--strip") { f.strip = true }
        if args.contains("--no-windows") { f.office = false; f.tank = false; f.strip = false; f.menu = true }     // 开发用：量「不画」时的底噪
        if args.contains("--test-hotkey") { f.hotkey = true }
        let cur = ApplyPlanner.entryFallback(f, stripHasBuddies: !present.isEmpty, initial: initial)        // 至少留一个入口
        let w = office.window
        let plan = ApplyPlanner.plan(previous: initial ? nil : lastApplied, current: cur,
                                     window: WindowState(isVisible: w?.isVisible ?? false, isMiniaturized: w?.isMiniaturized ?? false, appHidden: NSApp.isHidden))
        lastApplied = cur
        if let regular = plan.activationRegular { NSApp.setActivationPolicy(regular ? .regular : .accessory) }
        switch plan.office {
        case .show?: showOffice(initial: initial, persist: false)
        case .hide?: office.window?.orderOut(nil)
        case nil: break
        }
        if let a = plan.tank { if a == .show { tank.show(model: self) } else { tank.hide() } }
        if let a = plan.strip { if a == .show { strip.show(model: self) } else { strip.hide() } }
        office.titleBar.bar.update(tankOn: cur.tank, stripOn: cur.strip)
        if let a = plan.menuBar { status.setVisible(a == .show) }
        if let a = plan.hotkey { if a == .show { hotkey.register() } else { hotkey.unregister() } }
        // 入口被强制补上 Dock 图标时把设置也改过来：否则设置页显示「Dock 图标：关」而 Dock 里其实有图标
        for w in ApplyPlanner.settingsWriteBack(raw: f, effective: cur) { settings.set(w.value, w.key) }
        wake()
    }

    /// persist：这次是用户要打开的（小鱼缸双击、菜单、右键菜单……）就把「办公室窗口开着」记进设置——否则之后随便改一项设置，
    /// applySettings 看到 office.visible 还是 false，会又把窗口收起来。applySettings 自己调用时不写（它就是按设置在开）。
    func showOffice(initial: Bool = false, persist: Bool = true) {
        if persist && !settings.bool("office.visible") { settings.set(true, "office.visible") }
        // 先渲染好第一帧再显示窗口（不闪）
        office.render(model: self, force: true)
        if initial && !office.hadSavedFrame { office.window?.center() }        // 第一次运行才居中；之后用上次的位置（setFrameAutosaveName 自动恢复）
        if office.window?.isMiniaturized == true { office.window?.deminiaturize(nil) }        // 明确要打开办公室：最小化在 Dock 里的窗口也恢复出来
        office.showWindow(nil)
        office.window?.orderFrontRegardless()
        officeMayHaveOpened()
    }
    /// 办公室窗口出现了 / App 变成了前台：第一次主动打开办公室时请求通知授权（DESIGN §2 M0；后台启动的 App 不问，拒绝后不再反复弹）。
    func officeMayHaveOpened() {
        notifier.officeMayHaveOpened(appActive: { NSApp.isActive }, officeVisible: { [weak self] in self?.office?.window?.isVisible ?? false })
    }
    /// 标题栏上的「缩成小鱼缸」：办公室窗口收起，小鱼缸出现（双击小鱼缸的背景回到办公室）。
    func shrinkToTank() {
        settings.set(true, "tank.visible")
        settings.set(false, "office.visible")
    }
    /// 小鱼缸上双击背景：回到办公室（小鱼缸收起——它就是办公室缩小的样子；想两个都开，用菜单栏或设置）。
    func expandToOffice() {
        settings.set(false, "tank.visible")
        showOffice()
    }
    func toggleOffice() {
        if office.window?.isVisible == true { office.window?.orderOut(nil); settings.set(false, "office.visible") }
        else { showOffice() }
    }
    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: self) }
        NSApp.activate()
        settingsWindow?.showWindow(nil)
        notifier.refresh()
    }

    // MARK: 节拍
    /// 节拍：每拍结束时按需要排下一拍——
    ///  · 有东西需要 30 fps 才画得顺（转身、气泡弹出、走路、小助手在滑）或刚被叫醒 → 30 fps；
    ///  · 只剩逐格离散的小动作（打字、呼吸、眨眼……，节拍都是 15 fps 的整数倍）→ 15 fps；全员空闲 → 10 fps；
    ///  · 没有任何一个显示面可见（窗口被遮住 / 收起）→ 4 次/秒，只维持提醒、菜单栏、Dock 角标。
    func tick() {
        let mono = CACurrentMediaTime()
        pacer.didTick(at: mono)
        defer {
            let visible = office.wantsFrames || tank.isVisible || strip.isVisible
            let moving = CACurrentMediaTime() - wakeAt < 0.5 || director.needsFullRate(time: time) || !office.scene.walkers.isIdle
            // 稳态：有人在忙 / 在等你 → 15 fps（打字节拍是它的整数倍）；全员空闲 → 10 fps（只剩呼吸、待机灯、zzz，都是秒级的慢动作）
            let anyActive = present.contains { $0.phase != .idle }
            let interval = !visible ? 0.25 : (moving ? 1.0 / 30 : (anyActive ? 1.0 / 15 : 1.0 / 10))
            schedule(after: TickPacer.delayAfterTick(interval: interval, elapsed: CACurrentMediaTime() - mono))
        }
        let now = Date(), t = time
        let pres = present
        var pt = Prof.begin()
        director.update(snapshots: pres, now: now, time: t, privacy: privacy)
        Prof.end("app.director", pt)
        pt = Prof.begin()
        var changed = office.render(model: self)
        Prof.end("app.office", pt)
        pt = Prof.begin()
        if tank.render(model: self) { changed = true }
        Prof.end("app.tank", pt)
        pt = Prof.begin()
        if strip.render(model: self) { changed = true }
        Prof.end("app.strip", pt)
        _ = changed
        guard mono - lastAlerts >= 0.09 || lastAlerts == 0 else { profTick(mono); return }
        lastAlerts = mono
        pt = Prof.begin()
        defer { Prof.end("app.alerts", pt); profTick(mono) }
        // 提醒：判定 → 系统通知 / 提示卡 / 白板计数 / 菜单栏图标 / Dock 角标（用户隐藏的 buddy 不提醒，见 AlertCoordinator）
        pipeline.run(snapshots: snapshots, present: pres, hidden: hidden, now: now, config: AlertConfig(settings: settings),
                     isLooking: { [weak self] s in self?.isUserLooking(at: s) ?? false }, privacy: privacy, demo: demo)
    }

    // 开发用：--prof 时每 5 秒把主线程各段耗时写进日志
    private var profSince: CFTimeInterval = 0
    private var profTicks = 0
    private func profTick(_ mono: CFTimeInterval) {
        guard Prof.enabled else { return }
        profTicks += 1
        if profSince == 0 { profSince = mono }
        if mono - profSince >= 5 {
            DebugTools.log("prof（每次渲染的平均耗时，\(profTicks) 次渲染 / 5 秒）：\n" + Prof.report(frames: profTicks))
            Prof.reset(); profTicks = 0; profSince = mono
        }
    }

    /// 你正在看这个会话吗？（桌面会话：Claude 在最前，且这个会话是最近聚焦的；终端 / VS Code：宿主 App 在最前）
    func isUserLooking(at s: BuddySnapshot) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        switch s.origin {
        case .desktop:
            guard front?.bundleIdentifier == JumpService.claudeBundleID, let h = s.hostSessionId else { return false }
            return DesktopMeta.cache.isMostRecentlyFocused(host: h)          // 带 1 秒缓存：不在主线程上每个 tick 都重读全部元数据文件
        case .vscode: return front?.bundleIdentifier == "com.microsoft.VSCode"
        case .terminal:
            guard let pid = s.pid, let host = JumpService.shared.hostApp(of: pid) else { return false }
            return front?.processIdentifier == host.processIdentifier
        }
    }

    // MARK: 动作
    /// 点办公室里的座位：只认在场的会话（下班工位 / 空座位 / 悬空的座位号什么都不发生）。
    func jump(seat: Int) { if let s = JumpResolver.snapshot(forSeat: seat, in: snapshots) { jump(snapshot: s) } }
    /// 跳到这个会话：按 key 重新找最新的那份快照（拿到的可能是几十毫秒前的；会话已经走了就什么都不做）。
    func jump(snapshot s: BuddySnapshot) {
        guard let fresh = JumpResolver.snapshot(forKey: s.key, in: snapshots) else { return }
        if demo { NSLog("%@", "demo: 跳转到 \(fresh.title)"); return }
        JumpService.shared.jump(to: fresh)
        provider.markSeen(key: fresh.key)
    }
    /// 点通知 / 提示卡：合并提醒（「N 位同事在等你」）没有对应的会话，打开办公室；认得的 key 跳过去。
    func handleNotificationClick(key: String) {
        switch JumpResolver.notificationClick(key: key, in: snapshots) {
        case .openOffice: showOffice()
        case .jump(let k): if let s = JumpResolver.snapshot(forKey: k, in: snapshots) { jump(snapshot: s) }
        case .nothing: break
        }
    }

    func showContextMenu(seat: Int?, event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        if let seat = seat, let s = JumpResolver.snapshot(forSeat: seat, in: snapshots) {
            menu.addItem(ClosureMenuItem("跳转到「\(AlertText.title(s.title, privacy: privacy))」") { [weak self] in self?.jump(snapshot: s) })
            menu.addItem(ClosureMenuItem("换个造型") { [weak self] in self?.provider.rerollAppearance(key: s.key); self?.director.reroll(key: s.key) })
            menu.addItem(ClosureMenuItem("隐藏这个 buddy") { [weak self] in
                guard let self = self else { return }
                var h = self.settings.hiddenKeys; h.insert(s.key); self.settings.hiddenKeys = h
            })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("打开办公室") { [weak self] in self?.showOffice() })
        if !settings.hiddenKeys.isEmpty { menu.addItem(ClosureMenuItem("显示被隐藏的 buddy") { [weak self] in self?.settings.hiddenKeys = [] }) }
        menu.addItem(ClosureMenuItem("设置…") { [weak self] in self?.showSettings() })
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func setDemo(_ on: Bool) {
        guard on != demo else { return }
        stopProvider(provider, demo)
        demo = on
        gotData = false              // 换了数据源：新数据到来之前不显示「今天还没人上班」（原来 gotData 一直是 true，会闪一下那块牌子）
        snapshots = []
        provider = on ? makeDemoProvider() : makeRealProvider(args)
        wire(provider)
        provider.start()
    }

    // MARK: 诊断 / 测试
    /// 数据源诊断：数据层的 diagnostics() 是对 ingest 队列的 queue.sync（等一次 poll），放到后台取，取到之后在主线程拼文字、回填。
    func diagnosticsText(_ completion: @escaping (String) -> Void) {
        let p = provider
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let d = p.diagnostics()
            DispatchQueue.main.async {
                guard let self = self else { return }
                completion(DiagnosticsFormatter.text(d, notifierStatus: self.notifier.statusText,
                                                     deepLinkDisabled: JumpService.shared.deepLinkDisabled, deepLinkFailures: JumpService.shared.deepLinkFailures,
                                                     privacy: self.privacy))
            }
        }
    }

    func testNotification() {
        notifier.requestAuthorizationIfNeeded()
        notifier.post(key: "test", kind: .info, title: "Buddy 办公室", body: "这是一条测试提醒", sound: settings.string("notify.sound"))
    }

    func testDeepLink() -> String {
        guard let s = snapshots.first(where: { $0.origin == .desktop && $0.presence == .present }) else { return "没有在场的桌面 App 会话可以测试。" }
        JumpService.shared.jump(to: s)
        return Self.deepLinkReceipt(title: s.title, privacy: privacy)
    }

    /// 「测试深链」的回执：隐私模式下不写会话标题（共享屏幕时打开设置页不能露标题）。
    static func deepLinkReceipt(title: String, privacy: Bool) -> String {
        "已向「\(privacy ? "会话" : title)」发出深链跳转；2.5 秒后如果没生效会自动改为直接打开 Claude。"
    }
}
