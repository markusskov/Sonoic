struct SonosActiveTarget: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case room
        case group

        var title: String {
            switch self {
            case .room:
                "Room"
            case .group:
                "Group"
            }
        }

        var systemImage: String {
            switch self {
            case .room:
                "speaker.wave.2.fill"
            case .group:
                "square.stack.3d.up.fill"
            }
        }
    }

    let id: String
    var name: String
    var householdName: String
    var kind: Kind
    var memberNames: [String]

    var summary: String {
        switch kind {
        case .room:
            "Single-room target"
        case .group:
            "\(memberNames.count) rooms grouped"
        }
    }

    var membersDescription: String {
        memberNames.joined(separator: ", ")
    }
}
