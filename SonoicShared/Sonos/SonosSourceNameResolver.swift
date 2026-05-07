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
           SonosMetadataHeuristics.isPlaybackContainerURI(normalizedCurrentURI),
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
            || uri.hasPrefix("x-sonosapi-hls-static:")
            || uri.hasPrefix("x-sonosapi-hls:")
            || uri.hasPrefix("x-sonosapi-http:")
            || uri.hasPrefix("x-sonosapi-static:")
        {
            if let serviceName = SonosServiceCatalog.descriptor(from: uri)?.name {
                return serviceName
            }

            return "Streaming Audio"
        }

        if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return "Web Stream"
        }

        return nil
    }
}
