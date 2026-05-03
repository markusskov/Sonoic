import Foundation

struct SonoicAppleMusicPlaylistPlaybackPlan {
    var payloads: [SonosPlayablePayload]
    var startingTrackNumber: Int
    var localNowPlayingPayload: SonosPlayablePayload?
    var recentPlaybackPayload: SonosPlayablePayload?
}

extension SonoicModel {
    func appleMusicPlaylistPlaybackPlan(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        startingAtIndex startIndex: Int? = nil,
        shuffled: Bool = false
    ) -> SonoicAppleMusicPlaylistPlaybackPlan? {
        var playablePairs = trackItems.enumerated().compactMap { index, item -> (
            sourceIndex: Int,
            item: SonoicSourceItem,
            payload: SonosPlayablePayload
        )? in
            guard let payload = try? appleMusicPlayablePayload(for: item, purpose: .queueEntry) else {
                return nil
            }

            return (index, item, payload)
        }

        if shuffled {
            playablePairs.shuffle()
        }

        guard !playablePairs.isEmpty else {
            return nil
        }

        let startingIndex: Int
        if let startIndex {
            guard startIndex >= 0,
                  startIndex < trackItems.count,
                  let matchedIndex = playablePairs.firstIndex(where: { $0.sourceIndex == startIndex })
            else {
                return nil
            }

            startingIndex = matchedIndex
        } else {
            startingIndex = 0
        }

        let startingItem = playablePairs[startingIndex].item

        return SonoicAppleMusicPlaylistPlaybackPlan(
            payloads: playablePairs.map(\.payload),
            startingTrackNumber: startingIndex + 1,
            localNowPlayingPayload: try? appleMusicPlayablePayload(for: startingItem, purpose: .metadata),
            recentPlaybackPayload: try? appleMusicPlayablePayload(for: parentItem, purpose: .metadata)
        )
    }
}
