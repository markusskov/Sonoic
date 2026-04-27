import SwiftUI

struct HomeRecentlyPlayedSection: View {
    let items: [SonoicRecentPlayItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    HomeRecentPlayCard(item: item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeRecentPlayCard: View {
    let item: SonoicRecentPlayItem

    private var sourceItem: SonoicSourceItem? {
        guard let service = item.service else {
            return nil
        }

        let parsedReference = item.playbackURI.flatMap(Self.appleMusicServiceReference)
        let kind = item.sourceItemKindRawValue.flatMap(SonoicSourceItem.Kind.init(rawValue:))
            ?? parsedReference?.kind
            ?? SonoicSourceItem.Kind(favoriteKind: item.favoriteKind)
        let serviceItemID = item.sourceItemID ?? item.appleMusicCatalogID ?? parsedReference?.id

        return SonoicSourceItem(
            id: "recent-\(item.id)",
            title: item.title,
            subtitle: item.subtitle ?? item.sourceName,
            artworkURL: item.artworkURL,
            artworkIdentifier: item.artworkIdentifier,
            serviceItemID: serviceItemID,
            appleMusicIdentity: service.kind == .appleMusic ? SonoicAppleMusicItemIdentity(
                catalogID: item.appleMusicCatalogID ?? serviceItemID,
                libraryID: item.appleMusicLibraryID,
                kind: kind
            ) : nil,
            service: service,
            origin: .recentPlay,
            kind: kind,
            playbackCapability: item.replayFavorite?.playablePayload.map(SonoicPlaybackCapability.sonosNative) ?? .metadataOnly
        )
    }

    var body: some View {
        Group {
            if let sourceItem {
                NavigationLink {
                    AppleMusicItemDetailView(item: sourceItem)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .frame(width: 156, alignment: .leading)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 156
            )
            .frame(width: 156, height: 156)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.subtitle ?? item.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(item.sourceName, systemImage: item.service?.systemImage ?? "music.note")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private static func appleMusicServiceReference(from uri: String) -> (id: String, kind: SonoicSourceItem.Kind)? {
        let normalizedURI = uri
            .replacingOccurrences(of: "&amp;", with: "&")
        let lowercasedURI = normalizedURI.lowercased()

        let prefixes = [
            ("playlist%3a", SonoicSourceItem.Kind.playlist),
            ("album%3a", SonoicSourceItem.Kind.album),
            ("song%3a", SonoicSourceItem.Kind.song),
        ]

        for (prefix, kind) in prefixes {
            guard let prefixRange = lowercasedURI.range(of: prefix) else {
                continue
            }

            let valueStartOffset = lowercasedURI.distance(from: lowercasedURI.startIndex, to: prefixRange.upperBound)
            let valueStartIndex = normalizedURI.index(normalizedURI.startIndex, offsetBy: valueStartOffset)
            let valueAfterPrefix = normalizedURI[valueStartIndex...]
            guard let id = valueAfterPrefix
                .split(separator: "?", maxSplits: 1)
                .first
                .map(String.init)?
                .sonoicNonEmptyTrimmed
            else {
                return nil
            }

            return (id, kind)
        }

        return nil
    }
}

private extension SonoicSourceItem.Kind {
    init(favoriteKind: SonosFavoriteItem.Kind?) {
        switch favoriteKind {
        case .collection:
            self = .playlist
        case .item, .none:
            self = .song
        }
    }
}
