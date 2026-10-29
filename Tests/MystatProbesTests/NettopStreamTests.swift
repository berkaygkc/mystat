import Darwin
import Foundation
import MystatCore
import Synchronization
import Testing
@testable import MystatProbes

final class SampleLog: Sendable {
    let samples = Mutex<[[Int32: NetBytes]]>([])
    var count: Int { samples.withLock { $0.count } }
}

@Suite struct NettopStreamTests {
    static func waitUntil(_ seconds: Double, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return true }; usleep(50_000) }
        return cond()
    }

    static func children(of pid: pid_t) -> [pid_t] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-P", String(pid)]
        let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap { pid_t($0) }
    }

    @Test func streamsSamples() throws {
        let log = SampleLog()
        let s = NettopStream(intervalSeconds: 1) { sample in log.samples.withLock { $0.append(sample) } }
        #expect(s.start())
        let pid = try #require(s.processID)
        #expect(Self.waitUntil(12) { log.count >= 1 })
        #expect(log.samples.withLock { $0.first?.isEmpty == false })   // en az kernel_task satırı
        s.stop()
        #expect(!s.isRunning)
        #expect(Self.waitUntil(2) { kill(pid, 0) == -1 && errno == ESRCH })
    }

    /// Terminale bağlı nettop 1,4 çekirdek yiyor (ölçüldü): çıktı boruya gider, denetim terminali yok.
    @Test func runsWithoutTerminal() throws {
        let s = NettopStream { _ in }
        #expect(s.start())
        defer { s.stop() }
        let pid = try #require(s.processID)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "tty=,comm=", "-p", String(pid)]
        let out = Pipe(); p.standardOutput = out
        try p.run(); p.waitUntilExit()
        let line = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(line.hasPrefix("??"), "\(line)")
        #expect(line.contains("nettop"), "\(line)")
    }

    @Test func missingExecutable() {
        let s = NettopStream(executable: "/yok/nettop") { _ in }
        #expect(!s.start()); #expect(!s.isRunning)
    }

    @Test func stopIsIdempotent() {
        let s = NettopStream { _ in }
        s.stop(); s.stop()
        #expect(!s.isRunning)
    }

    @Test func exitedProcessReported() {
        let s = NettopStream(executable: "/usr/bin/true") { _ in }
        #expect(s.start())
        #expect(Self.waitUntil(3) { !s.isRunning })
    }
}
