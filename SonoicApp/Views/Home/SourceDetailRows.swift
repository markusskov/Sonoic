import SwiftUI

struct SourceActionFailure: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

struct SourceNavigationRow: View {
    struct Model: Identifiable, Equatable {
        var title: String
        var subtitle: String?
        var systemImage: String
        var badgeTitle: String?
        var showsChevron = true

        var id: String {
            title
        }
    }

    let row: Model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.serviceAccent)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(SonoicTheme.Typography.listTitle)
                    .foregroundStyle(SonoicTheme.Colors.primary)
                    .lineLimit(1)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(SonoicTheme.Typography.listSubtitle)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let badgeTitle = row.badgeTitle {
                Text(badgeTitle)
                    .font(SonoicTheme.Typography.badge)
                    .foregroundStyle(SonoicTheme.Colors.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: Capsule())
            }

            if row.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SonoicTheme.Colors.tertiary)
            }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

struct SourceItemNavigationRow: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    var playOverride: (() async -> Void)?
    var isCompact = false
    @State private var actionFailure: SourceActionFailure?

    private var canPlay: Bool {
        playOverride != nil || model.canPlaySourceItem(item)
    }

    private var shouldPlayOnRowTap: Bool {
        item.kind == .song && canPlay
    }

    private var opensContainerDetail: Bool {
        // Songs act from rows and the player; detail screens are reserved for browsable source containers.
        item.kind != .song
    }

    private var isFavorited: Bool {
        favoriteObjectID != nil
    }

    private var favoriteObjectID: String? {
        model.sourceFavoriteObjectID(for: item)
    }

    private var canFavorite: Bool {
        model.sourceAdapter(for: item).capabilities.supportsFavorites
    }

    private var hasAuxiliaryActions: Bool {
        canPlay || canFavorite || item.externalURL != nil || hasUnavailableContext
    }

    private var hasUnavailableContext: Bool {
        item.kind == .song && !canPlay
    }

    var body: some View {
        HStack(spacing: 12) {
            if shouldPlayOnRowTap {
                Button {
                    Task {
                        await play()
                    }
                } label: {
                    SourceItemMetadataRow(item: item, isCompact: isCompact)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            } else if opensContainerDetail {
                NavigationLink {
                    SourceItemDetailView(item: item)
                } label: {
                    SourceItemMetadataRow(item: item, isCompact: isCompact)
                }
                .buttonStyle(.plain)
            } else {
                SourceItemMetadataRow(item: item, isCompact: isCompact)
            }

            if shouldPlayOnRowTap || hasAuxiliaryActions {
                Menu {
                    if canPlay {
                        Button {
                            Task {
                                await play()
                            }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                    } else {
                        Button {} label: {
                            Label("Unavailable", systemImage: "lock")
                        }
                        .disabled(true)
                    }

                    if canFavorite {
                        Button {
                            Task {
                                await toggleFavorite()
                            }
                        } label: {
                            Label(
                                isFavorited ? "Remove Favorite" : "Save to Favorites",
                                systemImage: isFavorited ? "heart.fill" : "heart"
                            )
                            .foregroundStyle(.primary)
                        }
                    }

                    if let externalURL = item.externalURL.flatMap(URL.init(string:)) {
                        ShareLink(item: externalURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    SourceItemOptionsIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options for \(item.title)")
            }

            if opensContainerDetail && !shouldPlayOnRowTap {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, isCompact ? 8 : 12)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func play() async {
        if let playOverride {
            await playOverride()
            return
        }

        do {
            let didStart = try await model.playSourceItem(item)

            if !didStart {
                actionFailure = SourceActionFailure(
                    title: "Could Not Start",
                    detail: "Sonos could not start this item."
                )
            }
        } catch {
            actionFailure = SourceActionFailure(
                title: "Could Not Start",
                detail: error.localizedDescription
            )
        }
    }

    private func toggleFavorite() async {
        let wasFavorited = favoriteObjectID != nil

        do {
            _ = try await model.toggleSourceFavorite(for: item)
        } catch {
            actionFailure = SourceActionFailure(
                title: wasFavorited ? "Could Not Remove Favorite" : "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
    }
}

private struct SourceItemMetadataRow: View {
    let item: SonoicSourceItem
    var isCompact = false

    private var artworkDimension: CGFloat {
        isCompact ? 52 : 58
    }

    var body: some View {
        HStack(spacing: isCompact ? 12 : 14) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: artworkDimension
            )
            .frame(width: artworkDimension, height: artworkDimension)

            VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                Text(item.title)
                    .font(SonoicTheme.Typography.listTitle)
                    .foregroundStyle(SonoicTheme.Colors.primary)
                    .lineLimit(1)

                if let displaySubtitle {
                    Text(displaySubtitle)
                        .font(SonoicTheme.Typography.listSubtitle)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displaySubtitle: String? {
        guard let subtitle = item.subtitle else {
            return item.kind == .album ? "Album" : nil
        }

        guard item.kind == .album else {
            return subtitle
        }

        return "\(subtitle) • Album"
    }

}

private struct SourceItemOptionsIcon: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(SonoicTheme.Colors.secondary)
            .frame(width: 44, height: 44)
    }
}
