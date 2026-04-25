import Foundation

struct SonosGroupControlMember: Identifiable, Equatable {
    var player: SonosDiscoveredPlayer
    var volumeItem: SonosRoomVolumeItem?
    var isCoordinator: Bool
    var isActive: Bool
    var isMutatingGroup: Bool
    var isMutatingVolume: Bool

    var id: String {
        player.id
    }

    var volume: SonoicExternalControlState.Volume? {
        volumeItem?.volume
    }
}

struct SonosGroupControlOption: Identifiable, Equatable {
    var player: SonosDiscoveredPlayer
    var isMutating: Bool

    var id: String {
        player.id
    }
}
