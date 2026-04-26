import Foundation

extension SonoicModel {
    func appleMusicPlaybackCandidate(for item: SonoicSourceItem) -> SonoicSonosPlaybackCandidate? {
        appleMusicPlaybackCandidates(for: item).first
    }

    func appleMusicPlaybackCandidates(for item: SonoicSourceItem) -> [SonoicSonosPlaybackCandidate] {
        SonoicAppleMusicPlaybackPayloadResolver()
            .candidates(for: item, favorites: homeFavoritesState.snapshot?.items ?? [])
    }
}

struct SonoicAppleMusicPlaybackPayloadResolver {
    func candidates(
        for item: SonoicSourceItem,
        favorites: [SonosFavoriteItem]
    ) -> [SonoicSonosPlaybackCandidate] {
        guard item.service.kind == .appleMusic else {
            return []
        }

        let itemTitle = normalizedAppleMusicMatchText(item.title)
        guard !itemTitle.isEmpty else {
            return []
        }

        let itemSubtitleParts = normalizedAppleMusicSubtitleParts(item.subtitle)
        let itemSubtitleSet = Set(itemSubtitleParts)

        return favorites.compactMap { favorite in
            guard favorite.service?.kind == .appleMusic,
                  let payload = favorite.playablePayload,
                  normalizedAppleMusicMatchText(favorite.title) == itemTitle
            else {
                return nil
            }

            let favoriteSubtitleParts = normalizedAppleMusicSubtitleParts(favorite.subtitle)
            let favoriteSubtitleSet = Set(favoriteSubtitleParts)
            let hasSubtitleOverlap = !itemSubtitleSet.isDisjoint(with: favoriteSubtitleSet)
            let hasKindMatch = appleMusicItem(item, matchesFavoriteKind: favorite)
            let hasStrongSubtitleMatch = appleMusicItem(
                item,
                hasStrongSubtitleMatchWithItemParts: itemSubtitleParts,
                favoriteParts: favoriteSubtitleSet
            )

            guard hasSubtitleOverlap || hasKindMatch || favoriteSubtitleParts.isEmpty || itemSubtitleParts.isEmpty else {
                return nil
            }

            let confidence: SonoicSonosPlaybackCandidate.Confidence = hasKindMatch && hasStrongSubtitleMatch ? .exact : .likely
            return SonoicSonosPlaybackCandidate(
                payload: payload,
                confidence: confidence,
                detail: candidateDetail(confidence: confidence, hasKindMatch: hasKindMatch)
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.confidence, rhs.confidence) {
            case (.exact, .likely):
                true
            case (.likely, .exact):
                false
            default:
                lhs.payload.title.localizedCaseInsensitiveCompare(rhs.payload.title) == .orderedAscending
            }
        }
    }

    private func appleMusicItem(
        _ item: SonoicSourceItem,
        matchesFavoriteKind favorite: SonosFavoriteItem
    ) -> Bool {
        switch item.kind {
        case .album, .playlist, .station:
            favorite.isCollectionLike
        case .song:
            !favorite.isCollectionLike
        case .artist, .unknown:
            true
        }
    }

    private func appleMusicItem(
        _ item: SonoicSourceItem,
        hasStrongSubtitleMatchWithItemParts itemParts: [String],
        favoriteParts: Set<String>
    ) -> Bool {
        guard !itemParts.isEmpty, !favoriteParts.isEmpty else {
            return false
        }

        switch item.kind {
        case .song:
            guard let primaryArtist = itemParts.first else {
                return false
            }

            return favoriteParts.contains(primaryArtist)
        case .album, .playlist, .station:
            return !Set(itemParts).isDisjoint(with: favoriteParts)
        case .artist, .unknown:
            return false
        }
    }

    private func normalizedAppleMusicSubtitleParts(_ subtitle: String?) -> [String] {
        guard let subtitle else {
            return []
        }

        return subtitle
            .components(separatedBy: "•")
            .map(normalizedAppleMusicMatchText)
            .filter { !$0.isEmpty }
    }

    private func normalizedAppleMusicMatchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func candidateDetail(
        confidence: SonoicSonosPlaybackCandidate.Confidence,
        hasKindMatch: Bool
    ) -> String {
        switch (confidence, hasKindMatch) {
        case (.exact, true):
            "Sonoic found a saved Apple Music favorite with matching title, detail, and item type. Playback will use Sonos' own URI and DIDL metadata."
        case (.exact, false):
            "Sonoic found a saved Apple Music favorite with matching title and detail. Playback will use Sonos' own URI and DIDL metadata."
        case (.likely, true):
            "Sonoic found a saved Apple Music favorite with a matching title and compatible item type. Check the match before playing."
        case (.likely, false):
            "Sonoic found a saved Apple Music favorite with a matching title. Check the match before playing."
        }
    }
}
