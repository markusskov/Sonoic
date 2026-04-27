import Foundation

struct SonosContentDirectoryProbeState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var status: Status
    var snapshot: SonosContentDirectoryProbeSnapshot?

    static let idle = SonosContentDirectoryProbeState(status: .idle, snapshot: nil)

    var isLoading: Bool {
        status == .loading
    }
}

struct SonosContentDirectoryProbeSnapshot: Equatable {
    var observedAt: Date
    var browses: [SonosContentDirectoryProbeBrowse]

    var discoveredRecentCandidates: [SonosContentDirectoryProbeEntry] {
        browses
            .flatMap(\.entries)
            .filter(\.looksLikeRecentlyPlayedContainer)
    }
}

struct SonosContentDirectoryProbeBrowse: Identifiable, Equatable {
    enum Status: Equatable {
        case loaded
        case empty
        case failed(String)

        var title: String {
            switch self {
            case .loaded:
                "Loaded"
            case .empty:
                "Empty"
            case .failed:
                "Failed"
            }
        }
    }

    var objectID: String
    var title: String
    var status: Status
    var numberReturned: Int?
    var totalMatches: Int?
    var entries: [SonosContentDirectoryProbeEntry]

    var id: String {
        objectID
    }

    var countText: String {
        if let numberReturned, let totalMatches {
            return "\(numberReturned) of \(totalMatches)"
        }

        return status.title
    }
}

struct SonosContentDirectoryProbeEntry: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case container
        case item
    }

    var id: String
    var parentID: String?
    var kind: Kind
    var title: String
    var itemClass: String?
    var creator: String?
    var album: String?
    var resourceURI: String?
    var albumArtURI: String?

    var detailText: String {
        [
            kind.rawValue,
            itemClass,
            id,
        ]
        .compactMap(\.sonoicNonEmptyTrimmed)
        .joined(separator: " · ")
    }

    var looksLikeRecentlyPlayedContainer: Bool {
        guard kind == .container else {
            return false
        }

        let haystack = [
            title,
            id,
            itemClass ?? "",
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains("recent")
            || haystack.contains("history")
            || haystack.contains("played")
    }
}
