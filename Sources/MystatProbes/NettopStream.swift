import Darwin
import Foundation
import MystatCore
import Synchronization

/// Uygulama bazında ağ (spec §9.1, §9.2): Ağ bölümü açıkken kısa `nettop -P -c -L 2 -s <aralık> -d` çalıştırmaları arka
/// arkaya koşar; her biri bir delta örneği verip kendiliğinden biter. Ölçülenler (2026-10-29):
/// - Terminale bağlı `nettop` (`-c` olsa da) ≈ 1,4 çekirdek yiyor; boruya yazınca ≈ 0,01 çekirdek.
/// - Sürekli akan `nettop` boruda çıktıyı tamponluyor (örnekler 10 sn'den geç geliyor) ve `-c` olmadan pahalı.
/// - Kısa çalıştırmanın sabit ≈ 4 sn başlangıç gecikmesi var: örnek ≈ 5 sn'de bir, her biri ≈ 0,09 sn işlemci.
/// Bir çalıştırma en çok birkaç saniye yaşar; uygulama çökse de geride `nettop` kalmaz (boruya yazınca SIGPIPE).
public final class NettopStream: Sendable {
    private final class Shared: Sendable {
        struct State { var pid: pid_t = 0; var running = false; var stopping = false }
        let state = Mutex(State())
    }

    private let shared = Shared()
    private let interval: Int
    private let executable: String
    private let onSample: @Sendable ([Int32: NetBytes]) -> Void

    /// `onSample` her çalıştırmanın sonunda (≈ 5 sn) okuma iş parçacığından çağrılır.
    public init(intervalSeconds: Int = 2, executable: String = "/usr/bin/nettop",
                onSample: @escaping @Sendable ([Int32: NetBytes]) -> Void) {
        self.interval = max(1, intervalSeconds); self.executable = executable; self.onSample = onSample
    }

    deinit { stop() }

    public var isRunning: Bool { shared.state.withLock { $0.running } }
    /// O anki `nettop` çalıştırmasının pid'i.
    var processID: pid_t? { shared.state.withLock { $0.running && $0.pid > 0 ? $0.pid : nil } }

    /// İlk çalıştırma başlatılamazsa false.
    public func start() -> Bool {
        if isRunning { return true }
        guard access(executable, X_OK) == 0, let first = Self.spawn(executable, interval) else { return false }
        shared.state.withLock { $0 = .init(pid: first.pid, running: true, stopping: false) }
        let shared = shared, onSample = onSample, executable = executable, interval = interval
        let reader = Thread {
            var run: (pid: pid_t, fd: Int32)? = first
            while let r = run {
                let produced = Self.drain(r.fd, onSample)
                close(r.fd)
                var status: Int32 = 0
                while waitpid(r.pid, &status, 0) < 0, errno == EINTR {}
                run = nil
                // Durduruldu ya da örnek çıkmadı (nettop çalışmıyor): döngü biter, yeniden denenmez.
                guard produced, !shared.state.withLock({ $0.stopping }), let next = Self.spawn(executable, interval) else { break }
                let go = shared.state.withLock { s -> Bool in
                    guard !s.stopping else { return false }
                    s.pid = next.pid
                    return true
                }
                if go { run = next } else { kill(next.pid, SIGTERM); close(next.fd); while waitpid(next.pid, &status, 0) < 0, errno == EINTR {} }
            }
            shared.state.withLock { $0.running = false; $0.pid = 0 }
        }
        reader.qualityOfService = .utility
        reader.start()
        return true
    }

    /// O anki çalıştırmaya SIGTERM, 1 sn içinde bitmezse SIGKILL; döngü durur.
    public func stop() {
        let pid = shared.state.withLock { s -> pid_t in
            guard s.running else { return 0 }
            s.stopping = true
            return s.pid
        }
        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        if !waitStopped(seconds: 1) {
            if let p = shared.state.withLock({ $0.running ? $0.pid : nil }) { kill(p, SIGKILL) }
            _ = waitStopped(seconds: 1)
        }
    }

    private func waitStopped(seconds: Double) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !isRunning { return true }
            usleep(10_000)
        }
        return !isRunning
    }

    /// Çıktısı boruya giden bir `nettop` çalıştırması (terminal yok).
    private static func spawn(_ executable: String, _ interval: Int) -> (pid: pid_t, fd: Int32)? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))   // bizim diğer tanımlayıcılarımız geçmez
        let args = [executable, "-P", "-c", "-L", "2", "-s", String(interval), "-d", "-J", "bytes_in,bytes_out", "-x"]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = ["PATH=/usr/bin:/bin", "LC_ALL=C"].map { (s: String) in strdup(s) } + [nil]   // sayı biçimi sabit
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attr, &argv, &envp)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); return nil }
        return (pid, fds[0])
    }

    /// Çalıştırmanın çıktısını sonuna kadar okur; örnek çıktıysa true.
    private static func drain(_ fd: Int32, _ onSample: @Sendable ([Int32: NetBytes]) -> Void) -> Bool {
        var parser = NettopParser()
        var pending: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 8192)
        var produced = false
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { if n < 0, errno == EINTR { continue }; break }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[..<nl], as: UTF8.self)
                pending.removeSubrange(...nl)
                if let sample = parser.feed(Substring(line)) { onSample(sample); produced = true }
            }
        }
        if !pending.isEmpty, let sample = parser.feed(Substring(String(decoding: pending, as: UTF8.self))) { onSample(sample); produced = true }
        if let sample = parser.finish() { onSample(sample); produced = true }
        return produced
    }
}

/// Uygulama bazında ağ akışı (testlerde sahtesi kullanılır).
public protocol NetStream: AnyObject, Sendable {
    var isRunning: Bool { get }
    func stop()
}

extension NettopStream: NetStream {}
