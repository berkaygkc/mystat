import Darwin
import MystatCore

/// Stop = SIGTERM (lets apps save their state), Force Quit = SIGKILL. Only the user's own processes: if even a single process in the group
/// belongs to someone else, no signal is sent to any. The uid is re-read for each process right before signalling.
public enum ProcessActions {
    public static func signal(_ pids: [Int32], force: Bool, ownerUID: uid_t = getuid()) -> StopOutcome {
        var alive: [Int32] = []
        for pid in pids where pid > 0 {
            guard let uid = uid(of: pid) else { continue }               // already exited
            guard uid == ownerUID else { return .notPermitted(reason: StopOutcome.foreignReason) }
            alive.append(pid)
        }
        let sent = alive.filter { kill($0, force ? SIGKILL : SIGTERM) == 0 }.count
        return sent == 0 ? .notFound : .done(count: sent)
    }

    /// `kern.proc.pid`: gives each process's owner without root. nil if the process does not exist.
    static func uid(of pid: Int32) -> uid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid
    }
}
