import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicSourceItemReferenceTests {
    @Test
    func decodesLibraryPlayParametersCatalogID() throws {
        let json = """
        {
          "data": [
            {
              "id": "i.abc123",
              "type": "library-songs",
              "attributes": {
                "name": "Sweet Jane",
                "artistName": "Garrett Kato",
                "albumName": "That Low and Lonesome Sound",
                "url": "https://music.apple.com/us/song/sweet-jane/1440857781",
                "playParams": {
                  "id": "i.abc123",
                  "kind": "song",
                  "catalogId": "1440857781"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AppleMusicLibraryResponse.self, from: json)
        let resource = try #require(response.data.first)
        let metadata = try #require(AppleMusicItemMetadata.metadata(from: resource, origin: .library))

        #expect(metadata.serviceItemID == "i.abc123")
        #expect(metadata.libraryItemID == "i.abc123")
        #expect(metadata.catalogItemID == "1440857781")
        #expect(metadata.title == "Sweet Jane")
        #expect(metadata.subtitle == "Garrett Kato • That Low and Lonesome Sound")
        #expect(metadata.externalURL == "https://music.apple.com/us/song/sweet-jane/1440857781")
    }

    @Test
    func preservesCatalogIdentityOnSourceItems() {
        let item = SonoicSourceItem.appleMusicMetadata(
            id: "i.abc123",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .library,
            catalogID: "1440857781",
            libraryID: "i.abc123",
            externalURL: "https://music.apple.com/us/song/sweet-jane/1440857781"
        )

        #expect(item.serviceItemID == "i.abc123")
        #expect(item.sourceReference?.serviceID == SonosServiceDescriptor.appleMusic.id)
        #expect(item.sourceReference?.catalogID == "1440857781")
        #expect(item.sourceReference?.libraryID == "i.abc123")
        #expect(item.sourceReference?.kind == .song)
        #expect(item.externalURL == "https://music.apple.com/us/song/sweet-jane/1440857781")
    }

    @Test
    func libraryIdentityRoutesRelationshipsThroughLibraryID() throws {
        let item = SonoicSourceItem.appleMusicMetadata(
            id: "i.abc123",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .library,
            catalogID: "1440857781",
            libraryID: "i.abc123"
        )
        let identity = try #require(item.sourceReference)

        #expect(identity.routedID(for: .library) == "i.abc123")
        #expect(identity.routedID(for: .catalogSearch) == "1440857781")
    }

    @Test
    func detailCacheKeysDoNotCollideAcrossOrigins() {
        let libraryItem = SonoicSourceItem.appleMusicMetadata(
            id: "i.abc123",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .library,
            catalogID: "1440857781",
            libraryID: "i.abc123"
        )
        let catalogItem = SonoicSourceItem.appleMusicMetadata(
            id: "1440857781",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .catalogSearch,
            catalogID: "1440857781",
            libraryID: nil
        )

        #expect(libraryItem.sourceDetailCacheKey != catalogItem.sourceDetailCacheKey)
        #expect(libraryItem.sourceDetailCacheKey.hasPrefix("apple-music:library:song:"))
        #expect(catalogItem.sourceDetailCacheKey.hasPrefix("apple-music:catalogSearch:song:"))
    }

    @Test
    func treatsCatalogResourceIDAsCatalogIdentity() throws {
        let json = """
        {
          "data": [
            {
              "id": "1440857781",
              "type": "songs",
              "attributes": {
                "name": "Sweet Jane",
                "artistName": "Garrett Kato"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AppleMusicLibraryResponse.self, from: json)
        let resource = try #require(response.data.first)
        let metadata = try #require(AppleMusicItemMetadata.metadata(from: resource, origin: .catalogSearch))

        #expect(metadata.serviceItemID == "1440857781")
        #expect(metadata.catalogItemID == "1440857781")
        #expect(metadata.libraryItemID == nil)
    }

    @Test
    func decodesStationResources() throws {
        let json = """
        {
          "data": [
            {
              "id": "ra.1",
              "type": "stations",
              "attributes": {
                "name": "Apple Music 1",
                "url": "https://music.apple.com/us/station/apple-music-1/ra.1"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AppleMusicLibraryResponse.self, from: json)
        let resource = try #require(response.data.first)
        let metadata = try #require(AppleMusicItemMetadata.metadata(from: resource, origin: .catalogSearch))

        #expect(metadata.serviceItemID == "ra.1")
        #expect(metadata.kind == .station)
        #expect(metadata.title == "Apple Music 1")
        #expect(metadata.externalURL == "https://music.apple.com/us/station/apple-music-1/ra.1")
    }

    @Test
    func decodesRecommendationSections() throws {
        let json = """
        {
          "data": [
            {
              "id": "rec-1",
              "type": "personal-recommendation",
              "attributes": {
                "title": {
                  "stringForDisplay": "Made for You"
                }
              },
              "relationships": {
                "contents": {
                  "data": [
                    {
                      "id": "pl.1",
                      "type": "playlists",
                      "attributes": {
                        "name": "Replay",
                        "curatorName": "Apple Music"
                      }
                    }
                  ]
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AppleMusicRecommendationResponse.self, from: json)
        let section = try #require(response.sections().first)
        let item = try #require(section.items.first)

        #expect(section.id == "rec-1")
        #expect(section.title == "Made for You")
        #expect(item.kind == .playlist)
        #expect(item.title == "Replay")
    }

    @Test
    func mapsDeveloperTokenFailuresToFriendlyDiagnostics() {
        let error = NSError(
            domain: "MusicKit.MusicDataRequest.Error",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Failed to request developer token"]
        )

        let failure = SonoicAppleMusicCatalogSearchClient.appleMusicRequestFailure(
            from: error,
            endpointFamily: .search
        )

        #expect(failure.kind == .missingDeveloperTokenSetup)
        #expect(failure.endpointFamily == .search)
        #expect(failure.displayDetail.contains("MusicKit App Service"))
    }

    @Test
    func mapsNetworkFailuresToFriendlyDiagnostics() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        let failure = SonoicAppleMusicCatalogSearchClient.appleMusicRequestFailure(
            from: error,
            endpointFamily: .library
        )

        #expect(failure.kind == .networkUnavailable)
        #expect(failure.endpointFamily == .library)
    }

    @Test
    func identifiesCancelledAppleMusicRequests() {
        #expect(SonoicAppleMusicCatalogSearchClient.isCancellation(CancellationError()))
        #expect(
            SonoicAppleMusicCatalogSearchClient.isCancellation(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            )
        )
    }
}
