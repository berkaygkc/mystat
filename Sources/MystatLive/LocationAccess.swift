import CoreLocation
import Foundation
import MystatCore

/// Konum izni yöneticisi (testlerde sahtesi). `CLLocationManager` bu ikisini zaten sağlar.
protocol LocationAuthorizer: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
}

extension CLLocationManager: LocationAuthorizer {}

/// Wi‑Fi ağının adı (SSID) macOS'ta yalnızca konum izni olan uygulamaya verilir. İzin kendiliğinden istenmez; yalnızca
/// Bağlantı kartındaki "İzin ver" ile (plan 2e, karar 1). Konum kullanılmaz.
@MainActor
public final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager: LocationAuthorizer
    /// İzin durumu değişince (verildi, reddedildi).
    var onChange: (() -> Void)?

    public convenience override init() { self.init(manager: nil) }

    init(manager: LocationAuthorizer?) {
        if let manager {
            self.manager = manager
            super.init()
        } else {
            let m = CLLocationManager()
            self.manager = m
            super.init()
            m.delegate = self
        }
    }

    var status: SSIDAccess {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .known
        case .notDetermined: .needsPermission
        default: .denied
        }
    }

    /// Yalnızca henüz sorulmadıysa macOS'un istemini açar.
    func request() {
        guard status == .needsPermission else { return }
        manager.requestWhenInUseAuthorization()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onChange?() }
    }
}
