import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonosControlAPITransportTests {
    @Test
    func buildsAuthorizedJSONRequest() throws {
        let transport = SonosControlAPITransport(
            baseURL: try #require(URL(string: "https://api.ws.sonos.com/control/api/v1"))
        )
        let correlationID = try #require(UUID(uuidString: "9A68E68C-5A87-4B56-B103-AE6BE673AB6B"))
        let body = try JSONEncoder().encode(SonosControlAPILoadFavoriteRequest(favoriteId: "favorite-1"))

        let request = try transport.makeRequest(
            path: "/groups/group-1/favorites",
            method: "POST",
            accessToken: "token-1",
            correlationID: correlationID,
            body: body
        )

        #expect(request.url?.absoluteString == "https://api.ws.sonos.com/control/api/v1/groups/group-1/favorites")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "X-Sonos-Corr-Id") == correlationID.uuidString)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Sonoic iOS")
    }

    @Test
    func decodesGroupsResponse() throws {
        let data = """
        {
          "groups": [
            {
              "id": "group-1",
              "name": "Stue",
              "coordinatorId": "player-1",
              "playerIds": ["player-1", "player-2"]
            }
          ],
          "players": [
            {
              "id": "player-1",
              "name": "Arc Ultra",
              "roomName": "Stue",
              "deviceIds": ["device-1"]
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SonosControlAPIGroupsResponse.self, from: data)

        #expect(response.groups.first?.id == "group-1")
        #expect(response.groups.first?.coordinatorId == "player-1")
        #expect(response.groups.first?.playerIds == ["player-1", "player-2"])
        #expect(response.players.first?.roomName == "Stue")
    }

    @Test
    func decodesPlaybackStatusResponse() throws {
        let data = """
        {
          "playbackState": "PLAYBACK_STATE_PLAYING",
          "queueVersion": "queue-1",
          "itemId": "item-1",
          "positionMillis": 42000,
          "previousItemId": "item-0",
          "previousPositionMillis": 120000,
          "playModes": {
            "repeat": true,
            "repeatOne": false,
            "shuffle": true,
            "crossfade": false
          },
          "availablePlaybackActions": {
            "canSkip": true,
            "canSkipBack": true,
            "canSeek": true,
            "canPause": true,
            "canStop": false
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SonosControlAPIPlaybackStatus.self, from: data)

        #expect(response.playbackState == .playing)
        #expect(response.queueVersion == "queue-1")
        #expect(response.itemId == "item-1")
        #expect(response.positionMillis == 42_000)
        #expect(response.playModes?.repeatEnabled == true)
        #expect(response.availablePlaybackActions?.canSeek == true)
    }

    @Test
    func decodesPlaybackMetadataResponse() throws {
        let data = """
        {
          "container": {
            "name": "Easy Mode",
            "type": "playlist",
            "id": {
              "objectId": "playlist-1",
              "serviceId": "204",
              "accountId": "sn_3"
            },
            "service": {
              "name": "Apple Music",
              "id": "204",
              "imageUrl": "https://example.com/apple-music.png"
            },
            "imageUrl": "https://example.com/easy-mode.jpg"
          },
          "currentItem": {
            "id": "item-1",
            "track": {
              "type": "track",
              "name": "Easy",
              "album": {
                "name": "The Definitive Collection"
              },
              "artist": {
                "name": "The Commodores"
              },
              "id": {
                "objectId": "song:123",
                "serviceId": "204",
                "accountId": "sn_3"
              },
              "service": {
                "name": "Apple Music",
                "id": "204"
              },
              "durationMillis": 319000
            },
            "policies": {
              "canSeek": true,
              "canSkipToItem": true,
              "showNNextTracks": 3
            }
          },
          "nextItem": {
            "id": "item-2",
            "track": {
              "name": "Lovely Day",
              "artist": {
                "name": "Bill Withers"
              }
            }
          },
          "streamInfo": "Now playing"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SonosControlAPIMetadataStatus.self, from: data)

        #expect(response.container?.name == "Easy Mode")
        #expect(response.container?.id?.objectId == "playlist-1")
        #expect(response.container?.service?.imageUrl == "https://example.com/apple-music.png")
        #expect(response.currentItem?.id == "item-1")
        #expect(response.currentItem?.track?.name == "Easy")
        #expect(response.currentItem?.track?.album?.name == "The Definitive Collection")
        #expect(response.currentItem?.track?.artist?.name == "The Commodores")
        #expect(response.currentItem?.track?.id?.accountId == "sn_3")
        #expect(response.currentItem?.track?.durationMillis == 319_000)
        #expect(response.currentItem?.policies?.canSeek == true)
        #expect(response.currentItem?.policies?.canSkipToItem == true)
        #expect(response.currentItem?.policies?.showNNextTracks == 3)
        #expect(response.nextItem?.track?.artist?.name == "Bill Withers")
        #expect(response.streamInfo == "Now playing")
    }

    @Test
    func encodesSeekRequestsWithOptionalItemID() throws {
        let absolute = SonosControlAPISeekRequest(positionMillis: 30_000, itemId: "item-1")
        let relative = SonosControlAPISeekRelativeRequest(deltaMillis: -5_000, itemId: nil)

        let absoluteObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(absolute)
        ) as? [String: Any]
        let relativeObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(relative)
        ) as? [String: Any]

        #expect(absoluteObject?["positionMillis"] as? Int == 30_000)
        #expect(absoluteObject?["itemId"] as? String == "item-1")
        #expect(relativeObject?["deltaMillis"] as? Int == -5_000)
        #expect(relativeObject?["itemId"] == nil)
    }

    @Test
    func encodesPlaybackSessionRequests() throws {
        let session = SonosControlAPICreateSessionRequest(
            appId: "com.markusskov.Sonoic",
            appContext: "iphone-1",
            accountId: "sn_3",
            customData: "playlist:easy-mode"
        )
        let track = SonosControlAPITrack(
            type: "track",
            name: "Easy",
            mediaUrl: nil,
            imageUrl: nil,
            contentType: nil,
            album: SonosControlAPIAlbum(
                name: "The Definitive Collection",
                artist: nil,
                id: nil
            ),
            artist: SonosControlAPIArtist(
                name: "The Commodores",
                id: nil
            ),
            id: SonosControlAPIUniversalMusicObjectID(
                serviceId: "204",
                objectId: "song:123",
                accountId: "sn_3"
            ),
            service: SonosControlAPIService(
                id: "204",
                name: "Apple Music",
                imageUrl: nil
            ),
            durationMillis: 319_000,
            trackNumber: nil,
            quality: nil
        )
        let load = SonosControlAPILoadCloudQueueRequest(
            queueBaseUrl: "https://sonoic.example/queue/v1.0",
            httpAuthorization: "Bearer queue-token",
            useHttpAuthorizationForMedia: false,
            itemId: "item-1",
            queueVersion: "queue-v1",
            positionMillis: 0,
            playOnCompletion: true,
            trackMetadata: track
        )
        let skip = SonosControlAPISkipToItemRequest(
            itemId: "item-2",
            queueVersion: "queue-v2",
            positionMillis: 12_000,
            playOnCompletion: true,
            trackMetadata: track
        )

        let sessionObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(session)
        ) as? [String: Any]
        let loadObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(load)
        ) as? [String: Any]
        let skipObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(skip)
        ) as? [String: Any]
        let loadTrack = loadObject?["trackMetadata"] as? [String: Any]
        let loadArtist = loadTrack?["artist"] as? [String: Any]
        let skipTrack = skipObject?["trackMetadata"] as? [String: Any]

        #expect(sessionObject?["appId"] as? String == "com.markusskov.Sonoic")
        #expect(sessionObject?["appContext"] as? String == "iphone-1")
        #expect(sessionObject?["accountId"] as? String == "sn_3")
        #expect(loadObject?["queueBaseUrl"] as? String == "https://sonoic.example/queue/v1.0")
        #expect(loadObject?["httpAuthorization"] as? String == "Bearer queue-token")
        #expect(loadObject?["playOnCompletion"] as? Bool == true)
        #expect(loadTrack?["name"] as? String == "Easy")
        #expect(loadArtist?["name"] as? String == "The Commodores")
        #expect(skipObject?["itemId"] as? String == "item-2")
        #expect(skipObject?["positionMillis"] as? Int == 12_000)
        #expect(skipTrack?["durationMillis"] as? Int == 319_000)
    }

    @Test
    func settingsRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "SonosControlAPITransportTests-\(UUID().uuidString)")!
        let store = SonoicSettingsStore(userDefaults: defaults)
        let settings = SonosControlAPISettings(
            mode: .diagnosticsOnly,
            selectedHouseholdID: "household-1",
            selectedGroupID: "group-1"
        )

        store.saveSonosControlAPISettings(settings)

        #expect(store.loadSonosControlAPISettings() == settings)
    }
}
