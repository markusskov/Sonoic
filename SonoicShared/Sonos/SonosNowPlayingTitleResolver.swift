import Foundation

struct SonosNowPlayingTitleResolver {
    func resolveTitle(
        trackMetadata: SonosDIDLMetadata?,
        sourceMetadata: SonosDIDLMetadata?,
        sourceName: String,
        playbackState: SonosNowPlayingSnapshot.PlaybackState
    ) -> String {
        if let title = preferredTrackTitle(from: trackMetadata?.title, sourceName: sourceName) {
            return title
        }

        if let title = preferredSourceTitle(from: sourceMetadata?.title, sourceName: sourceName) {
            return title
        }

        if sourceName != "Sonos" {
            return sourceName
        }

        switch playbackState {
        case .playing:
            return "Audio Playing"
        case .paused:
            return "Nothing Playing"
        case .buffering:
            return "Loading Audio"
        }
    }

    private func preferredTrackTitle(from rawTitle: String?, sourceName: String) -> String? {
        guard let title = normalizedTitle(rawTitle) else {
            return nil
        }

        guard !looksLikeInternalTransportTitle(title, sourceName: sourceName) else {
            return nil
        }

        return title
    }

    private func preferredSourceTitle(from rawTitle: String?, sourceName: String) -> String? {
        guard let title = normalizedTitle(rawTitle) else {
            return nil
        }

        guard !SonosMetadataHeuristics.isGenericQueueTitle(title) else {
            return nil
        }

        guard title != sourceName else {
            return nil
        }

        guard !looksLikeInternalTransportTitle(title, sourceName: sourceName) else {
            return nil
        }

        return title
    }

    private func looksLikeInternalTransportTitle(_ title: String, sourceName: String) -> Bool {
        let normalizedTitle = title.uppercased()

        if normalizedTitle.hasPrefix("UUID:RINCON_") || normalizedTitle.hasPrefix("RINCON_") {
            return true
        }

        if sourceName == "TV Audio", normalizedTitle == "TV" {
            return true
        }

        return false
    }
    private func normalizedTitle(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
