import Foundation
import ServiceManagement
import MystatTestSupport
import Testing
@testable import MystatLive

/// Launch at login: registration happens once on first launch; if the user removed it or approval is pending, it is left alone.
@Suite(.language("tr")) struct LoginItemTests {
    @Test func registersOnlyOnceWhenNotRegistered() {
        #expect(LoginItem.shouldRegister(status: .notRegistered, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .notRegistered, alreadyAsked: true))   // the user removed it from Login Items
        #expect(!LoginItem.shouldRegister(status: .enabled, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .requiresApproval, alreadyAsked: false))   // awaiting the user's approval in System Settings
        // For an app that was never registered, macOS 26 returns `.notFound` (measured); that is also the first-registration opportunity.
        #expect(LoginItem.shouldRegister(status: .notFound, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .notFound, alreadyAsked: true))
    }

    /// Only the installed bundle registers; the development bundle under build/ must not change the login item's path.
    @Test func onlyInstalledBundleRegisters() {
        #expect(LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Applications/mystat.app")))
        #expect(LoginItem.isInstalled(URL(fileURLWithPath: "/Applications/mystat.app")))
        #expect(!LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Documents/hobby-projects/mystat/build/mystat.app")))
        #expect(!LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Documents/hobby-projects/mystat/.build/debug")))
    }
}
