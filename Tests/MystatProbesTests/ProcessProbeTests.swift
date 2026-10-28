import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

/// libproc okuyucusu bu makinede (spec §9.1 Süreçler).
@Suite(.serialized) struct ProcessProbeTests {
    @Test func ownProcessIsFullyReadable() throws {
        let me = try #require(ProcessProbe().processes().first { $0.pid == getpid() })
        #expect(!me.restricted && me.uid == getuid())
        #expect(me.cwd != nil && !me.args.isEmpty && me.path != nil)
        #expect(me.footprint > 1_000_000)
    }

    /// Başka kullanıcının süreci: yalnızca yol okunur, sayaçlar yok (root yardımcısı yok, spec §10).
    @Test func launchdIsRestrictedButNamed() throws {
        let l = try #require(ProcessProbe().processes().first { $0.pid == 1 })
        #expect(l.restricted && l.cwd == nil && l.cpuTime == 0)
        #expect(l.path == "/sbin/launchd" && l.name == "launchd")
    }

    /// Apple Silicon'da rusage süreleri Mach birimidir; çevrilmezse ~41 kat sapar.
    @Test func ownProcessBusyLoopIsAboutOneCore() throws {
        let probe = ProcessProbe()
        var m = ProcessMeter()
        _ = m.update(probe.processes(), at: Date())
        let until = Date().addingTimeInterval(0.5)
        var x = 0.0
        while Date() < until { x += sin(x) }
        let measured = m.update(probe.processes(), at: Date())
        let cores = try #require(measured?[getpid()])
        #expect(cores > 0.6 && cores < 4, "ölçülen \(cores) çekirdek, x=\(x)")
    }

    @Test func listeningPortIsFound() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0,
                               sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        #expect(listen(fd, 1) == 0)
        var bound = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        let port = Int(UInt16(bigEndian: bound.sin_port))
        #expect(ProcessProbe().listeningPorts(pids: [getpid()])[getpid()]?.contains(port) == true)
    }
    /// Proje kökü cwd'den yukarı en yakın `.git`; terminal ortamdaki `TERM_PROGRAM`.
    @Test func projectRootAndTerminal() throws {
        let me = try #require(ProcessProbe().processes().first { $0.pid == getpid() })
        let cwd = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: cwd + "/.git") { #expect(me.projectRoot == cwd) }
        if let t = ProcessInfo.processInfo.environment["TERM_PROGRAM"] { #expect(me.terminal == ProcessProbe.terminalName(t)) }
        #expect(ProcessProbe.terminalName("Apple_Terminal") == "Terminal" && ProcessProbe.terminalName("ghostty") == "Ghostty")
        #expect(ProcessProbe.terminalName("iTerm.app") == "iTerm2" && ProcessProbe.terminalName("vscode") == "VS Code")
    }
}
