import Foundation
import MystatCore
import MystatProbes
import MystatTestSupport
import Testing

/// Durdur / Zorla kapat gerçek sinyal gönderir (spec §7.4); yalnızca kullanıcının kendi süreçlerine.
@Suite(.language("tr")) struct ProcessActionsTests {
    @Test func terminatesOwnChild() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        #expect(ProcessActions.signal([p.processIdentifier], force: false) == .done(count: 1))
        let deadline = Date().addingTimeInterval(1)
        while p.isRunning, Date() < deadline { usleep(10_000) }
        #expect(!p.isRunning)
        #expect(p.terminationReason == .uncaughtSignal && p.terminationStatus == SIGTERM)
    }

    @Test func refusesForeignUID() {
        #expect(ProcessActions.signal([1], force: false) == .notPermitted(reason: StopOutcome.foreignReason))
        #expect(kill(1, 0) == 0 || errno == EPERM)   // launchd yaşıyor
    }

    /// Grupta tek bir yabancı süreç varsa kendi süreçlere de sinyal gitmez.
    @Test func mixedGroupSendsNothing() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { kill(p.processIdentifier, SIGKILL) }
        #expect(ProcessActions.signal([p.processIdentifier, 1], force: true) == .notPermitted(reason: StopOutcome.foreignReason))
        usleep(100_000)
        #expect(p.isRunning)
    }

    @Test func goneProcessIsNotFound() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        #expect(ProcessActions.signal([p.processIdentifier], force: false) == .notFound)
    }
}
