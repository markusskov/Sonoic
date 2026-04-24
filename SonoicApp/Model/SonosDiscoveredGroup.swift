import Foundation

struct SonosDiscoveredGroup: Identifiable, Equatable {
    let id: String
    var name: String
    var coordinatorID: String
    var coordinatorName: String
    var coordinatorHost: String
    var memberIDs: [String]
    var memberNames: [String]

    var summary: String {
        let roomCount = memberNames.count
        guard roomCount != 1 else {
            return "1 room grouped"
        }

        return "\(roomCount) rooms grouped"
    }

    var detailText: String {
        "Coordinator: \(coordinatorName)"
    }

    var activeTargetPlaceholder: SonosActiveTarget {
        SonosActiveTarget(
            id: id,
            name: name,
            householdName: coordinatorName,
            kind: .group,
            memberNames: memberNames
        )
    }

    static func displayName(for memberNames: [String]) -> String {
        let cleanedNames = memberNames.compactMap(\.sonoicNonEmptyTrimmed)
        guard let firstName = cleanedNames.first else {
            return "Group"
        }

        if cleanedNames.count == 2 {
            return cleanedNames.joined(separator: " + ")
        }

        if cleanedNames.count > 2 {
            return "\(firstName) + \(cleanedNames.count - 1) more"
        }

        return firstName
    }
}
