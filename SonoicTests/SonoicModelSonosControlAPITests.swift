import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicModelSonosControlAPITests {
    @Test
    func cloudCommandFailuresRollbackOptimisticState() async throws {
        let directPlayback = try Self.makeModel()
        defer {
            try? directPlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.responder = nil
        }
        Self.configureCloudCommandTarget(on: directPlayback.model)
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Play", playbackState: .paused)
        let previousNowPlayingObservedAt = Date(timeIntervalSince1970: 123)
        directPlayback.model.nowPlaying = previousNowPlaying
        directPlayback.model.nowPlayingObservedAt = previousNowPlayingObservedAt
        directPlayback.model.sonosControlAPICloudQueueSessionID = "session-before"
        directPlayback.model.sonosControlAPICloudQueueGroupID = "group-1"
        directPlayback.model.sonosControlAPICloudQueueVersion = "queue-before"
        directPlayback.model.sonosControlAPICloudQueueItemIDs = ["item-before"]

        Self.stubNetwork { request in
            Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected authorization failure"}"#
            )
        }

        let didPlay = await directPlayback.model.playSonosControlAPIPlaybackIfAvailable()

        #expect(didPlay == false)
        #expect(directPlayback.model.nowPlaying == previousNowPlaying)
        #expect(directPlayback.model.nowPlayingObservedAt == previousNowPlayingObservedAt)
        #expect(directPlayback.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(directPlayback.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(directPlayback.model.sonosControlAPICloudQueueSessionID == nil)
        #expect(directPlayback.model.sonosControlAPICloudQueueItemIDs == nil)
        #expect(directPlayback.model.isManualTransportCommandInFlight == false)
        #expect(directPlayback.model.isManualPlayTransitionAwaitingConfirmation == false)

        let cloudQueue = try Self.makeModel()
        defer {
            try? cloudQueue.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.responder = nil
        }
        Self.configureCloudCommandTarget(on: cloudQueue.model)
        let previousQueueState = SonosQueueState.loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "1",
                        title: "Previous",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 120
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        let previousCloudQueueTracks = [
            Self.track(id: "previous-track", name: "Previous Track")
        ]
        let previousPayload = Self.playbackPayload(id: "previous-payload")
        let previousNowPlayingForQueue = Self.nowPlayingSnapshot(title: "Before Queue", playbackState: .playing)
        cloudQueue.model.queueState = previousQueueState
        cloudQueue.model.nowPlaying = previousNowPlayingForQueue
        cloudQueue.model.manualPlaybackContextPayload = previousPayload
        cloudQueue.model.manualQueueContextPayloads = [previousPayload]
        cloudQueue.model.manualRecentPlaybackContextPayload = previousPayload
        cloudQueue.model.sonosControlAPICloudQueueSessionID = "session-before"
        cloudQueue.model.sonosControlAPICloudQueueGroupID = "group-before"
        cloudQueue.model.sonosControlAPICloudQueueVersion = "queue-before"
        cloudQueue.model.sonosControlAPICloudQueueItemIDs = ["item-before"]
        cloudQueue.model.sonosControlAPICloudQueueTracks = previousCloudQueueTracks

        Self.stubNetwork { request in
            Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected cloud queue failure"}"#
            )
        }

        let didLoadQueue = await cloudQueue.model.playSonosControlAPICloudQueueIfAvailable(
            parentItem: Self.playlistItem(),
            plan: Self.playlistPlan()
        )

        #expect(didLoadQueue == false)
        #expect(cloudQueue.model.queueState == previousQueueState)
        #expect(cloudQueue.model.nowPlaying == previousNowPlayingForQueue)
        #expect(cloudQueue.model.manualPlaybackContextPayload == previousPayload)
        #expect(cloudQueue.model.manualQueueContextPayloads == [previousPayload])
        #expect(cloudQueue.model.manualRecentPlaybackContextPayload == previousPayload)
        #expect(cloudQueue.model.sonosControlAPICloudQueueSessionID == "session-before")
        #expect(cloudQueue.model.sonosControlAPICloudQueueGroupID == "group-before")
        #expect(cloudQueue.model.sonosControlAPICloudQueueVersion == "queue-before")
        #expect(cloudQueue.model.sonosControlAPICloudQueueItemIDs == ["item-before"])
        #expect(cloudQueue.model.sonosControlAPICloudQueueTracks == previousCloudQueueTracks)
        #expect(cloudQueue.model.isManualTransportCommandInFlight == false)
        #expect(cloudQueue.model.sonosControlAPIState.authorizationStatus == .ready)
    }

    @Test
    func cloudSkipFailureRestoresPayloadAndFreshness() async throws {
        let next = try Self.makeModel()
        defer {
            try? next.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.responder = nil
        }
        Self.configureCloudCommandTarget(on: next.model)
        let previousPayload = Self.playbackPayload(id: "current-payload")
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Next", playbackState: .buffering)
        let previousObservedAt = Date(timeIntervalSince1970: 456)
        next.model.manualPlaybackContextPayload = previousPayload
        next.model.nowPlaying = previousNowPlaying
        next.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork { request in
            Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected next failure"}"#
            )
        }

        let didSkipNext = await next.model.skipToNextSonosControlAPITrackIfAvailable()

        #expect(didSkipNext == false)
        #expect(next.model.nowPlaying == previousNowPlaying)
        #expect(next.model.nowPlayingObservedAt == previousObservedAt)
        #expect(next.model.manualPlaybackContextPayload == previousPayload)

        let previous = try Self.makeModel()
        defer {
            try? previous.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.responder = nil
        }
        Self.configureCloudCommandTarget(on: previous.model)
        previous.model.manualPlaybackContextPayload = previousPayload
        previous.model.nowPlaying = previousNowPlaying
        previous.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork { request in
            Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected previous failure"}"#
            )
        }

        let didSkipPrevious = await previous.model.skipToPreviousSonosControlAPITrackIfAvailable()

        #expect(didSkipPrevious == false)
        #expect(previous.model.nowPlaying == previousNowPlaying)
        #expect(previous.model.nowPlayingObservedAt == previousObservedAt)
        #expect(previous.model.manualPlaybackContextPayload == previousPayload)
    }

    private static func makeModel() throws -> (model: SonoicModel, keychainStore: SonoicKeychainStore) {
        let keychainStore = SonoicKeychainStore(
            service: "com.markusskov.Sonoic.tests.\(UUID().uuidString)"
        )
        try keychainStore.saveSonosTokenSet(
            SonosOAuthTokenSet(
                accessToken: "access-token",
                refreshToken: nil,
                tokenType: "Bearer",
                scope: nil,
                expiresAt: Date().addingTimeInterval(3_600)
            )
        )

        let userDefaults = try #require(
            UserDefaults(suiteName: "SonoicModelSonosControlAPITests-\(UUID().uuidString)")
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SonoicModelSonosControlAPIURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let model = SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            sonosControlAPIClient: SonosControlAPIClient(
                transport: SonosControlAPITransport(
                    baseURL: URL(string: "https://sonos.test/control/api/v1")!,
                    urlSession: session
                )
            ),
            sonosOAuthConfiguration: Self.oauthConfiguration,
            sonoicCloudQueueClient: SonoicCloudQueueClient(session: session),
            keychainStore: keychainStore,
            startInitialSonosControlAPICloudRefresh: false
        )

        return (model, keychainStore)
    }

    private static func configureCloudCommandTarget(on model: SonoicModel) {
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .ready,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
        model.sonosControlAPICloudState = SonosControlAPICloudState(status: .verified(Self.cloudSnapshot))
        model.activeTarget = SonosActiveTarget(
            id: "group-1",
            name: "Kitchen",
            householdName: "Kitchen",
            kind: .group,
            memberNames: ["Kitchen"]
        )
    }

    private static func stubNetwork(
        _ responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        SonoicModelSonosControlAPIURLProtocol.responder = responder
    }

    nonisolated private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static var oauthConfiguration: SonosOAuthConfiguration {
        SonosOAuthConfiguration(
            clientID: "client-id",
            redirectURI: "https://sonoic.test/callback",
            callbackScheme: "sonoic",
            tokenExchangeURL: URL(string: "https://sonoic.test/api/token")!,
            tokenRefreshURL: nil,
            authorizationEndpoint: URL(string: "https://api.sonos.com/login/v3/oauth")!,
            scopes: ["playback-control-all"],
            cloudQueueCreateURL: URL(string: "https://sonoic.test/api/sonos/cloud-queues")!
        )
    }

    private static var cloudSnapshot: SonosControlAPICloudSnapshot {
        SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-1",
                            name: "Kitchen",
                            coordinatorId: "player-1",
                            playerIds: ["player-1"]
                        )
                    ],
                    players: [
                        SonosControlAPIPlayer(
                            id: "player-1",
                            name: "Kitchen",
                            roomName: "Kitchen",
                            deviceIds: nil
                        )
                    ]
                )
            ]
        )
    }

    private static func playlistItem() -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "playlist-1",
            title: "Cloud Queue",
            subtitle: "Sonoic",
            artworkURL: nil,
            kind: .playlist,
            origin: .library,
            catalogID: "playlist-1"
        )
    }

    private static func playlistPlan() -> SonoicSourcePlaylistPlaybackPlan {
        let payload = Self.playbackPayload(id: "queue-track-1")
        let item = SonoicSourceItem(
            id: "queue-track-1",
            title: "Queue Track",
            subtitle: "Sonoic",
            artworkURL: nil,
            artworkIdentifier: nil,
            sourceReference: .appleMusic(
                catalogID: "queue-track-1",
                libraryID: nil,
                kind: .song
            ),
            service: .appleMusic,
            origin: .catalogSearch,
            kind: .song,
            playbackCapability: .sonosNative(payload),
            duration: payload.duration
        )

        return SonoicSourcePlaylistPlaybackPlan(
            payloads: [payload],
            items: [item],
            startingTrackNumber: 1,
            localNowPlayingPayload: payload,
            recentPlaybackPayload: payload
        )
    }

    private static func playbackPayload(id: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Queue Track",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            uri: "x-sonos-http:song:\(id).m4p",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 180
        )
    }

    private static func track(id: String, name: String) -> SonosControlAPITrack {
        SonosControlAPITrack(
            type: "track",
            name: name,
            mediaUrl: nil,
            imageUrl: nil,
            contentType: "audio/mp4",
            album: nil,
            artist: SonosControlAPIArtist(name: "Sonoic", id: nil),
            id: SonosControlAPIUniversalMusicObjectID(
                serviceId: "204",
                objectId: "song:\(id)",
                accountId: nil
            ),
            service: SonosControlAPIService(id: "204", name: "Apple Music", imageUrl: nil),
            durationMillis: 180_000,
            trackNumber: nil,
            quality: nil
        )
    }

    private static func nowPlayingSnapshot(
        title: String,
        playbackState: SonosNowPlayingSnapshot.PlaybackState
    ) -> SonosNowPlayingSnapshot {
        SonosNowPlayingSnapshot(
            title: title,
            artistName: "Sonoic",
            albumTitle: "Cloud",
            sourceName: "Apple Music",
            playbackState: playbackState,
            elapsedTime: 10,
            duration: 180
        )
    }
}

private final class SonoicModelSonosControlAPIURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
