import Darwin
import Foundation
import MystatCore
import Synchronization

/// libproc ile süreç listesi (spec §9.1). Root gerektirmez; başka kullanıcıların süreçleri yalnızca yoluyla gelir.
/// Yol, argüman ve çalışma klasörü (pid, başlangıç) anahtarıyla önbellekte; her turda yalnızca sayaçlar okunur.
public final class ProcessProbe: Sendable {
    private struct Key: Hashable { let pid: Int32; let start: Date }
    private struct Static: Sendable { let path: String?; let args: [String]; let cwd: String? }
    private let statics = Mutex<[Key: Static]>([:])
    private let foreignPaths = Mutex<[Int32: String]>([:])

    /// Apple Silicon'da rusage süreleri Mach zaman birimidir (M serisinde 125/3); nanosaniyeye çevrilir.
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var t = mach_timebase_info()
        mach_timebase_info(&t)
        return (UInt64(t.numer), UInt64(max(1, t.denom)))
    }()

    public init() {}

    public func processes() -> [ProcessRecord] {
        let pids = Self.allPids()
        var out: [ProcessRecord] = []
        out.reserveCapacity(pids.count)
        var argBuf = [UInt8](repeating: 0, count: 256 * 1024)
        var seen = Set<Key>(), seenForeign = Set<Int32>()
        for pid in pids where pid >= 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
                seenForeign.insert(pid)
                out.append(foreign(pid))
                continue
            }
            let start = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6)
            let key = Key(pid: pid, start: start)
            seen.insert(key)
            let st = statics.withLock { $0[key] } ?? {
                let s = Static(path: Self.path(pid), args: Self.args(pid, &argBuf), cwd: Self.cwd(pid))
                statics.withLock { $0[key] = s }
                return s
            }()
            var r = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &r) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            } == 0
            let tb = Self.timebase
            let name = Self.string(info.pbi_name).nonEmpty ?? Self.string(info.pbi_comm)
            out.append(ProcessRecord(pid: pid, ppid: Int32(info.pbi_ppid), uid: info.pbi_uid, name: name, path: st.path, args: st.args,
                                     cwd: st.cwd, start: start, hasTTY: info.e_tdev != UInt32.max,
                                     cpuTime: ok ? (r.ri_user_time &+ r.ri_system_time) &* tb.numer / tb.denom : 0,
                                     footprint: ok ? r.ri_phys_footprint : 0, energy: ok ? r.ri_energy_nj : 0,
                                     diskWritten: ok ? r.ri_diskio_byteswritten : 0))
        }
        statics.withLock { d in d = d.filter { seen.contains($0.key) } }
        foreignPaths.withLock { d in d = d.filter { seenForeign.contains($0.key) } }
        return out
    }

    /// Başka kullanıcının süreci: yalnızca yol (önbellekte), sayaç yok.
    private func foreign(_ pid: Int32) -> ProcessRecord {
        let path = foreignPaths.withLock { $0[pid] } ?? {
            let p = Self.path(pid) ?? (pid == 0 ? "kernel_task" : "")
            foreignPaths.withLock { $0[pid] = p }
            return p
        }()
        return ProcessRecord(pid: pid, ppid: 0, uid: 0, name: (path as NSString).lastPathComponent, path: path.isEmpty ? nil : path,
                             args: [], cwd: nil, start: .distantPast, hasTTY: false, cpuTime: 0, footprint: 0, energy: 0, diskWritten: 0,
                             restricted: true)
    }

    /// Dinlenen TCP portları (yalnızca istenen pid'ler; geliştirme sunucusu adayları).
    public func listeningPorts(pids: [Int32]) -> [Int32: [Int]] {
        var out: [Int32: [Int]] = [:]
        for pid in pids {
            let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard bytes > 0 else { continue }
            let stride = MemoryLayout<proc_fdinfo>.stride
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride)
            let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
            guard used > 0 else { continue }
            var ports: [Int] = []
            for fd in fds.prefix(Int(used) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var si = socket_fdinfo()
                let size = Int32(MemoryLayout<socket_fdinfo>.size)
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, size) == size,
                      si.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = si.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
                ports.append(Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))))
            }
            if !ports.isEmpty { out[pid] = Array(Set(ports)).sorted() }
        }
        return out
    }

    // MARK: - libproc yardımcıları

    static func allPids() -> [Int32] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [Int32](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&buf, Int32(buf.count * MemoryLayout<Int32>.size))
        return Array(buf.prefix(Int(max(0, got))))
    }

    static func path(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))   // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func cwd(_ pid: Int32) -> String? {
        var v = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, size) == size else { return nil }
        return string(v.pvi_cdir.vip_path).nonEmpty
    }

    /// `KERN_PROCARGS2`: argc, çalıştırılabilir yol, boşluk, argv. Başka kullanıcının sürecinde EPERM → boş.
    static func args(_ pid: Int32, _ buf: inout [UInt8]) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buf.count
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var i = 4
        while i < size, buf[i] != 0 { i += 1 }
        while i < size, buf[i] == 0 { i += 1 }
        var out: [String] = []
        while out.count < argc, i < size {
            let s = i
            while i < size, buf[i] != 0 { i += 1 }
            out.append(String(decoding: buf[s..<i], as: UTF8.self))
            i += 1
        }
        return out
    }

    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
