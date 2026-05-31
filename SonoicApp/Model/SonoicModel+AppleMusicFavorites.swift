import Foundation

enum SonoicAppleMusicFavoriteOverride: Equatable {
    case added(objectID: String)
    case removed(objectID: String)
}

extension SonoicModel {
    enum AppleMusicFavoriteToggleResult {
        case added(objectID: String)
        case removed
    }

    enum AppleMusicFavoriteError: LocalizedError {
        case missingPayload
        case unsupportedLibraryPlaylist

        var errorDescription: String? {
            switch self {
            case .missingPayload:
                "This Apple Music item does not have a Sonos favorite payload yet."
            case .unsupportedLibraryPlaylist:
                "This Apple Music library playlist does not expose a Sonos-compatible catalog playlist ID yet. Try saving an Apple Music catalog playlist instead."
            }
        }
    }

    func appleMusicFavoriteObjectID(for item: SonoicSourceItem) -> String? {
        switch appleMusicFavoriteOverrides[appleMusicFavoriteOverrideKey(for: item)] {
        case .added(let objectID):
            objectID
        case .removed:
            nil
        case nil:
            appleMusicFavoriteObjectIDFromSnapshot(for: item)
        }
    }

    func toggleAppleMusicSonosFavorite(
        for item: SonoicSourceItem
    ) async throws -> AppleMusicFavoriteToggleResult {
        let overrideKey = appleMusicFavoriteOverrideKey(for: item)

        guard hasManualSonosHost else {
            throw SonosControlTransport.TransportError.invalidHost
        }

        let currentObjectID = appleMusicFavoriteObjectID(for: item)

        if let currentObjectID {
            appleMusicFavoriteOverrides[overrideKey] = .removed(objectID: currentObjectID)

            do {
                try await favoritesClient.removeFavorite(host: manualSonosHost, objectID: currentObjectID)
                await refreshHomeFavorites(showLoading: false)
            } catch {
                appleMusicFavoriteOverrides[overrideKey] = .added(objectID: currentObjectID)
                throw error
            }

            return .removed
        }

        await refreshAppleMusicFavoritePlaybackContextIfNeeded(for: item)

        guard let payload = try appleMusicPlayablePayload(for: item, purpose: .favorite) else {
            throw appleMusicFavoritePayloadUnavailableError(for: item)
        }

        let objectID: String
        do {
            objectID = try await favoritesClient.addFavorite(host: manualSonosHost, payload: payload)
            appleMusicFavoriteOverrides[overrideKey] = .added(objectID: objectID)
            await refreshHomeFavorites(showLoading: false)
        } catch {
            appleMusicFavoriteOverrides[overrideKey] = nil
            throw error
        }

        return .added(objectID: objectID)
    }

    func reconcileAppleMusicFavoriteOverrides() {
        guard !appleMusicFavoriteOverrides.isEmpty else {
            return
        }

        let snapshotObjectIDs = Set(homeFavoritesState.snapshot?.items.map(\.id) ?? [])

        for (overrideKey, override) in appleMusicFavoriteOverrides {
            switch override {
            case .added(let objectID):
                if snapshotObjectIDs.contains(objectID) {
                    appleMusicFavoriteOverrides[overrideKey] = nil
                }
            case .removed(let objectID):
                if !snapshotObjectIDs.contains(objectID) {
                    appleMusicFavoriteOverrides[overrideKey] = nil
                }
            }
        }
    }

    private func appleMusicFavoriteObjectIDFromSnapshot(for item: SonoicSourceItem) -> String? {
        appleMusicExactPlaybackCandidate(for: item)?.verifiedFavoriteObjectID
    }

    private func refreshAppleMusicFavoritePlaybackContextIfNeeded(for item: SonoicSourceItem) async {
        guard item.service.kind == .appleMusic else {
            return
        }

        await refreshSonosMusicServiceProbeIfNeeded()
    }

    private func appleMusicFavoritePayloadUnavailableError(for item: SonoicSourceItem) -> AppleMusicFavoriteError {
        if item.service.kind == .appleMusic,
           item.kind == .playlist,
           item.sourceReference?.catalogID?.sonoicNonEmptyTrimmed == nil,
           item.sourceReference?.libraryID?.sonoicNonEmptyTrimmed != nil
        {
            return .unsupportedLibraryPlaylist
        }

        return .missingPayload
    }

    private func appleMusicFavoriteOverrideKey(for item: SonoicSourceItem) -> String {
        [
            "apple-music-favorite",
            normalizedManualSonosHost(manualSonosHost),
            item.service.id,
            item.kind.rawValue,
            item.sourceReference?.catalogID ?? "no-catalog-id",
            item.sourceReference?.libraryID ?? "no-library-id",
            item.serviceItemID ?? item.id
        ].joined(separator: ":")
    }
}
