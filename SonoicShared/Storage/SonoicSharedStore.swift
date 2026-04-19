import Foundation

struct SonoicSharedStore {
    enum StoreError: Error {
        case unavailableAppGroup(String)
    }

    nonisolated static let appGroupIdentifier = "group.com.markusskov.sonoic.shared"
    nonisolated static let externalControlStateKey = "externalControlState"

    private let userDefaults: UserDefaults

    init(suiteName: String = appGroupIdentifier) throws {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw StoreError.unavailableAppGroup(suiteName)
        }

        self.userDefaults = userDefaults
    }

    func loadExternalControlState() -> SonoicExternalControlState? {
        guard let data = userDefaults.data(forKey: Self.externalControlStateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SonoicExternalControlState.self, from: data)
    }

    func saveExternalControlState(_ state: SonoicExternalControlState) throws {
        let data = try JSONEncoder().encode(state)
        userDefaults.set(data, forKey: Self.externalControlStateKey)
    }
}
