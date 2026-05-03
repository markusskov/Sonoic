import Foundation

enum SonoicLoadStatus: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        self == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = self {
            detail
        } else {
            nil
        }
    }
}

struct SonoicSourceSearchState: Equatable {
    var query: String
    var scope: SonoicSourceSearchScope
    var items: [SonoicSourceItem]
    var status: SonoicLoadStatus
    var lastUpdatedAt: Date?

    init(
        query: String = "",
        service: SonosServiceDescriptor,
        scope: SonoicSourceSearchScope = .all,
        items: [SonoicSourceItem]? = nil,
        status: SonoicLoadStatus = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.query = query
        self.scope = scope
        self.items = items ?? []
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var hasQuery: Bool {
        query.sonoicNonEmptyTrimmed != nil
    }

    var isSearching: Bool {
        status.isLoading
    }

    var failureDetail: String? {
        status.failureDetail
    }
}

struct SonoicSourceSearchSessionState: Equatable {
    var query = ""
    var selectedServiceID: String?
    var scope: SonoicSourceSearchScope = .all
    var lastSubmittedQuery: String?

    var hasQuery: Bool {
        query.sonoicNonEmptyTrimmed != nil
    }

    var hasSubmittedQuery: Bool {
        lastSubmittedQuery?.sonoicNonEmptyTrimmed != nil
    }

    func sourceIDs(from sources: [SonoicSource]) -> Set<String> {
        if let selectedServiceID {
            return [selectedServiceID]
        }

        return Set(sources.map(\.service.id))
    }

    func isSearching(in states: [String: SonoicSourceSearchState], sources: [SonoicSource]) -> Bool {
        sourceIDs(from: sources).contains { serviceID in
            states[serviceID]?.isSearching == true
        }
    }

    func failureDetail(in states: [String: SonoicSourceSearchState], sources: [SonoicSource]) -> String? {
        sourceIDs(from: sources)
            .compactMap { states[$0]?.failureDetail }
            .first
    }

    func visibleItems(
        in states: [String: SonoicSourceSearchState],
        sources: [SonoicSource]
    ) -> [SonoicSourceItem] {
        let visibleSourceIDs = sourceIDs(from: sources)

        return sources
            .filter { visibleSourceIDs.contains($0.service.id) }
            .flatMap { source in
                let items = states[source.service.id]?.items ?? []
                return items.filter { scope.matches($0) }
            }
    }

    func hasLoadedEmptyResults(
        in states: [String: SonoicSourceSearchState],
        sources: [SonoicSource]
    ) -> Bool {
        let visibleSourceIDs = sourceIDs(from: sources)
        let visibleStates = sources
            .filter { visibleSourceIDs.contains($0.service.id) }
            .compactMap { states[$0.service.id] }

        guard !visibleStates.isEmpty,
              visibleStates.allSatisfy({ $0.status == .loaded || $0.failureDetail != nil })
        else {
            return false
        }

        return visibleItems(in: states, sources: sources).isEmpty
    }
}

struct SonoicSourceItemPage: Equatable {
    var items: [SonoicSourceItem]
    var nextOffset: Int?
}

enum SonoicSourceSearchScope: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case songs
    case artists
    case albums
    case playlists

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All"
        case .songs:
            "Songs"
        case .artists:
            "Artists"
        case .albums:
            "Albums"
        case .playlists:
            "Playlists"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "magnifyingglass"
        case .songs:
            "music.note"
        case .artists:
            "music.mic"
        case .albums:
            "rectangle.stack"
        case .playlists:
            "music.note.list"
        }
    }

    func matches(_ item: SonoicSourceItem) -> Bool {
        switch self {
        case .all:
            true
        case .songs:
            item.kind == .song
        case .artists:
            item.kind == .artist
        case .albums:
            item.kind == .album
        case .playlists:
            item.kind == .playlist
        }
    }
}
