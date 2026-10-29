import Darwin
import Foundation
import MystatCore
import Synchronization

/// Uygulama bazında ağ (spec §9.1, §9.2): Ağ bölümü açıkken tek bir `nettop` süreci akar.
/// - Borudan okununca `nettop` çıktısını tamponluyor (13 sn'de tek satır gelmedi).
/// - Doğrudan bir pty'ye bağlanınca denetim terminali olmuyor; uygulama çökerse `nettop` sonsuza kadar yaşıyor.
/// - Bu yüzden `script -q /dev/null nettop …`: `script` pty'yi `nettop`'un denetim terminali yapar ve çıktıyı
///   anında boruya yazar. Biz ölünce `script` SIGPIPE ile, `nettop` da SIGHUP ile ≈ 2 sn içinde biter (ölçüldü).
/// Okuma ayrı bir iş parçacığında; `script` bitince (EOF) iş parçacığı onu toplar.
public final class NettopStream: Sendable {
    private final class Shared: Sendable {
        struct State { var pid: pid_t = 0; var running = false }
        let state = Mutex(State())
    }

    static let script = "/usr/bin/script"
    private let shared = Shared()
    private let interval: Int
    private let executable: String
    private let onSample: @Sendable ([Int32: NetBytes]) -> Void

    /// `onSample` örnek başına (≈ `intervalSeconds`) okuma iş parçacığından çağrılır.
    public init(intervalSeconds: Int = 2, executable: String = "/usr/bin/nettop",
                onSample: @escaping @Sendable ([Int32: NetBytes]) -> Void) {
        self.interval = max(1, intervalSeconds); self.executable = executable; self.onSample = onSample
    }

    deinit { stop() }

    public var isRunning: Bool { shared.state.withLock { $0.running } }
    var processID: pid_t? { shared.state.withLock { $0.running ? $0.pid : nil } }

    /// Süreç başlatılamazsa false.
    public func start() -> Bool {
        if isRunning { return true }
        guard access(executable, X_OK) == 0 else { return false }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return false }
        let (readEnd, writeEnd) = (fds[0], fds[1])
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Kendi oturumu; bizim diğer tanımlayıcılarımız çocuğa geçmez.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let args = [Self.script, "-q", "/dev/null", executable, "-P", "-L", "0", "-s", String(interval), "-d", "-J", "bytes_in,bytes_out", "-x"]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = ["PATH=/usr/bin:/bin", "LC_ALL=C"].map { (s: String) in strdup(s) } + [nil]   // sayı biçimi sabit
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, Self.script, &actions, &attr, &argv, &envp)
        close(writeEnd)
        guard rc == 0 else { close(readEnd); return false }
        shared.state.withLock { $0 = .init(pid: pid, running: true) }

        let shared = shared, onSample = onSample
        let reader = Thread {
            var parser = NettopParser()
            var pending: [UInt8] = []
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(readEnd, &buf, buf.count)
                if n <= 0 { if n < 0, errno == EINTR { continue }; break }   // EOF: script bitti
                pending.append(contentsOf: buf[0..<n])
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[..<nl], as: UTF8.self)
                    pending.removeSubrange(...nl)
                    if let sample = parser.feed(Substring(line)) { onSample(sample) }
                }
            }
            close(readEnd)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0, errno == EINTR {}
            shared.state.withLock { $0.running = false }
        }
        reader.qualityOfService = .utility
        reader.start()
        return true
    }

    /// `script`'e SIGTERM (pty'si kapanır, `nettop` SIGHUP ile biter); 1 sn içinde bitmezse SIGKILL. Okuma iş parçacığı süreci toplayana kadar bekler (en çok ≈ 2 sn).
    public func stop() {
        let pid = shared.state.withLock { $0.running ? $0.pid : 0 }
        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        if !waitStopped(seconds: 1) { kill(pid, SIGKILL); _ = waitStopped(seconds: 1) }
    }

    private func waitStopped(seconds: Double) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !isRunning { return true }
            usleep(10_000)
        }
        return !isRunning
    }
}

/// Uygulama bazında ağ akışı (testlerde sahtesi kullanılır).
public protocol NetStream: AnyObject, Sendable {
    var isRunning: Bool { get }
    func stop()
}

extension NettopStream: NetStream {}
