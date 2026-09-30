import Testing
import AppKit
@testable import BuddyOffice

/// B-010（P1）：FloatingPanel（提示卡 / 悬停卡 / 小鱼缸 / 宠物条）必须关掉 AppKit 的窗口出现 / 消失动画。
/// 这些面板被反复 setFrameOrigin（提示卡 60 Hz 滑动、悬停卡每个 tick 定位），AppKit 的 order-in / order-out 动画在 GCD 工作线程上跑
/// `-[NSAnimation _runBlocking]`，永远不返回——每弹一张提示卡就永久占住一个线程（replay 长跑里线程数 14 → 53）。
/// 只建面板、不 orderFront（不弹任何窗口）。
@MainActor @Suite struct PanelAnimationTests {
    @Test func everyFloatingPanelHasWindowAnimationsTurnedOff() {
        #expect(FloatingPanel(size: NSSize(width: 100, height: 50)).animationBehavior == .none)
        #expect(FloatingPanel(size: NSSize(width: 100, height: 50), level: .statusBar).animationBehavior == .none)
        #expect(HoverPanelController().panel.animationBehavior == .none, "悬停卡片")
        #expect(ToastController.Toast(key: "t").panel.animationBehavior == .none, "提示卡")
        #expect(TankPanelController().panel.animationBehavior == .none, "小鱼缸")
        #expect(StripPanelController().panel.animationBehavior == .none, "桌面宠物条")
        // 小鱼缸面板按名字让 AppKit 自动记位置：别在测试宿主进程的偏好域（~/Library/Preferences/swiftpm-testing-helper.plist）里留痕迹
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame BuddyOfficeTankPanel")
    }

    /// 反复 setFrame 又 order 的窗口只有 FloatingPanel 一族：源码里没有别的 NSWindow 在反复 setFrame（办公室窗口 / 设置窗口只在用户操作时 order）。
    @Test func noWindowOtherThanTheFloatingPanelsIsRepeatedlyReframed() throws {
        for (name, text) in try SourceAudit.allOfficeSources() {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.range(of: #"\.setFrame\("#, options: .regularExpression) != nil && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                Issue.record("\(name):\(i + 1) NSWindow.setFrame(_:display:animate:) 会触发窗口动画：\(line)")
            }
        }
        // 办公室窗口 / 设置窗口不是 FloatingPanel，只在用户操作 / 设置变化时 order（applySettings 只处理变化的项，见 A-003）
        let office = try SourceAudit.read("OfficeWindowController.swift")
        #expect(!office.contains("setContentSize") && !office.contains("setFrameOrigin"))
    }
}
