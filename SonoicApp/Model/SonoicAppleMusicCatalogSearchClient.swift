import Foundation
@preconcurrency import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    private static let allSearchItemLimitPerGroup = 25
    private static let allSearchTotalLimit = 100
    private static let scopedSearchLimit = 24

    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)
        case requestFailed(SonoicAppleMusicRequestFailure)

        var errorDescription: String? {
            switch self {
            case let .unauthorized(status):
                let appStatus = SonoicAppleMusicAuthorizationState.Status(status)
                return "Apple Music access is \(appStatus.sonoicDisplayName.lowercased())."
            case let .requestFailed(failure):
                return failure.displayDetail
            }
        }
    }

    private let requestGate = SonoicMusicKitRequestGate()

    func currentAuthorizationState() -> SonoicAppleMusicAuthorizationState {
        SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(MusicAuthorization.currentStatus))
    }

    func requestAuthorizationState() async -> SonoicAppleMusicAuthorizationState {
        let status = await MusicAuthorization.request()
        return SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(status))
    }

    func fetchServiceDetails() async throws -> SonoicAppleMusicServiceDetails {
        do {
            let metadata = try await requestGate.fetchServiceDetails()

            return .loaded(
                storefrontCountryCode: metadata.storefrontCountryCode,
                canPlayCatalogContent: metadata.canPlayCatalogContent,
                canBecomeSubscriber: metadata.canBecomeSubscriber,
                hasCloudLibraryEnabled: metadata.hasCloudLibraryEnabled
            )
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .serviceDetails)
        }
    }

    func searchCatalog(
        term: String,
        scope: SonoicSourceSearchScope = .all
    ) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .search)
        }

        do {
            return try await requestGate.searchCatalog(
                term: term,
                scope: scope,
                limit: searchRequestLimit(for: scope),
                totalLimit: searchTotalLimit(for: scope)
            )
            .map(sourceItem)
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .search)
        }
    }

    func fetchLibraryAlbums(limit: Int = 24, offset: Int? = nil) async throws -> SonoicSourceItemPage {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .library)
        }

        do {
            return sourceItemPage(from: try await requestGate.fetchLibraryAlbums(limit: limit, offset: offset))
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .library)
        }
    }

    func fetchLibraryPlaylists(limit: Int = 24, offset: Int? = nil) async throws -> SonoicSourceItemPage {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .library)
        }

        do {
            return sourceItemPage(from: try await requestGate.fetchLibraryPlaylists(limit: limit, offset: offset))
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .library)
        }
    }

    func fetchLibraryArtists(limit: Int = 50, offset: Int? = nil) async throws -> SonoicSourceItemPage {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .library)
        }

        do {
            return sourceItemPage(from: try await requestGate.fetchLibraryArtists(limit: limit, offset: offset))
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .library)
        }
    }

    func fetchLibrarySongs(limit: Int = 50, offset: Int? = nil) async throws -> SonoicSourceItemPage {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .library)
        }

        do {
            return sourceItemPage(from: try await requestGate.fetchLibrarySongs(limit: limit, offset: offset))
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .library)
        }
    }

    func fetchRecentlyAdded(limit: Int = 10) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .recentlyAdded)
        }

        do {
            return try await requestGate.fetchRecentlyAdded(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .recentlyAdded)
        }
    }

    func fetchBrowseState(for destination: SonoicAppleMusicBrowseDestination) async throws -> SonoicAppleMusicBrowseState {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .browse)
        }

        do {
            switch destination {
            case .popularRecommendations, .appleMusicPlaylists:
                let sections = try await requestGate.fetchTopCharts(for: destination).map { section in
                    SonoicSourceItemDetailSection(
                        id: section.id,
                        title: section.title,
                        subtitle: section.subtitle,
                        items: section.items.map(sourceItem)
                    )
                }
                return SonoicAppleMusicBrowseState(
                    destination: destination,
                    sections: sections,
                    status: .loaded
                )
            case .playlistsForYou:
                let sections = try await requestGate.fetchDefaultRecommendations(limit: 6)
                return browseState(destination: destination, sections: sections)
            case .categories:
                let genres = try await requestGate.fetchCatalogGenres(limit: 24).map { genre in
                    SonoicAppleMusicGenreItem(id: genre.id, title: genre.title)
                }
                return SonoicAppleMusicBrowseState(
                    destination: destination,
                    genres: genres,
                    status: .loaded
                )
            case .radioShows:
                let sections = try await requestGate.fetchLiveRadioStations()
                return browseState(destination: destination, sections: sections)
            case .newReleases:
                return SonoicAppleMusicBrowseState(destination: destination, status: .loaded)
            }
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .browse)
        }
    }

    func fetchItemDetailSections(for item: SonoicSourceItem) async throws -> [SonoicSourceItemDetailSection] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw unauthorizedError(endpointFamily: .itemDetail)
        }

        guard let kind = appleMusicKind(for: item.kind),
              let origin = appleMusicOrigin(for: item.origin, identity: item.sourceReference),
              let serviceItemID = item.sourceReference?.routedID(for: item.origin) ?? item.serviceItemID
        else {
            return []
        }
        let lookup = AppleMusicItemLookup(
            serviceItemID: serviceItemID,
            catalogItemID: item.sourceReference?.catalogID,
            libraryItemID: item.sourceReference?.libraryID,
            title: item.title,
            kind: kind,
            origin: origin
        )

        do {
            return try await requestGate.fetchItemDetailSections(for: lookup).map { section in
                SonoicSourceItemDetailSection(
                    id: section.id,
                    title: section.title,
                    subtitle: section.subtitle,
                    items: section.items.map(sourceItem)
                )
            }
        } catch {
            throw mappedMusicKitError(error, endpointFamily: .itemDetail)
        }
    }

    static func appleMusicRequestFailure(
        from error: Error,
        endpointFamily: SonoicAppleMusicEndpointFamily
    ) -> SonoicAppleMusicRequestFailure {
        let requestFailure = MusicKitRequestFailure(error)
        let message = requestFailure.message.lowercased()
        let kind: SonoicAppleMusicRequestFailureKind

        if case let ClientError.requestFailed(failure) = error {
            return failure
        }

        if case let ClientError.unauthorized(status) = error {
            return SonoicAppleMusicRequestFailure(
                kind: .unauthorized,
                endpointFamily: endpointFamily,
                rawDetail: SonoicAppleMusicAuthorizationState.Status(status).sonoicDisplayName
            )
        }

        if message.contains("developer token") || message.contains("musickit app service") {
            kind = .missingDeveloperTokenSetup
        } else if requestFailure.domain == NSURLErrorDomain {
            kind = .networkUnavailable
        } else if requestFailure.code == 429 || message.contains("rate limit") || message.contains("too many requests") {
            kind = .rateLimited
        } else if message.contains("storefront") || message.contains("country code") {
            kind = .storefrontUnavailable
        } else {
            kind = .unknown
        }

        return SonoicAppleMusicRequestFailure(
            kind: kind,
            endpointFamily: endpointFamily,
            rawDetail: requestFailure.displayDetail
        )
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func unauthorizedError(endpointFamily: SonoicAppleMusicEndpointFamily) -> Error {
        ClientError.requestFailed(
            Self.appleMusicRequestFailure(
                from: ClientError.unauthorized(MusicAuthorization.currentStatus),
                endpointFamily: endpointFamily
            )
        )
    }

    private func searchRequestLimit(for scope: SonoicSourceSearchScope) -> Int {
        switch scope {
        case .all:
            Self.allSearchItemLimitPerGroup
        case .songs, .artists, .albums, .playlists:
            Self.scopedSearchLimit
        }
    }

    private func searchTotalLimit(for scope: SonoicSourceSearchScope) -> Int {
        switch scope {
        case .all:
            Self.allSearchTotalLimit
        case .songs, .artists, .albums, .playlists:
            Self.scopedSearchLimit
        }
    }

    private func mappedMusicKitError(
        _ error: Error,
        endpointFamily: SonoicAppleMusicEndpointFamily
    ) -> Error {
        if Self.isCancellation(error) {
            return error
        }

        return ClientError.requestFailed(Self.appleMusicRequestFailure(from: error, endpointFamily: endpointFamily))
    }
}
