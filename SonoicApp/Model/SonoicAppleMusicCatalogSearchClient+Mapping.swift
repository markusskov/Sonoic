import Foundation

extension SonoicAppleMusicCatalogSearchClient {
    func sourceItem(from metadata: AppleMusicItemMetadata) -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: metadata.serviceItemID,
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkURL: metadata.artworkURL,
            kind: sourceKind(for: metadata.kind),
            origin: sourceOrigin(for: metadata.origin),
            catalogID: metadata.catalogItemID,
            libraryID: metadata.libraryItemID,
            externalURL: metadata.externalURL,
            duration: metadata.duration
        )
    }

    func sourceItemPage(from page: AppleMusicItemMetadataPage) -> SonoicSourceItemPage {
        SonoicSourceItemPage(
            items: page.items.map(sourceItem),
            nextOffset: page.nextOffset
        )
    }

    func browseState(
        destination: SonoicAppleMusicBrowseDestination,
        sections: [AppleMusicItemMetadataSection]
    ) -> SonoicAppleMusicBrowseState {
        SonoicAppleMusicBrowseState(
            destination: destination,
            sections: sections.map { section in
                SonoicSourceItemDetailSection(
                    id: section.id,
                    title: section.title,
                    subtitle: section.subtitle,
                    items: section.items.map(sourceItem)
                )
            },
            status: .loaded
        )
    }

    func appleMusicKind(for sourceKind: SonoicSourceItem.Kind) -> AppleMusicItemKind? {
        switch sourceKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        case .station, .unknown:
            nil
        }
    }

    func appleMusicOrigin(
        for sourceOrigin: SonoicSourceItem.Origin,
        identity: SonoicSourceItemReference?
    ) -> AppleMusicItemOrigin? {
        switch sourceOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        case .recentPlay:
            identity?.libraryID != nil ? .library : .catalogSearch
        case .favorite:
            identity?.libraryID != nil ? .library : .catalogSearch
        }
    }

    private func sourceKind(for appleMusicKind: AppleMusicItemKind) -> SonoicSourceItem.Kind {
        switch appleMusicKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        case .station:
            .station
        }
    }

    private func sourceOrigin(for appleMusicOrigin: AppleMusicItemOrigin) -> SonoicSourceItem.Origin {
        switch appleMusicOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        }
    }
}
