import Testing
import Foundation
import UserNotifications
@testable import BuddyOffice

/// B-3：DESIGN §2 M0 写的是「授权请求放到用户第一次主动打开办公室窗口的时候发」，原来只有设置页的按钮会请求。拒绝后不再反复弹。
@MainActor @Suite struct NotificationAuthTests {
    static func make(_ status: UNAuthorizationStatus, available: Bool = true, defaults: UserDefaults? = nil) -> (NotificationService, FakeCenter, Fx.Store) {
        let store = Fx.Store()
        let center = FakeCenter(status: status)
        let n = NotificationService(client: center, toast: FakeToast(), playSound: { _, _ in }, available: available, defaults: defaults ?? store.defaults)
        return (n, center, store)
    }

    @Test func theFirstActiveOpenOfTheOfficeAsksExactlyOnce() {
        let (n, c, store) = Self.make(.notDetermined); defer { store.cleanUp() }
        n.officeMayHaveOpened(appActive: { true }, officeVisible: { true })
        #expect(c.requests == 1)
        // 用户答复了（这里是「不允许」）：之后再怎么打开办公室都不再弹
        for _ in 0..<5 { n.officeMayHaveOpened(appActive: { true }, officeVisible: { true }) }
        #expect(c.requests == 1)
        #expect(n.status == .denied)
    }

    /// 后台启动（hook 用 open -g 拉起）：App 不在前台，不问；等用户真的点开办公室（App 变成前台）再问。
    @Test func aBackgroundLaunchDoesNotAskUntilTheAppIsInFront() {
        let (n, c, store) = Self.make(.notDetermined); defer { store.cleanUp() }
        n.officeMayHaveOpened(appActive: { false }, officeVisible: { true })
        n.officeMayHaveOpened(appActive: { true }, officeVisible: { false })
        #expect(c.requests == 0)
        n.officeMayHaveOpened(appActive: { true }, officeVisible: { true })
        #expect(c.requests == 1)
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .authorized, .provisional])
    func alreadyAnsweredNeverAsksAgain(status: UNAuthorizationStatus) {
        let (n, c, store) = Self.make(status); defer { store.cleanUp() }
        for _ in 0..<3 { n.officeMayHaveOpened(appActive: { true }, officeVisible: { true }) }
        #expect(c.requests == 0)
    }

    @Test func notAnAppBundleNeverTouchesTheNotificationCenter() {
        let (n, c, store) = Self.make(.notDetermined, available: false); defer { store.cleanUp() }
        n.officeMayHaveOpened(appActive: { true }, officeVisible: { true })
        n.requestAuthorizationIfNeeded()
        #expect(c.requests == 0)
        #expect(n.statusText == "不可用（不是 App 包）")
    }

    /// 问过一次就记下来：即使系统里状态还是「没问过」（比如上次弹窗没答复就退出了），也不会每次启动都弹。设置页的按钮不受这个限制。
    @Test func theAskedFlagSurvivesARestartButTheSettingsButtonStillWorks() {
        let store = Fx.Store(); defer { store.cleanUp() }
        let (first, c1, _) = Self.make(.notDetermined, defaults: store.defaults)
        first.officeMayHaveOpened(appActive: { true }, officeVisible: { true })
        #expect(c1.requests == 1)
        c1.statusAfterRequest = .notDetermined; c1.status = .notDetermined                 // 弹窗没答复
        let (second, c2, _) = Self.make(.notDetermined, defaults: store.defaults)          // 「重启」：新的实例，同一份偏好
        second.officeMayHaveOpened(appActive: { true }, officeVisible: { true })
        #expect(c2.requests == 0, "自动的那条路：问过就不再问")
        second.requestAuthorizationIfNeeded()
        #expect(c2.requests == 1, "设置页的按钮：用户主动点的，照发")
    }

    @Test func theDecisionFunction() {
        typealias N = NotificationService
        #expect(N.shouldRequestOnOfficeOpen(status: .notDetermined, alreadyAsked: false, appActive: true, officeVisible: true, available: true))
        #expect(!N.shouldRequestOnOfficeOpen(status: .denied, alreadyAsked: false, appActive: true, officeVisible: true, available: true))
        #expect(!N.shouldRequestOnOfficeOpen(status: .notDetermined, alreadyAsked: true, appActive: true, officeVisible: true, available: true))
        #expect(!N.shouldRequestOnOfficeOpen(status: .notDetermined, alreadyAsked: false, appActive: false, officeVisible: true, available: true))
        #expect(!N.shouldRequestOnOfficeOpen(status: .notDetermined, alreadyAsked: false, appActive: true, officeVisible: false, available: true))
        #expect(!N.shouldRequestOnOfficeOpen(status: .notDetermined, alreadyAsked: false, appActive: true, officeVisible: true, available: false))
    }
}
