import Foundation

struct SonosRoomListItem: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case room
        case group

        var title: String {
            switch self {
            case .room:
                "Room"
            case .group:
                "Group"
            }
        }

        var systemImage: String {
            switch self {
            case .room:
                "speaker.wave.2.fill"
            case .group:
                "square.stack.3d.up.fill"
            }
        }
    }

    enum Source: Equatable {
        case manualFallback
        case discovered

        var title: String {
            switch self {
            case .manualFallback:
                "Manual Fallback"
            case .discovered:
                "Discovered"
            }
        }
    }

    let id: String
    var name: String
    var kind: Kind
    var summary: String
    var source: Source
    var isActive: Bool
}

extension SonosRoomListItem {
    init(activeTarget: SonosActiveTarget, source: Source, isActive: Bool) {
        self.init(
            id: activeTarget.id,
            name: activeTarget.name,
            kind: .init(activeTargetKind: activeTarget.kind),
            summary: activeTarget.summary,
            source: source,
            isActive: isActive
        )
    }
}

private extension SonosRoomListItem.Kind {
    init(activeTargetKind: SonosActiveTarget.Kind) {
        switch activeTargetKind {
        case .room:
            self = .room
        case .group:
            self = .group
        }
    }
}
