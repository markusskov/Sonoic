import Foundation
import ImageIO

struct SonoicSharedArtworkStore {
    enum StoreError: LocalizedError {
        case unavailableAppGroup(String)
        case invalidResponse
        case invalidArtworkResource
        case unsupportedArtworkResponseType(String?)
        case artworkTooLarge(Int)

        var errorDescription: String? {
            switch self {
            case let .unavailableAppGroup(identifier):
                return "The shared artwork container is unavailable for \(identifier)."
            case .invalidResponse:
                return "The Sonos player returned unreadable artwork data."
            case .invalidArtworkResource:
                return "The Sonos player returned an invalid artwork path."
            case let .unsupportedArtworkResponseType(contentType):
                if let contentType {
                    return "The Sonos player returned unsupported artwork content type: \(contentType)."
                }

                return "The Sonos player returned unsupported artwork content."
            case let .artworkTooLarge(byteCount):
                return "The Sonos player returned artwork larger than allowed (\(byteCount) bytes)."
            }
        }
    }

    nonisolated private static let maximumArtworkByteCount = 5 * 1024 * 1024

    nonisolated(unsafe) private let fileManager: FileManager
    nonisolated private let transport: SonosControlTransport
    nonisolated private let artworkDirectoryURL: URL

    nonisolated init(
        fileManager: FileManager = .default,
        transport: SonosControlTransport = SonosControlTransport()
    ) throws {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SonoicSharedStore.appGroupIdentifier
        ) else {
            throw StoreError.unavailableAppGroup(SonoicSharedStore.appGroupIdentifier)
        }

        self.fileManager = fileManager
        self.transport = transport
        artworkDirectoryURL = containerURL.appendingPathComponent("Artwork", isDirectory: true)

        if !fileManager.fileExists(atPath: artworkDirectoryURL.path()) {
            try fileManager.createDirectory(at: artworkDirectoryURL, withIntermediateDirectories: true)
        }
    }

    nonisolated func loadArtworkData(named identifier: String) -> Data? {
        try? Data(contentsOf: artworkDirectoryURL.appending(path: identifier))
    }

    nonisolated func syncArtwork(
        from remotePath: String?,
        host: String,
        preferredIdentifier: String
    ) async throws -> String? {
        guard let trimmedRemotePath = trimmed(remotePath) else {
            try removeArtworkVariants(for: preferredIdentifier)
            return nil
        }

        let pinnedResource = try pinnedArtworkResource(from: trimmedRemotePath)
        let remoteURL = try transport.url(for: pinnedResource, host: host)
        let payload = try await transport.performGETWithResponse(resource: pinnedResource, host: host)
        let data = payload.data

        guard !data.isEmpty else {
            throw StoreError.invalidResponse
        }

        try validateArtworkPayload(payload)

        let fileURL = artworkDirectoryURL.appending(
            path: fileName(
                for: preferredIdentifier,
                remoteURL: remoteURL,
                contentType: payload.response.mimeType
            )
        )

        try removeArtworkVariants(for: preferredIdentifier)
        try data.write(to: fileURL, options: .atomic)

        return fileURL.lastPathComponent
    }

    nonisolated private func removeArtworkVariants(for preferredIdentifier: String) throws {
        let existingFiles = try fileManager.contentsOfDirectory(
            at: artworkDirectoryURL,
            includingPropertiesForKeys: nil
        )

        for existingFile in existingFiles where existingFile.lastPathComponent.hasPrefix(preferredIdentifier) {
            try fileManager.removeItem(at: existingFile)
        }
    }

    nonisolated private func fileName(for preferredIdentifier: String, remoteURL: URL, contentType: String?) -> String {
        let pathExtension = preferredPathExtension(for: remoteURL, contentType: contentType)
        return "\(preferredIdentifier).\(pathExtension)"
    }

    nonisolated private func preferredPathExtension(for remoteURL: URL, contentType: String?) -> String {
        if let mappedExtension = fileExtension(for: contentType) {
            return mappedExtension
        }

        if let pathExtension = trimmed(remoteURL.pathExtension) {
            return pathExtension.lowercased()
        }

        return "img"
    }

    nonisolated private func fileExtension(for contentType: String?) -> String? {
        guard let contentType = trimmed(contentType)?.lowercased() else {
            return nil
        }

        switch contentType {
        case "image/jpeg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        case "image/gif":
            return "gif"
        default:
            return nil
        }
    }

    nonisolated private func pinnedArtworkResource(from remotePath: String) throws -> String {
        guard let absoluteURL = URL(string: remotePath), absoluteURL.scheme != nil else {
            return remotePath
        }

        guard let components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            throw StoreError.invalidArtworkResource
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw StoreError.invalidArtworkResource
        }

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(path)\(query)"
    }

    nonisolated private func validateArtworkPayload(_ payload: SonosControlTransport.HTTPPayload) throws {
        if let contentLengthHeader = payload.response.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int(contentLengthHeader),
           contentLength > Self.maximumArtworkByteCount
        {
            throw StoreError.artworkTooLarge(contentLength)
        }

        guard payload.data.count <= Self.maximumArtworkByteCount else {
            throw StoreError.artworkTooLarge(payload.data.count)
        }

        if let mimeType = trimmed(payload.response.mimeType)?.lowercased(),
           mimeType.hasPrefix("image/")
        {
            return
        }

        guard isImageData(payload.data) else {
            throw StoreError.unsupportedArtworkResponseType(payload.response.mimeType)
        }
    }

    nonisolated private func isImageData(_ data: Data) -> Bool {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return false
        }

        return CGImageSourceGetCount(source) > 0
    }

    nonisolated private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
