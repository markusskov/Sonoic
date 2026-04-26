import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicRecentSourceSearchTests {
    @Test
    func canonicalizesIdentifierByServiceAndTrimmedQuery() {
        let first = SonoicRecentSourceSearch(
            serviceID: "apple-music",
            query: "  Elvis ",
            searchedAt: Date(timeIntervalSince1970: 1)
        )
        let second = SonoicRecentSourceSearch(
            serviceID: "apple-music",
            query: "elvis",
            searchedAt: Date(timeIntervalSince1970: 2)
        )
        let otherService = SonoicRecentSourceSearch(
            serviceID: "spotify",
            query: "elvis",
            searchedAt: Date(timeIntervalSince1970: 3)
        )

        #expect(first.id == second.id)
        #expect(first.id != otherService.id)
    }

    @Test
    func settingsStorePersistsRecentSourceSearches() throws {
        let userDefaults = try makeUserDefaults()
        let store = SonoicSettingsStore(userDefaults: userDefaults)
        let searches = [
            SonoicRecentSourceSearch(
                serviceID: "apple-music",
                query: "Sweet Jane",
                searchedAt: Date(timeIntervalSince1970: 10)
            ),
            SonoicRecentSourceSearch(
                serviceID: "spotify",
                query: "The Mollusk",
                searchedAt: Date(timeIntervalSince1970: 20)
            )
        ]

        store.saveRecentSourceSearches(searches)

        #expect(store.loadRecentSourceSearches() == searches)
    }

    @Test
    func settingsStoreIgnoresInvalidRecentSourceSearchData() throws {
        let userDefaults = try makeUserDefaults()
        userDefaults.set(Data("not-json".utf8), forKey: SonoicSettingsStore.recentSourceSearchesKey)
        let store = SonoicSettingsStore(userDefaults: userDefaults)

        #expect(store.loadRecentSourceSearches().isEmpty)
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "SonoicRecentSourceSearchTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
