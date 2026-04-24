import SwiftUI

struct RoomVolumeControlsSection: View {
    let activeTarget: SonosActiveTarget
    let targetVolume: SonoicExternalControlState.Volume
    let roomVolumeState: SonosRoomVolumeState
    let mutatingRoomVolumeIDs: Set<SonosRoomVolumeItem.ID>
    let operationErrorDetail: String?
    let isEnabled: Bool
    let refreshAction: () async -> Void
    let setTargetVolume: (Int) async -> Bool
    let toggleTargetMute: () async -> Void
    let setRoomVolume: (SonosRoomVolumeItem, Int) async -> Bool
    let toggleRoomMute: (SonosRoomVolumeItem) async -> Void

    private var sectionSubtitle: String {
        switch activeTarget.kind {
        case .group:
            "Control the group volume, then fine-tune each room inside it."
        case .room:
            "Control the selected room directly from its detail page."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoomsSectionHeader(title: "Volume", subtitle: sectionSubtitle)

            RoomSurfaceCard {
                RoomVolumeSliderRow(
                    title: activeTarget.kind == .group ? "Group Volume" : "Room Volume",
                    subtitle: activeTarget.name,
                    systemImage: activeTarget.kind.systemImage,
                    volume: targetVolume,
                    isEnabled: isEnabled,
                    setVolume: setTargetVolume,
                    toggleMute: toggleTargetMute
                )

                groupRoomsContent
                operationError
            }
        }
    }

    @ViewBuilder
    private var groupRoomsContent: some View {
        if activeTarget.kind == .group {
            Divider()
            roomVolumeStateContent
        }
    }

    @ViewBuilder
    private var roomVolumeStateContent: some View {
        switch roomVolumeState {
        case .idle:
            RoomVolumeMessageRow(
                title: "Room Volumes",
                detail: "Open this page to load individual room controls.",
                systemImage: "speaker.wave.2.circle",
                isLoading: false,
                actionTitle: "Load",
                action: refreshAction
            )

        case .loading:
            RoomVolumeMessageRow(
                title: "Loading Room Volumes",
                detail: "Sonoic is reading each grouped room.",
                systemImage: "arrow.clockwise",
                isLoading: true,
                actionTitle: nil,
                action: nil
            )

        case let .unavailable(detail), let .failed(detail):
            RoomVolumeMessageRow(
                title: "Room Volumes Unavailable",
                detail: detail,
                systemImage: "exclamationmark.triangle.fill",
                isLoading: false,
                actionTitle: "Try Again",
                action: refreshAction
            )

        case let .loaded(snapshot):
            VStack(spacing: 0) {
                ForEach(Array(snapshot.items.enumerated()), id: \.element.id) { index, item in
                    RoomVolumeSliderRow(
                        title: item.name,
                        subtitle: item.isCoordinator ? "Coordinator" : "Grouped room",
                        systemImage: item.isCoordinator ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                        volume: item.volume,
                        isEnabled: isEnabled && !mutatingRoomVolumeIDs.contains(item.id),
                        setVolume: { level in
                            await setRoomVolume(item, level)
                        },
                        toggleMute: {
                            await toggleRoomMute(item)
                        }
                    )

                    if index < snapshot.items.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var operationError: some View {
        if let operationErrorDetail = operationErrorDetail?.sonoicNonEmptyTrimmed {
            Divider()

            Label(operationErrorDetail, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }
}
