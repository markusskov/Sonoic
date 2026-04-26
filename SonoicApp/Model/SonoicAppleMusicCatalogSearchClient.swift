import Foundation
@preconcurrency import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)
        case missingDeveloperTokenSetup(MusicKitRequestFailure)

        var errorDescription: String? {
            switch self {
            case let .unauthorized(status):
                let appStatus = SonoicAppleMusicAuthorizationState.Status(status)
                return "Apple Music access is \(appStatus.sonoicDisplayName.lowercased())."
            case let .missingDeveloperTokenSetup(failure):
                return """
                MusicKit could not receive Apple's automatic developer token for this bundle. Confirm MusicKit is enabled for com.markusskov.Sonoic in Apple Developer, then rebuild after the App ID has propagated.

                \(failure.displayDetail)
                """
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
            throw mappedMusicKitError(error)
        }
    }

    func searchCatalog(
        term: String,
        scope: SonoicSourceSearchScope = .all
    ) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.searchCatalog(term: term, scope: scope, limit: 12).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryAlbums(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryAlbums(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryPlaylists(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryPlaylists(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryArtists(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryArtists(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibrarySongs(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibrarySongs(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchRecentlyAdded(limit: Int = 10) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchRecentlyAdded(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchBrowseState(for destination: SonoicAppleMusicBrowseDestination) async throws -> SonoicAppleMusicBrowseState {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            switch destination {
            case .popularRecommendations, .appleMusicPlaylists:
                let sections = try await requestGate.fetchTopCharts(for: destination).map { section in
                    SonoicAppleMusicItemDetailSection(
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
            case .categories:
                let genres = try await requestGate.fetchCatalogGenres(limit: 24).map { genre in
                    SonoicAppleMusicGenreItem(id: genre.id, title: genre.title)
                }
                return SonoicAppleMusicBrowseState(
                    destination: destination,
                    genres: genres,
                    status: .loaded
                )
            case .playlistsForYou, .newReleases, .radioShows:
                return SonoicAppleMusicBrowseState(destination: destination, status: .loaded)
            }
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchItemDetailSections(for item: SonoicSourceItem) async throws -> [SonoicAppleMusicItemDetailSection] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        guard let serviceItemID = item.serviceItemID else {
            return []
        }
        guard let kind = appleMusicKind(for: item.kind),
              let origin = appleMusicOrigin(for: item.origin)
        else {
            return []
        }
        let lookup = AppleMusicItemLookup(
            serviceItemID: serviceItemID,
            catalogItemID: item.appleMusicIdentity?.catalogID,
            libraryItemID: item.appleMusicIdentity?.libraryID,
            title: item.title,
            kind: kind,
            origin: origin
        )

        do {
            return try await requestGate.fetchItemDetailSections(for: lookup).map { section in
                SonoicAppleMusicItemDetailSection(
                    id: section.id,
                    title: section.title,
                    subtitle: section.subtitle,
                    items: section.items.map(sourceItem)
                )
            }
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    private func mappedMusicKitError(_ error: Error) -> Error {
        if error.localizedDescription.localizedCaseInsensitiveContains("developer token") {
            return ClientError.missingDeveloperTokenSetup(MusicKitRequestFailure(error))
        }

        return error
    }

    private func sourceItem(from metadata: AppleMusicItemMetadata) -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: metadata.serviceItemID,
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkURL: metadata.artworkURL,
            kind: sourceKind(for: metadata.kind),
            origin: sourceOrigin(for: metadata.origin),
            catalogID: metadata.catalogItemID,
            libraryID: metadata.libraryItemID
        )
    }

    private func appleMusicKind(for sourceKind: SonoicSourceItem.Kind) -> AppleMusicItemKind? {
        switch sourceKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        case .station, .unknown:
            nil
        }
    }

    private func appleMusicOrigin(for sourceOrigin: SonoicSourceItem.Origin) -> AppleMusicItemOrigin? {
        switch sourceOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        case .favorite, .recentPlay:
            nil
        }
    }

    private func sourceKind(for appleMusicKind: AppleMusicItemKind) -> SonoicSourceItem.Kind {
        switch appleMusicKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        }
    }

    private func sourceOrigin(for appleMusicOrigin: AppleMusicItemOrigin) -> SonoicSourceItem.Origin {
        switch appleMusicOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        }
    }
}

struct MusicKitRequestFailure: Equatable {
    var domain: String
    var code: Int
    var message: String

    init(_ error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
    }

    nonisolated var displayDetail: String {
        "\(domain) \(code): \(message)"
    }
}

extension SonoicAppleMusicAuthorizationState.Status {
    nonisolated init(_ musicAuthorizationStatus: MusicAuthorization.Status) {
        switch musicAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unavailable
        }
    }

    nonisolated var sonoicDisplayName: String {
        switch self {
        case .notDetermined:
            "Not Determined"
        case .requesting:
            "Requesting"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .authorized:
            "Authorized"
        case .unavailable:
            "Unavailable"
        @unknown default:
            "Unavailable"
        }
    }
}
