import Foundation

enum SonosFavoritesState: Equatable {
    case idle
    case loading
    case loaded(SonosFavoritesSnapshot)
    case empty
    case failed(String)

    var snapshot: SonosFavoritesSnapshot? {
        guard case let .loaded(snapshot) = self else {
            return nil
        }

        return snapshot
    }

    var hasLoadedValue: Bool {
        switch self {
        case .loaded, .empty:
            true
        case .idle, .loading, .failed:
            false
        }
    }
}
