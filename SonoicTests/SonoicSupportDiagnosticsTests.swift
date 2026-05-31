import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicSupportDiagnosticsTests {
    @Test
    func supportDiagnosticsRedactsSecretsHostsAndRawSonosIdentifiers() throws {
        let model = try makeModel()
        let githubToken = "gho_" + "abcdefghijklmnopqrstuvwx"
        let jwt = [
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "eyJzdWIiOiIxMjM0NSJ9",
            "signaturesecret"
        ].joined(separator: ".")
        model.manualSonosHost = "192.168.1.25"
        model.activeTarget = SonosActiveTarget(
            id: "RINCON_C43875141A0301400",
            name: "Stue",
            householdName: "Home",
            kind: .group,
            memberNames: ["Stue", "Kitchen"]
        )
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Private Song",
            artistName: "Private Artist",
            albumTitle: nil,
            sourceName: "Apple Music access_token=source-token",
            playbackState: .playing
        )
        model.sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(
            status: .failed("Authorization: Bearer sonos-access-token-12345")
        )
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-secret",
                selectedGroupID: "group-secret"
            ),
            authorizationStatus: .expired,
            lastErrorDetail: """
            HTTP 401 from http://192.168.1.25/control?refresh_token=refresh-secret \
            for RINCON_C43875141A0301400 using \(githubToken)
            """,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
        model.sonosControlAPICloudState = SonosControlAPICloudState(
            status: .failed("Worker failure client_secret=sonos-client-secret")
        )
        model.queueState = .failed("Queue failed at 192.168.1.25 with access_token=queue-token")
        model.queueOperationErrorDetail = "Authorization Bearer queue-operation-token-12345 \(jwt)"
        model.queueDiagnostics = SonosQueueDiagnostics(
            observedAt: nil,
            currentURI: "x-rincon-queue:RINCON_C43875141A0301400#0",
            itemCount: nil,
            lastRefreshErrorDetail: "Refresh failed at 192.168.1.25",
            lastMutationErrorDetail: "{\"refresh_token\":\"json-refresh-secret\"}"
        )
        model.seekDiagnostics = SonosSeekDiagnostics(
            status: .failed,
            requestedAt: nil,
            host: "192.168.1.25",
            target: nil,
            observed: nil,
            errorDetail: "Seek failed for RINCON_C43875141A0301400"
        )
        model.discoveryErrorDetail = "Discovery failed on 192.168.1.25"

        let summary = model.supportDiagnosticsSummary(
            generatedAt: Date(timeIntervalSince1970: 0),
            bundle: .main
        )

        #expect(summary.contains("Sonoic Support Summary"))
        #expect(summary.contains("Sonos Auth: Expired"))
        #expect(summary.contains("Target: Group selected · members=2"))
        #expect(summary.contains("Bearer <redacted>"))
        #expect(summary.contains("<ip-address>"))
        #expect(summary.contains("<sonos-player-id>"))
        #expect(summary.contains("<redacted-token>"))
        #expect(summary.contains("<redacted-jwt>"))
        #expect(!summary.contains("192.168.1.25"))
        #expect(!summary.contains("RINCON_C43875141A0301400"))
        #expect(!summary.contains("sonos-access-token-12345"))
        #expect(!summary.contains("refresh-secret"))
        #expect(!summary.contains("sonos-client-secret"))
        #expect(!summary.contains("json-refresh-secret"))
        #expect(!summary.contains(githubToken))
        #expect(!summary.contains(jwt))
        #expect(!summary.contains("Private Song"))
        #expect(!summary.contains("Private Artist"))
        #expect(!summary.contains("household-secret"))
        #expect(!summary.contains("group-secret"))
    }

    @Test
    func supportDiagnosticsKeepsActionableCloudQueueAndPlaybackState() throws {
        let model = try makeModel()
        model.manualSonosHost = "10.0.0.42"
        model.activeTarget = SonosActiveTarget(
            id: "RINCON_C43875141A0301400",
            name: "Living Room",
            householdName: "Home",
            kind: .room,
            memberNames: []
        )
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Current Track",
            artistName: nil,
            albumTitle: nil,
            sourceName: "Apple Music",
            playbackState: .buffering
        )
        model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-1",
                        title: "One",
                        artistName: nil,
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: nil
                    ),
                    SonosQueueItem(
                        id: "item-2",
                        title: "Two",
                        artistName: nil,
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: nil
                    )
                ],
                currentItemIndex: 1,
                sourceURI: "x-rincon-queue:RINCON_C43875141A0301400#0"
            )
        )
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .ready,
            lastErrorDetail: nil,
            lastCommandDescription: "Cloud favorite",
            lastUpdatedAt: Date(timeIntervalSince1970: 12)
        )
        model.sonosControlAPICloudState = SonosControlAPICloudState(
            status: .verified(
                SonosControlAPICloudSnapshot(
                    households: [
                        SonosControlAPIHousehold(id: "household-1")
                    ],
                    groupsByHouseholdID: [
                        "household-1": SonosControlAPIGroupSnapshot(
                            groups: [
                                SonosControlAPIGroup(
                                    id: "group-1",
                                    name: "Living Room",
                                    coordinatorId: "RINCON_C43875141A0301400",
                                    playerIds: ["RINCON_C43875141A0301400"]
                                )
                            ],
                            players: [
                                SonosControlAPIPlayer(
                                    id: "RINCON_C43875141A0301400",
                                    name: "Living Room",
                                    roomName: "Living Room",
                                    deviceIds: nil
                                )
                            ]
                        )
                    ],
                    favoritesByHouseholdID: [
                        "household-1": [
                            SonosControlAPIFavorite(
                                id: "favorite-1",
                                name: "Favorite One",
                                description: nil,
                                imageUrl: nil,
                                service: nil
                            )
                        ]
                    ],
                    playlistsByHouseholdID: [
                        "household-1": [
                            SonosControlAPIPlaylist(
                                id: "playlist-1",
                                name: "Playlist One",
                                type: nil,
                                trackCount: nil
                            )
                        ]
                    ],
                    contentFetchDiagnosticsByHouseholdID: [
                        "household-1": SonosControlAPICloudContentFetchDiagnostics(
                            favorites: .loaded(count: 1, version: nil),
                            playlists: .failed(
                                detail: "Missing CodingKeys(stringValue: \"items\") at 10.0.0.42?token=playlist-token",
                                isAuthorizationFailure: false
                            )
                        )
                    ]
                )
            )
        )

        let summary = model.supportDiagnosticsSummary(
            generatedAt: Date(timeIntervalSince1970: 0),
            bundle: .main
        )

        #expect(summary.contains("Sonos Auth: Ready"))
        #expect(summary.contains("Sonos Cloud: Verified · households=1 · groups=1 · players=1 · favorites=1 · playlists=1"))
        #expect(summary.contains("favorites loaded count=1 version=none"))
        #expect(summary.contains("playlists failed auth=no detail="))
        #expect(summary.contains("Playback: Buffering · Source: Apple Music"))
        #expect(summary.contains("Queue: Loaded · items=2 · current=2"))
        #expect(summary.contains("Last Control API Command: Cloud favorite"))
        #expect(!summary.contains("Current Track"))
        #expect(!summary.contains("RINCON_C43875141A0301400"))
        #expect(!summary.contains("group-1"))
        #expect(!summary.contains("household-1"))
        #expect(!summary.contains("10.0.0.42"))
        #expect(!summary.contains("playlist-token"))
    }

    @Test
    func diagnosticsRedactorTruncatesLongValuesAfterRedaction() {
        let value = "Bearer very-secret-token-12345 " + String(repeating: "diagnostic ", count: 80)

        let redacted = SonoicDiagnosticsRedactor.redacted(value, maxLength: 80)

        #expect(redacted.count == 83)
        #expect(redacted.hasSuffix("..."))
        #expect(!redacted.contains("very-secret-token-12345"))
        #expect(redacted.contains("Bearer <redacted>"))
    }

    private func makeModel() throws -> SonoicModel {
        let suiteName = "SonoicSupportDiagnosticsTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            startInitialSonosControlAPICloudRefresh: false
        )
    }
}
