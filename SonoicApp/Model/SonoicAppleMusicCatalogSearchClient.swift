import Foundation
@preconcurrency import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)
        case missingDeveloperTokenSetup(MusicKitRequestFailure)
        case timedOut

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
            case .timedOut:
                return "Apple Music did not respond. Try again in a moment."
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
            async let subscription = withMusicKitTimeout {
                try await MusicSubscription.current
            }
            async let storefrontCountryCode = withMusicKitTimeout {
                try await MusicDataRequest.currentCountryCode
            }

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
        let configuredRequest = request

        let response: MusicCatalogSearchResponse
        do {
            response = try await withMusicKitTimeout {
                try await configuredRequest.response()
            }
        } catch {
            throw mappedMusicKitError(error)
        }

        let songs = response.songs.map { song in
            SonoicSourceItem.catalogMetadata(
                id: "song-\(song.id)",
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .song,
                service: .appleMusic
            )
        }
        let albums = response.albums.map { album in
            SonoicSourceItem.catalogMetadata(
                id: "album-\(album.id)",
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .album,
                service: .appleMusic
            )
        }

        return Array((songs + albums).prefix(8))
    }

    func fetchLibraryAlbums(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        var request = MusicLibraryRequest<Album>()
        request.limit = limit
        let configuredRequest = request

        let response: MusicLibraryResponse<Album>
        do {
            response = try await withMusicKitTimeout {
                try await configuredRequest.response()
            }
        } catch {
            throw mappedMusicKitError(error)
        }

        return response.items.map { album in
            SonoicSourceItem.catalogMetadata(
                id: "library-album-\(album.id)",
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .album,
                service: .appleMusic
            )
        }
    }

    func fetchLibraryPlaylists(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        let configuredRequest = request

        let response: MusicLibraryResponse<Playlist>
        do {
            response = try await withMusicKitTimeout {
                try await configuredRequest.response()
            }
        } catch {
            throw mappedMusicKitError(error)
        }

        return response.items.map { playlist in
            SonoicSourceItem.catalogMetadata(
                id: "library-playlist-\(playlist.id)",
                title: playlist.name,
                subtitle: playlist.curatorName,
                artworkURL: playlist.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .playlist,
                service: .appleMusic
            )
        }
    }

    func fetchLibraryArtists(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        var request = MusicLibraryRequest<Artist>()
        request.limit = limit
        let configuredRequest = request

        let response: MusicLibraryResponse<Artist>
        do {
            response = try await withMusicKitTimeout {
                try await configuredRequest.response()
            }
        } catch {
            throw mappedMusicKitError(error)
        }

        return response.items.map { artist in
            SonoicSourceItem.catalogMetadata(
                id: "library-artist-\(artist.id)",
                title: artist.name,
                subtitle: "Artist",
                artworkURL: artist.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .artist,
                service: .appleMusic
            )
        }
    }

    func fetchLibrarySongs(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        var request = MusicLibraryRequest<Song>()
        request.limit = limit
        let configuredRequest = request

        let response: MusicLibraryResponse<Song>
        do {
            response = try await withMusicKitTimeout {
                try await configuredRequest.response()
            }
        } catch {
            throw mappedMusicKitError(error)
        }

        return response.items.map { song in
            SonoicSourceItem.catalogMetadata(
                id: "library-song-\(song.id)",
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .song,
                service: .appleMusic
            )
        }
    }

    private func mappedMusicKitError(_ error: Error) -> Error {
        if error.localizedDescription.localizedCaseInsensitiveContains("developer token") {
            return ClientError.missingDeveloperTokenSetup(MusicKitRequestFailure(error))
        }

        return error
    }

    private func withMusicKitTimeout<Value: Sendable>(
        _ duration: Duration = .seconds(8),
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let box = MusicKitTimeoutBox<Value>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.setContinuation(continuation)

                let operationTask = Task {
                    do {
                        let value = try await operation()
                        box.resume(.success(value))
                    } catch {
                        box.resume(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: duration)
                        box.resume(.failure(ClientError.timedOut))
                    } catch {
                        // The timeout task is canceled when the operation wins the race.
                    }
                }
                box.setTasks(operationTask: operationTask, timeoutTask: timeoutTask)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private nonisolated final class MusicKitTimeoutBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResolved = false
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func setContinuation(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if hasResolved {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func setTasks(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        lock.lock()
        if hasResolved {
            lock.unlock()
            operationTask.cancel()
            timeoutTask.cancel()
        } else {
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
            lock.unlock()
        }
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        guard !hasResolved else {
            lock.unlock()
            return
        }
        hasResolved = true
        let continuation = continuation
        self.continuation = nil
        let operationTask = operationTask
        let timeoutTask = timeoutTask
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }

    func cancel() {
        resume(.failure(CancellationError()))
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
