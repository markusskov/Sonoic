import Foundation

struct SonoicSettingsStore {
    static let manualSonosHostKey = "manualSonosHost"
    static let recentPlaysKey = "recentPlays"
    static let recentSourceSearchesKey = "recentSourceSearches"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let sonosControlAPISettingsKey = "sonosControlAPISettings"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadManualSonosHost() -> String {
        userDefaults.string(forKey: Self.manualSonosHostKey) ?? ""
    }

    func saveManualSonosHost(_ host: String) {
        userDefaults.set(host, forKey: Self.manualSonosHostKey)
    }

    func loadRecentPlays() -> [SonoicRecentPlayItem] {
        guard let data = userDefaults.data(forKey: Self.recentPlaysKey),
              let recentPlays = try? JSONDecoder().decode([SonoicRecentPlayItem].self, from: data)
        else {
            return []
        }

        return recentPlays
    }

    func saveRecentPlays(_ recentPlays: [SonoicRecentPlayItem]) {
        guard let data = try? JSONEncoder().encode(recentPlays) else {
            return
        }

        userDefaults.set(data, forKey: Self.recentPlaysKey)
    }

    func loadRecentSourceSearches() -> [SonoicRecentSourceSearch] {
        guard let data = userDefaults.data(forKey: Self.recentSourceSearchesKey),
              let recentSearches = try? JSONDecoder().decode([SonoicRecentSourceSearch].self, from: data)
        else {
            return []
        }

        return recentSearches
    }

    func saveRecentSourceSearches(_ recentSearches: [SonoicRecentSourceSearch]) {
        guard let data = try? JSONEncoder().encode(recentSearches) else {
            return
        }

        userDefaults.set(data, forKey: Self.recentSourceSearchesKey)
    }

    func loadHasCompletedOnboarding() -> Bool {
        userDefaults.bool(forKey: Self.hasCompletedOnboardingKey)
    }

    func saveHasCompletedOnboarding(_ hasCompletedOnboarding: Bool) {
        userDefaults.set(hasCompletedOnboarding, forKey: Self.hasCompletedOnboardingKey)
    }

    func loadSonosControlAPISettings() -> SonosControlAPISettings {
        guard let data = userDefaults.data(forKey: Self.sonosControlAPISettingsKey),
              let settings = try? JSONDecoder().decode(SonosControlAPISettings.self, from: data)
        else {
            return .disabled
        }

        return settings
    }

    func saveSonosControlAPISettings(_ settings: SonosControlAPISettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(data, forKey: Self.sonosControlAPISettingsKey)
    }
}
