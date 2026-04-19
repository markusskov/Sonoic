import Foundation

enum SonoicExternalStateLoader {
    static func load() -> SonoicExternalControlState {
        do {
            let sharedStore = try SonoicSharedStore()
            return sharedStore.loadExternalControlState() ?? .unconfigured
        } catch {
            return .unconfigured
        }
    }
}
