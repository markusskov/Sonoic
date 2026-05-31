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
    func getSendsAuthorizedRequestWithoutJSONContentTypeAndDecodesResponse() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"households":[{"id":"household-1"}]}"#
            )
        }
        defer { stub.cleanup() }
        let correlationID = try #require(UUID(uuidString: "4A16584F-183D-40DB-BF32-1B051756AF63"))

        let response: SonosControlAPIHouseholdsResponse = try await stub.transport.get(
            "/households",
            accessToken: "token-1",
            correlationID: correlationID
        )

        let request = try #require(recorder.requests.first)
        #expect(response.households == [SonosControlAPIHousehold(id: "household-1")])
        #expect(request.url?.path == "/control/api/v1/households")
        #expect(request.httpMethod == "GET")
        #expect(request.body == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "X-Sonos-Corr-Id") == correlationID.uuidString)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test
    func clientFetchCloudSnapshotRecordsContentCounts() async throws {
        let stub = try Self.stubbedTransport { request in
            switch request.url?.path {
            case "/control/api/v1/households":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"households":[{"id":"household-1"}]}"#
                )
            case "/control/api/v1/households/household-1/groups":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "groups": [
                        {
                          "id": "group-1",
                          "name": "Kitchen",
                          "coordinatorId": "player-1",
                          "playerIds": ["player-1"]
                        }
                      ],
                      "players": [
                        {
                          "id": "player-1",
                          "name": "Kitchen",
                          "roomName": "Kitchen"
                        }
                      ]
                    }
                    """
                )
            case "/control/api/v1/households/household-1/favorites":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"version":"favorites-v1","items":[]}"#
                )
            case "/control/api/v1/households/household-1/playlists":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "version": "playlists-v1",
                      "playlists": [
                        {
                          "id": "playlist-1",
                          "name": "Morning",
                          "type": "playlist",
                          "trackCount": 12
                        },
                        {
                          "id": "playlist-2",
                          "name": "Evening",
                          "type": "playlist",
                          "trackCount": 18
                        }
                      ]
                    }
                    """
                )
            default:
                return try Self.httpResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Unexpected path"}"#
                )
            }
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        let snapshot = try await client.fetchCloudSnapshot(tokenSet: Self.tokenSet)

        let diagnostics = try #require(snapshot.contentFetchDiagnosticsByHouseholdID["household-1"])
        #expect(snapshot.favoritesByHouseholdID["household-1"] == [])
        #expect(snapshot.playlistsByHouseholdID["household-1"]?.count == 2)
        #expect(diagnostics.favorites?.status == .loaded(count: 0, version: "favorites-v1"))
        #expect(diagnostics.playlists?.status == .loaded(count: 2, version: "playlists-v1"))
    }

    @Test
    func clientFetchCloudSnapshotRecordsContentFailures() async throws {
        let stub = try Self.stubbedTransport { request in
            switch request.url?.path {
            case "/control/api/v1/households":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"households":[{"id":"household-1"}]}"#
                )
            case "/control/api/v1/households/household-1/groups":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "groups": [
                        {
                          "id": "group-1",
                          "name": "Kitchen",
                          "coordinatorId": "player-1",
                          "playerIds": ["player-1"]
                        }
                      ],
                      "players": [
                        {
                          "id": "player-1",
                          "name": "Kitchen",
                          "roomName": "Kitchen"
                        }
                      ]
                    }
                    """
                )
            case "/control/api/v1/households/household-1/favorites":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 403,
                    body: #"{"message":"Missing content scope"}"#
                )
            case "/control/api/v1/households/household-1/playlists":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    body: #"{"reason":"Playlist service unavailable"}"#
                )
            default:
                return try Self.httpResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Unexpected path"}"#
                )
            }
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        let snapshot = try await client.fetchCloudSnapshot(tokenSet: Self.tokenSet)

        let diagnostics = try #require(snapshot.contentFetchDiagnosticsByHouseholdID["household-1"])
        #expect(snapshot.groupsByHouseholdID["household-1"]?.groups.count == 1)
        #expect(snapshot.favoritesByHouseholdID["household-1"] == nil)
        #expect(snapshot.playlistsByHouseholdID["household-1"] == nil)
        #expect(
            diagnostics.favorites?.status == .failed(
                detail: "Sonos Control API returned HTTP 403: Missing content scope",
                isAuthorizationFailure: true
            )
        )
        #expect(
            diagnostics.playlists?.status == .failed(
                detail: "Sonos Control API returned HTTP 500: Playlist service unavailable",
                isAuthorizationFailure: false
            )
        )
    }

    @Test
    func clientFetchCloudSnapshotRecordsFavoriteDecodingFailureDetail() async throws {
        let stub = try Self.stubbedTransport { request in
            switch request.url?.path {
            case "/control/api/v1/households":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"households":[{"id":"household-1"}]}"#
                )
            case "/control/api/v1/households/household-1/groups":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "groups": [
                        {
                          "id": "group-1",
                          "name": "Kitchen",
                          "coordinatorId": "player-1",
                          "playerIds": ["player-1"]
                        }
                      ],
                      "players": [
                        {
                          "id": "player-1",
                          "name": "Kitchen",
                          "roomName": "Kitchen"
                        }
                      ]
                    }
                    """
                )
            case "/control/api/v1/households/household-1/favorites":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"version":"favorites-v1","items":[{"name":"Cloud Favorite"}]}"#
                )
            case "/control/api/v1/households/household-1/playlists":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"version":"playlists-v1","playlists":[]}"#
                )
            default:
                return try Self.httpResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Unexpected path"}"#
                )
            }
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        let snapshot = try await client.fetchCloudSnapshot(tokenSet: Self.tokenSet)

        let diagnostics = try #require(snapshot.contentFetchDiagnosticsByHouseholdID["household-1"])
        #expect(snapshot.favoritesByHouseholdID["household-1"] == nil)
        #expect(snapshot.playlistsByHouseholdID["household-1"] == [])
        guard case let .failed(detail, isAuthorizationFailure) = diagnostics.favorites?.status else {
            Issue.record("Expected the favorites decode failure to be recorded.")
            return
        }
        #expect(isAuthorizationFailure == false)
        #expect(detail.contains("Decoding missing key 'id'"))
        #expect(detail.contains("items"))
    }

    @Test
    func clientFetchCloudSnapshotRecordsPlaylistDecodingFailureDetail() async throws {
        let stub = try Self.stubbedTransport { request in
            switch request.url?.path {
            case "/control/api/v1/households":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"households":[{"id":"household-1"}]}"#
                )
            case "/control/api/v1/households/household-1/groups":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "groups": [
                        {
                          "id": "group-1",
                          "name": "Kitchen",
                          "coordinatorId": "player-1",
                          "playerIds": ["player-1"]
                        }
                      ],
                      "players": [
                        {
                          "id": "player-1",
                          "name": "Kitchen",
                          "roomName": "Kitchen"
                        }
                      ]
                    }
                    """
                )
            case "/control/api/v1/households/household-1/favorites":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"version":"favorites-v1","items":[{"id":"favorite-1","name":"Cloud Favorite"}]}"#
                )
            case "/control/api/v1/households/household-1/playlists":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"version":"playlists-v1","playlists":[{"name":"Cloud Playlist"}]}"#
                )
            default:
                return try Self.httpResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Unexpected path"}"#
                )
            }
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        let snapshot = try await client.fetchCloudSnapshot(tokenSet: Self.tokenSet)

        let diagnostics = try #require(snapshot.contentFetchDiagnosticsByHouseholdID["household-1"])
        #expect(snapshot.favoritesByHouseholdID["household-1"]?.count == 1)
        #expect(snapshot.playlistsByHouseholdID["household-1"] == nil)
        #expect(diagnostics.favorites?.status == .loaded(count: 1, version: "favorites-v1"))
        guard case let .failed(detail, isAuthorizationFailure) = diagnostics.playlists?.status else {
            Issue.record("Expected the playlists decode failure to be recorded.")
            return
        }
        #expect(isAuthorizationFailure == false)
        #expect(detail.contains("Decoding missing key 'id'"))
        #expect(detail.contains("playlists"))
    }

    @Test
    func clientRefreshCloudQueueSendsPostWithoutBodyOrContentType() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(for: request, statusCode: 204)
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        try await client.refreshCloudQueue(sessionID: "session-1", accessToken: "token-1")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/control/api/v1/playbackSessions/session-1/playbackSession/refreshCloudQueue")
        #expect(request.httpMethod == "POST")
        #expect(request.body == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test
    func clientTrimsAndClampsOutgoingCommandBodies() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(for: request, statusCode: 204)
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        try await client.seek(
            groupID: "group-1",
            positionMillis: -250,
            itemID: "  item-1  ",
            accessToken: "token-1"
        )
        try await client.setGroupVolume(
            groupID: "group-1",
            level: -10,
            accessToken: "token-1"
        )
        try await client.setPlayerVolume(
            playerID: "player-1",
            level: 125,
            accessToken: "token-1"
        )

        let requests = recorder.requests
        try #require(requests.count == 3)
        let seekRequest = try #require(requests.first)
        let groupVolumeRequest = try #require(requests.dropFirst().first)
        let playerVolumeRequest = try #require(requests.dropFirst(2).first)
        let seekBody = try Self.jsonBody(from: seekRequest)
        let groupVolumeBody = try Self.jsonBody(from: groupVolumeRequest)
        let playerVolumeBody = try Self.jsonBody(from: playerVolumeRequest)

        #expect(seekRequest.url?.path == "/control/api/v1/groups/group-1/playback/seek")
        #expect(seekBody["positionMillis"] as? Int == 0)
        #expect(seekBody["itemId"] as? String == "item-1")
        #expect(groupVolumeRequest.url?.path == "/control/api/v1/groups/group-1/groupVolume")
        #expect(groupVolumeBody["volume"] as? Int == 0)
        #expect(playerVolumeRequest.url?.path == "/control/api/v1/players/player-1/playerVolume")
        #expect(playerVolumeBody["volume"] as? Int == 100)
    }

    @Test
    func createPlaybackSessionTrimsOptionalFieldsAndDecodesStatus() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 200,
                body: """
                {
                  "sessionId": "session-1",
                  "sessionState": "SESSION_STATE_CONNECTED",
                  "sessionCreated": true,
                  "customData": "playlist:easy-mode"
                }
                """
            )
        }
        defer { stub.cleanup() }
        let client = SonosControlAPIClient(transport: stub.transport)

        let status = try await client.createPlaybackSession(
            groupID: "group-1",
            appID: "com.markusskov.Sonoic",
            appContext: "iphone-1",
            accountID: "  sn_3  ",
            customData: "   ",
            accessToken: "token-1"
        )

        let request = try #require(recorder.requests.first)
        let body = try Self.jsonBody(from: request)
        #expect(status.sessionId == "session-1")
        #expect(status.sessionState == .connected)
        #expect(status.sessionCreated == true)
        #expect(request.url?.path == "/control/api/v1/groups/group-1/playbackSession")
        #expect(body["appId"] as? String == "com.markusskov.Sonoic")
        #expect(body["appContext"] as? String == "iphone-1")
        #expect(body["accountId"] as? String == "sn_3")
        #expect(body["customData"] == nil)
    }

    @Test
    func httpErrorUsesSonosErrorResponseDetailAndAuthorizationStatus() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 403,
                body: #"{"errorCode":"ERROR_FORBIDDEN","reason":"Forbidden","message":"  Token expired  "}"#
            )
        }
        defer { stub.cleanup() }

        do {
            let _: SonosControlAPIHouseholdsResponse = try await stub.transport.get(
                "/households",
                accessToken: "token-1"
            )
            Issue.record("Expected the transport to throw an HTTP status error.")
        } catch let error as SonosControlAPITransport.TransportError {
            #expect(error == .httpStatus(403, "Token expired"))
            #expect(error.isAuthorizationFailure == true)
            #expect(error.errorDescription == "Sonos Control API returned HTTP 403: Token expired")
        } catch {
            Issue.record("Expected a SonosControlAPITransport.TransportError, got \(error).")
        }

        #expect(recorder.requests.count == 1)
    }

    @Test
    func httpErrorFallsBackToPlainTextResponseDetail() async throws {
        let stub = try Self.stubbedTransport { request in
            try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: "  upstream unavailable  "
            )
        }
        defer { stub.cleanup() }

        do {
            let _: SonosControlAPIHouseholdsResponse = try await stub.transport.get(
                "/households",
                accessToken: "token-1"
            )
            Issue.record("Expected the transport to throw an HTTP status error.")
        } catch let error as SonosControlAPITransport.TransportError {
            #expect(error == .httpStatus(500, "upstream unavailable"))
            #expect(error.isAuthorizationFailure == false)
            #expect(error.errorDescription == "Sonos Control API returned HTTP 500: upstream unavailable")
        } catch {
            Issue.record("Expected a SonosControlAPITransport.TransportError, got \(error).")
        }
    }

    @Test
    func invalidPathsAreRejectedBeforeSending() async throws {
        let recorder = SonosControlAPITransportRequestRecorder()
        let stub = try Self.stubbedTransport { request in
            recorder.record(request)
            return try Self.httpResponse(for: request, statusCode: 200)
        }
        defer { stub.cleanup() }

        do {
            let _: SonosControlAPIHouseholdsResponse = try await stub.transport.get(
                "/",
                accessToken: "token-1"
            )
            Issue.record("Expected the transport to reject an empty path.")
        } catch let error as SonosControlAPITransport.TransportError {
            #expect(error == .invalidPath)
            #expect(error.errorDescription == "The Sonos Control API path is invalid.")
        } catch {
            Issue.record("Expected a SonosControlAPITransport.TransportError, got \(error).")
        }

        #expect(recorder.requests.isEmpty)
    }

    @Test
    func decodesGroupsResponse() throws {
        let data = try Self.jsonData("""
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
        """)

        let response = try JSONDecoder().decode(SonosControlAPIGroupsResponse.self, from: data)

        #expect(response.groups.first?.id == "group-1")
        #expect(response.groups.first?.coordinatorId == "player-1")
        #expect(response.groups.first?.playerIds == ["player-1", "player-2"])
        #expect(response.players.first?.roomName == "Stue")
    }

    @Test
    func decodesFavoritesResponseWithDocumentedItemsKey() throws {
        let data = try Self.jsonData("""
        {
          "version": "favorites-v1",
          "items": [
            {
              "id": "favorite-1",
              "name": "Let's Groove",
              "description": "Apple Music",
              "service": {
                "name": "Apple Music",
                "id": "204"
              }
            }
          ]
        }
        """)

        let response = try JSONDecoder().decode(SonosControlAPIFavoritesResponse.self, from: data)

        #expect(response.version == "favorites-v1")
        #expect(response.favorites.count == 1)
        #expect(response.favorites.first?.id == "favorite-1")
        #expect(response.favorites.first?.name == "Let's Groove")
        #expect(response.favorites.first?.service?.id == "204")
    }

    @Test
    func decodesMinimalFavoritesResponseWithoutVersion() throws {
        let data = try Self.jsonData("""
        {
          "items": [
            {
              "id": "favorite-1",
              "name": "Let's Groove"
            }
          ]
        }
        """)

        let response = try JSONDecoder().decode(SonosControlAPIFavoritesResponse.self, from: data)

        #expect(response.version == nil)
        #expect(response.favorites.count == 1)
        #expect(response.favorites.first?.id == "favorite-1")
        #expect(response.favorites.first?.name == "Let's Groove")
        #expect(response.favorites.first?.description == nil)
        #expect(response.favorites.first?.service == nil)
    }

    @Test
    func decodesMinimalPlaylistsResponseWithoutVersion() throws {
        let data = try Self.jsonData("""
        {
          "playlists": [
            {
              "id": "playlist-1",
              "name": "Morning Mix"
            }
          ]
        }
        """)

        let response = try JSONDecoder().decode(SonosControlAPIPlaylistsResponse.self, from: data)

        #expect(response.version == nil)
        #expect(response.playlists.count == 1)
        #expect(response.playlists.first?.id == "playlist-1")
        #expect(response.playlists.first?.name == "Morning Mix")
        #expect(response.playlists.first?.type == nil)
        #expect(response.playlists.first?.trackCount == nil)
    }

    @Test
    func decodesPlaybackStatusResponse() throws {
        let data = try Self.jsonData("""
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
        """)

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
        let data = try Self.jsonData("""
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
        """)

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
    func decodesAndEncodesVolumeRequests() throws {
        let data = try Self.jsonData("""
        {
          "volume": 42,
          "muted": false,
          "fixed": false
        }
        """)
        let volume = try JSONDecoder().decode(SonosControlAPIVolumeState.self, from: data)
        let setVolume = SonosControlAPISetVolumeRequest(volume: 65)
        let setMute = SonosControlAPISetMuteRequest(muted: true)

        let volumeObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(setVolume)
        ) as? [String: Any]
        let muteObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(setMute)
        ) as? [String: Any]

        #expect(volume.volume == 42)
        #expect(volume.muted == false)
        #expect(volume.fixed == false)
        #expect(volumeObject?["volume"] as? Int == 65)
        #expect(muteObject?["muted"] as? Bool == true)
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
    func buildsPlaybackSessionCommandPaths() {
        #expect(
            SonosControlAPIClient.playbackSessionCommandPath(
                sessionID: "session-1",
                command: "loadCloudQueue"
            ) == "/playbackSessions/session-1/playbackSession/loadCloudQueue"
        )
        #expect(
            SonosControlAPIClient.playbackSessionCommandPath(
                sessionID: "session-1",
                command: "skipToItem"
            ) == "/playbackSessions/session-1/playbackSession/skipToItem"
        )
        #expect(
            SonosControlAPIClient.playbackSessionCommandPath(
                sessionID: "session-1",
                command: "seek"
            ) == "/playbackSessions/session-1/playbackSession/seek"
        )
        #expect(
            SonosControlAPIClient.playbackSessionCommandPath(
                sessionID: "session-1",
                command: "refreshCloudQueue"
            ) == "/playbackSessions/session-1/playbackSession/refreshCloudQueue"
        )
    }

    @Test
    func preferredCommandTargetUsesConfiguredHouseholdAndGroup() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1"),
                SonosControlAPIHousehold(id: "household-2")
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
                    players: []
                ),
                "household-2": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-2",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2", "player-3"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: "household-2",
            selectedGroupID: "group-2"
        )

        let target = snapshot.preferredCommandTarget(
            settings: settings,
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        #expect(target?.householdID == "household-2")
        #expect(target?.groupID == "group-2")
        #expect(target?.playerID == "player-2")
        #expect(target?.coordinatorPlayerID == "player-2")
        #expect(target?.updatedAt == Date(timeIntervalSince1970: 123))
    }

    @Test
    func preferredCommandTargetUsesActiveTargetBeforeConfiguredGroup() {
        let snapshot = SonosControlAPICloudSnapshot(
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
                        ),
                        SonosControlAPIGroup(
                            id: "group-2",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2", "player-3"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: "household-1",
            selectedGroupID: "group-1"
        )

        let target = snapshot.preferredCommandTarget(
            settings: settings,
            activeTargetID: "player-2"
        )

        #expect(target?.groupID == "group-2")
        #expect(target?.coordinatorPlayerID == "player-2")
    }

    @Test
    func preferredCommandTargetIgnoresBlankActiveTargetAndTrimsConfiguredIDs() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1"),
                SonosControlAPIHousehold(id: "household-2")
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
                    players: []
                ),
                "household-2": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-2",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: " household-2\n",
            selectedGroupID: "\tgroup-2 "
        )

        let target = snapshot.preferredCommandTarget(
            settings: settings,
            activeTargetID: " \t\n"
        )

        #expect(target?.householdID == "household-2")
        #expect(target?.groupID == "group-2")
        #expect(target?.coordinatorPlayerID == "player-2")
    }

    @Test
    func preferredCommandTargetUsesConfiguredGroupWithoutHousehold() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1"),
                SonosControlAPIHousehold(id: "household-2")
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
                    players: []
                ),
                "household-2": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-2",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: nil,
            selectedGroupID: "group-2"
        )

        let target = snapshot.preferredCommandTarget(settings: settings)

        #expect(target?.householdID == "household-2")
        #expect(target?.groupID == "group-2")
        #expect(target?.coordinatorPlayerID == "player-2")
    }

    @Test
    func preferredCommandTargetFallsBackToFirstReachableGroup() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-1",
                            name: "Stue",
                            coordinatorId: nil,
                            playerIds: ["player-1"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: "missing-household",
            selectedGroupID: "missing-group"
        )

        let target = snapshot.preferredCommandTarget(settings: settings)

        #expect(target?.householdID == "household-1")
        #expect(target?.groupID == "group-1")
        #expect(target?.playerID == "player-1")
    }

    @Test
    func preferredCommandTargetSkipsEmptyHouseholds() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1"),
                SonosControlAPIHousehold(id: "household-2")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [],
                    players: []
                ),
                "household-2": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-2",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2"]
                        )
                    ],
                    players: []
                )
            ]
        )

        let target = snapshot.preferredCommandTarget(settings: .disabled)

        #expect(target?.householdID == "household-2")
        #expect(target?.groupID == "group-2")
    }

    @Test
    func settingsRoundTripThroughUserDefaults() throws {
        let defaults = try Self.makeUserDefaults()
        let store = SonoicSettingsStore(userDefaults: defaults)
        let settings = SonosControlAPISettings(
            mode: .diagnosticsOnly,
            selectedHouseholdID: "household-1",
            selectedGroupID: "group-1"
        )

        store.saveSonosControlAPISettings(settings)

        #expect(store.loadSonosControlAPISettings() == settings)
    }

    private static func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "SonosControlAPITransportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func stubbedTransport(
        responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> (transport: SonosControlAPITransport, cleanup: () -> Void) {
        let host = "sonos-control-api-\(UUID().uuidString).test"
        let baseURL = try #require(URL(string: "https://\(host)/control/api/v1"))
        SonosControlAPITransportURLProtocol.register(host: host, responder: responder)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SonosControlAPITransportURLProtocol.self]

        return (
            SonosControlAPITransport(
                baseURL: baseURL,
                urlSession: URLSession(configuration: configuration)
            ),
            {
                SonosControlAPITransportURLProtocol.unregister(host: host)
            }
        )
    }

    private static func jsonBody(from request: SonosControlAPITransportCapturedRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        let object = try JSONSerialization.jsonObject(with: body)
        return try #require(object as? [String: Any])
    }

    private static func jsonData(_ string: String) throws -> Data {
        try #require(string.data(using: .utf8))
    }

    private static var tokenSet: SonosOAuthTokenSet {
        SonosOAuthTokenSet(
            accessToken: "token-1",
            refreshToken: nil,
            tokenType: "Bearer",
            scope: "playback-control-all",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    nonisolated private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String = ""
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(body.utf8))
    }
}

private final class SonosControlAPITransportRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequests: [SonosControlAPITransportCapturedRequest] = []

    var requests: [SonosControlAPITransportCapturedRequest] {
        lock.withLock {
            capturedRequests
        }
    }

    func record(_ request: URLRequest) {
        let capturedRequest = SonosControlAPITransportCapturedRequest(request)
        lock.withLock {
            capturedRequests.append(capturedRequest)
        }
    }
}

private struct SonosControlAPITransportCapturedRequest: Sendable {
    var url: URL?
    var httpMethod: String?
    var body: Data?

    private var headers: [String: String]

    init(_ request: URLRequest) {
        url = request.url
        httpMethod = request.httpMethod
        body = request.httpBody ?? request.httpBodyStream.map(Self.bodyData)
        headers = Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { key, value in
                (key.lowercased(), value)
            }
        )
    }

    func value(forHTTPHeaderField field: String) -> String? {
        headers[field.lowercased()]
    }

    private static func bodyData(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? Data() : data
    }
}

private final class SonosControlAPITransportURLProtocol: URLProtocol {
    private struct Stub: Sendable {
        var responder: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    static func register(
        host: String,
        responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.withLock {
            stubs[host] = Stub(responder: responder)
        }
    }

    static func unregister(host: String) {
        lock.withLock {
            stubs[host] = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        stub(for: request.url?.host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.stub(for: request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try stub.responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func stub(for host: String?) -> Stub? {
        guard let host else {
            return nil
        }

        return lock.withLock {
            stubs[host]
        }
    }
}
