import Foundation
import Testing
@testable import CmdTabWheel

@MainActor
struct FavoritesStoreTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let suite = "com.faustienf.CmdTabWheel.FavoritesTests." + UUID().uuidString
        return (suite, UserDefaults(suiteName: suite)!)
    }

    @Test func theWheelOpensTheWayItWasLeft() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!Favorites(defaults: defaults).isShown)
        Favorites(defaults: defaults).isShown = true
        #expect(Favorites(defaults: defaults).isShown)
    }

    @Test func favoriteWindowsOutliveARestartButNotTheirApp() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        Favorites(defaults: defaults, isRunning: { _ in true }).save([201: 2, 301: 3])
        #expect(Favorites(defaults: defaults, isRunning: { _ in true }).windows == [201: 2, 301: 3])
        #expect(Favorites(defaults: defaults, isRunning: { $0 == 2 }).windows == [201: 2])
    }
}
