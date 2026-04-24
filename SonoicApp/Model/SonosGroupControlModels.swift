import Foundation

struct SonosGroupControlMember: Identifiable, Equatable {
    var player: SonosDiscoveredPlayer
    var volume: SonoicExternalControlState.Volume?
    var isCoordinator: Bool
    var isActive: Bool
    var isMutatingGroup: Bool
    var isMutatingVolume: Bool

    var id: String {
        player.id
    }
}

struct SonosGroupControlOption: Identifiable, Equatable {
    var player: SonosDiscoveredPlayer
    var isMutating: Bool

    var id: String {
        player.id
    }
}
