import Foundation
import Observation

public enum SeriesKey: Hashable, Sendable {
    case cpu, cpuSystem, memUsed, memPressure, netDown, netUp, diskRead, diskWrite
    case temp, fan, power, gpu, battery, dockerCPU, dockerTrend30
    /// Container memory (GB) and Docker's data (GB; for the daily trend).
    case dockerMem, dockerDisk
    case group(String)
}

/// The only data source the UI sees: `SampleSource` for sample data, a live source for real measurements.
@MainActor
public protocol MetricsSource: AnyObject, Observable {
    var snapshot: Snapshot { get }
    func series(_ key: SeriesKey, range: TimeRange) -> [Double]
    var diskTree: DiskTree { get }
    /// Disk scan: starts only manually, valid for 1 hour. A roughly 4 s simulation in the sample source.
    var diskScan: ScanPhase { get }
    /// In sample data the scan is simulated: the tree is complete from the start and the bubbles are drawn growing with progress. In a real scan the tree
    /// actually grows.
    var diskScanSimulated: Bool { get }
    func startDiskScan()
    /// Location permission for the Wi-Fi network name (only when the user presses "Allow").
    func requestNetworkNameAccess()
    /// Whether Full Disk Access is granted; without it, protected folders are skipped in the scan.
    var diskFullAccess: Bool { get }
    /// Number of folders that could not be read in the last scan.
    var diskInaccessible: Int { get }
    /// Stops a running scan; the previous state (none, or the previous result) comes back.
    func cancelDiskScan()
    /// Deletes the items in the basket or moves them to the Trash; called after confirmation. The tree is updated in place and disk usage
    /// is re-read. A simulation in the sample source.
    func delete(_ items: [BasketItem], mode: DeleteMode) async -> DeleteOutcome
    /// Whether the panel or monitor is open: 2 s while the process list is open, 5 s when closed.
    func setDetailInterest(_ visible: Bool)
    /// The section visible in the monitor ("docker", "net" …); nil if the monitor is closed. Docker's disk usage is refreshed when its section opens;
    /// the disk tree is kept in memory only while "disk" is open.
    func setVisibleSection(_ section: String?)
    /// The monitor window is covered or minimized (not closed): only work that runs while visible (Network details) stops;
    /// the disk tree stays in memory.
    func setMonitorOccluded(_ occluded: Bool)
    /// Docker action; called after confirmation. May take a while (cleanup); the UI does not wait.
    func perform(_ action: DockerAction) async -> DockerActionOutcome
    /// SIGTERM to the group's processes (SIGKILL if `force`); only your own processes.
    /// `pids`: the members when the confirmation dialog was opened; only those still in the group are signaled.
    func stop(groupID: String, pids: [Int32], force: Bool) -> StopOutcome
    /// Language changed: texts generated on the measurement side (facts, suggestions, group context) are refreshed in the new language without waiting.
    func languageChanged()
}

public extension MetricsSource {
    var diskScanSimulated: Bool { false }
    func setMonitorOccluded(_ occluded: Bool) {}
    func languageChanged() {}
}

public enum StopOutcome: Sendable, Equatable {
    case done(count: Int)
    case notPermitted(reason: String)
    case notFound

    /// When the group contains processes not owned by the user; the UI shows the buttons disabled and says so.
    public static var foreignReason: String { L10n.t("process.foreign") }
}
