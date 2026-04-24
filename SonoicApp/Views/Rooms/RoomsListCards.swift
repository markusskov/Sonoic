import SwiftUI

struct RoomsGroupListCard: View {
    let groups: [SonosDiscoveredGroup]
    let selectingTargetID: String?
    let activeGroupID: String?
    let selectGroup: (SonosDiscoveredGroup) async -> Void

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    RoomsGroupRow(
                        group: group,
                        isSelecting: selectingTargetID == group.id,
                        isActive: activeGroupID == group.id,
                        action: {
                            Task {
                                await selectGroup(group)
                            }
                        }
                    )

                    if index < groups.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}

struct RoomsListCard: View {
    let items: [SonosRoomListItem]
    let selectingItemID: String?
    let selectItem: (SonosRoomListItem) async -> Void

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    RoomsListRow(
                        item: item,
                        isSelecting: selectingItemID == item.id,
                        action: item.source == .discovered ? {
                            Task {
                                await selectItem(item)
                            }
                        } : nil
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}
