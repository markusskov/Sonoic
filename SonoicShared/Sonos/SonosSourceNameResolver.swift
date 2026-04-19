import Foundation

struct SonosSourceNameResolver {
    func resolve(
        sourceMetadataTitle: String?,
        trackTitle: String?,
        currentURI: String?,
        trackURI: String?
    ) -> String {
        let normalizedSourceMetadataTitle = sourceMetadataTitle.sonoicNonEmptyTrimmed
        let preferredURI = preferredSourceURI(currentURI: currentURI, trackURI: trackURI)

        if let inferredSourceName = inferredSourceName(from: preferredURI) {
            return inferredSourceName
        }

        if let sourceMetadataTitle = normalizedSourceMetadataTitle,
           !SonosMetadataHeuristics.isGenericQueueTitle(sourceMetadataTitle)
        {
            return sourceMetadataTitle
        }

        if let sourceMetadataTitle = normalizedSourceMetadataTitle,
           sourceMetadataTitle != trackTitle.sonoicNonEmptyTrimmed
        {
            return sourceMetadataTitle
        }

        return "Sonos"
    }

    private func preferredSourceURI(currentURI: String?, trackURI: String?) -> String? {
        let normalizedCurrentURI = currentURI.sonoicNonEmptyTrimmed
        let normalizedTrackURI = trackURI.sonoicNonEmptyTrimmed

        if let normalizedCurrentURI,
           SonosMetadataHeuristics.isQueueContainerURI(normalizedCurrentURI),
           normalizedTrackURI != nil
        {
            return normalizedTrackURI
        }

        return normalizedCurrentURI ?? normalizedTrackURI
    }

    private func inferredSourceName(from uri: String?) -> String? {
        guard let uri = uri.sonoicNonEmptyTrimmed?.lowercased() else {
            return nil
        }

        if uri.hasPrefix("x-sonos-htastream:") {
            return "TV Audio"
        }

        if uri.hasPrefix("x-rincon-stream:") {
            return "Line-In"
        }

        if uri.hasPrefix("x-file-cifs:") {
            return "Music Library"
        }

        if uri.hasPrefix("x-rincon-queue:") {
            return "Sonos Queue"
        }

        if uri.hasPrefix("x-sonos-http:")
            || uri.hasPrefix("x-sonosapi-radio:")
            || uri.hasPrefix("x-sonosapi-stream:")
            || uri.hasPrefix("x-sonosapi-hls:")
            || uri.hasPrefix("x-sonosapi-http:")
            || uri.hasPrefix("x-sonosapi-static:")
        {
            if let serviceID = serviceID(from: uri),
               let serviceName = knownServiceName(for: serviceID)
            {
                return serviceName
            }

            return "Streaming Audio"
        }

        if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return "Web Stream"
        }

        return nil
    }

    private func serviceID(from uri: String) -> String? {
        guard let queryRange = uri.range(of: "?") else {
            return nil
        }

        let query = uri[queryRange.upperBound...]
        let queryItems = query.split(separator: "&")

        for queryItem in queryItems {
            let parts = queryItem.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == "sid" else {
                continue
            }

            return String(parts[1])
        }

        return nil
    }

    private func knownServiceName(for serviceID: String) -> String? {
        switch serviceID {
        case "204":
            return "Apple Music"
        default:
            return nil
        }
    }
}
