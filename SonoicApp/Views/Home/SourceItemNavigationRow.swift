import SwiftUI

struct SourceActionFailure: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

private enum SourceItemPendingAction {
    case play
    case favorite
}

struct SourceItemNavigationRow: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    var playOverride: (() async -> Void)?
    var isCompact = false
    @State private var actionFailure: SourceActionFailure?
    @State private var pendingAction: SourceItemPendingAction?

    private var canPlay: Bool {
        playOverride != nil || (item.kind == .song && model.canPlaySourceItem(item))
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

    private var isNowPlayingSong: Bool {
        guard item.kind == .song else {
            return false
        }

        return model.effectiveNowPlayingSnapshotForActiveTarget.matchesSourceSong(item)
    }

    var body: some View {
        HStack(spacing: 12) {
            rowContent

            if shouldPlayOnRowTap || hasAuxiliaryActions {
                optionsMenu
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

    @ViewBuilder
    private var rowContent: some View {
        if shouldPlayOnRowTap {
            Button {
                Task {
                    await playWithPulse()
                }
            } label: {
                SourceItemMetadataRow(
                    item: item,
                    isCompact: isCompact,
                    isNowPlaying: isNowPlayingSong
                )
                .sonoicCommandPulse(isActive: pendingAction == .play, cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.title)")
        } else if opensContainerDetail {
            NavigationLink {
                SourceItemDetailView(item: item)
            } label: {
                SourceItemMetadataRow(
                    item: item,
                    isCompact: isCompact,
                    isNowPlaying: isNowPlayingSong
                )
            }
            .buttonStyle(.plain)
        } else {
            SourceItemMetadataRow(
                item: item,
                isCompact: isCompact,
                isNowPlaying: isNowPlayingSong
            )
        }
    }

    private var optionsMenu: some View {
        Menu {
            if canPlay {
                Button {
                    Task {
                        await playWithPulse()
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
                        await toggleFavoriteWithPulse()
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
                .sonoicCommandPulse(isActive: pendingAction == .favorite, cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(item.title)")
    }

    @MainActor
    private func playWithPulse() async {
        pendingAction = .play
        await play()
        await clearPendingAction(.play)
    }

    @MainActor
    private func toggleFavoriteWithPulse() async {
        pendingAction = .favorite
        await toggleFavorite()
        await clearPendingAction(.favorite)
    }

    @MainActor
    private func clearPendingAction(_ action: SourceItemPendingAction) async {
        try? await Task.sleep(for: .milliseconds(160))
        if pendingAction == action {
            pendingAction = nil
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
    var isNowPlaying = false

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
                HStack(spacing: 5) {
                    if isNowPlaying {
                        ActiveSongWaveformView()
                    }

                    Text(item.title)
                        .font(SonoicTheme.Typography.listTitle)
                        .foregroundStyle(isNowPlaying ? SonoicTheme.Colors.tabAccent : SonoicTheme.Colors.primary)
                        .lineLimit(1)
                }

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

private struct ActiveSongWaveformView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private let barHeights: [CGFloat] = [5, 10, 7]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(barHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(SonoicTheme.Colors.tabAccent)
                    .frame(width: 3, height: reduceMotion ? barHeights[index] : (isAnimating ? barHeights[index] : 4))
                    .animation(
                        waveformAnimation(for: index),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 14, height: 12, alignment: .bottom)
        .onAppear {
            isAnimating = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            isAnimating = !reduceMotion
        }
        .onDisappear {
            isAnimating = false
        }
        .accessibilityHidden(true)
    }

    private func waveformAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else {
            return nil
        }

        return .easeInOut(duration: 0.52)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.12)
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

private extension SonosNowPlayingSnapshot {
    func matchesSourceSong(_ item: SonoicSourceItem) -> Bool {
        guard playbackState == .playing || playbackState == .buffering else {
            return false
        }

        guard normalized(title) == normalized(item.title) else {
            return false
        }

        guard let subtitle = item.subtitle?.sonoicNonEmptyTrimmed else {
            return true
        }

        if let artistName = artistName?.sonoicNonEmptyTrimmed,
           subtitle.localizedCaseInsensitiveContains(artistName) {
            return true
        }

        if let albumTitle = albumTitle?.sonoicNonEmptyTrimmed,
           subtitle.localizedCaseInsensitiveContains(albumTitle) {
            return true
        }

        return artistName.sonoicNonEmptyTrimmed == nil && albumTitle.sonoicNonEmptyTrimmed == nil
    }

    private func normalized(_ value: String) -> String {
        value.sonoicTrimmed.lowercased()
    }
}
