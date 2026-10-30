#if DEBUG
import Darwin
import Foundation
import MystatCore
import MystatLive

/// `--scan-home` (DEBUG): scans the home folder without UI and prints duration, CPU time, memory and the 10 largest items.
/// tools/disk-check.sh compares the result with `du`. The cache is written to a temporary path; the app's own cache is untouched.
/// Run with `MallocLargeCache=0` to measure as in the bundled app (Info.plist `LSEnvironment`).
enum DiskCheck {
    @MainActor static func run() -> Never {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-diskcheck-\(getpid()).cache")
        defer { try? FileManager.default.removeItem(at: cache) }
        let (rss0, fp0) = memory()
        // The scanner's accuracy is measured against `du`, so scan the folders that are skipped without permission here too.
        let c = DiskScanController(cacheURL: cache, fullDiskAccess: { true })
        c.setVisible(true)
        let t0 = Date(), cpu0 = cpuSeconds()
        var peak = rss0
        c.start()
        while true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            peak = max(peak, memory().rss)
            if case .ready = c.phase { break }
        }
        let secs = Date().timeIntervalSince(t0), cpu = cpuSeconds() - cpu0
        let (rssReady, fpReady) = memory()
        let root = c.tree.root
        let top = (root.children ?? []).filter { $0.kind != .other }.sorted { $0.size > $1.size }.prefix(10)
        weak let weakIndex = c.tree.scanIndex
        c.setVisible(false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let (rssDropped, fpDropped) = memory()
        func mb(_ v: UInt64) -> String { String(format: "%.0f", Double(v) / 1_048_576) }
        print(String(format: "total_gb=%.2f secs=%.1f cpu_secs=%.1f", root.size, secs, cpu)
              + " inaccessible=\(c.inaccessible) cloud=\(root.cloudItems) rss_mb_before=\(mb(rss0)) rss_mb_peak=\(mb(peak)) rss_mb_ready=\(mb(rssReady)) rss_mb_released=\(mb(rssDropped))"
              + " index_released=\(weakIndex == nil) footprint_mb_before=\(mb(fp0)) footprint_mb_ready=\(mb(fpReady)) footprint_mb_released=\(mb(fpDropped))")
        for n in top { print("item\t\(n.name)\t\(Int64((n.size * 1e9).rounded()))") }
        exit(0)
    }

    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    /// Resident memory (RSS) and the "Memory" column of Activity Monitor (phys_footprint).
    static func memory() -> (rss: UInt64, footprint: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? (info.resident_size, info.phys_footprint) : (0, 0)
    }
}
#endif
