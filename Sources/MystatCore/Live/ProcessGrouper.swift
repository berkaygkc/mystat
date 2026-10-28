import Foundation

/// Süreçleri anlamına göre gruplar (spec §8). Önce soy ağacı: bir Claude Code oturumu tüm torunlarını alır;
/// ama torunlardan bir geliştirme sunucusu kendi grubudur. Sonra yol: uygulama paketleri yardımcılarıyla tek
/// grup, Docker'ın sanal makinesi, sistem süreçleri tek "macOS" satırı, kalanlar adlarıyla.
public enum ProcessGrouper {
    static let gib = 1_073_741_824.0
    static let dockerVM = "com.apple.Virtualization.VirtualMachine"

    private enum Kind: Hashable {
        case claude(root: Int32), dev(root: Int32), docker, app(String), systemApp(String), system, other(String)
    }

    public static func groups(_ r: [ProcessRecord], cores: [Int32: Double], ports: [Int32: [Int]],
                              system: (cores: Double, memoryGB: Double), now: Date, home: String,
                              owner: uid_t = getuid(), cache: ClassCache = .init()) -> [ProcessGroup] {
        let byPid = Dictionary(r.filter { !$0.restricted }.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let marks = cache.marks(r)
        var members: [Kind: [ProcessRecord]] = [:]
        for p in r { members[kind(p, byPid, marks), default: []].append(p) }
        if members[.system] == nil, system.cores > 0 || system.memoryGB > 0 { members[.system] = [] }

        var out: [ProcessGroup] = []
        var claudeIDs: [Int32: String] = [:]
        // Aynı klasörde iki oturum ya da portsuz iki sunucu: en küçük pid sade kimliği alır, kimlik turdan tura sabit.
        var used = Set<String>()
        func unique(_ id: String, _ root: Int32) -> String {
            let u = used.contains(id) ? "\(id)#\(root)" : id
            used.insert(u)
            return u
        }
        let roots = members.keys.sorted { rootPid($0) < rootPid($1) }
        for case .claude(let root) in roots {
            let ms = members[.claude(root: root)]!
            let rp = byPid[root]!
            let id = unique("claude:\(rp.cwd ?? "")", root)
            claudeIDs[root] = id
            out.append(make(id: id, name: "Claude Code", context: rp.cwd.map { ($0 as NSString).lastPathComponent } ?? "", ms, cores, owner,
                            now: now, folder: rp.cwd, terminal: ms.lazy.compactMap(\.terminal).first))
        }
        for case .dev(let root) in roots {
            let ms = members[.dev(root: root)]!
            let rp = byPid[root]!
            let port = ms.compactMap { ports[$0.pid]?.min() }.min() ?? argPort(rp.args)
            let cwd = rp.cwd ?? ""
            let svc = service(rp).flatMap { $0 == (cwd as NSString).lastPathComponent ? nil : "/" + $0 } ?? ""
            let ctx = projectContext(cwd: cwd, root: rp.projectRoot) + svc + (port.map { " · :\($0)" } ?? "")
            let related = ancestors(rp, byPid).lazy.compactMap { claudeIDs[$0.pid] }.first
                ?? out.first { $0.name == "Claude Code" && $0.folder.map { f in cwd.hasPrefix(f) || rp.projectRoot == f } == true }?.id
            out.append(make(id: unique("dev:\(cwd)\(svc):\(port ?? 0)", root), name: devName(rp), context: ctx, ms, cores, owner, now: now, folder: cwd,
                            terminal: rp.terminal, port: port, orphan: rp.ppid == 1, related: related))
        }
        for (k, ms) in members {
            switch k {
            case .docker:
                out.append(make(id: "docker:vm", name: "Docker", context: "sanal makine", ms, cores, owner, now: now, docker: true))
            case .app(let path):
                let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                out.append(make(id: "app:\(path)", name: name, context: ms.count > 1 ? "\(ms.count) süreç" : "", ms, cores, owner, now: now))
            case .systemApp(let path):   // loginwindow, Dock, Finder: kullanıcının uid'iyle çalışır ama durdurulmamalı
                var g = make(id: "app:\(path)", name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, context: "macOS",
                             ms, cores, owner, now: now)
                g.foreign = true
                out.append(g)
            case .other(let name):
                out.append(make(id: "proc:\(name)", name: name, context: ms.count > 1 ? "\(ms.count) süreç" : "", ms, cores, owner, now: now))
            case .system:
                var g = make(id: "sys:macos", name: "macOS", context: "sistem süreçleri", ms, cores, owner, now: now)
                g.cpuCores += system.cores
                g.memoryGB += system.memoryGB
                g.foreign = true
                out.append(g)
            case .claude, .dev: break
            }
        }
        return out.sorted { $0.cpuCores != $1.cpuCores ? $0.cpuCores > $1.cpuCores : $0.memoryGB > $1.memoryGB }
    }

    /// Dinlenen portu okunacak süreçler: geliştirme sunucusu gibi görünenler ve torunları.
    public static func devServerCandidates(_ r: [ProcessRecord], cache: ClassCache = .init()) -> [Int32] {
        let byPid = Dictionary(r.filter { !$0.restricted }.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let marks = cache.marks(r)
        return r.filter { p in !p.restricted && ([p] + ancestors(p, byPid)).contains { marks[$0.pid]?.dev == true } }.map(\.pid)
    }

    // MARK: - Sınıflandırma

    /// Bir sürecin ömrü boyunca değişmeyen sınıflandırması (argüman ve yol taraması). Örnekleyici turlar arasında
    /// tutar; anahtar (pid, başlangıç) olduğundan yeniden kullanılan pid yeniden hesaplanır. Boşta maliyetin çoğu buradaydı.
    public final class ClassCache {
        struct Key: Hashable { let pid: Int32; let start: Date }
        struct Entry { let claude: Bool, dev: Bool, app: String?, system: Bool }
        private var entries: [Key: Entry] = [:]
        public init() {}
        public var count: Int { entries.count }

        /// Bu turun kendi süreçleri için sınıflar; listede olmayan kayıtlar atılır.
        fileprivate func marks(_ r: [ProcessRecord]) -> [Int32: Entry] {
            var next: [Key: Entry] = [:], out: [Int32: Entry] = [:]
            next.reserveCapacity(r.count)
            for p in r where !p.restricted {
                let k = Key(pid: p.pid, start: p.start)
                let e = entries[k] ?? Entry(claude: isClaude(p), dev: devKind(p) != nil, app: p.path.flatMap(outermostApp),
                                            system: p.path.map { $0.hasPrefix("/System/") || $0.hasPrefix("/usr/") || $0.hasPrefix("/sbin/") } ?? false)
                next[k] = e
                out[p.pid] = e
            }
            entries = next
            return out
        }
    }

    private static func kind(_ p: ProcessRecord, _ byPid: [Int32: ProcessRecord], _ marks: [Int32: ClassCache.Entry]) -> Kind {
        if p.restricted { return .system }
        let chain = [p] + ancestors(p, byPid)
        let firstClaude = chain.firstIndex { marks[$0.pid]?.claude == true }
        let belowClaude = chain[..<(firstClaude ?? chain.count)]
        if let dev = belowClaude.last(where: { marks[$0.pid]?.dev == true }) { return .dev(root: dev.pid) }
        if firstClaude != nil, let top = chain.last(where: { marks[$0.pid]?.claude == true }) { return .claude(root: top.pid) }
        if isDockerVM(p) { return .docker }
        if let app = marks[p.pid]?.app { return app.hasPrefix("/System/") ? .systemApp(app) : .app(app) }
        if marks[p.pid]?.system == true { return .system }
        return .other(p.name)
    }

    /// Çekirdek süreç adını 32 karakterde kırptığı için ("com.apple.Virtualization.Virtua") tanıma yoldan.
    static func isDockerVM(_ p: ProcessRecord) -> Bool {
        p.name == dockerVM || p.path?.hasSuffix("/" + dockerVM) == true
    }

    static func isClaude(_ p: ProcessRecord) -> Bool {
        if let path = p.path, path.hasSuffix("/.local/bin/claude") || path.contains("/claude/versions/") { return true }
        return p.name == "claude" || p.args.first.map { ($0 as NSString).lastPathComponent == "claude" } == true
    }

    private static func rootPid(_ k: Kind) -> Int32 {
        switch k { case .claude(let r), .dev(let r): r; default: .max }
    }

    /// "next dev" → Next.js dev, "next start"/next-server → Next.js, vite (vitest değil), bun dev, node --watch,
    /// `tsx <betik>` (acmecorp servisleri böyle çalışır).
    static func devKind(_ p: ProcessRecord) -> String? {
        let t = p.args.flatMap { $0.split(separator: " ").map(String.init) }
        let last = t.map { ($0 as NSString).lastPathComponent }
        for (i, w) in last.enumerated() where w == "next" && i + 1 < t.count {
            if t[i + 1] == "dev" { return "Next.js dev" }
            if t[i + 1] == "start" { return "Next.js" }
        }
        if p.name == "next-server" { return "Next.js" }
        if last.contains("vite") { return "Vite" }
        if let i = last.firstIndex(of: "bun"), t.dropFirst(i + 1).prefix(2).contains("dev") { return "Bun dev" }
        if last.first == "node", t.contains("--watch") { return "Node watch" }
        if tsxScript(t) != nil { return "tsx" }
        return nil
    }

    /// `tsx [watch] services/panel/src/main.ts` → betik yolu.
    private static func tsxScript(_ t: [String]) -> String? {
        guard let i = t.firstIndex(where: { ($0 as NSString).lastPathComponent == "tsx" }) else { return nil }
        return t.dropFirst(i + 1).first { !$0.hasPrefix("-") && $0 != "watch" }
    }

    /// Betiğin servis adı: `services/panel/src/main.ts` → "panel" (`src`'den önceki klasör).
    static func service(_ p: ProcessRecord) -> String? {
        guard let script = tsxScript(p.args.flatMap { $0.split(separator: " ").map(String.init) }) else { return nil }
        let parts = script.split(separator: "/").map(String.init)
        guard let s = parts.lastIndex(of: "src"), s > 0 else { return nil }
        return parts[s - 1]
    }

    private static func devName(_ p: ProcessRecord) -> String { devKind(p) ?? "Sunucu" }

    static func ancestors(_ p: ProcessRecord, _ byPid: [Int32: ProcessRecord]) -> [ProcessRecord] {
        var out: [ProcessRecord] = [], cur = p, seen: Set<Int32> = [p.pid]
        while let parent = byPid[cur.ppid], !seen.contains(parent.pid), out.count < 64 {
            out.append(parent); seen.insert(parent.pid); cur = parent
        }
        return out
    }

    static func outermostApp(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    static func argPort(_ args: [String]) -> Int? {
        let t = args.flatMap { $0.split(separator: " ").map(String.init) }
        for (i, w) in t.enumerated() {
            if (w == "-p" || w == "--port"), i + 1 < t.count, let n = Int(t[i + 1]) { return n }
            if w.hasPrefix("--port="), let n = Int(w.dropFirst(7)) { return n }
        }
        return nil
    }

    /// "acmecorp/web": proje kökünün adı ve (kökte değilse) cwd'nin son parçası.
    static func projectContext(cwd: String, root: String?) -> String {
        let last = (cwd as NSString).lastPathComponent
        guard let root, root != cwd, cwd.hasPrefix(root) else { return last }
        return "\((root as NSString).lastPathComponent)/\(last)"
    }

    private static func make(id: String, name: String, context: String, _ ms: [ProcessRecord], _ cores: [Int32: Double], _ owner: uid_t, now: Date,
                             folder: String? = nil, terminal: String? = nil, port: Int? = nil, orphan: Bool = false,
                             related: String? = nil, docker: Bool = false) -> ProcessGroup {
        let cpu = ms.reduce(0) { $0 + (cores[$1.pid] ?? 0) }
        let mem = Double(ms.reduce(UInt64(0)) { $0 &+ $1.footprint }) / gib
        let oldest = ms.filter { !$0.restricted }.map(\.start).min()
        return ProcessGroup(id: id, name: name, context: context, cpuCores: cpu, memoryGB: mem, netMBps: 0,
                            uptime: oldest.map { Fmt.uptime(now.timeIntervalSince($0)) } ?? "", processCount: ms.count,
                            folder: folder, terminal: terminal, port: port, isOrphan: orphan, relatedID: related, isDocker: docker,
                            children: ms.map { ChildProcess(name: $0.name, cpuCores: cores[$0.pid] ?? 0) },
                            pids: ms.filter { !$0.restricted }.map(\.pid), foreign: ms.contains { $0.restricted || $0.uid != owner })
    }
}
