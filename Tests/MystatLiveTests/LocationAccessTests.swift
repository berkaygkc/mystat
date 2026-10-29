import CoreLocation
import Foundation
import MystatCore
import Testing
@testable import MystatLive

final class FakeAuthorizer: LocationAuthorizer {
    var authorizationStatus: CLAuthorizationStatus
    var requests = 0
    init(_ s: CLAuthorizationStatus) { authorizationStatus = s }
    func requestWhenInUseAuthorization() { requests += 1 }
}

@MainActor @Suite struct LocationAccessTests {
    @Test func statusMapping() {
        #expect(LocationAccess(manager: FakeAuthorizer(.notDetermined)).status == .needsPermission)
        #expect(LocationAccess(manager: FakeAuthorizer(.denied)).status == .denied)
        #expect(LocationAccess(manager: FakeAuthorizer(.restricted)).status == .denied)
        #expect(LocationAccess(manager: FakeAuthorizer(.authorizedAlways)).status == .known)
    }

    @Test func requestOnlyWhenUndetermined() {
        let denied = FakeAuthorizer(.denied), open = FakeAuthorizer(.notDetermined)
        LocationAccess(manager: denied).request(); LocationAccess(manager: open).request()
        #expect(denied.requests == 0); #expect(open.requests == 1)
    }

    /// İstem yalnızca "İzin ver"e basınca: kaynak oluşturulup Ağ bölümü açılınca sorulmaz.
    @Test func noPromptWithoutAction() async {
        let auth = FakeAuthorizer(.notDetermined), f = NetFakes()
        let s = LiveSource(probe: FakeProbe(), historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI(),
                           net: f.poller(), location: LocationAccess(manager: auth))
        s.setVisibleSection("net")
        #expect(auth.requests == 0)
        s.requestNetworkNameAccess()
        #expect(auth.requests == 1)
    }

    /// İzin verilince ağ adı bir sonraki tura kalmadan gelsin: bağlantı hemen yeniden okunur.
    @Test func grantRefreshesLink() async throws {
        let auth = FakeAuthorizer(.notDetermined), f = NetFakes(), poller = f.poller()
        let loc = LocationAccess(manager: auth)
        let s = LiveSource(probe: FakeProbe(), historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI(),
                           net: poller, location: loc)
        s.setVisibleSection("net"); await poller.sync()
        let before = f.links.load(ordering: .relaxed)
        auth.authorizationStatus = .authorizedAlways
        loc.onChange?()
        for _ in 0..<100 where f.links.load(ordering: .relaxed) == before { try await Task.sleep(for: .milliseconds(10)) }
        #expect(f.links.load(ordering: .relaxed) > before)
        #expect(loc.status == .known)
    }
}
