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
            let hasPayloadIDMatch = appleMusicItem(item, hasPayloadIDMatchWith: favorite)
            let hasSubtitleOverlap = !itemSubtitleSet.isDisjoint(with: favoriteSubtitleSet)
            let hasKindMatch = appleMusicItem(item, matchesFavoriteKind: favorite)
            let hasStrongSubtitleMatch = appleMusicItem(
                item,
                hasStrongSubtitleMatchWithItemParts: itemSubtitleParts,
                favoriteParts: favoriteSubtitleSet
            )

            guard appleMusicItem(
                item,
                payloadIDMatch: hasPayloadIDMatch,
                hasPlayableMatchWithKindMatch: hasKindMatch,
                subtitleOverlap: hasSubtitleOverlap,
                itemParts: itemSubtitleParts,
                favoriteParts: favoriteSubtitleParts
            ) else {
                return nil
            }

            let confidence: SonoicSonosPlaybackCandidate.Confidence =
                hasPayloadIDMatch || (hasKindMatch && hasStrongSubtitleMatch) ? .exact : .likely
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

    private func appleMusicItem(
        _ item: SonoicSourceItem,
        payloadIDMatch: Bool,
        hasPlayableMatchWithKindMatch hasKindMatch: Bool,
        subtitleOverlap: Bool,
        itemParts: [String],
        favoriteParts: [String]
    ) -> Bool {
        if payloadIDMatch {
            return true
        }

        switch item.kind {
        case .song:
            return hasKindMatch && subtitleOverlap && !itemParts.isEmpty && !favoriteParts.isEmpty
        case .album, .playlist, .station:
            return subtitleOverlap || hasKindMatch || favoriteParts.isEmpty || itemParts.isEmpty
        case .artist, .unknown:
            return subtitleOverlap || hasKindMatch
        }
    }

    private func appleMusicItem(
        _ item: SonoicSourceItem,
        hasPayloadIDMatchWith favorite: SonosFavoriteItem
    ) -> Bool {
        let candidateIDs = [
            item.appleMusicIdentity?.catalogID,
            item.appleMusicIdentity?.libraryID,
            item.serviceItemID
        ]
        .compactMap(\.self)
        .compactMap(\.sonoicNonEmptyTrimmed)

        guard !candidateIDs.isEmpty else {
            return false
        }

        let searchableFavoritePayload = normalizedFavoritePayloadSearchText(for: favorite)
        return candidateIDs.contains { candidateID in
            searchableFavoritePayload.contains(normalizedAppleMusicPayloadID(candidateID))
        }
    }

    private func normalizedFavoritePayloadSearchText(for favorite: SonosFavoriteItem) -> String {
        [
            favorite.playbackURI,
            favorite.playbackURI.removingPercentEncoding,
            favorite.playbackMetadataXML,
            favorite.playbackMetadataXML?.removingPercentEncoding
        ]
        .compactMap(\.self)
        .map(normalizedAppleMusicPayloadID)
        .joined(separator: " ")
    }

    private func normalizedAppleMusicPayloadID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
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
            "Favorite match"
        case (.exact, false):
            "Favorite match"
        case (.likely, true):
            "Possible favorite"
        case (.likely, false):
            "Possible favorite"
        }
    }
}
