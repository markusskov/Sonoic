import Foundation
import Testing
@testable import Sonoic

struct SonoicSharedArtworkStoreTests {
    @Test
    func rejectsSVGArtworkPayloads() throws {
        let payload = try Self.payload(
            data: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8),
            mimeType: "image/svg+xml"
        )

        do {
            try SonoicSharedArtworkStore.validateArtworkPayload(payload)
            Issue.record("Expected SVG artwork to be rejected.")
        } catch SonoicSharedArtworkStore.StoreError.unsupportedArtworkResponseType(let contentType) {
            #expect(contentType == "image/svg+xml")
        } catch {
            Issue.record("Expected unsupported artwork error, got \(error).")
        }
    }

    @Test
    func rejectsCorruptJPEGArtworkPayloads() throws {
        let payload = try Self.payload(
            data: Data("not actually a jpeg".utf8),
            mimeType: "image/jpeg"
        )

        do {
            try SonoicSharedArtworkStore.validateArtworkPayload(payload)
            Issue.record("Expected corrupt JPEG artwork to be rejected.")
        } catch SonoicSharedArtworkStore.StoreError.unsupportedArtworkResponseType(let contentType) {
            #expect(contentType == "image/jpeg")
        } catch {
            Issue.record("Expected unsupported artwork error, got \(error).")
        }
    }

    @Test
    func acceptsTinyRasterArtworkPayloads() throws {
        try SonoicSharedArtworkStore.validateArtworkPayload(
            try Self.payload(data: Self.validPNGData(), mimeType: "image/png")
        )
        try SonoicSharedArtworkStore.validateArtworkPayload(
            try Self.payload(data: Self.validJPEGData(), mimeType: "image/jpeg")
        )
    }

    @Test
    func nilRemotePathRemovesExistingArtworkVariants() async throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appending(
            path: "SonoicSharedArtworkStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: directoryURL) }

        let store = try SonoicSharedArtworkStore(fileManager: fileManager, artworkDirectoryURL: directoryURL)
        let oldPNGURL = directoryURL.appending(path: "album-1.png")
        let oldWebPURL = directoryURL.appending(path: "album-1.webp")
        let unrelatedURL = directoryURL.appending(path: "album-2.png")
        let pngData = try Self.validPNGData()

        try pngData.write(to: oldPNGURL)
        try Data("stale webp".utf8).write(to: oldWebPURL)
        try pngData.write(to: unrelatedURL)

        let result = try await store.syncArtwork(from: nil, host: "192.0.2.10", preferredIdentifier: "album-1")

        #expect(result == nil)
        #expect(fileManager.fileExists(atPath: oldPNGURL.path()) == false)
        #expect(fileManager.fileExists(atPath: oldWebPURL.path()) == false)
        #expect(fileManager.fileExists(atPath: unrelatedURL.path()))
        #expect(store.loadArtworkData(named: "album-1.png") == nil)
        #expect(store.loadArtworkData(named: "album-2.png") == pngData)
    }

    private static func payload(data: Data, mimeType: String?) throws -> SonosControlTransport.HTTPPayload {
        let url = try #require(URL(string: "https://example.com/artwork"))
        var headerFields: [String: String] = [:]
        if let mimeType {
            headerFields["Content-Type"] = mimeType
        }

        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headerFields
            )
        )

        return SonosControlTransport.HTTPPayload(data: data, response: response)
    }

    private static func validPNGData() throws -> Data {
        try #require(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l8K9WQAAAABJRU5ErkJggg==")
        )
    }

    private static func validJPEGData() throws -> Data {
        try #require(
            Data(base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBARXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwERAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAf/bAEMBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAf/dAAQAAf/aAAwDAQACEQMRAD8A/F+v8pz/AL+D/9k=")
        )
    }
}
