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
