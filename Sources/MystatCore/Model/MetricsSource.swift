import Foundation
import Observation

public enum SeriesKey: Hashable, Sendable {
    case cpu, cpuSystem, memUsed, memPressure, netDown, netUp, diskRead, diskWrite
    case temp, fan, power, gpu, battery, dockerCPU, dockerTrend30
    /// Container belleği (GB) ve Docker'ın verisi (GB; günlük gidişat için).
    case dockerMem, dockerDisk
    case group(String)
}

/// Arayüzün gördüğü tek veri kaynağı. Faz 1'de `SampleSource`, Faz 2'de gerçek kaynak.
@MainActor
public protocol MetricsSource: AnyObject, Observable {
    var snapshot: Snapshot { get }
    func series(_ key: SeriesKey, range: TimeRange) -> [Double]
    var diskTree: DiskTree { get }
    /// Disk taraması (§6.4): yalnızca elle başlar, 1 saat geçerli. Örnek kaynakta ≈ 4 sn'lik benzetim.
    var diskScan: ScanPhase { get }
    /// Örnek veride tarama benzetimdir: ağaç baştan tam, balonlar ilerlemeyle büyütülerek çizilir. Gerçek taramada ağaç
    /// gerçekten büyür.
    var diskScanSimulated: Bool { get }
    func startDiskScan()
    /// Wi‑Fi ağının adı için konum izni (yalnızca kullanıcı "İzin ver"e basınca).
    func requestNetworkNameAccess()
    /// Tam Disk Erişimi var mı; yoksa taramada korumalı klasörler atlanır (§6.4).
    var diskFullAccess: Bool { get }
    /// Son taramada okunamayan klasör sayısı.
    var diskInaccessible: Int { get }
    /// Süren taramayı durdurur; önceki durum (yok ya da önceki sonuç) geri gelir.
    func cancelDiskScan()
    /// Sepetteki öğeleri siler ya da çöpe taşır (§6.4); onaydan sonra çağrılır. Ağaç yerinde güncellenir, disk doluluğu
    /// yeniden okunur. Örnek kaynakta benzetim.
    func delete(_ items: [BasketItem], mode: DeleteMode) async -> DeleteOutcome
    /// Panel ya da monitör açık mı: süreç listesi açıkken 2 sn, kapalıyken 5 sn (spec §9.2).
    func setDetailInterest(_ visible: Bool)
    /// Monitörde görünen bölüm ("docker", "net" …); monitör kapalıysa nil. Docker'ın diski bölüm açılınca yenilenir (§9.2);
    /// disk ağacı yalnızca "disk" açıkken bellekte tutulur (§6.4).
    func setVisibleSection(_ section: String?)
    /// Docker eylemi (§7.4); onaydan sonra çağrılır. Uzun sürebilir (temizlik); arayüz beklemez.
    func perform(_ action: DockerAction) async -> DockerActionOutcome
    /// Grubun süreçlerine SIGTERM (`force` ise SIGKILL); yalnızca kendi süreçlerin (spec §7.4).
    /// `pids`: onay penceresi açıldığındaki üyeler; yalnızca hâlâ grupta olanlara sinyal gider.
    func stop(groupID: String, pids: [Int32], force: Bool) -> StopOutcome
}

public extension MetricsSource {
    var diskScanSimulated: Bool { false }
}

public enum StopOutcome: Sendable, Equatable {
    case done(count: Int)
    case notPermitted(reason: String)
    case notFound

    /// Grupta kullanıcının olmayan süreç varken; arayüz düğmeleri pasif gösterir ve bunu yazar.
    public static let foreignReason = "Bu grubun bazı süreçleri sistemin; yalnızca kendi süreçlerin kapatılabilir."
}
