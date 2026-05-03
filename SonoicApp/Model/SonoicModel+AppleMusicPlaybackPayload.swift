import Foundation

extension SonoicModel {
    func appleMusicPlaybackCandidate(for item: SonoicSourceItem) -> SonoicSonosPlaybackCandidate? {
        appleMusicPlaybackCandidates(for: item).first
    }

    func appleMusicExactPlaybackCandidate(for item: SonoicSourceItem) -> SonoicSonosPlaybackCandidate? {
        guard let candidate = appleMusicPlaybackCandidate(for: item),
              candidate.confidence == .exact
        else {
            return nil
        }

        return candidate
    }

    func appleMusicPlaybackCandidates(for item: SonoicSourceItem) -> [SonoicSonosPlaybackCandidate] {
        SonoicAppleMusicPlaybackPayloadResolver()
            .candidates(for: item, favorites: homeFavoritesState.snapshot?.items ?? [])
    }

    func appleMusicPlayablePayload(
        for item: SonoicSourceItem,
        purpose: SonoicSourcePlayablePayloadPurpose
    ) throws -> SonosPlayablePayload? {
        switch purpose {
        case .directPlay:
            if let exactPlaybackCandidate = appleMusicExactPlaybackCandidate(for: item) {
                return exactPlaybackCandidate.payload
            }

            if let generatedPlaybackCandidate = appleMusicGeneratedPlaybackCandidate(for: item) {
                return try generatedPlaybackCandidate.preparedPlaybackPayload(for: item)
            }

            return item.sonosNativePlaybackPayload

        case .queueEntry:
            if let generatedQueueCandidate = appleMusicGeneratedQueueCandidate(for: item) {
                return generatedQueueCandidate.playbackPayload(for: item)
            }

            return appleMusicExactPlaybackCandidate(for: item)?.payload ?? item.sonosNativePlaybackPayload

        case .favorite:
            if let generatedPlaybackCandidate = appleMusicGeneratedPlaybackCandidate(for: item) {
                return try generatedPlaybackCandidate.preparedPlaybackPayload(for: item)
            }

            guard appleMusicExactPlaybackCandidate(for: item)?.verifiedFavoriteObjectID != nil else {
                return nil
            }

            return appleMusicExactPlaybackCandidate(for: item)?.payload

        case .metadata:
            if let exactPlaybackCandidate = appleMusicExactPlaybackCandidate(for: item) {
                return exactPlaybackCandidate.payload
            }

            return appleMusicGeneratedPlaybackCandidate(for: item)?.playbackPayload(for: item)
                ?? item.sonosNativePlaybackPayload
        }
    }
}

private extension SonoicSourceItem {
    var sonosNativePlaybackPayload: SonosPlayablePayload? {
        if case let .sonosNative(payload) = playbackCapability {
            payload
        } else {
            nil
        }
    }
}
