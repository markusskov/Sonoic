import SwiftUI
import UIKit

struct PlayerSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(SonoicModel.self) var model
    @State var isAdjustingVolume = false
    @State private var artworkImage: UIImage?
    @State var volumeCommitTask: Task<Void, Never>?
    @State var volumeLevel = 0.0

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - 60, 1)
            let heroSize = CGSize(width: geometry.size.width, height: heroHeight(for: geometry))

            ZStack {
                PlayerFullscreenArtworkBackground(
                    artworkImage: artworkImage,
                    size: geometry.size
                )

                VStack(spacing: 0) {
                    PlayerFullscreenHeroArtwork(
                        artworkImage: artworkImage,
                        size: heroSize
                    )

                    Spacer(minLength: 0)

                    VStack(spacing: controlSpacing(for: geometry)) {
                        PlayerFullscreenTitleBlock(
                            title: model.nowPlaying.title,
                            subtitle: model.nowPlaying.subtitle ?? model.nowPlaying.sourceName,
                            artistName: model.nowPlaying.artistName,
                            openArtist: openArtist
                        )

                        PlayerProgressSection(
                            nowPlaying: model.nowPlaying,
                            observedAt: model.nowPlayingObservedAt,
                            contentIdentity: progressContentIdentity,
                            isEnabled: model.hasManualSonosHost && model.nowPlaying.canSeek,
                            showsTimeLabels: true,
                            showsThumb: false,
                            seek: { timeInterval in
                                await seek(to: timeInterval)
                            }
                        )

                        PlayerTransportControls(
                            nowPlaying: model.nowPlaying,
                            skipPrevious: skipToPreviousTrack,
                            togglePlayback: togglePlayback,
                            skipNext: skipToNextTrack
                        )

                        PlayerFullscreenVolumeBar(
                            volume: volumeBinding,
                            isEnabled: model.hasManualSonosHost,
                            volumeEditingChanged: handleVolumeEditingChanged
                        )

                        PlayerFullscreenSonosActions(
                            activeTargetSystemImage: model.activeTarget.kind.systemImage,
                            muteButtonSystemImage: muteButtonSystemImage,
                            isEnabled: model.hasManualSonosHost,
                            openRooms: openRooms,
                            toggleMute: toggleMute,
                            openQueue: openQueue
                        )
                    }
                    .frame(width: contentWidth)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom + 16, 28))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: artworkReloadKey) {
            artworkImage = await PlayerArtworkImageLoader.loadArtworkImage(
                artworkIdentifier: model.nowPlaying.artworkIdentifier,
                maxPixelDimension: max(geometryIndependentArtworkDimension * displayScale, 1)
            )
        }
        .onChange(of: model.externalVolume.level, initial: true) { _, newValue in
            guard !isAdjustingVolume else {
                return
            }

            volumeLevel = Double(newValue)
        }
        .onDisappear {
            volumeCommitTask?.cancel()
            volumeCommitTask = nil
        }
    }

    private var geometryIndependentArtworkDimension: CGFloat {
        1400
    }

    private func heroHeight(for geometry: GeometryProxy) -> CGFloat {
        let availableHeight = geometry.size.height + geometry.safeAreaInsets.top
        return min(max(availableHeight * 0.52, 320), 560)
    }

    private func controlSpacing(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.height < 720 ? 20 : 28
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    PlayerSheetView()
        .environment(model)
}
