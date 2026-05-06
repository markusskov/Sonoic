import Foundation

struct SonosPlayablePayloadPreparer {
    enum Failure: Error, Equatable, LocalizedError {
        case missingURI
        case queueOwnedURI
        case groupCoordinatorURI
        case unsupportedURI(String)
        case queueNextRequiresItem
        case queueNextRequiresMetadata

        var errorDescription: String? {
            switch self {
            case .missingURI:
                "Missing Sonos playback URI."
            case .queueOwnedURI:
                "Queue-owned URIs cannot be launched as source payloads."
            case .groupCoordinatorURI:
                "Group coordinator URIs cannot be launched as source payloads."
            case .unsupportedURI:
                "Unsupported Sonos playback URI."
            case .queueNextRequiresItem:
                "Only item payloads can be queued next."
            case .queueNextRequiresMetadata:
                "Queue playback needs Sonos DIDL metadata."
            }
        }
    }

    func prepare(_ payload: SonosPlayablePayload) throws -> SonosPlayablePayload {
        let uri = try preparedURI(payload.uri)
        let metadataXML = payload.metadataXML.sonoicNonEmptyTrimmed

        switch payload.launchMode {
        case .direct:
            break
        case .queueNext:
            guard payload.kind == .item else {
                throw Failure.queueNextRequiresItem
            }

            guard metadataXML != nil else {
                throw Failure.queueNextRequiresMetadata
            }
        }

        return SonosPlayablePayload(
            id: payload.id,
            title: payload.title,
            subtitle: payload.subtitle,
            artworkURL: payload.artworkURL,
            service: payload.service,
            uri: uri,
            metadataXML: metadataXML,
            kind: payload.kind,
            launchMode: payload.launchMode,
            duration: payload.duration
        )
    }

    private func preparedURI(_ rawURI: String) throws -> String {
        guard let uri = rawURI.sonoicNonEmptyTrimmed else {
            throw Failure.missingURI
        }

        let normalizedURI = uri.lowercased()

        if normalizedURI.hasPrefix("x-rincon-queue:") {
            throw Failure.queueOwnedURI
        }

        if normalizedURI.hasPrefix("x-rincon:") {
            throw Failure.groupCoordinatorURI
        }

        guard allowedDirectURIPrefixes.contains(where: normalizedURI.hasPrefix) else {
            throw Failure.unsupportedURI(uri)
        }

        return uri
    }

    static func protocolInfo(for uri: String) -> String {
        let normalizedURI = uri.lowercased()

        if normalizedURI.hasPrefix("x-rincon-cpcontainer:") {
            return "x-rincon-cpcontainer:*:*:*"
        }

        if normalizedURI.hasPrefix("x-sonosapi-hls-static:") {
            return "sonos.com-http:*:application/x-mpegURL:*"
        }

        if normalizedURI.hasPrefix("x-sonosapi-hls:") {
            return "sonos.com-http:*:application/vnd.apple.mpegurl:*"
        }

        return "sonos.com-http:*:audio/mp4:*"
    }

    private var allowedDirectURIPrefixes: [String] {
        Self.allowedDirectURIPrefixes
    }

    private static var allowedDirectURIPrefixes: [String] {
        [
            "x-sonosapi-stream:",
            "x-sonosapi-radio:",
            "x-sonosapi-hls-static:",
            "x-sonosapi-hls:",
            "x-sonosapi-http:",
            "x-sonosapi-static:",
            "x-sonos-http:",
            "x-rincon-cpcontainer:",
            "x-rincon-stream:",
            "x-rincon-mp3radio:"
        ]
    }
}
