import Foundation

struct SonoicSharedArtworkStore {
    enum StoreError: LocalizedError {
        case unavailableAppGroup(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case let .unavailableAppGroup(identifier):
                "The shared artwork container is unavailable for \(identifier)."
            case .invalidResponse:
                "The Sonos player returned unreadable artwork data."
            }
        }
    }

    private let fileManager: FileManager
    private let transport: SonosControlTransport
    private let artworkDirectoryURL: URL

    init(
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

    func loadArtworkData(named identifier: String) -> Data? {
        try? Data(contentsOf: artworkDirectoryURL.appending(path: identifier))
    }

    func syncArtwork(
        from remotePath: String?,
        host: String,
        preferredIdentifier: String
    ) async throws -> String? {
        guard let trimmedRemotePath = trimmed(remotePath) else {
            try removeArtworkVariants(for: preferredIdentifier)
            return nil
        }

        let remoteURL = try transport.url(for: trimmedRemotePath, host: host)
        let fileURL = artworkDirectoryURL.appending(path: fileName(for: preferredIdentifier, remoteURL: remoteURL))
        let (data, response) = try await URLSession.shared.data(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode),
              !data.isEmpty
        else {
            throw StoreError.invalidResponse
        }

        try removeArtworkVariants(for: preferredIdentifier)
        try data.write(to: fileURL, options: .atomic)

        return fileURL.lastPathComponent
    }

    private func removeArtworkVariants(for preferredIdentifier: String) throws {
        let existingFiles = try fileManager.contentsOfDirectory(
            at: artworkDirectoryURL,
            includingPropertiesForKeys: nil
        )

        for existingFile in existingFiles where existingFile.lastPathComponent.hasPrefix(preferredIdentifier) {
            try fileManager.removeItem(at: existingFile)
        }
    }

    private func fileName(for preferredIdentifier: String, remoteURL: URL) -> String {
        let pathExtension = trimmed(remoteURL.pathExtension) ?? "img"
        return "\(preferredIdentifier).\(pathExtension)"
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
