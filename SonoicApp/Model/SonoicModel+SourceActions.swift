import Foundation

enum SonoicSourceActionError: LocalizedError {
    case playbackPayloadUnavailable

    var errorDescription: String? {
        switch self {
        case .playbackPayloadUnavailable:
            "This item does not have a Sonos playback payload yet."
        }
    }
}

extension SonoicModel {
    func canPlaySourceItem(_ item: SonoicSourceItem) -> Bool {
        (try? sourcePlayablePayload(for: item, purpose: .directPlay)) != nil
    }

    func sourcePlaylistFallbackPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        try? sourcePlayablePayload(for: item, purpose: .metadata)
    }

    func canPlaySourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem]
    ) -> Bool {
        sourcePlaylistPlaybackPlan(parentItem: parentItem, trackItems: trackItems) != nil
    }

    @discardableResult
    func playSourceItem(_ item: SonoicSourceItem) async throws -> Bool {
        guard let payload = try sourcePlayablePayload(for: item, purpose: .directPlay) else {
            throw SonoicSourceActionError.playbackPayloadUnavailable
        }

        return await playManualSonosPayload(payload)
    }

    @discardableResult
    func playSourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        startingAtIndex startIndex: Int? = nil,
        shuffled: Bool = false
    ) async -> Bool {
        guard let plan = sourcePlaylistPlaybackPlan(
            parentItem: parentItem,
            trackItems: trackItems,
            startingAtIndex: startIndex,
            shuffled: shuffled
        ) else {
            return false
        }

        let didStartPlayback = await playManualSonosQueuePayloads(
            plan.payloads,
            startingTrackNumber: plan.startingTrackNumber,
            localNowPlayingPayload: plan.localNowPlayingPayload,
            recentPlaybackPayload: plan.recentPlaybackPayload
        )

        if didStartPlayback {
            recordRecentSourceItem(parentItem, replayPayload: plan.recentPlaybackPayload)
        }

        return didStartPlayback
    }

    @discardableResult
    func playSourcePlaylistFallback(_ item: SonoicSourceItem) async throws -> Bool {
        guard let payload = sourcePlaylistFallbackPayload(for: item) else {
            throw SonoicSourceActionError.playbackPayloadUnavailable
        }

        let didStartPlayback = await playManualSonosPayload(
            payload,
            localNowPlayingPayload: payload,
            recentPlaybackPayload: payload
        )

        if didStartPlayback {
            recordRecentSourceItem(item, replayPayload: payload)
        }

        return didStartPlayback
    }

    @discardableResult
    func playSourcePlaylist(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        shuffled: Bool = false
    ) async throws -> Bool {
        if canPlaySourcePlaylistQueue(parentItem: parentItem, trackItems: trackItems) {
            return await playSourcePlaylistQueue(
                parentItem: parentItem,
                trackItems: trackItems,
                shuffled: shuffled
            )
        }

        return try await playSourcePlaylistFallback(parentItem)
    }
}
