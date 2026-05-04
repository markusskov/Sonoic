import Foundation

extension SonoicModel {
    func sourceItemDetailState(for item: SonoicSourceItem) -> SonoicSourceItemDetailState {
        sourceItemDetailStates[item.sourceDetailCacheKey] ?? SonoicSourceItemDetailState(item: item)
    }

    func loadSourceItemDetail(
        for item: SonoicSourceItem,
        force: Bool = false
    ) {
        let detailCacheKey = item.sourceDetailCacheKey
        let currentState = sourceItemDetailState(for: item)

        if currentState.isLoading || (!force && currentState.status == .loaded) {
            return
        }

        let adapter = sourceAdapter(for: item)

        guard adapter.capabilities.supportsItemDetail,
              item.sourceReference?.routedID(for: item.origin) ?? item.serviceItemID != nil
        else {
            sourceItemDetailStates[detailCacheKey] = SonoicSourceItemDetailState(
                item: item,
                status: .loaded
            )
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            sourceItemDetailStates[detailCacheKey] = SonoicSourceItemDetailState(
                item: item,
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        sourceItemDetailLoadTasks[detailCacheKey]?.cancel()
        sourceItemDetailStates[detailCacheKey] = SonoicSourceItemDetailState(
            item: item,
            sections: currentState.sections,
            status: .loading,
            lastUpdatedAt: currentState.lastUpdatedAt
        )

        sourceItemDetailLoadTasks[detailCacheKey] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sections: [SonoicSourceItemDetailSection]
                switch item.service.kind {
                case .appleMusic:
                    sections = try await self.appleMusicCatalogSearchClient.fetchItemDetailSections(for: item)
                case .spotify, .sonosRadio, .genericStreaming:
                    sections = []
                }
                guard !Task.isCancelled else {
                    return
                }

                self.sourceItemDetailStates[detailCacheKey] = SonoicSourceItemDetailState(
                    item: item,
                    sections: sections,
                    status: .loaded,
                    lastUpdatedAt: .now
                )
                self.recordAppleMusicRequestSuccess()
            } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
                return
            } catch {
                self.sourceItemDetailStates[detailCacheKey] = SonoicSourceItemDetailState(
                    item: item,
                    sections: self.sourceItemDetailState(for: item).sections,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .itemDetail)
                    ),
                    lastUpdatedAt: self.sourceItemDetailState(for: item).lastUpdatedAt
                )
            }

            self.sourceItemDetailLoadTasks[detailCacheKey] = nil
        }
    }
}
