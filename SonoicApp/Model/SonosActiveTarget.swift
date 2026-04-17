import Foundation

struct SonosActiveTarget: Identifiable, Equatable {
    enum SetupRole: Equatable {
        case primaryPlayer
        case subwoofer
        case surroundSpeaker
        case bondedProduct

        var detail: String {
            switch self {
            case .primaryPlayer:
                "Primary player"
            case .subwoofer:
                "Subwoofer"
            case .surroundSpeaker:
                "Surround speaker"
            case .bondedProduct:
                "Bonded product"
            }
        }
    }

    struct SetupProduct: Identifiable, Equatable {
        let id: String
        let name: String
        let role: SetupRole

        var categoryTitle: String {
            switch role {
            case .subwoofer:
                return "Subwoofer"
            case .surroundSpeaker:
                return "Surround speaker"
            case .primaryPlayer:
                if normalizedName.contains("arc") || normalizedName.contains("beam") || normalizedName.contains("ray") {
                    return "Soundbar"
                }

                if normalizedName.contains("amp") {
                    return "Amplifier"
                }

                return "Speaker"
            case .bondedProduct:
                if normalizedName.contains("sub") {
                    return "Subwoofer"
                }

                return "Speaker"
            }
        }

        var badgeTitle: String {
            switch role {
            case .primaryPlayer:
                "Main"
            case .subwoofer:
                "Sub"
            case .surroundSpeaker:
                "Rear"
            case .bondedProduct:
                "Bonded"
            }
        }

        var systemImage: String {
            switch role {
            case .subwoofer:
                return "speaker.fill"
            case .primaryPlayer:
                if normalizedName.contains("arc") || normalizedName.contains("beam") || normalizedName.contains("ray") {
                    return "speaker.wave.3.fill"
                }

                return "speaker.wave.2.fill"
            case .surroundSpeaker, .bondedProduct:
                return "speaker.wave.2.fill"
            }
        }

        private var normalizedName: String {
            name.lowercased()
        }
    }

    struct BondedAccessory: Identifiable, Equatable {
        let id: String
        let name: String
        let role: SetupRole
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
    var bondedAccessories: [BondedAccessory] = []

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
        if !bondedAccessories.isEmpty {
            return bondedAccessories.map(\.name)
        }

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

    var setupProducts: [SetupProduct] {
        var products: [SetupProduct] = []

        if let primaryProductName {
            products.append(
                SetupProduct(
                    id: "\(id):setup:primary",
                    name: primaryProductName,
                    role: .primaryPlayer
                )
            )
        }

        if !bondedAccessories.isEmpty {
            products.append(
                contentsOf: bondedAccessories.map { accessory in
                    SetupProduct(
                        id: accessory.id,
                        name: accessory.name,
                        role: accessory.role
                    )
                }
            )

            return products
        }

        products.append(
            contentsOf: accessoryNames.enumerated().map { index, name in
                SetupProduct(
                    id: "\(id):setup:bonded:\(index)",
                    name: name,
                    role: .bondedProduct
                )
            }
        )

        return products
    }
}
