import Foundation
import Testing
@testable import MystatProbes

@Suite struct DiskAccessTests {
    /// Değeri ortama bağlı (Terminal'in Tam Disk Erişimi); izin istemi çıkarmadan bir Bool döner.
    @Test func fdaProbeDoesNotCrash() {
        let a = DiskAccess.hasFullDiskAccess(), b = DiskAccess.hasFullDiskAccess()
        #expect(a == b)
        #expect(DiskAccess.settingsURL.scheme == "x-apple.systempreferences")
    }
}
