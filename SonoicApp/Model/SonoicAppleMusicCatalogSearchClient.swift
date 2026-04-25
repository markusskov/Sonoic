import Foundation
import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)
        case missingDeveloperTokenSetup

        var errorDescription: String? {
            switch self {
            case let .unauthorized(status):
                let appStatus = SonoicAppleMusicAuthorizationState.Status(status)
                return "Apple Music access is \(appStatus.sonoicDisplayName.lowercased())."
            case .missingDeveloperTokenSetup:
                return "Enable MusicKit for Sonoic's App ID and provisioning profile, then rebuild the app."
            }
        }
    }

    func currentAuthorizationState() -> SonoicAppleMusicAuthorizationState {
        SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(MusicAuthorization.currentStatus))
    }

    func requestAuthorizationState() async -> SonoicAppleMusicAuthorizationState {
        let status = await MusicAuthorization.request()
        return SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(status))
    }

    func fetchServiceDetails() async throws -> SonoicAppleMusicServiceDetails {
        do {
            async let subscription = MusicSubscription.current
            async let storefrontCountryCode = MusicDataRequest.currentCountryCode

            let resolvedSubscription = try await subscription
            let resolvedStorefrontCountryCode = try await storefrontCountryCode

            return .loaded(
                storefrontCountryCode: resolvedStorefrontCountryCode,
                canPlayCatalogContent: resolvedSubscription.canPlayCatalogContent,
                canBecomeSubscriber: resolvedSubscription.canBecomeSubscriber,
                hasCloudLibraryEnabled: resolvedSubscription.hasCloudLibraryEnabled
            )
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func searchCatalog(term: String) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Song.self, Album.self]
        )
        request.limit = 8

        let response: MusicCatalogSearchResponse
        do {
            response = try await request.response()
        } catch {
            throw mappedMusicKitError(error)
        }

        let songs = response.songs.map { song in
            SonoicSourceItem.catalogMetadata(
                id: "song-\(song.id)",
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                service: .appleMusic
            )
        }
        let albums = response.albums.map { album in
            SonoicSourceItem.catalogMetadata(
                id: "album-\(album.id)",
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                service: .appleMusic
            )
        }

        return Array((songs + albums).prefix(8))
    }

    private func mappedMusicKitError(_ error: Error) -> Error {
        if error.localizedDescription.localizedCaseInsensitiveContains("developer token") {
            return ClientError.missingDeveloperTokenSetup
        }

        return error
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
