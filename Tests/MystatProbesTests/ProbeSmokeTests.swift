import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

/// Real system calls on this machine should return plausible values.
@Suite struct ProbeSmokeTests {
    @Test func machProbeIsPlausible() {
        let p = MachProbe()
        let ticks = p.coreTicks()
        #expect(ticks.count == ProcessInfo.processInfo.activeProcessorCount)
        #expect(ticks.allSatisfy { $0.user + $0.system + $0.idle > 0 })
        let vm = p.vm()
        #expect(vm.pageSize == UInt64(getpagesize()) && vm.pageSize == 16384)   // Apple Silicon
        #expect(vm.total == ProcessInfo.processInfo.physicalMemory)
        #expect([1, 2, 4].contains(vm.pressureLevel))
        #expect((0...100).contains(vm.memoryLevel))
        #expect(vm.`internal` > 0 && vm.wired > 0)
        let mem = MemoryMeter.state(vm)
        #expect(mem.percent > 5 && mem.percent < 100)
        #expect(p.loadAverage().count == 3)
    }

    @Test func cpuMeterOnRealTicks() async throws {
        let p = MachProbe()
        var m = CPUMeter()
        _ = m.update(p.coreTicks(), at: Date())
        try await Task.sleep(for: .milliseconds(300))
        let measured = m.update(p.coreTicks(), at: Date())
        let s = try #require(measured)
        #expect(s.percent >= 0 && s.percent <= 100)
        #expect(s.cores.count == ProcessInfo.processInfo.activeProcessorCount)
    }
    @Test func netDiskProbeIsPlausible() {
        let p = NetDiskProbe()
        let ifs = p.interfaces()
        #expect(ifs.contains { $0.name == "lo0" && $0.rx > 0 })
        #expect(p.localIPv4(of: "lo0") == "127.0.0.1")
        if let primary = p.primaryInterface() { #expect(ifs.contains { $0.name == primary }) }
        let v = p.dataVolume()
        #expect(v.total > 100_000_000_000 && v.available > 0 && v.available <= v.total)
        let io = p.diskIO()
        #expect(io.bytesRead > 0 && io.bytesWritten > 0)
    }

    @Test func defaultProbeConforms() {
        let p: any SystemProbe = DefaultProbe()
        #expect(!p.coreTicks().isEmpty && !p.interfaces().isEmpty)
    }
    /// `NET_RT_IFLIST2` wraps the received byte count at 32 bits (macOS 26); counters must match `netstat -ib`.
    @Test func interfaceBytesMatchNetstat() throws {
        let p = NetDiskProbe()
        let iface = p.primaryInterface() ?? "en0"
        let ours = try #require(p.interfaces().first { $0.name == iface })
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        proc.arguments = ["-ib", "-I", iface]
        let pipe = Pipe(); proc.standardOutput = pipe
        try proc.run(); proc.waitUntilExit()
        let line = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")[1]
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        let ibytes = try #require(UInt64(cols[6])), obytes = try #require(UInt64(cols[9]))
        #expect(ibytes >= ours.rx && ibytes - ours.rx < 1_000_000)
        #expect(obytes >= ours.tx && obytes - ours.tx < 1_000_000)
    }
    @Test func machineAndPowerArePlausible() {
        let m = MachineProbe().machine()
        #expect(m.pCores + m.eCores == ProcessInfo.processInfo.activeProcessorCount)
        #expect(m.memoryGB == Int(ProcessInfo.processInfo.physicalMemory >> 30))
        #expect(!m.model.isEmpty && !m.model.contains("(") && m.chip.hasPrefix("M"))
        #expect(m.boot < Date() && m.boot > Date().addingTimeInterval(-365 * 86_400))
        let p = PowerProbe()
        #expect([Level.ok, .warn, .crit].contains(p.thermal()))
        if let b = p.battery() {   // laptop
            #expect(b.percent >= 0 && b.percent <= 100)
            #expect((b.cycles ?? 0) >= 0 && (b.designCapacity ?? 1) > 0)
        }
    }
}
