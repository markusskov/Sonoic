import Foundation

struct SonosRoomVolumeItem: Identifiable, Equatable {
    let id: String
    var name: String
    var host: String
    var isCoordinator: Bool
    var volume: SonoicExternalControlState.Volume
}

struct SonosRoomVolumeSnapshot: Equatable {
    var targetID: String
    var targetName: String
    var targetKind: SonosActiveTarget.Kind
    var items: [SonosRoomVolumeItem]
    var refreshedAt: Date

    var isGroup: Bool {
        targetKind == .group
    }
}

enum SonosRoomVolumeState: Equatable {
    case idle
    case loading
    case unavailable(String)
    case loaded(SonosRoomVolumeSnapshot)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }

    var snapshot: SonosRoomVolumeSnapshot? {
        guard case let .loaded(snapshot) = self else {
            return nil
        }

        return snapshot
    }

    var failureDetail: String? {
        switch self {
        case let .unavailable(detail), let .failed(detail):
            detail
        case .idle, .loading, .loaded:
            nil
        }
    }
}
