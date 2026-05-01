import Foundation

extension SonoicModel {
    enum AppleMusicPlayablePayloadPurpose {
        case directPlay
        case queueEntry
        case favorite
        case metadata
    }

    enum AppleMusicFavoriteToggleResult {
        case added(objectID: String)
        case removed
    }

    enum AppleMusicFavoriteError: LocalizedError {
        case missingPayload

        var errorDescription: String? {
            switch self {
            case .missingPayload:
                "This Apple Music item does not have a Sonos favorite payload yet."
            }
        }
    }

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
        purpose: AppleMusicPlayablePayloadPurpose
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

    func appleMusicFavoriteObjectID(for item: SonoicSourceItem, localObjectID: String? = nil) -> String? {
        localObjectID ?? appleMusicExactPlaybackCandidate(for: item)?.verifiedFavoriteObjectID
    }

    func toggleAppleMusicSonosFavorite(
        for item: SonoicSourceItem,
        currentObjectID: String?
    ) async throws -> AppleMusicFavoriteToggleResult {
        if let currentObjectID {
            try await removeSonosFavorite(objectID: currentObjectID)
            return .removed
        }

        guard let payload = try appleMusicPlayablePayload(for: item, purpose: .favorite) else {
            throw AppleMusicFavoriteError.missingPayload
        }

        let objectID = try await addSonosFavorite(payload)
        return .added(objectID: objectID)
    }
}

struct SonoicAppleMusicPlaylistPlaybackPlan {
    var payloads: [SonosPlayablePayload]
    var startingTrackNumber: Int
    var localNowPlayingPayload: SonosPlayablePayload?
    var recentPlaybackPayload: SonosPlayablePayload?
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
                  let favoritePayload = favorite.playablePayload,
                  let payload = try? SonosPlayablePayloadPreparer().prepare(favoritePayload),
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
                detail: candidateDetail(confidence: confidence, hasKindMatch: hasKindMatch),
                hasVerifiedPayloadIDMatch: hasPayloadIDMatch
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
