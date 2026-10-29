#if DEBUG
import Darwin
import Foundation
import MystatCore
import MystatLive

/// `--scan-home` (DEBUG): ev klasörünü arayüzsüz tarar; süre, işlemci zamanı, bellek ve en büyük 10 kalemi yazar.
/// tools/disk-check.sh `du` ile karşılaştırır. Önbellek geçici bir yola yazılır, uygulamanınkine dokunulmaz.
/// Paketteki gibi ölçmek için `MallocLargeCache=0` ile çalıştırılır (Info.plist `LSEnvironment`).
enum DiskCheck {
    @MainActor static func run() -> Never {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-diskcheck-\(getpid()).cache")
        defer { try? FileManager.default.removeItem(at: cache) }
        let (rss0, fp0) = memory()
        // Tarayıcının doğruluğu `du` ile ölçülür: izinsizken atlanan klasörler (§10) burada da taransın.
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
        print(String(format: "toplam_gb=%.2f sure_sn=%.1f cpu_sn=%.1f", root.size, secs, cpu)
              + " erisilemeyen=\(c.inaccessible) bulutta=\(root.cloudItems) rss_mb_once=\(mb(rss0)) rss_mb_tepe=\(mb(peak)) rss_mb_hazir=\(mb(rssReady)) rss_mb_birakinca=\(mb(rssDropped))"
              + " dizin_birakildi=\(weakIndex == nil) ayak_izi_mb_once=\(mb(fp0)) ayak_izi_mb_hazir=\(mb(fpReady)) ayak_izi_mb_birakinca=\(mb(fpDropped))")
        for n in top { print("kalem\t\(n.name)\t\(Int64((n.size * 1e9).rounded()))") }
        exit(0)
    }

    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    /// Yerleşik bellek (RSS) ve Etkinlik Monitörü'nün "Bellek" sütunu (phys_footprint).
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
