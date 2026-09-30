import SwiftUI
import AppKit
import BuddyCore

/// 设置窗口里的 SwiftUI 表单。所有项直接绑定到 UserDefaults（键名见任务书 7.5），AppModel 监听变化后应用。
struct SettingsView: View {
    let model: AppModel
    @AppStorage("office.visible") var officeVisible = true
    @AppStorage("office.zoom") var officeZoom = 0
    @AppStorage("tank.visible") var tankVisible = false
    @AppStorage("tank.zoom") var tankZoom = 2
    @AppStorage("tank.opacity") var tankOpacity = 1.0
    @AppStorage("strip.visible") var stripVisible = false
    @AppStorage("strip.zoom") var stripZoom = 2
    @AppStorage("strip.align") var stripAlign = "right"
    @AppStorage("strip.level") var stripLevel = "floating"
    @AppStorage("strip.fullscreen") var stripFullscreen = false
    @AppStorage("strip.screen") var stripScreen = "main"
    @AppStorage("ui.menuBarIcon") var menuBarIcon = true
    @AppStorage("ui.dockIcon") var dockIcon = true
    @AppStorage("ui.labels") var labels = "always"
    @AppStorage("notify.permission") var nPermission = true
    @AppStorage("notify.question") var nQuestion = true
    @AppStorage("notify.finished") var nFinished = true
    @AppStorage("notify.finishedMinSeconds") var nMinSeconds = 30
    @AppStorage("notify.includeDesktop") var nDesktop = true
    @AppStorage("notify.suppressWhenFocused") var nSuppress = true
    @AppStorage("notify.error") var nError = false
    @AppStorage("notify.sound") var nSound = "8bit"
    @AppStorage("idle.dozeMinutes") var dozeMin = 10
    @AppStorage("idle.sleepMinutes") var sleepMin = 45
    @AppStorage("dormant.max") var dormantMax = 4
    @AppStorage("dormant.recentHours") var dormantHours = 3
    @AppStorage("privacy.hideDetails") var privacy = false
    @AppStorage("autoQuitWithClaude") var autoQuit = true
    @AppStorage("login.enabled") var loginEnabled = false
    @AppStorage("hotkey.enabled") var hotkey = false
    @State var loginNote = ""
    @State var diag = ""
    @State var authText = "…"
    /// 开发自检用：--dump-settings 会逐页打开。
    nonisolated(unsafe) static var initialTab = 0
    @State var tab = SettingsView.initialTab

    /// 系统通知授权状态：读一次系统里的真实状态再显示（NotificationService.status 不是被观察的状态，不会自己刷新）。
    func refreshAuth() { model.notifier.refresh { _ in authText = model.notifier.statusText } }

    var body: some View {
        TabView(selection: $tab) {
            Form {
                Section("办公室窗口") {
                    Toggle("显示办公室窗口", isOn: $officeVisible)
                    Picker("缩放", selection: $officeZoom) { Text("自动").tag(0); ForEach(1...5, id: \.self) { Text("\($0) 倍").tag($0) } }
                    Picker("桌牌文字", selection: $labels) { Text("总是显示").tag("always"); Text("悬停时显示").tag("hover"); Text("关闭").tag("off") }
                }
                Section("小鱼缸（置顶小窗）") {
                    Toggle("显示小鱼缸", isOn: $tankVisible)
                    Picker("缩放", selection: $tankZoom) { Text("1 倍").tag(1); Text("2 倍").tag(2) }
                    HStack { Text("不透明度"); Slider(value: $tankOpacity, in: 0.4...1) }
                }
                Section("桌面宠物（屏幕底部、Dock 上方）") {
                    Toggle("显示桌面宠物", isOn: $stripVisible)
                    Picker("缩放", selection: $stripZoom) { ForEach(1...3, id: \.self) { Text("\($0) 倍").tag($0) } }
                    Picker("位置", selection: $stripAlign) { Text("靠右").tag("right"); Text("居中").tag("center"); Text("靠左").tag("left") }
                    Picker("显示在", selection: $stripScreen) {
                        ForEach(StripScreenPicker.options(current: stripScreen, screens: NSScreen.screens.map(StripPanelController.info)), id: \.tag) { Text($0.title).tag($0.tag) }
                    }
                    Picker("层级", selection: $stripLevel) { Text("浮在窗口上面").tag("floating"); Text("桌面层").tag("desktop") }
                    Toggle("在全屏 App 里也显示", isOn: $stripFullscreen)
                }
                Section("入口") {
                    Toggle("菜单栏图标", isOn: $menuBarIcon)
                    Toggle("Dock 图标", isOn: $dockIcon)
                    Toggle("全局快捷键 ⌃⌥⌘B 开关办公室", isOn: $hotkey)
                }
            }.formStyle(.grouped).tabItem { Text("形态") }.tag(0)

            Form {
                Section("什么时候提醒你") {
                    Toggle("等你批准", isOn: $nPermission)
                    Toggle("有问题问你 / 计划待审", isOn: $nQuestion)
                    Toggle("一轮做完了", isOn: $nFinished)
                    Stepper("做完提醒的最短用时：\(nMinSeconds) 秒", value: $nMinSeconds, in: 5...600, step: 5)
                    Toggle("出错时也提醒", isOn: $nError)
                    Toggle("桌面 App 里的会话也提醒（Claude 自己也可能发通知，可能重复）", isOn: $nDesktop)
                    Toggle("你正在看那个会话时不提醒", isOn: $nSuppress)
                    Picker("提示音", selection: $nSound) { Text("8-bit").tag("8bit"); Text("系统提示音").tag("system"); Text("无").tag("none") }
                }
                Section("系统通知") {
                    Text("授权状态：\(authText)").foregroundStyle(.secondary)
                    HStack {
                        Button("请求通知授权") { model.notifier.requestAuthorizationIfNeeded { refreshAuth() } }
                        Button("打开系统通知设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                        Button("发一条测试提醒") { model.testNotification() }
                    }
                    Text("没授权时，会用屏幕右上角的像素提示面板 + Dock 角标 + 菜单栏图标提醒。").font(.footnote).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Text("提醒") }.tag(1)

            Form {
                Section("空闲") {
                    Stepper("空闲多久后打盹：\(dozeMin) 分钟", value: $dozeMin, in: 1...120)
                    Stepper("空闲多久后睡着：\(sleepMin) 分钟", value: $sleepMin, in: 2...240)
                }
                Section("下班工位") {
                    Stepper("最多保留：\(dormantMax) 个", value: $dormantMax, in: 0...8)
                    Stepper("启动时只显示最近 \(dormantHours) 小时内的会话", value: $dormantHours, in: 1...24)
                    Text("以上四项在下次启动 Buddy 办公室后生效（「最多保留」调小会立刻生效）。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("其他") {
                    Toggle("隐私模式（隐藏全部细节）", isOn: $privacy)
                    Toggle("跟着 Claude 一起收（Claude 退出且没有会话后 60 秒自动退出）", isOn: $autoQuit)
                    Toggle("开机启动", isOn: Binding(get: { loginEnabled }, set: { on in let r = LoginItem.set(on); loginNote = r.note; loginEnabled = r.isOn }))     // 开启失败时开关回退成关
                    if !loginNote.isEmpty { Text(loginNote).font(.footnote).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped).tabItem { Text("其他") }.tag(2)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据源诊断").font(.headline)
                    Text(diag.isEmpty ? "点一下「刷新」" : diag).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("刷新") { model.diagnosticsText { diag = $0 } }
                        Button("测试深链（跳到当前会话）") { diag = model.testDeepLink() }
                        Button("重新启用深链") { JumpService.shared.resetDeepLink(); model.diagnosticsText { diag = $0 } }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.tabItem { Text("数据源诊断") }.tag(3)
        }
        .frame(width: 560, height: 520)
        .onAppear {
            model.diagnosticsText { diag = $0 }
            refreshAuth()
            loginEnabled = LoginItem.isOn            // 和系统里的真实状态对一下（用户可能在系统设置里关掉了登录项）
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let host = NSHostingController(rootView: SettingsView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "Buddy 办公室 · 设置"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }
}
