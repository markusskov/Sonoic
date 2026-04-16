import Foundation

struct SonosActiveTarget: Identifiable, Equatable {
    struct SetupProduct: Identifiable, Equatable {
        enum Role: Equatable {
            case primaryPlayer
            case bondedProduct

            var detail: String {
                switch self {
                case .primaryPlayer:
                    "Primary player"
                case .bondedProduct:
                    "Bonded product"
                }
            }
        }

        let id: String
        let name: String
        let role: Role
    }

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
            memberNames.count > 1 ? "\(memberNames.count) speakers linked" : "Single-room target"
        case .group:
            "\(memberNames.count) rooms grouped"
        }
    }

    var membersDescription: String {
        memberNames.joined(separator: ", ")
    }

    var accessoryNames: [String] {
        guard kind == .room, memberNames.count > 1 else {
            return []
        }

        let filteredNames = memberNames.filter { $0 != name }
        if !filteredNames.isEmpty {
            return filteredNames
        }

        return Array(memberNames.dropFirst())
    }

    var accessoryDescription: String {
        accessoryNames.joined(separator: ", ")
    }

    var primaryProductName: String? {
        let trimmedName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    var setupProductNames: [String] {
        var seenNames: Set<String> = []
        var orderedNames: [String] = []

        for name in [primaryProductName] + accessoryNames.map(Optional.some) {
            guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedName.isEmpty else {
                continue
            }

            let normalizedName = trimmedName.lowercased()
            guard !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            orderedNames.append(trimmedName)
        }

        return orderedNames
    }

    var setupProducts: [SetupProduct] {
        setupProductNames.enumerated().map { index, name in
            SetupProduct(
                id: "\(id):setup:\(index)",
                name: name,
                role: index == 0 ? .primaryPlayer : .bondedProduct
            )
        }
    }
}
