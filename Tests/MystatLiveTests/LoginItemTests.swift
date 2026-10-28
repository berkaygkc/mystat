import Foundation
import ServiceManagement
import Testing
@testable import MystatLive

/// Oturum açılışında başlama: ilk açılışta bir kez kaydolunur; kullanıcı kaldırdıysa ya da onay bekliyorsa dokunulmaz.
@Suite struct LoginItemTests {
    @Test func registersOnlyOnceWhenNotRegistered() {
        #expect(LoginItem.shouldRegister(status: .notRegistered, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .notRegistered, alreadyAsked: true))   // kullanıcı Giriş Öğeleri'nden kaldırmış
        #expect(!LoginItem.shouldRegister(status: .enabled, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .requiresApproval, alreadyAsked: false))   // Sistem Ayarları'ndan onaylanır
        // Hiç kaydolmamış uygulamada macOS 26 `.notFound` döndürür (ölçüldü); bu da ilk kayıt fırsatıdır.
        #expect(LoginItem.shouldRegister(status: .notFound, alreadyAsked: false))
        #expect(!LoginItem.shouldRegister(status: .notFound, alreadyAsked: true))
    }

    /// Yalnızca kurulu paket kaydolur; build/ altındaki geliştirme paketi giriş öğesinin yolunu değiştirmesin.
    @Test func onlyInstalledBundleRegisters() {
        #expect(LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Applications/mystat.app")))
        #expect(LoginItem.isInstalled(URL(fileURLWithPath: "/Applications/mystat.app")))
        #expect(!LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Documents/hobby-projects/mystat/build/mystat.app")))
        #expect(!LoginItem.isInstalled(URL(fileURLWithPath: "/Users/u/Documents/hobby-projects/mystat/.build/debug")))
    }
}
