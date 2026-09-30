import Foundation
import Testing
@testable import BuddyCore

@Suite struct IdentityTests {
    final class Clock { var t = Harness.epoch; func now() -> Date { t } }

    func rec(pid: Int32, sid: String, host: String? = nil, start: Date? = Harness.epoch, entry: String? = nil) -> RegistryRecord {
        var r = RegistryRecord(pid: pid, sessionId: sid)
        r.hostSessionId = host
        r.procStart = start
        r.procStartRaw = start.map { TimeUtil.formatProcStart($0) }
        r.entrypoint = entry ?? (host == nil ? "cli" : "claude-desktop")
        return r
    }
    func meta(host: String, cli: String, priors: [String] = []) -> DesktopMeta {
        var m = DesktopMeta(hostSessionId: host); m.cliSessionId = cli; m.priorCliSessionIds = priors; return m
    }
    let none: (String) -> DesktopMeta? = { _ in nil }

    @Test func desktopKeyIsDPrefixPlusHostSessionId() {
        let r = IdentityResolver(path: nil)
        let m = r.resolve(rec(pid: 1, sid: "s1", host: "local_a"), metaLookup: none)
        #expect(m.identity.key == "d:local_a")
        #expect(m.isNew)
        #expect(m.identity.aliases.contains("host:local_a"))
        #expect(m.identity.aliases.contains("sid:s1"))
        #expect(m.identity.aliases.contains { $0.hasPrefix("proc:1@") })
    }

    @Test func terminalKeyIsTPrefixPlusFirstSeenSessionId() {
        let r = IdentityResolver(path: nil)
        let m = r.resolve(rec(pid: 5, sid: "s5"), metaLookup: none)
        #expect(m.identity.key == "t:s5")
    }

    @Test func hostAliasWinsEvenWhenPidAndSessionIdChange() {
        // 桌面 App 回收空闲进程后，用户再打开：新进程、新 sessionId，但同一个 hostSessionId
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 1, sid: "s1", host: "local_a"), metaLookup: none)
        let b = r.resolve(rec(pid: 2, sid: "s2", host: "local_a", start: Harness.at(3600)), metaLookup: none)
        #expect(b.identity.key == a.identity.key)
        #expect(b.kind == .host)
    }

    @Test func desktopPriorCliSessionIdsMapBackViaMetadataWhenHostIsMissing() {
        let r = IdentityResolver(path: nil)
        let m1 = meta(host: "local_a", cli: "s2", priors: ["s1"])
        let first = r.resolve(rec(pid: 1, sid: "s1", host: "local_a"), metaLookup: none)
        // 一个没有 hostSessionId 的新进程带着 s2 出现；桌面元数据说 s2 是 local_a 的当前 CLI 会话
        let second = r.resolve(rec(pid: 9, sid: "s2", host: nil, start: Harness.at(100)), metaLookup: { $0 == "s2" ? m1 : nil })
        #expect(second.identity.key == first.identity.key)
        #expect(second.kind == .desktopMeta)
        // 只有 prior id 也能反查
        let third = r.resolve(rec(pid: 10, sid: "s1", host: nil, start: Harness.at(200)), metaLookup: { $0 == "s1" ? m1 : nil })
        #expect(third.identity.key == first.identity.key)
    }

    @Test func aSessionKnownOnlyToDesktopMetadataBecomesADesktopIdentity() {
        let r = IdentityResolver(path: nil)
        let m = meta(host: "local_z", cli: "sz")
        let x = r.resolve(rec(pid: 3, sid: "sz", host: nil), metaLookup: { $0 == "sz" ? m : nil })
        #expect(x.identity.key == "d:local_z")
    }

    @Test func terminalClearKeepsTheSameBuddyBecauseItIsTheSameProcess() {
        // /clear：同一个进程（pid + 启动时间），登记表里的 sessionId 换了
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 7, sid: "before-clear"), metaLookup: none)
        let b = r.resolve(rec(pid: 7, sid: "after-clear"), metaLookup: none)
        #expect(b.identity.key == a.identity.key)
        #expect(b.kind == .process)
        #expect(a.identity.key == "t:before-clear")               // key 一直是第一次见到的 sessionId
        // 之后新 sessionId 也成了别名
        let c = r.resolve(rec(pid: 99, sid: "after-clear", start: Harness.at(50)), metaLookup: none)
        #expect(c.identity.key == a.identity.key)
        #expect(c.kind == .session)
    }

    @Test func terminalResumeInANewProcessKeepsTheSameBuddyViaSessionAlias() {
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 7, sid: "sess-x"), metaLookup: none)
        // 进程退出，过了一会儿在新进程里 --resume 同一个会话
        let b = r.resolve(rec(pid: 4242, sid: "sess-x", start: Harness.at(7200)), metaLookup: none)
        #expect(b.identity.key == a.identity.key)
        #expect(b.kind == .session)
    }

    @Test func pidReuseWithADifferentStartTimeIsANewBuddy() {
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 7, sid: "one"), metaLookup: none)
        let b = r.resolve(rec(pid: 7, sid: "two", start: Harness.at(9999)), metaLookup: none)   // 同 pid、不同启动时间、不同会话
        #expect(b.identity.key != a.identity.key)
        #expect(b.isNew)
    }

    @Test func withoutProcStartNoProcessAliasIsUsed() {
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 7, sid: "one", start: nil), metaLookup: none)
        #expect(!a.identity.aliases.contains { $0.hasPrefix("proc:") })
        let b = r.resolve(rec(pid: 7, sid: "two", start: nil), metaLookup: none)                // 没法确认是同一个进程
        #expect(b.identity.key != a.identity.key)
    }

    @Test func seatsAreTheSmallestFreeNumberAndReturningBuddiesGetTheirOwnSeatBack() {
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 1, sid: "a"), metaLookup: none).identity.key
        let b = r.resolve(rec(pid: 2, sid: "b"), metaLookup: none).identity.key
        let c = r.resolve(rec(pid: 3, sid: "c"), metaLookup: none).identity.key
        #expect(r.assignSeat(forKey: a, occupied: []) == 0)
        #expect(r.assignSeat(forKey: b, occupied: [0]) == 1)
        #expect(r.assignSeat(forKey: c, occupied: [0, 1]) == 2)
        // b 离场，d 来了：d 坐最小的空位 1
        let d = r.resolve(rec(pid: 4, sid: "d"), metaLookup: none).identity.key
        #expect(r.assignSeat(forKey: d, occupied: [0, 2]) == 1)
        // b 回来了：原来的工位被 d 占了 → 取最小的空位 3；如果没被占就坐回原位
        #expect(r.assignSeat(forKey: b, occupied: [0, 1, 2]) == 3)
        #expect(r.assignSeat(forKey: c, occupied: [0, 1]) == 2)
    }

    @Test func persistenceRoundTripKeepsAliasesSeatAndSalt() {
        let file = TempFile(name: "ident")
        let clock = Clock()
        let r1 = IdentityResolver(path: file.path, now: clock.now)
        let a = r1.resolve(rec(pid: 1, sid: "s1", host: "local_a"), metaLookup: none).identity.key
        _ = r1.assignSeat(forKey: a, occupied: [0])                          // → 1
        #expect(r1.reroll(key: a) == 1)
        r1.saveIfNeeded(force: true)
        #expect(r1.persistenceOK == true)

        let r2 = IdentityResolver(path: file.path, now: clock.now)
        let back = r2.resolve(rec(pid: 50, sid: "brand-new", host: "local_a", start: Harness.at(5000)), metaLookup: none)
        #expect(back.identity.key == a)
        #expect(back.kind == .host)
        #expect(back.identity.salt == 1)                                      // 外观种子盐（含「换个造型」的新盐）
        #expect(r2.assignSeat(forKey: a, occupied: [0]) == 1)                 // 坐回同一个工位
        // 老 sessionId 的别名也在
        #expect(r2.resolve(rec(pid: 51, sid: "s1", start: Harness.at(6000)), metaLookup: none).identity.key == a)
    }

    @Test func identitiesAreForgottenAfterSevenDays() {
        let file = TempFile(name: "ident7")
        let clock = Clock()
        let r1 = IdentityResolver(path: file.path, now: clock.now)
        let a = r1.resolve(rec(pid: 1, sid: "s1", host: "local_a"), metaLookup: none).identity.key
        r1.saveIfNeeded(force: true)
        clock.t = clock.t.addingTimeInterval(6 * 86400)
        #expect(IdentityResolver(path: file.path, now: clock.now).identity(forKey: a) != nil)        // 6 天：还在
        clock.t = clock.t.addingTimeInterval(1.1 * 86400)
        #expect(IdentityResolver(path: file.path, now: clock.now).identity(forKey: a) == nil)        // 超过 7 天：忘掉
    }

    @Test func rerollGivesANewSaltEachTime() {
        let r = IdentityResolver(path: nil)
        let a = r.resolve(rec(pid: 1, sid: "s1"), metaLookup: none).identity.key
        #expect(r.identity(forKey: a)?.salt == 0)
        #expect(r.reroll(key: a) == 1)
        #expect(r.reroll(key: a) == 2)
        #expect(r.reroll(key: "nope") == nil)
    }

    @Test func unwritableIdentityFileDegradesToMemoryOnly() {
        let blocker = TempFile(name: "blocker2")
        blocker.write("x")
        let r = IdentityResolver(path: blocker.path + "/sub/identities.json", now: Clock().now)
        let a = r.resolve(rec(pid: 1, sid: "s1"), metaLookup: none).identity.key       // 内部会试着写盘
        r.saveIfNeeded(force: true)
        #expect(r.persistenceOK == false)
        #expect(r.identity(forKey: a) != nil)                                            // 只在内存里，照常工作
    }

    @Test func corruptIdentityFileIsIgnored() {
        let file = TempFile(name: "corrupt")
        file.write("{ this is not json")
        let r = IdentityResolver(path: file.path, now: Clock().now)
        #expect(r.all.isEmpty)
        #expect(r.resolve(rec(pid: 1, sid: "s"), metaLookup: none).isNew)
    }

    @Test func aliasListIsBounded() {
        let r = IdentityResolver(path: nil)
        var key = ""
        for i in 0..<100 {
            key = r.resolve(rec(pid: 7, sid: "sess-\(i)"), metaLookup: none).identity.key       // 同一个进程反复 /clear
        }
        #expect(key == "t:sess-0")
        #expect((r.identity(forKey: key)?.aliases.count ?? 0) <= IdentityResolver.maxAliases)
    }
}
