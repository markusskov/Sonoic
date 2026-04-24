import Foundation

struct SonoicSettingsStore {
    static let manualSonosHostKey = "manualSonosHost"
    static let recentPlaysKey = "recentPlays"

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
}
