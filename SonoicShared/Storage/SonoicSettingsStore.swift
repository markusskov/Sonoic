import Foundation

struct SonoicSettingsStore {
    static let manualSonosHostKey = "manualSonosHost"

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
}
