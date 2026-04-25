import SwiftUI

struct RoomsGroupControlCard: View {
    enum PendingAction: Identifiable {
        case join(SonosDiscoveredPlayer)
        case remove(SonosDiscoveredPlayer)

        var id: String {
            switch self {
            case let .join(player):
                "join-\(player.id)"
            case let .remove(player):
                "remove-\(player.id)"
            }
        }

        var title: String {
            switch self {
            case let .join(player):
                "Add \(player.name)?"
            case let .remove(player):
                "Remove \(player.name)?"
            }
        }

        var message: String {
            switch self {
            case let .join(player):
                "\(player.name) will follow the active group's queue and playback."
            case let .remove(player):
                "\(player.name) will become its own standalone Sonos room."
            }
        }
    }

    let members: [SonosGroupControlMember]
    let options: [SonosGroupControlOption]
    let isRefreshing: Bool
    let addRoomToGroup: (SonosDiscoveredPlayer) async -> Void
    let removeRoomFromGroup: (SonosDiscoveredPlayer) async -> Void
    let setRoomVolume: (SonosRoomVolumeItem, Int) async -> Bool
    let toggleRoomMute: (SonosRoomVolumeItem) async -> Void
    let refreshGroupControl: () async -> Void

    @State private var pendingAction: PendingAction?

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 0) {
                if members.isEmpty {
                    Label("Choose a room before editing groups.", systemImage: "speaker.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    memberRows
                    optionRows
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(16)
            }
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: primaryButton(for: action),
                secondaryButton: .cancel()
            )
        }
    }

    private var memberRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                RoomsGroupMemberRow(
                    member: member,
                    canRemove: members.count > 1 && !member.isCoordinator,
                    setRoomVolume: setRoomVolume,
                    toggleRoomMute: toggleRoomMute,
                    removeAction: {
                        pendingAction = .remove(member.player)
                    }
                )

                if index < members.count - 1 || !options.isEmpty {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
    }

    @ViewBuilder
    private var optionRows: some View {
        if !options.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    RoomsGroupOptionRow(
                        option: option,
                        addAction: {
                            pendingAction = .join(option.player)
                        }
                    )

                    if index < options.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func primaryButton(for action: PendingAction) -> Alert.Button {
        switch action {
        case let .join(player):
            .default(Text("Add")) {
                Task {
                    await addRoomToGroup(player)
                    await refreshGroupControl()
                }
            }
        case let .remove(player):
            .destructive(Text("Remove")) {
                Task {
                    await removeRoomFromGroup(player)
                    await refreshGroupControl()
                }
            }
        }
    }
}
