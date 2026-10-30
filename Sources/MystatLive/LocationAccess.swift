import CoreLocation
import Foundation
import MystatCore

/// Location-permission manager (with a fake in tests). `CLLocationManager` already provides both of these.
protocol LocationAuthorizer: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
}

extension CLLocationManager: LocationAuthorizer {}

/// macOS gives the Wi‑Fi network name (SSID) only to apps with location permission. Permission is never requested automatically; only
/// via "Allow" on the Connection card. Location itself is not used.
@MainActor
public final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager: LocationAuthorizer
    /// When the permission state changes (granted, denied).
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

    /// Opens the macOS prompt only if the user has not been asked yet.
    func request() {
        guard status == .needsPermission else { return }
        manager.requestWhenInUseAuthorization()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onChange?() }
    }
}
