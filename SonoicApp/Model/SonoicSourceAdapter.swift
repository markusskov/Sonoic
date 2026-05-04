import Foundation

struct SonoicSourceCapabilities: Equatable {
    var supportsCatalogSearch = false
    var supportsItemDetail = false
    var supportsFavorites = false
    var supportsSonosPlaybackPayloads = false
}

enum SonoicSourcePlayablePayloadPurpose {
    case directPlay
    case queueEntry
    case favorite
    case metadata
}

enum SonoicSourceFavoriteToggleResult {
    case added(objectID: String)
    case removed
}

enum SonoicSourceAdapterError: LocalizedError {
    case unsupported(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let detail), .unavailable(let detail):
            detail
        }
    }
}

struct SonoicSourcePlaylistPlaybackPlan {
    var payloads: [SonosPlayablePayload]
    var startingTrackNumber: Int
    var localNowPlayingPayload: SonosPlayablePayload?
    var recentPlaybackPayload: SonosPlayablePayload?
}

struct SonoicSourceAdapter: Identifiable, Equatable {
    var service: SonosServiceDescriptor
    var capabilities: SonoicSourceCapabilities

    var id: String {
        service.id
    }

    static func adapter(for service: SonosServiceDescriptor) -> SonoicSourceAdapter {
        switch service.kind {
        case .appleMusic:
            SonoicSourceAdapter(
                service: service,
                capabilities: SonoicSourceCapabilities(
                    supportsCatalogSearch: true,
                    supportsItemDetail: true,
                    supportsFavorites: true,
                    supportsSonosPlaybackPayloads: true
                )
            )
        case .spotify, .sonosRadio, .genericStreaming:
            SonoicSourceAdapter(
                service: service,
                capabilities: SonoicSourceCapabilities()
            )
        }
    }

    @MainActor
    func searchCatalog(
        term: String,
        scope: SonoicSourceSearchScope,
        model: SonoicModel
    ) async throws -> [SonoicSourceItem] {
        guard capabilities.supportsCatalogSearch else {
            return []
        }

        switch service.kind {
        case .appleMusic:
            model.refreshAppleMusicAuthorizationState()
            guard model.appleMusicAuthorizationState.allowsCatalogSearch else {
                throw SonoicSourceAdapterError.unavailable(model.appleMusicAuthorizationState.detail)
            }

            let items = try await model.appleMusicCatalogSearchClient.searchCatalog(
                term: term,
                scope: scope
            )
            model.recordAppleMusicRequestSuccess()
            return items
        case .spotify, .sonosRadio, .genericStreaming:
            return []
        }
    }

    @MainActor
    func failureDetail(from error: Error, model: SonoicModel) -> String {
        if let adapterError = error as? SonoicSourceAdapterError,
           let detail = adapterError.errorDescription {
            return detail
        }

        switch service.kind {
        case .appleMusic:
            return model.appleMusicFailureDetail(from: error, endpointFamily: .search)
        case .spotify, .sonosRadio, .genericStreaming:
            return error.localizedDescription
        }
    }
}

extension SonoicModel {
    func sourceAdapter(for service: SonosServiceDescriptor) -> SonoicSourceAdapter {
        SonoicSourceAdapter.adapter(for: service)
    }

    func sourceAdapter(for item: SonoicSourceItem) -> SonoicSourceAdapter {
        sourceAdapter(for: item.service)
    }

    func sourcePlayablePayload(
        for item: SonoicSourceItem,
        purpose: SonoicSourcePlayablePayloadPurpose
    ) throws -> SonosPlayablePayload? {
        switch item.service.kind {
        case .appleMusic:
            guard sourceAdapter(for: item).capabilities.supportsSonosPlaybackPayloads else {
                return item.sonosNativePlaybackPayload
            }

            return try appleMusicPlayablePayload(
                for: item,
                purpose: purpose
            )
        case .spotify, .sonosRadio, .genericStreaming:
            return item.sonosNativePlaybackPayload
        }
    }

    func sourcePlaylistPlaybackPlan(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        startingAtIndex startIndex: Int? = nil,
        shuffled: Bool = false
    ) -> SonoicSourcePlaylistPlaybackPlan? {
        guard sourceAdapter(for: parentItem).capabilities.supportsSonosPlaybackPayloads else {
            return nil
        }

        switch parentItem.service.kind {
        case .appleMusic:
            guard let plan = appleMusicPlaylistPlaybackPlan(
                parentItem: parentItem,
                trackItems: trackItems,
                startingAtIndex: startIndex,
                shuffled: shuffled
            ) else {
                return nil
            }

            return SonoicSourcePlaylistPlaybackPlan(
                payloads: plan.payloads,
                startingTrackNumber: plan.startingTrackNumber,
                localNowPlayingPayload: plan.localNowPlayingPayload,
                recentPlaybackPayload: plan.recentPlaybackPayload
            )
        case .spotify, .sonosRadio, .genericStreaming:
            return nil
        }
    }

    func sourceFavoriteObjectID(for item: SonoicSourceItem) -> String? {
        guard sourceAdapter(for: item).capabilities.supportsFavorites else {
            return nil
        }

        switch item.service.kind {
        case .appleMusic:
            return appleMusicFavoriteObjectID(for: item)
        case .spotify, .sonosRadio, .genericStreaming:
            return nil
        }
    }

    func toggleSourceFavorite(
        for item: SonoicSourceItem
    ) async throws -> SonoicSourceFavoriteToggleResult {
        guard sourceAdapter(for: item).capabilities.supportsFavorites else {
            throw SonoicSourceAdapterError.unsupported("This source cannot save Sonos favorites yet.")
        }

        switch item.service.kind {
        case .appleMusic:
            switch try await toggleAppleMusicSonosFavorite(for: item) {
            case .added(let objectID):
                return .added(objectID: objectID)
            case .removed:
                return .removed
            }
        case .spotify, .sonosRadio, .genericStreaming:
            throw SonoicSourceAdapterError.unsupported("This source cannot save Sonos favorites yet.")
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
