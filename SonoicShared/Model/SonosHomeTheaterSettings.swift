import Foundation

struct SonosHomeTheaterSettings: Equatable {
    static let toneRange = -10 ... 10
    static let subLevelRange = -10 ... 10
    static let dialogLevelRange = 1 ... 4

    var bass: Int
    var treble: Int
    var loudness: Bool
    var subLevel: Int?
    var speechEnhancementEnabled: Bool?
    var dialogLevel: Int?
    var nightSoundEnabled: Bool?

    var supportsSubLevel: Bool {
        subLevel != nil
    }

    var supportsSpeechEnhancement: Bool {
        speechEnhancementEnabled != nil
    }

    var supportsDialogLevel: Bool {
        dialogLevel != nil
    }

    var supportsNightSound: Bool {
        nightSoundEnabled != nil
    }
}

struct SonosHomeTheaterTVDiagnostics: Equatable {
    var remoteConfigured: Bool?
    var irRepeaterState: String?
    var ledFeedbackState: String?

    static let empty = SonosHomeTheaterTVDiagnostics(
        remoteConfigured: nil,
        irRepeaterState: nil,
        ledFeedbackState: nil
    )
}
