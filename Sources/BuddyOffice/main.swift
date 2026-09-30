import AppKit

// 卸载脚本用：先让 App 自己注销开机启动项（登录项 / LaunchAgent），再删除 App。
if CommandLine.arguments.contains("--unregister-login") { print(LoginItem.set(false).note); exit(0) }
if CommandLine.arguments.contains("--version") {
    print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"); exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
