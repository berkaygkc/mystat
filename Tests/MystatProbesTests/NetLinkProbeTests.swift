import Foundation
import MystatCore
import Testing
@testable import MystatProbes

@Suite struct NetLinkProbeTests {
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// The router is the gateway in `route -n get default`; the first DNS is the first server of the first resolver in `scutil --dns`.
    @Test func readMatchesSystem() throws {
        guard let link = NetLinkProbe.read() else { return }   // no primary interface: nothing to check
        let gw = Self.run("/sbin/route", ["-n", "get", "default"]).split(separator: "\n")
            .first { $0.contains("gateway:") }.map { $0.split(separator: ":").last!.trimmingCharacters(in: .whitespaces) }
        #expect(link.router == gw)
        let ns = Self.run("/usr/sbin/scutil", ["--dns"]).split(separator: "\n")
            .first { $0.contains("nameserver[0]") }.map { $0.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces) }
        #expect(link.dns.first == ns)
        #expect(!link.bsdName.isEmpty); #expect(!link.displayName.contains("-"))   // non-breaking hyphen
        // macOS sometimes reports the signal as 0 dBm (unknown); the card then shows "—".
        if let w = link.wifi { #expect(w.rssi <= 0); #expect([2.4, 5, 6].contains(w.bandGHz)) }
    }

    @Test func pingLoopback() throws {
        let ms = try #require(RouterPing.ping("127.0.0.1"))
        #expect(ms >= 0 && ms < 10)
    }

    @Test func pingTimeout() {
        let t0 = Date()
        #expect(RouterPing.ping("192.0.2.1", timeout: 0.3) == nil)   // TEST-NET-1: no reply will come
        #expect(Date().timeIntervalSince(t0) < 0.6)
    }

    @Test func pingRejectsGarbage() {
        #expect(RouterPing.ping("yönlendirici") == nil)
        #expect(RouterPing.ping("") == nil)
    }
}
