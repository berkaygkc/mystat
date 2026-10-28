import Darwin
import MystatCore

/// Durdur = SIGTERM, Zorla kapat = SIGKILL (spec §7.4). Yalnızca kullanıcının kendi süreçleri: gruptan tek bir
/// süreç bile başkasınınsa hiçbirine sinyal gönderilmez. uid, her süreç için sinyalden hemen önce yeniden okunur.
public enum ProcessActions {
    public static func signal(_ pids: [Int32], force: Bool, ownerUID: uid_t = getuid()) -> StopOutcome {
        var alive: [Int32] = []
        for pid in pids where pid > 0 {
            guard let uid = uid(of: pid) else { continue }               // bitmiş
            guard uid == ownerUID else { return .notPermitted(reason: StopOutcome.foreignReason) }
            alive.append(pid)
        }
        let sent = alive.filter { kill($0, force ? SIGKILL : SIGTERM) == 0 }.count
        return sent == 0 ? .notFound : .done(count: sent)
    }

    /// `kern.proc.pid`: her sürecin sahibini root olmadan verir. Süreç yoksa nil.
    static func uid(of pid: Int32) -> uid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid
    }
}
