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

        var errorDescription: String? {
            switch self {
            case .missingPayload:
                "This Apple Music item does not have a Sonos favorite payload yet."
            }
        }
    }

    func appleMusicFavoriteObjectID(for item: SonoicSourceItem) -> String? {
        if let localFavorite = localAppleMusicFavorite(for: item) {
            return localFavorite.id
        }

        switch appleMusicFavoriteOverrides[appleMusicFavoriteOverrideKey(for: item)] {
        case .added(let objectID):
            return objectID
        case .removed:
            return nil
        case nil:
            return appleMusicFavoriteObjectIDFromSnapshot(for: item)
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
            if removeLocalAppleMusicFavorite(objectID: currentObjectID) {
                return .removed
            }

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

        if let localFavorite = localAppleMusicLibraryPlaylistFavorite(for: item) {
            saveLocalAppleMusicFavorite(localFavorite)
            return .added(objectID: localFavorite.id)
        }

        guard let payload = try appleMusicPlayablePayload(for: item, purpose: .favorite) else {
            throw AppleMusicFavoriteError.missingPayload
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

extension SonoicModel {
    private static let localAppleMusicFavoriteIDPrefix = "sonoic-local-apple-music:"

    func isLocalAppleMusicFavoriteObjectID(_ objectID: String) -> Bool {
        objectID.hasPrefix(Self.localAppleMusicFavoriteIDPrefix)
    }

    func removeLocalAppleMusicFavorite(objectID: String) -> Bool {
        guard isLocalAppleMusicFavoriteObjectID(objectID),
              let index = localAppleMusicFavorites.firstIndex(where: { $0.id == objectID })
        else {
            return false
        }

        localAppleMusicFavorites.remove(at: index)
        persistLocalAppleMusicFavorites()
        applyLocalAppleMusicFavoritesToHomeFavoritesState()
        return true
    }

    func localAppleMusicFavorite(for item: SonoicSourceItem) -> SonosFavoriteItem? {
        localAppleMusicFavorites.first {
            $0.id == localAppleMusicFavoriteObjectID(for: item)
        }
    }

    func applyLocalAppleMusicFavoritesToHomeFavoritesState() {
        switch homeFavoritesState {
        case .loading, .failed:
            return
        case .idle, .empty:
            let localFavorites = activeLocalAppleMusicFavorites
            homeFavoritesState = localFavorites.isEmpty
                ? .empty
                : .loaded(SonosFavoritesSnapshot(items: localFavorites))
        case .loaded(let snapshot):
            let remoteItems = snapshot.items.filter { !isLocalAppleMusicFavoriteObjectID($0.id) }
            let mergedSnapshot = mergedHomeFavoritesSnapshot(
                SonosFavoritesSnapshot(items: remoteItems)
            )
            homeFavoritesState = mergedSnapshot.items.isEmpty ? .empty : .loaded(mergedSnapshot)
        }
    }

    func mergedHomeFavoritesSnapshot(_ snapshot: SonosFavoritesSnapshot) -> SonosFavoritesSnapshot {
        let remoteIDs = Set(snapshot.items.map(\.id))
        let localFavorites = activeLocalAppleMusicFavorites.filter { !remoteIDs.contains($0.id) }
        return SonosFavoritesSnapshot(items: snapshot.items + localFavorites)
    }

    private var activeLocalAppleMusicFavorites: [SonosFavoriteItem] {
        let hostPrefix = localAppleMusicFavoriteHostPrefix()
        guard !hostPrefix.isEmpty else {
            return []
        }

        return localAppleMusicFavorites.filter { $0.id.hasPrefix(hostPrefix) }
    }

    private func saveLocalAppleMusicFavorite(_ favorite: SonosFavoriteItem) {
        localAppleMusicFavorites.removeAll { $0.id == favorite.id }
        localAppleMusicFavorites.append(favorite)
        persistLocalAppleMusicFavorites()
        applyLocalAppleMusicFavoritesToHomeFavoritesState()
    }

    private func persistLocalAppleMusicFavorites() {
        settingsStore.saveLocalAppleMusicFavorites(localAppleMusicFavorites)
    }

    private func localAppleMusicLibraryPlaylistFavorite(for item: SonoicSourceItem) -> SonosFavoriteItem? {
        guard item.service.kind == .appleMusic,
              item.kind == .playlist,
              item.sourceReference?.catalogID?.sonoicNonEmptyTrimmed == nil,
              let libraryID = item.sourceReference?.libraryID?.sonoicNonEmptyTrimmed,
              let encodedLibraryID = Self.localAppleMusicFavoritePayloadID(libraryID)
        else {
            return nil
        }

        let playbackURI = "x-sonoic-apple-music-libraryplaylist:\(encodedLibraryID)"
        return SonosFavoriteItem(
            id: localAppleMusicFavoriteObjectID(for: item),
            title: item.title,
            subtitle: item.subtitle ?? item.service.name,
            artworkURL: item.artworkURL,
            service: .appleMusic,
            playbackURI: playbackURI,
            playbackMetadataXML: localAppleMusicLibraryPlaylistMetadataXML(
                item: item,
                libraryID: libraryID,
                playbackURI: playbackURI
            ),
            kind: .collection
        )
    }

    private func localAppleMusicFavoriteObjectID(for item: SonoicSourceItem) -> String {
        Self.localAppleMusicFavoriteIDPrefix + appleMusicFavoriteOverrideKey(for: item)
    }

    private func localAppleMusicFavoriteHostPrefix() -> String {
        let host = normalizedManualSonosHost(manualSonosHost)
        guard !host.isEmpty else {
            return ""
        }

        return "\(Self.localAppleMusicFavoriteIDPrefix)apple-music-favorite:\(host):"
    }

    private func localAppleMusicLibraryPlaylistMetadataXML(
        item: SonoicSourceItem,
        libraryID: String,
        playbackURI: String
    ) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><container id="libraryplaylist:\(Self.xmlEscaped(libraryID))"><dc:title>\(Self.xmlEscaped(item.title))</dc:title><upnp:class>object.container.playlistContainer</upnp:class><res protocolInfo="x-sonoic-apple-music:*:*:*">\(Self.xmlEscaped(playbackURI))</res></container></DIDL-Lite>
        """
    }

    private static func localAppleMusicFavoritePayloadID(_ value: String) -> String? {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
