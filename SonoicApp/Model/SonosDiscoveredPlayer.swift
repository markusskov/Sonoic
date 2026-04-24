import Foundation

struct SonosDiscoveredPlayer: Identifiable, Equatable {
    let id: String
    var name: String
    var host: String
    var modelName: String?
    var memberNames: [String]
    var bondedAccessories: [SonosActiveTarget.BondedAccessory]
    var groupID: String?
    var groupName: String?
    var groupMemberNames: [String]
    var isGroupCoordinator: Bool

    var activeTargetPlaceholder: SonosActiveTarget {
        SonosActiveTarget(
            id: id,
            name: name,
            householdName: modelName ?? name,
            kind: .room,
            memberNames: memberNames,
            bondedAccessories: bondedAccessories
        )
    }

    var roomListItem: SonosRoomListItem {
        SonosRoomListItem(
            id: id,
            name: name,
            kind: .room,
            summary: selectionSummary,
            source: .discovered,
            isActive: false
        )
    }

    var detailText: String {
        modelName ?? host
    }

    private var selectionSummary: String {
        guard groupMemberNames.count > 1 else {
            return activeTargetPlaceholder.summary
        }

        if isGroupCoordinator {
            return "Coordinator • \(groupMemberNames.count) rooms grouped"
        }

        return "Member • \(groupMemberNames.count) rooms grouped"
    }
}
