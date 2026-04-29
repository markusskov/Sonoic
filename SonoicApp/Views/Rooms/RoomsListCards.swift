import SwiftUI

struct RoomsGroupListCard: View {
    let groups: [SonosDiscoveredGroup]
    let selectingTargetID: String?
    let activeGroupID: String?
    let selectGroup: (SonosDiscoveredGroup) async -> Void

    var body: some View {
        SonoicListCard {
            SonoicListRows(
                groups,
                dividerLeadingPadding: SonoicTheme.Layout.roomDividerLeading
            ) { group, _ in
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
            }
        }
    }
}

struct RoomsListCard: View {
    let items: [SonosRoomListItem]
    let selectingItemID: String?
    let selectItem: (SonosRoomListItem) async -> Void

    var body: some View {
        SonoicListCard {
            SonoicListRows(
                items,
                dividerLeadingPadding: SonoicTheme.Layout.roomDividerLeading
            ) { item, _ in
                RoomsListRow(
                    item: item,
                    isSelecting: selectingItemID == item.id,
                    action: item.source == .discovered ? {
                        Task {
                            await selectItem(item)
                        }
                    } : nil
                )
            }
        }
    }
}
