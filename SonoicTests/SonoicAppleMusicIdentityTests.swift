import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicAppleMusicIdentityTests {
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
            libraryID: "i.abc123"
        )

        #expect(item.serviceItemID == "i.abc123")
        #expect(item.appleMusicIdentity?.catalogID == "1440857781")
        #expect(item.appleMusicIdentity?.libraryID == "i.abc123")
        #expect(item.appleMusicIdentity?.kind == .song)
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
}
