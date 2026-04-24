import SwiftUI

struct RoomsGroupMemberRow: View {
    let member: SonosGroupControlMember
    let canRemove: Bool
    let setRoomVolume: (SonosDiscoveredPlayer, Int) async -> Void
    let toggleRoomMute: (SonosDiscoveredPlayer) async -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RoomSurfaceIconView(
                    systemImage: member.volume?.systemImage ?? "speaker.wave.2.fill",
                    size: 44,
                    cornerRadius: 14,
                    font: .body.weight(.semibold)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(member.player.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if member.isCoordinator {
                            RoomsGroupPill(title: "Coordinator")
                        } else if member.isActive {
                            RoomsGroupPill(title: "Active")
                        }
                    }

                    Text(member.player.detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if canRemove {
                    Button(role: .destructive, action: removeAction) {
                        if member.isMutatingGroup {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                    }
                    .disabled(member.isMutatingGroup)
                    .accessibilityLabel("Remove \(member.player.name) from group")
                }
            }

            if let volume = member.volume {
                RoomVolumeControl(
                    player: member.player,
                    volume: volume,
                    isMutating: member.isMutatingVolume,
                    setRoomVolume: setRoomVolume,
                    toggleRoomMute: toggleRoomMute
                )
                .padding(.leading, 58)
            }
        }
        .padding(.vertical, 12)
    }
}

struct RoomsGroupOptionRow: View {
    let option: SonosGroupControlOption
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: "plus.circle.fill",
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(option.player.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(option.player.detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: addAction) {
                if option.isMutating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            .disabled(option.isMutating)
            .accessibilityLabel("Add \(option.player.name) to group")
        }
        .padding(.vertical, 12)
    }
}

private struct RoomsGroupPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}
